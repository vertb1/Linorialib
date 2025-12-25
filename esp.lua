-- ESP Module Reconstructed from MoonSec V3 Bytecode
-- Deobfuscated using tupsutumppu/MoonsecDeobfuscator

print("ESP Module Loaded")

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")

local worldToViewportPoint = clonefunction(Instance.new("Camera").WorldToViewportPoint)
local vectorToWorldSpace = CFrame.new().VectorToWorldSpace
local getMouseLocation = clonefunction(UserInputService.GetMouseLocation)
local uniqueId = HttpService:GenerateGUID(false)

local Color3_new = Color3.new
local Color3_fromRGB = Color3.fromRGB
local Color3_lerp = Color3.new().lerp

local Vector3_new = Vector3.new
local Vector2_new = Vector2.new
local math_floor = math.floor
local math_rad = math.rad
local math_cos = math.cos
local math_sin = math.sin
local math_atan2 = math.atan2

-- Settings
local settings = {
    showTeam = true,
    allyColor = Color3.fromRGB(0, 255, 0),
    enemyColor = Color3.fromRGB(255, 0, 0),
    maxEspDistance = 1000,
    toggleBoxes = true,
    toggleTracers = false,
    unlockTracers = false,
    showHealthBar = true,
    proximityArrows = false,
    maxProximityArrowDistance = 100,
    textSize = 13,
    proximityArrowsSize = 20,
    debugMode = false
}

-- Cache settings
local showTeam = settings.showTeam
local allyColor = settings.allyColor
local enemyColor = settings.enemyColor
local maxEspDistance = settings.maxEspDistance
local toggleBoxes = settings.toggleBoxes
local toggleTracers = settings.toggleTracers
local unlockTracers = settings.unlockTracers
local showHealthBar = settings.showHealthBar
local proximityArrows = settings.proximityArrows
local maxProximityArrowDistance = settings.maxProximityArrowDistance
local debugMode = settings.debugMode
local proximityArrowsSize = settings.proximityArrowsSize

-- Colors
local healthBarBgColor = Color3.fromRGB(192, 57, 43)
local healthBarFgColor = Color3.fromRGB(39, 174, 96)
local rad45 = math_rad(45)

-- Debug throttle table
local debugThrottle = {}

-- ESP instances storage (declared early to avoid nil reference)
local espInstances = {}

-- Debug function
local function debugLog(msg, ...)
    if not settings.debugMode then return end
    
    local key = msg .. table.concat({...}, "_")
    local now = tick()
    
    if debugThrottle[key] then
        if now - debugThrottle[key] < 5 then
            return
        end
    end
    
    print("[ESP Debug]:", msg, ...)
    debugThrottle[key] = now
end

-- ESP offset vectors (calculated per frame)
local offsetTop, offsetBottom, offsetTopLeft, offsetBottomRight
local offsetHealthTop, offsetHealthBottom, offsetHealthValueTop, offsetHealthValueBottom

-- Entity ESP Class
local entityESP = {}
entityESP.__index = entityESP
entityESP.__ClassName = "entityESP"
entityESP.id = 0

-- Plugin data storage
local pluginData = {}

function entityESP:Plugin()
    return pluginData
end

function entityESP:ConvertVector(...)
    return vectorToWorldSpace(self._cameraCFrame, Vector3_new(...))
end

function entityESP:GetOffsetTrianglePosition(pos, angle)
    local cosA = math_cos(angle)
    local sinA = math_sin(angle)
    
    local x = pos.X
    local y = pos.Y
    
    local size = proximityArrowsSize
    local halfSize = size
    local negSize = -size
    
    -- Calculate triangle points
    local p1x = x + halfSize * cosA
    local p1y = y + halfSize * sinA
    
    local p2x = x + negSize * cosA - halfSize * sinA
    local p2y = y + negSize * sinA + halfSize * cosA
    
    local p3x = p1x - halfSize * sinA
    local p3y = p1y + halfSize * cosA
    
    local p4x = p1x - halfSize * sinA
    local p4y = p1y + halfSize * cosA
    
    return Vector2_new(math_floor(p2x), math_floor(p2y)),
           Vector2_new(math_floor(p3x), math_floor(p3y)),
           Vector2_new(math_floor(p4x), math_floor(p4y))
