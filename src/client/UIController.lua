--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local GuiService = game:GetService("GuiService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local ControlCatalog = require(script.Parent:WaitForChild("ControlCatalog"))
local ACTION_ORDER = ControlCatalog.ActionOrder
local ACTION_PRESENTATION = ControlCatalog.Actions
local ABILITY_GUIDE = ControlCatalog.GuideEntries

local COLORS = table.freeze({
	Background = Color3.fromRGB(18, 22, 30),
	Panel = Color3.fromRGB(29, 35, 46),
	PanelLight = Color3.fromRGB(45, 53, 68),
	Text = Color3.fromRGB(250, 252, 255),
	Muted = Color3.fromRGB(171, 184, 201),
	Cyan = Color3.fromRGB(0, 214, 242),
	Pink = Color3.fromRGB(255, 61, 129),
	Lime = Color3.fromRGB(91, 230, 126),
	Active = Color3.fromRGB(34, 151, 165),
	Warning = Color3.fromRGB(255, 221, 57),
	Danger = Color3.fromRGB(255, 77, 90),
})

local function addCorner(parent: GuiObject, radius: number): UICorner
	local corner = Instance.new("UICorner")
	corner.CornerRadius = UDim.new(0, radius)
	corner.Parent = parent
	return corner
end

local function addStroke(parent: GuiObject, color: Color3, transparency: number): UIStroke
	local stroke = Instance.new("UIStroke")
	stroke.Color = color
	stroke.Transparency = transparency
	stroke.Thickness = 1
	stroke.Parent = parent
	return stroke
end

local function makeLabel(
	parent: Instance,
	name: string,
	text: string,
	font: Enum.Font,
	textSize: number,
	color: Color3
): TextLabel
	local label = Instance.new("TextLabel")
	label.Name = name
	label.BackgroundTransparency = 1
	label.BorderSizePixel = 0
	label.Font = font
	label.Text = text
	label.TextColor3 = color
	label.TextSize = textSize
	label.TextWrapped = false
	label.Parent = parent
	return label
end

local function makeButton(parent: Instance, name: string, text: string): TextButton
	local button = Instance.new("TextButton")
	button.Name = name
	button.AutoButtonColor = false
	button.BackgroundColor3 = COLORS.Cyan
	button.BorderSizePixel = 0
	button.Font = Enum.Font.GothamBlack
	button.Text = text
	button.TextColor3 = COLORS.Background
	button.TextSize = 15
	button.Parent = parent
	addCorner(button, 10)
	addStroke(button, Color3.new(1, 1, 1), 0.72)
	return button
end

local function isVisibleInGui(object: GuiObject, root: ScreenGui): boolean
	if not root.Enabled then
		return false
	end

	local current: Instance? = object
	while current and current ~= root do
		if current:IsA("GuiObject") and not current.Visible then
			return false
		end
		current = current.Parent
	end
	return current == root
end

local function read(source: any, ...: string): any
	if typeof(source) ~= "table" then
		return nil
	end

	for _, key in { ... } do
		local value = source[key]
		if value ~= nil then
			return value
		end
	end
	return nil
end

local function readNumber(source: any, defaultValue: number, ...: string): number
	local value = read(source, ...)
	if typeof(value) == "number" then
		return value
	end
	return defaultValue
end

local function readBoolean(source: any, defaultValue: boolean, ...: string): boolean
	local value = read(source, ...)
	if typeof(value) == "boolean" then
		return value
	end
	return defaultValue
end

local function readString(source: any, defaultValue: string, ...: string): string
	local value = read(source, ...)
	if typeof(value) == "string" then
		return value
	end
	if typeof(value) == "number" then
		return tostring(value)
	end
	return defaultValue
end

local function formatCompact(value: number): string
	local absolute = math.abs(value)
	if absolute >= 1_000_000 then
		return string.format("%.1fM", value / 1_000_000)
	elseif absolute >= 1_000 then
		return string.format("%.1fK", value / 1_000)
	end
	return tostring(math.floor(value + 0.5))
end

local function formatTime(seconds: number): string
	local rounded = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", math.floor(rounded / 60), rounded % 60)
end

local function readableStatus(status: string): string
	local known = {
		idle = "READY FOR STREET FOOTBALL",
		ready = "READY FOR STREET FOOTBALL",
		queued = "SEARCHING FOR AN OPPONENT",
		searching = "SEARCHING FOR AN OPPONENT",
		["searching for opponent"] = "SEARCHING FOR AN OPPONENT",
		waiting = "WAITING IN QUEUE",
		waiting_arena = "WAITING FOR A FREE COURT",
		["waiting for free arena"] = "WAITING FOR A FREE COURT",
		matched = "MATCH FOUND",
	}
	local normalized = string.lower(status)
	return known[normalized] or string.upper(string.gsub(status, "_", " "))
end

local function readableArena(value: string): string
	if value == "" then
		return "NO COURT SELECTED"
	end
	return string.upper(string.gsub(value, "_", " "))
end

local function preferredInputIsTouch(): boolean
	local success, preferred = pcall(function(): any
		return UserInputService.PreferredInput
	end)
	if success and typeof(preferred) == "EnumItem" then
		return preferred.Name == "Touch"
	end
	return UserInputService:GetLastInputType() == Enum.UserInputType.Touch
end

local function readArenaState(source: any): (string, string, number, number, string)
	local nested = read(source, "arena", "Arena", "selectedArena", "SelectedArena", "room", "Room")
	local arenaSource = if typeof(nested) == "table" then nested else source
	local nestedId = if typeof(nested) == "string" then nested else ""
	local arenaId = readString(
		arenaSource,
		nestedId,
		"arenaId",
		"ArenaId",
		"selectedArenaId",
		"SelectedArenaId",
		"roomId",
		"RoomId"
	)
	if arenaId == "" and typeof(nested) == "table" then
		arenaId = readString(arenaSource, "", "id", "Id")
	end
	local arenaName = readString(
		arenaSource,
		arenaId,
		"arenaName",
		"ArenaName",
		"roomName",
		"RoomName",
		"displayName",
		"DisplayName"
	)
	if typeof(nested) == "table" then
		local nestedName = readString(arenaSource, "", "name", "Name")
		if nestedName ~= "" then
			arenaName = nestedName
		end
	end
	local occupants = readNumber(
		arenaSource,
		0,
		"occupants",
		"Occupants",
		"playersInRoom",
		"PlayersInRoom",
		"occupied",
		"Occupied"
	)
	local capacity = readNumber(arenaSource, 2, "capacity", "Capacity", "maxPlayers", "MaxPlayers")
	local roomStatus =
		readString(arenaSource, "", "roomStatus", "RoomStatus", "arenaStatus", "ArenaStatus")
	return arenaId, arenaName, math.max(0, occupants), math.max(1, capacity), roomStatus
end

type ControllerFields = {
	Gui: ScreenGui,
	TopBar: Frame,
	Brand: TextLabel,
	CoinsValue: TextLabel,
	LevelValue: TextLabel,
	RatingValue: TextLabel,
	QueueCard: Frame,
	QueueKicker: TextLabel,
	QueueOccupancy: TextLabel,
	QueueStatus: TextLabel,
	QueueButton: TextButton,
	MatchCard: Frame,
	MatchArena: TextLabel,
	MatchPhase: TextLabel,
	HomeName: TextLabel,
	AwayName: TextLabel,
	Score: TextLabel,
	PannaScore: TextLabel,
	Timer: TextLabel,
	PowerContainer: Frame,
	PowerFill: Frame,
	PowerCaption: TextLabel,
	PowerValue: TextLabel,
	BallStatus: TextLabel,
	ActionBar: Frame,
	ActionWidgets: { [string]: any },
	ActionFeedbackLabel: TextLabel,
	ScreenFlash: Frame,
	Notification: CanvasGroup,
	NotificationAccent: Frame,
	NotificationTitle: TextLabel,
	NotificationBody: TextLabel,
	RematchButton: TextButton,
	ResultExitButton: TextButton,
	LeaveMatchButton: TextButton,
	HelpButton: TextButton,
	TouchHelpButton: TextButton,
	ControlsDimmer: Frame,
	ControlsGuide: Frame,
	ControlsCloseButton: TextButton,
	_connections: { RBXScriptConnection },
	_queueCallback: ((string) -> ())?,
	_queueJoined: boolean,
	_queuePending: boolean,
	_matchVisible: boolean,
	_matchState: string,
	_selectedArena: string,
	_isTouchLayout: boolean,
	_controlsGuideVisible: boolean,
	_controlsGuideShown: boolean,
	_previousSelectedObject: GuiObject?,
	_exitArmToken: number,
	_exitArmedUntil: number,
	_localDeadline: number?,
	_serverDeadline: number?,
	_notificationToken: number,
	_notificationTween: Tween?,
	_actionFeedbackToken: number,
	_actionFeedbackTween: Tween?,
	_shotMode: string,
	_ballStatusKey: string,
	_flashTween: Tween?,
	_shakeEndsAt: number,
	_shakeStrength: number,
	_shakeHumanoid: Humanoid?,
	_shakeBaseOffset: Vector3?,
	_destroyed: boolean,
}

local UIController = {}
UIController.__index = UIController

export type UIController = typeof(setmetatable({} :: ControllerFields, UIController))

local function makeStatChip(parent: Instance, name: string, caption: string): (Frame, TextLabel)
	local chip = Instance.new("Frame")
	chip.Name = name
	chip.BackgroundColor3 = COLORS.PanelLight
	chip.BackgroundTransparency = 0.18
	chip.BorderSizePixel = 0
	chip.Size = UDim2.fromScale(0.32, 0.72)
	chip.Parent = parent
	addCorner(chip, 10)

	local captionLabel = makeLabel(chip, "Caption", caption, Enum.Font.GothamBold, 9, COLORS.Muted)
	captionLabel.Position = UDim2.fromOffset(10, 6)
	captionLabel.Size = UDim2.new(1, -20, 0, 11)
	captionLabel.TextXAlignment = Enum.TextXAlignment.Left

	local value = makeLabel(chip, "Value", "0", Enum.Font.GothamBlack, 16, COLORS.Text)
	value.Position = UDim2.fromOffset(10, 18)
	value.Size = UDim2.new(1, -20, 0, 21)
	value.TextXAlignment = Enum.TextXAlignment.Left
	return chip, value
end

function UIController.new(): UIController
	local playerGui = LOCAL_PLAYER:WaitForChild("PlayerGui") :: PlayerGui
	local gui = Instance.new("ScreenGui")
	gui.Name = "PannaHUD"
	gui.DisplayOrder = 30
	gui.IgnoreGuiInset = false
	gui.ResetOnSpawn = false
	gui.ZIndexBehavior = Enum.ZIndexBehavior.Sibling
	gui.Parent = playerGui

	local screenFlash = Instance.new("Frame")
	screenFlash.Name = "ImpactFlash"
	screenFlash.Active = false
	screenFlash.BackgroundColor3 = COLORS.Cyan
	screenFlash.BackgroundTransparency = 1
	screenFlash.BorderSizePixel = 0
	screenFlash.Size = UDim2.fromScale(1, 1)
	screenFlash.Visible = false
	screenFlash.ZIndex = 100
	screenFlash.Parent = gui

	local topBar = Instance.new("Frame")
	topBar.Name = "TopBar"
	topBar.AnchorPoint = Vector2.new(0.5, 0)
	topBar.BackgroundColor3 = COLORS.Panel
	topBar.BackgroundTransparency = 0.08
	topBar.BorderSizePixel = 0
	topBar.Position = UDim2.new(0.5, 0, 0, 12)
	topBar.Size = UDim2.new(1, -24, 0, 56)
	topBar.Parent = gui
	addCorner(topBar, 14)
	addStroke(topBar, COLORS.Cyan, 0.68)

	local topConstraint = Instance.new("UISizeConstraint")
	topConstraint.MaxSize = Vector2.new(720, 56)
	topConstraint.MinSize = Vector2.new(300, 56)
	topConstraint.Parent = topBar

	local brand =
		makeLabel(topBar, "Brand", "PANNA//STREET", Enum.Font.GothamBlack, 15, COLORS.Text)
	brand.Position = UDim2.fromOffset(18, 0)
	brand.Size = UDim2.new(0, 118, 1, 0)
	brand.TextXAlignment = Enum.TextXAlignment.Left

	local brandMark = Instance.new("Frame")
	brandMark.Name = "BrandMark"
	brandMark.BackgroundColor3 = COLORS.Pink
	brandMark.BorderSizePixel = 0
	brandMark.Position = UDim2.new(0, 10, 0.5, -12)
	brandMark.Size = UDim2.fromOffset(3, 24)
	brandMark.Parent = topBar
	addCorner(brandMark, 2)

	local helpButton = makeButton(topBar, "HelpButton", "HELP")
	helpButton.BackgroundColor3 = COLORS.PanelLight
	helpButton.Position = UDim2.fromOffset(132, 12)
	helpButton.Size = UDim2.fromOffset(38, 32)
	helpButton.TextColor3 = COLORS.Cyan
	helpButton.TextSize = 10
	helpButton.ZIndex = 5

	local stats = Instance.new("Frame")
	stats.Name = "Stats"
	stats.BackgroundTransparency = 1
	stats.Position = UDim2.fromOffset(176, 0)
	stats.Size = UDim2.new(1, -184, 1, 0)
	stats.Parent = topBar

	local statLayout = Instance.new("UIListLayout")
	statLayout.FillDirection = Enum.FillDirection.Horizontal
	statLayout.HorizontalAlignment = Enum.HorizontalAlignment.Right
	statLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	statLayout.Padding = UDim.new(0, 7)
	statLayout.Parent = stats

	local _, coinsValue = makeStatChip(stats, "Coins", "COINS")
	local _, levelValue = makeStatChip(stats, "Level", "LEVEL")
	local _, ratingValue = makeStatChip(stats, "Rating", "RATING")

	local touchHelpButton = makeButton(gui, "TouchHelpButton", "?")
	touchHelpButton.AnchorPoint = Vector2.new(1, 0)
	touchHelpButton.BackgroundColor3 = COLORS.Panel
	touchHelpButton.Position = UDim2.new(1, -12, 0, 132)
	touchHelpButton.Size = UDim2.fromOffset(38, 38)
	touchHelpButton.TextColor3 = COLORS.Cyan
	touchHelpButton.TextSize = 18
	touchHelpButton.Visible = false
	touchHelpButton.ZIndex = 75

	local matchCard = Instance.new("Frame")
	matchCard.Name = "MatchHUD"
	matchCard.AnchorPoint = Vector2.new(0.5, 0)
	matchCard.BackgroundColor3 = COLORS.Panel
	matchCard.BackgroundTransparency = 0.05
	matchCard.BorderSizePixel = 0
	matchCard.Position = UDim2.new(0.5, 0, 0, 80)
	matchCard.Size = UDim2.new(1, -24, 0, 112)
	matchCard.Visible = false
	matchCard.Parent = gui
	addCorner(matchCard, 16)
	addStroke(matchCard, COLORS.Pink, 0.55)

	local matchConstraint = Instance.new("UISizeConstraint")
	matchConstraint.MaxSize = Vector2.new(680, 112)
	matchConstraint.MinSize = Vector2.new(300, 112)
	matchConstraint.Parent = matchCard

	local matchArena =
		makeLabel(matchCard, "Arena", "COURT --", Enum.Font.GothamBold, 9, COLORS.Muted)
	matchArena.Position = UDim2.fromOffset(18, 8)
	matchArena.Size = UDim2.new(0.28, -18, 0, 14)
	matchArena.TextTruncate = Enum.TextTruncate.AtEnd
	matchArena.TextXAlignment = Enum.TextXAlignment.Left

	local matchPhase =
		makeLabel(matchCard, "Phase", "1V1 • ACTIVE", Enum.Font.GothamBold, 10, COLORS.Cyan)
	matchPhase.AnchorPoint = Vector2.new(0.5, 0)
	matchPhase.Position = UDim2.new(0.5, 0, 0, 8)
	matchPhase.Size = UDim2.new(0.5, 0, 0, 14)
	matchPhase.TextXAlignment = Enum.TextXAlignment.Center

	local homeName = makeLabel(matchCard, "HomeName", "HOME", Enum.Font.GothamBold, 16, COLORS.Text)
	homeName.Position = UDim2.fromOffset(18, 30)
	homeName.Size = UDim2.new(0.34, -18, 0, 27)
	homeName.TextTruncate = Enum.TextTruncate.AtEnd
	homeName.TextXAlignment = Enum.TextXAlignment.Left

	local awayName = makeLabel(matchCard, "AwayName", "AWAY", Enum.Font.GothamBold, 16, COLORS.Text)
	awayName.AnchorPoint = Vector2.new(1, 0)
	awayName.Position = UDim2.new(1, -18, 0, 30)
	awayName.Size = UDim2.new(0.34, -18, 0, 27)
	awayName.TextTruncate = Enum.TextTruncate.AtEnd
	awayName.TextXAlignment = Enum.TextXAlignment.Right

	local score = makeLabel(matchCard, "Score", "0  :  0", Enum.Font.GothamBlack, 29, COLORS.Text)
	score.AnchorPoint = Vector2.new(0.5, 0)
	score.Position = UDim2.new(0.5, 0, 0, 24)
	score.Size = UDim2.new(0.3, 0, 0, 38)
	score.TextXAlignment = Enum.TextXAlignment.Center

	local pannaScore =
		makeLabel(matchCard, "PannaScore", "PANNA  0 — 0", Enum.Font.GothamBold, 10, COLORS.Pink)
	pannaScore.AnchorPoint = Vector2.new(0.5, 0)
	pannaScore.Position = UDim2.new(0.5, 0, 0, 63)
	pannaScore.Size = UDim2.new(0.4, 0, 0, 15)
	pannaScore.TextXAlignment = Enum.TextXAlignment.Center

	local timerPill = Instance.new("Frame")
	timerPill.Name = "TimerPill"
	timerPill.AnchorPoint = Vector2.new(0.5, 1)
	timerPill.BackgroundColor3 = COLORS.Background
	timerPill.BackgroundTransparency = 0.08
	timerPill.BorderSizePixel = 0
	timerPill.Position = UDim2.new(0.5, 0, 1, -9)
	timerPill.Size = UDim2.fromOffset(100, 27)
	timerPill.Parent = matchCard
	addCorner(timerPill, 12)

	local timer = makeLabel(timerPill, "Timer", "0:00", Enum.Font.Code, 18, COLORS.Lime)
	timer.Size = UDim2.fromScale(1, 1)
	timer.TextXAlignment = Enum.TextXAlignment.Center

	local ballStatus =
		makeLabel(matchCard, "BallStatus", "● FREE", Enum.Font.GothamBlack, 9, COLORS.Muted)
	ballStatus.Position = UDim2.new(0, 18, 1, -27)
	ballStatus.Size = UDim2.fromOffset(94, 18)
	ballStatus.TextXAlignment = Enum.TextXAlignment.Left

	local leaveMatchButton = makeButton(matchCard, "LeaveMatchButton", "EXIT")
	leaveMatchButton.AnchorPoint = Vector2.new(1, 0)
	leaveMatchButton.BackgroundColor3 = COLORS.PanelLight
	leaveMatchButton.Position = UDim2.new(1, -10, 0, 8)
	leaveMatchButton.Size = UDim2.fromOffset(78, 24)
	leaveMatchButton.TextColor3 = COLORS.Text
	leaveMatchButton.TextSize = 10
	leaveMatchButton.Visible = false

	local queueCard = Instance.new("Frame")
	queueCard.Name = "QueueCard"
	queueCard.AnchorPoint = Vector2.new(0.5, 1)
	queueCard.BackgroundColor3 = COLORS.Panel
	queueCard.BackgroundTransparency = 0.04
	queueCard.BorderSizePixel = 0
	queueCard.Position = UDim2.new(0.5, 0, 1, -24)
	queueCard.Size = UDim2.new(1, -32, 0, 108)
	queueCard.Parent = gui
	addCorner(queueCard, 16)
	addStroke(queueCard, COLORS.Cyan, 0.55)

	local queueConstraint = Instance.new("UISizeConstraint")
	queueConstraint.MaxSize = Vector2.new(390, 108)
	queueConstraint.MinSize = Vector2.new(280, 108)
	queueConstraint.Parent = queueCard

	local queueKicker = makeLabel(
		queueCard,
		"Kicker",
		"WALK INTO A 1V1 COURT",
		Enum.Font.GothamBold,
		10,
		COLORS.Pink
	)
	queueKicker.Position = UDim2.fromOffset(14, 10)
	queueKicker.Size = UDim2.new(1, -92, 0, 13)
	queueKicker.TextTruncate = Enum.TextTruncate.AtEnd
	queueKicker.TextXAlignment = Enum.TextXAlignment.Left

	local queueOccupancy =
		makeLabel(queueCard, "Occupancy", "OPEN", Enum.Font.GothamBlack, 10, COLORS.Cyan)
	queueOccupancy.AnchorPoint = Vector2.new(1, 0)
	queueOccupancy.Position = UDim2.new(1, -14, 0, 10)
	queueOccupancy.Size = UDim2.fromOffset(70, 13)
	queueOccupancy.TextXAlignment = Enum.TextXAlignment.Right

	local queueStatus = makeLabel(
		queueCard,
		"Status",
		"CONNECTING TO THE STREET...",
		Enum.Font.Gotham,
		11,
		COLORS.Muted
	)
	queueStatus.Position = UDim2.fromOffset(14, 31)
	queueStatus.Size = UDim2.new(1, -28, 0, 16)
	queueStatus.TextTruncate = Enum.TextTruncate.AtEnd
	queueStatus.TextXAlignment = Enum.TextXAlignment.Left

	local queueButton = makeButton(queueCard, "QueueButton", "CONNECTING...")
	queueButton.Position = UDim2.fromOffset(14, 62)
	queueButton.Size = UDim2.new(1, -28, 0, 35)
	queueButton.Active = false

	local powerContainer = Instance.new("Frame")
	powerContainer.Name = "KickPower"
	powerContainer.AnchorPoint = Vector2.new(0.5, 1)
	powerContainer.BackgroundColor3 = COLORS.Panel
	powerContainer.BackgroundTransparency = 0.08
	powerContainer.BorderSizePixel = 0
	powerContainer.Position = UDim2.new(0.5, 0, 1, -128)
	powerContainer.Size = UDim2.new(1, -80, 0, 38)
	powerContainer.Visible = false
	powerContainer.Parent = gui
	addCorner(powerContainer, 12)
	addStroke(powerContainer, COLORS.Cyan, 0.64)

	local powerConstraint = Instance.new("UISizeConstraint")
	powerConstraint.MaxSize = Vector2.new(390, 38)
	powerConstraint.MinSize = Vector2.new(200, 32)
	powerConstraint.Parent = powerContainer

	local powerTrack = Instance.new("Frame")
	powerTrack.Name = "Track"
	powerTrack.BackgroundColor3 = COLORS.Background
	powerTrack.BackgroundTransparency = 0.04
	powerTrack.BorderSizePixel = 0
	powerTrack.Position = UDim2.fromOffset(10, 9)
	powerTrack.Size = UDim2.new(1, -88, 0, 20)
	powerTrack.ClipsDescendants = true
	powerTrack.Parent = powerContainer
	addCorner(powerTrack, 8)

	local powerFill = Instance.new("Frame")
	powerFill.Name = "Fill"
	powerFill.BackgroundColor3 = COLORS.Cyan
	powerFill.BorderSizePixel = 0
	powerFill.Size = UDim2.fromScale(0, 1)
	powerFill.Parent = powerTrack
	addCorner(powerFill, 8)

	local powerCaption =
		makeLabel(powerTrack, "Caption", "SHOT POWER", Enum.Font.GothamBlack, 9, COLORS.Text)
	powerCaption.Position = UDim2.fromOffset(8, 0)
	powerCaption.Size = UDim2.new(1, -16, 1, 0)
	powerCaption.TextXAlignment = Enum.TextXAlignment.Left
	powerCaption.ZIndex = 2

	local powerValue =
		makeLabel(powerContainer, "Value", "0%", Enum.Font.GothamBlack, 13, COLORS.Text)
	powerValue.AnchorPoint = Vector2.new(1, 0)
	powerValue.Position = UDim2.new(1, -10, 0, 0)
	powerValue.Size = UDim2.new(0, 60, 1, 0)
	powerValue.TextXAlignment = Enum.TextXAlignment.Right

	local actionBar = Instance.new("Frame")
	actionBar.Name = "ActionBar"
	actionBar.AnchorPoint = Vector2.new(0.5, 1)
	actionBar.BackgroundTransparency = 1
	actionBar.Position = UDim2.new(0.5, 0, 1, -18)
	actionBar.Size = UDim2.fromOffset(660, 54)
	actionBar.Visible = false
	actionBar.Parent = gui

	local actionScale = Instance.new("UIScale")
	actionScale.Scale = 1
	actionScale.Parent = actionBar

	local actionLayout = Instance.new("UIListLayout")
	actionLayout.FillDirection = Enum.FillDirection.Horizontal
	actionLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
	actionLayout.VerticalAlignment = Enum.VerticalAlignment.Center
	actionLayout.Padding = UDim.new(0, 6)
	actionLayout.Parent = actionBar

	local actionWidgets: { [string]: any } = {}
	for _, action in ACTION_ORDER do
		local presentation = (ACTION_PRESENTATION :: any)[action]
		local chip = Instance.new("Frame")
		chip.Name = action
		chip.BackgroundColor3 = COLORS.Panel
		chip.BackgroundTransparency = 0.06
		chip.BorderSizePixel = 0
		chip.ClipsDescendants = true
		chip.Size = UDim2.fromOffset(88, 50)
		chip.Parent = actionBar
		addCorner(chip, 11)
		addStroke(chip, COLORS.Cyan, 0.72)

		local cooldownFill = Instance.new("Frame")
		cooldownFill.Name = "CooldownFill"
		cooldownFill.AnchorPoint = Vector2.new(0, 1)
		cooldownFill.BackgroundColor3 = COLORS.Background
		cooldownFill.BackgroundTransparency = 0.18
		cooldownFill.BorderSizePixel = 0
		cooldownFill.Position = UDim2.fromScale(0, 1)
		cooldownFill.Size = UDim2.fromScale(1, 0)
		cooldownFill.ZIndex = 2
		cooldownFill.Parent = chip

		local title =
			makeLabel(chip, "Title", presentation.title, Enum.Font.GothamBlack, 11, COLORS.Text)
		title.Position = UDim2.fromOffset(8, 7)
		title.Size = UDim2.new(1, -16, 0, 14)
		title.TextXAlignment = Enum.TextXAlignment.Left
		title.ZIndex = 3

		local key =
			makeLabel(chip, "Binding", presentation.keyboard, Enum.Font.GothamBold, 9, COLORS.Cyan)
		key.Position = UDim2.fromOffset(8, 27)
		key.Size = UDim2.new(1, -16, 0, 12)
		key.TextXAlignment = Enum.TextXAlignment.Left
		key.ZIndex = 3

		local cooldown = makeLabel(chip, "Cooldown", "", Enum.Font.Code, 13, COLORS.Warning)
		cooldown.Position = UDim2.fromOffset(8, 20)
		cooldown.Size = UDim2.new(1, -16, 0, 22)
		cooldown.TextXAlignment = Enum.TextXAlignment.Right
		cooldown.ZIndex = 4

		actionWidgets[action] = {
			Container = chip,
			Fill = cooldownFill,
			Title = title,
			Binding = key,
			Cooldown = cooldown,
			Pending = false,
		}
	end

	local actionFeedbackLabel =
		makeLabel(gui, "ActionFeedback", "", Enum.Font.GothamBlack, 11, COLORS.Text)
	actionFeedbackLabel.AnchorPoint = Vector2.new(0.5, 0.5)
	actionFeedbackLabel.BackgroundColor3 = COLORS.Panel
	actionFeedbackLabel.BackgroundTransparency = 0.14
	actionFeedbackLabel.Position = UDim2.fromScale(0.5, 0.64)
	actionFeedbackLabel.Size = UDim2.fromOffset(260, 28)
	actionFeedbackLabel.TextTransparency = 1
	actionFeedbackLabel.Visible = false
	actionFeedbackLabel.ZIndex = 45
	addCorner(actionFeedbackLabel, 10)
	addStroke(actionFeedbackLabel, COLORS.Danger, 0.35)

	local notification = Instance.new("CanvasGroup")
	notification.Name = "Notification"
	notification.AnchorPoint = Vector2.new(0.5, 0.5)
	notification.BackgroundColor3 = COLORS.Panel
	notification.BackgroundTransparency = 0.02
	notification.BorderSizePixel = 0
	notification.GroupTransparency = 1
	notification.Position = UDim2.new(0.5, 0, 0.39, 12)
	notification.Size = UDim2.new(1, -32, 0, 104)
	notification.Visible = false
	notification.Parent = gui
	addCorner(notification, 18)
	addStroke(notification, COLORS.Pink, 0.35)

	local notificationConstraint = Instance.new("UISizeConstraint")
	notificationConstraint.MaxSize = Vector2.new(520, 104)
	notificationConstraint.MinSize = Vector2.new(280, 104)
	notificationConstraint.Parent = notification

	local notificationAccent = Instance.new("Frame")
	notificationAccent.Name = "Accent"
	notificationAccent.BackgroundColor3 = COLORS.Pink
	notificationAccent.BorderSizePixel = 0
	notificationAccent.Size = UDim2.new(0, 6, 1, 0)
	notificationAccent.Parent = notification
	addCorner(notificationAccent, 18)

	local notificationTitle =
		makeLabel(notification, "Title", "PANNA!", Enum.Font.GothamBlack, 27, COLORS.Text)
	notificationTitle.Position = UDim2.fromOffset(24, 15)
	notificationTitle.Size = UDim2.new(1, -48, 0, 34)
	notificationTitle.TextXAlignment = Enum.TextXAlignment.Center

	local notificationBody =
		makeLabel(notification, "Body", "THROUGH THE GATE", Enum.Font.GothamBold, 12, COLORS.Muted)
	notificationBody.Position = UDim2.fromOffset(24, 55)
	notificationBody.Size = UDim2.new(1, -48, 0, 28)
	notificationBody.TextWrapped = true
	notificationBody.TextXAlignment = Enum.TextXAlignment.Center

	local rematchButton = makeButton(gui, "RematchButton", "REMATCH")
	rematchButton.AnchorPoint = Vector2.new(0.5, 0.5)
	rematchButton.Position = UDim2.new(0.5, -88, 0.52, 82)
	rematchButton.Size = UDim2.fromOffset(164, 38)
	rematchButton.Visible = false

	local resultExitButton = makeButton(gui, "ResultExitButton", "EXIT COURT")
	resultExitButton.AnchorPoint = Vector2.new(0.5, 0.5)
	resultExitButton.BackgroundColor3 = COLORS.Danger
	resultExitButton.Position = UDim2.new(0.5, 88, 0.52, 82)
	resultExitButton.Size = UDim2.fromOffset(164, 38)
	resultExitButton.TextColor3 = COLORS.Text
	resultExitButton.Visible = false

	local controlsDimmer = Instance.new("Frame")
	controlsDimmer.Name = "ControlsDimmer"
	controlsDimmer.Active = true
	controlsDimmer.BackgroundColor3 = Color3.fromRGB(2, 5, 9)
	controlsDimmer.BackgroundTransparency = 0.2
	controlsDimmer.BorderSizePixel = 0
	controlsDimmer.Size = UDim2.fromScale(1, 1)
	controlsDimmer.Visible = false
	controlsDimmer.ZIndex = 70
	controlsDimmer.Parent = gui

	local controlsGuide = Instance.new("Frame")
	controlsGuide.Name = "ControlsGuide"
	controlsGuide.Active = true
	controlsGuide.AnchorPoint = Vector2.new(0.5, 0.5)
	controlsGuide.BackgroundColor3 = COLORS.Panel
	controlsGuide.BorderSizePixel = 0
	controlsGuide.ClipsDescendants = true
	controlsGuide.Position = UDim2.fromScale(0.5, 0.5)
	controlsGuide.Size = UDim2.new(1, -48, 1, -64)
	controlsGuide.ZIndex = 71
	controlsGuide.Parent = controlsDimmer
	addCorner(controlsGuide, 20)
	addStroke(controlsGuide, COLORS.Cyan, 0.34)

	local guideConstraint = Instance.new("UISizeConstraint")
	guideConstraint.MaxSize = Vector2.new(760, 620)
	guideConstraint.MinSize = Vector2.new(280, 240)
	guideConstraint.Parent = controlsGuide

	local guideAccent = Instance.new("Frame")
	guideAccent.Name = "Accent"
	guideAccent.BackgroundColor3 = COLORS.Cyan
	guideAccent.BorderSizePixel = 0
	guideAccent.Size = UDim2.new(1, 0, 0, 5)
	guideAccent.ZIndex = 72
	guideAccent.Parent = controlsGuide
	local guideTitle = makeLabel(
		controlsGuide,
		"Title",
		"CONTROLS & ABILITIES",
		Enum.Font.GothamBlack,
		23,
		COLORS.Text
	)
	guideTitle.Position = UDim2.fromOffset(20, 15)
	guideTitle.Size = UDim2.new(1, -92, 0, 28)
	guideTitle.TextXAlignment = Enum.TextXAlignment.Left
	guideTitle.ZIndex = 73

	local guideSubtitle = makeLabel(
		controlsGuide,
		"Subtitle",
		"H / SELECT TO TOGGLE  -  SCROLL FOR EVERY MOVE",
		Enum.Font.GothamBold,
		9,
		COLORS.Cyan
	)
	guideSubtitle.Position = UDim2.fromOffset(21, 45)
	guideSubtitle.Size = UDim2.new(1, -94, 0, 16)
	guideSubtitle.TextXAlignment = Enum.TextXAlignment.Left
	guideSubtitle.ZIndex = 73

	local guideClose = makeButton(controlsGuide, "Close", "X")
	guideClose.AnchorPoint = Vector2.new(1, 0)
	guideClose.BackgroundColor3 = COLORS.PanelLight
	guideClose.Position = UDim2.new(1, -16, 0, 15)
	guideClose.Size = UDim2.fromOffset(38, 38)
	guideClose.TextColor3 = COLORS.Text
	guideClose.TextSize = 15
	guideClose.Modal = true
	guideClose.ZIndex = 74

	local controlsList = Instance.new("ScrollingFrame")
	controlsList.Name = "AbilityList"
	controlsList.Active = true
	controlsList.AutomaticCanvasSize = Enum.AutomaticSize.Y
	controlsList.BackgroundTransparency = 1
	controlsList.BorderSizePixel = 0
	controlsList.CanvasSize = UDim2.fromOffset(0, 0)
	controlsList.Position = UDim2.fromOffset(16, 72)
	controlsList.ScrollBarImageColor3 = COLORS.Cyan
	controlsList.ScrollBarThickness = 5
	controlsList.Selectable = true
	controlsList.Size = UDim2.new(1, -32, 1, -88)
	controlsList.VerticalScrollBarInset = Enum.ScrollBarInset.ScrollBar
	controlsList.ZIndex = 72
	controlsList.Parent = controlsGuide
	guideClose.NextSelectionDown = controlsList
	controlsList.NextSelectionUp = guideClose

	local guidePadding = Instance.new("UIPadding")
	guidePadding.PaddingBottom = UDim.new(0, 8)
	guidePadding.PaddingRight = UDim.new(0, 8)
	guidePadding.Parent = controlsList

	local guideLayout = Instance.new("UIListLayout")
	guideLayout.Padding = UDim.new(0, 8)
	guideLayout.SortOrder = Enum.SortOrder.LayoutOrder
	guideLayout.Parent = controlsList

	for index, entry in ABILITY_GUIDE do
		local row = Instance.new("Frame")
		row.Name = entry.id
		row.BackgroundColor3 = if index % 2 == 0 then COLORS.PanelLight else COLORS.Background
		row.BackgroundTransparency = if index % 2 == 0 then 0.16 else 0.28
		row.BorderSizePixel = 0
		row.LayoutOrder = index
		row.Size = UDim2.new(1, -4, 0, 108)
		row.ZIndex = 73
		row.Parent = controlsList
		addCorner(row, 12)
		addStroke(row, if index % 3 == 0 then COLORS.Pink else COLORS.Cyan, 0.72)

		local rowAccent = Instance.new("Frame")
		rowAccent.BackgroundColor3 = if index % 3 == 0
			then COLORS.Pink
			else if index % 3 == 1 then COLORS.Cyan else COLORS.Lime
		rowAccent.BorderSizePixel = 0
		rowAccent.Position = UDim2.fromOffset(0, 10)
		rowAccent.Size = UDim2.new(0, 4, 1, -20)
		rowAccent.ZIndex = 74
		rowAccent.Parent = row
		addCorner(rowAccent, 2)

		local rowTitle =
			makeLabel(row, "Title", entry.title, Enum.Font.GothamBlack, 13, COLORS.Text)
		rowTitle.Position = UDim2.fromOffset(14, 8)
		rowTitle.Size = UDim2.new(1, -28, 0, 18)
		rowTitle.TextXAlignment = Enum.TextXAlignment.Left
		rowTitle.ZIndex = 74

		local bindings = makeLabel(
			row,
			"Bindings",
			string.format(
				"PC  %s     PAD  %s     TOUCH  %s",
				entry.keyboard,
				entry.gamepad,
				entry.touch
			),
			Enum.Font.Code,
			10,
			COLORS.Cyan
		)
		bindings.Position = UDim2.fromOffset(14, 28)
		bindings.Size = UDim2.new(1, -28, 0, 30)
		bindings.TextWrapped = true
		bindings.TextXAlignment = Enum.TextXAlignment.Left
		bindings.TextYAlignment = Enum.TextYAlignment.Top
		bindings.ZIndex = 74

		local description =
			makeLabel(row, "Description", entry.description, Enum.Font.Gotham, 10, COLORS.Muted)
		description.Position = UDim2.fromOffset(14, 62)
		description.Size = UDim2.new(1, -28, 0, 40)
		description.TextWrapped = true
		description.TextXAlignment = Enum.TextXAlignment.Left
		description.TextYAlignment = Enum.TextYAlignment.Top
		description.ZIndex = 74
	end

	local self = setmetatable({
		Gui = gui,
		TopBar = topBar,
		Brand = brand,
		CoinsValue = coinsValue,
		LevelValue = levelValue,
		RatingValue = ratingValue,
		QueueCard = queueCard,
		QueueKicker = queueKicker,
		QueueOccupancy = queueOccupancy,
		QueueStatus = queueStatus,
		QueueButton = queueButton,
		MatchCard = matchCard,
		MatchArena = matchArena,
		MatchPhase = matchPhase,
		HomeName = homeName,
		AwayName = awayName,
		Score = score,
		PannaScore = pannaScore,
		Timer = timer,
		PowerContainer = powerContainer,
		PowerFill = powerFill,
		PowerCaption = powerCaption,
		PowerValue = powerValue,
		BallStatus = ballStatus,
		ActionBar = actionBar,
		ActionWidgets = actionWidgets,
		ActionFeedbackLabel = actionFeedbackLabel,
		ScreenFlash = screenFlash,
		Notification = notification,
		NotificationAccent = notificationAccent,
		NotificationTitle = notificationTitle,
		NotificationBody = notificationBody,
		RematchButton = rematchButton,
		ResultExitButton = resultExitButton,
		LeaveMatchButton = leaveMatchButton,
		HelpButton = helpButton,
		TouchHelpButton = touchHelpButton,
		ControlsDimmer = controlsDimmer,
		ControlsGuide = controlsGuide,
		ControlsCloseButton = guideClose,
		_connections = {},
		_queueCallback = nil,
		_queueJoined = false,
		_queuePending = false,
		_matchVisible = false,
		_matchState = "",
		_selectedArena = "",
		_isTouchLayout = preferredInputIsTouch(),
		_controlsGuideVisible = false,
		_controlsGuideShown = false,
		_previousSelectedObject = nil,
		_exitArmToken = 0,
		_exitArmedUntil = 0,
		_localDeadline = nil,
		_serverDeadline = nil,
		_notificationToken = 0,
		_notificationTween = nil,
		_actionFeedbackToken = 0,
		_actionFeedbackTween = nil,
		_shotMode = "Normal",
		_ballStatusKey = "",
		_flashTween = nil,
		_shakeEndsAt = 0,
		_shakeStrength = 0,
		_shakeHumanoid = nil,
		_shakeBaseOffset = nil,
		_destroyed = false,
	}, UIController) :: UIController

	table.insert(
		self._connections,
		queueButton.Activated:Connect(function()
			if
				self._destroyed
				or self._controlsGuideVisible
				or self._queuePending
				or not self.QueueButton.Active
			then
				return
			end

			local callback = self._queueCallback
			if callback == nil then
				return
			end

			self._queuePending = true
			self.QueueButton.Active = false
			self.QueueButton.Text = "SENDING..."
			local request = "Join"
			if self._queueJoined then
				request = if self._selectedArena ~= "" then "Exit" else "Leave"
			end
			callback(request)

			task.delay(2, function()
				if not self._destroyed and self._queuePending then
					self._queuePending = false
					self.QueueButton.Active = true
					if self._queueJoined then
						self.QueueButton.Text = if self._selectedArena ~= ""
							then "LEAVE COURT QUEUE"
							else "LEAVE QUICK QUEUE"
					else
						self.QueueButton.Text = "QUICK JOIN ANY COURT"
					end
				end
			end)
		end)
	)

	table.insert(
		self._connections,
		resultExitButton.Activated:Connect(function()
			if
				self._destroyed
				or self._controlsGuideVisible
				or not self.ResultExitButton.Active
			then
				return
			end
			local callback = self._queueCallback
			if callback == nil then
				return
			end
			self.ResultExitButton.Active = false
			self.ResultExitButton.Text = "LEAVING..."
			callback("Exit")
		end)
	)

	table.insert(
		self._connections,
		leaveMatchButton.Activated:Connect(function()
			if
				self._destroyed
				or self._controlsGuideVisible
				or not self.LeaveMatchButton.Active
			then
				return
			end
			local callback = self._queueCallback
			if callback == nil then
				return
			end

			local now = os.clock()
			if now > self._exitArmedUntil then
				self._exitArmToken += 1
				local token = self._exitArmToken
				self._exitArmedUntil = now + 3
				self.LeaveMatchButton.Text = "CONFIRM"
				self.LeaveMatchButton.BackgroundColor3 = COLORS.Danger
				local exitWarning = if self._matchState == "Countdown"
					then "PRESS EXIT AGAIN TO CANCEL THIS MATCH."
					else "PRESS EXIT AGAIN. AN ACTIVE MATCH COUNTS AS A FORFEIT."
				self:ShowNotification("LEAVE THE COURT?", exitWarning, COLORS.Warning, 3)
				task.delay(3, function()
					if not self._destroyed and token == self._exitArmToken then
						self._exitArmedUntil = 0
						self.LeaveMatchButton.Text = "EXIT"
						self.LeaveMatchButton.BackgroundColor3 = COLORS.PanelLight
					end
				end)
				return
			end

			self._exitArmToken += 1
			self._exitArmedUntil = 0
			self.LeaveMatchButton.Active = false
			self.LeaveMatchButton.Text = "LEAVING..."
			callback("Exit")
		end)
	)

	table.insert(
		self._connections,
		rematchButton.Activated:Connect(function()
			if self._destroyed or self._controlsGuideVisible or not self.RematchButton.Active then
				return
			end
			local callback = self._queueCallback
			if callback == nil then
				return
			end
			self.RematchButton.Active = false
			self.RematchButton.Text = "REQUESTED"
			callback("Rematch")
		end)
	)

	for _, button in { helpButton, touchHelpButton } do
		table.insert(
			self._connections,
			button.Activated:Connect(function()
				self:ToggleControlsGuide()
			end)
		)
	end
	table.insert(
		self._connections,
		guideClose.Activated:Connect(function()
			self:SetControlsGuideVisible(false)
		end)
	)
	table.insert(
		self._connections,
		UserInputService.InputBegan:Connect(function(input: InputObject, gameProcessed: boolean)
			if self._destroyed then
				return
			end
			if input.KeyCode == Enum.KeyCode.Escape and self._controlsGuideVisible then
				self:SetControlsGuideVisible(false)
				return
			end
			if input.KeyCode == Enum.KeyCode.ButtonSelect then
				self:ToggleControlsGuide()
				return
			end
			if gameProcessed then
				return
			end
			if input.KeyCode == Enum.KeyCode.H then
				self:ToggleControlsGuide()
			end
		end)
	)

	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function()
			self:_updateTimer()
			self:_updateImpact()
		end)
	)

	local function updateInputPrompts()
		local lastInputName = UserInputService:GetLastInputType().Name
		local usingGamepad = string.find(lastInputName, "Gamepad", 1, true) ~= nil
		for action, widget in self.ActionWidgets do
			local presentation = (ACTION_PRESENTATION :: any)[action]
			widget.Binding.Text = if usingGamepad
				then presentation.gamepad
				else presentation.keyboard
		end
	end

	local function updateResponsive()
		if self._destroyed then
			return
		end
		local camera = Workspace.CurrentCamera
		local width = if camera then camera.ViewportSize.X else 800
		local height = if camera then camera.ViewportSize.Y else 600
		local compact = width < 600
		local short = height < 500
		local touchLayout = preferredInputIsTouch()
		self._isTouchLayout = touchLayout
		self.Brand.Visible = not compact
		helpButton.Text = if compact then "?" else "HELP"
		helpButton.Position = if compact then UDim2.fromOffset(8, 12) else UDim2.fromOffset(132, 12)
		helpButton.Size = UDim2.fromOffset(if compact then 34 else 38, 32)
		stats.Position = if compact then UDim2.fromOffset(48, 0) else UDim2.fromOffset(176, 0)
		stats.Size = if compact then UDim2.new(1, -56, 1, 0) else UDim2.new(1, -184, 1, 0)
		homeName.TextSize = if compact then 13 else 16
		awayName.TextSize = if compact then 13 else 16
		score.TextSize = if compact then 25 else 29
		matchPhase.Size = if compact then UDim2.new(0.34, 0, 0, 14) else UDim2.new(0.5, 0, 0, 14)
		local leaveButtonWidth = if compact then 64 else 78
		leaveMatchButton.Size = UDim2.fromOffset(leaveButtonWidth, 24)
		leaveMatchButton.TextSize = if compact then 9 else 10
		local touchGameplay = touchLayout and self:IsGameplayActive()
		topBar.Visible = not touchGameplay
		touchHelpButton.Visible = touchGameplay and not self._controlsGuideVisible
		matchCard.Position =
			UDim2.new(0.5, 0, 0, if touchGameplay then 12 else if compact then 76 else 80)
		queueCard.Position = UDim2.new(0.5, 0, 1, if touchLayout then -14 else -24)
		actionScale.Scale = math.min(1, math.max(0.5, (width - 20) / 660))
		actionBar.Position = UDim2.new(0.5, 0, 1, if short then -10 else -18)
		actionBar.Visible = self:IsGameplayActive() and not touchLayout

		if touchLayout then
			powerContainer.AnchorPoint = Vector2.new(0.5, 1)
			powerContainer.Position = UDim2.new(0.5, 0, 1, if short then -185 else -205)
			powerContainer.Size = UDim2.new(1, -100, 0, 34)
		else
			powerContainer.AnchorPoint = Vector2.new(0.5, 1)
			powerContainer.Position = UDim2.new(0.5, 0, 1, -80)
			powerContainer.Size = UDim2.new(1, -80, 0, 38)
		end

		local narrowResult = width < 410
		local resultWidth = if narrowResult then 134 else 164
		local resultOffset = if narrowResult then 72 else 88
		rematchButton.Position = UDim2.new(0.5, -resultOffset, 0.52, 82)
		rematchButton.Size = UDim2.fromOffset(resultWidth, 38)
		resultExitButton.Position = UDim2.new(0.5, resultOffset, 0.52, 82)
		resultExitButton.Size = UDim2.fromOffset(resultWidth, 38)
		controlsGuide.Size = if compact or short
			then UDim2.new(1, -20, 1, -20)
			else UDim2.new(1, -48, 1, -64)
		guideTitle.TextSize = if compact then 18 else 23
		local condensedGuideHeader = compact and short
		guideSubtitle.Visible = not condensedGuideHeader
		local guideListTop = if condensedGuideHeader then 57 else 72
		controlsList.Position = UDim2.fromOffset(12, guideListTop)
		controlsList.Size = UDim2.new(1, -24, 1, -(guideListTop + 12))
		updateInputPrompts()
	end

	local cameraViewportConnection: RBXScriptConnection? = nil
	local function connectCamera()
		if cameraViewportConnection then
			cameraViewportConnection:Disconnect()
			cameraViewportConnection = nil
		end
		local camera = Workspace.CurrentCamera
		if camera then
			cameraViewportConnection =
				camera:GetPropertyChangedSignal("ViewportSize"):Connect(updateResponsive)
		end
		updateResponsive()
	end

	connectCamera()
	table.insert(
		self._connections,
		Workspace:GetPropertyChangedSignal("CurrentCamera"):Connect(connectCamera)
	)
	table.insert(
		self._connections,
		UserInputService.LastInputTypeChanged:Connect(function()
			updateInputPrompts()
			updateResponsive()
		end)
	)
	local preferredSignalSuccess, preferredSignal = pcall(function()
		return UserInputService:GetPropertyChangedSignal("PreferredInput")
	end)
	if preferredSignalSuccess then
		table.insert(self._connections, preferredSignal:Connect(updateResponsive))
	end
	table.insert(
		self._connections,
		{
			Disconnect = function()
				if cameraViewportConnection then
					cameraViewportConnection:Disconnect()
					cameraViewportConnection = nil
				end
			end,
		} :: any
	)

	return self
