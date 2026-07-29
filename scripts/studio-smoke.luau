--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function expect(condition, message)
	if not condition then
		error("SMOKE CHECK FAILED: " .. message, 2)
	end
end

local serverRoot = ServerScriptService:FindFirstChild("PannaServer")
local sharedRoot = ReplicatedStorage:FindFirstChild("PannaShared")
expect(serverRoot ~= nil, "PannaServer was not mapped by Rojo")
expect(sharedRoot ~= nil, "PannaShared was not mapped by Rojo")

local config = require(sharedRoot:FindFirstChild("Config"))
local ballMath = require(sharedRoot:FindFirstChild("BallMath"))
local net = require(sharedRoot:FindFirstChild("Net"))
local worldBuilder = require(serverRoot:FindFirstChild("WorldBuilder"))
local arenaServiceModule = require(serverRoot:FindFirstChild("ArenaService"))
local ballServiceModule = require(serverRoot:FindFirstChild("BallService"))
local remoteRegistry = require(serverRoot:FindFirstChild("RemoteRegistry"))

expect(type(ballMath) == "table", "BallMath module failed to load")
for _, functionName in
	{
		"IsFiniteNumber",
		"IsFiniteVector3",
		"HorizontalUnit",
		"ClampMagnitude",
		"ChargePower",
		"DirectionDot",
		"ClosestPointOnRay",
	}
do
	expect(type(ballMath[functionName]) == "function", "BallMath." .. functionName .. " missing")
end

expect(ballMath.IsFiniteNumber(0), "BallMath rejected a finite number")
expect(not ballMath.IsFiniteNumber(math.huge), "BallMath accepted infinity")
expect(ballMath.IsFiniteVector3(Vector3.new(1, 2, 3)), "BallMath rejected a finite Vector3")
expect(
	not ballMath.IsFiniteVector3(Vector3.new(math.huge, 0, 0)),
	"BallMath accepted a non-finite Vector3"
)

local horizontal = ballMath.HorizontalUnit(Vector3.new(3, 8, 4), Vector3.zAxis)
expect(horizontal ~= nil, "BallMath.HorizontalUnit returned nil for a valid direction")
local horizontalDirection = horizontal :: Vector3
expect(
	math.abs(horizontalDirection.Magnitude - 1) < 1e-5 and math.abs(horizontalDirection.Y) < 1e-5,
	"BallMath.HorizontalUnit did not return a planar unit vector"
)
local capped = ballMath.ClampMagnitude(Vector3.new(300, 40, 0), config.Ball.Limits.MaximumSpeed)
expect(
	math.abs(capped.Magnitude - config.Ball.Limits.MaximumSpeed) < 1e-4,
	"BallMath.ClampMagnitude did not enforce the configured speed cap"
)
local closestPoint, distanceAlong =
	ballMath.ClosestPointOnRay(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(3, 0, -7))
expect(
	(closestPoint - Vector3.new(0, 0, -7)).Magnitude < 1e-4 and math.abs(distanceAlong - 7) < 1e-4,
	"BallMath.ClosestPointOnRay returned incorrect geometry"
)

local function tunedVelocity(tuning: any, exponent: number, power: number): Vector3
	local shapedPower = math.clamp(power, 0, 1) ^ exponent
	local speed = tuning.SpeedMinimum + (tuning.SpeedMaximum - tuning.SpeedMinimum) * shapedPower
	local lift = tuning.LiftMinimum + (tuning.LiftMaximum - tuning.LiftMinimum) * shapedPower
	return ballMath.ClampMagnitude(Vector3.new(0, lift, -speed), config.Ball.Limits.MaximumSpeed)
end

