--!strict

-- Asset-free additive football poses. The returned CFrames are visual offsets for
-- normalized joints; they never describe a character/root world-space transform.

export type Pose = { [string]: CFrame }

local ProceduralPoseCatalog = {}

local IDENTITY = CFrame.new()
local SUPPORTED_ACTIONS = table.freeze({
	"Charge",
	"Kick",
	"Pass",
	"Trap",
	"Shield",
	"Dash",
	"Tackle",
	"Skill",
	"Feint",
})
local FEINT_VARIANTS = table.freeze({ "StepOver", "Cut", "DragBack", "Roulette" })
local VALID_ACTIONS: { [string]: boolean } = {}
local VALID_FEINTS: { [string]: boolean } = {}

for _, action in SUPPORTED_ACTIONS do
	VALID_ACTIONS[action] = true
end
for _, variant in FEINT_VARIANTS do
	VALID_FEINTS[variant] = true
end

local DEFAULT_DURATIONS = table.freeze({
	Charge = 1.1,
	Kick = 0.44,
	Pass = 0.38,
	Trap = 0.34,
	Shield = 0.18,
	Dash = 0.34,
	Tackle = 0.42,
	Skill = 0.4,
	Feint = 0.42,
})

local FEINT_DURATIONS = table.freeze({
	StepOver = 0.42,
	Cut = 0.34,
	DragBack = 0.48,
	Roulette = 0.58,
})

local function finiteNumber(value: any): boolean
	return typeof(value) == "number" and value == value and math.abs(value) < math.huge
end

local function smoothstep(value: number): number
	local t = math.clamp(value, 0, 1)
	return t * t * (3 - 2 * t)
end

local function transientWeight(progress: number): number
	local blendIn = smoothstep(progress / 0.16)
	local blendOut = smoothstep((1 - progress) / 0.24)
	return math.min(blendIn, blendOut)
end

local function scaled(transform: CFrame, weight: number): CFrame
	return IDENTITY:Lerp(transform, math.clamp(weight, 0, 1))
end

local function offset(x: number, y: number, z: number, rx: number, ry: number, rz: number): CFrame
	return CFrame.new(x, y, z) * CFrame.Angles(math.rad(rx), math.rad(ry), math.rad(rz))
end

local function setPose(
	pose: Pose,
	joint: string,
	weight: number,
	x: number,
	y: number,
	z: number,
	rx: number,
	ry: number,
	rz: number
)
	pose[joint] = scaled(offset(x, y, z, rx, ry, rz), weight)
end

local function legNames(side: number): (string, string, string, string, string, string)
	if side < 0 then
		return "LeftHip", "LeftKnee", "LeftAnkle", "RightHip", "RightKnee", "RightAnkle"
	end
	return "RightHip", "RightKnee", "RightAnkle", "LeftHip", "LeftKnee", "LeftAnkle"
end

local function sampleCharge(mode: string, progress: number, power: number, side: number): Pose
	local pose: Pose = {}
	local weight = smoothstep(progress) * (0.72 + power * 0.28)
	local kickHip, kickKnee, kickAnkle, plantHip, plantKnee = legNames(side)
	local pass = mode == "Pass"
	local chip = mode == "Chip"
	local lean = if chip then -8 else if pass then 4 else 8
	setPose(pose, "Root", weight, 0, -0.02, 0, lean * 0.35, -7 * side, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, lean, -11 * side, -4 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, -9, 0, -16)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, 12, 0, 18)
	setPose(
		pose,
		kickHip,
		weight,
		0,
		0,
		0,
		if pass then 18 else 30,
		if pass then 26 * side else 0,
		4 * side
	)
	setPose(pose, kickKnee, weight, 0, 0, 0, if pass then -22 else -36, 0, 0)
	setPose(pose, kickAnkle, weight, 0, 0, 0, 10, if pass then 34 * side else 0, 0)
	setPose(pose, plantHip, weight, 0, -0.02, 0, -8, -4 * side, -2 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -12, 0, 0)
	return pose
end

