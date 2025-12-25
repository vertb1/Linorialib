-- Animation Logger Module (Standalone)
-- Logs animation IDs, names, priorities, and speeds from entities in the game.
-- Based on Lycoris-Rewrite animation handling patterns
local AnimationLogger = {}

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local MAX_LOG_ENTRIES = 100
local FONT_FACE = Font.new("rbxasset://fonts/families/RobotoMono.json")
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 26
local WINDOW_WIDTH = 520
local WINDOW_HEIGHT = 450
local BLACK_OUTLINE = Color3.new(0, 0, 0)

-- Animation name patterns to ignore (movement animations)
local IGNORED_PATTERNS = {
    "run", "walk", "sprint", "dash", "dodge", "roll", "jump", "fall", "land", "idle", 
    "climb", "swim", "crawl", "crouch", "slide", "vault", "mantle", "locomotion",
    "breathing", "emote", "pose", "stance", "standing", "sitting", "laying"
}

-- Important animation patterns (combat)
local IMPORTANT_PATTERNS = {
    "sword", "fist", "punch", "kick", "slash", "cut", "swing", "stab", "thrust",
    "heavy", "light", "combo", "attack", "hit", "strike", "parry", "block", "guard",
    "critical", "crit", "uppercut", "haymaker", "jab", "hook", "mantrastyle",
    "rapier", "spear", "axe", "hammer", "dagger", "greatsword", "katana", "gun",
    "bow", "staff", "wand", "gauntlet", "claw", "whip", "scythe", "halberd",
    "m1", "m2", "ability", "skill", "spell", "mantra", "feint", "grab", "throw"
}

-- Will be set when init is called
local Library = nil
local AnimationVisualizer = nil

-- Track playback data (like Lycoris PlaybackData)
local PlaybackData = {}
PlaybackData.__index = PlaybackData

function PlaybackData.new(track, entity)
    local self = setmetatable({}, PlaybackData)
    self.track = track
    self.entity = entity
    self.startTime = os.clock()
    self.speeds = {}
    self.timePositions = {}
    self.lastUpdate = os.clock()
    return self
end

function PlaybackData:update()
    if not self.track or not self.track.IsPlaying then return end
    local now = os.clock()
    table.insert(self.speeds, self.track.Speed)
    table.insert(self.timePositions, self.track.TimePosition)
    self.lastUpdate = now
end

function PlaybackData:getAvgSpeed()
    if #self.speeds == 0 then return 1 end
    local sum = 0
    for _, s in ipairs(self.speeds) do sum = sum + s end
    return sum / #self.speeds
end

function PlaybackData:getDuration()
    return os.clock() - self.startTime
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
local isLogging = false
local filterText = ""
local showNpcsOnly = false
local showPlayersOnly = false
local autoCopy = false
local combatOnly = false
local maxDistance = 100
local distanceSliderFill = nil
local distanceLabel = nil
local combatOnlyButton = nil

-- Playback tracking (like Lycoris)
local activePlaybacks = {} -- track -> PlaybackData
local recordedPlaybacks = {} -- animId -> PlaybackData (completed)

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

-- Check if animation name matches ignored patterns
local function isIgnoredAnimation(animName)
    local lowerName = animName:lower()
    for _, pattern in ipairs(IGNORED_PATTERNS) do
        if lowerName:find(pattern) then
            return true
        end
    end
    return false
end

-- Check if animation name matches important/combat patterns
local function isImportantAnimation(animName)
    local lowerName = animName:lower()
    for _, pattern in ipairs(IMPORTANT_PATTERNS) do
        if lowerName:find(pattern) then
            return true
        end
    end
    -- Also check priority - Action and above are usually important
    return false
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

    -- Animation name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "AnimName"
    nameLabel.FontFace = FONT_FACE
    nameLabel.TextColor3 = data.isImportant and Color3.fromRGB(100, 255, 100) or Library.FontColor
    nameLabel.Text = data.animName or "Unknown"
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
    lengthLabel.Size = UDim2.new(0, 35, 1, 0)
    lengthLabel.TextSize = 11
    lengthLabel.TextXAlignment = Enum.TextXAlignment.Left
    lengthLabel.ClipsDescendants = true
    lengthLabel.Parent = row

    -- Priority
    local priorityLabel = Instance.new("TextLabel")
    priorityLabel.Name = "Priority"
    priorityLabel.FontFace = FONT_FACE
    priorityLabel.TextColor3 = Library.FontColor
    priorityLabel.Text = data.priority:sub(1, 4)
    priorityLabel.BackgroundTransparency = 1
    priorityLabel.Position = UDim2.new(0, 374, 0, 0)
    priorityLabel.Size = UDim2.new(0, 35, 1, 0)
    priorityLabel.TextSize = 11
    priorityLabel.TextXAlignment = Enum.TextXAlignment.Left
    priorityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    priorityLabel.ClipsDescendants = true
    priorityLabel.Parent = row

    -- Copy button
    local copyBtn = Instance.new("TextButton")
    copyBtn.Name = "CopyBtn"
    copyBtn.FontFace = FONT_FACE
    copyBtn.TextColor3 = Library.FontColor
    copyBtn.Text = "Copy"
    copyBtn.BackgroundColor3 = Library.MainColor
    copyBtn.BorderColor3 = BLACK_OUTLINE
    copyBtn.Position = UDim2.new(1, -42, 0, 2)
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
    previewBtn.Position = UDim2.new(1, -62, 0, 2)
    previewBtn.Size = UDim2.new(0, 18, 0, ROW_HEIGHT - 4)
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
local function addLogEntry(entityName, animId, animName, priority, isPlayer, distance, isImportant, speed, length)
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

