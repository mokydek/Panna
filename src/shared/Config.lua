--!strict

local Config = {
	Version = "0.1.0-alpha",

	World = {
		RootName = "PannaWorld",
		LobbyOrigin = Vector3.new(0, 0, -115),
		LobbySpawn = CFrame.new(0, 4, -118),
		ArenaPositions = {
			CFrame.new(-72, 0, 20),
			CFrame.new(72, 0, 20),
		},
		ArenaWidth = 48,
		ArenaLength = 76,
		FenceHeight = 16,
		GoalWidth = 16,
		GoalHeight = 8,
		GoalDepth = 5,
	},

	Match = {
		MinimumPlayers = 2,
		CountdownSeconds = 4,
		DurationSeconds = 150,
		OvertimeSeconds = 45,
		GoalLimit = 5,
		GoalResetSeconds = 2.5,
		ResultSeconds = 6,
		EarlyForfeitSeconds = 15,
		GoldenGoalInOvertime = true,
		PannaPoints = 1,
		PannaInstantWin = false,
	},

	Ball = {
		Radius = 1.25,
		Density = 0.65,
		Friction = 0.45,
		Elasticity = 0.35,
		ControlRadius = 6.5,
		InteractionRadius = 8,
		DribbleDistance = 3.2,
		DribbleResponsiveness = 11,
		DribbleAcceleration = 280,
		MaxSpeed = 94,
		KickSpeedMin = 38,
		KickSpeedMax = 82,
		PassSpeed = 48,
		LiftMin = 3,
		LiftMax = 15,
		FreeFlightSeconds = 0.42,
		ResetBelowY = -18,
	},

	Actions = {
		KickCooldown = 0.28,
		PassCooldown = 0.35,
		TackleCooldown = 1.2,
		SkillCooldown = 2.0,
		DashCooldown = 3.0,
		TackleRadius = 7,
		SkillRadius = 8,
		DashSpeed = 44,
		DashSeconds = 0.22,
	},

	Security = {
		RemoteBurst = 12,
		RemoteRefillPerSecond = 8,
		MaxDirectionMagnitudeError = 0.12,
		MaxCharacterDistanceFromArena = 32,
	},

	Rewards = {
		ParticipationCoins = 15,
		WinCoins = 45,
		GoalCoins = 4,
		PannaCoins = 10,
		ParticipationXP = 25,
		WinXP = 60,
		StartingRating = 1000,
		RatingK = 24,
	},

	DataStore = {
		Name = "PannaPlayerData_v1",
		SchemaVersion = 1,
		Retries = 3,
		RetryDelaySeconds = 1.5,
		AutosaveSeconds = 90,
		RecentRewardIds = 24,
		SessionLeaseSeconds = 180,
		SaveLockWaitSeconds = 10,
		ShutdownTimeoutSeconds = 25,
	},
}

return table.freeze(Config)
