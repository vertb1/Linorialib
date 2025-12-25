-- Live Hitbox Visualizer
-- Shows hitboxes on players/NPCs in real-time

local HitboxVisualizer = {
    enabled = false,
    showPlayers = true,
    showNPCs = true,
    showSelf = false,
    hitboxSize = 3,
    hitboxColor = Color3.fromRGB(255, 50, 50),
    hitboxTransparency = 0.5,
    maxDistance = 200,
}

-- Services
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local LocalPlayer = Players.LocalPlayer

-- Storage
local hitboxFolder = nil
local entityHitboxes = {} -- [entity] = { parts = {}, connections = {} }
local updateConnection = nil

-- Limbs to show hitboxes on
local HITBOX_LIMBS = {
    -- R6
    "Head", "Torso", "Left Arm", "Right Arm", "Left Leg", "Right Leg",
    -- R15
    "Head", "UpperTorso", "LowerTorso",
    "LeftHand", "RightHand", "LeftFoot", "RightFoot",
    "LeftLowerArm", "RightLowerArm", "LeftUpperArm", "RightUpperArm",
    "LeftLowerLeg", "RightLowerLeg", "LeftUpperLeg", "RightUpperLeg",
}

---Create hitbox folder
local function ensureFolder()
    if not hitboxFolder or not hitboxFolder.Parent then
        hitboxFolder = Instance.new("Folder")
        hitboxFolder.Name = "HitboxVisuals"
        hitboxFolder.Parent = Workspace
    end
    return hitboxFolder
end

---Create a hitbox part for a limb
---@param limb BasePart
---@return BasePart
local function createHitbox(limb)
    local hitbox = Instance.new("Part")
    hitbox.Name = "HB_" .. limb.Name
    hitbox.Shape = Enum.PartType.Ball
    hitbox.Size = Vector3.new(HitboxVisualizer.hitboxSize, HitboxVisualizer.hitboxSize, HitboxVisualizer.hitboxSize)
    hitbox.Color = HitboxVisualizer.hitboxColor
    hitbox.Transparency = HitboxVisualizer.hitboxTransparency
    hitbox.Material = Enum.Material.ForceField
    hitbox.Anchored = true
    hitbox.CanCollide = false
    hitbox.CanQuery = false
    hitbox.CanTouch = false
    hitbox.CastShadow = false
    hitbox.Parent = ensureFolder()
    
    return hitbox
end

---Create hitboxes for an entity
---@param entity Model
local function createHitboxesForEntity(entity)
    if entityHitboxes[entity] then return end
    
    local data = {
        parts = {},
        limbMap = {},
    }
    
    for _, limbName in ipairs(HITBOX_LIMBS) do
        local limb = entity:FindFirstChild(limbName)
        if limb and limb:IsA("BasePart") then
            local hitbox = createHitbox(limb)
            data.parts[limb] = hitbox
            data.limbMap[limbName] = { limb = limb, hitbox = hitbox }
        end
    end
    
    entityHitboxes[entity] = data
end

---Remove hitboxes for an entity
---@param entity Model
local function removeHitboxesForEntity(entity)
    local data = entityHitboxes[entity]
    if not data then return end
    
    for _, hitbox in pairs(data.parts) do
        if hitbox and hitbox.Parent then
            hitbox:Destroy()
        end
    end
    
    entityHitboxes[entity] = nil
end

---Update hitbox positions for an entity
---@param entity Model
---@param data table
local function updateEntityHitboxes(entity, data)
    for limb, hitbox in pairs(data.parts) do
        if limb and limb.Parent and hitbox and hitbox.Parent then
            hitbox.CFrame = limb.CFrame
            hitbox.Size = Vector3.new(HitboxVisualizer.hitboxSize, HitboxVisualizer.hitboxSize, HitboxVisualizer.hitboxSize)
            hitbox.Color = HitboxVisualizer.hitboxColor
            hitbox.Transparency = HitboxVisualizer.hitboxTransparency
        end
    end
end

---Check if entity is within range
---@param entity Model
---@return boolean
local function isInRange(entity)
    local myRoot = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
    local theirRoot = entity:FindFirstChild("HumanoidRootPart") or entity.PrimaryPart
    
    if not myRoot or not theirRoot then return false end
    
    return (myRoot.Position - theirRoot.Position).Magnitude <= HitboxVisualizer.maxDistance