end

function UIController.GetAbilityGuide(): { any }
	return ABILITY_GUIDE
end

function UIController.SetControlsGuideVisible(self: UIController, visible: boolean)
	if self._destroyed then
		return
	end

	self._controlsGuideVisible = visible
	if visible then
		self._controlsGuideShown = true
		self._previousSelectedObject = GuiService.SelectedObject
	end
	self.ControlsDimmer.Visible = visible
	self.HelpButton.BackgroundColor3 = if visible then COLORS.Cyan else COLORS.PanelLight
	self.HelpButton.TextColor3 = if visible then COLORS.Background else COLORS.Cyan
	self.TouchHelpButton.Visible = not visible and self._isTouchLayout and self:IsGameplayActive()
	if visible then
		GuiService.SelectedObject = self.ControlsCloseButton
	else
		local previous = self._previousSelectedObject
		self._previousSelectedObject = nil
		GuiService.SelectedObject = if previous and isVisibleInGui(previous, self.Gui)
			then previous
			else nil
	end
end

function UIController.ToggleControlsGuide(self: UIController)
	self:SetControlsGuideVisible(not self._controlsGuideVisible)
end

function UIController.IsControlsGuideVisible(self: UIController): boolean
	return self._controlsGuideVisible
end

function UIController.SetQueueRequestHandler(self: UIController, callback: (string) -> ())
	self._queueCallback = callback
	self.QueueButton.Active = true
	self.QueueButton.Text = "QUICK JOIN ANY COURT"
	self.QueueStatus.Text = "CHOOSE A COURT AND STEP INTO ITS QUEUE ZONE"
