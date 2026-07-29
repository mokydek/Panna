--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local PannaDetector = require(script.Parent.PannaDetector)
local BallMath = require(ReplicatedStorage:WaitForChild("PannaShared"):WaitForChild("BallMath"))

local BallService = {}
BallService.__index = BallService

local SPECTATOR_COLLISION_GROUP = "PannaSpectator"
type BallMode = "Free" | "Controlled" | "Contested" | "Shot" | "Flight" | "Bounce" | "Reset"

type ChargeState = {
	action: string,
	startedAt: number,
	matchId: string,
	arenaId: string,
	revision: number,
	buffered: boolean,
}

type BufferedIntent = {
	action: string,
	direction: Vector3,
	shotType: string?,
	power: number,
	spin: number,
	createdAt: number,
	expiresAt: number,
	cooldownReserved: boolean,
}

type FeintState = {
	variant: string,
	direction: Vector3,
	lateral: number,
	startedAt: number,
	endsAt: number,
	vulnerableAt: number,
	vulnerableUntil: number,
}

type BallState = {
	arena: any,
	match: any?,
	active: boolean,
	owner: Player?,
	lastTouch: Player?,
	mode: BallMode,
	revision: number,
	modeSince: number,
	modeUntil: number,
	controlGraceUntil: number,
	recapturePlayer: Player?,
	recaptureUntil: number,
	contestedFirst: Player?,
	contestedSecond: Player?,
	buffered: { [Player]: BufferedIntent },
	grounded: boolean,
	groundPoint: Vector3?,
	groundNormal: Vector3,
	previousGrounded: boolean,
	lastBoundaryCheck: number,
	lastPosition: Vector3,
	ballCollisionGroup: string,
	participantCollisionGroup: string,
	controlForce: VectorForce,
	controlPosition: Vector3?,
	controlRotation: CFrame?,
	controlSnapPending: boolean,
	trail: Trail,
}

type MovementSample = {
	character: Model,
	trustedCFrame: CFrame,
	trustedAt: number,
	windowPosition: Vector3,
	windowAt: number,
	dashUsedInWindow: boolean,
	violations: number,
	lastViolationAt: number,
}

type DashState = {
	direction: Vector3,
	startedAt: number,
	endsAt: number,
	graceUntil: number,
	speedCapped: boolean,
}

type ShieldState = {
	direction: Vector3,
	startedAt: number,
	expiresAt: number,
}

export type ActionFeedback = {
	accepted: boolean,
	executed: boolean,
	reason: string,
	action: string,
	sequence: number,
	cooldownSeconds: number,
	revision: number,
	controllerUserId: number,
	mode: string,
}

export type Service = typeof(setmetatable(
	{} :: {
		config: any,
		arenas: any,
		states: { [string]: BallState },
		lastActions: { [number]: { [string]: number } },
		lastSequences: { [number]: number },
		charges: { [Player]: ChargeState },
		movementSamples: { [Player]: MovementSample },
		dashes: { [Player]: DashState },
		shields: { [Player]: ShieldState },
		feints: { [Player]: FeintState },
		playerConnections: { [Player]: RBXScriptConnection },
		characterConnections: { [Player]: RBXScriptConnection },
		onPanna: ((Player, Player) -> ())?,
		pannaDetector: any,
		heartbeat: RBXScriptConnection?,
		playerAddedConnection: RBXScriptConnection?,
		collisionGroupsReady: boolean,
		nextIntruderScan: number,
	},
	BallService
))

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function getHumanoid(player: Player): Humanoid?
	local character = player.Character
	return if character then character:FindFirstChildOfClass("Humanoid") else nil
end

local function finiteNumber(value: number): boolean
	return BallMath.IsFiniteNumber(value)
end

local function safeHorizontalDirection(value: any, fallback: Vector3): Vector3?
	local direction = if typeof(value) == "Vector3" then value else fallback
	if
		not finiteNumber(direction.X)
		or not finiteNumber(direction.Y)
		or not finiteNumber(direction.Z)
	then
		return nil
	end
	local horizontal = Vector3.new(direction.X, 0, direction.Z)
	if horizontal.Magnitude < 0.05 then
		horizontal = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if horizontal.Magnitude < 0.05 then
		return nil
	end
	return horizontal.Unit
end

local function groundRaycastParams(state: BallState): RaycastParams
	local exclusions: { Instance } = { state.arena.Ball }
	if state.match then
		if state.match.Home.Character then
			table.insert(exclusions, state.match.Home.Character)
		end
		if state.match.Away.Character then
			table.insert(exclusions, state.match.Away.Character)
		end
	end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	return params
end

local function opponent(match: any, player: Player): Player?
	if match.Home == player then
		return match.Away
	elseif match.Away == player then
		return match.Home
	end
	return nil
end

local function isParticipant(match: any, player: Player): boolean
	return match.Home == player or match.Away == player
end

local function collisionGroupNames(arenaId: string, index: number): (string, string)
	local safeId = string.gsub(arenaId, "[^%w_]", "_")
	if safeId == "" then
		safeId = "Arena"
	end
	safeId = string.sub(safeId, 1, 32)
	return string.format("PannaBall%d_%s", index, safeId),
		string.format("PannaPlayers%d_%s", index, safeId)
end

local function ensureCollisionGroup(name: string): boolean
	if pcall(function()
		PhysicsService:RegisterCollisionGroup(name)
	end) then
		return true
	end
	-- RegisterCollisionGroup raises when the group already exists. A harmless
	-- self-collidability query/write distinguishes that case from a real failure.
	return pcall(function()
		PhysicsService:CollisionGroupSetCollidable(name, name, true)
	end)
end

local function setGroupsCollidable(first: string, second: string, collidable: boolean): boolean
	return pcall(function()
		PhysicsService:CollisionGroupSetCollidable(first, second, collidable)
	end)
end

local function ensureAttachment(ball: BasePart, name: string, position: Vector3): Attachment
	local existing = ball:FindFirstChild(name)
	if existing and existing:IsA("Attachment") then
		existing.Position = position
		return existing
	end
	local attachment = Instance.new("Attachment")
	attachment.Name = name
	attachment.Position = position
	attachment.Parent = ball
	return attachment
end

local function ensureBallRuntime(ball: BasePart, config: any): (VectorForce, Trail)
	local controlAttachment = ensureAttachment(ball, "PannaControlAttachment", Vector3.zero)
	local forceInstance = ball:FindFirstChild("PannaDribbleForce")
	local controlForce: VectorForce
	if forceInstance and forceInstance:IsA("VectorForce") then
		controlForce = forceInstance
	else
		if forceInstance then
			forceInstance:Destroy()
		end
		controlForce = Instance.new("VectorForce")
		controlForce.Name = "PannaDribbleForce"
		controlForce.Parent = ball
	end
	controlForce.Attachment0 = controlAttachment
	controlForce.ApplyAtCenterOfMass = true
	controlForce.RelativeTo = Enum.ActuatorRelativeTo.World
	controlForce.Force = Vector3.zero
	-- Kept as a disabled runtime-contract object for existing places. Controlled
	-- possession is kinematic and never uses a mover force.
	controlForce.Enabled = false

	local radius = config.Ball.Radius
	local trailTop = ensureAttachment(ball, "PannaTrailTop", Vector3.new(0, radius * 0.55, 0))
	local trailBottom =
		ensureAttachment(ball, "PannaTrailBottom", Vector3.new(0, -radius * 0.55, 0))
	local trailInstance = ball:FindFirstChild("PannaSpeedTrail")
	local trail: Trail
	if trailInstance and trailInstance:IsA("Trail") then
		trail = trailInstance
	else
		if trailInstance then
			trailInstance:Destroy()
		end
		trail = Instance.new("Trail")
		trail.Name = "PannaSpeedTrail"
		trail.Parent = ball
	end
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Enabled = false
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.Lifetime = config.Ball.Trail.Lifetime
	trail.MinLength = 0.08
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, Color3.new(1, 1, 1)),
		ColorSequenceKeypoint.new(0.35, Color3.fromRGB(34, 238, 255)),
		ColorSequenceKeypoint.new(1, Color3.fromRGB(255, 54, 162)),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, config.Ball.Trail.WidthStart),
		NumberSequenceKeypoint.new(1, config.Ball.Trail.WidthEnd),
	})
	return controlForce, trail
end

