-- Minimap of the tower-defence map (bottom-left), and a "quick view" of the whole map when you click it.
--   red = enemies, green = your side (buildings, units, builders), yellow = the city and the trade truck
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local camera = workspace.CurrentCamera

local W, H, CELL = Config.GridW, Config.GridH, Config.Cell
local SIZE = 210

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local RED = Color3.fromRGB(255, 60, 60)
local GREEN = Color3.fromRGB(70, 210, 95)
local GREEN_UNIT = Color3.fromRGB(140, 255, 150)
local YELLOW = Color3.fromRGB(255, 215, 60)

local gui = new("ScreenGui", { Name = "MinimapUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 4 }, playerGui)

local holder = new("Frame", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -12), Size = UDim2.fromOffset(SIZE + 12, SIZE + 34),
	BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.1, BorderSizePixel = 0,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, holder)
local holderStroke = new("UIStroke", { Color = Color3.fromRGB(55, 60, 78), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, holder)
local title = new("TextLabel", {
	Position = UDim2.fromOffset(10, 4), Size = UDim2.new(1, -20, 0, 22), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
	TextSize = 12, TextColor3 = Color3.fromRGB(170, 175, 195), TextXAlignment = Enum.TextXAlignment.Left, Text = "MAP  -  click for full view (M)",
}, holder)

-- the map itself is a button: clicking it toggles the full view
local map = new("TextButton", {
	Position = UDim2.fromOffset(6, 28), Size = UDim2.fromOffset(SIZE, SIZE), BackgroundColor3 = Color3.fromRGB(62, 118, 52),
	AutoButtonColor = false, Text = "", ClipsDescendants = true, Selectable = false, BorderSizePixel = 0,
}, holder)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, map)
local terrainLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, map)
local staticLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, map)
local dotLayer = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1 }, map)

local function tileFrame(parent, i, j, w, h, color)
	return new("Frame", {
		Position = UDim2.fromScale((i - 1) / W, (j - 1) / H), Size = UDim2.fromScale(w / W, h / H),
		BackgroundColor3 = color, BorderSizePixel = 0,
	}, parent)
end

-- fixed things: the city (yellow), enemy gates (purple), dungeon portal (cyan, once open)
local c = Config.City
local city = tileFrame(staticLayer, c.MinI, c.MinJ, c.MaxI - c.MinI + 1, c.MaxJ - c.MinJ + 1, YELLOW)
new("UICorner", { CornerRadius = UDim.new(0, 3) }, city)
for _, s in ipairs(Config.Spawns) do
	local g = tileFrame(staticLayer, s[1], s[2], 1, 1, Color3.fromRGB(170, 70, 255))
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, g)
end
local portal = tileFrame(staticLayer, Config.Portal[1], Config.Portal[2], 1, 1, Color3.fromRGB(90, 220, 255))
new("UICorner", { CornerRadius = UDim.new(1, 0) }, portal)
portal.Visible = workspace:GetAttribute("PortalOpen") == true
workspace:GetAttributeChangedSignal("PortalOpen"):Connect(function()
	portal.Visible = workspace:GetAttribute("PortalOpen") == true
end)

-- water / mud / trade road tiles
local terrainFrames = {}
local function refreshTerrain()
	local tiles = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Tiles")
	if not tiles then return end
	for i = 1, W do
		for j = 1, H do
			local key = i .. "_" .. j
			local t = tiles:FindFirstChild(key)
			local color
			if t then
				local ter = t:GetAttribute("Terrain")
				if ter == "Water" then
					color = Color3.fromRGB(50, 120, 210)
				elseif ter == "Mud" then
					color = Color3.fromRGB(120, 84, 50)
				elseif t:GetAttribute("Route") then
					color = Color3.fromRGB(205, 175, 115)
				end
			end
			local f = terrainFrames[key]
			if color then
				if not f then
					f = tileFrame(terrainLayer, i, j, 1, 1, color)
					terrainFrames[key] = f
				end
				f.BackgroundColor3 = color
				f.Visible = true
			elseif f then
				f.Visible = false
			end
		end
	end
end

