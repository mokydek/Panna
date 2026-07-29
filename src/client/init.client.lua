--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local UIController = require(script:WaitForChild("UIController") :: ModuleScript)
local InputController = require(script:WaitForChild("InputController") :: ModuleScript)

local LOCAL_PLAYER = Players.LocalPlayer
local REMOTE_WAIT_SECONDS = 20

type NetDefinition = {
	FolderName: string,
	Events: {
		ActionRequest: string,
		ActionFeedback: string,
		QueueRequest: string,
		StateUpdate: string,
		Effect: string,
	},
	Functions: {
		GetSnapshot: string,
	},
}

local FALLBACK_NET: NetDefinition = {
	FolderName = "PannaRemotes",
	Events = {
		ActionRequest = "ActionRequest",
		ActionFeedback = "ActionFeedback",
		QueueRequest = "QueueRequest",
		StateUpdate = "StateUpdate",
		Effect = "Effect",
	},
	Functions = {
		GetSnapshot = "GetSnapshot",
	},
}

local function loadNetDefinition(): NetDefinition
	local sharedFolder = ReplicatedStorage:FindFirstChild("PannaShared")
		or ReplicatedStorage:WaitForChild("PannaShared", 8)
	if sharedFolder == nil then
		warn("[PannaClient] PannaShared was not replicated; using the stable remote names")
		return FALLBACK_NET
	end

	local netModule = sharedFolder:FindFirstChild("Net") or sharedFolder:WaitForChild("Net", 8)
	if netModule == nil or not netModule:IsA("ModuleScript") then
		warn("[PannaClient] PannaShared.Net is missing; using the stable remote names")
		return FALLBACK_NET
	end

	local success, result = pcall(require, netModule)
	if not success or typeof(result) ~= "table" then
		warn("[PannaClient] Unable to load PannaShared.Net; using the stable remote names")
		return FALLBACK_NET
	end
	return result :: NetDefinition
end

local function waitForRemote(
	parent: Instance,
	name: string,
	className: string,
	deadline: number
): Instance?
	local remaining = math.max(0.05, deadline - os.clock())
	local child = parent:FindFirstChild(name) or parent:WaitForChild(name, remaining)
	if child == nil then
		warn(string.format("[PannaClient] Timed out waiting for %s", name))
		return nil
	end
	if not child:IsA(className) then
		warn(
			string.format("[PannaClient] %s must be a %s, got %s", name, className, child.ClassName)
		)
		return nil
	end
	return child
end

local ui = UIController.new()
local inputController: any = nil
local connections: { RBXScriptConnection } = {}
local destroyed = false

local function destroy()
	if destroyed then
		return
	end
	destroyed = true
	if inputController then
		inputController:Destroy()
		inputController = nil
	end
	for _, connection in connections do
		connection:Disconnect()
	end
	table.clear(connections)
	ui:Destroy()
end

table.insert(connections, script.Destroying:Connect(destroy))

-- Character-dependent input reads are always guarded. A cancellable one-shot listener
-- warms the first character without leaving an event wait behind when the script is removed.
do
	local warmed = false
	local characterConnection: RBXScriptConnection? = nil
	local function warmCharacter(character: Model)
		if warmed then
			return
		end
		warmed = true
		if characterConnection then
			characterConnection:Disconnect()
			characterConnection = nil
		end
		task.spawn(function()
			if destroyed or character.Parent == nil then
				return
			end
			character:WaitForChild("HumanoidRootPart", 10)
		end)
	end

	local connection = LOCAL_PLAYER.CharacterAdded:Connect(warmCharacter)
	characterConnection = connection
	table.insert(connections, connection)
	local currentCharacter = LOCAL_PLAYER.Character
	if currentCharacter then
		warmCharacter(currentCharacter)
	end
end