function BallService.new(config: any, arenas: any): Service
	local self = setmetatable({
		config = config,
		arenas = arenas,
		states = {},
		lastActions = {},
		lastSequences = {},
		charges = {},
		movementSamples = {},
		dashes = {},
		shields = {},
		feints = {},
		playerConnections = {},
		characterConnections = {},
		onPanna = nil,
		pannaDetector = nil,
		heartbeat = nil,
		playerAddedConnection = nil,
		collisionGroupsReady = false,
		nextIntruderScan = 0,
	}, BallService)

	self.pannaDetector = PannaDetector.new(function(attacker: Player, defender: Player)
		if self.onPanna then
			self.onPanna(attacker, defender)
		end
	end)

	local groupsReady = ensureCollisionGroup(SPECTATOR_COLLISION_GROUP)
	for index, arena in arenas:GetAll() do
		local ballCollisionGroup, participantCollisionGroup = collisionGroupNames(arena.Id, index)
		local ballGroupReady = ensureCollisionGroup(ballCollisionGroup)
		local participantGroupReady = ensureCollisionGroup(participantCollisionGroup)
		groupsReady = groupsReady and ballGroupReady and participantGroupReady
		local controlForce, trail = ensureBallRuntime(arena.Ball, config)
		self.states[arena.Id] = {
			arena = arena,
			match = nil,
			active = false,
			owner = nil,
			lastTouch = nil,
			mode = "Reset",
			revision = 0,
			modeSince = os.clock(),
			modeUntil = 0,
			controlGraceUntil = 0,
			recapturePlayer = nil,
			recaptureUntil = 0,
			contestedFirst = nil,
			contestedSecond = nil,
			buffered = {},
			grounded = false,
			groundPoint = nil,
			groundNormal = Vector3.yAxis,
			previousGrounded = false,
			lastBoundaryCheck = 0,
			lastPosition = arena.Ball.Position,
			ballCollisionGroup = ballCollisionGroup,
			participantCollisionGroup = participantCollisionGroup,
			controlForce = controlForce,
			controlPosition = nil,
			controlRotation = nil,
			controlSnapPending = false,
			trail = trail,
		}
		arena.Ball.Anchored = false
		arena.Ball:SetNetworkOwner(nil)
		arena.Ball:SetAttribute("OwnerUserId", 0)
		arena.Ball:SetAttribute("LastTouchUserId", 0)
		arena.Ball:SetAttribute("BallState", "Reset")
		arena.Ball:SetAttribute("BallRevision", 0)
		arena.Ball:SetAttribute("LastAction", "Reset")
	end

	if groupsReady then
		for _, state in self.states do
			groupsReady = setGroupsCollidable(
				state.ballCollisionGroup,
				SPECTATOR_COLLISION_GROUP,
				false
			) and groupsReady
			groupsReady = setGroupsCollidable(
				state.participantCollisionGroup,
				SPECTATOR_COLLISION_GROUP,
				false
			) and groupsReady
			for _, otherState in self.states do
				groupsReady = setGroupsCollidable(
					state.ballCollisionGroup,
					otherState.ballCollisionGroup,
					state == otherState
				) and groupsReady
				groupsReady = setGroupsCollidable(
					state.ballCollisionGroup,
					otherState.participantCollisionGroup,
					false
				) and groupsReady
				groupsReady = setGroupsCollidable(
					state.participantCollisionGroup,
					otherState.participantCollisionGroup,
					state == otherState
				) and groupsReady
			end
		end
	end
	self.collisionGroupsReady = groupsReady
	if groupsReady then
		for _, state in self.states do
			state.arena.Ball.CollisionGroup = state.ballCollisionGroup
		end
	else
		warn("[Panna] Collision-group isolation is unavailable; intrusion ejection remains active")
	end

	self.playerAddedConnection = Players.PlayerAdded:Connect(function(player: Player)
		self:_trackPlayer(player)
	end)
	for _, player in Players:GetPlayers() do
		self:_trackPlayer(player)
	end

	return self
end

function BallService._collisionGroupForPlayer(self: Service, player: Player): string
	for _, state in self.states do
		if state.match and isParticipant(state.match, player) then
			return state.participantCollisionGroup
		end
	end
	return SPECTATOR_COLLISION_GROUP
end

function BallService._setCharacterCollisionGroup(self: Service, player: Player, groupName: string?)
	if not self.collisionGroupsReady then
		return
	end
	local character = player.Character
	if not character then
		return
	end
	local resolvedGroup = groupName or self:_collisionGroupForPlayer(player)
	for _, descendant in character:GetDescendants() do
		if descendant:IsA("BasePart") then
			descendant.CollisionGroup = resolvedGroup
		end
	end
end

function BallService._watchCharacter(self: Service, player: Player, character: Model)
	local previous = self.characterConnections[player]
	if previous then
		previous:Disconnect()
	end
	self:_setCharacterCollisionGroup(player)
	self.characterConnections[player] = character.DescendantAdded:Connect(
		function(descendant: Instance)
			if descendant:IsA("BasePart") and self.collisionGroupsReady then
				descendant.CollisionGroup = self:_collisionGroupForPlayer(player)
			end
		end
	)
end

function BallService._trackPlayer(self: Service, player: Player)
	local previous = self.playerConnections[player]
	if previous then
		previous:Disconnect()
	end
	self.playerConnections[player] = player.CharacterAdded:Connect(function(character: Model)
		self:_watchCharacter(player, character)
	end)
	if player.Character then
		self:_watchCharacter(player, player.Character)
	end
end

function BallService._spawnForPlayer(_self: Service, state: BallState, player: Player): BasePart
	return if state.match and player == state.match.Home
		then state.arena.HomeSpawn
		else state.arena.AwaySpawn
end

function BallService._recordMovementSample(
	self: Service,
	player: Player,
	root: BasePart,
	now: number,
	violations: number?
)
	local character = player.Character
	if not character then
		self.movementSamples[player] = nil
		return
	end
	local previous = self.movementSamples[player]
	self.movementSamples[player] = {
		character = character,
		trustedCFrame = root.CFrame,
		trustedAt = now,
		windowPosition = root.Position,
		windowAt = now,
		dashUsedInWindow = false,
		violations = violations or 0,
		lastViolationAt = if previous then previous.lastViolationAt else -math.huge,
	}
end

function BallService._teleportToParticipantSpawn(
	self: Service,
	state: BallState,
	player: Player,
	now: number
): boolean
	if not state.match or not isParticipant(state.match, player) then
		return false
	end
	local teleported = self.arenas:TeleportToSpawn(player, self:_spawnForPlayer(state, player))
	local root = getRoot(player)
	if teleported and root then
		self:_recordMovementSample(player, root, now)
		return true
	end
	self.movementSamples[player] = nil
	return false
end

function BallService._rejectMovement(
	self: Service,
	state: BallState,
	player: Player,
	root: BasePart,
	sample: MovementSample,
	now: number
)
	local movement = self.config.Security.Movement
	local violations = if now - sample.lastViolationAt <= movement.ViolationWindow
		then sample.violations + 1
		else 1
	local totalAttribute = player:GetAttribute("MovementViolationCount")
	local total = if type(totalAttribute) == "number" then totalAttribute else 0
	player:SetAttribute("MovementViolationCount", total + 1)

	if violations >= movement.ViolationsBeforeRespawn then
		self:_teleportToParticipantSpawn(state, player, now)
		return
	end

	local character = player.Character
	if character and character == sample.character then
		local rootFromPivot = character:GetPivot():ToObjectSpace(root.CFrame)
		character:PivotTo(sample.trustedCFrame * rootFromPivot:Inverse())
	end
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	sample.trustedAt = now
	sample.windowPosition = sample.trustedCFrame.Position
	sample.windowAt = now
	sample.dashUsedInWindow = false
	sample.violations = violations
	sample.lastViolationAt = now
end

function BallService._validateMovement(
	self: Service,
	state: BallState,
	player: Player,
	now: number
): boolean
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	local character = player.Character
	if not root or not humanoid or humanoid.Health <= 0 or not character then
		self.movementSamples[player] = nil
		self.dashes[player] = nil
		self.shields[player] = nil
		return false
	end

	local sample = self.movementSamples[player]
	if not sample or sample.character ~= character then
		return self:_teleportToParticipantSpawn(state, player, now)
	end

	local position = root.Position
	if
		not finiteNumber(position.X)
		or not finiteNumber(position.Y)
		or not finiteNumber(position.Z)
	then
		self:_rejectMovement(state, player, root, sample, now)
		return false
	end

	local elapsed = math.max(0, now - sample.trustedAt)
	local windowElapsed = math.max(0, now - sample.windowAt)
	local displacement = position - sample.trustedCFrame.Position
	local horizontalDistance = Vector3.new(displacement.X, 0, displacement.Z).Magnitude
	local windowDisplacement = position - sample.windowPosition
	local windowHorizontalDistance =
		Vector3.new(windowDisplacement.X, 0, windowDisplacement.Z).Magnitude

	local movement = self.config.Security.Movement
	local walkEnvelope = math.max(20, math.min(humanoid.WalkSpeed + 4, 26))
	local dash = self.dashes[player]
	local shortSpeed = if dash and now <= dash.graceUntil
		then self.config.Actions.DashSpeed + 8
		else walkEnvelope
	local shortAllowance = movement.ShortSlack + shortSpeed * math.min(elapsed, 1.5)
	local dashWindowAllowance = if sample.dashUsedInWindow
		then math.max(0, self.config.Actions.DashSpeed - walkEnvelope)
				* self.config.Actions.DashSeconds
			+ 3
		else 0
	local windowAllowance = movement.WindowSlack
		+ walkEnvelope * math.min(windowElapsed, 1.5)
		+ dashWindowAllowance
	local shortVerticalAllowance = movement.VerticalSlack + 70 * math.min(elapsed, 0.4)
	local windowVerticalAllowance = 18
	local outsideEnvelope = horizontalDistance > shortAllowance
		or math.abs(displacement.Y) > shortVerticalAllowance
		or windowHorizontalDistance > windowAllowance
		or math.abs(windowDisplacement.Y) > windowVerticalAllowance
		or not self.arenas:IsInside(
			state.arena,
			position,
			self.config.Security.MaxCharacterDistanceFromArena
		)

	if outsideEnvelope then
		self:_rejectMovement(state, player, root, sample, now)
		return false
	end

	if now - sample.lastViolationAt > movement.ViolationWindow then
		sample.violations = 0
	end
	if elapsed >= movement.SampleInterval then
		sample.trustedCFrame = root.CFrame
		sample.trustedAt = now
	end
	if windowElapsed >= movement.WindowSeconds then
		sample.windowPosition = position
		sample.windowAt = now
		sample.dashUsedInWindow = dash ~= nil and now <= dash.endsAt
	end
	return true
