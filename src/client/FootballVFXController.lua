--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local Workspace = game:GetService("Workspace")

local COLORS = table.freeze({
	Cyan = Color3.fromRGB(35, 224, 255),
	Lime = Color3.fromRGB(92, 235, 128),
	Pink = Color3.fromRGB(255, 70, 142),
	Yellow = Color3.fromRGB(255, 218, 65),
	Orange = Color3.fromRGB(255, 146, 53),
	White = Color3.fromRGB(244, 250, 255),
})

local DEFAULT_SETTINGS = table.freeze({
	Enabled = true,
	MaximumTransientParts = 56,
	AimGuide = table.freeze({
		IdleLength = 7.5,
		ChargedLength = 13.5,
		Width = 0.13,
		ChargedWidth = 0.22,
		TrajectoryDots = 8,
	}),
	BallDirection = table.freeze({
		MinimumSpeed = 14,
		MinimumLength = 4.5,
		MaximumLength = 13,
		SpeedToLength = 0.14,
		Width = 0.11,
	}),
	Impact = table.freeze({
		ShortLifetime = 0.28,
		Lifetime = 0.42,
		CelebrationLifetime = 0.72,
	}),
})

local DEFAULT_BALL = table.freeze({
	Radius = 1.15,
	Shot = table.freeze({
		Types = table.freeze({
			Low = table.freeze({
				SpeedMinimum = 34,
				SpeedMaximum = 78,
				LiftMinimum = 2.4,
				LiftMaximum = 6,
			}),
			Normal = table.freeze({
				SpeedMinimum = 38,
				SpeedMaximum = 84,
				LiftMinimum = 9,
				LiftMaximum = 27,
			}),
			Chip = table.freeze({
				SpeedMinimum = 30,
				SpeedMaximum = 60,
				LiftMinimum = 26,
				LiftMaximum = 49,
			}),
		}),
	}),
	Pass = table.freeze({
		SpeedMinimum = 24,
		SpeedMaximum = 56,
		LiftMinimum = 0.4,
		LiftMaximum = 1.8,
	}),
})

type GuideRig = {
	Folder: Folder,
	StartNode: Part,
	EndNode: Part,
	LeftNode: Part,
	RightNode: Part,
	Shaft: Beam,
	LeftHead: Beam,
	RightHead: Beam,
	Marker: Part,
	Dots: { Part },
}

type ControllerFields = {
	player: Player,
	folder: Folder,
	aimRig: GuideRig,
	motionRig: GuideRig,
	settings: any,
	ballConfig: any,
	transients: { Instance },
	shieldHighlights: { [number]: Highlight },
	shieldTokens: { [number]: number },
	currentBall: BasePart?,
	destroyed: boolean,
}

local FootballVFXController = {}
FootballVFXController.__index = FootballVFXController

export type FootballVFXController = typeof(setmetatable(
	{} :: ControllerFields,
	FootballVFXController
))

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function positiveNumber(value: any, fallback: number): number
	return if finiteNumber(value) and value >= 0 then value else fallback
end

local function safeDirection(value: Vector3): Vector3?
	if
		typeof(value) ~= "Vector3"
		or not finiteNumber(value.X)
		or not finiteNumber(value.Y)
		or not finiteNumber(value.Z)
	then
		return nil
	end
	local horizontal = Vector3.new(value.X, 0, value.Z)
	return if horizontal.Magnitude > 0.05 then horizontal.Unit else nil
end

local function actionColor(action: string, mode: string): Color3
	if action == "Pass" or action == "Trap" then
		return COLORS.Lime
	elseif action == "Skill" or action == "Panna" then
		return COLORS.Pink
	elseif action == "Tackle" then
		return if mode == "Blocked" then COLORS.Cyan else COLORS.Orange
	elseif mode == "Chip" then
		return COLORS.Yellow
	elseif mode == "Low" then
		return COLORS.Cyan
	end
	return COLORS.White
end

