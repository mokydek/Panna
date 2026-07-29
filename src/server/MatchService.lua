--!strict

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local GoalMath = require(ReplicatedStorage:WaitForChild("PannaShared"):WaitForChild("GoalMath"))

local MatchService = {}
MatchService.__index = MatchService

type Score = {
	Home: number,
	Away: number,
	HomeGoals: number,
	AwayGoals: number,
	HomePannas: number,
	AwayPannas: number,
}

type MatchRecord = {
	Id: string,
	Revision: number,
	Arena: any,
	Home: Player,
	Away: Player,
	State: string,
	Score: Score,
	StartedAt: number,
	EndsAt: number,
	GoldenGoal: boolean,
	Ended: boolean,
	GoalDebounce: boolean,
	RematchVotes: { [Player]: boolean },
	VisualRevision: number,
}

export type Service = typeof(setmetatable(
	{} :: {
		config: any,
		arenas: any,
		ballService: any,
		dataService: any,
		remotes: any,
		matches: { [string]: MatchRecord },
		byPlayer: { [Player]: MatchRecord },
		onArenaReleased: ((any, Player, Player) -> ())?,
		onRematchReady: ((Player, Player, any) -> ())?,
		goalHeartbeat: RBXScriptConnection?,
		goalPositions: { [string]: Vector3? },
		nextMatchRevision: number,
	},
	MatchService
))

local function serverNow(): number
	return workspace:GetServerTimeNow()
end

local function opponent(match: MatchRecord, player: Player): Player?
	if match.Home == player then
		return match.Away
	elseif match.Away == player then
		return match.Home
	end
	return nil
end

local function playerReady(player: Player): boolean
	local character = player.Character
	local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return player.Parent ~= nil
		and humanoid ~= nil
		and humanoid.Health > 0
		and root ~= nil
		and root:IsA("BasePart")
end

function MatchService.new(
	config: any,
	arenas: any,
	ballService: any,
	dataService: any,
	remotes: any
): Service
	local self = setmetatable({
		config = config,
		arenas = arenas,
		ballService = ballService,
		dataService = dataService,
		remotes = remotes,
		matches = {},
		byPlayer = {},
		onArenaReleased = nil,
		onRematchReady = nil,
		goalHeartbeat = nil,
		goalPositions = {},
		nextMatchRevision = 0,
	}, MatchService)

	self.goalHeartbeat = RunService.Heartbeat:Connect(function()
		self:_stepGoals()
	end)

	ballService:SetPannaCallback(function(attacker: Player, defender: Player)
		self:_onPanna(attacker, defender)
	end)
	ballService:SetActionCallback(
		function(actor: Player, action: string, mode: string?, lateral: number?)
			self:BroadcastPlayerAction(actor, action, mode, lateral)
		end
	)

	return self
end

function MatchService._stepGoal(
	self: Service,
	match: MatchRecord,
	defendedSide: string,
	goal: BasePart,
	previousPosition: Vector3,
	currentPosition: Vector3
)
	if match.GoalDebounce then
		return
	end

	local ball = match.Arena.Ball
	local radius =
		math.max(self.config.Ball.Radius, ball.Size.X * 0.5, ball.Size.Y * 0.5, ball.Size.Z * 0.5)
	local geometry = GoalMath.CreateGeometry(goal.CFrame, goal.Size, match.Arena.Bounds.Position)
	if
		geometry
		and GoalMath.DidSphereFullyCross(previousPosition, currentPosition, radius, geometry)
	then
		self:_onGoalCrossed(match.Arena, defendedSide)
	end
end

function MatchService._stepGoals(self: Service)
	local now = serverNow()
	for _, match in self.matches do
		if
			not match.Ended
			and now < match.EndsAt
			and (match.State == "Active" or match.State == "Overtime")
		then
			local currentPosition = match.Arena.Ball.Position
			local previousPosition = self.goalPositions[match.Id]
			self.goalPositions[match.Id] = currentPosition
			if previousPosition then
				self:_stepGoal(
					match,
					"Home",
					match.Arena.HomeGoal,
					previousPosition,
					currentPosition
				)
				self:_stepGoal(
					match,
					"Away",
					match.Arena.AwayGoal,
					previousPosition,
					currentPosition
				)
			end
		end
	end
