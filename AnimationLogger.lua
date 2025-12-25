-- Animation Logger Module (Standalone)
-- Logs animation IDs, names, priorities, and speeds from entities in the game.
local AnimationLogger = {}

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

-- Constants
local MAX_LOG_ENTRIES = 100
local FONT_FACE = Font.new("rbxasset://fonts/families/RobotoMono.json")
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 26
local WINDOW_WIDTH = 420
local WINDOW_HEIGHT = 350

-- Will be set when init is called
local Library = nil
local AnimationVisualizer = nil

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

-- UI References
local outer, inner, scrollFrame, listLayout
local filterTextbox, clearButton, toggleLoggingButton
local npcFilterButton, playerFilterButton, autoCopyButton
local entryCountLabel

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
    row.BorderColor3 = Library.OutlineColor
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
    entityLabel.Size = UDim2.new(0, 80, 1, 0)
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
    idLabel.Position = UDim2.new(0, 88, 0, 0)
    idLabel.Size = UDim2.new(0, 110, 1, 0)
    idLabel.TextSize = 11
    idLabel.TextXAlignment = Enum.TextXAlignment.Left
    idLabel.TextTruncate = Enum.TextTruncate.AtEnd
    idLabel.ClipsDescendants = true
    idLabel.Parent = row

    -- Animation name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "AnimName"
    nameLabel.FontFace = FONT_FACE
    nameLabel.TextColor3 = Library.FontColor
    nameLabel.Text = data.animName or "Unknown"
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 202, 0, 0)
    nameLabel.Size = UDim2.new(0, 100, 1, 0)
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.ClipsDescendants = true
    nameLabel.Parent = row

    -- Priority
    local priorityLabel = Instance.new("TextLabel")
    priorityLabel.Name = "Priority"
    priorityLabel.FontFace = FONT_FACE
    priorityLabel.TextColor3 = Library.FontColor
    priorityLabel.Text = data.priority
    priorityLabel.BackgroundTransparency = 1
    priorityLabel.Position = UDim2.new(0, 306, 0, 0)
    priorityLabel.Size = UDim2.new(0, 50, 1, 0)
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
    copyBtn.BorderColor3 = Library.OutlineColor
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
    previewBtn.BorderColor3 = Library.OutlineColor
    previewBtn.Position = UDim2.new(1, -62, 0, 2)
    previewBtn.Size = UDim2.new(0, 18, 0, ROW_HEIGHT - 4)
    previewBtn.TextSize = 10
    previewBtn.Parent = row

    -- Register colors
    Library:AddToRegistry(row, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(idLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(nameLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(priorityLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(copyBtn, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(previewBtn, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", TextColor3 = "FontColor" }, true)

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
local function addLogEntry(entityName, animId, animName, priority, isPlayer)
    local formattedId = formatAnimationId(animId)

    local entry = {
        id = #logEntries + 1,
        entityName = entityName,
        animId = formattedId,
        animName = animName,
        priority = priority,
        isPlayer = isPlayer,
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

    local entityName = entity.Name
    local isPlayer = Players:GetPlayerFromCharacter(entity) ~= nil

    -- Apply filters early for performance
    if showNpcsOnly and isPlayer then return end
    if showPlayersOnly and not isPlayer then return end

    local animId = track.Animation.AnimationId
    local animName = track.Animation.Name
    local priority = track.Priority.Name

    addLogEntry(entityName, animId, animName, priority, isPlayer)
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

    -- Watch for new animators
    local descendantConn = workspace.DescendantAdded:Connect(function(descendant)
        if descendant:IsA("Animator") then
            trackAnimator(descendant)
        end
    end)
    table.insert(connections, descendantConn)
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
    outer.Position = UDim2.new(0.5, 0, 0.216, 0)
    outer.BorderColor3 = Color3.new()
    outer.Size = UDim2.new(0, WINDOW_WIDTH, 0, WINDOW_HEIGHT)
    outer.ZIndex = 100
    outer.Parent = ScreenGui

    -- Create inner frame
    inner = Instance.new("Frame")
    inner.Name = "Inner"
    inner.BackgroundColor3 = Library.MainColor
    inner.BorderMode = Enum.BorderMode.Inset
    inner.BorderColor3 = Library.OutlineColor
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
    headerRow.BorderColor3 = Library.OutlineColor
    headerRow.BorderMode = Enum.BorderMode.Inset
    headerRow.Position = UDim2.new(0, 4, 0, HEADER_HEIGHT)
    headerRow.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
    headerRow.Parent = inner

    local headers = {
        { name = "Entity", pos = 4, width = 80 },
        { name = "Anim ID", pos = 88, width = 110 },
        { name = "Name", pos = 202, width = 100 },
        { name = "Priority", pos = 306, width = 50 },
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
    scrollFrame.BorderColor3 = Library.OutlineColor
    scrollFrame.BorderMode = Enum.BorderMode.Inset
    scrollFrame.Position = UDim2.new(0, 4, 0, HEADER_HEIGHT + ROW_HEIGHT + 4)
    scrollFrame.Size = UDim2.new(1, -8, 1, -(HEADER_HEIGHT + ROW_HEIGHT + 4 + 60))
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
    controlBar.Position = UDim2.new(0, 4, 1, -54)
    controlBar.Size = UDim2.new(1, -8, 0, 50)
    controlBar.Parent = inner

    -- Filter textbox
    filterTextbox = Instance.new("TextBox")
    filterTextbox.Name = "FilterTextbox"
    filterTextbox.FontFace = FONT_FACE
    filterTextbox.TextColor3 = Library.FontColor
    filterTextbox.PlaceholderText = "Filter..."
    filterTextbox.PlaceholderColor3 = Color3.fromRGB(100, 100, 100)
    filterTextbox.Text = ""
    filterTextbox.BackgroundColor3 = Library.MainColor
    filterTextbox.BorderColor3 = Library.OutlineColor
    filterTextbox.Position = UDim2.new(0, 0, 0, 0)
    filterTextbox.Size = UDim2.new(0, 120, 0, 20)
    filterTextbox.TextSize = 12
    filterTextbox.ClearTextOnFocus = false
    filterTextbox.Parent = controlBar

    -- Toggle logging button
    toggleLoggingButton = Instance.new("TextButton")
    toggleLoggingButton.Name = "ToggleLogging"
    toggleLoggingButton.FontFace = FONT_FACE
    toggleLoggingButton.TextColor3 = Library.FontColor
    toggleLoggingButton.Text = "Start Logging"
    toggleLoggingButton.BackgroundColor3 = Library.MainColor
    toggleLoggingButton.BorderColor3 = Library.OutlineColor
    toggleLoggingButton.Position = UDim2.new(0, 124, 0, 0)
    toggleLoggingButton.Size = UDim2.new(0, 90, 0, 20)
    toggleLoggingButton.TextSize = 12
    toggleLoggingButton.Parent = controlBar

    -- Clear button
    clearButton = Instance.new("TextButton")
    clearButton.Name = "ClearLogs"
    clearButton.FontFace = FONT_FACE
    clearButton.TextColor3 = Library.FontColor
    clearButton.Text = "Clear"
    clearButton.BackgroundColor3 = Library.MainColor
    clearButton.BorderColor3 = Library.OutlineColor
    clearButton.Position = UDim2.new(0, 218, 0, 0)
    clearButton.Size = UDim2.new(0, 50, 0, 20)
    clearButton.TextSize = 12
    clearButton.Parent = controlBar

    -- NPC filter button
    npcFilterButton = Instance.new("TextButton")
    npcFilterButton.Name = "NpcFilter"
    npcFilterButton.FontFace = FONT_FACE
    npcFilterButton.TextColor3 = Library.FontColor
    npcFilterButton.Text = "NPCs"
    npcFilterButton.BackgroundColor3 = Library.MainColor
    npcFilterButton.BorderColor3 = Library.OutlineColor
    npcFilterButton.Position = UDim2.new(0, 0, 0, 26)
    npcFilterButton.Size = UDim2.new(0, 50, 0, 20)
    npcFilterButton.TextSize = 12
    npcFilterButton.Parent = controlBar

    -- Player filter button
    playerFilterButton = Instance.new("TextButton")
    playerFilterButton.Name = "PlayerFilter"
    playerFilterButton.FontFace = FONT_FACE
    playerFilterButton.TextColor3 = Library.FontColor
    playerFilterButton.Text = "Players"
    playerFilterButton.BackgroundColor3 = Library.MainColor
    playerFilterButton.BorderColor3 = Library.OutlineColor
    playerFilterButton.Position = UDim2.new(0, 54, 0, 26)
    playerFilterButton.Size = UDim2.new(0, 55, 0, 20)
    playerFilterButton.TextSize = 12
    playerFilterButton.Parent = controlBar

    -- Auto copy button
    autoCopyButton = Instance.new("TextButton")
    autoCopyButton.Name = "AutoCopy"
    autoCopyButton.FontFace = FONT_FACE
    autoCopyButton.TextColor3 = Library.FontColor
    autoCopyButton.Text = "Auto Copy"
    autoCopyButton.BackgroundColor3 = Library.MainColor
    autoCopyButton.BorderColor3 = Library.OutlineColor
    autoCopyButton.Position = UDim2.new(0, 113, 0, 26)
    autoCopyButton.Size = UDim2.new(0, 70, 0, 20)
    autoCopyButton.TextSize = 12
    autoCopyButton.Parent = controlBar

    -- Make draggable
    Library:MakeDraggable(outer)

    -- Register colors
    Library:AddToRegistry(color, { BackgroundColor3 = "AccentColor" }, true)
    Library:AddToRegistry(titleLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(entryCountLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(headerRow, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(scrollFrame, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", ScrollBarImageColor3 = "AccentColor" }, true)
    Library:AddToRegistry(filterTextbox, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(toggleLoggingButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(clearButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(npcFilterButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(playerFilterButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(autoCopyButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)

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
end

-- Clean up
function AnimationLogger.detach()
    stopLogging()
    cleanConnections()
    if ScreenGui then
        ScreenGui:Destroy()
    end
end

-- Return module
return AnimationLogger