local function loadConfiguration(): (any, any)
	local shared = ReplicatedStorage:FindFirstChild("PannaShared")
	local configModule = if shared then shared:FindFirstChild("Config") else nil
	if not configModule or not configModule:IsA("ModuleScript") then
		return DEFAULT_SETTINGS, DEFAULT_BALL
	end
	local success, config = pcall(require, configModule)
	if not success or typeof(config) ~= "table" then
		return DEFAULT_SETTINGS, DEFAULT_BALL
	end
	local visualEffects = if typeof(config.VisualEffects) == "table"
		then config.VisualEffects
		else DEFAULT_SETTINGS
	local ball = if typeof(config.Ball) == "table" then config.Ball else DEFAULT_BALL
	return visualEffects, ball
end

local function createNode(parent: Instance, name: string): (Part, Attachment)
	local node = Instance.new("Part")
	node.Name = name
	node.Size = Vector3.new(0.05, 0.05, 0.05)
	node.Transparency = 1
	node.Anchored = true
	node.CanCollide = false
	node.CanTouch = false
	node.CanQuery = false
	node.CastShadow = false
	node.Parent = parent
	local attachment = Instance.new("Attachment")
	attachment.Name = "GuideAttachment"
	attachment.Parent = node
	return node, attachment
end

local function createBeam(
	parent: Instance,
	name: string,
	first: Attachment,
	second: Attachment,
	width: number
): Beam
	local beam = Instance.new("Beam")
	beam.Name = name
	beam.Attachment0 = first
	beam.Attachment1 = second
	beam.FaceCamera = true
	beam.LightEmission = 0.72
	beam.LightInfluence = 0
	beam.Width0 = width
	beam.Width1 = width
	beam.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.2),
		NumberSequenceKeypoint.new(1, 0.06),
	})
	beam.Enabled = false
	beam.Parent = parent
	return beam
end

local function createGuide(parent: Instance, name: string, dotCount: number): GuideRig
	local folder = Instance.new("Folder")
	folder.Name = name
	folder.Parent = parent
	local startNode, startAttachment = createNode(folder, "Start")
	local endNode, endAttachment = createNode(folder, "End")
	local leftNode, leftAttachment = createNode(folder, "ArrowLeft")
	local rightNode, rightAttachment = createNode(folder, "ArrowRight")
	local shaft = createBeam(folder, "Shaft", startAttachment, endAttachment, 0.12)
	local leftHead = createBeam(folder, "LeftHead", endAttachment, leftAttachment, 0.12)
	local rightHead = createBeam(folder, "RightHead", endAttachment, rightAttachment, 0.12)

	local marker = Instance.new("Part")
	marker.Name = "TargetMarker"
	marker.Shape = Enum.PartType.Ball
	marker.Size = Vector3.new(0.32, 0.32, 0.32)
	marker.Material = Enum.Material.Neon
	marker.Transparency = 1
	marker.Anchored = true
	marker.CanCollide = false
	marker.CanTouch = false
	marker.CanQuery = false
	marker.CastShadow = false
	marker.Parent = folder

	local dots: { Part } = {}
	for index = 1, dotCount do
		local dot = Instance.new("Part")
		dot.Name = string.format("TrajectoryDot_%02d", index)
		dot.Shape = Enum.PartType.Ball
		dot.Size = Vector3.new(0.22, 0.22, 0.22)
		dot.Material = Enum.Material.Neon
		dot.Transparency = 1
		dot.Anchored = true
		dot.CanCollide = false
		dot.CanTouch = false
		dot.CanQuery = false
		dot.CastShadow = false
		dot.Parent = folder
		table.insert(dots, dot)
	end

	return {
		Folder = folder,
		StartNode = startNode,
		EndNode = endNode,
		LeftNode = leftNode,
		RightNode = rightNode,
		Shaft = shaft,
		LeftHead = leftHead,
		RightHead = rightHead,
		Marker = marker,
		Dots = dots,
	}
end

local function setGuideVisible(rig: GuideRig, visible: boolean)
	rig.Shaft.Enabled = visible
	rig.LeftHead.Enabled = visible
	rig.RightHead.Enabled = visible
	rig.Marker.Transparency = if visible then 0.18 else 1
	if not visible then
		for _, dot in rig.Dots do
			dot.Transparency = 1
		end
	end
end

