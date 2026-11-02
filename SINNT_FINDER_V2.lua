--[[
  SINNT EGG FINDER V2 — Delta Android / Steal an Egg
  COMMUNITY FEDERATED FINDER (NOT the protected Chilli source).
  Validated V1.1 scanner + V2 cross-server community feed + manual join.
  Reporting starts OFF. Reporting sends only placeId, jobId, and egg fields.
  Requires Cloudflare Worker (worker.js) and its D1 database for cross-server use.
  Never paste Roblox passwords, cookies or account tokens into this script.
]]
if not game:IsLoaded() then game.Loaded:Wait() end
local Players = game:GetService('Players')
local RS = game:GetService('ReplicatedStorage')
local UIS = game:GetService('UserInputService')
local Http = game:GetService('HttpService')
local TP = game:GetService('TeleportService')
local CS = game:GetService('CollectionService')
local LP = Players.LocalPlayer
if not LP then warn('[SINNT] LocalPlayer belum siap'); return end
local env = (type(getgenv)=='function' and getgenv()) or _G
if env.__SINNT_FINDER_STOP then pcall(env.__SINNT_FINDER_STOP) end

local CFG_FILE = 'SINNT_FINDER_V1_CONFIG.json'
local cfg = {url='', reportKey='', minValue=0, rarity='All'}
if type(readfile)=='function' and type(isfile)=='function' then
  pcall(function()
    if isfile(CFG_FILE) then
      local data = Http:JSONDecode(readfile(CFG_FILE))
      if type(data)=='table' and type(data.url)=='string' then cfg.url=data.url end
    end
  end)
end
local state = {active=true,scout=false,feed={},rawFeed={},selected=1,feedVersion=0,mode='LOCAL',lastScan=0,
  assetCount=0,matchedAssets=0,assetPath='Unavailable',mutationPath='Unavailable',
  lastFeed=0,lastReport=0,feedBusy=false,reportBusy=false,serverCount=0,localEggs={},scannerMessage='',status='Ready. Scan lokal dulu.'}
local uiConnections = {}
local function info(text)
  state.status=tostring(text)
  print('[SINNT FINDER] '..tostring(text))
end
local function trim(s) return tostring(s or ''):match('^%s*(.-)%s*$') end
local function plain(v)
  if type(v)=='string' and v~='' then return v end
  if type(v)=='number' then return tostring(v) end
  return nil
end
local function first(t,names)
  if type(t)~='table' then return nil end
  for _,k in ipairs(names) do
    local v=plain(t[k]); if v then return v end
  end
  return nil
end
local function numeric(t,keys)
  if type(t)~='table' then return nil end
  for _,k in ipairs(keys) do
    local n=tonumber(t[k]); if n and n>=0 then return n end
  end
  return nil
end
-- This version resolves field records via the game's own asset catalog.
-- Nothing is guessed from an egg's displayed colour, position or rarity tier.
local function requirePath(path)
  local node=RS
  for part in tostring(path):gmatch('[^%.]+') do
    node=node and node:FindFirstChild(part)
  end
  if not node or not node:IsA('ModuleScript') then return nil end
  local ok,res=pcall(require,node)
  if ok and type(res)=='table' then return res end
  return nil
end
local function loadCatalog()
  local assets,assetPath=nil,'Unavailable'
  for _,path in ipairs({'Data.Assets','Directory.Assets'}) do
    local mod=requirePath(path)
    if mod and type(mod.Directory)=='table' then
      assets=mod.Directory;assetPath=path;break
    end
  end
  local mutations,mutationPath=nil,'Unavailable'
  for _,path in ipairs({'Shared.Modules.Mutations','Library.Modules.Mutations'}) do
    local mod=requirePath(path)
    if mod then mutations=mod;mutationPath=path;break end
  end
  state.assetPath=assetPath
  state.mutationPath=mutationPath
  state.assetCount=0
  for _ in pairs(assets or {}) do state.assetCount=state.assetCount+1 end
  return assets or {},mutations
