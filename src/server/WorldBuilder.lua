--!strict

local Lighting = game:GetService("Lighting")
local Workspace = game:GetService("Workspace")

type WorldSettings = {
	RootName: string,
	LobbyOrigin: Vector3,
	LobbySpawn: CFrame,
	ArenaPositions: { CFrame },
	ArenaWidth: number,
	ArenaLength: number,
	FenceHeight: number,
	GoalWidth: number,
	GoalHeight: number,
	GoalDepth: number,
}

type BallSettings = {
	Radius: number,
	Density: number,
	Friction: number,
	Elasticity: number,
}

type Config = {
	World: WorldSettings,
	Ball: BallSettings,
}

local COLORS = table.freeze({
	Asphalt = Color3.fromRGB(22, 25, 34),
	Concrete = Color3.fromRGB(43, 48, 60),
	Cyan = Color3.fromRGB(34, 238, 255),
	DarkGlass = Color3.fromRGB(20, 38, 51),
	Green = Color3.fromRGB(46, 255, 160),
	Orange = Color3.fromRGB(255, 142, 43),
	Pink = Color3.fromRGB(255, 47, 161),
	Purple = Color3.fromRGB(135, 76, 255),
	White = Color3.fromRGB(235, 247, 255),
	Yellow = Color3.fromRGB(255, 226, 82),
})

local LIGHTING_EFFECT_ATTRIBUTE = "PannaWorldBuilderEffect"
local ARENA_COUNT = 2

local WorldBuilder = {}

local function createPart(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3,
	material: Enum.Material
): Part
	local part = Instance.new("Part")
	part.Name = name
	part.Size = size
	part.CFrame = cframe
	part.Color = color
	part.Material = material
	part.Anchored = true
	part.CanCollide = true
	part.CanQuery = true
	part.CanTouch = true
	part.CastShadow = true
	part.TopSurface = Enum.SurfaceType.Smooth
	part.BottomSurface = Enum.SurfaceType.Smooth
	part.Parent = parent
	return part
end

local function createInvisibleMarker(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	canTouch: boolean
): Part
	local marker = createPart(parent, name, size, cframe, COLORS.White, Enum.Material.SmoothPlastic)
	marker.Transparency = 1
	marker.CanCollide = false
	marker.CanQuery = canTouch
	marker.CanTouch = canTouch
	marker.CastShadow = false
	return marker
end

local function createBillboardSign(
	parent: Instance,
	name: string,
	text: string,
	cframe: CFrame,
	color: Color3,
	width: number
): Part
	local backing = createPart(
		parent,
		name,
		Vector3.new(width, 3.8, 0.45),
		cframe,
		COLORS.Asphalt,
		Enum.Material.Metal
	)
	backing.CanCollide = false

	local trim = createPart(
		parent,
		name .. "Trim",
		Vector3.new(width + 0.45, 4.25, 0.18),
		cframe * CFrame.new(0, 0, 0.28),
		color,
		Enum.Material.Neon
	)
	trim.CanCollide = false

	local billboard = Instance.new("BillboardGui")
	billboard.Name = "Label"
	billboard.Adornee = backing
	billboard.AlwaysOnTop = true
	billboard.LightInfluence = 0
	billboard.MaxDistance = 220
	billboard.Size = UDim2.fromOffset(math.max(240, math.floor(width * 29)), 82)
	billboard.Parent = backing

	local label = Instance.new("TextLabel")
	label.Name = "Text"
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.GothamBold
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeColor3 = Color3.new(0, 0, 0)
	label.TextStrokeTransparency = 0.2
	label.Parent = billboard

	return backing
end

local function addPointLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	light.Shadows = true
	light.Parent = part
end

local function createLamp(
	parent: Instance,
	name: string,
	cframe: CFrame,
	color: Color3,
	height: number
)
	createPart(
		parent,
		name .. "Post",
		Vector3.new(0.55, height, 0.55),
		cframe * CFrame.new(0, height * 0.5, 0),
		COLORS.Concrete,
		Enum.Material.Metal
	)

	local lamp = createPart(
		parent,
		name .. "Lamp",
		Vector3.new(2.8, 0.45, 1.25),
		cframe * CFrame.new(0, height, 0),
		color,
		Enum.Material.Neon
	)
	lamp.CanCollide = false
	addPointLight(lamp, color, 46, 1.1)
