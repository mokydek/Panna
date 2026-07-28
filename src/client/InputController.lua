--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local CHARGE_SECONDS = 1.15
local MINIMUM_KICK_POWER = 0.12
local STRONG_KICK_POWER = 0.78
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

local ACTION_ORDER = table.freeze({ "Kick", "Pass", "Feint", "Skill", "Tackle", "Shield", "Dash" })
local BINDINGS = table.freeze({
	Kick = "Panna_Kick",
	Pass = "Panna_Pass",
	Feint = "Panna_Feint",
	Tackle = "Panna_Tackle",
	Skill = "Panna_Skill",
	Shield = "Panna_Shield",
	Dash = "Panna_Dash",
})
local TOUCH_TITLES = table.freeze({
	Kick = "KICK",
	Pass = "PASS",
	Feint = "FEINT",
	Tackle = "TAKE",
	Skill = "PANNA",
	Shield = "SHIELD",
	Dash = "DASH",
})
local DEFAULT_COOLDOWNS = table.freeze({
	Kick = 0.28,
	Pass = 0.35,
	Feint = 1.1,
	Tackle = 1.2,
	Skill = 2,
	Shield = 0.15,
	Dash = 3,
})

type UIControllerLike = {
	SetKickPower: (self: any, power: number, charging: boolean) -> (),
	SetActionCooldown: (self: any, action: string, remaining: number, duration: number) -> (),
	SetActionActive: (self: any, action: string, active: boolean) -> (),
	PlayImpact: (self: any, kind: string, strength: number?) -> (),
	IsGameplayActive: (self: any) -> boolean,
	IsPointerOverUI: (self: any) -> boolean,
}

type ControllerFields = {
	_actionRequest: RemoteEvent,
	_ui: UIControllerLike,
	_charging: boolean,
	_chargeStartedAt: number,
	_chargeInputId: string?,
	_chargeToken: number,
	_shielding: boolean,
	_shieldStartedAt: number,
	_shieldMaxSeconds: number,
	_lastSentAt: { [string]: number },
	_cooldownEnds: { [string]: number },
	_cooldownDurations: { [string]: number },
	_touchButtons: { [string]: GuiButton },
	_touchTitles: { [string]: string },
	_lastViewport: Vector2,
	_renderConnection: RBXScriptConnection?,
	_destroyed: boolean,
}

local InputController = {}
InputController.__index = InputController

export type InputController = typeof(setmetatable({} :: ControllerFields, InputController))

local function inputId(input: InputObject): string
	return string.format("%s/%s", input.UserInputType.Name, input.KeyCode.Name)
end

local function getPlanarDirection(preferMovement: boolean): Vector3
	local character = LOCAL_PLAYER.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil

	if preferMovement and humanoid and humanoid.MoveDirection.Magnitude > 0.08 then
		return humanoid.MoveDirection.Unit
	end

	local camera = Workspace.CurrentCamera
	if camera then
		local look = camera.CFrame.LookVector
		local planar = Vector3.new(look.X, 0, look.Z)
		if planar.Magnitude > 0.05 then
			return planar.Unit
		end
	end

	if root and root:IsA("BasePart") then
		local look = root.CFrame.LookVector
		local planar = Vector3.new(look.X, 0, look.Z)
		if planar.Magnitude > 0.05 then
			return planar.Unit
		end
	end

	return Vector3.new(0, 0, -1)
end

local function inputIsBlocked(): boolean
	return UserInputService:GetFocusedTextBox() ~= nil
end

