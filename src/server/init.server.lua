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
local queueService = QueueService.new(Config, arenas, matchService, remotes)
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
		return
	end
	ballService:HandleAction(player, payload)
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
