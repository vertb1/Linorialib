-- AutoDefense Module for dxe
-- Rewritten to match Lycoris-Rewrite architecture
-- Uses QueuedBlocking for frame-perfect blocking

local AutoDefense = {
    enabled = false,
    timings = {}, -- animId -> { parryMs, blockType, ... }
    debugMode = false,
}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local UserInputService = game:GetService("UserInputService")
local VirtualInputManager = game:GetService("VirtualInputManager")
local Stats = game:GetService("Stats")

-- Local player
local LocalPlayer = Players.LocalPlayer

-- Block types (matching Lycoris QueuedBlocking)
AutoDefense.BLOCK_TYPE_DEFLECT = 1 -- For parry/deflect frames - removed as soon as blocking
AutoDefense.BLOCK_TYPE_NORMAL = 2 -- For normal blocking - stays until dead time

-- State
local connections = {}
local trackedAnimators = {}
local pendingParries = {} -- { animId, entityName, executeAt, track, blockType }
local blockQueue = {} -- { id -> { start, type, dt } }
local isBlocking = false
local lastBlockTime = 0
local lastNotifyTime = 0
local NOTIFY_COOLDOWN = 0.5

-- Module references (loaded dynamically)
local KeyHandling = nil
local InputClient = nil
local StateListener = nil
local QueuedBlocking = nil
local Library = nil
local AnimationLogger = nil
local Latency = nil

-- Ping/Latency tracking
local pingHistory = {}
local PING_HISTORY_SIZE = 10
local lastPing = 0
local averagePing = 0

-- Effect replicator cache
local effectReplicatorModule = nil
local effectReplicatorFailed = false

-- Settings
AutoDefense.Settings = {
    enabled = false,
    maxDistance = 50,
    parryEarlyMs = 50,
    blockDuration = 0.15,
    onlyTargeted = false,
    useDetectedTimings = true,
    fallbackParryPercent = 0.45,
    minParryMs = 100,
    maxParryMs = 800,
    onlyWhitelisted = true,
    useQueuedBlocking = true, -- Use frame-perfect blocking like Lycoris
    checkBreakMeter = true, -- Don't block if break meter too high
    checkEffects = true, -- Check for Action, Knocked, etc.
    allowDodge = false, -- Use dodge instead of block for certain attacks
    autoRagdollRecover = false, -- Auto feint when knocked
    
    -- Ping compensation (Lycoris-style)
    autoPingCompensation = true, -- Auto-adjust timing based on ping
    pingMultiplier = 1.0, -- Multiplier for ping compensation (1.0 = 100% of one-way latency)
    maxPingCompensation = 150, -- Max ms to compensate for ping
    
    -- M1 Block
    blockM1 = false, -- Block input during M1 attacks
    m1BlockDuration = 0.3, -- How long to block M1 input after detecting attack
}

-- Animation blacklist
local ANIMATION_BLACKLIST = {
    "block", "parry", "trueparry", "guard", "defend",
    "stagger", "hit", "hurt", "flinch", "knockback",
    "idle", "walk", "run", "sprint", "jump", "fall",
    "dodge", "roll", "dash", "rest", "emote",
    "smith", "fly", "hover", "glide",
}

-- =============================================
-- UTILITY FUNCTIONS
-- =============================================
local function debugLog(...)
    if AutoDefense.debugMode then
        print("[AutoDefense]", ...)
    end
end

local function formatAnimationId(animId)
    local id = tostring(animId)
    id = id:gsub("rbxassetid://", "")
    id = id:gsub("http://www.roblox.com/asset/%?id=", "")
    id = id:gsub("https://www.roblox.com/asset/%?id=", "")
    return id
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

-- =============================================
-- PING/LATENCY FUNCTIONS (Lycoris-style)
-- =============================================
local function getCurrentPing()
    -- Try Latency module first
    if Latency and Latency.ping then
        local success, ping = pcall(function()
            return Latency.ping()
        end)
        if success and ping and ping > 0 then
            return ping
        end
    end
    
    -- Fallback to Stats
    local success, ping = pcall(function()
        local network = Stats:FindFirstChild("Network")
        if network then
            local serverStats = network:FindFirstChild("ServerStatsItem")
            if serverStats then
                local dataPing = serverStats:FindFirstChild("Data Ping")
                if dataPing then
                    return dataPing:GetValue() or 0
                end
            end
        end
        return 0
    end)
    
    return (success and ping) or 0
