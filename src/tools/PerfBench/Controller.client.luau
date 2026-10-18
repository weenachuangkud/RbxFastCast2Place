local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Settings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2PerfBenchSettings"))
local Reports = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2ToolReports"))

local IsRunning = false

local function runPerfBench()
	if IsRunning then
		warn("[FastCast2 PerfBench] A run is already in progress.")
		return
	end
	if Reports.UnitTest.status == "Running" or Reports.Benchmark.status == "Running" then
		warn("[FastCast2 PerfBench] Wait for the current test or benchmark run to finish first.")
		return
	end

	local initialized, initializeError = pcall(function()
		Wrapper:Initialize()
	end)
	if not initialized then
		Reports.PerfBench = { status = "Failed", results = {}, error = tostring(initializeError) }
		warn("[FastCast2 PerfBench] Could not initialize FastCast2:", initializeError)
		return
	end

	IsRunning = true
	Reports.PerfBench = { status = "Running", results = {}, error = nil }
	task.spawn(function()
		local ok, resultsOrError = pcall(function()
			local options = {
				projectileCount = math.clamp(math.floor(Settings.ProjectileCount), 1, Settings.MaxProjectileCount),
				maxProjectileCount = Settings.MaxProjectileCount,
				sampleDuration = math.clamp(Settings.SampleDuration, 1, 10),
				mode = Wrapper.Settings.Mode,
				workerCount = Wrapper.Settings.WorkerCount,
				instanced = Settings.Instanced,
				includeMovementEnabled = Settings.IncludeMovementEnabled,
				includeMovementDisabled = Settings.IncludeMovementDisabled,
			}
			local remote = ReplicatedStorage:WaitForChild("FastCast2BenchmarkRemote", 10)
			if not remote then error("Server benchmark endpoint was not available within 10 seconds.") end
			local response = remote:InvokeServer("PerfBench", options)
			if response and response.results then
				for _, result in response.results do result.side = "Server" end
				return response.results
			end
			error(if response and response.error then response.error else "Server PerfBench returned no results.")
		end)

		if ok then
			local failedCase = false
			for _, result in resultsOrError do
				failedCase = failedCase or result.error ~= nil
			end
			Reports.PerfBench = {
				status = if failedCase then "Failed" else "Complete",
				results = resultsOrError,
				error = nil,
			}
			print("[FastCast2 PerfBench] Complete. See ConfigUI for the results table.")
		else
			Reports.PerfBench = { status = "Failed", results = {}, error = tostring(resultsOrError) }
			warn("[FastCast2 PerfBench] Run failed:", resultsOrError)
		end
		IsRunning = false
	end)
end

Tool.Activated:Connect(runPerfBench)