local velocityTunings = {
	Low = {
		tuning = config.Ball.Shot.Types.Low,
		exponent = config.Ball.Shot.PowerExponent,
		chargeSeconds = config.Ball.Shot.ChargeSeconds,
		minimumPower = config.Ball.Shot.MinimumPower,
	},
	Normal = {
		tuning = config.Ball.Shot.Types.Normal,
		exponent = config.Ball.Shot.PowerExponent,
		chargeSeconds = config.Ball.Shot.ChargeSeconds,
		minimumPower = config.Ball.Shot.MinimumPower,
	},
	Chip = {
		tuning = config.Ball.Shot.Types.Chip,
		exponent = config.Ball.Shot.PowerExponent,
		chargeSeconds = config.Ball.Shot.ChargeSeconds,
		minimumPower = config.Ball.Shot.MinimumPower,
	},
	Pass = {
		tuning = config.Ball.Pass,
		exponent = config.Ball.Pass.PowerExponent,
		chargeSeconds = config.Ball.Pass.ChargeSeconds,
		minimumPower = config.Ball.Pass.MinimumPower,
	},
}

for name, definition in velocityTunings do
	local minimumPower = ballMath.ChargePower(0, definition.chargeSeconds, definition.minimumPower)
	local middlePower = ballMath.ChargePower(
		definition.chargeSeconds * 0.5,
		definition.chargeSeconds,
		definition.minimumPower
	)
	local maximumPower = ballMath.ChargePower(
		definition.chargeSeconds,
		definition.chargeSeconds,
		definition.minimumPower
	)
	local minimumVelocity = tunedVelocity(definition.tuning, definition.exponent, minimumPower)
	local middleVelocity = tunedVelocity(definition.tuning, definition.exponent, middlePower)
	local maximumVelocity = tunedVelocity(definition.tuning, definition.exponent, maximumPower)
	expect(ballMath.IsFiniteVector3(minimumVelocity), name .. " minimum velocity is not finite")
	expect(ballMath.IsFiniteVector3(middleVelocity), name .. " middle velocity is not finite")
	expect(ballMath.IsFiniteVector3(maximumVelocity), name .. " maximum velocity is not finite")
	expect(
		minimumVelocity.Magnitude < middleVelocity.Magnitude
			and middleVelocity.Magnitude < maximumVelocity.Magnitude,
		name .. " velocity is not monotonic across charge levels"
	)
	expect(
		maximumVelocity.Magnitude <= config.Ball.Limits.MaximumSpeed + 1e-4,
		name .. " velocity exceeds MaximumSpeed"
	)
end

expect(
	config.Ball.Shot.Types.Low.LiftMaximum < config.Ball.Shot.Types.Normal.LiftMaximum
		and config.Ball.Shot.Types.Normal.LiftMaximum < config.Ball.Shot.Types.Chip.LiftMaximum,
	"Low, Normal, and Chip lift tuning is not ordered"
)
expect(
	config.Ball.Pass.SpeedMaximum <= config.Ball.Limits.MaximumSpeed,
	"Pass tuning exceeds the global ball speed cap"
)

local tackleForward = Vector3.new(0, 0, -1)
local frontOffset = Vector3.new(0, 0, -4)
local sideOffset = Vector3.new(4, 0, 0)
local rearOffset = Vector3.new(0, 0, 4)
local frontDot = ballMath.DirectionDot(tackleForward, frontOffset)
local sideDot = ballMath.DirectionDot(tackleForward, sideOffset)
local rearDot = ballMath.DirectionDot(tackleForward, rearOffset)
expect(frontDot >= config.Actions.Tackle.AttackerForwardDot, "front tackle geometry rejected")
expect(sideDot < config.Actions.Tackle.AttackerForwardDot, "side tackle geometry accepted")
expect(rearDot < config.Actions.Tackle.AttackerForwardDot, "rear tackle geometry accepted")
expect(
	frontDot >= config.Actions.Tackle.DefenderFrontDot
		and sideDot < config.Actions.Tackle.DefenderFrontDot
		and rearDot < config.Actions.Tackle.DefenderFrontDot,
	"defender-facing tackle geometry is inconsistent"
)

for _, moduleName in
	{
		"RateLimiter",
		"PlayerDataService",
		"PannaDetector",
		"BallService",
		"MatchService",
		"QueueService",
		"RoomService",
	}
do
	local module = serverRoot:FindFirstChild(moduleName)
	expect(module ~= nil, moduleName .. " was not mapped by Rojo")
	local ok, result = pcall(require, module)
	expect(ok, moduleName .. " failed to load: " .. tostring(result))
	expect(type(result) == "table", moduleName .. " must return a module table")
