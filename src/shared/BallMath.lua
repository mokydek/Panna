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

return table.freeze(BallMath)