local function updateGuide(
	rig: GuideRig,
	startPosition: Vector3,
	endPosition: Vector3,
	color: Color3,
	width: number,
	pulse: number
)
	local travel = endPosition - startPosition
	if travel.Magnitude < 0.1 then
		setGuideVisible(rig, false)
		return
	end
	local horizontal = safeDirection(travel) or Vector3.zAxis
	local back = -horizontal
	local left = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(29)):VectorToWorldSpace(back)
	local right = CFrame.fromAxisAngle(Vector3.yAxis, math.rad(-29)):VectorToWorldSpace(back)
	local headLength = math.clamp(travel.Magnitude * 0.18, 0.85, 1.45)
	rig.StartNode.Position = startPosition
	rig.EndNode.Position = endPosition
	rig.LeftNode.Position = endPosition + left * headLength
	rig.RightNode.Position = endPosition + right * headLength
	rig.Marker.Position = endPosition
	rig.Marker.Color = color
	rig.Marker.Size = Vector3.one * (0.28 + pulse * 0.12)
	for _, beam in { rig.Shaft, rig.LeftHead, rig.RightHead } do
		beam.Color = ColorSequence.new(color)
		beam.Width0 = width
		beam.Width1 = width * 0.78
	end
	setGuideVisible(rig, true)
end

local function projectileProfile(
	ballConfig: any,
	action: string,
	mode: string,
	power: number
): (number, number)
	local safePower = math.clamp(if finiteNumber(power) then power else 0, 0, 1)
	if action == "Pass" then
		local pass = if typeof(ballConfig.Pass) == "table"
			then ballConfig.Pass
			else DEFAULT_BALL.Pass
		local minimumSpeed = positiveNumber(pass.SpeedMinimum, DEFAULT_BALL.Pass.SpeedMinimum)
		local maximumSpeed = math.max(
			minimumSpeed,
			positiveNumber(pass.SpeedMaximum, DEFAULT_BALL.Pass.SpeedMaximum)
		)
		local minimumLift = positiveNumber(pass.LiftMinimum, DEFAULT_BALL.Pass.LiftMinimum)
		local maximumLift =
			math.max(minimumLift, positiveNumber(pass.LiftMaximum, DEFAULT_BALL.Pass.LiftMaximum))
		return minimumSpeed + (maximumSpeed - minimumSpeed) * safePower,
			minimumLift + (maximumLift - minimumLift) * safePower
	end
	local shot = if typeof(ballConfig.Shot) == "table" then ballConfig.Shot else DEFAULT_BALL.Shot
	local types = if typeof(shot.Types) == "table" then shot.Types else DEFAULT_BALL.Shot.Types
	local resolvedMode = if mode == "Low" or mode == "Chip" then mode else "Normal"
	local profile = if typeof(types[resolvedMode]) == "table"
		then types[resolvedMode]
		else DEFAULT_BALL.Shot.Types[resolvedMode]
	local fallback = DEFAULT_BALL.Shot.Types[resolvedMode]
	local minimumSpeed = positiveNumber(profile.SpeedMinimum, fallback.SpeedMinimum)
	local maximumSpeed =
		math.max(minimumSpeed, positiveNumber(profile.SpeedMaximum, fallback.SpeedMaximum))
	local minimumLift = positiveNumber(profile.LiftMinimum, fallback.LiftMinimum)
	local maximumLift =
		math.max(minimumLift, positiveNumber(profile.LiftMaximum, fallback.LiftMaximum))
	return minimumSpeed + (maximumSpeed - minimumSpeed) * safePower,
		minimumLift + (maximumLift - minimumLift) * safePower
end

function FootballVFXController.GetPalette(): { [string]: Color3 }
	return COLORS
end

function FootballVFXController.new(player: Player): FootballVFXController
	local settings, ballConfig = loadConfiguration()
	local existing = Workspace:FindFirstChild("PannaLocalVFX_" .. tostring(player.UserId))
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "PannaLocalVFX_" .. tostring(player.UserId)
	folder:SetAttribute("LocalOnlyVFX", true)
	folder.Parent = Workspace
	local aimGuide = if typeof(settings.AimGuide) == "table"
		then settings.AimGuide
		else DEFAULT_SETTINGS.AimGuide
	local dotCount = math.clamp(math.floor(positiveNumber(aimGuide.TrajectoryDots, 8)), 4, 12)
	local self = setmetatable({
		player = player,
		folder = folder,
		aimRig = createGuide(folder, "AimGuide", dotCount),
		motionRig = createGuide(folder, "BallDirection", 0),
		settings = settings,
		ballConfig = ballConfig,
		transients = {},
		shieldHighlights = {},
		shieldTokens = {},
		currentBall = nil,
		destroyed = false,
	}, FootballVFXController) :: FootballVFXController
	return self
