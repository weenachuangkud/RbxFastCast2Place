local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Iris = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IrisClient"))
local BenchmarkSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2BenchmarkSettings"))
local PerfBenchSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2PerfBenchSettings"))
local Reports = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2ToolReports"))

-- These are the actual Config ModuleScripts used by each vendored library.
local SerialConfig = require(ReplicatedStorage:WaitForChild("FastCast2Serial"):WaitForChild("Config"))
local ParallelConfig = require(ReplicatedStorage:WaitForChild("FastCast2Parallel"):WaitForChild("Config"))
local SerialSimulation = require(ReplicatedStorage.FastCast2Serial:WaitForChild("SerialSimulation"))
local ParallelSimulation = require(ReplicatedStorage.FastCast2Parallel:WaitForChild("ParallelSimulation"))

local Equipped = false
local ModeSwitching = false

local States = {
	ConfigTarget = Iris.State("Serial"),
	ConfigSimulationMode = Iris.State(SerialConfig.SimulationMode),
	ConfigVisualizeCasts = Iris.State(SerialConfig.VisualizeCasts),
	ConfigFixedFrequency = Iris.State(tostring(SerialConfig.FixedSimulationFrequency)),
	ConfigCosmeticUpdateInterval = Iris.State(SerialConfig.CosmeticUpdateInterval),
	DebugCasting = Iris.State(SerialConfig.DebugLogging.Casting),
	DebugSegment = Iris.State(SerialConfig.DebugLogging.Segment),
	DebugHit = Iris.State(SerialConfig.DebugLogging.Hit),
	DebugPierced = Iris.State(SerialConfig.DebugLogging.Pierced),
	DebugCalculation = Iris.State(SerialConfig.DebugLogging.Calculation),
	ProjectileCount = Iris.State(BenchmarkSettings.ProjectileCount),
	SampleDuration = Iris.State(BenchmarkSettings.SampleDuration),
	WorkerCount = Iris.State(Wrapper.Settings.WorkerCount),
	PerfProjectileCount = Iris.State(PerfBenchSettings.ProjectileCount),
	PerfSampleDuration = Iris.State(PerfBenchSettings.SampleDuration),
	PerfInstanced = Iris.State(PerfBenchSettings.Instanced),
	PerfMovementEnabled = Iris.State(PerfBenchSettings.IncludeMovementEnabled),
	PerfMovementDisabled = Iris.State(PerfBenchSettings.IncludeMovementDisabled),
	Velocity = Iris.State(Wrapper.Settings.Velocity),
	BlockcastSize = Iris.State(Wrapper.Settings.BlockcastSize.X),
	SpherecastRadius = Iris.State(Wrapper.Settings.SpherecastRadius),
	MaxDistance = Iris.State(Wrapper.Behavior.MaxDistance),
	HighFidelitySegmentSize = Iris.State(Wrapper.Behavior.HighFidelitySegmentSize),
	AccelerationY = Iris.State(Wrapper.Behavior.Acceleration.Y),
	VisualizeCasts = Iris.State(Wrapper.Behavior.VisualizeCasts),
	AutoIgnoreContainer = Iris.State(Wrapper.Behavior.AutoIgnoreContainer),
	UISectionModuleConfig = Iris.State(true),
	UISectionBenchmark = Iris.State(true),
	UISectionPerfBench = Iris.State(false),
	UISectionUnitTests = Iris.State(false),
	UISectionRuntime = Iris.State(true),
}