end
local function mutationNames(muts)
  if type(muts)~='table' then return nil end
  local names={}
  for key,v in pairs(muts) do
    if type(v)=='string' and v~='' then
      names[#names+1]=v
    elseif type(key)=='string' and v then
      names[#names+1]=key
    end
  end
  if #names==0 then return nil end
  table.sort(names)
  return table.concat(names,', '):sub(1,90)
end
local function mutationMultiplier(muts,mod)
  if type(muts)~='table' or next(muts)==nil then return 1 end
  if type(mod)~='table' then return nil end
  local fn=mod.EarningsFor or mod.GetTotalMutationsEarningMulti
  if type(fn)~='function' then return nil end
  local ok,v=pcall(fn,muts)
  if (not ok or type(v)~='number') then ok,v=pcall(fn,mod,muts) end
  if ok and type(v)=='number' and v>0 and v<math.huge then return v end
  return nil
end
local function extractRecord(key,rec,assets,mutationModule)
  if type(rec)~='table' then return nil end
  local category=plain(rec.AssetCategory)
  local def=category and assets[category] or nil
  local rarity=nil
  local value=nil
  if type(def)=='table' then
    if type(def.Rarity)=='table' then
      rarity=plain(def.Rarity.DisplayName) or plain(def.Rarity.Name)
    else
      rarity=plain(def.Rarity)
    end
    local base=tonumber(def.EarningRate)
    local scale=tonumber(rec.AssetScale) or 1
    local mul=mutationMultiplier(rec.Mutations,mutationModule)
    -- Community-observed earnings formula; label all derived values as estimates.
    if base and base>=0 and scale>0 and mul then
      value=base * (scale^1.85) * mul
    end
  end
  local valueSource=value and 'ESTIMATE' or nil
  -- Trust exact income field if the game ever exposes one in future versions.
  local direct=numeric(rec,{'ValuePerSecond','CashPerSecond','MoneyPerSecond','IncomePerSecond','EarningsPerSecond'})
  if direct then value=direct;valueSource='DIRECT' end
  local name=(type(def)=='table' and (plain(def.DisplayName) or plain(def.Name))) or category
    or first(rec,{'EggName','DisplayName','Name'}) or 'Unidentified Egg'
  local uid=plain(rec.Uid) or plain(rec.UID) or plain(rec.Uuid) or tostring(key)
  local area=plain(rec.AreaId) or plain(rec.Area)
  local mutation=mutationNames(rec.Mutations)
  return {id=uid:sub(1,90),name=name:sub(1,90),category=category,rarity=rarity,
    area=area,mutation=mutation,valuePerSecond=value,valueSource=valueSource,
    placeId=game.PlaceId,jobId=game.JobId,source='EggState',ageSeconds=0,
    catalogMatched=type(def)=='table'}
end
local function scanLocal()
  local result,mode={},'NO_EGGSTATE'
  local client=RS:FindFirstChild('Client')
  local mod=client and client:FindFirstChild('EggState')
  local ok,obj=pcall(function() return mod and require(mod) end)
  if ok and type(obj)=='table' and type(obj.ReadFieldEggs)=='function' then
    local a,snapshot=pcall(obj.ReadFieldEggs)
    if not a then a,snapshot=pcall(function() return obj:ReadFieldEggs() end) end
    if a and type(snapshot)=='table' and type(snapshot.Records)=='table' then
      mode='EggState'
      local assets,mutationModule=loadCatalog()
      for k,r in pairs(snapshot.Records) do
        local item=extractRecord(k,r,assets,mutationModule)
        if item then result[#result+1]=item end
        if #result>=2500 then break end -- defensive safety cap; sorted before report/list truncation.
      end
      state.matchedAssets=0
      for _,item in ipairs(result) do
        if item.catalogMatched then state.matchedAssets=state.matchedAssets+1 end
      end
      table.sort(result,function(a,b)
        local x,y=tonumber(a.valuePerSecond),tonumber(b.valuePerSecond)
        if x and y and x~=y then return x>y end
        if x and not y then return true end
        if y and not x then return false end
        return tostring(a.name)<tostring(b.name)
      end)
    else
      mode='EggState unavailable: ReadFieldEggs gagal'
    end
  else
    mode='EggState module tidak tersedia'
  end
  -- Fallback is LOCAL DIAGNOSTIC only. Never send guessed objects to backend.
  if #result==0 and mode~='EggState' then
    local ok2,tags=pcall(function() return CS:GetTagged('CarryAreaEgg') end)
    if ok2 and type(tags)=='table' then
      for i,inst in ipairs(tags) do
        if i>20 then break end
        result[#result+1]={id='unverified-'..i,name='CarryAreaEgg (unverified)',
          rarity=nil,area=nil,mutation=nil,valuePerSecond=nil,
          placeId=game.PlaceId,jobId=game.JobId,source='UNVERIFIED',ageSeconds=0}
      end
      if #result>0 then mode=mode..'; fallback tagged' end
    end
  end
  state.localEggs=result
  state.scannerMessage=mode
  state.lastScan=os.clock()
  return result,mode
end
local function savedUrl(u)
  u=trim(u):gsub('/+$','')
  if u=='' then return '' end
  if not u:match('^https://[%w%-%.]+%.workers%.dev$') and
     not u:match('^https://[%w%-%.]+$') then return nil end
  return u
end
local function getResponse(url)
  local success,data=pcall(function() return game:HttpGet(url,true) end)
  if not success then return nil,tostring(data) end
  local ok,decoded=pcall(Http.JSONDecode,Http,data)
  if not ok or type(decoded)~='table' then return nil,'Respons bukan JSON' end
  return decoded
end
local function post(url,body,key)
  local fn = (type(request)=='function' and request)
    or (type(http_request)=='function' and http_request)
    or (type(http)=='table' and type(http.request)=='function' and http.request)
    or (type(syn)=='table' and type(syn.request)=='function' and syn.request)
  if not fn then return nil,'Executor tidak menyediakan fungsi request POST' end
  local ok,res=pcall(fn,{
    Url=url,Method='POST',Headers={['Content-Type']='application/json',
      ['Authorization']='Bearer '..key},Body=Http:JSONEncode(body)})
  if not ok then return nil,tostring(res) end
  local code=tonumber(res and (res.StatusCode or res.Status)) or 0
  local bodyText=tostring(res and (res.Body or res.body) or '')
  local decodedOk,decoded=pcall(Http.JSONDecode,Http,bodyText)
  if code<200 or code>=300 then
    return nil,decodedOk and tostring(decoded.error or code) or ('HTTP '..code)
  end
  if decodedOk and type(decoded)=='table' and decoded.ok then return decoded end
  return nil,'Respons server tidak sesuai'
end
-- V2 network and filters. Network operations run in task.spawn; reporter is opt-in.
local function filterEggs(items)
  local list={}
  for _,e in ipairs(items or {}) do
    local sameRarity=cfg.rarity=='All' or tostring(e.rarity or ''):lower()==cfg.rarity:lower()
    local val=tonumber(e.valuePerSecond)
    if sameRarity and (cfg.minValue<=0 or (val and val>=cfg.minValue)) then
      list[#list+1]=e
    end
  end
  return list
end
local function updateFilters()
  state.feed=filterEggs(state.rawFeed)
  state.selected=1
  state.feedVersion=state.feedVersion+1
  info('Filter: '..tostring(#state.feed)..' Egg ditampilkan | '..state.mode)
end
local function report()
  if state.reportBusy or not state.active or not state.scout then return end
  if cfg.url=='' then info('Masukkan URL Worker dulu');return end
  if cfg.reportKey=='' then info('Masukkan Reporter Key dulu');return end
  state.reportBusy=true
  local ok,err=pcall(function()
    local items,mode=scanLocal()
    if mode~='EggState' then info('Scout tidak dikirim: '..mode);return end
    local payload={placeId=game.PlaceId,jobId=game.JobId,eggs={}}
    -- Send highest value eggs first; one server snapshot = one D1 write.
    for _,e in ipairs(items) do
      if e.catalogMatched and type(e.valuePerSecond)=='number' then
        payload.eggs[#payload.eggs+1]={id=e.id,name=e.name,rarity=e.rarity,
          area=e.area,mutation=e.mutation,valuePerSecond=e.valuePerSecond}
      end
      if #payload.eggs>=100 then break end
    end
    local res,why=post(cfg.url..'/report',payload,cfg.reportKey)
    if res then info('SCOUT berhasil: '..tostring(res.accepted)..' Egg dikirim dari server ini')
    else info('SCOUT gagal: '..tostring(why)) end
  end)
  if not ok then info('SCOUT error: '..tostring(err)) end
  state.lastReport=os.clock()
  state.reportBusy=false
end
local function loadFeed()
  if state.feedBusy then return end
  if cfg.url=='' then info('Masukkan URL Worker sebelum FEED');return end
  state.feedBusy=true
  local ok,err=pcall(function()
    local params='?placeId='..tostring(game.PlaceId)..'&limit=60'
    if cfg.rarity~='All' then params=params..'&rarity='..Http:UrlEncode(cfg.rarity) end
    if cfg.minValue>0 then params=params..'&minValue='..tostring(cfg.minValue) end
    local data,why=getResponse(cfg.url..'/feed'..params)
    if data and data.ok and type(data.eggs)=='table' then
      state.rawFeed=data.eggs
      state.feed=filterEggs(state.rawFeed)
      state.selected=1;state.mode='REMOTE'
      state.serverCount=tonumber(data.serverCount) or 0
      state.feedVersion=state.feedVersion+1
      local tip=state.serverCount<=1 and ' (butuh scout di server lain)' or ''
      info('FEED: '..state.serverCount..' server | '..#state.feed..' Egg'..tip)
    else
      info('FEED gagal: '..tostring((data and data.error) or why))
    end
  end)
  if not ok then info('FEED error: '..tostring(err)) end
  state.lastFeed=os.clock()
  state.feedBusy=false
end
local function showLocal()
  local list=scanLocal()
  state.rawFeed=list
  state.feed=filterEggs(list)
  state.mode='LOCAL'
  state.feedVersion=state.feedVersion+1
  state.selected=1
  info('LOCAL: '..#state.feed..' Egg sesuai filter | katalog '..state.matchedAssets..'/'..#list)
end
local function checkHealth()
  if cfg.url=='' then info('Isi URL Worker dulu');return end
  local data,err=getResponse(cfg.url..'/health')
  if data and data.ok then
    info('Worker ONLINE V'..tostring(data.version or '?')..' | Reporter '..(data.reporterReady and 'siap' or 'belum diatur'))
  else info('Worker belum siap: '..tostring((data and data.error) or err)) end
end
local function diagnose()
  local client=RS:FindFirstChild('Client')
  local module=client and client:FindFirstChild('EggState')
  local textOut='[SINNT DIAGNOSTIC] PlaceId='..game.PlaceId
    ..' | EggState='..tostring(module~=nil)..' | Scanner='..state.scannerMessage
    ..' | LocalCount='..#state.localEggs
  if module then
    local ok,snapshot=pcall(function()
      local obj=require(module)
      if type(obj)~='table' or type(obj.ReadFieldEggs)~='function' then return nil end
      local s,ret=pcall(obj.ReadFieldEggs)
      if not s then s,ret=pcall(function()return obj:ReadFieldEggs() end)end
      return s and ret or nil
    end)
    if ok and type(snapshot)=='table' and type(snapshot.Records)=='table' then
      for _,rec in pairs(snapshot.Records) do
        if type(rec)=='table' then
          local keys={}
          for k,v in pairs(rec) do
            local typeName=typeof(v)
            keys[#keys+1]=tostring(k)..'<'..tostring(typeName)..'>'
            if #keys>=35 then break end
          end
          table.sort(keys)
          textOut=textOut..'\nEgg fields: '..table.concat(keys,', ')
          break
        end
      end
    end
  end
  textOut=textOut..'\nAssets='..tostring(state.assetPath)..' ('..tostring(state.assetCount)..' categories)'
    ..' | Matched='..tostring(state.matchedAssets)..'/'..tostring(#state.localEggs)
    ..' | MutationModule='..tostring(state.mutationPath)
  local sample=state.localEggs[1]
  if sample then
    textOut=textOut..'\nSample category='..tostring(sample.category or 'unknown')
      ..' | Name='..tostring(sample.name or 'unknown')
      ..' | Rarity='..tostring(sample.rarity or 'unknown')
      ..' | Value='..tostring(sample.valuePerSecond or 'unknown')
      ..' | Source='..tostring(sample.valueSource or 'unknown')
      ..' | Mutation='..tostring(sample.mutation or 'none')
  end
  print(textOut)
  if type(setclipboard)=='function' then pcall(setclipboard,textOut) end
  info('Diagnostik tampil di console / clipboard (tidak berisi nilai pribadi)')
end

-- Touch-friendly UI; only one panel; reporter OFF by default.
local gui=Instance.new('ScreenGui')
gui.Name='SINNT_EGG_FINDER_V1'
gui.ResetOnSpawn=false
gui.IgnoreGuiInset=false
local parent=LP:WaitForChild('PlayerGui')
if type(gethui)=='function' then
  local ok,p=pcall(gethui); if ok and p then parent=p end
end
local okParent=pcall(function() gui.Parent=parent end)
if not okParent then gui.Parent=LP:WaitForChild('PlayerGui') end
local frame=Instance.new('Frame',gui)
frame.Name='Window';frame.Size=UDim2.new(0,320,0,444)
frame.Position=UDim2.new(0.5,-160,0.5,-222)
frame.BackgroundColor3=Color3.fromRGB(19,21,31)
frame.BorderSizePixel=0
local corner=Instance.new('UICorner',frame);corner.CornerRadius=UDim.new(0,11)
local stroke=Instance.new('UIStroke',frame);stroke.Color=Color3.fromRGB(124,84,204);stroke.Thickness=1.5
local function label(text,x,y,w,h,color,size)
  local t=Instance.new('TextLabel',frame)
  t.BackgroundTransparency=1;t.Text=tostring(text);t.TextColor3=color or Color3.new(1,1,1)
  t.TextSize=size or 12;t.Font=Enum.Font.Gotham;t.TextXAlignment=Enum.TextXAlignment.Left
  t.Size=UDim2.new(0,w,0,h);t.Position=UDim2.new(0,x,0,y)
  t.TextTruncate=Enum.TextTruncate.AtEnd
  return t
end
local function btn(text,x,y,w,h,callback)
  local b=Instance.new('TextButton',frame)
  b.Text=tostring(text);b.Font=Enum.Font.GothamMedium;b.TextSize=12
  b.TextColor3=Color3.fromRGB(242,241,255)
  b.BackgroundColor3=Color3.fromRGB(75,50,131)
  b.Size=UDim2.new(0,w,0,h);b.Position=UDim2.new(0,x,0,y)
  b.BorderSizePixel=0
  local c=Instance.new('UICorner',b);c.CornerRadius=UDim.new(0,6)
  table.insert(uiConnections,b.MouseButton1Click:Connect(callback))
  return b
end
local function entry(placeholder,x,y,w)
  local b=Instance.new('TextBox',frame)
  b.Text='';b.PlaceholderText=placeholder;b.ClearTextOnFocus=false
  b.Font=Enum.Font.Gotham;b.TextSize=12;b.TextColor3=Color3.new(1,1,1)
  b.PlaceholderColor3=Color3.fromRGB(145,145,175)
  b.BackgroundColor3=Color3.fromRGB(35,38,52)
  b.Size=UDim2.new(0,w,0,27);b.Position=UDim2.new(0,x,0,y)
  b.TextXAlignment=Enum.TextXAlignment.Left
  local c=Instance.new('UICorner',b);c.CornerRadius=UDim.new(0,5)
  return b
end
label('SINNT EGG FINDER V2',12,8,240,22,Color3.fromRGB(206,183,255),15)
btn('X',280,7,27,24,function()
  if type(env.__SINNT_FINDER_STOP)=='function' then env.__SINNT_FINDER_STOP() end
end)
label('Cross-server • SCAN / FEED • Scout opt-in',12,31,295,16,Color3.fromRGB(166,167,186),10)
local urlBox=entry('https://nama-worker.workers.dev',12,55,295)
urlBox.Text=cfg.url
local keyBox=entry('Reporter key (jangan bagikan)',12,88,225)
-- Characters are not drawn; key is held only in session memory after SAVE.
keyBox.TextTransparency=1
local saveBtn=btn('SAVE',243,88,64,27,function()
  local url=savedUrl(urlBox.Text)
  if url==nil then info('Gunakan URL Worker HTTPS tanpa /feed');return end
  cfg.url=url;cfg.reportKey=trim(keyBox.Text)
  if type(writefile)=='function' then
    pcall(writefile,CFG_FILE,Http:JSONEncode({url=cfg.url}))
  end
  keyBox.Text=''
  info('URL tersimpan; key hanya di memori sesi. Menguji koneksi...')
  task.spawn(checkHealth)
end)
local scoutBtn,rarityBtn
scoutBtn=btn('SCOUT: OFF',12,123,103,30,function()
  if state.scout then state.scout=false; info('Scout dihentikan')
  elseif cfg.url=='' or cfg.reportKey=='' then info('Masukkan URL + Reporter Key, lalu SAVE')
  else state.scout=true; state.lastReport=os.clock(); info('Scout ON; pelaporan tiap ~35 detik');task.spawn(report) end
end)
btn('SCAN',121,123,59,30,function()task.spawn(showLocal)end)
btn('FEED',185,123,59,30,function()task.spawn(loadFeed)end)
btn('DIAG',250,123,57,30,diagnose)
rarityBtn=btn('Rarity: ALL',12,160,117,26,function()
  local opts={'All','Secret','Divine','Eternal','Cosmic','Mythic'}
  local idx=1
  for i,s in ipairs(opts) do if s==cfg.rarity then idx=i;break end end
  cfg.rarity=opts[idx%#opts+1]
  rarityBtn.Text='Rarity: '..cfg.rarity:upper()
  updateFilters()
end)
label('Min /s:',136,165,49,18,Color3.fromRGB(193,190,216),11)
local minBox=entry('0',187,160,64)
minBox.Text='0'
btn('SET',255,160,52,26,function()
  cfg.minValue=math.max(0,tonumber(minBox.Text) or 0)
  updateFilters()
end)
local statusLabel=label('',12,189,296,18,Color3.fromRGB(171,224,188),11)
local list=Instance.new('ScrollingFrame',frame)
list.Position=UDim2.new(0,12,0,211);list.Size=UDim2.new(0,296,0,172)
list.BackgroundColor3=Color3.fromRGB(26,28,39)
list.BorderSizePixel=0;list.ScrollBarThickness=3
list.AutomaticCanvasSize=Enum.AutomaticSize.Y
list.CanvasSize=UDim2.new(0,0,0,0)
local lcorner=Instance.new('UICorner',list);lcorner.CornerRadius=UDim.new(0,5)
local layout=Instance.new('UIListLayout',list)
layout.SortOrder=Enum.SortOrder.LayoutOrder;layout.Padding=UDim.new(0,3)
local selectedLabel=label('Pilih Egg dari daftar, lalu JOIN',12,388,296,18,Color3.fromRGB(182,179,200),11)
btn('JOIN TARGET',12,409,143,27,function()
  local e=state.feed[state.selected]
  if not e then info('Belum ada target terpilih');return end
  if e.source=='UNVERIFIED' then info('Objek belum terverifikasi');return end
  local placeId=tonumber(e.placeId)
  local jobId=tostring(e.jobId or '')
  if not placeId or #jobId<8 then info('PlaceId / JobId tidak valid');return end
  if placeId~=game.PlaceId then info('Target bukan tempat yang sama');return end
  if jobId==game.JobId then info('Egg berada di server kamu sekarang');return end
  info('Mencoba join '..jobId:sub(1,10)..'...')
  task.spawn(function()
    local ok,err=pcall(function() TP:TeleportToPlaceInstance(placeId,jobId,LP) end)
    if not ok then info('Join gagal: '..tostring(err)) end
  end)
end)
btn('REFRESH FEED',160,409,147,27,function()task.spawn(loadFeed)end)
local function formatValue(n)
  if tonumber(n)==nil then return '? /s' end
  n=tonumber(n)
  if n>=1e12 then return string.format('%.2fT/s',n/1e12) end
  if n>=1e9 then return string.format('%.2fB/s',n/1e9) end
  if n>=1e6 then return string.format('%.2fM/s',n/1e6) end
  if n>=1e3 then return string.format('%.1fK/s',n/1e3) end
  return tostring(math.floor(n))..'/s'
end
local lastRenderedVersion=-1
local lastRenderedSelected=-1
local function render()
  if not state.active or not frame.Parent then return end
  statusLabel.Text=state.status
  scoutBtn.Text=state.scout and 'SCOUT: ON' or 'SCOUT: OFF'
  local e=state.feed[state.selected]
  selectedLabel.Text=e and ('TARGET: '..tostring(e.name)..' | '..tostring(e.area or 'area ?'))
    or 'Belum ada target. Tekan SCAN atau FEED.'
  if state.feedVersion==lastRenderedVersion and state.selected==lastRenderedSelected then return end
  lastRenderedVersion=state.feedVersion; lastRenderedSelected=state.selected
  for _,c in ipairs(list:GetChildren()) do if c:IsA('TextButton') then c:Destroy() end end
  for i,item in ipairs(state.feed) do
    if i>60 then break end -- avoid creating hundreds of buttons on low-end Android
    local selected=i==state.selected
    local b=Instance.new('TextButton',list)
    b.Name='Egg'..i;b.LayoutOrder=i
    b.Size=UDim2.new(1,-7,0,38)
    b.BackgroundColor3=selected and Color3.fromRGB(80,58,126) or Color3.fromRGB(38,41,55)
    b.BorderSizePixel=0;b.TextXAlignment=Enum.TextXAlignment.Left
    b.Font=Enum.Font.Gotham;b.TextSize=11
    b.TextColor3=Color3.fromRGB(242,241,252)
    local rarity=tostring(item.rarity or 'rarity unknown')
    local area=tostring(item.area or 'area unknown')
    local age=tostring(item.ageSeconds or 0)
    b.Text='  '..tostring(item.name or 'Egg')..' ['..rarity..']\n'
      ..'  '..(item.valueSource=='ESTIMATE' and '≈' or '')..formatValue(item.valuePerSecond)
      ..' | '..area..(state.mode=='REMOTE' and (' | '..age..'s') or ' | lokal')
    local co=Instance.new('UICorner',b);co.CornerRadius=UDim.new(0,5)
    b.MouseButton1Click:Connect(function()
      state.selected=i
      selectedLabel.Text='TARGET: '..tostring(item.name or '?')..' | '..area
      render()
    end)
  end
end
-- Drag window by header (mobile touch and mouse).
local dragging,startInput,startPos
local c1=frame.InputBegan:Connect(function(input)
  if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
    if input.Position.Y > frame.AbsolutePosition.Y+50 then return end
    dragging=input;startInput=input.Position;startPos=frame.Position
  end
end)
local c2=UIS.InputChanged:Connect(function(input)
  if not dragging or not frame.Parent or not startInput then return end
  if input.UserInputType==Enum.UserInputType.Touch and input~=dragging then return end
  if input.UserInputType~=Enum.UserInputType.Touch and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
  local delta=input.Position-startInput
  frame.Position=UDim2.new(startPos.X.Scale,startPos.X.Offset+delta.X,
    startPos.Y.Scale,startPos.Y.Offset+delta.Y)
end)
local c3=UIS.InputEnded:Connect(function(input)
  if dragging==input or (dragging and dragging.UserInputType==Enum.UserInputType.MouseButton1 and input.UserInputType==Enum.UserInputType.MouseButton1) then dragging=nil end
end)
local function stop()
  state.active=false;state.scout=false
  pcall(function()c1:Disconnect();c2:Disconnect();c3:Disconnect()end)
  for _,c in ipairs(uiConnections) do pcall(function()c:Disconnect()end)end
  pcall(function()gui:Destroy()end)
  env.__SINNT_FINDER_STOP=nil
end
env.__SINNT_FINDER_STOP=stop
-- Loop keeps feed fresh and reports only with explicit opt-in.
task.spawn(function()
  local lastRender=0
  while state.active do
    local now=os.clock()
    if state.scout and now-state.lastReport>=35 and not state.reportBusy then
      state.lastReport=now
      task.spawn(report)
    end
    if state.mode=='REMOTE' and cfg.url~='' and now-state.lastFeed>=20 and not state.feedBusy then
      state.lastFeed=now
      task.spawn(loadFeed)
    end
    if now-lastRender>=2 then render();lastRender=now end
    task.wait(1)
  end
end)
render()
info('V2 ready. SCAN=lokal; FEED=lintas server; SAVE menguji Worker.')