end

function UIController.SetConnectionError(self: UIController, message: string)
	self._queuePending = false
	self.QueueButton.Active = false
	self.QueueButton.Text = "OFFLINE"
	self.QueueButton.BackgroundColor3 = COLORS.Danger
	self.QueueStatus.Text = string.upper(message)
	self:ShowNotification("CONNECTION LOST", message, COLORS.Danger, 6)
end

function UIController.SetStats(self: UIController, stats: any)
	self.CoinsValue.Text = formatCompact(readNumber(stats, 0, "Coins", "coins"))
	self.LevelValue.Text = formatCompact(readNumber(stats, 1, "Level", "level"))
	self.RatingValue.Text = formatCompact(readNumber(stats, 1000, "Rating", "rating"))
end

function UIController.SetQueueState(self: UIController, queue: any)
	local joined = readBoolean(queue, false, "joined", "Joined", "inQueue", "InQueue")
	local status = readString(
		queue,
		if joined then "queued" else "idle",
		"status",
		"Status",
		"queueStatus",
		"QueueStatus"
	)
	local position = readNumber(queue, 0, "position", "Position")
	local arenaId, arenaName, occupants, capacity, roomStatus = readArenaState(queue)
	if arenaId == "" then
		local attribute = LOCAL_PLAYER:GetAttribute("SelectedArenaId")
		if typeof(attribute) ~= "string" or attribute == "" then
			attribute = LOCAL_PLAYER:GetAttribute("ArenaId")
		end
		if typeof(attribute) == "string" then
			arenaId = attribute
			if arenaName == "" then
				arenaName = attribute
			end
		end
	end
	if roomStatus ~= "" and status == "idle" then
		status = roomStatus
	end
	if occupants == 0 and joined and arenaId ~= "" then
		occupants = 1
	end

	self._queueJoined = joined
	self._queuePending = false
	self._selectedArena = arenaId
	self.QueueButton.Active = self._queueCallback ~= nil
	if joined then
		self.QueueButton.Text = if arenaId ~= "" then "LEAVE COURT QUEUE" else "LEAVE QUICK QUEUE"
	else
		self.QueueButton.Text = "QUICK JOIN ANY COURT"
	end
	self.QueueButton.BackgroundColor3 = if joined then COLORS.Danger else COLORS.Cyan
	self.QueueKicker.Text = if arenaName ~= ""
		then readableArena(arenaName) .. "  /  1V1"
		else "WALK INTO A 1V1 COURT"
	self.QueueOccupancy.Text = if arenaName ~= "" or arenaId ~= ""
		then string.format("%d / %d", math.floor(occupants), math.floor(capacity))
		else "OPEN"
	self.QueueOccupancy.TextColor3 = if occupants >= capacity then COLORS.Danger else COLORS.Cyan

	local statusText = readableStatus(status)
	if joined and position > 0 then
		statusText ..= string.format("  •  #%d", math.floor(position))
	elseif
		arenaName == ""
		and not joined
		and (string.lower(status) == "idle" or string.lower(status) == "ready")
	then
		statusText = "CHOOSE A COURT AND STEP INTO ITS QUEUE ZONE"
	end
	self.QueueStatus.Text = statusText
