-- City Defense: client UI + grid placement
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local remotes = RS:WaitForChild("Remotes")
local placeRemote = remotes:WaitForChild("PlaceItem")
local sellRemote = remotes:WaitForChild("SellItem")
local readyRemote = remotes:WaitForChild("ReadyUp")
local notifyRemote = remotes:WaitForChild("Notify")
local moveRemote = remotes:WaitForChild("MoveUnit")
local coinsValue = player:WaitForChild("leaderstats"):WaitForChild("Coins")
local tiles = workspace:WaitForChild("Map"):WaitForChild("Tiles")
local camera = workspace.CurrentCamera

local W, H, CELL, TOP = Config.GridW, Config.GridH, Config.Cell, Config.TileTop

local selected = nil -- item id, "SELL", or nil
local selectedUnit = nil -- the first unit you're commanding, or nil
local selectedUnits = {} -- every unit you're commanding (drag a box to pick several)

---------------------------------------------------------------- helpers
local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

local function cellCenter(i, j)
	return Vector3.new((i - (W + 1) / 2) * CELL, TOP, (j - (H + 1) / 2) * CELL)
end

local function cellFromRay(ray)
	if ray.Direction.Y >= -1e-4 then return nil end
	local t = (TOP - ray.Origin.Y) / ray.Direction.Y
	if t < 0 then return nil end
	local p = ray.Origin + ray.Direction * t
	local i = math.floor(p.X / CELL + W / 2) + 1
	local j = math.floor(p.Z / CELL + H / 2) + 1
	if i < 1 or i > W or j < 1 or j > H then return nil end
	return i, j
end

---------------------------------------------------------------- UI
local gui = new("ScreenGui", { Name = "CityDefenseUI", ResetOnSpawn = false }, playerGui)
local overUI = false
local function trackHover(frame)
	frame.MouseEnter:Connect(function() overUI = true end)
	frame.MouseLeave:Connect(function() overUI = false end)
end

-- top panel
local top = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 8), Size = UDim2.fromOffset(380, 62),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, top)

-- game speed buttons, right of the wave panel
local speedRemote = remotes:WaitForChild("SetSpeed")
local speedFrame = new("Frame", {
	Position = UDim2.new(1, 8, 0, 0), Size = UDim2.fromOffset(0, 62), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0,
}, top)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, speedFrame)
new("UIPadding", { PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }, speedFrame)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 4), VerticalAlignment = Enum.VerticalAlignment.Center,
	SortOrder = Enum.SortOrder.LayoutOrder,
}, speedFrame)
local speedButtons = {}
for _, s in ipairs({ 1, 2, 3 }) do
	local b = new("TextButton", {
		Name = "Speed" .. s, Size = UDim2.fromOffset(44, 48), BackgroundColor3 = Color3.fromRGB(40, 44, 58), BorderSizePixel = 0,
		TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 16, Text = s .. "x", LayoutOrder = s, Selectable = false,
	}, speedFrame)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, b)
	b.Activated:Connect(function() speedRemote:FireServer(s) end)
	speedButtons[s] = b
end
local function refreshSpeed()
	local cur = workspace:GetAttribute("GameSpeed") or 1
	for s, b in pairs(speedButtons) do
		local on = s == cur
		b.BackgroundColor3 = on and Color3.fromRGB(255, 200, 60) or Color3.fromRGB(40, 44, 58)
		b.TextColor3 = on and Color3.fromRGB(35, 28, 10) or Color3.new(1, 1, 1)
	end
end
workspace:GetAttributeChangedSignal("GameSpeed"):Connect(refreshSpeed)
refreshSpeed()
local waveLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 28), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 16, Text = "Wave 1",
}, top)
local hpBack = new("Frame", {
	Position = UDim2.new(0, 10, 0, 34), Size = UDim2.new(1, -20, 0, 18),
	BackgroundColor3 = Color3.fromRGB(60, 20, 20), BorderSizePixel = 0,
}, top)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, hpBack)
local hpFill = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(90, 210, 90), BorderSizePixel = 0,
}, hpBack)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, hpFill)
local hpText = new("TextLabel", {
	Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 13, Text = "City HP", ZIndex = 2,
}, hpBack)

-- coins
local coinsLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 8), Size = UDim2.fromOffset(170, 40),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0,
	TextColor3 = Color3.fromRGB(255, 220, 90), Font = Enum.Font.GothamBold, TextSize = 20, Text = "Coins: 0",
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, coinsLabel)

-- ready button
local readyBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 78), Size = UDim2.fromOffset(220, 34),
	BackgroundColor3 = Color3.fromRGB(60, 170, 90), BorderSizePixel = 0, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBold, TextSize = 14, Text = "Start wave early",
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, readyBtn)
readyBtn.Activated:Connect(function() readyRemote:FireServer() end)

-- trade truck bar
local tradeFrame = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 118), Size = UDim2.fromOffset(400, 40),
	BackgroundColor3 = Color3.fromRGB(60, 45, 15), BackgroundTransparency = 0.2, BorderSizePixel = 0, Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, tradeFrame)
local tradeLabel = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 20), Position = UDim2.fromOffset(0, 2), BackgroundTransparency = 1,
	TextColor3 = Color3.fromRGB(255, 220, 90), Font = Enum.Font.GothamBold, TextSize = 13, Text = "TRADE ROUTE",
}, tradeFrame)
local tradeBack = new("Frame", {
	Position = UDim2.new(0, 10, 0, 25), Size = UDim2.new(1, -20, 0, 10), BackgroundColor3 = Color3.fromRGB(30, 22, 8), BorderSizePixel = 0,
}, tradeFrame)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, tradeBack)
local tradeFill = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(255, 200, 60), BorderSizePixel = 0,
}, tradeBack)
new("UICorner", { CornerRadius = UDim.new(0, 4) }, tradeFill)