end

function BallService._stepDashes(self: Service, now: number)
	for player, dash in self.dashes do
		local state = self:_stateForPlayer(player)
		local root = getRoot(player)
		local humanoid = getHumanoid(player)
		if
			not state
			or not state.active
			or state.match == nil
			or state.match.Ended
			or player:GetAttribute("ControlsLocked") == true
			or not root
			or not humanoid
			or humanoid.Health <= 0
			or now > dash.graceUntil
		then
			self.dashes[player] = nil
		elseif now <= dash.endsAt then
			root.AssemblyLinearVelocity = dash.direction * self.config.Actions.DashSpeed
				+ Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		elseif not dash.speedCapped then
			local horizontal =
				Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
			local maximum = math.max(20, math.min(humanoid.WalkSpeed + 4, 26))
			if horizontal.Magnitude > maximum then
				horizontal = horizontal.Unit * maximum
				root.AssemblyLinearVelocity = horizontal
					+ Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
			end
			dash.speedCapped = true
		end
	end
end

function BallService._ejectIntruders(self: Service, now: number)
	if now < self.nextIntruderScan then
		return
	end
	self.nextIntruderScan = now + self.config.Security.Movement.IntruderScanInterval

	local players = Players:GetPlayers()
	for _, state in self.states do
		if state.match then
			for _, player in players do
				local root = getRoot(player)
				if
					not isParticipant(state.match, player)
					and root
					and self.arenas:IsInside(state.arena, root.Position, 0)
				then
					local intrusionAttribute = player:GetAttribute("ArenaIntrusionCount")
					local intrusions = if type(intrusionAttribute) == "number"
						then intrusionAttribute
						else 0
					player:SetAttribute("ArenaIntrusionCount", intrusions + 1)
					self.movementSamples[player] = nil
					self.dashes[player] = nil
					self.shields[player] = nil
					self.arenas:ReturnToStreet(state.arena, player)
					self:_setCharacterCollisionGroup(player)
				end
			end
		end
	end
end

function BallService.SetPannaCallback(self: Service, callback: (Player, Player) -> ())
	self.onPanna = callback
end

function BallService._feedback(
	_self: Service,
	state: BallState?,
	accepted: boolean,
	executed: boolean,
	reason: string,
	action: string,
	sequence: number,
	cooldownSeconds: number
): ActionFeedback
	return {
		accepted = accepted,
		executed = executed,
		reason = reason,
		action = action,
		sequence = sequence,
		cooldownSeconds = math.max(0, cooldownSeconds),
		revision = if state then state.revision else 0,
		controllerUserId = if state and state.owner then state.owner.UserId else 0,
		mode = if state then state.mode else "Free",
	}
end

function BallService._beginKinematicControl(_self: Service, state: BallState)
	local ball = state.arena.Ball
	state.controlForce.Force = Vector3.zero
	state.controlForce.Enabled = false
	state.trail.Enabled = false

	if not ball.Anchored then
		ball:SetNetworkOwner(nil)
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
		ball.Anchored = true
	end
	state.controlPosition = ball.Position
	state.controlRotation = ball.CFrame.Rotation
	state.controlSnapPending = false
end

function BallService._restorePhysicalBall(_self: Service, state: BallState)
	local ball = state.arena.Ball
	state.controlForce.Force = Vector3.zero
	state.controlForce.Enabled = false
	state.controlPosition = nil
	state.controlRotation = nil
	state.controlSnapPending = false

	-- Only clear velocity when leaving the anchored control invariant. Other
	-- physical-to-physical state changes (Shot -> Flight -> Bounce) must retain it.
	if ball.Anchored then
		ball.Anchored = false
		ball.AssemblyLinearVelocity = Vector3.zero
		ball.AssemblyAngularVelocity = Vector3.zero
	end
	ball:SetNetworkOwner(nil)
end

function BallService._setBallMode(
	self: Service,
	state: BallState,
	mode: BallMode,
	owner: Player?,
	lastAction: string?
)
	local ball = state.arena.Ball
	local currentAction = ball:GetAttribute("LastAction")
	local changed = state.mode ~= mode or state.owner ~= owner
	local actionChanged = lastAction ~= nil and currentAction ~= lastAction
	if not changed and not actionChanged then
		return
	end

	local previousOwner = state.owner
	state.mode = mode
	state.owner = owner
	state.modeSince = os.clock()
	state.revision += 1
	if previousOwner and previousOwner ~= owner then
		self.shields[previousOwner] = nil
		self.feints[previousOwner] = nil
	end
	if mode == "Controlled" and owner then
		self:_beginKinematicControl(state)
	else
		self:_restorePhysicalBall(state)
	end
	if mode ~= "Contested" then
		state.contestedFirst = nil
		state.contestedSecond = nil
	end
	ball:SetAttribute("BallState", mode)
	ball:SetAttribute("BallRevision", state.revision)
	ball:SetAttribute("OwnerUserId", if owner then owner.UserId else 0)
	if lastAction then
		ball:SetAttribute("LastAction", lastAction)
	end
end

function BallService._markAction(_self: Service, state: BallState, action: string, player: Player?)
	state.revision += 1
	local ball = state.arena.Ball
	ball:SetAttribute("BallRevision", state.revision)
	ball:SetAttribute("LastAction", action)
	ball:SetAttribute("LastActionUserId", if player then player.UserId else 0)
end

function BallService._clearPlayerRuntime(self: Service, player: Player)
	self.charges[player] = nil
	self.dashes[player] = nil
	self.shields[player] = nil
	self.feints[player] = nil
	for _, state in self.states do
		state.buffered[player] = nil
		if state.recapturePlayer == player then
			state.recapturePlayer = nil
			state.recaptureUntil = 0
		end
	end
end

function BallService.Start(self: Service)
	if self.heartbeat then
		return
	end
	self.heartbeat = RunService.Heartbeat:Connect(function(deltaTime: number)
		self:_step(deltaTime)
	end)
end

function BallService.AttachMatch(self: Service, match: any)
	local state = self.states[match.Arena.Id]
	assert(state, "Missing ball state for arena")
	state.match = match
	state.active = false
	state.owner = nil
	state.lastTouch = nil
	state.buffered = {}
	state.recapturePlayer = nil
	state.recaptureUntil = 0
	state.contestedFirst = nil
	state.contestedSecond = nil
	for _, player in { match.Home, match.Away } do
		self.movementSamples[player] = nil
		self:_clearPlayerRuntime(player)
		self:_setCharacterCollisionGroup(player, state.participantCollisionGroup)
	end
	match.Arena.Ball:SetAttribute("MatchId", match.Id)
	self:ResetMatchBall(match)
end

function BallService.DetachMatch(self: Service, match: any)
	local state = self.states[match.Arena.Id]
	if not state or state.match ~= match then
		return
	end
	state.match = nil
	state.active = false
	self:_setBallMode(state, "Reset", nil, "Reset")
	state.lastTouch = nil
	state.arena.Ball:SetAttribute("MatchId", "")
	state.arena.Ball:SetAttribute("OwnerUserId", 0)
	state.arena.Ball:SetAttribute("LastTouchUserId", 0)
	self.pannaDetector:ClearBall(state.arena.Ball)
	self.pannaDetector:ClearPlayer(match.Home)
	self.pannaDetector:ClearPlayer(match.Away)
	for _, player in { match.Home, match.Away } do
		self.movementSamples[player] = nil
		self:_clearPlayerRuntime(player)
		self:_setCharacterCollisionGroup(player, SPECTATOR_COLLISION_GROUP)
	end
end

function BallService.SetActive(self: Service, match: any, active: boolean)
	local state = self.states[match.Arena.Id]
	if state and state.match == match then
		state.active = active
		if active then
			local now = os.clock()
			for _, player in { match.Home, match.Away } do
				self:_clearPlayerRuntime(player)
				self:_teleportToParticipantSpawn(state, player, now)
			end
		else
			self:_setBallMode(state, "Reset", nil, "Reset")
			self.pannaDetector:ClearBall(state.arena.Ball)
			for _, player in { match.Home, match.Away } do
				self.movementSamples[player] = nil
				self:_clearPlayerRuntime(player)
			end
		end
	end
end

