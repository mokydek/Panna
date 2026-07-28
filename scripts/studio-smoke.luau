local ServerScriptService = game:GetService("ServerScriptService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local function expect(condition, message)
	if not condition then
		error("SMOKE CHECK FAILED: " .. message, 2)
	end
end

local serverRoot = ServerScriptService:FindFirstChild("PannaServer")
local sharedRoot = ReplicatedStorage:FindFirstChild("PannaShared")
expect(serverRoot ~= nil, "PannaServer was not mapped by Rojo")
expect(sharedRoot ~= nil, "PannaShared was not mapped by Rojo")

local config = require(sharedRoot:FindFirstChild("Config"))
local net = require(sharedRoot:FindFirstChild("Net"))
local worldBuilder = require(serverRoot:FindFirstChild("WorldBuilder"))
local arenaServiceModule = require(serverRoot:FindFirstChild("ArenaService"))
local ballServiceModule = require(serverRoot:FindFirstChild("BallService"))
local remoteRegistry = require(serverRoot:FindFirstChild("RemoteRegistry"))

for _, moduleName in
	{
		"RateLimiter",
		"PlayerDataService",
		"PannaDetector",
		"BallService",
		"MatchService",
		"QueueService",
		"RoomService",
	}
do
	local module = serverRoot:FindFirstChild(moduleName)
	expect(module ~= nil, moduleName .. " was not mapped by Rojo")
	local ok, result = pcall(require, module)
	expect(ok, moduleName .. " failed to load: " .. tostring(result))
	expect(type(result) == "table", moduleName .. " must return a module table")
end

local typesModule = sharedRoot:FindFirstChild("Types")
expect(typesModule ~= nil and type(require(typesModule)) == "table", "Types module failed to load")

local world = worldBuilder.Build(config)
expect(world.Name == config.World.RootName, "world root name does not match config")
expect(world.Name == "PannaDistrict", "district root must be named PannaDistrict")
expect(world:GetAttribute("ArenaCount") == 6, "district must declare six arenas")
expect(world:GetAttribute("DistrictName") == "PannaDistrict", "district identity is missing")
local lobbySpawn = world:FindFirstChild("LobbySpawn", true)
expect(lobbySpawn ~= nil and lobbySpawn:IsA("BasePart"), "LobbySpawn is missing")
expect(world:FindFirstChild("QueuePrompt", true) ~= nil, "QueuePrompt is missing")

local environment = world:FindFirstChild("DistrictEnvironment")
expect(environment ~= nil and environment:IsA("Model"), "DistrictEnvironment is missing")
expect(
	environment:GetAttribute("ExternalAssetCount") == 0,
	"district must use zero external assets"
)
local centralStreet = environment:FindFirstChild("CentralStreet")
expect(centralStreet ~= nil and centralStreet:IsA("Model"), "CentralStreet is missing")
expect(centralStreet:GetAttribute("Continuous") == true, "CentralStreet must be continuous")
local streetSurface = centralStreet:FindFirstChild("StreetSurface")
expect(streetSurface ~= nil and streetSurface:IsA("BasePart"), "StreetSurface is missing")
local streetStart = streetSurface.Position.Z - streetSurface.Size.Z * 0.5
local streetEnd = streetSurface.Position.Z + streetSurface.Size.Z * 0.5
expect(
	lobbySpawn.Position.Z >= streetStart and lobbySpawn.Position.Z <= streetEnd,
	"CentralStreet must include LobbySpawn"
)

for _, facilityName in
	{
		"TrainingZone",
		"StreetShop",
		"LockerRoom",
		"TrophyCorner",
		"RestZone",
		"EndLandmark",
	}
do
	expect(world:FindFirstChild(facilityName, true) ~= nil, facilityName .. " is missing")
end

local arenas = arenaServiceModule.new(world, config)
local arenaList = arenas:GetAll()
expect(#arenaList == 6, "expected exactly six physical 1v1 rooms")

local expectedRoomTitles = {
	["Concrete Cage"] = true,
	["Neon Futsal"] = true,
	["Club House"] = true,
	Industrial = true,
	["Training Lab"] = true,
	Championship = true,
}

for _, arena in arenaList do
	expect(arena.Model:GetAttribute("ArenaId") == arena.Id, arena.Id .. " has invalid ArenaId")
	local roomTitle = arena.Model:GetAttribute("RoomTitle")
	expect(
		type(roomTitle) == "string" and expectedRoomTitles[roomTitle] == true,
		arena.Id .. " has an invalid room title"
	)
	expectedRoomTitles[roomTitle] = nil
	expect(arena.Model:GetAttribute("ArenaState") == "Free", arena.Id .. " must start Free")
	expect(arena.Model:GetAttribute("WaitingCount") == 0, arena.Id .. " has stale waiting state")
	for _, partName in
		{
			"EntryZone",
			"ExitZone",
			"Barrier",
			"HomeWaitingSpawn",
			"AwayWaitingSpawn",
			"StreetSpawn",
			"StatusBoard",
			"SpectatorZone",
		}
	do
		local contractPart = arena.Model:FindFirstChild(partName)
		expect(
			contractPart ~= nil and contractPart:IsA("BasePart"),
			arena.Id .. " is missing direct " .. partName
		)
	end
	expect(
		arena.EntryPrompt ~= nil and arena.EntryPrompt.Name == "EntryPrompt",
		arena.Id .. " EntryPrompt is missing"
	)
	expect(
		arena.ExitPrompt ~= nil and arena.ExitPrompt.Name == "ExitPrompt",
		arena.Id .. " ExitPrompt is missing"
	)
	expect(arena.EntryPrompt.Enabled, arena.Id .. " EntryPrompt must be enabled while Free")
	expect(not arena.ExitPrompt.Enabled, arena.Id .. " ExitPrompt must be disabled while Free")
	expect(not arena.Barrier.CanCollide, arena.Id .. " Barrier must be open while Free")
	expect(
		arena.Ball:IsA("BasePart") and not arena.Ball.Anchored,
		arena.Id .. " ball must be physical"
	)
	expect(
		arena.HomeGoal.CanTouch and arena.AwayGoal.CanTouch,
		arena.Id .. " goal triggers must touch"
	)
	expect(
		not arena.HomeGoal.CanCollide and not arena.AwayGoal.CanCollide,
		arena.Id .. " goals must not collide"
	)
	expect(
		arena.Bounds.Anchored and not arena.Bounds.CanCollide,
		arena.Id .. " bounds marker is invalid"
	)
	for _, goal in { arena.HomeGoal, arena.AwayGoal } do
		local apertureBottom = goal.Position.Y - goal.Size.Y * 0.5
		expect(
			math.abs(apertureBottom) < 0.05,
			arena.Id .. " goal aperture must start at court level"
		)
	end
	expect(
		arena.Model:FindFirstChild("RoomLabel", true) ~= nil
			and arena.Model:FindFirstChild("StateLabel", true) ~= nil
			and arena.Model:FindFirstChild("ScoreLabel", true) ~= nil,
		arena.Id .. " status-board labels are incomplete"
	)
	arenas:ResetBall(arena)
	expect(
		(arena.Ball.Position - arena.BallSpawn.Position).Magnitude < 0.05,
		arena.Id .. " ball reset failed"
	)
end

expect(next(expectedRoomTitles) == nil, "not all six named room themes were created")
for _, arenaPosition in config.World.ArenaPositions do
	expect(
		arenaPosition.Position.Z >= streetStart and arenaPosition.Position.Z <= streetEnd,
		"CentralStreet must continue through every room row"
	)
end

local ballService = ballServiceModule.new(config, arenas)
expect(type(ballService.states) == "table", "BallService did not create arena states")
for _, arena in arenaList do
	expect(ballService.states[arena.Id] ~= nil, arena.Id .. " BallService state is missing")
	expect(arena.Ball:GetNetworkOwner() == nil, arena.Id .. " ball must remain server-owned")
end

local remotes = remoteRegistry.Create(net)
expect(remotes.ActionRequest:IsA("RemoteEvent"), "ActionRequest remote missing")
expect(remotes.QueueRequest:IsA("RemoteEvent"), "QueueRequest remote missing")
expect(remotes.StateUpdate:IsA("RemoteEvent"), "StateUpdate remote missing")
expect(remotes.Effect:IsA("RemoteEvent"), "Effect remote missing")
expect(remotes.GetSnapshot:IsA("RemoteFunction"), "GetSnapshot remote missing")

print(string.format("PANNA_STUDIO_SMOKE_OK version=%s arenas=%d", config.Version, #arenaList))