-- toast
local toast = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0.18, 0), Size = UDim2.fromOffset(460, 34),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.2, BorderSizePixel = 0,
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamMedium, TextSize = 16, Text = "", Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, toast)
local toastId = 0
local function showToast(msg)
	toastId += 1
	local my = toastId
	toast.Text = msg
	toast.Visible = true
	task.delay(2.5, function()
		if toastId == my then toast.Visible = false end
	end)
end
notifyRemote.OnClientEvent:Connect(showToast)

-- random events panel (left side)
local HttpService = game:GetService("HttpService")
local eventsFrame = new("Frame", {
	Position = UDim2.new(0, 12, 0, 70), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1,
}, gui)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, eventsFrame)
local eventRows = {}
local function rebuildEvents()
	for _, r in ipairs(eventRows) do r.Frame:Destroy() end
	table.clear(eventRows)
	local ok, list = pcall(function() return HttpService:JSONDecode(workspace:GetAttribute("Events") or "[]") end)
	if not ok or type(list) ~= "table" then return end
	for k, ev in ipairs(list) do
		local accent = ev.Good and Color3.fromRGB(90, 230, 120) or Color3.fromRGB(255, 80, 80)
		local f = new("Frame", {
			Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y, LayoutOrder = k, BorderSizePixel = 0,
			BackgroundColor3 = ev.Good and Color3.fromRGB(20, 70, 35) or Color3.fromRGB(80, 18, 24), BackgroundTransparency = 0.15,
		}, eventsFrame)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, f)
		new("UIStroke", { Color = accent, Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, f)
		new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 6) }, f)
		new("UIListLayout", { SortOrder = Enum.SortOrder.LayoutOrder }, f)
		local title = new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, TextXAlignment = Enum.TextXAlignment.Left,
			TextColor3 = accent, Font = Enum.Font.GothamBlack, TextSize = 15, Text = ev.Name, LayoutOrder = 1,
		}, f)
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true,
			TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = Color3.fromRGB(235, 235, 235), Font = Enum.Font.GothamMedium,
			TextSize = 13, Text = ev.Desc or "", LayoutOrder = 2,
		}, f)
		table.insert(eventRows, { Frame = f, Title = title, Ev = ev })
	end
end
workspace:GetAttributeChangedSignal("Events"):Connect(rebuildEvents)
rebuildEvents()
RunService.Heartbeat:Connect(function()
	local now = workspace:GetServerTimeNow()
	for _, r in ipairs(eventRows) do
		local left = math.max(0, math.ceil((r.Ev.EndsAt or now) - now))
		r.Title.Text = (r.Ev.Good and "+ " or "! ") .. r.Ev.Name .. "   " .. left .. "s"
	end
end)

-- earthquake camera shake
local shakeUntil = 0
workspace:GetAttributeChangedSignal("Quake"):Connect(function() shakeUntil = os.clock() + 1.6 end)
RunService:BindToRenderStep("QuakeShake", Enum.RenderPriority.Camera.Value + 1, function()
	local left = shakeUntil - os.clock()
	if left > 0 then
		local a = left / 1.6 * 0.7
		camera.CFrame = camera.CFrame * CFrame.new((math.random() - 0.5) * a, (math.random() - 0.5) * a, 0)
	end
end)

-- game over banner
local overBanner = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.4), Size = UDim2.fromOffset(520, 80),
	BackgroundColor3 = Color3.fromRGB(120, 20, 20), BackgroundTransparency = 0.15, BorderSizePixel = 0,
	TextColor3 = Color3.new(1, 1, 1), Font = Enum.Font.GothamBlack, TextSize = 28, Visible = false,
	Text = "THE CITY HAS FALLEN\nRestarting...",
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 10) }, overBanner)

---------------------------------------------------------------- build bar
local Models = require(RS:WaitForChild("Shared"):WaitForChild("Models"))
local DEFAULT_INFO = "Pick something to build (hold to paint). Click a unit, or drag a box around several, to move them. Q/E/R = abilities, C = deselect."
local GOLD = Color3.fromRGB(255, 210, 90)
local CARD_BG = Color3.fromRGB(30, 33, 44)
local CARD_HOVER = Color3.fromRGB(44, 48, 63)
local STROKE_IDLE = Color3.fromRGB(60, 64, 82)
local STROKE_ON = Color3.fromRGB(255, 214, 90)
local KIND_STYLE = {
	Wall    = { Tag = "DEFENSE", Color = Color3.fromRGB(165, 170, 185) },
	Trap    = { Tag = "TRAP",    Color = Color3.fromRGB(235, 135, 55) },
	Tower   = { Tag = "TOWER",   Color = Color3.fromRGB(230, 85, 85) },
	Monster = { Tag = "UNIT",    Color = Color3.fromRGB(95, 205, 105) },
	Farm    = { Tag = "ECONOMY", Color = Color3.fromRGB(245, 200, 70) },
	Terrain = { Tag = "TERRAIN", Color = Color3.fromRGB(75, 155, 235) },
	Sell    = { Tag = "SELL",    Color = Color3.fromRGB(225, 75, 75) },
}

-- hint line above the bar
local info = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -124), Size = UDim2.fromOffset(0, 26),
	AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.2,
	BorderSizePixel = 0, TextColor3 = Color3.fromRGB(225, 228, 240), Font = Enum.Font.GothamMedium, TextSize = 14,
	Text = DEFAULT_INFO,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, info)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, info)
