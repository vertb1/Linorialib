-- Animation Visualizer Module (Standalone)
-- Fixed version that handles character cloning issues
local AnimationVisualizer = {}

-- Services
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Players = game:GetService("Players")
local InsertService = game:GetService("InsertService")

-- Will be set when init is called
local Library = nil

-- Create a simple R6 dummy rig for animation preview
local function createDummyRig()
    local model = Instance.new("Model")
    model.Name = "AnimDummy"
    
    local humanoid = Instance.new("Humanoid")
    humanoid.Parent = model
    
    local animator = Instance.new("Animator")
    animator.Parent = humanoid
    
    -- Create basic R6 parts
    local parts = {
        { name = "HumanoidRootPart", size = Vector3.new(2, 2, 1), pos = Vector3.new(0, 3, 0), transparency = 1 },
        { name = "Torso", size = Vector3.new(2, 2, 1), pos = Vector3.new(0, 3, 0), color = BrickColor.new("Bright blue") },
        { name = "Head", size = Vector3.new(1, 1, 1), pos = Vector3.new(0, 4.5, 0), color = BrickColor.new("Bright yellow") },
        { name = "Left Arm", size = Vector3.new(1, 2, 1), pos = Vector3.new(-1.5, 3, 0), color = BrickColor.new("Bright yellow") },
        { name = "Right Arm", size = Vector3.new(1, 2, 1), pos = Vector3.new(1.5, 3, 0), color = BrickColor.new("Bright yellow") },
        { name = "Left Leg", size = Vector3.new(1, 2, 1), pos = Vector3.new(-0.5, 1, 0), color = BrickColor.new("Br. yellowish green") },
        { name = "Right Leg", size = Vector3.new(1, 2, 1), pos = Vector3.new(0.5, 1, 0), color = BrickColor.new("Br. yellowish green") },
    }
    
    for _, partData in ipairs(parts) do
        local part = Instance.new("Part")
        part.Name = partData.name
        part.Size = partData.size
        part.Position = partData.pos
        part.Anchored = false
        part.CanCollide = false
        part.Transparency = partData.transparency or 0
        if partData.color then
            part.BrickColor = partData.color
        end
        part.Parent = model
    end
    
    model.PrimaryPart = model:FindFirstChild("HumanoidRootPart")
    return model
end

-- Try to get a usable rig for animation
local function getAnimationRig()
    local player = Players.LocalPlayer
    local character = player and player.Character
    
    -- Method 1: Clone character with Archivable trick
    if character then
        local oldArchivable = character.Archivable
        character.Archivable = true
        
        local success, clone = pcall(function()
            local c = character:Clone()
            for _, child in pairs(c:GetDescendants()) do
                if child:IsA("Script") or child:IsA("LocalScript") or child:IsA("ModuleScript") 
                   or child:IsA("Sound") or child:IsA("ParticleEmitter") or child:IsA("Trail")
                   or child:IsA("Beam") or child:IsA("Fire") or child:IsA("Smoke") or child:IsA("Sparkles")
                   or child:IsA("BillboardGui") or child:IsA("Decal") then
                    pcall(function() child:Destroy() end)
                end
            end
            return c
        end)
        
        character.Archivable = oldArchivable
        
        if success and clone then
            return clone
        end
    end
    
    -- Method 2: Create a dummy rig
    return createDummyRig()
end

-- Create ScreenGui
local ScreenGui = Instance.new("ScreenGui")
ScreenGui.Name = "AnimationVisualizer"
ScreenGui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
ScreenGui.Enabled = false
ScreenGui.ResetOnSpawn = false

-- Current playback state
local currentTrack = nil
local isPaused = false
local playbackSpeed = 1.0

-- UI Elements (will be created in init)
local outer, inner, viewportFrame, noViewportFrame, textLabel
local sliderOuter, sliderFill, sliderText, sliderInner, hideBorderRight
local playStop, frameBackwards, frameForwards, animationTextbox
local iconTwo, speedText, worldModel, camera

-- Connections
local connections = {}

local function cleanConnections()
    for _, conn in pairs(connections) do
        if conn and conn.Connected then
            conn:Disconnect()
        end
    end
    connections = {}
end

local function mapSliderValue(value, min, max, minSize, maxSize)
    if max == min then return minSize end
    return (1 - ((value - min) / (max - min))) * minSize + ((value - min) / (max - min)) * maxSize
end

