-- Animation Logger Module (Standalone)
-- Logs combat animation IDs with parry timing suggestions and hitbox visualization
local AnimationLogger = {}

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Debris = game:GetService("Debris")

-- Constants
local MAX_LOG_ENTRIES = 100
local FONT_FACE = Font.new("rbxasset://fonts/families/RobotoMono.json")
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 26
local WINDOW_WIDTH = 600
local WINDOW_HEIGHT = 480
local BLACK_OUTLINE = Color3.new(0, 0, 0)
local MAX_HITBOX_TIME = 3.0
local DEFAULT_HITBOX_SIZE = Vector3.new(6, 6, 8)

-- Movement animation names to ALWAYS filter (even if Action priority)
local MOVEMENT_NAMES = {
    "front", "back", "left", "right", "forward", "backward",
    "run", "walk", "sprint", "idle", "jump", "fall", "land",
    "climb", "swim", "crawl", "crouch", "slide", "vault", "mantle",
    "dodge", "roll", "dash", "locomotion", "movement",
    "breathing", "emote", "pose", "stance", "standing", "sitting",
    "equip", "unequip", "holster", "draw", "sheath",
    -- Stagger animations (reactions, not attacks)
    "stagger", "stagger1", "stagger2", "stagger3", "stagger4",
    "hit", "hurt", "flinch", "knockback", "knockdown", "stunned",
    -- Defensive animations (not attacks)
    "block", "block1", "block2", "block3", "block4",
    "parry", "parry1", "parry2", "parry3", "parry4",
    "trueparry", "trueparry1", "trueparry2", "trueparry3", "trueparry4",
    "true_parry", "perfectparry", "perfect_parry",
    "guard", "defend", "deflect", "counter", "riposte",
}

-- TRUE PARRY animation patterns (only these = successful parry)
-- "parry" alone is an attempt, "trueparry" is a successful parry
local TRUE_PARRY_PATTERNS = {
    "trueparry", "true_parry", "perfectparry", "perfect_parry",
    "successfulparry", "successful_parry",
}

-- Will be set when init is called
local Library = nil
local AnimationVisualizer = nil

-- Track playback data with animation speed history (Lycoris-style)
local PlaybackData = {}
PlaybackData.__index = PlaybackData

function PlaybackData.new(track, entity)
    local self = setmetatable({}, PlaybackData)
    self.track = track
    self.entity = entity
    self.base = os.clock() -- Timestamp of creation
    self.ash = {} -- Animation Speed History: { [timeDelta] = speed }
    self.lastSpeed = nil
    return self
end

-- Track animation speed at current time delta
function PlaybackData:astrack(speed)
    local delta = os.clock() - self.base
    -- Only record if speed changed
    if self.lastSpeed == speed then return end
    self.ash[delta] = speed
    self.lastSpeed = speed
end

-- Get the last recorded speed before a given time delta
function PlaybackData:last(fromDelta)
    local latestSpeed = nil
    local latestDelta = nil
    for delta, speed in pairs(self.ash) do
        if fromDelta <= delta then continue end
        if latestDelta and delta <= latestDelta then continue end
        latestSpeed = speed
        latestDelta = delta
    end
    return latestSpeed, latestDelta
end

function PlaybackData:getAvgSpeed()
    local sum = 0
    local count = 0
    for _, speed in pairs(self.ash) do
        sum = sum + speed
        count = count + 1
    end
    return count > 0 and (sum / count) or 1
end

function PlaybackData:getDuration()
    return os.clock() - self.base
end

-- Calculate real-world time to reach a position, accounting for speed changes
function PlaybackData:calculateTimeToPosition(targetPos)
    local currentPos = 0
    local elapsed = 0
    local dt = 0.01
    local maxIter = 10000
    local iter = 0
    while currentPos < targetPos and iter < maxIter do
        local speed = self:last(elapsed) or 1
        currentPos = currentPos + (speed * dt)
        elapsed = elapsed + dt
        iter = iter + 1
    end
    return elapsed
end

-- UI Elements
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AnimationLogger"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Enabled = false
ScreenGui.ResetOnSpawn = false

-- State
local logEntries = {}
local connections = {}
local trackedAnimators = {}
local isLogging = true -- Start logging by default
local filterText = ""
local showNpcsOnly = false
local showPlayersOnly = false
local autoCopy = false
local maxDistance = 100
local distanceSliderFill = nil
local distanceLabel = nil

-- Playback tracking
local activePlaybacks = {} -- track -> PlaybackData
local recordedPlaybacks = {} -- animId -> PlaybackData (completed)

-- Parry detection
local lastEnemyAttack = nil -- { animId, entityName, startTime, track }
local parryTimings = {} -- animId -> { parryTimeMs, count }
local localPlayerAnimator = nil

-- Hitbox visualization
local activeHitboxes = {} -- track -> Part

-- UI References
local outer, inner, scrollFrame, listLayout
local filterTextbox, clearButton, toggleLoggingButton
local npcFilterButton, playerFilterButton, autoCopyButton
local entryCountLabel

-- Animation name cache (try to find real names)
local animationNameCache = {}

-- Clean all connections
local function cleanConnections()
    for _, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    connections = {}
    trackedAnimators = {}
end

-- Format animation ID to be cleaner
local function formatAnimationId(animId)
    local id = tostring(animId)
    id = id:gsub("rbxassetid://", "")
    id = id:gsub("http://www.roblox.com/asset/%?id=", "")
    id = id:gsub("https://www.roblox.com/asset/%?id=", "")
    return id
end

-- Try to get the real animation name from various sources
local function getRealAnimationName(track, animId)
    local formattedId = formatAnimationId(animId)
    
    -- Check cache first
    if animationNameCache[formattedId] then
        return animationNameCache[formattedId]
    end
    
    local name = track.Animation.Name
    
    -- If name is just "Animation" or empty, try to find better name
    if name == "Animation" or name == "" or name:match("^%d+$") then
        -- Try to get from animation instance name in ReplicatedStorage
        pcall(function()
            for _, child in pairs(ReplicatedStorage:GetDescendants()) do
                if child:IsA("Animation") and formatAnimationId(child.AnimationId) == formattedId then
                    if child.Name ~= "Animation" and child.Name ~= "" then
                        name = child.Name
                        break
                    end
                end
            end
        end)
    end
    
    -- Still no good name? Try the track name
    if name == "Animation" or name == "" then
        local trackName = tostring(track):match("Animation (.+)") or ""
        if trackName ~= "" and trackName ~= "Animation" then
            name = trackName
        end
    end
    
    -- Cache it
    animationNameCache[formattedId] = name
    return name
