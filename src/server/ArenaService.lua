--!strict

export type RoomState = "Free" | "Waiting" | "Countdown" | "Active" | "Result"

local VALID_ROOM_STATES: { [string]: boolean } = table.freeze({
	Free = true,
	Waiting = true,
	Countdown = true,
	Active = true,
	Result = true,
})

local ArenaService = {}
ArenaService.__index = ArenaService

export type Arena = {
	Id: string,
	Model: Model,
	HomeSpawn: BasePart,
	AwaySpawn: BasePart,
	BallSpawn: BasePart,
	HomeGoal: BasePart,
	AwayGoal: BasePart,
	Bounds: BasePart,
	Ball: BasePart,
	EntryZone: BasePart?,
	ExitZone: BasePart?,
	Barrier: BasePart?,
	HomeWaitingSpawn: BasePart?,
	AwayWaitingSpawn: BasePart?,
	StreetSpawn: BasePart?,
	EntryPrompt: ProximityPrompt?,
	ExitPrompt: ProximityPrompt?,
	State: RoomState,
	Busy: boolean,
	MatchId: string?,
}

export type Service = typeof(setmetatable(
	{} :: {
		root: Model,
		config: any,
		arenas: { Arena },
		byId: { [string]: Arena },
		lobbySpawn: BasePart,
	},
	ArenaService
))

local function requirePart(model: Instance, name: string): BasePart
	local found = model:FindFirstChild(name)
	assert(
		found and found:IsA("BasePart"),
		string.format("Missing BasePart %s in %s", name, model:GetFullName())
	)
	return found
end

local function optionalPart(model: Instance, name: string): BasePart?
	local found = model:FindFirstChild(name)
	return if found and found:IsA("BasePart") then found else nil
end

local function optionalPrompt(zone: BasePart?, name: string): ProximityPrompt?
	if not zone then
		return nil
	end
	local named = zone:FindFirstChild(name)
	if named and named:IsA("ProximityPrompt") then
		return named
	end
	return zone:FindFirstChildOfClass("ProximityPrompt")
end

local function findTextLabel(model: Model, name: string): TextLabel?
	local found = model:FindFirstChild(name, true)
	return if found and found:IsA("TextLabel") then found else nil
end

local function displayName(arena: Arena): string
	local configured = arena.Model:GetAttribute("DisplayName")
	return if type(configured) == "string" and configured ~= ""
		then configured
		else arena.Model.Name
end

local function playerId(player: Player?): number
	return if player then player.UserId else 0
end

function ArenaService.new(root: Model, config: any): Service
	local arenasFolder = root:FindFirstChild("Arenas")
	assert(arenasFolder, string.format("WorldBuilder must create %s/Arenas", root.Name))
	local lobbySpawn = root:FindFirstChild("LobbySpawn", true)
	assert(lobbySpawn and lobbySpawn:IsA("BasePart"), "WorldBuilder must create LobbySpawn")

	local self = setmetatable({
		root = root,
		config = config,
		arenas = {},
		byId = {},
		lobbySpawn = lobbySpawn,
	}, ArenaService)

	for _, child in arenasFolder:GetChildren() do
		if child:IsA("Model") then
			local idAttribute = child:GetAttribute("ArenaId")
			local id = if type(idAttribute) == "string" then idAttribute else child.Name
			assert(self.byId[id] == nil, string.format("Duplicate arena id %s", id))
			local entryZone = optionalPart(child, "EntryZone")
			local exitZone = optionalPart(child, "ExitZone")
			local arena: Arena = {
				Id = id,
				Model = child,
				HomeSpawn = requirePart(child, "HomeSpawn"),
				AwaySpawn = requirePart(child, "AwaySpawn"),
				BallSpawn = requirePart(child, "BallSpawn"),
				HomeGoal = requirePart(child, "HomeGoal"),
				AwayGoal = requirePart(child, "AwayGoal"),
				Bounds = requirePart(child, "Bounds"),
				Ball = requirePart(child, "Ball"),
				EntryZone = entryZone,
				ExitZone = exitZone,
				Barrier = optionalPart(child, "Barrier"),
				HomeWaitingSpawn = optionalPart(child, "HomeWaitingSpawn"),
				AwayWaitingSpawn = optionalPart(child, "AwayWaitingSpawn"),
				StreetSpawn = optionalPart(child, "StreetSpawn")
					or optionalPart(child, "ReturnSpawn"),
				EntryPrompt = optionalPrompt(entryZone, "EntryPrompt"),
				ExitPrompt = optionalPrompt(exitZone, "ExitPrompt"),
				State = "Free",
				Busy = false,
				MatchId = nil,
			}
			table.insert(self.arenas, arena)
			self.byId[id] = arena
		end
	end

	table.sort(self.arenas, function(a: Arena, b: Arena): boolean
		return a.Id < b.Id
	end)
	local minimumArenaCount = if config and config.World
		then config.World.MinimumArenaCount or 1
		else 1
	assert(
		#self.arenas >= minimumArenaCount,
		string.format(
			"Expected at least %d physical arenas, found %d",
			minimumArenaCount,
			#self.arenas
		)
	)

	for _, arena in self.arenas do
		self:SetRoomState(arena, "Free", nil, nil)
		self:ResetBall(arena)
	end
	return self
