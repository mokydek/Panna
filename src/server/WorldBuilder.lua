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
	Trail: {
		Lifetime: number,
		WidthStart: number,
		WidthEnd: number,
	},
}

type Config = {
	Version: string,
	World: WorldSettings,
	Ball: BallSettings,
}

local COLORS = table.freeze({
	Asphalt = Color3.fromRGB(58, 67, 74),
	Black = Color3.fromRGB(38, 49, 56),
	Blue = Color3.fromRGB(56, 118, 255),
	Concrete = Color3.fromRGB(126, 137, 145),
	Cyan = Color3.fromRGB(34, 238, 255),
	DarkGlass = Color3.fromRGB(54, 76, 83),
	Green = Color3.fromRGB(46, 255, 160),
	Orange = Color3.fromRGB(255, 142, 43),
	Pink = Color3.fromRGB(255, 47, 161),
	Purple = Color3.fromRGB(135, 76, 255),
	White = Color3.fromRGB(235, 247, 255),
	Yellow = Color3.fromRGB(255, 226, 82),
})

local LIGHTING_EFFECT_ATTRIBUTE = "PannaDistrictBuilderEffect"
local ARENA_COUNT = 6
local ROOM_STATES = table.freeze({ "Free", "Waiting", "Countdown", "Active", "Result" })
local ARENA_ACCENTS = table.freeze({
	COLORS.Cyan,
	COLORS.Pink,
	COLORS.Green,
	COLORS.Orange,
	COLORS.Purple,
	COLORS.Yellow,
})
local ARENA_NAMES = table.freeze({
	"Concrete Cage",
	"Neon Futsal",
	"Club House",
	"Industrial",
	"Training Lab",
	"Championship",
})
local ARENA_COURTS = table.freeze({
	{ Color = Color3.fromRGB(112, 119, 123), Material = Enum.Material.Concrete },
	{ Color = Color3.fromRGB(41, 119, 164), Material = Enum.Material.SmoothPlastic },
	{ Color = Color3.fromRGB(54, 139, 76), Material = Enum.Material.Grass },
	{ Color = Color3.fromRGB(105, 113, 120), Material = Enum.Material.Concrete },
	{ Color = Color3.fromRGB(47, 143, 136), Material = Enum.Material.SmoothPlastic },
	{ Color = Color3.fromRGB(42, 130, 68), Material = Enum.Material.Grass },
})

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

local function createPrompt(
	parent: BasePart,
	name: string,
	actionText: string,
	objectText: string,
	arenaId: string?,
	roomAction: string?
): ProximityPrompt
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = name
	prompt.ActionText = actionText
	prompt.ObjectText = objectText
	prompt.KeyboardKeyCode = Enum.KeyCode.T
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonR3
	prompt.HoldDuration = 0.15
	prompt.MaxActivationDistance = 12
	prompt.RequiresLineOfSight = false
	if arenaId then
		prompt:SetAttribute("ArenaId", arenaId)
	end
	if roomAction then
		prompt:SetAttribute("RoomAction", roomAction)
	end
	prompt.Parent = parent
	return prompt
end

local function createBoardLabel(
	parent: Instance,
	name: string,
	text: string,
	position: UDim2,
	size: UDim2,
	color: Color3,
	font: Enum.Font
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.Position = position
	label.Size = size
	label.Font = font
	label.Text = text
	label.TextColor3 = color
	label.TextScaled = true
	label.TextStrokeColor3 = COLORS.Black
	label.TextStrokeTransparency = 0.2
	label.Parent = parent
	return label
end

local function createStatusBoard(
	parent: Instance,
	origin: CFrame,
	arenaId: string,
	index: number,
	roomTitle: string,
	streetDirection: number,
	world: WorldSettings,
	accent: Color3
): Part
	local board = createPart(
		parent,
		"StatusBoard",
		Vector3.new(0.55, 7.2, 13.5),
		origin * CFrame.new(streetDirection * (world.ArenaWidth * 0.5 + 1.2), 7.2, -13),
		COLORS.Black,
		Enum.Material.Metal
	)
	board.CanCollide = false
	board:SetAttribute("ArenaId", arenaId)
	board:SetAttribute("BoardRole", "RoomStatus")
	board:SetAttribute("RoomTitle", roomTitle)

	local surface = Instance.new("SurfaceGui")
	surface.Name = "Display"
	surface.Face = if streetDirection > 0 then Enum.NormalId.Right else Enum.NormalId.Left
	surface.AlwaysOnTop = false
	surface.LightInfluence = 0
	surface.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	surface.PixelsPerStud = 38
	surface.Parent = board

	local panel = Instance.new("Frame")
	panel.Name = "Panel"
	panel.BackgroundColor3 = COLORS.Black
	panel.BackgroundTransparency = 0.08
	panel.BorderSizePixel = 0
	panel.Size = UDim2.fromScale(1, 1)
	panel.Parent = surface

	createBoardLabel(
		panel,
		"RoomLabel",
		string.format("%02d  %s", index, string.upper(roomTitle)),
		UDim2.fromScale(0.04, 0.05),
		UDim2.fromScale(0.92, 0.2),
		accent,
		Enum.Font.GothamBlack
	)
	createBoardLabel(
		panel,
		"StateLabel",
		"FREE",
		UDim2.fromScale(0.04, 0.31),
		UDim2.fromScale(0.92, 0.25),
		COLORS.Green,
		Enum.Font.GothamBold
	)
	createBoardLabel(
		panel,
		"ScoreLabel",
		"0  :  0",
		UDim2.fromScale(0.04, 0.62),
		UDim2.fromScale(0.92, 0.24),
		COLORS.White,
		Enum.Font.GothamBlack
	)
	return board
end

local function addPointLight(part: BasePart, color: Color3, range: number, brightness: number)
	local light = Instance.new("PointLight")
	light.Color = color
	light.Range = range
	light.Brightness = brightness
	-- Six rooms plus the street use many practical lights. Disabling per-light
	-- shadows keeps the bright district readable without multiplying shadow-map cost.
	light.Shadows = false
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
	addPointLight(lamp, color, 34, 0.42)
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
	ball:SetAttribute("LastTouchUserId", 0)
	ball:SetAttribute("BallState", "Reset")
	ball:SetAttribute("BallRevision", 0)
	ball:SetAttribute("LastAction", "Reset")

	local controlAttachment = Instance.new("Attachment")
	controlAttachment.Name = "PannaControlAttachment"
	controlAttachment.Parent = ball

	local trailTop = Instance.new("Attachment")
	trailTop.Name = "PannaTrailTop"
	trailTop.Position = Vector3.new(0, settings.Radius * 0.55, 0)
	trailTop.Parent = ball

	local trailBottom = Instance.new("Attachment")
	trailBottom.Name = "PannaTrailBottom"
	trailBottom.Position = Vector3.new(0, -settings.Radius * 0.55, 0)
	trailBottom.Parent = ball

	local trail = Instance.new("Trail")
	trail.Name = "PannaSpeedTrail"
	trail.Attachment0 = trailTop
	trail.Attachment1 = trailBottom
	trail.Enabled = false
	trail.FaceCamera = true
	trail.LightEmission = 0.8
	trail.Lifetime = settings.Trail.Lifetime
	trail.MinLength = 0.08
	trail.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.White),
		ColorSequenceKeypoint.new(0.35, COLORS.Cyan),
		ColorSequenceKeypoint.new(1, COLORS.Pink),
	})
	trail.Transparency = NumberSequence.new({
		NumberSequenceKeypoint.new(0, 0.12),
		NumberSequenceKeypoint.new(1, 1),
	})
	trail.WidthScale = NumberSequence.new({
		NumberSequenceKeypoint.new(0, settings.Trail.WidthStart),
		NumberSequenceKeypoint.new(1, settings.Trail.WidthEnd),
	})
	trail.Parent = ball
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
	local marking = createPart(parent, name, size, cframe, color, Enum.Material.SmoothPlastic)
	marking.CanCollide = false
	marking.CanTouch = false
	marking.CanQuery = false
	marking.CastShadow = false