end

function entityESP.new(player)
    print("Creating new ESP")
    debugLog("Creating new ESP for player:", player.Name)
    
    entityESP.id = entityESP.id + 1
    
    local self = setmetatable({}, entityESP)
    self._id = entityESP.id
    self._player = player
    self._playerName = player.Name
    
    debugLog("Initializing drawings for player:", player.Name)
    
    -- Triangle (proximity arrow)
    self._triangle = Drawing.new("Triangle")
    self._triangle.Visible = true
    self._triangle.Thickness = 0
    self._triangle.Color = Color3.fromRGB(255, 255, 255)
    self._triangle.Filled = true
    
    -- Label
    self._label = Drawing.new("Text")
    self._label.Visible = false
    self._label.Center = true
    self._label.Outline = true
    self._label.Text = ""
    self._label.Size = settings.textSize
    self._label.Color = Color3.fromRGB(255, 255, 255)
    
    -- Box
    self._box = Drawing.new("Quad")
    self._box.Visible = false
    self._box.Thickness = 1
    self._box.Filled = false
    self._box.Color = Color3.fromRGB(255, 255, 255)
    
    -- Health bar background
    self._healthBar = Drawing.new("Quad")
    self._healthBar.Visible = false
    self._healthBar.Thickness = 1
    self._healthBar.Filled = false
    self._healthBar.Color = Color3.fromRGB(255, 255, 255)
    
    -- Health bar value
    self._healthBarValue = Drawing.new("Quad")
    self._healthBarValue.Visible = false
    self._healthBarValue.Thickness = 1
    self._healthBarValue.Filled = true
    self._healthBarValue.Color = Color3.fromRGB(0, 255, 0)
    
    -- Tracer line
    self._line = Drawing.new("Line")
    self._line.Visible = false
    self._line.Color = Color3.fromRGB(255, 255, 255)
    
    self._labelObject = self._label
    
    debugLog("ESP created successfully for player:", player.Name)
    
    return self
end

function entityESP:SetFont(font)
    debugLog("Setting font for player:", self._playerName, "to:", font)
    self._label.Font = font
end

function entityESP:SetTextSize(size)
    debugLog("Setting text size for player:", self._playerName, "to:", size)
    self._label.Size = size
end

function entityESP:Hide(keepTriangle)
    debugLog("Hiding ESP elements for player:", self._playerName)
    
    if not keepTriangle then
        self._triangle.Visible = false
    end
    
    if not self._visible then return end
    
    self._visible = false
    self._label.Visible = false
    self._box.Visible = false
    self._line.Visible = false
    self._healthBar.Visible = false
    self._healthBarValue.Visible = false
end

function entityESP:Destroy()
    if not self._label then return end
    
    debugLog("Destroying ESP for player:", self._playerName)
    
    self._label:Destroy()
    self._box:Destroy()
    self._line:Destroy()
    self._healthBar:Destroy()
    self._healthBarValue:Destroy()
    self._triangle:Destroy()
end