local function sampleKick(mode: string, progress: number, power: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local kickHip, kickKnee, kickAnkle, plantHip, plantKnee = legNames(side)
	local contact = smoothstep(math.clamp((progress - 0.08) / 0.42, 0, 1))
	local follow = smoothstep(math.clamp((progress - 0.46) / 0.34, 0, 1))
	local chip = mode == "Chip"
	local low = mode == "Low"
	local swing = (if chip then 44 else 34)
		- contact * (if chip then 92 else if low then 105 else 112)
	swing += follow * (if chip then 20 else 30)
	local torsoPitch = if chip then -14 else if low then 13 else 7
	setPose(pose, "Root", weight, 0, -0.03, 0, torsoPitch * 0.35, 8 * side * contact, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, torsoPitch, 14 * side * contact, 6 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, 18 * contact, 0, -24)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -22 * contact, 0, 24)
	setPose(pose, kickHip, weight, 0, 0, 0, swing * (0.82 + power * 0.18), 3 * side, 4 * side)
	setPose(pose, kickKnee, weight, 0, 0, 0, -42 + contact * 58, 0, 0)
	setPose(pose, kickAnkle, weight, 0, 0, 0, if chip then -22 else 18, 0, 0)
	setPose(pose, plantHip, weight, 0, -0.04, 0, -8, -8 * side, -4 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -18, 0, 0)
	return pose
end

local function samplePass(progress: number, power: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local kickHip, kickKnee, kickAnkle, plantHip, plantKnee = legNames(side)
	local contact = smoothstep(math.clamp((progress - 0.08) / 0.4, 0, 1))
	local swing = 18 - contact * (56 + 14 * power)
	setPose(pose, "Root", weight, 0, -0.02, 0, 2, 12 * side, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, 4, 17 * side, 7 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, 8, 0, -18)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -10, 0, 18)
	setPose(pose, kickHip, weight, 0, 0, 0, swing, 38 * side, 6 * side)
	setPose(pose, kickKnee, weight, 0, 0, 0, -24 + contact * 27, 0, 0)
	setPose(pose, kickAnkle, weight, 0, 0, 0, 5, 42 * side, 0)
	setPose(pose, plantHip, weight, 0, -0.03, 0, -6, -6 * side, -3 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -15, 0, 0)
	return pose
end

local function sampleTrap(progress: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local trapHip, trapKnee, trapAnkle, plantHip, plantKnee = legNames(side)
	local settle = math.sin(math.clamp(progress, 0, 1) * math.pi)
	setPose(pose, "Root", weight, 0, -0.04 * settle, 0, 4, -5 * side, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, 8, -8 * side, 3 * side)
	setPose(pose, trapHip, weight, 0, 0, -0.04 * settle, -22 * settle, 12 * side, 3 * side)
	setPose(pose, trapKnee, weight, 0, 0, 0, -38 * settle, 0, 0)
	setPose(pose, trapAnkle, weight, 0, 0, 0, 24 * settle, 0, 0)
	setPose(pose, plantHip, weight, 0, -0.03, 0, -8, 0, -3 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -17, 0, 0)
	return pose
end

local function sampleShield(progress: number, side: number): Pose
	local pose: Pose = {}
	local weight = smoothstep(progress)
	setPose(pose, "Root", weight, 0, -0.07, 0, 5, 0, -7 * side)
	setPose(pose, "Waist", weight, 0, 0, 0, 8, 10 * side, -13 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, -8, 0, -34)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -8, 0, 34)
	setPose(pose, "LeftHip", weight, 0, -0.025, 0, -7, -8, 4)
	setPose(pose, "RightHip", weight, 0, -0.025, 0, -7, 8, -4)
	setPose(pose, "LeftKnee", weight, 0, 0, 0, -18, 0, 0)
	setPose(pose, "RightKnee", weight, 0, 0, 0, -18, 0, 0)
	return pose
end

local function sampleDash(progress: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local stride = math.sin(progress * math.pi)
	setPose(pose, "Root", weight, 0, -0.05 * stride, -0.03 * stride, 13 * stride, 0, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, 17 * stride, 0, 3 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, 38 * stride, 0, -8)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -42 * stride, 0, 8)
	setPose(pose, "LeftHip", weight, 0, 0, 0, -32 * stride, 0, 0)
	setPose(pose, "RightHip", weight, 0, 0, 0, 38 * stride, 0, 0)
	setPose(pose, "LeftKnee", weight, 0, 0, 0, -18 * stride, 0, 0)
	setPose(pose, "RightKnee", weight, 0, 0, 0, -42 * stride, 0, 0)
	return pose
end

local function sampleTackle(progress: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local lunge = math.sin(progress * math.pi)
	local tackleHip, tackleKnee, tackleAnkle, plantHip, plantKnee = legNames(side)
	setPose(pose, "Root", weight, 0, -0.1 * lunge, -0.04 * lunge, 14 * lunge, 0, -6 * side)
	setPose(pose, "Waist", weight, 0, 0, 0, 21 * lunge, 8 * side, -9 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, -24 * lunge, 0, -24)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -24 * lunge, 0, 24)
	setPose(pose, tackleHip, weight, 0, 0, -0.04 * lunge, -57 * lunge, 5 * side, 5 * side)
	setPose(pose, tackleKnee, weight, 0, 0, 0, 24 * lunge, 0, 0)
	setPose(pose, tackleAnkle, weight, 0, 0, 0, -18 * lunge, 0, 0)
	setPose(pose, plantHip, weight, 0, -0.05 * lunge, 0, 25 * lunge, 0, -3 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -48 * lunge, 0, 0)
	return pose