end

local function createBall(
	parent: Instance,
	name: string,
	cframe: CFrame,
	settings: BallSettings,
	arenaId: string?
): Part
	local diameter = settings.Radius * 2
	local ball = createPart(
		parent,
		name,
		Vector3.new(diameter, diameter, diameter),
		cframe,
		COLORS.White,
		Enum.Material.SmoothPlastic
	)
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = false
	ball.CustomPhysicalProperties =
		PhysicalProperties.new(settings.Density, settings.Friction, settings.Elasticity, 1, 1)
	ball:SetAttribute("OwnerUserId", 0)
	if arenaId then
		ball:SetAttribute("ArenaId", arenaId)
	end
	return ball
end

local function createCourtMarking(
	parent: Instance,
	name: string,
	size: Vector3,
	cframe: CFrame,
	color: Color3
)
	local marking = createPart(parent, name, size, cframe, color, Enum.Material.Neon)
	marking.CanCollide = false
	marking.CanTouch = false
	marking.CanQuery = false
	marking.CastShadow = false
end

local function createCenterCircle(parent: Instance, origin: CFrame, color: Color3)
	local circleModel = Instance.new("Model")
	circleModel.Name = "CenterCircle"
	circleModel.Parent = parent

	local radius = 7
	local segmentCount = 24
	local segmentLength = (2 * math.pi * radius) / segmentCount + 0.06
	for index = 1, segmentCount do
		local angle = ((index - 0.5) / segmentCount) * 2 * math.pi
		local position = Vector3.new(math.cos(angle) * radius, 0.07, math.sin(angle) * radius)
		local tangent = Vector3.new(-math.sin(angle), 0, math.cos(angle))
		createCourtMarking(
			circleModel,
			string.format("Segment_%02d", index),
			Vector3.new(0.14, 0.07, segmentLength),
			origin * CFrame.lookAt(position, position + tangent),
			color
		)
	end
end

local function createGoalFrame(
	parent: Instance,
	origin: CFrame,
	name: string,
	side: number,
	world: WorldSettings,
	color: Color3
)
	local model = Instance.new("Model")
	model.Name = name .. "Frame"
	model.Parent = parent

	local goalLineZ = side * (world.ArenaLength * 0.5)
	local goalCenterZ = goalLineZ + side * (world.GoalDepth * 0.5)
	local backZ = goalLineZ + side * world.GoalDepth
	local postThickness = 0.55

	for _, xDirection in { -1, 1 } do
		createPart(
			model,
			if xDirection < 0 then "LeftPost" else "RightPost",
			Vector3.new(postThickness, world.GoalHeight + 0.4, postThickness),
			origin
				* CFrame.new(
					xDirection * world.GoalWidth * 0.5,
					(world.GoalHeight + 0.4) * 0.5,
					goalLineZ
				),
			color,
			Enum.Material.Neon
		)
	end

	createPart(
		model,
		"Crossbar",
		Vector3.new(world.GoalWidth + postThickness, postThickness, postThickness),
		origin * CFrame.new(0, world.GoalHeight, goalLineZ),
		color,
		Enum.Material.Neon
	)

	local backNet = createPart(
		model,
		"BackNet",
		Vector3.new(world.GoalWidth, world.GoalHeight, 0.2),
		origin * CFrame.new(0, world.GoalHeight * 0.5, backZ),
		color,
		Enum.Material.ForceField
	)
	backNet.Transparency = 0.72

	for _, xDirection in { -1, 1 } do
		local sideNet = createPart(
			model,
			if xDirection < 0 then "LeftNet" else "RightNet",
			Vector3.new(0.2, world.GoalHeight, world.GoalDepth),
			origin
				* CFrame.new(
					xDirection * world.GoalWidth * 0.5,
					world.GoalHeight * 0.5,
					goalCenterZ
				),
			color,
			Enum.Material.ForceField
		)
		sideNet.Transparency = 0.78
	end

	local topNet = createPart(
		model,
		"TopNet",
		Vector3.new(world.GoalWidth, 0.2, world.GoalDepth),
		origin * CFrame.new(0, world.GoalHeight, goalCenterZ),
		color,
		Enum.Material.ForceField
	)
	topNet.Transparency = 0.78

	createPart(
		model,
		"GoalFloor",
		Vector3.new(world.GoalWidth, 0.45, world.GoalDepth),
		origin * CFrame.new(0, -0.2, goalCenterZ),
		COLORS.Asphalt,
		Enum.Material.Asphalt
	)
