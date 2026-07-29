--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local StudioTestService = game:GetService("StudioTestService")
local Workspace = game:GetService("Workspace")

print("PANNA_MULTIPLAYER_SERVER_BOOT args=" .. tostring(StudioTestService:GetTestArgs()))

local shared = assert(ReplicatedStorage:WaitForChild("PannaShared", 15), "PannaShared missing")
local configModule = assert(shared:WaitForChild("Config", 10), "Config missing")
local Config = require(configModule)

local existingSmokeAck = ReplicatedStorage:FindFirstChild("PannaSmokeTestAck")
assert(existingSmokeAck == nil, "PannaSmokeTestAck already exists")
local smokeAck = Instance.new("RemoteEvent")
smokeAck.Name = "PannaSmokeTestAck"
smokeAck.Parent = ReplicatedStorage

local readyClients: { [Player]: boolean } = {}
local feedbackAcks: { [Player]: any } = {}
local spamAcks: { [Player]: any } = {}
local ackFailure: string? = nil

smokeAck.OnServerEvent:Connect(function(player: Player, payload: any)
	if type(payload) ~= "table" or type(payload.kind) ~= "string" then
		ackFailure = player.Name .. " sent malformed smoke acknowledgement"
		return
	end
	if payload.kind == "Ready" then
		readyClients[player] = true
	elseif payload.kind == "Feedback" then
		feedbackAcks[player] = payload
	elseif payload.kind == "SpamComplete" then
		spamAcks[player] = payload
	else
		ackFailure = player.Name .. " sent unknown smoke acknowledgement"
	end
end)

local function waitUntil(timeoutSeconds: number, predicate: () -> boolean): boolean
	local deadline = os.clock() + timeoutSeconds
	repeat
		local ok, result = pcall(predicate)
		if ok and result then
			return true
		end
		task.wait(0.1)
	until os.clock() >= deadline
	return false
end

local function finish(value: string)
	print("PANNA_MULTIPLAYER_END " .. value)
	StudioTestService:EndTest(value)
end

local function getRoot(player: Player): BasePart
	local character = assert(player.Character, player.Name .. " character missing")
	local root = assert(
		character:FindFirstChild("HumanoidRootPart"),
		player.Name .. " HumanoidRootPart missing"
	)
	assert(root:IsA("BasePart"), player.Name .. " HumanoidRootPart has the wrong class")
	return root
end

local function getBall(arena: Instance): BasePart
	local ball = assert(arena:FindFirstChild("Ball"), arena.Name .. " Ball missing")
	assert(ball:IsA("BasePart"), arena.Name .. " Ball has the wrong class")
	return ball
end

local function getBallSpawn(arena: Instance): BasePart
	local spawn = assert(arena:FindFirstChild("BallSpawn"), arena.Name .. " BallSpawn missing")
	assert(spawn:IsA("BasePart"), arena.Name .. " BallSpawn has the wrong class")
	return spawn
end

local function configuredMaxSpeed(): number
	local ballConfig = Config.Ball
	local nested = ballConfig.Limits
	local nestedValue = if type(nested) == "table"
		then nested.MaximumSpeed or nested.MaxSpeed
		else nil
	local value = nestedValue or ballConfig.MaxSpeed
	assert(type(value) == "number" and value > 0, "Config Ball MaxSpeed missing")
	return value
end

local function placeBallForController(arena: Instance, player: Player): BasePart
	local ball = getBall(arena)
	local ballSpawn = getBallSpawn(arena)
	local root = getRoot(player)
	local look = Vector3.new(root.CFrame.LookVector.X, 0, root.CFrame.LookVector.Z)
	if look.Magnitude < 0.05 then
		look = Vector3.new(0, 0, -1)
	else
		look = look.Unit
	end
	local horizontalTarget = root.Position + look * 2.8
	ball.AssemblyLinearVelocity = Vector3.zero
	ball.AssemblyAngularVelocity = Vector3.zero
	ball.CFrame = CFrame.new(horizontalTarget.X, ballSpawn.Position.Y, horizontalTarget.Z)
	return ball
end