trackHover(info)

local order = {}
for _, def in ipairs(Config.Items) do table.insert(order, def.Id) end
table.insert(order, "SELL")

local CARD_W, CARD_H, GAP = 76, 94, 6
local hotbar = new("ScrollingFrame", {
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(0.98, 0, 0, CARD_H + 14),
	BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.15, BorderSizePixel = 0, ScrollBarThickness = 0,
	AutomaticCanvasSize = Enum.AutomaticSize.X, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.X,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 14) }, hotbar)
new("UIStroke", { Color = Color3.fromRGB(50, 54, 70), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, hotbar)
new("UISizeConstraint", { MaxSize = Vector2.new(#order * (CARD_W + GAP) + 14, CARD_H + 14) }, hotbar)
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, hotbar)
new("UIListLayout", {
	FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, GAP), SortOrder = Enum.SortOrder.LayoutOrder,
	HorizontalAlignment = Enum.HorizontalAlignment.Center, VerticalAlignment = Enum.VerticalAlignment.Center,
}, hotbar)
trackHover(hotbar)

-- "put it away" button, shown above the left end of the bar while you hold something
local cancelBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0, 1), Size = UDim2.fromOffset(0, 32), AutomaticSize = Enum.AutomaticSize.X,
	BackgroundColor3 = Color3.fromRGB(170, 45, 50), AutoButtonColor = true, BorderSizePixel = 0, Selectable = false,
	Font = Enum.Font.GothamBold, TextSize = 14, TextColor3 = Color3.new(1, 1, 1),
	Text = "X   Cancel", Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 8) }, cancelBtn)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 12) }, cancelBtn)
trackHover(cancelBtn)
local function placeCancelBtn()
	local x = hotbar.AbsolutePosition.X - gui.AbsolutePosition.X
	local y = hotbar.AbsolutePosition.Y - gui.AbsolutePosition.Y - 8
	cancelBtn.Position = UDim2.fromOffset(x, y)
end
hotbar:GetPropertyChangedSignal("AbsolutePosition"):Connect(placeCancelBtn)
hotbar:GetPropertyChangedSignal("AbsoluteSize"):Connect(placeCancelBtn)
task.defer(placeCancelBtn)

-- little 3D preview of the real model
local function makeIcon(def, parent)
	local vp = new("ViewportFrame", {
		Position = UDim2.fromOffset(4, 7), Size = UDim2.new(1, -8, 0, 52), BorderSizePixel = 0,
		BackgroundColor3 = Color3.fromRGB(22, 24, 33), Ambient = Color3.fromRGB(165, 165, 175),
		LightColor = Color3.new(1, 1, 1), LightDirection = Vector3.new(-1, -2, 1),
	}, parent)
	new("UICorner", { CornerRadius = UDim.new(0, 8) }, vp)
	local model
	if def.Kind == "Terrain" then
		model = Instance.new("Model")
		local grass = new("Part", { Anchored = true, Size = Vector3.new(5, 0.5, 5), Position = Vector3.new(0, -0.3, 0), Color = Color3.fromRGB(96, 176, 64), Material = Enum.Material.Grass }, model)
		new("Part", { Anchored = true, Size = Vector3.new(3.6, 0.5, 3.6), Position = Vector3.new(0, -0.1, 0), Color = def.Color,
			Material = (def.TerrainType == "Mud") and Enum.Material.Ground or Enum.Material.SmoothPlastic }, model)
		model.PrimaryPart = grass
	else
		model = Models.Building(def, Vector3.zero)
	end
	for _, d in ipairs(model:GetDescendants()) do
		if d:IsA("BillboardGui") then d:Destroy() end
	end
	model.Parent = vp
	local cam = Instance.new("Camera")
	cam.FieldOfView = 30
	cam.Parent = vp
	vp.CurrentCamera = cam
	local cf, size = model:GetBoundingBox()
	local dir = Vector3.new(0.9, 0.85, -1.1).Unit   -- models face -Z, so look at their front
	cam.CFrame = CFrame.lookAt(cf.Position + dir * size.Magnitude * 1.8, cf.Position)
	return vp
end

local buttons = {}
local function makeCard(id, n)
	local isSell = id == "SELL"
	local def = Config.ItemsById[id]
	local style = isSell and KIND_STYLE.Sell or KIND_STYLE[def.Kind]
	local card = new("TextButton", {
		Name = id, Size = UDim2.fromOffset(CARD_W, CARD_H), BackgroundColor3 = CARD_BG, AutoButtonColor = false,
		Text = "", LayoutOrder = n, BorderSizePixel = 0, Selectable = false,
	}, hotbar)
	new("UICorner", { CornerRadius = UDim.new(0, 10) }, card)
	local stroke = new("UIStroke", { Color = STROKE_IDLE, Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, card)
	-- category colour strip along the top
	local strip = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 2), Size = UDim2.new(1, -24, 0, 3),
		BackgroundColor3 = style.Color, BorderSizePixel = 0,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(1, 0) }, strip)

	local icon
	if isSell then
		icon = new("Frame", {
			Position = UDim2.fromOffset(4, 7), Size = UDim2.new(1, -8, 0, 52), BackgroundColor3 = Color3.fromRGB(60, 24, 30), BorderSizePixel = 0,
		}, card)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, icon)
		new("TextLabel", {
			Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 30,
			TextColor3 = Color3.fromRGB(255, 120, 120), Text = "$",
		}, icon)
	else
		icon = makeIcon(def, card)
	end

	local nameLabel = new("TextLabel", {
		Position = UDim2.fromOffset(4, 61), Size = UDim2.new(1, -8, 0, 15), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextScaled = true, TextColor3 = Color3.new(1, 1, 1),
		Text = isSell and "Sell" or def.Name,
	}, card)
	new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, nameLabel)
	local costLabel = new("TextLabel", {
		Position = UDim2.fromOffset(4, 76), Size = UDim2.new(1, -8, 0, 13), BackgroundTransparency = 1,
		Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = GOLD,
		Text = isSell and (math.floor(Config.SellRefund * 100) .. "% back") or ("$" .. def.Cost),
	}, card)
	local key = isSell and "X" or ((n <= 9) and tostring(n) or "0")
	local badge = new("TextLabel", {
		Position = UDim2.fromOffset(7, 10), Size = UDim2.fromOffset(16, 16), BackgroundColor3 = Color3.fromRGB(10, 12, 18),
		BackgroundTransparency = 0.2, Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.fromRGB(205, 210, 225), Text = key,
	}, card)
	new("UICorner", { CornerRadius = UDim.new(0, 4) }, badge)
	return { Card = card, Stroke = stroke, Icon = icon, Cost = costLabel, Def = def }