function BallService.ResetMatchBall(self: Service, match: any)
	local state = self.states[match.Arena.Id]
	if not state or state.match ~= match then
		return
	end
	self.pannaDetector:ClearBall(state.arena.Ball)
	self:_setBallMode(state, "Reset", nil, "Reset")
	self:_restorePhysicalBall(state)
	state.lastTouch = nil
	state.modeUntil = os.clock() + self.config.Ball.ResetHoldSeconds
	state.recapturePlayer = nil
	state.recaptureUntil = 0
	state.buffered = {}
	state.grounded = false
	state.previousGrounded = false
	state.arena.Ball:SetAttribute("LastTouchUserId", 0)
	self.arenas:ResetBall(state.arena)
	state.arena.Ball:SetAttribute("BallState", "Reset")
	state.arena.Ball:SetAttribute("BallRevision", state.revision)
	state.arena.Ball:SetAttribute("LastAction", "Reset")
	state.trail.Enabled = false
	state.lastPosition = state.arena.Ball.Position
end

function BallService._setOwner(self: Service, state: BallState, player: Player?)
	self:_setBallMode(state, if player then "Controlled" else "Free", player, nil)
end

function BallService._stateForPlayer(self: Service, player: Player): BallState?
	local arenaId = player:GetAttribute("ArenaId")
	if type(arenaId) ~= "string" then
		return nil
	end
	local state = self.states[arenaId]
	if not state or not state.match or not isParticipant(state.match, player) then
		return nil
	end
	return state
end

function BallService._activeShield(
	self: Service,
	state: BallState,
	player: Player,
	now: number
): ShieldState?
	local shield = self.shields[player]
	if not shield then
		return nil
	end
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if
		state.owner ~= player
		or not state.active
		or not state.match
		or state.match.Ended
		or player:GetAttribute("ControlsLocked") == true
		or not root
		or not humanoid
		or humanoid.Health <= 0
		or now > shield.expiresAt
		or (root.Position - state.arena.Ball.Position).Magnitude
			> self.config.Actions.Shield.Radius
	then
		self.shields[player] = nil
		return nil
	end
	local facing = if humanoid.MoveDirection.Magnitude > 0.15
		then humanoid.MoveDirection
		else root.CFrame.LookVector
	local currentDirection = safeHorizontalDirection(facing, shield.direction)
	if currentDirection then
		shield.direction = currentDirection
	end
	return shield
end

function BallService._stepShields(self: Service, now: number)
	for player in self.shields do
		local state = self:_stateForPlayer(player)
		if not state then
			self.shields[player] = nil
		else
			self:_activeShield(state, player, now)
		end
	end
end

function BallService._stepFeints(self: Service, now: number)
	for player, feint in self.feints do
		local state = self:_stateForPlayer(player)
		if
			not state
			or not state.active
			or state.owner ~= player
			or now > feint.endsAt
			or player:GetAttribute("ControlsLocked") == true
		then
			self.feints[player] = nil
		end
	end
end

function BallService._cooldownRemaining(
	self: Service,
	player: Player,
	action: string,
	duration: number,
	now: number
): number
	local byAction = self.lastActions[player.UserId]
	local last = if byAction then byAction[action] else nil
	return math.max(0, duration - (now - (last or -1e6)))
end

function BallService._consumeCooldown(
	self: Service,
	player: Player,
	action: string,
	duration: number,
	now: number
): (boolean, number)
	local remaining = self:_cooldownRemaining(player, action, duration, now)
	if remaining > 0 then
		return false, remaining
	end
	local byAction = self.lastActions[player.UserId]
	if not byAction then
		byAction = {}
		self.lastActions[player.UserId] = byAction
	end
	byAction[action] = now
	return true, duration
end

function BallService._hasStrictContact(
	self: Service,
	player: Player,
	state: BallState,
	radius: number?,
	maximumHeight: number?
): (boolean, BasePart?)
	local root = getRoot(player)
	if not root then
		return false, nil
	end
	local ball = state.arena.Ball
	local offset = ball.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	local capture = self.config.Ball.Capture
	local localBall = root.CFrame:PointToObjectSpace(ball.Position)
	local forward = -localBall.Z
	local allowedRadius = radius or self.config.Ball.InteractionRadius
	local allowedHeight = maximumHeight or self.config.Security.Command.MaximumContactHeight
	local valid = horizontal.Magnitude <= allowedRadius
		and math.abs(offset.Y) <= allowedHeight
		and forward >= -capture.RearAllowance
		and math.abs(localBall.X) <= math.max(capture.LateralDistance, allowedRadius * 0.72)
	return valid, root
end

function BallService._aimAccepted(self: Service, root: BasePart, direction: Vector3): boolean
	local facing = safeHorizontalDirection(root.CFrame.LookVector, direction)
	return facing ~= nil
		and facing:Dot(direction) >= self.config.Security.Command.MinimumAimFacingDot
end

function BallService._canBuffer(
	self: Service,
	player: Player,
	state: BallState,
	now: number
): boolean
	if state.recapturePlayer == player and now < state.recaptureUntil then
		return false
	end
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local firstTouch = self.config.Ball.FirstTouch
	local offset = root.Position - state.arena.Ball.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if
		horizontal.Magnitude > firstTouch.Radius
		or math.abs(offset.Y) > firstTouch.MaximumHeight
	then
		return false
	end
	local velocity = state.arena.Ball.AssemblyLinearVelocity
	if velocity.Magnitude <= firstTouch.SoftSpeed then
		return true
	end
	return horizontal.Magnitude > 0.05 and velocity.Unit:Dot(horizontal.Unit) > 0.05
end

function BallService._chargedPower(self: Service, action: string, elapsed: number): number
	local settings = if action == "Kick" then self.config.Ball.Shot else self.config.Ball.Pass
	local raw = BallMath.ChargePower(elapsed, settings.ChargeSeconds, settings.MinimumPower)
	local normalized =
		math.clamp((raw - settings.MinimumPower) / math.max(0.001, 1 - settings.MinimumPower), 0, 1)
	return settings.MinimumPower + (1 - settings.MinimumPower) * normalized ^ settings.PowerExponent
end

function BallService._launch(
	self: Service,
	state: BallState,
	player: Player,
	action: string,
	velocity: Vector3,
	angularImpulse: Vector3,
	recapturePlayer: Player?,
	recaptureSeconds: number,
	shotSeconds: number
)
	local ball = state.arena.Ball
	local limits = self.config.Ball.Limits
	local horizontal =
		BallMath.ClampMagnitude(Vector3.new(velocity.X, 0, velocity.Z), limits.MaximumSpeed)
	local targetVelocity = horizontal
		+ Vector3.new(
			0,
			math.clamp(velocity.Y, -limits.MaximumVerticalSpeed, limits.MaximumVerticalSpeed),
			0
		)
	targetVelocity = BallMath.ClampMagnitude(targetVelocity, limits.MaximumSpeed)
	state.lastTouch = player
	state.recapturePlayer = recapturePlayer
	state.recaptureUntil = os.clock() + math.max(0, recaptureSeconds)
	state.modeUntil = os.clock() + math.max(0, shotSeconds)
	self:_setBallMode(state, "Shot", nil, action)
	ball:SetNetworkOwner(nil)
	ball:SetAttribute("LastTouchUserId", player.UserId)
	ball:SetAttribute("LastActionUserId", player.UserId)
	ball:ApplyImpulse((targetVelocity - ball.AssemblyLinearVelocity) * ball.AssemblyMass)
	if angularImpulse.Magnitude > 0.01 then
		ball:ApplyAngularImpulse(angularImpulse * ball.AssemblyMass)
	end
end

function BallService._executeKick(
	self: Service,
	state: BallState,
	player: Player,
	direction: Vector3,
	power: number,
	shotType: string,
	spin: number
): boolean
	local root = getRoot(player)
	local shot = self.config.Ball.Shot
	local settings = shot.Types[shotType]
	if not root or type(settings) ~= "table" then
		return false
	end
	local speed = settings.SpeedMinimum + (settings.SpeedMaximum - settings.SpeedMinimum) * power
	local lift = settings.LiftMinimum + (settings.LiftMaximum - settings.LiftMinimum) * power
	local rootVelocity =
		Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local velocity = direction * speed
		+ rootVelocity * shot.PlayerVelocityCarry
		+ Vector3.new(0, lift, 0)
	local rollAxis = Vector3.new(0, 1, 0):Cross(direction)
	local angular = rollAxis * settings.RollSpin * shot.AngularImpulseScale
		+ Vector3.yAxis
			* math.clamp(spin, -1, 1)
			* shot.SideSpinMaximum
			* settings.SideSpinMultiplier
			* shot.AngularImpulseScale
	self:_launch(
		state,
		player,
		"Kick",
		velocity,
		angular,
		player,
		shot.ShooterRecaptureSeconds,
		shot.StateSeconds
	)
	state.arena.Ball:SetAttribute("LastShotType", shotType)
	return true
end

function BallService._executePass(
	self: Service,
	state: BallState,
	player: Player,
	direction: Vector3,
	power: number
): boolean
	local root = getRoot(player)
	if not root then
		return false
	end
	local pass = self.config.Ball.Pass
	local speed = pass.SpeedMinimum + (pass.SpeedMaximum - pass.SpeedMinimum) * power
	local lift = pass.LiftMinimum + (pass.LiftMaximum - pass.LiftMinimum) * power
	local rootVelocity =
		Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local velocity = direction * speed
		+ rootVelocity * pass.PlayerVelocityCarry
		+ Vector3.new(0, lift, 0)
	local angular = Vector3.new(0, 1, 0):Cross(direction) * pass.RollSpin * pass.AngularImpulseScale
	self:_launch(
		state,
		player,
		"Pass",
		velocity,
		angular,
		player,
		pass.ShooterRecaptureSeconds,
		pass.StateSeconds
	)
	return true