-- Handle animation played event (like Lycoris AnimatorDefender.process)
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
    
    -- Check if it's an important animation
    local isImportant = isImportantAnimation(animName) or priority == "Action" or priority == "Action2" or priority == "Action3" or priority == "Action4"
    
    -- Combat only filter
    if combatOnly then
        if isIgnoredAnimation(animName) and not isImportant then
            return
        end
    end

    -- Start tracking playback data (like Lycoris pbdata)
    local pbdata = PlaybackData.new(track, entity)
    activePlaybacks[track] = pbdata
    
    -- Track when animation ends to record final data
    local conn
    conn = track.Stopped:Connect(function()
        if conn then conn:Disconnect() end
        
        -- Move to recorded playbacks
        local formattedId = formatAnimationId(animId)
        recordedPlaybacks[formattedId] = pbdata
        activePlaybacks[track] = nil
    end)
    
    -- Get initial speed and length
    local speed = track.Speed
    local length = track.Length

    addLogEntry(entityName, animId, animName, priority, isPlayer, distance, isImportant, speed, length)
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
    
    -- Watch for new descendants in Live folder specifically (like Lycoris StateListener)
    if live then
        local liveConn = live.DescendantAdded:Connect(function(descendant)
            if descendant:IsA("Animator") then
                trackAnimator(descendant)
            end
        end)
        table.insert(connections, liveConn)
    end
    
    -- Update loop for playback tracking (like Lycoris AnimatorDefender.update)
    local updateConn = RunService.RenderStepped:Connect(function()
        for track, pbdata in pairs(activePlaybacks) do
            if not track.IsPlaying then
                -- Clean up finished tracks
                local formattedId = formatAnimationId(track.Animation.AnimationId)
                recordedPlaybacks[formattedId] = pbdata
                activePlaybacks[track] = nil
            else
                -- Update playback data
                pbdata:update()
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

-- Toggle combat only
local function toggleCombatOnly()
    combatOnly = not combatOnly
    combatOnlyButton.TextColor3 = combatOnly and Library.AccentColor or Library.FontColor
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
    titleLabel.Text = "Animation Logger"
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 5, 0, 5)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextSize = 17
    titleLabel.Size = UDim2.new(0, 150, 0, 20)
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
        { name = "Len", pos = 335, width = 35 },
        { name = "Prio", pos = 374, width = 35 },
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

    combatOnlyButton = Instance.new("TextButton")
    combatOnlyButton.Name = "CombatOnly"
    combatOnlyButton.FontFace = FONT_FACE
    combatOnlyButton.TextColor3 = Library.FontColor
    combatOnlyButton.Text = "Combat Only"
    combatOnlyButton.BackgroundColor3 = Library.MainColor
    combatOnlyButton.BorderColor3 = BLACK_OUTLINE
    combatOnlyButton.Position = UDim2.new(0, 113, 0, 26)
    combatOnlyButton.Size = UDim2.new(0, 85, 0, 20)
    combatOnlyButton.TextSize = 12
    combatOnlyButton.Parent = controlBar

    autoCopyButton = Instance.new("TextButton")
    autoCopyButton.Name = "AutoCopy"
    autoCopyButton.FontFace = FONT_FACE
    autoCopyButton.TextColor3 = Library.FontColor
    autoCopyButton.Text = "Auto Copy"
    autoCopyButton.BackgroundColor3 = Library.MainColor
    autoCopyButton.BorderColor3 = BLACK_OUTLINE
    autoCopyButton.Position = UDim2.new(0, 202, 0, 26)
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
    Library:AddToRegistry(combatOnlyButton, { BackgroundColor3 = "MainColor" }, true)
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
    combatOnlyButton.MouseButton1Click:Connect(toggleCombatOnly)
    autoCopyButton.MouseButton1Click:Connect(toggleAutoCopy)

    -- Store reference in Library
    Library.AnimationLoggerFrame = outer
end

-- Clean up
function AnimationLogger.detach()
    stopLogging()
    cleanConnections()
    activePlaybacks = {}
    recordedPlaybacks = {}
    if ScreenGui then
        ScreenGui:Destroy()
    end
end

-- Get playback data for an animation ID (like Lycoris Defense.agpd)
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
    
    -- Find the log entry for this animation
    local entry = nil
    for _, e in ipairs(logEntries) do
        if e.animId == formattedId then
            entry = e
            break
        end
    end
    
    if not entry then return nil end
    
    return {
        -- Animation info
        animId = "rbxassetid://" .. formattedId,
        name = entry.animName,
        priority = entry.priority,
        
        -- Timing info (for defender configs like Lycoris)
        length = entry.length,
        speed = entry.speed,
        avgSpeed = pbdata and pbdata:getAvgSpeed() or entry.speed,
        duration = pbdata and pbdata:getDuration() or entry.length,
        
        -- Entity info
        entityName = entry.entityName,
        isPlayer = entry.isPlayer,
        isImportant = entry.isImportant,
        
        -- Suggested timing (can be used as a starting point)
        suggestedParryTime = entry.length * 0.5 * 1000, -- mid-point in ms
    }
end

-- Return module
return AnimationLogger
