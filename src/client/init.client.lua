--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local Workspace = game:GetService("Workspace")

local UIController = require(script:WaitForChild("UIController") :: ModuleScript)
local InputController = require(script:WaitForChild("InputController") :: ModuleScript)
local EffectScope = require(script:WaitForChild("EffectScope") :: ModuleScript)

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
local controlsRestoreToken = 0

local function stringAttribute(name: string): string
	local value = LOCAL_PLAYER:GetAttribute(name)
	return if typeof(value) == "string" then value else ""
end

local function revisionAttribute(): number
	local value = LOCAL_PLAYER:GetAttribute("MatchRevision")
	return if type(value) == "number"
			and value == value
			and value >= 1
		then math.floor(value)
		else 0
end

local function resetTransientClientState()
	if destroyed then
		return
	end
	if inputController then
		inputController:ResetTransientState()
	else
		ui:ResetTransientState()
	end
end

local function restoreDefaultControls()
	controlsRestoreToken += 1
	local token = controlsRestoreToken
	task.spawn(function()
		local playerScripts = LOCAL_PLAYER:FindFirstChild("PlayerScripts")
			or LOCAL_PLAYER:WaitForChild("PlayerScripts", 8)
		if destroyed or token ~= controlsRestoreToken then
			return
		end
		if LOCAL_PLAYER:GetAttribute("ControlsLocked") == true then
			return
		end

		if playerScripts then
			local playerModuleInstance = playerScripts:FindFirstChild("PlayerModule")
				or playerScripts:WaitForChild("PlayerModule", 8)
			if
				playerModuleInstance
				and playerModuleInstance:IsA("ModuleScript")
				and not destroyed
				and token == controlsRestoreToken
				and LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true
			then
				local moduleSuccess, playerModule = pcall(require, playerModuleInstance)
				if moduleSuccess and typeof(playerModule) == "table" then
					local controlsSuccess, controls = pcall(function(): any
						return playerModule:GetControls()
					end)
					if
						controlsSuccess
						and typeof(controls) == "table"
						and not destroyed
						and token == controlsRestoreToken
						and LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true
					then
						pcall(function()
							controls:Enable()
						end)
					end
				end
			end
		end

		if
			destroyed
			or token ~= controlsRestoreToken
			or LOCAL_PLAYER:GetAttribute("ControlsLocked") == true
		then
			return
		end
		local character = LOCAL_PLAYER.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		local camera = Workspace.CurrentCamera
		if character and humanoid and humanoid.Health > 0 and camera then
			camera.CameraType = Enum.CameraType.Custom
			camera.CameraSubject = humanoid
		end
	end)
end

local lastInMatch = LOCAL_PLAYER:GetAttribute("InMatch") == true
local lastControlsLocked = LOCAL_PLAYER:GetAttribute("ControlsLocked") == true
local lastArenaId = stringAttribute("ArenaId")
local lastMatchId = stringAttribute("MatchId")
local recentArenaId = lastArenaId
local recentMatchId = lastMatchId
local recentMatchRevision = revisionAttribute()

local function handleMatchContextChanged()
	if destroyed then
		return
	end
	local inMatch = LOCAL_PLAYER:GetAttribute("InMatch") == true
	local controlsLocked = LOCAL_PLAYER:GetAttribute("ControlsLocked") == true
	local arenaId = stringAttribute("ArenaId")
	local matchId = stringAttribute("MatchId")
	local identityChanged = arenaId ~= lastArenaId or matchId ~= lastMatchId
	local leftMatch = lastInMatch and not inMatch
	local enteredMatch = not lastInMatch and inMatch
	local becameLocked = not lastControlsLocked and controlsLocked
	local becameUnlocked = lastControlsLocked and not controlsLocked
	if enteredMatch then
		controlsRestoreToken += 1
	end
	if identityChanged or enteredMatch or leftMatch or becameLocked then
		resetTransientClientState()
	end
	if leftMatch then
		ui:SetMatchState(nil)
	end
	if (leftMatch or becameUnlocked) and not controlsLocked then
		restoreDefaultControls()
	end

	lastInMatch = inMatch
	lastControlsLocked = controlsLocked
	lastArenaId = arenaId
	lastMatchId = matchId
end

local function destroy()
	if destroyed then
		return
	end
	destroyed = true
	controlsRestoreToken += 1
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