end

function UIController.ResetTransientState(self: UIController)
	if self._destroyed then
		return
	end

	self:SetPowerMeter("Kick", 0, false, self._shotMode)
	self.PowerContainer.Visible = false
	self.ActionBar.Visible = self:IsGameplayActive() and not self._isTouchLayout
	self._ballStatusKey = ""
	self:SetBallStatus("Free", 0)
	for _, action in ACTION_ORDER do
		self:SetActionPending(action, false)
		self:SetActionActive(action, false)
		self:SetActionCooldown(action, 0, 0)
	end

	self._actionFeedbackToken += 1
	if self._actionFeedbackTween then
		self._actionFeedbackTween:Cancel()
		self._actionFeedbackTween = nil
	end
	self.ActionFeedbackLabel.Visible = false
	self.ActionFeedbackLabel.TextTransparency = 1
	self.ActionFeedbackLabel.BackgroundTransparency = 1

	if self._flashTween then
		self._flashTween:Cancel()
		self._flashTween = nil
	end
	self.ScreenFlash.Visible = false
	self.ScreenFlash.BackgroundTransparency = 1
	self:_restoreCameraOffset()
end

function UIController.SetMatchState(self: UIController, match: any)
	if typeof(match) ~= "table" then
		self:ResetTransientState()
		self._matchVisible = false
		self._matchState = ""
		self._localDeadline = nil
		self._serverDeadline = nil
		self.TopBar.Visible = true
		self.TouchHelpButton.Visible = false
		self.MatchCard.Visible = false
		self.BallStatus.Visible = false
		self.PowerContainer.Visible = false
		self.ActionBar.Visible = false
		self.QueueCard.Visible = true
		self.RematchButton.Visible = false
		self.RematchButton.Active = true
		self.RematchButton.Text = "REMATCH"
		self.ResultExitButton.Visible = false
		self.ResultExitButton.Active = true
		self.ResultExitButton.Text = "EXIT COURT"
		self.LeaveMatchButton.Visible = false
		self.LeaveMatchButton.Active = true
		self.LeaveMatchButton.Text = "EXIT"
		self.LeaveMatchButton.BackgroundColor3 = COLORS.PanelLight
		self._exitArmToken += 1
		self._exitArmedUntil = 0
		return
	end

	local previousState = self._matchState
	local state = readString(match, "Active", "state", "State")
	local homeName = readString(match, "HOME", "homeName", "HomeName")
	local awayName = readString(match, "AWAY", "awayName", "AwayName")
	local homeScore = readNumber(match, 0, "homeScore", "HomeScore")
	local awayScore = readNumber(match, 0, "awayScore", "AwayScore")
	local homePannas = readNumber(match, 0, "homePannas", "HomePannas")
	local awayPannas = readNumber(match, 0, "awayPannas", "AwayPannas")
	local arenaId, arenaName = readArenaState(match)
	if arenaId == "" then
		arenaId = self._selectedArena
	end
	if arenaName == "" then
		arenaName = arenaId
	end
	if arenaId == "" then
		local attribute = LOCAL_PLAYER:GetAttribute("ArenaId")
		if typeof(attribute) == "string" then
			arenaId = attribute
			arenaName = attribute
		end
	end
	local scoreTable = read(match, "score", "Score")
	if typeof(scoreTable) == "table" then
		homeScore = readNumber(scoreTable, homeScore, "home", "Home")
		awayScore = readNumber(scoreTable, awayScore, "away", "Away")
		homePannas = readNumber(scoreTable, homePannas, "homePannas", "HomePannas")
		awayPannas = readNumber(scoreTable, awayPannas, "awayPannas", "AwayPannas")
	end

	self._matchVisible = true
	self._matchState = state
	self.MatchCard.Visible = true
	self.BallStatus.Visible = true
	self.QueueCard.Visible = false
	local gameplayActive = state == "Active" or state == "Overtime"
	if state == "Countdown" and previousState ~= "Countdown" and not self._controlsGuideShown then
		self:SetControlsGuideVisible(true)
	elseif gameplayActive and previousState == "Countdown" and self._controlsGuideVisible then
		self:SetControlsGuideVisible(false)
	end
	if not gameplayActive then
		self:ResetTransientState()
	end
	local camera = Workspace.CurrentCamera
	local compact = camera ~= nil and camera.ViewportSize.X < 600
	self.TopBar.Visible = not (self._isTouchLayout and gameplayActive)
	self.TouchHelpButton.Visible = self._isTouchLayout
		and gameplayActive
		and not self._controlsGuideVisible
	self.MatchCard.Position = UDim2.new(
		0.5,
		0,
		0,
		if self._isTouchLayout and gameplayActive then 12 else if compact then 76 else 80
	)
	self.PowerContainer.Visible = false
	self.ActionBar.Visible = gameplayActive and not self._isTouchLayout
	self.LeaveMatchButton.Visible = state ~= "Finished"
	self.LeaveMatchButton.Active = true
	self.LeaveMatchButton.Text = "EXIT"
	self.LeaveMatchButton.BackgroundColor3 = COLORS.PanelLight
	self._exitArmToken += 1
	self._exitArmedUntil = 0
	self.MatchArena.Text = if arenaName ~= "" then readableArena(arenaName) else "COURT --"
	self.HomeName.Text = string.upper(homeName)
	self.AwayName.Text = string.upper(awayName)
	self.Score.Text = string.format("%d  :  %d", math.floor(homeScore), math.floor(awayScore))
	self.PannaScore.Text = string.format(
		"PANNA  %d — %d%s",
		math.floor(homePannas),
		math.floor(awayPannas),
		if readBoolean(match, false, "goldenGoal", "GoldenGoal") then "  •  GOLDEN GOAL" else ""
	)

	local phaseLabels = {
		Countdown = "1V1 • GET READY",
		Active = "1V1 • LIVE",
		GoalPause = "1V1 • GOAL",
		Overtime = "1V1 • OVERTIME",
		Finished = "1V1 • FULL TIME",
	}
	self.MatchPhase.Text = phaseLabels[state] or ("1V1 • " .. string.upper(state))
	self.MatchPhase.TextColor3 = if state == "Overtime" then COLORS.Warning else COLORS.Cyan

	local remainingValue = read(match, "remaining", "Remaining")
	local endsAtValue = read(match, "endsAt", "EndsAt")
	local serverNowValue = read(match, "serverNow", "ServerNow")
	if typeof(remainingValue) == "number" then
		self._localDeadline = os.clock() + math.max(0, remainingValue)
		self._serverDeadline = nil
	elseif typeof(endsAtValue) == "number" and typeof(serverNowValue) == "number" then
		self._localDeadline = os.clock() + math.max(0, endsAtValue - serverNowValue)
		self._serverDeadline = nil
	elseif typeof(endsAtValue) == "number" then
		self._localDeadline = nil
		self._serverDeadline = endsAtValue
	end

	if state == "Finished" then
		self.RematchButton.Visible = true
		self.RematchButton.Active = true
		self.RematchButton.Text = "REMATCH"
		self.ResultExitButton.Visible = true
		self.ResultExitButton.Active = true
		self.ResultExitButton.Text = "EXIT COURT"
	else
		self.RematchButton.Visible = false
		self.ResultExitButton.Visible = false
	end
	self:_updateTimer()