end

function BallService._executeTrap(
	self: Service,
	state: BallState,
	player: Player,
	_direction: Vector3
): boolean
	local root = getRoot(player)
	if not root then
		return false
	end
	local ball = state.arena.Ball
	self:_setBallMode(state, "Controlled", player, "Trap")
	state.controlSnapPending = true
	state.controlGraceUntil = os.clock() + self.config.Ball.Capture.ControlGraceSeconds
	state.lastTouch = player
	ball:SetAttribute("LastTouchUserId", player.UserId)
	ball:SetAttribute("LastActionUserId", player.UserId)
	return true
end

function BallService._bufferIntent(
	self: Service,
	state: BallState,
	player: Player,
	action: string,
	direction: Vector3,
	shotType: string?,
	power: number,
	spin: number,
	now: number
)
	state.buffered[player] = {
		action = action,
		direction = direction,
		shotType = shotType,
		power = power,
		spin = spin,
		createdAt = now,
		expiresAt = now + self.config.Ball.FirstTouch.BufferSeconds,
		cooldownReserved = true,
	}
end

function BallService._executeBuffered(self: Service, state: BallState, player: Player, now: number)
	local buffered = state.buffered[player]
	state.buffered[player] = nil
	if not buffered or buffered.expiresAt < now or state.owner ~= player then
		return
	end
	if buffered.action == "Kick" then
		self:_executeKick(
			state,
			player,
			buffered.direction,
			buffered.power,
			buffered.shotType or "Normal",
			buffered.spin
		)
	elseif buffered.action == "Pass" then
		self:_executePass(state, player, buffered.direction, buffered.power)
	elseif buffered.action == "Trap" then
		self:_executeTrap(state, player, buffered.direction)
	end
end