end

local function getOneWayLatency()
    -- One-way latency is approximately half of RTT
    if Latency and Latency.oneWay then
        local success, lat = pcall(function()
            return Latency.oneWay()
        end)
        if success and lat then
            return lat
        end
    end
    return getCurrentPing() / 2
end

local function updatePingHistory()
    local ping = getCurrentPing()
    table.insert(pingHistory, ping)
    
    -- Keep only recent history
    while #pingHistory > PING_HISTORY_SIZE do
        table.remove(pingHistory, 1)
    end
    
    -- Calculate average
    local sum = 0
    for _, p in ipairs(pingHistory) do
        sum = sum + p
    end
    averagePing = #pingHistory > 0 and (sum / #pingHistory) or ping
    lastPing = ping
    
    return ping
end

local function getPingCompensation()
    if not AutoDefense.Settings.autoPingCompensation then
        return 0
    end
    
    updatePingHistory()
    
    -- Use one-way latency (server to client) for compensation
    local oneWay = getOneWayLatency()
    local compensation = oneWay * AutoDefense.Settings.pingMultiplier
    
    -- Clamp to max
    compensation = math.min(compensation, AutoDefense.Settings.maxPingCompensation)
    
    return compensation
end

-- Expose ping info
function AutoDefense.getPing()
    return lastPing, averagePing
end

function AutoDefense.getCompensation()
    return getPingCompensation()
end

-- =============================================
-- M1 BLOCKING (Block input during attack)
-- =============================================
local m1BlockedUntil = 0
local originalFireServer = nil
local m1Remotes = {} -- Track M1/Attack remotes

local function isM1Blocked()
    return AutoDefense.Settings.blockM1 and os.clock() < m1BlockedUntil
end

local function blockM1ForDuration(duration)
    if not AutoDefense.Settings.blockM1 then return end
    
    local newBlockTime = os.clock() + (duration or AutoDefense.Settings.m1BlockDuration)
    if newBlockTime > m1BlockedUntil then
        m1BlockedUntil = newBlockTime
        debugLog(string.format("M1 blocked for %.2f seconds", duration or AutoDefense.Settings.m1BlockDuration))
    end
end

local function setupM1BlockHook()
    if not AutoDefense.Settings.blockM1 then return end
    
    -- Find attack remotes
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("EVENTS")
        if events then
            local attackNames = {"Attack", "LightAttack", "M1", "Swing", "Hit"}
            for _, name in ipairs(attackNames) do
                local remote = events:FindFirstChild(name)
                if remote then
                    m1Remotes[remote] = true
                end
            end
        end
    end)
    
    -- Try to use KeyHandling if available
    if KeyHandling and KeyHandling.getRemote then
        pcall(function()
            local attackRemote = KeyHandling.getRemote("Attack")
            if attackRemote then
                m1Remotes[attackRemote] = true
            end
        end)
    end
    
    debugLog("M1 block hook setup complete, tracking", 0, "remotes")
end

-- =============================================
-- MODULE LOADING
-- =============================================
local function loadModules()
    -- Try to load KeyHandling
    pcall(function()
        local kh = script.Parent:FindFirstChild("KeyHandling")
        if kh then
            KeyHandling = require(kh)
            if KeyHandling.init then
                KeyHandling.init()
            end
            debugLog("KeyHandling loaded")
        end
    end)
    
    -- Try to load InputClient
    pcall(function()
        local ic = script.Parent:FindFirstChild("InputClient")
        if ic then
            InputClient = require(ic)
            debugLog("InputClient loaded")
        end
    end)
    
    -- Try to load StateListener
    pcall(function()
        local sl = script.Parent:FindFirstChild("StateListener")
        if sl then
            StateListener = require(sl)
            if StateListener.init then
                StateListener.init()
            end
            debugLog("StateListener loaded")
        end
    end)
    
    -- Try to load QueuedBlocking
    pcall(function()
        local qb = script.Parent:FindFirstChild("QueuedBlocking")
        if qb then
            QueuedBlocking = require(qb)
            if QueuedBlocking.init then
                QueuedBlocking.init()
            end
            debugLog("QueuedBlocking loaded")
        end
    end)
    
    -- Try to load Latency
    pcall(function()
        local utilFolder = script.Parent.Parent:FindFirstChild("Utility")
        if utilFolder then
            local lat = utilFolder:FindFirstChild("Latency")
            if lat then
                Latency = require(lat)
                debugLog("Latency module loaded")
            end
        end
    end)
