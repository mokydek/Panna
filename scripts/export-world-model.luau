--!strict

-- Studio command-bar/RunScript utility. It rebuilds the procedural district,
-- serializes the supported edit-time instances as a Rojo JSON model, and emits
-- the JSON in deterministic chunks for scripts/extract-world-model.ps1.

local HttpService = game:GetService("HttpService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerScriptService = game:GetService("ServerScriptService")
local Workspace = game:GetService("Workspace")

local serverRoot = assert(ServerScriptService:FindFirstChild("PannaServer"), "PannaServer missing")
local sharedRoot = assert(ReplicatedStorage:FindFirstChild("PannaShared"), "PannaShared missing")
local config = require(assert(sharedRoot:FindFirstChild("Config")))
local worldBuilder = require(assert(serverRoot:FindFirstChild("WorldBuilder")))

local existing = Workspace:FindFirstChild(config.World.RootName)
if existing then
	existing:Destroy()
end

local world = worldBuilder.Build(config)

local PROPERTY_CANDIDATES = {
	"Anchored",
	"CanCollide",
	"CanQuery",
	"CanTouch",
	"CastShadow",
	"Color",
	"Material",
	"Reflectance",
	"Transparency",
	"Size",
	"CFrame",
	"Shape",
	"TopSurface",
	"BottomSurface",
	"Massless",
	"Neutral",
	"AllowTeamChangeOnTouch",
	"Duration",
	"Enabled",
	"ActionText",
	"ObjectText",
	"KeyboardKeyCode",
	"GamepadKeyCode",
	"HoldDuration",
	"MaxActivationDistance",
	"RequiresLineOfSight",
	"ClickablePrompt",
	"Style",
	"UIOffset",
	"Exclusivity",
	"AlwaysOnTop",
	"LightInfluence",
	"MaxDistance",
	"StudsOffset",
	"StudsOffsetWorldSpace",
	"Active",
	"BackgroundTransparency",
	"BackgroundColor3",
	"BorderSizePixel",
	"Position",
	"AnchorPoint",
	"Font",
	"Text",
	"TextColor3",
	"TextScaled",
	"TextSize",
	"TextStrokeColor3",
	"TextStrokeTransparency",
	"TextXAlignment",
	"TextYAlignment",
	"RichText",
	"TextWrapped",
	"ZIndex",
	"Range",
	"Brightness",
	"Shadows",
	"Angle",
	"Face",
	"CanvasSize",
	"SizingMode",
	"PixelsPerStud",
}

local function encodeCFrame(value: CFrame): { number }
	local x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 = value:GetComponents()
	return { x, y, z, r00, r01, r02, r10, r11, r12, r20, r21, r22 }
end

local function encodeValue(value: any): any
	local valueType = typeof(value)
	if valueType == "boolean" or valueType == "string" or valueType == "number" then
		return value
	elseif valueType == "Vector2" then
		return { value.X, value.Y }
	elseif valueType == "Vector3" then
		return { value.X, value.Y, value.Z }
	elseif valueType == "Color3" then
		return { value.R, value.G, value.B }
	elseif valueType == "CFrame" then
		return encodeCFrame(value)
	elseif valueType == "UDim" then
		return { UDim = { value.Scale, value.Offset } }
	elseif valueType == "UDim2" then
		return {
			UDim2 = {
				{ value.X.Scale, value.X.Offset },
				{ value.Y.Scale, value.Y.Offset },
			},
		}
	elseif valueType == "EnumItem" then
		return value.Name
	elseif valueType == "PhysicalProperties" then
		return {
			PhysicalProperties = {
				density = value.Density,
				friction = value.Friction,
				elasticity = value.Elasticity,
				frictionWeight = value.FrictionWeight,
				elasticityWeight = value.ElasticityWeight,
			},
		}
	end
	return nil
end

local function encodeAttribute(value: any): any
	local valueType = typeof(value)
	if valueType == "boolean" then
		return { Bool = value }
	elseif valueType == "string" then
		return { String = value }
	elseif valueType == "number" then
		return { Float64 = value }
	elseif valueType == "Vector2" then
		return { Vector2 = { value.X, value.Y } }
	elseif valueType == "Vector3" then
		return { Vector3 = { value.X, value.Y, value.Z } }
	elseif valueType == "Color3" then
		return { Color3 = { value.R, value.G, value.B } }
	elseif valueType == "CFrame" then
		local components = encodeCFrame(value)
		return {
			CFrame = {
				position = { components[1], components[2], components[3] },
				orientation = {
					{ components[4], components[5], components[6] },
					{ components[7], components[8], components[9] },
					{ components[10], components[11], components[12] },
				},
			},
		}
	end
	return nil
end

local function serialize(instance: Instance): { [string]: any }
	local node: { [string]: any } = {
		Name = instance.Name,
		ClassName = instance.ClassName,
	}

	local properties: { [string]: any } = {}
	local attributes: { [string]: any } = {}
	for name, value in instance:GetAttributes() do
		local encoded = encodeAttribute(value)
		if encoded ~= nil then
			attributes[name] = encoded
		end
	end
	if next(attributes) ~= nil then
		properties.Attributes = attributes
	end

	for _, propertyName in PROPERTY_CANDIDATES do
		local ok, value = pcall(function()
			return (instance :: any)[propertyName]
		end)
		if ok then
			local encoded = encodeValue(value)
			if encoded ~= nil then
				properties[propertyName] = encoded
			end
		end
	end
	if next(properties) ~= nil then
		node.Properties = properties
	end

	local children = instance:GetChildren()
	table.sort(children, function(first: Instance, second: Instance): boolean
		if first.Name == second.Name then
			return first.ClassName < second.ClassName
		end
		return first.Name < second.Name
	end)
	if #children > 0 then
		local childNodes = {}
		for _, child in children do
			table.insert(childNodes, serialize(child))
		end
		node.Children = childNodes
	end

	return node
end

local serializedWorld = serialize(world)
-- Rojo derives a JSON model's root name from the file/project mapping. Keeping
-- a top-level Name is harmless but produces a build warning in Rojo 7.
serializedWorld.Name = nil
local payload = HttpService:JSONEncode(serializedWorld)
local chunkSize = 24000
local chunkCount = math.ceil(#payload / chunkSize)
for index = 1, chunkCount do
	local first = (index - 1) * chunkSize + 1
	local last = math.min(index * chunkSize, #payload)
	print(
		string.format(
			"PANNA_WORLD_CHUNK %06d/%06d %s",
			index,
			chunkCount,
			string.sub(payload, first, last)
		)
	)
end
print(
	string.format(
		"PANNA_WORLD_EXPORT_OK instances=%d bytes=%d chunks=%d",
		#world:GetDescendants() + 1,
		#payload,
		chunkCount
	)
)