function entityESP:Update()
    local camera = workspace.CurrentCamera
    
    if not camera then
        debugLog("Camera not found, hiding ESP")
        return self:Hide()
    end
    
    local player = self._player
    local character = player.Character
    
    if not character then
        debugLog("Character not found for player:", self._playerName)
        return self:Hide()
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not rootPart or not humanoid then
        debugLog("Missing humanoid or rootpart for player:", self._playerName)
        return self:Hide()
    end
    
    local maxHealth = humanoid.MaxHealth
    local health = humanoid.Health
    local healthPercent = (health / maxHealth) * 100
    local position = rootPart.Position
    
    -- World to screen
    local screenPos, onScreen = worldToViewportPoint(camera, position + offsetTop)
    
    local triangle = self._triangle
    
    -- Team check
    local playerTeam = player.Team
    local localTeam = game.Players.LocalPlayer.Team
    local isEnemy = playerTeam ~= localTeam
    
    if not isEnemy and not showTeam then
        return self:Hide()
    end
    
    -- Distance check
    local distance = (position - self._cameraPosition).Magnitude
    
    if distance > maxEspDistance then
        debugLog("Player", self._playerName, "is beyond maxEspDistance:", distance)
        return self:Hide()
    end
    
    -- Color selection
    local color = isEnemy and enemyColor or allyColor
    local showProximityArrow = false
    
    -- Proximity arrows
    if proximityArrows and not onScreen and distance < maxProximityArrowDistance then
        debugLog("Drawing proximity arrow for player:", self._playerName)
        
        local direction
        if screenPos.Z < 0 then
            local screenVec = Vector2.new(screenPos.X, screenPos.Y)
            direction = -(screenVec - self._viewportSizeCenter).Unit
        else
            local screenVec = Vector2.new(screenPos.X, screenPos.Y)
            direction = (screenVec - self._viewportSizeCenter).Unit
        end
        
        local angle = -math_atan2(direction.X, direction.Y) - rad45
        local arrowPos = self._viewportSizeCenter + direction * proximityArrowsSize
        
        local pointA, pointB, pointC = self:GetOffsetTrianglePosition(arrowPos, angle)
        
        triangle.PointA = pointA
        triangle.PointB = pointB
        triangle.PointC = pointC
        triangle.Color = color
        showProximityArrow = true
        triangle.Visible = showProximityArrow
    end
    
    -- Not visible on screen
    if not onScreen then
        debugLog("Player", self._playerName, "not visible on screen")
        return self:Hide(true)
    end
    
    self._visible = onScreen
    
    local label = self._label
    local box = self._box
    local line = self._line
    local healthBar = self._healthBar
    local healthBarValue = self._healthBarValue
    
    -- Plugin data
    local plugin = self:Plugin()
    
    -- Build label text
    local labelText = "[" .. (plugin.playerName or self._playerName) .. "] [" ..
        math_floor(distance) .. "]\n[" ..
        math_floor(health) .. "/" .. math_floor(maxHealth) .. "] [" ..
        math_floor(healthPercent) .. " %]" ..
        (plugin.text or "") .. " [" .. uniqueId .. "]"
    
    debugLog("Updating ESP elements for player:", self._playerName)
    
    -- Update label
    label.Visible = onScreen
    label.Position = Vector2_new(screenPos.X, screenPos.Y - label.TextBounds.Y)
    label.Text = labelText
    label.Color = color
    
    -- Update box
    if toggleBoxes then
        local topLeft = worldToViewportPoint(camera, position + offsetTopLeft)
        local bottomRight = worldToViewportPoint(camera, position + offsetBottomRight)
        
        local x1, y1 = topLeft.X, topLeft.Y
        local x2, y2 = bottomRight.X, bottomRight.Y
        
        box.Visible = onScreen
        box.PointA = Vector2_new(x1, y1)
        box.PointB = Vector2_new(x2, y1)
        box.PointC = Vector2_new(x2, y2)
        box.PointD = Vector2_new(x1, y2)
        box.Color = color
    else
        box.Visible = false
    end
    
    -- Update tracer
    if toggleTracers then
        local tracerPos = worldToViewportPoint(camera, position + offsetBottom)
        line.Visible = onScreen
        
        local fromPos
        if unlockTracers then
            fromPos = getMouseLocation(UserInputService)
        else
            fromPos = self._viewportSize
        end
        
        line.From = fromPos
        line.To = Vector2_new(tracerPos.X, tracerPos.Y)
        line.Color = color
    else
        line.Visible = false
    end
    
    -- Update health bar
    if showHealthBar then
        local healthOffset = (1 - healthPercent / 100) * 7.4
        
        local hbTopLeft = worldToViewportPoint(camera, position + offsetHealthTop)
        local hbBottomRight = worldToViewportPoint(camera, position + offsetHealthBottom)
        
        local hx1, hy1 = hbTopLeft.X, hbTopLeft.Y
        local hx2, hy2 = hbBottomRight.X, hbBottomRight.Y
        
        local valueTopLeft = worldToViewportPoint(camera, position + offsetHealthValueTop - self:ConvertVector(0, healthOffset, 0))
        local valueBottomRight = worldToViewportPoint(camera, position - offsetHealthValueBottom)
        
        local vx1, vy1 = valueTopLeft.X, valueTopLeft.Y
        local vx2, vy2 = valueBottomRight.X, valueBottomRight.Y
        
        healthBar.Visible = onScreen
        healthBar.Color = color
        healthBar.PointA = Vector2_new(hx1, hy1)
        healthBar.PointB = Vector2_new(hx2, hy1)
        healthBar.PointC = Vector2_new(hx2, hy2)
        healthBar.PointD = Vector2_new(hx1, hy2)
        
        healthBarValue.Visible = onScreen
        healthBarValue.Color = Color3_lerp(healthBarBgColor, healthBarFgColor, healthPercent / 100)
        healthBarValue.PointA = Vector2_new(vx1, vy1)
        healthBarValue.PointB = Vector2_new(vx2, vy1)
        healthBarValue.PointC = Vector2_new(vx2, vy2)
        healthBarValue.PointD = Vector2_new(vx1, vy2)
    else
        healthBar.Visible = false
        healthBarValue.Visible = false
    end