end

local function createPitchFinish(
	parent: Instance,
	origin: CFrame,
	world: WorldSettings,
	baseColor: Color3,
	material: Enum.Material
)
	local finish = Instance.new("Model")
	finish.Name = "PitchFinish"
	finish.Parent = parent

	local stripeCount = 8
	local stripeLength = world.ArenaLength / stripeCount
	for index = 1, stripeCount do
		if index % 2 == 0 then
			local stripe = createPart(
				finish,
				string.format("MowingStripe_%02d", index),
				Vector3.new(world.ArenaWidth - 1.2, 0.025, stripeLength),
				origin
					* CFrame.new(0, 0.018, -world.ArenaLength * 0.5 + stripeLength * (index - 0.5)),
				baseColor:Lerp(
					Color3.new(1, 1, 1),
					if material == Enum.Material.Grass then 0.055 else 0.035
				),
				material
			)
			stripe.CanCollide = false
			stripe.CanTouch = false
			stripe.CanQuery = false
			stripe.CastShadow = false
		end
	end
end

local function createPitchBoundaryAndBoxes(parent: Instance, origin: CFrame, world: WorldSettings)
	local halfWidth = world.ArenaWidth * 0.5
	local halfLength = world.ArenaLength * 0.5
	local lineInset = 0.6
	for _, xDirection in { -1, 1 } do
		createCourtMarking(
			parent,
			if xDirection < 0 then "LeftTouchLine" else "RightTouchLine",
			Vector3.new(0.14, 0.07, world.ArenaLength - lineInset * 2),
			origin * CFrame.new(xDirection * (halfWidth - lineInset), 0.07, 0),
			COLORS.White
		)
	end

	local penaltyDepth = 10.5
	local penaltyWidth = math.min(world.GoalWidth + 10, world.ArenaWidth - 6)
	for _, zDirection in { -1, 1 } do
		createCourtMarking(
			parent,
			if zDirection < 0 then "AwayPenaltyLine" else "HomePenaltyLine",
			Vector3.new(penaltyWidth, 0.07, 0.14),
			origin * CFrame.new(0, 0.07, zDirection * (halfLength - penaltyDepth)),
			COLORS.White
		)
		for _, xDirection in { -1, 1 } do
			createCourtMarking(
				parent,
				string.format("PenaltySide_%d_%d", zDirection, xDirection),
				Vector3.new(0.14, 0.07, penaltyDepth - lineInset),
				origin
					* CFrame.new(
						xDirection * penaltyWidth * 0.5,
						0.07,
						zDirection * (halfLength - penaltyDepth * 0.5 - lineInset * 0.5)
					),
				COLORS.White
			)
		end
	end
end

local function createCenterCircle(parent: Instance, origin: CFrame, color: Color3)
	local circleModel = Instance.new("Model")
	circleModel.Name = "CenterCircle"
	circleModel.Parent = parent

	local radius = 7
	local segmentCount = 16
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
			COLORS.White,
			Enum.Material.Metal
		)
	end

	createPart(
		model,
		"Crossbar",
		Vector3.new(world.GoalWidth + postThickness, postThickness, postThickness),
		origin * CFrame.new(0, world.GoalHeight, goalLineZ),
		COLORS.White,
		Enum.Material.Metal
	)

	local backNet = createPart(
		model,
		"BackNet",
		Vector3.new(world.GoalWidth, world.GoalHeight, 0.2),
		origin * CFrame.new(0, world.GoalHeight * 0.5, backZ),
		COLORS.White,
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
			COLORS.White,
			Enum.Material.ForceField
		)
		sideNet.Transparency = 0.78
	end

	local topNet = createPart(
		model,
		"TopNet",
		Vector3.new(world.GoalWidth, 0.2, world.GoalDepth),
		origin * CFrame.new(0, world.GoalHeight, goalCenterZ),
		COLORS.White,
		Enum.Material.ForceField
	)
	topNet.Transparency = 0.78

	createPart(
		model,
		"GoalFloor",
		Vector3.new(world.GoalWidth, 0.45, world.GoalDepth),
		origin * CFrame.new(0, -0.2, goalCenterZ),
		Color3.fromRGB(92, 109, 96),
		Enum.Material.Grass
	)
	local teamAccent = createPart(
		model,
		"TeamAccent",
		Vector3.new(world.GoalWidth - 1, 0.18, 0.18),
		origin * CFrame.new(0, 0.22, backZ - side * 0.14),
		color,
		Enum.Material.SmoothPlastic
	)
	teamAccent.CanCollide = false
	teamAccent.CanTouch = false
	teamAccent.CanQuery = false
	teamAccent.CastShadow = false