-- moving dots, reused every update
local pool = {}
local used = 0
local function dot(pos, size, color, round, transparency)
	used += 1
	local f = pool[used]
	if not f then
		f = new("Frame", { AnchorPoint = Vector2.new(0.5, 0.5), BorderSizePixel = 0 }, dotLayer)
		new("UICorner", { Name = "C" }, f)
		pool[used] = f
	end
	f.Position = UDim2.fromScale((pos.X + W * CELL / 2) / (W * CELL), (pos.Z + H * CELL / 2) / (H * CELL))
	f.Size = UDim2.fromOffset(size, size)
	f.BackgroundColor3 = color
	f.BackgroundTransparency = transparency or 0
	f.C.CornerRadius = round and UDim.new(1, 0) or UDim.new(0, 1)
	f.Visible = true
end

local TILE_PX = SIZE / W
local function refreshDots()
	used = 0
	local mapFolder = workspace:FindFirstChild("Map")
	if mapFolder then
		local buildings = mapFolder:FindFirstChild("Buildings")
		if buildings then
			for _, m in ipairs(buildings:GetChildren()) do
				local kind = m:GetAttribute("Kind")
				if kind and kind ~= "Terrain" then
					local site = m:GetAttribute("Building") == true
					if kind == "Monster" then
						dot(m:GetPivot().Position, 7, GREEN_UNIT, true, site and 0.5 or 0)
					else
						dot(m:GetPivot().Position, TILE_PX * 0.8, GREEN, false, site and 0.55 or 0)
					end
				end
			end
		end
		local builders = mapFolder:FindFirstChild("Builders")
		if builders then
			for _, m in ipairs(builders:GetChildren()) do
				dot(m:GetPivot().Position, 4, GREEN_UNIT, true)
			end
		end
		local truck = mapFolder:FindFirstChild("TradeTruck")
		if truck then dot(truck:GetPivot().Position, 9, YELLOW, true) end
		local enemies = mapFolder:FindFirstChild("Enemies")
		if enemies then
			for _, m in ipairs(enemies:GetChildren()) do
				local big = m.Name == "Boss" or m.Name:find("^Champion") ~= nil
				dot(m:GetPivot().Position, big and 9 or 5, RED, true)
			end
		end
	end
	for k = used + 1, #pool do pool[k].Visible = false end
end

local acc, terrainAcc = 0, 0
RunService.Heartbeat:Connect(function(dt)
	acc += dt
	terrainAcc += dt
	if acc >= 0.1 then
		acc = 0
		refreshDots()
	end
	if terrainAcc >= 0.5 then
		terrainAcc = 0
		refreshTerrain()
	end
end)

---------------------------------------------------------------- quick view of the whole map
local function setQuick(on)
	player:SetAttribute("QuickView", on)
end
local function refreshQuickUI()
	local on = player:GetAttribute("QuickView") == true
	title.Text = on and "FULL VIEW  -  click to go back (M)" or "MAP  -  click for full view (M)"
	title.TextColor3 = on and YELLOW or Color3.fromRGB(170, 175, 195)
	holderStroke.Color = on and YELLOW or Color3.fromRGB(55, 60, 78)
	holderStroke.Thickness = on and 2 or 1
end
player:GetAttributeChangedSignal("QuickView"):Connect(refreshQuickUI)
refreshQuickUI()

map.Activated:Connect(function()
	setQuick(not (player:GetAttribute("QuickView") == true))
end)
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.M then
		setQuick(not (player:GetAttribute("QuickView") == true))
	end
end)

-- top-down camera that fits the entire map (a bit shifted so the HUD and build bar don't cover the edges)
local wasQuick = false
RunService:BindToRenderStep("QuickViewCamera", Enum.RenderPriority.Camera.Value + 3, function()
	if player:GetAttribute("QuickView") == true then
		camera.CameraType = Enum.CameraType.Scriptable
		local half = 72
		local height = half / math.tan(math.rad(camera.FieldOfView / 2))
		local centre = Vector3.new(0, 0, 4)
		camera.CFrame = CFrame.lookAt(centre + Vector3.new(0, height, 0), centre, Vector3.new(0, 0, -1))
		wasQuick = true
	elseif wasQuick then
		wasQuick = false
		if player:GetAttribute("ViewDungeon") ~= true then
			camera.CameraType = Enum.CameraType.Custom
		end
	end
end)
