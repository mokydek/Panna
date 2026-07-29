--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local Workspace = game:GetService("Workspace")

local ProceduralPoseCatalog = require(script.Parent:WaitForChild("ProceduralPoseCatalog"))

type Pose = ProceduralPoseCatalog.Pose

type Cue = {
	action: string,
	mode: string,
	phase: string,
	startedAt: number,
	duration: number,
	power: number,
	lateral: number,
	revision: number,
}

type JointBinding = {
	instance: Instance,
	lastOffset: CFrame,
	lastWritten: CFrame?,
}

type ActorState = {
	userId: number,
	player: Player?,
	character: Model?,
	bindings: { [string]: JointBinding },
	hold: Cue?,
	action: Cue?,
}

type ControllerFields = {
	localPlayer: Player?,
	actors: { [number]: ActorState },
	lastVisualRevision: { [number]: number },
	preSimulationConnection: RBXScriptConnection?,
	destroyed: boolean,
}

local PlayerAnimationController = {}
PlayerAnimationController.__index = PlayerAnimationController

export type PlayerAnimationController = typeof(setmetatable(
	{} :: ControllerFields,
	PlayerAnimationController
))

local IDENTITY = CFrame.new()
local MAX_EFFECT_AGE = 5
local MAX_EFFECT_FUTURE = 0.75
local MAX_CUE_DURATION = 5
local MAX_HOLD_AGE = 6

local JOINT_ALIASES = table.freeze({
	root = "Root",
	rootjoint = "Root",
	waist = "Waist",
	neck = "Neck",
	leftshoulder = "LeftShoulder",
	rightshoulder = "RightShoulder",
	lefthip = "LeftHip",
	righthip = "RightHip",
	leftknee = "LeftKnee",
	rightknee = "RightKnee",
	leftankle = "LeftAnkle",
	rightankle = "RightAnkle",
})

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function readString(source: any, ...: string): string
	if typeof(source) ~= "table" then
		return ""
	end
	for _, key in { ... } do
		local value = source[key]
		if typeof(value) == "string" then
			return value
		end
	end
	return ""
end

local function readNumber(source: any, ...: string): number?
	if typeof(source) ~= "table" then
		return nil
	end
	for _, key in { ... } do
		local value = source[key]
		if finiteNumber(value) then
			return value
		end
	end
	return nil
end

local function normalizedToken(value: string): string
	return string.lower((string.gsub(value, "[%s_%-]", "")))
end

local function normalizeAction(action: string): string
	local token = normalizedToken(action)
	if token == "chargestart" or token == "charge" then
		return "Charge"
	elseif token == "kick" then
		return "Kick"
	elseif token == "pass" then
		return "Pass"
	elseif token == "trap" then
		return "Trap"
	elseif token == "shield" then
		return "Shield"
	elseif token == "dash" then
		return "Dash"
	elseif token == "tackle" then
		return "Tackle"
	elseif token == "skill" or token == "panna" then
		return "Skill"
	elseif token == "feint" then
		return "Feint"
	end
	return ""
end

local function normalizeMode(mode: string): string
	local token = normalizedToken(mode)
	if token == "low" then
		return "Low"
	elseif token == "normal" then
		return "Normal"
	elseif token == "chip" then
		return "Chip"
	elseif token == "kick" then
		return "Kick"
	elseif token == "pass" then
		return "Pass"
	elseif token == "stepover" then
		return "StepOver"
	elseif token == "cut" then
		return "Cut"
	elseif token == "dragback" then
		return "DragBack"
	elseif token == "roulette" then
		return "Roulette"
	end
	return mode
end

local function serverNow(): number
	local success, value = pcall(function(): number
		return Workspace:GetServerTimeNow()
	end)
	return if success and finiteNumber(value) then value else os.clock()
end

local function normalizeJoint(instance: Instance): string?
	local token = normalizedToken(instance.Name)
	return JOINT_ALIASES[token] or JOINT_ALIASES[string.gsub(token, "constraint$", "")]
end

local function readTransform(instance: Instance): (boolean, CFrame)
	if instance:IsA("Motor6D") then
		return true, instance.Transform
	elseif instance:IsA("AnimationConstraint") then
		local kinematicSuccess, isKinematic = pcall(function(): any
			return (instance :: any).IsKinematic
		end)
		if not kinematicSuccess or isKinematic ~= true then
			return false, IDENTITY
		end
		local success, value = pcall(function(): any
			return (instance :: any).Transform
		end)
		if success and typeof(value) == "CFrame" then
			return true, value
		end
	end
	return false, IDENTITY
end

