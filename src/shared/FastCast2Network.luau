-- Shared ByteNet packet definitions. Require on both client and server.
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ByteNet = require(ReplicatedStorage:WaitForChild("Packages"):WaitForChild("ByteNet"))

return ByteNet.defineNamespace("FastCast2Place", function()
	local FirePayload = ByteNet.struct({
		origin = ByteNet.vec3,
		direction = ByteNet.vec3,
		velocityMode = ByteNet.uint8,
		velocity = ByteNet.vec3,
		context = ByteNet.uint8,
	})

	local ConfigurationPayload = ByteNet.struct({
		mode = ByteNet.uint8,
		movementMode = ByteNet.uint8,
		workerCount = ByteNet.uint8,
		castType = ByteNet.uint8,
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

	return {
		FireRequest = ByteNet.definePacket({ value = FirePayload }),
		FireBroadcast = ByteNet.definePacket({ value = FirePayload }),
		Configuration = ByteNet.definePacket({ value = ConfigurationPayload }),
		RequestConfiguration = ByteNet.definePacket({ value = ByteNet.nothing }),
	}
end)