task.spawn(function()
	local net = loadNetDefinition()
	if destroyed then
		return
	end

	local remoteFolder = ReplicatedStorage:FindFirstChild(net.FolderName)
		or ReplicatedStorage:WaitForChild(net.FolderName, REMOTE_WAIT_SECONDS)
	if remoteFolder == nil then
		if not destroyed then
			ui:SetConnectionError("Server remotes did not load")
		end
		return
	end

	local remoteDeadline = os.clock() + REMOTE_WAIT_SECONDS
	local actionInstance =
		waitForRemote(remoteFolder, net.Events.ActionRequest, "RemoteEvent", remoteDeadline)
	local actionFeedbackInstance =
		waitForRemote(remoteFolder, net.Events.ActionFeedback, "RemoteEvent", remoteDeadline)
	local queueInstance =
		waitForRemote(remoteFolder, net.Events.QueueRequest, "RemoteEvent", remoteDeadline)
	local stateInstance =
		waitForRemote(remoteFolder, net.Events.StateUpdate, "RemoteEvent", remoteDeadline)
	local effectInstance =
		waitForRemote(remoteFolder, net.Events.Effect, "RemoteEvent", remoteDeadline)
	local snapshotInstance =
		waitForRemote(remoteFolder, net.Functions.GetSnapshot, "RemoteFunction", remoteDeadline)
	if destroyed then
		return
	end
	if
		not (
			actionInstance
			and actionFeedbackInstance
			and queueInstance
			and stateInstance
			and effectInstance
			and snapshotInstance
		)
	then
		ui:SetConnectionError("Server protocol is incomplete")
		return
	end

	local actionRequest = actionInstance :: RemoteEvent
	local actionFeedback = actionFeedbackInstance :: RemoteEvent
	local queueRequest = queueInstance :: RemoteEvent
	local stateUpdate = stateInstance :: RemoteEvent
	local effect = effectInstance :: RemoteEvent
	local getSnapshot = snapshotInstance :: RemoteFunction

	ui:SetQueueRequestHandler(function(action: string)
		if destroyed or queueRequest.Parent == nil then
			return
		end
		queueRequest:FireServer(action)
	end)

	local feedbackBeforeInput: { any } = {}
	table.insert(
		connections,
		actionFeedback.OnClientEvent:Connect(function(payload: any)
			if destroyed then
				return
			end
			local success, message = pcall(function()
				ui:ApplyActionFeedback(payload)
				if inputController then
					inputController:ApplyActionFeedback(payload)
				else
					table.insert(feedbackBeforeInput, payload)
				end
			end)
			if not success then
				warn("[PannaClient] Rejected malformed ActionFeedback:", message)
			end
		end)
	)

	table.insert(
		connections,
		stateUpdate.OnClientEvent:Connect(function(payload: any)
			if destroyed then
				return
			end
			local success, message = pcall(function()
				ui:ApplyState(payload, false)
			end)
			if not success then
				warn("[PannaClient] Rejected malformed StateUpdate:", message)
			end
		end)
	)

	table.insert(
		connections,
		effect.OnClientEvent:Connect(function(payload: any)
			if destroyed then
				return
			end
			local success, message = pcall(function()
				ui:ApplyEffect(payload)
			end)
			if not success then
				warn("[PannaClient] Rejected malformed Effect:", message)
			end
		end)
	)

	inputController = InputController.new(actionRequest, ui)
	for _, payload in feedbackBeforeInput do
		inputController:ApplyActionFeedback(payload)
	end
	table.clear(feedbackBeforeInput)

	local success, snapshot = pcall(function()
		return getSnapshot:InvokeServer()
	end)
	if destroyed then
		return
	end
	if success and typeof(snapshot) == "table" then
		ui:ApplyState(snapshot, true)
	elseif not success then
		warn("[PannaClient] Initial snapshot failed:", snapshot)
		ui:ShowNotification("SYNC DELAYED", "Live updates are still connected", nil, 3.5)
	end
end)