end

function MatchService.SetArenaReleasedCallback(self: Service, callback: (any, Player, Player) -> ())
	self.onArenaReleased = callback
end

function MatchService.SetRematchCallback(self: Service, callback: (Player, Player, any) -> ())
	self.onRematchReady = callback
end

function MatchService._setControlsLocked(_self: Service, match: MatchRecord, locked: boolean)
	for _, player in { match.Home, match.Away } do
		player:SetAttribute("ControlsLocked", locked)
		local character = player.Character
		local humanoid = if character then character:FindFirstChildOfClass("Humanoid") else nil
		if humanoid then
			humanoid.WalkSpeed = if locked then 0 else 18
			humanoid.JumpHeight = if locked then 0 else 7.2
			humanoid.JumpPower = if locked then 0 else 50
		end
	end
end

function MatchService._teleportPlayers(self: Service, match: MatchRecord): boolean
	local homeReady = self.arenas:TeleportToSpawn(match.Home, match.Arena.HomeSpawn)
	local awayReady = self.arenas:TeleportToSpawn(match.Away, match.Arena.AwaySpawn)
	return homeReady and awayReady
end

function MatchService._snapshot(self: Service, match: MatchRecord): { [string]: any }
	return {
		id = match.Id,
		revision = match.Revision,
		state = match.State,
		arenaId = match.Arena.Id,
		arenaName = self.arenas:GetDisplayName(match.Arena),
		homeName = match.Home.DisplayName,
		awayName = match.Away.DisplayName,
		homeUserId = match.Home.UserId,
		awayUserId = match.Away.UserId,
		homeScore = match.Score.Home,
		awayScore = match.Score.Away,
		homePannas = match.Score.HomePannas,
		awayPannas = match.Score.AwayPannas,
		remaining = math.max(0, math.ceil(match.EndsAt - serverNow())),
		endsAt = match.EndsAt,
		serverNow = serverNow(),
		goldenGoal = match.GoldenGoal,
	}
end

function MatchService.GetSnapshot(self: Service, player: Player): { [string]: any }?
	local match = self.byPlayer[player]
	return if match then self:_snapshot(match) else nil
end

function MatchService._broadcast(self: Service, match: MatchRecord)
	self.arenas:UpdateScore(match.Arena, match.Score.Home, match.Score.Away)
	local snapshot = self:_snapshot(match)
	for _, player in { match.Home, match.Away } do
		if player.Parent then
			self.remotes.StateUpdate:FireClient(player, { match = snapshot })
		end
	end
end

function MatchService._effect(self: Service, match: MatchRecord, payload: { [string]: any })
	local scopedPayload = table.clone(payload)
	scopedPayload.matchId = match.Id
	scopedPayload.arenaId = match.Arena.Id
	scopedPayload.matchRevision = match.Revision
	for _, player in { match.Home, match.Away } do
		if player.Parent then
			self.remotes.Effect:FireClient(player, scopedPayload)
		end
	end
end

function MatchService.BroadcastPlayerAction(
	self: Service,
	actor: Player,
	action: string,
	mode: string?,
	lateral: number?
)
	local match = self.byPlayer[actor]
	if
		not match
		or match.Ended
		or (match.Home ~= actor and match.Away ~= actor)
		or type(action) ~= "string"
		or action == ""
	then
		return
	end

	match.VisualRevision += 1
	self:_effect(match, {
		kind = "PlayerAction",
		actorUserId = actor.UserId,
		action = action,
		mode = if type(mode) == "string" then mode else "",
		lateral = if type(lateral) == "number" and lateral == lateral
			then math.clamp(lateral, -1, 1)
			else 0,
		visualRevision = match.VisualRevision,
		serverTime = serverNow(),
	})
end

