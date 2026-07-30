--!strict

local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Lighting = game:GetService("Lighting")
local StarterPlayer = game:GetService("StarterPlayer")
local Workspace = game:GetService("Workspace")

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
local goalMath = require(sharedRoot:FindFirstChild("GoalMath"))
local net = require(sharedRoot:FindFirstChild("Net"))
local worldBuilder = require(serverRoot:FindFirstChild("WorldBuilder"))
local arenaServiceModule = require(serverRoot:FindFirstChild("ArenaService"))
local ballServiceModule = require(serverRoot:FindFirstChild("BallService"))
local matchServiceModule = require(serverRoot:FindFirstChild("MatchService"))
local remoteRegistry = require(serverRoot:FindFirstChild("RemoteRegistry"))
local clientRoot = StarterPlayer.StarterPlayerScripts:FindFirstChild("PannaClient")
expect(clientRoot ~= nil, "PannaClient was not mapped by Rojo")
local effectScope = require(clientRoot:FindFirstChild("EffectScope"))
local clientModules = {}
for _, moduleName in
	{
		"ControlCatalog",
		"FootballVFXController",
		"InputController",
		"PlayerAnimationController",
		"ProceduralPoseCatalog",
		"UIController",
	}
do
	local clientModule = clientRoot:FindFirstChild(moduleName)
	expect(clientModule ~= nil, moduleName .. " was not mapped by Rojo")
	local ok, result = pcall(require, clientModule)
	expect(ok, moduleName .. " failed to load: " .. tostring(result))
	expect(type(result) == "table", moduleName .. " must return a module table")
	clientModules[moduleName] = result
end

local controlCatalog = clientModules.ControlCatalog
local footballVFXControllerModule = clientModules.FootballVFXController
local playerAnimationControllerModule = clientModules.PlayerAnimationController
local proceduralPoseCatalog = clientModules.ProceduralPoseCatalog
local uiControllerModule = clientModules.UIController
for _, methodName in
	{
		"new",
		"SetAimState",
		"ApplyEffect",
		"ResetTransientState",
		"Destroy",
		"GetPalette",
	}
do
	expect(
		type(footballVFXControllerModule[methodName]) == "function",
		"FootballVFXController." .. methodName .. " missing"
	)
