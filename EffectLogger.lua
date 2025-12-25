-- Effect Logger Module (Standalone)
-- Logs effects and sounds from EffectReplicator for finding parry timings.
local EffectLogger = {}

-- Services
local RunService = game:GetService("RunService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

-- Constants
local MAX_LOG_ENTRIES = 100
local FONT_FACE = Font.new("rbxasset://fonts/families/RobotoMono.json")
local ROW_HEIGHT = 18
local HEADER_HEIGHT = 26
local WINDOW_WIDTH = 480
local WINDOW_HEIGHT = 380

-- Will be set when init is called
local Library = nil

-- UI Elements
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "EffectLogger"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Enabled = false
ScreenGui.ResetOnSpawn = false

-- State
local logEntries = {}
local connections = {}
local isLogging = false
local filterText = ""
local showSoundsOnly = false
local showEffectsOnly = false
local autoCopy = false
local originalFunctions = {}

-- UI References
local outer, inner, scrollFrame, listLayout
local filterTextbox, clearButton, toggleLoggingButton
local soundFilterButton, effectFilterButton, autoCopyButton
local entryCountLabel

-- Clean all connections
local function cleanConnections()
    for _, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    connections = {}
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

    -- Type indicator (Sound/Effect)
    local typeLabel = Instance.new("TextLabel")
    typeLabel.Name = "Type"
    typeLabel.FontFace = FONT_FACE
    typeLabel.TextColor3 = data.isSound and Color3.fromRGB(100, 200, 255) or Color3.fromRGB(255, 200, 100)
    typeLabel.Text = data.isSound and "SND" or "EFX"
    typeLabel.BackgroundTransparency = 1
    typeLabel.Position = UDim2.new(0, 4, 0, 0)
    typeLabel.Size = UDim2.new(0, 30, 1, 0)
    typeLabel.TextSize = 10
    typeLabel.TextXAlignment = Enum.TextXAlignment.Left
    typeLabel.ClipsDescendants = true
    typeLabel.Parent = row

    -- Effect name
    local nameLabel = Instance.new("TextLabel")
    nameLabel.Name = "EffectName"
    nameLabel.FontFace = FONT_FACE
    nameLabel.TextColor3 = Library.AccentColor
    nameLabel.Text = data.effectName
    nameLabel.BackgroundTransparency = 1
    nameLabel.Position = UDim2.new(0, 38, 0, 0)
    nameLabel.Size = UDim2.new(0, 120, 1, 0)
    nameLabel.TextSize = 11
    nameLabel.TextXAlignment = Enum.TextXAlignment.Left
    nameLabel.TextTruncate = Enum.TextTruncate.AtEnd
    nameLabel.ClipsDescendants = true
    nameLabel.Parent = row

    -- Entity name
    local entityLabel = Instance.new("TextLabel")
    entityLabel.Name = "Entity"
    entityLabel.FontFace = FONT_FACE
    entityLabel.TextColor3 = Library.FontColor
    entityLabel.Text = data.entityName or "N/A"
    entityLabel.BackgroundTransparency = 1
    entityLabel.Position = UDim2.new(0, 162, 0, 0)
    entityLabel.Size = UDim2.new(0, 80, 1, 0)
    entityLabel.TextSize = 11
    entityLabel.TextXAlignment = Enum.TextXAlignment.Left
    entityLabel.TextTruncate = Enum.TextTruncate.AtEnd
    entityLabel.ClipsDescendants = true
    entityLabel.Parent = row

    -- Extra info (SoundId or effect data)
    local infoLabel = Instance.new("TextLabel")
    infoLabel.Name = "Info"
    infoLabel.FontFace = FONT_FACE
    infoLabel.TextColor3 = Library.FontColor
    infoLabel.Text = data.extraInfo or ""
    infoLabel.BackgroundTransparency = 1
    infoLabel.Position = UDim2.new(0, 246, 0, 0)
    infoLabel.Size = UDim2.new(0, 140, 1, 0)
    infoLabel.TextSize = 11
    infoLabel.TextXAlignment = Enum.TextXAlignment.Left
    infoLabel.TextTruncate = Enum.TextTruncate.AtEnd
    infoLabel.ClipsDescendants = true
    infoLabel.Parent = row

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

    -- Register colors
    Library:AddToRegistry(row, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(nameLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(entityLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(infoLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(copyBtn, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor", TextColor3 = "FontColor" }, true)

    -- Copy button click
    copyBtn.MouseButton1Click:Connect(function()
        local copyText = string.format("%s | %s | %s", data.effectName, data.entityName or "N/A", data.extraInfo or "")
        if copyToClipboard(copyText) then
            copyBtn.Text = "✓"
            task.delay(1, function()
                if copyBtn and copyBtn.Parent then
                    copyBtn.Text = "Copy"
                end
            end)
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
            entry.effectName:lower():find(lowerFilter) or
            (entry.entityName and entry.entityName:lower():find(lowerFilter)) or
            (entry.extraInfo and entry.extraInfo:lower():find(lowerFilter))

        local matchesSoundFilter = not showSoundsOnly or entry.isSound
        local matchesEffectFilter = not showEffectsOnly or not entry.isSound

        if matchesFilter and matchesSoundFilter and matchesEffectFilter then
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
local function addLogEntry(effectName, entityName, extraInfo, isSound)
    local entry = {
        id = #logEntries + 1,
        effectName = effectName,
        entityName = entityName,
        extraInfo = extraInfo,
        isSound = isSound,
        timestamp = os.clock()
    }

    table.insert(logEntries, entry)

    -- Trim old entries if we exceed max
    while #logEntries > MAX_LOG_ENTRIES do
        table.remove(logEntries, 1)
    end

    -- Auto copy if enabled
    if autoCopy then
        local copyText = string.format("%s | %s", effectName, extraInfo or "")
        copyToClipboard(copyText)
    end

    -- Update display if visible
    if ScreenGui.Enabled then
        updateLogDisplay()
    end
end

-- Hook EffectReplicator
local function hookEffectReplicator()
    local effectReplicator = ReplicatedStorage:FindFirstChild("EffectReplicator")
    if not effectReplicator then
        return false
    end

    local success, effectModule = pcall(function()
        return require(effectReplicator)
    end)
    
    if not success or not effectModule then
        return false
    end

    -- Hook Replicate if it exists
    if effectModule.Replicate and not originalFunctions.Replicate then
        originalFunctions.Replicate = effectModule.Replicate
        effectModule.Replicate = function(self, effectName, ...)
            if isLogging then
                local args = {...}
                local entityName = nil
                local extraInfo = ""
                
                -- Try to extract entity from arguments
                for _, arg in ipairs(args) do
                    if typeof(arg) == "Instance" then
                        if arg:IsA("Model") then
                            entityName = arg.Name
                        elseif arg:IsA("BasePart") then
                            local model = arg:FindFirstAncestorWhichIsA("Model")
                            if model then
                                entityName = model.Name
                            end
                        end
                    elseif typeof(arg) == "table" then
                        extraInfo = "table data"
                    elseif typeof(arg) == "string" then
                        if #extraInfo > 0 then
                            extraInfo = extraInfo .. ", " .. arg
                        else
                            extraInfo = arg
                        end
                    end
                end
                
                addLogEntry(effectName, entityName, extraInfo, false)
            end
            return originalFunctions.Replicate(self, effectName, ...)
        end
    end

    return true
end

-- Restore original functions
local function unhookEffectReplicator()
    local effectReplicator = ReplicatedStorage:FindFirstChild("EffectReplicator")
    if not effectReplicator then return end

    local success, effectModule = pcall(function()
        return require(effectReplicator)
    end)
    
    if not success or not effectModule then return end

    if originalFunctions.Replicate then
        effectModule.Replicate = originalFunctions.Replicate
        originalFunctions.Replicate = nil
    end
end

-- Hook Sound.Played events
local function hookSounds()
    -- Watch for new sounds
    local conn = workspace.DescendantAdded:Connect(function(descendant)
        if not isLogging then return end
        if not descendant:IsA("Sound") then return end
        
        -- Log when sound plays
        local playConn
        playConn = descendant.Played:Connect(function()
            if not isLogging then return end
            
            local parent = descendant.Parent
            local entityName = nil
            
            if parent then
                local model = parent:FindFirstAncestorWhichIsA("Model") or 
                              (parent:IsA("Model") and parent)
                if model then
                    entityName = model.Name
                end
            end
            
            local soundId = descendant.SoundId:gsub("rbxassetid://", "")
            addLogEntry(descendant.Name, entityName, soundId, true)
        end)
        
        table.insert(connections, playConn)
    end)
    
    table.insert(connections, conn)
end

-- Start logging
local function startLogging()
    isLogging = true
    toggleLoggingButton.Text = "Stop Logging"
    toggleLoggingButton.TextColor3 = Color3.fromRGB(255, 100, 100)

    hookEffectReplicator()
    hookSounds()
end

-- Stop logging
local function stopLogging()
    isLogging = false
    toggleLoggingButton.Text = "Start Logging"
    toggleLoggingButton.TextColor3 = Library.FontColor

    unhookEffectReplicator()
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

-- Toggle sound filter
local function toggleSoundFilter()
    showSoundsOnly = not showSoundsOnly
    if showSoundsOnly then
        showEffectsOnly = false
        effectFilterButton.TextColor3 = Library.FontColor
    end
    soundFilterButton.TextColor3 = showSoundsOnly and Library.AccentColor or Library.FontColor
    updateLogDisplay()
end

-- Toggle effect filter
local function toggleEffectFilter()
    showEffectsOnly = not showEffectsOnly
    if showEffectsOnly then
        showSoundsOnly = false
        soundFilterButton.TextColor3 = Library.FontColor
    end
    effectFilterButton.TextColor3 = showEffectsOnly and Library.AccentColor or Library.FontColor
    updateLogDisplay()
end

-- Toggle auto copy
local function toggleAutoCopy()
    autoCopy = not autoCopy
    autoCopyButton.TextColor3 = autoCopy and Library.AccentColor or Library.FontColor
end

-- Set visibility
function EffectLogger.visible(state)
    ScreenGui.Enabled = state
    if state then
        updateLogDisplay()
    end
end

-- Initialize the module
function EffectLogger.init(lib)
    Library = lib

    -- Parent ScreenGui
    ScreenGui.Parent = Library.ScreenGui.Parent

    -- Create outer frame
    outer = Instance.new("Frame")
    outer.Name = "Outer"
    outer.BackgroundColor3 = Color3.new(1, 1, 1)
    outer.Position = UDim2.new(0.3, 0, 0.15, 0)
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
    titleLabel.Text = "Effect Logger"
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

    -- Header row
    local headerRow = Instance.new("Frame")
    headerRow.Name = "HeaderRow"
    headerRow.BackgroundColor3 = Library.MainColor
    headerRow.BorderColor3 = Library.OutlineColor
    headerRow.BorderMode = Enum.BorderMode.Inset
    headerRow.Position = UDim2.new(0, 4, 0, HEADER_HEIGHT)
    headerRow.Size = UDim2.new(1, -8, 0, ROW_HEIGHT)
    headerRow.Parent = inner

    local headers = {
        { name = "Type", pos = 4, width = 30 },
        { name = "Effect", pos = 38, width = 120 },
        { name = "Entity", pos = 162, width = 80 },
        { name = "Info", pos = 246, width = 140 },
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

    -- Scroll frame
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

    -- Sound filter button
    soundFilterButton = Instance.new("TextButton")
    soundFilterButton.Name = "SoundFilter"
    soundFilterButton.FontFace = FONT_FACE
    soundFilterButton.TextColor3 = Library.FontColor
    soundFilterButton.Text = "Sounds"
    soundFilterButton.BackgroundColor3 = Library.MainColor
    soundFilterButton.BorderColor3 = Library.OutlineColor
    soundFilterButton.Position = UDim2.new(0, 0, 0, 26)
    soundFilterButton.Size = UDim2.new(0, 55, 0, 20)
    soundFilterButton.TextSize = 12
    soundFilterButton.Parent = controlBar

    -- Effect filter button
    effectFilterButton = Instance.new("TextButton")
    effectFilterButton.Name = "EffectFilter"
    effectFilterButton.FontFace = FONT_FACE
    effectFilterButton.TextColor3 = Library.FontColor
    effectFilterButton.Text = "Effects"
    effectFilterButton.BackgroundColor3 = Library.MainColor
    effectFilterButton.BorderColor3 = Library.OutlineColor
    effectFilterButton.Position = UDim2.new(0, 59, 0, 26)
    effectFilterButton.Size = UDim2.new(0, 55, 0, 20)
    effectFilterButton.TextSize = 12
    effectFilterButton.Parent = controlBar

    -- Auto copy button
    autoCopyButton = Instance.new("TextButton")
    autoCopyButton.Name = "AutoCopy"
    autoCopyButton.FontFace = FONT_FACE
    autoCopyButton.TextColor3 = Library.FontColor
    autoCopyButton.Text = "Auto Copy"
    autoCopyButton.BackgroundColor3 = Library.MainColor
    autoCopyButton.BorderColor3 = Library.OutlineColor
    autoCopyButton.Position = UDim2.new(0, 118, 0, 26)
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
    Library:AddToRegistry(soundFilterButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(effectFilterButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(autoCopyButton, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)

    -- Connect events
    filterTextbox:GetPropertyChangedSignal("Text"):Connect(function()
        filterText = filterTextbox.Text
        updateLogDisplay()
    end)

    toggleLoggingButton.MouseButton1Click:Connect(toggleLogging)
    clearButton.MouseButton1Click:Connect(clearLogs)
    soundFilterButton.MouseButton1Click:Connect(toggleSoundFilter)
    effectFilterButton.MouseButton1Click:Connect(toggleEffectFilter)
    autoCopyButton.MouseButton1Click:Connect(toggleAutoCopy)

    -- Store reference
    Library.EffectLoggerFrame = outer
end

-- Clean up
function EffectLogger.detach()
    stopLogging()
    cleanConnections()
    unhookEffectReplicator()
    if ScreenGui then
        ScreenGui:Destroy()
    end
end

-- Return module
return EffectLogger
