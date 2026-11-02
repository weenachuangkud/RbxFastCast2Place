local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Libraries = {
	Serial = {
		library = require(ReplicatedStorage:WaitForChild("FastCast2Serial")),
		config = require(ReplicatedStorage.FastCast2Serial:WaitForChild("Config")),
	},
	Parallel = {
		library = require(ReplicatedStorage:WaitForChild("FastCast2Parallel")),
		config = require(ReplicatedStorage.FastCast2Parallel:WaitForChild("Config")),
	},
}

local PerfBench = {}

local function summarizeFrames(frameTimes)
	if #frameTimes == 0 then return 0, 0, 0, 0 end
	local sorted = table.clone(frameTimes)
	table.sort(sorted)
	local total = 0
	for _, value in frameTimes do total += value end
	local function percentile(fraction)
		return sorted[math.max(1, math.ceil(#sorted * fraction))]
	end
	return total / #frameTimes, percentile(0.50), percentile(0.95), percentile(0.99)
end

local function runCase(modeName: string, projectileCount: number, sampleDuration: number,
	instanced: boolean, movement: boolean, workerCount: number, movementMode: string)
	local mode = Libraries[modeName]
	local library = mode.library
	local simulationMode = mode.config.SimulationMode
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
	local castFireConnection = nil
	local castTerminatingConnection = nil
	local ok, result = xpcall(function()
		if modeName == "Serial" then library.Init(movementMode) else library.Init(workerCount, movementMode) end
		local behavior = library.newBehavior()
		behavior.MaxDistance = 1e9
		behavior.Acceleration = Vector3.zero
		behavior.AutoIgnoreContainer = true
		behavior.HighFidelitySegmentSize = 1
		behavior.CosmeticBulletTemplate = if instanced then template else nil
		behavior.CosmeticBulletContainer = if instanced then container else nil
		local raycastParams = RaycastParams.new()
		raycastParams.FilterType = Enum.RaycastFilterType.Exclude
		raycastParams.FilterDescendantsInstances = { container }
		raycastParams.IgnoreWater = true
		behavior.RaycastParams = raycastParams

		caster = library.new()
		castFireConnection = caster.CastFire:Connect(function(cast)
			firedCount += 1
			local casterCasts = activeCasts[cast.Caster.Actor or cast.Caster]
			if not casterCasts then
				casterCasts = {}
				activeCasts[cast.Caster.Actor or cast.Caster] = casterCasts
			end
			casterCasts[cast.ID] = cast
		end)
		castTerminatingConnection = caster.CastTerminating:Connect(function(cast)
			local casterCasts = activeCasts[cast.Caster.Actor or cast.Caster]
			if casterCasts then
				casterCasts[cast.ID] = nil
				if next(casterCasts) == nil then
					activeCasts[cast.Caster.Actor or cast.Caster] = nil
				end
			end
			local cosmetic = cast and cast.RayInfo and cast.RayInfo.CosmeticBulletObject
			if cosmetic and cosmetic.Parent then cosmetic:Destroy() end
		end)
		library.SetMovementModeEnabled(movement, movementMode)

		local random = Random.new(2026)
		local creationStarted = os.clock()
		for _ = 1, projectileCount do
			local origin = Vector3.new(random:NextInteger(-100, 100), random:NextInteger(0, 100), random:NextInteger(-100, 100))
			local direction = Vector3.new(random:NextNumber(-1, 1), random:NextNumber(-1, 1), random:NextNumber(-1, 1))
			direction = if direction.Magnitude == 0 then Vector3.xAxis else direction.Unit
			caster:RaycastFire(origin, direction, 6, behavior)
		end
		local creationElapsed = os.clock() - creationStarted
		local creationMs = creationElapsed * 1000
		local creationProjectilesPerSecond = if creationElapsed > 0 then projectileCount / creationElapsed else 0

		task.wait() -- flush queued parallel fire requests before sampling
		local frameTimes = {}
		local measuring = true
		heartbeatConnection = RunService.Heartbeat:Connect(function(dt)
			if measuring and dt > 0 then table.insert(frameTimes, dt * 1000) end
		end)
		task.wait(sampleDuration)
		measuring = false
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil
		local average, p50, p95, p99 = summarizeFrames(frameTimes)
		return {
			mode = modeName, simulationMode = simulationMode, projectiles = projectileCount,
			firedCasts = firedCount, instanced = instanced, movement = movement,
			creationMs = creationMs, creationProjectilesPerSecond = creationProjectilesPerSecond,
			averageFrameMs = average, p50FrameMs = p50, p95FrameMs = p95, p99FrameMs = p99,
		}
	end, debug.traceback)

	if heartbeatConnection then heartbeatConnection:Disconnect() end
	local cleanupStarted = os.clock()
	local castsAtCleanupStart = 0
	local castsToTerminate = {}
	for _, casterCasts in activeCasts do
		for _, cast in casterCasts do
			castsAtCleanupStart += 1
			table.insert(castsToTerminate, cast)
		end
	end
	for _, cast in castsToTerminate do
		pcall(function() library.TerminateCast(cast) end)
	end
	local cleanupDeadline = os.clock() + 5
	while next(activeCasts) ~= nil and os.clock() < cleanupDeadline do task.wait() end
	local cleanupElapsed = os.clock() - cleanupStarted
	local cleanupMs = cleanupElapsed * 1000
	local cleanupProjectilesPerSecond = if cleanupElapsed > 0 then castsAtCleanupStart / cleanupElapsed else 0

	-- Restore movement after timing cleanup; do not let disabled movement leak.
	if caster then
		pcall(function() library.SetMovementModeEnabled(true, movementMode) end)
		if castFireConnection then castFireConnection:Disconnect() end
		if castTerminatingConnection then castTerminatingConnection:Disconnect() end
		pcall(function() caster:Destroy() end)
	end
	pcall(function() template:Destroy() end)
	pcall(function() container:Destroy() end)

	local remaining = 0
	for _, casterCasts in activeCasts do
		for _ in casterCasts do remaining += 1 end
	end
	if ok then
		result.cleanupMs = cleanupMs
		result.cleanupCasts = castsAtCleanupStart
		result.cleanupProjectilesPerSecond = cleanupProjectilesPerSecond
		result.remainingCastsAtCleanup = remaining
		if remaining > 0 then result.error = "Cleanup timed out; remaining casts would contaminate the next case." end
		return result
	end
	return {
		mode = modeName, simulationMode = simulationMode, projectiles = projectileCount,
		instanced = instanced, movement = movement, cleanupMs = cleanupMs,
		cleanupCasts = castsAtCleanupStart, cleanupProjectilesPerSecond = cleanupProjectilesPerSecond,
		remainingCastsAtCleanup = remaining, error = tostring(result),
	}
end

function PerfBench.run(options: {
	projectileCount: number, maxProjectileCount: number?, sampleDuration: number,
	mode: string, workerCount: number, instanced: boolean,
	includeMovementEnabled: boolean, includeMovementDisabled: boolean,
}): { any }
	-- Server-only: use the actual selected module Config; never rewrite SimulationMode.
	local maxCount = math.max(1, math.floor(options.maxProjectileCount or 100000))
	local count = math.clamp(math.floor(options.projectileCount), 1, maxCount)
	local duration = math.clamp(options.sampleDuration, 1, 10)
	local movementMode = "BulkMoveTo"
	local movements = {}
	if options.includeMovementEnabled then table.insert(movements, true) end
	if options.includeMovementDisabled then table.insert(movements, false) end
	if #movements == 0 then return { { error = "Select at least one movement case in ConfigUI." } } end

	local modeName = options.mode
	assert(modeName == "Serial" or modeName == "Parallel", "PerfBench mode must be Serial or Parallel")
	local selected = Libraries[modeName]
	if modeName == "Serial" then selected.library.Init(movementMode) else selected.library.Init(options.workerCount, movementMode) end

	local results = {}
	for _, movement in movements do
		local result = runCase(modeName, count, duration, options.instanced == true, movement, options.workerCount, movementMode)
		table.insert(results, result)
		if result.error then break end -- isolation: do not start another case after failed cleanup
		task.wait(2) -- match upstream's inter-case cooldown and let worker messages settle
	end
	return results
end

return PerfBench
