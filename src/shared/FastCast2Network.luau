--!strict
-- Shared ByteNet packet definitions. Require on both client and server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ByteNet"))
local t = ByteNet.t

local FirePayload = t.struct({
	origin = t.vec3,
	direction = t.vec3,
	velocityMode = t.uint8, -- 0 = shared speed, 1 = scalar speed, 2 = vector velocity
	velocity = t.vec3,
})

local ConfigurationPayload = t.struct({
	mode = t.uint8, -- 1 = Serial, 2 = Parallel
	movementMode = t.uint8, -- 1 = BulkMoveTo, 2 = Motor6D
	workerCount = t.uint8,
	castType = t.uint8, -- 1 = Raycast, 2 = Blockcast, 3 = Spherecast
	velocity = t.float32,
	blockcastSize = t.vec3,
	spherecastRadius = t.float32,
	maxDistance = t.float32,
	highFidelityBehavior = t.uint8,
	highFidelitySegmentSize = t.float32,
	acceleration = t.vec3,
	visualizeCasts = t.bool,
	autoIgnoreContainer = t.bool,
})

return ByteNet.defineNamespace("FastCast2Place", function()
	return {
		FireRequest = ByteNet.definePacket({ value = FirePayload }),
		FireBroadcast = ByteNet.definePacket({ value = FirePayload }),
		Configuration = ByteNet.definePacket({ value = ConfigurationPayload }),
		RequestConfiguration = ByteNet.definePacket({ value = t.nothing }),
	}
end)
