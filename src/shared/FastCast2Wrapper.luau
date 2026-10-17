--!strict
-- One wrapper instance per Luau context (client and server are separate).
-- Serial and Parallel are separate source modules with separate global runtimes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local SerialFastCast = require(ReplicatedStorage:WaitForChild("FastCast2Serial"))
local ParallelFastCast = require(ReplicatedStorage:WaitForChild("FastCast2Parallel"))

type CasterMode = "Serial" | "Parallel"
type CastType = "Raycast" | "Blockcast" | "Spherecast"
type MovementMode = "BulkMoveTo" | "Motor6D"
type WrapperState = "Uninitialized" | "Initializing" | "Ready" | "Failed" | "Destroyed"

type WrapperSettings = {
	Mode: CasterMode,
	MovementMode: MovementMode,
	WorkerCount: number,
	Velocity: number,
	CastType: CastType,
	BlockcastSize: Vector3,
	SpherecastRadius: number,
	SerialConfig: { [string]: any },
	ParallelConfig: { [string]: any },
}

local Wrapper = {
	State = "Uninitialized" :: WrapperState,
	Mode = "Serial" :: CasterMode,
	ErrorMessage = nil :: string?,
	Caster = nil :: any,
	Library = nil :: any,

	Settings = {
		Mode = "Serial",
		MovementMode = "BulkMoveTo",
		WorkerCount = 4,
		Velocity = 500,
		CastType = "Raycast",
		BlockcastSize = Vector3.one,
		SpherecastRadius = 1,
		SerialConfig = {},
		ParallelConfig = {},
	} :: WrapperSettings,

	Behavior = SerialFastCast.newBehavior(),

	Events = {
		CastFire = nil,
		OnStep = nil,
		CastTerminating = nil,
		Hit = nil,
		Pierced = nil,
		LengthChanged = nil,
		CanPierce = nil,
	},

	FastCastEventsModule = nil :: ModuleScript?,
}

local SIGNAL_EVENTS = {
	CastFire = true,
	OnStep = true,
	CastTerminating = true,
	Hit = true,
	Pierced = true,
	LengthChanged = true,
}

local function AssertNotInitializing(self)
	if self.State == "Initializing" then
		error("FastCast2Wrapper is initializing; wait until it is ready.", 3)
	end
	if self.State == "Destroyed" then
		error("FastCast2Wrapper has been destroyed.", 3)
	end
end

local function ApplyEvents(self, caster)
	for name, callback in self.Events do
		if callback ~= nil then
			caster[name] = callback
		end
	end

	if self.Settings.Mode == "Parallel" and self.FastCastEventsModule then
		caster:SetFastCastEventsModule(self.FastCastEventsModule)
	end
end

local function CreateCaster(self)
	local library
	if self.Settings.Mode == "Serial" then
		library = SerialFastCast
	else
		library = ParallelFastCast
	end

	-- Both source repositories use a shared runtime initialized once per
	-- Luau context. They do not use the old per-caster :Init() API.
	if self.Settings.Mode == "Serial" then
		library.Init(self.Settings.MovementMode)
	else
		library.Init(self.Settings.WorkerCount, self.Settings.MovementMode, self.FastCastEventsModule)
	end

	local caster = library.new()
	ApplyEvents(self, caster)
	return library, caster
end

local function InitializeInternal(self)
	local ok, library, caster = pcall(function()
		local newLibrary, newCaster = CreateCaster(self)
		return newLibrary, newCaster
	end)

	if not ok then
		self.Caster = nil
		self.Library = nil
		self.State = "Failed"
		self.ErrorMessage = tostring(library)
		error(library, 2)
	end

	self.Library = library
	self.Caster = caster
	self.State = "Ready"
	self.ErrorMessage = nil
	return caster
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
	return InitializeInternal(self)
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

	self.State = "Initializing"
	local oldCaster = self.Caster
	self.Caster = nil
	self.Library = nil

	if oldCaster then
		pcall(function()
			oldCaster:Destroy()
		end)
	end

	self.Settings.Mode = mode
	self.Mode = mode
	-- Update defaults from the selected source implementation.
	self.Behavior = (if mode == "Serial" then SerialFastCast else ParallelFastCast).newBehavior()
	return InitializeInternal(self)
end

function Wrapper:SetEvent(eventName: string, callback)
	AssertNotInitializing(self)
	assert(SIGNAL_EVENTS[eventName] or eventName == "CanPierce", "Unsupported FastCast event: " .. eventName)
	assert(callback == nil or type(callback) == "function", "Event callback must be a function or nil.")
	if eventName == "CanPierce" and self.Settings.Mode == "Parallel" then
		error("Parallel CanPierce callbacks must be implemented in FastCastEventsModule.", 2)
	end

	self.Events[eventName] = callback
	if self.State == "Ready" then
		self.Caster[eventName] = callback
	end
end

function Wrapper:SetFastCastEventsModule(moduleScript: ModuleScript?)
	AssertNotInitializing(self)
	assert(moduleScript == nil or moduleScript:IsA("ModuleScript"), "Expected a ModuleScript or nil.")
	self.FastCastEventsModule = moduleScript

	if self.State == "Ready" and self.Settings.Mode == "Parallel" then
		self.Caster:SetFastCastEventsModule(moduleScript)
	end
end

function Wrapper:Fire(origin: Vector3, direction: Vector3, velocity: (number | Vector3)?, behavior)
	if not self:IsReady() then
		error("FastCast2Wrapper is not ready. Current state: " .. self.State, 2)
	end
	assert(typeof(origin) == "Vector3", "Origin must be a Vector3.")
	assert(typeof(direction) == "Vector3" and direction.Magnitude > 0, "Direction must be a non-zero Vector3.")

	local caster = self.Caster
	local castVelocity = velocity or self.Settings.Velocity
	local castBehavior = behavior or self.Behavior
	local unitDirection = direction.Unit

	if self.Settings.CastType == "Raycast" then
		return caster:RaycastFire(origin, unitDirection, castVelocity, castBehavior)
	elseif self.Settings.CastType == "Blockcast" then
		return caster:BlockcastFire(origin, self.Settings.BlockcastSize, unitDirection, castVelocity, castBehavior)
	else
		return caster:SpherecastFire(origin, self.Settings.SpherecastRadius, unitDirection, castVelocity, castBehavior)
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
	self.Library = nil
	if caster then
		caster:Destroy()
	end
end

return Wrapper
