-- AutoDefense Module for dxe
-- Auto-parry system that listens to enemy animations and blocks at the right time

local AutoDefense = {
    enabled = false,
    timings = {}, -- animId -> parryMs (whitelist of animations to parry)
    debugMode = false,
}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")

-- Local player
local LocalPlayer = Players.LocalPlayer

-- State
local connections = {}
local trackedAnimators = {}
local pendingParries = {} -- { animId, entityName, executeAt, track }
local isBlocking = false
local lastBlockTime = 0
local lastNotifyTime = 0
local NOTIFY_COOLDOWN = 0.5 -- seconds between notifications

-- Key handling (will be initialized)
local KeyHandling = nil
local InputClient = nil

-- Settings (can be changed via UI)
AutoDefense.Settings = {
    enabled = false,
    maxDistance = 50, -- Max distance to auto-parry
    parryEarlyMs = 50, -- How many ms early to start blocking (ping compensation)
    blockDuration = 0.15, -- How long to hold block (seconds)
    onlyTargeted = false, -- Only parry if enemy is targeting you
    useDetectedTimings = true, -- Use timings from AnimationLogger
    fallbackParryPercent = 0.45, -- Fallback: parry at this % of animation if no timing data
    minParryMs = 100, -- Minimum ms into animation to parry
    maxParryMs = 800, -- Maximum ms into animation to parry
    onlyWhitelisted = true, -- Only parry animations with known timings
}

