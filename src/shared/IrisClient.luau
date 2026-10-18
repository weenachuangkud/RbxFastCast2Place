-- Iris is initialized once per client context and shared by all UI scripts.
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Iris = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("Iris"))
Iris.Init()

return Iris