local function writeTransform(instance: Instance, transform: CFrame): boolean
	if instance:IsA("Motor6D") then
		instance.Transform = transform
		return true
	elseif instance:IsA("AnimationConstraint") then
		return pcall(function()
			(instance :: any).Transform = transform
		end)
	end
	return false
end

local function cframeClose(first: CFrame, second: CFrame): boolean
	return (first.Position - second.Position).Magnitude <= 1e-4
		and first.LookVector:Dot(second.LookVector) >= 0.99999
		and first.UpVector:Dot(second.UpVector) >= 0.99999
end

local function restoreBinding(binding: JointBinding)
	local success, current = readTransform(binding.instance)
	if success and binding.lastWritten and cframeClose(current, binding.lastWritten :: CFrame) then
		writeTransform(binding.instance, binding.lastOffset:Inverse() * current)
	end
	binding.lastOffset = IDENTITY
	binding.lastWritten = nil
end

local function restoreActor(actor: ActorState)
	for _, binding in actor.bindings do
		restoreBinding(binding)
	end
end

local function bindingPriority(instance: Instance): number
	return if instance:IsA("AnimationConstraint") then 2 else 1
end

local function bindCharacter(actor: ActorState, character: Model?)
	restoreActor(actor)
	actor.character = character
	actor.bindings = {}
	if not character then
		return
	end

	for _, descendant in character:GetDescendants() do
		if descendant:IsA("Motor6D") or descendant:IsA("AnimationConstraint") then
			local normalized = normalizeJoint(descendant)
			if normalized then
				local existing = actor.bindings[normalized]
				if
					not existing
					or bindingPriority(descendant) > bindingPriority(existing.instance)
				then
					actor.bindings[normalized] = {
						instance = descendant,
						lastOffset = IDENTITY,
						lastWritten = nil,
					}
				end
			end
		end
	end
end

local function combinePose(target: Pose, source: Pose)
	for joint, transform in source do
		target[joint] = (target[joint] or IDENTITY) * transform
	end
end

local function newActor(userId: number, player: Player?): ActorState
	return {
		userId = userId,
		player = player,
		character = nil,
		bindings = {},
		hold = nil,
		action = nil,
	}
end

local function makeCue(
	action: string,
	mode: string,
	phase: string,
	startedAt: number,
	duration: number?,
	power: number?,
	lateral: number?,
	revision: number
): Cue
	local resolvedDuration = if finiteNumber(duration) and (duration :: number) > 0
		then math.clamp(duration :: number, 0.05, MAX_CUE_DURATION)
		else ProceduralPoseCatalog.GetDuration(action, mode)
	return {
		action = action,
		mode = mode,
		phase = phase,
		startedAt = startedAt,
		duration = resolvedDuration,
		power = if finiteNumber(power) then math.clamp(power :: number, 0, 1) else 0.65,
		lateral = if finiteNumber(lateral) then math.clamp(lateral :: number, -1, 1) else 1,
		revision = revision,
	}
end

function PlayerAnimationController.new(localPlayer: Player?): PlayerAnimationController
	local resolvedLocalPlayer = localPlayer
	if resolvedLocalPlayer == nil and RunService:IsClient() then
		resolvedLocalPlayer = Players.LocalPlayer
	end
	local self = setmetatable({
		localPlayer = resolvedLocalPlayer,
		actors = {},
		lastVisualRevision = {},
		preSimulationConnection = nil,
		destroyed = false,
	}, PlayerAnimationController) :: PlayerAnimationController

	if RunService:IsClient() and resolvedLocalPlayer ~= nil then
		self.preSimulationConnection = RunService.PreSimulation:Connect(function()
			self:_step()
		end)
	end
	return self
end

function PlayerAnimationController._actor(
	self: PlayerAnimationController,
	userId: number,
	player: Player?
): ActorState
	local actor = self.actors[userId]
	if not actor then
		actor = newActor(userId, player)
		self.actors[userId] = actor
	elseif player then
		actor.player = player
	end
	return actor
end

function PlayerAnimationController._sampleActor(
	_self: PlayerAnimationController,
	actor: ActorState,
	now: number
): Pose
	local pose: Pose = {}
	local hold = actor.hold
	if hold and now - hold.startedAt > MAX_HOLD_AGE then
		actor.hold = nil
		hold = nil
	end
	if hold then
		combinePose(
			pose,
			ProceduralPoseCatalog.Sample(
				hold.action,
				hold.mode,
				now - hold.startedAt,
				hold.duration,
				hold.power,
				hold.lateral
			)
		)
	end

	local action = actor.action
	if action then
		local elapsed = now - action.startedAt
		if elapsed > action.duration then
			actor.action = nil
		else
			combinePose(
				pose,
				ProceduralPoseCatalog.Sample(
					action.action,
					action.mode,
					elapsed,
					action.duration,
					action.power,
					action.lateral
				)
			)
		end
	end
	return pose
