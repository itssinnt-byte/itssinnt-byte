--[[
    SINNT HUB V3 ULTIMATE • Preview | Standalone Luau / mobile UI
    Target: Roblox client, tested by static inspection only (not run in Delta).
    Designed around Roblox APIs; no key, no expiry, no remote code.
    Does NOT alter, patch, or remove Delta executor's own licensing.
    Features are client-side and may be limited by server validation.
]]

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Lighting = game:GetService("Lighting")
local HttpService = game:GetService("HttpService")
local Workspace = game:GetService("Workspace")
local player = Players.LocalPlayer
if not player then return end

local env = _G
if type(getgenv) == "function" then
    local ok, value = pcall(getgenv)
    if ok and type(value) == "table" then env = value end
end
-- Destroy the previous release before creating a new UI.
for _, key in ipairs({"SINNT_HUB_V1", "SINNT_HUB_V2", "SINNT_HUB_V3"}) do
    if env[key] and type(env[key].Destroy) == "function" then
        pcall(env[key].Destroy)
    end
end

local guiName = "SINNT_HUB_V3_GUI"
local playerGui = player:WaitForChild("PlayerGui")
local oldGui = playerGui:FindFirstChild(guiName)
if oldGui then oldGui:Destroy() end

local alive = true
local connections = {}
local pageConnections = {}
local function trackPage(conn)
    table.insert(pageConnections, conn)
    return conn
end
local function track(conn)
    table.insert(connections, conn)
    return conn
end

local TweenService = game:GetService("TweenService")
local TeleportService = game:GetService("TeleportService")
local cfg = {
    method="Walk", speed=32, jumpPower=85, travelSpeed=28, interval=3,
    timeout=15, maxFailures=3, retry=true, autoReturn=true, autoSave=true,
    minValue=0, maxValue=0, rarity="", mutation="", names="", blacklist="", zone="",
    priority="Nearest", selectedName="", toolName="", combatRange=8,
    rarityAttribute="", valueAttribute="", mutationAttribute="", zoneAttribute="",
    maxMarkers=40, scanRadius=1500,
}
local state = {speed=false,jump=false,noclip=false,infiniteJump=false,playerESP=false,
 eggESP=false,guardESP=false,petESP=false,baseESP=false,antiAFK=false,fpsSaver=false,
 autoStealEgg=false,autoFarmEgg=false,autoEquip=false,autoHit=false}
local metrics = {attempts=0,acquired=0,failed=0,deposits=0,prompts=0,hitsAttempted=0,
 state="IDLE",started=os.clock(),fps=0,lastError="",failures=0}
