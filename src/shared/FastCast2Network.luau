-- Shared ByteNet packet definitions. Require on both client and server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ByteNet"))
local DataTypes = ByteNet.dataTypes

local FirePayload = DataTypes.struct({
	origin = DataTypes.vec3(),
	direction = DataTypes.vec3(),
	velocityMode = DataTypes.uint8(),
	velocity = DataTypes.vec3(),
	context = DataTypes.uint8(),
})

local ConfigurationPayload = DataTypes.struct({
	mode = DataTypes.uint8(),
	movementMode = DataTypes.uint8(),
	workerCount = DataTypes.uint8(),
	castType = DataTypes.uint8(),
	velocity = DataTypes.float32(),
	blockcastSize = DataTypes.vec3(),
	spherecastRadius = DataTypes.float32(),
	maxDistance = DataTypes.float32(),
	highFidelityBehavior = DataTypes.uint8(),
	highFidelitySegmentSize = DataTypes.float32(),
	acceleration = DataTypes.vec3(),
	visualizeCasts = DataTypes.bool(),
	autoIgnoreContainer = DataTypes.bool(),
})

return ByteNet.defineNamespace("FastCast2Place", function()
	return {
		FireRequest = ByteNet.definePacket({ value = FirePayload }),
		FireBroadcast = ByteNet.definePacket({ value = FirePayload }),
		Configuration = ByteNet.definePacket({ value = ConfigurationPayload }),
		RequestConfiguration = ByteNet.definePacket({ value = DataTypes.nothing() }),
	}
end)
