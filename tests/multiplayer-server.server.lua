--!strict

local Players = game:GetService("Players")
local StudioTestService = game:GetService("StudioTestService")
local Workspace = game:GetService("Workspace")

print("PANNA_MULTIPLAYER_SERVER_BOOT args=" .. tostring(StudioTestService:GetTestArgs()))

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

	finish("PANNA_MULTIPLAYER_SMOKE_OK clients=4 arenas=2 matches=2")
end, debug.traceback)

if not ok then
	finish("PANNA_MULTIPLAYER_SMOKE_FAIL " .. tostring(failure))
end