end

function UIController._updateTimer(self: UIController)
	if not self._matchVisible then
		return
	end

	local remaining = 0
	if self._localDeadline then
		remaining = self._localDeadline - os.clock()
	elseif self._serverDeadline then
		remaining = self._serverDeadline - Workspace:GetServerTimeNow()
	end
	self.Timer.Text = formatTime(remaining)
	self.Timer.TextColor3 = if remaining <= 10 and self._matchState ~= "Finished"
		then COLORS.Danger
		else COLORS.Lime
end

function UIController.SetPowerMeter(
	self: UIController,
	action: string,
	power: number,
	active: boolean,
	mode: string?
)
	local safePower = math.clamp(power, 0, 1)
	self.PowerFill.Size = UDim2.fromScale(safePower, 1)
	self.PowerValue.Text = string.format("%d%%", math.floor(safePower * 100 + 0.5))
	if action == "Pass" then
		self.PowerCaption.Text = "PASS POWER"
	elseif action == "Trap" then
		self.PowerCaption.Text = "FIRST TOUCH"
	else
		self.PowerCaption.Text = "SHOT " .. string.upper(mode or self._shotMode)
	end
	self.PowerContainer.Visible = self._matchVisible and self:IsGameplayActive() and active
end

function UIController.SetKickPower(self: UIController, power: number, charging: boolean)
	self:SetPowerMeter("Kick", power, charging, self._shotMode)