end
local vfxPalette = footballVFXControllerModule.GetPalette()
expect(
	type(vfxPalette) == "table"
		and typeof(vfxPalette.Cyan) == "Color3"
		and typeof(vfxPalette.Pink) == "Color3",
	"football VFX palette is incomplete"
)
local vfxTestUserId = 900001
local vfxController = footballVFXControllerModule.new({
	UserId = vfxTestUserId,
	Character = nil,
} :: any)
local vfxNow = Workspace:GetServerTimeNow()
local noOriginCue = {
	kind = "PlayerAction",
	actorUserId = vfxTestUserId,
	action = "Kick",
	mode = "Normal",
	visualRevision = 1,
	serverTime = vfxNow,
}
expect(not vfxController:ApplyEffect(noOriginCue), "origin-less VFX cue created a world effect")
expect(#vfxController.transients == 0, "origin-less VFX cue left transient parts")
expect(
	vfxController:ApplyEffect(noOriginCue) and #vfxController.transients == 0,
	"duplicate origin-less VFX cue was not consumed safely"
)
local vfxBall = Instance.new("Part")
vfxBall.Name = "VFXSmokeBall"
vfxBall.Shape = Enum.PartType.Ball
vfxBall.Size = Vector3.new(2.3, 2.3, 2.3)
vfxBall.Anchored = true
vfxBall.Position = Vector3.new(0, 8, 0)
vfxBall.Parent = Workspace
vfxController:SetAimState(
	vfxBall,
	"Controlled",
	vfxTestUserId,
	Vector3.new(0, 0, -1),
	"Kick",
	"Normal",
	0.6,
	true,
	true
)
local validCue = table.clone(noOriginCue)
validCue.visualRevision = 2
expect(vfxController:ApplyEffect(validCue), "valid football VFX cue was rejected")
local transientCount = #vfxController.transients
expect(transientCount > 0, "valid football VFX cue created no transient parts")
expect(vfxController:ApplyEffect(validCue), "duplicate football VFX cue was not consumed")
expect(#vfxController.transients == transientCount, "duplicate football VFX cue replayed")
local staleCue = table.clone(validCue)
staleCue.visualRevision = 3
staleCue.serverTime = vfxNow - 100
expect(vfxController:ApplyEffect(staleCue), "stale football VFX cue was not consumed")
expect(
	#vfxController.transients == transientCount
		and vfxController.lastVisualRevision[vfxTestUserId] == 2,
	"stale football VFX cue changed the presentation state"
)
vfxController:ResetTransientState()
expect(
	#vfxController.transients == 0 and next(vfxController.lastVisualRevision) == nil,
	"football VFX reset did not clear transient parts and revisions"
)
vfxController:Destroy()
vfxBall:Destroy()
expect(
	Workspace:FindFirstChild("PannaLocalVFX_" .. tostring(vfxTestUserId)) == nil,
	"football VFX folder leaked"
)
expect(#controlCatalog.ActionOrder == 7, "control catalog must expose seven HUD actions")
expect(#controlCatalog.TouchOrder == 8, "touch catalog must include ShotMode")
local guideEntries = uiControllerModule.GetAbilityGuide()
expect(guideEntries == controlCatalog.GuideEntries, "HUD guide did not use the shared catalog")
expect(#guideEntries == 9, "ability guide must explain control plus all eight actions")
local expectedGuideEntries = {
	BallControl = true,
	Kick = true,
	ShotMode = true,
	Pass = true,
	Feint = true,
	Skill = true,
	Tackle = true,
	Shield = true,
	Dash = true,
}
for _, entry in guideEntries do
	expect(
		expectedGuideEntries[entry.id] == true,
		"unexpected or duplicate guide entry " .. entry.id
	)
	expect(entry.title ~= "", entry.id .. " guide title is empty")
	expect(entry.keyboard ~= "", entry.id .. " keyboard guide is empty")
	expect(entry.gamepad ~= "", entry.id .. " gamepad guide is empty")
	expect(entry.touch ~= "", entry.id .. " touch guide is empty")
	expect(entry.description ~= "", entry.id .. " guide description is empty")
	expectedGuideEntries[entry.id] = nil
end
expect(next(expectedGuideEntries) == nil, "ability guide is missing an entry")
for _, methodName in
	{
		"SetControlsGuideVisible",
		"ToggleControlsGuide",
		"IsControlsGuideVisible",
	}
do
	expect(
		type(uiControllerModule[methodName]) == "function",
		"UIController." .. methodName .. " missing"
	)
end

local expectedInputs = {
	Kick = { Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 },
	Pass = { Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonX },
	Feint = { Enum.KeyCode.Q, Enum.KeyCode.V, Enum.KeyCode.ButtonR1 },
	Skill = { Enum.KeyCode.R, Enum.KeyCode.ButtonY },
	Tackle = { Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.ButtonB },
	Shield = { Enum.KeyCode.C, Enum.KeyCode.ButtonL2 },
	Dash = { Enum.KeyCode.X, Enum.KeyCode.ButtonL1 },
	ShotMode = { Enum.KeyCode.Z, Enum.KeyCode.DPadUp },
}
local seenBindings = {}
for action, inputs in expectedInputs do
	local definition = controlCatalog.Actions[action]
	expect(type(definition) == "table", action .. " control definition missing")
	expect(definition.bindingName ~= "", action .. " binding name is empty")
	expect(seenBindings[definition.bindingName] == nil, action .. " binding name is duplicated")
	seenBindings[definition.bindingName] = true
	for _, expectedInput in inputs do
		expect(table.find(definition.inputs, expectedInput) ~= nil, action .. " input is missing")
	end
end
expect(
	string.find(controlCatalog.Actions.Kick.keyboard, "STEAL", 1, true) ~= nil,
	"primary mouse binding does not advertise contextual takeover"
)
expect(
	string.find(controlCatalog.Actions.Tackle.keyboard, "LMB", 1, true) ~= nil,
	"tackle guide does not expose contextual LMB takeover"
)

local expectedPoseActions = {
	Charge = true,
	Kick = true,
	Pass = true,
	Trap = true,
	Shield = true,
	Dash = true,
	Tackle = true,
	Skill = true,
	Feint = true,
}
for _, action in proceduralPoseCatalog.SupportedActions do
	expect(expectedPoseActions[action] == true, "unexpected or duplicate pose action " .. action)
	expectedPoseActions[action] = nil
end
expect(next(expectedPoseActions) == nil, "procedural pose catalog misses a football action")

local expectedFeintPoses = {
	StepOver = true,
	Cut = true,
	DragBack = true,
	Roulette = true,
}
for _, variant in proceduralPoseCatalog.FeintVariants do
	expect(expectedFeintPoses[variant] == true, "unexpected or duplicate feint pose " .. variant)
	expectedFeintPoses[variant] = nil
end
expect(next(expectedFeintPoses) == nil, "procedural pose catalog misses a feint variant")

local allowedPoseJoints = {
	Root = true,
	Waist = true,
	Neck = true,
	LeftShoulder = true,
	RightShoulder = true,
	LeftHip = true,
	RightHip = true,
	LeftKnee = true,
	RightKnee = true,
	LeftAnkle = true,
	RightAnkle = true,
}
local declaredPoseJoints = table.clone(allowedPoseJoints)
for _, joint in proceduralPoseCatalog.NormalizedJoints do
	expect(declaredPoseJoints[joint] == true, "pose catalog declares an unsafe joint " .. joint)
	declaredPoseJoints[joint] = nil
end
expect(next(declaredPoseJoints) == nil, "pose catalog joint whitelist is incomplete")

local function finiteCFrame(value: any): boolean
	if typeof(value) ~= "CFrame" then
		return false
	end
	for _, component in { (value :: CFrame):GetComponents() } do
		if
			type(component) ~= "number"
			or component ~= component
			or math.abs(component) == math.huge
		then
			return false
		end
	end
	return true
end

local function poseHasMotion(pose: { [string]: CFrame }): boolean
	for _, transform in pose do
		if
			transform.Position.Magnitude > 1e-4
			or transform.LookVector:Dot(Vector3.new(0, 0, -1)) < 0.99999
			or transform.UpVector:Dot(Vector3.yAxis) < 0.99999
		then
			return true
		end
	end
	return false
end

local poseScenarios = {
	{ action = "Charge", mode = "Kick" },
	{ action = "Charge", mode = "Pass" },
	{ action = "Kick", mode = "Low" },
	{ action = "Kick", mode = "Normal" },
	{ action = "Kick", mode = "Chip" },
	{ action = "Pass", mode = "Ground" },
	{ action = "Trap", mode = "Control" },
	{ action = "Shield", mode = "Start" },
	{ action = "Dash", mode = "Forward" },
	{ action = "Tackle", mode = "Standing" },
	{ action = "Skill", mode = "Panna" },
	{ action = "Feint", mode = "StepOver" },
	{ action = "Feint", mode = "Cut" },
	{ action = "Feint", mode = "DragBack" },
	{ action = "Feint", mode = "Roulette" },
}
for _, scenario in poseScenarios do
	expect(
		proceduralPoseCatalog.IsSupported(scenario.action, scenario.mode),
		scenario.action .. "/" .. scenario.mode .. " pose is not supported"
	)
	local duration = proceduralPoseCatalog.GetDuration(scenario.action, scenario.mode)
	expect(
		type(duration) == "number" and duration >= 0.05 and duration <= 5,
		scenario.action .. "/" .. scenario.mode .. " duration is invalid"
	)
	for _, elapsed in { 0, duration * 0.5, duration, duration * 2, math.huge } do
		local pose = proceduralPoseCatalog.Sample(
			scenario.action,
			scenario.mode,
			elapsed,
			duration,
			0.8,
			-0.65
		)
		expect(type(pose) == "table", scenario.action .. " pose sample is not a table")
		for joint, transform in pose do
			expect(allowedPoseJoints[joint] == true, scenario.action .. " writes an unsafe joint")
			expect(finiteCFrame(transform), scenario.action .. " produced a non-finite pose")
		end
		if elapsed == duration * 0.5 then
			expect(poseHasMotion(pose), scenario.action .. "/" .. scenario.mode .. " has no motion")
		end
	end
end
expect(
	next(proceduralPoseCatalog.Sample("Unknown", "", 0.2, 0.4, 1, 0)) == nil,
	"unknown action produced a procedural pose"
)
expect(
	proceduralPoseCatalog.IsHold("Charge")
		and proceduralPoseCatalog.IsHold("Shield")
		and not proceduralPoseCatalog.IsHold("Kick"),
	"pose hold classification is invalid"
)

for _, methodName in
	{
		"new",
		"ApplyEffect",
		"BeginCharge",
		"CancelCharge",
		"ApplyActionFeedback",
		"Reset",
		"ResetTransientState",
		"Destroy",
	}
do
	expect(
		type(playerAnimationControllerModule[methodName]) == "function",
		"PlayerAnimationController." .. methodName .. " missing"
	)
end

local animationRig = Instance.new("Model")
animationRig.Name = "AnimationSmokeRig"
local animationRoot = Instance.new("Part")
animationRoot.Name = "AnimationRoot"
animationRoot.Anchored = true
animationRoot.Parent = animationRig
local animationLeg = Instance.new("Part")
animationLeg.Name = "AnimationLeg"
animationLeg.Anchored = true
animationLeg.Parent = animationRig
local animationMotor = Instance.new("Motor6D")
animationMotor.Name = "RightHip"
animationMotor.Part0 = animationRoot
animationMotor.Part1 = animationLeg
animationMotor.Parent = animationRoot
animationRig.Parent = Workspace
local animationAttributes: { [string]: any } = {
	MatchId = "AnimationMatch",
	ArenaId = "Arena_1",
	MatchRevision = 4,
}
local animationPlayer: any = {
	UserId = 7654321,
	Parent = Workspace,
	Character = animationRig,
}
function animationPlayer:GetAttribute(attributeName: string): any
	return animationAttributes[attributeName]
end

local animationController = playerAnimationControllerModule.new(animationPlayer)
expect(
	animationController:BeginCharge("Kick", Workspace:GetServerTimeNow() - 0.5),
	"require-safe animation controller rejected local charge pose"
)
animationController:_step()
expect(
	poseHasMotion({ RightHip = animationMotor.Transform }),
	"controller did not apply Motor6D pose"
)
local authoritativeChargeStart = animationController.actors[animationPlayer.UserId].hold.startedAt
animationController:ApplyActionFeedback({
	action = "ChargeStart",
	accepted = true,
	mode = "Kick",
})
expect(
	animationController.actors[animationPlayer.UserId].hold.startedAt == authoritativeChargeStart,
	"valid ActionFeedback rewound an already-authoritative charge pose"
)
local staleChargeStop = {
	kind = "PlayerAction",
	matchId = "AnimationMatch",
	arenaId = "Arena_1",
	matchRevision = 4,
	actorUserId = animationPlayer.UserId,
	action = "Charge",
	mode = "Stop",
	lateral = 0,
	visualRevision = 1,
	serverTime = Workspace:GetServerTimeNow() - 20,
}
expect(animationController:ApplyEffect(staleChargeStop), "stale Charge Stop cue was not consumed")
expect(
	animationController.actors[animationPlayer.UserId].hold == nil
		and animationController.lastVisualRevision[animationPlayer.UserId] == 1,
	"stale Charge Stop did not clear the active hold"
)
animationController:_step()
expect(
	not poseHasMotion({ RightHip = animationMotor.Transform }),
	"controller did not restore Motor6D after a stale Stop cue"
)
expect(
	animationController:BeginCharge("Pass", Workspace:GetServerTimeNow() - 20),
	"animation controller rejected the hold-timeout fixture"
)
animationController:_step()
expect(
	animationController.actors[animationPlayer.UserId] == nil
		and not poseHasMotion({ RightHip = animationMotor.Transform }),
	"local hold hard-timeout left a stuck pose"
)
expect(
	animationController:BeginCharge("Kick", Workspace:GetServerTimeNow()),
	"animation controller rejected the explicit cancel fixture"
)
animationController:CancelCharge()
animationController:_step()
expect(
	not poseHasMotion({ RightHip = animationMotor.Transform }),
	"controller did not restore Motor6D after cancelling a hold pose"
)

local actionServerTime = Workspace:GetServerTimeNow()
local actionEffect = {
	kind = "PlayerAction",
	matchId = "AnimationMatch",
	arenaId = "Arena_1",
	matchRevision = 4,
	actorUserId = 9001,
	action = "Kick",
	mode = "Normal",
	lateral = 0,
	visualRevision = 1,
	serverTime = actionServerTime,
}
expect(animationController:ApplyEffect(actionEffect), "PlayerAction cue was not consumed")
expect(
	animationController.lastVisualRevision[9001] == 1
		and animationController.actors[9001].action.action == "Kick",
	"valid scoped PlayerAction cue was not accepted"
)
local duplicateCue = table.clone(actionEffect)
duplicateCue.action = "Dash"
expect(animationController:ApplyEffect(duplicateCue), "duplicate PlayerAction was not consumed")
expect(
	animationController.actors[9001].action.action == "Kick",
	"duplicate visual revision replaced the accepted animation"
)
local wrongScopeCue = table.clone(actionEffect)
wrongScopeCue.matchId = "WrongMatch"
wrongScopeCue.visualRevision = 2
expect(animationController:ApplyEffect(wrongScopeCue), "wrong-scope PlayerAction was not consumed")
expect(
	animationController.lastVisualRevision[9001] == 1,
	"wrong-scope PlayerAction advanced visual revision"
)
local staleTimeCue = table.clone(actionEffect)
staleTimeCue.visualRevision = 2
staleTimeCue.serverTime = actionServerTime - 20
expect(animationController:ApplyEffect(staleTimeCue), "stale PlayerAction was not consumed")
expect(
	animationController.lastVisualRevision[9001] == 1,
	"stale PlayerAction advanced visual revision"
)
expect(
	not animationController:ApplyEffect({ kind = "Message" }),
	"animation controller swallowed a non-animation effect"
)
animationController:ResetTransientState()
expect(
	next(animationController.actors) == nil and next(animationController.lastVisualRevision) == nil,
	"animation reset kept actor or revision state"
)
animationController:Destroy()
animationController:Destroy()
expect(animationController.destroyed, "animation controller destroy is not idempotent")
animationRig:Destroy()

expect(type(ballMath) == "table", "BallMath module failed to load")
expect(type(goalMath) == "table", "GoalMath module failed to load")
for _, functionName in
	{
		"IsFiniteNumber",
		"IsFiniteVector3",
		"HorizontalUnit",
		"ClampMagnitude",
		"ChargePower",
		"LaunchVelocity",
		"LaunchAngularVelocity",
		"AerodynamicDragAcceleration",
		"DirectionDot",
		"ClosestPointOnRay",
		"ProjectOnPlane",
		"RotateHorizontalTowards",
		"SmoothControlDistance",
		"AssistedHorizontalDirection",
		"CushionedTouchVelocity",
		"PhysicalControlTarget",
		"PhysicalControlAcceleration",
		"MagnusAcceleration",
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

local launchDirection = Vector3.new(0, 0, -1)
local launchVelocity = ballMath.LaunchVelocity(launchDirection, 50, 24, Vector3.new(10, 7, 0), 0.2)
expect(launchVelocity ~= nil, "BallMath.LaunchVelocity rejected finite launch inputs")
local resolvedLaunchVelocity = launchVelocity :: Vector3
expect(
	(resolvedLaunchVelocity - Vector3.new(2, 24, -50)).Magnitude < 1e-4,
	"launch velocity did not keep lift independent from carrier vertical velocity"
)
expect(
	ballMath.LaunchVelocity(launchDirection, 50, 24, Vector3.new(math.huge, 0, 0), 0.2) == nil,
	"launch velocity accepted a non-finite carrier velocity"
)

local launchAngular =
	ballMath.LaunchAngularVelocity(launchDirection, 50, config.Ball.Radius, 0.8, 6)
expect(launchAngular ~= nil, "BallMath.LaunchAngularVelocity rejected finite launch inputs")
local resolvedLaunchAngular = launchAngular :: Vector3
local expectedRollAxis = Vector3.new(0, 1, 0):Cross(launchDirection)
local expectedRollSpeed = 50 / config.Ball.Radius * 0.8
expect(
	math.abs(resolvedLaunchAngular:Dot(expectedRollAxis) - expectedRollSpeed) < 1e-4,
	"launch roll rate is not coupled to linear speed and ball radius"
)
expect(
	math.abs(resolvedLaunchAngular.Y - 6) < 1e-4
		and math.abs(resolvedLaunchAngular:Dot(launchDirection)) < 1e-4,
	"launch angular velocity contains an invalid longitudinal or yaw component"
)
expect(
	ballMath.LaunchAngularVelocity(launchDirection, 50, 0, 0.8, 0) == nil,
	"launch angular velocity accepted a zero radius"
)

local dragAcceleration = ballMath.AerodynamicDragAcceleration(
	Vector3.new(30, 10, -40),
	config.Ball.Aerodynamics.DragCoefficient,
	config.Ball.Aerodynamics.MaximumDragAcceleration
)
expect(
	ballMath.IsFiniteVector3(dragAcceleration)
		and dragAcceleration.Magnitude > 0
		and dragAcceleration.Magnitude
			<= config.Ball.Aerodynamics.MaximumDragAcceleration + 1e-4,
	"aerodynamic drag is not finite and bounded"
)
expect(
	dragAcceleration:Dot(Vector3.new(30, 10, -40)) < 0,
	"aerodynamic drag accelerates the ball along its velocity"
)
expect(
	ballMath.AerodynamicDragAcceleration(
		Vector3.zero,
		config.Ball.Aerodynamics.DragCoefficient,
		config.Ball.Aerodynamics.MaximumDragAcceleration
	) == Vector3.zero,
	"stationary ball received aerodynamic drag"
)
local closestPoint, distanceAlong =
	ballMath.ClosestPointOnRay(Vector3.zero, Vector3.new(0, 0, -1), Vector3.new(3, 0, -7))
expect(
	(closestPoint - Vector3.new(0, 0, -7)).Magnitude < 1e-4 and math.abs(distanceAlong - 7) < 1e-4,
	"BallMath.ClosestPointOnRay returned incorrect geometry"
)

local controlTarget =
	ballMath.PhysicalControlTarget(CFrame.new(10, 5, 20), Vector3.new(0, 0, -1), 3, 1, 1.34)
expect(controlTarget ~= nil, "physical control target rejected valid input")
local resolvedControlTarget = controlTarget :: Vector3
expect(
	(resolvedControlTarget - Vector3.new(11, 1.34, 17)).Magnitude < 1e-4,
	"physical control target does not stay in front of the player"
)
expect(
	ballMath.PhysicalControlTarget(CFrame.new(10, 5, 20), Vector3.new(0, 0, -1), 3, 0, math.huge)
		== nil,
	"physical control accepted a non-finite target height"
)
local rotated =
	ballMath.RotateHorizontalTowards(Vector3.new(0, 0, -1), Vector3.new(1, 0, 0), math.pi * 0.25)
expect(rotated ~= nil, "physical control direction rotation failed")
local resolvedRotated = rotated :: Vector3
expect(
	math.abs(resolvedRotated.Magnitude - 1) < 1e-4 and resolvedRotated:Dot(Vector3.new(1, 0, 0)) > 0,
	"physical control direction did not rotate along the shortest arc"
)
local movingControlDirection =
	ballMath.PreferredControlDirection(Vector3.new(0, 0, -1), Vector3.new(8, 3, 0), 2)
expect(
	movingControlDirection ~= nil and (movingControlDirection :: Vector3):Dot(Vector3.xAxis) > 0.999,
	"physical control direction did not follow trusted horizontal movement"
)
local idleControlDirection =
	ballMath.PreferredControlDirection(Vector3.new(0, 0, -1), Vector3.new(0.25, 4, 0), 2)
expect(
	idleControlDirection ~= nil
		and (idleControlDirection :: Vector3):Dot(Vector3.new(0, 0, -1)) > 0.999,
	"physical control direction did not fall back to character facing"
)
local idleDistance = ballMath.SmoothControlDistance(0, 2.1, 2.5, 3.4, 2, 20)
local walkingDistance = ballMath.SmoothControlDistance(2, 2.1, 2.5, 3.4, 2, 20)
local runningDistance = ballMath.SmoothControlDistance(11, 2.1, 2.5, 3.4, 2, 20)
local sprintDistance = ballMath.SmoothControlDistance(20, 2.1, 2.5, 3.4, 2, 20)
expect(
	idleDistance ~= nil
		and math.abs((idleDistance :: number) - 2.1) < 1e-4
		and walkingDistance ~= nil
		and math.abs((walkingDistance :: number) - 2.5) < 1e-4
		and runningDistance ~= nil
		and runningDistance > 2.5
		and runningDistance < 3.4
		and sprintDistance ~= nil
		and math.abs((sprintDistance :: number) - 3.4) < 1e-4,
	"smooth dribble distance does not interpolate across player speed"
)
local assistedDirection, assistUsed =
	ballMath.AssistedHorizontalDirection(Vector3.new(0, 0, -1), Vector3.new(1, 0, -1), 0.7, 0.25)
expect(
	assistUsed
		and assistedDirection ~= nil
		and (assistedDirection :: Vector3):Dot(Vector3.new(1, 0, -1).Unit)
			> Vector3.new(0, 0, -1):Dot(Vector3.new(1, 0, -1).Unit),
	"bounded shot assistance did not move an already plausible aim toward its target"
)
local rejectedAssist, rejectedAssistUsed =
	ballMath.AssistedHorizontalDirection(Vector3.new(0, 0, -1), Vector3.new(0, 0, 1), 0.7, 0.25)
expect(
	not rejectedAssistUsed
		and rejectedAssist ~= nil
		and (rejectedAssist :: Vector3):Dot(Vector3.new(0, 0, -1)) > 0.999,
	"aim assistance redirected an implausible backwards shot"
)
local cushionedVelocity = ballMath.CushionedTouchVelocity(
	Vector3.new(0, 10, -30),
	Vector3.new(8, 0, 0),
	Vector3.new(0, 0, -1),
	0.1,
	0.05,
	32
)
expect(
	cushionedVelocity ~= nil
		and ((cushionedVelocity :: Vector3) - Vector3.new(8, 0.5, -3)).Magnitude < 1e-4,
	"first-touch cushion did not absorb incoming horizontal and vertical speed"
)
local cappedTrapVelocity = ballMath.CushionedTouchVelocity(
	Vector3.new(0, 18, -84),
	Vector3.zero,
	Vector3.new(0, 0, -1),
	config.Ball.FirstTouch.TrapHorizontalRetention,
	config.Ball.FirstTouch.TrapVerticalRetention,
	config.Ball.FirstTouch.MaximumExitSpeed
)
expect(
	cappedTrapVelocity ~= nil
		and (cappedTrapVelocity :: Vector3).Magnitude
			<= config.Ball.FirstTouch.MaximumExitSpeed + 1e-4,
	"explicit trap can exceed the configured maximum exit speed"
)
local projected = ballMath.ProjectOnPlane(Vector3.new(3, 5, 4), Vector3.yAxis)
expect(projected == Vector3.new(3, 0, 4), "ground-plane projection is incorrect")
expect(
	ballMath.ProjectOnPlane(Vector3.new(math.huge, 0, 0), Vector3.yAxis) == Vector3.zero,
	"ground-plane projection propagated a non-finite vector"
)
local physicalAcceleration = ballMath.PhysicalControlAcceleration(
	Vector3.zero,
	Vector3.zero,
	Vector3.new(2, 0, 0),
	Vector3.zero,
	Vector3.yAxis,
	7,
	0.95,
	1,
	28,
	118
)
expect(physicalAcceleration ~= nil, "physical PD acceleration rejected valid input")
local resolvedAcceleration = physicalAcceleration :: Vector3
expect(
	resolvedAcceleration.X > 0 and resolvedAcceleration.Magnitude <= 118 + 1e-4,
	"physical PD acceleration is not bounded toward its target"
)
local lowDampingSpring = ballMath.PhysicalControlAcceleration(
	Vector3.zero,
	Vector3.zero,
	Vector3.new(1, 0, 0),
	Vector3.zero,
	Vector3.yAxis,
	5,
	0.4,
	1,
	100,
	1000
)
local highDampingSpring = ballMath.PhysicalControlAcceleration(
	Vector3.zero,
	Vector3.zero,
	Vector3.new(1, 0, 0),
	Vector3.zero,
	Vector3.yAxis,
	5,
	1.4,
	1,
	100,
	1000
)
expect(
	lowDampingSpring ~= nil
		and highDampingSpring ~= nil
		and ((lowDampingSpring :: Vector3) - (highDampingSpring :: Vector3)).Magnitude < 1e-4,
	"PD damping ratio incorrectly changes spring stiffness at rest"
)
local positiveCurve =
	ballMath.MagnusAcceleration(Vector3.new(0, 0, -50), Vector3.new(0, 4, 0), 0.014, 10)
local negativeCurve =
	ballMath.MagnusAcceleration(Vector3.new(0, 0, -50), Vector3.new(0, -4, 0), 0.014, 10)
expect(
	positiveCurve.Magnitude > 0
		and negativeCurve.Magnitude > 0
		and positiveCurve:Dot(negativeCurve) < 0,
	"Magnus side-spin does not curve in opposite directions"
)
local cappedCurve =
	ballMath.MagnusAcceleration(Vector3.new(0, 0, -100), Vector3.new(0, 100, 0), 0.1, 10)
expect(math.abs(cappedCurve.Magnitude - 10) < 1e-4, "Magnus acceleration cap is not enforced")
expect(
	ballMath.MagnusAcceleration(Vector3.new(math.huge, 0, 0), Vector3.yAxis, 0.1, 10)
		== Vector3.zero,
	"Magnus acceleration propagated a non-finite vector"
)
expect(ballMath.KinematicControlTarget == nil, "legacy kinematic target still exists")
expect(ballMath.KinematicRollCFrame == nil, "legacy kinematic roll still exists")
expect(config.Ball.Dribble.IdleDistance > config.Ball.Radius, "idle control distance is invalid")
expect(
	config.Ball.Dribble.ShieldDistance < config.Ball.Dribble.IdleDistance
		and config.Ball.Dribble.IdleDistance < config.Ball.Dribble.WalkDistance
		and config.Ball.Dribble.WalkDistance < config.Ball.Dribble.SprintDistance,
	"physical dribble distances are not ordered"
)
expect(config.Ball.Dribble.NaturalFrequency > 0, "physical PD frequency is disabled")
expect(config.Ball.Dribble.MaximumAccelerationWalk > 0, "physical drive force is disabled")
expect(config.Ball.Dribble.RollResponsiveness > 0, "physical roll torque is disabled")
expect(config.Ball.MechanicsVersion == "StreetControlV3", "football mechanics version is stale")
expect(
	type(config.VisualEffects) == "table" and config.VisualEffects.Version == "StreetReadabilityV1",
	"football VFX version is stale"
)
expect(
	config.VisualEffects.MaximumTransientParts >= 16
		and config.VisualEffects.AimGuide.TrajectoryDots >= 4
		and config.VisualEffects.BallDirection.MinimumSpeed > 0,
	"football VFX limits are invalid"
)
expect(
	config.Ball.FirstTouch.TrapHorizontalRetention
		< config.Ball.FirstTouch.RedirectHorizontalRetention,
	"explicit trap does not absorb more speed than automatic first touch"
)
expect(
	config.Ball.Shot.AimAssist.Strength > 0 and config.Ball.Shot.AimAssist.Strength < 0.5,
	"shot assistance is missing or too strong"
)
expect(
	config.Ball.Pass.MovementAssistStrength > 0 and config.Ball.Pass.MovementAssistStrength < 0.5,
	"running pass assistance is missing or too strong"
)
expect(config.Ball.Spin.MagnusCoefficient > 0, "physical side-spin curve is disabled")
expect(
	config.Ball.Capture.MaximumControlledBallSpeed >= config.Actions.DashSpeed,
	"physical owner speed envelope is below DashSpeed"
)
expect(
	config.Actions.Feint.ProtectionBreakRadius <= config.Ball.Capture.OwnerBreakRadius,
	"close-control protection can outlive the owner retention envelope"
)
expect(
	config.Ball.Capture.OwnerFrontDistance < config.Ball.Capture.OwnerBreakRadius,
	"owner front envelope is shadowed by the radial break limit"
)
expect(
	config.Ball.Capture.AirSettleGraceSeconds >= config.Ball.Capture.ControlGraceSeconds,
	"air first touch has no physical settle grace"
)
expect(
	config.Security.Movement.MaximumCarrierSpeed >= config.Actions.DashSpeed,
	"trusted carrier speed cap rejects the server dash"
)
expect(config.Ball.ControlRadius == nil, "unused legacy Ball.ControlRadius still exists")
expect(config.Actions.TackleRadius == nil, "unused legacy Actions.TackleRadius still exists")
expect(config.Match.MinimumPlayers == nil, "fixed 1v1 Match.MinimumPlayers must not be misleading")
expect(config.Rooms.Capacity == nil, "fixed 1v1 Rooms.Capacity must not be misleading")
expect(config.Actions.ShieldMaxSeconds == nil, "duplicate shield duration still exists")
expect(config.Ball.Pass.StateSeconds > 0, "pass state duration is missing")
expect(config.Ball.Shot.MinimumFlightSeconds == nil, "flight timing is still coupled to Shot")
expect(config.Ball.Limits.MinimumFlightSeconds > 0, "neutral minimum flight duration is missing")
expect(
	config.Actions.ChargeMaximumSeconds
		> math.max(config.Ball.Shot.ChargeSeconds, config.Ball.Pass.ChargeSeconds),
	"server charge safety timeout is shorter than the playable charge window"
)
expect(
	config.Actions.Tackle.TakeoverGraceSeconds > 0
		and config.Actions.Tackle.MaximumStopDeltaSpeed > 0
		and config.Actions.Tackle.MaximumStopAngularSpeed > 0,
	"direct tackle takeover tuning is missing"
)
expect(
	config.Actions.Feint.Variants.StepOver.LateralDistance > 0
		and config.Actions.Feint.Variants.Cut.DistanceMultiplier > 1
		and config.Actions.Feint.Variants.DragBack.DistanceMultiplier < 1
		and config.Actions.Feint.Variants.Roulette.LateralDistance
			> config.Actions.Feint.Variants.StepOver.LateralDistance,
	"variant feint trajectories are missing or indistinguishable"
)
expect(
	config.Actions.Feint.VulnerabilityStart == nil
		and config.Actions.Tackle.FeintVulnerabilityRadiusBonus == nil,
	"legacy dribble vulnerability tuning still exists"
)
expect(config.Actions.Panna.RollRatio > 0, "panna speed-derived roll tuning is missing")
expect(config.Actions.Panna.ShooterRecaptureSeconds > 0, "panna recapture tuning is missing")
expect(
	config.Ball.Capture.OwnerBreakRadius
		< math.sqrt(config.Ball.Capture.FrontDistance ^ 2 + config.Ball.Capture.LateralDistance ^ 2),
	"owner break radius can never become the active capture limit"
)

local defenderToAttacker = Vector3.new(0, 0, -1)
expect(
	ballMath.DirectionDot(defenderToAttacker, defenderToAttacker)
		>= config.Actions.Shield.TackleFrontDot,
	"shield facing the tackler did not block"
)
expect(
	ballMath.DirectionDot(defenderToAttacker, -defenderToAttacker)
		< config.Actions.Shield.TackleFrontDot,
	"shield facing away from the tackler blocked"
)

expect(type(effectScope) == "table", "EffectScope module failed to load")
expect(
	effectScope.Matches({ kind = "Message" }, "", "", 0, "", "", 0),
	"global effect was incorrectly scoped"
)
expect(
	effectScope.Matches(
		{ kind = "Result", matchId = "MatchB", arenaId = "Arena_2", matchRevision = 2 },
		"MatchB",
		"Arena_2",
		2,
		"MatchB",
		"Arena_2",
		2
	),
	"converged current result was rejected"
)
expect(
	not effectScope.Matches(
		{ kind = "Result", matchId = "MatchA", arenaId = "Arena_1", matchRevision = 1 },
		"MatchA",
		"Arena_1",
		1,
		"MatchB",
		"Arena_2",
		2
	),
	"stale result was accepted after a newer StateUpdate"
)
expect(
	effectScope.Matches(
		{ kind = "Message", matchId = "MatchB", arenaId = "Arena_2", matchRevision = 2 },
		"MatchA",
		"Arena_1",
		1,
		"MatchB",
		"Arena_2",
		2
	),
	"new effect was rejected while Player attributes were catching up"
)
expect(
	effectScope.Matches(
		{ kind = "Message", matchId = "MatchB", arenaId = "Arena_2", matchRevision = 2 },
		"MatchB",
		"Arena_2",
		2,
		"MatchA",
		"Arena_1",
		1
	),
	"new effect was rejected while StateUpdate was catching up"
)
expect(
	effectScope.Matches(
		{ kind = "Message", matchId = "MatchB", arenaId = "Arena_2", matchRevision = 2 },
		"MatchA",
		"Arena_1",
		1,
		"MatchA",
		"Arena_1",
		1
	),
	"newer effect could not establish the next match context"
)
expect(
	not effectScope.Matches(
		{ kind = "Result", matchId = "MatchA", arenaId = "Arena_1", matchRevision = 1 },
		"MatchB",
		"Arena_2",
		2,
		"MatchA",
		"Arena_1",
		1
	),
	"stale result was accepted after newer Player attributes"
)
expect(
	effectScope.Matches(
		{ kind = "Result", matchId = "MatchOld", arenaId = "Arena_1", matchRevision = 1 },
		"",
		"",
		1,
		"MatchOld",
		"Arena_1",
		1
	),
	"recent result was rejected after cleanup"
)
expect(
	not effectScope.Matches(
		{ kind = "Result", matchId = "MatchB", arenaId = "Arena_2" },
		"MatchB",
		"Arena_2",
		2,
		"MatchB",
		"Arena_2",
		2
	),
	"scoped effect without a server revision was accepted"
)
expect(
	not effectScope.Matches(
		{ kind = "Message", matchId = "MatchB", arenaId = "Arena_3", matchRevision = 2 },
		"MatchB",
		"Arena_2",
		2,
		"MatchB",
		"Arena_2",
		2
	),
	"same-revision effect from the wrong arena was accepted"
)
local stateMatchId, stateArenaId, stateRevision = effectScope.ReadStateContext({
	match = { id = "MatchNew", arenaId = "Arena_2", revision = 3 },
})
expect(
	stateMatchId == "MatchNew" and stateArenaId == "Arena_2" and stateRevision == 3,
	"state context was not read"
)
expect(
	effectScope.ReadStateRevision({ match = false, matchRevision = 3 }) == 3,
	"cleared snapshot lost its match revision"
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
expect(Workspace.Gravity > 0, "ballistic regression requires positive Workspace.Gravity")
local function ballisticEnvelope(tuning: any): (number, number, number)
	local velocity = ballMath.LaunchVelocity(
		Vector3.new(0, 0, -1),
		tuning.SpeedMaximum,
		tuning.LiftMaximum,
		Vector3.zero,
		0
	)
	expect(velocity ~= nil, "full-power ballistic tuning produced no launch velocity")
	local resolved = velocity :: Vector3
	local airTime = 2 * resolved.Y / Workspace.Gravity
	local apexGain = resolved.Y ^ 2 / (2 * Workspace.Gravity)
	local horizontalRange = Vector3.new(resolved.X, 0, resolved.Z).Magnitude * airTime
	return airTime, apexGain, horizontalRange
end

local lowAirTime, lowApex, lowRange = ballisticEnvelope(config.Ball.Shot.Types.Low)
local normalAirTime, normalApex, normalRange = ballisticEnvelope(config.Ball.Shot.Types.Normal)
local chipAirTime, chipApex, chipRange = ballisticEnvelope(config.Ball.Shot.Types.Chip)
expect(
	lowAirTime < normalAirTime and normalAirTime < chipAirTime,
	"shot airtime envelopes are not ordered Low < Normal < Chip"
)
expect(
	lowApex < normalApex and normalApex < chipApex,
	"shot ballistic apex envelopes are not ordered Low < Normal < Chip"
)
expect(
	lowApex <= 0.5 and normalApex >= 1.5 and chipApex >= 5,
	"shot lifts still produce a plate-flat Low/Normal/Chip trajectory"
)
expect(
	normalAirTime >= 0.25 and chipAirTime >= 0.45,
	"Normal or Chip airtime is too short for a readable football arc"
)
expect(
	lowRange >= 4
		and normalRange >= config.World.ArenaLength * 0.25
		and chipRange >= config.World.ArenaLength * 0.35,
	"full-power shot range is too short for the arena scale"
)
expect(
	config.Ball.Shot.Types.Chip.LiftMaximum <= config.Ball.Limits.MaximumVerticalSpeed,
	"Chip lift exceeds the global vertical speed cap"
)
expect(
	config.Ball.Pass.SpeedMaximum <= config.Ball.Limits.MaximumSpeed,
	"Pass tuning exceeds the global ball speed cap"
)
expect(
	config.Ball.Pass.LiftMaximum < config.Ball.Shot.Types.Low.LiftMinimum,
	"ground pass lift overlaps the shot trajectory envelope"
)
expect(config.Ball.Radius < 1.25 and config.Ball.Radius >= 1, "ball was not made slightly smaller")
expect(
	type(config.Ball.VisualVersion) == "string" and config.Ball.VisualVersion ~= "",
	"soccer-ball visual version is missing"
)
local previousMassScale = 0.65 * 1.25 ^ 3
local tunedMassScale = config.Ball.Density * config.Ball.Radius ^ 3
expect(
	math.abs(tunedMassScale / previousMassScale - 1) <= 0.03,
	"smaller ball tuning did not preserve approximate mass"
)
expect(
	config.Ball.Dribble.ShieldDistance > config.Ball.Radius + 0.5,
	"shield target clips the smaller ball into the carrier"
)
expect(
	config.Ball.Dribble.SprintDistance < config.Ball.Capture.OwnerFrontDistance
		and config.Ball.Dribble.SprintDistance < config.Ball.Capture.OwnerBreakRadius,
	"dribble targets exceed the owner retention envelope"
)
expect(
	config.Ball.Dribble.DampingRatio >= 1
		and config.Ball.Dribble.NaturalFrequency >= 8
		and config.Ball.Dribble.MaximumAccelerationSprint
			> config.Ball.Dribble.MaximumAccelerationWalk,
	"controlled dribble response tuning is not stable"
)
expect(
	config.Ball.Shot.PlayerVelocityCarry <= 0.2 and config.Ball.Pass.PlayerVelocityCarry <= 0.2,
	"launch direction still inherits too much player velocity"
)
expect(
	config.Ball.Aerodynamics.DragCoefficient > 0
		and config.Ball.Aerodynamics.MaximumDragAcceleration > 0
		and config.Ball.Aerodynamics.MaximumStepSeconds > 0
		and config.Ball.Aerodynamics.MaximumStepSeconds <= 0.05,
	"bounded airborne drag tuning is incomplete"
)
expect(
	config.Ball.Trail.EnabledSpeed > config.Ball.Trail.DisabledSpeed
		and config.Ball.Trail.Lifetime <= 0.1
		and config.Ball.Trail.WidthStart <= config.Ball.Radius * 0.2,
	"subtle high-speed trail gating is invalid"
)
for _, tuning in config.Ball.Shot.Types do
	expect(
		type(tuning.RollRatio) == "number"
			and tuning.RollRatio == tuning.RollRatio
			and tuning.RollSpin == nil,
		"shot tuning did not migrate from arbitrary spin to a finite roll ratio"
	)
end
expect(
	type(config.Ball.Pass.RollRatio) == "number"
		and config.Ball.Pass.RollRatio == config.Ball.Pass.RollRatio
		and config.Ball.Pass.RollSpin == nil,
	"pass tuning did not migrate from arbitrary spin to a finite roll ratio"
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
	frontDot >= config.Actions.Tackle.DefenderMinimumDot
		and sideDot >= config.Actions.Tackle.DefenderMinimumDot
		and rearDot < config.Actions.Tackle.DefenderMinimumDot,
	"defender-facing tackle geometry is inconsistent"
)
for variantName, variant in config.Actions.Feint.Variants do
	expect(
		type(variant.Duration) == "number"
			and variant.Duration > 0
			and type(variant.DistanceMultiplier) == "number"
			and variant.DistanceMultiplier > 0
			and type(variant.LateralDistance) == "number"
			and variant.LateralDistance >= 0
			and type(variant.ControlAccelerationMultiplier) == "number"
			and variant.ControlAccelerationMultiplier > 0
			and variant.ControlAccelerationMultiplier <= 1,
		"invalid physical trajectory tuning for " .. variantName
	)
end
local feintOwner = {} :: any
local feintService = {
	config = config,
	feints = {},
} :: any
local baseFeintDirection = Vector3.new(0, 0, -1)
local feintStartedAt = 100
local function sampleFeint(variantName: string, lateral: number): (Vector3, number)
	local variant = config.Actions.Feint.Variants[variantName]
	feintService.feints[feintOwner] = {
		variant = variantName,
		direction = baseFeintDirection,
		lateral = lateral,
		startedAt = feintStartedAt,
		endsAt = feintStartedAt + variant.Duration,
		protectedUntil = feintStartedAt + variant.Duration,
	}
	local direction, offset = ballServiceModule._feintTarget(
		feintService,
		feintOwner,
		baseFeintDirection,
		feintStartedAt + variant.Duration * 0.5
	)
	return direction, offset
end
local stepOverDirection, stepOverOffset = sampleFeint("StepOver", 1)
local cutDirection, cutOffset = sampleFeint("Cut", -1)
local dragBackDirection = sampleFeint("DragBack", 0)
local rouletteDirection, rouletteOffset = sampleFeint("Roulette", 1)
expect(
	stepOverDirection:Dot(baseFeintDirection) > 0.999 and stepOverOffset > 0,
	"StepOver physical trajectory is invalid"
)
expect(
	cutDirection:Dot(baseFeintDirection) > 0.999 and cutOffset < 0,
	"Cut physical trajectory is invalid"
)
expect(
	dragBackDirection:Dot(-baseFeintDirection) > 0.999,
	"DragBack physical trajectory did not reverse the ball"
)
expect(
	math.abs(rouletteDirection:Dot(baseFeintDirection)) < 0.05 and rouletteOffset > stepOverOffset,
	"Roulette physical trajectory did not rotate around the player"
)

for _, functionName in
	{
		"CreateGeometry",
		"SignedDistance",
		"FullCrossingCenter",
		"IsSphereInsideAperture",
		"DidSphereFullyCross",
	}
do
	expect(type(goalMath[functionName]) == "function", "GoalMath." .. functionName .. " missing")
end

local goalGeometry =
	goalMath.CreateGeometry(CFrame.new(0, 4, 10), Vector3.new(16, 8, 4), Vector3.zero)
expect(goalGeometry ~= nil, "GoalMath rejected valid goal geometry")
local resolvedGoalGeometry = goalGeometry :: any
local ballRadius = 1
expect(
	not goalMath.DidSphereFullyCross(
		Vector3.new(0, 1, 6),
		Vector3.new(0, 1, 8),
		ballRadius,
		resolvedGoalGeometry
	),
	"ball touching the goal line counted as a goal"
)
expect(
	not goalMath.DidSphereFullyCross(
		Vector3.new(0, 1, 6),
		Vector3.new(0, 1, 8.5),
		ballRadius,
		resolvedGoalGeometry
	),
	"half-crossed ball counted as a goal"
)
expect(
	goalMath.DidSphereFullyCross(
		Vector3.new(0, 1, 6),
		Vector3.new(0, 1, 9.2),
		ballRadius,
		resolvedGoalGeometry
	),
	"fully crossed ball did not count"
)
expect(
	goalMath.DidSphereFullyCross(
		Vector3.new(0, 1.5, 6),
		Vector3.new(0, 1.5, 9.4),
		config.Ball.Radius,
		resolvedGoalGeometry
	),
	"configured smaller ball did not register a full goal-line crossing"
)
expect(
	goalMath.DidSphereFullyCross(
		Vector3.new(0, 1, 5),
		Vector3.new(0, 1, 14),
		ballRadius,
		resolvedGoalGeometry
	),
	"fast swept crossing did not count"
)
expect(
	not goalMath.DidSphereFullyCross(
		Vector3.new(7, 1, 6),
		Vector3.new(7, 1, 10),
		ballRadius,
		resolvedGoalGeometry
	),
	"post tangency counted as a goal"
)
expect(
	not goalMath.DidSphereFullyCross(
		Vector3.new(0, 1, 10),
		Vector3.new(0, 1, 7),
		ballRadius,
		resolvedGoalGeometry
	),
	"reverse entry from behind the goal counted"
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
expect(
	world:GetAttribute("FieldStyle") == config.World.FieldStyle,
	"district field style does not match Config"
)
local builtBallRadius = world:GetAttribute("BallRadius")
expect(
	typeof(builtBallRadius) == "number"
		and math.abs((builtBallRadius :: number) - config.Ball.Radius) < 1e-4,
	"district bake is not versioned by ball radius"
)
expect(
	world:GetAttribute("BallVisualVersion") == config.Ball.VisualVersion,
	"district bake is not versioned by the soccer-ball visual contract"
)
expect(
	world:GetAttribute("MechanicsVersion") == config.Ball.MechanicsVersion,
	"district bake is not versioned by the football mechanics contract"
)
expect(
	world:GetAttribute("VFXVersion") == config.VisualEffects.Version,
	"district bake is not versioned by the football VFX contract"
)

local function expectConfiguredBall(ball: BasePart, label: string)
	local diameter = config.Ball.Radius * 2
	expect(ball.Shape == Enum.PartType.Ball, label .. " is not spherical")
	expect(
		(ball.Size - Vector3.new(diameter, diameter, diameter)).Magnitude < 1e-4,
		label .. " size does not match Config.Ball.Radius"
	)
	local physicalProperties = ball.CustomPhysicalProperties
	expect(physicalProperties ~= nil, label .. " custom physical properties are missing")
	expect(
		math.abs((physicalProperties :: PhysicalProperties).Density - config.Ball.Density) < 1e-4,
		label .. " density does not match the mass-preserving tune"
	)
	expect(
		ball:GetAttribute("BallVisualVersion") == config.Ball.VisualVersion,
		label .. " visual version differs from Config"
	)
	expect(
		ball:GetAttribute("MechanicsVersion") == config.Ball.MechanicsVersion,
		label .. " mechanics version differs from Config"
	)
	local panelCount = 0
	for _, child in ball:GetChildren() do
		if
			child:GetAttribute("BallVisualPanel") == true
			or string.match(child.Name, "^PannaBallPanel_%d+$") ~= nil
		then
			panelCount += 1
		end
	end
	expect(panelCount == 6, label .. " must contain exactly six soccer panels")
	for index = 1, 6 do
		local panel = ball:FindFirstChild(string.format("PannaBallPanel_%02d", index))
		expect(panel ~= nil and panel:IsA("BasePart"), label .. " soccer panel is missing")
		local resolvedPanel = panel :: BasePart
		expect(
			resolvedPanel:GetAttribute("BallVisualPanel") == true
				and resolvedPanel:GetAttribute("PanelIndex") == index,
			label .. " soccer panel identity is invalid"
		)
		expect(
			resolvedPanel.Shape == Enum.PartType.Cylinder
				and not resolvedPanel.Anchored
				and resolvedPanel.Massless
				and not resolvedPanel.CanCollide
				and not resolvedPanel.CanTouch
				and not resolvedPanel.CanQuery,
			label .. " soccer panel changes canonical ball physics"
		)
		expect(
			math.abs(resolvedPanel.Size.X - config.Ball.Radius * 0.045) < 1e-4
				and math.abs(resolvedPanel.Size.Y - config.Ball.Radius * 0.42) < 1e-4
				and math.abs(resolvedPanel.Size.Z - config.Ball.Radius * 0.42) < 1e-4,
			label .. " soccer panel scale does not follow ball radius"
		)
		local weld = resolvedPanel:FindFirstChild("PanelWeld")
		expect(
			weld ~= nil
				and weld:IsA("WeldConstraint")
				and (weld :: WeldConstraint).Part0 == ball
				and (weld :: WeldConstraint).Part1 == resolvedPanel,
			label .. " soccer panel is not welded to the canonical sphere"
		)
	end
	local trailTop = ball:FindFirstChild("PannaTrailTop")
	local trailBottom = ball:FindFirstChild("PannaTrailBottom")
	expect(trailTop ~= nil and trailTop:IsA("Attachment"), label .. " trail top is missing")
	expect(
		trailBottom ~= nil and trailBottom:IsA("Attachment"),
		label .. " trail bottom is missing"
	)
	expect(
		math.abs((trailTop :: Attachment).Position.Y - config.Ball.Radius * 0.25) < 1e-4
			and math.abs((trailBottom :: Attachment).Position.Y + config.Ball.Radius * 0.25)
				< 1e-4,
		label .. " compact trail offsets do not match the smaller radius"
	)
	local trail = ball:FindFirstChild("PannaSpeedTrail")
	expect(trail ~= nil and trail:IsA("Trail"), label .. " speed trail is missing")
	local resolvedTrail = trail :: Trail
	expect(
		math.abs(resolvedTrail.Lifetime - config.Ball.Trail.Lifetime) < 1e-4
			and resolvedTrail.Lifetime <= 0.1
			and resolvedTrail.LightEmission <= 0.1
			and resolvedTrail.WidthScale.Keypoints[1].Value <= config.Ball.Radius * 0.2
			and resolvedTrail.Transparency.Keypoints[1].Value >= 0.5,
		label .. " speed trail still reads as a bright plate"
	)
end

local trainingBall = world:FindFirstChild("TrainingBall", true)
expect(trainingBall ~= nil and trainingBall:IsA("BasePart"), "TrainingBall is missing")
expectConfiguredBall(trainingBall :: BasePart, "TrainingBall")
local trainingBallSpawn = world:FindFirstChild("TrainingBallSpawn", true)
expect(
	trainingBallSpawn ~= nil
		and trainingBallSpawn:IsA("BasePart")
		and ((trainingBall :: BasePart).Position - trainingBallSpawn.Position).Magnitude < 1e-4,
	"TrainingBall does not start at its radius-aware spawn"
)
local environment = world:FindFirstChild("DistrictEnvironment")
expect(environment ~= nil and environment:IsA("Model"), "DistrictEnvironment is missing")
expect(
	environment:GetAttribute("DistrictStyle") == "BrightBlockDistrict",
	"district did not use the bright block visual style"
)
expect(
	environment:GetAttribute("FieldStyle") == config.World.FieldStyle,
	"environment field style does not match Config"
)
expect(
	Lighting.ClockTime >= 12 and Lighting.ClockTime <= 16,
	"district is not configured for daylight"
)
expect(Lighting.Brightness >= 2.5, "daylight brightness is too low")
expect(Lighting.GlobalShadows == false, "minimal district should disable global shadows")
local sunRays = Lighting:FindFirstChild("PannaSunRays")
expect(sunRays ~= nil and sunRays:IsA("SunRaysEffect"), "sun rays effect is missing")
expect((sunRays :: SunRaysEffect).Enabled == false, "sun rays should be disabled")
local softBloom = Lighting:FindFirstChild("PannaSoftBloom")
expect(softBloom ~= nil and softBloom:IsA("BloomEffect"), "bloom effect is missing")
expect(
	(softBloom :: BloomEffect).Enabled == false and (softBloom :: BloomEffect).Intensity == 0,
	"minimal district bloom should be disabled"
)
local lobbySpawn = world:FindFirstChild("LobbySpawn", true)
expect(lobbySpawn ~= nil and lobbySpawn:IsA("BasePart"), "LobbySpawn is missing")
expect(world:FindFirstChild("QueuePrompt", true) ~= nil, "QueuePrompt is missing")

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
	["Street Football"] = true,
	["Community Pitch"] = true,
	["Club Ground"] = true,
	["Railway End"] = true,
	["Training Ground"] = true,
	["Championship Field"] = true,
}

for _, arena in arenaList do
	expect(arena.Model:GetAttribute("ArenaId") == arena.Id, arena.Id .. " has invalid ArenaId")
	local roomTitle = arena.Model:GetAttribute("RoomTitle")
	expect(
		type(roomTitle) == "string" and expectedRoomTitles[roomTitle] == true,
		arena.Id .. " has an invalid room title"
	)
	expectedRoomTitles[roomTitle] = nil
	expect(
		arena.Model:GetAttribute("PitchStyle") == config.World.FieldStyle,
		arena.Id .. " pitch style does not match Config"
	)
	expect(arena.Model:GetAttribute("ArenaState") == "Free", arena.Id .. " must start Free")
	expect(arena.Model:GetAttribute("WaitingCount") == 0, arena.Id .. " has stale waiting state")
	expectConfiguredBall(arena.Ball, arena.Id .. " ball")
	expect(
		(arena.Ball.Position - arena.BallSpawn.Position).Magnitude < 1e-4,
		arena.Id .. " ball does not start at its radius-aware spawn"
	)
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
	local court = arena.Model:FindFirstChild("Court")
	expect(court ~= nil and court:IsA("BasePart"), arena.Id .. " court is missing")
	local pitch = court :: BasePart
	expect(pitch.Material == Enum.Material.Grass, arena.Id .. " court must use natural grass")
	expect(
		pitch.Color.G > pitch.Color.R * 1.6 and pitch.Color.G > pitch.Color.B * 1.5,
		arena.Id .. " court is not a natural readable green"
	)
	local pitchProperties = pitch.CustomPhysicalProperties
	expect(pitchProperties ~= nil, arena.Id .. " court must define consistent physical properties")
	expect(
		math.abs((pitchProperties :: PhysicalProperties).Friction - 0.55) < 1e-4,
		arena.Id .. " court friction differs from the natural-pitch contract"
	)
	local pitchFinish = arena.Model:FindFirstChild("PitchFinish")
	expect(pitchFinish ~= nil and pitchFinish:IsA("Model"), arena.Id .. " pitch finish missing")
	for _, stripe in (pitchFinish :: Model):GetChildren() do
		expect(
			stripe:IsA("BasePart") and stripe.Material == Enum.Material.Grass,
			arena.Id .. " mowing stripe must use grass"
		)
	end
	expect(arena.Model:FindFirstChild("LeftTouchLine") ~= nil, arena.Id .. " touch line missing")
	expect(arena.Model:FindFirstChild("HomePenaltyLine") ~= nil, arena.Id .. " penalty box missing")
	for _, goalName in { "HomeGoalFrame", "AwayGoalFrame" } do
		local goalFrame = arena.Model:FindFirstChild(goalName)
		expect(
			goalFrame ~= nil and goalFrame:IsA("Model"),
			arena.Id .. " " .. goalName .. " missing"
		)
		local crossbar = goalFrame:FindFirstChild("Crossbar")
		local teamAccent = goalFrame:FindFirstChild("TeamAccent")
		expect(
			crossbar ~= nil
				and crossbar:IsA("BasePart")
				and crossbar.Material == Enum.Material.Metal
				and crossbar.Color == Color3.fromRGB(250, 252, 255),
			arena.Id .. " " .. goalName .. " does not use a readable football frame"
		)
		expect(teamAccent ~= nil and teamAccent:IsA("BasePart"), arena.Id .. " goal accent missing")
	end
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
		if descendant:IsA("WeldConstraint") then
			local panel = descendant.Parent
			expect(
				descendant.Name == "PanelWeld"
					and panel ~= nil
					and panel:GetAttribute("BallVisualPanel") == true
					and descendant.Part0 == arena.Ball
					and descendant.Part1 == panel,
				arena.Id .. " contains a non-visual ball weld"
			)
		else
			expect(
				not descendant:IsA("Weld") and not descendant:IsA("Motor6D"),
				arena.Id .. " ball contains a gameplay weld"
			)
		end
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
for _, descendant in world:GetDescendants() do
	if descendant:IsA("BasePart") then
		expect(
			descendant.Material ~= Enum.Material.Neon,
			descendant:GetFullName() .. " still uses Neon"
		)
	end
end
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
	local rollTorque = arena.Ball:FindFirstChild("PannaRollTorque")
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
		arena.Ball:GetAttribute("ControlModel") == "PhysicalForce",
		arena.Id .. " physical control identity is missing"
	)
	expect(
		controlAttachment ~= nil and controlAttachment:IsA("Attachment"),
		arena.Id .. " runtime control attachment missing"
	)
	expect(
		controlForce ~= nil and controlForce:IsA("VectorForce"),
		arena.Id .. " runtime control force missing"
	)
	expect(
		rollTorque ~= nil and rollTorque:IsA("Torque"),
		arena.Id .. " runtime roll torque missing"
	)
	local resolvedForce = controlForce :: VectorForce
	local resolvedTorque = rollTorque :: Torque
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
	expect(
		not resolvedForce.Enabled,
		arena.Id .. " physical control force must start disabled in Reset"
	)
	expect(
		resolvedTorque.Attachment0 == controlAttachment
			and resolvedTorque.RelativeTo == Enum.ActuatorRelativeTo.World
			and resolvedTorque.Torque.Magnitude < 1e-4
			and not resolvedTorque.Enabled,
		arena.Id .. " physical roll torque must start disabled in Reset"
	)
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
	expect(state.controlTorque == resolvedTorque, arena.Id .. " runtime state lost roll torque")
	expect(state.controlDirection == nil, arena.Id .. " runtime state kept stale control direction")
	expect(state.trail == resolvedTrail, arena.Id .. " runtime state lost speed trail")
	expect(state.mode == "Reset", arena.Id .. " runtime state must start Reset")
end

do
	local state = ballService.states[arenaList[1].Id]
	local ball = state.arena.Ball
	state.groundPoint = ball.Position
		- Vector3.new(
			0,
			config.Ball.Radius
				+ config.Ball.Dribble.HeightOffset
				+ config.Ball.Dribble.MaximumAirControlHeight
				+ 1,
			0
		)
	expect(
		ballServiceModule._controlGraceSeconds(ballService, state)
			>= config.Ball.Capture.AirSettleGraceSeconds,
		"high physical first touch did not receive settle grace"
	)
	state.groundPoint = nil
	local character = Instance.new("Model")
	character.Name = "PhysicalBallSmokeCharacter"
	local humanoid = Instance.new("Humanoid")
	humanoid.Parent = character
	local root = Instance.new("Part")
	root.Name = "HumanoidRootPart"
	root.Size = Vector3.new(2, 2, 1)
	root.Anchored = true
	root.CanCollide = false
	root.CFrame = CFrame.lookAt(
		ball.Position + Vector3.new(0, 1.75, 4),
		ball.Position + Vector3.new(0, 1.75, 0)
	)
	root.Parent = character
	local owner: any = { UserId = 987654, Character = character }
	root.AssemblyLinearVelocity = Vector3.new(1_000, 0, 0)
	local trustedCarrier =
		ballServiceModule._trustedCarrierVelocity(ballService, owner, root, os.clock())
	expect(
		ballMath.IsFiniteVector3(trustedCarrier)
			and trustedCarrier.Magnitude <= config.Security.Movement.MaximumCarrierSpeed + 1e-4,
		"carrier velocity reached ball physics without a finite server cap"
	)
	root.AssemblyLinearVelocity = Vector3.zero
	local before = ball.CFrame
	ballServiceModule._setBallMode(ballService, state, "Controlled", owner, "PhysicalSmoke")
	expect(not ball.Anchored, "Controlled physically anchored the ball")
	expect(state.controlForce.Enabled, "Controlled did not enable physical drive force")
	expect(state.controlTorque.Enabled, "Controlled did not enable physical roll torque")
	expect(ball.CFrame == before, "Controlled teleported the physical ball")
	-- RunScript does not advance physics, so seed a finite tangent velocity only
	-- inside the test harness to exercise the production Torque calculation.
	ball.AssemblyLinearVelocity = Vector3.new(4, 0, 0)
	ballServiceModule._updateGround(ballService, state)
	local beforeDribble = ball.CFrame
	ballServiceModule._dribble(ballService, state, 1 / 60, os.clock())
	expect(
		state.mode == "Controlled" and state.owner == owner,
		"physical dribble lost valid control"
	)
	expect(ball.CFrame == beforeDribble and not ball.Anchored, "physical dribble snapped the ball")
	expect(
		Vector3.new(state.controlForce.Force.X, 0, state.controlForce.Force.Z).Magnitude > 0.01,
		"physical dribble produced no planar drive force"
	)
	expect(state.grounded, "physical dribble did not detect the arena surface")
	expect(state.controlTorque.Torque.Magnitude > 0.01, "physical dribble produced no roll torque")
	expect(not state.controlDampingPending, "physical first-touch damping was not consumed")
	ballServiceModule._setBallMode(ballService, state, "Free", nil, "PhysicalReleaseSmoke")
	expect(not ball.Anchored, "Free left the ball anchored")
	expect(
		not state.controlForce.Enabled and state.controlForce.Force.Magnitude < 1e-4,
		"physical drive force survived release"
	)
	expect(
		not state.controlTorque.Enabled and state.controlTorque.Torque.Magnitude < 1e-4,
		"physical roll torque survived release"
	)
	ballService.charges[owner] = {
		action = "Kick",
		startedAt = 0,
		expiresAt = 0,
		matchId = "ChargeExpirySmoke",
		arenaId = state.arena.Id,
		revision = state.revision,
		buffered = false,
	}
	ballServiceModule._stepCharges(ballService, os.clock())
	expect(ballService.charges[owner] == nil, "expired server charge survived its safety timeout")
	state.controlForce.Enabled = true
	state.controlForce.Force = Vector3.new(10, 0, 0)
	state.controlTorque.Enabled = true
	state.controlTorque.Torque = Vector3.new(0, 0, 10)
	ball.Anchored = true
	ballServiceModule._setBallMode(ballService, state, "Free", nil, nil)
	expect(
		not state.controlForce.Enabled
			and not state.controlTorque.Enabled
			and not ball.Anchored
			and state.controlForce.Force.Magnitude < 1e-4
			and state.controlTorque.Torque.Magnitude < 1e-4,
		"same-mode reconciliation left physical actuators active"
	)

	ball.AssemblyLinearVelocity = Vector3.new(config.Ball.Trail.EnabledSpeed + 1, 0, 0)
	state.grounded = false
	ballServiceModule._setBallMode(ballService, state, "Free", nil, "TrailFreeSmoke")
	ballServiceModule._enforceBallLimits(ballService, state)
	expect(not state.trail.Enabled, "high-speed Free ball enabled the flight-only trail")
	ballServiceModule._setBallMode(ballService, state, "Shot", nil, "TrailShotSmoke")
	ballServiceModule._enforceBallLimits(ballService, state)
	expect(state.trail.Enabled, "airborne high-speed Shot did not enable the trail")
	ball.AssemblyLinearVelocity =
		Vector3.new((config.Ball.Trail.EnabledSpeed + config.Ball.Trail.DisabledSpeed) * 0.5, 0, 0)
	ballServiceModule._enforceBallLimits(ballService, state)
	expect(state.trail.Enabled, "trail hysteresis disabled inside its speed band")
	ball.AssemblyLinearVelocity =
		Vector3.new(math.max(0, config.Ball.Trail.DisabledSpeed - 1), 0, 0)
	ballServiceModule._enforceBallLimits(ballService, state)
	expect(not state.trail.Enabled, "trail stayed enabled below its disable threshold")
	ball.AssemblyLinearVelocity = Vector3.new(config.Ball.Trail.EnabledSpeed + 1, 0, 0)
	state.grounded = true
	ballServiceModule._enforceBallLimits(ballService, state)
	expect(not state.trail.Enabled, "grounded fast ball enabled the plate-like trail")

	state.modeUntil = 0
	state.previousGrounded = true
	ballServiceModule._stepMode(ballService, state, os.clock())
	expect(state.mode == "Free", "expired grounded Shot incorrectly transitioned to Flight")
	ball.AssemblyLinearVelocity = Vector3.zero
	state.grounded = false
	ballServiceModule._setBallMode(ballService, state, "Controlled", owner, "LaunchSmoke")
	expect(
		not ballServiceModule._launch(
			ballService,
			state,
			owner,
			"InvalidLaunchSmoke",
			Vector3.new(math.huge, 0, 0),
			Vector3.zero,
			owner,
			0.2,
			0.1
		),
		"physical launch accepted a non-finite target velocity"
	)
	local launched = ballServiceModule._launch(
		ballService,
		state,
		owner,
		"Kick",
		Vector3.new(30, 4, 0),
		Vector3.new(0, 3, 8),
		owner,
		0.2,
		0.1
	)
	expect(launched, "physical launch rejected a finite impulse")
	expect(state.mode == "Shot" and not ball.Anchored, "physical launch did not enter Shot")
	expect(
		not state.controlForce.Enabled and not state.controlTorque.Enabled,
		"physical launch kept dribble actuators enabled"
	)
	expect(ball:GetNetworkOwner() == nil, "physical launch transferred network ownership")
	-- Edit-mode RunScript does not advance physics, so impulse response itself is
	-- covered by the source validator and requires Play/Local Server simulation.
	ballServiceModule._applySpinPhysics(ballService, state, 0.05)
	ballServiceModule._setBallMode(ballService, state, "Reset", nil, "Reset")
	arenas:ResetBall(state.arena)
	character:Destroy()
end

local function newMatchHarnessPlayer(name: string, userId: number): (any, Humanoid, Model)
	local character = Instance.new("Model")
	character.Name = name .. "Character"
	local humanoid = Instance.new("Humanoid")
	humanoid.WalkSpeed = 18
	humanoid.JumpHeight = 7.2
	humanoid.JumpPower = 50
	humanoid.Parent = character
	local attributes: { [string]: any } = {}
	local player: any = {
		Name = name,
		DisplayName = name,
		UserId = userId,
		Parent = Workspace,
		Character = character,
	}
	function player:SetAttribute(attributeName: string, value: any)
		attributes[attributeName] = value
	end
	function player:GetAttribute(attributeName: string): any
		return attributes[attributeName]
	end
	return player, humanoid, character
end

for cycle = 1, 3 do
	local home, homeHumanoid, homeCharacter =
		newMatchHarnessPlayer("CycleHome" .. cycle, 10_000 + cycle)
	local away, awayHumanoid, awayCharacter =
		newMatchHarnessPlayer("CycleAway" .. cycle, 20_000 + cycle)
	local arena: any = { Id = "CycleArena" .. cycle }
	local match: any = {
		Id = "CycleMatch" .. cycle,
		Revision = cycle,
		Arena = arena,
		Home = home,
		Away = away,
		RematchVotes = {},
		VisualRevision = 0,
	}
	local detachCount = 0
	local releaseCount = 0
	local returnCount = 0
	local stateClearCount = 0
	local effectCount = 0
	local playerActionEffects: { any } = {}
	local service: any = {
		_setControlsLocked = matchServiceModule._setControlsLocked,
		_effect = matchServiceModule._effect,
		matches = { [match.Id] = match },
		goalPositions = { [match.Id] = Vector3.zero },
		byPlayer = { [home] = match, [away] = match },
		ballService = {
			DetachMatch = function(_self: any, detachedMatch: any)
				expect(detachedMatch == match, "cleanup detached the wrong match")
				detachCount += 1
			end,
		},
		arenas = {
			Release = function(_self: any, releasedArena: any)
				expect(releasedArena == arena, "cleanup released the wrong arena")
				releaseCount += 1
			end,
			ReturnToStreet = function(_self: any, returnedArena: any, returnedPlayer: any)
				expect(returnedArena == arena, "cleanup returned through the wrong arena")
				expect(
					returnedPlayer == home or returnedPlayer == away,
					"cleanup returned a stranger"
				)
				returnCount += 1
			end,
		},
		remotes = {
			Effect = {
				FireClient = function(_self: any, target: any, payload: any)
					expect(target == home or target == away, "effect notified a stranger")
					expect(payload.matchId == match.Id, "match effect was not scoped")
					expect(payload.arenaId == arena.Id, "arena effect was not scoped")
					expect(
						payload.matchRevision == match.Revision,
						"effect revision was not scoped"
					)
					effectCount += 1
					if payload.kind == "PlayerAction" then
						table.insert(playerActionEffects, payload)
					end
				end,
			},
			StateUpdate = {
				FireClient = function(_self: any, target: any, payload: any)
					expect(target == home or target == away, "cleanup notified a stranger")
					expect(payload.match == false, "cleanup did not clear the match snapshot")
					expect(
						payload.matchRevision == match.Revision,
						"cleanup did not preserve the match revision"
					)
					stateClearCount += 1
				end,
			},
		},
		onRematchReady = nil,
		onArenaReleased = nil,
	}

	local unscopedEffect = { kind = "Message" }
	matchServiceModule._effect(service, match, unscopedEffect)
	expect(effectCount == 2, "match effect did not reach both participants")
	expect(unscopedEffect.matchId == nil, "effect scoping mutated the caller payload")
	matchServiceModule.BroadcastPlayerAction(service, home, "Kick", "Normal", 4)
	expect(effectCount == 4, "player action cue did not reach both match participants")
	expect(#playerActionEffects == 2, "player action cue recipient count is invalid")
	for _, cue in playerActionEffects do
		expect(cue.kind == "PlayerAction", "visual cue kind is invalid")
		expect(cue.actorUserId == home.UserId, "visual cue actor is invalid")
		expect(cue.action == "Kick" and cue.mode == "Normal", "visual cue action data is invalid")
		expect(cue.lateral == 1, "visual cue lateral input was not clamped")
		expect(cue.visualRevision == 1, "first visual cue revision is invalid")
		expect(
			type(cue.serverTime) == "number" and cue.serverTime == cue.serverTime,
			"visual cue server time is invalid"
		)
	end
	table.clear(playerActionEffects)
	matchServiceModule.BroadcastPlayerAction(service, away, "Shield", "Stop", -0.4)
	expect(effectCount == 6 and #playerActionEffects == 2, "second visual cue was not broadcast")
	for _, cue in playerActionEffects do
		expect(
			cue.actorUserId == away.UserId
				and cue.action == "Shield"
				and cue.mode == "Stop"
				and math.abs(cue.lateral + 0.4) < 1e-4
				and cue.visualRevision == 2,
			"visual cue revision or payload did not advance monotonically"
		)
	end
	matchServiceModule._setControlsLocked(service, match, true)
	expect(home:GetAttribute("ControlsLocked") == true, "home did not lock before cleanup")
	expect(away:GetAttribute("ControlsLocked") == true, "away did not lock before cleanup")
	expect(homeHumanoid.WalkSpeed == 0 and awayHumanoid.WalkSpeed == 0, "result lock kept movement")

	matchServiceModule._cleanup(service, match)
	expect(home:GetAttribute("ControlsLocked") == false, "home stayed locked after cleanup")
	expect(away:GetAttribute("ControlsLocked") == false, "away stayed locked after cleanup")
	for _, humanoid in { homeHumanoid, awayHumanoid } do
		expect(humanoid.WalkSpeed == 18, "cleanup did not restore WalkSpeed")
		expect(math.abs(humanoid.JumpHeight - 7.2) < 1e-4, "cleanup did not restore JumpHeight")
		expect(humanoid.JumpPower == 50, "cleanup did not restore JumpPower")
	end
	expect(home:GetAttribute("InMatch") == false, "home kept InMatch after cleanup")
	expect(away:GetAttribute("InMatch") == false, "away kept InMatch after cleanup")
	expect(home:GetAttribute("MatchId") == "", "home kept MatchId after cleanup")
	expect(away:GetAttribute("MatchId") == "", "away kept MatchId after cleanup")
	expect(service.matches[match.Id] == nil, "cleanup kept match registry entry")
	expect(
		service.byPlayer[home] == nil and service.byPlayer[away] == nil,
		"cleanup kept player registry"
	)
	expect(detachCount == 1 and releaseCount == 1, "cleanup did not release runtime exactly once")
	expect(
		returnCount == 2 and stateClearCount == 2,
		"cleanup did not restore both players exactly once"
	)
	homeCharacter:Destroy()
	awayCharacter:Destroy()
end

local remotes = remoteRegistry.Create(net)
expect(remotes.ActionRequest:IsA("RemoteEvent"), "ActionRequest remote missing")
expect(remotes.ActionFeedback:IsA("RemoteEvent"), "ActionFeedback remote missing")
expect(remotes.QueueRequest:IsA("RemoteEvent"), "QueueRequest remote missing")
expect(remotes.StateUpdate:IsA("RemoteEvent"), "StateUpdate remote missing")
expect(remotes.Effect:IsA("RemoteEvent"), "Effect remote missing")
expect(remotes.GetSnapshot:IsA("RemoteFunction"), "GetSnapshot remote missing")

print(string.format("PANNA_STUDIO_SMOKE_OK version=%s arenas=%d", config.Version, #arenaList))