end

---------------------------------------------------------------- tooltip
local tip = new("Frame", {
	AnchorPoint = Vector2.new(0.5, 1), Size = UDim2.fromOffset(290, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(18, 20, 28), BackgroundTransparency = 0.04, BorderSizePixel = 0, Visible = false,
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 12) }, tip)
new("UIStroke", { Color = Color3.fromRGB(70, 75, 95), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, tip)
new("UIPadding", { PaddingLeft = UDim.new(0, 14), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 12), PaddingBottom = UDim.new(0, 12) }, tip)
new("UIListLayout", { Padding = UDim.new(0, 7), SortOrder = Enum.SortOrder.LayoutOrder }, tip)

local tipHead = new("Frame", { Size = UDim2.new(1, 0, 0, 22), BackgroundTransparency = 1, LayoutOrder = 1 }, tip)
local tipName = new("TextLabel", {
	Size = UDim2.new(1, -90, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18,
	TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = "",
}, tipHead)
local tipTag = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, 0, 0.5, 0), Size = UDim2.fromOffset(0, 18), AutomaticSize = Enum.AutomaticSize.X,
	Font = Enum.Font.GothamBold, TextSize = 11, TextColor3 = Color3.fromRGB(20, 20, 26), Text = "", BorderSizePixel = 0,
}, tipHead)
new("UICorner", { CornerRadius = UDim.new(0, 5) }, tipTag)
new("UIPadding", { PaddingLeft = UDim.new(0, 7), PaddingRight = UDim.new(0, 7) }, tipTag)
local tipDesc = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true,
	Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = Color3.fromRGB(200, 205, 220), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", LayoutOrder = 2,
}, tip)
new("Frame", { Size = UDim2.new(1, 0, 0, 1), BackgroundColor3 = Color3.fromRGB(55, 59, 76), BorderSizePixel = 0, LayoutOrder = 3 }, tip)
local tipStats = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 4 }, tip)
new("UIListLayout", { Padding = UDim.new(0, 3), SortOrder = Enum.SortOrder.LayoutOrder }, tipStats)
local tipHint = new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true,
	Font = Enum.Font.GothamMedium, TextSize = 12, TextColor3 = Color3.fromRGB(135, 140, 160), TextXAlignment = Enum.TextXAlignment.Left,
	Text = "", LayoutOrder = 5,
}, tip)

local function fmt(x)
	if x == math.floor(x) then return tostring(x) end
	return string.format("%.1f", x)
end

-- the numbers shown for each item
local function statsFor(def)
	local s = {}
	local function add(label, value, color) table.insert(s, { label, value, color }) end
	if def.HP then add("Health", fmt(def.HP) .. " HP", Color3.fromRGB(120, 230, 120)) end
	if def.Damage then
		add("Damage", fmt(def.Damage) .. (def.Splash and " + splash" or "") .. " per hit", Color3.fromRGB(255, 135, 115))
		add("Attack speed", "every " .. fmt(def.Interval) .. "s")
		add("Damage per second", fmt(math.floor(def.Damage / def.Interval * 10 + 0.5) / 10))
	end
	if def.Kind == "Trap" then
		add("Hits", "enemies on its tile")
	elseif def.Range then
		add("Range", fmt(def.Range) .. " tiles")
	end
	if def.Attack == "Spear" then
		add("Attack", "spear: hits a whole line")
	elseif def.Attack == "Sweep" then
		add("Attack", "sweep: hits all in front")
	end
	if def.Income then
		add("Income", "$" .. def.Income .. "-$" .. (def.Income + def.Bonus * def.MaxBonusWaves) .. " per wave", GOLD)
	end
	if def.WalkSpeed then add("Walk speed", fmt(def.WalkSpeed / Config.Cell) .. " tiles/s") end
	if def.TerrainType == "Mud" then add("Effect", "enemies 50% slower") end
	if def.TerrainType == "Water" then add("Effect", "blocks most enemies") end
	add("Blocks the path", def.Blocks and "yes" or "no")
	add("Build time", (def.Kind == "Monster") and "instant, no builder" or (fmt(def.BuildTime or 0) .. "s"))
	add("Cost", "$" .. def.Cost, GOLD)
	return s
end

