--!strict

local EffectScope = {}

local function readString(source: any, ...: string): string
	if typeof(source) ~= "table" then
		return ""
	end
	for _, key in { ... } do
		local value = source[key]
		if typeof(value) == "string" then
			return value
		end
	end
	return ""
end

local function readRevision(source: any, ...: string): number
	if typeof(source) ~= "table" then
		return 0
	end
	for _, key in { ... } do
		local value = source[key]
		if
			type(value) == "number"
			and value == value
			and value >= 1
			and value <= 9007199254740991
		then
			return math.floor(value)
		end
	end
	return 0
end

function EffectScope.ReadStateContext(payload: any): (string, string, number)
	if typeof(payload) ~= "table" then
		return "", "", 0
	end
	local wrapped = payload.data or payload.Data or payload.snapshot or payload.Snapshot
	local state = if typeof(wrapped) == "table" then wrapped else payload
	local match = state.match or state.Match
	if typeof(match) ~= "table" then
		return "", "", 0
	end
	return readString(match, "id", "Id", "matchId", "MatchId"),
		readString(match, "arenaId", "ArenaId"),
		readRevision(match, "revision", "Revision", "matchRevision", "MatchRevision")
end

function EffectScope.ReadStateRevision(payload: any): number
	if typeof(payload) ~= "table" then
		return 0
	end
	local wrapped = payload.data or payload.Data or payload.snapshot or payload.Snapshot
	local state = if typeof(wrapped) == "table" then wrapped else payload
	local match = state.match or state.Match
	if typeof(match) == "table" then
		local matchRevision =
			readRevision(match, "revision", "Revision", "matchRevision", "MatchRevision")
		if matchRevision > 0 then
			return matchRevision
		end
	end
	return readRevision(state, "matchRevision", "MatchRevision")
end

function EffectScope.ReadEffectContext(payload: any): (string, string, number)
	return readString(payload, "matchId", "MatchId"),
		readString(payload, "arenaId", "ArenaId"),
		readRevision(payload, "matchRevision", "MatchRevision", "revision", "Revision")
end

function EffectScope.Matches(
	payload: any,
	currentMatchId: string,
	currentArenaId: string,
	currentRevision: number,
	recentMatchId: string,
	recentArenaId: string,
	recentRevision: number
): boolean
	if typeof(payload) ~= "table" then
		return true
	end
	local effectMatchId, effectArenaId, effectRevision = EffectScope.ReadEffectContext(payload)
	if effectMatchId == "" then
		return true
	end
	-- Attributes, StateUpdate, and Effect are replicated independently. A server-issued,
	-- monotonic match revision makes their arrival order unambiguous: a newer effect may
	-- establish the context, while an older result can never reset a newer match.
	if effectRevision <= 0 then
		return false
	end

	local knownRevision = math.max(currentRevision, recentRevision)
	if effectRevision < knownRevision then
		return false
	end
	if effectRevision > knownRevision then
		return true
	end

	local currentMatches = currentRevision == effectRevision
		and currentMatchId == effectMatchId
		and (effectArenaId == "" or currentArenaId == "" or currentArenaId == effectArenaId)
	local recentMatches = recentRevision == effectRevision
		and recentMatchId == effectMatchId
		and (effectArenaId == "" or recentArenaId == "" or recentArenaId == effectArenaId)
	return currentMatches or recentMatches
end

return table.freeze(EffectScope)