end

-- =============================================
-- EFFECT REPLICATOR
-- =============================================
local function getEffectModule()
    if effectReplicatorModule then return effectReplicatorModule end
    if effectReplicatorFailed then return nil end
    
    local success, result = pcall(function()
        local er = ReplicatedStorage:FindFirstChild("EffectReplicator")
        if er then
            return require(er)
        end
        return nil
    end)
    
    if success and result then
        effectReplicatorModule = result
        debugLog("EffectReplicator loaded")
        return effectReplicatorModule
    else
        effectReplicatorFailed = true
        debugLog("EffectReplicator not found")
        return nil
    end
end

local function hasEffect(effectName)
    local module = getEffectModule()
    if not module then return false end
    
    local success, result = pcall(function()
        if type(module.HasEffect) == "function" then
            return module:HasEffect(effectName)
        elseif type(module.FindEffect) == "function" then
            return module:FindEffect(effectName) ~= nil
        end
        return false
    end)
    
    return success and result
end

local function findEffect(effectName)
    local module = getEffectModule()
    if not module then return nil end
    
    local success, result = pcall(function()
        if type(module.FindEffect) == "function" then
            return module:FindEffect(effectName)
        end
        return nil
    end)
    
    return success and result or nil
end

-- =============================================
-- STATE CHECKS (like Lycoris StateListener)
-- =============================================
local function canBlock()
    -- Use StateListener if available
    if StateListener and StateListener.cblock then
        local success, result = pcall(function()
            return StateListener.cblock()
        end)
        if success then
            if not result then
                debugLog("StateListener.cblock() returned false")
            end
            return result
        end
    end
    
    -- Fallback checks
    local character = LocalPlayer.Character
    if not character then return false end
    
    -- Check break meter
    if AutoDefense.Settings.checkBreakMeter then
        local breakMeter = character:FindFirstChild("BreakMeter")
        if breakMeter and breakMeter.MaxValue > 0 then
            if breakMeter.Value / breakMeter.MaxValue > 0.6 then
                debugLog("Break meter too high")
                return false
            end
        end
    end
    
    -- Check effects
    if AutoDefense.Settings.checkEffects then
        if hasEffect("Action") then
            debugLog("In action")
            return false
        end
        
        if hasEffect("Knocked") or hasEffect("Ragdoll") then
            debugLog("Knocked/Ragdolled")
            return false
        end
        
        if hasEffect("ShakyBlock") then
            debugLog("Shaky block")
            return false
        end
        
        if hasEffect("CancelBlock") then
            debugLog("Block cancelled")
            return false
        end
    end
    
    return true
end

local function canParry()
    -- Use StateListener if available
    if StateListener and StateListener.cparry then
        local success, result = pcall(function()
            return StateListener.cparry()
        end)
        if success then return result end
    end
    
    -- Fallback - check parry cooldown
    if hasEffect("ParryCool") then
        debugLog("Parry on cooldown")
        return false
    end
    
    if not hasEffect("Equipped") then
        debugLog("Not equipped")
        return false
    end
    
    return true
end

local function canDodge()
    -- Use StateListener if available
    if StateListener and StateListener.cdodge then
        local success, result = pcall(function()
            return StateListener.cdodge()
        end)
        if success then return result end
    end
    
    -- Fallback
    if hasEffect("NoRoll") then
        debugLog("Dodge on cooldown")
        return false
    end
    
    return true
end

