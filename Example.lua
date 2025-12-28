-- Initialize shared.dxe table (required for Library notifications)
shared.dxe = shared.dxe or {}
shared.dxe.silent = true -- Start with notifications disabled by default

local ConsoleFilter = {
    enabled = true,
    origPrint = print,
    origWarn = warn,
    prefixes = {
        "[dxe]",
        "[AnimLogger]",
        "[AutoDefense]",
        "[ESP",
        "[Hitbox",
        "[Defense]",
        "[KeyHandler]",
    }
}

local function isOurOutput(firstArg)
    if type(firstArg) ~= "string" then return false end
    for _, prefix in ipairs(ConsoleFilter.prefixes) do
        if firstArg:sub(1, #prefix) == prefix then
            return true
        end
    end
    return false
end

-- Check if we have executor functions available
if hookfunction or replaceclosure then
    local hook = hookfunction or replaceclosure
    
    -- Hook print - store original in table to avoid closure issues
    ConsoleFilter.origPrint = hook(print, function(...)
        if not ConsoleFilter.enabled then
            return ConsoleFilter.origPrint(...)
        end
        
        local firstArg = select(1, ...)
        if isOurOutput(firstArg) then
            return ConsoleFilter.origPrint(...)
        end
        
        if checkcaller and checkcaller() then
            return ConsoleFilter.origPrint("[dxe]", ...)
        end
        
        return nil
    end)
    
    -- Hook warn
    ConsoleFilter.origWarn = hook(warn, function(...)
        if not ConsoleFilter.enabled then
            return ConsoleFilter.origWarn(...)
        end
        
        local firstArg = select(1, ...)
        if isOurOutput(firstArg) then
            return ConsoleFilter.origWarn(...)
        end
        
        if checkcaller and checkcaller() then
            return ConsoleFilter.origWarn("[dxe]", ...)
        end
        
        return nil
    end)
    
    ConsoleFilter.origPrint("[dxe] Console filter enabled - blocking game output")
end

-- Our own print function that always works
local function dxePrint(...)
    ConsoleFilter.origPrint("[dxe]", ...)
end

local function dxeWarn(...)
    ConsoleFilter.origWarn("[dxe]", ...)
end

-- Store references for toggling and use
shared.dxe.filterConsole = function(enabled)
    ConsoleFilter.enabled = enabled
    if enabled then
        dxePrint("Console filter enabled")
    else
        dxePrint("Console filter disabled - showing all output")
    end
end
shared.dxe.print = dxePrint
shared.dxe.warn = dxeWarn
shared.dxe.originalPrint = ConsoleFilter.origPrint
shared.dxe.originalWarn = ConsoleFilter.origWarn

shared.dxe.espFont = 3 -- Default to Monospace
shared.dxe.trackedTextObjects = setmetatable({}, {__mode = "v"})

if Drawing and Drawing.new then
    local originalDrawingNew = Drawing.new
    Drawing.new = function(objectType)
        local obj = originalDrawingNew(objectType)
        if objectType == "Text" then
            -- Apply current font setting
            pcall(function()
                obj.Font = shared.dxe.espFont or 3
            end)
            -- Track it for later updates
            table.insert(shared.dxe.trackedTextObjects, obj)
        end
        return obj
    end
    dxePrint("Drawing.new hook installed for ESP fonts")
end

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/SaveManager.lua"))()
local AnimationVisualizer = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/AnimationVisualizer.lua"))()
local AnimationLogger = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/AnimationLogger.lua"))()
local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/esp.lua"))()
local AutoDefense = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/AutoDefense.lua"))()

local Window = Library:CreateWindow({
    Title = 'dxe.exe',
    Center = true,
    AutoShow = true,
    TabPadding = 8,
    MenuFadeTime = 0.2
})

-- CALLBACK NOTE:
-- Passing in callback functions via the initial element parameters (i.e. Callback = function(Value)...) works
-- HOWEVER, using Toggles/Options.INDEX:OnChanged(function(Value) ... ) is the RECOMMENDED way to do this.
-- I strongly recommend decoupling UI code from logic code. i.e. Create your UI elements FIRST, and THEN setup :OnChanged functions later.

-- You do not have to set your tabs & groups up this way, just a prefrence.
local Tabs = {
    -- Creates a new tab titled Main
    Main = Window:AddTab('Main'),
    Combat = Window:AddTab('Combat'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

-- Groupbox and Tabbox inherit the same functions
-- except Tabboxes you have to call the functions on a tab (Tabbox:AddTab(name))
local LeftGroupBox = Tabs.Main:AddLeftGroupbox('Groupbox')

-- We can also get our Main tab via the following code:
-- local LeftGroupBox = Window.Tabs.Main:AddLeftGroupbox('Groupbox')

-- Tabboxes are a tiny bit different, but here's a basic example:
--[[

local TabBox = Tabs.Main:AddLeftTabbox() -- Add Tabbox on left side

local Tab1 = TabBox:AddTab('Tab 1')
local Tab2 = TabBox:AddTab('Tab 2')

-- You can now call AddToggle, etc on the tabs you added to the Tabbox
]]

-- Groupbox:AddToggle
-- Arguments: Index, Options
LeftGroupBox:AddToggle('MyToggle', {
    Text = 'This is a toggle',
    Default = true, -- Default value (true / false)
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the toggle
})


-- Fetching a toggle object for later use:
-- Toggles.MyToggle.Value

-- Toggles is a table added to getgenv() by the library
-- You index Toggles with the specified index, in this case it is 'MyToggle'
-- To get the state of the toggle you do toggle.Value

-- Calls the passed function when the toggle is updated
-- Use task.defer to ensure toggle is fully registered before attaching callback
task.defer(function()
    if Toggles.MyToggle then
        Toggles.MyToggle:OnChanged(function()
            -- Add your logic here
        end)
        
        -- This should print to the console: "My toggle state changed! New value: false"
        Toggles.MyToggle:SetValue(false)
    end
end)

-- 1/15/23
-- Deprecated old way of creating buttons in favor of using a table
-- Added DoubleClick button functionality

--[[
    Groupbox:AddButton
    Arguments: {
        Text = string,
        Func = function,
        DoubleClick = boolean
        Tooltip = string,
    }

    You can call :AddButton on a button to add a SubButton!
]]

local MyButton = LeftGroupBox:AddButton({
    Text = 'Button',
    Func = function()
        -- Add your logic here
    end,
    DoubleClick = false,
    Tooltip = 'This is the main button'
})

local MyButton2 = MyButton:AddButton({
    Text = 'Sub button',
    Func = function()
        -- Add your logic here
    end,
    DoubleClick = true, -- You will have to click this button twice to trigger the callback
    Tooltip = 'This is the sub button (double click me!)'
})

--[[
    NOTE: You can chain the button methods!
    EXAMPLE:

    LeftGroupBox:AddButton({ Text = 'Kill all', Func = Functions.KillAll, Tooltip = 'This will kill everyone in the game!' })
        :AddButton({ Text = 'Kick all', Func = Functions.KickAll, Tooltip = 'This will kick everyone in the game!' })
]]

-- Groupbox:AddLabel
-- Arguments: Text, DoesWrap
LeftGroupBox:AddLabel('This is a label')
LeftGroupBox:AddLabel('This is a label\n\nwhich wraps its text!', true)

-- Groupbox:AddDivider
-- Arguments: None
LeftGroupBox:AddDivider()

--[[
    Groupbox:AddSlider
    Arguments: Idx, SliderOptions

    SliderOptions: {
        Text = string,
        Default = number,
        Min = number,
        Max = number,
        Suffix = string,
        Rounding = number,
        Compact = boolean,
        HideMax = boolean,
    }

    Text, Default, Min, Max, Rounding must be specified.
    Suffix is optional.
    Rounding is the number of decimal places for precision.

    Compact will hide the title label of the Slider

    HideMax will only display the value instead of the value & max value of the slider
    Compact will do the same thing
]]
LeftGroupBox:AddSlider('MySlider', {
    Text = 'This is my slider!',
    Default = 0,
    Min = 0,
    Max = 5,
    Rounding = 1,
    Compact = false,
})

-- Options is a table added to getgenv() by the library
-- You index Options with the specified index, in this case it is 'MySlider'
-- To get the value of the slider you do slider.Value

-- Note: Access Options after they're registered
-- local Number = Options.MySlider.Value

-- Groupbox:AddInput
-- Arguments: Idx, Info
LeftGroupBox:AddInput('MyTextbox', {
    Default = 'My textbox!',
    Numeric = false, -- true / false, only allows numbers
    Finished = false, -- true / false, only calls callback when you press enter

    Text = 'This is a textbox',
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the textbox

    Placeholder = 'Placeholder text', -- placeholder text when the box is empty
    -- MaxLength is also an option which is the max length of the text
})

-- Callbacks will be set up in the deferred block below

-- Groupbox:AddDropdown
-- Arguments: Idx, Info

LeftGroupBox:AddDropdown('MyDropdown', {
    Values = { 'This', 'is', 'a', 'dropdown' },
    Default = 1, -- number index of the value / string
    Multi = false, -- true / false, allows multiple choices to be selected

    Text = 'A dropdown',
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the dropdown
})

-- Callbacks will be set up in the deferred block below

-- Multi dropdowns
LeftGroupBox:AddDropdown('MyMultiDropdown', {
    -- Default is the numeric index (e.g. "This" would be 1 since it if first in the values list)
    -- Default also accepts a string as well

    -- Currently you can not set multiple values with a dropdown

    Values = { 'This', 'is', 'a', 'dropdown' },
    Default = 1,
    Multi = true, -- true / false, allows multiple choices to be selected

    Text = 'A dropdown',
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the dropdown
})

-- Callbacks will be set up in the deferred block below

LeftGroupBox:AddDropdown('MyPlayerDropdown', {
    SpecialType = 'Player',
    Text = 'A player dropdown',
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the dropdown
})

-- Label:AddColorPicker
-- Arguments: Idx, Info

-- You can also ColorPicker & KeyPicker to a Toggle as well

LeftGroupBox:AddLabel('Color'):AddColorPicker('ColorPicker', {
    Default = Color3.new(0, 1, 0), -- Bright green
    Title = 'Some color', -- Optional. Allows you to have a custom color picker title (when you open it)
    Transparency = 0, -- Optional. Enables transparency changing for this color picker (leave as nil to disable)
})

-- Callbacks will be set up in the deferred block below

-- Label:AddKeyPicker
-- Arguments: Idx, Info

LeftGroupBox:AddLabel('Keybind'):AddKeyPicker('KeyPicker', {
    -- SyncToggleState only works with toggles.
    -- It allows you to make a keybind which has its state synced with its parent toggle

    -- Example: Keybind which you use to toggle flyhack, etc.
    -- Changing the toggle disables the keybind state and toggling the keybind switches the toggle state

    Default = 'MB2', -- String as the name of the keybind (MB1, MB2 for mouse buttons)
    SyncToggleState = false,


    -- You can define custom Modes but I have never had a use for it.
    Mode = 'Toggle', -- Modes: Always, Toggle, Hold

    Text = 'Auto lockpick safes', -- Text to display in the keybind menu
    NoUI = false, -- Set to true if you want to hide from the Keybind menu,
})

-- OnClick is only fired when you press the keybind and the mode is Toggle
-- Otherwise, you will have to use Keybind:GetState()
-- Callbacks will be set up in the deferred block below

-- Long text label to demonstrate UI scrolling behaviour.
local LeftGroupBox2 = Tabs.Main:AddLeftGroupbox('Groupbox #2');
LeftGroupBox2:AddLabel('Oh no...\nThis label spans multiple lines!\n\nWe\'re gonna run out of UI space...\nJust kidding! Scroll down!\n\n\nHello from below!', true)

-- ESP Controls
local ESPGroupBox = Tabs.Main:AddRightGroupbox('ESP')

ESPGroupBox:AddToggle('ESPEnabled', {
    Text = 'Enable ESP',
    Default = false,
    Tooltip = 'Toggle player ESP'
})

ESPGroupBox:AddToggle('ESPBoxes', {
    Text = 'Boxes',
    Default = true,
    Tooltip = 'Show bounding boxes'
})

ESPGroupBox:AddToggle('ESPTracers', {
    Text = 'Tracers',
    Default = false,
    Tooltip = 'Show tracer lines'
})

ESPGroupBox:AddToggle('ESPHealthBar', {
    Text = 'Health Bar',
    Default = true,
    Tooltip = 'Show health bars'
})

ESPGroupBox:AddToggle('ESPPostureBar', {
    Text = 'Posture Bar',
    Default = true,
    Tooltip = 'Show posture bars (orange)'
})

ESPGroupBox:AddToggle('ESPLifeforceBar', {
    Text = 'Lifeforce Bar',
    Default = true,
    Tooltip = 'Show lifeforce/blood bars (red)'
})

ESPGroupBox:AddToggle('ESPShowName', {
    Text = 'Show Names',
    Default = true,
    Tooltip = 'Show player names'
})

ESPGroupBox:AddToggle('ESPShowLevel', {
    Text = 'Show Level',
    Default = true,
    Tooltip = 'Show player level'
})

ESPGroupBox:AddToggle('ESPShowHealth', {
    Text = 'Show Health',
    Default = true,
    Tooltip = 'Show health values (HP: 100/100)'
})

ESPGroupBox:AddToggle('ESPShowHealthPercent', {
    Text = 'Show Health %',
    Default = true,
    Tooltip = 'Show health percentage'
})

ESPGroupBox:AddToggle('ESPShowDistance', {
    Text = 'Show Distance',
    Default = true,
    Tooltip = 'Show distance in studs'
})

ESPGroupBox:AddToggle('ESPShowTeam', {
    Text = 'Show Teammates',
    Default = true,
    Tooltip = 'Show ESP for teammates'
})

ESPGroupBox:AddToggle('ESPProximityArrows', {
    Text = 'Proximity Arrows',
    Default = false,
    Tooltip = 'Show arrows for off-screen players'
})

ESPGroupBox:AddSlider('ESPMaxDistance', {
    Text = 'Max Distance',
    Default = 1000,
    Min = 100,
    Max = 5000,
    Rounding = 0,
    Compact = false,
})

ESPGroupBox:AddSlider('ESPTextSize', {
    Text = 'Text Size',
    Default = 13,
    Min = 8,
    Max = 24,
    Rounding = 0,
    Compact = false,
})

ESPGroupBox:AddDropdown('ESPFont', {
    Text = 'Font',
    Default = 'Monospace',
    Values = {'UI', 'System', 'Plex', 'Monospace'},
    Tooltip = 'ESP text font'
})

ESPGroupBox:AddToggle('ESPTeamColors', {
    Text = 'Use Team Colors',
    Default = true,
    Tooltip = 'Different colors for allies/enemies (off = use enemy color for all)'
})

ESPGroupBox:AddLabel('Name/Text Color'):AddColorPicker('ESPNameColor', {
    Default = Color3.fromRGB(255, 255, 255),
    Title = 'Name/Text Color',
})

ESPGroupBox:AddLabel('Ally Color'):AddColorPicker('ESPAllyColor', {
    Default = Color3.fromRGB(0, 255, 0),
    Title = 'Ally Color',
})

ESPGroupBox:AddLabel('Enemy Color'):AddColorPicker('ESPEnemyColor', {
    Default = Color3.fromRGB(255, 0, 0),
    Title = 'Enemy Color',
})

-- ESP Settings Callbacks
if ESP and ESP.Settings then
    -- Font map for dropdown (Drawing.Fonts enum values)
    local fontMap = ESP.FontMap or {
        ["UI"] = 0,
        ["System"] = 1,
        ["Plex"] = 2,
        ["Monospace"] = 3,
    }
    
    -- Function to update font on all tracked text objects
    local function updateAllESPFonts(fontIndex)
        shared.dxe.espFont = fontIndex
        
        -- Update settings
        ESP.Settings.font = fontIndex
        if ESP.Settings.Font then ESP.Settings.Font = fontIndex end
        
        -- Update all tracked text objects from the hook
        local trackedTextObjects = shared.dxe.trackedTextObjects or {}
        for i = #trackedTextObjects, 1, -1 do
            local obj = trackedTextObjects[i]
            if obj then
                local success = pcall(function()
                    obj.Font = fontIndex
                end)
                if not success then
                    table.remove(trackedTextObjects, i)
                end
            else
                table.remove(trackedTextObjects, i)
            end
        end
        
        -- Also try ESP internal tables
        local instanceTables = {
            ESP.instances,
            ESP._instances, 
            ESP.Objects,
            ESP.objects,
            ESP.Players,
            ESP.players,
        }
        
        for _, instances in pairs(instanceTables) do
            if type(instances) == "table" then
                for _, espObj in pairs(instances) do
                    if type(espObj) == "table" then
                        for key, value in pairs(espObj) do
                            if type(value) == "userdata" then
                                pcall(function()
                                    value.Font = fontIndex
                                end)
                            end
                        end
                    end
                end
            end
        end
    end
    
    -- Store for use in callbacks
    shared.dxe.updateESPFonts = updateAllESPFonts
    
    -- Continuously update fonts (for newly created ESP instances)
    task.spawn(function()
        while task.wait(0.5) do
            if ESP and ESP.Settings and ESP.Settings.enabled then
                updateAllESPFonts(shared.dxe.espFont or 3)
            end
        end
    end)
    
    Toggles.ESPEnabled:OnChanged(function()
        ESP.Settings.enabled = Toggles.ESPEnabled.Value
    end)
    
    Toggles.ESPBoxes:OnChanged(function()
        ESP.Settings.showBoxes = Toggles.ESPBoxes.Value
    end)
    
    Toggles.ESPTracers:OnChanged(function()
        ESP.Settings.showTracers = Toggles.ESPTracers.Value
    end)
    
    Toggles.ESPHealthBar:OnChanged(function()
        ESP.Settings.showHealthBar = Toggles.ESPHealthBar.Value
    end)
    
    Toggles.ESPPostureBar:OnChanged(function()
        ESP.Settings.showPostureBar = Toggles.ESPPostureBar.Value
    end)
    
    Toggles.ESPLifeforceBar:OnChanged(function()
        ESP.Settings.showLifeforceBar = Toggles.ESPLifeforceBar.Value
    end)
    
    Toggles.ESPShowName:OnChanged(function()
        ESP.Settings.showName = Toggles.ESPShowName.Value
    end)
    
    Toggles.ESPShowLevel:OnChanged(function()
        ESP.Settings.showLevel = Toggles.ESPShowLevel.Value
    end)
    
    Toggles.ESPShowHealth:OnChanged(function()
        ESP.Settings.showHealth = Toggles.ESPShowHealth.Value
    end)
    
    Toggles.ESPShowHealthPercent:OnChanged(function()
        ESP.Settings.showHealthPercent = Toggles.ESPShowHealthPercent.Value
    end)
    
    Toggles.ESPShowDistance:OnChanged(function()
        ESP.Settings.showDistance = Toggles.ESPShowDistance.Value
    end)
    
    Toggles.ESPShowTeam:OnChanged(function()
        ESP.Settings.showTeam = Toggles.ESPShowTeam.Value
    end)
    
    Toggles.ESPProximityArrows:OnChanged(function()
        ESP.Settings.showProximityArrows = Toggles.ESPProximityArrows.Value
    end)
    
    Options.ESPMaxDistance:OnChanged(function()
        ESP.Settings.maxDistance = Options.ESPMaxDistance.Value
    end)
    
    Options.ESPTextSize:OnChanged(function()
        ESP.Settings.textSize = Options.ESPTextSize.Value
    end)
    
    Options.ESPFont:OnChanged(function()
        local fontName = Options.ESPFont.Value
        local fontIndex = fontMap[fontName] or 3
        ESP.Settings.fontName = fontName
        ESP.Settings.font = fontIndex
        shared.dxe.espFont = fontIndex
        -- Update all ESP instances directly
        updateAllESPFonts(fontIndex)
        -- Also try calling setFont method if it exists
        if ESP.setFont then
            pcall(function() ESP:setFont(fontIndex) end)
        end
        -- Debug notification
        if shared.dxe and shared.dxe.print then
            shared.dxe.print("ESP Font changed to:", fontName, "(", fontIndex, ")")
        end
    end)
    
    Toggles.ESPTeamColors:OnChanged(function()
        ESP.Settings.useTeamColors = Toggles.ESPTeamColors.Value
    end)
    
    Options.ESPNameColor:OnChanged(function()
        ESP.Settings.nameColor = Options.ESPNameColor.Value
    end)
    
    Options.ESPAllyColor:OnChanged(function()
        ESP.Settings.allyColor = Options.ESPAllyColor.Value
    end)
    
    Options.ESPEnemyColor:OnChanged(function()
        ESP.Settings.enemyColor = Options.ESPEnemyColor.Value
    end)
end

-- ============================================
-- COMBAT TAB - Auto Defense
-- ============================================
local DefenseGroupBox = Tabs.Combat:AddLeftGroupbox('Auto Defense')

DefenseGroupBox:AddToggle('AutoDefenseEnabled', {
    Text = 'Enable Auto Defense',
    Default = false,
    Tooltip = 'Automatically parry enemy attacks'
})

DefenseGroupBox:AddSlider('AutoDefenseDistance', {
    Text = 'Max Distance',
    Default = 50,
    Min = 10,
    Max = 100,
    Rounding = 0,
    Tooltip = 'Maximum distance to auto-parry enemies'
})

DefenseGroupBox:AddSlider('AutoDefenseEarlyMs', {
    Text = 'Early Compensation (ms)',
    Default = 50,
    Min = 0,
    Max = 200,
    Rounding = 0,
    Tooltip = 'How early to parry (ping compensation)'
})

DefenseGroupBox:AddSlider('AutoDefenseBlockDuration', {
    Text = 'Block Duration (ms)',
    Default = 150,
    Min = 50,
    Max = 500,
    Rounding = 0,
    Tooltip = 'How long to hold block'
})

DefenseGroupBox:AddToggle('AutoDefenseOnlyTargeted', {
    Text = 'Only When Targeted',
    Default = false,
    Tooltip = 'Only parry if enemy is targeting you'
})

DefenseGroupBox:AddToggle('AutoDefenseUseDetected', {
    Text = 'Use Detected Timings',
    Default = true,
    Tooltip = 'Use parry timings learned from AnimationLogger'
})

DefenseGroupBox:AddToggle('AutoDefenseOnlyWhitelisted', {
    Text = 'Only Whitelisted Anims',
    Default = true,
    Tooltip = 'Only parry animations with known/learned timings (recommended)'
})

DefenseGroupBox:AddToggle('AutoDefenseDebug', {
    Text = 'Debug Mode',
    Default = false,
    Tooltip = 'Show debug notifications when parrying'
})

DefenseGroupBox:AddButton({
    Text = 'Import Timings from Logger',
    Func = function()
        if AutoDefense and AutoDefense.importTimings then
            AutoDefense.importTimings()
        end
    end,
    Tooltip = 'Import learned parry timings from AnimationLogger'
})

-- Fallback Settings
local FallbackGroupBox = Tabs.Combat:AddLeftGroupbox('Fallback Settings')

FallbackGroupBox:AddSlider('AutoDefenseFallbackPercent', {
    Text = 'Fallback Parry %',
    Default = 45,
    Min = 20,
    Max = 80,
    Rounding = 0,
    Tooltip = 'When no timing data, parry at this % of animation'
})

FallbackGroupBox:AddSlider('AutoDefenseMinMs', {
    Text = 'Min Parry Time (ms)',
    Default = 100,
    Min = 50,
    Max = 300,
    Rounding = 0,
    Tooltip = 'Minimum time into animation to parry'
})

FallbackGroupBox:AddSlider('AutoDefenseMaxMs', {
    Text = 'Max Parry Time (ms)',
    Default = 800,
    Min = 400,
    Max = 1500,
    Rounding = 0,
    Tooltip = 'Maximum time into animation to parry'
})

-- Ping Compensation Settings (Lycoris-style)
local PingGroupBox = Tabs.Combat:AddRightGroupbox('Ping Compensation')

PingGroupBox:AddToggle('AutoDefenseAutoPing', {
    Text = 'Auto Ping Compensation',
    Default = true,
    Tooltip = 'Automatically adjust parry timing based on network latency'
})

PingGroupBox:AddSlider('AutoDefensePingMultiplier', {
    Text = 'Ping Multiplier',
    Default = 100,
    Min = 0,
    Max = 200,
    Rounding = 0,
    Suffix = '%',
    Tooltip = 'How much of one-way latency to compensate (100% = full compensation)'
})

PingGroupBox:AddSlider('AutoDefenseMaxPingComp', {
    Text = 'Max Ping Compensation',
    Default = 150,
    Min = 0,
    Max = 300,
    Rounding = 0,
    Suffix = 'ms',
    Tooltip = 'Maximum ping compensation in milliseconds'
})

PingGroupBox:AddLabel('Current Ping: --ms'):SetText('Current Ping: --ms')

-- M1 Block Settings
local M1BlockGroupBox = Tabs.Combat:AddRightGroupbox('M1 Block')

M1BlockGroupBox:AddToggle('AutoDefenseBlockM1', {
    Text = 'Block M1 During Attack',
    Default = false,
    Tooltip = 'Prevent M1 input when enemy attack is detected'
})

M1BlockGroupBox:AddSlider('AutoDefenseM1BlockDuration', {
    Text = 'M1 Block Duration',
    Default = 300,
    Min = 100,
    Max = 1000,
    Rounding = 0,
    Suffix = 'ms',
    Tooltip = 'How long to block M1 input after detecting attack'
})

-- Auto Defense Callbacks
if AutoDefense then
    AutoDefense.init(Library, AnimationLogger)
    
    Toggles.AutoDefenseEnabled:OnChanged(function()
        if Toggles.AutoDefenseEnabled.Value then
            AutoDefense.start()
        else
            AutoDefense.stop()
        end
    end)
    
    Options.AutoDefenseDistance:OnChanged(function()
        AutoDefense.Settings.maxDistance = Options.AutoDefenseDistance.Value
    end)
    
    Options.AutoDefenseEarlyMs:OnChanged(function()
        AutoDefense.Settings.parryEarlyMs = Options.AutoDefenseEarlyMs.Value
    end)
    
    Options.AutoDefenseBlockDuration:OnChanged(function()
        AutoDefense.Settings.blockDuration = Options.AutoDefenseBlockDuration.Value / 1000
    end)
    
    Toggles.AutoDefenseOnlyTargeted:OnChanged(function()
        AutoDefense.Settings.onlyTargeted = Toggles.AutoDefenseOnlyTargeted.Value
    end)
    
    Toggles.AutoDefenseUseDetected:OnChanged(function()
        AutoDefense.Settings.useDetectedTimings = Toggles.AutoDefenseUseDetected.Value
    end)
    
    Toggles.AutoDefenseOnlyWhitelisted:OnChanged(function()
        AutoDefense.Settings.onlyWhitelisted = Toggles.AutoDefenseOnlyWhitelisted.Value
    end)
    
    Toggles.AutoDefenseDebug:OnChanged(function()
        AutoDefense.debugMode = Toggles.AutoDefenseDebug.Value
    end)
    
    Options.AutoDefenseFallbackPercent:OnChanged(function()
        AutoDefense.Settings.fallbackParryPercent = Options.AutoDefenseFallbackPercent.Value / 100
    end)
    
    Options.AutoDefenseMinMs:OnChanged(function()
        AutoDefense.Settings.minParryMs = Options.AutoDefenseMinMs.Value
    end)
    
    Options.AutoDefenseMaxMs:OnChanged(function()
        AutoDefense.Settings.maxParryMs = Options.AutoDefenseMaxMs.Value
    end)
    
    -- Ping Compensation Callbacks
    Toggles.AutoDefenseAutoPing:OnChanged(function()
        AutoDefense.Settings.autoPingCompensation = Toggles.AutoDefenseAutoPing.Value
    end)
    
    Options.AutoDefensePingMultiplier:OnChanged(function()
        AutoDefense.Settings.pingMultiplier = Options.AutoDefensePingMultiplier.Value / 100
    end)
    
    Options.AutoDefenseMaxPingComp:OnChanged(function()
        AutoDefense.Settings.maxPingCompensation = Options.AutoDefenseMaxPingComp.Value
    end)
    
    -- M1 Block Callbacks
    Toggles.AutoDefenseBlockM1:OnChanged(function()
        AutoDefense.Settings.blockM1 = Toggles.AutoDefenseBlockM1.Value
    end)
    
    Options.AutoDefenseM1BlockDuration:OnChanged(function()
        AutoDefense.Settings.m1BlockDuration = Options.AutoDefenseM1BlockDuration.Value / 1000
    end)
    
    -- Ping display update loop
    task.spawn(function()
        while task.wait(1) do
            if AutoDefense.getLatencyInfo then
                local info = AutoDefense.getLatencyInfo()
                local label = PingGroupBox:FindChild("Label") -- Try to update label
                if info then
                    local pingText = string.format("Ping: %dms | Comp: %dms", 
                        math.floor(info.ping or 0), 
                        math.floor(info.compensation or 0))
                    -- Debug print the ping info
                    if AutoDefense.debugMode and shared.dxe and shared.dxe.print then
                        shared.dxe.print("[AutoDefense] " .. pingText)
                    end
                end
            end
        end
    end)
end

local TabBox = Tabs.Main:AddRightTabbox() -- Add Tabbox on right side

-- Anything we can do in a Groupbox, we can do in a Tabbox tab (AddToggle, AddSlider, AddLabel, etc etc...)
local Tab1 = TabBox:AddTab('Tab 1')
Tab1:AddToggle('Tab1Toggle', { Text = 'Tab1 Toggle' });

local Tab2 = TabBox:AddTab('Tab 2')
Tab2:AddToggle('Tab2Toggle', { Text = 'Tab2 Toggle' });

-- Dependency boxes let us control the visibility of UI elements depending on another UI elements state.
-- e.g. we have a 'Feature Enabled' toggle, and we only want to show that features sliders, dropdowns etc when it's enabled!
-- Dependency box example:
local RightGroupbox = Tabs.Main:AddRightGroupbox('Groupbox #3');
RightGroupbox:AddToggle('ControlToggle', { Text = 'Dependency box toggle' });

local Depbox = RightGroupbox:AddDependencyBox();
Depbox:AddToggle('DepboxToggle', { Text = 'Sub-dependency box toggle' });

-- We can also nest dependency boxes!
-- When we do this, our SupDepbox automatically relies on the visiblity of the Depbox - on top of whatever additional dependencies we set
local SubDepbox = Depbox:AddDependencyBox();
SubDepbox:AddSlider('DepboxSlider', { Text = 'Slider', Default = 50, Min = 0, Max = 100, Rounding = 0 });
SubDepbox:AddDropdown('DepboxDropdown', { Text = 'Dropdown', Default = 1, Values = {'a', 'b', 'c'} });

Depbox:SetupDependencies({
    { Toggles.ControlToggle, true } -- We can also pass `false` if we only want our features to show when the toggle is off!
});

SubDepbox:SetupDependencies({
    { Toggles.DepboxToggle, true }
});

-- Library functions
-- Sets the watermark visibility (debug info updates automatically in Library)
Library:SetWatermarkVisibility(true)

Library.KeybindFrame.Visible = true; -- todo: add a function for this

Library:OnUnload(function()
    AnimationVisualizer.detach()
    AnimationLogger.detach()
    Library.Unloaded = true
end)

-- UI Settings
local MenuGroup = Tabs['UI Settings']:AddLeftGroupbox('Menu')

-- I set NoUI so it does not show up in the keybinds menu
MenuGroup:AddButton('Unload', function() Library:Unload() end)
MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind', { Default = 'End', NoUI = true, Text = 'Menu keybind' })
MenuGroup:AddLabel('Watermark'):AddKeyPicker('WatermarkKeybind', { Default = '', NoUI = true, Text = 'Watermark toggle' })
MenuGroup:AddLabel('Keybind List'):AddKeyPicker('KeybindListKeybind', { Default = '', NoUI = true, Text = 'Keybind list toggle' })

-- Watermark toggle keybind
Options.WatermarkKeybind:OnClick(function()
    Library:SetWatermarkVisibility(not Library.Watermark.Visible)
end)

-- Keybind list toggle keybind
Options.KeybindListKeybind:OnClick(function()
    Library.KeybindFrame.Visible = not Library.KeybindFrame.Visible
end)

-- Server Options
local ServerGroup = Tabs['UI Settings']:AddLeftGroupbox('Server')

local TeleportService = game:GetService('TeleportService')
local HttpService = game:GetService('HttpService')
local Players = game:GetService('Players')

local function GetServers()
    local servers = {}
    local cursor = ""
    local placeId = game.PlaceId
    
    pcall(function()
        local url = string.format("https://games.roblox.com/v1/games/%d/servers/Public?sortOrder=Asc&limit=100", placeId)
        if cursor ~= "" then
            url = url .. "&cursor=" .. cursor
        end
        
        local response = game:HttpGet(url)
        local data = HttpService:JSONDecode(response)
        
        for _, server in pairs(data.data or {}) do
            if server.playing < server.maxPlayers and server.id ~= game.JobId then
                table.insert(servers, server)
            end
        end
    end)
    
    return servers
end

ServerGroup:AddButton({
    Text = 'Rejoin Server',
    Func = function()
        TeleportService:TeleportToPlaceInstance(game.PlaceId, game.JobId)
    end,
    Tooltip = 'Rejoin the current server'
})

ServerGroup:AddButton({
    Text = 'Server Hop',
    Func = function()
        local servers = GetServers()
        if #servers > 0 then
            local randomServer = servers[math.random(1, #servers)]
            TeleportService:TeleportToPlaceInstance(game.PlaceId, randomServer.id)
        end
    end,
    Tooltip = 'Join a random server'
})

ServerGroup:AddButton({
    Text = 'Join Lowest Server',
    Func = function()
        local servers = GetServers()
        if #servers > 0 then
            table.sort(servers, function(a, b) return a.playing < b.playing end)
            TeleportService:TeleportToPlaceInstance(game.PlaceId, servers[1].id)
        end
    end,
    Tooltip = 'Join the server with least players'
})

-- Animation Tools
local ToolsGroup = Tabs['UI Settings']:AddLeftGroupbox('Animation Tools')

-- Initialize tools
AnimationVisualizer.init(Library)
AnimationLogger.init(Library, AnimationVisualizer)

ToolsGroup:AddToggle('AnimVisualizerToggle', {
    Text = 'Animation Visualizer',
    Default = false,
    Tooltip = 'Preview animations by ID'
})

ToolsGroup:AddToggle('AnimLoggerToggle', {
    Text = 'Animation Logger',
    Default = false,
    Tooltip = 'Log animations played by entities'
})

ToolsGroup:AddDivider()

ToolsGroup:AddToggle('DebugNotifications', {
    Text = 'Debug Notifications',
    Default = false,
    Tooltip = 'Show UI debug/info notifications'
})

ToolsGroup:AddToggle('ShowHitboxes', {
    Text = 'Show Hitboxes',
    Default = false,
    Tooltip = 'Visualize attack hitboxes when animation logging'
})

ToolsGroup:AddToggle('FilterConsole', {
    Text = 'Filter Console',
    Default = true,
    Tooltip = 'Only show dxe script output, hide game spam'
})

-- Timing Config Management
local TimingConfigGroup = Tabs['UI Settings']:AddRightGroupbox('Timing Configs')

TimingConfigGroup:AddInput('TimingConfigName', {
    Default = 'swin1',
    Numeric = false,
    Finished = false,
    Text = 'Config Name',
    Tooltip = 'Name for saving/loading timing configs (e.g., swin1, sword2)',
    Placeholder = 'Enter config name...'
})

TimingConfigGroup:AddDropdown('TimingConfigList', {
    Values = AnimationLogger.listConfigs and AnimationLogger.listConfigs() or {},
    Default = 1,
    Multi = false,
    Text = 'Saved Configs',
    Tooltip = 'Select a config to load',
    AllowNull = true
})

TimingConfigGroup:AddButton({
    Text = 'Quick Save (Auto Name)',
    Func = function()
        if AnimationLogger.quickSave then
            local success, result = AnimationLogger.quickSave("swin")
            if success then
                Library:Notify("Saved config: " .. result, 2)
                -- Refresh dropdown
                Options.TimingConfigList:SetValues(AnimationLogger.listConfigs())
                Options.TimingConfigName:SetValue(result)
            else
                Library:Notify("Failed to save: " .. (result or "unknown error"), 3)
            end
        end
    end,
    Tooltip = 'Save current timings to swin1, swin2, etc.'
})

TimingConfigGroup:AddButton({
    Text = 'Save Config',
    Func = function()
        if AnimationLogger.saveConfig then
            local name = Options.TimingConfigName.Value
            if name == "" then
                return Library:Notify("Enter a config name first", 2)
            end
            local success, result = AnimationLogger.saveConfig(name)
            if success then
                Library:Notify("Saved config: " .. name, 2)
                -- Refresh dropdown
                Options.TimingConfigList:SetValues(AnimationLogger.listConfigs())
            else
                Library:Notify("Failed to save: " .. (result or "unknown error"), 3)
            end
        end
    end,
    Tooltip = 'Save current timings with the entered name'
})

TimingConfigGroup:AddButton({
    Text = 'Load Config',
    Func = function()
        if AnimationLogger.loadConfig then
            local name = Options.TimingConfigList.Value
            if not name or name == "" then
                return Library:Notify("Select a config from the list", 2)
            end
            local success, count = AnimationLogger.loadConfig(name)
            if success then
                Library:Notify(string.format("Loaded %d timings from: %s", count or 0, name), 2)
                Options.TimingConfigName:SetValue(name)
            else
                Library:Notify("Failed to load: " .. (count or "unknown error"), 3)
            end
        end
    end,
    Tooltip = 'Load timings from the selected config'
})

TimingConfigGroup:AddButton({
    Text = 'Delete Config',
    Func = function()
        if AnimationLogger.deleteConfig then
            local name = Options.TimingConfigList.Value
            if not name or name == "" then
                return Library:Notify("Select a config from the list", 2)
            end
            local success = AnimationLogger.deleteConfig(name)
            if success then
                Library:Notify("Deleted config: " .. name, 2)
                -- Refresh dropdown
                Options.TimingConfigList:SetValues(AnimationLogger.listConfigs())
            else
                Library:Notify("Failed to delete config", 3)
            end
        end
    end,
    Tooltip = 'Delete the selected config'
})

TimingConfigGroup:AddButton({
    Text = 'Refresh List',
    Func = function()
        if AnimationLogger.listConfigs then
            local configs = AnimationLogger.listConfigs()
            Options.TimingConfigList:SetValues(configs)
            Library:Notify("Found " .. #configs .. " configs", 2)
        end
    end,
    Tooltip = 'Refresh the config list'
})

TimingConfigGroup:AddButton({
    Text = 'Clear Current Timings',
    Func = function()
        if AnimationLogger.clearTimings then
            AnimationLogger.clearTimings()
            Library:Notify("Cleared all current timings", 2)
        end
    end,
    Tooltip = 'Clear all timings in memory (does not delete saved configs)'
})

Toggles.AnimVisualizerToggle:OnChanged(function()
    AnimationVisualizer.visible(Toggles.AnimVisualizerToggle.Value)
end)

Toggles.AnimLoggerToggle:OnChanged(function()
    AnimationLogger.visible(Toggles.AnimLoggerToggle.Value)
end)

Toggles.DebugNotifications:OnChanged(function()
    shared.dxe.silent = not Toggles.DebugNotifications.Value
end)

Toggles.ShowHitboxes:OnChanged(function()
    shared.dxe.showHitboxes = Toggles.ShowHitboxes.Value
end)

Toggles.FilterConsole:OnChanged(function()
    if shared.dxe.filterConsole then
        shared.dxe.filterConsole(Toggles.FilterConsole.Value)
    end
end)

-- Apply initial values (for autoload)
task.defer(function()
    task.wait(0.5) -- Wait for config to load
    shared.dxe.silent = not Toggles.DebugNotifications.Value
    shared.dxe.showHitboxes = Toggles.ShowHitboxes.Value
    
    -- Apply ESP settings from loaded config
    if ESP and ESP.Settings then
        local fontMap = ESP.FontMap or {
            ["UI"] = 0,
            ["System"] = 1,
            ["Plex"] = 2,
            ["Monospace"] = 3,
        }
        
        ESP.Settings.enabled = Toggles.ESPEnabled.Value
        ESP.Settings.showBoxes = Toggles.ESPBoxes.Value
        ESP.Settings.showTracers = Toggles.ESPTracers.Value
        ESP.Settings.showHealthBar = Toggles.ESPHealthBar.Value
        ESP.Settings.showPostureBar = Toggles.ESPPostureBar.Value
        ESP.Settings.showLifeforceBar = Toggles.ESPLifeforceBar.Value
        ESP.Settings.showName = Toggles.ESPShowName.Value
        ESP.Settings.showLevel = Toggles.ESPShowLevel.Value
        ESP.Settings.showHealth = Toggles.ESPShowHealth.Value
        ESP.Settings.showHealthPercent = Toggles.ESPShowHealthPercent.Value
        ESP.Settings.showDistance = Toggles.ESPShowDistance.Value
        ESP.Settings.showTeam = Toggles.ESPShowTeam.Value
        ESP.Settings.showProximityArrows = Toggles.ESPProximityArrows.Value
        ESP.Settings.maxDistance = Options.ESPMaxDistance.Value
        ESP.Settings.textSize = Options.ESPTextSize.Value
        ESP.Settings.fontName = Options.ESPFont.Value
        ESP.Settings.font = fontMap[Options.ESPFont.Value] or 3
        -- Update the global font setting and all ESP instances
        if shared.dxe then
            shared.dxe.espFont = fontMap[Options.ESPFont.Value] or 3
            if shared.dxe.updateESPFonts then
                shared.dxe.updateESPFonts(fontMap[Options.ESPFont.Value] or 3)
            end
        end
        ESP.Settings.useTeamColors = Toggles.ESPTeamColors.Value
        ESP.Settings.nameColor = Options.ESPNameColor.Value
        ESP.Settings.allyColor = Options.ESPAllyColor.Value
        ESP.Settings.enemyColor = Options.ESPEnemyColor.Value
    end
    
    -- Apply AutoDefense settings from loaded config
    if AutoDefense and AutoDefense.Settings then
        AutoDefense.Settings.maxDistance = Options.AutoDefenseDistance.Value
        AutoDefense.Settings.parryEarlyMs = Options.AutoDefenseEarlyMs.Value
        AutoDefense.Settings.blockDuration = Options.AutoDefenseBlockDuration.Value / 1000
        AutoDefense.Settings.onlyTargeted = Toggles.AutoDefenseOnlyTargeted.Value
        AutoDefense.Settings.useDetectedTimings = Toggles.AutoDefenseUseDetected.Value
        AutoDefense.Settings.onlyWhitelisted = Toggles.AutoDefenseOnlyWhitelisted.Value
        AutoDefense.debugMode = Toggles.AutoDefenseDebug.Value
        AutoDefense.Settings.fallbackParryPercent = Options.AutoDefenseFallbackPercent.Value / 100
        AutoDefense.Settings.minParryMs = Options.AutoDefenseMinMs.Value
        AutoDefense.Settings.maxParryMs = Options.AutoDefenseMaxMs.Value
        
        -- Ping compensation settings
        AutoDefense.Settings.autoPingCompensation = Toggles.AutoDefenseAutoPing.Value
        AutoDefense.Settings.pingMultiplier = Options.AutoDefensePingMultiplier.Value / 100
        AutoDefense.Settings.maxPingCompensation = Options.AutoDefenseMaxPingComp.Value
        
        -- M1 Block settings
        AutoDefense.Settings.blockM1 = Toggles.AutoDefenseBlockM1.Value
        AutoDefense.Settings.m1BlockDuration = Options.AutoDefenseM1BlockDuration.Value / 1000
        
        -- Start if enabled
        if Toggles.AutoDefenseEnabled.Value then
            AutoDefense.start()
        end
    end
    
    -- Apply AnimationLogger settings
    if AnimationLogger then
        -- Use AnimLoggerToggle for visibility (that's the actual toggle name)
        if AnimationLogger.visible and Toggles.AnimLoggerToggle then
            AnimationLogger.visible(Toggles.AnimLoggerToggle.Value)
        end
    end
end)

Library.ToggleKeybind = Options.MenuKeybind -- Allows you to have a custom keybind for the menu

-- Addons:
-- SaveManager (Allows you to have a configuration system)
-- ThemeManager (Allows you to have a menu theme system)

-- Hand the library over to our managers
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)

-- Ignore keys that are used by ThemeManager.
-- (we dont want configs to save themes, do we?)
SaveManager:IgnoreThemeSettings()

-- Adds our MenuKeybind to the ignore list
-- (do you want each config to have a different menu key? probably not.)
SaveManager:SetIgnoreIndexes({ 'MenuKeybind', 'WatermarkKeybind', 'KeybindListKeybind' })

-- use case for doing it this way:
-- a script hub could have themes in a global folder
-- and game configs in a separate folder per game
ThemeManager:SetFolder('dxe')
SaveManager:SetFolder('dxe/configs')

-- Builds our config menu on the right side of our tab
SaveManager:BuildConfigSection(Tabs['UI Settings'])

-- Builds our theme menu (with plenty of built in themes) on the left side
-- NOTE: you can also call ThemeManager:ApplyToGroupbox to add it to a specific groupbox
ThemeManager:ApplyToTab(Tabs['UI Settings'])

-- You can use the SaveManager:LoadAutoloadConfig() to load a config
-- which has been marked to be one that auto loads!
SaveManager:LoadAutoloadConfig()