end

local function createFence(parent: Instance, origin: CFrame, world: WorldSettings)
	local model = Instance.new("Model")
	model.Name = "Fence"
	model.Parent = parent

	local halfWidth = world.ArenaWidth * 0.5
	local halfLength = world.ArenaLength * 0.5
	local panelColor = COLORS.DarkGlass

	for _, xDirection in { -1, 1 } do
		local sidePanel = createPart(
			model,
			if xDirection < 0 then "LeftPanel" else "RightPanel",
			Vector3.new(0.38, world.FenceHeight, world.ArenaLength + 0.7),
			origin * CFrame.new(xDirection * (halfWidth + 0.2), world.FenceHeight * 0.5, 0),
			panelColor,
			Enum.Material.Glass
		)
		sidePanel.Transparency = 0.58

		createPart(
			model,
			if xDirection < 0 then "LeftNeonRail" else "RightNeonRail",
			Vector3.new(0.3, 0.3, world.ArenaLength + 1),
			origin * CFrame.new(xDirection * (halfWidth + 0.4), 0.45, 0),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
	end

	local endSegmentWidth = (world.ArenaWidth - world.GoalWidth) * 0.5
	local endSegmentOffset = world.GoalWidth * 0.5 + endSegmentWidth * 0.5
	for _, zDirection in { -1, 1 } do
		for _, xDirection in { -1, 1 } do
			local endPanel = createPart(
				model,
				string.format("EndPanel_%d_%d", zDirection, xDirection),
				Vector3.new(endSegmentWidth, world.FenceHeight, 0.38),
				origin
					* CFrame.new(
						xDirection * endSegmentOffset,
						world.FenceHeight * 0.5,
						zDirection * (halfLength + 0.2)
					),
				panelColor,
				Enum.Material.Glass
			)
			endPanel.Transparency = 0.58
		end
	end

	local sidePostCount = math.max(2, math.ceil(world.ArenaLength / 12))
	for index = 0, sidePostCount do
		local z = -halfLength + (world.ArenaLength * index / sidePostCount)
		for _, xDirection in { -1, 1 } do
			createPart(
				model,
				string.format("SidePost_%d_%d", index, xDirection),
				Vector3.new(0.5, world.FenceHeight + 0.8, 0.5),
				origin
					* CFrame.new(
						xDirection * (halfWidth + 0.25),
						(world.FenceHeight + 0.8) * 0.5,
						z
					),
				COLORS.Concrete,
				Enum.Material.Metal
			)
		end
	end
end

local function createArena(
	arenasFolder: Folder,
	index: number,
	origin: CFrame,
	world: WorldSettings,
	ballSettings: BallSettings
): Model
	local arenaId = string.format("Arena_%d", index)
	local model = Instance.new("Model")
	model.Name = arenaId
	model:SetAttribute("ArenaId", arenaId)
	model:SetAttribute("Busy", false)
	model:SetAttribute("MatchId", "")
	model.Parent = arenasFolder

	local halfWidth = world.ArenaWidth * 0.5
	local halfLength = world.ArenaLength * 0.5
	local accent = if index % 2 == 1 then COLORS.Cyan else COLORS.Pink

	local floor = createPart(
		model,
		"Court",
		Vector3.new(world.ArenaWidth, 1, world.ArenaLength),
		origin * CFrame.new(0, -0.5, 0),
		COLORS.Asphalt,
		Enum.Material.Asphalt
	)
	model.PrimaryPart = floor

	createCourtMarking(
		model,
		"CenterLine",
		Vector3.new(world.ArenaWidth - 1.2, 0.07, 0.14),
		origin * CFrame.new(0, 0.07, 0),
		COLORS.White
	)
	createCourtMarking(
		model,
		"CenterSpot",
		Vector3.new(0.75, 0.08, 0.75),
		origin * CFrame.new(0, 0.08, 0),
		accent
	)
	createCenterCircle(model, origin, COLORS.White)

	for _, zDirection in { -1, 1 } do
		createCourtMarking(
			model,
			if zDirection < 0 then "AwayGoalLine" else "HomeGoalLine",
			Vector3.new(world.ArenaWidth - 1.2, 0.07, 0.14),
			origin * CFrame.new(0, 0.07, zDirection * (halfLength - 0.6)),
			if zDirection < 0 then COLORS.Pink else COLORS.Cyan
		)
	end

	local homeSpawn = createInvisibleMarker(
		model,
		"HomeSpawn",
		Vector3.new(5, 0.4, 5),
		origin * CFrame.new(0, 0.2, halfLength - 12),
		false
	)
	homeSpawn:SetAttribute("TeamSide", "Home")

	local awaySpawn = createInvisibleMarker(
		model,
		"AwaySpawn",
		Vector3.new(5, 0.4, 5),
		origin * CFrame.new(0, 0.2, -(halfLength - 12)) * CFrame.Angles(0, math.pi, 0),
		false
	)
	awaySpawn:SetAttribute("TeamSide", "Away")

	local ballSpawn = createInvisibleMarker(
		model,
		"BallSpawn",
		Vector3.new(1, 1, 1),
		origin * CFrame.new(0, ballSettings.Radius + 0.15, 0),
		false
	)

	local bounds = createInvisibleMarker(
		model,
		"Bounds",
		Vector3.new(
			world.ArenaWidth,
			world.FenceHeight + 6,
			world.ArenaLength + world.GoalDepth * 2
		),
		origin * CFrame.new(0, (world.FenceHeight + 6) * 0.5, 0),
		false
	)
	bounds:SetAttribute("ArenaId", arenaId)

	-- The trigger describes the clear goal aperture: its bottom is exactly on
	-- the court and its top sits just below the physical crossbar.
	local goalTriggerHeight = world.GoalHeight - 0.2
	local homeGoal = createInvisibleMarker(
		model,
		"HomeGoal",
		Vector3.new(world.GoalWidth - 0.8, goalTriggerHeight, world.GoalDepth),
		origin * CFrame.new(0, goalTriggerHeight * 0.5, halfLength + world.GoalDepth * 0.5),
		true
	)
	homeGoal:SetAttribute("TeamSide", "Home")
	homeGoal:SetAttribute("ArenaId", arenaId)

	local awayGoal = createInvisibleMarker(
		model,
		"AwayGoal",
		Vector3.new(world.GoalWidth - 0.8, goalTriggerHeight, world.GoalDepth),
		origin * CFrame.new(0, goalTriggerHeight * 0.5, -(halfLength + world.GoalDepth * 0.5)),
		true
	)
	awayGoal:SetAttribute("TeamSide", "Away")
	awayGoal:SetAttribute("ArenaId", arenaId)

	createGoalFrame(model, origin, "HomeGoal", 1, world, COLORS.Cyan)
	createGoalFrame(model, origin, "AwayGoal", -1, world, COLORS.Pink)
	createFence(model, origin, world)

	createBall(model, "Ball", ballSpawn.CFrame, ballSettings, arenaId)

	local decor = Instance.new("Model")
	decor.Name = "Floodlights"
	decor.Parent = model
	for _, corner in
		{
			Vector3.new(-halfWidth - 3, 0, -halfLength + 7),
			Vector3.new(halfWidth + 3, 0, -halfLength + 7),
			Vector3.new(-halfWidth - 3, 0, halfLength - 7),
			Vector3.new(halfWidth + 3, 0, halfLength - 7),
		}
	do
		local sideName = string.format("Lamp_%d_%d", math.floor(corner.X), math.floor(corner.Z))
		createLamp(
			decor,
			sideName,
			origin * CFrame.new(corner),
			COLORS.White,
			world.FenceHeight + 6
		)
	end

	createBillboardSign(
		model,
		"ArenaSign",
		string.format("PANNA COURT %02d", index),
		origin * CFrame.new(0, world.FenceHeight + 4, -halfLength - 2),
		accent,
		19
	)

	return model
end

local function createTrainingZone(lobby: Model, origin: CFrame, ballSettings: BallSettings)
	local training = Instance.new("Model")
	training.Name = "TrainingZone"
	training:SetAttribute("ZoneType", "Training")
	training.Parent = lobby

	local zoneOrigin = origin * CFrame.new(36, 0, -3)
	createPart(
		training,
		"TrainingCourt",
		Vector3.new(28, 0.35, 34),
		zoneOrigin * CFrame.new(0, 0.18, 0),
		Color3.fromRGB(28, 48, 48),
		Enum.Material.Asphalt
	)

	for _, xDirection in { -1, 1 } do
		local wall = createPart(
			training,
			if xDirection < 0 then "LeftReboundWall" else "RightReboundWall",
			Vector3.new(0.4, 5, 34),
			zoneOrigin * CFrame.new(xDirection * 14, 2.5, 0),
			COLORS.DarkGlass,
			Enum.Material.Glass
		)
		wall.Transparency = 0.52
	end

	local backWall = createPart(
		training,
		"SkillWall",
		Vector3.new(28, 7, 0.55),
		zoneOrigin * CFrame.new(0, 3.5, -17),
		COLORS.Concrete,
		Enum.Material.Concrete
	)
	backWall:SetAttribute("TrainingTarget", true)

	for targetIndex, targetColor in { COLORS.Cyan, COLORS.Pink, COLORS.Yellow } do
		local x = (targetIndex - 2) * 6
		local target = createPart(
			training,
			string.format("Target_%d", targetIndex),
			Vector3.new(3.8, 3.8, 0.22),
			zoneOrigin * CFrame.new(x, 3.5, -17.35),
			targetColor,
			Enum.Material.Neon
		)
		target.CanCollide = false
		target:SetAttribute("TrainingTarget", true)
	end

	local trainingBallSpawn = createInvisibleMarker(
		training,
		"TrainingBallSpawn",
		Vector3.new(1, 1, 1),
		zoneOrigin * CFrame.new(0, ballSettings.Radius + 0.45, 7),
		false
	)
	local trainingBall =
		createBall(training, "TrainingBall", trainingBallSpawn.CFrame, ballSettings, nil)
	trainingBall:SetAttribute("TrainingBall", true)

	createBillboardSign(
		training,
		"TrainingSign",
		"FREEPLAY  /  SKILL LAB",
		zoneOrigin * CFrame.new(0, 8.5, -16.5),
		COLORS.Green,
		18
	)
end

local function createStreetDecor(lobby: Model, origin: CFrame)
	local decor = Instance.new("Model")
	decor.Name = "StreetDecor"
	decor.Parent = lobby

	local muralWall = createPart(
		decor,
		"MuralWall",
		Vector3.new(29, 10, 1),
		origin * CFrame.new(-38, 5, -22),
		Color3.fromRGB(34, 35, 48),
		Enum.Material.Concrete
	)
	muralWall:SetAttribute("Decorative", true)

	local muralColors = { COLORS.Pink, COLORS.Purple, COLORS.Cyan, COLORS.Orange, COLORS.Green }
	for index, color in muralColors do
		local stripe = createPart(
			decor,
			string.format("MuralStripe_%d", index),
			Vector3.new(4.6, 0.55, 0.18),
			origin
				* CFrame.new(-48 + index * 4, 3 + (index % 3) * 1.45, -22.6)
				* CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 18 else -18)),
			color,
			Enum.Material.Neon
		)
		stripe.CanCollide = false
	end

	for index, x in { -49, -39, -29 } do
		local benchSeat = createPart(
			decor,
			string.format("Bench_%d_Seat", index),
			Vector3.new(7, 0.45, 2.1),
			origin * CFrame.new(x, 1.35, -13),
			COLORS.Orange,
			Enum.Material.WoodPlanks
		)
		benchSeat:SetAttribute("Decorative", true)
		for _, legX in { -2.5, 2.5 } do
			createPart(
				decor,
				string.format("Bench_%d_Leg_%s", index, if legX < 0 then "Left" else "Right"),
				Vector3.new(0.4, 1.2, 1.3),
				origin * CFrame.new(x + legX, 0.6, -13),
				COLORS.Concrete,
				Enum.Material.Metal
			)
		end
	end

	createLamp(decor, "LobbyLampLeft", origin * CFrame.new(-52, 0, 16), COLORS.Cyan, 15)
	createLamp(decor, "LobbyLampRight", origin * CFrame.new(52, 0, 16), COLORS.Pink, 15)
