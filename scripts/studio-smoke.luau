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
expect(world:FindFirstChild("LobbySpawn", true) ~= nil, "LobbySpawn is missing")
expect(world:FindFirstChild("QueuePrompt", true) ~= nil, "QueuePrompt is missing")

local arenas = arenaServiceModule.new(world)
local arenaList = arenas:GetAll()
expect(#arenaList == 2, "expected exactly two MVP arenas")

for _, arena in arenaList do
	expect(arena.Model:GetAttribute("ArenaId") == arena.Id, arena.Id .. " has invalid ArenaId")
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
	arenas:ResetBall(arena)
	expect(
		(arena.Ball.Position - arena.BallSpawn.Position).Magnitude < 0.05,
		arena.Id .. " ball reset failed"
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