end

function UIController.SetShotMode(self: UIController, mode: string)
	local normalized = if mode == "Low" or mode == "Chip" then mode else "Normal"
	if self._shotMode == normalized then
		return
	end
	self._shotMode = normalized
	local widget = self.ActionWidgets.Kick
	if typeof(widget) == "table" then
		widget.Title.Text = "SHOT · " .. string.upper(normalized)
	end
end

function UIController.SetBallStatus(self: UIController, state: string, ownerUserId: number)
	local normalized = string.lower(state)
	local key = normalized .. ":" .. tostring(ownerUserId)
	if self._ballStatusKey == key then
		return
	end
	self._ballStatusKey = key
	if ownerUserId == LOCAL_PLAYER.UserId then
		self.BallStatus.Text = "● CONTROL"
		self.BallStatus.TextColor3 = COLORS.Lime
	elseif normalized == "contested" or ownerUserId ~= 0 then
		self.BallStatus.Text = "● CONTESTED"
		self.BallStatus.TextColor3 = COLORS.Warning
	elseif normalized == "flight" or normalized == "shot" or normalized == "bounce" then
		self.BallStatus.Text = "● FLIGHT"
		self.BallStatus.TextColor3 = COLORS.Cyan
	else
		self.BallStatus.Text = "● FREE"
		self.BallStatus.TextColor3 = COLORS.Muted
	end
