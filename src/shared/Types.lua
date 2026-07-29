--!strict

export type MatchState = "Countdown" | "Active" | "GoalPause" | "Overtime" | "Finished"
export type RoomState = "Free" | "Waiting" | "Countdown" | "Active" | "Result"
export type TeamSide = "Home" | "Away"
export type ShotType = "Normal" | "Low" | "Chip"
export type FeintVariant = "StepOver" | "Cut" | "DragBack" | "Roulette"
export type BallControlState =
	"Free"
	| "Controlled"
	| "Contested"
	| "Shot"
	| "Flight"
	| "Bounce"
	| "Reset"
export type BallAction =
	"ChargeStart"
	| "Kick"
	| "Pass"
	| "Feint"
	| "Skill"
	| "Tackle"
	| "Shield"
	| "Trap"
	| "Dash"

export type BallActionRequest = {
	action: BallAction,
	sequence: number,
	arenaId: string,
	matchId: string,
	ballRevision: number,
	clientTime: number,
	direction: Vector3,
	moveDirection: Vector3,
	chargeAction: ("Kick" | "Pass")?,
	shotType: ShotType?,
	variant: FeintVariant?,
	lateral: number?,
	power: number?,
	active: boolean?,
}

export type ActionFeedback = {
	accepted: boolean,
	executed: boolean,
	reason: string,
	action: string,
	sequence: number,
	cooldownSeconds: number,
	revision: number,
	controllerUserId: number,
	mode: string, -- shotType / feint variant / chargeAction, if present in the request
	ballState: string,
}

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
