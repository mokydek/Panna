--!strict

local ReplicatedStorage = game:GetService("ReplicatedStorage")

local RemoteRegistry = {}
RemoteRegistry.__index = RemoteRegistry

export type Registry = {
	Folder: Folder,
	ActionRequest: RemoteEvent,
	QueueRequest: RemoteEvent,
	StateUpdate: RemoteEvent,
	Effect: RemoteEvent,
	GetSnapshot: RemoteFunction,
}

local function getOrCreate(parent: Instance, className: string, name: string): Instance
	local existing = parent:FindFirstChild(name)
	if existing then
		assert(existing.ClassName == className, string.format("%s must be a %s", name, className))
		return existing
	end

	local instance = Instance.new(className)
	instance.Name = name
	instance.Parent = parent
	return instance
end

function RemoteRegistry.Create(net: any): Registry
	local folder = getOrCreate(ReplicatedStorage, "Folder", net.FolderName) :: Folder
	local registry = {
		Folder = folder,
		ActionRequest = getOrCreate(folder, "RemoteEvent", net.Events.ActionRequest) :: RemoteEvent,
		QueueRequest = getOrCreate(folder, "RemoteEvent", net.Events.QueueRequest) :: RemoteEvent,
		StateUpdate = getOrCreate(folder, "RemoteEvent", net.Events.StateUpdate) :: RemoteEvent,
		Effect = getOrCreate(folder, "RemoteEvent", net.Events.Effect) :: RemoteEvent,
		GetSnapshot = getOrCreate(folder, "RemoteFunction", net.Functions.GetSnapshot) :: RemoteFunction,
	}

	return registry
end

return RemoteRegistry
