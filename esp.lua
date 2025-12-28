-- ESP Module Reconstructed
-- With font selection, customizable colors, and toggle options

local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")

-- Constants
local DEFAULT_FONT = 3 -- Drawing.Font: 0=UI, 1=System, 2=Plex, 3=Monospace (Code)
local DEFAULT_TEXT_SIZE = 13
local DEFAULT_MAX_DISTANCE = 1000
local DEFAULT_PROXIMITY_DISTANCE = 100
local DEFAULT_ARROW_SIZE = 20
local DEBUG_THROTTLE_TIME = 5
local HEALTH_BAR_OFFSET = 7.4

-- Font map for dropdown
local FONT_MAP = {
    ["UI"] = 0,
    ["System"] = 1,
    ["Plex"] = 2,
    ["Monospace"] = 3,
}

local ALLY_COLOR = Color3.fromRGB(0, 255, 0)
local ENEMY_COLOR = Color3.fromRGB(255, 0, 0)
local WHITE_COLOR = Color3.fromRGB(255, 255, 255)
local HEALTH_BG_COLOR = Color3.fromRGB(192, 57, 43)
local HEALTH_FG_COLOR = Color3.fromRGB(39, 174, 96)
local POSTURE_COLOR = Color3.fromRGB(255, 165, 0) -- Orange
local POSTURE_BG_COLOR = Color3.fromRGB(100, 65, 0) -- Dark orange
local LIFEFORCE_COLOR = Color3.fromRGB(139, 0, 0) -- Dark red (blood)
local LIFEFORCE_BG_COLOR = Color3.fromRGB(60, 0, 0) -- Very dark red

-- Cached functions
local worldToViewportPoint = clonefunction(Instance.new("Camera").WorldToViewportPoint)
local vectorToWorldSpace = CFrame.new().VectorToWorldSpace

local floor = math.floor
local rad = math.rad
local cos = math.cos
local sin = math.sin
local atan2 = math.atan2

local RAD_45 = rad(45)

-- Settings table (PascalCase for table)
local Settings = {
    enabled = false,
    showTeam = true,
    useTeamColors = true,
    allyColor = ALLY_COLOR,
    enemyColor = ENEMY_COLOR,
    nameColor = WHITE_COLOR, -- New: name/text color
    maxDistance = DEFAULT_MAX_DISTANCE,
    showBoxes = true,
    showTracers = false,
    unlockTracers = false,
    showHealthBar = true,
    showPostureBar = true,
    showLifeforceBar = true,
    showLevel = true,
    showName = true, -- New: toggle for name
    showHealth = true, -- New: toggle for health display
    showHealthPercent = true, -- New: toggle for health percent
    showDistance = true, -- New: toggle for distance
    showProximityArrows = false,
    maxProximityDistance = DEFAULT_PROXIMITY_DISTANCE,
    textSize = DEFAULT_TEXT_SIZE,
    font = DEFAULT_FONT,
    fontName = "Monospace", -- New: font name for dropdown
    arrowSize = DEFAULT_ARROW_SIZE,
    debugMode = false
}

-- Private state
local uniqueId = HttpService:GenerateGUID(false)
local debugThrottle = {}
local instances = {}
local pluginData = {}

-- Offset vectors (calculated per frame)
local offsetTop, offsetBottom, offsetTopLeft, offsetBottomRight
local offsetHealthTop, offsetHealthBottom, offsetHealthValueTop, offsetHealthValueBottom

local function debugLog(message, ...)
    if not Settings.debugMode then return end
    
    local key = message .. table.concat({...}, "_")
    local now = tick()
    
    if debugThrottle[key] and (now - debugThrottle[key]) < DEBUG_THROTTLE_TIME then
        return
    end
    
    print("[ESP Debug]:", message, ...)
    debugThrottle[key] = now
end

-- EntityESP Class (PascalCase for class table)
local EntityESP = {}
EntityESP.__index = EntityESP
EntityESP.ClassName = "EntityESP"
EntityESP.Settings = Settings
EntityESP.FontMap = FONT_MAP -- Export for UI

