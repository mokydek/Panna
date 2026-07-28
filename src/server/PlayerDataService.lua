--!strict

local DataStoreService = game:GetService("DataStoreService")
local HttpService = game:GetService("HttpService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local PlayerDataService = {}
PlayerDataService.__index = PlayerDataService

type PlayerData = {
	SchemaVersion: number,
	Wins: number,
	Losses: number,
	Goals: number,
	Pannas: number,
	WinStreak: number,
	Rating: number,
	Level: number,
	XP: number,
	Coins: number,
	OwnedCosmetics: { string },
	EquippedCosmetics: { [string]: string },
	Settings: { [string]: any },
	RecentRewardIds: { string },
}

export type Service = typeof(setmetatable(
	{} :: {
		config: any,
		remotes: any,
		store: GlobalDataStore,
		profiles: { [Player]: PlayerData },
		loading: { [Player]: boolean },
		loadFailed: { [Player]: boolean },
		sessionUnsafe: { [Player]: boolean },
		saving: { [Player]: boolean },
		releaseRequested: { [Player]: boolean },
		removing: { [Player]: boolean },
		leaseIds: { [Player]: string },
		sessionId: string,
		shuttingDown: boolean,
	},
	PlayerDataService
))

local NUMERIC_FIELDS = {
	"Wins",
	"Losses",
	"Goals",
	"Pannas",
	"WinStreak",
	"Rating",
	"Level",
	"XP",
	"Coins",
}

local function round(value: number): number
	return math.floor(value + 0.5)
end

local function defaultData(config: any): PlayerData
	return {
		SchemaVersion = config.DataStore.SchemaVersion,
		Wins = 0,
		Losses = 0,
		Goals = 0,
		Pannas = 0,
		WinStreak = 0,
		Rating = config.Rewards.StartingRating,
		Level = 1,
		XP = 0,
		Coins = 0,
		OwnedCosmetics = { "DefaultBall" },
		EquippedCosmetics = { Ball = "DefaultBall" },
		Settings = {
			MusicVolume = 0.7,
			EffectsVolume = 1,
			CameraShake = true,
			LowDetail = false,
		},
		RecentRewardIds = {},
	}
end

local function stringArray(value: any, maximum: number): { string }
	local result = {}
	if type(value) ~= "table" then
		return result
	end
	for _, item in value do
		if type(item) == "string" and #item <= 80 then
			table.insert(result, item)
			if #result >= maximum then
				break
			end
		end
	end
	return result
end

local function normalize(config: any, raw: any): PlayerData
	local data = defaultData(config)
	if type(raw) ~= "table" then
		return data
	end

	for _, field in NUMERIC_FIELDS do
		local value = raw[field]
		if type(value) == "number" and value == value then
			(data :: any)[field] = math.max(0, round(value))
		end
	end

	data.SchemaVersion = config.DataStore.SchemaVersion
	data.Rating = math.clamp(data.Rating, 100, 5000)
	data.OwnedCosmetics = stringArray(raw.OwnedCosmetics, 200)
	if #data.OwnedCosmetics == 0 then
		data.OwnedCosmetics = { "DefaultBall" }
	end
	data.RecentRewardIds = stringArray(raw.RecentRewardIds, config.DataStore.RecentRewardIds)

	if type(raw.EquippedCosmetics) == "table" then
		for key, value in raw.EquippedCosmetics do
			if
				type(key) == "string"
				and type(value) == "string"
				and #key <= 30
				and #value <= 80
			then
				data.EquippedCosmetics[key] = value
			end
		end
	end

	if type(raw.Settings) == "table" then
		local settings = raw.Settings
		if type(settings.MusicVolume) == "number" then
			data.Settings.MusicVolume = math.clamp(settings.MusicVolume, 0, 1)
		end
		if type(settings.EffectsVolume) == "number" then
			data.Settings.EffectsVolume = math.clamp(settings.EffectsVolume, 0, 1)
		end
		if type(settings.CameraShake) == "boolean" then
			data.Settings.CameraShake = settings.CameraShake
		end
		if type(settings.LowDetail) == "boolean" then
			data.Settings.LowDetail = settings.LowDetail
		end
	end

	return data
end

local function getSessionLock(raw: any): (string?, number)
	if type(raw) ~= "table" or type(raw.SessionLock) ~= "table" then
		return nil, 0
	end
	local lock = raw.SessionLock
	local id = if type(lock.Id) == "string" then lock.Id else nil
	local expiresAt = if type(lock.ExpiresAt) == "number" then lock.ExpiresAt else 0
	return id, expiresAt
end

local function serialize(
	data: PlayerData,
	sessionId: string,
	leaseSeconds: number,
	releaseLock: boolean
): any
	return {
		SchemaVersion = data.SchemaVersion,
		Wins = data.Wins,
		Losses = data.Losses,
		Goals = data.Goals,
		Pannas = data.Pannas,
		WinStreak = data.WinStreak,
		Rating = data.Rating,
		Level = data.Level,
		XP = data.XP,
		Coins = data.Coins,
		OwnedCosmetics = data.OwnedCosmetics,
		EquippedCosmetics = data.EquippedCosmetics,
		Settings = data.Settings,
		RecentRewardIds = data.RecentRewardIds,
		SessionLock = if releaseLock
			then nil
			else {
				Id = sessionId,
				ExpiresAt = os.time() + leaseSeconds,
			},
	}
end

local function contains(list: { string }, value: string): boolean
	return table.find(list, value) ~= nil
end

local function calculateLevel(xp: number): number
	return math.max(1, math.floor(math.sqrt(math.max(0, xp) / 100)) + 1)
end

function PlayerDataService.new(config: any, remotes: any): Service
	local storeName = config.DataStore.Name
	if RunService:IsStudio() then
		storeName ..= "_Studio"
	end

	return setmetatable({
		config = config,
		remotes = remotes,
		store = DataStoreService:GetDataStore(storeName),
		profiles = {},
		loading = {},
		loadFailed = {},
		sessionUnsafe = {},
		saving = {},
		releaseRequested = {},
		removing = {},
		leaseIds = {},
		sessionId = if game.JobId ~= ""
			then game.JobId
			else "studio-" .. HttpService:GenerateGUID(false),
		shuttingDown = false,
	}, PlayerDataService)
end

function PlayerDataService.GetPublicStats(self: Service, player: Player): { [string]: number }
	local data = self.profiles[player] or defaultData(self.config)
	return {
		Wins = data.Wins,
		Losses = data.Losses,
		Goals = data.Goals,
		Pannas = data.Pannas,
		Coins = data.Coins,
		Level = data.Level,
		XP = data.XP,
		Rating = data.Rating,
		WinStreak = data.WinStreak,
	}
end

function PlayerDataService._syncPresentation(self: Service, player: Player)
	local data = self.profiles[player]
	if not data then
		return
	end

	local leaderstats = player:FindFirstChild("leaderstats") :: Folder?
	if not leaderstats then
		leaderstats = Instance.new("Folder")
		leaderstats.Name = "leaderstats"
		leaderstats.Parent = player
	end

	local values = {
		Wins = data.Wins,
		Rating = data.Rating,
		Coins = data.Coins,
	}
	for name, amount in values do
		local valueObject = leaderstats:FindFirstChild(name) :: IntValue?
		if not valueObject then
			valueObject = Instance.new("IntValue")
			valueObject.Name = name
			valueObject.Parent = leaderstats
		end
		valueObject.Value = amount
	end

	player:SetAttribute("Level", data.Level)
	player:SetAttribute("Rating", data.Rating)
	player:SetAttribute("Coins", data.Coins)
	self.remotes.StateUpdate:FireClient(player, { stats = self:GetPublicStats(player) })
end

function PlayerDataService.LoadPlayer(self: Service, player: Player)
	if
		self.shuttingDown
		or self.profiles[player]
		or self.loading[player]
		or self.removing[player]
	then
		return
	end
	self.loading[player] = true
	local leaseId = string.format("%s:%s", self.sessionId, HttpService:GenerateGUID(false))
	self.leaseIds[player] = leaseId

	local key = string.format("player_%d", player.UserId)
	local loaded: any = nil
	local succeeded = false
	for attempt = 1, self.config.DataStore.Retries do
		if self.shuttingDown then
			break
		end
		local acquired = false
		local ok, result = pcall(function()
			return self.store:UpdateAsync(key, function(previous: any)
				acquired = false
				local lockId, expiresAt = getSessionLock(previous)
				if lockId and lockId ~= leaseId and expiresAt > os.time() then
					return nil
				end

				acquired = true
				return serialize(
					normalize(self.config, previous),
					leaseId,
					self.config.DataStore.SessionLeaseSeconds,
					false
				)
			end)
		end)
		if ok and acquired then
			loaded = result
			succeeded = true
			break
		end
		warn(
			string.format(
				"[Panna/Data] Load attempt %d failed for %d: %s",
				attempt,
				player.UserId,
				if ok then "active session lock" else tostring(result)
			)
		)
		if attempt < self.config.DataStore.Retries then
			task.wait(self.config.DataStore.RetryDelaySeconds * attempt)
		end
	end

	self.profiles[player] = normalize(self.config, loaded)
	self.loading[player] = nil
	self.loadFailed[player] = not succeeded
	if not succeeded then
		self.leaseIds[player] = nil
	end

	-- PlayerRemoving can run while UpdateAsync is still acquiring the lease. In
	-- that case we must release the newly acquired lease instead of abandoning it
	-- until its timeout.
	if not player.Parent or self.removing[player] or self.shuttingDown then
		if succeeded then
			local releaseDeadline = os.clock() + self.config.DataStore.ShutdownTimeoutSeconds
			repeat
				self:SavePlayer(player, true)
				if self.releaseRequested[player] then
					task.wait(0.1)
				end
			until not self.releaseRequested[player] or os.clock() >= releaseDeadline
			if self.releaseRequested[player] then
				warn(
					string.format(
						"[Panna/Data] Post-load lease release failed for %d",
						player.UserId
					)
				)
			end
		end
		self.profiles[player] = nil
		self.loadFailed[player] = nil
		self.sessionUnsafe[player] = nil
		self.releaseRequested[player] = nil
		self.removing[player] = nil
		self.leaseIds[player] = nil
		return
	end

	player:SetAttribute("DataLoaded", true)
	player:SetAttribute("DataSessionFallback", not succeeded)
	self:_syncPresentation(player)
	if not succeeded then
		self.remotes.Effect:FireClient(player, {
			kind = "Message",
			title = "SESSION MODE",
			text = "Profile storage is unavailable or locked; ranked play is disabled.",
		})
	end
end

function PlayerDataService._writeOwnedProfile(
	self: Service,
	player: Player,
	data: PlayerData,
	releaseLock: boolean
): boolean
	local leaseId = self.leaseIds[player]
	if not leaseId then
		return false
	end
	local key = string.format("player_%d", player.UserId)
	for attempt = 1, self.config.DataStore.Retries do
		local wrote = false
		local alreadyReleased = false
		local ok, result = pcall(function()
			return self.store:UpdateAsync(key, function(previous: any)
				wrote = false
				alreadyReleased = false
				local lockId = getSessionLock(previous)
				if lockId ~= leaseId then
					-- A release may have committed even when the request returned an
					-- ambiguous transport error. Treat an absent lock as released, but
					-- never write stale profile data without exact ownership.
					alreadyReleased = releaseLock and lockId == nil
					return nil
				end

				wrote = true
				return serialize(
					data,
					leaseId,
					self.config.DataStore.SessionLeaseSeconds,
					releaseLock
				)
			end)
		end)
		if ok and (wrote or alreadyReleased) then
			return true
		end
		warn(
			string.format(
				"[Panna/Data] Save attempt %d failed for %d: %s",
				attempt,
				player.UserId,
				if ok then "session ownership changed" else tostring(result)
			)
		)
		if attempt < self.config.DataStore.Retries then
			task.wait(self.config.DataStore.RetryDelaySeconds * attempt)
		end
	end
	return false
end

function PlayerDataService.SavePlayer(self: Service, player: Player, releaseLock: boolean?): boolean
	local data = self.profiles[player]
	if not data then
		return true
	end
	if self.loadFailed[player] then
		if releaseLock == true then
			-- A fallback profile never acquired a lease.
			self.releaseRequested[player] = nil
			return true
		end
		return false
	end
	if releaseLock == true then
		self.releaseRequested[player] = true
	end

	local waitDeadline = os.clock() + self.config.DataStore.SaveLockWaitSeconds
	while self.saving[player] and os.clock() < waitDeadline do
		task.wait(0.05)
	end
	if self.saving[player] then
		warn(
			string.format(
				"[Panna/Data] Timed out waiting for an earlier save for %d",
				player.UserId
			)
		)
		return false
	end
	if releaseLock == true and not self.releaseRequested[player] then
		-- The in-flight worker observed our request and already released it.
		return true
	end
	self.saving[player] = true

	local shouldRelease = self.releaseRequested[player] == true
	local succeeded = self:_writeOwnedProfile(player, data, shouldRelease)
	-- If PlayerRemoving requested a release while an autosave was in flight,
	-- serialize one final exact-owner release before the worker exits.
	if not shouldRelease and self.releaseRequested[player] then
		shouldRelease = true
		succeeded = self:_writeOwnedProfile(player, data, true)
	end
	if succeeded and shouldRelease then
		self.releaseRequested[player] = nil
	end
	self.saving[player] = nil
	if not shouldRelease and player.Parent then
		if succeeded then
			if self.sessionUnsafe[player] then
				self.sessionUnsafe[player] = nil
				player:SetAttribute("DataSessionFallback", false)
				self.remotes.Effect:FireClient(player, {
					kind = "Message",
					title = "PROFILE RESTORED",
					text = "Saving is available again; ranked matchmaking is enabled.",
				})
			end
		elseif not self.sessionUnsafe[player] then
			self.sessionUnsafe[player] = true
			player:SetAttribute("DataSessionFallback", true)
			self.remotes.Effect:FireClient(player, {
				kind = "Message",
				title = "PROFILE UNSAFE",
				text = "Saving could not be confirmed; rewards and ranked matchmaking are disabled.",
			})
		end
	end
	return succeeded
end

function PlayerDataService._addRewardId(self: Service, data: PlayerData, matchId: string)
	table.insert(data.RecentRewardIds, 1, matchId)
	while #data.RecentRewardIds > self.config.DataStore.RecentRewardIds do
		table.remove(data.RecentRewardIds)
	end
end

function PlayerDataService.RewardMatch(
	self: Service,
	home: Player,
	away: Player,
	matchId: string,
	winner: Player?,
	score: { [string]: number }
): boolean
	local homeData = self.profiles[home]
	local awayData = self.profiles[away]
	if
		not homeData
		or not awayData
		or self.loadFailed[home]
		or self.loadFailed[away]
		or self.sessionUnsafe[home]
		or self.sessionUnsafe[away]
	then
		return false
	end
	if
		contains(homeData.RecentRewardIds, matchId) or contains(awayData.RecentRewardIds, matchId)
	then
		return false
	end

	local expectedHome = 1 / (1 + 10 ^ ((awayData.Rating - homeData.Rating) / 400))
	local actualHome = if winner == home then 1 elseif winner == away then 0 else 0.5
	local homeDelta = round(self.config.Rewards.RatingK * (actualHome - expectedHome))
	local awayDelta = -homeDelta

	local function apply(
		player: Player,
		data: PlayerData,
		won: boolean,
		goals: number,
		pannas: number,
		ratingDelta: number
	)
		data.Goals += math.max(0, goals)
		data.Pannas += math.max(0, pannas)
		if winner == nil then
			data.WinStreak = 0
		elseif won then
			data.Wins += 1
			data.WinStreak += 1
		else
			data.Losses += 1
			data.WinStreak = 0
		end

		local winCoins = if won then self.config.Rewards.WinCoins else 0
		local winXP = if won then self.config.Rewards.WinXP else 0
		data.Coins += self.config.Rewards.ParticipationCoins + winCoins + goals * self.config.Rewards.GoalCoins + pannas * self.config.Rewards.PannaCoins
		data.XP += self.config.Rewards.ParticipationXP + winXP
		data.Level = calculateLevel(data.XP)
		data.Rating = math.clamp(data.Rating + ratingDelta, 100, 5000)
		self:_addRewardId(data, matchId)
		self:_syncPresentation(player)
	end

	apply(
		home,
		homeData,
		winner == home,
		score.HomeGoals or score.Home or 0,
		score.HomePannas or 0,
		homeDelta
	)
	apply(
		away,
		awayData,
		winner == away,
		score.AwayGoals or score.Away or 0,
		score.AwayPannas or 0,
		awayDelta
	)
	return true
end

function PlayerDataService.RemovePlayer(self: Service, player: Player)
	self.removing[player] = true
	self.releaseRequested[player] = true
	if self.loading[player] then
		-- LoadPlayer owns cleanup and will release any lease it acquires.
		return
	end

	self:SavePlayer(player, true)
	local function clearWhenIdle()
		local deadline = os.clock() + self.config.DataStore.ShutdownTimeoutSeconds
		repeat
			while self.saving[player] and os.clock() < deadline do
				task.wait(0.05)
			end
			if self.releaseRequested[player] and os.clock() < deadline then
				self:SavePlayer(player, true)
				if self.releaseRequested[player] then
					task.wait(0.1)
				end
			end
		until not self.releaseRequested[player] or os.clock() >= deadline
		if self.releaseRequested[player] then
			warn(string.format("[Panna/Data] Final lease release failed for %d", player.UserId))
		end
		self.profiles[player] = nil
		self.loading[player] = nil
		self.loadFailed[player] = nil
		self.sessionUnsafe[player] = nil
		self.releaseRequested[player] = nil
		self.removing[player] = nil
		self.leaseIds[player] = nil
	end
	if self.saving[player] then
		task.spawn(clearWhenIdle)
	else
		clearWhenIdle()
	end
end

function PlayerDataService.StartAutosave(self: Service)
	task.spawn(function()
		while not self.shuttingDown do
			task.wait(self.config.DataStore.AutosaveSeconds)
			if self.shuttingDown then
				break
			end
			for player in self.profiles do
				task.spawn(function()
					self:SavePlayer(player)
				end)
			end
		end
	end)
end

function PlayerDataService.Shutdown(self: Service)
	self.shuttingDown = true
	local deadline = os.clock() + self.config.DataStore.ShutdownTimeoutSeconds
	while next(self.loading) ~= nil and os.clock() < deadline do
		task.wait(0.05)
	end

	local remaining = 0
	for player in self.profiles do
		remaining += 1
		task.spawn(function()
			self:SavePlayer(player, true)
			remaining -= 1
		end)
	end

	while (remaining > 0 or next(self.saving) ~= nil) and os.clock() < deadline do
		task.wait(0.1)
	end
end

function PlayerDataService.InitPlayers(self: Service)
	Players.PlayerAdded:Connect(function(player: Player)
		task.spawn(function()
			self:LoadPlayer(player)
		end)
	end)

	for _, player in Players:GetPlayers() do
		task.spawn(function()
			self:LoadPlayer(player)
		end)
	end

	self:StartAutosave()
end

return PlayerDataService