end

-- Initialize camera data
local function updateCameraData()
    local camera = workspace.CurrentCamera
    entityESP._camera = camera
    
    if not camera then
        debugLog("Camera not found in updateESP")
        return
    end
    
    entityESP._cameraCFrame = camera.CFrame
    entityESP._cameraPosition = entityESP._cameraCFrame.Position
    
    local viewportSize = camera.ViewportSize
    entityESP._viewportSize = Vector2_new(viewportSize.X / 2, viewportSize.Y - 10)
    entityESP._viewportSizeCenter = viewportSize / 2
    
    -- Update proximity arrow size
    proximityArrowsSize = settings.proximityArrowsSize
    
    -- Calculate offset vectors
    offsetTop = entityESP:ConvertVector(0, 3.25, 0)
    offsetBottom = entityESP:ConvertVector(0, -4.5, 0)
    offsetTopLeft = entityESP:ConvertVector(2.5, 3, 0)
    offsetBottomRight = entityESP:ConvertVector(-2.5, -4.5, 0)
    offsetHealthTop = entityESP:ConvertVector(-3, 3, 0)
    offsetHealthBottom = entityESP:ConvertVector(-3.5, -4.5, 0)
    offsetHealthValueTop = entityESP:ConvertVector(-3.05, 2.95, 0)
    offsetHealthValueBottom = entityESP:ConvertVector(3.45, 4.45, 0)
end

-- Update all ESPs
local function updateAllESP()
    for _, esp in pairs(espInstances) do
        esp:Update()
    end
end

-- Initialize
updateCameraData()

local Players = game:GetService("Players")

-- Create ESP for existing players
for _, player in ipairs(Players:GetPlayers()) do
    if player ~= Players.LocalPlayer then
        espInstances[player] = entityESP.new(player)
    end
end

-- Player added handler
Players.PlayerAdded:Connect(function(player)
    espInstances[player] = entityESP.new(player)
end)

-- Player removing handler
Players.PlayerRemoving:Connect(function(player)
    if espInstances[player] then
        espInstances[player]:Destroy()
        espInstances[player] = nil
    end
end)

-- Bind to render step
RunService:BindToRenderStep(uniqueId, Enum.RenderPriority.Camera.Value, updateCameraData)
RunService:BindToRenderStep(uniqueId .. "_update", Enum.RenderPriority.Camera.Value + 1, updateAllESP)

return entityESP