end

function FootballVFXController._groundHeight(
	self: FootballVFXController,
	position: Vector3,
	ball: BasePart
): number
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local exclusions: { Instance } = { self.folder, ball }
	if self.player.Character then
		table.insert(exclusions, self.player.Character)
	end
	params.FilterDescendantsInstances = exclusions
	params.IgnoreWater = true
	params.RespectCanCollide = true
	local result = Workspace:Raycast(position + Vector3.yAxis * 4, Vector3.yAxis * -12, params)
	if result then
		return result.Position.Y + 0.08
	end
	return position.Y - ball.Size.Y * 0.5 + 0.08
end

function FootballVFXController._updateTrajectory(
	self: FootballVFXController,
	ball: BasePart,
	direction: Vector3,
	action: string,
	mode: string,
	power: number,
	color: Color3,
	charging: boolean
)
	local dots = self.aimRig.Dots
	if not charging then
		for _, dot in dots do
			dot.Transparency = 1
		end
		return
	end
	local speed, lift = projectileProfile(self.ballConfig, action, mode, power)
	local gravity = math.max(1, Workspace.Gravity)
	local naturalFlight = math.max(0.08, 2 * lift / gravity)
	local previewTime = if action == "Pass" or mode == "Low"
		then math.max(naturalFlight, 0.16 + 0.1 * power)
		else naturalFlight
	previewTime = math.clamp(previewTime, 0.12, 0.58)
	local startPosition = ball.Position + Vector3.yAxis * 0.08
	for index, dot in dots do
		local alpha = index / (#dots + 1)
		local time = previewTime * alpha
		local height = lift * time - 0.5 * gravity * time * time
		dot.Position = startPosition
			+ direction * speed * time
			+ Vector3.yAxis * math.max(0, height)
		dot.Color = color
		dot.Size = Vector3.one * (0.15 + alpha * 0.12)
		dot.Transparency = 0.16 + alpha * 0.48
	end
end

function FootballVFXController.SetAimState(
	self: FootballVFXController,
	ball: BasePart?,
	ballState: string,
	ownerUserId: number,
	direction: Vector3,
	action: string,
	mode: string,
	power: number,
	gameplayActive: boolean,
	charging: boolean
)
	if self.destroyed then
		return
	end
	self.currentBall = if ball and ball.Parent then ball else nil
	local enabled = self.settings.Enabled ~= false
	if not enabled or not gameplayActive or not self.currentBall then
		setGuideVisible(self.aimRig, false)
		setGuideVisible(self.motionRig, false)
		return
	end
	local resolvedBall = self.currentBall :: BasePart
	local planarDirection = safeDirection(direction)
	local showAim = ownerUserId == self.player.UserId
		and string.lower(ballState) == "controlled"
		and planarDirection ~= nil
	if showAim then
		local aim = if typeof(self.settings.AimGuide) == "table"
			then self.settings.AimGuide
			else DEFAULT_SETTINGS.AimGuide
		local idleLength = positiveNumber(aim.IdleLength, DEFAULT_SETTINGS.AimGuide.IdleLength)
		local chargedLength = math.max(
			idleLength,
			positiveNumber(aim.ChargedLength, DEFAULT_SETTINGS.AimGuide.ChargedLength)
		)
		local safePower = math.clamp(if finiteNumber(power) then power else 0, 0, 1)
		local length = idleLength
			+ (chargedLength - idleLength) * (if charging then safePower else 0)
		local baseWidth = positiveNumber(aim.Width, DEFAULT_SETTINGS.AimGuide.Width)
		local chargedWidth = math.max(
			baseWidth,
			positiveNumber(aim.ChargedWidth, DEFAULT_SETTINGS.AimGuide.ChargedWidth)
		)
		local width = baseWidth + (chargedWidth - baseWidth) * (if charging then safePower else 0)
		local groundY = self:_groundHeight(resolvedBall.Position, resolvedBall)
		local startPosition = Vector3.new(resolvedBall.Position.X, groundY, resolvedBall.Position.Z)
		local endPosition = startPosition + (planarDirection :: Vector3) * length
		local color = actionColor(action, mode)
		local pulse = (math.sin(os.clock() * 7) + 1) * 0.5 * (if charging then safePower else 0.2)
		updateGuide(self.aimRig, startPosition, endPosition, color, width, pulse)
		self:_updateTrajectory(
			resolvedBall,
			planarDirection :: Vector3,
			action,
			mode,
			safePower,
			color,
			charging
		)
	else
		setGuideVisible(self.aimRig, false)
	end

	local motion = if typeof(self.settings.BallDirection) == "table"
		then self.settings.BallDirection
		else DEFAULT_SETTINGS.BallDirection
	local velocity = resolvedBall.AssemblyLinearVelocity
	local speed = velocity.Magnitude
	local minimumSpeed =
		positiveNumber(motion.MinimumSpeed, DEFAULT_SETTINGS.BallDirection.MinimumSpeed)
	local showMotion = not showAim and speed >= minimumSpeed
	if showMotion then
		local minimumLength =
			positiveNumber(motion.MinimumLength, DEFAULT_SETTINGS.BallDirection.MinimumLength)
		local maximumLength = math.max(
			minimumLength,
			positiveNumber(motion.MaximumLength, DEFAULT_SETTINGS.BallDirection.MaximumLength)
		)
		local speedToLength =
			positiveNumber(motion.SpeedToLength, DEFAULT_SETTINGS.BallDirection.SpeedToLength)
		local length = math.clamp(speed * speedToLength, minimumLength, maximumLength)
		local startPosition = resolvedBall.Position + velocity.Unit * (resolvedBall.Size.X * 0.52)
		local endPosition = startPosition + velocity.Unit * length
		updateGuide(
			self.motionRig,
			startPosition,
			endPosition,
			COLORS.Cyan,
			positiveNumber(motion.Width, DEFAULT_SETTINGS.BallDirection.Width),
			(math.sin(os.clock() * 10) + 1) * 0.22
		)
	else
		setGuideVisible(self.motionRig, false)
	end
end

function FootballVFXController._track(
	self: FootballVFXController,
	instance: Instance,
	lifetime: number
)
	table.insert(self.transients, instance)
	local maximum = math.clamp(
		math.floor(
			positiveNumber(
				self.settings.MaximumTransientParts,
				DEFAULT_SETTINGS.MaximumTransientParts
			)
		),
		16,
		96
	)
	while #self.transients > maximum do
		local oldest = table.remove(self.transients, 1)
		if oldest and oldest.Parent then
			oldest:Destroy()
		end
	end
	task.delay(math.max(0.05, lifetime) + 0.08, function()
		local index = table.find(self.transients, instance)
		if index then
			table.remove(self.transients, index)
		end
		if instance.Parent then
			instance:Destroy()
		end
	end)
end

function FootballVFXController._makePart(
	self: FootballVFXController,
	name: string,
	color: Color3,
	position: Vector3
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Color = color
	part.Material = Enum.Material.Neon
	part.Anchored = true
	part.CanCollide = false
	part.CanTouch = false
	part.CanQuery = false
	part.CastShadow = false
	part.Position = position
	part.Parent = self.folder
	return part
end

function FootballVFXController._pulse(
	self: FootballVFXController,
	position: Vector3,
	color: Color3,
	scale: number,
	lifetime: number,
	contract: boolean?
)
	local pulse = self:_makePart("ImpactPulse", color, position)
	pulse.Shape = Enum.PartType.Ball
	local startSize = if contract then Vector3.one * scale else Vector3.one * 0.28
	local endSize = if contract then Vector3.one * 0.25 else Vector3.one * scale
	pulse.Size = startSize
	pulse.Transparency = if contract then 0.76 else 0.42
	local tween = TweenService:Create(
		pulse,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ Size = endSize, Transparency = 1 }
	)
	self:_track(pulse, lifetime)
	tween:Play()
end

function FootballVFXController._groundDisc(
	self: FootballVFXController,
	position: Vector3,
	color: Color3,
	scale: number,
	lifetime: number
)
	local disc = self:_makePart("GroundRipple", color, position + Vector3.yAxis * 0.06)
	disc.Shape = Enum.PartType.Cylinder
	disc.Size = Vector3.new(0.045, 0.6, 0.6)
	disc.CFrame = CFrame.new(disc.Position) * CFrame.Angles(0, 0, math.pi * 0.5)
	disc.Transparency = 0.68
	local tween = TweenService:Create(
		disc,
		TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ Size = Vector3.new(0.045, scale, scale), Transparency = 1 }
	)
	self:_track(disc, lifetime)
	tween:Play()
