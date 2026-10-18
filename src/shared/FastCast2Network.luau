-- Shared ByteNet packet definitions. Require on both client and server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ByteNet"))

local FirePayload = ByteNet.struct({
	origin = ByteNet.vec3,
	direction = ByteNet.vec3,
	velocityMode = ByteNet.uint8, -- 0 = shared speed, 1 = scalar speed, 2 = vector velocity
	velocity = ByteNet.vec3,
	context = ByteNet.uint8, -- 1 = Client, 2 = Server, 3 = Both
})

local ConfigurationPayload = ByteNet.struct({
	mode = ByteNet.uint8, -- 1 = Serial, 2 = Parallel
	movementMode = ByteNet.uint8, -- 1 = BulkMoveTo, 2 = Motor6D
	workerCount = ByteNet.uint8,
	castType = ByteNet.uint8, -- 1 = Raycast, 2 = Blockcast, 3 = Spherecast
	velocity = ByteNet.float32,
	blockcastSize = ByteNet.vec3,
	spherecastRadius = ByteNet.float32,
	maxDistance = ByteNet.float32,
	highFidelityBehavior = ByteNet.uint8,
	highFidelitySegmentSize = ByteNet.float32,
	acceleration = ByteNet.vec3,
	visualizeCasts = ByteNet.bool,
	autoIgnoreContainer = ByteNet.bool,
})

return ByteNet.defineNamespace("FastCast2Place", function()
	return {
		FireRequest = ByteNet.definePacket({ value = FirePayload }),
		FireBroadcast = ByteNet.definePacket({ value = FirePayload }),
		Configuration = ByteNet.definePacket({ value = ConfigurationPayload }),
		RequestConfiguration = ByteNet.definePacket({ value = ByteNet.nothing }),
	}
end)