end

local function createFence(
	parent: Instance,
	origin: CFrame,
	world: WorldSettings,
	streetDirection: number
)
	local model = Instance.new("Model")
	model.Name = "Fence"
	model.Parent = parent

	local halfWidth = world.ArenaWidth * 0.5
	local halfLength = world.ArenaLength * 0.5
	local panelColor = COLORS.DarkGlass
	local entranceWidth = 12

	for _, xDirection in { -1, 1 } do
		local sideName = if xDirection < 0 then "Left" else "Right"
		local railColor = if xDirection < 0 then COLORS.Cyan else COLORS.Pink
		if xDirection == streetDirection then
			local segmentLength = (world.ArenaLength - entranceWidth) * 0.5
			local segmentOffset = entranceWidth * 0.5 + segmentLength * 0.5
			for _, zDirection in { -1, 1 } do
				local suffix = if zDirection < 0 then "South" else "North"
				local sidePanel = createPart(
					model,
					sideName .. "Panel" .. suffix,
					Vector3.new(0.38, world.FenceHeight, segmentLength),
					origin
						* CFrame.new(
							xDirection * (halfWidth + 0.2),
							world.FenceHeight * 0.5,
							zDirection * segmentOffset
						),
					panelColor,
					Enum.Material.Glass
				)
				sidePanel.Transparency = 0.58
				createPart(
					model,
					sideName .. "NeonRail" .. suffix,
					Vector3.new(0.3, 0.3, segmentLength),
					origin
						* CFrame.new(
							xDirection * (halfWidth + 0.4),
							0.45,
							zDirection * segmentOffset
						),
					railColor,
					Enum.Material.Neon
				)
			end
		else
			local sidePanel = createPart(
				model,
				sideName .. "Panel",
				Vector3.new(0.38, world.FenceHeight, world.ArenaLength + 0.7),
				origin * CFrame.new(xDirection * (halfWidth + 0.2), world.FenceHeight * 0.5, 0),
				panelColor,
				Enum.Material.Glass
			)
			sidePanel.Transparency = 0.58
			createPart(
				model,
				sideName .. "NeonRail",
				Vector3.new(0.3, 0.3, world.ArenaLength + 1),
				origin * CFrame.new(xDirection * (halfWidth + 0.4), 0.45, 0),
				railColor,
				Enum.Material.Neon
			)
		end
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
			if xDirection ~= streetDirection or math.abs(z) > entranceWidth * 0.5 + 0.5 then
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

	for _, zDirection in { -1, 1 } do
		createPart(
			model,
			if zDirection < 0 then "EntryPostSouth" else "EntryPostNorth",
			Vector3.new(0.7, 6.5, 0.7),
			origin
				* CFrame.new(
					streetDirection * (halfWidth + 0.25),
					3.25,
					zDirection * entranceWidth * 0.5
				),
			COLORS.Concrete,
			Enum.Material.Metal
		)
	end
end

local function createWaitingMarker(
	parent: Instance,
	name: string,
	cframe: CFrame,
	arenaId: string,
	teamSide: string
): Part
	local marker = createInvisibleMarker(parent, name, Vector3.new(4.5, 0.4, 4.5), cframe, false)
	marker:SetAttribute("ArenaId", arenaId)
	marker:SetAttribute("TeamSide", teamSide)
	marker:SetAttribute("MarkerRole", "RoomWaitingSpawn")
	return marker
end

local function createSpectatorStand(
	parent: Instance,
	origin: CFrame,
	world: WorldSettings,
	streetDirection: number,
	arenaId: string,
	accent: Color3
)
	local stand = Instance.new("Model")
	stand.Name = "SpectatorStand"
	stand.Parent = parent

	local outerDirection = -streetDirection
	local baseX = outerDirection * (world.ArenaWidth * 0.5 + 5.5)
	createPart(
		stand,
		"StandBase",
		Vector3.new(13, 0.8, 48),
		origin * CFrame.new(baseX, 0.4, 0),
		COLORS.Concrete,
		Enum.Material.Concrete
	)
	for row = 1, 3 do
		local rowX = baseX + outerDirection * ((row - 1) * 2.1)
		createPart(
			stand,
			string.format("Tier_%d", row),
			Vector3.new(2.2, row * 0.75, 44),
			origin * CFrame.new(rowX, row * 0.375, 0),
			if row % 2 == 0 then COLORS.Asphalt else COLORS.Concrete,
			Enum.Material.Concrete
		)
		local bench = createPart(
			stand,
			string.format("Bench_%d", row),
			Vector3.new(1.7, 0.35, 40),
			origin * CFrame.new(rowX, row * 0.75 + 0.45, 0),
			accent,
			Enum.Material.Metal
		)
		bench:SetAttribute("SpectatorSeating", true)
	end

	local zone = createInvisibleMarker(
		parent,
		"SpectatorZone",
		Vector3.new(13, 8, 48),
		origin * CFrame.new(baseX, 4, 0),
		true
	)
	zone:SetAttribute("ArenaId", arenaId)
	zone:SetAttribute("ZoneType", "Spectator")
end

