--!strict

local RoomService = {}
RoomService.__index = RoomService

type RoomRecord = {
	arena: any,
	waiting: Player?,
	generation: number,
	transitioning: boolean,
}

export type Service = typeof(setmetatable(
	{} :: {
		config: any,
		arenas: any,
		matches: any,
		queue: any,
		remotes: any,
		rooms: { [string]: RoomRecord },
		playerRooms: { [Player]: RoomRecord },
		connections: { RBXScriptConnection },
		started: boolean,
	},
	RoomService
))

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function playerReady(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	return player.Parent ~= nil
		and getRoot(player) ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
end

local function distanceFromZone(position: Vector3, zone: BasePart): number
	local localPosition = zone.CFrame:PointToObjectSpace(position)
	local halfSize = zone.Size * 0.5
	local outside = Vector3.new(
		math.max(0, math.abs(localPosition.X) - halfSize.X),
		math.max(0, math.abs(localPosition.Y) - halfSize.Y),
		math.max(0, math.abs(localPosition.Z) - halfSize.Z)
	)
	return outside.Magnitude
end

function RoomService.new(config: any, arenas: any, matches: any, queue: any, remotes: any): Service
	local self = setmetatable({
		config = config,
		arenas = arenas,
		matches = matches,
		queue = queue,
		remotes = remotes,
		rooms = {},
		playerRooms = {},
		connections = {},
		started = false,
	}, RoomService)
	for _, arena in arenas:GetAll() do
		self.rooms[arena.Id] = {
			arena = arena,
			waiting = nil,
			generation = 0,
			transitioning = false,
		}
	end
	return self
end

function RoomService._message(self: Service, player: Player, title: string, message: string)
	if player.Parent then
		self.remotes.Effect:FireClient(player, {
			kind = "Message",
			title = title,
			text = message,
		})
	end
end

function RoomService._isNearZone(self: Service, player: Player, zone: BasePart?): boolean
	local root = getRoot(player)
	if not root or not zone then
		return false
	end
	local maximum = if self.config.Rooms
			and type(self.config.Rooms.InteractionDistance) == "number"
		then self.config.Rooms.InteractionDistance
		else 16
	return distanceFromZone(root.Position, zone) <= maximum
end

function RoomService._setSelected(_self: Service, player: Player, arenaId: string, waiting: boolean)
	player:SetAttribute("InRoomWaiting", waiting)
	player:SetAttribute("SelectedArenaId", arenaId)
	player:SetAttribute("InQueue", false)
end

function RoomService._clearSelected(_self: Service, player: Player, arenaId: string)
	player:SetAttribute("InRoomWaiting", false)
	if player:GetAttribute("SelectedArenaId") == arenaId then
		player:SetAttribute("SelectedArenaId", "")
	end
end

function RoomService._isWaitingValid(self: Service, room: RoomRecord, player: Player): boolean
	return room.waiting == player
		and self.playerRooms[player] == room
		and player:GetAttribute("InRoomWaiting") == true
		and player:GetAttribute("InMatch") ~= true
		and playerReady(player)
		and self.queue:IsEligible(player)
end

function RoomService._clearWaiting(
	self: Service,
	room: RoomRecord,
	returnToStreet: boolean,
	notifyQueue: boolean?
)
	local player = room.waiting
	room.waiting = nil
	room.generation += 1
	room.transitioning = false
	if player and self.playerRooms[player] == room then
		self.playerRooms[player] = nil
		self:_clearSelected(player, room.arena.Id)
		if returnToStreet and player.Parent then
			player:SetAttribute("ControlsLocked", false)
			self.arenas:ReturnToStreet(room.arena, player)
		end
		self.queue:Refresh(player)
	end
	if room.arena.State == "Waiting" and room.arena.MatchId == nil then
		self.arenas:ClearWaiting(room.arena)
	end
	if notifyQueue ~= false then
		self.queue:Process()
	end
end

function RoomService._scheduleWaitingTimeout(self: Service, room: RoomRecord, player: Player)
	local timeout = if self.config.Rooms
			and type(self.config.Rooms.WaitingTimeoutSeconds) == "number"
		then self.config.Rooms.WaitingTimeoutSeconds
		else 120
	if timeout <= 0 then
		return
	end
	local generation = room.generation
	task.delay(timeout, function()
		if room.generation ~= generation or room.waiting ~= player then
			return
		end
		self:_message(player, "ROOM RELEASED", "No opponent joined in time.")
		self:_clearWaiting(room, true)
	end)
end

function RoomService._placeWaitingPlayer(self: Service, room: RoomRecord, player: Player): boolean
	if not self.arenas:SetWaiting(room.arena, player) then
		return false
	end
	room.waiting = player
	room.generation += 1
	self.playerRooms[player] = room
	self:_setSelected(player, room.arena.Id, true)
	player:SetAttribute("ControlsLocked", false)
	local waitingSpawn = room.arena.HomeWaitingSpawn or room.arena.HomeSpawn
	if not self.arenas:TeleportToSpawn(player, waitingSpawn) then
		self:_clearWaiting(room, false)
		return false
	end
	self.queue:Refresh(player)
	self:_message(player, "ROOM READY", "Waiting for one opponent.")
	self:_scheduleWaitingTimeout(room, player)
	return true
end

function RoomService._takeWaiting(self: Service, room: RoomRecord): Player?
	local player = room.waiting
	room.waiting = nil
	room.generation += 1
	if player and self.playerRooms[player] == room then
		self.playerRooms[player] = nil
		self:_setSelected(player, room.arena.Id, false)
	end
	return player
end

function RoomService._restoreWaiting(self: Service, room: RoomRecord, player: Player): boolean
	if
		room.arena.MatchId ~= nil or (room.arena.State ~= "Waiting" and room.arena.State ~= "Free")
	then
		return false
	end
	if room.arena.State == "Free" and not self.arenas:SetWaiting(room.arena, player) then
		return false
	end
	room.waiting = player
	room.generation += 1
	self.playerRooms[player] = room
	self:_setSelected(player, room.arena.Id, true)
	self.queue:Refresh(player)
	self:_scheduleWaitingTimeout(room, player)
	return true
end

function RoomService._startWaitingMatch(
	self: Service,
	room: RoomRecord,
	challenger: Player
): boolean
	local waiting = room.waiting
	if not waiting or not self:_isWaitingValid(room, waiting) then
		self:_clearWaiting(room, waiting ~= nil, false)
		if not self.queue:PrepareRoomEntry(challenger) then
			return false
		end
		return self:_placeWaitingPlayer(room, challenger)
	end
	if waiting == challenger or not self.queue:PrepareRoomEntry(challenger) then
		return false
	end

	room.transitioning = true
	waiting = self:_takeWaiting(room)
	if not waiting then
		room.transitioning = false
		return false
	end
	self:_setSelected(challenger, room.arena.Id, false)
	local awayWaitingSpawn = room.arena.AwayWaitingSpawn or room.arena.AwaySpawn
	self.arenas:TeleportToSpawn(challenger, awayWaitingSpawn)
	local match = self.matches:StartMatch(waiting, challenger, room.arena)
	room.transitioning = false
	if match then
		self.queue:Refresh(waiting)
		self.queue:Refresh(challenger)
		return true
	end

	self:_clearSelected(challenger, room.arena.Id)
	self.arenas:ReturnToStreet(room.arena, challenger)
	self.queue:Refresh(challenger)
	if playerReady(waiting) and self.queue:IsEligible(waiting) then
		self:_restoreWaiting(room, waiting)
	else
		self:_clearSelected(waiting, room.arena.Id)
		self.arenas:ClearWaiting(room.arena)
		self.queue:Refresh(waiting)
		self.queue:Process()
	end
	return false
end

function RoomService.Enter(
	self: Service,
	player: Player,
	arena: any,
	requireProximity: boolean?
): boolean
	local room = self.rooms[arena.Id]
	if not room or room.transitioning then
		return false
	end
	if requireProximity == true and not self:_isNearZone(player, arena.EntryZone) then
		return false
	end
	if player:GetAttribute("InMatch") == true then
		self:_message(player, "ROOM UNAVAILABLE", "Finish your current match first.")
		return false
	end
	local currentRoom = self.playerRooms[player]
	if currentRoom then
		self:_message(player, "ALREADY WAITING", "Use EXIT before choosing another room.")
		return false
	end
	if arena.State ~= "Free" and arena.State ~= "Waiting" then
		self:_message(player, "ROOM BUSY", "This court is already playing a match.")
		return false
	end
	if arena.State == "Waiting" then
		return self:_startWaitingMatch(room, player)
	end
	if not self.queue:PrepareRoomEntry(player) then
		return false
	end
	return self:_placeWaitingPlayer(room, player)
end

function RoomService.Exit(
	self: Service,
	player: Player,
	arena: any?,
	requireProximity: boolean?
): boolean
	local waitingRoom = self.playerRooms[player]
	if waitingRoom then
		if arena and waitingRoom.arena ~= arena then
			return false
		end
		if
			requireProximity == true and not self:_isNearZone(player, waitingRoom.arena.ExitZone)
		then
			return false
		end
		self:_clearWaiting(waitingRoom, true)
		return true
	end

	local arenaId = player:GetAttribute("ArenaId")
	local matchArena = if type(arenaId) == "string" then self.arenas:GetById(arenaId) else nil
	if arena and matchArena ~= arena then
		return false
	end
	if matchArena then
		if requireProximity == true and not self:_isNearZone(player, matchArena.ExitZone) then
			return false
		end
		return self.matches:RequestExit(player)
	end
	if self.queue:Contains(player) then
		return self.queue:Leave(player)
	end
	return false
end

function RoomService.StartRematch(self: Service, first: Player, second: Player, arena: any): boolean
	local room = self.rooms[arena.Id]
	if
		not room
		or room.transitioning
		or room.waiting ~= nil
		or arena.State ~= "Free"
		or not self.queue:PrepareRoomEntry(first)
		or not self.queue:PrepareRoomEntry(second)
	then
		return false
	end
	room.transitioning = true
	self:_setSelected(first, arena.Id, false)
	self:_setSelected(second, arena.Id, false)
	local match = self.matches:StartMatch(first, second, arena)
	room.transitioning = false
	if not match then
		self:_clearSelected(first, arena.Id)
		self:_clearSelected(second, arena.Id)
		return false
	end
	self.queue:Refresh(first)
	self.queue:Refresh(second)
	return true
end

function RoomService.HandlePlayerRemoving(self: Service, player: Player)
	local room = self.playerRooms[player]
	if room then
		self:_clearWaiting(room, false)
	end
end

function RoomService.HandleCharacterAdded(self: Service, player: Player, character: Model)
	local room = self.playerRooms[player]
	if not room then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 8)
		if
			not root
			or player.Character ~= character
			or self.playerRooms[player] ~= room
			or room.waiting ~= player
		then
			return
		end
		self.arenas:TeleportToSpawn(player, room.arena.HomeWaitingSpawn or room.arena.HomeSpawn)
	end)
end

function RoomService.Start(self: Service)
	if self.started then
		return
	end
	self.started = true
	for _, room in self.rooms do
		local arena = room.arena
		if arena.EntryPrompt then
			table.insert(
				self.connections,
				arena.EntryPrompt.Triggered:Connect(function(player: Player)
					self:Enter(player, arena, true)
				end)
			)
		else
			warn(string.format("[Panna] %s is missing EntryZone/EntryPrompt", arena.Id))
		end
		if arena.ExitPrompt then
			table.insert(
				self.connections,
				arena.ExitPrompt.Triggered:Connect(function(player: Player)
					self:Exit(player, arena, true)
				end)
			)
		else
			warn(string.format("[Panna] %s is missing ExitZone/ExitPrompt", arena.Id))
		end
	end
end

return RoomService
