--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Tool = script.Parent :: Tool
local Wrapper = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Wrapper"))

Tool.Activated:Connect(function()
	if not Wrapper:IsReady() then
		warn("[UnitTest] FastCast2Wrapper is not ready.")
		return
	end

	print(string.format(
		"[UnitTest] Wrapper ready | Mode=%s",
		Wrapper.Settings.Mode
	))
	warn("[UnitTest] Test cases have not been ported into this place yet.")
end)
