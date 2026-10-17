--!strict
-- Packet definitions shared by the client and server.
-- Require this module on both sides so ByteNet initializes consistently.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Packages = ReplicatedStorage:WaitForChild("Packages")
local ByteNet = require(Packages:WaitForChild("ByteNet"))

local FirePayload = ByteNet.struct({
	origin = ByteNet.vec3,
	direction = ByteNet.vec3,
	-- velocityMode: 0 = use shared settings, 1 = scalar speed, 2 = vector velocity.
	velocityMode = ByteNet.uint8,
	velocity = ByteNet.vec3,
})

local ConfigurationPayload = ByteNet.struct({
	-- Enum values are encoded as uint8 to keep the packet compact.
	-- mode: 1 = Serial, 2 = Parallel.
	mode = ByteNet.uint8,
	-- movementMode: 1 = BulkMoveTo, 2 = Motor6D.
	movementMode = ByteNet.uint8,
	workerCount = ByteNet.uint8,
	-- castType: 1 = Raycast, 2 = Blockcast, 3 = Spherecast.
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

return ByteNet.defineNamespace("FastCast2Place", function()
	return {
		FireRequest = ByteNet.definePacket({
			value = FirePayload,
		}),
		-- Server -> clients. The requesting client is excluded for client-fired casts,
		-- since it has already rendered its predicted local cast.
		FireBroadcast = ByteNet.definePacket({
			value = FirePayload,
		}),
		-- Client -> server requests and server -> client snapshots use the same schema.
		Configuration = ByteNet.definePacket({
			value = ConfigurationPayload,
		}),
		RequestConfiguration = ByteNet.definePacket({
			value = ByteNet.nothing,
		}),
	}
end)
