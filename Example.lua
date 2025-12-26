-- Initialize shared.dxe table (required for Library notifications)
shared.dxe = shared.dxe or {}
shared.dxe.silent = true -- Start with notifications disabled by default

local Library = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/Library.lua"))()
local ThemeManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/ThemeManager.lua"))()
local SaveManager = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/SaveManager.lua"))()
local AnimationVisualizer = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/AnimationVisualizer.lua"))()
local AnimationLogger = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/AnimationLogger.lua"))()
local ESP = loadstring(game:HttpGet("https://raw.githubusercontent.com/vertb1/Linorialib/refs/heads/main/esp.lua"))()

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
Toggles.MyToggle:OnChanged(function()
    -- Add your logic here
end)

-- This should print to the console: "My toggle state changed! New value: false"
Toggles.MyToggle:SetValue(false)

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

local Number = Options.MySlider.Value
Options.MySlider:OnChanged(function()
    -- Add your logic here
end)

-- This should print to the console: "MySlider was changed! New value: 3"
Options.MySlider:SetValue(3)

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

Options.MyTextbox:OnChanged(function()
    -- Add your logic here
end)

-- Groupbox:AddDropdown
-- Arguments: Idx, Info

LeftGroupBox:AddDropdown('MyDropdown', {
    Values = { 'This', 'is', 'a', 'dropdown' },
    Default = 1, -- number index of the value / string
    Multi = false, -- true / false, allows multiple choices to be selected

    Text = 'A dropdown',
    Tooltip = 'This is a tooltip', -- Information shown when you hover over the dropdown
})

Options.MyDropdown:OnChanged(function()
    -- Add your logic here
end)

Options.MyDropdown:SetValue('This')

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

Options.MyMultiDropdown:OnChanged(function()
    -- Add your logic here
end)

Options.MyMultiDropdown:SetValue({
    This = true,
    is = true,
})

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

Options.ColorPicker:OnChanged(function()
    -- Add your logic here
end)

Options.ColorPicker:SetValueRGB(Color3.fromRGB(0, 255, 140))

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
Options.KeyPicker:OnClick(function()
    -- Add your logic here
end)

Options.KeyPicker:OnChanged(function()
    -- Add your logic here
end)

Options.KeyPicker:SetValue({ 'MB2', 'Toggle' }) -- Sets keybind to MB2, mode to Hold

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

ESPGroupBox:AddToggle('ESPTeamColors', {
    Text = 'Use Team Colors',
    Default = true,
    Tooltip = 'Different colors for allies/enemies (off = use enemy color for all)'
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
    Toggles.ESPEnabled:OnChanged(function()
        -- Toggle all ESP visibility via enabled setting
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
    
    Toggles.ESPTeamColors:OnChanged(function()
        ESP.Settings.useTeamColors = Toggles.ESPTeamColors.Value
    end)
    
    Options.ESPAllyColor:OnChanged(function()
        ESP.Settings.allyColor = Options.ESPAllyColor.Value
    end)
    
    Options.ESPEnemyColor:OnChanged(function()
        ESP.Settings.enemyColor = Options.ESPEnemyColor.Value
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

-- Apply initial values (for autoload)
task.defer(function()
    task.wait(0.5) -- Wait for config to load
    shared.dxe.silent = not Toggles.DebugNotifications.Value
    shared.dxe.showHitboxes = Toggles.ShowHitboxes.Value
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
