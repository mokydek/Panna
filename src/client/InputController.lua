--!strict

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

local LOCAL_PLAYER = Players.LocalPlayer
local CHARGE_SECONDS = 1.15
local MINIMUM_KICK_POWER = 0.12
local ACTION_PRIORITY = Enum.ContextActionPriority.High.Value

local BINDINGS = table.freeze({
	Kick = "Panna_Kick",
	Pass = "Panna_Pass",
	Tackle = "Panna_Tackle",
	Skill = "Panna_Skill",
	Dash = "Panna_Dash",
})

type UIControllerLike = {
	SetKickPower: (self: any, power: number, charging: boolean) -> (),
	IsPointerOverUI: (self: any) -> boolean,
}

type ControllerFields = {
	_actionRequest: RemoteEvent,
	_ui: UIControllerLike,
	_charging: boolean,
	_chargeStartedAt: number,
	_chargeInputId: string?,
	_chargeToken: number,
	_lastSentAt: { [string]: number },
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

function InputController.new(actionRequest: RemoteEvent, ui: UIControllerLike): InputController
	local self = setmetatable({
		_actionRequest = actionRequest,
		_ui = ui,
		_charging = false,
		_chargeStartedAt = 0,
		_chargeInputId = nil,
		_chargeToken = 0,
		_lastSentAt = {},
		_renderConnection = nil,
		_destroyed = false,
	}, InputController) :: InputController

	self:_bindActions()
	self._renderConnection = RunService.RenderStepped:Connect(function()
		if not self._charging or self._destroyed then
			return
		end
		local power = math.clamp((os.clock() - self._chargeStartedAt) / CHARGE_SECONDS, 0, 1)
		self._ui:SetKickPower(power, true)
	end)

	return self
end

function InputController._canSend(
	self: InputController,
	action: string,
	minimumInterval: number
): boolean
	if self._destroyed or self._actionRequest.Parent == nil or inputIsBlocked() then
		return false
	end

	local now = os.clock()
	local lastSentAt = self._lastSentAt[action] or 0
	if now - lastSentAt < minimumInterval then
		return false
	end
	self._lastSentAt[action] = now
	return true
end

function InputController._sendAction(self: InputController, action: string, power: number?)
	local interval = if action == "Kick" then 0.08 else 0.14
	if not self:_canSend(action, interval) then
		return
	end

	local payload: { [string]: any } = {
		action = action,
		direction = getPlanarDirection(action == "Dash"),
		clientTime = Workspace:GetServerTimeNow(),
	}
	if power ~= nil then
		payload.power = math.clamp(power, 0, 1)
	end

	self._actionRequest:FireServer(payload)
end

function InputController._beginKick(
	self: InputController,
	input: InputObject
): Enum.ContextActionResult
	if self._charging or inputIsBlocked() then
		return Enum.ContextActionResult.Pass
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
	self._ui:SetKickPower(if cancelled then 0 else power, false)
	if not cancelled then
		self:_sendAction("Kick", power)
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
	if inputIsBlocked() then
		return Enum.ContextActionResult.Pass
	end
	self:_sendAction(action, nil)
	return Enum.ContextActionResult.Sink
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
	ContextActionService:BindActionAtPriority(BINDINGS.Tackle, function(_, inputState)
		return self:_onInstantAction("Tackle", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.F, Enum.KeyCode.ButtonB)
	ContextActionService:BindActionAtPriority(BINDINGS.Skill, function(_, inputState)
		return self:_onInstantAction("Skill", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.R, Enum.KeyCode.ButtonY)
	ContextActionService:BindActionAtPriority(BINDINGS.Dash, function(_, inputState)
		return self:_onInstantAction("Dash", inputState)
	end, makeTouchButtons, ACTION_PRIORITY, Enum.KeyCode.LeftShift, Enum.KeyCode.ButtonL1)

	if makeTouchButtons then
		ContextActionService:SetTitle(BINDINGS.Kick, "KICK")
		ContextActionService:SetPosition(BINDINGS.Kick, UDim2.new(1, -94, 1, -172))
		ContextActionService:SetTitle(BINDINGS.Pass, "PASS")
		ContextActionService:SetPosition(BINDINGS.Pass, UDim2.new(1, -186, 1, -116))
		ContextActionService:SetTitle(BINDINGS.Tackle, "TAKE")
		ContextActionService:SetPosition(BINDINGS.Tackle, UDim2.new(1, -278, 1, -172))
		ContextActionService:SetTitle(BINDINGS.Skill, "PANNA")
		ContextActionService:SetPosition(BINDINGS.Skill, UDim2.new(1, -186, 1, -224))
		ContextActionService:SetTitle(BINDINGS.Dash, "DASH")
		ContextActionService:SetPosition(BINDINGS.Dash, UDim2.new(1, -94, 1, -278))
	end
end

function InputController.Destroy(self: InputController)
	if self._destroyed then
		return
	end
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
	self._ui:SetKickPower(0, false)
end

return InputController