local function onIdFocusLost(enter, _)
    if not enter then return end

    -- Reset
    currentTrack = nil

    local animId = animationTextbox.Text
    if not animId or animId == "" then
        return AnimationVisualizer.message("Please Enter Animation ID")
    end
    
    -- Format animation ID
    if not animId:match("rbxassetid://") and not animId:match("http") then
        animId = "rbxassetid://" .. animId
    end

    -- Make sure worldModel exists
    if not worldModel then
        return AnimationVisualizer.message("Visualizer Not Ready")
    end

    -- Clean up previous models
    pcall(function()
        for _, descendant in pairs(worldModel:GetChildren()) do
            descendant:Destroy()
        end
    end)

    AnimationVisualizer.message("Loading...")

    -- Get animation rig using improved method
    local entity = getAnimationRig()
    if not entity then
        return AnimationVisualizer.message("Failed to Create Rig")
    end
    
    -- Prepare entity for viewport
    pcall(function()
        for _, part in pairs(entity:GetDescendants()) do
            if part:IsA("BasePart") then
                part.Anchored = false
                part.CanCollide = false
            end
        end
    end)

    entity.Parent = worldModel
    
    local pivotSuccess = pcall(function()
        entity:PivotTo(CFrame.new(0, 0, 0))
    end)
    
    if not pivotSuccess then
        return AnimationVisualizer.message("Failed to Position Rig")
    end

    local primaryPart = entity.PrimaryPart or entity:FindFirstChild("HumanoidRootPart") or entity:FindFirstChild("Torso")
    if not primaryPart then
        return AnimationVisualizer.message("No Root Part Found")
    end

    -- Setup camera
    local _, bbs = entity:GetBoundingBox()
    camera.CFrame = CFrame.lookAt(
        primaryPart.Position - Vector3.new(0, 0, math.max(bbs.Magnitude * 1.5, 8)),
        primaryPart.Position
    )

    -- Find or create animator
    local humanoid = entity:FindFirstChildWhichIsA("Humanoid")
    if not humanoid then
        humanoid = Instance.new("Humanoid", entity)
    end
    
    local animator = humanoid:FindFirstChildWhichIsA("Animator")
    if not animator then
        animator = Instance.new("Animator", humanoid)
    end

    -- Stop previous animations
    for _, track in pairs(animator:GetPlayingAnimationTracks()) do
        track:Stop(0)
    end

    -- Create and load animation
    local animation = Instance.new("Animation")
    animation.AnimationId = animId

    local success, result = pcall(function()
        return animator:LoadAnimation(animation)
    end)

    if not success then
        return AnimationVisualizer.message("Load Failed:\n" .. tostring(result):sub(1, 40))
    end

    currentTrack = result
    currentTrack:Play(0, 1, isPaused and 0 or playbackSpeed)
    currentTrack.Priority = Enum.AnimationPriority.Action4
    currentTrack.Looped = true

    -- Show viewport
    viewportFrame.Visible = true
    noViewportFrame.Visible = false
end

local function onPlaybackLoop(delta)
    if not ScreenGui.Enabled then return end

    -- Update play/pause icon
    iconTwo.Image = isPaused and "rbxassetid://10734923549" or "rbxassetid://10734919336"

    -- Slider calculations
    local mhs = sliderOuter.AbsoluteSize.X
    local hs = currentTrack and mapSliderValue(currentTrack.TimePosition, 0, currentTrack.Length, 0, mhs) or 0

    -- Update slider text
    if currentTrack then
        sliderText.Text = string.format("%.3f / %.3f", currentTrack.TimePosition, currentTrack.Length)
    else
        sliderText.Text = "0.000 / ???"
    end

    -- Update slider fill
    sliderFill.Visible = hs > 0
    sliderFill.Size = UDim2.new(0, math.max(math.ceil(hs), 1), 1, 0)
    hideBorderRight.Visible = not (hs >= mhs or hs <= 0)

    -- Update speed text
    speedText.Text = string.format("Speed (%.2fx)", playbackSpeed)

    if currentTrack then
        currentTrack:AdjustSpeed(isPaused and 0 or playbackSpeed)
    end
end

local function togglePlayStop()
    if not currentTrack then return end
    isPaused = not isPaused
end

local function onFrameBackwards()
    if not currentTrack then return end
    isPaused = true
    currentTrack.TimePosition = math.max(currentTrack.TimePosition - (1/60), 0)
end

local function onFrameForwards()
    if not currentTrack then return end
    isPaused = true
    currentTrack.TimePosition = math.min(currentTrack.TimePosition + (1/60), currentTrack.Length)
end

