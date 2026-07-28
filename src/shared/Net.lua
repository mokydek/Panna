--!strict

local Net = {
	FolderName = "PannaRemotes",
	Events = table.freeze({
		ActionRequest = "ActionRequest",
		QueueRequest = "QueueRequest",
		StateUpdate = "StateUpdate",
		Effect = "Effect",
	}),
	Functions = table.freeze({
		GetSnapshot = "GetSnapshot",
	}),
}

return table.freeze(Net)
