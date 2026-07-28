--!strict

-- Driver for a Rojo-built multiplayer.project.json place. The server/client
-- assertions are stored in tests/ so ExecuteMultiplayerTestAsync can load them
-- from the saved local place used by its child Studio processes.

local StudioTestService = game:GetService("StudioTestService")

local result = StudioTestService:ExecuteMultiplayerTestAsync(4, "PannaRoomSmokeV1")
assert(type(result) == "string", "multiplayer test returned a non-string result")
assert(string.find(result, "PANNA_MULTIPLAYER_SMOKE_OK", 1, true) == 1, result)
print("PANNA_MULTIPLAYER_DRIVER_OK " .. result)
