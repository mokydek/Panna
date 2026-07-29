--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

print("PANNA_MULTIPLAYER_CLIENT_BOOT args=" .. tostring(StudioTestService:GetTestArgs()))

local player = Players.LocalPlayer
local arenaId = player:GetAttribute("PannaSmokeArena")
if type(arenaId) ~= "string" or arenaId == "" then
	repeat
		player:GetAttributeChangedSignal("PannaSmokeArena"):Wait()
		arenaId = player:GetAttribute("PannaSmokeArena")
	until type(arenaId) == "string" and arenaId ~= ""
end

local district = assert(Workspace:WaitForChild("PannaDistrict", 15), "PannaDistrict missing")
local arenas = assert(district:WaitForChild("Arenas", 10), "Arenas folder missing")
local arena = assert(arenas:WaitForChild(arenaId, 10), arenaId .. " missing")
local entry = assert(arena:WaitForChild("EntryZone", 10), "EntryZone missing")
local prompt = assert(entry:WaitForChild("EntryPrompt", 10), "EntryPrompt missing")
assert(prompt:IsA("ProximityPrompt"), "room entry prompt has the wrong class")

local character =
	assert(player.Character or player.CharacterAdded:Wait(), "local character missing")
local root = assert(character:WaitForChild("HumanoidRootPart", 15), "HumanoidRootPart missing")
local deadline = os.clock() + 15
repeat
	task.wait(0.1)
until (root.Position - entry.Position).Magnitude <= prompt.MaxActivationDistance
	or os.clock() >= deadline

print(
	string.format(
		"PANNA_PROMPT_ATTEMPT player=%s arena=%s distance=%.2f enabled=%s",
		player.Name,
		arenaId,
		(root.Position - entry.Position).Magnitude,
		tostring(prompt.Enabled)
	)
)

type PendingFeedback = {
	commandId: number,
	action: string,
}

local remoteFolder =
	assert(ReplicatedStorage:WaitForChild("PannaRemotes", 15), "PannaRemotes missing")
local actionRequest =
	assert(remoteFolder:WaitForChild("ActionRequest", 10), "ActionRequest missing")
local actionFeedback =
	assert(remoteFolder:WaitForChild("ActionFeedback", 10), "ActionFeedback missing")
local smokeAck =
	assert(ReplicatedStorage:WaitForChild("PannaSmokeTestAck", 15), "PannaSmokeTestAck missing")
assert(actionRequest:IsA("RemoteEvent"), "ActionRequest has the wrong class")
assert(actionFeedback:IsA("RemoteEvent"), "ActionFeedback has the wrong class")
assert(smokeAck:IsA("RemoteEvent"), "PannaSmokeTestAck has the wrong class")

local pendingFeedback: { [number]: PendingFeedback } = {}
local nextSequence = 1_000
local lastBallCommand = 0
local lastSpamCommand = 0

local function planarUnit(value: Vector3): Vector3
	local planar = Vector3.new(value.X, 0, value.Z)
	if planar.Magnitude < 0.05 then
		return Vector3.new(0, 0, -1)
	end
	return planar.Unit
end

local function currentBall(): BasePart
	local found = arena:FindFirstChild("Ball")
	assert(found and found:IsA("BasePart"), arenaId .. " Ball missing")
	return found
end

local function passContext(): (BasePart, number, string, string, Vector3)
	local currentCharacter = assert(player.Character, "character disappeared before pass")
	local currentRoot = assert(
		currentCharacter:FindFirstChild("HumanoidRootPart"),
		"HumanoidRootPart disappeared before pass"
	)
	assert(currentRoot:IsA("BasePart"), "HumanoidRootPart has the wrong class")
	local humanoid = assert(
		currentCharacter:FindFirstChildOfClass("Humanoid"),
		"Humanoid disappeared before pass"
	)
	local ball = currentBall()
	local revision = ball:GetAttribute("BallRevision")
	local matchId = player:GetAttribute("MatchId")
	local currentArenaId = player:GetAttribute("ArenaId")
	assert(type(revision) == "number", "BallRevision missing before pass")
	assert(type(matchId) == "string" and matchId ~= "", "MatchId missing before pass")
	assert(currentArenaId == arenaId, "ArenaId changed before pass")
	local moveDirection = humanoid.MoveDirection
	if moveDirection.Magnitude > 1 then
		moveDirection = moveDirection.Unit
	end
	return currentRoot,
		revision,
		matchId,
		currentArenaId,
		Vector3.new(moveDirection.X, 0, moveDirection.Z)
end

local function sendPassRelease(commandId: number)
	local currentRoot, revision, matchId, currentArenaId, moveDirection = passContext()
	nextSequence += 1
	local sequence = nextSequence
	pendingFeedback[sequence] = {
		commandId = commandId,
		action = "Pass",
	}
	actionRequest:FireServer({
		action = "Pass",
		sequence = sequence,
		arenaId = currentArenaId,
		matchId = matchId,
		ballRevision = revision,
		clientTime = Workspace:GetServerTimeNow(),
		direction = planarUnit(currentRoot.CFrame.LookVector),
		moveDirection = moveDirection,
		power = 0.55,
	})
end

local function sendPass(commandId: number)
	local currentRoot, revision, matchId, currentArenaId, moveDirection = passContext()
	nextSequence += 1
	local sequence = nextSequence
	pendingFeedback[sequence] = {
		commandId = commandId,
		action = "ChargeStart",
	}
	actionRequest:FireServer({
		action = "ChargeStart",
		chargeAction = "Pass",
		sequence = sequence,
		arenaId = currentArenaId,
		matchId = matchId,
		ballRevision = revision,
		clientTime = Workspace:GetServerTimeNow(),
		direction = planarUnit(currentRoot.CFrame.LookVector),
		moveDirection = moveDirection,
	})
