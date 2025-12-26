-- AutoDefense Module for dxe
-- Auto-parry system that listens to enemy animations and blocks at the right time
-- Based on Lycoris-Rewrite blocking system

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

-- Remote references (direct path from SimpleSpy)
local blockRemote = nil
local unblockRemote = nil

-- Get Block remote directly
local function getBlockRemote()
    if blockRemote then return blockRemote end
    
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("EVENTS")
        if events then
            blockRemote = events:FindFirstChild("Block")
        end
    end)
    
    return blockRemote
end

-- Get Unblock remote (if it exists)
local function getUnblockRemote()
    if unblockRemote then return unblockRemote end
    
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("EVENTS")
        if events then
            unblockRemote = events:FindFirstChild("Unblock")
        end
    end)
    
    return unblockRemote
end

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

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================
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

local function debugNotify(message, duration)
    if not AutoDefense.debugMode or not Library then return end
    
    local now = os.clock()
    if now - lastNotifyTime < NOTIFY_COOLDOWN then return end
    lastNotifyTime = now
    
    Library:Notify("[Debug] " .. message, duration or 2)
end

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

local function getDistanceToEntity(entity)
    local character = LocalPlayer.Character
    if not character then return math.huge end
    
    local localRoot = character:FindFirstChild("HumanoidRootPart")
    if not localRoot then return math.huge end
    
    local entityRoot = entity:FindFirstChild("HumanoidRootPart")
    if not entityRoot then return math.huge end
    
    return (localRoot.Position - entityRoot.Position).Magnitude
end

local function isTargetingMe(entity)
    local targetValue = entity:FindFirstChild("Target")
    if not targetValue then return true end
    
    local character = LocalPlayer.Character
    return targetValue.Value == character
end

local function getParryTiming(animId, animLength, animSpeed)
    local formattedId = formatAnimationId(animId)
    
    -- Check detected timings from AnimationLogger
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
    
    -- If onlyWhitelisted, return nil
    if AutoDefense.Settings.onlyWhitelisted then
        return nil
    end
    
    -- Fallback calculation
    local adjustedLength = (animLength or 1) / (animSpeed or 1)
    local parryMs = adjustedLength * AutoDefense.Settings.fallbackParryPercent * 1000
    parryMs = math.clamp(parryMs, AutoDefense.Settings.minParryMs, AutoDefense.Settings.maxParryMs)
    
    debugLog("Using fallback timing for", formattedId, ":", parryMs, "ms")
    return parryMs
end

-- =============================================
-- BLOCKING FUNCTIONS
-- =============================================
local function canBlock()
    local effectReplicator = ReplicatedStorage:FindFirstChild("EffectReplicator")
    if not effectReplicator then return false end
    
    local effectReplicatorModule
    pcall(function()
        effectReplicatorModule = require(effectReplicator)
    end)
    
    if not effectReplicatorModule then return false end
    
    -- Can't block if in action or knocked
    if effectReplicatorModule:FindEffect("Action") then
        debugLog("Cannot block - in action")
        return false
    end
    
    if effectReplicatorModule:FindEffect("Knocked") then
        debugLog("Cannot block - knocked")
        return false
    end
    
    return true
end

local function isCurrentlyBlocking()
    local effectReplicator = ReplicatedStorage:FindFirstChild("EffectReplicator")
    if not effectReplicator then return false end
    
    local effectReplicatorModule
    pcall(function()
        effectReplicatorModule = require(effectReplicator)
    end)
    
    if not effectReplicatorModule then return false end
    return effectReplicatorModule:HasEffect("Blocking")
end

local function sendBlock()
    local character = LocalPlayer.Character
    if not character then 
        debugLog("Block failed: No character")
        return false 
    end
    
    if not canBlock() then
        return false
    end
    
    if isCurrentlyBlocking() then
        debugLog("Already blocking")
        return true
    end
    
    -- Method 1: Use Block remote directly (from SimpleSpy)
    local remote = getBlockRemote()
    if remote then
        local success = pcall(function()
            remote:FireServer()
        end)
        if success then
            isBlocking = true
            lastBlockTime = os.clock()
            debugLog("Block sent via EVENTS.Block remote!")
            return true
        end
    end
    
    -- Method 2: Use VirtualInputManager to press F (fallback)
    local success = pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    
    if success then
        isBlocking = true
        lastBlockTime = os.clock()
        debugLog("Block sent via VIM (F key)!")
        return true
    end
    
    debugLog("Block failed: No method worked")
    return false
end

local function sendUnblock()
    if not isBlocking then return end
    
    -- Method 1: Use Unblock remote if it exists
    local remote = getUnblockRemote()
    if remote then
        pcall(function()
            remote:FireServer()
        end)
        isBlocking = false
        debugLog("Unblock sent via EVENTS.Unblock remote!")
        return
    end
    
    -- Method 2: Release F key
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    
    isBlocking = false
    debugLog("Unblock sent via VIM!")
end

