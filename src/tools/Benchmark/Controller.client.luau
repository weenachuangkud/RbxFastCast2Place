
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))

Tool.Activated:Connect(function()
	if not Wrapper:IsReady() then
		warn("[Benchmark] FastCast2Wrapper is not ready.")
		return
	end

	-- Benchmark UI/runner will own the workload. Keep the tool entry point
	-- intentionally lightweight so benchmark overhead stays measurable.
	print(string.format(
		"[Benchmark] Ready | Mode=%s | CastType=%s | Velocity=%.2f",
		Wrapper.Settings.Mode,
		Wrapper.Settings.CastType,
		Wrapper.Settings.Velocity
	))
end)