end

local function sampleSkill(progress: number, power: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local poke = math.sin(math.clamp(progress / 0.72, 0, 1) * math.pi)
	local skillHip, skillKnee, skillAnkle, plantHip, plantKnee = legNames(side)
	setPose(pose, "Root", weight, 0, -0.04, 0, 7, 5 * side, 0)
	setPose(pose, "Waist", weight, 0, 0, 0, 11, 9 * side, 4 * side)
	setPose(pose, "LeftShoulder", weight, 0, 0, 0, 12 * poke, 0, -19)
	setPose(pose, "RightShoulder", weight, 0, 0, 0, -14 * poke, 0, 19)
	setPose(
		pose,
		skillHip,
		weight,
		0,
		0,
		-0.035 * poke,
		-45 * poke * (0.85 + power * 0.15),
		0,
		3 * side
	)
	setPose(pose, skillKnee, weight, 0, 0, 0, 18 * poke, 0, 0)
	setPose(pose, skillAnkle, weight, 0, 0, 0, -28 * poke, 0, 0)
	setPose(pose, plantHip, weight, 0, -0.03, 0, -7, 0, -2 * side)
	setPose(pose, plantKnee, weight, 0, 0, 0, -15, 0, 0)
	return pose
end

local function sampleFeint(variant: string, progress: number, side: number): Pose
	local pose: Pose = {}
	local weight = transientWeight(progress)
	local wave = math.sin(progress * math.pi)
	local full = smoothstep(progress)
	local leadHip, leadKnee, leadAnkle, plantHip, plantKnee = legNames(side)

	if variant == "Cut" then
		setPose(
			pose,
			"Root",
			weight,
			0.06 * side * wave,
			-0.04,
			0,
			8,
			-18 * side * full,
			-13 * side
		)
		setPose(pose, "Waist", weight, 0, 0, 0, 11, -25 * side * full, -16 * side)
		setPose(pose, leadHip, weight, 0, 0, 0, -33 * wave, 21 * side, 9 * side)
		setPose(pose, leadKnee, weight, 0, 0, 0, -34 * wave, 0, 0)
		setPose(pose, leadAnkle, weight, 0, 0, 0, 17 * wave, 22 * side, 0)
		setPose(pose, plantHip, weight, 0, -0.04, 0, 12 * wave, -8 * side, -8 * side)
		setPose(pose, plantKnee, weight, 0, 0, 0, -27 * wave, 0, 0)
	elseif variant == "DragBack" then
		setPose(pose, "Root", weight, 0, -0.05 * wave, 0.03 * full, -5, 7 * side, 0)
		setPose(pose, "Waist", weight, 0, 0, 0, 5, 12 * side, 5 * side)
		setPose(pose, leadHip, weight, 0, 0, 0, -42 * wave, 0, 5 * side)
		setPose(pose, leadKnee, weight, 0, 0, 0, -51 * wave, 0, 0)
		setPose(pose, leadAnkle, weight, 0, 0, 0, 32 * wave, 0, 0)
		setPose(pose, plantHip, weight, 0, -0.04, 0, 9 * wave, 0, -4 * side)
		setPose(pose, plantKnee, weight, 0, 0, 0, -24 * wave, 0, 0)
	elseif variant == "Roulette" then
		local turn = 175 * full * side
		setPose(pose, "Root", weight, 0, -0.05 * wave, 0, 4, turn * 0.42, 0)
		setPose(pose, "Waist", weight, 0, 0, 0, 7, turn * 0.58, 8 * side * wave)
		setPose(pose, "LeftShoulder", weight, 0, 0, 0, 0, 0, -31 * wave)
		setPose(pose, "RightShoulder", weight, 0, 0, 0, 0, 0, 31 * wave)
		setPose(pose, "LeftHip", weight, 0, 0, 0, 24 * math.sin(progress * math.pi * 2), 0, 6)
		setPose(pose, "RightHip", weight, 0, 0, 0, -24 * math.sin(progress * math.pi * 2), 0, -6)
		setPose(pose, "LeftKnee", weight, 0, 0, 0, -24 * wave, 0, 0)
		setPose(pose, "RightKnee", weight, 0, 0, 0, -24 * wave, 0, 0)
	else
		local circle = math.sin(progress * math.pi * 2)
		setPose(pose, "Root", weight, 0, -0.03 * wave, 0, 5, -8 * side * wave, 0)
		setPose(pose, "Waist", weight, 0, 0, 0, 8, -13 * side * wave, -5 * side)
		setPose(
			pose,
			leadHip,
			weight,
			0,
			0,
			-0.035 * wave,
			-25 * wave,
			24 * side * circle,
			12 * side * wave
		)
		setPose(pose, leadKnee, weight, 0, 0, 0, -45 * wave, 0, 0)
		setPose(pose, leadAnkle, weight, 0, 0, 0, 20 * wave, 20 * side * circle, 0)
		setPose(pose, plantHip, weight, 0, -0.03, 0, 7 * wave, 0, -4 * side)
		setPose(pose, plantKnee, weight, 0, 0, 0, -18 * wave, 0, 0)
	end

	return pose
end

function ProceduralPoseCatalog.IsSupported(action: any, mode: any?): boolean
	if typeof(action) ~= "string" then
		return false
	end
	local normalizedAction = if action == "ChargeStart" then "Charge" else action
	if not VALID_ACTIONS[normalizedAction] then
		return false
	end
	return normalizedAction ~= "Feint" or typeof(mode) ~= "string" or VALID_FEINTS[mode] == true
end

function ProceduralPoseCatalog.GetDuration(action: string, mode: string?): number
	local normalizedAction = if action == "ChargeStart" then "Charge" else action
	if normalizedAction == "Charge" and mode == "Pass" then
		return 0.9
	elseif normalizedAction == "Feint" and mode and FEINT_DURATIONS[mode] then
		return FEINT_DURATIONS[mode]
	elseif normalizedAction == "Kick" and mode == "Chip" then
		return 0.5
	end
	return DEFAULT_DURATIONS[normalizedAction] or 0.4
end

function ProceduralPoseCatalog.IsHold(action: string): boolean
	return action == "Charge" or action == "ChargeStart" or action == "Shield"
end

function ProceduralPoseCatalog.Sample(
	action: string,
	mode: string?,
	elapsed: number,
	duration: number?,
	power: number?,
	lateral: number?
): Pose
	local normalizedAction = if action == "ChargeStart" then "Charge" else action
	if not ProceduralPoseCatalog.IsSupported(normalizedAction, mode) then
		return {}
	end
	local resolvedDuration = if finiteNumber(duration) and (duration :: number) > 0
		then duration :: number
		else ProceduralPoseCatalog.GetDuration(normalizedAction, mode)
	local safeElapsed = if finiteNumber(elapsed) then math.max(0, elapsed) else 0
	local progress = math.clamp(safeElapsed / math.max(0.01, resolvedDuration), 0, 1)
	local safePower = if finiteNumber(power) then math.clamp(power :: number, 0, 1) else 0.65
	local safeLateral = if finiteNumber(lateral) then math.clamp(lateral :: number, -1, 1) else 1
	local side = if safeLateral < -0.05 then -1 else 1
	local resolvedMode = if typeof(mode) == "string" then mode else ""

	if normalizedAction == "Charge" then
		return sampleCharge(resolvedMode, progress, safePower, side)
	elseif normalizedAction == "Kick" then
		return sampleKick(resolvedMode, progress, safePower, side)
	elseif normalizedAction == "Pass" then
		return samplePass(progress, safePower, side)
	elseif normalizedAction == "Trap" then
		return sampleTrap(progress, side)
	elseif normalizedAction == "Shield" then
		return sampleShield(progress, side)
	elseif normalizedAction == "Dash" then
		return sampleDash(progress, side)
	elseif normalizedAction == "Tackle" then
		return sampleTackle(progress, side)
	elseif normalizedAction == "Skill" then
		return sampleSkill(progress, safePower, side)
	end
	return sampleFeint(
		if VALID_FEINTS[resolvedMode] then resolvedMode else "StepOver",
		progress,
		side
	)
end

ProceduralPoseCatalog.SupportedActions = SUPPORTED_ACTIONS
ProceduralPoseCatalog.FeintVariants = FEINT_VARIANTS
ProceduralPoseCatalog.NormalizedJoints = table.freeze({
	"Root",
	"Waist",
	"Neck",
	"LeftShoulder",
	"RightShoulder",
	"LeftHip",
	"RightHip",
	"LeftKnee",
	"RightKnee",
	"LeftAnkle",
	"RightAnkle",
})

return table.freeze(ProceduralPoseCatalog)
