--!strict

-- Development UI bootstrap.
-- The actual benchmark runner will be wired to these controls next.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local ImGuiPackage = require(ReplicatedStorage.Packages.ImGui)
local ImGui = ImGuiPackage.ImGui
local ImGui_ImplRoblox = ImGuiPackage.ImGui_ImplRoblox

ImGui.CreateContext()
local io = ImGui.GetIO()
io.ConfigFlags = bit32.bor(io.ConfigFlags, ImGuiPackage.ImGuiConfigFlags.DockingEnable)
ImGui_ImplRoblox.Init()

local projectileCount = 100
local simulationMode = "PerFrame"
local castMode = "Serial"
local showDemo = false

RunService.Stepped:Connect(function()
	ImGui_ImplRoblox.NewFrame()
	ImGui.NewFrame()

	local visible = ImGui.Begin("FastCast2 Benchmark")
	if visible then
		ImGui.Text("Benchmark controls")
		ImGui.Separator()

		projectileCount = ImGui.SliderInt("Projectile count", projectileCount, 1, 5000)

		local serialPressed = ImGui.Button("Serial")
		if serialPressed then
			castMode = "Serial"
		end
		ImGui.SameLine()
		local parallelPressed = ImGui.Button("Parallel")
		if parallelPressed then
			castMode = "Parallel"
		end
		ImGui.Text("Cast mode: %s", castMode)

		local perFramePressed = ImGui.Button("PerFrame")
		if perFramePressed then
			simulationMode = "PerFrame"
		end
		ImGui.SameLine()
		local fixedPressed = ImGui.Button("Fixed")
		if fixedPressed then
			simulationMode = "Fixed"
		end
		ImGui.Text("Simulation mode: %s", simulationMode)

		local demoPressed = ImGui.Button(if showDemo then "Hide ImGui demo" else "Show ImGui demo")
		if demoPressed then
			showDemo = not showDemo
		end
		if showDemo then
			ImGui.ShowDemoWindow()
		end

		ImGui.Separator()
		ImGui.Text("Runner: not connected yet")
		ImGui.Text("Count: %d", projectileCount)
	end
	ImGui.End()

	ImGui.Render()
	ImGui_ImplRoblox.RenderDrawData(ImGui.GetDrawData())
end)
