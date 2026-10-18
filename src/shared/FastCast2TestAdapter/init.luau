local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Adapter = {}
local instanceMethods = {
	AddAccelerationCast = true,
	AddPositionCast = true,
	AddVelocityCast = true,
	GetAccelerationCast = true,
	GetPositionCast = true,
	GetVelocityCast = true,
	PauseCast = true,
	ResumeCast = true,
	SetAcceleration = true,
	SetAccelerationCast = true,
	SetPositionCast = true,
	SetVelocity = true,
	SetVelocityCast = true,
	TerminateCast = true,
}

local function getLibrary()
	if script:GetAttribute("Mode") == "Parallel" then
		return require(ReplicatedStorage:WaitForChild("FastCast2Parallel"))
	end
	return require(ReplicatedStorage:WaitForChild("FastCast2Serial"))
end

return setmetatable(Adapter, {
	__index = function(_, name)
		local library = getLibrary()
		local member = library[name]
		if instanceMethods[name] then
			return function(_, ...)
				return member(library, ...)
			end
		end
		return member
	end,
})
