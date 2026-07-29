--!strict

local RunService = game:GetService("RunService")

local EMIT_BATCH_SECONDS = 0.1
local ALLOW_FALLBACK_SESSIONS = RunService:IsStudio()
local ROOM_CAPACITY = 2

local QueueService = {}
QueueService.__index = QueueService

export type Service = typeof(setmetatable(
	{} :: {
		arenas: any,
		matches: any,
		remotes: any,
		queue: { Player },
		membership: { [Player]: boolean },
		processing: boolean,
		emitScheduled: boolean,
	},
	QueueService
))

function QueueService.new(arenas: any, matches: any, remotes: any): Service
	return setmetatable({
		arenas = arenas,
		matches = matches,
		remotes = remotes,
		queue = {},
		membership = {},
		processing = false,
		emitScheduled = false,
	}, QueueService)
end

function QueueService.GetSnapshot(self: Service, player: Player): { [string]: any }
	local position = table.find(self.queue, player)
	local globalJoined = self.membership[player] == true and position ~= nil
	local roomWaiting = player:GetAttribute("InRoomWaiting") == true
	local joined = globalJoined or roomWaiting
	local selectedAttribute = player:GetAttribute("SelectedArenaId")
	local matchArenaAttribute = player:GetAttribute("ArenaId")
	local selectedArenaId = if type(selectedAttribute) == "string"
			and selectedAttribute ~= ""
		then selectedAttribute
		else if type(matchArenaAttribute) == "string" then matchArenaAttribute else ""
	local arena = if selectedArenaId ~= "" then self.arenas:GetById(selectedArenaId) else nil
	local roomStatus = if arena then arena.State else if globalJoined then "Waiting" else "Free"
	local occupantsAttribute = if arena then arena.Model:GetAttribute("Occupants") else nil
	local occupants = if type(occupantsAttribute) == "number" then occupantsAttribute else 0
	local status = "Ready"
	if roomWaiting and arena then
		status = string.format("Waiting in %s", self.arenas:GetDisplayName(arena))
	elseif globalJoined then
		status = if self.arenas:GetAvailable()
			then "Searching for opponent"
			else "Waiting for free arena"
	elseif player:GetAttribute("InMatch") == true and arena then
		status = string.format("Playing in %s", self.arenas:GetDisplayName(arena))
	end
	return {
		joined = joined,
		status = status,
		position = position or 0,
		count = #self.queue,
		arenaId = selectedArenaId,
		selectedArenaId = selectedArenaId,
		arenaName = if arena then self.arenas:GetDisplayName(arena) else "",
		roomStatus = roomStatus,
		occupants = occupants,
		capacity = ROOM_CAPACITY,
	}
end

function QueueService._emit(self: Service, player: Player)
	if player.Parent then
		self.remotes.StateUpdate:FireClient(player, { queue = self:GetSnapshot(player) })
	end
end

function QueueService._flushEmissions(self: Service)
	for _, player in self.queue do
		self:_emit(player)
	end
end

function QueueService._emitAll(self: Service)
	if self.emitScheduled then
		return
	end

	-- Coalesce rapid joins/leaves into one positional refresh instead of broadcasting
	-- the entire queue once per request.
	self.emitScheduled = true
	task.delay(EMIT_BATCH_SECONDS, function()
		self.emitScheduled = false
		self:_flushEmissions()
	end)
end

function QueueService._canEnterRanked(self: Service, player: Player): boolean
	if player.Parent == nil then
		return false
	end
	if player:GetAttribute("DataLoaded") ~= true then
		self.remotes.Effect:FireClient(player, {
			kind = "Message",
			title = "LOADING",
			text = "Your player profile is still loading.",
		})
		return false
	end
	if not ALLOW_FALLBACK_SESSIONS and player:GetAttribute("DataSessionFallback") == true then
		self.remotes.Effect:FireClient(player, {
			kind = "Message",
			title = "RANKED UNAVAILABLE",
			text = "Your progress could not be loaded safely. Rejoin before entering ranked matchmaking.",
		})
		return false
	end
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	if not humanoid or humanoid.Health <= 0 or not root or not root:IsA("BasePart") then
		self.remotes.Effect:FireClient(player, {
			kind = "Message",
			title = "RESPAWNING",
			text = "Wait for your character to spawn before joining matchmaking.",
		})
		return false
	end
	return true
end

