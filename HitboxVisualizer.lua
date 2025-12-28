-- Hitbox Visualizer (Snapshot-based)
-- Creates hitbox visuals that stay at their spawn position (don't follow the entity)
-- Useful for visualizing attack ranges and parry windows

local HitboxVisualizer = {
    enabled = false,
    defaultDuration = 0.5, -- How long hitboxes stay visible
    defaultSize = Vector3.new(6, 6, 8), -- Default hitbox size
    defaultColor = Color3.fromRGB(255, 50, 50),
    defaultTransparency = 0.6,
    fadeOut = true, -- Fade out before disappearing
    maxHitboxes = 50, -- Max active hitboxes (cleanup old ones)
}

-- Services
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local RunService = game:GetService("RunService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

-- Storage
local hitboxFolder = nil
local activeHitboxes = {} -- { part, createTime, duration }
local hitboxCount = 0

-- Animation path for reference (game-specific)
local ANIMATION_PATH = "Assets.Animations"

---Ensure hitbox folder exists
---@return Folder
local function ensureFolder()
    if not hitboxFolder or not hitboxFolder.Parent then
        hitboxFolder = Instance.new("Folder")
        hitboxFolder.Name = "HitboxVisuals_Snapshot"
        hitboxFolder.Parent = Workspace
    end
    return hitboxFolder
end

---Get animations folder (for reference/lookup)
---@return Instance?
function HitboxVisualizer.getAnimationsFolder()
    local assets = ReplicatedStorage:FindFirstChild("Assets")
    if assets then
        return assets:FindFirstChild("Animations")
    end
    return nil
end

---Create a snapshot hitbox at a specific CFrame
---@param cframe CFrame The position/rotation of the hitbox
---@param size Vector3? Size of the hitbox (optional)
---@param color Color3? Color of the hitbox (optional)
---@param duration number? How long it stays visible (optional)
---@param transparency number? Transparency (optional)
---@return BasePart
function HitboxVisualizer.create(cframe, size, color, duration, transparency)
    size = size or HitboxVisualizer.defaultSize
    color = color or HitboxVisualizer.defaultColor
    duration = duration or HitboxVisualizer.defaultDuration
    transparency = transparency or HitboxVisualizer.defaultTransparency
    
    -- Cleanup old hitboxes if at max
    if hitboxCount >= HitboxVisualizer.maxHitboxes then
        HitboxVisualizer.cleanupOldest()
    end
    
    local hitbox = Instance.new("Part")
    hitbox.Name = "HB_Snapshot_" .. hitboxCount
    hitbox.Shape = Enum.PartType.Block
    hitbox.Size = size
    hitbox.CFrame = cframe
    hitbox.Color = color
    hitbox.Transparency = transparency
    hitbox.Material = Enum.Material.ForceField
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.CanQuery = false
    hitbox.CanTouch = false
    hitbox.CastShadow = false
    hitbox.Parent = ensureFolder()
    
    hitboxCount = hitboxCount + 1
    
    local data = {
        part = hitbox,
        createTime = os.clock(),
        duration = duration,
        originalTransparency = transparency,
    }
    table.insert(activeHitboxes, data)
    
    -- Fade out and destroy
    if HitboxVisualizer.fadeOut then
        local fadeTime = math.min(duration * 0.4, 0.3)
        local waitTime = duration - fadeTime
        
        task.delay(waitTime, function()
            if hitbox and hitbox.Parent then
                local tweenInfo = TweenInfo.new(fadeTime, Enum.EasingStyle.Linear)
                local tween = TweenService:Create(hitbox, tweenInfo, { Transparency = 1 })
                tween:Play()
                tween.Completed:Wait()
                if hitbox and hitbox.Parent then
                    hitbox:Destroy()
                end
            end
        end)
    else
        Debris:AddItem(hitbox, duration)
    end
    
    return hitbox
end

---Create hitbox in front of an entity (attack hitbox visualization)
---@param entity Model The entity performing the attack
---@param offset Vector3? Offset from entity root (optional, default: forward)
---@param size Vector3? Size of hitbox (optional)
---@param color Color3? Color (optional)
---@param duration number? Duration (optional)
---@return BasePart?
function HitboxVisualizer.createFromEntity(entity, offset, size, color, duration)
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    offset = offset or Vector3.new(0, 0, -4) -- Default: in front of entity
    size = size or HitboxVisualizer.defaultSize
    
    -- Calculate world position (snapshot - doesn't follow)
    local cframe = root.CFrame * CFrame.new(offset)
    
    return HitboxVisualizer.create(cframe, size, color, duration)
end

---Create hitbox at entity's current position (body hitbox snapshot)
---@param entity Model
---@param size Vector3?
---@param color Color3?
---@param duration number?
---@return BasePart?
function HitboxVisualizer.createAtEntity(entity, size, color, duration)
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    size = size or Vector3.new(4, 6, 4)
    
    return HitboxVisualizer.create(root.CFrame, size, color, duration)
end

---Create attack cone/arc visualization (for sweep attacks)
---@param entity Model
---@param arcAngle number Angle of arc in degrees
---@param range number Range of the attack
---@param color Color3?
---@param duration number?
---@return table Parts created
function HitboxVisualizer.createArc(entity, arcAngle, range, color, duration)
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return {} end
    
    color = color or Color3.fromRGB(255, 165, 0) -- Orange for arcs
    duration = duration or HitboxVisualizer.defaultDuration
    
    local parts = {}
    local segments = math.ceil(arcAngle / 15) -- One segment per 15 degrees
    local startAngle = -arcAngle / 2
    
    for i = 0, segments do
        local angle = math.rad(startAngle + (arcAngle / segments) * i)
        local offset = Vector3.new(math.sin(angle) * range, 0, -math.cos(angle) * range)
        local cframe = root.CFrame * CFrame.new(offset)
        
        local part = HitboxVisualizer.create(cframe, Vector3.new(1, 6, 1), color, duration, 0.7)
        table.insert(parts, part)
    end
    
    return parts
end

---Create a hit indicator (small flash at position)
---@param position Vector3
---@param wasParried boolean? Green if parried, red if hit
---@return BasePart
function HitboxVisualizer.createHitIndicator(position, wasParried)
    local color = wasParried and Color3.fromRGB(100, 255, 100) or Color3.fromRGB(255, 100, 100)
    local size = Vector3.new(2, 2, 2)
    
    local cframe = CFrame.new(position)
    return HitboxVisualizer.create(cframe, size, color, 0.3, 0.3)
end

---Create danger zone visualization (parry window indicator)
---@param entity Model
---@param range number
---@param duration number?
---@return BasePart?
function HitboxVisualizer.createDangerZone(entity, range, duration)
    local root = entity:FindFirstChild("HumanoidRootPart")
    if not root then return nil end
    
    -- Yellow = danger/parry window
    local color = Color3.fromRGB(255, 255, 0)
    local size = Vector3.new(range * 2, 0.5, range * 2)
    
    -- Ground-level disc
    local cframe = CFrame.new(root.Position.X, root.Position.Y - 3, root.Position.Z)
    
    return HitboxVisualizer.create(cframe, size, color, duration or 0.5, 0.7)
end

---Cleanup the oldest hitbox
function HitboxVisualizer.cleanupOldest()
    if #activeHitboxes == 0 then return end
    
    local oldest = table.remove(activeHitboxes, 1)
    if oldest and oldest.part and oldest.part.Parent then
        oldest.part:Destroy()
    end
    hitboxCount = math.max(0, hitboxCount - 1)
end

---Cleanup all hitboxes
function HitboxVisualizer.cleanupAll()
    for _, data in ipairs(activeHitboxes) do
        if data.part and data.part.Parent then
            data.part:Destroy()
        end
    end
    activeHitboxes = {}
    hitboxCount = 0
    
    if hitboxFolder then
        hitboxFolder:ClearAllChildren()
    end
end

---Set default duration
---@param duration number
function HitboxVisualizer.setDuration(duration)
    HitboxVisualizer.defaultDuration = math.clamp(duration, 0.1, 5)
end

---Set default size
---@param size Vector3
function HitboxVisualizer.setSize(size)
    HitboxVisualizer.defaultSize = size
end

---Set default color
---@param color Color3
function HitboxVisualizer.setColor(color)
    HitboxVisualizer.defaultColor = color
end

---Set max hitboxes
---@param max number
function HitboxVisualizer.setMaxHitboxes(max)
    HitboxVisualizer.maxHitboxes = math.clamp(max, 10, 200)
end

---Enable/disable
function HitboxVisualizer.enable()
    HitboxVisualizer.enabled = true
end

function HitboxVisualizer.disable()
    HitboxVisualizer.enabled = false
    HitboxVisualizer.cleanupAll()
end

function HitboxVisualizer.toggle()
    if HitboxVisualizer.enabled then
        HitboxVisualizer.disable()
    else
        HitboxVisualizer.enable()
    end
    return HitboxVisualizer.enabled
end

---Full cleanup
function HitboxVisualizer.cleanup()
    HitboxVisualizer.disable()
    
    if hitboxFolder then
        hitboxFolder:Destroy()
        hitboxFolder = nil
    end
end

-- Return module
return HitboxVisualizer
