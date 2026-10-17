--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))

local ProjectileTemplate: BasePart? = nil

local function GetProjectileTemplate(): BasePart
	if ProjectileTemplate and ProjectileTemplate.Parent then
		return ProjectileTemplate
	end

	local existing = ReplicatedStorage:FindFirstChild("FastCast2DebugProjectile")
	if existing and existing:IsA("BasePart") then
		ProjectileTemplate = existing
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "FastCast2DebugProjectile"
	part.Size = Vector3.new(0.18, 0.18, 1.2)
	part.Material = Enum.Material.Neon
	part.Color = Color3.fromRGB(255, 220, 80)
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = ReplicatedStorage

	ProjectileTemplate = part
	return part
end

local function ConfigureBehavior()
	if not Wrapper:IsReady() then
		return
	end

	local behavior = Wrapper.Behavior
	if not behavior.CosmeticBulletTemplate then
		behavior.CosmeticBulletTemplate = GetProjectileTemplate()
	end
	behavior.CosmeticBulletContainer = Workspace

	local character = Player.Character
	if character then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true
		behavior.RaycastParams = params
	end
end

Tool.Equipped:Connect(function()
	task.spawn(function()
		local ok, err = pcall(function()
			Wrapper:Initialize()
		end)
		if not ok then
			warn("[BasicFire] FastCast2 initialization failed:", err)
		end
	end)
end)

Tool.Activated:Connect(function()
	if not Wrapper:IsReady() then
		warn("[BasicFire] FastCast2Wrapper is not ready yet.")
		return
	end

	local character = Player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	ConfigureBehavior()

	local targetPosition = Mouse.Hit.Position
	local direction = targetPosition - head.Position
	if direction.Magnitude <= 0 then
		return
	end

	local ok, err = pcall(function()
		Wrapper:Fire(head.Position, direction)
	end)
	if not ok then
		warn("[BasicFire] Could not fire:", err)
	end
end)
