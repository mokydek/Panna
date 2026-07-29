--!strict

local BallMath = {}

function BallMath.IsFiniteNumber(value: any): boolean
	return type(value) == "number" and value == value and value > -math.huge and value < math.huge
end

function BallMath.IsFiniteVector3(value: any): boolean
	return typeof(value) == "Vector3"
		and BallMath.IsFiniteNumber(value.X)
		and BallMath.IsFiniteNumber(value.Y)
		and BallMath.IsFiniteNumber(value.Z)
end

function BallMath.HorizontalUnit(value: any, fallback: Vector3): Vector3?
	local source = if BallMath.IsFiniteVector3(value) then value :: Vector3 else fallback
	local horizontal = Vector3.new(source.X, 0, source.Z)
	if horizontal.Magnitude < 0.05 then
		horizontal = Vector3.new(fallback.X, 0, fallback.Z)
	end
	if horizontal.Magnitude < 0.05 then
		return nil
	end
	return horizontal.Unit
end

function BallMath.ClampMagnitude(value: Vector3, maximum: number): Vector3
	if not BallMath.IsFiniteVector3(value) or not BallMath.IsFiniteNumber(maximum) then
		return Vector3.zero
	end
	local safeMaximum = math.max(0, maximum)
	local magnitude = value.Magnitude
	if magnitude <= safeMaximum or magnitude < 1e-5 then
		return value
	end
	return value.Unit * safeMaximum
end

function BallMath.ChargePower(elapsed: number, chargeSeconds: number, minimumPower: number): number
	local duration = math.max(0.05, chargeSeconds)
	local minimum = math.clamp(minimumPower, 0, 1)
	return minimum + (1 - minimum) * math.clamp(elapsed / duration, 0, 1)
end

function BallMath.LaunchVelocity(
	direction: Vector3,
	horizontalSpeed: number,
	lift: number,
	carrierVelocity: Vector3,
	carrierVelocityCarry: number
): Vector3?
	if
		not BallMath.IsFiniteVector3(direction)
		or not BallMath.IsFiniteVector3(carrierVelocity)
		or not BallMath.IsFiniteNumber(horizontalSpeed)
		or not BallMath.IsFiniteNumber(lift)
		or not BallMath.IsFiniteNumber(carrierVelocityCarry)
	then
		return nil
	end
	local forward = BallMath.HorizontalUnit(direction, Vector3.zero)
	if not forward then
		return nil
	end
	local carrierHorizontal = Vector3.new(carrierVelocity.X, 0, carrierVelocity.Z)
	return forward * math.max(0, horizontalSpeed)
		+ carrierHorizontal * math.max(0, carrierVelocityCarry)
		+ Vector3.yAxis * math.max(0, lift)
end

function BallMath.LaunchAngularVelocity(
	direction: Vector3,
	horizontalSpeed: number,
	radius: number,
	rollRatio: number,
	yawSpin: number
): Vector3?
	if
		not BallMath.IsFiniteVector3(direction)
		or not BallMath.IsFiniteNumber(horizontalSpeed)
		or not BallMath.IsFiniteNumber(radius)
		or not BallMath.IsFiniteNumber(rollRatio)
		or not BallMath.IsFiniteNumber(yawSpin)
		or radius <= 0.05
	then
		return nil
	end
	local forward = BallMath.HorizontalUnit(direction, Vector3.zero)
	if not forward then
		return nil
	end
	local rollAxis = Vector3.new(0, 1, 0):Cross(forward)
	local rollSpeed = math.max(0, horizontalSpeed) / radius * rollRatio
	return rollAxis * rollSpeed + Vector3.yAxis * yawSpin
end

function BallMath.AerodynamicDragAcceleration(
	linearVelocity: Vector3,
	coefficient: number,
	maximumAcceleration: number
): Vector3
	if
		not BallMath.IsFiniteVector3(linearVelocity)
		or not BallMath.IsFiniteNumber(coefficient)
		or not BallMath.IsFiniteNumber(maximumAcceleration)
	then
		return Vector3.zero
	end
	local speed = linearVelocity.Magnitude
	if speed < 0.05 then
		return Vector3.zero
	end
	return BallMath.ClampMagnitude(
		-linearVelocity * speed * math.max(0, coefficient),
		math.max(0, maximumAcceleration)
	)
end

function BallMath.DirectionDot(first: Vector3, second: Vector3): number
	local firstHorizontal = BallMath.HorizontalUnit(first, Vector3.zero)
	local secondHorizontal = BallMath.HorizontalUnit(second, Vector3.zero)
	if not firstHorizontal or not secondHorizontal then
		return -1
	end
	return firstHorizontal:Dot(secondHorizontal)
end

function BallMath.ClosestPointOnRay(
	origin: Vector3,
	direction: Vector3,
	point: Vector3
): (Vector3, number)
	local unitDirection = BallMath.HorizontalUnit(direction, Vector3.zero)
	if not unitDirection then
		return origin, 0
	end
	local along = math.max(0, (point - origin):Dot(unitDirection))
	return origin + unitDirection * along, along
end