local idCounter = 0

function EntityESP.new(player)
    idCounter = idCounter + 1
    
    local self = setmetatable({}, EntityESP)
    
    self.id = idCounter
    self.player = player
    self.playerName = player.Name
    self.visible = false
    
    debugLog("Creating ESP for player:", player.Name)
    
    -- Triangle (proximity arrow)
    self.triangle = Drawing.new("Triangle")
    self.triangle.Visible = false
    self.triangle.Thickness = 0
    self.triangle.Color = WHITE_COLOR
    self.triangle.Filled = true
    
    -- Label (using monospace/code font for clean look)
    self.label = Drawing.new("Text")
    self.label.Visible = false
    self.label.Center = true
    self.label.Outline = true
    self.label.Text = ""
    self.label.Size = Settings.textSize
    self.label.Color = WHITE_COLOR
    self.label.Font = Settings.font
    
    -- Box
    self.box = Drawing.new("Quad")
    self.box.Visible = false
    self.box.Thickness = 1
    self.box.Filled = false
    self.box.Color = WHITE_COLOR
    
    -- Health bar background
    self.healthBar = Drawing.new("Quad")
    self.healthBar.Visible = false
    self.healthBar.Thickness = 1
    self.healthBar.Filled = false
    self.healthBar.Color = WHITE_COLOR
    
    -- Health bar value
    self.healthBarValue = Drawing.new("Quad")
    self.healthBarValue.Visible = false
    self.healthBarValue.Thickness = 1
    self.healthBarValue.Filled = true
    self.healthBarValue.Color = ALLY_COLOR
    
    -- Tracer line
    self.line = Drawing.new("Line")
    self.line.Visible = false
    self.line.Color = WHITE_COLOR
    
    -- Posture bar background
    self.postureBar = Drawing.new("Quad")
    self.postureBar.Visible = false
    self.postureBar.Thickness = 1
    self.postureBar.Filled = false
    self.postureBar.Color = WHITE_COLOR
    
    -- Posture bar value
    self.postureBarValue = Drawing.new("Quad")
    self.postureBarValue.Visible = false
    self.postureBarValue.Thickness = 1
    self.postureBarValue.Filled = true
    self.postureBarValue.Color = POSTURE_COLOR
    
    -- Lifeforce bar background
    self.lifeforceBar = Drawing.new("Quad")
    self.lifeforceBar.Visible = false
    self.lifeforceBar.Thickness = 1
    self.lifeforceBar.Filled = false
    self.lifeforceBar.Color = WHITE_COLOR
    
    -- Lifeforce bar value
    self.lifeforceBarValue = Drawing.new("Quad")
    self.lifeforceBarValue.Visible = false
    self.lifeforceBarValue.Thickness = 1
    self.lifeforceBarValue.Filled = true
    self.lifeforceBarValue.Color = LIFEFORCE_COLOR
    
    debugLog("ESP created for player:", player.Name)
    
    return self
end

function EntityESP:getPlugin()
    return pluginData
end

function EntityESP:convertVector(x, y, z)
    return vectorToWorldSpace(self.cameraCFrame, Vector3.new(x, y, z))
end

function EntityESP:getTrianglePoints(position, angle)
    local cosAngle = cos(angle)
    local sinAngle = sin(angle)
    
    local x, y = position.X, position.Y
    local size = Settings.arrowSize
    
    local p1x = x + size * cosAngle
    local p1y = y + size * sinAngle
    
    local p2x = x - size * cosAngle - size * sinAngle
    local p2y = y - size * sinAngle + size * cosAngle
    
    local p3x = p1x - size * sinAngle
    local p3y = p1y + size * cosAngle
    
    return Vector2.new(floor(p2x), floor(p2y)),
           Vector2.new(floor(p3x), floor(p3y)),
           Vector2.new(floor(p3x), floor(p3y))
end