local ok, failure = xpcall(function()
	assert(
		waitUntil(25, function()
			return Workspace:GetAttribute("PannaServerReady") == true
		end),
		"server readiness marker timed out"
	)
	assert(
		waitUntil(60, function()
			return #Players:GetPlayers() == 4
		end),
		"four clients did not connect"
	)
	local playersReady = waitUntil(45, function()
		local players = Players:GetPlayers()
		for _, player in players do
			if player:GetAttribute("DataLoaded") ~= true or not player.Character then
				return false
			end
			local humanoid = player.Character:FindFirstChildOfClass("Humanoid")
			local root = player.Character:FindFirstChild("HumanoidRootPart")
			if not humanoid or humanoid.Health <= 0 or not root then
				return false
			end
		end
		return true
	end)
	if not playersReady then
		for _, player in Players:GetPlayers() do
			local character = player.Character
			local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
			local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
			print(
				string.format(
					"PANNA_READY_DIAG name=%s userId=%d data=%s character=%s root=%s humanoid=%s health=%s",
					player.Name,
					player.UserId,
					tostring(player:GetAttribute("DataLoaded")),
					tostring(character ~= nil),
					tostring(root ~= nil),
					tostring(humanoid ~= nil),
					tostring(if humanoid then humanoid.Health else nil)
				)
			)
		end
	end
	assert(playersReady, "four ready players timed out")

	local district = assert(Workspace:FindFirstChild("PannaDistrict"), "PannaDistrict missing")
	local arenas = assert(district:FindFirstChild("Arenas"), "Arenas folder missing")
	local arenaOne = assert(arenas:FindFirstChild("Arena_1"), "Arena_1 missing")
	local arenaTwo = assert(arenas:FindFirstChild("Arena_2"), "Arena_2 missing")
	local entryOne =
		assert(arenaOne:FindFirstChild("EntryZone"), "Arena_1 EntryZone missing") :: BasePart
	local entryTwo =
		assert(arenaTwo:FindFirstChild("EntryZone"), "Arena_2 EntryZone missing") :: BasePart

	local players = Players:GetPlayers()
	table.sort(players, function(first: Player, second: Player): boolean
		return first.UserId < second.UserId
	end)
	for index, player in players do
		local arenaId = if index <= 2 then "Arena_1" else "Arena_2"
		local entry = if index <= 2 then entryOne else entryTwo
		assert(player.Character, player.Name .. " character disappeared")
		player.Character:PivotTo(entry.CFrame + Vector3.new(0, 3.5, 0))
		player:SetAttribute("PannaSmokeArena", arenaId)
	end

	local roomsActive = waitUntil(30, function()
		local stateOne = arenaOne:GetAttribute("ArenaState")
		local stateTwo = arenaTwo:GetAttribute("ArenaState")
		local activeOne = stateOne == "Countdown" or stateOne == "Active"
		local activeTwo = stateTwo == "Countdown" or stateTwo == "Active"
		return activeOne and activeTwo
	end)
	if not roomsActive then
		print(
			string.format(
				"PANNA_ROOM_DIAG arena1=%s occupants1=%s waiting1=%s arena2=%s occupants2=%s waiting2=%s",
				tostring(arenaOne:GetAttribute("ArenaState")),
				tostring(arenaOne:GetAttribute("Occupants")),
				tostring(arenaOne:GetAttribute("WaitingCount")),
				tostring(arenaTwo:GetAttribute("ArenaState")),
				tostring(arenaTwo:GetAttribute("Occupants")),
				tostring(arenaTwo:GetAttribute("WaitingCount"))
			)
		)
		for _, player in players do
			print(
				string.format(
					"PANNA_ROOM_PLAYER name=%s target=%s waiting=%s match=%s selected=%s arena=%s",
					player.Name,
					tostring(player:GetAttribute("PannaSmokeArena")),
					tostring(player:GetAttribute("InRoomWaiting")),
					tostring(player:GetAttribute("InMatch")),
					tostring(player:GetAttribute("SelectedArenaId")),
					tostring(player:GetAttribute("ArenaId"))
				)
			)
		end
	end
	assert(roomsActive, "two physical rooms did not enter Countdown/Active")

	local firstMatchId = arenaOne:GetAttribute("MatchId")
	local secondMatchId = arenaTwo:GetAttribute("MatchId")
	assert(type(firstMatchId) == "string" and firstMatchId ~= "", "Arena_1 MatchId missing")
	assert(type(secondMatchId) == "string" and secondMatchId ~= "", "Arena_2 MatchId missing")
	assert(firstMatchId ~= secondMatchId, "simultaneous rooms share a MatchId")
	for _, player in players do
		assert(player:GetAttribute("InMatch") == true, player.Name .. " was not placed in a match")
		assert(
			player:GetAttribute("ArenaId") == player:GetAttribute("PannaSmokeArena"),
			player.Name .. " entered the wrong arena"
		)
	end

	local barrierOne =
		assert(arenaOne:FindFirstChild("Barrier"), "Arena_1 Barrier missing") :: BasePart
	local barrierTwo =
		assert(arenaTwo:FindFirstChild("Barrier"), "Arena_2 Barrier missing") :: BasePart
	assert(barrierOne.CanCollide and barrierTwo.CanCollide, "active room barriers are not closed")

	assert(
		waitUntil(20, function()
			return arenaOne:GetAttribute("ArenaState") == "Active"
				and arenaTwo:GetAttribute("ArenaState") == "Active"
		end),
		"two physical rooms did not reach Active"
	)
	assert(
		waitUntil(15, function()
			if ackFailure then
				return true
			end
			for _, player in players do
				if readyClients[player] ~= true then
					return false
				end
			end
			return true
		end),
		"ball smoke clients did not become ready"
	)
	assert(ackFailure == nil, ackFailure)

	local arenaPlayers: { [string]: { Player } } = {
		Arena_1 = {},
		Arena_2 = {},
	}
	for _, player in players do
		local currentArenaId = player:GetAttribute("ArenaId")
		assert(type(currentArenaId) == "string", player.Name .. " ArenaId missing")
		local assigned = arenaPlayers[currentArenaId]
		assert(assigned ~= nil, player.Name .. " entered an unexpected arena")
		table.insert(assigned, player)
	end
	assert(#arenaPlayers.Arena_1 == 2, "Arena_1 does not have two players")
	assert(#arenaPlayers.Arena_2 == 2, "Arena_2 does not have two players")
	table.sort(arenaPlayers.Arena_1, function(first: Player, second: Player): boolean
		return first.UserId < second.UserId
	end)
	table.sort(arenaPlayers.Arena_2, function(first: Player, second: Player): boolean
		return first.UserId < second.UserId
	end)
	local controllerOne = arenaPlayers.Arena_1[1]
	local controllerTwo = arenaPlayers.Arena_2[1]
	assert(controllerOne ~= controllerTwo, "two rooms selected the same controller")

	task.wait(0.6)
	local ballOne = placeBallForController(arenaOne, controllerOne)
	local ballTwo = placeBallForController(arenaTwo, controllerTwo)
	assert(
		waitUntil(8, function()
			return ballOne:GetAttribute("OwnerUserId") == controllerOne.UserId
				and ballTwo:GetAttribute("OwnerUserId") == controllerTwo.UserId
				and ballOne:GetAttribute("BallState") == "Controlled"
				and ballTwo:GetAttribute("BallState") == "Controlled"
		end),
		"two rooms did not acquire unique ball ownership"
	)
	assert(ballOne:GetNetworkOwner() == nil, "Arena_1 ball stopped being server-owned")
	assert(ballTwo:GetNetworkOwner() == nil, "Arena_2 ball stopped being server-owned")
	assert(ballOne:GetAttribute("ArenaId") == "Arena_1", "Arena_1 ball identity changed")
	assert(ballTwo:GetAttribute("ArenaId") == "Arena_2", "Arena_2 ball identity changed")
	assert(ballOne:GetAttribute("MatchId") == firstMatchId, "Arena_1 ball MatchId changed")
	assert(ballTwo:GetAttribute("MatchId") == secondMatchId, "Arena_2 ball MatchId changed")

	local revisionBeforeOne = ballOne:GetAttribute("BallRevision")
	local revisionBeforeTwo = ballTwo:GetAttribute("BallRevision")
	assert(type(revisionBeforeOne) == "number", "Arena_1 BallRevision missing")
	assert(type(revisionBeforeTwo) == "number", "Arena_2 BallRevision missing")
	local commandId = 1
	controllerOne:SetAttribute("PannaSmokeBallCommand", commandId)
	controllerTwo:SetAttribute("PannaSmokeBallCommand", commandId)

	assert(
		waitUntil(8, function()
			if ackFailure then
				return true
			end
			local first = feedbackAcks[controllerOne]
			local second = feedbackAcks[controllerTwo]
			return first ~= nil
				and second ~= nil
				and first.commandId == commandId
				and second.commandId == commandId
		end),
		"two clients did not acknowledge Pass feedback"
	)
	assert(ackFailure == nil, ackFailure)
	local feedbackOne = feedbackAcks[controllerOne]
	local feedbackTwo = feedbackAcks[controllerTwo]
	for _, feedback in { feedbackOne, feedbackTwo } do
		assert(feedback.action == "Pass", "unexpected accepted feedback action")
		assert(feedback.accepted == true, "Pass feedback was not accepted")
		assert(feedback.executed == true, "Pass feedback was not executed")
		assert(type(feedback.sequence) == "number", "Pass feedback sequence missing")
		assert(type(feedback.revision) == "number", "Pass feedback revision missing")
	end

	local observedSpeedOne = 0
	local observedSpeedTwo = 0
	assert(
		waitUntil(5, function()
			observedSpeedOne = math.max(observedSpeedOne, ballOne.AssemblyLinearVelocity.Magnitude)
			observedSpeedTwo = math.max(observedSpeedTwo, ballTwo.AssemblyLinearVelocity.Magnitude)
			local revisionOne = ballOne:GetAttribute("BallRevision")
			local revisionTwo = ballTwo:GetAttribute("BallRevision")
			return ballOne:GetAttribute("LastAction") == "Pass"
				and ballTwo:GetAttribute("LastAction") == "Pass"
				and type(revisionOne) == "number"
				and type(revisionTwo) == "number"
				and revisionOne > revisionBeforeOne
				and revisionTwo > revisionBeforeTwo
				and observedSpeedOne > 1
				and observedSpeedTwo > 1
		end),
		"two isolated Pass actions were not observed"
	)
	local revisionAfterOne = ballOne:GetAttribute("BallRevision")
	local revisionAfterTwo = ballTwo:GetAttribute("BallRevision")
	assert(
		type(revisionAfterOne) == "number" and revisionAfterOne > revisionBeforeOne,
		"Arena_1 BallRevision did not advance"
	)
	assert(
		type(revisionAfterTwo) == "number" and revisionAfterTwo > revisionBeforeTwo,
		"Arena_2 BallRevision did not advance"
	)
	assert(feedbackOne.revision > revisionBeforeOne, "Arena_1 feedback revision did not advance")
	assert(feedbackTwo.revision > revisionBeforeTwo, "Arena_2 feedback revision did not advance")
	assert(
		ballOne:GetAttribute("LastTouchUserId") == controllerOne.UserId,
		"Arena_1 Pass was attributed to another room"
	)
	assert(
		ballTwo:GetAttribute("LastTouchUserId") == controllerTwo.UserId,
		"Arena_2 Pass was attributed to another room"
	)
	assert(arenaOne:GetAttribute("MatchId") == firstMatchId, "Arena_1 match changed after Pass")
	assert(arenaTwo:GetAttribute("MatchId") == secondMatchId, "Arena_2 match changed after Pass")

	local maxSpeed = configuredMaxSpeed()
	assert(observedSpeedOne <= maxSpeed + 0.75, "Arena_1 Pass exceeded MaxSpeed")
	assert(observedSpeedTwo <= maxSpeed + 0.75, "Arena_2 Pass exceeded MaxSpeed")
	local spamCommandId = 2
	controllerOne:SetAttribute("PannaSmokeSpamCommand", spamCommandId)
	controllerTwo:SetAttribute("PannaSmokeSpamCommand", spamCommandId)
	local spamDeadline = os.clock() + 8
	repeat
		assert(
			ballOne.AssemblyLinearVelocity.Magnitude <= maxSpeed + 0.75,
			"Arena_1 spam exceeded MaxSpeed"
		)
		assert(
			ballTwo.AssemblyLinearVelocity.Magnitude <= maxSpeed + 0.75,
			"Arena_2 spam exceeded MaxSpeed"
		)
		if spamAcks[controllerOne] and spamAcks[controllerTwo] then
			break
		end
		task.wait(0.05)
	until os.clock() >= spamDeadline
	assert(spamAcks[controllerOne] ~= nil, "Arena_1 client did not finish malformed spam")
	assert(spamAcks[controllerTwo] ~= nil, "Arena_2 client did not finish malformed spam")
	assert(
		spamAcks[controllerOne].commandId == spamCommandId,
		"Arena_1 spam command acknowledgement mismatched"
	)
	assert(
		spamAcks[controllerTwo].commandId == spamCommandId,
		"Arena_2 spam command acknowledgement mismatched"
	)
	assert(spamAcks[controllerOne].requests == 72, "Arena_1 spam request count mismatched")
	assert(spamAcks[controllerTwo].requests == 72, "Arena_2 spam request count mismatched")
	assert(ackFailure == nil, ackFailure)
	for _ = 1, 20 do
		assert(
			ballOne.AssemblyLinearVelocity.Magnitude <= maxSpeed + 0.75,
			"Arena_1 post-spam speed cap failed"
		)
		assert(
			ballTwo.AssemblyLinearVelocity.Magnitude <= maxSpeed + 0.75,
			"Arena_2 post-spam speed cap failed"
		)
		task.wait(0.05)
	end
	assert(Workspace:GetAttribute("PannaServerReady") == true, "server lost its readiness marker")
	assert(arenaOne:GetAttribute("MatchId") == firstMatchId, "Arena_1 isolation failed during spam")
	assert(
		arenaTwo:GetAttribute("MatchId") == secondMatchId,
		"Arena_2 isolation failed during spam"
	)

	finish(
		string.format(
			"PANNA_MULTIPLAYER_SMOKE_OK clients=4 arenas=2 matches=2 passes=2 spam=%d revisions=%d/%d",
			spamAcks[controllerOne].requests + spamAcks[controllerTwo].requests,
			revisionAfterOne,
			revisionAfterTwo
		)
	)
end, debug.traceback)

if not ok then
	finish("PANNA_MULTIPLAYER_SMOKE_FAIL " .. tostring(failure))
end
