--!strict

-- Headless Studio renderer for review screenshots. The PNG bytes are emitted as
-- base64 chunks and reconstructed by scripts/extract-captures.ps1.

local EncodingService = game:GetService("EncodingService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local StudioCaptureService = game:GetService("StudioCaptureService")
local Workspace = game:GetService("Workspace")

local serverRoot = assert(ServerScriptService:FindFirstChild("PannaServer"), "PannaServer missing")
local sharedRoot = assert(ReplicatedStorage:FindFirstChild("PannaShared"), "PannaShared missing")
local config = require(assert(sharedRoot:FindFirstChild("Config")))
local worldBuilder = require(assert(serverRoot:FindFirstChild("WorldBuilder")))

local world = worldBuilder.Build(config)
assert(world.Parent == Workspace, "Panna world was not parented to Workspace")

local camera = Workspace.CurrentCamera
if not camera then
	camera = Instance.new("Camera")
	camera.Name = "PannaReviewCamera"
	camera.Parent = Workspace
	Workspace.CurrentCamera = camera
end
camera.CameraType = Enum.CameraType.Scriptable
camera.FieldOfView = 62

local CAPTURE_TIMEOUT_SECONDS = 12

local function captureErrors(capture: StudioScreenshotCapture): string
	local messages = {}
	for _, captureError in capture:GetErrors() do
		table.insert(messages, tostring(captureError))
	end
	return if #messages > 0 then table.concat(messages, "; ") else "unknown capture error"
end

local function waitForScreenshotAvailability(): (boolean, string?)
	local deadline = os.clock() + CAPTURE_TIMEOUT_SECONDS
	while true do
		local ok, availableOrError = pcall(function()
			return StudioCaptureService:CanCaptureScreenshot()
		end)
		if not ok then
			return false, tostring(availableOrError)
		end
		if availableOrError then
			return true, nil
		end
		if os.clock() >= deadline then
			return false, "StudioCaptureService did not become available before timeout"
		end
		task.wait(0.1)
	end
end

local function getPngBytes(): (string?, string?)
	local available, availabilityError = waitForScreenshotAvailability()
	if not available then
		return nil, availabilityError
	end

	local ok, captureOrError = pcall(function()
		return StudioCaptureService:CaptureScreenshot({})
	end)
	if not ok then
		return nil, tostring(captureOrError)
	end
	if captureOrError == nil then
		return nil, "CaptureScreenshot returned nil"
	end
	local capture = captureOrError :: StudioScreenshotCapture
	local deadline = os.clock() + CAPTURE_TIMEOUT_SECONDS
	while
		capture.BufferStatus == Enum.StudioCaptureBufferStatus.NotStarted
		or capture.BufferStatus == Enum.StudioCaptureBufferStatus.Pending
	do
		if os.clock() >= deadline then
			return nil, "screenshot buffer timed out"
		end
		task.wait(0.05)
	end

	if capture.BufferStatus ~= Enum.StudioCaptureBufferStatus.Ready then
		return nil, captureErrors(capture)
	end
	if capture.BufferFormat ~= Enum.StudioCaptureScreenshotFormat.PNG then
		return nil, string.format("unsupported screenshot format %s", capture.BufferFormat.Name)
	end

	local bufferOk, imageBufferOrError = pcall(function()
		return capture:GetBuffer()
	end)
	if not bufferOk or typeof(imageBufferOrError) ~= "buffer" then
		return nil, tostring(imageBufferOrError)
	end
	local imageBytes = buffer.tostring(imageBufferOrError)
	if #imageBytes < 100 then
		return nil, "screenshot buffer is empty"
	end
	return imageBytes, nil
end

local function emitCapture(name: string, cframe: CFrame, focus: Vector3): boolean
	camera.CFrame = cframe
	camera.Focus = CFrame.new(focus)
	task.wait(0.35)

	local imageOrError, captureError = getPngBytes()
	if not imageOrError then
		print(string.format("PANNA_CAPTURE_ERROR %s %s", name, tostring(captureError)))
		return false
	end

	local encodedBuffer = EncodingService:Base64Encode(buffer.fromstring(imageOrError))
	local encoded = buffer.tostring(encodedBuffer)
	local chunkSize = 24000
	local count = math.ceil(#encoded / chunkSize)
	for index = 1, count do
		local first = (index - 1) * chunkSize + 1
		local last = math.min(index * chunkSize, #encoded)
		print(
			string.format(
				"PANNA_CAPTURE_CHUNK %s %06d/%06d %s",
				name,
				index,
				count,
				string.sub(encoded, first, last)
			)
		)
	end
	print(string.format("PANNA_CAPTURE_OK name=%s bytes=%d chunks=%d", name, #imageOrError, count))
	return true
end

local capturesCompleted = 0
if
	emitCapture(
		"district-overview",
		CFrame.lookAt(Vector3.new(205, 175, -42), Vector3.new(0, 4, -5)),
		Vector3.new(0, 4, -5)
	)
then
	capturesCompleted += 1
end
if
	emitCapture(
		"central-street",
		CFrame.lookAt(Vector3.new(0, 24, -205), Vector3.new(0, 7, 115)),
		Vector3.new(0, 7, 115)
	)
then
	capturesCompleted += 1
end

local firstArena = config.World.ArenaPositions[1]
local arenaFocus = firstArena.Position + Vector3.new(0, 4, 0)
if
	emitCapture(
		"arena-room",
		CFrame.lookAt(arenaFocus + Vector3.new(70, 58, -64), arenaFocus),
		arenaFocus
	)
then
	capturesCompleted += 1
end

assert(capturesCompleted == 3, string.format("Only %d/3 captures completed", capturesCompleted))
print(string.format("PANNA_CAPTURE_SET_OK count=%d", capturesCompleted))
