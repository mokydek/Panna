--!strict

local RateLimiter = {}
RateLimiter.__index = RateLimiter

type Bucket = {
	tokens: number,
	updatedAt: number,
}

export type Limiter = typeof(setmetatable(
	{} :: {
		capacity: number,
		refillPerSecond: number,
		buckets: { [number]: { [string]: Bucket } },
	},
	RateLimiter
))

function RateLimiter.new(capacity: number, refillPerSecond: number): Limiter
	return setmetatable({
		capacity = math.max(1, capacity),
		refillPerSecond = math.max(0.1, refillPerSecond),
		buckets = {},
	}, RateLimiter)
end

function RateLimiter.Allow(self: Limiter, player: Player, key: string, cost: number?): boolean
	local userBuckets = self.buckets[player.UserId]
	if not userBuckets then
		userBuckets = {}
		self.buckets[player.UserId] = userBuckets
	end

	local now = os.clock()
	local bucket = userBuckets[key]
	if not bucket then
		bucket = {
			tokens = self.capacity,
			updatedAt = now,
		}
		userBuckets[key] = bucket
	end

	local elapsed = math.max(0, now - bucket.updatedAt)
	bucket.updatedAt = now
	bucket.tokens = math.min(self.capacity, bucket.tokens + elapsed * self.refillPerSecond)

	local requested = math.max(0.1, cost or 1)
	if bucket.tokens < requested then
		return false
	end

	bucket.tokens -= requested
	return true
end

function RateLimiter.RemovePlayer(self: Limiter, player: Player)
	self.buckets[player.UserId] = nil
end

return RateLimiter