local function onSliderInputBegan(input)
    if input.UserInputType ~= Enum.UserInputType.MouseButton1 then return end
    if not currentTrack then return end

    isPaused = true

    while ScreenGui.Enabled and UserInputService:IsMouseButtonPressed(Enum.UserInputType.MouseButton1) do
        local mouse = Players.LocalPlayer:GetMouse()
        local sliderSize = sliderOuter.AbsoluteSize.X
        local mouseX = math.clamp(mouse.X - sliderOuter.AbsolutePosition.X, 0, sliderSize)
        local newTime = mapSliderValue(mouseX, 0, sliderSize, 0, currentTrack.Length)
        currentTrack.TimePosition = newTime
        RunService.RenderStepped:Wait()
    end
end

local function outerFrameInputBegan(input)
    if input.KeyCode == Enum.KeyCode.Space then
        return togglePlayStop()
    elseif input.KeyCode == Enum.KeyCode.Right then
        return onFrameForwards()
    elseif input.KeyCode == Enum.KeyCode.Left then
        return onFrameBackwards()
    elseif input.KeyCode == Enum.KeyCode.Up then
        playbackSpeed = math.min(playbackSpeed + 0.25, 4)
    elseif input.KeyCode == Enum.KeyCode.Down then
        playbackSpeed = math.max(playbackSpeed - 0.25, 0.25)
    end
end

function AnimationVisualizer.visible(state)
    ScreenGui.Enabled = state
end

function AnimationVisualizer.message(message)
    viewportFrame.Visible = false
    noViewportFrame.Visible = true
    textLabel.Text = message
end