function EntityESP:setFont(fontNameOrIndex)
    if type(fontNameOrIndex) == "string" then
        Settings.fontName = fontNameOrIndex
        Settings.font = FONT_MAP[fontNameOrIndex] or DEFAULT_FONT
    else
        Settings.font = fontNameOrIndex or DEFAULT_FONT
    end
end

function EntityESP:setTextSize(size)
    Settings.textSize = size or DEFAULT_TEXT_SIZE
end

function EntityESP:hide(keepTriangle)
    debugLog("Hiding ESP for player:", self.playerName)
    
    if not keepTriangle and self.triangle then
        self.triangle.Visible = false
    end
    
    if not self.visible then return end
    
    self.visible = false
    if self.label then self.label.Visible = false end
    if self.box then self.box.Visible = false end
    if self.line then self.line.Visible = false end
    if self.healthBar then self.healthBar.Visible = false end
    if self.healthBarValue then self.healthBarValue.Visible = false end
    if self.postureBar then self.postureBar.Visible = false end
    if self.postureBarValue then self.postureBarValue.Visible = false end
    if self.lifeforceBar then self.lifeforceBar.Visible = false end
    if self.lifeforceBarValue then self.lifeforceBarValue.Visible = false end
end

function EntityESP:destroy()
    if not self.label then return end
    
    debugLog("Destroying ESP for player:", self.playerName)
    
    self.label:Destroy()
    self.box:Destroy()
    self.line:Destroy()
    self.healthBar:Destroy()
    self.healthBarValue:Destroy()
    self.postureBar:Destroy()
    self.postureBarValue:Destroy()
    self.lifeforceBar:Destroy()
    self.lifeforceBarValue:Destroy()
    self.triangle:Destroy()
    
    self.label = nil
end

