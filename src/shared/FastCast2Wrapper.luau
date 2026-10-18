-- One wrapper instance per Luau context (client and server are separate).
-- Serial and Parallel are separate source modules with separate global runtimes.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")
local RunService = game:GetService("RunService")

local SerialFastCast = require(ReplicatedStorage:WaitForChild("FastCast2Serial"))
local ParallelFastCast = require(ReplicatedStorage:WaitForChild("FastCast2Parallel"))
local Network = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("FastCast2Network"))

local defaultBehavior = SerialFastCast.newBehavior()
defaultBehavior.Acceleration = Vector3.new(
	defaultBehavior.Acceleration.X,
	0,
	defaultBehavior.Acceleration.Z
)

type CasterMode = "Serial" | "Parallel"
type CastType = "Raycast" | "Blockcast" | "Spherecast"
type MovementMode = "BulkMoveTo" | "Motor6D"
type WrapperState = "Uninitialized" | "Initializing" | "Ready" | "Failed" | "Destroyed"
type CosmeticMode = "Instanced" | "Instanceless"
type FireContext = "Client" | "Server" | "Both"

type WrapperSettings = {
	Mode: CasterMode,
	Context: FireContext,
	MovementMode: MovementMode,
	WorkerCount: number,
	Velocity: number,
	CastType: CastType,
	BlockcastSize: Vector3,
	SpherecastRadius: number,
	CosmeticMode: CosmeticMode,
	CosmeticProjectileName: string?,
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
		Context = "Both",
		MovementMode = "BulkMoveTo",
		WorkerCount = 4,
		Velocity = 50,
		CastType = "Raycast",
		BlockcastSize = Vector3.one,
		SpherecastRadius = 1,
		CosmeticMode = "Instanced",
		CosmeticProjectileName = nil,
		SerialConfig = {},
		ParallelConfig = {},
	} :: WrapperSettings,

	Behavior = defaultBehavior,

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

local function GetDefaultCosmeticTemplate(): BasePart
	local existing = ReplicatedStorage:FindFirstChild("FastCast2DefaultProjectile")
	if existing and existing:IsA("BasePart") then
		return existing
	end

	local part = Instance.new("Part")
	part.Name = "FastCast2DefaultProjectile"
	part.Size = Vector3.one
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Parent = ReplicatedStorage
	return part
end

local function ApplyCosmeticSettings(self)
	local behavior = self.Behavior
	local visualizeColor = if RunService:IsServer()
		then Color3.fromRGB(0, 255, 100)
		else Color3.fromRGB(0, 170, 255)
	local visualizeSettings = behavior.VisualizeCastSettings or {}
	visualizeSettings.Debug_SegmentColor = visualizeColor
	visualizeSettings.Debug_HitColor = visualizeColor
	behavior.VisualizeCastSettings = visualizeSettings
	behavior.CosmeticBulletContainer = Workspace
	behavior.CloneTemplate = true

	if self.Settings.CosmeticMode == "Instanceless" then
		behavior.CosmeticBulletTemplate = nil
		return
	end

	local template: BasePart? = nil
	local projectileName = self.Settings.CosmeticProjectileName
	if projectileName then
		local folder = ReplicatedStorage:FindFirstChild("Projectiles")
		local candidate = folder and folder:FindFirstChild(projectileName)
		if candidate and candidate:IsA("BasePart") then
			template = candidate
		end
	end

	-- Instanced mode always has a template, even when Projectiles is empty
	-- or the configured projectile is missing/unsupported.
	behavior.CosmeticBulletTemplate = template or GetDefaultCosmeticTemplate()
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

	ApplyCosmeticSettings(self)
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
	self.Behavior = (if mode == "Serial" then SerialFastCast else ParallelFastCast).newBehavior()
	ApplyCosmeticSettings(self)
	return InitializeInternal(self)
end

function Wrapper:SetCosmeticMode(mode: CosmeticMode)
	AssertNotInitializing(self)
	assert(mode == "Instanced" or mode == "Instanceless", "Cosmetic mode must be Instanced or Instanceless.")
	self.Settings.CosmeticMode = mode
	ApplyCosmeticSettings(self)
end

function Wrapper:SetCosmeticProjectile(name: string?)
	AssertNotInitializing(self)
	if name ~= nil then
		local folder = ReplicatedStorage:FindFirstChild("Projectiles")
		local candidate = folder and folder:FindFirstChild(name)
		assert(candidate and candidate:IsA("BasePart"), "Projectile must be a BasePart directly inside ReplicatedStorage.Projectiles.")
	end
	self.Settings.CosmeticProjectileName = name
	self.Settings.CosmeticMode = "Instanced"
	ApplyCosmeticSettings(self)
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

local LastConfigurationKey: string? = nil

local function EncodeConfiguration(self)
	local settings = self.Settings
	local behavior = self.Behavior
	return {
		mode = if settings.Mode == "Parallel" then 2 else 1,
		movementMode = if settings.MovementMode == "Motor6D" then 2 else 1,
		workerCount = math.clamp(math.floor(settings.WorkerCount), 1, 32),
		castType = if settings.CastType == "Blockcast" then 2 elseif settings.CastType == "Spherecast" then 3 else 1,
		velocity = settings.Velocity,
		blockcastSize = settings.BlockcastSize,
		spherecastRadius = settings.SpherecastRadius,
		maxDistance = behavior.MaxDistance,
		highFidelityBehavior = behavior.HighFidelityBehavior,
		highFidelitySegmentSize = behavior.HighFidelitySegmentSize,
		acceleration = behavior.Acceleration,
		visualizeCasts = behavior.VisualizeCasts,
		autoIgnoreContainer = behavior.AutoIgnoreContainer,
	}
