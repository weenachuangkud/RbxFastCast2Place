
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Reports = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2ToolReports"))

local IsRunning = false

local function cleanupLeftovers()
	for _, child in workspace:GetChildren() do
		if string.match(child.Name, "^FastCast2TestArena") then
			child:Destroy()
		end
	end
end

local function runMode(mode: "Serial" | "Parallel")
	local adapter = ReplicatedStorage:WaitForChild("FastCast2")
	adapter:SetAttribute("Mode", mode)

	if mode == "Parallel" and ReplicatedStorage:FindFirstChild("FastCast2TestSignal") == nil then
		local signal = Instance.new("BindableEvent")
		signal.Name = "FastCast2TestSignal"
		signal.Parent = ReplicatedStorage
	end

	local testModules = ReplicatedStorage:WaitForChild("FastCast2" .. mode .. "Tests")
	local Framework = require(testModules:WaitForChild("Framework"))
	local FunctionalTests = require(testModules:WaitForChild("FunctionalTests"))
	local report = Framework.run(FunctionalTests(), cleanupLeftovers)
	table.insert(Reports.UnitTest.modes, {
		mode = mode,
		passed = report.passed,
		failed = report.failed,
		total = report.total,
	})

	for _, group in report.groups do
		for _, case in group.cases do
			if case.status == "failed" then
				table.insert(Reports.UnitTest.failures, {
					mode = mode,
					name = group.name .. ": " .. case.name,
					error = case.error,
				})
			end
		end
	end

	print(string.format(
		"[FastCast2 UnitTest] %s: %d passed, %d failed, %d total (%.1f ms)",
		mode,
		report.passed,
		report.failed,
		report.total,
		report.durationMs
	))
	return report
end

local function runTests()
	if IsRunning then
		warn("[FastCast2 UnitTest] A test run is already in progress.")
		return
	end
	if Reports.Benchmark.status == "Running" or Reports.PerfBench.status == "Running" then
		warn("[FastCast2 UnitTest] Wait for the benchmark run to finish first.")
		return
	end
	local initialized, initializeError = pcall(function()
		Wrapper:Initialize()
	end)
	if not initialized then
		Reports.UnitTest = {
			status = "Failed",
			modes = {},
			failures = {},
			error = tostring(initializeError),
		}
		warn("[FastCast2 UnitTest] Could not initialize FastCast2:", initializeError)
		return
	end

	IsRunning = true
	Reports.UnitTest = { status = "Running", modes = {}, failures = {}, error = nil }
	task.spawn(function()
		local ok, err = pcall(function()
			local serialReport = runMode("Serial")
			cleanupLeftovers()
			local parallelReport = runMode("Parallel")
			cleanupLeftovers()
			local failed = serialReport.failed + parallelReport.failed
			Reports.UnitTest.status = if failed == 0 then "Complete" else "Failed"
			print(string.format(
				"[FastCast2 UnitTest] Complete: %d passed, %d failed",
				serialReport.passed + parallelReport.passed,
				failed
			))
		end)
		if not ok then
			cleanupLeftovers()
			Reports.UnitTest.status = "Failed"
			Reports.UnitTest.error = tostring(err)
			warn("[FastCast2 UnitTest] Run failed:", err)
		end
		IsRunning = false
	end)
end

Tool.Activated:Connect(runTests)