function BallService.HandleAction(self: Service, player: Player, payload: any): ActionFeedback
	local action = if type(payload) == "table" and type(payload.action) == "string"
		then payload.action
		else ""
	local state = self:_stateForPlayer(player)
	local rawSequence = if type(payload) == "table" then payload.sequence else nil
	local sequence = if type(rawSequence) == "number" and finiteNumber(rawSequence)
		then math.floor(rawSequence)
		else 0
	if type(payload) ~= "table" or action == "" then
		return self:_feedback(state, false, false, "InvalidPayload", action, sequence, 0)
	end
	if not state or not state.match or not state.active or state.match.Ended then
		return self:_feedback(state, false, false, "NoActiveMatch", action, sequence, 0)
	end
	if player:GetAttribute("ControlsLocked") == true then
		return self:_feedback(state, false, false, "ControlsLocked", action, sequence, 0)
	end
	if sequence < 1 or rawSequence ~= sequence then
		return self:_feedback(state, false, false, "InvalidSequence", action, sequence, 0)
	end
	local previousSequence = self.lastSequences[player.UserId] or 0
	if sequence <= previousSequence then
		return self:_feedback(state, false, false, "StaleSequence", action, sequence, 0)
	end
	if sequence - previousSequence > self.config.Security.Command.MaximumSequenceJump then
		return self:_feedback(state, false, false, "SequenceJump", action, sequence, 0)
	end
	if payload.matchId ~= state.match.Id then
		return self:_feedback(state, false, false, "MatchMismatch", action, sequence, 0)
	end
	if payload.arenaId ~= state.arena.Id then
		return self:_feedback(state, false, false, "ArenaMismatch", action, sequence, 0)
	end
	if type(payload.ballRevision) ~= "number" or payload.ballRevision ~= state.revision then
		return self:_feedback(state, false, false, "RevisionMismatch", action, sequence, 0)
	end
	local clientTime = payload.clientTime
	local serverTime = Workspace:GetServerTimeNow()
	if
		type(clientTime) ~= "number"
		or not finiteNumber(clientTime)
		or serverTime - clientTime > self.config.Security.Command.MaximumPastSeconds
		or clientTime - serverTime > self.config.Security.Command.MaximumFutureSeconds
	then
		return self:_feedback(state, false, false, "StaleClientTime", action, sequence, 0)
	end

	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	local now = os.clock()
	if not root or not humanoid or humanoid.Health <= 0 then
		return self:_feedback(state, false, false, "CharacterUnavailable", action, sequence, 0)
	end
	if not self:_validateMovement(state, player, now) then
		return self:_feedback(state, false, false, "MovementRejected", action, sequence, 0)
	end

	local needsDirection = action ~= "ChargeStart"
		and not (action == "Shield" and payload.active == false)
	local direction: Vector3? = nil
	if needsDirection then
		if
			typeof(payload.direction) ~= "Vector3"
			or not BallMath.IsFiniteVector3(payload.direction)
		then
			return self:_feedback(state, false, false, "InvalidDirection", action, sequence, 0)
		end
		local submittedHorizontal = Vector3.new(payload.direction.X, 0, payload.direction.Z)
		if
			math.abs(submittedHorizontal.Magnitude - 1)
			> self.config.Security.MaxDirectionMagnitudeError
		then
			return self:_feedback(state, false, false, "InvalidDirection", action, sequence, 0)
		end
		direction = safeHorizontalDirection(payload.direction, root.CFrame.LookVector)
		if not direction then
			return self:_feedback(state, false, false, "InvalidDirection", action, sequence, 0)
		end
	end
	self.lastSequences[player.UserId] = sequence

	if action == "ChargeStart" then
		local chargeAction = payload.chargeAction
		if chargeAction ~= "Kick" and chargeAction ~= "Pass" then
			return self:_feedback(state, false, false, "InvalidChargeAction", action, sequence, 0)
		end
		local contact = self:_hasStrictContact(player, state)
		local controls = state.owner == player and state.mode == "Controlled" and contact
		local buffered = not controls and self:_canBuffer(player, state, now)
		if not controls and not buffered then
			return self:_feedback(
				state,
				false,
				false,
				if contact then "NotController" else "NoContact",
				action,
				sequence,
				0
			)
		end
		local ready, cooldown = self:_consumeCooldown(
			player,
			"ChargeStart",
			self.config.Actions.ChargeStartCooldown,
			now
		)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		self.charges[player] = {
			action = chargeAction,
			startedAt = now,
			matchId = state.match.Id,
			arenaId = state.arena.Id,
			revision = state.revision,
			buffered = buffered,
		}
		return self:_feedback(state, true, true, "Charging", action, sequence, 0)
	end

	if action == "Shield" and payload.active == false then
		local wasActive = self.shields[player] ~= nil
		self.shields[player] = nil
		return self:_feedback(
			state,
			true,
			wasActive,
			if wasActive then "Executed" else "AlreadyOff",
			action,
			sequence,
			0
		)
	end

	local resolvedDirection = direction :: Vector3
	if action == "Dash" then
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.DashCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		self.shields[player] = nil
		local dashSeconds = math.max(0, self.config.Actions.DashSeconds)
		self.dashes[player] = {
			direction = resolvedDirection,
			startedAt = now,
			endsAt = now + dashSeconds,
			graceUntil = now + dashSeconds + 0.35,
			speedCapped = false,
		}
		local movementSample = self.movementSamples[player]
		if movementSample then
			movementSample.dashUsedInWindow = true
		end
		root.AssemblyLinearVelocity = resolvedDirection * self.config.Actions.DashSpeed
			+ Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
		return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
	end

	if action == "Shield" then
		if payload.active ~= true or state.owner ~= player or state.mode ~= "Controlled" then
			return self:_feedback(state, false, false, "NotController", action, sequence, 0)
		end
		local contact = self:_hasStrictContact(
			player,
			state,
			self.config.Actions.Shield.Radius,
			self.config.Security.Command.MaximumContactHeight
		)
		if not contact then
			return self:_feedback(state, false, false, "NoContact", action, sequence, 0)
		end
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.ShieldToggleCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		self.shields[player] = {
			direction = resolvedDirection,
			startedAt = now,
			expiresAt = now + self.config.Actions.Shield.MaximumSeconds,
		}
		return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
	end

	if action == "Kick" or action == "Pass" then
		local charge = self.charges[player]
		self.charges[player] = nil
		if
			not charge
			or charge.action ~= action
			or charge.matchId ~= state.match.Id
			or charge.arenaId ~= state.arena.Id
		then
			return self:_feedback(state, false, false, "MissingCharge", action, sequence, 0)
		end
		local revisionAdvance = state.revision - charge.revision
		local maximumRevisionAdvance = if charge.buffered
			then self.config.Ball.FirstTouch.MaximumRevisionAdvance
			else 0
		if revisionAdvance < 0 or revisionAdvance > maximumRevisionAdvance then
			return self:_feedback(state, false, false, "ChargeStateChanged", action, sequence, 0)
		end
		if not self:_aimAccepted(root, resolvedDirection) then
			return self:_feedback(state, false, false, "AimRejected", action, sequence, 0)
		end
		local shotType: string? = nil
		local spin = 0
		if action == "Kick" then
			if
				type(payload.shotType) ~= "string"
				or self.config.Ball.Shot.Types[payload.shotType] == nil
			then
				return self:_feedback(state, false, false, "InvalidShotType", action, sequence, 0)
			end
			shotType = payload.shotType
			if payload.spin ~= nil then
				if
					type(payload.spin) ~= "number"
					or not finiteNumber(payload.spin)
					or math.abs(payload.spin) > 1.05
				then
					return self:_feedback(state, false, false, "InvalidSpin", action, sequence, 0)
				end
				spin = math.clamp(payload.spin, -1, 1)
			end
		end
		local power = self:_chargedPower(action, now - charge.startedAt)
		local cooldownDuration = if action == "Kick"
			then self.config.Actions.KickCooldown
			else self.config.Actions.PassCooldown
		local contact = self:_hasStrictContact(player, state)
		local controls = state.owner == player and state.mode == "Controlled"
		if not controls or not contact then
			if not self:_canBuffer(player, state, now) then
				return self:_feedback(
					state,
					false,
					false,
					if contact then "NotController" else "NoContact",
					action,
					sequence,
					0
				)
			end
			local ready, cooldown = self:_consumeCooldown(player, action, cooldownDuration, now)
			if not ready then
				return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
			end
			self:_bufferIntent(state, player, action, resolvedDirection, shotType, power, spin, now)
			return self:_feedback(state, true, false, "Buffered", action, sequence, cooldown)
		end
		local ready, cooldown = self:_consumeCooldown(player, action, cooldownDuration, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		local executed = if action == "Kick"
			then self:_executeKick(
				state,
				player,
				resolvedDirection,
				power,
				shotType :: string,
				spin
			)
			else self:_executePass(state, player, resolvedDirection, power)
		return self:_feedback(
			state,
			executed,
			executed,
			if executed then "Executed" else "Rejected",
			action,
			sequence,
			cooldown
		)
	end

	if action == "Trap" then
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.TrapCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		if state.owner == player and state.mode == "Controlled" then
			local contact = self:_hasStrictContact(player, state)
			if not contact then
				return self:_feedback(state, false, false, "NoContact", action, sequence, 0)
			end
			self:_executeTrap(state, player, resolvedDirection)
			return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
		end
		if not self:_canBuffer(player, state, now) then
			return self:_feedback(state, false, false, "CannotBuffer", action, sequence, 0)
		end
		self:_bufferIntent(state, player, action, resolvedDirection, nil, 0, 0, now)
		return self:_feedback(state, true, false, "Buffered", action, sequence, cooldown)
	end

	if action == "Tackle" then
		local other = opponent(state.match, player)
		local otherRoot = if other then getRoot(other) else nil
		if not other or not otherRoot or state.owner ~= other or state.mode ~= "Controlled" then
			return self:_feedback(state, false, false, "NoTarget", action, sequence, 0)
		end
		local tackle = self.config.Actions.Tackle
		local feint = self.feints[other]
		local vulnerable = feint ~= nil
			and now >= feint.vulnerableAt
			and now <= feint.vulnerableUntil
		local radius = tackle.PlayerRadius
			+ (if vulnerable then tackle.FeintVulnerabilityRadiusBonus else 0)
		local offset = otherRoot.Position - root.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		local ballOffset = state.arena.Ball.Position - root.Position
		local ballHorizontal = Vector3.new(ballOffset.X, 0, ballOffset.Z)
		if
			horizontal.Magnitude < 0.05
			or horizontal.Magnitude > radius
			or ballHorizontal.Magnitude > tackle.BallRadius
			or math.abs(ballOffset.Y) > tackle.MaximumHeight
		then
			return self:_feedback(state, false, false, "NoContact", action, sequence, 0)
		end
		local towardDefender = horizontal.Unit
		local attackerFacing = safeHorizontalDirection(root.CFrame.LookVector, towardDefender)
		local defenderFacing = safeHorizontalDirection(otherRoot.CFrame.LookVector, -towardDefender)
		local requiredAttackDot = tackle.AttackerForwardDot
			- (if vulnerable then tackle.FeintVulnerabilityDotBonus else 0)
		if
			not attackerFacing
			or attackerFacing:Dot(towardDefender) < requiredAttackDot
			or resolvedDirection:Dot(towardDefender) < requiredAttackDot
			or not defenderFacing
			or defenderFacing:Dot(-towardDefender) < tackle.DefenderFrontDot
		then
			return self:_feedback(state, false, false, "BehindDefender", action, sequence, 0)
		end
		local shield = self:_activeShield(state, other, now)
		if
			shield
			and BallMath.DirectionDot(-towardDefender, shield.direction)
				>= self.config.Actions.Shield.TackleFrontDot
		then
			return self:_feedback(state, false, false, "Shielded", action, sequence, 0)
		end
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.TackleCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		local contactDirection = safeHorizontalDirection(ballHorizontal, resolvedDirection)
			or resolvedDirection
		local launchDirection = (contactDirection * 0.65 + resolvedDirection * 0.35).Unit
		self:_launch(
			state,
			player,
			"Tackle",
			launchDirection * tackle.ImpulseSpeed + Vector3.new(0, tackle.Lift, 0),
			Vector3.new(0, 1, 0):Cross(launchDirection) * tackle.AngularImpulseScale,
			other,
			tackle.ReleaseSeconds,
			tackle.ReleaseSeconds
		)
		return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
	end

	if action == "Feint" then
		if state.owner ~= player or state.mode ~= "Controlled" then
			return self:_feedback(state, false, false, "NotController", action, sequence, 0)
		end
		local contact = self:_hasStrictContact(player, state)
		local variant = payload.variant
		local variantConfig = if type(variant) == "string"
			then self.config.Actions.Feint.Variants[variant]
			else nil
		local lateral = payload.lateral
		if
			not contact
			or type(variantConfig) ~= "table"
			or type(lateral) ~= "number"
			or not finiteNumber(lateral)
			or math.abs(lateral) > self.config.Actions.Feint.LateralMaximum + 0.05
		then
			return self:_feedback(state, false, false, "InvalidFeint", action, sequence, 0)
		end
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.FeintCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		self.shields[player] = nil
		self.feints[player] = {
			variant = variant :: string,
			direction = resolvedDirection,
			lateral = math.clamp(lateral, -1, 1),
			startedAt = now,
			endsAt = now + variantConfig.Duration,
			vulnerableAt = now + self.config.Actions.Feint.VulnerabilityStart,
			vulnerableUntil = now + self.config.Actions.Feint.VulnerabilityEnd,
		}
		self:_markAction(state, "Feint", player)
		state.arena.Ball:SetAttribute("LastFeintVariant", variant)
		return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
	end

	if action == "Skill" then
		if state.owner ~= player or state.mode ~= "Controlled" then
			return self:_feedback(state, false, false, "NotController", action, sequence, 0)
		end
		local contact = self:_hasStrictContact(player, state)
		local other = opponent(state.match, player)
		local otherRoot = if other then getRoot(other) else nil
		if not contact or not other or not otherRoot then
			return self:_feedback(state, false, false, "NoTarget", action, sequence, 0)
		end
		local panna = self.config.Actions.Panna
		local offset = otherRoot.Position - root.Position
		local horizontal = Vector3.new(offset.X, 0, offset.Z)
		if horizontal.Magnitude < panna.MinimumDistance or horizontal.Magnitude > panna.Radius then
			return self:_feedback(state, false, false, "NoTarget", action, sequence, 0)
		end
		local throughDirection = horizontal.Unit
		local rootFacing = safeHorizontalDirection(root.CFrame.LookVector, throughDirection)
		local closest = BallMath.ClosestPointOnRay(
			state.arena.Ball.Position,
			resolvedDirection,
			otherRoot.Position
		)
		local corridorOffset = Vector3.new(
			closest.X - otherRoot.Position.X,
			0,
			closest.Z - otherRoot.Position.Z
		).Magnitude
		if
			resolvedDirection:Dot(throughDirection) < panna.AimDot
			or not rootFacing
			or rootFacing:Dot(throughDirection) < panna.AttackerFacingDot
			or corridorOffset > panna.CorridorRadius
		then
			return self:_feedback(state, false, false, "AimRejected", action, sequence, 0)
		end
		local ready, cooldown =
			self:_consumeCooldown(player, action, self.config.Actions.SkillCooldown, now)
		if not ready then
			return self:_feedback(state, false, false, "Cooldown", action, sequence, cooldown)
		end
		if not self.pannaDetector:Begin(player, other, state.arena.Ball) then
			return self:_feedback(state, false, false, "PannaUnavailable", action, sequence, 0)
		end
		self:_launch(
			state,
			player,
			"Skill",
			resolvedDirection * panna.Speed + Vector3.new(0, panna.Lift, 0),
			Vector3.new(0, 1, 0):Cross(resolvedDirection) * panna.AngularImpulseScale,
			player,
			panna.ShooterRecaptureSeconds,
			panna.ReleaseSeconds
		)
		return self:_feedback(state, true, true, "Executed", action, sequence, cooldown)
	end

	return self:_feedback(state, false, false, "UnknownAction", action, sequence, 0)
end

function BallService._updateGround(self: Service, state: BallState)
	local ball = state.arena.Ball
	local dribble = self.config.Ball.Dribble
	local result = Workspace:Raycast(
		ball.Position,
		Vector3.new(0, -(self.config.Ball.Radius + dribble.GroundProbeDistance), 0),
		groundRaycastParams(state)
	)
	state.previousGrounded = state.grounded
	state.grounded = false
	state.groundPoint = nil
	state.groundNormal = Vector3.yAxis
	if result and result.Normal.Y >= dribble.GroundNormalMinimumY then
		state.groundPoint = result.Position
		state.groundNormal = result.Normal
		state.grounded = ball.Position.Y - result.Position.Y
			<= self.config.Ball.Radius + dribble.HeightOffset + 0.28
	end
end

function BallService._candidateScore(
	self: Service,
	state: BallState,
	player: Player,
	now: number
): number?
	if state.recapturePlayer == player and now < state.recaptureUntil then
		return nil
	end
	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return nil
	end
	local ball = state.arena.Ball
	local capture = self.config.Ball.Capture
	local firstTouch = self.config.Ball.FirstTouch
	local hasBuffer = state.buffered[player] ~= nil
	local radius = if hasBuffer
		then firstTouch.Radius
		else if state.owner == player and state.mode == "Controlled"
			then capture.OwnerBreakRadius
			else capture.Radius
	local maximumHeight = if hasBuffer then firstTouch.MaximumHeight else capture.MaximumHeight
	local offset = ball.Position - root.Position
	local horizontal = Vector3.new(offset.X, 0, offset.Z)
	if horizontal.Magnitude > radius or math.abs(offset.Y) > maximumHeight then
		return nil
	end
	local localBall = root.CFrame:PointToObjectSpace(ball.Position)
	local forward = -localBall.Z
	if
		forward < -capture.RearAllowance
		or forward > capture.FrontDistance
		or math.abs(localBall.X) > capture.LateralDistance
	then
		return nil
	end
	local ballSpeed = ball.AssemblyLinearVelocity.Magnitude
	local maximumSpeed = if hasBuffer then firstTouch.HardSpeed else capture.MaximumBallSpeed
	if ballSpeed > maximumSpeed then
		return nil
	end

	local distanceScore = 1 - math.clamp(horizontal.Magnitude / math.max(0.1, radius), 0, 1)
	local frontScore = math.clamp(
		(forward + capture.RearAllowance)
			/ math.max(0.1, capture.FrontDistance + capture.RearAllowance),
		0,
		1
	)
	local approachScore = 0
	if horizontal.Magnitude > 0.05 then
		local rootVelocity =
			Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
		approachScore = math.clamp(
			rootVelocity:Dot(horizontal.Unit) / math.max(0.1, capture.ApproachSpeed),
			0,
			1
		)
	end
	local score = distanceScore * capture.DistanceWeight
		+ frontScore * capture.FrontWeight
		+ approachScore * capture.ApproachWeight
	if state.owner == player and now <= state.controlGraceUntil then
		score += capture.OwnerRetentionBonus
	end
	if hasBuffer then
		score += firstTouch.BufferedScoreBonus
	end
	return score
end

function BallService._applyFirstTouch(self: Service, state: BallState, player: Player, now: number)
	local root = getRoot(player)
	if not root then
		return
	end
	local ball = state.arena.Ball
	self:_setBallMode(state, "Controlled", player, "FirstTouch")
	state.controlGraceUntil = now + self.config.Ball.Capture.ControlGraceSeconds
	state.lastTouch = player
	ball:SetAttribute("LastTouchUserId", player.UserId)
	ball:SetAttribute("LastActionUserId", player.UserId)
	self:_executeBuffered(state, player, now)
end

function BallService._updatePossession(self: Service, state: BallState, now: number)
	if not state.match or not state.active or state.mode == "Reset" or state.mode == "Shot" then
		return
	end
	for player, buffered in state.buffered do
		if buffered.expiresAt < now or not isParticipant(state.match, player) then
			state.buffered[player] = nil
		end
	end

	local first = state.match.Home
	local second = state.match.Away
	local firstScore = self:_candidateScore(state, first, now)
	local secondScore = self:_candidateScore(state, second, now)
	if firstScore == nil and secondScore == nil then
		if state.owner and now <= state.controlGraceUntil then
			return
		end
		if (state.mode == "Flight" or state.mode == "Bounce") and now < state.modeUntil then
			return
		end
		local nextMode: BallMode = if state.grounded
			then "Free"
			else if state.mode == "Bounce" then "Bounce" else "Flight"
		self:_setBallMode(state, nextMode, nil, nil)
		return
	end

	local selected: Player? = nil
	if firstScore ~= nil and secondScore == nil then
		selected = first
	elseif secondScore ~= nil and firstScore == nil then
		selected = second
	elseif firstScore ~= nil and secondScore ~= nil then
		local difference = firstScore - secondScore
		if math.abs(difference) <= self.config.Ball.Capture.ContestedScoreMargin then
			if state.mode ~= "Contested" then
				self:_setBallMode(state, "Contested", nil, "Contested")
				state.modeUntil = now + self.config.Ball.Capture.ContestedSeconds
				state.contestedFirst = first
				state.contestedSecond = second
				state.controlForce.Force = Vector3.zero
				return
			elseif now < state.modeUntil then
				state.controlForce.Force = Vector3.zero
				return
			end
			if difference > 0 then
				selected = first
			elseif difference < 0 then
				selected = second
			else
				local tieBreaker = (
					math.abs(first.UserId)
					+ math.abs(second.UserId)
					+ state.revision
				) % 2
				selected = if tieBreaker == 0 then first else second
			end
		else
			selected = if difference > 0 then first else second
		end
	end

	if selected then
		if state.owner ~= selected or state.mode ~= "Controlled" then
			self:_applyFirstTouch(state, selected, now)
		else
			self:_setBallMode(state, "Controlled", selected, nil)
		end
	end
end

function BallService._feintTarget(
	self: Service,
	owner: Player,
	baseDirection: Vector3,
	now: number
): (Vector3, number, number, number)
	local feint = self.feints[owner]
	if not feint then
		return baseDirection, 0, 1, 1
	end
	local settings = self.config.Actions.Feint.Variants[feint.variant]
	if type(settings) ~= "table" then
		self.feints[owner] = nil
		return baseDirection, 0, 1, 1
	end
	local progress =
		math.clamp((now - feint.startedAt) / math.max(0.05, feint.endsAt - feint.startedAt), 0, 1)
	local lateralSign = if math.abs(feint.lateral) > 0.05 then feint.lateral else 1
	local direction = feint.direction
	local lateral = 0
	if feint.variant == "StepOver" then
		direction = baseDirection
		lateral = math.sin(progress * math.pi) * settings.LateralDistance * lateralSign
	elseif feint.variant == "Cut" then
		lateral = settings.LateralDistance * lateralSign * math.sin(progress * math.pi * 0.5)
	elseif feint.variant == "DragBack" then
		direction = -baseDirection
		lateral = settings.LateralDistance * lateralSign * math.sin(progress * math.pi)
	elseif feint.variant == "Roulette" then
		local rotation = CFrame.fromAxisAngle(Vector3.yAxis, math.pi * progress * lateralSign)
		direction = rotation:VectorToWorldSpace(baseDirection)
		lateral = settings.LateralDistance * lateralSign * math.sin(progress * math.pi)
	end
	return direction, lateral, settings.DistanceMultiplier, settings.FollowResponsivenessMultiplier
end

function BallService._loseKinematicControl(
	self: Service,
	state: BallState,
	owner: Player,
	now: number,
	reason: string?
)
	state.recapturePlayer = owner
	state.recaptureUntil = now + self.config.Ball.Capture.ControlLossRecaptureSeconds
	self:_setBallMode(state, "Free", nil, reason)
end

function BallService._dribble(self: Service, state: BallState, deltaTime: number, now: number)
	local owner = state.owner
	state.controlForce.Force = Vector3.zero
	state.controlForce.Enabled = false
	if not owner or state.mode ~= "Controlled" then
		return
	end
	local root = getRoot(owner)
	local humanoid = getHumanoid(owner)
	if not root or not humanoid or humanoid.Health <= 0 then
		self:_loseKinematicControl(state, owner, now, "ControllerUnavailable")
		return
	end

	local dribble = self.config.Ball.Dribble
	local shield = self:_activeShield(state, owner, now)
	local facing = safeHorizontalDirection(root.CFrame.LookVector, root.CFrame.LookVector)
	if not facing then
		self:_loseKinematicControl(state, owner, now, "ControlDirectionLost")
		return
	end
	local feintDirection, lateralOffset, feintDistanceMultiplier, feintFollowMultiplier =
		self:_feintTarget(owner, facing, now)
	local rootHorizontalVelocity =
		Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z)
	local sprintMultiplier = if rootHorizontalVelocity.Magnitude >= dribble.SprintSpeed
		then dribble.SprintDistanceMultiplier
		else 1
	local distanceMultiplier = sprintMultiplier
		* (if shield then dribble.ShieldDistanceMultiplier else 1)
		* feintDistanceMultiplier
	local flatTarget = BallMath.KinematicControlTarget(
		root.CFrame,
		Vector3.zero,
		feintDirection,
		dribble.Distance * distanceMultiplier,
		lateralOffset,
		self.config.Ball.Radius,
		0
	)
	if not flatTarget then
		self:_loseKinematicControl(state, owner, now, "ControlTargetLost")
		return
	end
	local probeOrigin =
		Vector3.new(flatTarget.X, root.Position.Y + dribble.GroundProbeHeight, flatTarget.Z)
	local ground = Workspace:Raycast(
		probeOrigin,
		Vector3.new(0, -(dribble.GroundProbeHeight + dribble.GroundProbeDistance), 0),
		groundRaycastParams(state)
	)
	if not ground or ground.Normal.Y < dribble.GroundNormalMinimumY then
		self:_loseKinematicControl(state, owner, now, "ControlGroundLost")
		return
	end
	local target = BallMath.KinematicControlTarget(
		root.CFrame,
		ground.Position,
		feintDirection,
		dribble.Distance * distanceMultiplier,
		lateralOffset,
		self.config.Ball.Radius,
		dribble.HeightOffset
	)
	if not target then
		self:_loseKinematicControl(state, owner, now, "ControlTargetLost")
		return
	end
	local ball = state.arena.Ball
	if not ball.Anchored then
		self:_beginKinematicControl(state)
	end
	local current = state.controlPosition or ball.Position
	local horizontalDelta = Vector3.new(target.X - current.X, 0, target.Z - current.Z)
	local nextPosition: Vector3
	if state.controlSnapPending or horizontalDelta.Magnitude >= dribble.MaximumFollowDistance then
		nextPosition = target
	else
		local responsiveness = dribble.FollowResponsiveness
			* feintFollowMultiplier
			* (if shield then dribble.ShieldFollowResponsivenessMultiplier else 1)
		local alpha = 1 - math.exp(-math.max(0, responsiveness) * math.clamp(deltaTime, 0, 0.1))
		nextPosition = Vector3.new(
			current.X + horizontalDelta.X * alpha,
			target.Y,
			current.Z + horizontalDelta.Z * alpha
		)
	end
	local controlTravel = nextPosition - current
	if controlTravel.Magnitude >= 1e-4 then
		local obstacle = Workspace:Spherecast(
			current,
			self.config.Ball.Radius * dribble.ObstacleRadiusScale,
			controlTravel,
			groundRaycastParams(state)
		)
		if obstacle then
			local allowedDistance = math.max(0, obstacle.Distance - dribble.ObstacleClearance)
			nextPosition = current
				+ controlTravel.Unit * math.min(controlTravel.Magnitude, allowedDistance)
		end
	end
	state.controlSnapPending = false
	local currentCFrame = CFrame.new(current) * (state.controlRotation or ball.CFrame.Rotation)
	local nextCFrame = BallMath.KinematicRollCFrame(
		currentCFrame,
		nextPosition,
		self.config.Ball.Radius,
		dribble.RotationMultiplier,
		dribble.MaximumRotationRadiansPerStep
	)
	state.controlPosition = nextPosition
	state.controlRotation = nextCFrame.Rotation
	ball.CFrame = nextCFrame
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	state.grounded = true
	state.groundPoint = ground.Position
	state.groundNormal = ground.Normal
	ball:SetAttribute("LastTouchUserId", owner.UserId)
	state.lastTouch = owner
