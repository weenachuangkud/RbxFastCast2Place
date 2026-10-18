local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))
local Iris = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IrisClient"))
local BenchmarkSettings = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2BenchmarkSettings"))
local Reports = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2ToolReports"))

local Equipped = false
local ModeSwitching = false

local States = {
	ProjectileCount = Iris.State(BenchmarkSettings.ProjectileCount),
	SampleDuration = Iris.State(BenchmarkSettings.SampleDuration),
	Velocity = Iris.State(Wrapper.Settings.Velocity),
	BlockcastSize = Iris.State(Wrapper.Settings.BlockcastSize.X),
	SpherecastRadius = Iris.State(Wrapper.Settings.SpherecastRadius),
	MaxDistance = Iris.State(Wrapper.Behavior.MaxDistance),
	HighFidelitySegmentSize = Iris.State(Wrapper.Behavior.HighFidelitySegmentSize),
	AccelerationY = Iris.State(Wrapper.Behavior.Acceleration.Y),
	VisualizeCasts = Iris.State(Wrapper.Behavior.VisualizeCasts),
	AutoIgnoreContainer = Iris.State(Wrapper.Behavior.AutoIgnoreContainer),
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
		Iris.SeparatorText({ "FastCast2 Benchmark" })
		local projectileCount = Iris.SliderNum({ "Projectile count", 1, 1, 5000 }, { number = States.ProjectileCount })
		if projectileCount.numberChanged() then
			BenchmarkSettings.ProjectileCount = math.floor(States.ProjectileCount.value)
		end
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

		Iris.Text({ "Use Benchmark for the cast-type suite, or PerfBench for the separate PerFrame / Fixed stress matrix." })
		Iris.Text({ "Benchmark status: " .. Reports.Benchmark.status })
		if Reports.Benchmark.error then
			Iris.Text({ "Benchmark error: " .. Reports.Benchmark.error })
		end
		for _, result in Reports.Benchmark.results do
			Iris.Text({ string.format(
				"%s / %s | create %.2f ms | avg %.2f ms | p95 %.2f ms | p99 %.2f ms | cleanup %.2f ms",
				result.mode,
				result.castType,
				result.creationMs,
				result.averageFrameMs,
				result.p95FrameMs,
				result.p99FrameMs,
				result.cleanupMs
			) })
		end

		Iris.SeparatorText({ "FastCast2 PerfBench" })
		Iris.Text({ "PerfBench status: " .. Reports.PerfBench.status })
		if Reports.PerfBench.error then
			Iris.Text({ "PerfBench error: " .. Reports.PerfBench.error })
		end
		if #Reports.PerfBench.results > 0 then
			Iris.Text({ "Per-frame / fixed-step stress benchmark (instancing and movement toggled):" })
		end
		for _, result in Reports.PerfBench.results do
			if result.error then
				Iris.Text({ string.format("%s / %s: %s", result.mode or "PerfBench", result.simulationMode or "", result.error) })
			else
				Iris.Text({ string.format(
					"%s / %s | instanced=%s | movement=%s | create %.2f ms | avg %.2f | p95 %.2f | p99 %.2f | cleanup %.2f",
					result.mode,
					result.simulationMode,
					tostring(result.instanced),
					tostring(result.movement),
					result.creationMs,
					result.averageFrameMs,
					result.p95FrameMs,
					result.p99FrameMs,
					result.cleanupMs
				) })
			end
		end

		Iris.SeparatorText({ "FastCast2 Unit Tests" })
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
			local velocity = Iris.SliderNum({ "Velocity", 1, 1, 5000 }, { number = States.Velocity })
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

			local accelerationY = Iris.SliderNum({ "Acceleration Y", 1, -500, 500 }, { number = States.AccelerationY })
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
