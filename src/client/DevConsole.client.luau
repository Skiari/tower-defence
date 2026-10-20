-- Test console: buttons for testing the game quickly.
-- Only shows up in Studio or for the game's owner (the server checks this too). Open with the DEV button or F2.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")

local player = Players.LocalPlayer
if player:GetAttribute("IsDev") == nil then player:GetAttributeChangedSignal("IsDev"):Wait() end
if not player:GetAttribute("IsDev") then return end

local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local remote = RS:WaitForChild("Remotes"):WaitForChild("DevCommand")

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r) new("UICorner", { CornerRadius = UDim.new(0, r or 6) }, o) end

local gui = new("ScreenGui", { Name = "DevConsoleUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 20 }, player:WaitForChild("PlayerGui"))

-- small DEV button above the minimap
local openBtn = new("TextButton", {
	AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -264), Size = UDim2.fromOffset(86, 28),
	BackgroundColor3 = Color3.fromRGB(200, 70, 40), BorderSizePixel = 0, TextColor3 = Color3.new(1, 1, 1),
	Font = Enum.Font.GothamBlack, TextSize = 13, Text = "DEV (F2)", Selectable = false,
}, gui)
corner(openBtn)

local panel = new("ScrollingFrame", {
	AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -12, 0.56, 0), Size = UDim2.fromOffset(340, 560),
	BackgroundColor3 = Color3.fromRGB(16, 16, 22), BackgroundTransparency = 0.05, BorderSizePixel = 0, Visible = false, Active = true,
	ScrollBarThickness = 6, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ScrollingDirection = Enum.ScrollingDirection.Y,
}, gui)
corner(panel, 12)
new("UIStroke", { Color = Color3.fromRGB(200, 70, 40), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, panel)
new("UIPadding", { PaddingLeft = UDim.new(0, 12), PaddingRight = UDim.new(0, 14), PaddingTop = UDim.new(0, 10), PaddingBottom = UDim.new(0, 12) }, panel)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, panel)

local order = 0
local function nextOrder() order += 1 return order end

new("TextLabel", {
	Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18,
	TextColor3 = Color3.fromRGB(255, 140, 90), TextXAlignment = Enum.TextXAlignment.Left, Text = "TEST CONSOLE", LayoutOrder = nextOrder(),
}, panel)

local function section(title)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 12,
		TextColor3 = Color3.fromRGB(150, 155, 175), TextXAlignment = Enum.TextXAlignment.Left, Text = string.upper(title), LayoutOrder = nextOrder(),
	}, panel)
	local grid = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = nextOrder() }, panel)
	new("UIGridLayout", { CellSize = UDim2.new(1 / 3, -4, 0, 30), CellPadding = UDim2.fromOffset(5, 5), SortOrder = Enum.SortOrder.LayoutOrder }, grid)
	return grid
end

local function button(grid, text, cmd, arg, color)
	local b = new("TextButton", {
		BackgroundColor3 = color or Color3.fromRGB(45, 48, 62), BorderSizePixel = 0, TextColor3 = Color3.new(1, 1, 1),
		Font = Enum.Font.GothamBold, TextScaled = true, Text = text, Selectable = false,
	}, grid)
	corner(b)
	new("UITextSizeConstraint", { MaxTextSize = 12, MinTextSize = 8 }, b)
	new("UIPadding", { PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }, b)
	if cmd then
		b.Activated:Connect(function() remote:FireServer(cmd, arg) end)
	end
	return b
end

local GOLD = Color3.fromRGB(150, 115, 30)
local RED = Color3.fromRGB(150, 45, 45)
local BLUE = Color3.fromRGB(40, 90, 150)
local PURPLE = Color3.fromRGB(100, 60, 150)

-- money
local g = section("Money")
button(g, "+1000 coins", "Coins", nil, GOLD)
button(g, "+10 crystals", "Crystals", nil, PURPLE)
button(g, "Max upgrades", "MaxUpgrades", nil, PURPLE)

-- waves
g = section("Waves")
button(g, "Start wave now", "StartWave", nil, BLUE)
button(g, "Kill all enemies", "KillAll", nil, RED)
button(g, "Heal city", "HealCity")
local godBtn = button(g, "God mode: OFF", "God")
local waveBox = new("TextBox", {
	BackgroundColor3 = Color3.fromRGB(28, 30, 40), BorderSizePixel = 0, TextColor3 = Color3.new(1, 1, 1), PlaceholderText = "wave #",
	PlaceholderColor3 = Color3.fromRGB(120, 125, 145), Font = Enum.Font.GothamBold, TextSize = 13, Text = "", ClearTextOnFocus = false,
}, g)
corner(waveBox)
local jumpBtn = button(g, "Jump to wave", nil, nil, BLUE)
jumpBtn.Activated:Connect(function() remote:FireServer("JumpWave", waveBox.Text) end)

-- building
g = section("Building")
local instantBtn = button(g, "Instant build: OFF", "Instant")
button(g, "+1 builder", "AddBuilder")
button(g, "Kill a builder", "KillBuilder", nil, RED)

-- enemies
g = section("Spawn enemy")
for _, name in ipairs({ "Grunt", "Runner", "Tank", "Climber", "Flyer", "Bomber", "Swimmer", "Champion", "Boss" }) do
	button(g, name, "Spawn", name, Color3.fromRGB(110, 40, 40))
end

-- random events
g = section("Random events")
for _, ev in ipairs(Config.Events) do
	button(g, ev.Name, "Event", ev.Id, ev.Good and Color3.fromRGB(40, 110, 60) or Color3.fromRGB(110, 50, 40))
end

-- other
g = section("Truck & dungeon")
button(g, "Trade truck now", "Trade", nil, GOLD)
button(g, "Open portal", "Portal", nil, Color3.fromRGB(30, 120, 150))
button(g, "Clear dungeon room", "DungeonRoom", nil, Color3.fromRGB(30, 120, 150))
button(g, "Final floor", "FinalFloor", nil, Color3.fromRGB(110, 50, 160))
button(g, "Random buff", "Buff", nil, Color3.fromRGB(150, 60, 50))

-- show the ON/OFF switches
local function refreshToggles()
	local god = workspace:GetAttribute("DevGod") == true
	godBtn.Text = "God mode: " .. (god and "ON" or "OFF")
	godBtn.BackgroundColor3 = god and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(45, 48, 62)
	local inst = workspace:GetAttribute("DevInstant") == true
	instantBtn.Text = "Instant build: " .. (inst and "ON" or "OFF")
	instantBtn.BackgroundColor3 = inst and Color3.fromRGB(40, 140, 70) or Color3.fromRGB(45, 48, 62)
end
workspace:GetAttributeChangedSignal("DevGod"):Connect(refreshToggles)
workspace:GetAttributeChangedSignal("DevInstant"):Connect(refreshToggles)
refreshToggles()

local function toggle()
	panel.Visible = not panel.Visible
end
openBtn.Activated:Connect(toggle)
UIS.InputBegan:Connect(function(input, processed)
	if processed then return end
	if input.KeyCode == Enum.KeyCode.F2 then toggle() end
end)
