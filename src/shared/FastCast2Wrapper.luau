--!strict
-- One wrapper instance per Luau context (client and server are separate).
-- All tools in a context should require this module instead of creating their own caster.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local Packages = ReplicatedStorage:WaitForChild("Packages")
local FastCast2 = require(Packages:WaitForChild("FastCast2"))

type CasterMode = "Serial" | "Parallel"
type CastType = "Raycast" | "Blockcast" | "Spherecast"

type WrapperSettings = {
	Mode: CasterMode,
	MovementMode: "BulkMoveTo" | "Motor6D",
	UseObjectCache: boolean,
	WorkerCount: number,
	Velocity: number,
	CastType: CastType,
	BlockcastSize: Vector3,
	SpherecastRadius: number,
}

type WrapperState = "Uninitialized" | "Initializing" | "Ready" | "Failed" | "Destroyed"

local Wrapper = {
	State = "Uninitialized" :: WrapperState,
	Mode = "Serial" :: CasterMode,
	ErrorMessage = nil :: string?,
	Caster = nil :: any,

	Settings = {
		Mode = "Serial",
		MovementMode = "BulkMoveTo",
		UseObjectCache = false,
		WorkerCount = 4,
		Velocity = 500,
		CastType = "Raycast",
		BlockcastSize = Vector3.new(1, 1, 1),
		SpherecastRadius = 1,
	} :: WrapperSettings,

	-- This behavior is shared by the tools in this Luau context.
	-- UI edits apply to casts fired after the edit.
	Behavior = FastCast2.newBehavior(),

	Events = {
		CastFire = nil,
		LengthChanged = nil,
		Hit = nil,
		Pierced = nil,
		CastTerminating = nil,
	},
}

local function CreateCaster(self)
	local caster
	local mode: CasterMode = self.Settings.Mode

	if mode == "Serial" then
		caster = FastCast2.new()
	else
		caster = FastCast2.newParallel()
	end

	for eventName, callback in self.Events do
		if callback then
			caster[eventName] = callback
		end
	end

	if mode == "Serial" then
		caster:Init(self.Settings.MovementMode, self.Settings.UseObjectCache)
	else
		-- Each rebuild gets unique names so old worker folders can finish
		-- cleaning up without colliding with the new dispatcher.
		local suffix = HttpService:GenerateGUID(false)
		caster:Init(
			self.Settings.WorkerCount,
			Workspace,
			"FastCastVMs_" .. suffix,
			Workspace,
			"FastCastWorkers_" .. suffix,
			"FastCastWorker",
			self.Settings.MovementMode,
			nil, -- FastCastEventsModule
			self.Settings.UseObjectCache,
			nil, -- cosmetic template (not used when ObjectCache is disabled)
			500,
			Workspace
		)
	end

	return caster
end

local function FinishInitialization(self)
	local caster
	local ok, result = pcall(function()
		caster = CreateCaster(self)
	end)

	if not ok then
		if caster then
			pcall(function()
				caster:Destroy()
			end)
		end

		self.Caster = nil
		self.State = "Failed"
		self.ErrorMessage = tostring(result)
		error(result, 2)
	end

	self.Caster = caster
	self.State = "Ready"
	self.ErrorMessage = nil
	return caster
end

local function AssertNotInitializing(self)
	if self.State == "Initializing" then
		error("FastCast2Wrapper is initializing; wait until it is ready before changing settings.", 3)
	end
	if self.State == "Destroyed" then
		error("FastCast2Wrapper has been destroyed.", 3)
	end
end

function Wrapper:Initialize()
	if self.State == "Ready" then
		return self.Caster
	end

	if self.State == "Initializing" then
		repeat
			task.wait()
		until self.State ~= "Initializing"

		if self.State == "Ready" then
			return self.Caster
		end
		error(self.ErrorMessage or "FastCast2Wrapper initialization failed.", 2)
	end

	if self.State == "Destroyed" then
		error("FastCast2Wrapper has been destroyed.", 2)
	end

	self.State = "Initializing"
	return FinishInitialization(self)
end

function Wrapper:IsReady(): boolean
	return self.State == "Ready" and self.Caster ~= nil
end

function Wrapper:GetCaster()
	if not self:IsReady() then
		error("FastCast2Wrapper is not ready. Current state: " .. self.State, 2)
	end
	return self.Caster
end

function Wrapper:SetMode(mode: CasterMode)
	AssertNotInitializing(self)
	assert(mode == "Serial" or mode == "Parallel", "Mode must be Serial or Parallel.")

	if self.State == "Ready" and self.Settings.Mode == mode then
		return self.Caster
	end

	-- Block all wrapper operations before destroying the old caster.
	self.State = "Initializing"
	local oldCaster = self.Caster
	self.Caster = nil

	if oldCaster then
		pcall(function()
			oldCaster:Destroy()
		end)
	end

	self.Settings.Mode = mode
	self.Mode = mode
	return FinishInitialization(self)
end

function Wrapper:SetEvent(eventName: string, callback)
	AssertNotInitializing(self)
	assert(self.Events[eventName] ~= nil or eventName == "Hit", "Unsupported FastCast event: " .. eventName)
	assert(callback == nil or type(callback) == "function", "Event callback must be a function or nil.")

	self.Events[eventName] = callback
	if self.State == "Ready" and self.Caster then
		self.Caster[eventName] = callback
	end
end

function Wrapper:Fire(origin: Vector3, direction: Vector3, velocity: number?, behavior)
	if not self:IsReady() then
		error("FastCast2Wrapper is not ready. Current state: " .. self.State, 2)
	end
	assert(typeof(origin) == "Vector3", "Origin must be a Vector3.")
	assert(typeof(direction) == "Vector3", "Direction must be a Vector3.")
	assert(direction.Magnitude > 0, "Direction cannot be zero.")

	local caster = self.Caster
	local castVelocity = velocity or self.Settings.Velocity
	local castBehavior = behavior or self.Behavior
	local castType: CastType = self.Settings.CastType

	if castType == "Raycast" then
		caster:RaycastFire(origin, direction.Unit, castVelocity, castBehavior)
	elseif castType == "Blockcast" then
		caster:BlockcastFire(origin, self.Settings.BlockcastSize, direction.Unit, castVelocity, castBehavior)
	elseif castType == "Spherecast" then
		caster:SpherecastFire(origin, self.Settings.SpherecastRadius, direction.Unit, castVelocity, castBehavior)
	else
		error("Unsupported cast type: " .. tostring(castType), 2)
	end
end

function Wrapper:Destroy()
	if self.State == "Initializing" then
		error("Cannot destroy FastCast2Wrapper while it is initializing.", 2)
	end
	if self.State == "Destroyed" then
		return
	end

	self.State = "Destroyed"
	local caster = self.Caster
	self.Caster = nil
	if caster then
		caster:Destroy()
	end
end

return Wrapper