local tipFor = nil
local hovered = nil
local function showTip(id)
	local entry = buttons[id]
	if not entry then return end
	if tipFor ~= id then
		tipFor = id
		for _, c in ipairs(tipStats:GetChildren()) do
			if c:IsA("Frame") then c:Destroy() end
		end
		local rows
		if id == "SELL" then
			tipName.Text = "Sell"
			tipTag.Text = KIND_STYLE.Sell.Tag
			tipTag.BackgroundColor3 = KIND_STYLE.Sell.Color
			tipDesc.Text = "Get coins back for your own buildings or terrain. Cancelling something that's still being built refunds everything."
			rows = { { "Refund", math.floor(Config.SellRefund * 100) .. "% (less if damaged)", GOLD }, { "Cancel a build", "100% back", GOLD } }
			tipHint.Text = "Click your building to sell it. Hotkey X."
		else
			local def = entry.Def
			local style = KIND_STYLE[def.Kind]
			tipName.Text = def.Name
			tipTag.Text = style.Tag
			tipTag.BackgroundColor3 = style.Color
			tipDesc.Text = def.Short or def.Desc
			rows = statsFor(def)
			tipHint.Text = (def.Kind == "Monster") and "Click a tile and it appears right away. Later, click it to walk it somewhere."
				or "Click a tile to place it. Hold the mouse to place several."
		end
		for k, r in ipairs(rows) do
			local row = new("Frame", { Size = UDim2.new(1, 0, 0, 17), BackgroundTransparency = 1, LayoutOrder = k }, tipStats)
			new("TextLabel", {
				Size = UDim2.new(0.45, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 13,
				TextColor3 = Color3.fromRGB(145, 150, 172), TextXAlignment = Enum.TextXAlignment.Left, Text = r[1],
			}, row)
			new("TextLabel", {
				Position = UDim2.fromScale(0.45, 0), Size = UDim2.new(0.55, 0, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
				TextSize = 13, TextColor3 = r[3] or Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Right, Text = r[2],
			}, row)
		end
	end
	-- sit just above the card, kept on screen
	local card = entry.Card
	local half = tip.AbsoluteSize.X / 2
	local x = card.AbsolutePosition.X + card.AbsoluteSize.X / 2 - gui.AbsolutePosition.X
	x = math.clamp(x, half + 8, math.max(half + 8, gui.AbsoluteSize.X - half - 8))
	local y = hotbar.AbsolutePosition.Y - gui.AbsolutePosition.Y - 10
	tip.Position = UDim2.fromOffset(x, y)
	tip.Visible = true
	info.Visible = false
end

local function hideTip()
	tip.Visible = false
	tipFor = nil
	info.Visible = true
end

local tipToken = 0
local function setSelected(id)
	selected = id
	if id then
		selectedUnit = nil
		table.clear(selectedUnits)
	end
	cancelBtn.Visible = (id ~= nil) or (selectedUnit ~= nil)
	for key, b in pairs(buttons) do
		local on = key == id
		b.Stroke.Color = on and STROKE_ON or STROKE_IDLE
		b.Stroke.Thickness = on and 2 or 1
		b.Card.BackgroundColor3 = (on or key == hovered) and CARD_HOVER or CARD_BG
	end
	if id == "SELL" then
		info.Text = "Selling: click your own building or terrain. Q = cancel."
	elseif id then
		info.Text = "Placing " .. Config.ItemsById[id].Name .. ": click a tile (hold to paint). Q = cancel."
	else
		info.Text = DEFAULT_INFO
	end
	-- briefly show the tooltip on select (so touch players see it too), then get out of the way
	if id then
		showTip(id)
		tipToken += 1
		local my = tipToken
		task.delay(3, function()
			if tipToken == my and hovered == nil then hideTip() end
		end)
	elseif hovered == nil then
		hideTip()
	end
end

-- pick it, or put it away if it's already picked
local function toggleSelected(id)
	if selected == id then
		setSelected(nil)
	else
		setSelected(id)
	end
end

for n, id in ipairs(order) do
	local entry = makeCard(id, n)
	buttons[id] = entry
	entry.Card.MouseEnter:Connect(function()
		hovered = id
		entry.Card.BackgroundColor3 = CARD_HOVER
		showTip(id)
	end)
	entry.Card.MouseLeave:Connect(function()
		if hovered == id then hovered = nil end
		if selected ~= id then entry.Card.BackgroundColor3 = CARD_BG end
		if hovered == nil then hideTip() end
	end)
	entry.Card.Activated:Connect(function()
		toggleSelected(id)
	end)
end

-- dim what you can't afford
local function refreshAfford()
	for _, b in pairs(buttons) do
		if b.Def then
			local ok = coinsValue.Value >= b.Def.Cost
			b.Cost.TextColor3 = ok and GOLD or Color3.fromRGB(255, 95, 95)
			if b.Icon:IsA("ViewportFrame") then b.Icon.ImageTransparency = ok and 0 or 0.6 end
		end
	end
end
coinsValue.Changed:Connect(refreshAfford)
refreshAfford()

---------------------------------------------------------------- state -> UI
local function refreshHUD()
	local wave = workspace:GetAttribute("Wave") or 1
	local phase = workspace:GetAttribute("Phase") or "Build"
	local hp = workspace:GetAttribute("CityHP") or Config.CityHP
	local maxHp = workspace:GetAttribute("CityMaxHP") or Config.CityHP

	if phase == "Build" then
		waveLabel.Text = "Wave " .. wave .. "  -  Build phase: " .. (workspace:GetAttribute("Timer") or 0) .. "s"
	elseif phase == "Wave" then
		waveLabel.Text = "Wave " .. wave .. "  -  Enemies left: " .. (workspace:GetAttribute("Enemies") or 0)
	elseif phase == "Victory" then
		waveLabel.Text = "VICTORY - the city is saved!"
	else
		waveLabel.Text = "Game over - reached wave " .. wave
	end

	hpFill.Size = UDim2.fromScale(math.clamp(hp / maxHp, 0, 1), 1)
	hpText.Text = "City HP  " .. hp .. " / " .. maxHp

	readyBtn.Visible = (phase == "Build")
	readyBtn.Text = "Start wave early (" .. (workspace:GetAttribute("ReadyCount") or 0) .. "/" .. (workspace:GetAttribute("ReadyNeed") or 1) .. ")"
	overBanner.Visible = (phase == "GameOver")

	local tradeActive = workspace:GetAttribute("TradeActive") == true
	tradeFrame.Visible = tradeActive and phase ~= "GameOver"
	if tradeActive then
		local thp, tmax = workspace:GetAttribute("TradeHP") or 0, workspace:GetAttribute("TradeMax") or 1
		tradeFill.Size = UDim2.fromScale(math.clamp(thp / math.max(tmax, 1), 0, 1), 1)
		local state = workspace:GetAttribute("TradeMoving") and "TRADE TRUCK rolling - protect it!" or "TRADE ROUTE open - the truck leaves when the wave starts"
		tradeLabel.Text = state .. "   Hits left: " .. thp .. "/" .. tmax
	end
end
for _, a in ipairs({ "Wave", "Phase", "Timer", "CityHP", "CityMaxHP", "Enemies", "ReadyCount", "ReadyNeed", "TradeActive", "TradeMoving", "TradeHP", "TradeMax" }) do
	workspace:GetAttributeChangedSignal(a):Connect(refreshHUD)
end
refreshHUD()

local function refreshCoins()
	coinsLabel.Text = "Coins: " .. coinsValue.Value
end
coinsValue.Changed:Connect(refreshCoins)
refreshCoins()

-- builders busy / queue size
local buildLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 52), Size = UDim2.fromOffset(240, 24),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0,
	TextColor3 = Color3.fromRGB(170, 210, 255), Font = Enum.Font.GothamBold, TextSize = 13, Text = "",
}, gui)
new("UICorner", { CornerRadius = UDim.new(0, 6) }, buildLabel)
local function refreshBuild()
	local alive = player:GetAttribute("BuildersAlive") or Config.Builders
	local b, q = player:GetAttribute("Building") or 0, player:GetAttribute("Queued") or 0
	if alive == 0 then
		buildLabel.Text = "No builders left! New one after this wave"
		buildLabel.TextColor3 = Color3.fromRGB(255, 110, 110)
	else
		buildLabel.Text = "Builders " .. alive .. "/" .. Config.Builders .. "  -  " .. b .. " busy" .. ((q > 0) and (", " .. q .. " waiting") or "")
		buildLabel.TextColor3 = Color3.fromRGB(170, 210, 255)
	end