end

function FootballVFXController._streaks(
	self: FootballVFXController,
	position: Vector3,
	direction: Vector3,
	color: Color3,
	count: number,
	lifetime: number
)
	local forward = safeDirection(direction) or Vector3.zAxis
	for index = 1, count do
		local angle = (index - 1) / math.max(1, count) * math.pi * 2
		local offset = Vector3.new(math.cos(angle), 0.18 + (index % 2) * 0.22, math.sin(angle))
		local startPosition = position + offset * 0.55
		local finishPosition = startPosition + forward * (1.6 + index * 0.18) + offset * 0.7
		local streak = self:_makePart("ActionStreak", color, startPosition)
		streak.Size = Vector3.new(0.1, 0.1, 0.9)
		streak.Transparency = 0.18
		streak.CFrame = CFrame.lookAt(startPosition, finishPosition)
		local finishCFrame = CFrame.lookAt(finishPosition, finishPosition + forward)
		local tween = TweenService:Create(
			streak,
			TweenInfo.new(lifetime, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ CFrame = finishCFrame, Transparency = 1, Size = Vector3.new(0.04, 0.04, 1.5) }
		)
		self:_track(streak, lifetime)
		tween:Play()
	end
end

function FootballVFXController._actorRoot(_self: FootballVFXController, userId: number): BasePart?
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

