--!strict

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local shared = ReplicatedStorage:WaitForChild("PannaShared")
local Config = require(shared:WaitForChild("Config"))
local Net = require(shared:WaitForChild("Net"))

local WorldBuilder = require(script:WaitForChild("WorldBuilder"))
local RemoteRegistry = require(script:WaitForChild("RemoteRegistry"))
local RateLimiter = require(script:WaitForChild("RateLimiter"))
local ArenaService = require(script:WaitForChild("ArenaService"))
local PlayerDataService = require(script:WaitForChild("PlayerDataService"))
local BallService = require(script:WaitForChild("BallService"))
local MatchService = require(script:WaitForChild("MatchService"))
local QueueService = require(script:WaitForChild("QueueService"))
local RoomService = require(script:WaitForChild("RoomService"))

local world = WorldBuilder.Build(Config)
local remotes = RemoteRegistry.Create(Net)
local limiter = RateLimiter.new(Config.Security.RemoteBurst, Config.Security.RemoteRefillPerSecond)
local arenas = ArenaService.new(world, Config)
local dataService = PlayerDataService.new(Config, remotes)
local ballService = BallService.new(Config, arenas)
local matchService = MatchService.new(Config, arenas, ballService, dataService, remotes)
local queueService = QueueService.new(arenas, matchService, remotes)
local roomService = RoomService.new(Config, arenas, matchService, queueService, remotes)

matchService:SetArenaReleasedCallback(function(_arena: any, home: Player, away: Player)
	queueService:Refresh(home)
	queueService:Refresh(away)
	queueService:Process()
end)
matchService:SetRematchCallback(function(first: Player, second: Player, arena: any)
	if not roomService:StartRematch(first, second, arena) then
		queueService:EnqueuePair(first, second)
	end
end)

local initializedPlayers: { [Player]: boolean } = {}

local function requestString(payload: any, key: string): string
	if typeof(payload) == "table" and typeof(payload[key]) == "string" then
		return payload[key]
	end
	return ""
end

local function requestNumber(payload: any, key: string): number
	if typeof(payload) == "table" and typeof(payload[key]) == "number" then
		local value = payload[key]
		if value == value and value > -1e9 and value < 1e9 then
			return value
		end
	end
	return 0
end

local function requestMode(payload: any): string
	for _, key in { "shotType", "variant", "chargeAction" } do
		local value = requestString(payload, key)
		if value ~= "" then
			return value
		end
	end
	return ""
end

local function sendActionFeedback(player: Player, payload: any, result: any)
	local resultTable = if typeof(result) == "table" then result else nil
	local accepted = if resultTable then resultTable.accepted == true else result == true
	local executed = if resultTable then resultTable.executed == true else accepted
	local reason = if resultTable and typeof(resultTable.reason) == "string"
		then resultTable.reason
		else if accepted then "Accepted" else "Rejected"
	local action = if resultTable and typeof(resultTable.action) == "string"
		then resultTable.action
		else requestString(payload, "action")
	local sequence = if resultTable and typeof(resultTable.sequence) == "number"
		then resultTable.sequence
		else requestNumber(payload, "sequence")
	local cooldownSeconds = if resultTable
			and typeof(resultTable.cooldownSeconds) == "number"
		then math.max(0, resultTable.cooldownSeconds)
		else 0
	local revision = if resultTable and typeof(resultTable.revision) == "number"
		then math.max(0, resultTable.revision)
		else requestNumber(payload, "ballRevision")
	local controllerUserId = if resultTable
			and typeof(resultTable.controllerUserId) == "number"
		then resultTable.controllerUserId
		else 0
	local mode = requestMode(payload)
	local ballState = if resultTable and typeof(resultTable.mode) == "string"
		then resultTable.mode
		else ""

	remotes.ActionFeedback:FireClient(player, {
		accepted = accepted,
		executed = executed,
		reason = reason,
		action = action,
		sequence = sequence,
		cooldownSeconds = cooldownSeconds,
		revision = revision,
		controllerUserId = controllerUserId,
		mode = mode,
		ballState = ballState,
	})
end

local function initializePlayer(player: Player)
	if initializedPlayers[player] then
		return
	end
	initializedPlayers[player] = true
	player:SetAttribute("InQueue", false)
	player:SetAttribute("InRoomWaiting", false)
	player:SetAttribute("InMatch", false)
	player:SetAttribute("MatchId", "")
	player:SetAttribute("ArenaId", "")
	player:SetAttribute("MatchRevision", 0)
	player:SetAttribute("SelectedArenaId", "")
	player:SetAttribute("ControlsLocked", false)
	player:SetAttribute("DataLoaded", false)
	task.spawn(function()
		dataService:LoadPlayer(player)
	end)

	player.CharacterAdded:Connect(function(character: Model)
		matchService:HandleCharacterAdded(player, character)
		roomService:HandleCharacterAdded(player, character)
	end)
end

Players.PlayerAdded:Connect(initializePlayer)
for _, player in Players:GetPlayers() do
	initializePlayer(player)
end

remotes.ActionRequest.OnServerEvent:Connect(function(player: Player, payload: any)
	if not limiter:Allow(player, "Action", 1) then
		sendActionFeedback(player, payload, {
			accepted = false,
			executed = false,
			reason = "RateLimited",
		})
		return
	end
	local result = ballService:HandleAction(player, payload)
	sendActionFeedback(player, payload, result)
end)

remotes.QueueRequest.OnServerEvent:Connect(function(player: Player, request: any)
	if type(request) ~= "string" or not limiter:Allow(player, "Queue", 2) then
		return
	end
	if request == "Join" then
		queueService:Join(player)
	elseif request == "Leave" then
		queueService:Leave(player)
	elseif request == "Rematch" then
		matchService:RequestRematch(player)
	elseif request == "Exit" then
		roomService:Exit(player)
	end
end)

remotes.GetSnapshot.OnServerInvoke = function(player: Player): { [string]: any }
	if not limiter:Allow(player, "Snapshot", 3) then
		return {}
	end
	return {
		version = Config.Version,
		queue = queueService:GetSnapshot(player),
		match = matchService:GetSnapshot(player),
		matchRevision = player:GetAttribute("MatchRevision") or 0,
		stats = dataService:GetPublicStats(player),
		serverNow = workspace:GetServerTimeNow(),
	}
end

local queuePrompt = world:FindFirstChild("QueuePrompt", true)
if queuePrompt and queuePrompt:IsA("ProximityPrompt") then
	queuePrompt.Triggered:Connect(function(player: Player)
		if limiter:Allow(player, "QueuePrompt", 2) then
			queueService:Toggle(player)
		end
	end)
else
	warn("[Panna] QueuePrompt was not created; UI matchmaking remains available")
end

Players.PlayerRemoving:Connect(function(player: Player)
	initializedPlayers[player] = nil
	roomService:HandlePlayerRemoving(player)
	queueService:HandlePlayerRemoving(player)
	matchService:HandlePlayerRemoving(player)
	ballService:RemovePlayer(player)
	limiter:RemovePlayer(player)
	dataService:RemovePlayer(player)
end)

game:BindToClose(function()
	dataService:Shutdown()
end)

ballService:Start()
roomService:Start()
dataService:InitPlayers()
workspace:SetAttribute("PannaServerReady", true)

print(string.format("[Panna] Server %s ready with %d arenas", Config.Version, #arenas:GetAll()))
