--!strict
-- Server-authoritative FastCast2 networking for the test place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Network"))

local function encodeConfiguration()
	local settings = Wrapper.Settings
	local behavior = Wrapper.Behavior
	return {
		mode = if settings.Mode == "Parallel" then 2 else 1,
		movementMode = if settings.MovementMode == "Motor6D" then 2 else 1,
		workerCount = math.clamp(math.floor(settings.WorkerCount), 1, 32),
		castType = if settings.CastType == "Blockcast" then 2 elseif settings.CastType == "Spherecast" then 3 else 1,
		velocity = math.clamp(settings.Velocity, 1, 10000),
		blockcastSize = settings.BlockcastSize,
		spherecastRadius = math.clamp(settings.SpherecastRadius, 0.05, 100),
		maxDistance = math.clamp(behavior.MaxDistance, 1, 100000),
		highFidelityBehavior = math.clamp(math.floor(behavior.HighFidelityBehavior), 1, 3),
		highFidelitySegmentSize = math.clamp(behavior.HighFidelitySegmentSize, 0.05, 100),
		acceleration = behavior.Acceleration,
		visualizeCasts = behavior.VisualizeCasts,
		autoIgnoreContainer = behavior.AutoIgnoreContainer,
	}
end

local function applyConfiguration(payload)
	-- Change mode first because SetMode creates a fresh behavior.
	local mode = if payload.mode == 2 then "Parallel" else "Serial"
	if Wrapper.Settings.Mode ~= mode then
		Wrapper:SetMode(mode)
	end

	-- Clamp all client-controlled numeric settings before accepting them.
	Wrapper.Settings.Velocity = math.clamp(payload.velocity, 1, 10000)
	Wrapper.Settings.MovementMode = if payload.movementMode == 2 then "Motor6D" else "BulkMoveTo"
	Wrapper.Settings.WorkerCount = math.clamp(math.floor(payload.workerCount), 1, 32)
	Wrapper.Settings.CastType = if payload.castType == 2 then "Blockcast" elseif payload.castType == 3 then "Spherecast" else "Raycast"
	Wrapper.Settings.BlockcastSize = Vector3.new(
		math.clamp(payload.blockcastSize.X, 0.05, 100),
		math.clamp(payload.blockcastSize.Y, 0.05, 100),
		math.clamp(payload.blockcastSize.Z, 0.05, 100)
	)
	Wrapper.Settings.SpherecastRadius = math.clamp(payload.spherecastRadius, 0.05, 100)
	Wrapper.Behavior.MaxDistance = math.clamp(payload.maxDistance, 1, 100000)
	Wrapper.Behavior.HighFidelityBehavior = math.clamp(math.floor(payload.highFidelityBehavior), 1, 3)
	Wrapper.Behavior.HighFidelitySegmentSize = math.clamp(payload.highFidelitySegmentSize, 0.05, 100)
	Wrapper.Behavior.Acceleration = payload.acceleration
	Wrapper.Behavior.VisualizeCasts = payload.visualizeCasts == true
	Wrapper.Behavior.AutoIgnoreContainer = payload.autoIgnoreContainer == true

end

local LastFireAt: { [Player]: number } = {}

local function getVelocity(payload)
	if payload.velocityMode == 2 then
		return payload.velocity
	elseif payload.velocityMode == 1 then
		return payload.velocity.Magnitude
	end
	return Wrapper.Settings.Velocity
end

do
	local ok, err = pcall(function()
		Wrapper:Initialize()
		-- Server simulates gameplay; cosmetic instances are rendered by clients.
		Wrapper:SetCosmeticMode("Instanceless")
	end)
	if not ok then
		warn("[FastCast2Server] FastCast2 initialization failed:", err)
	end
end

Network.RequestConfiguration.listen(function(_, player)
	if player then
		Network.Configuration.sendTo(encodeConfiguration(), player)
	end
end)

Network.Configuration.listen(function(payload, player)
	if not player or type(payload) ~= "table" then
		return
	end
	local ok, err = pcall(function()
		applyConfiguration(payload)
	end)
	if not ok then
		warn("[FastCast2Server] Rejected configuration from", player.Name, err)
		return
	end
	Network.Configuration.sendToAll(encodeConfiguration())
end)

Network.FireRequest.listen(function(payload, player)
	if not player or type(payload) ~= "table" or not Wrapper:IsReady() then
		return
	end

	local now = os.clock()
	if now - (LastFireAt[player] or 0) < 0.025 then
		return
	end
	LastFireAt[player] = now

	local character = player.Character
	local head = character and character:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end

	local origin = payload.origin
	local direction = payload.direction
	if typeof(origin) ~= "Vector3" or typeof(direction) ~= "Vector3" then
		return
	end
	if direction.Magnitude < 1e-4 or direction.Magnitude > 1.001 then
		return
	end
	-- Prevent clients from firing from arbitrary positions.
	if (origin - head.Position).Magnitude > 12 then
		return
	end

	local castOrigin = head.Position
	local castDirection = direction.Unit
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true
	Wrapper.Behavior.RaycastParams = raycastParams

	local velocity = getVelocity(payload)
	local ok, err = pcall(function()
		Wrapper:FireLocal(castOrigin, castDirection, velocity)
	end)
	if not ok then
		warn("[FastCast2Server] Fire failed for", player.Name, err)
		return
	end

	Network.FireBroadcast.sendToAllExcept({
		origin = castOrigin,
		direction = castDirection,
		velocityMode = if typeof(velocity) == "Vector3" then 2 elseif typeof(velocity) == "number" then 1 else 0,
		velocity = if typeof(velocity) == "Vector3" then velocity elseif typeof(velocity) == "number" then Vector3.new(velocity, 0, 0) else Vector3.zero,
		context = 2,
	}, player)
end)
