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

local world = WorldBuilder.Build(Config)
local remotes = RemoteRegistry.Create(Net)
local limiter = RateLimiter.new(Config.Security.RemoteBurst, Config.Security.RemoteRefillPerSecond)
local arenas = ArenaService.new(world)
local dataService = PlayerDataService.new(Config, remotes)
local ballService = BallService.new(Config, arenas)
local matchService = MatchService.new(Config, arenas, ballService, dataService, remotes)
local queueService = QueueService.new(arenas, matchService, remotes)

matchService:SetArenaReleasedCallback(function()
	queueService:Process()
end)
matchService:SetRematchCallback(function(first: Player, second: Player)
	queueService:EnqueuePair(first, second)
end)

local function initializePlayer(player: Player)
	player:SetAttribute("InQueue", false)
	player:SetAttribute("InMatch", false)
	player:SetAttribute("MatchId", "")
	player:SetAttribute("ArenaId", "")
	player:SetAttribute("ControlsLocked", false)
	player:SetAttribute("DataLoaded", false)

	player.CharacterAdded:Connect(function(character: Model)
		matchService:HandleCharacterAdded(player, character)
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
dataService:InitPlayers()

print(string.format("[Panna] Server %s ready with %d arenas", Config.Version, #arenas:GetAll()))
