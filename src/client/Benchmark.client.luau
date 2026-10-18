-- Development UI bootstrap.
-- The actual benchmark runner will be wired to these controls next.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Iris = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("IrisClient"))

local projectileCount = Iris.State(100)
local simulationMode = Iris.State("PerFrame")
local castMode = Iris.State("Serial")
local showDemo = Iris.State(false)

Iris:Connect(function()
	local window = Iris.Window({ "FastCast2 Benchmark" })
	if window.state.isOpened.value then
		Iris.Text({ "Benchmark controls" })
		Iris.Separator()

		Iris.SliderNum({ "Projectile count", 1, 1, 5000 }, { number = projectileCount })

		for _, mode in { "Serial", "Parallel" } do
			if Iris.Button({ mode }).clicked() then
				castMode:set(mode)
			end
		end
		Iris.Text({ "Cast mode: " .. castMode.value })

		for _, mode in { "PerFrame", "Fixed" } do
			if Iris.Button({ mode }).clicked() then
				simulationMode:set(mode)
			end
		end
		Iris.Text({ "Simulation mode: " .. simulationMode.value })

		Iris.Checkbox({ "Show Iris demo" }, { isChecked = showDemo })

		Iris.Separator()
		Iris.Text({ "Runner: not connected yet" })
		Iris.Text({ string.format("Count: %d", projectileCount.value) })
	end
	Iris.End()
end)

Iris:Connect(function()
	if showDemo.value then
		Iris.ShowDemoWindow()
	end
end)