end

function ArenaService.GetAll(self: Service): { Arena }
	return self.arenas
end

function ArenaService.GetById(self: Service, id: string): Arena?
	return self.byId[id]
end

function ArenaService.GetDisplayName(_self: Service, arena: Arena): string
	return displayName(arena)
end

function ArenaService.GetAvailable(self: Service): Arena?
	for _, arena in self.arenas do
		if arena.State == "Free" and arena.MatchId == nil then
			return arena
		end
	end
	return nil
end

function ArenaService.SetRoomState(
	_self: Service,
	arena: Arena,
	state: RoomState,
	home: Player?,
	away: Player?
)
	assert(VALID_ROOM_STATES[state], string.format("Invalid room state %s", state))
	arena.State = state
	arena.Busy = state ~= "Free"

	local occupants = (if home then 1 else 0) + (if away then 1 else 0)
	local waitingCount = if state == "Waiting" then occupants else 0
	arena.Model:SetAttribute("ArenaState", state)
	arena.Model:SetAttribute("Busy", arena.Busy)
	arena.Model:SetAttribute("WaitingCount", waitingCount)
	arena.Model:SetAttribute("Occupants", occupants)
	arena.Model:SetAttribute("HomeUserId", playerId(home))
	arena.Model:SetAttribute("AwayUserId", playerId(away))

	local barrierClosed = state == "Countdown" or state == "Active" or state == "Result"
	if arena.Barrier then
		arena.Barrier.CanCollide = barrierClosed
		arena.Barrier.CanTouch = barrierClosed
		arena.Barrier:SetAttribute("Closed", barrierClosed)
	end
	if arena.EntryPrompt then
		arena.EntryPrompt.Enabled = state == "Free" or state == "Waiting"
		arena.EntryPrompt.ActionText = if state == "Waiting" then "JOIN 1v1" else "ENTER ROOM"
		arena.EntryPrompt.ObjectText = displayName(arena)
	end
	if arena.ExitPrompt then
		arena.ExitPrompt.Enabled = state ~= "Free"
		arena.ExitPrompt.ObjectText = displayName(arena)
	end

	local stateLabel = findTextLabel(arena.Model, "StateLabel")
	if stateLabel then
		stateLabel.Text = string.upper(state)
	end
	local roomLabel = findTextLabel(arena.Model, "RoomLabel")
	if roomLabel then
		roomLabel.Text = displayName(arena)
	end
	if state == "Free" or state == "Waiting" then
		local scoreLabel = findTextLabel(arena.Model, "ScoreLabel")
		if scoreLabel then
			scoreLabel.Text = string.format("%d / 2", occupants)
		end
	end
end

function ArenaService.SetWaiting(self: Service, arena: Arena, player: Player): boolean
	if arena.State ~= "Free" or arena.MatchId ~= nil then
		return false
	end
	self:SetRoomState(arena, "Waiting", player, nil)
	return true