end

local function createLobby(root: Model, world: WorldSettings, ballSettings: BallSettings): Model
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = root

	local origin = CFrame.new(world.LobbyOrigin)
	local floor = createPart(
		lobby,
		"Plaza",
		Vector3.new(112, 1, 58),
		origin * CFrame.new(0, -0.5, 0),
		COLORS.Asphalt,
		Enum.Material.Asphalt
	)
	lobby.PrimaryPart = floor

	for _, xDirection in { -1, 1 } do
		createPart(
			lobby,
			if xDirection < 0 then "PlazaRailLeft" else "PlazaRailRight",
			Vector3.new(0.45, 0.35, 58),
			origin * CFrame.new(xDirection * 55.7, 0.18, 0),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Size = Vector3.new(7, 0.5, 7)
	spawn.CFrame = world.LobbySpawn
	spawn.Anchored = true
	spawn.CanCollide = false
	spawn.CanQuery = false
	spawn.CanTouch = false
	spawn.Transparency = 1
	spawn.Neutral = true
	spawn.AllowTeamChangeOnTouch = false
	spawn.Duration = 0
	spawn.Parent = lobby

	local queueOrigin = origin * CFrame.new(0, 0, 12)
	local queuePad = createPart(
		lobby,
		"QueuePad",
		Vector3.new(14, 0.55, 11),
		queueOrigin * CFrame.new(0, 0.28, 0),
		COLORS.Purple,
		Enum.Material.Neon
	)
	queuePad.Transparency = 0.1
	queuePad:SetAttribute("QueueMode", "1v1")

	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "QueuePrompt"
	prompt.ActionText = "JOIN 1v1 QUEUE"
	prompt.ObjectText = "PANNA MATCHMAKING"
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonR3
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	prompt:SetAttribute("QueueMode", "1v1")
	prompt.Parent = queuePad

	for _, xDirection in { -1, 1 } do
		createPart(
			lobby,
			if xDirection < 0 then "QueueArchLeft" else "QueueArchRight",
			Vector3.new(0.75, 8, 0.75),
			queueOrigin * CFrame.new(xDirection * 7.3, 4, 0),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
	end
	createPart(
		lobby,
		"QueueArchTop",
		Vector3.new(15.35, 0.75, 0.75),
		queueOrigin * CFrame.new(0, 8, 0),
		COLORS.Purple,
		Enum.Material.Neon
	)
	createBillboardSign(
		lobby,
		"QueueSign",
		"1v1  /  STEP UP & PLAY",
		queueOrigin * CFrame.new(0, 10.5, 0),
		COLORS.Yellow,
		20
	)

	createBillboardSign(
		lobby,
		"DistrictSign",
		"PANNA DISTRICT",
		origin * CFrame.new(0, 12, -22),
		COLORS.Cyan,
		27
	)
	createBillboardSign(
		lobby,
		"ArenaDirectionSign",
		"MATCH COURTS  >>>",
		origin * CFrame.new(0, 5, 25),
		COLORS.Pink,
		16
	)

	createTrainingZone(lobby, origin, ballSettings)
	createStreetDecor(lobby, origin)
	return lobby
end

local function configureLighting()
	Lighting.ClockTime = 20.2
	Lighting.Brightness = 2.2
	Lighting.ExposureCompensation = 0.1
	Lighting.Ambient = Color3.fromRGB(37, 32, 56)
	Lighting.OutdoorAmbient = Color3.fromRGB(24, 34, 52)
	Lighting.EnvironmentDiffuseScale = 0.38
	Lighting.EnvironmentSpecularScale = 0.72
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.3

	local atmosphere: Atmosphere? = nil
	local colorCorrection: ColorCorrectionEffect? = nil
	local bloom: BloomEffect? = nil
	for _, child in Lighting:GetChildren() do
		if child:GetAttribute(LIGHTING_EFFECT_ATTRIBUTE) == true then
			if child:IsA("Atmosphere") then
				atmosphere = child
			elseif child:IsA("ColorCorrectionEffect") then
				colorCorrection = child
			elseif child:IsA("BloomEffect") then
				bloom = child
			end
		end
	end

	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "PannaAtmosphere"
		atmosphere:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.08
	atmosphere.Color = Color3.fromRGB(125, 142, 181)
	atmosphere.Decay = Color3.fromRGB(49, 34, 77)
	atmosphere.Glare = 0.08
	atmosphere.Haze = 1.25

	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "PannaColorGrade"
		colorCorrection:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Brightness = -0.02
	colorCorrection.Contrast = 0.08
	colorCorrection.Saturation = 0.12
	colorCorrection.TintColor = Color3.fromRGB(224, 228, 255)

	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "PannaNeonBloom"
		bloom:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.55
	bloom.Size = 28
	bloom.Threshold = 1.15
end

local function validateConfig(config: Config)
	local world = config.World
	local ball = config.Ball
	assert(world.RootName ~= "", "Config.World.RootName must not be empty")
	assert(
		#world.ArenaPositions >= ARENA_COUNT,
		"Config.World.ArenaPositions must contain two arenas"
	)
	assert(world.ArenaWidth > 20, "Config.World.ArenaWidth must be greater than 20")
	assert(world.ArenaLength > 30, "Config.World.ArenaLength must be greater than 30")
	assert(world.FenceHeight > 3, "Config.World.FenceHeight must be greater than 3")
	assert(
		world.GoalWidth > 4 and world.GoalWidth < world.ArenaWidth - 4,
		"GoalWidth does not fit the arena"
	)
	assert(world.GoalHeight > ball.Radius * 2, "GoalHeight must be taller than the ball")
	assert(world.GoalDepth > ball.Radius * 2, "GoalDepth must be deeper than the ball")
	assert(ball.Radius > 0, "Config.Ball.Radius must be positive")
	assert(ball.Density > 0, "Config.Ball.Density must be positive")
	assert(
		ball.Friction >= 0 and ball.Friction <= 2,
		"Config.Ball.Friction must be between 0 and 2"
	)
	assert(
		ball.Elasticity >= 0 and ball.Elasticity <= 1,
		"Config.Ball.Elasticity must be between 0 and 1"
	)
end

function WorldBuilder.Build(config: Config): Model
	validateConfig(config)

	-- Build off-tree first, so a construction error leaves the current playable world intact.
	local root = Instance.new("Model")
	root.Name = config.World.RootName
	root:SetAttribute("GeneratedBy", "WorldBuilder")
	root:SetAttribute("ArenaCount", ARENA_COUNT)

	createLobby(root, config.World, config.Ball)

	local arenasFolder = Instance.new("Folder")
	arenasFolder.Name = "Arenas"
	arenasFolder.Parent = root
	for index = 1, ARENA_COUNT do
		createArena(
			arenasFolder,
			index,
			config.World.ArenaPositions[index],
			config.World,
			config.Ball
		)
	end

	local existingRoot = Workspace:FindFirstChild(config.World.RootName)
	if existingRoot then
		existingRoot:Destroy()
	end
	root.Parent = Workspace
	configureLighting()
	return root
end

return table.freeze(WorldBuilder)