end

function UIController.IsGameplayActive(self: UIController): boolean
	local state = string.lower(self._matchState)
	local arenaId = LOCAL_PLAYER:GetAttribute("ArenaId")
	local matchId = LOCAL_PLAYER:GetAttribute("MatchId")
	return self._matchVisible
		and (state == "active" or state == "live" or state == "overtime")
		and LOCAL_PLAYER:GetAttribute("InMatch") == true
		and LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true
		and typeof(arenaId) == "string"
		and arenaId ~= ""
		and typeof(matchId) == "string"
		and matchId ~= ""
end

function UIController.SetActionCooldown(
	self: UIController,
	action: string,
	remaining: number,
	duration: number
)
	local widget = self.ActionWidgets[action]
	if typeof(widget) ~= "table" or widget.Active == true or widget.Pending == true then
		return
	end

	local safeRemaining = math.max(0, remaining)
	local ratio = if duration > 0 then math.clamp(safeRemaining / duration, 0, 1) else 0
	widget.Fill.Size = UDim2.fromScale(1, ratio)
	widget.Binding.Visible = safeRemaining <= 0.04
	widget.Cooldown.Text = if safeRemaining > 0.04 then string.format("%.1f", safeRemaining) else ""
	widget.Cooldown.TextColor3 = COLORS.Warning
end

function UIController.SetActionPending(self: UIController, action: string, pending: boolean)
	local widget = self.ActionWidgets[action]
	if typeof(widget) ~= "table" then
		return
	end
	widget.Pending = pending
	if widget.Active == true then
		return
	end
	widget.Container.BackgroundColor3 = if pending then COLORS.PanelLight else COLORS.Panel
	widget.Binding.Visible = not pending
	widget.Cooldown.Text = if pending then "…" else ""
	widget.Cooldown.TextColor3 = COLORS.Muted
	if pending then
		widget.Fill.Size = UDim2.fromScale(1, 0)
	end
end

function UIController.SetActionActive(self: UIController, action: string, active: boolean)
	local widget = self.ActionWidgets[action]
	if typeof(widget) ~= "table" then
		return
	end

	widget.Active = active
	widget.Container.BackgroundColor3 = if active then COLORS.Active else COLORS.Panel
	widget.Cooldown.Text = if active then "HOLD" else ""
	widget.Cooldown.TextColor3 = if active then COLORS.Background else COLORS.Warning
	widget.Binding.Visible = not active
	widget.Fill.Size = UDim2.fromScale(1, 0)
end

function UIController._showActionFeedback(self: UIController, text: string, color: Color3)
	self._actionFeedbackToken += 1
	local token = self._actionFeedbackToken
	if self._actionFeedbackTween then
		self._actionFeedbackTween:Cancel()
		self._actionFeedbackTween = nil
	end

	local label = self.ActionFeedbackLabel
	label.Text = text
	label.TextColor3 = color
	label.TextTransparency = 0
	label.BackgroundTransparency = 0.14
	label.Visible = true
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Color = color
	end

	task.delay(0.62, function()
		if self._destroyed or token ~= self._actionFeedbackToken then
			return
		end
		local tween = TweenService:Create(
			label,
			TweenInfo.new(0.18, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
			{ TextTransparency = 1, BackgroundTransparency = 1 }
		)
		self._actionFeedbackTween = tween
		tween:Play()
		tween.Completed:Once(function()
			if not self._destroyed and token == self._actionFeedbackToken then
				label.Visible = false
				self._actionFeedbackTween = nil
			end
		end)
	end)
end

function UIController.ApplyActionFeedback(self: UIController, feedback: any)
	if self._destroyed or typeof(feedback) ~= "table" then
		return
	end
	local action = readString(feedback, "", "action", "Action")
	local accepted = readBoolean(feedback, false, "accepted", "Accepted")
	local executed = readBoolean(feedback, false, "executed", "Executed")
	local mode = readString(feedback, "", "mode", "Mode")
	local reason = readString(feedback, "Rejected", "reason", "Reason")
	if accepted then
		if action == "ChargeStart" then
			return
		end
		if not executed then
			if reason == "Buffered" then
				local bufferedMessages: { [string]: string } = {
					Kick = "SHOT BUFFERED",
					Pass = "PASS BUFFERED",
					Trap = "FIRST TOUCH READY",
				}
				local message = bufferedMessages[action]
				if message then
					self:_showActionFeedback(message, COLORS.Lime)
				end
			elseif reason == "DribbleProtected" then
				self:_showActionFeedback("DRIBBLE PROTECTED", COLORS.Warning)
			elseif reason == "Shielded" then
				self:_showActionFeedback("TACKLE BLOCKED", COLORS.Warning)
			elseif reason == "BadTackleAngle" then
				self:_showActionFeedback("TACKLE MISSED", COLORS.Danger)
			end
			return
		end
		if action == "Kick" then
			local shotMode = if mode == "Low"
					or mode == "Normal"
					or mode == "Chip"
				then mode
				else self._shotMode
			local strength = if shotMode == "Low"
				then 0.55
				else if shotMode == "Chip" then 0.7 else 0.82
			self:PlayImpact("Kick", strength)
		elseif action == "Pass" then
			self:PlayImpact("Pass", 0.4)
		elseif action == "Tackle" then
			self:PlayImpact("Tackle", 0.55)
			self:_showActionFeedback("BALL WON", COLORS.Lime)
		elseif action == "Feint" then
			self:PlayImpact("Skill", 0.35)
			self:_showActionFeedback("CLOSE CONTROL", COLORS.Cyan)
		elseif action == "Skill" then
			self:PlayImpact("Skill", 0.35)
		elseif action == "Trap" then
			self:_showActionFeedback("FIRST TOUCH READY", COLORS.Lime)
		end
		return
	end

	local messages: { [string]: string } = {
		RateLimited = "SLOW DOWN",
		Cooldown = "ACTION ON COOLDOWN",
		FeedbackTimeout = "WAITING FOR SERVER",
		StaleBall = "BALL CHANGED — TRY AGAIN",
		StaleRevision = "BALL CHANGED — TRY AGAIN",
		NotController = "NO BALL CONTROL",
		NotOwner = "NO BALL CONTROL",
		TooFar = "GET CLOSER TO THE BALL",
		InvalidState = "ACTION NOT AVAILABLE",
		ControlsLocked = "WAIT FOR THE WHISTLE",
		NoMatch = "MATCH IS NOT ACTIVE",
		NoActiveMatch = "MATCH IS NOT ACTIVE",
		RevisionMismatch = "BALL CHANGED - TRY AGAIN",
		MissingCharge = "CHARGE THE BALL FIRST",
		NoContact = "GET CLOSER TO THE BALL",
		InvalidFeint = "CHOOSE ANOTHER FEINT",
		CannotBuffer = "CANNOT READY THAT TOUCH",
		NoTarget = "NO OPPONENT IN RANGE",
		BehindDefender = "ATTACK FROM THE FRONT",
		Shielded = "OPPONENT IS SHIELDING",
		DribbleProtected = "DRIBBLE IS PROTECTED",
		AimRejected = "FACE YOUR TARGET",
		MatchMismatch = "MATCH CHANGED - TRY AGAIN",
		ArenaMismatch = "ARENA CHANGED - TRY AGAIN",
		StaleClientTime = "CONNECTION DELAY - TRY AGAIN",
		CharacterUnavailable = "CHARACTER NOT READY",
		MovementRejected = "MOVEMENT NOT VALID",
		InvalidDirection = "AIM AGAIN",
		InvalidChargeAction = "CHARGE CANCELLED",
		InvalidPayload = "REQUEST INVALID",
		InvalidSequence = "REQUEST OUT OF ORDER",
		StaleSequence = "REQUEST OUT OF ORDER",
		SequenceJump = "REQUEST OUT OF ORDER",
	}
	local readableReason = string.gsub(reason, "(%l)(%u)", "%1 %2")
	readableReason = string.gsub(readableReason, "_", " ")
	local message = messages[reason] or string.upper(readableReason)
	self:_showActionFeedback(message, COLORS.Danger)
end

function UIController._restoreCameraOffset(self: UIController)
	local humanoid = self._shakeHumanoid
	local baseOffset = self._shakeBaseOffset
	if humanoid and humanoid.Parent and baseOffset then
		humanoid.CameraOffset = baseOffset
	end
	self._shakeHumanoid = nil
	self._shakeBaseOffset = nil
	self._shakeEndsAt = 0
	self._shakeStrength = 0
end

function UIController._updateImpact(self: UIController)
	if self._shakeEndsAt <= 0 then
		return
	end

	local now = os.clock()
	if now >= self._shakeEndsAt then
		self:_restoreCameraOffset()
		return
	end

	local humanoid = self._shakeHumanoid
	local baseOffset = self._shakeBaseOffset
	if not humanoid or not humanoid.Parent or not baseOffset then
		self:_restoreCameraOffset()
		return
	end

	local fade = math.clamp((self._shakeEndsAt - now) / 0.16, 0, 1)
	local amplitude = self._shakeStrength * fade
	humanoid.CameraOffset = baseOffset
		+ Vector3.new(math.noise(now * 47, 0) * amplitude, math.noise(0, now * 53) * amplitude, 0)
end

function UIController.PlayImpact(self: UIController, kind: string, strength: number?)
	if self._destroyed then
		return
	end

	local normalized = string.lower(kind)
	local duration = 0.14
	local shakeStrength = 0.14
	local flashColor = COLORS.Cyan
	local flashTransparency = 0.8
	if normalized == "panna" then
		duration = 0.24
		shakeStrength = 0.34
		flashColor = COLORS.Pink
		flashTransparency = 0.58
	elseif normalized == "goal" then
		duration = 0.2
		shakeStrength = 0.25
		flashColor = COLORS.Lime
		flashTransparency = 0.68
	elseif normalized == "kick" then
		local safeStrength = math.clamp(strength or 1, 0, 1)
		duration = 0.11 + safeStrength * 0.05
		shakeStrength = 0.08 + safeStrength * 0.13
		flashTransparency = 0.88 - safeStrength * 0.08
	end

	local now = os.clock()
	if self._shakeEndsAt <= now then
		local character = LOCAL_PLAYER.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			self._shakeHumanoid = humanoid
			self._shakeBaseOffset = humanoid.CameraOffset
		end
	end
	self._shakeEndsAt = math.max(self._shakeEndsAt, now + duration)
	self._shakeStrength = math.max(self._shakeStrength, shakeStrength)

	if self._flashTween then
		self._flashTween:Cancel()
	end
	self.ScreenFlash.BackgroundColor3 = flashColor
	self.ScreenFlash.BackgroundTransparency = flashTransparency
	self.ScreenFlash.Visible = true
	local flashTween = TweenService:Create(
		self.ScreenFlash,
		TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.Out),
		{ BackgroundTransparency = 1 }
	)
	self._flashTween = flashTween
	flashTween:Play()
	flashTween.Completed:Once(function()
		if not self._destroyed and self._flashTween == flashTween then
			self.ScreenFlash.Visible = false
			self._flashTween = nil
		end
	end)