end
player:GetAttributeChangedSignal("BuildersAlive"):Connect(refreshBuild)
player:GetAttributeChangedSignal("Building"):Connect(refreshBuild)
player:GetAttributeChangedSignal("Queued"):Connect(refreshBuild)
refreshBuild()

---------------------------------------------------------------- ghost cursor
local ghost = new("Part", {
	Name = "PlacementGhost", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	Material = Enum.Material.Neon, Transparency = 0.6, Size = Vector3.new(CELL - 0.2, 0.4, CELL - 0.2),
}, nil)
local ring = new("Part", {
	Name = "RangeRing", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	Material = Enum.Material.Neon, Transparency = 0.85, Shape = Enum.PartType.Cylinder,
	Color = Color3.fromRGB(255, 255, 255),
}, nil)

---------------------------------------------------------------- unit selection
local buildingsFolder = workspace.Map:WaitForChild("Buildings")
local SelectBox = require(RS:WaitForChild("Shared"):WaitForChild("SelectBox"))
local box = SelectBox.new(playerGui)
-- Q / E / R abilities of the selected units (bar above the build bar)
local AbilityBar = require(RS:WaitForChild("Shared"):WaitForChild("AbilityBar"))
local abilityBar = AbilityBar.new(gui, {
	Position = UDim2.new(0.5, 0, 1, -158), IdAttr = "Id", PlaneY = TOP, InDungeon = false,
	GetUnits = function()
		if selected or player:GetAttribute("ViewDungeon") == true then return {} end
		return selectedUnits
	end,
})
-- blue rings under the selected units (one per unit, reused)
local unitRings = {}
local function unitRing(k)
	local r = unitRings[k]
	if not r then
		r = new("Part", {
			Name = "UnitSelectRing", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
			Material = Enum.Material.Neon, Transparency = 0.3, Shape = Enum.PartType.Cylinder,
			Color = Color3.fromRGB(80, 170, 255), Size = Vector3.new(0.15, CELL * 0.95, CELL * 0.95),
		}, nil)
		unitRings[k] = r
	end
	return r
end
local function hideUnitRings(from)
	for k = from or 1, #unitRings do
		if unitRings[k].Parent then unitRings[k].Parent = nil end
	end
end
local moveFlag = new("Part", {
	Name = "MoveFlag", Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false,
	Material = Enum.Material.Neon, Transparency = 0.2, Color = Color3.fromRGB(80, 170, 255),
	Size = Vector3.new(0.4, 3, 0.4),
}, nil)
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include
rayParams.FilterDescendantsInstances = { buildingsFolder }

