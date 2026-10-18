-- Server-authoritative FastCast2 networking for the test place.
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Network"))

local function isFiniteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function isFiniteVector3(value)
	return typeof(value) == "Vector3"
		and isFiniteNumber(value.X)
		and isFiniteNumber(value.Y)
		and isFiniteNumber(value.Z)
end

local function encodeConfiguration()
	local settings = Wrapper.Settings
	local behavior = Wrapper.Behavior
	return {
		mode = if settings.Mode == "Parallel" then 2 else 1,
		movementMode = if settings.MovementMode == "Motor6D" then 2 else 1,
		workerCount = math.clamp(math.floor(settings.WorkerCount), 1, 32),
		castType = if settings.CastType == "Blockcast" then 2 elseif settings.CastType == "Spherecast" then 3 else 1,
		velocity = math.clamp(settings.Velocity, 1, 10000),
		blockcastSize = behavior.BlockcastSize or settings.BlockcastSize,
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
	assert(payload.mode == 1 or payload.mode == 2, "Invalid caster mode.")
	assert(payload.movementMode == 1 or payload.movementMode == 2, "Invalid movement mode.")
	assert(payload.castType == 1 or payload.castType == 2 or payload.castType == 3, "Invalid cast type.")
	assert(isFiniteNumber(payload.workerCount) and payload.workerCount % 1 == 0, "Invalid worker count.")
	assert(isFiniteNumber(payload.velocity), "Invalid velocity.")
	assert(isFiniteVector3(payload.blockcastSize), "Invalid blockcast size.")
	assert(isFiniteNumber(payload.spherecastRadius), "Invalid spherecast radius.")
	assert(isFiniteNumber(payload.maxDistance), "Invalid max distance.")
	assert(isFiniteNumber(payload.highFidelityBehavior) and payload.highFidelityBehavior % 1 == 0, "Invalid high-fidelity behavior.")
	assert(isFiniteNumber(payload.highFidelitySegmentSize), "Invalid high-fidelity segment size.")
	assert(isFiniteVector3(payload.acceleration), "Invalid acceleration.")
	assert(type(payload.visualizeCasts) == "boolean", "Invalid visualize setting.")
	assert(type(payload.autoIgnoreContainer) == "boolean", "Invalid auto-ignore setting.")

	local mode = if payload.mode == 2 then "Parallel" else "Serial"
	local movementMode = if payload.movementMode == 2 then "Motor6D" else "BulkMoveTo"
	local workerCount = math.clamp(math.floor(payload.workerCount), 1, 32)
	local velocity = math.clamp(payload.velocity, 1, 10000)
	local blockcastSize = Vector3.new(
		math.clamp(payload.blockcastSize.X, 0.05, 100),
		math.clamp(payload.blockcastSize.Y, 0.05, 100),
		math.clamp(payload.blockcastSize.Z, 0.05, 100)
	)
	local spherecastRadius = math.clamp(payload.spherecastRadius, 0.05, 100)
	local maxDistance = math.clamp(payload.maxDistance, 1, 100000)
	local highFidelityBehavior = math.clamp(math.floor(payload.highFidelityBehavior), 1, 3)
	local highFidelitySegmentSize = math.clamp(payload.highFidelitySegmentSize, 0.05, 100)
	local acceleration = Vector3.new(
		math.clamp(payload.acceleration.X, -100000, 100000),
		math.clamp(payload.acceleration.Y, -100000, 100000),
		math.clamp(payload.acceleration.Z, -100000, 100000)
	)

	local modeChanged = Wrapper.Settings.Mode ~= mode
	Wrapper.Settings.MovementMode = movementMode
	Wrapper.Settings.Velocity = velocity
	Wrapper.Settings.CastType = if payload.castType == 2 then "Blockcast" elseif payload.castType == 3 then "Spherecast" else "Raycast"
	Wrapper.Settings.BlockcastSize = blockcastSize
	Wrapper.Settings.SpherecastRadius = spherecastRadius

	-- Set runtime initialization inputs before switching modes. For an unchanged
	-- mode, update the existing shared movement runtime directly.
	if modeChanged then
		Wrapper.Settings.WorkerCount = workerCount
		Wrapper:SetMode(mode)
	elseif mode == "Parallel" then
		Wrapper:SetWorkerCount(workerCount)
	elseif Wrapper.Settings.WorkerCount ~= workerCount then
		Wrapper.Settings.WorkerCount = workerCount
	end

	if Wrapper:IsReady() then
		Wrapper.Caster:SetMovementModeEnabled(true, movementMode)
	end

	Wrapper.Behavior.MaxDistance = maxDistance
	Wrapper.Behavior.HighFidelityBehavior = highFidelityBehavior
	Wrapper.Behavior.HighFidelitySegmentSize = highFidelitySegmentSize
	Wrapper.Behavior.Acceleration = acceleration
	Wrapper.Behavior.VisualizeCasts = payload.visualizeCasts
	Wrapper.Behavior.AutoIgnoreContainer = payload.autoIgnoreContainer
end

local LastFireAt: { [Player]: number } = {}

local function getVelocity(payload)
	if payload.velocityMode == 2 then
		return payload.velocity
	elseif payload.velocityMode == 1 then
		return payload.velocity.X
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

	if payload.context ~= 2 and payload.context ~= 3 then
		return
	end
	local origin = payload.origin
	local direction = payload.direction
	if not isFiniteVector3(origin) or not isFiniteVector3(direction) then
		return
	end
	if direction.Magnitude < 1e-4 or direction.Magnitude > 1.001 then
		return
	end
	if payload.velocityMode ~= 0 and payload.velocityMode ~= 1 and payload.velocityMode ~= 2 then
		return
	end
	if not isFiniteVector3(payload.velocity) or payload.velocity.Magnitude > 10000 then
		return
	end
	if (origin - head.Position).Magnitude > 12 then
		return
	end

	local castOrigin = head.Position
	local castDirection = direction.Unit
	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { character }
	raycastParams.IgnoreWater = true

	-- Each player's cast gets its own behavior snapshot. Mutating the shared
	-- wrapper behavior here would change the filter used by other active casts.
	local castBehavior = table.clone(Wrapper.Behavior)
	castBehavior.RaycastParams = raycastParams

	local velocity = getVelocity(payload)
	if typeof(velocity) == "number" and (not isFiniteNumber(velocity) or math.abs(velocity) > 10000) then
		return
	end
	if typeof(velocity) == "Vector3" and (not isFiniteVector3(velocity) or velocity.Magnitude > 10000) then
		return
	end

	local ok, err = pcall(function()
		Wrapper:FireLocal(castOrigin, castDirection, velocity, castBehavior)
	end)
	if not ok then
		warn("[FastCast2Server] Fire failed for", player.Name, err)
		return
	end

	local broadcast = {
		origin = castOrigin,
		direction = castDirection,
		velocityMode = if typeof(velocity) == "Vector3" then 2 elseif typeof(velocity) == "number" then 1 else 0,
		velocity = if typeof(velocity) == "Vector3" then velocity elseif typeof(velocity) == "number" then Vector3.new(velocity, 0, 0) else Vector3.zero,
		context = payload.context,
	}
	if payload.context == 3 then
		-- Both predicts locally, so don't render a second cosmetic on the shooter.
		Network.FireBroadcast.sendToAllExcept(broadcast, player)
	else
		-- Server-only requests need the server result rendered on the requesting client too.
		Network.FireBroadcast.sendToAll(broadcast)
	end
end)

Players.PlayerRemoving:Connect(function(player)
	LastFireAt[player] = nil
end)