end

function BallService._stepMode(self: Service, state: BallState, now: number)
	if state.mode == "Reset" then
		if state.active and now >= state.modeUntil then
			self:_setBallMode(state, "Free", nil, nil)
		end
	elseif state.mode == "Shot" and now >= state.modeUntil then
		self:_setBallMode(state, "Flight", nil, nil)
		state.modeUntil = now + self.config.Ball.Limits.MinimumFlightSeconds
	elseif state.mode == "Flight" then
		if
			state.grounded
			and not state.previousGrounded
			and math.abs(state.arena.Ball.AssemblyLinearVelocity.Y)
				>= self.config.Ball.Limits.BounceVerticalSpeed
		then
			self:_setBallMode(state, "Bounce", nil, nil)
			state.modeUntil = now + self.config.Ball.Limits.BounceStateSeconds
		elseif state.grounded and now >= state.modeUntil then
			self:_setBallMode(state, "Free", nil, nil)
		end
	elseif state.mode == "Bounce" and now >= state.modeUntil then
		self:_setBallMode(state, if state.grounded then "Free" else "Flight", nil, nil)
	end
end

function BallService._enforceBallLimits(self: Service, state: BallState)
	local ball = state.arena.Ball
	local limits = self.config.Ball.Limits
	if
		not BallMath.IsFiniteVector3(ball.Position)
		or not BallMath.IsFiniteVector3(ball.AssemblyLinearVelocity)
		or not BallMath.IsFiniteVector3(ball.AssemblyAngularVelocity)
		or ball.Position.Magnitude > limits.FiniteMagnitude
	then
		if state.match then
			self:ResetMatchBall(state.match)
		end
		return
	end
	if ball:GetNetworkOwner() ~= nil then
		ball:SetNetworkOwner(nil)
	end
	local velocity = ball.AssemblyLinearVelocity
	local horizontal =
		BallMath.ClampMagnitude(Vector3.new(velocity.X, 0, velocity.Z), limits.MaximumSpeed)
	local limitedVelocity = horizontal
		+ Vector3.new(
			0,
			math.clamp(velocity.Y, -limits.MaximumVerticalSpeed, limits.MaximumVerticalSpeed),
			0
		)
	limitedVelocity = BallMath.ClampMagnitude(limitedVelocity, limits.MaximumSpeed)
	if (limitedVelocity - velocity).Magnitude > 0.01 then
		ball.AssemblyLinearVelocity = limitedVelocity
	end
	local angular =
		BallMath.ClampMagnitude(ball.AssemblyAngularVelocity, limits.MaximumAngularSpeed)
	if (angular - ball.AssemblyAngularVelocity).Magnitude > 0.01 then
		ball.AssemblyAngularVelocity = angular
	end
	local speed = limitedVelocity.Magnitude
	if not state.trail.Enabled and speed >= self.config.Ball.Trail.EnabledSpeed then
		state.trail.Enabled = true
	elseif state.trail.Enabled and speed <= self.config.Ball.Trail.DisabledSpeed then
		state.trail.Enabled = false
	end
	state.lastPosition = ball.Position