function BallMath.ProjectOnPlane(value: Vector3, normal: Vector3): Vector3
	if not BallMath.IsFiniteVector3(value) then
		return Vector3.zero
	end
	if not BallMath.IsFiniteVector3(normal) or normal.Magnitude < 0.05 then
		return value
	end
	local unitNormal = normal.Unit
	return value - unitNormal * value:Dot(unitNormal)
end

function BallMath.RotateHorizontalTowards(
	current: Vector3,
	target: Vector3,
	maximumRadians: number
): Vector3?
	local from = BallMath.HorizontalUnit(current, target)
	local to = BallMath.HorizontalUnit(target, current)
	if not from or not to or not BallMath.IsFiniteNumber(maximumRadians) then
		return nil
	end
	local signedAngle = math.atan2(from:Cross(to).Y, from:Dot(to))
	local step = math.clamp(signedAngle, -math.max(0, maximumRadians), math.max(0, maximumRadians))
	return CFrame.fromAxisAngle(Vector3.yAxis, step):VectorToWorldSpace(from).Unit
end

function BallMath.PreferredControlDirection(
	facing: Vector3,
	carrierVelocity: Vector3,
	minimumMovementSpeed: number
): Vector3?
	if
		not BallMath.IsFiniteVector3(facing)
		or not BallMath.IsFiniteVector3(carrierVelocity)
		or not BallMath.IsFiniteNumber(minimumMovementSpeed)
	then
		return nil
	end

	local horizontalVelocity = Vector3.new(carrierVelocity.X, 0, carrierVelocity.Z)
	if horizontalVelocity.Magnitude >= math.max(0.05, minimumMovementSpeed) then
		return horizontalVelocity.Unit
	end
	return BallMath.HorizontalUnit(facing, Vector3.zero)
end

function BallMath.PhysicalControlTarget(
	rootCFrame: CFrame,
	direction: Vector3,
	distance: number,
	lateralOffset: number,
	targetHeight: number
): Vector3?
	local forward = BallMath.HorizontalUnit(direction, rootCFrame.LookVector)
	if
		not forward
		or not BallMath.IsFiniteNumber(distance)
		or not BallMath.IsFiniteNumber(lateralOffset)
		or not BallMath.IsFiniteNumber(targetHeight)
	then
		return nil
	end
	local right = forward:Cross(Vector3.yAxis)
	local horizontal = rootCFrame.Position + forward * math.max(0, distance) + right * lateralOffset
	return Vector3.new(horizontal.X, targetHeight, horizontal.Z)
end

function BallMath.PhysicalControlAcceleration(
	ballPosition: Vector3,
	ballVelocity: Vector3,
	targetPosition: Vector3,
	carrierVelocity: Vector3,
	groundNormal: Vector3,
	naturalFrequency: number,
	dampingRatio: number,
	velocityCarry: number,
	maximumCorrectionSpeed: number,
	maximumAcceleration: number
): Vector3?
	if
		not BallMath.IsFiniteVector3(ballPosition)
		or not BallMath.IsFiniteVector3(ballVelocity)
		or not BallMath.IsFiniteVector3(targetPosition)
		or not BallMath.IsFiniteVector3(carrierVelocity)
		or not BallMath.IsFiniteVector3(groundNormal)
		or groundNormal.Magnitude < 0.05
	then
		return nil
	end
	for _, value in
		{
			naturalFrequency,
			dampingRatio,
			velocityCarry,
			maximumCorrectionSpeed,
			maximumAcceleration,
		}
	do
		if not BallMath.IsFiniteNumber(value) then
			return nil
		end
	end

	local normal = groundNormal.Unit
	local positionError = BallMath.ProjectOnPlane(targetPosition - ballPosition, normal)
	local ballTangentVelocity = BallMath.ProjectOnPlane(ballVelocity, normal)
	local carrierTangentVelocity = BallMath.ProjectOnPlane(carrierVelocity, normal)
	local frequency = math.max(0, naturalFrequency)
	local correctionVelocity =
		BallMath.ClampMagnitude(positionError * frequency, math.max(0, maximumCorrectionSpeed))
	local carrierTargetVelocity = carrierTangentVelocity * math.max(0, velocityCarry)
	local velocityDamping = (carrierTargetVelocity - ballTangentVelocity)
		* (2 * math.max(0, dampingRatio) * frequency)
	return BallMath.ClampMagnitude(
		correctionVelocity * frequency + velocityDamping,
		math.max(0, maximumAcceleration)
	)
end

function BallMath.MagnusAcceleration(
	linearVelocity: Vector3,
	angularVelocity: Vector3,
	coefficient: number,
	maximumAcceleration: number
): Vector3
	if
		not BallMath.IsFiniteVector3(linearVelocity)
		or not BallMath.IsFiniteVector3(angularVelocity)
		or not BallMath.IsFiniteNumber(coefficient)
		or not BallMath.IsFiniteNumber(maximumAcceleration)
	then
		return Vector3.zero
	end
	local horizontalVelocity = Vector3.new(linearVelocity.X, 0, linearVelocity.Z)
	local yawSpin = Vector3.new(0, angularVelocity.Y, 0)
	return BallMath.ClampMagnitude(
		yawSpin:Cross(horizontalVelocity) * math.max(0, coefficient),
		math.max(0, maximumAcceleration)
	)
end

return table.freeze(BallMath)