function MatchService.StartMatch(
	self: Service,
	home: Player,
	away: Player,
	arena: any
): MatchRecord?
	if
		self.byPlayer[home]
		or self.byPlayer[away]
		or not playerReady(home)
		or not playerReady(away)
	then
		return nil
	end

	local matchId = HttpService:GenerateGUID(false)
	if not self.arenas:Reserve(arena, matchId, home, away) then
		return nil
	end
	self.nextMatchRevision += 1

	local now = serverNow()
	local match: MatchRecord = {
		Id = matchId,
		Revision = self.nextMatchRevision,
		Arena = arena,
		Home = home,
		Away = away,
		State = "Countdown",
		Score = {
			Home = 0,
			Away = 0,
			HomeGoals = 0,
			AwayGoals = 0,
			HomePannas = 0,
			AwayPannas = 0,
		},
		StartedAt = 0,
		EndsAt = now + self.config.Match.CountdownSeconds,
		GoldenGoal = false,
		Ended = false,
		GoalDebounce = false,
		RematchVotes = {},
		VisualRevision = 0,
	}

	self.matches[matchId] = match
	self.goalPositions[matchId] = nil
	self.byPlayer[home] = match
	self.byPlayer[away] = match
	for _, player in { home, away } do
		player:SetAttribute("InQueue", false)
		player:SetAttribute("InRoomWaiting", false)
		player:SetAttribute("InMatch", true)
		player:SetAttribute("MatchId", matchId)
		player:SetAttribute("ArenaId", arena.Id)
		player:SetAttribute("MatchRevision", match.Revision)
		player:SetAttribute("SelectedArenaId", arena.Id)
	end

	self:_setControlsLocked(match, true)
	self:_teleportPlayers(match)
	self.ballService:AttachMatch(match)
	self:_broadcast(match)
	self:_effect(match, { kind = "Message", title = "MATCH FOUND", text = "Get ready!" })

	task.spawn(function()
		self:_runMatch(match)
	end)
	return match
end

function MatchService._runMatch(self: Service, match: MatchRecord)
	for remaining = self.config.Match.CountdownSeconds, 1, -1 do
		if match.Ended then
			return
		end
		match.EndsAt = serverNow() + remaining
		self:_broadcast(match)
		task.wait(1)
	end

	if match.Ended then
		return
	end
	if
		not playerReady(match.Home)
		or not playerReady(match.Away)
		or not self:_teleportPlayers(match)
	then
		self:_finish(match, nil, "Cancelled", false)
		return
	end
	match.State = "Active"
	match.StartedAt = serverNow()
	match.EndsAt = match.StartedAt + self.config.Match.DurationSeconds
	self:_setControlsLocked(match, false)
	self.arenas:SetMatchState(match.Arena, match.Id, "Active", match.Home, match.Away)
	self.ballService:SetActive(match, true)
	self:_broadcast(match)

	local lastSecond = -1
	while not match.Ended do
		if match.State == "Active" or match.State == "Overtime" then
			local remaining = math.max(0, math.ceil(match.EndsAt - serverNow()))
			if remaining ~= lastSecond then
				lastSecond = remaining
				self:_broadcast(match)
			end

			if remaining <= 0 then
				if match.Score.Home == match.Score.Away and match.State == "Active" then
					match.State = "Overtime"
					match.GoldenGoal = self.config.Match.GoldenGoalInOvertime
					match.EndsAt = serverNow() + self.config.Match.OvertimeSeconds
					lastSecond = -1
					self:_effect(
						match,
						{ kind = "Message", title = "OVERTIME", text = "Golden goal wins." }
					)
					self:_broadcast(match)
				else
					local winner: Player? = nil
					if match.Score.Home > match.Score.Away then
						winner = match.Home
					elseif match.Score.Away > match.Score.Home then
						winner = match.Away
					end
					self:_finish(match, winner, if winner then "Time" else "Draw")
				end
			end
		end
		task.wait(0.2)
	end
end