function EntityESP:update()
    -- Check if ESP is enabled globally
    if not Settings.enabled then
        return self:hide()
    end
    
    local camera = workspace.CurrentCamera
    if not camera then
        return self:hide()
    end
    
    local character = self.player.Character
    if not character then
        return self:hide()
    end
    
    local humanoid = character:FindFirstChild("Humanoid")
    local rootPart = character:FindFirstChild("HumanoidRootPart")
    
    if not rootPart or not humanoid then
        return self:hide()
    end
    
    local maxHealth = humanoid.MaxHealth
    local health = humanoid.Health
    local healthPercent = (health / maxHealth) * 100
    local position = rootPart.Position
    
    -- Get the Live folder for this player (workspace.Live.PlayerName)
    local liveFolder = workspace:FindFirstChild("Live")
    local charFolder = liveFolder and liveFolder:FindFirstChild(self.playerName)
    
    -- Get Posture values from workspace.Live.PlayerName.Posture
    local posture, maxPosture, posturePercent = 0, 100, 0
    if charFolder then
        local postureObj = charFolder:FindFirstChild("Posture")
        if postureObj then
            pcall(function()
                posture = postureObj.Value or 0
                maxPosture = postureObj.MaxValue or postureObj.Max or 100
                posturePercent = maxPosture > 0 and (posture / maxPosture) * 100 or 0
            end)
        end
    end
    
    -- Get Lifeforce values (Blood) from workspace.Live.PlayerName.Lifeforce
    local lifeforce, maxLifeforce, lifeforcePercent = 0, 100, 0
    if charFolder then
        local lifeforceObj = charFolder:FindFirstChild("Lifeforce")
        if lifeforceObj then
            pcall(function()
                lifeforce = lifeforceObj.Value or 0
                maxLifeforce = lifeforceObj.MaxValue or lifeforceObj.Max or 100
                lifeforcePercent = maxLifeforce > 0 and (lifeforce / maxLifeforce) * 100 or 0
            end)
        end
    end
    
    -- Get Level from Live folder attributes
    local level = 0
    if charFolder then
        level = charFolder:GetAttribute("LVL") or 0
    end
    
    local screenPos, onScreen = worldToViewportPoint(camera, position + offsetTop)
    
    -- Team check
    local localPlayer = Players.LocalPlayer
    local isEnemy = self.player.Team ~= localPlayer.Team
    
    if not isEnemy and not Settings.showTeam then
        return self:hide()
    end
    
    -- Distance check
    local distance = (position - self.cameraPosition).Magnitude
    
    if distance > Settings.maxDistance then
        return self:hide()
    end
    
    -- Determine colors
    local color
    if Settings.useTeamColors then
        color = isEnemy and Settings.enemyColor or Settings.allyColor
    else
        color = Settings.enemyColor
    end
    
    -- Name color (use nameColor setting or fall back to team color)
    local textColor = Settings.nameColor or color
    
    -- Proximity arrows
    if Settings.showProximityArrows and not onScreen and distance < Settings.maxProximityDistance then
        local screenVec = Vector2.new(screenPos.X, screenPos.Y)
        local direction
        
        if screenPos.Z < 0 then
            direction = -(screenVec - self.viewportCenter).Unit
        else
            direction = (screenVec - self.viewportCenter).Unit
        end
        
        local angle = -atan2(direction.X, direction.Y) - RAD_45
        local arrowPos = self.viewportCenter + direction * Settings.arrowSize
        
        local pointA, pointB, pointC = self:getTrianglePoints(arrowPos, angle)
        
        self.triangle.PointA = pointA
        self.triangle.PointB = pointB
        self.triangle.PointC = pointC
        self.triangle.Color = color
        self.triangle.Visible = true
    else
        self.triangle.Visible = false
    end
    
    if not onScreen then
        return self:hide(true)
    end
    
    self.visible = true
    
    -- Plugin data
    local plugin = self:getPlugin()
    
    -- Build label text based on settings
    local labelParts = {}
    
    -- Name
    if Settings.showName then
        local nameText = plugin.playerName or self.playerName
        if Settings.showLevel then
            nameText = nameText .. string.format(" [Lv.%d]", level)
        end
        table.insert(labelParts, nameText)
    end
    
    -- Distance
    if Settings.showDistance then
        table.insert(labelParts, string.format("[%d studs]", floor(distance)))
    end
    
    -- Health
    if Settings.showHealth then
        local healthText = string.format("HP: %d/%d", floor(health), floor(maxHealth))
        if Settings.showHealthPercent then
            healthText = healthText .. string.format(" (%d%%)", floor(healthPercent))
        end
        table.insert(labelParts, healthText)
    elseif Settings.showHealthPercent then
        table.insert(labelParts, string.format("HP: %d%%", floor(healthPercent)))
    end
    
    -- Plugin text
    if plugin.text and plugin.text ~= "" then
        table.insert(labelParts, plugin.text)
    end
    
    local labelText = table.concat(labelParts, "\n")
    
    -- Update label
    if #labelParts > 0 then
        self.label.Visible = true
        self.label.Position = Vector2.new(screenPos.X, screenPos.Y - self.label.TextBounds.Y)
        self.label.Text = labelText
        self.label.Color = textColor
        self.label.Size = Settings.textSize
        self.label.Font = Settings.font
    else
        self.label.Visible = false
    end
    
    -- Update box
    if Settings.showBoxes then
        local topLeft = worldToViewportPoint(camera, position + offsetTopLeft)
        local bottomRight = worldToViewportPoint(camera, position + offsetBottomRight)
        
        self.box.Visible = true
        self.box.PointA = Vector2.new(topLeft.X, topLeft.Y)
        self.box.PointB = Vector2.new(bottomRight.X, topLeft.Y)
        self.box.PointC = Vector2.new(bottomRight.X, bottomRight.Y)
        self.box.PointD = Vector2.new(topLeft.X, bottomRight.Y)
        self.box.Color = color
    else
        self.box.Visible = false
    end
    
    -- Update tracer
    if Settings.showTracers then
        local tracerPos = worldToViewportPoint(camera, position + offsetBottom)
        
        local fromPos = self.viewportSize
        if Settings.unlockTracers then
            fromPos = UserInputService:GetMouseLocation()
        end
        
        self.line.Visible = true
        self.line.From = fromPos
        self.line.To = Vector2.new(tracerPos.X, tracerPos.Y)
        self.line.Color = color
    else
        self.line.Visible = false
    end
    
    -- Update health bar
    if Settings.showHealthBar then
        local healthOffset = (1 - healthPercent / 100) * HEALTH_BAR_OFFSET
        
        local hbTopLeft = worldToViewportPoint(camera, position + offsetHealthTop)
        local hbBottomRight = worldToViewportPoint(camera, position + offsetHealthBottom)
        
        local valueTopLeft = worldToViewportPoint(camera, position + offsetHealthValueTop - self:convertVector(0, healthOffset, 0))
        local valueBottomRight = worldToViewportPoint(camera, position - offsetHealthValueBottom)
        
        self.healthBar.Visible = true
        self.healthBar.Color = color -- Outline uses team color
        self.healthBar.PointA = Vector2.new(hbTopLeft.X, hbTopLeft.Y)
        self.healthBar.PointB = Vector2.new(hbBottomRight.X, hbTopLeft.Y)
        self.healthBar.PointC = Vector2.new(hbBottomRight.X, hbBottomRight.Y)
        self.healthBar.PointD = Vector2.new(hbTopLeft.X, hbBottomRight.Y)
        
        self.healthBarValue.Visible = true
        self.healthBarValue.Color = HEALTH_BG_COLOR:Lerp(HEALTH_FG_COLOR, healthPercent / 100)
        self.healthBarValue.PointA = Vector2.new(valueTopLeft.X, valueTopLeft.Y)
        self.healthBarValue.PointB = Vector2.new(valueBottomRight.X, valueTopLeft.Y)
        self.healthBarValue.PointC = Vector2.new(valueBottomRight.X, valueBottomRight.Y)
        self.healthBarValue.PointD = Vector2.new(valueTopLeft.X, valueBottomRight.Y)
    else
        self.healthBar.Visible = false
        self.healthBarValue.Visible = false
    end
    
    -- Update posture bar (to the right of character)
    if Settings.showPostureBar and maxPosture > 0 then
        local postureOffset = (1 - posturePercent / 100) * HEALTH_BAR_OFFSET
        
        local pbTopLeft = worldToViewportPoint(camera, position + self:convertVector(3, 3, 0))
        local pbBottomRight = worldToViewportPoint(camera, position + self:convertVector(3.5, -4.5, 0))
        
        local pValueTopLeft = worldToViewportPoint(camera, position + self:convertVector(3.05, 2.95, 0) - self:convertVector(0, postureOffset, 0))
        local pValueBottomRight = worldToViewportPoint(camera, position + self:convertVector(3.45, -4.45, 0))
        
        self.postureBar.Visible = true
        self.postureBar.Color = color -- Outline uses team color now
        self.postureBar.PointA = Vector2.new(pbTopLeft.X, pbTopLeft.Y)
        self.postureBar.PointB = Vector2.new(pbBottomRight.X, pbTopLeft.Y)
        self.postureBar.PointC = Vector2.new(pbBottomRight.X, pbBottomRight.Y)
        self.postureBar.PointD = Vector2.new(pbTopLeft.X, pbBottomRight.Y)
        
        self.postureBarValue.Visible = true
        self.postureBarValue.Color = POSTURE_BG_COLOR:Lerp(POSTURE_COLOR, posturePercent / 100)
        self.postureBarValue.PointA = Vector2.new(pValueTopLeft.X, pValueTopLeft.Y)
        self.postureBarValue.PointB = Vector2.new(pValueBottomRight.X, pValueTopLeft.Y)
        self.postureBarValue.PointC = Vector2.new(pValueBottomRight.X, pValueBottomRight.Y)
        self.postureBarValue.PointD = Vector2.new(pValueTopLeft.X, pValueBottomRight.Y)
    else
        self.postureBar.Visible = false
        self.postureBarValue.Visible = false
    end
    
    -- Update lifeforce bar (further right)
    if Settings.showLifeforceBar and maxLifeforce > 0 then
        local lifeforceOffset = (1 - lifeforcePercent / 100) * HEALTH_BAR_OFFSET
        
        local lfTopLeft = worldToViewportPoint(camera, position + self:convertVector(4, 3, 0))
        local lfBottomRight = worldToViewportPoint(camera, position + self:convertVector(4.5, -4.5, 0))
        
        local lfValueTopLeft = worldToViewportPoint(camera, position + self:convertVector(4.05, 2.95, 0) - self:convertVector(0, lifeforceOffset, 0))
        local lfValueBottomRight = worldToViewportPoint(camera, position + self:convertVector(4.45, -4.45, 0))
        
        self.lifeforceBar.Visible = true
        self.lifeforceBar.Color = color -- Outline uses team color now
        self.lifeforceBar.PointA = Vector2.new(lfTopLeft.X, lfTopLeft.Y)
        self.lifeforceBar.PointB = Vector2.new(lfBottomRight.X, lfTopLeft.Y)
        self.lifeforceBar.PointC = Vector2.new(lfBottomRight.X, lfBottomRight.Y)
        self.lifeforceBar.PointD = Vector2.new(lfTopLeft.X, lfBottomRight.Y)
        
        self.lifeforceBarValue.Visible = true
        self.lifeforceBarValue.Color = LIFEFORCE_BG_COLOR:Lerp(LIFEFORCE_COLOR, lifeforcePercent / 100)
        self.lifeforceBarValue.PointA = Vector2.new(lfValueTopLeft.X, lfValueTopLeft.Y)
        self.lifeforceBarValue.PointB = Vector2.new(lfValueBottomRight.X, lfValueTopLeft.Y)
        self.lifeforceBarValue.PointC = Vector2.new(lfValueBottomRight.X, lfValueBottomRight.Y)
        self.lifeforceBarValue.PointD = Vector2.new(lfValueTopLeft.X, lfValueBottomRight.Y)
    else
        self.lifeforceBar.Visible = false
        self.lifeforceBarValue.Visible = false
    end