end

function PlayerAnimationController._applyPose(
	_self: PlayerAnimationController,
	actor: ActorState,
	pose: Pose
)
	for semantic, binding in actor.bindings do
		if binding.instance.Parent == nil then
			continue
		end
		local success, current = readTransform(binding.instance)
		if not success then
			continue
		end
		local base = current
		if binding.lastWritten and cframeClose(current, binding.lastWritten :: CFrame) then
			base = binding.lastOffset:Inverse() * current
		end
		local desiredOffset = pose[semantic] or IDENTITY
		local written = desiredOffset * base
		if writeTransform(binding.instance, written) then
			binding.lastOffset = desiredOffset
			binding.lastWritten = written
		end
	end
end

function PlayerAnimationController._step(self: PlayerAnimationController)
	if self.destroyed then
		return
	end
	local now = serverNow()
	local expired: { number } = {}
	for userId, actor in self.actors do
		local player = actor.player
		if not player or player.Parent == nil then
			player = Players:GetPlayerByUserId(userId)
			actor.player = player
		end
		local character = if player then player.Character else nil
		if character ~= actor.character or (character ~= nil and next(actor.bindings) == nil) then
			bindCharacter(actor, character)
		end

		local pose = self:_sampleActor(actor, now)
		if actor.hold or actor.action then
			self:_applyPose(actor, pose)
		else
			restoreActor(actor)
			table.insert(expired, userId)
		end
	end
	for _, userId in expired do
		self.actors[userId] = nil
	end
end

function PlayerAnimationController._scopeMatches(
	self: PlayerAnimationController,
	payload: any
): boolean
	local localPlayer = self.localPlayer
	if not localPlayer or localPlayer.Parent == nil then
		return false
	end
	local matchId = readString(payload, "matchId", "MatchId")
	local arenaId = readString(payload, "arenaId", "ArenaId")
	local revision = readNumber(payload, "matchRevision", "MatchRevision")
	if matchId == "" or arenaId == "" or not revision or revision < 1 then
		return false
	end
	local currentMatchId = localPlayer:GetAttribute("MatchId")
	local currentArenaId = localPlayer:GetAttribute("ArenaId")
	local currentRevision = localPlayer:GetAttribute("MatchRevision")
	if typeof(currentMatchId) ~= "string" or currentMatchId ~= matchId then
		return false
	end
	if
		typeof(currentArenaId) == "string"
		and currentArenaId ~= ""
		and currentArenaId ~= arenaId
	then
		return false
	end
	return typeof(currentRevision) ~= "number" or revision >= currentRevision
end

