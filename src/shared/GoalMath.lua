--!strict

local GoalMath = {}

-- A small spatial tolerance keeps a sphere that is only touching the goal
-- line, a post, or the crossbar from being counted as fully through.
local SPATIAL_EPSILON = 1e-4

export type Geometry = {
	planePoint: Vector3,
	outward: Vector3,
	right: Vector3,
	up: Vector3,
	halfWidth: number,
	halfHeight: number,
}

function GoalMath.CreateGeometry(
	goalCFrame: CFrame,
	goalSize: Vector3,
	fieldCenter: Vector3
): Geometry?
	local towardGoal = goalCFrame.Position - fieldCenter
	local horizontalTowardGoal = Vector3.new(towardGoal.X, 0, towardGoal.Z)
	if horizontalTowardGoal.Magnitude < SPATIAL_EPSILON then
		return nil
	end

	-- Goal markers use local Z as their depth. Choose the sign of that axis
	-- which points from the field centre into this goal.
	local look = goalCFrame.LookVector
	local horizontalDepth = Vector3.new(look.X, 0, look.Z)
	if horizontalDepth.Magnitude < SPATIAL_EPSILON then
		return nil
	end
	local outward = horizontalDepth.Unit
	if outward:Dot(horizontalTowardGoal) < 0 then
		outward = -outward
	end

	return {
		planePoint = goalCFrame.Position - outward * (goalSize.Z * 0.5),
		outward = outward,
		right = goalCFrame.RightVector,
		up = goalCFrame.UpVector,
		halfWidth = goalSize.X * 0.5,
		halfHeight = goalSize.Y * 0.5,
	}
end

function GoalMath.SignedDistance(point: Vector3, geometry: Geometry): number
	return (point - geometry.planePoint):Dot(geometry.outward)
end

function GoalMath.FullCrossingCenter(
	previousCenter: Vector3,
	currentCenter: Vector3,
	radius: number,
	geometry: Geometry
): Vector3?
	local safeRadius = math.max(0, radius)
	local threshold = safeRadius + SPATIAL_EPSILON
	local previousDistance = GoalMath.SignedDistance(previousCenter, geometry)
	local currentDistance = GoalMath.SignedDistance(currentCenter, geometry)

	-- Positive signed distance points from the field into the goal. Requiring
	-- an increasing segment rejects entry from behind the net. The centre must
	-- pass farther than one radius beyond the plane, so contact and half-ball
	-- crossings do not score.
	local distanceDelta = currentDistance - previousDistance
	if previousDistance > threshold or currentDistance <= threshold then
		return nil
	end
	if distanceDelta <= SPATIAL_EPSILON then
		return nil
	end

	local alpha = (threshold - previousDistance) / distanceDelta
	if alpha < -SPATIAL_EPSILON or alpha > 1 + SPATIAL_EPSILON then
		return nil
	end
	return previousCenter:Lerp(currentCenter, math.clamp(alpha, 0, 1))
end

function GoalMath.IsSphereInsideAperture(
	center: Vector3,
	radius: number,
	geometry: Geometry
): boolean
	local safeRadius = math.max(0, radius)
	local relative = center - geometry.planePoint
	local lateral = math.abs(relative:Dot(geometry.right))
	local vertical = relative:Dot(geometry.up)

	-- Post and crossbar tangency are deliberately excluded. Floor tangency is
	-- allowed so that a normally rolling ball can score along the ground.
	local clearsPosts = geometry.halfWidth - lateral - safeRadius > SPATIAL_EPSILON
	local clearsCrossbar = geometry.halfHeight - vertical - safeRadius > SPATIAL_EPSILON
	local aboveFloor = vertical - safeRadius >= -geometry.halfHeight - SPATIAL_EPSILON
	return clearsPosts and clearsCrossbar and aboveFloor
end

function GoalMath.DidSphereFullyCross(
	previousCenter: Vector3,
	currentCenter: Vector3,
	radius: number,
	geometry: Geometry
): boolean
	local crossingCenter =
		GoalMath.FullCrossingCenter(previousCenter, currentCenter, radius, geometry)
	return crossingCenter ~= nil
		and GoalMath.IsSphereInsideAperture(crossingCenter, radius, geometry)
end

return table.freeze(GoalMath)