-- Animation blacklist (defensive animations we don't react to)
local ANIMATION_BLACKLIST = {
    "block", "parry", "trueparry", "guard", "defend",
    "stagger", "hit", "hurt", "flinch", "knockback",
    "idle", "walk", "run", "sprint", "jump", "fall",
    "dodge", "roll", "dash", "rest", "emote",
}

-- Will be set when init is called
local Library = nil
local AnimationLogger = nil

-- Utility functions
local function formatAnimationId(animId)
    local id = tostring(animId)
    id = id:gsub("rbxassetid://", "")
    id = id:gsub("http://www.roblox.com/asset/%?id=", "")
    id = id:gsub("https://www.roblox.com/asset/%?id=", "")
    return id
end

local function debugLog(...)
    if AutoDefense.debugMode then
        print("[AutoDefense]", ...)
    end
end

local function notify(message, duration)
    if Library and not (shared.dxe and shared.dxe.silent) then
        Library:Notify(message, duration or 2)
    end
end

-- Debug notification (only shows when debug mode is on, with cooldown)
local function debugNotify(message, duration)
    if not AutoDefense.debugMode or not Library then return end
    
    local now = os.clock()
    if now - lastNotifyTime < NOTIFY_COOLDOWN then return end
    lastNotifyTime = now
    
    Library:Notify("[Debug] " .. message, duration or 2)
end

-- Check if animation name is blacklisted
local function isBlacklisted(animName)
    if not animName then return false end
    local lowerName = animName:lower()
    for _, pattern in ipairs(ANIMATION_BLACKLIST) do
        if lowerName:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- Get distance to entity
local function getDistanceToEntity(entity)
    local character = LocalPlayer.Character
    if not character then return math.huge end
    
    local localRoot = character:FindFirstChild("HumanoidRootPart")
    if not localRoot then return math.huge end
    
    local entityRoot = entity:FindFirstChild("HumanoidRootPart")
    if not entityRoot then return math.huge end
    
    return (localRoot.Position - entityRoot.Position).Magnitude
end

-- Check if entity is targeting local player
local function isTargetingMe(entity)
    local targetValue = entity:FindFirstChild("Target")
    if not targetValue then return true end -- Assume yes if no target value
    
    local character = LocalPlayer.Character
    return targetValue.Value == character
end

-- Get the parry timing for an animation (returns nil if not in whitelist)
local function getParryTiming(animId, animLength, animSpeed)
    local formattedId = formatAnimationId(animId)
    
    -- First check detected timings from AnimationLogger
    if AutoDefense.Settings.useDetectedTimings and AnimationLogger and type(AnimationLogger.getParryTimings) == "function" then
        local success, loggerTimings = pcall(function()
            return AnimationLogger.getParryTimings()
        end)
        if success and loggerTimings and loggerTimings[formattedId] then
            local avgMs = loggerTimings[formattedId].avgMs
            if avgMs and avgMs > 0 then
                debugLog("Using detected timing for", formattedId, ":", avgMs, "ms")
                return avgMs
            end
        end
    end
    
    -- Check manual timings
    if AutoDefense.timings[formattedId] then
        return AutoDefense.timings[formattedId]
    end
    
    -- If onlyWhitelisted is true, return nil (don't parry unknown animations)
    if AutoDefense.Settings.onlyWhitelisted then
        return nil
    end
    
    -- Fallback: calculate based on animation length (only if not whitelisted mode)
    local adjustedLength = (animLength or 1) / (animSpeed or 1)
    local parryMs = adjustedLength * AutoDefense.Settings.fallbackParryPercent * 1000
    
    -- Clamp to reasonable range
    parryMs = math.clamp(parryMs, AutoDefense.Settings.minParryMs, AutoDefense.Settings.maxParryMs)
    
    debugLog("Using fallback timing for", formattedId, ":", parryMs, "ms")
    return parryMs
end

-- Send block input to server (press F key)
local function sendBlock()
    local character = LocalPlayer.Character
    if not character then 
        debugLog("Block failed: No character")
        return false 
    end
    
    -- Get EffectReplicator to check state
    local effectReplicator = ReplicatedStorage:FindFirstChild("EffectReplicator")
    if not effectReplicator then 
        debugLog("Block failed: No EffectReplicator")
        return false 
    end
    
    local effectReplicatorModule
    pcall(function()
        effectReplicatorModule = require(effectReplicator)
    end)
    
    if not effectReplicatorModule then 
        debugLog("Block failed: Can't require EffectReplicator")
        return false 
    end
    
    -- Check if we can block (not in action, not knocked, etc.)
    if effectReplicatorModule:FindEffect("Action") then
        debugLog("Cannot block - in action")
        return false
    end
    
    if effectReplicatorModule:FindEffect("Knocked") then
        debugLog("Cannot block - knocked")
        return false
    end
    
    if effectReplicatorModule:HasEffect("Blocking") then
        debugLog("Already blocking")
        return true
    end
    
    -- Press F key using VirtualInputManager
    local success = pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    
    if success then
        isBlocking = true
        lastBlockTime = os.clock()
        debugLog("Block sent (F key pressed)!")
        return true
    end
    
    debugLog("Block failed: VirtualInputManager error")
    return false
end

-- Send unblock input (release F key)
local function sendUnblock()
    if not isBlocking then return end
    
    -- Release F key
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    
    isBlocking = false
    debugLog("Unblock sent (F key released)!")
end

-- Schedule a parry
local function scheduleParry(animId, animName, entityName, parryMs, track)
    local now = os.clock()
    local executeAt = now + (parryMs - AutoDefense.Settings.parryEarlyMs) / 1000
    
    table.insert(pendingParries, {
        animId = animId,
        animName = animName,
        entityName = entityName,
        executeAt = executeAt,
        track = track,
        scheduled = now,
    })
    
    local delayMs = parryMs - AutoDefense.Settings.parryEarlyMs
    debugLog(string.format("Scheduled parry for %s's %s in %.0fms", entityName, animName or animId, delayMs))
end

-- Process pending parries
local function processPendingParries()
    local now = os.clock()
    
    for i = #pendingParries, 1, -1 do
        local parry = pendingParries[i]
        
        -- Check if animation stopped
        if parry.track and not parry.track.IsPlaying then
            debugLog("Parry cancelled - animation stopped:", parry.animName or parry.animId)
            table.remove(pendingParries, i)
            continue
        end
        
        -- Check if it's time to parry
        if now >= parry.executeAt then
            debugLog(string.format("Executing parry for %s's %s", parry.entityName, parry.animName or parry.animId))
            
            if sendBlock() then
                debugNotify(string.format("⚔ Parry: %s", parry.animName or parry.animId), 1)
                
                -- Schedule unblock
                task.delay(AutoDefense.Settings.blockDuration, function()
                    sendUnblock()
                end)
            else
                debugNotify(string.format("✗ Failed: %s", parry.animName or parry.animId), 1)
            end
            
            table.remove(pendingParries, i)
        end
    end
end

-- Handle animation played on an entity
local function onAnimationPlayed(animator, track)
    if not AutoDefense.Settings.enabled then return end
    if not track or not track.Animation then return end
    
    local entity = animator:FindFirstAncestorWhichIsA("Model")
    if not entity then return end
    
    -- Skip local player's animations
    if entity == LocalPlayer.Character then return end
    
    -- Get animation info
    local animId = track.Animation.AnimationId
    local animName = track.Animation.Name
    local formattedId = formatAnimationId(animId)
    
    -- Skip blacklisted animations (defensive/movement)
    if isBlacklisted(animName) then return end
    
    -- Distance check FIRST (most important filter)
    local distance = getDistanceToEntity(entity)
    if distance > AutoDefense.Settings.maxDistance then return end
    
    -- Target check (optional)
    if AutoDefense.Settings.onlyTargeted and not isTargetingMe(entity) then
        return
    end
    
    -- Get parry timing (returns nil if not in whitelist when onlyWhitelisted is true)
    local parryMs = getParryTiming(animId, track.Length, track.Speed)
    
    -- Skip if no timing found (not in whitelist)
    if not parryMs then
        debugLog("Skipping unknown animation:", animName or formattedId)
        return
    end
    
    debugLog(string.format("Attack detected: %s playing %s @ %.1f studs (%.0fms timing)", 
        entity.Name, animName or formattedId, distance, parryMs))
    
    -- Schedule the parry
    scheduleParry(formattedId, animName, entity.Name, parryMs, track)
end

-- Track an animator
local function trackAnimator(animator)
    if trackedAnimators[animator] then return end
    
    local conn = animator.AnimationPlayed:Connect(function(track)
        onAnimationPlayed(animator, track)
    end)
    
    trackedAnimators[animator] = conn
    table.insert(connections, conn)
end

-- Scan for animators in a model
local function scanForAnimators(model)
    for _, descendant in pairs(model:GetDescendants()) do
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end
end

-- Start auto defense
function AutoDefense.start()
    if AutoDefense.Settings.enabled then return end
    
    AutoDefense.Settings.enabled = true
    debugLog("Auto Defense started")
    
    -- Scan workspace for existing animators
    scanForAnimators(workspace)
    
    -- Scan Live folder specifically
    local live = workspace:FindFirstChild("Live")
    if live then
        scanForAnimators(live)
        
        -- Watch for new entities in Live
        local liveConn = live.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Animator") then
                trackAnimator(descendant)
            end
        end)
        table.insert(connections, liveConn)
    end
    
    -- Watch for new animators in workspace
    local wsConn = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end)
    table.insert(connections, wsConn)
    
    -- Update loop for processing pending parries
    local updateConn = RunService.RenderStepped:Connect(function()
        if AutoDefense.Settings.enabled then
            processPendingParries()
        end
    end)
    table.insert(connections, updateConn)
    
    notify("Auto Defense enabled", 2)