end

-- Check if animation name matches movement patterns (should be filtered)
local function isMovementAnimation(animName)
    if not animName then return false end
    local lowerName = animName:lower()
    for _, pattern in ipairs(MOVEMENT_NAMES) do
        if lowerName:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- Check if animation name matches TRUE parry patterns (successful parry only)
local function isTrueParryAnimation(animName)
    if not animName then return false end
    local lowerName = animName:lower()
    for _, pattern in ipairs(TRUE_PARRY_PATTERNS) do
        if lowerName:find(pattern, 1, true) then
            return true
        end
    end
    return false
end

-- Called when local player plays a TRUE parry animation (successful parry)
local function onLocalParry(parryAnimName)
    if not lastEnemyAttack then return end
    
    local timeSinceAttack = (os.clock() - lastEnemyAttack.startTime) * 1000 -- Convert to ms
    local enemyAnimId = lastEnemyAttack.animId
    local enemyAnimName = lastEnemyAttack.animName or "Unknown"
    
    -- Record this parry timing
    if not parryTimings[enemyAnimId] then
        parryTimings[enemyAnimId] = { timings = {}, avgMs = 0 }
    end
    
    table.insert(parryTimings[enemyAnimId].timings, timeSinceAttack)
    
    -- Calculate average
    local sum = 0
    for _, t in ipairs(parryTimings[enemyAnimId].timings) do
        sum = sum + t
    end
    parryTimings[enemyAnimId].avgMs = sum / #parryTimings[enemyAnimId].timings
    
    -- Update the log entry with the new parry timing and parried status
    for i, entry in ipairs(logEntries) do
        if entry.animId == enemyAnimId then
            entry.parryDetectedMs = math.floor(timeSinceAttack)
            entry.avgParryMs = math.floor(parryTimings[enemyAnimId].avgMs)
            entry.parryCount = #parryTimings[enemyAnimId].timings
            entry.wasParried = true -- Mark as parried
            break
        end
    end
    
    -- Notify with animation name
    if Library and not (shared.dxe and shared.dxe.silent) then
        Library:Notify(string.format("✓ PARRIED: %s's [%s] @ %.0fms (avg: %.0fms x%d)", 
            lastEnemyAttack.entityName, enemyAnimName, timeSinceAttack, 
            parryTimings[enemyAnimId].avgMs, #parryTimings[enemyAnimId].timings), 4)
    end
    
    print(string.format("[AnimLogger] ✓ PARRIED: %s's attack [%s] (ID: %s) at %.0fms", 
        lastEnemyAttack.entityName, enemyAnimName, enemyAnimId, timeSinceAttack))
    
    -- Update display to show parried status
    if ScreenGui.Enabled then
        updateLogDisplay()
    end
end

-- Track local player's animator for parry detection
local function setupLocalPlayerTracking()
    local localPlayer = Players.LocalPlayer
    if not localPlayer then return end
    
    local function onCharacterAdded(character)
        local humanoid = character:WaitForChild("Humanoid", 5)
        if not humanoid then return end
        
        local animator = humanoid:WaitForChild("Animator", 5)
        if not animator then return end
        
        localPlayerAnimator = animator
        
        local conn = animator.AnimationPlayed:Connect(function(track)
            if not isLogging then return end
            if not track or not track.Animation then return end
            
            local animName = track.Animation.Name
            local animId = track.Animation.AnimationId
            
            -- Try to get real name
            pcall(function()
                animName = getRealAnimationName(track, animId)
            end)
            
            -- Check if this is a TRUE parry animation (successful parry)
            if isTrueParryAnimation(animName) then
                onLocalParry(animName)
            end
        end)
        
        table.insert(connections, conn)
    end
    
    if localPlayer.Character then
        task.spawn(function()
            onCharacterAdded(localPlayer.Character)
        end)
    end
    
    local charConn = localPlayer.CharacterAdded:Connect(onCharacterAdded)
    table.insert(connections, charConn)
end

-- Get distance from local player to entity
local function getDistanceToEntity(entity)
    local localPlayer = Players.LocalPlayer
    local character = localPlayer and localPlayer.Character
    if not character then return math.huge end
    
    local localRoot = character:FindFirstChild("HumanoidRootPart")
    if not localRoot then return math.huge end
    
    local entityRoot = entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso") or entity.PrimaryPart
    if not entityRoot then return math.huge end
    
    return (localRoot.Position - entityRoot.Position).Magnitude
end

-- Copy text to clipboard if available
local function copyToClipboard(text)
    if setclipboard then
        setclipboard(text)
        return true
    elseif toclipboard then
        toclipboard(text)
        return true
    end
    return false
end

-- Hitbox visualization functions
local function createHitboxVisualization(entity, color)
    if not (shared.dxe and shared.dxe.showHitboxes) then return nil end
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "AnimLoggerHitbox"
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.CanQuery = false
    hitbox.CanTouch = false
    hitbox.Material = Enum.Material.ForceField
    hitbox.CastShadow = false
    hitbox.Size = DEFAULT_HITBOX_SIZE
    hitbox.Transparency = 0.6
    hitbox.Color = color or Color3.fromRGB(255, 50, 50)
    hitbox.Shape = Enum.PartType.Block
    hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -(DEFAULT_HITBOX_SIZE.Z / 2))
    hitbox.Parent = workspace
    Debris:AddItem(hitbox, MAX_HITBOX_TIME)
    return hitbox
end

local function updateHitboxPosition(hitbox, entity)
    if not hitbox or not hitbox.Parent then return end
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return end
    hitbox.CFrame = root.CFrame * CFrame.new(0, 0, -(DEFAULT_HITBOX_SIZE.Z / 2))
end

local function cleanupHitbox(track)
    local hitbox = activeHitboxes[track]
    if hitbox and hitbox.Parent then hitbox:Destroy() end
    activeHitboxes[track] = nil
end

-- Create a log entry row
local function createLogEntryRow(data)
    local row = Instance.new("Frame")
    row.Name = "LogEntry_" .. data.id
    row.BackgroundColor3 = Library.MainColor
    row.BorderColor3 = BLACK_OUTLINE
    row.BorderMode = Enum.BorderMode.Inset
    row.Size = UDim2.new(1, -4, 0, ROW_HEIGHT)

    -- Entity name
    local entityLabel = Instance.new("TextLabel")
    entityLabel.Name = "Entity"
    entityLabel.FontFace = FONT_FACE
    entityLabel.TextColor3 = data.isPlayer and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 200, 100)
    entityLabel.Text = data.entityName
    entityLabel.BackgroundTransparency = 1
    entityLabel.Position = UDim2.new(0, 4, 0, 0)
    entityLabel.Size = UDim2.new(0, 60, 1, 0)
    entityLabel.TextSize = 11
    entityLabel.TextXAlignment = Enum.TextXAlignment.Left
    entityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    entityLabel.ClipsDescendants = true
    entityLabel.Parent = row

    -- Animation ID
    local idLabel = Instance.new("TextLabel")
    idLabel.Name = "AnimId"
    idLabel.FontFace = FONT_FACE
    idLabel.TextColor3 = Library.AccentColor
    idLabel.Text = data.animId
    idLabel.BackgroundTransparency = 1
    idLabel.Position = UDim2.new(0, 64, 0, 0)
    idLabel.Size = UDim2.new(0, 90, 1, 0)
    idLabel.TextSize = 11
    idLabel.TextXAlignment = Enum.TextXAlignment.Left
    idLabel.TextTruncate = Enum.TextTruncate.AtEnd
    idLabel.ClipsDescendants = true
    idLabel.Parent = row

    -- Animation name (with parried indicator)
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "AnimName"
    nameLabel.FontFace = FONT_FACE
    
    -- If parried, show green with checkmark
    if data.wasParried then
        nameLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green = parried
        nameLabel.Text = "✓ " .. (data.animName or "Unknown")
    else
        nameLabel.TextColor3 = data.isImportant and Color3.fromRGB(255, 200, 100) or Library.FontColor
        nameLabel.Text = data.animName or "Unknown"
    end
    
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 158, 0, 0)
    nameLabel.Size = UDim2.new(0, 100, 1, 0)
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.ClipsDescendants = true
    nameLabel.Parent = row

    -- Distance
    local distLabel = Instance.new("TextLabel")
    distLabel.Name = "Distance"
    distLabel.FontFace = FONT_FACE
    distLabel.TextColor3 = Library.FontColor
    distLabel.Text = string.format("%.0f", data.distance or 0)
    distLabel.BackgroundTransparency = 1
    distLabel.Position = UDim2.new(0, 262, 0, 0)
    distLabel.Size = UDim2.new(0, 30, 1, 0)
    distLabel.TextSize = 11
    distLabel.TextXAlignment = Enum.TextXAlignment.Left
    distLabel.ClipsDescendants = true
    distLabel.Parent = row

    -- Speed
    local speedLabel = Instance.new("TextLabel")
    speedLabel.Name = "Speed"
    speedLabel.FontFace = FONT_FACE
    speedLabel.TextColor3 = data.speed ~= 1 and Color3.fromRGB(255, 180, 100) or Library.FontColor
    speedLabel.Text = string.format("%.2f", data.speed or 1)
    speedLabel.BackgroundTransparency = 1
    speedLabel.Position = UDim2.new(0, 296, 0, 0)
    speedLabel.Size = UDim2.new(0, 35, 1, 0)
    speedLabel.TextSize = 11
    speedLabel.TextXAlignment = Enum.TextXAlignment.Left
    speedLabel.ClipsDescendants = true
    speedLabel.Parent = row

    -- Length (duration)
    local lengthLabel = Instance.new("TextLabel")
    lengthLabel.Name = "Length"
    lengthLabel.FontFace = FONT_FACE
    lengthLabel.TextColor3 = Library.FontColor
    lengthLabel.Text = string.format("%.2f", data.length or 0)
    lengthLabel.BackgroundTransparency = 1
    lengthLabel.Position = UDim2.new(0, 335, 0, 0)
    lengthLabel.Size = UDim2.new(0, 32, 1, 0)
    lengthLabel.TextSize = 11
    lengthLabel.TextXAlignment = Enum.TextXAlignment.Left
    lengthLabel.ClipsDescendants = true
    lengthLabel.Parent = row

    -- Parry Time (suggested timing in ms) - shows detected timing if available
    local parryLabel = Instance.new("TextLabel")
    parryLabel.Name = "ParryTime"
    parryLabel.FontFace = FONT_FACE
    
    -- If we have detected parry timing, show it in green, otherwise show suggested in yellow
    if data.avgParryMs and data.parryCount and data.parryCount > 0 then
        parryLabel.TextColor3 = Color3.fromRGB(100, 255, 100) -- Green = confirmed timing
        parryLabel.Text = string.format("%dms(%d)", data.avgParryMs, data.parryCount)
    elseif data.suggestedParryMs then
        parryLabel.TextColor3 = Color3.fromRGB(255, 255, 100) -- Yellow = suggested
        parryLabel.Text = string.format("%dms", data.suggestedParryMs)
    else
        parryLabel.TextColor3 = Color3.fromRGB(255, 255, 100)
        parryLabel.Text = "---"
    end
    
    parryLabel.BackgroundTransparency = 1
    parryLabel.Position = UDim2.new(0, 370, 0, 0)
    parryLabel.Size = UDim2.new(0, 42, 1, 0)
    parryLabel.TextSize = 11
    parryLabel.TextXAlignment = Enum.TextXAlignment.Left
    parryLabel.ClipsDescendants = true
    parryLabel.Parent = row

    -- Priority
    local priorityLabel = Instance.new("TextLabel")
    priorityLabel.Name = "Priority"
    priorityLabel.FontFace = FONT_FACE
    priorityLabel.TextColor3 = Library.FontColor
    priorityLabel.Text = data.priority:sub(1, 4)
    priorityLabel.BackgroundTransparency = 1
    priorityLabel.Position = UDim2.new(0, 414, 0, 0)
    priorityLabel.Size = UDim2.new(0, 32, 1, 0)
    priorityLabel.TextSize = 11
    priorityLabel.TextXAlignment = Enum.TextXAlignment.Left
    priorityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    priorityLabel.ClipsDescendants = true
    priorityLabel.Parent = row

    -- Export button (exports timing data)
    local exportBtn = Instance.new("TextButton")
    exportBtn.Name = "ExportBtn"
    exportBtn.FontFace = FONT_FACE
    exportBtn.TextColor3 = Library.FontColor
    exportBtn.Text = "Exp"
    exportBtn.BackgroundColor3 = Library.MainColor
    exportBtn.BorderColor3 = BLACK_OUTLINE
    exportBtn.Position = UDim2.new(1, -88, 0, 2)
    exportBtn.Size = UDim2.new(0, 28, 0, ROW_HEIGHT - 4)
    exportBtn.TextSize = 9
    exportBtn.Parent = row

    -- Copy button
    local copyBtn = Instance.new("TextButton")
    copyBtn.Name = "CopyBtn"
    copyBtn.FontFace = FONT_FACE
    copyBtn.TextColor3 = Library.FontColor
    copyBtn.Text = "Copy"
    copyBtn.BackgroundColor3 = Library.MainColor
    copyBtn.BorderColor3 = BLACK_OUTLINE
    copyBtn.Position = UDim2.new(1, -58, 0, 2)
    copyBtn.Size = UDim2.new(0, 38, 0, ROW_HEIGHT - 4)
    copyBtn.TextSize = 10
    copyBtn.Parent = row

    -- Preview button (sends to AnimationVisualizer)
    local previewBtn = Instance.new("TextButton")
    previewBtn.Name = "PreviewBtn"
    previewBtn.FontFace = FONT_FACE
    previewBtn.TextColor3 = Library.FontColor
    previewBtn.Text = "▶"
    previewBtn.BackgroundColor3 = Library.MainColor
    previewBtn.BorderColor3 = BLACK_OUTLINE
    previewBtn.Position = UDim2.new(1, -18, 0, 2)
    previewBtn.Size = UDim2.new(0, 14, 0, ROW_HEIGHT - 4)
    previewBtn.TextSize = 10
    previewBtn.Parent = row

    -- Register colors (but NOT border - keep it black)
    Library:AddToRegistry(row, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(idLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(distLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(speedLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(lengthLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(priorityLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(copyBtn, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(exportBtn, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(previewBtn, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)

    -- Copy button click
    copyBtn.MouseButton1Click:Connect(function()
        local fullId = "rbxassetid://" .. data.animId
        if copyToClipboard(fullId) then
            copyBtn.Text = "✓"
            task.delay(1, function()
                if copyBtn and copyBtn.Parent then
                    copyBtn.Text = "Copy"
                end
            end)
        end
    end)

    -- Export button click (exports timing data)
    exportBtn.MouseButton1Click:Connect(function()
        local exportStr = string.format(
            '{\n  animId = "rbxassetid://%s",\n  name = "%s",\n  length = %.3f,\n  speed = %.2f,\n  suggestedParryMs = %d,\n  priority = "%s"\n}',
            data.animId,
            data.animName or "Unknown",
            data.length or 0,
            data.speed or 1,
            data.suggestedParryMs or 0,
            data.priority or "Unknown"
        )
        if copyToClipboard(exportStr) then
            exportBtn.Text = "✓"
            task.delay(1, function()
                if exportBtn and exportBtn.Parent then
                    exportBtn.Text = "Exp"
                end
            end)
        end
    end)

    -- Preview button click (send to AnimationVisualizer)
    previewBtn.MouseButton1Click:Connect(function()
        if AnimationVisualizer then
            local fullId = "rbxassetid://" .. data.animId
            AnimationVisualizer.visible(true)
            -- Find the textbox and set its text
            if Library.AnimationVisualizerFrame then
                local vizInner = Library.AnimationVisualizerFrame:FindFirstChild("Inner")
                if vizInner then
                    local textbox = vizInner:FindFirstChild("AnimationTextbox")
                    if textbox then
                        textbox.Text = fullId
                        -- Simulate focus lost with enter
                        textbox:ReleaseFocus(true)
                    end
                end
            end
        end
    end)

    return row
end

-- Update the scroll frame with filtered entries
local function updateLogDisplay()
    -- Clear existing entries
    for _, child in pairs(scrollFrame:GetChildren()) do
        if child:IsA("Frame") and child.Name:match("^LogEntry_") then
            child:Destroy()
        end
    end

    local filteredEntries = {}
    local lowerFilter = filterText:lower()

    for _, entry in ipairs(logEntries) do
        local matchesFilter = filterText == "" or 
            entry.entityName:lower():find(lowerFilter) or
            entry.animId:find(lowerFilter) or
            (entry.animName and entry.animName:lower():find(lowerFilter))

        local matchesNpcFilter = not showNpcsOnly or not entry.isPlayer
        local matchesPlayerFilter = not showPlayersOnly or entry.isPlayer

        if matchesFilter and matchesNpcFilter and matchesPlayerFilter then
            table.insert(filteredEntries, entry)
        end
    end

    -- Create rows for filtered entries (newest first)
    for i = #filteredEntries, 1, -1 do
        local row = createLogEntryRow(filteredEntries[i])
        row.Parent = scrollFrame
    end

    -- Update entry count
    entryCountLabel.Text = string.format("%d/%d", #filteredEntries, #logEntries)
end

-- Add a new log entry
local function addLogEntry(entityName, animId, animName, priority, isPlayer, distance, isImportant, speed, length, suggestedParryMs)
    local formattedId = formatAnimationId(animId)

    local entry = {
        id = #logEntries + 1,
        entityName = entityName,
        animId = formattedId,
        animName = animName,
        priority = priority,
        isPlayer = isPlayer,
        distance = distance,
        isImportant = isImportant,
        speed = speed or 1,
        length = length or 0,
        suggestedParryMs = suggestedParryMs,
        timestamp = os.clock()
    }

    table.insert(logEntries, entry)

    -- Trim old entries if we exceed max
    while #logEntries > MAX_LOG_ENTRIES do
        table.remove(logEntries, 1)
    end

    -- Auto copy if enabled
    if autoCopy then
        copyToClipboard("rbxassetid://" .. formattedId)
    end

    -- Update display if visible
    if ScreenGui.Enabled then
        updateLogDisplay()
    end
end

-- Handle animation played event
local function onAnimationPlayed(animator, track)
    if not isLogging then return end
    if not track or not track.Animation then return end

    local entity = animator:FindFirstAncestorWhichIsA("Model")
    if not entity then return end
    
    -- Skip local player's animations
    local localPlayer = Players.LocalPlayer
    if localPlayer and localPlayer.Character == entity then return end

    local entityName = entity.Name
    
    -- Check if NPC or Player using ModelCollisionGroup attribute (game-specific)
    local collisionGroup = entity:GetAttribute("ModelCollisionGroup")
    local isPlayer = collisionGroup == "Player" or Players:GetPlayerFromCharacter(entity) ~= nil
    local isNpc = collisionGroup == "NPC"
    
    -- Distance check
    local distance = getDistanceToEntity(entity)
    if distance > maxDistance then return end

    -- Apply filters early for performance
    if showNpcsOnly and not isNpc then return end
    if showPlayersOnly and not isPlayer then return end

    local animId = track.Animation.AnimationId
    local animName = getRealAnimationName(track, animId)
    local priority = track.Priority.Name
    
    -- =========================================================================
    -- STRICT FILTERING: Only Action priority (combat) animations
    -- =========================================================================
    local isActionPriority = priority == "Action" or priority == "Action2" or priority == "Action3" or priority == "Action4"
    
    -- Skip anything that isn't Action priority
    if not isActionPriority then
        return
    end
    
    -- Skip movement animations by name (even if Action priority)
    if isMovementAnimation(animName) then
        return
    end
    
    -- Skip low weight (blend/transition)
    if track.WeightTarget <= 0.05 then
        return
    end
    
    local isImportant = true -- All Action priority are important

    -- Start tracking playback data (Lycoris-style ash)
    local pbdata = PlaybackData.new(track, entity)
    activePlaybacks[track] = pbdata
    
    -- Record initial speed
    pbdata:astrack(track.Speed)
    
    -- Create hitbox visualization if enabled
    local hitbox = createHitboxVisualization(entity, Color3.fromRGB(255, 50, 50))
    if hitbox then
        activeHitboxes[track] = hitbox
    end
    
    -- Track when animation ends
    local conn
    conn = track.Stopped:Connect(function()
        if conn then conn:Disconnect() end
        
        -- Move to recorded playbacks
        local formattedId = formatAnimationId(animId)
        recordedPlaybacks[formattedId] = pbdata
        activePlaybacks[track] = nil
        
        -- Cleanup hitbox
        cleanupHitbox(track)
    end)
    
    -- Get speed and length
    local speed = track.Speed
    local length = track.Length
    
    -- Calculate suggested parry timing
    -- Most attacks hit around 40-60% of animation, suggest 50% adjusted for speed
    local suggestedParryMs = math.floor((length * 0.5 / speed) * 1000)
    
    local formattedId = formatAnimationId(animId)
    
    -- Track this as the last enemy attack for parry detection correlation
    lastEnemyAttack = {
        animId = formattedId,
        animName = animName,
        entityName = entityName,
        startTime = os.clock(),
        track = track,
        length = length,
        speed = speed,
    }

    addLogEntry(entityName, animId, animName, priority, isPlayer, distance, isImportant, speed, length, suggestedParryMs)
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

-- Start logging
local function startLogging()
    isLogging = true
    toggleLoggingButton.Text = "Stop Logging"
    toggleLoggingButton.TextColor3 = Color3.fromRGB(255, 100, 100)
    
    -- Setup local player parry detection
    setupLocalPlayerTracking()

    -- Scan workspace for existing animators
    scanForAnimators(workspace)
    
    -- Also scan Live folder specifically (Deepwoken spawns characters here)
    local live = workspace:FindFirstChild("Live")
    if live then
        scanForAnimators(live)
    end

    -- Watch for new animators in workspace
    local descendantConn = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end)
    table.insert(connections, descendantConn)
    
    -- Watch for new descendants in Live folder specifically
    if live then
        local liveConn = live.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Animator") then
                trackAnimator(descendant)
            end
        end)
        table.insert(connections, liveConn)
    end
    
    -- Update loop for playback tracking and hitbox positions
    local updateConn = RunService.RenderStepped:Connect(function()
        for track, pbdata in pairs(activePlaybacks) do
            if not track.IsPlaying then
                -- Clean up finished tracks
                local formattedId = formatAnimationId(track.Animation.AnimationId)
                recordedPlaybacks[formattedId] = pbdata
                activePlaybacks[track] = nil
                cleanupHitbox(track)
            else
                -- Track speed changes (Lycoris-style ash)
                pbdata:astrack(track.Speed)
                
                -- Update hitbox position and color based on progress
                local hitbox = activeHitboxes[track]
                if hitbox and hitbox.Parent and pbdata.entity then
                    updateHitboxPosition(hitbox, pbdata.entity)
                    
                    -- Color based on animation progress (parry window detection)
                    local progress = track.TimePosition / track.Length
                    if progress >= 0.35 and progress <= 0.65 then
                        -- Danger zone (likely parry window) - Yellow
                        hitbox.Color = Color3.fromRGB(255, 255, 0)
                    elseif progress > 0.65 then
                        -- Past danger zone - Green
                        hitbox.Color = Color3.fromRGB(100, 255, 100)
                    else
                        -- Before danger zone - Red
                        hitbox.Color = Color3.fromRGB(255, 50, 50)
                    end
                end
            end
        end
    end)
    table.insert(connections, updateConn)
end

-- Stop logging
local function stopLogging()
    isLogging = false
    toggleLoggingButton.Text = "Start Logging"
    toggleLoggingButton.TextColor3 = Library.FontColor

    -- Cleanup hitboxes
    for track, _ in pairs(activeHitboxes) do
        cleanupHitbox(track)
    end

    -- Disconnect animator connections but keep UI connections
    for animator, conn in pairs(trackedAnimators) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    trackedAnimators = {}
end

-- Toggle logging state
local function toggleLogging()
    if isLogging then
        stopLogging()
    else
        startLogging()
    end
end

-- Clear all logs
local function clearLogs()
    logEntries = {}
    updateLogDisplay()
end

-- Toggle NPC filter
local function toggleNpcFilter()
    showNpcsOnly = not showNpcsOnly
    if showNpcsOnly then
        showPlayersOnly = false
        playerFilterButton.TextColor3 = Library.FontColor
    end
    npcFilterButton.TextColor3 = showNpcsOnly and Library.AccentColor or Library.FontColor
    updateLogDisplay()
end

-- Toggle player filter
local function togglePlayerFilter()
    showPlayersOnly = not showPlayersOnly
    if showPlayersOnly then
        showNpcsOnly = false
        npcFilterButton.TextColor3 = Library.FontColor
    end
    playerFilterButton.TextColor3 = showPlayersOnly and Library.AccentColor or Library.FontColor
    updateLogDisplay()
end

-- Toggle auto copy
local function toggleAutoCopy()
    autoCopy = not autoCopy
    autoCopyButton.TextColor3 = autoCopy and Library.AccentColor or Library.FontColor
end

-- Update distance slider
local function updateDistanceSlider(value)
    maxDistance = value
    local percentage = (value - 10) / (500 - 10)
    distanceSliderFill.Size = UDim2.new(percentage, 0, 1, 0)
    distanceLabel.Text = string.format("Range: %d", value)
end

-- Set visibility
function AnimationLogger.visible(state)
    ScreenGui.Enabled = state
    if state then
        updateLogDisplay()
    end
end

-- Initialize the module
function AnimationLogger.init(lib, animVis)
    Library = lib
    AnimationVisualizer = animVis

    -- Parent ScreenGui
    ScreenGui.Parent = Library.ScreenGui.Parent

    -- Create outer frame
    outer = Instance.new("Frame")
    outer.Name = "Outer"
    outer.BackgroundColor3 = Color3.new(1, 1, 1)
    outer.Position = UDim2.new(0.5, 0, 0.15, 0)
    outer.BorderColor3 = BLACK_OUTLINE
    outer.Size = UDim2.new(0, WINDOW_WIDTH, 0, WINDOW_HEIGHT)
    outer.ZIndex = 100
    outer.Parent = ScreenGui

    -- Create inner frame
    inner = Instance.new("Frame")
    inner.Name = "Inner"
    inner.BackgroundColor3 = Library.MainColor
    inner.BorderMode = Enum.BorderMode.Inset
    inner.BorderColor3 = BLACK_OUTLINE
    inner.Size = UDim2.new(1, 0, 1, 0)
    inner.Parent = outer

    -- Title
    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.FontFace = FONT_FACE
    titleLabel.TextColor3 = Library.AccentColor
    titleLabel.Text = "Animation Logger (Combat)"
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 5, 0, 5)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextSize = 17
    titleLabel.Size = UDim2.new(0, 200, 0, 20)
    titleLabel.Parent = inner

    -- Entry count
    entryCountLabel = Instance.new("TextLabel")
    entryCountLabel.Name = "EntryCount"
    entryCountLabel.FontFace = FONT_FACE
    entryCountLabel.TextColor3 = Library.FontColor
    entryCountLabel.Text = "0/0"
    entryCountLabel.BackgroundTransparency = 1
    entryCountLabel.Position = UDim2.new(1, -60, 0, 5)
    entryCountLabel.TextXAlignment = Enum.TextXAlignment.Right
    entryCountLabel.TextSize = 12
    entryCountLabel.Size = UDim2.new(0, 55, 0, 20)
    entryCountLabel.Parent = inner

    -- Accent bar
    local color = Instance.new("Frame")
    color.Name = "Color"
    color.BackgroundColor3 = Library.AccentColor
    color.BorderSizePixel = 0
    color.Size = UDim2.new(1, 0, 0, 2)
    color.Parent = inner

    -- Header row (column labels)
    local headerRow = Instance.new("Frame")
    headerRow.Name = "HeaderRow"
    headerRow.BackgroundColor3 = Library.MainColor
    headerRow.BorderColor3 = BLACK_OUTLINE
    headerRow.BorderMode = Enum.BorderMode.Inset
    headerRow.Position = UDim2.new(0, 4, 0, HEADER_HEIGHT)
    headerRow.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
    headerRow.Parent = inner

    local headers = {
        { name = "Entity", pos = 4, width = 60 },
        { name = "Anim ID", pos = 64, width = 90 },
        { name = "Name", pos = 158, width = 100 },
        { name = "Dist", pos = 262, width = 30 },
        { name = "Spd", pos = 296, width = 35 },
        { name = "Len", pos = 335, width = 32 },
        { name = "Parry", pos = 370, width = 42 },
        { name = "Prio", pos = 414, width = 32 },
    }

    for _, header in ipairs(headers) do
        local label = Instance.new("TextLabel")
        label.Name = header.name
        label.FontFace = FONT_FACE
        label.TextColor3 = Library.AccentColor
        label.Text = header.name
        label.BackgroundTransparency = 1
        label.Position = UDim2.new(0, header.pos, 0, 0)
        label.Size = UDim2.new(0, header.width, 1, 0)
        label.TextSize = 11
        label.TextXAlignment = Enum.TextXAlignment.Left
        label.Parent = headerRow
        Library:AddToRegistry(label, { TextColor3 = "AccentColor" }, true)
    end

    -- Scroll frame for log entries
    scrollFrame = Instance.new("ScrollingFrame")
    scrollFrame.Name = "ScrollFrame"
    scrollFrame.BackgroundColor3 = Library.MainColor
    scrollFrame.BorderColor3 = BLACK_OUTLINE
    scrollFrame.BorderMode = Enum.BorderMode.Inset
    scrollFrame.Position = UDim2.new(0, 4, 0, HEADER_HEIGHT + ROW_HEIGHT + 4)
    scrollFrame.Size = UDim2.new(1, -8, 1, -(HEADER_HEIGHT + ROW_HEIGHT + 4 + 100))
    scrollFrame.ScrollBarThickness = 4
    scrollFrame.ScrollBarImageColor3 = Library.AccentColor
    scrollFrame.CanvasSize = UDim2.new(0, 0, 0, 0)
    scrollFrame.AutomaticCanvasSize = Enum.AutomaticSize.Y
    scrollFrame.Parent = inner

    listLayout = Instance.new("UIListLayout")
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Padding = UDim.new(0, 2)
    listLayout.Parent = scrollFrame

    -- Control bar
    local controlBar = Instance.new("Frame")
    controlBar.Name = "ControlBar"
    controlBar.BackgroundTransparency = 1
    controlBar.Position = UDim2.new(0, 4, 1, -94)
    controlBar.Size = UDim2.new(1, -8, 0, 90)
    controlBar.Parent = inner

    -- Row 1: Filter, Start/Stop, Clear
    filterTextbox = Instance.new("TextBox")
    filterTextbox.Name = "FilterTextbox"
    filterTextbox.FontFace = FONT_FACE
    filterTextbox.TextColor3 = Library.FontColor
    filterTextbox.PlaceholderText = "Filter..."
    filterTextbox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    filterTextbox.Text = ""
    filterTextbox.BackgroundColor3 = Library.MainColor
    filterTextbox.BorderColor3 = BLACK_OUTLINE
    filterTextbox.Position = UDim2.new(0, 0, 0, 0)
    filterTextbox.Size = UDim2.new(0, 140, 0, 20)
    filterTextbox.TextSize = 12
    filterTextbox.ClearTextOnFocus = false
    filterTextbox.Parent = controlBar

    toggleLoggingButton = Instance.new("TextButton")
    toggleLoggingButton.Name = "ToggleLogging"
    toggleLoggingButton.FontFace = FONT_FACE
    toggleLoggingButton.TextColor3 = Library.FontColor
    toggleLoggingButton.Text = "Start Logging"
    toggleLoggingButton.BackgroundColor3 = Library.MainColor
    toggleLoggingButton.BorderColor3 = BLACK_OUTLINE
    toggleLoggingButton.Position = UDim2.new(0, 144, 0, 0)
    toggleLoggingButton.Size = UDim2.new(0, 90, 0, 20)
    toggleLoggingButton.TextSize = 12
    toggleLoggingButton.Parent = controlBar

    clearButton = Instance.new("TextButton")
    clearButton.Name = "ClearLogs"
    clearButton.FontFace = FONT_FACE
    clearButton.TextColor3 = Library.FontColor
    clearButton.Text = "Clear"
    clearButton.BackgroundColor3 = Library.MainColor
    clearButton.BorderColor3 = BLACK_OUTLINE
    clearButton.Position = UDim2.new(0, 238, 0, 0)
    clearButton.Size = UDim2.new(0, 50, 0, 20)
    clearButton.TextSize = 12
    clearButton.Parent = controlBar

    -- Row 2: NPCs, Players, Combat Only, Auto Copy
    npcFilterButton = Instance.new("TextButton")
    npcFilterButton.Name = "NpcFilter"
    npcFilterButton.FontFace = FONT_FACE
    npcFilterButton.TextColor3 = Library.FontColor
    npcFilterButton.Text = "NPCs"
    npcFilterButton.BackgroundColor3 = Library.MainColor
    npcFilterButton.BorderColor3 = BLACK_OUTLINE
    npcFilterButton.Position = UDim2.new(0, 0, 0, 26)
    npcFilterButton.Size = UDim2.new(0, 50, 0, 20)
    npcFilterButton.TextSize = 12
    npcFilterButton.Parent = controlBar

    playerFilterButton = Instance.new("TextButton")
    playerFilterButton.Name = "PlayerFilter"
    playerFilterButton.FontFace = FONT_FACE
    playerFilterButton.TextColor3 = Library.FontColor
    playerFilterButton.Text = "Players"
    playerFilterButton.BackgroundColor3 = Library.MainColor
    playerFilterButton.BorderColor3 = BLACK_OUTLINE
    playerFilterButton.Position = UDim2.new(0, 54, 0, 26)
    playerFilterButton.Size = UDim2.new(0, 55, 0, 20)
    playerFilterButton.TextSize = 12
    playerFilterButton.Parent = controlBar

    autoCopyButton = Instance.new("TextButton")
    autoCopyButton.Name = "AutoCopy"
    autoCopyButton.FontFace = FONT_FACE
    autoCopyButton.TextColor3 = Library.FontColor
    autoCopyButton.Text = "Auto Copy"
    autoCopyButton.BackgroundColor3 = Library.MainColor
    autoCopyButton.BorderColor3 = BLACK_OUTLINE
    autoCopyButton.Position = UDim2.new(0, 113, 0, 26)
    autoCopyButton.Size = UDim2.new(0, 70, 0, 20)
    autoCopyButton.TextSize = 12
    autoCopyButton.Parent = controlBar

    -- Row 3: Distance slider
    distanceLabel = Instance.new("TextLabel")
    distanceLabel.Name = "DistanceLabel"
    distanceLabel.FontFace = FONT_FACE
    distanceLabel.TextColor3 = Library.FontColor
    distanceLabel.Text = "Range: 100"
    distanceLabel.BackgroundTransparency = 1
    distanceLabel.Position = UDim2.new(0, 0, 0, 52)
    distanceLabel.TextXAlignment = Enum.TextXAlignment.Left
    distanceLabel.TextSize = 12
    distanceLabel.Size = UDim2.new(0, 80, 0, 20)
    distanceLabel.Parent = controlBar

    local distanceSliderOuter = Instance.new("Frame")
    distanceSliderOuter.Name = "DistanceSliderOuter"
    distanceSliderOuter.BackgroundColor3 = Color3.new(1, 1, 1)
    distanceSliderOuter.Position = UDim2.new(0, 84, 0, 52)
    distanceSliderOuter.BorderColor3 = BLACK_OUTLINE
    distanceSliderOuter.BorderSizePixel = 0
    distanceSliderOuter.Size = UDim2.new(0, 200, 0, 18)
    distanceSliderOuter.Parent = controlBar

    local distanceSliderInner = Instance.new("Frame")
    distanceSliderInner.Name = "SliderInner"
    distanceSliderInner.BorderColor3 = BLACK_OUTLINE
    distanceSliderInner.BackgroundColor3 = Library.MainColor
    distanceSliderInner.Size = UDim2.new(1, 0, 1, 0)
    distanceSliderInner.Parent = distanceSliderOuter

    distanceSliderFill = Instance.new("Frame")
    distanceSliderFill.Name = "SliderFill"
    distanceSliderFill.BorderMode = Enum.BorderMode.Inset
    distanceSliderFill.BorderColor3 = Library.AccentColorDark
    distanceSliderFill.BackgroundColor3 = Library.AccentColor
    distanceSliderFill.Size = UDim2.new((100 - 10) / (500 - 10), 0, 1, 0)
    distanceSliderFill.ZIndex = 10
    distanceSliderFill.Parent = distanceSliderOuter

    -- Distance slider interaction
    local draggingSlider = false
    distanceSliderOuter.InputBegan:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = true
        end
    end)

    distanceSliderOuter.InputEnded:Connect(function(input)
        if input.UserInputType == Enum.UserInputType.MouseButton1 then
            draggingSlider = false
        end
    end)

    RunService.RenderStepped:Connect(function()
        if draggingSlider and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) then
            local mouse = Players.LocalPlayer:GetMouse()
            local sliderSize = distanceSliderOuter.AbsoluteSize.X
            local mouseX = math.clamp(mouse.X - distanceSliderOuter.AbsolutePosition.X, 0, sliderSize)
            local percentage = mouseX / sliderSize
            local value = math.floor(10 + (percentage * (500 - 10)))
            updateDistanceSlider(value)
        end
    end)

    -- Make draggable
    Library:MakeDraggable(outer)

    -- Register colors (keep borders black)
    Library:AddToRegistry(color, { BackgroundColor3 = "AccentColor" }, true)
    Library:AddToRegistry(titleLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(entryCountLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(headerRow, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(scrollFrame, { BackgroundColor3 = "MainColor", ScrollBarImageColor3 = "AccentColor" }, true)
    Library:AddToRegistry(filterTextbox, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(toggleLoggingButton, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(clearButton, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(npcFilterButton, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(playerFilterButton, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(autoCopyButton, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(distanceLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(distanceSliderInner, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(distanceSliderFill, { BackgroundColor3 = "AccentColor", BorderColor3 = "AccentColorDark" }, true)

    -- Connect events
    filterTextbox:GetPropertyChangedSignal("Text"):Connect(function()
        filterText = filterTextbox.Text
        updateLogDisplay()
    end)

    toggleLoggingButton.MouseButton1Click:Connect(toggleLogging)
    clearButton.MouseButton1Click:Connect(clearLogs)
    npcFilterButton.MouseButton1Click:Connect(toggleNpcFilter)
    playerFilterButton.MouseButton1Click:Connect(togglePlayerFilter)
    autoCopyButton.MouseButton1Click:Connect(toggleAutoCopy)

    -- Store reference in Library
    Library.AnimationLoggerFrame = outer
    
    -- Auto-start logging (on by default)
    task.defer(function()
        startLogging()
    end)
end

-- Clean up
function AnimationLogger.detach()
    stopLogging()
    cleanConnections()
    activePlaybacks = {}
    recordedPlaybacks = {}
    
    -- Cleanup all hitboxes
    for track, _ in pairs(activeHitboxes) do
        cleanupHitbox(track)
    end
    
    if ScreenGui then
        ScreenGui:Destroy()
    end
end

-- Get playback data for an animation ID
function AnimationLogger.getPlaybackData(animId)
    local formattedId = formatAnimationId(animId)
    return recordedPlaybacks[formattedId]
end

-- Get all recorded playback data
function AnimationLogger.getAllPlaybackData()
    return recordedPlaybacks
end

-- Get all logged entries
function AnimationLogger.getLogEntries()
    return logEntries
end

-- Export timing data for an animation (useful for creating timing configs)
function AnimationLogger.exportTimingData(animId)
    local formattedId = formatAnimationId(animId)
    local pbdata = recordedPlaybacks[formattedId]
    local parryData = parryTimings[formattedId]
    
    -- Find the log entry for this animation
    local entry = nil
    for _, e in ipairs(logEntries) do
        if e.animId == formattedId then
            entry = e
            break
        end
    end
    
    if not entry then return nil end
    
    local avgSpeed = pbdata and pbdata:getAvgSpeed() or entry.speed
    local suggestedParryMs = entry.suggestedParryMs or math.floor((entry.length * 0.5 / avgSpeed) * 1000)
    
    -- Use detected parry timing if available
    local detectedParryMs = parryData and parryData.avgMs or nil
    local parryCount = parryData and #parryData.timings or 0
    
    return {
        -- Animation info
        animId = "rbxassetid://" .. formattedId,
        name = entry.animName,
        priority = entry.priority,
        
        -- Timing info for defender configs
        length = entry.length,
        speed = entry.speed,
        avgSpeed = avgSpeed,
        duration = pbdata and pbdata:getDuration() or entry.length,
        suggestedParryMs = suggestedParryMs,
        
        -- Detected parry timing (from actual gameplay)
        detectedParryMs = detectedParryMs,
        parryCount = parryCount,
        
        -- Speed history (if available)
        speedHistory = pbdata and pbdata.ash or {},
        
        -- Entity info
        entityName = entry.entityName,
        isPlayer = entry.isPlayer,
        isImportant = entry.isImportant,
    }
end

-- Get all detected parry timings
function AnimationLogger.getParryTimings()
    return parryTimings
end

-- Return module
return AnimationLogger
