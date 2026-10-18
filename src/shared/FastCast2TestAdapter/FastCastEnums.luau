local ReplicatedStorage = game:GetService("ReplicatedStorage")

if script.Parent:GetAttribute("Mode") == "Parallel" then
	return require(ReplicatedStorage:WaitForChild("FastCast2Parallel"):WaitForChild("FastCastEnums"))
end

return require(ReplicatedStorage:WaitForChild("FastCast2Serial"):WaitForChild("FastCastEnums"))
