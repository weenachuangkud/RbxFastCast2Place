--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))

local ImGuiPackage = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ImGui"))
local ImGui = ImGuiPackage.ImGui
local ImGui_ImplRoblox = ImGuiPackage.ImGui_ImplRoblox

local Equipped = false
local ContextCreated = false
local WindowOpen = true
local FrameConnection: RBXScriptConnection? = nil
local ModeSwitching = false

local HIGH_FIDELITY_BEHAVIORS = {
	{ Name = "Default", Value = 1 },
	{ Name = "Automatic", Value = 2 },
	{ Name = "Always", Value = 3 },
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
		end
		ModeSwitching = false
	end)
end

local function RenderConfig()
	ImGui_ImplRoblox.NewFrame()
	ImGui.NewFrame()

	local isOpen, visible = ImGui.Begin("FastCast2 Config", WindowOpen)
	WindowOpen = isOpen

	if visible then
		ImGui.Text("Wrapper state: " .. Wrapper.State)
		ImGui.Text("Settings apply to future casts.")

		if Wrapper.State == "Initializing" then
			ImGui.Text("Please wait for caster initialization to finish.")
		elseif Wrapper.State == "Failed" then
			ImGui.Text("Initialization failed: " .. tostring(Wrapper.ErrorMessage))
			if ImGui.Button("Retry initialization") then
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
			ImGui.Text("The wrapper has been destroyed.")
		else
			if Wrapper.Settings.Mode == "Serial" then
				ImGui.Text("Current caster: Serial")
				if ImGui.Button("Switch to Parallel") then
					RequestMode("Parallel")
				end
			else
				ImGui.Text("Current caster: Parallel")
				if ImGui.Button("Switch to Serial") then
					RequestMode("Serial")
				end
			end

			ImGui.Separator()
			ImGui.Text("Fire settings")
			Wrapper.Settings.Velocity = ImGui.SliderFloat(
				"Velocity",
				Wrapper.Settings.Velocity,
				1,
				5000
			)

			if ImGui.Button("Raycast") then
				Wrapper.Settings.CastType = "Raycast"
			end
			ImGui.SameLine()
			if ImGui.Button("Blockcast") then
				Wrapper.Settings.CastType = "Blockcast"
			end
			ImGui.SameLine()
			if ImGui.Button("Spherecast") then
				Wrapper.Settings.CastType = "Spherecast"
			end
			ImGui.Text("Cast type: " .. Wrapper.Settings.CastType)

			if Wrapper.Settings.CastType == "Blockcast" then
				local size = Wrapper.Settings.BlockcastSize
				local uniformSize = ImGui.SliderFloat("Blockcast size", size.X, 0.1, 10)
				Wrapper.Settings.BlockcastSize = Vector3.new(uniformSize, uniformSize, uniformSize)
			elseif Wrapper.Settings.CastType == "Spherecast" then
				Wrapper.Settings.SpherecastRadius = ImGui.SliderFloat(
					"Sphere radius",
					Wrapper.Settings.SpherecastRadius,
					0.1,
					10
				)
			end

			ImGui.Separator()
			ImGui.Text("FastCastBehavior")
			local behavior = Wrapper.Behavior

			behavior.MaxDistance = ImGui.SliderFloat("Max distance", behavior.MaxDistance, 1, 10000)

			ImGui.Text("HighFidelityBehavior")
			local currentBehaviorName = "Unknown"
			for _, option in HIGH_FIDELITY_BEHAVIORS do
				if behavior.HighFidelityBehavior == option.Value then
					currentBehaviorName = option.Name
				end
			end
			ImGui.Text("Current: " .. currentBehaviorName)
			for _, option in HIGH_FIDELITY_BEHAVIORS do
				if ImGui.Button(option.Name) then
					behavior.HighFidelityBehavior = option.Value
				end
				if option ~= HIGH_FIDELITY_BEHAVIORS[#HIGH_FIDELITY_BEHAVIORS] then
					ImGui.SameLine()
				end
			end

			behavior.HighFidelitySegmentSize = ImGui.SliderFloat(
				"High-fidelity segment size",
				behavior.HighFidelitySegmentSize,
				0.1,
				10
			)

			local gravityY = ImGui.SliderFloat("Acceleration Y", behavior.Acceleration.Y, -500, 500)
			behavior.Acceleration = Vector3.new(
				behavior.Acceleration.X,
				gravityY,
				behavior.Acceleration.Z
			)

			local _, visualizeCasts = ImGui.Checkbox("Visualize casts", behavior.VisualizeCasts)
			behavior.VisualizeCasts = visualizeCasts

			local _, autoIgnore = ImGui.Checkbox("Auto-ignore cosmetic container", behavior.AutoIgnoreContainer)
			behavior.AutoIgnoreContainer = autoIgnore
		end
	end

	ImGui.End()
	ImGui.Render()
	ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
end

local function StopUI()
	Equipped = false
	if FrameConnection then
		FrameConnection:Disconnect()
		FrameConnection = nil
	end

	if ContextCreated then
		pcall(function()
			ImGui_ImplRoblox.Shutdown()
		end)
		pcall(function()
			ImGui.DestroyContext()
		end)
		ContextCreated = false
	end
end

local function StartUI()
	if Equipped then
		return
	end
	Equipped = true
	WindowOpen = true

	ImGui.CreateContext()
	ContextCreated = true
	local io = ImGui.GetIO()
	io.IniFilename = nil
	io.ConfigFlags = bit32.bor(io.ConfigFlags, ImGuiPackage.ImGuiConfigFlags.NavEnableKeyboard)

	ImGui_ImplRoblox.Init()
	ImGui_ImplRoblox.SetRenderRate(60)

	FrameConnection = RunService.RenderStepped:Connect(RenderConfig)

	task.spawn(function()
		local ok, err = pcall(function()
			Wrapper:Initialize()
		end)
		if not ok then
			warn("[FastCast2 ConfigUI] Initialization failed:", err)
		end
	end)
end

Tool.Equipped:Connect(StartUI)
Tool.Unequipped:Connect(StopUI)
script.Destroying:Connect(StopUI)
