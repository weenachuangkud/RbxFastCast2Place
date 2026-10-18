
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Player = Players.LocalPlayer
local Mouse = Player:GetMouse()
local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))

local function ConfigureBehavior()
	if not Wrapper:IsReady() then
		return
	end

	local character = Player.Character
	if character then
		local params = RaycastParams.new()
		params.FilterType = Enum.RaycastFilterType.Exclude
		params.FilterDescendantsInstances = { character }
		params.IgnoreWater = true
		Wrapper.Behavior.RaycastParams = params
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