function FootballVFXController._removeShield(self: FootballVFXController, userId: number)
	self.shieldTokens[userId] = (self.shieldTokens[userId] or 0) + 1
	local highlight = self.shieldHighlights[userId]
	self.shieldHighlights[userId] = nil
	if highlight then
		highlight:Destroy()
	end
end

function FootballVFXController._startShield(self: FootballVFXController, userId: number)
	self:_removeShield(userId)
	local player = Players:GetPlayerByUserId(userId)
	local character = if player then player.Character else nil
	if not character then
		return
	end
	local highlight = Instance.new("Highlight")
	highlight.Name = "ShieldReadability"
	highlight.Adornee = character
	highlight.DepthMode = Enum.HighlightDepthMode.Occluded
	highlight.FillColor = COLORS.Cyan
	highlight.FillTransparency = 0.9
	highlight.OutlineColor = COLORS.White
	highlight.OutlineTransparency = 0.18
	highlight.Parent = self.folder
	self.shieldHighlights[userId] = highlight
	local token = (self.shieldTokens[userId] or 0) + 1
	self.shieldTokens[userId] = token
	task.delay(3, function()
		if not self.destroyed and self.shieldTokens[userId] == token then
			self:_removeShield(userId)
		end
	end)
end

function FootballVFXController.ApplyEffect(self: FootballVFXController, effect: any): boolean
	if self.destroyed or typeof(effect) ~= "table" or self.settings.Enabled == false then
		return false
	end
	local kindValue = effect.kind or effect.Kind or effect.type or effect.Type
	local kind = if typeof(kindValue) == "string" then string.lower(kindValue) else ""
	local impact = if typeof(self.settings.Impact) == "table"
		then self.settings.Impact
		else DEFAULT_SETTINGS.Impact
	local shortLifetime =
		positiveNumber(impact.ShortLifetime, DEFAULT_SETTINGS.Impact.ShortLifetime)
	local lifetime = positiveNumber(impact.Lifetime, DEFAULT_SETTINGS.Impact.Lifetime)
	local celebrationLifetime =
		positiveNumber(impact.CelebrationLifetime, DEFAULT_SETTINGS.Impact.CelebrationLifetime)

	if kind == "playeraction" then
		local actorValue = effect.actorUserId or effect.ActorUserId
		local userId = if finiteNumber(actorValue) then math.floor(actorValue) else 0
		local actionValue = effect.action or effect.Action
		local modeValue = effect.mode or effect.Mode
		local action = if typeof(actionValue) == "string" then actionValue else ""
		local mode = if typeof(modeValue) == "string" then modeValue else ""
		if action == "Shield" then
			if mode == "Start" then
				self:_startShield(userId)
			elseif mode == "Stop" or mode == "Cancel" then
				self:_removeShield(userId)
			end
			return true
		elseif action == "Charge" then
			return true
		end
		local root = self:_actorRoot(userId)
		local ball = self.currentBall
		local origin = if ball and ball.Parent
			then ball.Position
			else if root then root.Position + Vector3.new(0, 0.8, 0) else Vector3.zero
		local direction = if root then root.CFrame.LookVector else Vector3.zAxis
		local color = actionColor(action, mode)
		if action == "Kick" then
			self:_pulse(origin, color, if mode == "Chip" then 3.4 else 2.7, lifetime)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, color, 4.6, lifetime)
			self:_streaks(origin, direction, color, 5, shortLifetime)
		elseif action == "Pass" then
			self:_pulse(origin, color, 1.8, shortLifetime)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, color, 3.2, lifetime)
			self:_streaks(origin, direction, color, 3, shortLifetime)
		elseif action == "Trap" then
			self:_pulse(origin, color, 2.6, lifetime, true)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, color, 2.5, lifetime)
		elseif action == "Dash" and root then
			self:_streaks(
				root.Position + Vector3.yAxis,
				-root.CFrame.LookVector,
				color,
				5,
				lifetime
			)
		elseif action == "Feint" then
			self:_pulse(origin, COLORS.Pink, 2.5, lifetime, true)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, color, 3.7, lifetime)
		elseif action == "Tackle" then
			local scale = if mode == "Standing" then 3 else if mode == "Blocked" then 2.5 else 1.8
			self:_pulse(origin, color, scale, lifetime)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, color, scale + 1, lifetime)
		elseif action == "Skill" then
			self:_pulse(origin, COLORS.Pink, 3.8, lifetime)
			self:_groundDisc(origin - Vector3.yAxis * 1.05, COLORS.Pink, 5.2, celebrationLifetime)
			self:_streaks(origin, direction, COLORS.Pink, 6, lifetime)
		else
			return false
		end
		return true
	elseif kind == "goal" or kind == "panna" then
		local ball = self.currentBall
		local root = self:_actorRoot(self.player.UserId)
		local origin = if ball and ball.Parent
			then ball.Position
			else if root then root.Position + Vector3.yAxis else Vector3.zero
		local color = if kind == "panna" then COLORS.Pink else COLORS.Lime
		self:_pulse(origin, color, 5.5, celebrationLifetime)
		self:_groundDisc(origin - Vector3.yAxis, color, 7, celebrationLifetime)
		self:_streaks(origin, Vector3.zAxis, color, 8, celebrationLifetime)
		return true
	end
	return false
end

function FootballVFXController.ResetTransientState(self: FootballVFXController)
	if self.destroyed then
		return
	end
	setGuideVisible(self.aimRig, false)
	setGuideVisible(self.motionRig, false)
	self.currentBall = nil
	for _, transient in self.transients do
		if transient.Parent then
			transient:Destroy()
		end
	end
	table.clear(self.transients)
	local shieldUserIds = {}
	for userId in self.shieldHighlights do
		table.insert(shieldUserIds, userId)
	end
	for _, userId in shieldUserIds do
		self:_removeShield(userId)
	end
end

function FootballVFXController.Destroy(self: FootballVFXController)
	if self.destroyed then
		return
	end
	self:ResetTransientState()
	self.destroyed = true
	if self.folder.Parent then
		self.folder:Destroy()
	end
end

return FootballVFXController