function AnimationVisualizer.init(lib)
    Library = lib

    -- Parent ScreenGui
    ScreenGui.Parent = Library.ScreenGui.Parent

    -- Create UI
    outer = Instance.new("Frame")
    outer.Name = "Outer"
    outer.BackgroundColor3 = Color3.new(1, 1, 1)
    outer.Position = UDim2.new(0.27, 0, 0.216, 0)
    outer.BorderColor3 = Color3.new()
    outer.Size = UDim2.new(0, 260, 0, 301)
    outer.ZIndex = 100
    outer.Parent = ScreenGui

    inner = Instance.new("Frame")
    inner.Name = "Inner"
    inner.BackgroundColor3 = Library.MainColor
    inner.BorderMode = Enum.BorderMode.Inset
    inner.BorderColor3 = Library.OutlineColor
    inner.Size = UDim2.new(1, 0, 1, 0)
    inner.Parent = outer

    local titleLabel = Instance.new("TextLabel")
    titleLabel.Name = "Title"
    titleLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    titleLabel.TextColor3 = Library.AccentColor
    titleLabel.Text = "Animation Visualizer"
    titleLabel.BackgroundTransparency = 1
    titleLabel.Position = UDim2.new(0, 5, 0, 5)
    titleLabel.TextXAlignment = Enum.TextXAlignment.Left
    titleLabel.TextSize = 17
    titleLabel.Size = UDim2.new(1, 0, 0, 20)
    titleLabel.Parent = inner

    local color = Instance.new("Frame")
    color.Name = "Color"
    color.BackgroundColor3 = Library.AccentColor
    color.BorderSizePixel = 0
    color.Size = UDim2.new(1, 0, 0, 2)
    color.Parent = inner

    viewportFrame = Instance.new("ViewportFrame")
    viewportFrame.Name = "ViewportFrame"
    viewportFrame.Visible = false
    viewportFrame.BorderMode = Enum.BorderMode.Inset
    viewportFrame.LightColor = Color3.new(0.549, 0.525, 0.435)
    viewportFrame.Ambient = Color3.new(0.318, 0.318, 0.318)
    viewportFrame.Position = UDim2.new(0, 4, 0, 26)
    viewportFrame.BackgroundColor3 = Library.MainColor
    viewportFrame.BorderColor3 = Color3.new()
    viewportFrame.Size = UDim2.new(1, -8, 0, 195)
    viewportFrame.Parent = inner

    worldModel = Instance.new("WorldModel", viewportFrame)

    camera = Instance.new("Camera", viewportFrame)
    camera.CameraType = Enum.CameraType.Scriptable
    camera.FieldOfView = 70
    viewportFrame.CurrentCamera = camera

    speedText = Instance.new("TextLabel")
    speedText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    speedText.TextColor3 = Library.FontColor
    speedText.Text = "Speed (1.00x)"
    speedText.BackgroundTransparency = 1
    speedText.TextSize = 12
    speedText.Size = UDim2.new(0, 82, 0, 20)
    speedText.ZIndex = 19
    speedText.Parent = viewportFrame

    noViewportFrame = Instance.new("Frame")
    noViewportFrame.Name = "NoViewportFrame"
    noViewportFrame.BackgroundColor3 = Library.MainColor
    noViewportFrame.Position = UDim2.new(0, 4, 0, 26)
    noViewportFrame.BorderColor3 = Color3.new()
    noViewportFrame.BorderMode = Enum.BorderMode.Inset
    noViewportFrame.Size = UDim2.new(1, -8, 0, 195)
    noViewportFrame.Parent = inner

    textLabel = Instance.new("TextLabel")
    textLabel.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    textLabel.TextColor3 = Library.FontColor
    textLabel.Text = "Waiting For Animation ID"
    textLabel.BackgroundTransparency = 1
    textLabel.Position = UDim2.new(0, 0, 0, 0)
    textLabel.TextWrapped = true
    textLabel.TextSize = 14
    textLabel.Size = UDim2.new(1, 0, 1, 0)
    textLabel.TextXAlignment = Enum.TextXAlignment.Center
    textLabel.TextYAlignment = Enum.TextYAlignment.Center
    textLabel.Parent = noViewportFrame

    animationTextbox = Instance.new("TextBox")
    animationTextbox.Name = "AnimationTextbox"
    animationTextbox.TextColor3 = Library.FontColor
    animationTextbox.PlaceholderText = "rbxassetid://0"
    animationTextbox.Text = ""
    animationTextbox.BackgroundColor3 = Library.MainColor
    animationTextbox.Position = UDim2.new(0, 6, 0, 228)
    animationTextbox.BorderColor3 = Color3.new()
    animationTextbox.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    animationTextbox.TextSize = 14
    animationTextbox.Size = UDim2.new(1, -12, 0, 18)
    animationTextbox.ClipsDescendants = true
    animationTextbox.TextTruncate = Enum.TextTruncate.AtEnd
    animationTextbox.ClearTextOnFocus = false
    animationTextbox.Parent = inner

    frameBackwards = Instance.new("TextButton")
    frameBackwards.Name = "FrameBackwards"
    frameBackwards.Text = ""
    frameBackwards.Position = UDim2.new(0, 6, 0, 252)
    frameBackwards.BackgroundColor3 = Library.MainColor
    frameBackwards.BorderColor3 = Color3.new()
    frameBackwards.Size = UDim2.new(0, 70, 0, 20)
    frameBackwards.Parent = inner

    local icon = Instance.new("ImageLabel")
    icon.Image = "rbxassetid://10734961526"
    icon.BackgroundTransparency = 1
    icon.Position = UDim2.new(0.5, -8, 0.5, -8)
    icon.Size = UDim2.new(0, 16, 0, 16)
    icon.ImageColor3 = Library.FontColor
    icon.Parent = frameBackwards

    playStop = Instance.new("TextButton")
    playStop.Name = "PlayStop"
    playStop.Text = ""
    playStop.Position = UDim2.new(0, 84, 0, 252)
    playStop.BackgroundColor3 = Library.MainColor
    playStop.BorderColor3 = Color3.new()
    playStop.Size = UDim2.new(0, 91, 0, 20)
    playStop.Parent = inner

    iconTwo = Instance.new("ImageLabel")
    iconTwo.Image = "rbxassetid://10734919336"
    iconTwo.BackgroundTransparency = 1
    iconTwo.Position = UDim2.new(0.5, -8, 0.5, -8)
    iconTwo.Size = UDim2.new(0, 16, 0, 16)
    iconTwo.ImageColor3 = Library.FontColor
    iconTwo.Parent = playStop

    frameForwards = Instance.new("TextButton")
    frameForwards.Name = "FrameForwards"
    frameForwards.Text = ""
    frameForwards.Position = UDim2.new(0, 183, 0, 252)
    frameForwards.BackgroundColor3 = Library.MainColor
    frameForwards.BorderColor3 = Color3.new()
    frameForwards.Size = UDim2.new(0, 70, 0, 20)
    frameForwards.Parent = inner

    local iconThree = Instance.new("ImageLabel")
    iconThree.Image = "rbxassetid://10734961809"
    iconThree.BackgroundTransparency = 1
    iconThree.Position = UDim2.new(0.5, -8, 0.5, -8)
    iconThree.Size = UDim2.new(0, 16, 0, 16)
    iconThree.ImageColor3 = Library.FontColor
    iconThree.Parent = frameForwards

    sliderOuter = Instance.new("Frame")
    sliderOuter.Name = "SliderOuter"
    sliderOuter.BackgroundColor3 = Color3.new(1, 1, 1)
    sliderOuter.Position = UDim2.new(0, 6, 0, 278)
    sliderOuter.BorderColor3 = Color3.new()
    sliderOuter.BorderSizePixel = 0
    sliderOuter.Size = UDim2.new(1, -12, 0, 15)
    sliderOuter.Parent = inner

    sliderInner = Instance.new("Frame")
    sliderInner.Name = "SliderInner"
    sliderInner.BorderColor3 = Color3.new()
    sliderInner.BackgroundColor3 = Library.MainColor
    sliderInner.Size = UDim2.new(1, 0, 1, 0)
    sliderInner.Parent = sliderOuter

    sliderFill = Instance.new("Frame")
    sliderFill.Name = "SliderFill"
    sliderFill.BorderMode = Enum.BorderMode.Inset
    sliderFill.BorderColor3 = Library.AccentColorDark
    sliderFill.BackgroundColor3 = Library.AccentColor
    sliderFill.Size = UDim2.new(0, 1, 1, 0)
    sliderFill.ZIndex = 10
    sliderFill.Parent = sliderOuter

    hideBorderRight = Instance.new("Frame")
    hideBorderRight.BackgroundColor3 = Library.AccentColor
    hideBorderRight.Position = UDim2.new(1, 0, 0, 0)
    hideBorderRight.BorderSizePixel = 0
    hideBorderRight.Size = UDim2.new(0, 1, 1, 0)
    hideBorderRight.Visible = false
    hideBorderRight.Parent = sliderFill

    sliderText = Instance.new("TextLabel")
    sliderText.FontFace = Font.new("rbxasset://fonts/families/RobotoMono.json")
    sliderText.TextColor3 = Library.FontColor
    sliderText.Text = "0.000 / ???"
    sliderText.BackgroundTransparency = 1
    sliderText.TextSize = 12
    sliderText.ZIndex = 12
    sliderText.Size = UDim2.new(1, 0, 1, 0)
    sliderText.Parent = sliderOuter

    -- Make draggable
    Library:MakeDraggable(outer)

    -- Register colors
    Library:AddToRegistry(color, { BackgroundColor3 = "AccentColor" }, true)
    Library:AddToRegistry(titleLabel, { TextColor3 = "AccentColor" }, true)
    Library:AddToRegistry(inner, { BackgroundColor3 = "MainColor", BorderColor3 = "OutlineColor" }, true)
    Library:AddToRegistry(viewportFrame, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(noViewportFrame, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(textLabel, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(animationTextbox, { BackgroundColor3 = "MainColor", TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(frameBackwards, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(playStop, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(frameForwards, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(icon, { ImageColor3 = "FontColor" }, true)
    Library:AddToRegistry(iconTwo, { ImageColor3 = "FontColor" }, true)
    Library:AddToRegistry(iconThree, { ImageColor3 = "FontColor" }, true)
    Library:AddToRegistry(sliderInner, { BackgroundColor3 = "MainColor" }, true)
    Library:AddToRegistry(sliderFill, { BackgroundColor3 = "AccentColor", BorderColor3 = "AccentColorDark" }, true)
    Library:AddToRegistry(hideBorderRight, { BackgroundColor3 = "AccentColor" }, true)
    Library:AddToRegistry(sliderText, { TextColor3 = "FontColor" }, true)
    Library:AddToRegistry(speedText, { TextColor3 = "FontColor" }, true)

    -- Connect events
    table.insert(connections, animationTextbox.FocusLost:Connect(onIdFocusLost))
    table.insert(connections, RunService.RenderStepped:Connect(onPlaybackLoop))
    table.insert(connections, playStop.MouseButton1Click:Connect(togglePlayStop))
    table.insert(connections, frameBackwards.MouseButton1Click:Connect(onFrameBackwards))
    table.insert(connections, frameForwards.MouseButton1Click:Connect(onFrameForwards))
    table.insert(connections, sliderOuter.InputBegan:Connect(onSliderInputBegan))
    table.insert(connections, outer.InputBegan:Connect(outerFrameInputBegan))

    -- Store reference in Library
    Library.AnimationVisualizerFrame = outer

    -- Show intro message
    AnimationVisualizer.message("Enter Animation ID\nPress Enter to load")
end

function AnimationVisualizer.detach()
    cleanConnections()
    if ScreenGui then
        ScreenGui:Destroy()
    end
end

return AnimationVisualizer