local function isHoldingBlock()
    -- Use StateListener if available
    if StateListener and StateListener.hblock then
        local success, result = pcall(function()
            return StateListener.hblock()
        end)
        if success then return result end
    end
    
    -- Fallback - check if F key is pressed
    return UserInputService:IsKeyDown(Enum.KeyCode.F)
end

-- =============================================
-- REMOTE HANDLING
-- =============================================
local blockRemote = nil
local unblockRemote = nil

local function getBlockRemote()
    if blockRemote then return blockRemote end
    
    -- Use KeyHandling if available
    if KeyHandling and KeyHandling.getRemote then
        local success, result = pcall(function()
            return KeyHandling.getRemote("Block")
        end)
        if success and result then
            blockRemote = result
            debugLog("Found Block remote via KeyHandling")
            return blockRemote
        end
    end
    
    -- Fallback
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("EVENTS")
        if events then
            blockRemote = events:FindFirstChild("Block")
        end
    end)
    
    return blockRemote
end

local function getUnblockRemote()
    if unblockRemote then return unblockRemote end
    
    if KeyHandling and KeyHandling.getRemote then
        local success, result = pcall(function()
            return KeyHandling.getRemote("Unblock")
        end)
        if success and result then
            unblockRemote = result
            debugLog("Found Unblock remote via KeyHandling")
            return unblockRemote
        end
    end
    
    pcall(function()
        local events = ReplicatedStorage:FindFirstChild("EVENTS")
        if events then
            unblockRemote = events:FindFirstChild("Unblock")
        end
    end)
    
    return unblockRemote
end

-- =============================================
-- QUEUED BLOCKING (like Lycoris)
-- =============================================
local function invokeBlock(blockType, id, deadTime)
    -- Use QueuedBlocking if available and enabled
    if AutoDefense.Settings.useQueuedBlocking and QueuedBlocking and QueuedBlocking.invoke then
        local success = pcall(function()
            QueuedBlocking.invoke(blockType, id, deadTime)
        end)
        if success then
            debugLog("Block invoked via QueuedBlocking:", id)
            return true
        end
    end
    
    -- Fallback - direct blocking
    if not canBlock() then
        return false
    end
    
    if hasEffect("Blocking") then
        debugLog("Already blocking")
        return true
    end
    
    -- Update input data if available
    if InputClient and InputClient.getInputData then
        local inputData = InputClient.getInputData()
        if inputData then
            inputData["f"] = true
        end
    end
    
    -- Fire block remote
    local remote = getBlockRemote()
    if remote then
        local fireServer = Instance.new("RemoteEvent").FireServer
        local success = pcall(function()
            fireServer(remote)
        end)
        if success then
            isBlocking = true
            lastBlockTime = os.clock()
            
            -- Add to our queue
            blockQueue[id] = {
                start = os.clock(),
                type = blockType,
                dt = deadTime,
            }
            
            debugLog("Block sent via remote:", id)
            return true
        end
    end
    
    -- VIM fallback
    local success = pcall(function()
        VirtualInputManager:SendKeyEvent(true, Enum.KeyCode.F, false, game)
    end)
    
    if success then
        isBlocking = true
        lastBlockTime = os.clock()
        blockQueue[id] = {
            start = os.clock(),
            type = blockType,
            dt = deadTime,
        }
        debugLog("Block sent via VIM:", id)
        return true
    end
    
    return false
end

local function stopBlock(id)
    -- Use QueuedBlocking if available
    if QueuedBlocking and QueuedBlocking.stop then
        pcall(function()
            QueuedBlocking.stop(id)
        end)
        debugLog("Block stopped via QueuedBlocking:", id)
        return
    end
    
    -- Fallback
    if blockQueue[id] then
        blockQueue[id] = nil
        debugLog("Block stopped:", id)
    end
    
    -- Check if queue is empty
    local queueLength = 0
    for _ in pairs(blockQueue) do
        queueLength = queueLength + 1
    end
    
    if queueLength <= 0 and isBlocking then
        -- Update input data
        if InputClient and InputClient.getInputData then
            local inputData = InputClient.getInputData()
            if inputData then
                inputData["f"] = false
            end
        end
        
        -- Send unblock
        local remote = getUnblockRemote()
        if remote then
            local fireServer = Instance.new("RemoteEvent").FireServer
            pcall(function()
                fireServer(remote)
            end)
        end
        
        pcall(function()
            VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
        end)
        
        isBlocking = false
        debugLog("Unblocked - queue empty")
    end