function QueueService.CanEnterRoom(self: Service, player: Player): boolean
	if player:GetAttribute("InMatch") == true or player:GetAttribute("InRoomWaiting") == true then
		return false
	end
	return self:IsEligible(player)
end

function QueueService.IsEligible(self: Service, player: Player): boolean
	return self:_canEnterRanked(player)
end

function QueueService.PrepareRoomEntry(self: Service, player: Player): boolean
	if not self:CanEnterRoom(player) then
		return false
	end
	if self.membership[player] then
		self:Leave(player)
	end
	return true
end

function QueueService.Contains(self: Service, player: Player): boolean
	return self.membership[player] == true
end

function QueueService.Refresh(self: Service, player: Player)
	self:_emit(player)
end

function QueueService.Join(self: Service, player: Player): boolean
	if
		self.membership[player]
		or player:GetAttribute("InMatch") == true
		or player:GetAttribute("InRoomWaiting") == true
	then
		return false
	end
	if not self:_canEnterRanked(player) then
		return false
	end

	self.membership[player] = true
	table.insert(self.queue, player)
	player:SetAttribute("InQueue", true)
	player:SetAttribute("SelectedArenaId", "")
	self:_emitAll()
	self:Process()
	return true
end

function QueueService.Leave(self: Service, player: Player): boolean
	if not self.membership[player] then
		return false
	end
	self.membership[player] = nil
	local index = table.find(self.queue, player)
	if index then
		table.remove(self.queue, index)
	end
	player:SetAttribute("InQueue", false)
	self:_emit(player)
	self:_emitAll()
	return true
end

function QueueService.Toggle(self: Service, player: Player): boolean
	if self.membership[player] then
		return self:Leave(player)
	end
	return self:Join(player)
end

function QueueService._popValid(self: Service): Player?
	while #self.queue > 0 do
		local player = table.remove(self.queue, 1)
		self.membership[player] = nil
		if
			player.Parent
			and player:GetAttribute("InMatch") ~= true
			and player:GetAttribute("InRoomWaiting") ~= true
			and self:_canEnterRanked(player)
		then
			player:SetAttribute("InQueue", false)
			return player
		end
		player:SetAttribute("InQueue", false)
		self:_emit(player)
	end
	return nil
end

function QueueService.Process(self: Service)
	if self.processing then
		return
	end
	self.processing = true

	task.defer(function()
		while #self.queue >= ROOM_CAPACITY do
			local arena = self.arenas:GetAvailable()
			if not arena then
				break
			end

			local home = self:_popValid()
			local away = self:_popValid()
			if not home then
				break
			end
			if not away then
				self.membership[home] = true
				table.insert(self.queue, 1, home)
				home:SetAttribute("InQueue", true)
				break
			end

			local match = self.matches:StartMatch(home, away, arena)
			if not match then
				if home.Parent and home:GetAttribute("InMatch") ~= true then
					self.membership[home] = true
					table.insert(self.queue, home)
					home:SetAttribute("InQueue", true)
				end
				if away.Parent and away:GetAttribute("InMatch") ~= true then
					self.membership[away] = true
					table.insert(self.queue, away)
					away:SetAttribute("InQueue", true)
				end
				break
			end
			-- Clear the queue presentation for both players before the result screen
			-- eventually reveals the lobby controls again.
			self:_emit(home)
			self:_emit(away)
		end

		self.processing = false
		self:_emitAll()
	end)
end

function QueueService.EnqueuePair(self: Service, first: Player, second: Player): boolean
	local firstEligible = self:_canEnterRanked(first)
	local secondEligible = self:_canEnterRanked(second)
	if
		not firstEligible
		or not secondEligible
		or first:GetAttribute("InRoomWaiting") == true
		or second:GetAttribute("InRoomWaiting") == true
	then
		return false
	end

	if first.Parent and first:GetAttribute("InMatch") ~= true and not self.membership[first] then
		self.membership[first] = true
		table.insert(self.queue, 1, first)
		first:SetAttribute("InQueue", true)
	end
	if second.Parent and second:GetAttribute("InMatch") ~= true and not self.membership[second] then
		self.membership[second] = true
		table.insert(self.queue, ROOM_CAPACITY, second)
		second:SetAttribute("InQueue", true)
	end
	self:_emitAll()
	self:Process()
	return self.membership[first] == true and self.membership[second] == true
end

function QueueService.HandlePlayerRemoving(self: Service, player: Player)
	if self.membership[player] then
		self:Leave(player)
	end
end

return QueueService
