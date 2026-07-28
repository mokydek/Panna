--!strict

local PannaDetector = {}
PannaDetector.__index = PannaDetector

type Candidate = {
	attacker: Player,
	defender: Player,
	defenderCharacter: Model,
	ball: BasePart,
	planePoint: Vector3,
	planeNormal: Vector3,
	gateRadius: number,
	gateMinimumY: number,
	gateMaximumY: number,
	startDistance: number,
	previousPosition: Vector3,
	previousDistance: number,
	startedAt: number,
	crossedAt: number?,
}

export type Detector = typeof(setmetatable(
	{} :: {
		candidates: { Candidate },
		onSuccess: (Player, Player) -> (),
	},
	PannaDetector
))

local function getRoot(player: Player): BasePart?
	local character = player.Character
	local root = if character then character:FindFirstChild("HumanoidRootPart") else nil
	return if root and root:IsA("BasePart") then root else nil
end

local function getLegGate(defender: Player): (Vector3?, number)
	local character = defender.Character
	if not character then
		return nil, 0
	end

	local left = character:FindFirstChild("LeftFoot") or character:FindFirstChild("Left Leg")
	local right = character:FindFirstChild("RightFoot") or character:FindFirstChild("Right Leg")
	if left and left:IsA("BasePart") and right and right:IsA("BasePart") then
		local middle = (left.Position + right.Position) * 0.5
		return middle, math.clamp((left.Position - right.Position).Magnitude * 0.65, 1.25, 2.5)
	end

	local root = getRoot(defender)
	return if root then root.Position - Vector3.new(0, 2.3, 0) else nil, 1.6
end

local function horizontalLook(root: BasePart): Vector3?
	local look = root.CFrame.LookVector
	local horizontal = Vector3.new(look.X, 0, look.Z)
	if horizontal.Magnitude < 0.05 then
		return nil
	end
	return horizontal.Unit
end

function PannaDetector.new(onSuccess: (Player, Player) -> ()): Detector
	return setmetatable({
		candidates = {},
		onSuccess = onSuccess,
	}, PannaDetector)
end

function PannaDetector.Begin(
	self: Detector,
	attacker: Player,
	defender: Player,
	ball: BasePart
): boolean
	local defenderRoot = getRoot(defender)
	if not defenderRoot then
		return false
	end

	local gatePosition, gateRadius = getLegGate(defender)
	local planeNormal = horizontalLook(defenderRoot)
	if not gatePosition or not planeNormal then
		return false
	end

	local startDistance = (ball.Position - gatePosition):Dot(planeNormal)
	if math.abs(startDistance) < 0.2 then
		return false
	end

	for index = #self.candidates, 1, -1 do
		local candidate = self.candidates[index]
		if candidate.attacker == attacker or candidate.defender == defender then
			table.remove(self.candidates, index)
		end
	end

	table.insert(self.candidates, {
		attacker = attacker,
		defender = defender,
		defenderCharacter = defender.Character :: Model,
		ball = ball,
		planePoint = gatePosition,
		planeNormal = planeNormal,
		gateRadius = gateRadius,
		gateMinimumY = gatePosition.Y - 0.75,
		gateMaximumY = defenderRoot.Position.Y + 0.4,
		startDistance = startDistance,
		previousPosition = ball.Position,
		previousDistance = startDistance,
		startedAt = os.clock(),
		crossedAt = nil,
	})
	return true
end

function PannaDetector.Step(
	self: Detector,
	ownersByBall: { [BasePart]: Player? },
	lastTouchesByBall: { [BasePart]: Player? }?
)
	local now = os.clock()
	local successes: { { attacker: Player, defender: Player } } = {}
	for index = #self.candidates, 1, -1 do
		local candidate = self.candidates[index]
		local remove = false
		local success = false
		local defenderRoot = getRoot(candidate.defender)
		local currentGatePosition = getLegGate(candidate.defender)
		local owner = ownersByBall[candidate.ball]
		local lastTouch = if lastTouchesByBall then lastTouchesByBall[candidate.ball] else nil
		local defenderMoved = true
		if currentGatePosition then
			local gateDisplacement = currentGatePosition - candidate.planePoint
			local horizontalGateDisplacement =
				Vector3.new(gateDisplacement.X, 0, gateDisplacement.Z).Magnitude
			defenderMoved = horizontalGateDisplacement > math.max(1.25, candidate.gateRadius * 0.8)
				or math.abs(gateDisplacement.Y) > 1.5
		end

		if
			now - candidate.startedAt > 2.1
			or not defenderRoot
			or candidate.defender.Character ~= candidate.defenderCharacter
			or (candidate.crossedAt == nil and defenderMoved)
			or not candidate.ball.Parent
			or (owner ~= nil and owner ~= candidate.attacker)
			or (lastTouch ~= nil and lastTouch ~= candidate.attacker)
		then
			remove = true
		elseif candidate.crossedAt then
			if owner == candidate.attacker then
				remove = true
				success = true
			elseif now - candidate.crossedAt > 1.15 then
				remove = true
			end
		else
			local currentPosition = candidate.ball.Position
			local currentDistance = (currentPosition - candidate.planePoint):Dot(
				candidate.planeNormal
			)
			local crossedPlane = if candidate.startDistance > 0
				then candidate.previousDistance > 0 and currentDistance <= 0
				else candidate.previousDistance < 0 and currentDistance >= 0

			if crossedPlane then
				local denominator = candidate.previousDistance - currentDistance
				if math.abs(denominator) < 1e-5 then
					remove = true
				else
					local alpha = math.clamp(candidate.previousDistance / denominator, 0, 1)
					local crossingPoint = candidate.previousPosition:Lerp(currentPosition, alpha)
					local horizontalOffset = Vector3.new(
						crossingPoint.X - candidate.planePoint.X,
						0,
						crossingPoint.Z - candidate.planePoint.Z
					).Magnitude
					local plausibleHeight = crossingPoint.Y >= candidate.gateMinimumY
						and crossingPoint.Y <= candidate.gateMaximumY
					if horizontalOffset <= candidate.gateRadius and plausibleHeight then
						candidate.crossedAt = now
					else
						-- Both the plane and the gate segment remain in their Begin-time
						-- world positions, so moving the defender cannot drag a candidate.
						remove = true
					end
				end
			end

			candidate.previousPosition = currentPosition
			candidate.previousDistance = currentDistance
		end

		if remove then
			table.remove(self.candidates, index)
		end
		if success then
			table.insert(successes, {
				attacker = candidate.attacker,
				defender = candidate.defender,
			})
		end
	end

	-- Match callbacks may reset a ball and clear candidates, so invoke them only
	-- after the detector has finished mutating its own candidate list.
	for _, result in successes do
		self.onSuccess(result.attacker, result.defender)
	end
end

function PannaDetector.ClearBall(self: Detector, ball: BasePart)
	for index = #self.candidates, 1, -1 do
		if self.candidates[index].ball == ball then
			table.remove(self.candidates, index)
		end
	end
end

function PannaDetector.ClearPlayer(self: Detector, player: Player)
	for index = #self.candidates, 1, -1 do
		local candidate = self.candidates[index]
		if candidate.attacker == player or candidate.defender == player then
			table.remove(self.candidates, index)
		end
	end
end

return PannaDetector