end

local function emptyBlockQueue()
    if QueuedBlocking and QueuedBlocking.empty then
        pcall(function()
            QueuedBlocking.empty()
        end)
    end
    blockQueue = {}
end

-- =============================================
-- BLOCKING QUEUE UPDATE (runs on RenderStepped)
-- =============================================
local function updateBlockQueue()
    if not AutoDefense.Settings.enabled then return end
    
    -- Skip if using external QueuedBlocking
    if AutoDefense.Settings.useQueuedBlocking and QueuedBlocking then
        return
    end
    
    -- Check if player is holding block manually
    if isHoldingBlock() then
        emptyBlockQueue()
        return
    end
    
    local blocking = hasEffect("Blocking")
    
    -- Process queue entries
    for id, data in pairs(blockQueue) do
        local dead = data.dt and (os.clock() - data.start >= data.dt)
        local deflected = data.type == AutoDefense.BLOCK_TYPE_DEFLECT and blocking
        
        if dead or deflected then
            stopBlock(id)
        end
    end
    
    -- Calculate queue length
    local queueLength = 0
    for _ in pairs(blockQueue) do
        queueLength = queueLength + 1
    end
    
    -- Handle blocking state
    if blocking and queueLength <= 0 then
        -- Should unblock
        local remote = getUnblockRemote()
        if remote then
            local fireServer = Instance.new("RemoteEvent").FireServer
            pcall(function()
                fireServer(remote)
            end)
        end
        isBlocking = false
    elseif not blocking and queueLength > 0 then
        -- Should block
        if canBlock() then
            local remote = getBlockRemote()
            if remote then
                local fireServer = Instance.new("RemoteEvent").FireServer
                pcall(function()
                    fireServer(remote)
                end)
            end
            isBlocking = true
        end
    end
end

-- =============================================
-- TARGET VALIDATION
-- =============================================
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
    if not targetValue then return true end -- Assume targeting if no Target value
    
    local character = LocalPlayer.Character
    return targetValue.Value == character
end

local function isValidTarget(entity)
    if not entity then return false end
    
    -- Skip local player
    if entity == LocalPlayer.Character then return false end
    
    -- Distance check
    local distance = getDistanceToEntity(entity)
    if distance > AutoDefense.Settings.maxDistance then
        return false
    end
    
    -- Target check
    if AutoDefense.Settings.onlyTargeted and not isTargetingMe(entity) then
        return false
    end
    
    -- Check if entity is block broken (NPC only)
    if not Players:GetPlayerFromCharacter(entity) then
        local root = entity:FindFirstChild("HumanoidRootPart")
        if root and root:FindFirstChild("MegalodauntBroken") then
            return false
        end
    end
    
    return true
end

-- =============================================
-- TIMING FUNCTIONS
-- =============================================
local function getParryTiming(animId, animLength, animSpeed)
    local formattedId = formatAnimationId(animId)
    
    -- Check AnimationLogger timings
    if AutoDefense.Settings.useDetectedTimings and AnimationLogger then
        local success, loggerTimings = pcall(function()
            if type(AnimationLogger.getParryTimings) == "function" then
                return AnimationLogger.getParryTimings()
            end
            return nil
        end)
        
        if success and loggerTimings and loggerTimings[formattedId] then
            local avgMs = loggerTimings[formattedId].avgMs
            if avgMs and avgMs > 0 then
                debugLog("Using detected timing:", formattedId, avgMs, "ms")
                return avgMs, AutoDefense.BLOCK_TYPE_DEFLECT
            end
        end
    end
    
    -- Check manual timings
    if AutoDefense.timings[formattedId] then
        local timing = AutoDefense.timings[formattedId]
        if type(timing) == "table" then
            return timing.parryMs, timing.blockType or AutoDefense.BLOCK_TYPE_DEFLECT
        end
        return timing, AutoDefense.BLOCK_TYPE_DEFLECT
    end
    
    -- If only whitelisted, return nil
    if AutoDefense.Settings.onlyWhitelisted then
        return nil, nil
    end
    
    -- Fallback calculation
    local adjustedLength = (animLength or 1) / (animSpeed or 1)
    local parryMs = adjustedLength * AutoDefense.Settings.fallbackParryPercent * 1000
    parryMs = math.clamp(parryMs, AutoDefense.Settings.minParryMs, AutoDefense.Settings.maxParryMs)
    
    debugLog("Using fallback timing:", formattedId, parryMs, "ms")
    return parryMs, AutoDefense.BLOCK_TYPE_DEFLECT