function MatchService._onGoalCrossed(self: Service, arena: any, defendedSide: string)
	local matchId = arena.MatchId
	local match = if matchId then self.matches[matchId] else nil
	if not match or match.Ended or match.GoalDebounce then
		return
	end
	if match.State ~= "Active" and match.State ~= "Overtime" then
		return
	end
	if serverNow() >= match.EndsAt then
		return
	end

	match.GoalDebounce = true
	local previousState = match.State
	local remaining = math.max(1, match.EndsAt - serverNow())
	local scoringSide = if defendedSide == "Home" then "Away" else "Home"
	if scoringSide == "Home" then
		match.Score.Home += 1
		match.Score.HomeGoals += 1
	else
		match.Score.Away += 1
		match.Score.AwayGoals += 1
	end

	self:_effect(match, {
		kind = "Goal",
		title = "GOAL!",
		text = string.format(
			"%s scores",
			if scoringSide == "Home" then match.Home.DisplayName else match.Away.DisplayName
		),
	})
	self:_broadcast(match)

	local reachedLimit = match.Score.Home >= self.config.Match.GoalLimit
		or match.Score.Away >= self.config.Match.GoalLimit
	if reachedLimit or (previousState == "Overtime" and match.GoldenGoal) then
		local winner = if scoringSide == "Home" then match.Home else match.Away
		self:_finish(match, winner, if reachedLimit then "GoalLimit" else "GoldenGoal")
		return
	end

	match.State = "GoalPause"
	self:_setControlsLocked(match, true)
	self.ballService:SetActive(match, false)
	self:_teleportPlayers(match)
	self.ballService:ResetMatchBall(match)
	self.goalPositions[match.Id] = nil
	self:_broadcast(match)
	task.delay(self.config.Match.GoalResetSeconds, function()
		if match.Ended then
			return
		end
		match.State = previousState
		match.EndsAt = serverNow() + remaining
		match.GoalDebounce = false
		self:_setControlsLocked(match, false)
		self.ballService:SetActive(match, true)
		self:_broadcast(match)
	end)
end

function MatchService._onPanna(self: Service, attacker: Player, defender: Player)
	local match = self.byPlayer[attacker]
	if not match or match ~= self.byPlayer[defender] or match.Ended then
		return
	end
	if match.State ~= "Active" and match.State ~= "Overtime" then
		return
	end
	if serverNow() >= match.EndsAt then
		return
	end

	if attacker == match.Home then
		match.Score.HomePannas += 1
		match.Score.Home += self.config.Match.PannaPoints
	else
		match.Score.AwayPannas += 1
		match.Score.Away += self.config.Match.PannaPoints
	end
	self:_effect(match, {
		kind = "Panna",
		title = "PANNA!",
		text = string.format("%s nutmegged %s", attacker.DisplayName, defender.DisplayName),
	})
	self:_broadcast(match)
	local reachedLimit = match.Score.Home >= self.config.Match.GoalLimit
		or match.Score.Away >= self.config.Match.GoalLimit
	local goldenPanna = match.State == "Overtime"
		and match.GoldenGoal
		and self.config.Match.PannaPoints > 0
	if self.config.Match.PannaInstantWin or reachedLimit or goldenPanna then
		self:_finish(match, attacker, if goldenPanna then "GoldenPanna" else "Panna")
	end
end

function MatchService._finish(
	self: Service,
	match: MatchRecord,
	winner: Player?,
	reason: string,
	awardRewards: boolean?
)
	if match.Ended then
		return
	end
	match.Ended = true
	match.State = "Finished"
	match.EndsAt = serverNow()
	self.arenas:SetMatchState(match.Arena, match.Id, "Result", match.Home, match.Away)
	self:_setControlsLocked(match, true)
	self.ballService:SetActive(match, false)
	if awardRewards ~= false then
		self.dataService:RewardMatch(match.Home, match.Away, match.Id, winner, match.Score)
	end
	self:_broadcast(match)

	for _, player in { match.Home, match.Away } do
		if player.Parent then
			local won = winner == player
			local title = if reason == "Cancelled"
				then "CANCELLED"
				else if winner == nil then "DRAW" elseif won then "VICTORY" else "DEFEAT"
			self.remotes.Effect:FireClient(player, {
				kind = "Result",
				matchId = match.Id,
				arenaId = match.Arena.Id,
				matchRevision = match.Revision,
				title = title,
				text = string.format("%d - %d · %s", match.Score.Home, match.Score.Away, reason),
				won = won,
			})
		end
	end

	task.delay(self.config.Match.ResultSeconds, function()
		self:_cleanup(match)
	end)
