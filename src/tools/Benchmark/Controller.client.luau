local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2BenchmarkSettings"))
local Reports = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2ToolReports"))

local IsRunning = false

local function runBenchmark()
	if IsRunning then
		warn("[FastCast2 Benchmark] A benchmark is already running.")
		return
	end
	if Reports.UnitTest.status == "Running" then
		warn("[FastCast2 Benchmark] Wait for the unit test run to finish first.")
		return
	end
	if Reports.PerfBench.status == "Running" then
		warn("[FastCast2 Benchmark] Wait for the PerfBench run to finish first.")
		return
	end
	local initialized, initializeError = pcall(function()
		Wrapper:Initialize()
	end)
	if not initialized then
		Reports.Benchmark = {
			status = "Failed",
			results = {},
			error = tostring(initializeError),
		}
		warn("[FastCast2 Benchmark] Could not initialize FastCast2:", initializeError)
		return
	end

	IsRunning = true
	Reports.Benchmark = { status = "Running", results = {}, error = nil }
	task.spawn(function()
		local ok, resultOrError = pcall(function()
			local BenchmarkRunner = require(script.Parent:WaitForChild("BenchmarkRunner"))
			local options = {
				projectileCount = math.clamp(math.floor(Settings.ProjectileCount), 1, Settings.MaxProjectileCount),
				sampleDuration = math.clamp(Settings.SampleDuration, 1, 10),
				mode = Wrapper.Settings.Mode,
				workerCount = Wrapper.Settings.WorkerCount,
				castType = Wrapper.Settings.CastType,
				movementMode = Wrapper.Settings.MovementMode,
				velocity = Wrapper.Settings.Velocity,
				blockcastSize = Wrapper.Settings.BlockcastSize,
				spherecastRadius = Wrapper.Settings.SpherecastRadius,
				maxDistance = Wrapper.Behavior.MaxDistance,
				acceleration = Wrapper.Behavior.Acceleration,
				autoIgnoreContainer = Wrapper.Behavior.AutoIgnoreContainer,
				highFidelityBehavior = Wrapper.Behavior.HighFidelityBehavior,
				highFidelitySegmentSize = Wrapper.Behavior.HighFidelitySegmentSize,
				visualizeCasts = Wrapper.Behavior.VisualizeCasts,
				cosmeticTemplate = if Wrapper.Settings.CosmeticMode == "Instanced"
					then Wrapper.Behavior.CosmeticBulletTemplate
					else nil,
				randomSeed = 2026,
			}
			local results = BenchmarkRunner.run(options)
			local remote = ReplicatedStorage:WaitForChild("FastCast2BenchmarkRemote")
			local serverOptions = table.clone(options)
			serverOptions.cosmeticTemplate = nil
			serverOptions.cosmeticMode = Wrapper.Settings.CosmeticMode
			local serverResponse = remote:InvokeServer("Benchmark", serverOptions)
			if serverResponse and serverResponse.results then
				for _, result in serverResponse.results do
					table.insert(results, result)
				end
			elseif serverResponse and serverResponse.error then
				table.insert(results, { side = "Server", error = serverResponse.error })
			end
			for _, result in results do
				result.side = result.side or "Client"
			end
			return results
		end)

		if ok then
			local failedCase = false
			for _, result in resultOrError do
				failedCase = failedCase or result.error ~= nil
			end
			Reports.Benchmark = {
				status = if failedCase then "Failed" else "Complete",
				results = resultOrError,
				error = nil,
			}
			print("[FastCast2 Benchmark] Complete for " .. Wrapper.Settings.Mode .. " / " .. Wrapper.Settings.CastType .. ". See ConfigUI for the results table.")
		else
			Reports.Benchmark = {
				status = "Failed",
				results = {},
				error = tostring(resultOrError),
			}
			warn("[FastCast2 Benchmark] Run failed:", resultOrError)
		end
		IsRunning = false
	end)
end

Tool.Activated:Connect(runBenchmark)