end

function UIController.ShowNotification(
	self: UIController,
	title: string,
	body: string,
	accent: Color3?,
	duration: number?
)
	if self._destroyed then
		return
	end

	self._notificationToken += 1
	local token = self._notificationToken
	if self._notificationTween then
		self._notificationTween:Cancel()
	end

	self.NotificationTitle.Text = title
	self.NotificationBody.Text = body
	self.NotificationAccent.BackgroundColor3 = accent or COLORS.Cyan
	self.Notification.Visible = true
	self.Notification.GroupTransparency = 1
	self.Notification.Position = UDim2.new(0.5, 0, 0.39, 12)

	local showTween = TweenService:Create(
		self.Notification,
		TweenInfo.new(0.2, Enum.EasingStyle.Quint, Enum.EasingDirection.Out),
		{ GroupTransparency = 0, Position = UDim2.fromScale(0.5, 0.39) }
	)
	self._notificationTween = showTween
	showTween:Play()

	task.delay(duration or 2.8, function()
		if self._destroyed or token ~= self._notificationToken then
			return
		end
		local hideTween = TweenService:Create(
			self.Notification,
			TweenInfo.new(0.25, Enum.EasingStyle.Quad, Enum.EasingDirection.In),
			{ GroupTransparency = 1, Position = UDim2.new(0.5, 0, 0.39, -10) }
		)
		self._notificationTween = hideTween
		hideTween:Play()
		hideTween.Completed:Once(function()
			if not self._destroyed and token == self._notificationToken then
				self.Notification.Visible = false
			end
		end)
	end)
end

function UIController.ApplyEffect(self: UIController, effect: any)
	if typeof(effect) == "string" then
		self:ShowNotification("PANNA", effect, COLORS.Cyan, 3)
		return
	end
	if typeof(effect) ~= "table" then
		return
	end

	local kind = string.lower(readString(effect, "Message", "kind", "Kind", "type", "Type"))
	local explicitTitle = read(effect, "title", "Title")
	local explicitText = readString(effect, "", "text", "Text", "message", "Message")
	if kind == "goal" then
		self:PlayImpact("Goal", 1)
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "GOAL!"
		self:ShowNotification(
			title,
			if explicitText ~= "" then explicitText else "BACK OF THE NET",
			COLORS.Cyan,
			2.6
		)
	elseif kind == "panna" then
		self:PlayImpact("Panna", 1)
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "PANNA!"
		self:ShowNotification(
			title,
			if explicitText ~= "" then explicitText else "THROUGH THE GATE",
			COLORS.Pink,
			3
		)
	elseif kind == "result" then
		self:ResetTransientState()
		local won = readBoolean(effect, false, "won", "Won")
		local title = if typeof(explicitTitle) == "string"
			then explicitTitle
			else if won then "YOU WIN" else "FULL TIME"
		self:ShowNotification(
			title,
			if explicitText ~= "" then explicitText else "MATCH COMPLETE",
			if won then COLORS.Lime else COLORS.Pink,
			5.5
		)
		self.RematchButton.Visible = readBoolean(effect, true, "canRematch", "CanRematch")
		self.RematchButton.Active = true
		self.RematchButton.Text = "REMATCH"
		self.ResultExitButton.Visible = true
		self.ResultExitButton.Active = true
		self.ResultExitButton.Text = "EXIT COURT"
	else
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "PANNA STREET"
		self:ShowNotification(title, explicitText, COLORS.Warning, 3.5)
	end
end

function UIController.ApplyState(
	self: UIController,
	payload: any,
	isSnapshot: boolean?,
	allowMatchState: boolean?
)
	if typeof(payload) ~= "table" then
		return
	end

	local wrapped = read(payload, "data", "Data", "snapshot", "Snapshot")
	local state = if typeof(wrapped) == "table" then wrapped else payload
	local stats = read(state, "stats", "Stats", "playerStats", "PlayerStats")
	if typeof(stats) == "table" then
		self:SetStats(stats)
	end

	local queue = read(
		state,
		"queue",
		"Queue",
		"room",
		"Room",
		"selectedArena",
		"SelectedArena",
		"arenaSelection",
		"ArenaSelection"
	)
	if typeof(queue) == "table" then
		self:SetQueueState(queue)
	elseif
		read(
			state,
			"joined",
			"Joined",
			"inQueue",
			"InQueue",
			"arenaId",
			"ArenaId",
			"selectedArenaId",
			"SelectedArenaId"
		) ~= nil
	then
		self:SetQueueState(state)
	end
	if allowMatchState == false then
		return
	end

	local match = read(state, "match", "Match")
	if typeof(match) == "table" then
		self:SetMatchState(match)
	elseif match == false or (isSnapshot == true and match == nil) then
		self:SetMatchState(nil)
	elseif read(state, "homeName", "HomeName", "homeScore", "HomeScore") ~= nil then
		self:SetMatchState(state)
	end
end

function UIController.IsPointerOverUI(self: UIController): boolean
	local mousePosition = UserInputService:GetMouseLocation()
	local playerGui = self.Gui.Parent
	if not playerGui or not playerGui:IsA("PlayerGui") then
		return false
	end

	local success, objects = pcall(function()
		return playerGui:GetGuiObjectsAtPosition(mousePosition.X, mousePosition.Y)
	end)
	if not success then
		return false
	end

	for _, object in objects do
		if
			object:IsDescendantOf(self.Gui)
			and object:IsA("GuiButton")
			and object.Visible
			and object.Active
		then
			return true
		end
	end
	return false
end

function UIController.Destroy(self: UIController)
	if self._destroyed then
		return
	end
	self._destroyed = true
	self._notificationToken += 1
	if self._notificationTween then
		self._notificationTween:Cancel()
		self._notificationTween = nil
	end
	if self._flashTween then
		self._flashTween:Cancel()
		self._flashTween = nil
	end
	self._actionFeedbackToken += 1
	if self._actionFeedbackTween then
		self._actionFeedbackTween:Cancel()
		self._actionFeedbackTween = nil
	end
	self:_restoreCameraOffset()
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

return UIController