end

local typesModule = sharedRoot:FindFirstChild("Types")
expect(typesModule ~= nil and type(require(typesModule)) == "table", "Types module failed to load")

local world = worldBuilder.Build(config)
expect(world.Name == config.World.RootName, "world root name does not match config")
expect(world.Name == "PannaDistrict", "district root must be named PannaDistrict")
expect(world:GetAttribute("ArenaCount") == 6, "district must declare six arenas")
expect(world:GetAttribute("DistrictName") == "PannaDistrict", "district identity is missing")
local lobbySpawn = world:FindFirstChild("LobbySpawn", true)
expect(lobbySpawn ~= nil and lobbySpawn:IsA("BasePart"), "LobbySpawn is missing")
expect(world:FindFirstChild("QueuePrompt", true) ~= nil, "QueuePrompt is missing")

local environment = world:FindFirstChild("DistrictEnvironment")
expect(environment ~= nil and environment:IsA("Model"), "DistrictEnvironment is missing")
expect(
	environment:GetAttribute("ExternalAssetCount") == 0,
	"district must use zero external assets"
)
local centralStreet = environment:FindFirstChild("CentralStreet")
expect(centralStreet ~= nil and centralStreet:IsA("Model"), "CentralStreet is missing")
expect(centralStreet:GetAttribute("Continuous") == true, "CentralStreet must be continuous")
local streetSurface = centralStreet:FindFirstChild("StreetSurface")
expect(streetSurface ~= nil and streetSurface:IsA("BasePart"), "StreetSurface is missing")
local streetStart = streetSurface.Position.Z - streetSurface.Size.Z * 0.5
local streetEnd = streetSurface.Position.Z + streetSurface.Size.Z * 0.5
expect(
	lobbySpawn.Position.Z >= streetStart and lobbySpawn.Position.Z <= streetEnd,
	"CentralStreet must include LobbySpawn"
)

for _, facilityName in
	{
		"TrainingZone",
		"StreetShop",
		"LockerRoom",
		"TrophyCorner",
		"RestZone",
		"EndLandmark",
	}
do
	expect(world:FindFirstChild(facilityName, true) ~= nil, facilityName .. " is missing")
end

