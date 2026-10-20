local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Libraries = {
	Serial = require(ReplicatedStorage:WaitForChild("FastCast2Serial")),
	Parallel = require(ReplicatedStorage:WaitForChild("FastCast2Parallel")),
}

local Benchmark = {}

local function summarizeFrames(frameTimes)
	if #frameTimes == 0 then
		return {
			frames = 0, averageMs = 0, p50Ms = 0, p95Ms = 0, p99Ms = 0,
			averageFps = 0, minFps = 0, maxFps = 0,
		}
	end

	local sorted = table.clone(frameTimes)
	table.sort(sorted)
	local total = 0
	for _, value in frameTimes do
		total += value
	end

	local averageMs = total / #frameTimes
	local fastestFrameMs = sorted[1]
	local slowestFrameMs = sorted[#sorted]
	local function percentile(fraction)
		return sorted[math.max(1, math.ceil(#sorted * fraction))]
	end

	return {
		frames = #frameTimes,
		averageMs = averageMs,
		p50Ms = percentile(0.50),
		p95Ms = percentile(0.95),
		p99Ms = percentile(0.99),
		averageFps = if averageMs > 0 then 1000 / averageMs else 0,
		minFps = if slowestFrameMs > 0 then 1000 / slowestFrameMs else 0,
		maxFps = if fastestFrameMs > 0 then 1000 / fastestFrameMs else 0,
	}
end

local function fire(caster, castType, origin, direction, options, behavior)
	if castType == "Blockcast" then
		caster:BlockcastFire(origin, options.blockcastSize, direction, options.velocity, behavior)
	elseif castType == "Spherecast" then
		caster:SpherecastFire(origin, options.spherecastRadius, direction, options.velocity, behavior)
	else
		caster:RaycastFire(origin, direction, options.velocity, behavior)
	end
end

local function runMode(modeName, options)
	local library = Libraries[modeName]
	if modeName == "Serial" then
		library.Init(options.movementMode)
	else
		library.Init(options.workerCount, options.movementMode)
	end

	local behavior = library.newBehavior()
	behavior.MaxDistance = options.maxDistance
	behavior.Acceleration = options.acceleration
	behavior.AutoIgnoreContainer = options.autoIgnoreContainer
	behavior.HighFidelityBehavior = options.highFidelityBehavior
	behavior.HighFidelitySegmentSize = options.highFidelitySegmentSize
	behavior.VisualizeCasts = options.visualizeCasts
	behavior.CloneTemplate = true
	behavior.FastCastEventsConfig.UseCastFire = true
	behavior.FastCastEventsConfig.UseCastTerminating = true

	local cosmeticTemplate = if options.cosmeticTemplate then options.cosmeticTemplate:Clone() else nil
	if cosmeticTemplate then
		cosmeticTemplate.Name = "FastCastBenchmarkProjectileTemplate"
		cosmeticTemplate.Anchored = true
		cosmeticTemplate.CanCollide = false
		cosmeticTemplate.CanQuery = false
		cosmeticTemplate.CanTouch = false
		cosmeticTemplate.CastShadow = false
		cosmeticTemplate.Massless = true
		cosmeticTemplate.Parent = ReplicatedStorage
	end
	behavior.CosmeticBulletTemplate = cosmeticTemplate

	local container = Instance.new("Folder")
	container.Name = "FastCastBenchmarkProjectiles"
	container.Parent = Workspace
	behavior.CosmeticBulletContainer = container

	local raycastParams = RaycastParams.new()
	raycastParams.FilterType = Enum.RaycastFilterType.Exclude
	raycastParams.FilterDescendantsInstances = { container }
	raycastParams.IgnoreWater = true
	behavior.RaycastParams = raycastParams

	local caster = library.new()
	local activeCasts = {}
	local firedCount = 0
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
	caster:SetMovementModeEnabled(true, options.movementMode)

	local result
	local heartbeatConnection = nil
	local ok, runError = xpcall(function()
		local random = Random.new(options.randomSeed)
		local creationStarted = os.clock()
		for _ = 1, options.projectileCount do
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
			fire(caster, options.castType, origin, direction, options, behavior)
		end
		local creationElapsed = os.clock() - creationStarted
		local creationMs = creationElapsed * 1000
		local creationProjectilesPerSecond = if creationElapsed > 0 then options.projectileCount / creationElapsed else 0

		-- Let the parallel runtime flush queued fire requests before sampling.
		task.wait()
		local frameTimes = {}
		local measuring = true
		heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
			if measuring and deltaTime > 0 then
				frameTimes[#frameTimes + 1] = deltaTime * 1000
			end
		end)
		task.wait(options.sampleDuration)
		measuring = false
		heartbeatConnection:Disconnect()
		heartbeatConnection = nil

		local frameStats = summarizeFrames(frameTimes)
		result = {
			mode = modeName,
			castType = options.castType,
			projectiles = options.projectileCount,
			firedCasts = firedCount,
			frames = frameStats.frames,
			averageFrameMs = frameStats.averageMs,
			averageFps = frameStats.averageFps,
			minFps = frameStats.minFps,
			maxFps = frameStats.maxFps,
			p50FrameMs = frameStats.p50Ms,
			p95FrameMs = frameStats.p95Ms,
			p99FrameMs = frameStats.p99Ms,
			creationMs = creationMs,
			creationProjectilesPerSecond = creationProjectilesPerSecond,
		}
	end, debug.traceback)

	-- Disconnect even when sampling throws, so the next mode cannot inherit a
	-- stale Heartbeat callback.
	if heartbeatConnection then
		heartbeatConnection:Disconnect()
	end

	-- Explicitly terminate remaining casts so one mode cannot pollute the next.
	local cleanupStarted = os.clock()
	local castsAtCleanupStart = #activeCasts
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
	pcall(function()
		caster:Destroy()
	end)
	local cleanupElapsed = os.clock() - cleanupStarted
	local cleanupMs = cleanupElapsed * 1000
	local cleanupProjectilesPerSecond = if cleanupElapsed > 0 then castsAtCleanupStart / cleanupElapsed else 0
	if cosmeticTemplate then pcall(function() cosmeticTemplate:Destroy() end) end
	pcall(function() container:Destroy() end)

	-- Match the upstream benchmark's recovery window, then reinitialize the
	-- selected runtime before another run can start. Cooldown is not included
	-- in the measured cleanup duration.
	task.wait(2.5)
	local recovered, recoveryError = pcall(function()
		if modeName == "Serial" then
			library.Init(options.movementMode)
		else
			library.Init(options.workerCount, options.movementMode)
		end
	end)

	if not ok then
		return { mode = modeName, castType = options.castType, cleanupMs = cleanupMs,
			cleanupCasts = castsAtCleanupStart, cleanupProjectilesPerSecond = cleanupProjectilesPerSecond,
			remainingCastsAtCleanup = #activeCasts, error = tostring(runError) }
	end
	if not recovered then
		return { mode = modeName, castType = options.castType, cleanupMs = cleanupMs,
			cleanupCasts = castsAtCleanupStart, cleanupProjectilesPerSecond = cleanupProjectilesPerSecond,
			remainingCastsAtCleanup = #activeCasts, error = "Runtime recovery failed: " .. tostring(recoveryError) }
	end
	result.cleanupMs = cleanupMs
	result.cleanupCasts = castsAtCleanupStart
	result.cleanupProjectilesPerSecond = cleanupProjectilesPerSecond
	result.remainingCastsAtCleanup = #activeCasts
	if #activeCasts > 0 then result.warning = "Cleanup timed out; active casts remain, so results may be contaminated." end
	return result
end

function Benchmark.run(options)
	local modeName = options.mode
	assert(modeName == "Serial" or modeName == "Parallel", "Benchmark mode must be Serial or Parallel")
	local ok, result = pcall(runMode, modeName, options)
	if not ok then
		result = { mode = modeName, castType = options.castType, error = tostring(result) }
	end
	return { result }
end

return Benchmark
