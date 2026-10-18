-- Runs benchmark workloads on the server so server Heartbeat results are measured
-- in the server process, not approximated from a client's frame timings.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StarterPack = game:GetService("StarterPack")

local remote = ReplicatedStorage:FindFirstChild("FastCast2BenchmarkRemote")
if not remote then
	remote = Instance.new("RemoteFunction")
	remote.Name = "FastCast2BenchmarkRemote"
	remote.Parent = ReplicatedStorage
end

local busy = false
local lastRequestAt = {}

local function ownsTool(player, name)
	local character = player.Character
	local backpack = player:FindFirstChildOfClass("Backpack")
	return (character and character:FindFirstChild(name) ~= nil)
		or (backpack and backpack:FindFirstChild(name) ~= nil)
end

local function finiteNumber(value)
	return type(value) == "number" and value == value and math.abs(value) < math.huge
end

local function validateCommon(options)
	if type(options) ~= "table" then
		return false, "Options must be a table."
	end
	if options.mode ~= "Serial" and options.mode ~= "Parallel" then
		return false, "Invalid library mode."
	end
	if not finiteNumber(options.projectileCount) then
		return false, "Invalid projectile count."
	end
	if not finiteNumber(options.sampleDuration) then
		return false, "Invalid sample duration."
	end
	return true
end

local function runBenchmark(options)
	local valid, reason = validateCommon(options)
	if not valid then
		return { error = reason }
	end

	local benchmarkTool = StarterPack:FindFirstChild("Benchmark")
	local runnerModule = benchmarkTool and benchmarkTool:FindFirstChild("BenchmarkRunner")
	if not runnerModule or not runnerModule:IsA("ModuleScript") then
		return { error = "Server BenchmarkRunner module is missing." }
	end

	local serverTemplate
	local serverOptions = table.clone(options)
	serverOptions.projectileCount = math.clamp(math.floor(options.projectileCount), 1, 100000)
	serverOptions.sampleDuration = math.clamp(options.sampleDuration, 1, 10)
	serverOptions.workerCount = math.clamp(math.floor(options.workerCount or 4), 1, 32)
	serverOptions.cosmeticTemplate = nil

	if options.cosmeticMode == "Instanced" then
		serverTemplate = Instance.new("Part")
		serverTemplate.Name = "FastCast2ServerBenchmarkTemplate"
		serverTemplate.Size = Vector3.one
		serverTemplate.Anchored = true
		serverTemplate.CanCollide = false
		serverTemplate.CanQuery = false
		serverTemplate.CanTouch = false
		serverTemplate.CastShadow = false
		serverTemplate.Massless = true
		serverTemplate.Parent = ReplicatedStorage
		serverOptions.cosmeticTemplate = serverTemplate
	end

	local ok, result = pcall(function()
		return require(runnerModule).run(serverOptions)
	end)
	if serverTemplate then
		serverTemplate:Destroy()
	end
	if not ok then
		return { error = tostring(result) }
	end
	for _, item in result do
		item.side = "Server"
	end
	return { results = result }
end

local function runPerfBench(options)
	local valid, reason = validateCommon(options)
	if not valid then
		return { error = reason }
	end
	local perfTool = StarterPack:FindFirstChild("PerfBench")
	local runnerModule = perfTool and perfTool:FindFirstChild("PerfBenchRunner")
	if not runnerModule or not runnerModule:IsA("ModuleScript") then
		return { error = "Server PerfBenchRunner module is missing." }
	end

	local safeOptions = {
		projectileCount = math.clamp(math.floor(options.projectileCount), 1, 100000),
		maxProjectileCount = 100000,
		sampleDuration = math.clamp(options.sampleDuration, 1, 5),
		mode = options.mode,
		workerCount = math.clamp(math.floor(options.workerCount or 4), 1, 32),
		instanced = options.instanced == true,
		includeMovementEnabled = options.includeMovementEnabled == true,
		includeMovementDisabled = options.includeMovementDisabled == true,
	}

	local ok, results = pcall(function()
		return require(runnerModule).run(safeOptions)
	end)
	if not ok then
		return { error = tostring(results) }
	end
	for _, item in results do
		item.side = "Server"
	end
	return { results = results }
end

remote.OnServerInvoke = function(player, action, options)
	local toolName = if action == "Benchmark" then "Benchmark" elseif action == "PerfBench" then "PerfBench" else nil
	if not toolName or not ownsTool(player, toolName) then
		return { error = "Equip the matching benchmark tool before requesting a server run." }
	end
	local now = os.clock()
	if busy or now - (lastRequestAt[player] or 0) < 3 then
		return { error = "A benchmark is already running or requests are rate-limited." }
	end
	busy = true
	lastRequestAt[player] = now
	local ok, result = pcall(function()
		if action == "Benchmark" then
			return runBenchmark(options)
		end
		return runPerfBench(options)
	end)
	busy = false
	if not ok then
		return { error = tostring(result) }
	end
	return result
end