end

function ArenaService.ClearWaiting(self: Service, arena: Arena): boolean
	if arena.State ~= "Waiting" or arena.MatchId ~= nil then
		return false
	end
	self:SetRoomState(arena, "Free", nil, nil)
	return true
end

function ArenaService.Reserve(
	self: Service,
	arena: Arena,
	matchId: string,
	home: Player?,
	away: Player?
): boolean
	if arena.MatchId ~= nil or (arena.State ~= "Free" and arena.State ~= "Waiting") then
		return false
	end
	if arena.State == "Waiting" then
		local waitingUserId = arena.Model:GetAttribute("HomeUserId")
		if
			type(waitingUserId) == "number"
			and waitingUserId ~= 0
			and (not home or waitingUserId ~= home.UserId)
		then
			return false
		end
	end
	arena.MatchId = matchId
	arena.Model:SetAttribute("MatchId", matchId)
	self:SetRoomState(arena, "Countdown", home, away)
	return true
end

function ArenaService.SetMatchState(
	self: Service,
	arena: Arena,
	matchId: string,
	state: RoomState,
	home: Player?,
	away: Player?
): boolean
	if arena.MatchId ~= matchId then
		return false
	end
	self:SetRoomState(arena, state, home, away)
	return true
end

function ArenaService.UpdateScore(
	_self: Service,
	arena: Arena,
	homeScore: number,
	awayScore: number
)
	arena.Model:SetAttribute("HomeScore", homeScore)
	arena.Model:SetAttribute("AwayScore", awayScore)
	local scoreLabel = findTextLabel(arena.Model, "ScoreLabel")
	if scoreLabel then
		scoreLabel.Text = string.format("%d  -  %d", homeScore, awayScore)
	end
end

function ArenaService.Release(self: Service, arena: Arena)
	arena.MatchId = nil
	arena.Model:SetAttribute("MatchId", "")
	self:SetRoomState(arena, "Free", nil, nil)
	self:ResetBall(arena)
end

function ArenaService.ResetBall(_self: Service, arena: Arena)
	arena.Ball:SetNetworkOwner(nil)
	arena.Ball.AssemblyLinearVelocity = Vector3.zero
	arena.Ball.AssemblyAngularVelocity = Vector3.zero
	arena.Ball.CFrame = arena.BallSpawn.CFrame
	arena.Ball:SetAttribute("OwnerUserId", 0)
	arena.Ball:SetAttribute("LastTouchUserId", 0)
end

function ArenaService.TeleportToSpawn(_self: Service, player: Player, spawnPart: BasePart): boolean
	local character = player.Character
	if not character then
		return false
	end
	local root = character:FindFirstChild("HumanoidRootPart")
	if not root or not root:IsA("BasePart") then
		return false
	end
	character:PivotTo(spawnPart.CFrame + Vector3.new(0, 3.2, 0))
	root.AssemblyLinearVelocity = Vector3.zero
	root.AssemblyAngularVelocity = Vector3.zero
	return true
end

function ArenaService.ReturnToLobby(self: Service, player: Player): boolean
	return self:TeleportToSpawn(player, self.lobbySpawn)
end

function ArenaService.ReturnToStreet(self: Service, arena: Arena, player: Player): boolean
	return self:TeleportToSpawn(player, arena.StreetSpawn or self.lobbySpawn)
end

function ArenaService.IsInside(
	_self: Service,
	arena: Arena,
	position: Vector3,
	margin: number?
): boolean
	local localPosition = arena.Bounds.CFrame:PointToObjectSpace(position)
	local halfSize = arena.Bounds.Size * 0.5
	local extra = margin or 0
	return math.abs(localPosition.X) <= halfSize.X + extra
		and math.abs(localPosition.Z) <= halfSize.Z + extra
		and localPosition.Y >= -25
		and localPosition.Y <= halfSize.Y + 30
end

function ArenaService.GetLobbySpawn(self: Service): BasePart
	return self.lobbySpawn
end

return ArenaService
