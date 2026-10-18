local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local Libraries = {
	Serial = require(ReplicatedStorage:WaitForChild("FastCast2Serial")),
	Parallel = require(ReplicatedStorage:WaitForChild("FastCast2Parallel")),
}

local Benchmark = {}

local function summarizeFrames(frameTimes: { number })
	if #frameTimes == 0 then
		return 0, 0, 0
	end

	local sorted = table.clone(frameTimes)
	table.sort(sorted)
	local total = 0
	for _, value in frameTimes do
		total += value
	end

	local function percentile(fraction: number): number
		return sorted[math.max(1, math.ceil(#sorted * fraction))]
	end

	return total / #frameTimes, percentile(0.95), percentile(0.99)
end

local function fire(caster: any, castType: string, origin: Vector3, direction: Vector3, options: any, behavior: any)
	if castType == "Blockcast" then
		caster:BlockcastFire(origin, options.blockcastSize, direction, options.velocity, behavior)
	elseif castType == "Spherecast" then
		caster:SpherecastFire(origin, options.spherecastRadius, direction, options.velocity, behavior)
	else
		caster:RaycastFire(origin, direction, options.velocity, behavior)
	end
end

local function runMode(modeName: string, options: any): any
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
	caster:SetMovementModeEnabled(true, options.movementMode)

	local count = 0
	caster.CastFire = function()
		count += 1
	end

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
	local creationMs = (os.clock() - creationStarted) * 1000

	task.wait()
	local frameTimes = {}
	local measuring = true
	local heartbeatConnection = RunService.Heartbeat:Connect(function(deltaTime)
		if measuring and deltaTime > 0 then
			table.insert(frameTimes, deltaTime * 1000)
		end
	end)
	task.wait(options.sampleDuration)
	measuring = false
	heartbeatConnection:Disconnect()
	local averageFrameMs, p95FrameMs, p99FrameMs = summarizeFrames(frameTimes)

	local cleanupStarted = os.clock()
	caster:Destroy()
	local cleanupMs = (os.clock() - cleanupStarted) * 1000
	if cosmeticTemplate then
		cosmeticTemplate:Destroy()
	end
	container:Destroy()

	return {
		mode = modeName,
		castType = options.castType,
		projectiles = options.projectileCount,
		activeCasts = count,
		creationMs = creationMs,
		averageFrameMs = averageFrameMs,
		p95FrameMs = p95FrameMs,
		p99FrameMs = p99FrameMs,
		cleanupMs = cleanupMs,
	}
end

function Benchmark.run(options: any): { any }
	local results = {}
	for _, modeName in { "Serial", "Parallel" } do
		local ok, result = pcall(runMode, modeName, options)
		if ok then
			table.insert(results, result)
		else
			table.insert(results, { mode = modeName, castType = options.castType, error = tostring(result) })
		end
		task.wait(1)
	end
	return results
end

return Benchmark