for _, attributeName in { "InMatch", "ControlsLocked", "ArenaId", "MatchId", "MatchRevision" } do
	table.insert(
		connections,
		LOCAL_PLAYER:GetAttributeChangedSignal(attributeName):Connect(handleMatchContextChanged)
	)
end
table.insert(
	connections,
	LOCAL_PLAYER.CharacterRemoving:Connect(function()
		controlsRestoreToken += 1
		resetTransientClientState()
	end)
)
table.insert(
	connections,
	LOCAL_PLAYER.CharacterAdded:Connect(function(character: Model)
		resetTransientClientState()
		task.spawn(function()
			local humanoid = character:WaitForChild("Humanoid", 8)
			if
				not destroyed
				and character == LOCAL_PLAYER.Character
				and humanoid
				and humanoid:IsA("Humanoid")
				and LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true
			then
				restoreDefaultControls()
			end
		end)
	end)
)
if LOCAL_PLAYER:GetAttribute("ControlsLocked") ~= true then
	restoreDefaultControls()
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
				if inputController then
					if inputController:ApplyActionFeedback(payload) then
						ui:ApplyActionFeedback(payload)
					end
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
				local stateMatchId, stateArenaId, stateRevision =
					EffectScope.ReadStateContext(payload)
				local envelopeRevision = EffectScope.ReadStateRevision(payload)
				local knownRevision = math.max(revisionAttribute(), recentMatchRevision)
				local allowMatchState = envelopeRevision <= 0 or envelopeRevision >= knownRevision
				if stateMatchId ~= "" and stateRevision >= recentMatchRevision then
					recentMatchId = stateMatchId
					recentArenaId = stateArenaId
					recentMatchRevision = stateRevision
				end
				local wasGameplayActive = ui:IsGameplayActive()
				ui:ApplyState(payload, false, allowMatchState)
				if wasGameplayActive and not ui:IsGameplayActive() then
					resetTransientClientState()
				end
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
				local effectMatchId, effectArenaId, effectRevision =
					EffectScope.ReadEffectContext(payload)
				if
					not EffectScope.Matches(
						payload,
						stringAttribute("MatchId"),
						stringAttribute("ArenaId"),
						revisionAttribute(),
						recentMatchId,
						recentArenaId,
						recentMatchRevision
					)
				then
					return
				end
				if effectMatchId ~= "" and effectRevision >= recentMatchRevision then
					recentMatchId = effectMatchId
					recentArenaId = effectArenaId
					recentMatchRevision = effectRevision
				end
				if typeof(payload) == "table" then
					local kind = payload.kind or payload.Kind or payload.type or payload.Type
					if
						typeof(kind) == "string"
						and (
							string.lower(kind) == "result"
							or string.lower(kind) == "cancelled"
							or string.lower(kind) == "timeout"
						)
					then
						resetTransientClientState()
					end
				end
				ui:ApplyEffect(payload)
			end)
			if not success then
				warn("[PannaClient] Rejected malformed Effect:", message)
			end
		end)
	)

	inputController = InputController.new(actionRequest, ui)
	for _, payload in feedbackBeforeInput do
		if inputController:ApplyActionFeedback(payload) then
			ui:ApplyActionFeedback(payload)
		end
	end
	table.clear(feedbackBeforeInput)
	handleMatchContextChanged()

	local success, snapshot = pcall(function()
		return getSnapshot:InvokeServer()
	end)
	if destroyed then
		return
	end
	if success and typeof(snapshot) == "table" then
		local snapshotMatchId, snapshotArenaId, snapshotRevision =
			EffectScope.ReadStateContext(snapshot)
		local envelopeRevision = EffectScope.ReadStateRevision(snapshot)
		local knownRevision = math.max(revisionAttribute(), recentMatchRevision)
		local allowMatchState = envelopeRevision >= knownRevision
		if snapshotMatchId ~= "" and snapshotRevision >= recentMatchRevision then
			recentMatchId = snapshotMatchId
			recentArenaId = snapshotArenaId
			recentMatchRevision = snapshotRevision
		end
		local wasGameplayActive = ui:IsGameplayActive()
		ui:ApplyState(snapshot, true, allowMatchState)
		if wasGameplayActive and not ui:IsGameplayActive() then
			resetTransientClientState()
		end
	elseif not success then
		warn("[PannaClient] Initial snapshot failed:", snapshot)
		ui:ShowNotification("SYNC DELAYED", "Live updates are still connected", nil, 3.5)
	end
end)