end

-- Stop auto defense
function AutoDefense.stop()
    AutoDefense.Settings.enabled = false
    
    -- Clean up connections
    for _, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    connections = {}
    trackedAnimators = {}
    pendingParries = {}
    
    -- Make sure we're not stuck blocking
    sendUnblock()
    
    debugLog("Auto Defense stopped")
    notify("Auto Defense disabled", 2)
end

-- Toggle auto defense
function AutoDefense.toggle()
    if AutoDefense.Settings.enabled then
        AutoDefense.stop()
    else
        AutoDefense.start()
    end
end

-- Set a manual timing for an animation
function AutoDefense.setTiming(animId, parryMs)
    local formattedId = formatAnimationId(animId)
    AutoDefense.timings[formattedId] = parryMs
    debugLog("Set timing for", formattedId, "to", parryMs, "ms")
end

-- Import timings from AnimationLogger
function AutoDefense.importTimings()
    if not AnimationLogger then
        notify("AnimationLogger not available", 2)
        return
    end
    
    if type(AnimationLogger.getParryTimings) ~= "function" then
        notify("AnimationLogger.getParryTimings not available (update AnimationLogger)", 3)
        return
    end
    
    local success, loggerTimings = pcall(function()
        return AnimationLogger.getParryTimings()
    end)
    
    if not success or not loggerTimings then
        notify("No timings to import", 2)
        return
    end
    
    local count = 0
    for animId, data in pairs(loggerTimings) do
        if data.avgMs and data.avgMs > 0 then
            AutoDefense.timings[animId] = data.avgMs
            count = count + 1
        end
    end
    
    notify(string.format("Imported %d timings from AnimationLogger", count), 3)
    debugLog("Imported", count, "timings")
end

-- Initialize the module
function AutoDefense.init(lib, animLogger)
    Library = lib
    AnimationLogger = animLogger
    
    -- Initialize shared table if needed
    shared.dxe = shared.dxe or {}
    shared.dxe.AutoDefense = AutoDefense
    
    -- Try to load KeyHandling module (Lycoris style)
    pcall(function()
        -- Check if already loaded in shared
        if shared.KeyHandling then
            KeyHandling = shared.KeyHandling
            debugLog("Using shared KeyHandling")
        end
    end)
    
    -- Try to load InputClient module
    pcall(function()
        if shared.InputClient then
            InputClient = shared.InputClient
            debugLog("Using shared InputClient")
        end
    end)
    
    debugLog("Auto Defense initialized", KeyHandling and "(KeyHandling found)" or "(KeyHandling not found)")
end

-- Set KeyHandling module externally
function AutoDefense.setKeyHandling(keyHandlingModule)
    KeyHandling = keyHandlingModule
    debugLog("KeyHandling set externally")
end

-- Set InputClient module externally
function AutoDefense.setInputClient(inputClientModule)
    InputClient = inputClientModule
    debugLog("InputClient set externally")
end

-- Return module
return AutoDefense