function PlayerAnimationController.ApplyEffect(
	self: PlayerAnimationController,
	payload: any
): boolean
	local kind = normalizedToken(readString(payload, "kind", "Kind", "type", "Type"))
	if kind ~= "playeraction" then
		return false
	end
	-- PlayerAction is intentionally consumed even when malformed/stale so the generic
	-- UI effect fallback never turns gameplay cues into notification cards.
	if self.destroyed or not self:_scopeMatches(payload) then
		return true
	end

	local actorValue = readNumber(payload, "actorUserId", "ActorUserId", "userId", "UserId")
	local revisionValue = readNumber(
		payload,
		"visualRevision",
		"VisualRevision",
		"actionRevision",
		"ActionRevision",
		"cueSerial",
		"CueSerial"
	)
	if not actorValue or actorValue < 1 or actorValue ~= math.floor(actorValue) then
		return true
	end
	if not revisionValue or revisionValue < 1 or revisionValue ~= math.floor(revisionValue) then
		return true
	end
	local userId = math.floor(actorValue)
	local revision = math.floor(revisionValue)
	if revision <= (self.lastVisualRevision[userId] or 0) then
		return true
	end

	local action = normalizeAction(readString(payload, "action", "Action"))
	local mode = normalizeMode(
		readString(payload, "mode", "Mode", "variant", "Variant", "shotType", "ShotType")
	)
	if action == "" or not ProceduralPoseCatalog.IsSupported(action, mode) then
		return true
	end
	local phase = normalizeMode(readString(payload, "phase", "Phase"))
	if phase == "" then
		phase = "Execute"
	end
	local phaseToken = normalizedToken(phase)
	local modeToken = normalizedToken(mode)
	local isStop = phaseToken == "stop"
		or phaseToken == "end"
		or phaseToken == "cancel"
		or (
			(action == "Charge" or action == "Shield")
			and (
				modeToken == "stop"
				or modeToken == "end"
				or modeToken == "cancel"
				or modeToken == "off"
			)
		)
	local startedAt = readNumber(payload, "serverTime", "ServerTime", "startedAt", "StartedAt")
	local now = serverNow()
	local timestampValid = startedAt ~= nil
		and startedAt >= now - MAX_EFFECT_AGE
		and startedAt <= now + MAX_EFFECT_FUTURE
	if not timestampValid and not isStop then
		return true
	end

	local actorPlayer = Players:GetPlayerByUserId(userId)
	if actorPlayer then
		local actorMatchId = actorPlayer:GetAttribute("MatchId")
		local actorArenaId = actorPlayer:GetAttribute("ArenaId")
		local effectMatchId = readString(payload, "matchId", "MatchId")
		local effectArenaId = readString(payload, "arenaId", "ArenaId")
		if
			typeof(actorMatchId) == "string"
			and actorMatchId ~= ""
			and actorMatchId ~= effectMatchId
		then
			return true
		end
		if
			typeof(actorArenaId) == "string"
			and actorArenaId ~= ""
			and actorArenaId ~= effectArenaId
		then
			return true
		end
	end

	self.lastVisualRevision[userId] = revision
	local actor = self:_actor(userId, actorPlayer)
	if isStop then
		if actor.hold and (actor.hold :: Cue).action == action then
			actor.hold = nil
		end
		return true
	end
	local cueStartedAt = startedAt :: number
	local cue = makeCue(
		action,
		mode,
		phase,
		cueStartedAt,
		readNumber(payload, "duration", "Duration"),
		readNumber(payload, "power", "Power"),
		readNumber(payload, "lateral", "Lateral"),
		revision
	)

	if action == "Charge" or action == "Shield" then
		actor.hold = cue
	else
		if
			action == "Kick"
			or action == "Pass"
			or action == "Skill"
			or action == "Feint"
			or action == "Dash"
		then
			actor.hold = nil
		end
		actor.action = cue
	end
	return true
end

function PlayerAnimationController.BeginCharge(
	self: PlayerAnimationController,
	action: string,
	startedAt: number?
): boolean
	if self.destroyed or not self.localPlayer then
		return false
	end
	local mode = normalizeMode(action)
	if mode ~= "Kick" and mode ~= "Pass" then
		return false
	end
	local player = self.localPlayer :: Player
	local actor = self:_actor(player.UserId, player)
	actor.hold = makeCue(
		"Charge",
		mode,
		"Start",
		if finiteNumber(startedAt) then startedAt :: number else serverNow(),
		nil,
		0.65,
		1,
		0
	)
	return true
end

function PlayerAnimationController.CancelCharge(self: PlayerAnimationController)
	local player = self.localPlayer
	if not player then
		return
	end
	local actor = self.actors[player.UserId]
	if actor and actor.hold and (actor.hold :: Cue).action == "Charge" then
		actor.hold = nil
	end
end

function PlayerAnimationController.ApplyActionFeedback(
	self: PlayerAnimationController,
	feedback: any
): boolean
	if self.destroyed or typeof(feedback) ~= "table" then
		return false
	end
	local action = normalizeAction(readString(feedback, "action", "Action"))
	if action == "Charge" then
		local accepted = feedback.accepted == true or feedback.Accepted == true
		local mode =
			normalizeMode(readString(feedback, "mode", "Mode", "chargeAction", "ChargeAction"))
		if accepted and (mode == "Kick" or mode == "Pass") then
			local localPlayer = self.localPlayer
			local actor = if localPlayer then self.actors[localPlayer.UserId] else nil
			if not actor or not actor.hold or (actor.hold :: Cue).action ~= "Charge" then
				self:BeginCharge(mode)
			end
		else
			self:CancelCharge()
		end
		return true
	elseif action == "Kick" or action == "Pass" then
		self:CancelCharge()
	end
	return false
end

function PlayerAnimationController.Reset(self: PlayerAnimationController)
	for _, actor in self.actors do
		restoreActor(actor)
	end
	table.clear(self.actors)
	table.clear(self.lastVisualRevision)
end

function PlayerAnimationController.ResetTransientState(self: PlayerAnimationController)
	self:Reset()
end

function PlayerAnimationController.Destroy(self: PlayerAnimationController)
	if self.destroyed then
		return
	end
	self:Reset()
	self.destroyed = true
	if self.preSimulationConnection then
		self.preSimulationConnection:Disconnect()
		self.preSimulationConnection = nil
	end
end

return PlayerAnimationController