local logs = {}
local notice = function(_) end
local function log(message)
    local s = tostring(message):sub(1,700)
    logs[#logs+1] = string.format("%.1f | %s",os.clock()-metrics.started,s)
    if #logs>100 then table.remove(logs,1) end
    notice(s)
end
local configFile = "SINNT_HUB_V3_"..tostring(game.PlaceId)..".json"
local function saveSettings()
    if type(writefile)~="function" then return false,"writefile unavailable" end
    return pcall(function() writefile(configFile,HttpService:JSONEncode({version=3,config=cfg})) end)
end
local function loadSettings()
    if type(readfile)~="function" or type(isfile)~="function" then return end
    local ok,data=pcall(function()
        if isfile(configFile) then return HttpService:JSONDecode(readfile(configFile)) end
    end)
    if not ok or type(data)~="table" or data.version~=3 or type(data.config)~="table" then return end
    for k,default in pairs(cfg) do
        local value=data.config[k]
        if type(value)==type(default) then
            if type(value)=="number" then
                if value==value and math.abs(value)<1e18 then cfg[k]=value end
            elseif type(value)=="string" then cfg[k]=value:sub(1,500)
            else cfg[k]=value end
        end
    end
    cfg.speed=math.clamp(cfg.speed,1,150);cfg.jumpPower=math.clamp(cfg.jumpPower,1,150)
    cfg.travelSpeed=math.clamp(cfg.travelSpeed,1,150);cfg.interval=math.clamp(cfg.interval,1,60)
    cfg.timeout=math.clamp(cfg.timeout,2,60);cfg.maxFailures=math.clamp(math.floor(cfg.maxFailures),1,10)
    cfg.maxMarkers=math.clamp(math.floor(cfg.maxMarkers),1,60)
    cfg.combatRange=math.clamp(cfg.combatRange,1,15);cfg.scanRadius=math.clamp(cfg.scanRadius,10,5000)
    cfg.minValue=math.max(0,cfg.minValue);cfg.maxValue=math.max(0,cfg.maxValue)
    if cfg.method~="Walk" and cfg.method~="Tween" and cfg.method~="Teleport" then cfg.method="Walk" end
end
loadSettings() -- Preferences only; actions never resume automatically.
-- Restore only properties actually changed by this hub.
local humanoidDefaults = setmetatable({}, {__mode = "k"})
local collisions = setmetatable({}, {__mode = "k"})
local visuals = setmetatable({}, {__mode = "k"})
local playerVisuals = {}

local function character()
    return player.Character
end
local function humanoid()
    local ch = character()
    return ch and ch:FindFirstChildOfClass("Humanoid")
end
local function rootPart()
    local ch = character()
    return ch and ch:FindFirstChild("HumanoidRootPart")
end
local function cacheHumanoid(h)
    if not h then return end
    if not humanoidDefaults[h] then
        humanoidDefaults[h] = {
            WalkSpeed = h.WalkSpeed,
            JumpPower = h.JumpPower,
            JumpHeight = h.JumpHeight,
            UseJumpPower = h.UseJumpPower,
        }
    end
end
local function applyMovement()
    local h = humanoid()
    if not h then return end
    cacheHumanoid(h)
    local orig = humanoidDefaults[h]
    pcall(function()
        h.WalkSpeed = state.speed and cfg.speed or orig.WalkSpeed
        if state.jump then
            h.UseJumpPower = true
            h.JumpPower = cfg.jumpPower
        else
            h.UseJumpPower = orig.UseJumpPower
            h.JumpPower = orig.JumpPower
            h.JumpHeight = orig.JumpHeight
        end
    end)
end
local function restoreCollisions()
    for part, original in pairs(collisions) do
        if part and part.Parent then
            pcall(function() part.CanCollide = original end)
        end
        collisions[part] = nil
    end
end
local function applyNoclip()
    local ch = character()
    if not ch then return end
    for _, item in ipairs(ch:GetDescendants()) do
        if item:IsA("BasePart") then
            if collisions[item] == nil then collisions[item] = item.CanCollide end
            if item.CanCollide then item.CanCollide = false end
        end
    end
end

local function restoreVisuals()
    for obj, props in pairs(visuals) do
        if obj and obj.Parent then
            for key, value in pairs(props) do
                pcall(function() obj[key] = value end)
            end
        end
        visuals[obj] = nil
    end
end
local function setVisual(obj, prop, value)
    local previous = visuals[obj]
    if not previous then
        previous = {}
        visuals[obj] = previous
    end
    if previous[prop] == nil then
        local ok, old = pcall(function() return obj[prop] end)
        if ok then previous[prop] = old end
    end
    pcall(function() obj[prop] = value end)
end
local function deletePlayerVisual(plr)
    local objects = playerVisuals[plr]
    if not objects then return end
    for _, object in ipairs(objects) do
        if object and object.Parent then object:Destroy() end
    end
    playerVisuals[plr] = nil
end
local function addPlayerVisual(plr)
    if not alive or not state.playerESP or plr == player then return end
    local ch = plr.Character
    if not ch then return end
    local head = ch:FindFirstChild("Head")
    if not head then return end
    deletePlayerVisual(plr)
    local hl = Instance.new("Highlight")
    hl.Name = "SinntPlayerMarker"
    hl.Adornee = ch
    hl.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
    hl.FillColor = Color3.fromRGB(72, 166, 255)
    hl.FillTransparency = 0.75
    hl.OutlineColor = Color3.fromRGB(160, 218, 255)
    hl.Parent = ch
    local labelGui = Instance.new("BillboardGui")
    labelGui.Name = "SinntPlayerLabel"
    labelGui.Size = UDim2.new(0, 180, 0, 28)
    labelGui.StudsOffsetWorldSpace = Vector3.new(0, 2.8, 0)
    labelGui.AlwaysOnTop = true
    labelGui.Adornee = head
    labelGui.Parent = head
    local label = Instance.new("TextLabel")
    label.Size = UDim2.new(1, 0, 1, 0)
    label.BackgroundTransparency = 1
    label.TextColor3 = Color3.fromRGB(230, 244, 255)
    label.TextStrokeTransparency = 0.3
    label.TextScaled = true
    label.Font = Enum.Font.GothamBold
    label.Text = plr.DisplayName
    label.Parent = labelGui
    playerVisuals[plr] = {hl, labelGui, label}
end
local function refreshPlayerVisuals()
    for plr in pairs(playerVisuals) do deletePlayerVisual(plr) end
    if state.playerESP then
        for _, plr in ipairs(Players:GetPlayers()) do addPlayerVisual(plr) end
    end
end


-- GAME ADAPTER: implement only after observing the actual game's data contract.
-- Callbacks must be non-yielding. IDs must be stable across pickup/despawn.
-- No guessed RemoteEvent, RemoteFunction, anti-cheat hook, or external payload.
local Adapter = {
    name="Unmapped Steal an Egg", placeId=nil,
    -- describe(instance) -> {id,name,rarity,value,mutation,zone,kind}
    describe=nil,
    -- snapshot(id) -> {id=id,owned=boolean,carried=boolean,deposited=boolean}
    -- This MUST read authoritative replicated inventory/ownership for this ID,
    -- including after the original Workspace instance disappears.
    snapshot=nil,
    -- pickupPrompt(instance) -> observed ProximityPrompt or nil
    pickupPrompt=nil,
    -- depositPrompt(id) -> ProximityPrompt or nil; basePosition() -> Vector3
    depositPrompt=nil,basePosition=nil,
    -- permitTeleport=true only after consistency testing for this place.
    permitTeleport=false,
}
local function adapterReady(deposit)
    return Adapter.placeId==game.PlaceId and type(Adapter.describe)=="function"
        and type(Adapter.snapshot)=="function" and type(Adapter.pickupPrompt)=="function"
        and (not deposit or (type(Adapter.depositPrompt)=="function" and type(Adapter.basePosition)=="function"))
end
local function finite(n) return type(n)=="number" and n==n and math.abs(n)<1e18 end
local function partOf(o)
    if not o or not o.Parent then return nil end
    if o:IsA("BasePart") then return o end
    if o:IsA("Attachment") then return o.Parent and o.Parent:IsA("BasePart") and o.Parent or nil end
    if o:IsA("Model") then return o.PrimaryPart or o:FindFirstChildWhichIsA("BasePart",true) end
    return nil
end
local function promptPosition(p)
    if not p or not p.Parent then return nil end
    if p.Parent:IsA("Attachment") then return p.Parent.WorldPosition end
    local part=partOf(p.Parent)
    return part and part.Position
end
local index, prompts, effects = {}, {}, {}
local scanning=false
local scanGeneration=0
local selected, home
local recent=setmetatable({},{__mode="k"})
local function namedKind(o)
    if not o:IsA("Model") and not o:IsA("BasePart") then return nil end
    if player.Character and o:IsDescendantOf(player.Character) then return nil end
    local n=o.Name:lower()
    if n:find("egg",1,true) or n:find("telur",1,true) then return "Egg" end
    if n:find("guard",1,true) then return "Guard" end
    if n:find("pet",1,true) then return "Pet" end
    if n:find("base",1,true) or n:find("pen",1,true) then return "Base" end
end
local function isEffect(o)
    return o:IsA("ParticleEmitter") or o:IsA("Trail") or o:IsA("Beam") or o:IsA("PostEffect")
end
local function indexObject(o)
    if not o:IsDescendantOf(Workspace) then return end
    if o:IsA("Model") or o:IsA("BasePart") then
        local eventName=o.Name:lower()
        if namedKind(o) or (Adapter.placeId==game.PlaceId and Adapter.describe) or
            eventName:find("butterfly",1,true) or eventName:find("star",1,true) or
            eventName:find("halloween",1,true) or eventName:find("phantom",1,true) or
            eventName:find("racing",1,true) or eventName:find("capture",1,true) then index[o]=true end
    end
    if o:IsA("ProximityPrompt") then prompts[o]=true end
    if isEffect(o) then
        effects[o]=true
        if state.fpsSaver then setVisual(o,"Enabled",false) end
    end
end
local function rescan()
    if scanning then return end
    scanning=true;scanGeneration=scanGeneration+1
    local generation=scanGeneration
    task.spawn(function()
        for i,o in ipairs(Workspace:GetDescendants()) do
            if not alive or generation~=scanGeneration then return end
            indexObject(o)
            if i%250==0 then task.wait() end
        end
        scanning=false
    end)
end
local function readAttribute(o,key)
    if key=="" then return nil end
    local value=o:GetAttribute(key)
    if type(value)=="string" or finite(value) then return value end
end
local function describe(o)
    if not o or not o:IsDescendantOf(Workspace) then return nil end
    if Adapter.placeId==game.PlaceId and type(Adapter.describe)=="function" then
        local ok,data=pcall(Adapter.describe,o)
        if ok and type(data)=="table" then return data end
    end
    local kind=namedKind(o)
    if not kind then return nil end
    local ancestor=o.Parent
    while ancestor and ancestor~=Workspace do
        if namedKind(ancestor)==kind then return nil end
        ancestor=ancestor.Parent
    end
    -- Explicit metadata mapping; empty by default, never infer rarity from name.
    return {name=o.Name,kind=kind,rarity=readAttribute(o,cfg.rarityAttribute),
        value=readAttribute(o,cfg.valueAttribute),mutation=readAttribute(o,cfg.mutationAttribute),
        zone=readAttribute(o,cfg.zoneAttribute),heuristic=true}
end
local function contains(csv,value)
    if csv=="" then return true end
    if value==nil then return false end
    for token in csv:gmatch("[^,]+") do
        token=token:match("^%s*(.-)%s*$"):lower()
        if token==tostring(value):lower() then return true end
    end
    return false
end
local function matches(d)
    if not d then return false end
    if not contains(cfg.rarity,d.rarity) or not contains(cfg.mutation,d.mutation)
       or not contains(cfg.names,d.name) or not contains(cfg.zone,d.zone) then return false end
    if cfg.blacklist~="" and contains(cfg.blacklist,d.name) then return false end
    if cfg.minValue>0 and (not finite(d.value) or d.value<cfg.minValue) then return false end
    if cfg.maxValue>0 and (not finite(d.value) or d.value>cfg.maxValue) then return false end
    return true
end
local rarities={"Common","Uncommon","Rare","Epic","Legendary","Mythic","Cosmic","Secret","Divine","Eternal"}
local rank={}
for i,name in ipairs(rarities) do rank[name]=i end
local function candidates()
    local root=rootPart();local list={}
    if not root then return list end
    for o in pairs(index) do
        local d=describe(o)
        if d and d.kind=="Egg" and matches(d) then
            local p=partOf(o)
            if p then
                local distance=(p.Position-root.Position).Magnitude
                if distance<=cfg.scanRadius and (not recent[o] or os.clock()-recent[o]>12) then
                    list[#list+1]={object=o,data=d,distance=distance}
                end
            end
        end
    end
    table.sort(list,function(a,b)
        if cfg.priority=="Value" and (a.data.value or -1)~=(b.data.value or -1) then
            local av=finite(a.data.value) and a.data.value or -1
            local bv=finite(b.data.value) and b.data.value or -1
            if av~=bv then return av>bv end
        end
        if cfg.priority=="Rarity" and (rank[a.data.rarity] or 0)~=(rank[b.data.rarity] or 0) then
            return (rank[a.data.rarity] or 0)>(rank[b.data.rarity] or 0)
        end
        return a.distance<b.distance
    end)
    return list
end
local function choose()
    local list=candidates()
    for _,entry in ipairs(list) do
        if cfg.selectedName=="" or entry.data.name==cfg.selectedName then
            selected=entry.object;return entry
        end
    end
    selected=nil
end
local operation={generation=0,busy=false,tween=nil,hold=nil}
local function stop(reason)
    operation.generation=operation.generation+1
    state.autoStealEgg=false;state.autoFarmEgg=false
    if operation.tween then operation.tween:Cancel();operation.tween=nil end
    if operation.hold then pcall(function() operation.hold:InputHoldEnd() end);operation.hold=nil end
    local h=humanoid();local r=rootPart()
    if h and r then h:MoveTo(r.Position) end
    metrics.state="IDLE"
    if reason then log(reason) end
end
local function live(token,ch)
    local h=humanoid()
    return alive and token==operation.generation and player.Character==ch and h and h.Health>0
end
local function pause(seconds,token,ch)
    local deadline=os.clock()+seconds
    repeat
        if not live(token,ch) then return false end
        task.wait(0.05)
    until os.clock()>=deadline
    return live(token,ch)
end
local function moveTo(getPosition,token,ch,tolerance)
    local root=rootPart();local h=humanoid()
    if not root or not h or not live(token,ch) then return false,"Character unavailable" end
    local goal=getPosition()
    if typeof(goal)~="Vector3" then return false,"Target disappeared" end
    tolerance=tolerance or 5
    if cfg.method=="Teleport" then
        if not adapterReady(false) or not Adapter.permitTeleport then return false,"Teleport unsupported: no consistency evidence" end
        root.CFrame=CFrame.new(goal)
    elseif cfg.method=="Tween" then
        operation.tween=TweenService:Create(root,TweenInfo.new(math.max(0.1,(goal-root.Position).Magnitude/cfg.travelSpeed),Enum.EasingStyle.Linear),{CFrame=CFrame.new(goal)})
        operation.tween:Play()
    end
    local deadline=os.clock()+cfg.timeout;local stable=0
    while live(token,ch) and os.clock()<deadline do
        root=rootPart();goal=getPosition()
        if not root or typeof(goal)~="Vector3" then break end
        if cfg.method=="Walk" then h:MoveTo(goal) end
        if (root.Position-goal).Magnitude<=tolerance then stable=stable+1 else stable=0 end
        if stable>=3 then
            if operation.tween then operation.tween:Cancel();operation.tween=nil end
            h:MoveTo(root.Position)
            return true
        end
        task.wait(0.1)
    end
    if operation.tween then operation.tween:Cancel();operation.tween=nil end
    if h.Parent and root and root.Parent then h:MoveTo(root.Position) end
    return false,"Movement timeout, target invalidated, or cancelled"
end
local function interact(prompt,token,ch)
    if not live(token,ch) or not prompt or not prompt.Parent or not prompt.Enabled then return false,"Prompt unavailable" end
    local p=promptPosition(prompt);local r=rootPart()
    if not p or not r or (p-r.Position).Magnitude>prompt.MaxActivationDistance then return false,"Outside prompt range" end
    if prompt.RequiresLineOfSight then
        local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
        params.FilterDescendantsInstances={ch}
        local hit=Workspace:Raycast(r.Position,p-r.Position,params)
        if hit and (hit.Position-p).Magnitude>2 then return false,"Prompt line of sight blocked" end
    end
    metrics.prompts=metrics.prompts+1
    local duration=prompt.HoldDuration
    if duration>cfg.timeout then return false,"HoldDuration exceeds timeout" end
    local ok,err
    if type(fireproximityprompt)=="function" then
        -- Use one interaction path only, never native input plus executor trigger.
        if not pause(math.max(0.1,duration),token,ch) then return false,"Cancelled" end
        p=promptPosition(prompt);r=rootPart()
        if not prompt.Parent or not prompt.Enabled or not p or not r or
            (p-r.Position).Magnitude>prompt.MaxActivationDistance then return false,"Prompt invalidated" end
        ok,err=pcall(fireproximityprompt,prompt,duration)
    else
        operation.hold=prompt
        ok,err=pcall(function() prompt:InputHoldBegin() end)
        if not ok then operation.hold=nil;return false,tostring(err) end
        local held=pause(math.max(0.1,duration+0.1),token,ch)
        pcall(function() prompt:InputHoldEnd() end);operation.hold=nil
        if not held then return false,"Cancelled" end
    end
    if not ok then return false,tostring(err) end
    return true,"Interaction attempted; outcome unverified"
end
local function snapshot(id)
    local ok,s=pcall(Adapter.snapshot,id)
    if not ok or type(s)~="table" or s.id~=id or type(s.owned)~="boolean"
        or type(s.carried)~="boolean" or type(s.deposited)~="boolean" then return nil end
    return s
end
local function waitEvidence(id,phase,token,ch)
    local deadline=os.clock()+cfg.timeout;local stable=0
    while live(token,ch) and os.clock()<deadline do
        local s=snapshot(id)
        local accepted=s and s.owned and ((phase=="pickup" and s.carried and not s.deposited)
            or (phase=="deposit" and s.deposited and not s.carried))
        stable=accepted and stable+1 or 0
        if stable>=3 then return true end
        task.wait(0.15)
    end
    return false
end
local function cycle(deposit,token,ch)
    metrics.state="SCAN"
    local entry=choose()
    if not entry then return false,"No matching Egg" end
    metrics.state="SELECT TARGET"
    local target,id=entry.object,entry.data.id
    if id==nil then return false,"Adapter did not provide stable Egg ID" end
    local before=snapshot(id)
    if not before or before.owned or before.carried or before.deposited then return false,"Missing or already-owned baseline" end
    recent[target]=os.clock();metrics.attempts=metrics.attempts+1
    local prompt=Adapter.pickupPrompt(target)
    metrics.state="APPROACH"
    local ok,err=moveTo(function() return promptPosition(prompt) end,token,ch,prompt and math.min(5,prompt.MaxActivationDistance*0.8) or 5)
    if not ok then return false,err end
    metrics.state="INTERACT"
    ok,err=interact(prompt,token,ch)
    if not ok then return false,err end
    metrics.state="VERIFY"
    if not waitEvidence(id,"pickup",token,ch) then
        -- An uncertain pickup must never be retried automatically (duplicate/lost item risk).
        stop("Pickup outcome unknown; inspect inventory before restarting")
        return false,"No acquisition evidence"
    end
    metrics.acquired=metrics.acquired+1
    if not deposit then stop("Acquisition observed; deposit manually before restarting");return true end
    local destination=Adapter.basePosition()
    if typeof(destination)~="Vector3" then stop("Owned Egg retained: base unavailable");return false,"Base unavailable" end
    metrics.state="RETURN"
    ok,err=moveTo(function() return destination end,token,ch,5)
    if not ok then stop("Return failed; inspect carried Egg");return false,err end
    metrics.state="DEPOSIT"
    prompt=Adapter.depositPrompt(id)
    if not prompt then stop("Deposit prompt unavailable");return false,"Deposit unsupported" end
    ok,err=moveTo(function() return promptPosition(prompt) end,token,ch,math.min(5,prompt.MaxActivationDistance*0.8))
    if not ok then stop("Deposit approach failed");return false,err end
    ok,err=interact(prompt,token,ch)
    if not ok then stop("Deposit interaction failed");return false,err end
    if not waitEvidence(id,"deposit",token,ch) then stop("Deposit unverified; inspect inventory");return false,"No deposit evidence" end
    metrics.deposits=metrics.deposits+1;metrics.state="REPEAT"
    return true
end
local function start(mode)
    if operation.busy then log("Wait for the current operation to stop");return end
    local deposit=(mode=="farm") or cfg.autoReturn
    if not adapterReady(deposit) then log("UNSUPPORTED: ownership/deposit adapter unmapped. Use diagnostic probe.");return end
    if not rootPart() or not humanoid() or humanoid().Health<=0 then log("Character unavailable");return end
    stop();metrics.failures=0
    state.autoFarmEgg=mode=="farm";state.autoStealEgg=mode~="farm"
    operation.busy=true
    local token,ch=operation.generation,player.Character
    task.spawn(function()
        repeat
            local ok,result,err=pcall(cycle,deposit,token,ch)
            if not ok or not result then
                metrics.failed=metrics.failed+1;metrics.failures=metrics.failures+1
                metrics.lastError=tostring(ok and err or result);log(metrics.lastError)
                if not cfg.retry or metrics.failures>=cfg.maxFailures then stop("Failure limit reached");break end
            else metrics.failures=0 end
            if not live(token,ch) then break end
            if mode=="manual" then break end
        until not pause(cfg.interval,token,ch)
        if token==operation.generation then stop() end
        operation.busy=false
    end)
end
-- Serialized local probe/movement. Never counts a pickup/deposit as successful.
local function manualJob(callback)
    if operation.busy then log("Operation busy; STOP first");return end
    if not rootPart() or not humanoid() or humanoid().Health<=0 then log("Character unavailable");return end
    stop();operation.busy=true
    local token,ch=operation.generation,player.Character
    task.spawn(function()
        local ok,err=pcall(callback,token,ch)
        if not ok then metrics.lastError=tostring(err);log(err) end
        if token==operation.generation then stop() end
        operation.busy=false
    end)
end
local function probe()
    manualJob(function(token,ch)
        local entry=choose()
        if not entry then log("No matching Egg candidate");return end
        local target=entry.object;local found
        -- Only prompts under this exact target; never sibling cash/sell prompts.
        for p in pairs(prompts) do
            local action=p.ActionText:lower()
            if p.Enabled and p:IsDescendantOf(target) and
                (action=="steal" or action=="steal egg" or action=="take egg" or action=="pick up") then
                if found then log("Ambiguous prompts; use the game interaction manually");return end
                found=p
            end
        end
        if not found then log("No unambiguous pickup prompt; diagnostic export needed");return end
        metrics.attempts=metrics.attempts+1
        local ok,err=moveTo(function() return promptPosition(found) end,token,ch,math.min(5,found.MaxActivationDistance*0.8))
        if ok then ok,err=interact(found,token,ch) end
        if not ok then metrics.failed=metrics.failed+1 end
        log(err or "Probe complete. Check game inventory manually.")
    end)
end

-- ESP, Performance, Inventory protection, Diagnostics.
local markers={}
local function clearMarkers()
    for o,m in pairs(markers) do m.gui:Destroy();m.highlight:Destroy();markers[o]=nil end
end
local function applyFpsSaver()
    if not state.fpsSaver then restoreVisuals();return end
    setVisual(Lighting,"GlobalShadows",false)
    for _,o in ipairs(Lighting:GetChildren()) do if isEffect(o) then setVisual(o,"Enabled",false) end end
    for o in pairs(effects) do if o.Parent then setVisual(o,"Enabled",false) end end
end
local function refreshESP()
    local root=rootPart();local keep={};local count=0
    if root then
        for o in pairs(index) do
            local d=describe(o)
            local enabled=d and ((d.kind=="Egg" and state.eggESP and matches(d)) or
                (d.kind=="Guard" and state.guardESP) or (d.kind=="Pet" and state.petESP) or
                (d.kind=="Base" and state.baseESP))
            local p=enabled and partOf(o)
            if p and (p.Position-root.Position).Magnitude<=cfg.scanRadius and count<cfg.maxMarkers then
                count=count+1;keep[o]=true
                local m=markers[o]
                if not m then
                    local hl=Instance.new("Highlight");hl.Name="SinntV3Highlight";hl.Adornee=o
                    hl.FillTransparency=0.8;hl.Parent=o
                    local bill=Instance.new("BillboardGui");bill.Name="SinntV3Label";bill.Adornee=p
                    bill.Size=UDim2.fromOffset(220,55);bill.StudsOffsetWorldSpace=Vector3.new(0,3,0)
                    bill.AlwaysOnTop=true;bill.Parent=p
                    local label=Instance.new("TextLabel");label.Size=UDim2.fromScale(1,1)
                    label.BackgroundTransparency=1;label.TextSize=11;label.Font=Enum.Font.GothamBold
                    label.TextStrokeTransparency=0.25;label.TextWrapped=true;label.Parent=bill
                    m={gui=bill,highlight=hl,label=label};markers[o]=m
                end
                local color=d.rarity and rank[d.rarity] and Color3.fromHSV((rank[d.rarity]-1)/12,0.65,1) or Color3.fromRGB(185,185,200)
                m.highlight.FillColor=color;m.highlight.OutlineColor=color;m.label.TextColor3=color
                m.label.Text=string.format("%s%s | %d studs\n%s | Value %s | %s",tostring(d.name or o.Name),
                    d.heuristic and " [?]" or "",math.floor((p.Position-root.Position).Magnitude),
                    tostring(d.rarity or "Unknown"),tostring(d.value or "Unknown"),tostring(d.mutation or "Unknown"))
            end
        end
    end
    for o,m in pairs(markers) do
        if not keep[o] then m.gui:Destroy();m.highlight:Destroy();markers[o]=nil end
    end
    for _,plr in ipairs(Players:GetPlayers()) do
        local m=playerVisuals[plr]
        local head=plr.Character and plr.Character:FindFirstChild("Head")
        if not state.playerESP or not head then deletePlayerVisual(plr)
        elseif plr~=player then
            if not m or m[2].Adornee~=head then addPlayerVisual(plr);m=playerVisuals[plr] end
            if m and root then m[3].Text=plr.DisplayName.." ["..math.floor((head.Position-root.Position).Magnitude).." studs]" end
        end
    end
end
local Inventory={}
-- Destructive automation intentionally has no interaction path until game integration.
function Inventory.CanConsume(item,rules)
    if type(item)~="table" or type(rules)~="table" or rules.enabled~=true then return false end
    if item.owned~=true or item.favorite~=false or item.equipped~=false then return false end
    if not finite(item.value) or not finite(rules.maxValue) or item.value>rules.maxValue then return false end
    if not rank[item.rarity] or rank[item.rarity]>=rank.Mythic then return false end
    if item.mutation==nil or (item.mutation~="None" and rules.allowMutated~=true) then return false end
    if type(rules.whitelist)~="string" or rules.whitelist=="" or not contains(rules.whitelist,item.name) then return false end
    if type(rules.blacklist)=="string" and rules.blacklist~="" and contains(rules.blacklist,item.name) then return false end
    return true
end
local function diagnostic()
    local root=rootPart();local out={version="3.0.0-preview",placeId=game.PlaceId,
        adapter=Adapter.name,runtime="RUNTIME TEST REQUIRED",metrics=metrics,logs=logs,
        capabilities={getgenv=type(getgenv)=="function",writefile=type(writefile)=="function",
        readfile=type(readfile)=="function",isfile=type(isfile)=="function",
        fireproximityprompt=type(fireproximityprompt)=="function",queue_on_teleport=type(queue_on_teleport)=="function"},objects={}}
    -- Allowlisted metadata only: no player attributes, account tokens, cookies, or remotes.
    local sorted=candidates()
    for i,entry in ipairs(sorted) do
        if i>40 then break end
        local o=entry.object;local item={name=o.Name,path=o:GetFullName(),distance=entry.distance,
            metadata=entry.data,prompts={}}
        item.metadata={name=entry.data.name,rarity=entry.data.rarity,value=entry.data.value,mutation=entry.data.mutation,zone=entry.data.zone}
        local n=0
        for p in pairs(prompts) do
            if p:IsDescendantOf(o) and n<10 then
                n=n+1;item.prompts[#item.prompts+1]={name=p.Name,action=p.ActionText,object=p.ObjectText,
                    enabled=p.Enabled,hold=p.HoldDuration,range=p.MaxActivationDistance}
            end
        end
        out.objects[#out.objects+1]=item
    end
    local body=HttpService:JSONEncode(out)
    if type(writefile)=="function" then
        local ok,err=pcall(writefile,"SINNT_HUB_V3_DIAGNOSTIC.json",body)
        log(ok and "Saved SINNT_HUB_V3_DIAGNOSTIC.json locally" or err)
    else log("writefile unavailable; diagnostic printed to executor console");print(body) end
end
local eventTerms={"butterfly","shooting star","halloween","phantom express","halloween dimension","racing","capture the egg"}
local function eventReport()
    local report={}
    for _,term in ipairs(eventTerms) do
        local seen=false
        for o in pairs(index) do if o.Name:lower():find(term,1,true) then seen=true;break end end
        report[#report+1]=term..": "..(seen and "Experimental: name observed, active status unknown" or "Not observed (may be streamed out)")
    end
    return table.concat(report,"\n")
end
local serverBusy=false
local function rejoin()
    if serverBusy then return end
    stop("Rejoining");serverBusy=true
    local ok,err=pcall(function() TeleportService:TeleportToPlaceInstance(game.PlaceId,game.JobId,player) end)
    if not ok then serverBusy=false;log(err) end
end
local function hop()
    if serverBusy or operation.busy then log("Stop the active operation first");return end
    serverBusy=true
    task.spawn(function()
        local ok,err=pcall(function()
            local body=game:HttpGet("https://games.roblox.com/v1/games/"..game.PlaceId.."/servers/Public?sortOrder=Asc&limit=100")
            local data=HttpService:JSONDecode(body)
            if not alive then return end
            if type(data)~="table" or type(data.data)~="table" then error("Invalid server response") end
            for _,s in ipairs(data.data) do
                if type(s.id)=="string" and s.id~=game.JobId and finite(s.playing) and finite(s.maxPlayers) and s.playing<s.maxPlayers then
                    stop("Joining another server; rerun the hub after arrival")
                    TeleportService:TeleportToPlaceInstance(game.PlaceId,s.id,player);return
                end
            end
            error("No free server found in the first 100; retry later")
        end)
        if not ok and alive then log("Server hop failed: "..tostring(err)) end
        serverBusy=false
    end)
end
local mainGui = Instance.new("ScreenGui")
mainGui.Name = guiName
mainGui.DisplayOrder = 950
mainGui.ResetOnSpawn = false
mainGui.IgnoreGuiInset = true
mainGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
mainGui.Parent = playerGui
local BG = Color3.fromRGB(16, 19, 30)
local CARD = Color3.fromRGB(27, 32, 49)
local ACCENT = Color3.fromRGB(121, 94, 253)
local MUTED = Color3.fromRGB(161, 169, 190)
local WHITE = Color3.fromRGB(242, 243, 250)
local GREEN = Color3.fromRGB(77, 213, 157)

local function corner(parent, radius)
    local x = Instance.new("UICorner")
    x.CornerRadius = UDim.new(0, radius or 9)
    x.Parent = parent
    return x
end
local function stroke(parent, color)
    local x = Instance.new("UIStroke")
    x.Color = color or Color3.fromRGB(56, 63, 88)
    x.Transparency = 0.35
    x.Thickness = 1
    x.Parent = parent
    return x
end
local function text(parent, str, size, color, bold)
    local x = Instance.new("TextLabel")
    x.BackgroundTransparency = 1
    x.Text = str
    x.Font = bold and Enum.Font.GothamBold or Enum.Font.Gotham
    x.TextColor3 = color or WHITE
    x.TextSize = size or 14
    x.TextWrapped = true
    x.TextXAlignment = Enum.TextXAlignment.Left
    x.Parent = parent
    return x
end
local function button(parent, str, size)
    local b = Instance.new("TextButton")
    b.BackgroundColor3 = CARD
    b.AutoButtonColor = true
    b.TextColor3 = WHITE
    b.Font = Enum.Font.GothamMedium
    b.TextSize = size or 13
    b.Text = str
    b.Parent = parent
    corner(b, 9)
    return b
end

local bubble = button(mainGui, "S", 22)
bubble.Size = UDim2.fromOffset(50, 50)
bubble.Position = UDim2.new(0, 14, 0.48, 0)
bubble.BackgroundColor3 = ACCENT
bubble.Visible = false
stroke(bubble, Color3.fromRGB(183, 165, 255))

local panel = Instance.new("Frame")
panel.Name = "Panel"
panel.Size = UDim2.new(0, 326, 0, 426)
panel.AnchorPoint = Vector2.new(0.5, 0.5)
panel.Position = UDim2.new(0.5, 0, 0.5, 0)
panel.BackgroundColor3 = BG
panel.BorderSizePixel = 0
panel.ClipsDescendants = true
panel.Parent = mainGui
corner(panel, 14)
stroke(panel)

local titleBar = Instance.new("Frame")
titleBar.Size = UDim2.new(1, 0, 0, 55)
titleBar.BackgroundColor3 = Color3.fromRGB(23, 26, 42)
titleBar.BorderSizePixel = 0
titleBar.Parent = panel
local titleText = text(titleBar, "SINNT HUB", 18, WHITE, true)
titleText.Size = UDim2.new(1, -78, 0, 26)
titleText.Position = UDim2.fromOffset(16, 6)
local subtitle = text(titleBar, "V3 ULTIMATE • PREVIEW • NO KEY", 10, MUTED)
subtitle.Size = UDim2.new(1, -82, 0, 16)
subtitle.Position = UDim2.fromOffset(16, 31)
local closeBtn = button(titleBar, "−", 23)
closeBtn.Size = UDim2.fromOffset(36, 34)
closeBtn.Position = UDim2.new(1, -46, 0, 10)
closeBtn.BackgroundColor3 = Color3.fromRGB(51, 55, 79)

local tabFrame = Instance.new("ScrollingFrame")
tabFrame.CanvasSize=UDim2.new()
tabFrame.AutomaticCanvasSize=Enum.AutomaticSize.X
tabFrame.ScrollingDirection=Enum.ScrollingDirection.X
tabFrame.ScrollBarThickness=2
tabFrame.BorderSizePixel=0
tabFrame.BackgroundTransparency = 1
tabFrame.Position = UDim2.fromOffset(10, 62)
tabFrame.Size = UDim2.new(1, -20, 0, 38)
tabFrame.Parent = panel
local tabLayout = Instance.new("UIListLayout")
tabLayout.FillDirection = Enum.FillDirection.Horizontal
tabLayout.Padding = UDim.new(0, 6)
tabLayout.Parent = tabFrame
local scroll = Instance.new("ScrollingFrame")
scroll.Position = UDim2.fromOffset(10, 107)
scroll.Size = UDim2.new(1, -20, 1, -145)
scroll.BackgroundTransparency = 1
scroll.ScrollBarThickness = 3
scroll.ScrollBarImageColor3 = ACCENT
scroll.BorderSizePixel = 0
scroll.AutomaticCanvasSize = Enum.AutomaticSize.Y
scroll.CanvasSize = UDim2.new(0, 0, 0, 0)
scroll.Parent = panel
local listLayout = Instance.new("UIListLayout")
listLayout.SortOrder = Enum.SortOrder.LayoutOrder
listLayout.Padding = UDim.new(0, 7)
listLayout.Parent = scroll

local status = text(panel, "Siap untuk pengujian.", 11, MUTED)
status.Size = UDim2.new(1, -22, 0, 24)
status.Position = UDim2.new(0, 11, 1, -32)
status.TextTruncate = Enum.TextTruncate.AtEnd
notice = function(message)
    if alive then status.Text = tostring(message) end
end

local function draggable(frame, handle)
    local active, origin, position
    track(handle.InputBegan:Connect(function(input)
        if input.UserInputType==Enum.UserInputType.Touch or input.UserInputType==Enum.UserInputType.MouseButton1 then
            active=input;origin=input.Position;position=frame.AbsolutePosition
        end
    end))
    track(UserInputService.InputEnded:Connect(function(input) if input==active then active=nil end end))
    track(UserInputService.InputChanged:Connect(function(input)
        if not active or not origin then return end
        if input~=active and input.UserInputType~=Enum.UserInputType.MouseMovement then return end
        local camera=Workspace.CurrentCamera;if not camera then return end
        local delta=input.Position-origin;local size=frame.AbsoluteSize;local viewport=camera.ViewportSize
        local x=math.clamp(position.X+delta.X,0,math.max(0,viewport.X-size.X))
        local y=math.clamp(position.Y+delta.Y,0,math.max(0,viewport.Y-size.Y))
        frame.Position=UDim2.fromOffset(x+size.X*frame.AnchorPoint.X,y+size.Y*frame.AnchorPoint.Y)
    end))
end
draggable(panel, titleBar)
draggable(bubble, bubble)
track(closeBtn.Activated:Connect(function()
    panel.Visible = false
    bubble.Visible = true
end))
track(bubble.Activated:Connect(function()
    panel.Visible = true
    bubble.Visible = false
end))

local currentTab = "HOME"
local tabs = {}
local renderTab
for _, name in ipairs({"HOME", "STEAL", "FARM", "ESP", "PLAYER", "COMBAT", "EVENTS", "SERVER", "SETTINGS"}) do
    local b = button(tabFrame, name, 12)
    b.Size = UDim2.new(0, 80, 1, -3)
    tabs[name] = b
    track(b.Activated:Connect(function()
        currentTab = name
        renderTab()
    end))
end
local toggleRefresh={}
local function cleanPage()
    table.clear(toggleRefresh)
    for _, conn in ipairs(pageConnections) do
        pcall(function() conn:Disconnect() end)
    end
    table.clear(pageConnections)
    for _, item in ipairs(scroll:GetChildren()) do
        if item ~= listLayout then item:Destroy() end
    end
    scroll.CanvasPosition = Vector2.new(0, 0)
end
local function heading(t)
    local x = text(scroll, t, 12, MUTED, true)
    x.Size = UDim2.new(1, -10, 0, 25)
    return x
end
local function paragraph(s, height)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -5, 0, height or 59)
    f.BackgroundColor3 = CARD
    f.Parent = scroll
    corner(f)
    local x = text(f, s, 12, WHITE)
    x.Size = UDim2.new(1, -24, 1, -12)
    x.Position = UDim2.fromOffset(12, 6)
    return f
end
local featureChanged
local function toggleRow(title, desc, key)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -5, 0, 64)
    f.BackgroundColor3 = CARD
    f.Parent = scroll
    corner(f)
    local nameLabel = text(f, title, 13, WHITE, true)
    nameLabel.Position = UDim2.fromOffset(12, 8)
    nameLabel.Size = UDim2.new(1, -98, 0, 20)
    local descLabel = text(f, desc, 10, MUTED)
    descLabel.Position = UDim2.fromOffset(12, 31)
    descLabel.Size = UDim2.new(1, -100, 0, 23)
    local b = button(f, "", 11)
    b.Position = UDim2.new(1, -83, 0, 15)
    b.Size = UDim2.fromOffset(70, 34)
    local function refresh()
        b.Text = state[key] and "ON" or "OFF"
        b.BackgroundColor3 = state[key] and Color3.fromRGB(36, 104, 78) or Color3.fromRGB(64, 69, 89)
        b.TextColor3 = state[key] and GREEN or WHITE
    end
    refresh()
    toggleRefresh[#toggleRefresh+1]=refresh
    trackPage(b.Activated:Connect(function()
        state[key] = not state[key]
        featureChanged(key)
        if cfg.autoSave then saveSettings() end
        refresh()

    end))
end
local function actionRow(title, desc, callback)
    local f = Instance.new("Frame")
    f.Size = UDim2.new(1, -5, 0, 62)
    f.BackgroundColor3 = CARD
    f.Parent = scroll
    corner(f)
    local a = text(f, title, 13, WHITE, true)
    a.Position = UDim2.fromOffset(12, 8)
    a.Size = UDim2.new(1, -95, 0, 20)
    local d = text(f, desc, 10, MUTED)
    d.Position = UDim2.fromOffset(12, 30)
    d.Size = UDim2.new(1, -105, 0, 25)
    local b = button(f, "JALANKAN", 10)
    b.BackgroundColor3 = ACCENT
    b.Position = UDim2.new(1, -92, 0, 15)
    b.Size = UDim2.fromOffset(80, 32)
    trackPage(b.Activated:Connect(function()
        local ok, msg = pcall(callback)
        if not ok then metrics.lastError=tostring(msg);log("Error: " .. tostring(msg)) end
    end))
end


local function field(title,key,min,max)
    heading(title)
    local box=Instance.new("TextBox");box.Size=UDim2.new(1,-8,0,40)
    box.BackgroundColor3=CARD;box.TextColor3=WHITE;box.Font=Enum.Font.Gotham
    box.TextSize=13;box.ClearTextOnFocus=false;box.Text=tostring(cfg[key]);box.Parent=scroll;corner(box)
    trackPage(box.FocusLost:Connect(function()
        if operation.busy then box.Text=tostring(cfg[key]);log("Stop operation before changing settings");return end
        if min then
            local value=tonumber(box.Text)
            if not finite(value) then box.Text=tostring(cfg[key]);log("Enter a finite number");return end
            cfg[key]=math.clamp(value,min,max)
        else cfg[key]=box.Text:sub(1,500) end
        box.Text=tostring(cfg[key]);applyMovement()
        if cfg.autoSave then saveSettings() end
    end))
end
local function choice(title,key,values)
    local b=button(scroll,title..": "..tostring(cfg[key]),12);b.Size=UDim2.new(1,-8,0,42)
    trackPage(b.Activated:Connect(function()
        if operation.busy then log("Stop operation before changing settings");return end
        local current=1
        for i,value in ipairs(values) do if cfg[key]==value then current=i end end
        cfg[key]=values[current%#values+1]
        b.Text=title..": "..tostring(cfg[key]);if cfg.autoSave then saveSettings() end
    end))
end
local function statsText()
    return string.format("State: %s | Runtime: %ds\nAttempts: %d | Acquired (observed): %d\nFailed/cancelled: %d | Deposits (observed): %d\nPrompt attempts: %d | FPS: %.0f\nLast error: %s",metrics.state,
        math.floor(os.clock()-metrics.started),metrics.attempts,metrics.acquired,metrics.failed,
        metrics.deposits,metrics.prompts,metrics.fps,metrics.lastError~="" and metrics.lastError or "None")
end
featureChanged=function(key)
    if key=="speed" or key=="jump" then applyMovement() end
    if key=="noclip" and not state.noclip then restoreCollisions() end
    if key=="fpsSaver" then applyFpsSaver() end
    if key=="playerESP" then refreshPlayerVisuals() end
    log(key..": "..tostring(state[key]))
end
local function resetAll()
    stop("All features OFF")
    for key in pairs(state) do state[key]=false end
    applyMovement();restoreCollisions();restoreVisuals();clearMarkers();refreshPlayerVisuals()
end
local destroyHub
local pageStats
renderTab=function()
    if not alive then return end
    cleanPage();pageStats=nil
    for name,b in pairs(tabs) do b.BackgroundColor3=name==currentTab and ACCENT or CARD end
    if currentTab=="HOME" then
        heading("SINNT HUB V3 ULTIMATE • PREVIEW")
        paragraph("Standalone upgrade from V2. RUNTIME TEST REQUIRED. Steal/Farm needs a verified game adapter; this build does not claim feature parity with Chilli.",95)
        local card=paragraph(statsText(),145);pageStats=card:FindFirstChildOfClass("TextLabel")
        actionRow("Export diagnostic","Save local candidate + prompt report",diagnostic)
        actionRow("STOP","Cancel movement and automation now",function() stop("Stopped by user") end)
    elseif currentTab=="STEAL" then
        heading("STEAL • "..(adapterReady(false) and "EXPERIMENTAL ADAPTER" or "ADAPTER REQUIRED"))
        paragraph("Automatic pickup is blocked until ownership can be verified. Diagnostic probe attempts one visible pickup prompt; it never reports success.",90)
        actionRow("Auto Steal ON / OFF","Current: "..tostring(state.autoStealEgg),function() if state.autoStealEgg then stop("Auto Steal OFF") else start("steal") end end)
        actionRow("Manual Steal Egg","One verified cycle; requires adapter",function() start("manual") end)
        actionRow("Diagnostic probe","One unverified prompt attempt",probe)
        actionRow("STOP","Immediately cancels the current operation",function() stop("Stopped") end)
        actionRow("Select target","Nearest / Value / Rarity with filters",function()
            local e=choose();log(e and (e.data.name.." | "..math.floor(e.distance).." studs | "..tostring(e.data.rarity or "Unknown")) or "No match")
        end)
        field("Exact target name (empty = automatic)","selectedName")
        choice("Priority","priority",{"Nearest","Value","Rarity"})
        choice("Movement","method",{"Walk","Tween","Teleport"})
        paragraph("Walk uses MoveTo and can time out at obstacles. Tween is experimental. Teleport is blocked until the adapter confirms consistent game support.",85)
        field("Travel speed (Tween)","travelSpeed",1,150)
        field("Interval seconds","interval",1,60);field("Timeout seconds","timeout",2,60)
        field("Consecutive failure limit","maxFailures",1,10)
        choice("Retry","retry",{false,true});choice("Return + deposit","autoReturn",{false,true})
        heading("FILTERS • exact comma-separated values")
        field("Rarity (Common ... Eternal)","rarity");field("Minimum value (0 = off)","minValue",0,1e17)
        field("Maximum value (0 = off)","maxValue",0,1e17);field("Mutations","mutation")
        field("Name whitelist","names");field("Name blacklist","blacklist");field("Zones","zone")
        actionRow("Set Base Here","Session only; not proof of base ownership",function()
            local r=rootPart();if r then home=r.Position;log("Manual base point recorded for this life") end
        end)
        actionRow("Return to marked point","Movement only; never counts as deposit",function()
            if not home then log("Set Base Here first");return end
            manualJob(function(t,c) local ok,err=moveTo(function() return home end,t,c,5);log(ok and "Arrived; deposit unverified" or err) end)
        end)
    elseif currentTab=="FARM" then
        heading("STATE MACHINE")
        paragraph("IDLE > SCAN > SELECT > APPROACH > INTERACT > VERIFY > RETURN > DEPOSIT > REPEAT. One shared operation lock. Unknown pickup/deposit stops the loop.",105)
        actionRow("Auto Farm ON / OFF","Current: "..tostring(state.autoFarmEgg),function() if state.autoFarmEgg then stop("Auto Farm OFF") else start("farm") end end)
        actionRow("STOP","Cancel farm and movement",function() stop("Farm OFF") end)
        paragraph("UNSUPPORTED: Auto Place, Hatch, Cash, Claim, Equip Best Pet, Favorite, Sell Eggs/Pets, Mutate, Fuse, Treadmill, Upgrade Treadmill/Base, task priorities. Game integration required.",130)
        paragraph("Inventory protection is implemented as a fail-closed policy. No sell/fuse/mutate/hatch action is dispatched. Unknown, favorite, equipped, mutated or Mythic+ items are protected by default.",115)
        actionRow("Export evidence","Capture nearby Egg + prompt metadata",diagnostic)
    elseif currentTab=="ESP" then
        heading("CLIENT OBSERVATIONS • UNKNOWN IS NOT GUESSED")
        toggleRow("Egg ESP","Filtered labels; name heuristic marked [?]","eggESP")
        toggleRow("Player ESP","Character name and distance","playerESP")
        toggleRow("Guard ESP","Name heuristic only","guardESP")
        toggleRow("Pet ESP","Name heuristic only","petESP")
        toggleRow("Base ESP","Name heuristic only","baseESP")
        field("Marker limit","maxMarkers",1,60);field("Scan radius (studs)","scanRadius",10,5000)
        actionRow("Rescan","One batched pass; streaming supported",rescan)
        actionRow("Egg Information","Top 12 matching candidates",function()
            local lines={}
            for i,e in ipairs(candidates()) do
                if i>12 then break end
                lines[#lines+1]=e.data.name.." | "..tostring(e.data.rarity or "Unknown").." | Value "..tostring(e.data.value or "Unknown").." | Zone "..tostring(e.data.zone or "Unknown")
            end
            paragraph(#lines>0 and table.concat(lines,"\n") or "No candidates",math.max(60,#lines*45))
        end)
    elseif currentTab=="PLAYER" then
        toggleRow("Speed Boost","Client-side; server may reject","speed");field("WalkSpeed","speed",1,150)
        toggleRow("Jump Boost","Client JumpPower","jump");field("JumpPower","jumpPower",1,150)
        toggleRow("Infinite Jump","Jump input while airborne","infiniteJump")
        toggleRow("Noclip","Local collisions; restored on OFF","noclip")
        toggleRow("Anti-AFK","VirtualUser attempt; runtime required","antiAFK")
        toggleRow("Auto Equip Tool","Exact tool name, no arbitrary selection","autoEquip");field("Tool name","toolName")
        actionRow("Character status","Current observed values",function()
            local h=humanoid();log(h and ("Health "..h.Health.." | Speed "..h.WalkSpeed.." | State "..h:GetState().Name) or "No character")
        end)
        paragraph("God Mode, Anti Guard, Anti Ragdoll, Invisible and trap bypass are unsupported. No anti-cheat or licensing bypass is included.",90)
    elseif currentTab=="COMBAT" then
        paragraph("Auto Hit attempts Tool:Activate() only when another living player is in range. It does not claim a hit, damage, or a kill. Hit Aura and damage verification are unsupported.",105)
        toggleRow("Auto Hit (Experimental)","Pauses while a movement job is active","autoHit")
        field("Range (studs)","combatRange",1,15);field("Required tool name","toolName")
        paragraph("Tool activation attempts: "..metrics.hitsAttempted.."\nTarget: nearest living player. No chase, remote calls, or range modification.",80)
    elseif currentTab=="EVENTS" then
        paragraph(eventReport(),250)
        paragraph("Event automation and reward collection: Unsupported. Object names alone do not establish that an event is active. Refresh this tab to rescan indexed names.",100)
    elseif currentTab=="SERVER" then
        paragraph("PlaceId: "..game.PlaceId.."\nJobId: "..game.JobId.."\nPlayers: "..#Players:GetPlayers().." / "..Players.MaxPlayers,100)
        actionRow("Rejoin","Reconnect to this exact server",rejoin)
        actionRow("Server Hop","Public server list; first page only",hop)
        paragraph("Auto Hop and automatic execution after teleport: Unsupported in this preview. Re-execute the standalone script after joining.",90)
    elseif currentTab=="SETTINGS" then
        toggleRow("Low Graphics / FPS Saver","Disable shadows and effects, reversible","fpsSaver")
        choice("Auto save preferences","autoSave",{true,false})
        actionRow("Save config","Actions always start OFF",function() local ok,err=saveSettings();log(ok and "Config saved" or err) end)
        actionRow("Load config","Stop first; place-scoped settings",function() resetAll();loadSettings();renderTab();log("Preferences loaded; actions OFF") end)
        heading("METADATA MAPPING • exact observed attribute names")
        paragraph("Leave empty when unknown. These mappings label/filter objects only. They do not enable ownership verification or automatic farming.",90)
        field("Rarity attribute","rarityAttribute");field("Value attribute","valueAttribute")
        field("Mutation attribute","mutationAttribute");field("Zone attribute","zoneAttribute")
        actionRow("Export diagnostic","No account tokens or remote dumps",diagnostic)
        actionRow("Error log","Last 20 entries",function()
            local lines={};for i=math.max(1,#logs-19),#logs do lines[#lines+1]=logs[i] end
            paragraph(table.concat(lines,"\n"),math.max(70,#lines*45))
        end)
        actionRow("Reset All Features","Restore properties and remove markers",function() resetAll();renderTab() end)
        actionRow("Unload Hub","Disconnect events and restore changes",function() destroyHub() end)
    end
end
-- Fixed lifetime connections, no per-drag or per-player connection accumulation.
track(Workspace.DescendantAdded:Connect(indexObject))
track(Workspace.DescendantRemoving:Connect(function(o) index[o]=nil;prompts[o]=nil;effects[o]=nil;recent[o]=nil end))
track(Lighting.ChildAdded:Connect(function(o) if state.fpsSaver and isEffect(o) then setVisual(o,"Enabled",false) end end))
track(player.CharacterRemoving:Connect(function() stop("Character removed; automation OFF");home=nil;restoreCollisions() end))
track(player.CharacterAdded:Connect(function() home=nil;restoreCollisions() end))
track(Players.PlayerRemoving:Connect(deletePlayerVisual))
track(UserInputService.JumpRequest:Connect(function()
    local h=humanoid();if alive and state.infiniteJump and h and h.Health>0 then h:ChangeState(Enum.HumanoidStateType.Jumping) end
end))
track(player.Idled:Connect(function()
    if not state.antiAFK then return end
    local ok,err=pcall(function() local vu=game:GetService("VirtualUser");vu:CaptureController();vu:ClickButton2(Vector2.new()) end)
    if not ok then log("Anti-AFK unavailable: "..tostring(err));state.antiAFK=false end
end))
track(TeleportService.TeleportInitFailed:Connect(function(plr,_,message)
    if plr==player then serverBusy=false;log("Teleport failed: "..tostring(message)) end
end))
local elapsed,frames=0,0
track(RunService.RenderStepped:Connect(function(dt)
    elapsed=elapsed+dt;frames=frames+1
    if elapsed>=1 then metrics.fps=frames/elapsed;elapsed=0;frames=0 end
end))
local noclipTick=0
track(RunService.Stepped:Connect(function(_,dt)
    noclipTick=noclipTick+dt
    if state.noclip and noclipTick>=0.05 then noclipTick=0;applyNoclip() end
end))
local function equipAndCombat()
    local ch=character();local h=humanoid();local r=rootPart()
    if operation.busy or not ch or not h or h.Health<=0 or not r or cfg.toolName=="" then return end
    if state.autoEquip then
        local bag=player:FindFirstChildOfClass("Backpack")
        local tool=bag and bag:FindFirstChild(cfg.toolName)
        if tool and tool:IsA("Tool") then h:EquipTool(tool) end
    end
    if not state.autoHit then return end
    local nearest,distance=nil,cfg.combatRange
    for _,other in ipairs(Players:GetPlayers()) do
        local c=other~=player and other.Character
        local p=c and c:FindFirstChild("HumanoidRootPart");local hum=c and c:FindFirstChildOfClass("Humanoid")
        if p and hum and hum.Health>0 then
            local d=(p.Position-r.Position).Magnitude
            if d<=distance then nearest=other;distance=d end
        end
    end
    local tool=ch:FindFirstChild(cfg.toolName)
    if nearest and tool and tool:IsA("Tool") and tool.Enabled then tool:Activate();metrics.hitsAttempted=metrics.hitsAttempted+1 end
end
local function resize()
    local cam=Workspace.CurrentCamera;if not cam then return end
    local size=cam.ViewportSize
    local width=math.min(430,math.max(180,size.X-24));local height=math.min(550,math.max(220,size.Y-24))
    if panel.Size.X.Offset~=width or panel.Size.Y.Offset~=height then
        panel.Size=UDim2.fromOffset(width,height);panel.Position=UDim2.fromScale(0.5,0.5)
    end
end
-- One periodic worker for UI, ESP and combat. Failures logged with backoff.
task.spawn(function()
    local ticks=0
    while alive do
        task.wait(0.5)
        if not alive then break end
        local ok,err=pcall(function()
            ticks=ticks+1;resize()
            if state.speed or state.jump then applyMovement() end
            equipAndCombat()
            if ticks%2==0 then
                refreshESP()
                for _,refresh in ipairs(toggleRefresh) do refresh() end
                if pageStats and pageStats.Parent then pageStats.Text=statsText() end
                local ping="Unknown"
                pcall(function() ping=game:GetService("Stats").Network.ServerStatsItem["Data Ping"]:GetValueString() end)
                subtitle.Text=string.format("V3 PREVIEW | %.0f FPS | %s | %s",metrics.fps,ping,metrics.state)
            end
        end)
        if not ok then metrics.lastError=tostring(err);log("Worker: "..tostring(err));task.wait(2) end
    end
end)
destroyHub=function()
    if not alive then return end
    resetAll();alive=false;scanGeneration=scanGeneration+1
    for _,c in ipairs(pageConnections) do pcall(function() c:Disconnect() end) end
    for _,c in ipairs(connections) do pcall(function() c:Disconnect() end) end
    table.clear(pageConnections);table.clear(connections);table.clear(toggleRefresh)
    table.clear(index);table.clear(prompts);table.clear(effects)
    mainGui:Destroy()
    if env.SINNT_HUB_V3 and env.SINNT_HUB_V3.Destroy==destroyHub then env.SINNT_HUB_V3=nil end
end
env.SINNT_HUB_V3={Destroy=destroyHub,Version="3.0.0-preview",Stop=stop,ExportDiagnostic=diagnostic}
rescan();resize();renderTab()
log("V3 PREVIEW ready | game adapter unmapped | runtime test required")