local function isMyUnit(m)
	return m ~= nil and m.Parent == buildingsFolder and m:GetAttribute("Kind") == "Monster" and m:GetAttribute("Owner") == player.UserId
end

-- your unit under the cursor: by clicking its body, or the tile it stands on
local function unitFromRay(ray)
	local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
	local inst = hit and hit.Instance
	while inst and inst.Parent ~= buildingsFolder do inst = inst.Parent end
	if isMyUnit(inst) then return inst end
	local i, j = cellFromRay(ray)
	if i then
		local tile = tiles:FindFirstChild(i .. "_" .. j)
		local id = tile and tile:GetAttribute("BId")
		if id and id ~= 0 and tile:GetAttribute("BKind") == "Monster" and tile:GetAttribute("BOwner") == player.UserId then
			for _, m in ipairs(buildingsFolder:GetChildren()) do
				if m:GetAttribute("Id") == id then return m end
			end
		end
	end
	return nil
end

local function selectUnits(list)
	table.clear(selectedUnits)
	for _, m in ipairs(list) do table.insert(selectedUnits, m) end
	selectedUnit = selectedUnits[1]
	if not selected then setSelected(nil) end   -- refreshes the hint line and Cancel button
	if #selectedUnits == 1 then
		local def = Config.ItemsById[selectedUnit.Name]
		info.Text = (def and def.Name or selectedUnit.Name) .. " selected: click a tile to walk there. Q / E / R = abilities, C = deselect."
	elseif #selectedUnits > 1 then
		info.Text = #selectedUnits .. " units selected: click a tile to send them. Q / E / R = abilities, C = deselect."
	end
end
local function selectUnit(m)
	selectUnits(m and { m } or {})
end
-- Shift-click adds or removes one unit
local function toggleUnit(m)
	local list = table.clone(selectedUnits)
	local k = table.find(list, m)
	if k then table.remove(list, k) else table.insert(list, m) end
	selectUnits(list)
end

-- the Cancel button puts away whatever you're holding (building or unit selection)
cancelBtn.Activated:Connect(function()
	setSelected(nil)
	selectUnit(nil)
	overUI = false
end)

local flagToken = 0
local orderMove -- (below)

-- a plain click with nothing from the bar picked: select a unit, or send the selected ones
local function clickUnits(ray)
	local unit = unitFromRay(ray)
	if unit then
		if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then toggleUnit(unit) else selectUnit(unit) end
	elseif #selectedUnits > 0 then
		local ui, uj = cellFromRay(ray)
		if ui then orderMove(ui, uj) end
	end
end

function orderMove(i, j)
	local ids = {}
	for _, m in ipairs(selectedUnits) do
		if m.Parent then table.insert(ids, m:GetAttribute("Id")) end
	end
	if #ids == 0 then
		selectUnit(nil)
		return
	end
	moveRemote:FireServer(ids, i, j)
	moveFlag.Position = cellCenter(i, j) + Vector3.new(0, 1.5, 0)
	moveFlag.Parent = workspace
	flagToken += 1
	local my = flagToken
	task.delay(1.2, function()
		if flagToken == my then moveFlag.Parent = nil end
	end)
end

local function cellValid(i, j)
	local tile = tiles:FindFirstChild(i .. "_" .. j)
	if not tile then return false end
	local occ = tile:GetAttribute("Occupied")
	local ter = tile:GetAttribute("Terrain")

	if selected == "SELL" then
		if occ then return tile:GetAttribute("BOwner") == player.UserId end
		if ter and ter ~= "Grass" then return tile:GetAttribute("TOwner") == player.UserId end
		return false
	end

	local def = Config.ItemsById[selected]
	if not def then return false end
	if tile:GetAttribute("Route") then return false end
	if coinsValue.Value < def.Cost then return false end
	if def.Kind ~= "Monster" and (player:GetAttribute("BuildersAlive") or 1) == 0 then return false end
	if Config.IsCity(i, j) or Config.IsSpawn(i, j) then return false end
	if occ then return false end
	if def.Kind == "Terrain" then
		return ter == "Grass"
	end
	return ter ~= "Water"
end

local hoverI, hoverJ = nil, nil
local painting = false
local lastI, lastJ = nil, nil

local function act(i, j)
	if not selected or not i then return end
	if selected == "SELL" then
		sellRemote:FireServer(i, j)
	else
		placeRemote:FireServer(selected, i, j)
	end
end

