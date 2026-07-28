--!strict

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
	Busy: boolean,
	MatchId: string?,
}

export type Service = typeof(setmetatable(
	{} :: {
		root: Model,
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

function ArenaService.new(root: Model): Service
	local arenasFolder = root:FindFirstChild("Arenas")
	assert(arenasFolder, "WorldBuilder must create PannaWorld/Arenas")
	local lobbySpawn = root:FindFirstChild("LobbySpawn", true)
	assert(lobbySpawn and lobbySpawn:IsA("BasePart"), "WorldBuilder must create LobbySpawn")

	local self = setmetatable({
		root = root,
		arenas = {},
		byId = {},
		lobbySpawn = lobbySpawn,
	}, ArenaService)

	for _, child in arenasFolder:GetChildren() do
		if child:IsA("Model") then
			local idAttribute = child:GetAttribute("ArenaId")
			local id = if type(idAttribute) == "string" then idAttribute else child.Name
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
				Busy = false,
				MatchId = nil,
			}
			child:SetAttribute("Busy", false)
			child:SetAttribute("MatchId", "")
			table.insert(self.arenas, arena)
			self.byId[id] = arena
		end
	end

	table.sort(self.arenas, function(a: Arena, b: Arena): boolean
		return a.Id < b.Id
	end)
	assert(#self.arenas > 0, "WorldBuilder did not create any arenas")

	return self
end

function ArenaService.GetAll(self: Service): { Arena }
	return self.arenas
end

function ArenaService.GetById(self: Service, id: string): Arena?
	return self.byId[id]
end

function ArenaService.GetAvailable(self: Service): Arena?
	for _, arena in self.arenas do
		if not arena.Busy then
			return arena
		end
	end
	return nil
end

function ArenaService.Reserve(_self: Service, arena: Arena, matchId: string): boolean
	if arena.Busy then
		return false
	end
	arena.Busy = true
	arena.MatchId = matchId
	arena.Model:SetAttribute("Busy", true)
	arena.Model:SetAttribute("MatchId", matchId)
	return true
end

function ArenaService.Release(self: Service, arena: Arena)
	arena.Busy = false
	arena.MatchId = nil
	arena.Model:SetAttribute("Busy", false)
	arena.Model:SetAttribute("MatchId", "")
	self:ResetBall(arena)
end

function ArenaService.ResetBall(_self: Service, arena: Arena)
	arena.Ball:SetNetworkOwner(nil)
	arena.Ball.AssemblyLinearVelocity = Vector3.zero
	arena.Ball.AssemblyAngularVelocity = Vector3.zero
	arena.Ball.CFrame = arena.BallSpawn.CFrame
	arena.Ball:SetAttribute("OwnerUserId", 0)
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
