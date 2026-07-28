--!strict

local PhysicsService = game:GetService("PhysicsService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PannaDetector = require(script.Parent.PannaDetector)

local BallService = {}
BallService.__index = BallService

local SPECTATOR_COLLISION_GROUP = "PannaSpectator"
local MOVEMENT_SAMPLE_INTERVAL = 0.1
local MOVEMENT_WINDOW_SECONDS = 1
local MOVEMENT_SHORT_SLACK = 7
local MOVEMENT_WINDOW_SLACK = 9
local MOVEMENT_VERTICAL_SLACK = 8
local MOVEMENT_VIOLATION_WINDOW = 4
local MOVEMENT_VIOLATIONS_BEFORE_RESPAWN = 3
local INTRUDER_SCAN_INTERVAL = 0.12

type BallState = {
	arena: any,
	match: any?,
	active: boolean,
	owner: Player?,
	lastTouch: Player?,
	freeUntil: number,
	lastBoundaryCheck: number,
	ballCollisionGroup: string,
	participantCollisionGroup: string,
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

export type Service = typeof(setmetatable(
	{} :: {
		config: any,
		arenas: any,
		states: { [string]: BallState },
		lastActions: { [number]: { [string]: number } },
		movementSamples: { [Player]: MovementSample },
		dashes: { [Player]: DashState },
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
	return value == value and value > -1e5 and value < 1e5
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

function BallService.new(config: any, arenas: any): Service
	local self = setmetatable({
		config = config,
		arenas = arenas,
		states = {},
		lastActions = {},
		movementSamples = {},
		dashes = {},
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
		self.states[arena.Id] = {
			arena = arena,
			match = nil,
			active = false,
			owner = nil,
			lastTouch = nil,
			freeUntil = 0,
			lastBoundaryCheck = 0,
			ballCollisionGroup = ballCollisionGroup,
			participantCollisionGroup = participantCollisionGroup,
		}
		arena.Ball:SetNetworkOwner(nil)
		arena.Ball:SetAttribute("OwnerUserId", 0)
		arena.Ball:SetAttribute("LastTouchUserId", 0)
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
					otherState.participantCollisionGroup,
					state == otherState
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
	local violations = if now - sample.lastViolationAt <= MOVEMENT_VIOLATION_WINDOW
		then sample.violations + 1
		else 1
	local totalAttribute = player:GetAttribute("MovementViolationCount")
	local total = if type(totalAttribute) == "number" then totalAttribute else 0
	player:SetAttribute("MovementViolationCount", total + 1)

	if violations >= MOVEMENT_VIOLATIONS_BEFORE_RESPAWN then
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

	local walkEnvelope = math.max(20, math.min(humanoid.WalkSpeed + 4, 26))
	local dash = self.dashes[player]
	local shortSpeed = if dash and now <= dash.graceUntil
		then self.config.Actions.DashSpeed + 8
		else walkEnvelope
	local shortAllowance = MOVEMENT_SHORT_SLACK + shortSpeed * math.min(elapsed, 1.5)
	local dashWindowAllowance = if sample.dashUsedInWindow
		then math.max(0, self.config.Actions.DashSpeed - walkEnvelope)
				* self.config.Actions.DashSeconds
			+ 3
		else 0
	local windowAllowance = MOVEMENT_WINDOW_SLACK
		+ walkEnvelope * math.min(windowElapsed, 1.5)
		+ dashWindowAllowance
	local shortVerticalAllowance = MOVEMENT_VERTICAL_SLACK + 70 * math.min(elapsed, 0.4)
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

	if now - sample.lastViolationAt > MOVEMENT_VIOLATION_WINDOW then
		sample.violations = 0
	end
	if elapsed >= MOVEMENT_SAMPLE_INTERVAL then
		sample.trustedCFrame = root.CFrame
		sample.trustedAt = now
	end
	if windowElapsed >= MOVEMENT_WINDOW_SECONDS then
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
	self.nextIntruderScan = now + INTRUDER_SCAN_INTERVAL

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
					self.arenas:ReturnToLobby(player)
					self:_setCharacterCollisionGroup(player)
				end
			end
		end
	end
end

function BallService.SetPannaCallback(self: Service, callback: (Player, Player) -> ())
	self.onPanna = callback
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
	state.freeUntil = 0
	for _, player in { match.Home, match.Away } do
		self.movementSamples[player] = nil
		self.dashes[player] = nil
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
	state.owner = nil
	state.lastTouch = nil
	state.arena.Ball:SetAttribute("MatchId", "")
	state.arena.Ball:SetAttribute("OwnerUserId", 0)
	state.arena.Ball:SetAttribute("LastTouchUserId", 0)
	self.pannaDetector:ClearBall(state.arena.Ball)
	self.pannaDetector:ClearPlayer(match.Home)
	self.pannaDetector:ClearPlayer(match.Away)
	for _, player in { match.Home, match.Away } do
		self.movementSamples[player] = nil
		self.dashes[player] = nil
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
				self.dashes[player] = nil
				self:_teleportToParticipantSpawn(state, player, now)
			end
		else
			self:_setOwner(state, nil)
			self.pannaDetector:ClearBall(state.arena.Ball)
			for _, player in { match.Home, match.Away } do
				self.movementSamples[player] = nil
				self.dashes[player] = nil
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
	self:_setOwner(state, nil)
	state.lastTouch = nil
	state.freeUntil = os.clock() + 0.35
	state.arena.Ball:SetAttribute("LastTouchUserId", 0)
	self.arenas:ResetBall(state.arena)
end

function BallService._setOwner(_self: Service, state: BallState, player: Player?)
	if state.owner == player then
		return
	end
	state.owner = player
	state.arena.Ball:SetAttribute("OwnerUserId", if player then player.UserId else 0)
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

function BallService._cooldown(
	self: Service,
	player: Player,
	action: string,
	duration: number
): boolean
	local byAction = self.lastActions[player.UserId]
	if not byAction then
		byAction = {}
		self.lastActions[player.UserId] = byAction
	end
	local now = os.clock()
	if now - (byAction[action] or -1e6) < duration then
		return false
	end
	byAction[action] = now
	return true
end

function BallService._canTouchBall(
	self: Service,
	player: Player,
	state: BallState
): (boolean, BasePart?)
	local root = getRoot(player)
	if not root then
		return false, nil
	end
	local distance = (root.Position - state.arena.Ball.Position).Magnitude
	return distance <= self.config.Ball.InteractionRadius, root
end

function BallService._releaseBall(
	self: Service,
	state: BallState,
	player: Player,
	velocity: Vector3
)
	local ball = state.arena.Ball
	state.lastTouch = player
	state.freeUntil = os.clock() + self.config.Ball.FreeFlightSeconds
	self:_setOwner(state, nil)
	ball:SetNetworkOwner(nil)
	ball:SetAttribute("LastTouchUserId", player.UserId)
	ball.AssemblyLinearVelocity = velocity
	ball.AssemblyAngularVelocity = Vector3.new(0, 8, 0)
end

function BallService.HandleAction(self: Service, player: Player, payload: any): boolean
	if type(payload) ~= "table" or type(payload.action) ~= "string" then
		return false
	end
	local action = payload.action
	local state = self:_stateForPlayer(player)
	if not state or not state.match or not state.active or state.match.Ended then
		return false
	end
	if player:GetAttribute("ControlsLocked") == true then
		return false
	end

	local root = getRoot(player)
	local humanoid = getHumanoid(player)
	if not root or not humanoid or humanoid.Health <= 0 then
		return false
	end
	local now = os.clock()
	if not self:_validateMovement(state, player, now) then
		return false
	end
	local direction = safeHorizontalDirection(payload.direction, root.CFrame.LookVector)
	if not direction then
		return false
	end
	if typeof(payload.direction) ~= "Vector3" then
		return false
	end
	local submittedMagnitude = Vector3.new(payload.direction.X, 0, payload.direction.Z).Magnitude
	if math.abs(submittedMagnitude - 1) > self.config.Security.MaxDirectionMagnitudeError then
		return false
	end

	if action == "Dash" then
		if not self:_cooldown(player, action, self.config.Actions.DashCooldown) then
			return false
		end
		local dashSeconds = math.max(0, self.config.Actions.DashSeconds)
		self.dashes[player] = {
			direction = direction,
			startedAt = now,
			endsAt = now + dashSeconds,
			graceUntil = now + dashSeconds + 0.35,
			speedCapped = false,
		}
		local movementSample = self.movementSamples[player]
		if movementSample then
			movementSample.dashUsedInWindow = true
		end
		local currentY = root.AssemblyLinearVelocity.Y
		root.AssemblyLinearVelocity = direction * self.config.Actions.DashSpeed
			+ Vector3.new(0, currentY, 0)
		return true
	end

	local canTouch = self:_canTouchBall(player, state)
	if not canTouch then
		return false
	end
	-- A released ball has a short server-owned flight epoch. No second action type
	-- may overwrite its velocity until that epoch ends.
	if os.clock() < state.freeUntil then
		return false
	end
	local ownsOrControls = state.owner == player
		or (
			state.owner == nil
			and (state.arena.Ball.Position - root.Position).Magnitude
				<= self.config.Ball.ControlRadius
		)

	if action == "Kick" then
		if
			not ownsOrControls
			or not self:_cooldown(player, action, self.config.Actions.KickCooldown)
		then
			return false
		end
		local rawPower = if type(payload.power) == "number" and finiteNumber(payload.power)
			then payload.power
			else 0.5
		local power = math.clamp(rawPower, 0, 1)
		local speed = self.config.Ball.KickSpeedMin
			+ (self.config.Ball.KickSpeedMax - self.config.Ball.KickSpeedMin) * power
		local lift = self.config.Ball.LiftMin
			+ (self.config.Ball.LiftMax - self.config.Ball.LiftMin) * power
		self:_releaseBall(state, player, direction * speed + Vector3.new(0, lift, 0))
		return true
	elseif action == "Pass" then
		if
			not ownsOrControls
			or not self:_cooldown(player, action, self.config.Actions.PassCooldown)
		then
			return false
		end
		self:_releaseBall(
			state,
			player,
			direction * self.config.Ball.PassSpeed + Vector3.new(0, 3, 0)
		)
		return true
	elseif action == "Tackle" then
		if not self:_cooldown(player, action, self.config.Actions.TackleCooldown) then
			return false
		end
		local other = opponent(state.match, player)
		local otherRoot = if other then getRoot(other) else nil
		if
			not other
			or not otherRoot
			or (otherRoot.Position - root.Position).Magnitude > self.config.Actions.TackleRadius
		then
			return false
		end
		if
			state.owner ~= other
			and (state.arena.Ball.Position - otherRoot.Position).Magnitude
				> self.config.Ball.ControlRadius
		then
			return false
		end
		self:_releaseBall(state, player, direction * 25 + Vector3.new(0, 2.5, 0))
		state.freeUntil = os.clock() + 0.18
		return true
	elseif action == "Skill" then
		if
			not ownsOrControls
			or not self:_cooldown(player, action, self.config.Actions.SkillCooldown)
		then
			return false
		end
		local other = opponent(state.match, player)
		local otherRoot = if other then getRoot(other) else nil
		if not other or not otherRoot then
			return false
		end
		local offset = otherRoot.Position - root.Position
		local horizontalOffset = Vector3.new(offset.X, 0, offset.Z)
		if
			horizontalOffset.Magnitude > self.config.Actions.SkillRadius
			or horizontalOffset.Magnitude < 1
		then
			return false
		end
		local throughDirection = horizontalOffset.Unit
		if direction:Dot(throughDirection) < -0.2 then
			return false
		end
		if not self.pannaDetector:Begin(player, other, state.arena.Ball) then
			return false
		end
		self:_releaseBall(state, player, throughDirection * 33 + Vector3.new(0, 1.4, 0))
		state.freeUntil = os.clock() + 0.3
		return true
	end

	return false
end

function BallService._chooseOwner(self: Service, state: BallState): Player?
	if not state.match or not state.active or os.clock() < state.freeUntil then
		return nil
	end
	local ball = state.arena.Ball
	if ball.AssemblyLinearVelocity.Magnitude > self.config.Ball.KickSpeedMin * 0.92 then
		return nil
	end

	if state.owner then
		local currentRoot = getRoot(state.owner)
		if
			currentRoot
			and (currentRoot.Position - ball.Position).Magnitude
				<= self.config.Ball.ControlRadius + 1.2
		then
			return state.owner
		end
	end

	local nearest: Player? = nil
	local nearestDistance = self.config.Ball.ControlRadius
	for _, player in { state.match.Home, state.match.Away } do
		local root = getRoot(player)
		local humanoid = getHumanoid(player)
		if root and humanoid and humanoid.Health > 0 then
			local distance = (root.Position - ball.Position).Magnitude
			if distance < nearestDistance then
				nearest = player
				nearestDistance = distance
			end
		end
	end
	return nearest
end

function BallService._dribble(self: Service, state: BallState, deltaTime: number)
	local owner = state.owner
	if not owner then
		return
	end
	local root = getRoot(owner)
	local humanoid = getHumanoid(owner)
	if not root or not humanoid then
		self:_setOwner(state, nil)
		return
	end

	local moveDirection = humanoid.MoveDirection
	local facing = if moveDirection.Magnitude > 0.15
		then moveDirection.Unit
		else root.CFrame.LookVector
	local horizontalFacing = Vector3.new(facing.X, 0, facing.Z)
	if horizontalFacing.Magnitude < 0.05 then
		return
	end
	horizontalFacing = horizontalFacing.Unit

	local ball = state.arena.Ball
	local target = root.Position + horizontalFacing * self.config.Ball.DribbleDistance
	local desiredY = math.max(state.arena.BallSpawn.Position.Y, root.Position.Y - 2.25)
	target = Vector3.new(target.X, desiredY, target.Z)
	local displacement = target - ball.Position
	local response = math.min(self.config.Ball.DribbleResponsiveness * deltaTime, 1)
	local desiredVelocity = displacement * self.config.Ball.DribbleResponsiveness
		+ Vector3.new(root.AssemblyLinearVelocity.X, 0, root.AssemblyLinearVelocity.Z) * 0.45
	if desiredVelocity.Magnitude > self.config.Ball.MaxSpeed * 0.55 then
		desiredVelocity = desiredVelocity.Unit * self.config.Ball.MaxSpeed * 0.55
	end
	local currentVelocity = ball.AssemblyLinearVelocity
	local proposedVelocity = currentVelocity:Lerp(desiredVelocity, response)
	local configuredAcceleration = self.config.Ball.DribbleAcceleration
	local fallbackAcceleration = self.config.Ball.MaxSpeed
		* math.clamp(self.config.Ball.DribbleResponsiveness * 0.28, 2, 5)
	local maxAcceleration = if type(configuredAcceleration) == "number"
			and finiteNumber(configuredAcceleration)
		then math.clamp(configuredAcceleration, 1, 2_000)
		else fallbackAcceleration
	local velocityChange = proposedVelocity - currentVelocity
	local maxVelocityChange = maxAcceleration * math.max(0, deltaTime)
	if velocityChange.Magnitude > maxVelocityChange and maxVelocityChange > 0 then
		proposedVelocity = currentVelocity + velocityChange.Unit * maxVelocityChange
	end
	ball.AssemblyLinearVelocity = proposedVelocity
	ball:SetAttribute("LastTouchUserId", owner.UserId)
	state.lastTouch = owner
end

function BallService._enforceBounds(self: Service, state: BallState)
	if not state.match or not state.active then
		return
	end
	local now = os.clock()
	if now - state.lastBoundaryCheck < 0.35 then
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
			self:_setOwner(state, self:_chooseOwner(state))
			self:_dribble(state, deltaTime)
			self:_enforceBounds(state)
			local speed = ball.AssemblyLinearVelocity.Magnitude
			if speed > self.config.Ball.MaxSpeed then
				ball.AssemblyLinearVelocity = ball.AssemblyLinearVelocity.Unit
					* self.config.Ball.MaxSpeed
			end
		end
		ownersByBall[ball] = state.owner
		lastTouchesByBall[ball] = state.lastTouch
	end
	self.pannaDetector:Step(ownersByBall, lastTouchesByBall)
end

function BallService.RemovePlayer(self: Service, player: Player)
	self.lastActions[player.UserId] = nil
	self.movementSamples[player] = nil
	self.dashes[player] = nil
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
			self:_setOwner(state, nil)
		end
	end
end

return BallService