end

function MatchService._cleanup(self: Service, match: MatchRecord)
	if self.matches[match.Id] ~= match then
		return
	end

	local wantsRematch = match.RematchVotes[match.Home] and match.RematchVotes[match.Away]
	self.ballService:DetachMatch(match)
	self.arenas:Release(match.Arena)
	self:_setControlsLocked(match, false)
	for _, player in { match.Home, match.Away } do
		self.byPlayer[player] = nil
		if player.Parent then
			player:SetAttribute("InMatch", false)
			player:SetAttribute("InRoomWaiting", false)
			player:SetAttribute("MatchId", "")
			player:SetAttribute("ArenaId", "")
			player:SetAttribute("SelectedArenaId", "")
			self.arenas:ReturnToStreet(match.Arena, player)
			self.remotes.StateUpdate:FireClient(
				player,
				{ match = false, matchRevision = match.Revision }
			)
		end
	end
	self.matches[match.Id] = nil
	self.goalPositions[match.Id] = nil

	if wantsRematch and self.onRematchReady and match.Home.Parent and match.Away.Parent then
		self.onRematchReady(match.Home, match.Away, match.Arena)
	end
	if self.onArenaReleased then
		self.onArenaReleased(match.Arena, match.Home, match.Away)
	end
end

function MatchService.RequestExit(self: Service, player: Player): boolean
	local match = self.byPlayer[player]
	if not match then
		return false
	end
	if match.Ended then
		match.RematchVotes[player] = nil
		self:_cleanup(match)
		return true
	end
	local other = opponent(match, player)
	if match.StartedAt <= 0 then
		self:_finish(match, nil, "Cancelled", false)
	else
		self:_finish(match, if other and other.Parent then other else nil, "Forfeit", false)
	end
	return true
end

function MatchService.RequestRematch(self: Service, player: Player): boolean
	local match = self.byPlayer[player]
	if not match or match.State ~= "Finished" then
		return false
	end
	match.RematchVotes[player] = true
	local other = opponent(match, player)
	if other and other.Parent then
		self.remotes.Effect:FireClient(other, {
			kind = "Message",
			matchId = match.Id,
			arenaId = match.Arena.Id,
			matchRevision = match.Revision,
			title = "REMATCH",
			text = string.format("%s wants another game.", player.DisplayName),
		})
	end
	return true
end

function MatchService.HandlePlayerRemoving(self: Service, player: Player)
	local match = self.byPlayer[player]
	if not match then
		return
	end
	if not match.Ended then
		local other = opponent(match, player)
		local now = serverNow()
		if (match.State == "Active" or match.State == "Overtime") and now >= match.EndsAt then
			local winner: Player? = nil
			if match.Score.Home > match.Score.Away then
				winner = match.Home
			elseif match.Score.Away > match.Score.Home then
				winner = match.Away
			end
			self:_finish(match, winner, if winner then "Time" else "Draw")
		elseif match.StartedAt <= 0 then
			self:_finish(match, nil, "Cancelled", false)
		else
			local playedLongEnough = now - match.StartedAt >= self.config.Match.EarlyForfeitSeconds
			self:_finish(
				match,
				if other and other.Parent then other else nil,
				if playedLongEnough then "Forfeit" else "EarlyForfeit",
				false
			)
		end
	end
end

function MatchService.HandleCharacterAdded(self: Service, player: Player, character: Model)
	local match = self.byPlayer[player]
	if not match or match.Ended then
		return
	end
	task.spawn(function()
		local root = character:WaitForChild("HumanoidRootPart", 8)
		if
			not root
			or self.byPlayer[player] ~= match
			or player.Character ~= character
			or match.Ended
		then
			return
		end
		local spawnPart = if player == match.Home
			then match.Arena.HomeSpawn
			else match.Arena.AwaySpawn
		self.arenas:TeleportToSpawn(player, spawnPart)
		self:_setControlsLocked(
			match,
			match.Ended or match.State == "Countdown" or match.State == "GoalPause"
		)
	end)
end

return MatchService
