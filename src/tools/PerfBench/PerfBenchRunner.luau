local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Libraries = {
	Serial = {
		library = require(ReplicatedStorage:WaitForChild("FastCast2Serial")),
		config = require(ReplicatedStorage.FastCast2Serial:WaitForChild("Config")),
		simulation = require(ReplicatedStorage.FastCast2Serial:WaitForChild("SerialSimulation")),
	},
	Parallel = {
		library = require(ReplicatedStorage:WaitForChild("FastCast2Parallel")),
		config = require(ReplicatedStorage.FastCast2Parallel:WaitForChild("Config")),
		simulation = require(ReplicatedStorage.FastCast2Parallel:WaitForChild("ParallelSimulation")),
	},
}

local PerfBench = {}

local function summarizeFrames(frameTimes)
	if #frameTimes == 0 then
		return 0, 0, 0, 0
	end

	local sorted = table.clone(frameTimes)
	table.sort(sorted)
	local total = 0
	for _, value in frameTimes do
		total += value
	end

	local function percentile(fraction)
		return sorted[math.max(1, math.ceil(#sorted * fraction))]
	end

	return total / #frameTimes, percentile(0.50), percentile(0.95), percentile(0.99)
end

local function setSimulationMode(modeName: string, simulationMode: string)
	local mode = Libraries[modeName]
	mode.simulation.Stop()
	mode.config.SimulationMode = simulationMode
	mode.simulation.Start()
end

local function restoreMovement(library: any, movementMode: string)
	local resetCaster = library.new()
	resetCaster:SetMovementModeEnabled(true, movementMode)
	resetCaster:Destroy()
end

local function runCase(
	modeName: string,
	simulationMode: string,
	projectileCount: number,
	sampleDuration: number,
	instanced: boolean,
	movement: boolean,
	workerCount: number,
	movementMode: string
)
	local mode = Libraries[modeName]
	local library = mode.library
	local caster = nil
	local container = Instance.new("Folder")
	container.Name = "FastCast2PerfBenchCosmetics"
	container.Parent = Workspace

	local template = Instance.new("Part")
	template.Name = "FastCast2PerfBenchProjectile"
	template.Size = Vector3.one
	template.Anchored = true
	template.CanCollide = false
	template.CanQuery = false
	template.CanTouch = false
	template.CastShadow = false
	template.Massless = true
	template.Parent = ReplicatedStorage

	local activeCasts = {}
	local firedCount = 0
	local heartbeatConnection = nil
	local ok, result = xpcall(function()
		if modeName == "Serial" then
			library.Init(movementMode)
		else
			library.Init(workerCount, movementMode)
		end

		local behavior = library.newBehavior()
		behavior.MaxDistance = 1e9
		behavior.Acceleration = Vector3.zero
		behavior.AutoIgnoreContainer = true
		behavior.HighFidelitySegmentSize = 1
		behavior.FastCastEventsConfig.UseCastFire = true
		behavior.FastCastEventsConfig.UseCastTerminating = true
		behavior.CosmeticBulletTemplate = if instanced then template else nil
		behavior.CosmeticBulletContainer = if instanced then container else nil

		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { container }
		raycastParams.IgnoreWater = true
		behavior.RaycastParams = raycastParams

		caster = library.new()
		caster.CastFire = function(cast)
			firedCount += 1
			activeCasts[#activeCasts + 1] = cast
		end
		caster.CastTerminating = function(cast)
			local index = table.find(activeCasts, cast)
			if index then
				table.remove(activeCasts, index)
			end
			local cosmetic = cast and cast.RayInfo and cast.RayInfo.CosmeticBulletObject
			if cosmetic and cosmetic.Parent then
				cosmetic:Destroy()
			end
		end
		caster:SetMovementModeEnabled(movement, movementMode)

		local random = Random.new(2026)
		local creationStarted = os.clock()
		for _ = 1, projectileCount do
			local origin = Vector3.new(
				random:NextInteger(-100, 100),
				random:NextInteger(0, 100),
				random:NextInteger(-100, 100)
			)
			local direction = Vector3.new(
				random:NextNumber(-1, 1),
				random:NextNumber(-1, 1),
				random:NextNumber(-1, 1)
			)
			direction = if direction.Magnitude == 0 then Vector3.xAxis else direction.Unit
			caster:RaycastFire(origin, direction, 6, behavior)
		end
		local creationMs = (os.clock() - creationStarted) * 1000

		task.wait()
		local frameTimes = {}
		local measuring = true
		heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if measuring and deltaTime > 0 then
				frameTimes[#frameTimes + 1] = deltaTime * 1000
			end
		end)
		task.wait(sampleDuration)
		measuring = false
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil

		local average, p50, p95, p99 = summarizeFrames(frameTimes)

		return {
			mode = modeName,
			simulationMode = simulationMode,
			projectiles = projectileCount,
			firedCasts = firedCount,
			instanced = instanced,
			movement = movement,
			creationMs = creationMs,
			averageFrameMs = average,
			p50FrameMs = p50,
			p95FrameMs = p95,
			p99FrameMs = p99,
		}
	end)

	-- Always stop sampling and terminate casts before destroying their caster.
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end
	local cleanupStarted = os.clock()
	local castsToTerminate = table.clone(activeCasts)
	for i = #castsToTerminate, 1, -1 do
		local cast = castsToTerminate[i]
		if cast then
			pcall(function()
				library:TerminateCast(cast)
			end)
		end
	end
	local cleanupDeadline = os.clock() + 5
	while #activeCasts > 0 and os.clock() < cleanupDeadline do
		task.wait()
	end
	if caster then
		pcall(function()
			caster:Destroy()
		end)
	end
	pcall(restoreMovement, library, movementMode)
	local cleanupMs = (os.clock() - cleanupStarted) * 1000
	template:Destroy()
	container:Destroy()

	if ok then
		result.cleanupMs = cleanupMs
		result.remainingCastsAtCleanup = #activeCasts
		return result
	end
	return {
		mode = modeName,
		simulationMode = simulationMode,
		projectiles = projectileCount,
		instanced = instanced,
		movement = movement,
		error = tostring(result),
	}
end

function PerfBench.run(options: {
	projectileCount: number,
	sampleDuration: number,
	workerCount: number,
	instanced: boolean,
	includePerFrame: boolean,
	includeFixed: boolean,
	includeMovementEnabled: boolean,
	includeMovementDisabled: boolean,
}): { any }
	-- Keep the perfbench workload separate from benchmarks/: Raycast only,
	-- with independently configurable simulation mode, instancing, and movement.
	local maxProjectileCount = math.max(1, math.floor(options.maxProjectileCount))
	local projectileCount = math.clamp(math.floor(options.projectileCount), 1, maxProjectileCount)
	local sampleDuration = math.clamp(options.sampleDuration, 1, 10)
	local movementMode = "BulkMoveTo"
	local simulationModes = {}
	local movements = {}
	if options.includePerFrame then
		table.insert(simulationModes, "PerFrame")
	end
	if options.includeFixed then
		table.insert(simulationModes, "Fixed")
	end
	if options.includeMovementEnabled then
		table.insert(movements, true)
	end
	if options.includeMovementDisabled then
		table.insert(movements, false)
	end
	if #simulationModes == 0 or #movements == 0 then
		return { { error = "Select at least one simulation mode and one movement case in ConfigUI." } }
	end

	Libraries.Serial.library.Init(movementMode)
	Libraries.Parallel.library.Init(options.workerCount, movementMode)

	local originalModes = {
		Serial = Libraries.Serial.config.SimulationMode,
		Parallel = Libraries.Parallel.config.SimulationMode,
	}
	local results = {}

	local ok, err = pcall(function()
		for _, simulationMode in simulationModes do
			for _, modeName in { "Serial", "Parallel" } do
				setSimulationMode(modeName, simulationMode)
				for _, movement in movements do
					local result = runCase(
						modeName,
						simulationMode,
						projectileCount,
						sampleDuration,
						options.instanced,
						movement,
						options.workerCount,
						movementMode
					)
					table.insert(results, result)
					task.wait(1)
				end
			end
		end
	end)

	for modeName, originalMode in originalModes do
		local restored, restoreError = pcall(setSimulationMode, modeName, originalMode)
		if not restored then
			table.insert(results, {
				mode = modeName,
				simulationMode = originalMode,
				error = "Could not restore simulation mode: " .. tostring(restoreError),
			})
		end
	end

	if not ok then
		table.insert(results, { error = tostring(err) })
	end

	return results
end

return PerfBench