end

function BallService._enforceBounds(self: Service, state: BallState)
	if not state.match or not state.active then
		return
	end
	local now = os.clock()
	if now - state.lastBoundaryCheck < self.config.Ball.Limits.BoundaryCheckSeconds then
		return
	end
	state.lastBoundaryCheck = now

	local ball = state.arena.Ball
	if
		ball.Position.Y < self.config.Ball.ResetBelowY
		or not self.arenas:IsInside(state.arena, ball.Position, 12)
	then
		self:ResetMatchBall(state.match)
	end

	for _, player in { state.match.Home, state.match.Away } do
		local root = getRoot(player)
		if
			root
			and not self.arenas:IsInside(
				state.arena,
				root.Position,
				self.config.Security.MaxCharacterDistanceFromArena
			)
		then
			self:_teleportToParticipantSpawn(state, player, now)
		end
	end
end

function BallService._step(self: Service, deltaTime: number)
	local now = os.clock()
	self:_ejectIntruders(now)
	self:_stepDashes(now)
	self:_stepShields(now)
	self:_stepFeints(now)
	local ownersByBall: { [BasePart]: Player? } = {}
	local lastTouchesByBall: { [BasePart]: Player? } = {}
	for _, state in self.states do
		local ball = state.arena.Ball
		if state.match and state.active then
			for _, player in { state.match.Home, state.match.Away } do
				if not self:_validateMovement(state, player, now) and state.owner == player then
					self:_setOwner(state, nil)
				end
			end
			self:_updateGround(state)
			self:_stepMode(state, now)
			local previousController = if state.mode == "Controlled" then state.owner else nil
			if previousController then
				self:_dribble(state, deltaTime, now)
			end
			self:_updatePossession(state, now)
			if state.mode == "Controlled" and state.owner ~= previousController then
				self:_dribble(state, deltaTime, now)
			end
			self:_enforceBallLimits(state)
			self:_enforceBounds(state)
		else
			state.controlForce.Force = Vector3.zero
			state.trail.Enabled = false
		end
		ownersByBall[ball] = state.owner
		lastTouchesByBall[ball] = state.lastTouch
	end
	self.pannaDetector:Step(ownersByBall, lastTouchesByBall)
end

function BallService.RemovePlayer(self: Service, player: Player)
	self.lastActions[player.UserId] = nil
	self.lastSequences[player.UserId] = nil
	self.movementSamples[player] = nil
	self:_clearPlayerRuntime(player)
	local playerConnection = self.playerConnections[player]
	if playerConnection then
		playerConnection:Disconnect()
		self.playerConnections[player] = nil
	end
	local characterConnection = self.characterConnections[player]
	if characterConnection then
		characterConnection:Disconnect()
		self.characterConnections[player] = nil
	end
	self.pannaDetector:ClearPlayer(player)
	for _, state in self.states do
		if state.owner == player then
			self:_setBallMode(state, "Free", nil, "OwnerLeft")
		end
		state.buffered[player] = nil
	end
end

return BallService
