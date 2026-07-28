--!strict

export type MatchState = "Countdown" | "Active" | "GoalPause" | "Overtime" | "Finished"
export type TeamSide = "Home" | "Away"

export type PlayerStats = {
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

export type Score = {
	Home: number,
	Away: number,
	HomeGoals: number,
	AwayGoals: number,
	HomePannas: number,
	AwayPannas: number,
}

export type MatchRecord = {
	Id: string,
	Arena: Arena,
	Home: Player,
	Away: Player,
	State: MatchState,
	Score: Score,
	StartedAt: number,
	EndsAt: number,
	GoldenGoal: boolean,
	Ended: boolean,
}

return table.freeze({})