end

-- Camera update function
local function updateCamera()
    local camera = workspace.CurrentCamera
    if not camera then return end
    
    EntityESP.camera = camera
    EntityESP.cameraCFrame = camera.CFrame
    EntityESP.cameraPosition = camera.CFrame.Position
    
    local viewportSize = camera.ViewportSize
    EntityESP.viewportSize = Vector2.new(viewportSize.X / 2, viewportSize.Y - 10)
    EntityESP.viewportCenter = viewportSize / 2
    
    -- Calculate offset vectors
    offsetTop = EntityESP:convertVector(0, 3.25, 0)
    offsetBottom = EntityESP:convertVector(0, -4.5, 0)
    offsetTopLeft = EntityESP:convertVector(2.5, 3, 0)
    offsetBottomRight = EntityESP:convertVector(-2.5, -4.5, 0)
    offsetHealthTop = EntityESP:convertVector(-3, 3, 0)
    offsetHealthBottom = EntityESP:convertVector(-3.5, -4.5, 0)
    offsetHealthValueTop = EntityESP:convertVector(-3.05, 2.95, 0)
    offsetHealthValueBottom = EntityESP:convertVector(3.45, 4.45, 0)
end

-- Update all instances
local function updateAll()
    for _, esp in pairs(instances) do
        esp:update()
    end
end

-- Player handlers
local function onPlayerAdded(player)
    if player == Players.LocalPlayer then return end
    instances[player] = EntityESP.new(player)
end

local function onPlayerRemoving(player)
    if instances[player] then
        instances[player]:destroy()
        instances[player] = nil
    end
end

-- Initialize
updateCamera()

for _, player in ipairs(Players:GetPlayers()) do
    onPlayerAdded(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
Players.PlayerRemoving:Connect(onPlayerRemoving)

RunService:BindToRenderStep(uniqueId, Enum.RenderPriority.Camera.Value, updateCamera)
RunService:BindToRenderStep(uniqueId .. "_update", Enum.RenderPriority.Camera.Value + 1, updateAll)

print("[dxe] ESP Module Loaded")

return EntityESP