-- =============================================
-- PARRY SCHEDULING
-- =============================================
local function scheduleParry(animId, animName, entityName, parryMs, track)
    local now = os.clock()
    local delayMs = math.max(0, parryMs - AutoDefense.Settings.parryEarlyMs)
    local executeAt = now + delayMs / 1000
    
    table.insert(pendingParries, {
        animId = animId,
        animName = animName,
        entityName = entityName,
        executeAt = executeAt,
        track = track,
        scheduled = now,
    })
    
    debugLog(string.format("Scheduled parry for %s's %s in %.0fms", entityName, animName or animId, delayMs))
end

local function processPendingParries()
    local now = os.clock()
    
    for i = #pendingParries, 1, -1 do
        local parry = pendingParries[i]
        
        -- Cancel if animation stopped
        if parry.track and not parry.track.IsPlaying then
            debugLog("Parry cancelled - animation stopped:", parry.animName or parry.animId)
            table.remove(pendingParries, i)
            continue
        end
        
        -- Execute when time
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

-- =============================================
-- ANIMATION TRACKING
-- =============================================
local function onAnimationPlayed(animator, track)
    if not AutoDefense.Settings.enabled then return end
    if not track or not track.Animation then return end
    
    local entity = animator:FindFirstAncestorWhichIsA("Model")
    if not entity then return end
    
    -- Skip local player
    if entity == LocalPlayer.Character then return end
    
    local animId = track.Animation.AnimationId
    local animName = track.Animation.Name
    local formattedId = formatAnimationId(animId)
    
    -- Skip blacklisted
    if isBlacklisted(animName) then return end
    
    -- Distance check
    local distance = getDistanceToEntity(entity)
    if distance > AutoDefense.Settings.maxDistance then return end
    
    -- Target check
    if AutoDefense.Settings.onlyTargeted and not isTargetingMe(entity) then
        return
    end
    
    -- Get timing (nil if not whitelisted)
    local parryMs = getParryTiming(animId, track.Length, track.Speed)
    if not parryMs then
        return
    end
    
    debugLog(string.format("Attack: %s playing %s @ %.1f studs (%.0fms)", 
        entity.Name, animName or formattedId, distance, parryMs))
    
    scheduleParry(formattedId, animName, entity.Name, parryMs, track)
end

local function trackAnimator(animator)
    if trackedAnimators[animator] then return end
    
    local conn = animator.AnimationPlayed:Connect(function(track)
        onAnimationPlayed(animator, track)
    end)
    
    trackedAnimators[animator] = conn
    table.insert(connections, conn)
end

local function scanForAnimators(model)
    for _, descendant in pairs(model:GetDescendants()) do
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end
end

-- =============================================
-- PUBLIC API
-- =============================================
function AutoDefense.start()
    if AutoDefense.Settings.enabled then return end
    
    AutoDefense.Settings.enabled = true
    debugLog("Auto Defense starting...")
    
    -- Try to find Block remote
    local remote = getBlockRemote()
    if remote then
        debugLog("Found Block remote at EVENTS.Block!")
    else
        debugLog("Block remote not found, using VIM fallback")
    end
    
    -- Scan for animators
    scanForAnimators(workspace)
    
    local live = workspace:FindFirstChild("Live")
    if live then
        scanForAnimators(live)
        
        local liveConn = live.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Animator") then
                trackAnimator(descendant)
            end
        end)
        table.insert(connections, liveConn)
    end
    
    local wsConn = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end)
    table.insert(connections, wsConn)
    
    -- Update loop
    local updateConn = RunService.RenderStepped:Connect(function()
        if AutoDefense.Settings.enabled then
            processPendingParries()
        end
    end)
    table.insert(connections, updateConn)
    
    local remote = getBlockRemote()
    notify("Auto Defense enabled" .. (remote and " (remote)" or " (VIM)"), 2)
end

function AutoDefense.stop()
    AutoDefense.Settings.enabled = false
    
    for _, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    connections = {}
    trackedAnimators = {}
    pendingParries = {}
    
    sendUnblock()
    
    debugLog("Auto Defense stopped")
    notify("Auto Defense disabled", 2)
end

function AutoDefense.toggle()
    if AutoDefense.Settings.enabled then
        AutoDefense.stop()
    else
        AutoDefense.start()
    end
end

function AutoDefense.setTiming(animId, parryMs)
    local formattedId = formatAnimationId(animId)
    AutoDefense.timings[formattedId] = parryMs
    debugLog("Set timing for", formattedId, "to", parryMs, "ms")
end

function AutoDefense.importTimings()
    if not AnimationLogger then
        notify("AnimationLogger not available", 2)
        return
    end
    
    if type(AnimationLogger.getParryTimings) ~= "function" then
        notify("AnimationLogger.getParryTimings not available", 3)
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
    
    notify(string.format("Imported %d timings", count), 3)
    debugLog("Imported", count, "timings")
end

function AutoDefense.init(lib, animLogger)
    Library = lib
    AnimationLogger = animLogger
    
    shared.dxe = shared.dxe or {}
    shared.dxe.AutoDefense = AutoDefense
    
    debugLog("Auto Defense initialized")
end

return AutoDefense