end

local function sendMalformedSpam(commandId: number)
	local ball = currentBall()
	local revision = ball:GetAttribute("BallRevision")
	local matchId = player:GetAttribute("MatchId")
	for index = 1, 72 do
		nextSequence += 1
		local variant = index % 6
		if variant == 0 then
			actionRequest:FireServer("malformed")
		elseif variant == 1 then
			actionRequest:FireServer({ action = "Pass" })
		elseif variant == 2 then
			actionRequest:FireServer({
				action = "Pass",
				sequence = "invalid",
				arenaId = arenaId,
				matchId = matchId,
				ballRevision = revision,
				direction = Vector3.new(0, 0, -1),
			})
		elseif variant == 3 then
			actionRequest:FireServer({
				action = "Pass",
				sequence = nextSequence,
				arenaId = "Arena_999",
				matchId = "wrong-match",
				ballRevision = -1,
				clientTime = Workspace:GetServerTimeNow(),
				direction = Vector3.new(0, 0, -1),
				moveDirection = Vector3.zero,
				power = 4,
			})
		elseif variant == 4 then
			actionRequest:FireServer({
				action = "Pass",
				sequence = nextSequence,
				arenaId = arenaId,
				matchId = matchId,
				ballRevision = revision,
				clientTime = Workspace:GetServerTimeNow(),
				direction = "not-a-vector",
				moveDirection = Vector3.zero,
				power = 0.5,
			})
		else
			actionRequest:FireServer({
				action = "UnknownAction",
				sequence = nextSequence,
				arenaId = arenaId,
				matchId = matchId,
				ballRevision = revision,
				clientTime = Workspace:GetServerTimeNow(),
				direction = Vector3.new(10_000, 0, 0),
				moveDirection = Vector3.zero,
			})
		end
		if index % 12 == 0 then
			task.wait()
		end
	end
	task.wait(0.5)
	smokeAck:FireServer({
		kind = "SpamComplete",
		commandId = commandId,
		requests = 72,
	})
end

actionFeedback.OnClientEvent:Connect(function(feedback: any)
	if type(feedback) ~= "table" or type(feedback.sequence) ~= "number" then
		return
	end
	local pending = pendingFeedback[feedback.sequence]
	if not pending then
		return
	end
	pendingFeedback[feedback.sequence] = nil
	assert(feedback.action == pending.action, "feedback action does not match request")
	assert(
		feedback.accepted == true,
		pending.action .. " feedback was not accepted: " .. tostring(feedback.reason)
	)
	assert(feedback.executed == true, pending.action .. " feedback was accepted but not executed")
	assert(type(feedback.revision) == "number", "accepted feedback revision missing")
	if pending.action == "ChargeStart" then
		sendPassRelease(pending.commandId)
		return
	end
	player:SetAttribute("PannaSmokeAcceptedFeedback", true)
	player:SetAttribute("PannaSmokeAcceptedSequence", feedback.sequence)
	smokeAck:FireServer({
		kind = "Feedback",
		commandId = pending.commandId,
		action = feedback.action,
		sequence = feedback.sequence,
		accepted = feedback.accepted,
		executed = feedback.executed,
		reason = feedback.reason,
		revision = feedback.revision,
	})
end)

player:GetAttributeChangedSignal("PannaSmokeBallCommand"):Connect(function()
	local commandId = player:GetAttribute("PannaSmokeBallCommand")
	if type(commandId) == "number" and commandId > lastBallCommand then
		lastBallCommand = commandId
		sendPass(commandId)
	end
end)

player:GetAttributeChangedSignal("PannaSmokeSpamCommand"):Connect(function()
	local commandId = player:GetAttribute("PannaSmokeSpamCommand")
	if type(commandId) == "number" and commandId > lastSpamCommand then
		lastSpamCommand = commandId
		sendMalformedSpam(commandId)
	end
end)

smokeAck:FireServer({ kind = "Ready" })
print(string.format("PANNA_BALL_CLIENT_READY player=%s arena=%s", player.Name, arenaId))
local virtualInput = UserInputService:CreateVirtualInput()
for attempt = 1, 4 do
	prompt:InputHoldBegin()
	task.wait(math.max(0.35, prompt.HoldDuration + 0.2))
	prompt:InputHoldEnd()
	task.wait(0.5)
	if
		player:GetAttribute("InRoomWaiting") ~= true
		and player:GetAttribute("InMatch") ~= true
		and virtualInput
	then
		local keyCode = prompt.KeyboardKeyCode
		virtualInput:SendKey(true, keyCode, false)
		task.wait(math.max(0.35, prompt.HoldDuration + 0.2))
		virtualInput:SendKey(false, keyCode, false)
		task.wait(0.75)
	end
	if player:GetAttribute("InRoomWaiting") == true or player:GetAttribute("InMatch") == true then
		break
	end
	print(string.format("PANNA_PROMPT_RETRY player=%s attempt=%d", player.Name, attempt))
end
print(
	string.format(
		"PANNA_PROMPT_RESULT player=%s waiting=%s match=%s selected=%s",
		player.Name,
		tostring(player:GetAttribute("InRoomWaiting")),
		tostring(player:GetAttribute("InMatch")),
		tostring(player:GetAttribute("SelectedArenaId"))
	)
)