end

function Wrapper:SyncConfiguration()
	if not RunService:IsClient() then
		return
	end
	local configuration = EncodeConfiguration(self)
	local key = table.concat({
		tostring(configuration.mode), tostring(configuration.movementMode),
		tostring(configuration.workerCount), tostring(configuration.castType),
		tostring(configuration.velocity), tostring(configuration.blockcastSize),
		tostring(configuration.spherecastRadius), tostring(configuration.maxDistance),
		tostring(configuration.highFidelityBehavior), tostring(configuration.highFidelitySegmentSize),
		tostring(configuration.acceleration), tostring(configuration.visualizeCasts),
		tostring(configuration.autoIgnoreContainer),
	}, "|")
	if key == LastConfigurationKey then return end
	LastConfigurationKey = key
	Network.Configuration.send(configuration)
end

local function ApplyConfiguration(self, payload)
	-- Set runtime initialization inputs before SetMode creates a new caster.
	-- Parallel.Init consumes WorkerCount only on its first initialization.
	local mode = if payload.mode == 2 then "Parallel" else "Serial"
	local movementMode = if payload.movementMode == 2 then "Motor6D" else "BulkMoveTo"

	self.Settings.Velocity = payload.velocity
	self.Settings.MovementMode = movementMode
	self.Settings.WorkerCount = payload.workerCount
	self.Settings.CastType = if payload.castType == 2 then "Blockcast" elseif payload.castType == 3 then "Spherecast" else "Raycast"
	self.Settings.BlockcastSize = payload.blockcastSize
	self.Settings.SpherecastRadius = payload.spherecastRadius

	if self.Settings.Mode ~= mode then
		self:SetMode(mode)
	elseif self:IsReady() then
		-- Init updates movement mode but does not rebuild the caster.
		if mode == "Serial" then
			SerialFastCast.Init(movementMode)
		else
			ParallelFastCast.Init(self.Settings.WorkerCount, movementMode, self.FastCastEventsModule)
		end
		self.Caster:SetMovementModeEnabled(true, movementMode)
	end

	self.Behavior.MaxDistance = payload.maxDistance
	self.Behavior.HighFidelityBehavior = payload.highFidelityBehavior
	self.Behavior.HighFidelitySegmentSize = payload.highFidelitySegmentSize
	self.Behavior.Acceleration = payload.acceleration
	self.Behavior.VisualizeCasts = payload.visualizeCasts
	self.Behavior.AutoIgnoreContainer = payload.autoIgnoreContainer
	ApplyCosmeticSettings(self)
end

function Wrapper:FireLocal(origin: Vector3, direction: Vector3, velocity: (number | Vector3)?, behavior)
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

function Wrapper:SetContext(context: FireContext)
	assert(context == "Client" or context == "Server" or context == "Both", "Context must be Client, Server, or Both.")
	self.Settings.Context = context
end

local function EncodeFire(origin, direction, velocity, context: FireContext)
	local velocityMode = if typeof(velocity) == "Vector3" then 2 elseif typeof(velocity) == "number" then 1 else 0
	local velocityVector = if typeof(velocity) == "Vector3" then velocity elseif typeof(velocity) == "number" then Vector3.new(velocity, 0, 0) else Vector3.zero
	return {
		origin = origin,
		direction = direction.Unit,
		velocityMode = velocityMode,
		velocity = velocityVector,
		context = if context == "Client" then 1 elseif context == "Server" then 2 else 3,
	}
end

function Wrapper:Fire(origin: Vector3, direction: Vector3, velocity: (number | Vector3)?, behavior)
	assert(typeof(origin) == "Vector3", "Origin must be a Vector3.")
	assert(typeof(direction) == "Vector3" and direction.Magnitude > 0, "Direction must be a non-zero Vector3.")
	local context = self.Settings.Context
	if RunService:IsClient() then
		if context ~= "Client" then
			self:SyncConfiguration()
			Network.FireRequest.send(EncodeFire(origin, direction, velocity, context))
		end
		if context ~= "Server" then
			return self:FireLocal(origin, direction, velocity, behavior)
		end
		return nil
	end

	-- Server calls always simulate authoritatively. Also tell clients to render
	-- the cast, since server-side cosmetic instances are disabled.
	local result = self:FireLocal(origin, direction, velocity, behavior)
	Network.FireBroadcast.sendToAll(EncodeFire(origin, direction, velocity, "Server"))
	return result
end

if RunService:IsClient() then
	Network.Configuration.listen(function(payload)
		local ok, err = pcall(function()
			ApplyConfiguration(Wrapper, payload)
		end)
		if not ok then
			warn("[FastCast2Wrapper] Could not apply server configuration:", err)
		end
	end)
	Network.FireBroadcast.listen(function(payload)
		if not Wrapper:IsReady() then
			local ok, err = pcall(function()
				Wrapper:Initialize()
			end)
			if not ok then
				warn("[FastCast2Wrapper] Could not initialize for remote cast:", err)
				return
			end
		end
		local ok, err = pcall(function()
			Wrapper:FireLocal(payload.origin, payload.direction, if payload.velocityMode == 2 then payload.velocity elseif payload.velocityMode == 1 then payload.velocity.X else nil)
		end)
		if not ok then
			warn("[FastCast2Wrapper] Could not render remote cast:", err)
		end
	end)
	Network.RequestConfiguration.send()
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