end

-- =============================================
-- PARRY SCHEDULING
-- =============================================
local function scheduleParry(animId, animName, entity, parryMs, blockType, track)
    local now = os.clock()
    
    -- Calculate ping compensation (Lycoris-style)
    local pingComp = getPingCompensation()
    
    -- The total delay we need to wait:
    -- parryMs = when the hit lands (from animation start)
    -- parryEarlyMs = how early we want to start blocking
    -- pingComp = ping compensation (network delay)
    -- We subtract ping compensation because we need to send the block earlier to account for network latency
    local delayMs = math.max(0, parryMs - AutoDefense.Settings.parryEarlyMs - pingComp)
    local executeAt = now + delayMs / 1000
    local uid = string.format("%s_%s_%.4f", entity.Name, formatAnimationId(animId), now)
    
    table.insert(pendingParries, {
        animId = animId,
        animName = animName,
        entity = entity,
        entityName = entity.Name,
        executeAt = executeAt,
        track = track,
        blockType = blockType or AutoDefense.BLOCK_TYPE_DEFLECT,
        uid = uid,
        scheduled = now,
        pingCompensation = pingComp, -- Track what compensation was used
    })
    
    debugLog(string.format("Scheduled parry for %s's %s in %.0fms (type %d, ping comp: %.0fms)", 
        entity.Name, animName or formatAnimationId(animId), delayMs, blockType or 1, pingComp))
    
    -- Block M1 input when attack is detected
    if AutoDefense.Settings.blockM1 then
        local m1BlockTime = math.max(0.1, (parryMs + AutoDefense.Settings.blockDuration * 1000) / 1000)
        blockM1ForDuration(m1BlockTime)
    end
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
        
        -- Cancel if target no longer valid
        if not isValidTarget(parry.entity) then
            debugLog("Parry cancelled - target invalid")
            table.remove(pendingParries, i)
            continue
        end
        
        -- Execute when time
        if now >= parry.executeAt then
            debugLog(string.format("Executing parry for %s's %s", parry.entityName, parry.animName or parry.animId))
            
            -- Calculate dead time based on block type
            local deadTime = nil
            if parry.blockType == AutoDefense.BLOCK_TYPE_DEFLECT then
                deadTime = AutoDefense.Settings.blockDuration
            end
            
            if invokeBlock(parry.blockType, parry.uid, deadTime) then
                debugNotify(string.format("⚔ Parry: %s", parry.animName or parry.animId), 1)
                
                -- Schedule stop for DEFLECT type
                if parry.blockType == AutoDefense.BLOCK_TYPE_DEFLECT then
                    task.delay(AutoDefense.Settings.blockDuration, function()
                        stopBlock(parry.uid)
                    end)
                end
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
    
    -- Validate target
    if not isValidTarget(entity) then return end
    
    local animId = track.Animation.AnimationId
    local animName = track.Animation.Name
    local formattedId = formatAnimationId(animId)
    
    -- Skip blacklisted
    if isBlacklisted(animName) then return end
    
    -- Skip low priority animations
    if track.Priority == Enum.AnimationPriority.Core then return end
    
    -- Skip low weight (blend/transition) for players
    local isPlayer = Players:GetPlayerFromCharacter(entity) ~= nil
    if isPlayer and track.WeightTarget <= 0.05 then return end
    
    -- Get timing
    local parryMs, blockType = getParryTiming(animId, track.Length, track.Speed)
    if not parryMs then return end
    
    local distance = getDistanceToEntity(entity)
    debugLog(string.format("Attack: %s playing %s @ %.1f studs (%.0fms, type %d)", 
        entity.Name, animName or formattedId, distance, parryMs, blockType or 1))
    
    scheduleParry(formattedId, animName, entity, parryMs, blockType, track)
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
    
    -- Load modules
    loadModules()
    
    -- Initialize ping tracking
    updatePingHistory()
    
    -- Setup M1 blocking
    if AutoDefense.Settings.blockM1 then
        setupM1BlockHook()
    end
    
    -- Check for remotes
    local remote = getBlockRemote()
    if remote then
        notify("Auto Defense: Block remote found", 2)
    else
        notify("Auto Defense: Using VIM fallback", 2)
    end
    
    -- Show ping info
    local ping = getCurrentPing()
    local comp = getPingCompensation()
    debugLog(string.format("Current ping: %.0fms, compensation: %.0fms", ping, comp))
    
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
    
    -- Main update loop
    local updateConn = RunService.RenderStepped:Connect(function()
        if AutoDefense.Settings.enabled then
            processPendingParries()
            updateBlockQueue()
        end
    end)
    table.insert(connections, updateConn)
    
    debugLog("Auto Defense started")
    notify("Auto Defense enabled", 2)
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
    
    emptyBlockQueue()
    
    -- Make sure we unblock
    local remote = getUnblockRemote()
    if remote then
        pcall(function()
            remote:FireServer()
        end)
    end
    
    pcall(function()
        VirtualInputManager:SendKeyEvent(false, Enum.KeyCode.F, false, game)
    end)
    
    isBlocking = false
    
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