local function RequestMode(mode: "Serial" | "Parallel")
	if ModeSwitching or Wrapper.State == "Initializing" then
		return
	end
	if Wrapper.Settings.Mode == mode and Wrapper:IsReady() then
		return
	end

	ModeSwitching = true
	task.spawn(function()
		local ok, err = pcall(function()
			Wrapper:SetMode(mode)
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Could not switch mode:", err)
		else
			States.MaxDistance:set(Wrapper.Behavior.MaxDistance)
			States.HighFidelitySegmentSize:set(Wrapper.Behavior.HighFidelitySegmentSize)
			States.AccelerationY:set(Wrapper.Behavior.Acceleration.Y)
		end
		ModeSwitching = false
	end)
end

local function RequestWorkerCount(workerCount: number)
	if ModeSwitching or Wrapper.State == "Initializing" then
		return
	end
	workerCount = math.clamp(math.floor(workerCount), 1, 32)
	if workerCount == Wrapper.Settings.WorkerCount then
		States.WorkerCount:set(workerCount)
		return
	end
	if Reports.Benchmark.status == "Running" or Reports.PerfBench.status == "Running" or Reports.UnitTest.status == "Running" then
		States.WorkerCount:set(Wrapper.Settings.WorkerCount)
		warn("[FastCast2 ConfigUI] Wait for the current benchmark or test to finish before resizing Actors.")
		return
	end

	States.WorkerCount:set(workerCount)
	ModeSwitching = true
	task.spawn(function()
		local ok, err = pcall(function()
			Wrapper:SetWorkerCount(workerCount)
		end)
		if not ok then
			States.WorkerCount:set(Wrapper.Settings.WorkerCount)
			warn("[FastCast2 ConfigUI] Could not change Actor count:", err)
		end
		ModeSwitching = false
	end)
end

local function GetConfigTarget()
	if States.ConfigTarget.value == "Parallel" then
		return ParallelConfig, ParallelSimulation
	end
	return SerialConfig, SerialSimulation
end

local function IsTestRunning()
	return Reports.Benchmark.status == "Running"
		or Reports.PerfBench.status == "Running"
		or Reports.UnitTest.status == "Running"
end

local function RestartSelectedSimulation(simulation)
	if IsTestRunning() then
		return false
	end
	local ok, err = pcall(function()
		simulation.Stop()
		simulation.Start()
	end)
	if not ok then
		warn("[FastCast2 ConfigUI] Could not restart simulation after Config change:", err)
		return false
	end
	return true
end

local function GetFrequencyName(frequency)
	if frequency == Enum.StepFrequency.Hz30 then return "Hz30" end
	if frequency == Enum.StepFrequency.Hz120 then return "Hz120" end
	return "Hz60"
end

local function SyncServerModuleConfig(target: "Serial" | "Parallel", config)
	task.spawn(function()
		local remote = ReplicatedStorage:WaitForChild("FastCast2BenchmarkRemote", 10)
		if not remote then
			warn("[FastCast2 ConfigUI] Server Config endpoint is unavailable; only the client Config was changed.")
			return
		end
		local ok, response = pcall(function()
			return remote:InvokeServer("SetModuleConfig", {
				target = target,
				simulationMode = config.SimulationMode,
				fixedFrequency = GetFrequencyName(config.FixedSimulationFrequency),
			})
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Could not sync server Config:", response)
		elseif not response or not response.ok then
			warn("[FastCast2 ConfigUI] Server Config was not changed:", if response then response.error else "No response")
		end
	end)
end

local function RenderLibraryConfig()
	local section = Iris.Tree({ "FastCast2 module Config" }, { isUncollapsed = States.UISectionModuleConfig })
	if section.state.isUncollapsed.value then
			Iris.Text({ "Edit the module Config for this client and sync SimulationMode / fixed frequency to the server." })
		local function LoadConfigStates(target: "Serial" | "Parallel")
			local config = if target == "Parallel" then ParallelConfig else SerialConfig
			States.ConfigSimulationMode:set(config.SimulationMode)
			States.ConfigVisualizeCasts:set(config.VisualizeCasts)
			States.ConfigFixedFrequency:set(tostring(config.FixedSimulationFrequency))
			States.ConfigCosmeticUpdateInterval:set(config.CosmeticUpdateInterval)
			States.DebugCasting:set(config.DebugLogging.Casting)
			States.DebugSegment:set(config.DebugLogging.Segment)
			States.DebugHit:set(config.DebugLogging.Hit)
			States.DebugPierced:set(config.DebugLogging.Pierced)
			States.DebugCalculation:set(config.DebugLogging.Calculation)
		end

		for _, target in { "Serial", "Parallel" } do
			if Iris.Button({ target .. " Config" }).clicked() and States.ConfigTarget.value ~= target then
				States.ConfigTarget:set(target)
				LoadConfigStates(target)
				local targetConfig = if target == "Parallel" then ParallelConfig else SerialConfig
				SyncServerModuleConfig(target, targetConfig)
			end
		end

		local config, simulation = GetConfigTarget()

		Iris.Text({ "Editing: " .. States.ConfigTarget.value })
		Iris.Text({ "Simulation mode: " .. config.SimulationMode })
		for _, mode in { "PerFrame", "Fixed" } do
			if Iris.Button({ mode }).clicked() and config.SimulationMode ~= mode then
				if IsTestRunning() then
					warn("[FastCast2 ConfigUI] Finish benchmarks/tests before changing SimulationMode.")
				else
					local previousMode = config.SimulationMode
					config.SimulationMode = mode
					if not RestartSelectedSimulation(simulation) then
						config.SimulationMode = previousMode
					else
						SyncServerModuleConfig(States.ConfigTarget.value, config)
					end
					States.ConfigSimulationMode:set(config.SimulationMode)
				end
			end
		end

		Iris.Text({ "Fixed simulation frequency: " .. tostring(config.FixedSimulationFrequency) })
		for _, frequency in {
			{ name = "Hz30", value = Enum.StepFrequency.Hz30 },
			{ name = "Hz60", value = Enum.StepFrequency.Hz60 },
			{ name = "Hz120", value = Enum.StepFrequency.Hz120 },
		} do
			if Iris.Button({ frequency.name }).clicked() and config.FixedSimulationFrequency ~= frequency.value then
				if IsTestRunning() then
					warn("[FastCast2 ConfigUI] Finish benchmarks/tests before changing fixed frequency.")
				else
					local previousFrequency = config.FixedSimulationFrequency
					config.FixedSimulationFrequency = frequency.value
					if config.SimulationMode == "Fixed" and not RestartSelectedSimulation(simulation) then
						config.FixedSimulationFrequency = previousFrequency
					else
						SyncServerModuleConfig(States.ConfigTarget.value, config)
					end
					States.ConfigFixedFrequency:set(tostring(config.FixedSimulationFrequency))
				end
			end
		end

		local visualize = Iris.Checkbox({ "Config.VisualizeCasts" }, { isChecked = States.ConfigVisualizeCasts })
		if visualize.checked() or visualize.unchecked() then
			config.VisualizeCasts = States.ConfigVisualizeCasts.value
		end

		local interval = Iris.InputNum(
			{ "Config.CosmeticUpdateInterval" },
			{ number = States.ConfigCosmeticUpdateInterval }
		)
		if interval.numberChanged() then
			local value = math.clamp(math.floor(States.ConfigCosmeticUpdateInterval.value), 1, 120)
			States.ConfigCosmeticUpdateInterval:set(value)
			config.CosmeticUpdateInterval = value
		end

		Iris.SeparatorText({ "Config.DebugLogging" })
		for _, entry in {
			{ label = "Casting", key = "Casting", state = States.DebugCasting },
			{ label = "Segment", key = "Segment", state = States.DebugSegment },
			{ label = "Hit", key = "Hit", state = States.DebugHit },
			{ label = "Pierced", key = "Pierced", state = States.DebugPierced },
			{ label = "Calculation", key = "Calculation", state = States.DebugCalculation },
		} do
			local checkbox = Iris.Checkbox({ entry.label }, { isChecked = entry.state })
			if checkbox.checked() or checkbox.unchecked() then
				config.DebugLogging[entry.key] = entry.state.value
			end
		end
		Iris.Text({ "Config edits are local to this client. SimulationMode and fixed frequency are synced to the server." })
	end
	Iris.End()
end

local function RenderCosmeticSettings()
	Iris.SeparatorText({ "Cosmetic projectile" })

	if Iris.Button({ "Instanced" }).clicked() then
		local ok, err = pcall(function()
			Wrapper:SetCosmeticMode("Instanced")
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Could not enable instanced cosmetics:", err)
		end
	end
	if Iris.Button({ "Instanceless" }).clicked() then
		local ok, err = pcall(function()
			Wrapper:SetCosmeticMode("Instanceless")
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Could not disable cosmetic instances:", err)
		end
	end
	Iris.Text({ "Mode: " .. Wrapper.Settings.CosmeticMode })

	if Wrapper.Settings.CosmeticMode == "Instanced" then
		local folder = ReplicatedStorage:FindFirstChild("Projectiles")
		Iris.Text({ "Projectiles in ReplicatedStorage.Projectiles:" })

		if folder then
			local foundProjectile = false
			for _, item in folder:GetChildren() do
				if item:IsA("BasePart") then
					foundProjectile = true
					if Iris.Button({ item.Name }).clicked() then
						local ok, err = pcall(function()
							Wrapper:SetCosmeticProjectile(item.Name)
						end)
						if not ok then
							warn("[FastCast2 ConfigUI] Could not select projectile:", err)
						end
					end
				end
			end
			Iris.Text({ "Selected: " .. (Wrapper.Settings.CosmeticProjectileName or "Default part") })

			if not foundProjectile then
				Iris.Text({ "No BasePart projectiles found; using the default 1x1x1 part." })
			end
		else
			Iris.Text({ "Projectiles folder is missing; using the default 1x1x1 part." })
		end

		if Iris.Button({ "Use default 1x1x1 part" }).clicked() then
			local ok, err = pcall(function()
				Wrapper:SetCosmeticProjectile(nil)
			end)
			if not ok then
				warn("[FastCast2 ConfigUI] Could not select default projectile:", err)
			end
		end
	end
end

local function RenderConfig()
	local window = Iris.Window({ "FastCast2 Config" })
	if window.state.isOpened.value then
		RenderLibraryConfig()

		local benchmarkSection = Iris.Tree({ "Benchmark settings & results" }, { isUncollapsed = States.UISectionBenchmark })
		if benchmarkSection.state.isUncollapsed.value then
			local projectileCount = Iris.InputNum(
				{ "Projectile count" },
				{ number = States.ProjectileCount }
			)
			if projectileCount.numberChanged() then
				local count = math.clamp(
					math.floor(States.ProjectileCount.value),
					1,
					BenchmarkSettings.MaxProjectileCount
				)
				States.ProjectileCount:set(count)
				BenchmarkSettings.ProjectileCount = count
			end
			Iris.Text({ string.format("Default: 500 | allowed range: 1 to %d.", BenchmarkSettings.MaxProjectileCount) })
			local sampleDuration = Iris.SliderNum(
				{ "Sample duration (seconds)", 1, 1, 10 },
				{ number = States.SampleDuration }
			)
			if sampleDuration.numberChanged() then
				BenchmarkSettings.SampleDuration = States.SampleDuration.value
			end
			Iris.Text({ "Cast mode: " .. Wrapper.Settings.Mode })
			for _, mode in { "Serial", "Parallel" } do
				if Iris.Button({ mode }).clicked() then
					RequestMode(mode)
				end
			end

			Iris.Text({ "Benchmark follows the selected fire context (Client / Server / Both). PerfBench always runs on the server and uses the server's current FastCast2 module Config." })
			local workerCount = Iris.InputNum(
				{ "Parallel Actor count" },
				{ number = States.WorkerCount }
			)
			if workerCount.numberChanged() then
				RequestWorkerCount(States.WorkerCount.value)
			end
			Iris.Text({ "Used by Parallel mode only; changing the active Actor pool pauses the wrapper for 6 seconds." })
			if not ModeSwitching then
				States.WorkerCount:set(Wrapper.Settings.WorkerCount)
			end
			Iris.SeparatorText({ "Latest Benchmark Results" })
			Iris.Text({ "Benchmark status: " .. Reports.Benchmark.status })
			if Reports.Benchmark.error then
				Iris.Text({ "Benchmark error: " .. Reports.Benchmark.error })
			end
			for _, result in Reports.Benchmark.results do
				if result.error then
					Iris.SeparatorText({ string.format("%s / %s / %s", result.side or "Client", result.mode or "Benchmark", result.castType or "") })
					Iris.Text({ "Error: " .. result.error })
				else
					Iris.SeparatorText({ string.format("%s / %s / %s", result.side or "Client", result.mode, result.castType) })
					Iris.Text({ string.format(
						"Casts: %d fired | %d remaining at cleanup",
						result.firedCasts or 0,
						result.remainingCastsAtCleanup or 0
					) })
					Iris.Text({ string.format(
						"FPS: average %.2f | minimum %.2f | maximum %.2f",
						result.averageFps,
						result.minFps,
						result.maxFps
					) })
					Iris.Text({ string.format(
						"Frame time: %d frames | average %.2f ms | P50 %.2f | P95 %.2f | P99 %.2f ms",
						result.frames,
						result.averageFrameMs,
						result.p50FrameMs,
						result.p95FrameMs,
						result.p99FrameMs
					) })
					Iris.Text({ string.format("Create: %.2f ms (%.0f casts/s) | cleanup: %.2f ms (%.0f casts/s)", result.creationMs, result.creationProjectilesPerSecond or 0, result.cleanupMs, result.cleanupProjectilesPerSecond or 0) })
				end
			end

		end
		Iris.End()

		local perfBenchSection = Iris.Tree({ "PerfBench settings & results" }, { isUncollapsed = States.UISectionPerfBench })
		if perfBenchSection.state.isUncollapsed.value then
			local perfProjectileCount = Iris.InputNum(
				{ "PerfBench projectile count" },
				{ number = States.PerfProjectileCount }
			)
			if perfProjectileCount.numberChanged() then
				local count = math.clamp(
					math.floor(States.PerfProjectileCount.value),
					1,
					PerfBenchSettings.MaxProjectileCount
				)
				States.PerfProjectileCount:set(count)
				PerfBenchSettings.ProjectileCount = count
			end
			Iris.Text({ string.format("Default: 6,000 | allowed range: 1 to %d.", PerfBenchSettings.MaxProjectileCount) })
			local perfSampleDuration = Iris.SliderNum(
				{ "PerfBench sample duration (seconds)", 5, 1, 10 },
				{ number = States.PerfSampleDuration }
			)
			if perfSampleDuration.numberChanged() then
				PerfBenchSettings.SampleDuration = States.PerfSampleDuration.value
			end
			local perfInstanced = Iris.Checkbox(
				{ "PerfBench instanced projectiles" },
				{ isChecked = States.PerfInstanced }
			)
			if perfInstanced.checked() or perfInstanced.unchecked() then
				PerfBenchSettings.Instanced = States.PerfInstanced.value
			end
			for _, toggle in {
				{ label = "Movement enabled case", state = States.PerfMovementEnabled, key = "IncludeMovementEnabled" },
				{ label = "Movement disabled case", state = States.PerfMovementDisabled, key = "IncludeMovementDisabled" },
			} do
				local checkbox = Iris.Checkbox({ "PerfBench " .. toggle.label }, { isChecked = toggle.state })
				if checkbox.checked() or checkbox.unchecked() then
					PerfBenchSettings[toggle.key] = toggle.state.value
				end
			end
			Iris.Text({ "PerfBench runs on the server only and reads the server's own FastCast2 Config. The Config editor syncs SimulationMode and fixed frequency to the server when changed." })
			Iris.SeparatorText({ "Latest PerfBench Results" })
			Iris.Text({ "PerfBench status: " .. Reports.PerfBench.status })
			if Reports.PerfBench.error then
				Iris.Text({ "PerfBench error: " .. Reports.PerfBench.error })
			end
			if #Reports.PerfBench.results > 0 then
				Iris.Text({ "Server Heartbeat stress benchmark using the current FastCast2 Config (instancing and movement toggled):" })
			end
			for _, result in Reports.PerfBench.results do
				if result.error then
					Iris.SeparatorText({ string.format("%s / %s / %s", result.side or "Client", result.mode or "PerfBench", result.simulationMode or "") })
					Iris.Text({ "Error: " .. result.error })
				else
					Iris.SeparatorText({ string.format("%s / %s / %s", result.side or "Client", result.mode or "PerfBench", result.simulationMode or "") })
					Iris.Text({ string.format(
						"Setup: instanced %s | movement %s",
						tostring(result.instanced),
						tostring(result.movement)
					) })
					Iris.Text({ string.format(
						"Casts: %d fired | %d remaining at cleanup",
						result.firedCasts or 0,
						result.remainingCastsAtCleanup or 0
					) })
					Iris.Text({ string.format(
						"Frame time: average %.2f ms | P50 %.2f | P95 %.2f | P99 %.2f ms",
						result.averageFrameMs,
						result.p50FrameMs,
						result.p95FrameMs,
						result.p99FrameMs
					) })
					Iris.Text({ string.format("Create: %.2f ms (%.0f casts/s) | cleanup: %.2f ms (%.0f casts/s)", result.creationMs, result.creationProjectilesPerSecond or 0, result.cleanupMs, result.cleanupProjectilesPerSecond or 0) })
				end
			end

		end
		Iris.End()

		local unitTestsSection = Iris.Tree({ "Unit test results" }, { isUncollapsed = States.UISectionUnitTests })
		if unitTestsSection.state.isUncollapsed.value then
			Iris.Text({ "Unit test status: " .. Reports.UnitTest.status })
			for _, result in Reports.UnitTest.modes do
				Iris.Text({
					string.format("%s: %d passed / %d, %d failed", result.mode, result.passed, result.total, result.failed),
				})
			end
			for _, failure in Reports.UnitTest.failures do
				Iris.Text({ string.format("FAIL %s / %s: %s", failure.mode, failure.name, failure.error) })
			end
			if Reports.UnitTest.error then
				Iris.Text({ "Unit test error: " .. Reports.UnitTest.error })
			end

		end
		Iris.End()

		local runtimeSection = Iris.Tree({ "Runtime status & firing controls" }, { isUncollapsed = States.UISectionRuntime })
		if runtimeSection.state.isUncollapsed.value then
			Iris.Text({ "Wrapper state: " .. Wrapper.State })
			Iris.Text({ "Settings apply to future casts." })
			Iris.SeparatorText({ "Fire context" })
			for _, context in { "Client", "Server", "Both" } do
				if Iris.Button({ context }).clicked() then
					Wrapper:SetContext(context)
				end
			end
			Iris.Text({ "Selected: " .. Wrapper.Settings.Context })
			Iris.Text({ if Wrapper.Settings.Context == "Client"
				then "Client: simulate locally only."
				elseif Wrapper.Settings.Context == "Server"
				then "Server: request server simulation; render when the server broadcasts."
				else "Both: predict locally and request authoritative server simulation." })

			if Wrapper.State == "Initializing" then
				Iris.Text({ "Please wait for caster initialization to finish." })
			elseif Wrapper.State == "Failed" then
				Iris.Text({ "Initialization failed: " .. tostring(Wrapper.ErrorMessage) })
				if Iris.Button({ "Retry initialization" }).clicked() then
					task.spawn(function()
						local ok, err = pcall(function()
							Wrapper:Initialize()
						end)
						if not ok then
							warn("[FastCast2 ConfigUI] Retry failed:", err)
						end
					end)
				end
			elseif Wrapper.State == "Destroyed" then
				Iris.Text({ "The wrapper has been destroyed." })
			else
				Iris.SeparatorText({ "Fire settings" })
				local velocity = Iris.SliderNum({ "Velocity", 50, 1, 5000 }, { number = States.Velocity })
				if velocity.numberChanged() then
					Wrapper.Settings.Velocity = States.Velocity.value
				end

				for _, castType in { "Raycast", "Blockcast", "Spherecast" } do
					if Iris.Button({ castType }).clicked() then
						Wrapper.Settings.CastType = castType
					end
				end
				Iris.Text({ "Cast type: " .. Wrapper.Settings.CastType })

				if Wrapper.Settings.CastType == "Blockcast" then
					local size = Iris.SliderNum({ "Blockcast size", 0.1, 0.1, 10 }, { number = States.BlockcastSize })
					if size.numberChanged() then
						local uniformSize = States.BlockcastSize.value
						Wrapper.Settings.BlockcastSize = Vector3.new(uniformSize, uniformSize, uniformSize)
					end
				elseif Wrapper.Settings.CastType == "Spherecast" then
					local radius = Iris.SliderNum({ "Sphere radius", 0.1, 0.1, 10 }, { number = States.SpherecastRadius })
					if radius.numberChanged() then
						Wrapper.Settings.SpherecastRadius = States.SpherecastRadius.value
					end
				end

				Iris.SeparatorText({ "FastCastBehavior" })
				local behavior = Wrapper.Behavior
				local maxDistance = Iris.SliderNum({ "Max distance", 1, 1, 10000 }, { number = States.MaxDistance })
				if maxDistance.numberChanged() then
					behavior.MaxDistance = States.MaxDistance.value
				end

				local highFidelityBehavior = behavior.HighFidelityBehavior
				local currentBehaviorName = if highFidelityBehavior == 1 then "Default"
					elseif highFidelityBehavior == 2 then "Automatic"
					elseif highFidelityBehavior == 3 then "Always"
					else "Unknown"
				Iris.Text({ "High fidelity: " .. currentBehaviorName })
				for index, name in { "Default", "Automatic", "Always" } do
					if Iris.Button({ name }).clicked() then
						behavior.HighFidelityBehavior = index
					end
				end

				local segmentSize = Iris.SliderNum(
					{ "High-fidelity segment size", 0.05, 0.1, 10 },
					{ number = States.HighFidelitySegmentSize }
				)
				if segmentSize.numberChanged() then
					behavior.HighFidelitySegmentSize = States.HighFidelitySegmentSize.value
				end

				local accelerationY = Iris.SliderNum({ "Acceleration Y", 0, -500, 500 }, { number = States.AccelerationY })
				if accelerationY.numberChanged() then
					behavior.Acceleration = Vector3.new(
						behavior.Acceleration.X,
						States.AccelerationY.value,
						behavior.Acceleration.Z
					)
				end

				local visualize = Iris.Checkbox({ "Visualize casts" }, { isChecked = States.VisualizeCasts })
				if visualize.checked() or visualize.unchecked() then
					behavior.VisualizeCasts = States.VisualizeCasts.value
				end

				local autoIgnore = Iris.Checkbox(
					{ "Auto-ignore cosmetic container" },
					{ isChecked = States.AutoIgnoreContainer }
				)
				if autoIgnore.checked() or autoIgnore.unchecked() then
					behavior.AutoIgnoreContainer = States.AutoIgnoreContainer.value
				end

				RenderCosmeticSettings()
			end

		end
		Iris.End()
		Wrapper:SyncConfiguration()
	end
	Iris.End()
end

local UiConnection = Iris:Connect(function()
	if Equipped then
		RenderConfig()
	end
end)

local function StartUI()
	if Equipped then
		return
	end
	Equipped = true
	task.spawn(function()
		local ok, err = pcall(function()
			Wrapper:Initialize()
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Initialization failed:", err)
		end
	end)
end

local function StopUI()
	Equipped = false
end

Tool.Equipped:Connect(StartUI)
Tool.Unequipped:Connect(StopUI)
script.Destroying:Connect(function()
	StopUI()
	UiConnection:Disconnect()
end)