local arenas = arenaServiceModule.new(world, config)
local arenaList = arenas:GetAll()
expect(#arenaList == 6, "expected exactly six physical 1v1 rooms")

local expectedRoomTitles = {
	["Concrete Cage"] = true,
	["Neon Futsal"] = true,
	["Club House"] = true,
	Industrial = true,
	["Training Lab"] = true,
	Championship = true,
}

for _, arena in arenaList do
	expect(arena.Model:GetAttribute("ArenaId") == arena.Id, arena.Id .. " has invalid ArenaId")
	local roomTitle = arena.Model:GetAttribute("RoomTitle")
	expect(
		type(roomTitle) == "string" and expectedRoomTitles[roomTitle] == true,
		arena.Id .. " has an invalid room title"
	)
	expectedRoomTitles[roomTitle] = nil
	expect(arena.Model:GetAttribute("ArenaState") == "Free", arena.Id .. " must start Free")
	expect(arena.Model:GetAttribute("WaitingCount") == 0, arena.Id .. " has stale waiting state")
	for _, partName in
		{
			"EntryZone",
			"ExitZone",
			"Barrier",
			"HomeWaitingSpawn",
			"AwayWaitingSpawn",
			"StreetSpawn",
			"StatusBoard",
			"SpectatorZone",
		}
	do
		local contractPart = arena.Model:FindFirstChild(partName)
		expect(
			contractPart ~= nil and contractPart:IsA("BasePart"),
			arena.Id .. " is missing direct " .. partName
		)
	end
	expect(
		arena.EntryPrompt ~= nil and arena.EntryPrompt.Name == "EntryPrompt",
		arena.Id .. " EntryPrompt is missing"
	)
	expect(
		arena.ExitPrompt ~= nil and arena.ExitPrompt.Name == "ExitPrompt",
		arena.Id .. " ExitPrompt is missing"
	)
	expect(arena.EntryPrompt.Enabled, arena.Id .. " EntryPrompt must be enabled while Free")
	expect(not arena.ExitPrompt.Enabled, arena.Id .. " ExitPrompt must be disabled while Free")
	expect(not arena.Barrier.CanCollide, arena.Id .. " Barrier must be open while Free")
	expect(
		arena.Ball:IsA("BasePart") and not arena.Ball.Anchored,
		arena.Id .. " ball must be physical"
	)
	expect(arena.Ball:GetNetworkOwner() == nil, arena.Id .. " ball must be server-owned")
	expect(arena.Ball:GetAttribute("ArenaId") == arena.Id, arena.Id .. " ball identity missing")
	expect(arena.Ball:GetAttribute("OwnerUserId") == 0, arena.Id .. " has a stale owner")
	expect(arena.Ball:GetAttribute("LastTouchUserId") == 0, arena.Id .. " has a stale last touch")
	local physicalProperties = arena.Ball.CustomPhysicalProperties
	expect(physicalProperties ~= nil, arena.Id .. " custom physical properties missing")
	local resolvedPhysicalProperties = physicalProperties :: PhysicalProperties
	expect(
		math.abs(resolvedPhysicalProperties.Density - config.Ball.Density) < 1e-4,
		arena.Id .. " ball density differs from Config"
	)
	expect(
		math.abs(resolvedPhysicalProperties.Friction - config.Ball.Friction) < 1e-4,
		arena.Id .. " ball friction differs from Config"
	)
	expect(
		math.abs(resolvedPhysicalProperties.Elasticity - config.Ball.Elasticity) < 1e-4,
		arena.Id .. " ball elasticity differs from Config"
	)
	for _, descendant in arena.Ball:GetDescendants() do
		expect(
			not descendant:IsA("Weld")
				and not descendant:IsA("WeldConstraint")
				and not descendant:IsA("Motor6D"),
			arena.Id .. " ball must not be welded"
		)
	end
	expect(
		arena.HomeGoal.CanTouch and arena.AwayGoal.CanTouch,
		arena.Id .. " goal triggers must touch"
	)
	expect(
		not arena.HomeGoal.CanCollide and not arena.AwayGoal.CanCollide,
		arena.Id .. " goals must not collide"
	)
	expect(
		arena.Bounds.Anchored and not arena.Bounds.CanCollide,
		arena.Id .. " bounds marker is invalid"
	)
	for _, goal in { arena.HomeGoal, arena.AwayGoal } do
		local apertureBottom = goal.Position.Y - goal.Size.Y * 0.5
		expect(
			math.abs(apertureBottom) < 0.05,
			arena.Id .. " goal aperture must start at court level"
		)
	end
	expect(
		arena.Model:FindFirstChild("RoomLabel", true) ~= nil
			and arena.Model:FindFirstChild("StateLabel", true) ~= nil
			and arena.Model:FindFirstChild("ScoreLabel", true) ~= nil,
		arena.Id .. " status-board labels are incomplete"
	)
	arenas:ResetBall(arena)
	expect(
		(arena.Ball.Position - arena.BallSpawn.Position).Magnitude < 0.05,
		arena.Id .. " ball reset failed"
	)
	expect(arena.Ball.AssemblyLinearVelocity.Magnitude < 1e-4, arena.Id .. " reset kept velocity")
	expect(
		arena.Ball.AssemblyAngularVelocity.Magnitude < 1e-4,
		arena.Id .. " reset kept angular velocity"
	)
	expect(arena.Ball:GetAttribute("OwnerUserId") == 0, arena.Id .. " reset kept owner")
	expect(arena.Ball:GetAttribute("LastTouchUserId") == 0, arena.Id .. " reset kept last touch")
end

expect(next(expectedRoomTitles) == nil, "not all six named room themes were created")
for _, arenaPosition in config.World.ArenaPositions do
	expect(
		arenaPosition.Position.Z >= streetStart and arenaPosition.Position.Z <= streetEnd,
		"CentralStreet must continue through every room row"
	)
end

local ballService = ballServiceModule.new(config, arenas)
expect(type(ballService.states) == "table", "BallService did not create arena states")
for _, arena in arenaList do
	expect(ballService.states[arena.Id] ~= nil, arena.Id .. " BallService state is missing")
	expect(arena.Ball:GetNetworkOwner() == nil, arena.Id .. " ball must remain server-owned")
	local controlAttachment = arena.Ball:FindFirstChild("PannaControlAttachment")
	local controlForce = arena.Ball:FindFirstChild("PannaDribbleForce")
	local trailTop = arena.Ball:FindFirstChild("PannaTrailTop")
	local trailBottom = arena.Ball:FindFirstChild("PannaTrailBottom")
	local speedTrail = arena.Ball:FindFirstChild("PannaSpeedTrail")
	expect(arena.Ball:GetAttribute("BallState") == "Reset", arena.Id .. " BallState is invalid")
	expect(
		type(arena.Ball:GetAttribute("BallRevision")) == "number",
		arena.Id .. " BallRevision missing"
	)
	expect(arena.Ball:GetAttribute("OwnerUserId") == 0, arena.Id .. " runtime owner is stale")
	expect(
		arena.Ball:GetAttribute("LastTouchUserId") == 0,
		arena.Id .. " runtime last touch is stale"
	)
	expect(arena.Ball:GetAttribute("LastAction") == "Reset", arena.Id .. " LastAction is invalid")
	expect(
		controlAttachment ~= nil and controlAttachment:IsA("Attachment"),
		arena.Id .. " runtime control attachment missing"
	)
	expect(
		controlForce ~= nil and controlForce:IsA("VectorForce"),
		arena.Id .. " runtime control force missing"
	)
	local resolvedForce = controlForce :: VectorForce
	expect(
		resolvedForce.Attachment0 == controlAttachment,
		arena.Id .. " runtime control force attachment is invalid"
	)
	expect(resolvedForce.ApplyAtCenterOfMass, arena.Id .. " control force must apply at center")
	expect(
		resolvedForce.RelativeTo == Enum.ActuatorRelativeTo.World,
		arena.Id .. " control force must use world space"
	)
	expect(resolvedForce.Force.Magnitude < 1e-4, arena.Id .. " control force must start at zero")
	expect(trailTop ~= nil and trailTop:IsA("Attachment"), arena.Id .. " trail top missing")
	expect(
		trailBottom ~= nil and trailBottom:IsA("Attachment"),
		arena.Id .. " trail bottom missing"
	)
	expect(
		speedTrail ~= nil and speedTrail:IsA("Trail") and not speedTrail.Enabled,
		arena.Id .. " runtime trail contract is invalid"
	)
	local resolvedTrail = speedTrail :: Trail
	expect(
		resolvedTrail.Attachment0 == trailTop and resolvedTrail.Attachment1 == trailBottom,
		arena.Id .. " speed trail attachments are invalid"
	)
	expect(
		math.abs(resolvedTrail.Lifetime - config.Ball.Trail.Lifetime) < 1e-4,
		arena.Id .. " speed trail lifetime differs from Config"
	)
	local state = ballService.states[arena.Id]
	expect(state.controlForce == resolvedForce, arena.Id .. " runtime state lost control force")
	expect(state.trail == resolvedTrail, arena.Id .. " runtime state lost speed trail")
	expect(state.mode == "Reset", arena.Id .. " runtime state must start Reset")
end

local remotes = remoteRegistry.Create(net)
expect(remotes.ActionRequest:IsA("RemoteEvent"), "ActionRequest remote missing")
expect(remotes.ActionFeedback:IsA("RemoteEvent"), "ActionFeedback remote missing")
expect(remotes.QueueRequest:IsA("RemoteEvent"), "QueueRequest remote missing")
expect(remotes.StateUpdate:IsA("RemoteEvent"), "StateUpdate remote missing")
expect(remotes.Effect:IsA("RemoteEvent"), "Effect remote missing")
expect(remotes.GetSnapshot:IsA("RemoteFunction"), "GetSnapshot remote missing")

print(string.format("PANNA_STUDIO_SMOKE_OK version=%s arenas=%d", config.Version, #arenaList))