function AutoDefense.setTiming(animId, parryMs, blockType)
    local formattedId = formatAnimationId(animId)
    AutoDefense.timings[formattedId] = {
        parryMs = parryMs,
        blockType = blockType or AutoDefense.BLOCK_TYPE_DEFLECT,
    }
    debugLog("Set timing for", formattedId, "to", parryMs, "ms (type", blockType or 1, ")")
end

function AutoDefense.importTimings()
    if not AnimationLogger then
        notify("AnimationLogger not available", 2)
        return 0
    end
    
    if type(AnimationLogger.getParryTimings) ~= "function" then
        notify("AnimationLogger.getParryTimings not available", 3)
        return 0
    end
    
    local success, loggerTimings = pcall(function()
        return AnimationLogger.getParryTimings()
    end)
    
    if not success or not loggerTimings then
        notify("No timings to import", 2)
        return 0
    end
    
    local count = 0
    for animId, data in pairs(loggerTimings) do
        if data.avgMs and data.avgMs > 0 then
            AutoDefense.timings[animId] = {
                parryMs = data.avgMs,
                blockType = AutoDefense.BLOCK_TYPE_DEFLECT,
            }
            count = count + 1
        end
    end
    
    notify(string.format("Imported %d timings", count), 3)
    debugLog("Imported", count, "timings")
    return count
end

function AutoDefense.init(lib, animLogger)
    Library = lib
    AnimationLogger = animLogger
    
    shared.dxe = shared.dxe or {}
    shared.dxe.AutoDefense = AutoDefense
    
    debugLog("Auto Defense initialized")
end

-- Expose block types for external use
AutoDefense.BlockTypes = {
    DEFLECT = AutoDefense.BLOCK_TYPE_DEFLECT,
    NORMAL = AutoDefense.BLOCK_TYPE_NORMAL,
}

-- M1 Block API
function AutoDefense.isM1Blocked()
    return isM1Blocked()
end

function AutoDefense.getM1BlockTimeRemaining()
    if isM1Blocked() then
        return m1BlockedUntil - os.clock()
    end
    return 0
end

-- Latency API
function AutoDefense.getLatencyInfo()
    local ping = getCurrentPing()
    local oneWay = getOneWayLatency()
    local comp = getPingCompensation()
    return {
        ping = ping,
        average = averagePing,
        oneWay = oneWay,
        compensation = comp,
    }
end

return AutoDefense