local function loadActionSettings(): ({ [string]: number }, number)
	local cooldowns: { [string]: number } = table.clone(DEFAULT_COOLDOWNS :: any)

	local shieldMaxSeconds = 2.5
	local shared = ReplicatedStorage:FindFirstChild("PannaShared")
	local configModule = if shared then shared:FindFirstChild("Config") else nil
	if not configModule or not configModule:IsA("ModuleScript") then
		return cooldowns, shieldMaxSeconds
	end

	local success, config = pcall(require, configModule)
	if not success or typeof(config) ~= "table" or typeof(config.Actions) ~= "table" then
		return cooldowns, shieldMaxSeconds
	end

	local actions = config.Actions
	for _, action in ACTION_ORDER do
		local key = if action == "Shield" then "ShieldToggleCooldown" else action .. "Cooldown"
		local value = actions[key]
		if typeof(value) == "number" and value >= 0 then
			cooldowns[action] = value
		elseif action == "Shield" and typeof(actions.ShieldCooldown) == "number" then
			cooldowns[action] = math.max(0, actions.ShieldCooldown)
		end
	end
	if typeof(actions.ShieldMaxSeconds) == "number" and actions.ShieldMaxSeconds > 0 then
		shieldMaxSeconds = actions.ShieldMaxSeconds
	end

	return cooldowns, shieldMaxSeconds
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
			descendant.TextSize = if size <= 50 then 9 else 10
			descendant.TextWrapped = true
		end
	end
end

function InputController.new(actionRequest: RemoteEvent, ui: UIControllerLike): InputController
	local cooldowns, shieldMaxSeconds = loadActionSettings()
	local self = setmetatable({
		_actionRequest = actionRequest,
		_ui = ui,
		_charging = false,
		_chargeStartedAt = 0,
		_chargeInputId = nil,
		_chargeToken = 0,
		_shielding = false,
		_shieldStartedAt = 0,
		_shieldMaxSeconds = shieldMaxSeconds,
		_lastSentAt = {},
		_cooldownEnds = {},
		_cooldownDurations = cooldowns,
		_touchButtons = {},
		_touchTitles = {},
		_lastViewport = Vector2.zero,
		_renderConnection = nil,
		_destroyed = false,
	}, InputController) :: InputController

	self:_bindActions()
	self:_refreshTouchLayout(true)
	self:_updateFeedback()
	self._renderConnection = RunService.RenderStepped:Connect(function()
		self:_onRenderStep()
	end)

	return self
end

function InputController._actionReady(self: InputController, action: string): boolean
	return os.clock() >= (self._cooldownEnds[action] or 0)
end

function InputController._canSend(self: InputController, action: string): boolean
	if
		self._destroyed
		or self._actionRequest.Parent == nil
		or inputIsBlocked()
		or not self._ui:IsGameplayActive()
		or not self:_actionReady(action)
	then
		return false
	end

	local now = os.clock()
	local lastSentAt = self._lastSentAt[action] or 0
	if now - lastSentAt < 0.04 then
		return false
	end
	self._lastSentAt[action] = now
	return true
end

function InputController._sendAction(
	self: InputController,
	action: string,
	power: number?,
	extra: { [string]: any }?
): boolean
	if not self:_canSend(action) then
		return false
	end

	local payload: { [string]: any } = {
		action = action,
		direction = getPlanarDirection(action == "Dash" or action == "Feint" or action == "Shield"),
		clientTime = Workspace:GetServerTimeNow(),
	}
	if power ~= nil then
		payload.power = math.clamp(power, 0, 1)
	end
	if extra then
		for key, value in extra do
			payload[key] = value
		end
	end

	self._actionRequest:FireServer(payload)
	local duration = self._cooldownDurations[action] or 0
	self._cooldownEnds[action] = os.clock() + duration
	return true
end

function InputController._cancelKick(self: InputController)
	if not self._charging then
		return
	end
	self._charging = false
	self._chargeInputId = nil
	self._chargeToken += 1
	self._ui:SetKickPower(0, false)
end

function InputController._beginKick(
	self: InputController,
	input: InputObject
): Enum.ContextActionResult
	if inputIsBlocked() or not self._ui:IsGameplayActive() then
		return Enum.ContextActionResult.Pass
	end
	if self._charging or not self:_actionReady("Kick") then
		return Enum.ContextActionResult.Sink
	end
	if input.UserInputType == Enum.UserInputType.MouseButton1 and self._ui:IsPointerOverUI() then
		return Enum.ContextActionResult.Pass
	end

	self._charging = true
	self._chargeStartedAt = os.clock()
	self._chargeInputId = inputId(input)
	self._chargeToken += 1
	self._ui:SetKickPower(0, true)
	return Enum.ContextActionResult.Sink
end