end

---Check if entity is a player
---@param entity Model
---@return boolean
local function isPlayer(entity)
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character == entity then
            return true
        end
    end
    return false
end

---Check if entity is local player
---@param entity Model
---@return boolean
local function isLocalPlayer(entity)
    return LocalPlayer.Character == entity
end

---Check if entity is an NPC (has humanoid but not a player)
---@param entity Model
---@return boolean
local function isNPC(entity)
    local humanoid = entity:FindFirstChildWhichIsA("Humanoid")
    return humanoid ~= nil and not isPlayer(entity)
end

---Should show hitboxes for this entity
---@param entity Model
---@return boolean
local function shouldShowEntity(entity)
    if not HitboxVisualizer.enabled then return false end
    if not isInRange(entity) then return false end
    
    if isLocalPlayer(entity) then
        return HitboxVisualizer.showSelf
    elseif isPlayer(entity) then
        return HitboxVisualizer.showPlayers
    elseif isNPC(entity) then
        return HitboxVisualizer.showNPCs
    end
    
    return false
end

---Main update loop
local function onUpdate()
    if not HitboxVisualizer.enabled then return end
    
    -- Get all entities with humanoids
    local entities = {}
    
    -- Add players
    for _, player in ipairs(Players:GetPlayers()) do
        if player.Character then
            table.insert(entities, player.Character)
        end
    end
    
    -- Add NPCs (models with humanoids in workspace)
    for _, child in ipairs(Workspace:GetDescendants()) do
        if child:IsA("Model") and child:FindFirstChildWhichIsA("Humanoid") then
            if not isPlayer(child) then
                table.insert(entities, child)
            end
        end
    end
    
    -- Update each entity
    for _, entity in ipairs(entities) do
        if shouldShowEntity(entity) then
            if not entityHitboxes[entity] then
                createHitboxesForEntity(entity)
            end
            updateEntityHitboxes(entity, entityHitboxes[entity])
        else
            removeHitboxesForEntity(entity)
        end
    end
    
    -- Clean up removed entities
    for entity, _ in pairs(entityHitboxes) do
        if not entity or not entity.Parent then
            removeHitboxesForEntity(entity)
        end
    end
end

---Enable hitbox visualization
function HitboxVisualizer.enable()
    HitboxVisualizer.enabled = true
    
    if not updateConnection then
        updateConnection = RunService.RenderStepped:Connect(onUpdate)
    end
end

---Disable hitbox visualization
function HitboxVisualizer.disable()
    HitboxVisualizer.enabled = false
    
    -- Clean up all hitboxes
    for entity, _ in pairs(entityHitboxes) do
        removeHitboxesForEntity(entity)
    end
    entityHitboxes = {}
end

---Toggle hitbox visualization
function HitboxVisualizer.toggle()
    if HitboxVisualizer.enabled then
        HitboxVisualizer.disable()
    else
        HitboxVisualizer.enable()
    end
    return HitboxVisualizer.enabled
end

---Set hitbox size
---@param size number
function HitboxVisualizer.setSize(size)
    HitboxVisualizer.hitboxSize = math.clamp(size, 0.5, 20)
end

---Set hitbox color
---@param color Color3
function HitboxVisualizer.setColor(color)
    HitboxVisualizer.hitboxColor = color
end

---Set hitbox transparency
---@param transparency number
function HitboxVisualizer.setTransparency(transparency)
    HitboxVisualizer.hitboxTransparency = math.clamp(transparency, 0, 1)
end

---Set max distance
---@param distance number
function HitboxVisualizer.setMaxDistance(distance)
    HitboxVisualizer.maxDistance = math.max(distance, 10)
end

---Cleanup
function HitboxVisualizer.cleanup()
    HitboxVisualizer.disable()
    
    if updateConnection then
        updateConnection:Disconnect()
        updateConnection = nil
    end
    
    if hitboxFolder then
        hitboxFolder:Destroy()
        hitboxFolder = nil
    end
end

return HitboxVisualizer
