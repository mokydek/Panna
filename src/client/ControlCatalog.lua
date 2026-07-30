--!strict

export type ActionDefinition = {
	bindingName: string,
	title: string,
	keyboard: string,
	gamepad: string,
	touchTitle: string,
	inputs: { EnumItem },
}

export type GuideEntry = {
	id: string,
	title: string,
	keyboard: string,
	gamepad: string,
	touch: string,
	description: string,
}

local actionOrder = table.freeze({ "Kick", "Pass", "Feint", "Skill", "Tackle", "Shield", "Dash" })
local touchOrder = table.freeze({
	"Kick",
	"Pass",
	"Feint",
	"Skill",
	"Tackle",
	"Shield",
	"Dash",
	"ShotMode",
})

local actions = {
	Kick = table.freeze({
		bindingName = "Panna_Kick",
		title = "SHOT - NORMAL",
		keyboard = "LMB: SHOT / STEAL",
		gamepad = "R2 - DPAD UP",
		touchTitle = "SHOT",
		inputs = table.freeze({ Enum.UserInputType.MouseButton1, Enum.KeyCode.ButtonR2 }),
	}),
	Pass = table.freeze({
		bindingName = "Panna_Pass",
		title = "LOW PASS - HOLD",
		keyboard = "RMB",
		gamepad = "X",
		touchTitle = "PASS",
		inputs = table.freeze({ Enum.UserInputType.MouseButton2, Enum.KeyCode.ButtonX }),
	}),
	Feint = table.freeze({
		bindingName = "Panna_Feint",
		title = "CLOSE CONTROL",
		keyboard = "Q",
		gamepad = "R1",
		touchTitle = "DRIBBLE",
		inputs = table.freeze({ Enum.KeyCode.Q, Enum.KeyCode.V, Enum.KeyCode.ButtonR1 }),
	}),
	Tackle = table.freeze({
		bindingName = "Panna_Tackle",
		title = "TACKLE",
		keyboard = "LMB / E",
		gamepad = "B",
		touchTitle = "TACKLE",
		inputs = table.freeze({ Enum.KeyCode.E, Enum.KeyCode.F, Enum.KeyCode.ButtonB }),
	}),
	Skill = table.freeze({
		bindingName = "Panna_Skill",
		title = "PANNA",
		keyboard = "R",
		gamepad = "Y",
		touchTitle = "PANNA",
		inputs = table.freeze({ Enum.KeyCode.R, Enum.KeyCode.ButtonY }),
	}),
	Shield = table.freeze({
		bindingName = "Panna_Shield",
		title = "SHIELD / TRAP",
		keyboard = "HOLD C",
		gamepad = "HOLD L2",
		touchTitle = "SHIELD",
		inputs = table.freeze({ Enum.KeyCode.C, Enum.KeyCode.ButtonL2 }),
	}),
	Dash = table.freeze({
		bindingName = "Panna_Dash",
		title = "DASH",
		keyboard = "X",
		gamepad = "L1",
		touchTitle = "DASH",
		inputs = table.freeze({ Enum.KeyCode.X, Enum.KeyCode.ButtonL1 }),
	}),
	ShotMode = table.freeze({
		bindingName = "Panna_ShotMode",
		title = "SHOT TYPE",
		keyboard = "Z",
		gamepad = "DPAD UP",
		touchTitle = "SHOT MODE",
		inputs = table.freeze({ Enum.KeyCode.Z, Enum.KeyCode.DPadUp }),
	}),
} :: { [string]: ActionDefinition }
table.freeze(actions)

local bindings = {}
local touchTitles = {}
for action, definition in actions do
	bindings[action] = definition.bindingName
	touchTitles[action] = definition.touchTitle
end

local guideEntries = table.freeze({
	table.freeze({
		id = "BallControl",
		title = "BALL CONTROL",
		keyboard = "WASD + TURN",
		gamepad = "LEFT STICK",
		touch = "THUMBSTICK",
		description = "Approach a slow free ball. Move or turn to keep it close in front; control is automatic.",
	}),
	table.freeze({
		id = "Kick",
		title = "SHOT",
		keyboard = "WITH BALL: HOLD / RELEASE LMB",
		gamepad = "HOLD / RELEASE R2",
		touch = "HOLD / RELEASE SHOT",
		description = "With possession, hold for power and aim with the camera. Plausible goal-facing shots get a small server assist; move sideways while releasing to add curve.",
	}),
	table.freeze({
		id = "ShotMode",
		title = "SHOT TYPE",
		keyboard = "Z",
		gamepad = "DPAD UP",
		touch = "SHOT NORMAL / LOW / CHIP",
		description = "Cycle Normal, Low and Chip before releasing the shot.",
	}),
	table.freeze({
		id = "Pass",
		title = "LOW PASS",
		keyboard = "HOLD / RELEASE RMB",
		gamepad = "HOLD / RELEASE X",
		touch = "HOLD / RELEASE PASS",
		description = "Charge a controlled low pass into space. While running, it bends slightly toward your trusted movement line and can be buffered before first touch.",
	}),
	table.freeze({
		id = "Feint",
		title = "FEINT / CLOSE CONTROL",
		keyboard = "Q",
		gamepad = "R1",
		touch = "DRIBBLE",
		description = "With the ball, your movement input selects StepOver, Cut, DragBack or Roulette. The ball brakes into the variant path and is protected from tackles only during the short move.",
	}),
	table.freeze({
		id = "Skill",
		title = "PANNA",
		keyboard = "R",
		gamepad = "Y",
		touch = "PANNA",
		description = "With the ball, face a nearby defender who is set toward you; a valid attempt is guided through the leg gate.",
	}),
	table.freeze({
		id = "Tackle",
		title = "TACKLE",
		keyboard = "LMB WITHOUT BALL / E",
		gamepad = "B",
		touch = "TACKLE",
		description = "When the opponent controls the ball, LMB becomes Tackle: win possession directly without kicking the ball. E, gamepad B and the touch button do the same. Shield or an active Feint blocks it.",
	}),
	table.freeze({
		id = "Shield",
		title = "SHIELD / FIRST TOUCH",
		keyboard = "C: TAP TRAP / HOLD SHIELD",
		gamepad = "L2: TAP TRAP / HOLD SHIELD",
		touch = "TAP TRAP / HOLD SHIELD",
		description = "Near a free or incoming ball, press once to buffer a full trap; automatic touches preserve a little momentum. With possession, hold to shield.",
	}),
	table.freeze({
		id = "Dash",
		title = "DASH",
		keyboard = "X",
		gamepad = "L1",
		touch = "DASH",
		description = "Burst in your movement direction. Possession is not required; wait for the cooldown.",
	}),
})

return table.freeze({
	ActionOrder = actionOrder,
	TouchOrder = touchOrder,
	ShotTypes = table.freeze({ "Normal", "Low", "Chip" }),
	Actions = actions,
	Bindings = table.freeze(bindings),
	TouchTitles = table.freeze(touchTitles),
	GuideEntries = guideEntries,
})
