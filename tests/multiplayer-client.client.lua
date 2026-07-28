--!strict

local Players = game:GetService("Players")
local StudioTestService = game:GetService("StudioTestService")
local UserInputService = game:GetService("UserInputService")
local Workspace = game:GetService("Workspace")

print("PANNA_MULTIPLAYER_CLIENT_BOOT args=" .. tostring(StudioTestService:GetTestArgs()))

local player = Players.LocalPlayer
local arenaId = player:GetAttribute("PannaSmokeArena")
if type(arenaId) ~= "string" or arenaId == "" then
	repeat
		player:GetAttributeChangedSignal("PannaSmokeArena"):Wait()
		arenaId = player:GetAttribute("PannaSmokeArena")
	until type(arenaId) == "string" and arenaId ~= ""
end

local district = assert(Workspace:WaitForChild("PannaDistrict", 15), "PannaDistrict missing")
local arenas = assert(district:WaitForChild("Arenas", 10), "Arenas folder missing")
local arena = assert(arenas:WaitForChild(arenaId, 10), arenaId .. " missing")
local entry = assert(arena:WaitForChild("EntryZone", 10), "EntryZone missing")
local prompt = assert(entry:WaitForChild("EntryPrompt", 10), "EntryPrompt missing")
assert(prompt:IsA("ProximityPrompt"), "room entry prompt has the wrong class")

local character =
	assert(player.Character or player.CharacterAdded:Wait(), "local character missing")
local root = assert(character:WaitForChild("HumanoidRootPart", 15), "HumanoidRootPart missing")
local deadline = os.clock() + 15
repeat
	task.wait(0.1)
until (root.Position - entry.Position).Magnitude <= prompt.MaxActivationDistance
	or os.clock() >= deadline

print(
	string.format(
		"PANNA_PROMPT_ATTEMPT player=%s arena=%s distance=%.2f enabled=%s",
		player.Name,
		arenaId,
		(root.Position - entry.Position).Magnitude,
		tostring(prompt.Enabled)
	)
)
local virtualInput = UserInputService:CreateVirtualInput()
for attempt = 1, 4 do
	prompt:InputHoldBegin()
	task.wait(math.max(0.35, prompt.HoldDuration + 0.2))
	prompt:InputHoldEnd()
	task.wait(0.5)
	if
		player:GetAttribute("InRoomWaiting") ~= true
		and player:GetAttribute("InMatch") ~= true
		and virtualInput
	then
		local keyCode = prompt.KeyboardKeyCode
		virtualInput:SendKey(true, keyCode, false)
		task.wait(math.max(0.35, prompt.HoldDuration + 0.2))
		virtualInput:SendKey(false, keyCode, false)
		task.wait(0.75)
	end
	if player:GetAttribute("InRoomWaiting") == true or player:GetAttribute("InMatch") == true then
		break
	end
	print(string.format("PANNA_PROMPT_RETRY player=%s attempt=%d", player.Name, attempt))
end
print(
	string.format(
		"PANNA_PROMPT_RESULT player=%s waiting=%s match=%s selected=%s",
		player.Name,
		tostring(player:GetAttribute("InRoomWaiting")),
		tostring(player:GetAttribute("InMatch")),
		tostring(player:GetAttribute("SelectedArenaId"))
	)
)