local function createRoomLifecycle(
	model: Model,
	index: number,
	origin: CFrame,
	world: WorldSettings,
	arenaId: string,
	roomTitle: string,
	streetDirection: number,
	accent: Color3
)
	local halfWidth = world.ArenaWidth * 0.5
	local deckX = streetDirection * (halfWidth + 5.7)
	local insideX = streetDirection * (halfWidth - 5.5)

	local deck = createPart(
		model,
		"EntryDeck",
		Vector3.new(11, 0.45, 16),
		origin * CFrame.new(deckX, 0.23, 0),
		COLORS.Concrete,
		Enum.Material.Concrete
	)
	deck:SetAttribute("ArenaId", arenaId)
	for _, zDirection in { -1, 1 } do
		local side = if zDirection < 0 then "Home" else "Away"
		local pad = createPart(
			model,
			side .. "WaitingPad",
			Vector3.new(4.4, 0.12, 5.4),
			origin * CFrame.new(deckX, 0.51, zDirection * 4.2),
			if side == "Home" then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
		pad.CanCollide = false
		pad.CanTouch = false
		pad.CanQuery = false
	end

	createWaitingMarker(
		model,
		"HomeWaitingSpawn",
		origin * CFrame.new(deckX, 0.55, -4.2),
		arenaId,
		"Home"
	)
	createWaitingMarker(
		model,
		"AwayWaitingSpawn",
		origin * CFrame.new(deckX, 0.55, 4.2),
		arenaId,
		"Away"
	)
	local streetSpawn = createInvisibleMarker(
		model,
		"StreetSpawn",
		Vector3.new(5, 0.4, 5),
		origin * CFrame.new(streetDirection * (halfWidth + 13), 0.55, 0),
		false
	)
	streetSpawn:SetAttribute("ArenaId", arenaId)
	streetSpawn:SetAttribute("MarkerRole", "RoomStreetReturn")

	local entryZone = createInvisibleMarker(
		model,
		"EntryZone",
		Vector3.new(11, 4, 16),
		origin * CFrame.new(deckX, 2, 0),
		true
	)
	entryZone:SetAttribute("ArenaId", arenaId)
	entryZone:SetAttribute("RoomAction", "Enter")
	createPrompt(
		entryZone,
		"EntryPrompt",
		"ENTER ROOM",
		string.format("%s  •  FREE", string.upper(roomTitle)),
		arenaId,
		"Enter"
	)

	local exitZone = createInvisibleMarker(
		model,
		"ExitZone",
		Vector3.new(8, 4, 10),
		origin * CFrame.new(insideX, 2, 0),
		true
	)
	exitZone:SetAttribute("ArenaId", arenaId)
	exitZone:SetAttribute("RoomAction", "Exit")
	createPrompt(exitZone, "ExitPrompt", "LEAVE ROOM", "RETURN TO DISTRICT", arenaId, "Exit")

	local barrier = createPart(
		model,
		"Barrier",
		Vector3.new(0.5, 5.5, 11.8),
		origin * CFrame.new(streetDirection * (halfWidth + 0.2), 2.75, 0),
		accent,
		Enum.Material.ForceField
	)
	barrier.Transparency = 0.58
	barrier.CanCollide = false
	barrier.CanTouch = false
	barrier:SetAttribute("ArenaId", arenaId)
	barrier:SetAttribute("BarrierRole", "RoomGate")
	barrier:SetAttribute("Closed", false)

	createStatusBoard(model, origin, arenaId, index, roomTitle, streetDirection, world, accent)
	createSpectatorStand(model, origin, world, streetDirection, arenaId, accent)
end

local function createArenaThemeDecor(
	parent: Instance,
	index: number,
	origin: CFrame,
	world: WorldSettings,
	streetDirection: number,
	accent: Color3
)
	local theme = Instance.new("Model")
	theme.Name = string.gsub(ARENA_NAMES[index], "%s+", "") .. "Theme"
	theme:SetAttribute("ThemeName", ARENA_NAMES[index])
	theme.Parent = parent
	local halfWidth = world.ArenaWidth * 0.5
	local outerDirection = -streetDirection

	if index == 1 then
		for _, zDirection in { -1, 1 } do
			createPart(
				theme,
				if zDirection < 0 then "ConcreteButtressSouth" else "ConcreteButtressNorth",
				Vector3.new(3.2, 10, 5.5),
				origin * CFrame.new(outerDirection * (halfWidth + 1.8), 5, zDirection * 23),
				Color3.fromRGB(68, 72, 78),
				Enum.Material.Concrete
			)
		end
	elseif index == 2 then
		for _, zDirection in { -1, 1 } do
			createPart(
				theme,
				if zDirection < 0 then "NeonCrossbeamSouth" else "NeonCrossbeamNorth",
				Vector3.new(world.ArenaWidth + 5, 0.45, 0.45),
				origin * CFrame.new(0, world.FenceHeight + 3, zDirection * 18),
				accent,
				Enum.Material.Neon
			)
		end
	elseif index == 3 then
		createPart(
			theme,
			"ClubFacade",
			Vector3.new(1.2, 9, 28),
			origin * CFrame.new(outerDirection * (halfWidth + 8.5), 4.5, 0),
			Color3.fromRGB(92, 62, 45),
			Enum.Material.WoodPlanks
		)
		createPart(
			theme,
			"ClubCanopy",
			Vector3.new(10, 0.65, 30),
			origin * CFrame.new(outerDirection * (halfWidth + 4.5), 9, 0),
			COLORS.Green,
			Enum.Material.Metal
		)
	elseif index == 4 then
		for _, zDirection in { -1, 1 } do
			local pipe = createPart(
				theme,
				if zDirection < 0 then "IndustrialPipeSouth" else "IndustrialPipeNorth",
				Vector3.new(30, 2.2, 2.2),
				origin * CFrame.new(outerDirection * (halfWidth + 7), 8, zDirection * 17),
				Color3.fromRGB(112, 118, 128),
				Enum.Material.Metal
			)
			pipe.Shape = Enum.PartType.Cylinder
			pipe.CFrame *= CFrame.Angles(0, math.pi * 0.5, 0)
		end
	elseif index == 5 then
		for panelIndex, z in { -18, 0, 18 } do
			local panel = createPart(
				theme,
				string.format("LabPanel_%d", panelIndex),
				Vector3.new(0.3, 5.5, 8),
				origin * CFrame.new(outerDirection * (halfWidth + 1), 7, z),
				if panelIndex % 2 == 0 then COLORS.Green else COLORS.Cyan,
				Enum.Material.Neon
			)
			panel.Transparency = 0.32
			panel.CanCollide = false
		end
	elseif index == 6 then
		for _, zDirection in { -1, 1 } do
			createPart(
				theme,
				if zDirection < 0 then "ChampionshipBannerSouth" else "ChampionshipBannerNorth",
				Vector3.new(0.45, 10, 5),
				origin
					* CFrame.new(
						streetDirection * (halfWidth + 0.9),
						world.FenceHeight - 2,
						zDirection * 22
					),
				COLORS.Yellow,
				Enum.Material.Neon
			)
		end
		createPart(
			theme,
			"ChampionshipCrown",
			Vector3.new(world.ArenaWidth + 4, 0.8, 0.8),
			origin * CFrame.new(0, world.FenceHeight + 4.5, 0),
			COLORS.Yellow,
			Enum.Material.Neon
		)
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
	local roomTitle = ARENA_NAMES[index]
	local districtSide = if origin.Position.X < 0 then "Left" else "Right"
	local streetDirection = if districtSide == "Left" then 1 else -1
	local model = Instance.new("Model")
	model.Name = arenaId
	model:SetAttribute("ArenaId", arenaId)
	model:SetAttribute("ArenaState", ROOM_STATES[1])
	model:SetAttribute("Busy", false)
	model:SetAttribute("DisplayName", roomTitle)
	model:SetAttribute("DistrictSide", districtSide)
	model:SetAttribute("HomeUserId", 0)
	model:SetAttribute("MatchId", "")
	model:SetAttribute("AwayUserId", 0)
	model:SetAttribute("RoomIndex", index)
	model:SetAttribute("RoomTitle", roomTitle)
	model:SetAttribute("WaitingCount", 0)
	model.Parent = arenasFolder

	local halfWidth = world.ArenaWidth * 0.5
	local halfLength = world.ArenaLength * 0.5
	local accent = ARENA_ACCENTS[((index - 1) % #ARENA_ACCENTS) + 1]

	local courtStyle = ARENA_COURTS[index]
	local floor = createPart(
		model,
		"Court",
		Vector3.new(world.ArenaWidth, 1, world.ArenaLength),
		origin * CFrame.new(0, -0.5, 0),
		courtStyle.Color,
		courtStyle.Material
	)
	model.PrimaryPart = floor
	createPitchFinish(model, origin, world, courtStyle.Color, courtStyle.Material)
	createPitchBoundaryAndBoxes(model, origin, world)

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
		COLORS.White
	)
	createCenterCircle(model, origin, COLORS.White)

	for _, zDirection in { -1, 1 } do
		createCourtMarking(
			model,
			if zDirection < 0 then "AwayGoalLine" else "HomeGoalLine",
			Vector3.new(world.ArenaWidth - 1.2, 0.07, 0.14),
			origin * CFrame.new(0, 0.07, zDirection * halfLength),
			COLORS.White
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
	createFence(model, origin, world, streetDirection)

	createBall(model, "Ball", ballSpawn.CFrame, ballSettings, arenaId)
	createRoomLifecycle(model, index, origin, world, arenaId, roomTitle, streetDirection, accent)
	createArenaThemeDecor(model, index, origin, world, streetDirection, accent)

	local decor = Instance.new("Model")
	decor.Name = "Floodlights"
	decor.Parent = model
	for _, corner in
		{
			Vector3.new(-halfWidth - 3, 0, -halfLength + 7),
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
		string.format("%02d  /  %s", index, string.upper(roomTitle)),
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

	local zoneOrigin = origin * CFrame.new(-47, 0, 2)
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

local function createFacilityKiosk(
	parent: Instance,
	name: string,
	title: string,
	origin: CFrame,
	accent: Color3
): Model
	local facility = Instance.new("Model")
	facility.Name = name
	facility:SetAttribute("FacilityType", name)
	facility.Parent = parent

	createPart(
		facility,
		"Floor",
		Vector3.new(22, 0.5, 16),
		origin * CFrame.new(0, 0.25, 0),
		COLORS.Concrete,
		Enum.Material.Concrete
	)
	createPart(
		facility,
		"BackWall",
		Vector3.new(22, 8, 0.7),
		origin * CFrame.new(0, 4, -7.65),
		COLORS.DarkGlass,
		Enum.Material.Glass
	).Transparency =
		0.3
	for _, xDirection in { -1, 1 } do
		createPart(
			facility,
			if xDirection < 0 then "LeftColumn" else "RightColumn",
			Vector3.new(0.8, 8.6, 0.8),
			origin * CFrame.new(xDirection * 10.5, 4.3, -7.2),
			accent,
			Enum.Material.Neon
		)
	end
	createPart(
		facility,
		"Roof",
		Vector3.new(22.8, 0.65, 16.8),
		origin * CFrame.new(0, 8.25, 0),
		COLORS.Asphalt,
		Enum.Material.Metal
	)
	createPart(
		facility,
		"Counter",
		Vector3.new(16, 2.5, 2.2),
		origin * CFrame.new(0, 1.25, -4.8),
		accent,
		Enum.Material.Metal
	)
	createBillboardSign(
		facility,
		name .. "Sign",
		title,
		origin * CFrame.new(0, 10.5, -6.8),
		accent,
		17
	)
	return facility
end

local function createTrophyCorner(parent: Instance, origin: CFrame)
	local trophy = Instance.new("Model")
	trophy.Name = "TrophyCorner"
	trophy:SetAttribute("FacilityType", "Trophy")
	trophy.Parent = parent

	createPart(
		trophy,
		"Podium",
		Vector3.new(12, 1.4, 8),
		origin * CFrame.new(0, 0.7, 0),
		COLORS.Concrete,
		Enum.Material.Marble
	)
	for index, height in { 5.8, 4.4, 3.8 } do
		local x = (index - 2) * 3.4
		createPart(
			trophy,
			string.format("TrophyStem_%d", index),
			Vector3.new(0.65, height, 0.65),
			origin * CFrame.new(x, 1.4 + height * 0.5, 0),
			COLORS.Yellow,
			Enum.Material.Metal
		)
		local ball = createPart(
			trophy,
			string.format("TrophyBall_%d", index),
			Vector3.new(1.8, 1.8, 1.8),
			origin * CFrame.new(x, 1.4 + height + 0.8, 0),
			if index == 1 then COLORS.Cyan elseif index == 2 then COLORS.Yellow else COLORS.Pink,
			Enum.Material.Neon
		)
		ball.Shape = Enum.PartType.Ball
		ball.CanCollide = false
	end
	createBillboardSign(
		trophy,
		"TrophySign",
		"DISTRICT HONOURS",
		origin * CFrame.new(0, 10.5, 0),
		COLORS.Yellow,
		15
	)
end

local function createRestZone(parent: Instance, origin: CFrame)
	local rest = Instance.new("Model")
	rest.Name = "RestZone"
	rest:SetAttribute("FacilityType", "Rest")
	rest.Parent = parent
	createPart(
		rest,
		"RestDeck",
		Vector3.new(28, 0.4, 13),
		origin * CFrame.new(0, 0.2, 0),
		COLORS.Concrete,
		Enum.Material.Concrete
	)
	for _, x in { -8.5, 0, 8.5 } do
		createPart(
			rest,
			string.format("Bench_%d", math.floor(x * 10)),
			Vector3.new(6.8, 0.5, 2.1),
			origin * CFrame.new(x, 1.25, 0),
			COLORS.Orange,
			Enum.Material.WoodPlanks
		)
	end
	createBillboardSign(
		rest,
		"RestSign",
		"RECOVER  /  WATCH  /  REQUEUE",
		origin * CFrame.new(0, 5.5, -5),
		COLORS.Green,
		22
	)
end

local function createStreetDecor(lobby: Model, origin: CFrame)
	local decor = Instance.new("Model")
	decor.Name = "StreetDecor"
	decor.Parent = lobby

	local muralWall = createPart(
		decor,
		"MuralWall",
		Vector3.new(38, 11, 1),
		origin * CFrame.new(-17, 5.5, -33),
		Color3.fromRGB(34, 35, 48),
		Enum.Material.Concrete
	)
	muralWall:SetAttribute("Decorative", true)

	local muralColors = { COLORS.Pink, COLORS.Purple, COLORS.Cyan, COLORS.Orange, COLORS.Green }
	for index, color in muralColors do
		local stripe = createPart(
			decor,
			string.format("MuralStripe_%d", index),
			Vector3.new(6.4, 0.65, 0.18),
			origin
				* CFrame.new(-34 + index * 7, 3 + (index % 3) * 1.65, -33.6)
				* CFrame.Angles(0, 0, math.rad(if index % 2 == 0 then 18 else -18)),
			color,
			Enum.Material.Neon
		)
		stripe.CanCollide = false
	end

	createLamp(decor, "LobbyLampLeft", origin * CFrame.new(-67, 0, 26), COLORS.Cyan, 15)
	createLamp(decor, "LobbyLampRight", origin * CFrame.new(67, 0, 26), COLORS.Pink, 15)
end

local function createLobbyFacilities(lobby: Model, origin: CFrame)
	local facilities = Instance.new("Model")
	facilities.Name = "Facilities"
	facilities.Parent = lobby
	createFacilityKiosk(
		facilities,
		"StreetShop",
		"PANNA SUPPLY  /  COSMETICS",
		origin * CFrame.new(49, 0, -16),
		COLORS.Pink
	)
	createFacilityKiosk(
		facilities,
		"LockerRoom",
		"LOCKER  /  LOADOUT",
		origin * CFrame.new(49, 0, 12),
		COLORS.Cyan
	)
	createTrophyCorner(facilities, origin * CFrame.new(14, 0, -22))
	createRestZone(facilities, origin * CFrame.new(0, 0, 27))
end

local function createLobby(root: Model, world: WorldSettings, ballSettings: BallSettings): Model
	local lobby = Instance.new("Model")
	lobby.Name = "Lobby"
	lobby.Parent = root

	local origin = CFrame.new(world.LobbyOrigin)
	local floor = createPart(
		lobby,
		"Plaza",
		Vector3.new(150, 1, 74),
		origin * CFrame.new(0, -0.5, 0),
		COLORS.Asphalt,
		Enum.Material.Asphalt
	)
	lobby.PrimaryPart = floor

	for _, xDirection in { -1, 1 } do
		createPart(
			lobby,
			if xDirection < 0 then "PlazaRailLeft" else "PlazaRailRight",
			Vector3.new(0.45, 0.35, 74),
			origin * CFrame.new(xDirection * 74.7, 0.18, 0),
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

	local queueOrigin = origin * CFrame.new(0, 0, 7)
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

	local prompt =
		createPrompt(queuePad, "QueuePrompt", "JOIN 1v1 QUEUE", "DISTRICT MATCHMAKING", nil, nil)
	prompt:SetAttribute("QueueMode", "1v1")

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
		origin * CFrame.new(0, 12, -32),
		COLORS.Cyan,
		27
	)
	createBillboardSign(
		lobby,
		"ArenaDirectionSign",
		"6 ROOMS  /  WALK THE STREET  >>>",
		origin * CFrame.new(0, 5, 34),
		COLORS.Pink,
		16
	)

	createTrainingZone(lobby, origin, ballSettings)
	createLobbyFacilities(lobby, origin)
	createStreetDecor(lobby, origin)
	return lobby
end

local function getDistrictExtents(world: WorldSettings): (number, number)
	local startZ = world.LobbyOrigin.Z - 38
	local furthestArenaZ = world.LobbyOrigin.Z
	for _, arenaCFrame in world.ArenaPositions do
		furthestArenaZ = math.max(furthestArenaZ, arenaCFrame.Position.Z)
	end
	local endZ = furthestArenaZ + world.ArenaLength * 0.5 + 58
	return startZ, endZ
end

local function createEndLandmark(parent: Instance, origin: CFrame)
	local landmark = Instance.new("Model")
	landmark.Name = "EndLandmark"
	landmark:SetAttribute("LandmarkType", "DistrictFinish")
	landmark.Parent = parent

	for _, xDirection in { -1, 1 } do
		createPart(
			landmark,
			if xDirection < 0 then "WestTower" else "EastTower",
			Vector3.new(3, 20, 3),
			origin * CFrame.new(xDirection * 14, 10, 0),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
		createPart(
			landmark,
			if xDirection < 0 then "WestFoot" else "EastFoot",
			Vector3.new(7, 1.2, 7),
			origin * CFrame.new(xDirection * 14, 0.6, 0),
			COLORS.Concrete,
			Enum.Material.Concrete
		)
	end
	createPart(
		landmark,
		"CrownBeam",
		Vector3.new(31, 2, 3),
		origin * CFrame.new(0, 20, 0),
		COLORS.Yellow,
		Enum.Material.Neon
	)
	local crownBall = createPart(
		landmark,
		"CrownBall",
		Vector3.new(6, 6, 6),
		origin * CFrame.new(0, 25, 0),
		COLORS.White,
		Enum.Material.Neon
	)
	crownBall.Shape = Enum.PartType.Ball
	crownBall.CanCollide = false
	createBillboardSign(
		landmark,
		"LandmarkSign",
		"END OF THE STREET  /  CHAMPIONS RISE",
		origin * CFrame.new(0, 15.5, 0),
		COLORS.Yellow,
		31
	)
end

local function createPannaDistrict(root: Model, world: WorldSettings): Model
	local district = Instance.new("Model")
	district.Name = "DistrictEnvironment"
	district:SetAttribute("DistrictStyle", "BrightDayFootballDistrict")
	district:SetAttribute("ExternalAssetCount", 0)
	district.Parent = root

	local startZ, endZ = getDistrictExtents(world)
	local streetLength = endZ - startZ
	local centerZ = (startZ + endZ) * 0.5

	local ground = createPart(
		district,
		"DistrictGround",
		Vector3.new(214, 1.2, streetLength + 18),
		CFrame.new(0, -1.1, centerZ),
		Color3.fromRGB(72, 91, 73),
		Enum.Material.Concrete
	)
	district.PrimaryPart = ground

	local street = Instance.new("Model")
	street.Name = "CentralStreet"
	street:SetAttribute("Continuous", true)
	street:SetAttribute("StartZ", startZ)
	street:SetAttribute("EndZ", endZ)
	street.Parent = district
	createPart(
		street,
		"StreetSurface",
		Vector3.new(30, 0.55, streetLength),
		CFrame.new(0, -0.28, centerZ),
		COLORS.Asphalt,
		Enum.Material.Asphalt
	)
	for _, xDirection in { -1, 1 } do
		createPart(
			street,
			if xDirection < 0 then "WestWalk" else "EastWalk",
			Vector3.new(12, 0.7, streetLength),
			CFrame.new(xDirection * 21, -0.15, centerZ),
			COLORS.Concrete,
			Enum.Material.Concrete
		)
		createPart(
			street,
			if xDirection < 0 then "WestCurbNeon" else "EastCurbNeon",
			Vector3.new(0.3, 0.16, streetLength),
			CFrame.new(xDirection * 15.1, 0.09, centerZ),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			Enum.Material.Neon
		)
	end

	local laneMarkers = Instance.new("Model")
	laneMarkers.Name = "LaneMarkers"
	laneMarkers.Parent = street
	local markerCount = math.max(1, math.floor(streetLength / 20))
	for index = 0, markerCount do
		local z = startZ + (streetLength * index / markerCount)
		local marker = createPart(
			laneMarkers,
			string.format("Marker_%02d", index),
			Vector3.new(0.24, 0.08, 8),
			CFrame.new(0, 0.08, z),
			COLORS.Yellow,
			Enum.Material.Neon
		)
		marker.CanCollide = false
		marker.CanTouch = false
		marker.CanQuery = false
	end

	local crosswalks = Instance.new("Model")
	crosswalks.Name = "RoomCrosswalks"
	crosswalks.Parent = street
	for index = 1, ARENA_COUNT, 2 do
		local rowZ = world.ArenaPositions[index].Position.Z
		for stripeIndex = 1, 6 do
			local stripe = createPart(
				crosswalks,
				string.format("Row_%02d_Stripe_%d", math.ceil(index * 0.5), stripeIndex),
				Vector3.new(24, 0.07, 0.8),
				CFrame.new(0, 0.09, rowZ - 3.5 + stripeIndex),
				COLORS.White,
				Enum.Material.SmoothPlastic
			)
			stripe.CanCollide = false
			stripe.CanTouch = false
			stripe.CanQuery = false
		end
	end

	local lighting = Instance.new("Model")
	lighting.Name = "DistrictLighting"
	lighting.Parent = district
	local lampCount = math.max(2, math.floor(streetLength / 55))
	for index = 0, lampCount do
		local alpha = index / lampCount
		local z = startZ + streetLength * alpha
		local xDirection = if index % 2 == 0 then -1 else 1
		createLamp(
			lighting,
			string.format("StreetLamp_%02d", index),
			CFrame.new(xDirection * 21, 0, z),
			if xDirection < 0 then COLORS.Cyan else COLORS.Pink,
			14
		)
	end

	local skyline = Instance.new("Model")
	skyline.Name = "DistrictSkyline"
	skyline.Parent = district
	local blockCount = math.max(3, math.floor(streetLength / 68))
	for index = 0, blockCount - 1 do
		local blockLength = streetLength / blockCount - 5
		local z = startZ + blockLength * 0.5 + index * (streetLength / blockCount)
		for _, xDirection in { -1, 1 } do
			local height = 17 + ((index * 7 + (if xDirection < 0 then 3 else 0)) % 14)
			createPart(
				skyline,
				string.format("Block_%02d_%s", index, if xDirection < 0 then "West" else "East"),
				Vector3.new(28, height, blockLength),
				CFrame.new(xDirection * 99, height * 0.5 - 0.4, z),
				if index % 2 == 0 then Color3.fromRGB(27, 30, 40) else COLORS.Concrete,
				Enum.Material.Concrete
			)
			local roofCap = createPart(
				skyline,
				string.format("RoofCap_%02d_%s", index, if xDirection < 0 then "West" else "East"),
				Vector3.new(28.4, 0.35, blockLength + 0.4),
				CFrame.new(xDirection * 99, height - 0.2, z),
				Color3.fromRGB(19, 23, 32),
				Enum.Material.Metal
			)
			roofCap.CanCollide = false
			local roofAccent = if xDirection < 0 then COLORS.Cyan else COLORS.Pink
			for _, zEdge in { -1, 1 } do
				local rail = createPart(
					skyline,
					string.format(
						"RoofRailZ_%02d_%s_%s",
						index,
						if xDirection < 0 then "West" else "East",
						if zEdge < 0 then "South" else "North"
					),
					Vector3.new(28.7, 0.24, 0.24),
					CFrame.new(
						xDirection * 99,
						height + 0.02,
						z + zEdge * (blockLength * 0.5 + 0.12)
					),
					roofAccent,
					Enum.Material.Neon
				)
				rail.CanCollide = false
				rail.CanTouch = false
				rail.CanQuery = false
			end
			for _, xEdge in { -1, 1 } do
				local rail = createPart(
					skyline,
					string.format(
						"RoofRailX_%02d_%s_%s",
						index,
						if xDirection < 0 then "West" else "East",
						if xEdge < 0 then "Inner" else "Outer"
					),
					Vector3.new(0.24, 0.24, blockLength + 0.4),
					CFrame.new(xDirection * 99 + xEdge * 14.22, height + 0.02, z),
					roofAccent,
					Enum.Material.Neon
				)
				rail.CanCollide = false
				rail.CanTouch = false
				rail.CanQuery = false
			end
		end
	end

	createEndLandmark(district, CFrame.new(0, 0, endZ - 10))
	return district
end

local function configureLighting()
	Lighting.ClockTime = 14.15
	Lighting.Brightness = 3
	Lighting.ExposureCompensation = 0.18
	Lighting.Ambient = Color3.fromRGB(144, 158, 174)
	Lighting.OutdoorAmbient = Color3.fromRGB(176, 190, 205)
	Lighting.EnvironmentDiffuseScale = 0.72
	Lighting.EnvironmentSpecularScale = 0.5
	Lighting.GlobalShadows = true
	Lighting.ShadowSoftness = 0.55

	local atmosphere: Atmosphere? = nil
	local colorCorrection: ColorCorrectionEffect? = nil
	local bloom: BloomEffect? = nil
	local sunRays: SunRaysEffect? = nil
	for _, child in Lighting:GetChildren() do
		if child:GetAttribute(LIGHTING_EFFECT_ATTRIBUTE) == true then
			if child:IsA("Atmosphere") then
				atmosphere = child
			elseif child:IsA("ColorCorrectionEffect") then
				colorCorrection = child
			elseif child:IsA("BloomEffect") then
				bloom = child
			elseif child:IsA("SunRaysEffect") then
				sunRays = child
			end
		end
	end

	if not atmosphere then
		atmosphere = Instance.new("Atmosphere")
		atmosphere.Name = "PannaAtmosphere"
		atmosphere:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		atmosphere.Parent = Lighting
	end
	atmosphere.Density = 0.18
	atmosphere.Offset = 0.2
	atmosphere.Color = Color3.fromRGB(199, 225, 255)
	atmosphere.Decay = Color3.fromRGB(121, 157, 190)
	atmosphere.Glare = 0.06
	atmosphere.Haze = 0.65

	if not colorCorrection then
		colorCorrection = Instance.new("ColorCorrectionEffect")
		colorCorrection.Name = "PannaColorGrade"
		colorCorrection:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		colorCorrection.Parent = Lighting
	end
	colorCorrection.Brightness = 0.04
	colorCorrection.Contrast = 0.06
	colorCorrection.Saturation = 0.08
	colorCorrection.TintColor = Color3.fromRGB(255, 248, 235)

	if not bloom then
		bloom = Instance.new("BloomEffect")
		bloom.Name = "PannaNeonBloom"
		bloom:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		bloom.Parent = Lighting
	end
	bloom.Intensity = 0.12
	bloom.Size = 18
	bloom.Threshold = 1.4

	if not sunRays then
		sunRays = Instance.new("SunRaysEffect")
		sunRays.Name = "PannaSunRays"
		sunRays:SetAttribute(LIGHTING_EFFECT_ATTRIBUTE, true)
		sunRays.Parent = Lighting
	end
	sunRays.Intensity = 0.035
	sunRays.Spread = 0.72
end

local function validateConfig(config: Config)
	local world = config.World
	local ball = config.Ball
	assert(world.RootName ~= "", "Config.World.RootName must not be empty")
	assert(
		#world.ArenaPositions >= ARENA_COUNT,
		string.format("Config.World.ArenaPositions must contain at least %d arenas", ARENA_COUNT)
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

local function configureBallPhysics(root: Model, ballSettings: BallSettings)
	local physicalProperties = PhysicalProperties.new(
		ballSettings.Density,
		ballSettings.Friction,
		ballSettings.Elasticity,
		1,
		1
	)
	for _, descendant in root:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and (descendant.Name == "Ball" or descendant:GetAttribute("TrainingBall") == true)
		then
			descendant.CustomPhysicalProperties = physicalProperties
		end
	end
end

local function isCompatibleBakedDistrict(candidate: Instance, config: Config): boolean
	if not candidate:IsA("Model") then
		return false
	end
	if
		candidate:GetAttribute("LayoutVersion") ~= config.Version
		or candidate:GetAttribute("ArenaCount") ~= ARENA_COUNT
		or not candidate:FindFirstChild("DistrictEnvironment")
		or not candidate:FindFirstChild("Lobby")
	then
		return false
	end
	local arenas = candidate:FindFirstChild("Arenas")
	if not arenas or not arenas:IsA("Folder") then
		return false
	end
	local arenaCount = 0
	for _, child in arenas:GetChildren() do
		if child:IsA("Model") then
			arenaCount += 1
		end
	end
	return arenaCount == ARENA_COUNT
end

function WorldBuilder.Build(config: Config): Model
	validateConfig(config)
	local existingRoot = Workspace:FindFirstChild(config.World.RootName)
	if existingRoot and isCompatibleBakedDistrict(existingRoot, config) then
		configureBallPhysics(existingRoot, config.Ball)
		configureLighting()
		return existingRoot
	end

	-- Build off-tree first, so a construction error leaves the current playable world intact.
	local root = Instance.new("Model")
	root.Name = config.World.RootName
	root:SetAttribute("DistrictName", "PannaDistrict")
	root:SetAttribute("GeneratedBy", "WorldBuilder")
	root:SetAttribute("ArenaCount", ARENA_COUNT)
	root:SetAttribute("LayoutVersion", config.Version)
	root:SetAttribute("RoomStateContract", table.concat(ROOM_STATES, ","))

	createPannaDistrict(root, config.World)
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

	configureBallPhysics(root, config.Ball)
	if existingRoot then
		existingRoot:Destroy()
	end
	root.Parent = Workspace
	configureLighting()
	return root
end

return table.freeze(WorldBuilder)