RunService.RenderStepped:Connect(function()
	local mp = UIS:GetMouseLocation()
	local ray = camera:ViewportPointToRay(mp.X, mp.Y)
	hoverI, hoverJ = cellFromRay(ray)
	if player:GetAttribute("ViewDungeon") then
		ghost.Parent = nil
		ring.Parent = nil
		hideUnitRings()
		return
	end

	if selected and hoverI and not overUI then
		local c = cellCenter(hoverI, hoverJ)
		local ok = cellValid(hoverI, hoverJ)
		ghost.Position = c + Vector3.new(0, 0.2, 0)
		ghost.Color = ok and Color3.fromRGB(80, 255, 120) or Color3.fromRGB(255, 70, 70)
		if selected == "SELL" then ghost.Color = ok and Color3.fromRGB(255, 190, 60) or Color3.fromRGB(255, 70, 70) end
		ghost.Parent = workspace

		local def = Config.ItemsById[selected]
		if def and def.Range then
			local r = def.Range * CELL
			ring.Size = Vector3.new(0.2, r * 2, r * 2)
			ring.CFrame = CFrame.new(c + Vector3.new(0, 0.2, 0)) * CFrame.Angles(0, 0, math.pi / 2)
			ring.Parent = workspace
		else
			ring.Parent = nil
		end

		-- paint while dragging
		if painting and (hoverI ~= lastI or hoverJ ~= lastJ) then
			lastI, lastJ = hoverI, hoverJ
			act(hoverI, hoverJ)
		end
	else
		ring.Parent = nil
		-- commanding a unit: blue marker where it would walk to
		-- (only change Parent when needed: re-parenting every frame makes it flicker)
		if not (not selected and selectedUnit and hoverI and not overUI) then
			ghost.Parent = nil
		else
			local tile = tiles:FindFirstChild(hoverI .. "_" .. hoverJ)
			local ok = tile ~= nil and not tile:GetAttribute("Occupied") and tile:GetAttribute("Terrain") ~= "Water"
				and not tile:GetAttribute("Route") and not Config.IsCity(hoverI, hoverJ) and not Config.IsSpawn(hoverI, hoverJ)
			ghost.Position = cellCenter(hoverI, hoverJ) + Vector3.new(0, 0.2, 0)
			ghost.Color = ok and Color3.fromRGB(80, 170, 255) or Color3.fromRGB(255, 70, 70)
			ghost.Parent = workspace
		end
	end

	-- selection rings follow the commanded units (units that died drop out of the selection)
	local alive = {}
	for _, m in ipairs(selectedUnits) do
		if m.Parent then table.insert(alive, m) end
	end
	if #alive ~= #selectedUnits then selectUnits(alive) end
	for k, m in ipairs(selectedUnits) do
		local r = unitRing(k)
		local p = m:GetPivot().Position
		r.CFrame = CFrame.new(p.X, TOP + 0.12, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
		if r.Parent ~= workspace then r.Parent = workspace end
	end
	hideUnitRings(#selectedUnits + 1)
end)

---------------------------------------------------------------- input
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if player:GetAttribute("ViewDungeon") then return end   -- the dungeon screen handles clicks there
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		if not selected then
			-- nothing picked from the bar: select / command units
			if t == Enum.UserInputType.Touch then
				clickUnits(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
			else
				-- wait for the release: dragging draws a selection box, a plain click selects or moves
				box.begin(UIS:GetMouseLocation())
			end
			return
		end
		local i, j
		if t == Enum.UserInputType.Touch then
			i, j = cellFromRay(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
		else
			i, j = hoverI, hoverJ
		end
		if i then
			painting = true
			lastI, lastJ = i, j
			act(i, j)
		end
	elseif t == Enum.UserInputType.MouseButton2 then
		if not selected and selectedUnit and hoverI and not overUI then orderMove(hoverI, hoverJ) end
	elseif t == Enum.UserInputType.Keyboard then
		local k = input.KeyCode
		local map = {
			[Enum.KeyCode.One] = 1, [Enum.KeyCode.Two] = 2, [Enum.KeyCode.Three] = 3, [Enum.KeyCode.Four] = 4,
			[Enum.KeyCode.Five] = 5, [Enum.KeyCode.Six] = 6, [Enum.KeyCode.Seven] = 7, [Enum.KeyCode.Eight] = 8,
			[Enum.KeyCode.Nine] = 9, [Enum.KeyCode.Zero] = 10,
		}
		if map[k] and order[map[k]] then
			local id = order[map[k]]
			toggleSelected(id)
		elseif k == Enum.KeyCode.X then
			toggleSelected("SELL")
		elseif (k == Enum.KeyCode.Q or k == Enum.KeyCode.E or k == Enum.KeyCode.R) and not selected and #selectedUnits > 0 then
			abilityBar:cast(k.Name)   -- unit abilities
		elseif k == Enum.KeyCode.Q then
			setSelected(nil)          -- put away the building you're holding
		elseif k == Enum.KeyCode.C then
			setSelected(nil)
			selectUnit(nil)
		end
	end
end)

UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		box.update(UIS:GetMouseLocation())
	end
end)

UIS.InputEnded:Connect(function(input)
	local t = input.UserInputType
	if t == Enum.UserInputType.MouseButton1 or t == Enum.UserInputType.Touch then
		painting = false
		lastI, lastJ = nil, nil
	end
	if t == Enum.UserInputType.MouseButton1 and box.active() then
		local mp = UIS:GetMouseLocation()
		local dragged, a, b = box.finish(mp)
		if player:GetAttribute("ViewDungeon") or selected then return end
		if dragged then
			-- select every one of your units inside the box (Shift = add to the selection)
			local list = UIS:IsKeyDown(Enum.KeyCode.LeftShift) and table.clone(selectedUnits) or {}
			for _, m in ipairs(buildingsFolder:GetChildren()) do
				if isMyUnit(m) and not m:GetAttribute("Building") and not table.find(list, m) then
					local sp, onScreen = camera:WorldToViewportPoint(m:GetPivot().Position)
					if onScreen and box.contains(a, b, sp) then table.insert(list, m) end
				end
			end
			selectUnits(list)
		else
			clickUnits(camera:ViewportPointToRay(mp.X, mp.Y))
		end
	end
end)

-- while you watch the dungeon, the base's build bar steps aside
local function applyDungeonView()
	local v = player:GetAttribute("ViewDungeon") == true
	if v then
		setSelected(nil)
		selectUnit(nil)
		painting = false
	end
	hotbar.Visible = not v
	info.Visible = not v
	tip.Visible = false
	cancelBtn.Visible = false
end
player:GetAttributeChangedSignal("ViewDungeon"):Connect(applyDungeonView)
