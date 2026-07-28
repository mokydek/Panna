--!strict

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer

local COLORS = table.freeze({
	Background = Color3.fromRGB(8, 12, 19),
	Panel = Color3.fromRGB(17, 24, 34),
	PanelLight = Color3.fromRGB(28, 38, 52),
	Text = Color3.fromRGB(244, 248, 255),
	Muted = Color3.fromRGB(146, 161, 181),
	Cyan = Color3.fromRGB(36, 226, 255),
	Pink = Color3.fromRGB(255, 61, 181),
	Lime = Color3.fromRGB(157, 255, 71),
	Warning = Color3.fromRGB(255, 188, 52),
	Danger = Color3.fromRGB(255, 76, 92),
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

type ControllerFields = {
	Gui: ScreenGui,
	TopBar: Frame,
	Brand: TextLabel,
	CoinsValue: TextLabel,
	LevelValue: TextLabel,
	RatingValue: TextLabel,
	QueueCard: Frame,
	QueueStatus: TextLabel,
	QueueButton: TextButton,
	MatchCard: Frame,
	MatchPhase: TextLabel,
	HomeName: TextLabel,
	AwayName: TextLabel,
	Score: TextLabel,
	PannaScore: TextLabel,
	Timer: TextLabel,
	PowerContainer: Frame,
	PowerFill: Frame,
	PowerValue: TextLabel,
	Notification: CanvasGroup,
	NotificationAccent: Frame,
	NotificationTitle: TextLabel,
	NotificationBody: TextLabel,
	RematchButton: TextButton,
	_connections: { RBXScriptConnection },
	_queueCallback: ((string) -> ())?,
	_queueJoined: boolean,
	_queuePending: boolean,
	_matchVisible: boolean,
	_matchState: string,
	_localDeadline: number?,
	_serverDeadline: number?,
	_notificationToken: number,
	_notificationTween: Tween?,
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
	brand.Size = UDim2.new(0, 158, 1, 0)
	brand.TextXAlignment = Enum.TextXAlignment.Left

	local brandMark = Instance.new("Frame")
	brandMark.Name = "BrandMark"
	brandMark.BackgroundColor3 = COLORS.Pink
	brandMark.BorderSizePixel = 0
	brandMark.Position = UDim2.new(0, 10, 0.5, -12)
	brandMark.Size = UDim2.fromOffset(3, 24)
	brandMark.Parent = topBar
	addCorner(brandMark, 2)

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

	local queueCard = Instance.new("Frame")
	queueCard.Name = "QueueCard"
	queueCard.AnchorPoint = Vector2.new(0.5, 1)
	queueCard.BackgroundColor3 = COLORS.Panel
	queueCard.BackgroundTransparency = 0.04
	queueCard.BorderSizePixel = 0
	queueCard.Position = UDim2.new(0.5, 0, 1, -24)
	queueCard.Size = UDim2.new(1, -32, 0, 94)
	queueCard.Parent = gui
	addCorner(queueCard, 16)
	addStroke(queueCard, COLORS.Cyan, 0.55)

	local queueConstraint = Instance.new("UISizeConstraint")
	queueConstraint.MaxSize = Vector2.new(370, 94)
	queueConstraint.MinSize = Vector2.new(280, 94)
	queueConstraint.Parent = queueCard

	local queueKicker =
		makeLabel(queueCard, "Kicker", "QUICK MATCH • 1V1", Enum.Font.GothamBold, 10, COLORS.Pink)
	queueKicker.Position = UDim2.fromOffset(14, 10)
	queueKicker.Size = UDim2.new(1, -28, 0, 13)
	queueKicker.TextXAlignment = Enum.TextXAlignment.Left

	local queueStatus = makeLabel(
		queueCard,
		"Status",
		"CONNECTING TO THE STREET...",
		Enum.Font.Gotham,
		11,
		COLORS.Muted
	)
	queueStatus.Position = UDim2.fromOffset(14, 26)
	queueStatus.Size = UDim2.new(1, -28, 0, 16)
	queueStatus.TextTruncate = Enum.TextTruncate.AtEnd
	queueStatus.TextXAlignment = Enum.TextXAlignment.Left

	local queueButton = makeButton(queueCard, "QueueButton", "CONNECTING...")
	queueButton.Position = UDim2.fromOffset(14, 51)
	queueButton.Size = UDim2.new(1, -28, 0, 32)
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
	powerConstraint.MinSize = Vector2.new(240, 38)
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

	local powerGradient = Instance.new("UIGradient")
	powerGradient.Color = ColorSequence.new({
		ColorSequenceKeypoint.new(0, COLORS.Cyan),
		ColorSequenceKeypoint.new(0.72, COLORS.Lime),
		ColorSequenceKeypoint.new(1, COLORS.Pink),
	})
	powerGradient.Parent = powerFill

	local powerValue =
		makeLabel(powerContainer, "Value", "0%", Enum.Font.GothamBlack, 13, COLORS.Text)
	powerValue.AnchorPoint = Vector2.new(1, 0)
	powerValue.Position = UDim2.new(1, -10, 0, 0)
	powerValue.Size = UDim2.new(0, 60, 1, 0)
	powerValue.TextXAlignment = Enum.TextXAlignment.Right

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
	rematchButton.Position = UDim2.new(0.5, 0, 0.52, 82)
	rematchButton.Size = UDim2.fromOffset(180, 38)
	rematchButton.Visible = false

	local self = setmetatable({
		Gui = gui,
		TopBar = topBar,
		Brand = brand,
		CoinsValue = coinsValue,
		LevelValue = levelValue,
		RatingValue = ratingValue,
		QueueCard = queueCard,
		QueueStatus = queueStatus,
		QueueButton = queueButton,
		MatchCard = matchCard,
		MatchPhase = matchPhase,
		HomeName = homeName,
		AwayName = awayName,
		Score = score,
		PannaScore = pannaScore,
		Timer = timer,
		PowerContainer = powerContainer,
		PowerFill = powerFill,
		PowerValue = powerValue,
		Notification = notification,
		NotificationAccent = notificationAccent,
		NotificationTitle = notificationTitle,
		NotificationBody = notificationBody,
		RematchButton = rematchButton,
		_connections = {},
		_queueCallback = nil,
		_queueJoined = false,
		_queuePending = false,
		_matchVisible = false,
		_matchState = "",
		_localDeadline = nil,
		_serverDeadline = nil,
		_notificationToken = 0,
		_notificationTween = nil,
		_destroyed = false,
	}, UIController) :: UIController

	table.insert(
		self._connections,
		queueButton.Activated:Connect(function()
			if self._destroyed or self._queuePending or not self.QueueButton.Active then
				return
			end

			local callback = self._queueCallback
			if callback == nil then
				return
			end

			self._queuePending = true
			self.QueueButton.Active = false
			self.QueueButton.Text = "SENDING..."
			callback(if self._queueJoined then "Leave" else "Join")

			task.delay(2, function()
				if not self._destroyed and self._queuePending then
					self._queuePending = false
					self.QueueButton.Active = true
					self.QueueButton.Text = if self._queueJoined then "LEAVE QUEUE" else "JOIN 1V1"
				end
			end)
		end)
	)

	table.insert(
		self._connections,
		rematchButton.Activated:Connect(function()
			if self._destroyed or not self.RematchButton.Active then
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

	table.insert(
		self._connections,
		RunService.RenderStepped:Connect(function()
			self:_updateTimer()
		end)
	)

	local function updateResponsive()
		if self._destroyed then
			return
		end
		local camera = Workspace.CurrentCamera
		local width = if camera then camera.ViewportSize.X else 800
		local compact = width < 600
		self.Brand.Visible = not compact
		stats.Position = if compact then UDim2.fromOffset(8, 0) else UDim2.fromOffset(176, 0)
		stats.Size = if compact then UDim2.new(1, -16, 1, 0) else UDim2.new(1, -184, 1, 0)
		homeName.TextSize = if compact then 13 else 16
		awayName.TextSize = if compact then 13 else 16
		score.TextSize = if compact then 25 else 29
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

function UIController.SetQueueRequestHandler(self: UIController, callback: (string) -> ())
	self._queueCallback = callback
	self.QueueButton.Active = true
	self.QueueButton.Text = "JOIN 1V1"
	self.QueueStatus.Text = "READY FOR STREET FOOTBALL"
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
	local status = readString(queue, if joined then "queued" else "idle", "status", "Status")
	local position = readNumber(queue, 0, "position", "Position")

	self._queueJoined = joined
	self._queuePending = false
	self.QueueButton.Active = self._queueCallback ~= nil
	self.QueueButton.Text = if joined then "LEAVE QUEUE" else "JOIN 1V1"
	self.QueueButton.BackgroundColor3 = if joined then COLORS.Danger else COLORS.Cyan

	local statusText = readableStatus(status)
	if joined and position > 0 then
		statusText ..= string.format("  •  #%d", math.floor(position))
	end
	self.QueueStatus.Text = statusText
end

function UIController.SetMatchState(self: UIController, match: any)
	if typeof(match) ~= "table" then
		self._matchVisible = false
		self._matchState = ""
		self._localDeadline = nil
		self._serverDeadline = nil
		self.MatchCard.Visible = false
		self.PowerContainer.Visible = false
		self.QueueCard.Visible = true
		self.RematchButton.Visible = false
		self.RematchButton.Active = true
		self.RematchButton.Text = "REMATCH"
		return
	end

	local state = readString(match, "Active", "state", "State")
	local homeName = readString(match, "HOME", "homeName", "HomeName")
	local awayName = readString(match, "AWAY", "awayName", "AwayName")
	local homeScore = readNumber(match, 0, "homeScore", "HomeScore")
	local awayScore = readNumber(match, 0, "awayScore", "AwayScore")
	local homePannas = readNumber(match, 0, "homePannas", "HomePannas")
	local awayPannas = readNumber(match, 0, "awayPannas", "AwayPannas")
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
	self.QueueCard.Visible = false
	self.PowerContainer.Visible = state == "Active" or state == "Overtime"
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
	else
		self.RematchButton.Visible = false
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

function UIController.SetKickPower(self: UIController, power: number, charging: boolean)
	local safePower = math.clamp(power, 0, 1)
	self.PowerFill.Size = UDim2.fromScale(safePower, 1)
	self.PowerValue.Text = string.format("%d%%", math.floor(safePower * 100 + 0.5))
	self.PowerContainer.Visible = self._matchVisible
		and (charging or self._matchState == "Active" or self._matchState == "Overtime")
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
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "GOAL!"
		self:ShowNotification(
			title,
			if explicitText ~= "" then explicitText else "BACK OF THE NET",
			COLORS.Cyan,
			2.6
		)
	elseif kind == "panna" then
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "PANNA!"
		self:ShowNotification(
			title,
			if explicitText ~= "" then explicitText else "THROUGH THE GATE",
			COLORS.Pink,
			3
		)
	elseif kind == "result" then
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
	else
		local title = if typeof(explicitTitle) == "string" then explicitTitle else "PANNA STREET"
		self:ShowNotification(title, explicitText, COLORS.Warning, 3.5)
	end
end

function UIController.ApplyState(self: UIController, payload: any, isSnapshot: boolean?)
	if typeof(payload) ~= "table" then
		return
	end

	local wrapped = read(payload, "data", "Data", "snapshot", "Snapshot")
	local state = if typeof(wrapped) == "table" then wrapped else payload
	local stats = read(state, "stats", "Stats", "playerStats", "PlayerStats")
	if typeof(stats) == "table" then
		self:SetStats(stats)
	end

	local queue = read(state, "queue", "Queue")
	if typeof(queue) == "table" then
		self:SetQueueState(queue)
	elseif read(state, "joined", "Joined", "inQueue", "InQueue") ~= nil then
		self:SetQueueState(state)
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
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	self.Gui:Destroy()
end

return UIController