function InputController._finishKick(
	self: InputController,
	input: InputObject,
	cancelled: boolean
): Enum.ContextActionResult
	if not self._charging or self._chargeInputId ~= inputId(input) then
		return Enum.ContextActionResult.Pass
	end

	local power =
		math.clamp((os.clock() - self._chargeStartedAt) / CHARGE_SECONDS, MINIMUM_KICK_POWER, 1)
	self._charging = false
	self._chargeInputId = nil
	self._chargeToken += 1
	local token = self._chargeToken
	local shouldSend = not cancelled and self._ui:IsGameplayActive()
	self._ui:SetKickPower(if shouldSend then power else 0, false)
	if shouldSend and self:_sendAction("Kick", power, nil) and power >= STRONG_KICK_POWER then
		self._ui:PlayImpact("Kick", power)
	end

	task.delay(0.18, function()
		if not self._destroyed and not self._charging and token == self._chargeToken then
			self._ui:SetKickPower(0, false)
		end
	end)
	return Enum.ContextActionResult.Sink
end

function InputController._onKick(
	self: InputController,
	_: string,
	inputState: Enum.UserInputState,
	input: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		return self:_beginKick(input)
	elseif inputState == Enum.UserInputState.End then
		return self:_finishKick(input, false)
	elseif inputState == Enum.UserInputState.Cancel then
		return self:_finishKick(input, true)
	end
	return Enum.ContextActionResult.Pass
end

function InputController._onInstantAction(
	self: InputController,
	action: string,
	inputState: Enum.UserInputState
): Enum.ContextActionResult
	if inputState ~= Enum.UserInputState.Begin then
		return Enum.ContextActionResult.Pass
	end
	if inputIsBlocked() or not self._ui:IsGameplayActive() then
		return Enum.ContextActionResult.Pass
	end
	self:_sendAction(action, nil, nil)
	return Enum.ContextActionResult.Sink
end

function InputController._stopShield(self: InputController)
	if not self._shielding then
		return
	end
	self._shielding = false
	self._ui:SetActionActive("Shield", false)
	if self._actionRequest.Parent ~= nil then
		self._actionRequest:FireServer({
			action = "Shield",
			active = false,
			direction = getPlanarDirection(true),
			clientTime = Workspace:GetServerTimeNow(),
		})
	end
end

function InputController._onShield(
	self: InputController,
	_: string,
	inputState: Enum.UserInputState,
	_: InputObject
): Enum.ContextActionResult
	if inputState == Enum.UserInputState.Begin then
		if inputIsBlocked() or not self._ui:IsGameplayActive() then
			return Enum.ContextActionResult.Pass
		end
		if self._shielding then
			return Enum.ContextActionResult.Sink
		end
		if self:_sendAction("Shield", nil, { active = true }) then
			self._shielding = true
			self._shieldStartedAt = os.clock()
			self._ui:SetActionActive("Shield", true)
		end
		return Enum.ContextActionResult.Sink
	elseif inputState == Enum.UserInputState.End or inputState == Enum.UserInputState.Cancel then
		if self._shielding then
			self:_stopShield()
			return Enum.ContextActionResult.Sink
		end
	end
	return Enum.ContextActionResult.Pass
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
	for _, action in ACTION_ORDER do
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
	local bottomY = if short then -55 else -66
	local topY = if short then -108 else -128
	local rightX = if short then -36 else -42
	local positions = {
		Kick = UDim2.new(1, rightX, 1, bottomY),
		Pass = UDim2.new(1, rightX - xStep, 1, bottomY),
		Feint = UDim2.new(1, rightX - xStep * 2, 1, bottomY),
		Tackle = UDim2.new(1, rightX - xStep * 3, 1, bottomY),
		Skill = UDim2.new(1, rightX, 1, topY),
		Shield = UDim2.new(1, rightX - xStep, 1, topY),
		Dash = UDim2.new(1, rightX - xStep * 2, 1, topY),
	}

	for action, position in positions do
		local binding = (BINDINGS :: any)[action]
		ContextActionService:SetPosition(binding, position)
		local button = ContextActionService:GetButton(binding)
		if button then
			styleTouchButton(button, size)
			self._touchButtons[action] = button
		end
	end
end

function InputController._updateFeedback(self: InputController)
	local now = os.clock()
	local gameplayActive = self._ui:IsGameplayActive()
	for _, action in ACTION_ORDER do
		local duration = self._cooldownDurations[action] or 0
		local remaining = math.max(0, (self._cooldownEnds[action] or 0) - now)
		self._ui:SetActionCooldown(action, remaining, duration)

		if UserInputService.TouchEnabled then
			local button = self._touchButtons[action]
			if button then
				button.Visible = gameplayActive
				button.BackgroundColor3 = if action == "Shield" and self._shielding
					then Color3.fromRGB(22, 112, 126)
					else if remaining > 0.04
						then Color3.fromRGB(52, 38, 48)
						else Color3.fromRGB(17, 24, 34)
				local stroke = button:FindFirstChild("PannaStroke")
				if stroke and stroke:IsA("UIStroke") then
					stroke.Color = if remaining > 0.04
						then Color3.fromRGB(255, 188, 52)
						else Color3.fromRGB(36, 226, 255)
				end
			end
			local baseTitle = (TOUCH_TITLES :: any)[action]
			local title = if action == "Shield" and self._shielding
				then baseTitle .. "\nHOLD"
				else if remaining > 0.04
					then string.format("%s\n%.1f", baseTitle, remaining)
					else baseTitle
			self:_setTouchTitle(action, title)
		end
	end
end

function InputController._onRenderStep(self: InputController)
	if self._destroyed then
		return
	end
	local gameplayActive = self._ui:IsGameplayActive()
	if self._charging then
		if gameplayActive then
			local power = math.clamp((os.clock() - self._chargeStartedAt) / CHARGE_SECONDS, 0, 1)
			self._ui:SetKickPower(power, true)
		else
			self:_cancelKick()
		end
	end
	if
		self._shielding
		and (not gameplayActive or os.clock() - self._shieldStartedAt >= self._shieldMaxSeconds)
	then
		self:_stopShield()
	end

	self:_refreshTouchLayout(false)
	self:_updateFeedback()
end

function InputController._bindActions(self: InputController)
	local makeTouchButtons = UserInputService.TouchEnabled

	ContextActionService:BindActionAtPriority(
		BINDINGS.Kick,
		function(actionName, inputState, input)
			return self:_onKick(actionName, inputState, input)
		end,
		makeTouchButtons,
		ACTION_PRIORITY,
		Enum.UserInputType.MouseButton1,
		Enum.KeyCode.E,
		Enum.KeyCode.ButtonR2
	)
	ContextActionService:BindActionAtPriority(BINDINGS.Pass, function(_, inputState)
		return self:_onInstantAction("Pass", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.Q, Enum.KeyCode.ButtonX)
	ContextActionService:BindActionAtPriority(BINDINGS.Feint, function(_, inputState)
		return self:_onInstantAction("Feint", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.V, Enum.KeyCode.ButtonR1)
	ContextActionService:BindActionAtPriority(BINDINGS.Tackle, function(_, inputState)
		return self:_onInstantAction("Tackle", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority(BINDINGS.Skill, function(_, inputState)
		return self:_onInstantAction("Skill", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority(
		BINDINGS.Shield,
		function(actionName, inputState, input)
			return self:_onShield(actionName, inputState, input)
		end,
		makeTouchButtons,
		ACTION_PRIORITY,
		Enum.KeyCode.C,
		Enum.KeyCode.ButtonL2
	)
	ContextActionService:BindActionAtPriority(BINDINGS.Dash, function(_, inputState)
		return self:_onInstantAction("Dash", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL1)

	if makeTouchButtons then
		for action, binding in BINDINGS do
			self:_setTouchTitle(action, (TOUCH_TITLES :: any)[action])
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
	self:_stopShield()
	self._destroyed = true
	self._chargeToken += 1
	self._charging = false
	self._chargeInputId = nil
	if self._renderConnection then
		self._renderConnection:Disconnect()
		self._renderConnection = nil
	end
	for _, actionName in BINDINGS do
		ContextActionService:UnbindAction(actionName)
	end
	self._ui:SetActionActive("Shield", false)
	self._ui:SetKickPower(0, false)
end

return InputController
