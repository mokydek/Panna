--!strict

local ContextActionService = game:GetService("ContextActionService")
local GuiService = game:GetService("GuiService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value
local ControlCatalog = require(script.Parent:WaitForChild("ControlCatalog"))
local SHOT_TYPES = ControlCatalog.ShotTypes
local ACTION_ORDER = ControlCatalog.ActionOrder
local TOUCH_ORDER = ControlCatalog.TouchOrder
local ACTIONS = ControlCatalog.Actions
local BINDINGS = ControlCatalog.Bindings
local TOUCH_TITLES = ControlCatalog.TouchTitles
local DEFAULT_COOLDOWNS = table.freeze({
	Kick = 0.28,
	Pass = 0.28,
	Feint = 0.95,
	Tackle = 0.9,
	Skill = 2,
	Shield = 0.15,
	Dash = 3,
})

type TimingSettings = {
	kickChargeSeconds: number,
	passChargeSeconds: number,
	minimumKickPower: number,
	minimumPassPower: number,
	kickPowerExponent: number,
	passPowerExponent: number,
	pendingTimeoutSeconds: number,
	trapBufferSeconds: number,
}

local DEFAULT_TIMINGS: TimingSettings = table.freeze({
	kickChargeSeconds = 1.1,
	passChargeSeconds = 0.9,
	minimumKickPower = 0.1,
	minimumPassPower = 0.1,
	kickPowerExponent = 1.1,
	passPowerExponent = 1.08,
	pendingTimeoutSeconds = 2.1,
	trapBufferSeconds = 0.9,
})

type UIControllerLike = {
	SetPowerMeter: (self: any, action: string, power: number, active: boolean, mode: string?) -> (),
	SetShotMode: (self: any, mode: string) -> (),
	SetBallStatus: (self: any, state: string, ownerUserId: number) -> (),
	SetActionCooldown: (self: any, action: string, remaining: number, duration: number) -> (),
	SetActionActive: (self: any, action: string, active: boolean) -> (),
	SetActionPending: (self: any, action: string, pending: boolean) -> (),
	ApplyActionFeedback: (self: any, feedback: any) -> (),
	ResetTransientState: (self: any) -> (),
	IsGameplayActive: (self: any) -> boolean,
	IsPointerOverUI: (self: any) -> boolean,
	IsControlsGuideVisible: (self: any) -> boolean,
}

type VFXControllerLike = {
	SetAimState: (
		self: any,
		ball: BasePart?,
		ballState: string,
		ownerUserId: number,
		direction: Vector3,
		action: string,
		mode: string,
		power: number,
		gameplayActive: boolean,
		charging: boolean
	) -> (),
	ResetTransientState: (self: any) -> (),
}

type PendingRequest = {
	action: string,
	uiAction: string?,
	sentAt: number,
	power: number?,
	mode: string?,
	active: boolean?,
	arenaId: string,
	matchId: string,
}

type ControllerFields = {
	_actionRequest: RemoteEvent,
	_ui: UIControllerLike,
	_vfx: VFXControllerLike?,
	_chargingAction: string?,
	_chargeStartedAt: number,
	_chargeInputId: string?,
	_chargeToken: number,
	_primaryMouseTackleActive: boolean,
	_shotTypeIndex: number,
	_shieldHeld: boolean,
	_shielding: boolean,
	_shieldStartedAt: number,
	_shieldMaxSeconds: number,
	_trapBufferEndsAt: number,
	_kickChargeSeconds: number,
	_passChargeSeconds: number,
	_minimumKickPower: number,
	_minimumPassPower: number,
	_kickPowerExponent: number,
	_passPowerExponent: number,
	_pendingTimeoutSeconds: number,
	_trapBufferSeconds: number,
	_nextSequence: number,
	_lastSentAt: { [string]: number },
	_pending: { [number]: PendingRequest },
	_pendingByAction: { [string]: number },
	_cooldownEnds: { [string]: number },
	_cooldownDurations: { [string]: number },
	_touchButtons: { [string]: GuiButton },
	_touchTitles: { [string]: string },
	_lastViewport: Vector2,
	_preferredTouch: boolean,
	_cachedBall: BasePart?,
	_cachedArenaId: string,
	_feedbackRevision: number,
	_feedbackArenaId: string,
	_feedbackMatchId: string,
	_renderConnection: RBXScriptConnection?,
	_connections: { RBXScriptConnection },
	_destroyed: boolean,
}

local InputController = {}
InputController.__index = InputController

export type InputController = typeof(setmetatable({} :: ControllerFields, InputController))

local function inputId(input: InputObject): string
	return string.format("%s/%s", input.UserInputType.Name, input.KeyCode.Name)
end

local function safePlanar(value: Vector3): Vector3
	local planar = Vector3.new(value.X, 0, value.Z)
	if planar.Magnitude > 1 then
		return planar.Unit
	end
	return planar
end

local function normalizedPlanar(value: Vector3, fallback: Vector3): Vector3
	local planar = safePlanar(value)
	if planar.Magnitude > 0.05 then
		return planar.Unit
	end
	local fallbackPlanar = safePlanar(fallback)
	if fallbackPlanar.Magnitude > 0.05 then
		return fallbackPlanar.Unit
	end
	return Vector3.new(0, 0, -1)
end

local function inputIsBlocked(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function readPreferredTouch(): boolean
	local success, preferred = pcall(function(): any
		return UserInputService.PreferredInput
	end)
	if success and typeof(preferred) == "EnumItem" then
		return preferred.Name == "Touch"
	end
	local lastInput = UserInputService:GetLastInputType()
	return lastInput == Enum.UserInputType.Touch
end

local function validNumber(value: any, minimum: number): boolean
	return typeof(value) == "number"
		and value == value
		and math.abs(value) < math.huge
		and value >= minimum
end

local function chargePower(
	elapsed: number,
	duration: number,
	minimumPower: number,
	exponent: number
): number
	local normalized = math.clamp(elapsed / math.max(0.01, duration), 0, 1)
	local minimum = math.clamp(minimumPower, 0, 1)
	return minimum + (1 - minimum) * normalized ^ math.max(0.01, exponent)
end

local function loadActionSettings(): ({ [string]: number }, number, TimingSettings)
	local cooldowns: { [string]: number } = table.clone(DEFAULT_COOLDOWNS :: any)
	local shieldMaxSeconds = 2.5
	local timings: TimingSettings = table.clone(DEFAULT_TIMINGS :: any)
	local shared = ReplicatedStorage:FindFirstChild("PannaShared")
	local configModule = if shared then shared:FindFirstChild("Config") else nil
	if not configModule or not configModule:IsA("ModuleScript") then
		return cooldowns, shieldMaxSeconds, timings
	end

	local success, config = pcall(require, configModule)
	if not success or typeof(config) ~= "table" then
		return cooldowns, shieldMaxSeconds, timings
	end

	local actions = config.Actions
	if typeof(actions) == "table" then
		for _, action in ACTION_ORDER do
			local key = if action == "Shield" then "ShieldToggleCooldown" else action .. "Cooldown"
			local value = actions[key]
			if validNumber(value, 0) then
				cooldowns[action] = value
			end
		end
		local shield = actions.Shield
		if typeof(shield) == "table" and validNumber(shield.MaximumSeconds, 0.01) then
			shieldMaxSeconds = shield.MaximumSeconds
		end
	end

	local ball = config.Ball
	if typeof(ball) == "table" then
		local shot = ball.Shot
		if typeof(shot) == "table" then
			if validNumber(shot.ChargeSeconds, 0.01) then
				timings.kickChargeSeconds = shot.ChargeSeconds
			end
			if validNumber(shot.MinimumPower, 0) then
				timings.minimumKickPower = math.clamp(shot.MinimumPower, 0, 1)
			end
			if validNumber(shot.PowerExponent, 0.01) then
				timings.kickPowerExponent = shot.PowerExponent
			end
		end
		local pass = ball.Pass
		if typeof(pass) == "table" then
			if validNumber(pass.ChargeSeconds, 0.01) then
				timings.passChargeSeconds = pass.ChargeSeconds
			end
			if validNumber(pass.MinimumPower, 0) then
				timings.minimumPassPower = math.clamp(pass.MinimumPower, 0, 1)
			end
			if validNumber(pass.PowerExponent, 0.01) then
				timings.passPowerExponent = pass.PowerExponent
			end
		end
		local firstTouch = ball.FirstTouch
		if typeof(firstTouch) == "table" and validNumber(firstTouch.BufferSeconds, 0.01) then
			timings.trapBufferSeconds = firstTouch.BufferSeconds
		end
	end

	local security = config.Security
	local command = if typeof(security) == "table" then security.Command else nil
	if typeof(command) == "table" then
		local maximumPast = command.MaximumPastSeconds
		local maximumFuture = command.MaximumFutureSeconds
		if validNumber(maximumPast, 0) and validNumber(maximumFuture, 0) then
			timings.pendingTimeoutSeconds =
				math.max(timings.pendingTimeoutSeconds, maximumPast + maximumFuture + 0.25)
		end
	end
	return cooldowns, shieldMaxSeconds, timings
end

local function styleTouchButton(button: GuiButton, size: number)
	button.AutoButtonColor = false
	button.BackgroundColor3 = Color3.fromRGB(17, 24, 34)
	button.BackgroundTransparency = 0.08
	button.Size = UDim2.fromOffset(size, size)
	if button:IsA("ImageButton") then
		button.ImageTransparency = 1
	end

	local existingCorner = button:FindFirstChild("PannaCorner")
	local corner: UICorner
	if existingCorner and existingCorner:IsA("UICorner") then
		corner = existingCorner
	else
		corner = Instance.new("UICorner")
		corner.Name = "PannaCorner"
		corner.Parent = button
	end
	corner.CornerRadius = UDim.new(0.5, 0)

	local existingStroke = button:FindFirstChild("PannaStroke")
	local stroke: UIStroke
	if existingStroke and existingStroke:IsA("UIStroke") then
		stroke = existingStroke
	else
		stroke = Instance.new("UIStroke")
		stroke.Name = "PannaStroke"
		stroke.Parent = button
	end
	stroke.Color = Color3.fromRGB(36, 226, 255)
	stroke.Transparency = 0.28
	stroke.Thickness = 1.5

	for _, descendant in button:GetDescendants() do
		if descendant:IsA("TextLabel") then
			descendant.Font = Enum.Font.GothamBlack
			descendant.TextColor3 = Color3.fromRGB(244, 248, 255)
			descendant.TextSize = if size <= 44 then 8 else if size <= 50 then 9 else 10
			descendant.TextWrapped = true
		end
	end
end

function InputController.new(
	actionRequest: RemoteEvent,
	ui: UIControllerLike,
	vfx: VFXControllerLike?
): InputController
	local cooldowns, shieldMaxSeconds, timings = loadActionSettings()
	local self = setmetatable({
		_actionRequest = actionRequest,
		_ui = ui,
		_vfx = vfx,
		_chargingAction = nil,
		_chargeStartedAt = 0,
		_chargeInputId = nil,
		_chargeToken = 0,
		_primaryMouseTackleActive = false,
		_shotTypeIndex = 1,
		_shieldHeld = false,
		_shielding = false,
		_shieldStartedAt = 0,
		_shieldMaxSeconds = shieldMaxSeconds,
		_trapBufferEndsAt = 0,
		_kickChargeSeconds = timings.kickChargeSeconds,
		_passChargeSeconds = timings.passChargeSeconds,
		_minimumKickPower = timings.minimumKickPower,
		_minimumPassPower = timings.minimumPassPower,
		_kickPowerExponent = timings.kickPowerExponent,
		_passPowerExponent = timings.passPowerExponent,
		_pendingTimeoutSeconds = timings.pendingTimeoutSeconds,
		_trapBufferSeconds = timings.trapBufferSeconds,
		_nextSequence = 0,
		_lastSentAt = {},
		_pending = {},
		_pendingByAction = {},
		_cooldownEnds = {},
		_cooldownDurations = cooldowns,
		_touchButtons = {},
		_touchTitles = {},
		_lastViewport = Vector2.zero,
		_preferredTouch = readPreferredTouch(),
		_cachedBall = nil,
		_cachedArenaId = "",
		_feedbackRevision = 0,
		_feedbackArenaId = "",
		_feedbackMatchId = "",
		_renderConnection = nil,
		_connections = {},
		_destroyed = false,
	}, InputController) :: InputController

	self:_bindActions()
	self:_refreshTouchLayout(true)
	self._ui:SetShotMode(SHOT_TYPES[self._shotTypeIndex])
	self:_updateFeedback()
	self._renderConnection = RunService.RenderStepped:Connect(function()
		self:_onRenderStep()
	end)

	local function cancelTransientInput()
		self:_cancelCharge()
		self._primaryMouseTackleActive = false
		self._shieldHeld = false
		self._trapBufferEndsAt = 0
		self:_stopShield()
		self._ui:SetPowerMeter("Kick", 0, false, self:_shotType())
	end
	table.insert(
		self._connections,
		UserInputService.WindowFocusReleased:Connect(cancelTransientInput)
	)
	table.insert(self._connections, GuiService.MenuOpened:Connect(cancelTransientInput))
	table.insert(
		self._connections,
		LOCAL_PLAYER.CharacterRemoving:Connect(function()
			self:ResetTransientState()
		end)
	)
	table.insert(
		self._connections,
		UserInputService.LastInputTypeChanged:Connect(function()
			self._preferredTouch = readPreferredTouch()
			self:_refreshTouchLayout(true)
		end)
	)
	local preferredSignalSuccess, preferredSignal = pcall(function()
		return UserInputService:GetPropertyChangedSignal("PreferredInput")
	end)
	if preferredSignalSuccess then
		table.insert(
			self._connections,
			preferredSignal:Connect(function()
				self._preferredTouch = readPreferredTouch()
				self:_refreshTouchLayout(true)
			end)
		)
	end

	return self
end

function InputController._shotType(self: InputController): string
	return SHOT_TYPES[self._shotTypeIndex]
end

function InputController._actionReady(self: InputController, action: string): boolean
	return os.clock() >= (self._cooldownEnds[action] or 0) and self._pendingByAction[action] == nil
end

function InputController._isGameplayActive(self: InputController): boolean
	return self._ui:IsGameplayActive()
		and not self._ui:IsControlsGuideVisible()
		and LOCAL_PLAYER:GetAttribute("InMatch") == true
		and LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true
		and self:_arenaId() ~= ""
		and self:_matchId() ~= ""
end

function InputController._arenaId(_self: InputController): string
	local value = LOCAL_PLAYER:GetAttribute("ArenaId")
	return if typeof(value) == "string" then value else ""
end

function InputController._matchId(_self: InputController): string
	local value = LOCAL_PLAYER:GetAttribute("MatchId")
	return if typeof(value) == "string" then value else ""
end

function InputController._feedbackRevisionForContext(
	self: InputController,
	arenaId: string,
	matchId: string
): number
	if arenaId ~= self._feedbackArenaId or matchId ~= self._feedbackMatchId then
		self._feedbackArenaId = arenaId
		self._feedbackMatchId = matchId
		self._feedbackRevision = 0
	end
	return self._feedbackRevision
end

function InputController._resolveBall(self: InputController): BasePart?
	local arenaId = self:_arenaId()
	local cached = self._cachedBall
	if
		arenaId ~= ""
		and cached
		and cached.Parent ~= nil
		and cached:GetAttribute("ArenaId") == arenaId
	then
		return cached
	end

	self._cachedBall = nil
	self._cachedArenaId = arenaId
	if arenaId == "" then
		return nil
	end
	local district = Workspace:FindFirstChild("PannaDistrict")
	if not district then
		return nil
	end
	for _, descendant in district:GetDescendants() do
		if
			descendant:IsA("BasePart")
			and descendant.Name == "Ball"
			and descendant:GetAttribute("ArenaId") == arenaId
		then
			self._cachedBall = descendant
			return descendant
		end
	end
	return nil
end

function InputController._ballContext(self: InputController): (BasePart?, string, number, number)
	local arenaId = self:_arenaId()
	local matchId = self:_matchId()
	local feedbackRevision = self:_feedbackRevisionForContext(arenaId, matchId)
	local ball = self:_resolveBall()
	if not ball then
		return nil, "Free", 0, feedbackRevision
	end
	local ownerValue = ball:GetAttribute("OwnerUserId")
	local ownerUserId = if typeof(ownerValue) == "number" then ownerValue else 0
	local revisionValue = ball:GetAttribute("BallRevision")
	local attributeRevision = if typeof(revisionValue) == "number"
		then math.max(0, revisionValue)
		else 0
	local revision = math.max(attributeRevision, feedbackRevision)
	local stateValue = ball:GetAttribute("BallState")
	local state = if typeof(stateValue) == "string" then stateValue else ""
	if state == "" then
		if ownerUserId ~= 0 then
			state = "Controlled"
		elseif ball.AssemblyLinearVelocity.Magnitude > 10 then
			state = "Flight"
		else
			state = "Free"
		end
	end
	return ball, state, ownerUserId, revision
end

function InputController._opponentRoot(self: InputController): BasePart?
	local arenaId = self:_arenaId()
	local matchId = self:_matchId()
	if arenaId == "" or matchId == "" then
		return nil
	end
	for _, candidate in Players:GetPlayers() do
		if
			candidate ~= LOCAL_PLAYER
			and candidate:GetAttribute("ArenaId") == arenaId
			and candidate:GetAttribute("MatchId") == matchId
		then
			local character = candidate.Character
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			if root and root:IsA("BasePart") then
				return root
			end
		end
	end
	return nil
end

function InputController._directionForAction(
	self: InputController,
	action: string
): (Vector3, Vector3)
	local character = LOCAL_PLAYER.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local rootPart = if root and root:IsA("BasePart") then root else nil
	local facing = if rootPart then rootPart.CFrame.LookVector else Vector3.new(0, 0, -1)
	local moveDirection = if humanoid then safePlanar(humanoid.MoveDirection) else Vector3.zero

	local camera = Workspace.CurrentCamera
	local cameraDirection = if camera then camera.CFrame.LookVector else facing
	local direction = normalizedPlanar(cameraDirection, facing)
	if action == "Dash" or action == "Feint" or action == "Shield" or action == "Trap" then
		direction = normalizedPlanar(moveDirection, facing)
	elseif action == "Tackle" or action == "Skill" then
		local opponentRoot = self:_opponentRoot()
		if opponentRoot and rootPart then
			direction = normalizedPlanar(opponentRoot.Position - rootPart.Position, facing)
		else
			direction = normalizedPlanar(moveDirection, cameraDirection)
		end
	end
	return direction, moveDirection
end

function InputController._kickSpin(self: InputController): number
	local direction, moveDirection = self:_directionForAction("Kick")
	if moveDirection.Magnitude < 0.05 then
		return 0
	end
	return math.clamp(direction:Cross(moveDirection.Unit).Y, -1, 1)
end

function InputController._requestKey(
	_self: InputController,
	action: string,
	extra: { [string]: any }?
): string
	if action == "ChargeStart" and extra then
		return action .. ":" .. tostring(extra.chargeAction)
	elseif action == "Shield" and extra then
		return action .. ":" .. tostring(extra.active)
	end
	return action
end

function InputController._sendRequest(
	self: InputController,
	action: string,
	uiAction: string?,
	extra: { [string]: any }?,
	allowInactive: boolean?
): (boolean, number?)
	if self._destroyed or self._actionRequest.Parent == nil then
		return false, nil
	end
	local arenaId = self:_arenaId()
	local matchId = self:_matchId()
	if arenaId == "" or matchId == "" or LOCAL_PLAYER:GetAttribute("InMatch") ~= true then
		return false, nil
	end
	if not allowInactive and (inputIsBlocked() or not self:_isGameplayActive()) then
		return false, nil
	end
	if uiAction and not self:_actionReady(uiAction) then
		return false, nil
	end

	local now = os.clock()
	local requestKey = self:_requestKey(action, extra)
	if now - (self._lastSentAt[requestKey] or 0) < 0.04 then
		return false, nil
	end
	self._lastSentAt[requestKey] = now

	self._nextSequence += 1
	if self._nextSequence >= 2_000_000_000 then
		self._nextSequence = 1
	end
	local sequence = self._nextSequence
	local _, _, _, ballRevision = self:_ballContext()
	local direction, moveDirection = self:_directionForAction(action)
	local payload: { [string]: any } = {
		action = action,
		sequence = sequence,
		arenaId = arenaId,
		matchId = matchId,
		ballRevision = ballRevision,
		clientTime = Workspace:GetServerTimeNow(),
		direction = direction,
		moveDirection = moveDirection,
	}
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end

	self._actionRequest:FireServer(payload)
	local pending: PendingRequest = {
		action = action,
		uiAction = uiAction,
		sentAt = now,
		power = if extra and typeof(extra.power) == "number" then extra.power else nil,
		active = if extra and typeof(extra.active) == "boolean" then extra.active else nil,
		arenaId = arenaId,
		matchId = matchId,
		mode = if extra and typeof(extra.shotType) == "string"
			then extra.shotType
			else if extra and typeof(extra.variant) == "string"
				then extra.variant
				else if extra and typeof(extra.chargeAction) == "string"
					then extra.chargeAction
					else nil,
	}
	self._pending[sequence] = pending
	if uiAction then
		self._pendingByAction[uiAction] = sequence
		self._ui:SetActionPending(uiAction, true)
	end
	return true, sequence
end

function InputController._clearPending(self: InputController, sequence: number): PendingRequest?
	local pending = self._pending[sequence]
	if not pending then
		return nil
	end
	self._pending[sequence] = nil
	local uiAction = pending.uiAction
	if uiAction and self._pendingByAction[uiAction] == sequence then
		self._pendingByAction[uiAction] = nil
		self._ui:SetActionPending(uiAction, false)
	end
	return pending
end

function InputController.ApplyActionFeedback(self: InputController, feedback: any): boolean
	if self._destroyed or typeof(feedback) ~= "table" then
		return false
	end
	local sequenceValue = feedback.sequence
	if typeof(sequenceValue) ~= "number" then
		return false
	end
	local sequence = math.floor(sequenceValue)
	local pending = self:_clearPending(sequence)
	if not pending then
		return false
	end
	local arenaId = self:_arenaId()
	local matchId = self:_matchId()
	if pending.arenaId ~= arenaId or pending.matchId ~= matchId then
		return false
	end
	local feedbackRevision = feedback.revision
	if validNumber(feedbackRevision, 0) then
		local cachedRevision = self:_feedbackRevisionForContext(arenaId, matchId)
		self._feedbackRevision = math.max(cachedRevision, math.floor(feedbackRevision))
	end
	local action = if typeof(feedback.action) == "string" then feedback.action else pending.action
	local accepted = feedback.accepted == true
	local uiAction = if pending.uiAction
		then pending.uiAction
		else if action == "Trap" then "Shield" else action
	if accepted and uiAction ~= "" and action ~= "ChargeStart" then
		local cooldown = if typeof(feedback.cooldownSeconds) == "number"
			then math.max(0, feedback.cooldownSeconds)
			else 0
		if cooldown > 0 then
			self._cooldownDurations[uiAction] = cooldown
			self._cooldownEnds[uiAction] =
				math.max(self._cooldownEnds[uiAction] or 0, os.clock() + cooldown)
		end
	end

	if action == "ChargeStart" and not accepted and self._chargingAction == pending.mode then
		self:_cancelCharge()
	elseif action == "Shield" then
		if pending.active == true then
			if accepted and self._shieldHeld then
				self._shielding = true
				self._shieldStartedAt = os.clock()
				self._ui:SetActionActive("Shield", true)
			elseif not accepted then
				self._shielding = false
				self._ui:SetActionActive("Shield", false)
			end
		elseif pending.active == false and accepted and not self._shieldHeld then
			self._shielding = false
			self._ui:SetActionActive("Shield", false)
		end
	elseif action == "Trap" and not accepted then
		self._trapBufferEndsAt = 0
		self._ui:SetPowerMeter("Trap", 0, false, "Trap")
	elseif action == "Feint" and accepted and pending.mode == "Roulette" then
		self._shielding = false
		self._ui:SetActionActive("Shield", false)
	end
	return true
end

function InputController._cancelCharge(self: InputController)
	local action = self._chargingAction
	if not action then
		return
	end
	self._chargingAction = nil
	self._chargeInputId = nil
	self._chargeToken += 1
	self._ui:SetPowerMeter(action, 0, false, if action == "Kick" then self:_shotType() else nil)
end

function InputController.ResetTransientState(self: InputController)
	if self._destroyed then
		return
	end

	self:_cancelCharge()
	self._chargingAction = nil
	self._chargeInputId = nil
	self._chargeToken += 1
	self._primaryMouseTackleActive = false
	self._chargeStartedAt = 0
	self._shieldHeld = false
	self:_stopShield(false)
	self._shieldStartedAt = 0
	self._trapBufferEndsAt = 0

	for _, action in ACTION_ORDER do
		self._ui:SetActionPending(action, false)
		self._ui:SetActionActive(action, false)
	end
	table.clear(self._pending)
	table.clear(self._pendingByAction)
	table.clear(self._cooldownEnds)
	table.clear(self._lastSentAt)

	self._cachedBall = nil
	self._cachedArenaId = self:_arenaId()
	self._feedbackArenaId = self:_arenaId()
	self._feedbackMatchId = self:_matchId()
	self._feedbackRevision = 0

	for _, button in self._touchButtons do
		if button.Parent ~= nil then
			button.Visible = false
		end
	end
	self._ui:ResetTransientState()
	local vfx = self._vfx
	if vfx then
		vfx:ResetTransientState()
	end
end

function InputController._beginCharge(
	self: InputController,
	action: string,
	input: InputObject
): Enum.ContextActionResult
	if inputIsBlocked() or not self:_isGameplayActive() then
		return Enum.ContextActionResult.Pass
	end
	if self._chargingAction or not self:_actionReady(action) then
		return Enum.ContextActionResult.Sink
	end
	if
		action == "Kick"
		and input.UserInputType == Enum.UserInputType.MouseButton1
		and self._ui:IsPointerOverUI()
	then
		return Enum.ContextActionResult.Pass
	end

	self._chargingAction = action
	self._chargeStartedAt = os.clock()
	self._chargeInputId = inputId(input)
	self._chargeToken += 1
	local minimumPower = if action == "Kick" then self._minimumKickPower else self._minimumPassPower
	self._ui:SetPowerMeter(
		action,
		minimumPower,
		true,
		if action == "Kick" then self:_shotType() else nil
	)
	self:_sendRequest("ChargeStart", nil, { chargeAction = action }, false)
	return Enum.ContextActionResult.Sink
end

function InputController._finishCharge(
	self: InputController,
	action: string,
	input: InputObject,
	cancelled: boolean
): Enum.ContextActionResult
	if self._chargingAction ~= action or self._chargeInputId ~= inputId(input) then
		return Enum.ContextActionResult.Pass
	end

	local chargeSeconds = if action == "Kick"
		then self._kickChargeSeconds
		else self._passChargeSeconds
	local minimumPower = if action == "Kick" then self._minimumKickPower else self._minimumPassPower
	local powerExponent = if action == "Kick"
		then self._kickPowerExponent
		else self._passPowerExponent
	local power =
		chargePower(os.clock() - self._chargeStartedAt, chargeSeconds, minimumPower, powerExponent)
	self._chargingAction = nil
	self._chargeInputId = nil
	self._chargeToken += 1
	self._ui:SetPowerMeter(action, 0, false, if action == "Kick" then self:_shotType() else nil)
	if not cancelled and self:_isGameplayActive() then
		if action == "Kick" then
			self:_sendRequest("Kick", "Kick", {
				power = power,
				shotType = self:_shotType(),
				spin = self:_kickSpin(),
			}, false)
		else
			self:_sendRequest("Pass", "Pass", { power = power }, false)
		end
	end
	return Enum.ContextActionResult.Sink
end

function InputController._onChargeAction(
	self: InputController,
	action: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		return self:_beginCharge(action, input)
	elseif inputState == Enum.UserInputState.End then
		return self:_finishCharge(action, input, false)
	elseif inputState == Enum.UserInputState.Cancel then
		return self:_finishCharge(action, input, true)
	end
	return Enum.ContextActionResult.Pass
end

function InputController._primaryMouseUsesTackle(self: InputController): boolean
	local _, ballState, ownerUserId = self:_ballContext()
	return ballState == "Controlled" and ownerUserId ~= 0 and ownerUserId ~= LOCAL_PLAYER.UserId
end

function InputController._onPrimaryAction(
	self: InputController,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 then
		return self:_onChargeAction("Kick", inputState, input)
	end

	if self._primaryMouseTackleActive then
		if inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
			self._primaryMouseTackleActive = false
		end
		return Enum.ContextActionResult.Sink
	end

	if inputState == Enum.UserInputState.Begin and self:_primaryMouseUsesTackle() then
		if inputIsBlocked() or not self:_isGameplayActive() or self._ui:IsPointerOverUI() then
			return Enum.ContextActionResult.Pass
		end
		self:_cancelCharge()
		self._primaryMouseTackleActive = true
		return self:_onInstantAction("Tackle", inputState)
	end

	return self:_onChargeAction("Kick", inputState, input)
end

function InputController._feintPayload(self: InputController): { [string]: any }
	local character = LOCAL_PLAYER.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	if self._shieldHeld or self._shielding then
		return { variant = "Roulette", lateral = 0 }
	end
	if not root or not root:IsA("BasePart") or not humanoid then
		return { variant = "StepOver", lateral = 0 }
	end
	local move = safePlanar(humanoid.MoveDirection)
	if move.Magnitude < 0.1 then
		return { variant = "StepOver", lateral = 0 }
	end
	local unit = move.Unit
	local forward = normalizedPlanar(root.CFrame.LookVector, Vector3.new(0, 0, -1))
	local right = normalizedPlanar(root.CFrame.RightVector, Vector3.new(1, 0, 0))
	local forwardDot = unit:Dot(forward)
	local lateralDot = unit:Dot(right)
	if forwardDot < -0.45 then
		return { variant = "DragBack", lateral = 0 }
	elseif math.abs(lateralDot) > math.max(0.35, math.abs(forwardDot)) then
		return {
			variant = "Cut",
			lateral = if lateralDot >= 0 then 1 else -1,
		}
	end
	return { variant = "StepOver", lateral = 0 }
end

function InputController._onInstantAction(
	self: InputController,
	action: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if inputIsBlocked() or not self:_isGameplayActive() then
		return Enum.ContextActionResult.Pass
	end
	local extra = if action == "Feint" then self:_feintPayload() else nil
	self:_sendRequest(action, action, extra, false)
	return Enum.ContextActionResult.Sink
end

function InputController._stopShield(self: InputController, notifyServer: boolean?)
	if not self._shielding then
		self._ui:SetActionActive("Shield", false)
		return
	end
	self._shielding = false
	self._ui:SetActionActive("Shield", false)
	if notifyServer ~= false then
		self:_sendRequest("Shield", nil, { active = false }, true)
	end
end

function InputController._onShield(
	self: InputController,
	_: string,
	inputState: Enum.UserInputState,
	_: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		if inputIsBlocked() or not self:_isGameplayActive() then
			return Enum.ContextActionResult.Pass
		end
		if self._shieldHeld then
			return Enum.ContextActionResult.Sink
		end
		self._shieldHeld = true
		local _, _, ownerUserId = self:_ballContext()
		if ownerUserId == LOCAL_PLAYER.UserId then
			if self:_sendRequest("Shield", "Shield", { active = true }, false) then
				self._shielding = true
				self._shieldStartedAt = os.clock()
				self._ui:SetActionActive("Shield", true)
			end
		else
			if self:_sendRequest("Trap", "Shield", nil, false) then
				self._trapBufferEndsAt = os.clock() + self._trapBufferSeconds
				self._ui:SetPowerMeter("Trap", 1, true, "Trap")
			end
		end
		return Enum.ContextActionResult.Sink
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		self._shieldHeld = false
		self._trapBufferEndsAt = 0
		self._ui:SetPowerMeter("Trap", 0, false, "Trap")
		self:_stopShield()
		return Enum.ContextActionResult.Sink
	end
	return Enum.ContextActionResult.Pass
end

function InputController._onShotMode(
	self: InputController,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if inputIsBlocked() or not self:_isGameplayActive() then
		return Enum.ContextActionResult.Pass
	end
	self._shotTypeIndex = self._shotTypeIndex % #SHOT_TYPES + 1
	local shotType = self:_shotType()
	self._ui:SetShotMode(shotType)
	if self._chargingAction == "Kick" then
		local power = chargePower(
			os.clock() - self._chargeStartedAt,
			self._kickChargeSeconds,
			self._minimumKickPower,
			self._kickPowerExponent
		)
		self._ui:SetPowerMeter("Kick", power, true, shotType)
	end
	self:_setTouchTitle("ShotMode", "SHOT\n" .. string.upper(shotType))
	return Enum.ContextActionResult.Sink
end

function InputController._setTouchTitle(self: InputController, action: string, title: string)
	if self._touchTitles[action] == title then
		return
	end
	self._touchTitles[action] = title
	local binding = (BINDINGS :: any)[action]
	ContextActionService:SetTitle(binding, title)
end

function InputController._refreshTouchLayout(self: InputController, force: boolean?)
	if not UserInputService.TouchEnabled then
		return
	end
	local camera = Workspace.CurrentCamera
	local viewport = if camera then camera.ViewportSize else Vector2.new(800, 600)
	local missingButton = false
	for _, action in TOUCH_ORDER do
		local button = self._touchButtons[action]
		if not button or button.Parent == nil then
			missingButton = true
			break
		end
	end
	if not force and viewport == self._lastViewport and not missingButton then
		return
	end
	self._lastViewport = viewport

	local short = viewport.Y < 500
	local size = if short then 48 else 56
	local xStep = if short then 54 else 62
	local bottomY = if short then -58 else -68
	local topY = if short then -112 else -130
	local modeY = if short then -162 else -191
	local rightX = if short then -36 else -42
	local positions = {
		Kick = UDim2.new(1, rightX, 1, bottomY),
		Pass = UDim2.new(1, rightX - xStep, 1, bottomY),
		Feint = UDim2.new(1, rightX - xStep * 2, 1, bottomY),
		Skill = UDim2.new(1, rightX, 1, topY),
		Shield = UDim2.new(1, rightX - xStep, 1, topY),
		Tackle = UDim2.new(1, rightX - xStep, 1, topY),
		Dash = UDim2.new(1, rightX - xStep * 2, 1, topY),
		ShotMode = UDim2.new(1, rightX, 1, modeY),
	}

	for action, position in positions do
		local binding = (BINDINGS :: any)[action]
		ContextActionService:SetPosition(binding, position)
		local button = ContextActionService:GetButton(binding)
		if button then
			styleTouchButton(button, if action == "ShotMode" then size - 12 else size)
			self._touchButtons[action] = button
		end
	end
end

function InputController._expirePending(self: InputController, now: number)
	local expired: { number } = {}
	for sequence, pending in self._pending do
		if now - pending.sentAt >= self._pendingTimeoutSeconds then
			table.insert(expired, sequence)
		end
	end
	for _, sequence in expired do
		local pending = self:_clearPending(sequence)
		if pending then
			if pending.action == "Shield" and pending.active == true then
				self._shielding = false
				self._ui:SetActionActive("Shield", false)
			elseif pending.action == "Trap" then
				self._trapBufferEndsAt = 0
				self._ui:SetPowerMeter("Trap", 0, false, "Trap")
			end
			self._ui:ApplyActionFeedback({
				accepted = false,
				executed = false,
				reason = "FeedbackTimeout",
				action = pending.action,
				sequence = sequence,
				cooldownSeconds = 0,
				revision = 0,
				controllerUserId = 0,
				mode = pending.mode or "",
			})
		end
	end
end

function InputController._updateFeedback(self: InputController)
	local now = os.clock()
	local gameplayActive = self:_isGameplayActive()
	local _, ballState, ownerUserId = self:_ballContext()
	self._ui:SetBallStatus(ballState, ownerUserId)
	for _, action in ACTION_ORDER do
		local duration = self._cooldownDurations[action] or 0
		local remaining = math.max(0, (self._cooldownEnds[action] or 0) - now)
		self._ui:SetActionCooldown(action, remaining, duration)

		if UserInputService.TouchEnabled then
			local button = self._touchButtons[action]
			local pending = self._pendingByAction[action] ~= nil
			if button then
				local visible = gameplayActive and self._preferredTouch
				if action == "Shield" then
					visible = visible
						and not (ownerUserId ~= 0 and ownerUserId ~= LOCAL_PLAYER.UserId)
				elseif action == "Tackle" then
					visible = visible and ownerUserId ~= 0 and ownerUserId ~= LOCAL_PLAYER.UserId
				end
				button.Visible = visible
				button.BackgroundColor3 = if action == "Shield" and self._shielding
					then Color3.fromRGB(22, 112, 126)
					else if pending
						then Color3.fromRGB(45, 65, 84)
						else if remaining > 0.04
							then Color3.fromRGB(52, 38, 48)
							else Color3.fromRGB(17, 24, 34)
				local stroke = button:FindFirstChild("PannaStroke")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Color = if pending
						then Color3.fromRGB(146, 161, 181)
						else if remaining > 0.04
							then Color3.fromRGB(255, 188, 52)
							else Color3.fromRGB(36, 226, 255)
				end
			end
			local baseTitle = (TOUCH_TITLES :: any)[action]
			if action == "Shield" and ownerUserId ~= LOCAL_PLAYER.UserId then
				baseTitle = "TRAP"
			end
			local title = if action == "Shield" and self._shielding
				then baseTitle .. "\nHOLD"
				else if pending
					then baseTitle .. "\n..."
					else if remaining > 0.04
						then string.format("%s\n%.1f", baseTitle, remaining)
						else baseTitle
			self:_setTouchTitle(action, title)
		end
	end

	local modeButton = self._touchButtons.ShotMode
	if modeButton then
		modeButton.Visible = gameplayActive and self._preferredTouch
	end
	self:_setTouchTitle("ShotMode", "SHOT\n" .. string.upper(self:_shotType()))
end

function InputController._onRenderStep(self: InputController)
	if self._destroyed then
		return
	end
	local now = os.clock()
	local gameplayActive = self:_isGameplayActive()
	local previewAction = self._chargingAction
		or if self:_primaryMouseUsesTackle() then "Tackle" else "Kick"
	local previewPower = 0
	if self._chargingAction then
		if gameplayActive then
			local action = self._chargingAction
			local duration = if action == "Kick"
				then self._kickChargeSeconds
				else self._passChargeSeconds
			local minimumPower = if action == "Kick"
				then self._minimumKickPower
				else self._minimumPassPower
			local exponent = if action == "Kick"
				then self._kickPowerExponent
				else self._passPowerExponent
			local power = chargePower(now - self._chargeStartedAt, duration, minimumPower, exponent)
			previewPower = power
			self._ui:SetPowerMeter(
				action,
				power,
				true,
				if action == "Kick" then self:_shotType() else nil
			)
		else
			self:_cancelCharge()
		end
	end
	local vfx = self._vfx
	if vfx then
		local ball, ballState, ownerUserId = self:_ballContext()
		local direction = self:_directionForAction(previewAction)
		vfx:SetAimState(
			ball,
			ballState,
			ownerUserId,
			direction,
			previewAction,
			if previewAction == "Kick" then self:_shotType() else "Ground",
			previewPower,
			gameplayActive,
			self._chargingAction ~= nil
		)
	end
	if self._trapBufferEndsAt > 0 then
		local remaining = self._trapBufferEndsAt - now
		if not gameplayActive or remaining <= 0 then
			self._trapBufferEndsAt = 0
			self._ui:SetPowerMeter("Trap", 0, false, "Trap")
		else
			self._ui:SetPowerMeter("Trap", remaining / self._trapBufferSeconds, true, "Trap")
		end
	end
	if
		self._shielding
		and (not gameplayActive or now - self._shieldStartedAt >= self._shieldMaxSeconds)
	then
		self._shieldHeld = false
		self:_stopShield()
	end
	self:_expirePending(now)
	self:_refreshTouchLayout(false)
	self:_updateFeedback()
end

function InputController._bindActions(self: InputController)
	local makeTouchButtons = UserInputService.TouchEnabled
	local kickInputs = (ACTIONS :: any).Kick.inputs
	local passInputs = (ACTIONS :: any).Pass.inputs
	local feintInputs = (ACTIONS :: any).Feint.inputs
	local tackleInputs = (ACTIONS :: any).Tackle.inputs
	local skillInputs = (ACTIONS :: any).Skill.inputs
	local shieldInputs = (ACTIONS :: any).Shield.inputs
	local dashInputs = (ACTIONS :: any).Dash.inputs
	local shotModeInputs = (ACTIONS :: any).ShotMode.inputs
	ContextActionService:BindActionAtPriority(BINDINGS.Kick, function(_, inputState, input)
		return self:_onPrimaryAction(inputState, input)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(kickInputs))
	ContextActionService:BindActionAtPriority(BINDINGS.Pass, function(_, inputState, input)
		return self:_onChargeAction("Pass", inputState, input)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(passInputs))
	ContextActionService:BindActionAtPriority(BINDINGS.Feint, function(_, inputState)
		return self:_onInstantAction("Feint", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(feintInputs))
	ContextActionService:BindActionAtPriority(BINDINGS.Tackle, function(_, inputState)
		return self:_onInstantAction("Tackle", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(tackleInputs))
	ContextActionService:BindActionAtPriority(BINDINGS.Skill, function(_, inputState)
		return self:_onInstantAction("Skill", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(skillInputs))
	ContextActionService:BindActionAtPriority(
		BINDINGS.Shield,
		function(actionName, inputState, input)
			return self:_onShield(actionName, inputState, input)
		end,
		makeTouchButtons,
		ACTION_PRIORITY,
		table.unpack(shieldInputs)
	)
	ContextActionService:BindActionAtPriority(BINDINGS.Dash, function(_, inputState)
		return self:_onInstantAction("Dash", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(dashInputs))
	ContextActionService:BindActionAtPriority(BINDINGS.ShotMode, function(_, inputState)
		return self:_onShotMode(inputState)
	end, makeTouchButtons, ACTION_PRIORITY, table.unpack(shotModeInputs))

	if makeTouchButtons then
		for action, binding in BINDINGS do
			local title = if action == "ShotMode"
				then "SHOT\n" .. string.upper(self:_shotType())
				else (TOUCH_TITLES :: any)[action]
			self:_setTouchTitle(action, title)
			local button = ContextActionService:GetButton(binding)
			if button then
				button.Visible = false
				self._touchButtons[action] = button
			end
		end
	end
end

function InputController.Destroy(self: InputController)
	if self._destroyed then
		return
	end
	self:ResetTransientState()
	self._destroyed = true
	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end
	for _, connection in self._connections do
		connection:Disconnect()
	end
	table.clear(self._connections)
	for _, actionName in BINDINGS do
		ContextActionService:UnbindAction(actionName)
	end
end

return InputController
