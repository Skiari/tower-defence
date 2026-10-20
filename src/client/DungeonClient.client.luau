-- Dungeon screen: portal button, squad picker, crystal upgrades shop,
-- quarter-down dungeon camera and the dungeon controls.
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
local playerGui = player:WaitForChild("PlayerGui")
local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local remote = RS:WaitForChild("Remotes"):WaitForChild("Dungeon")
local crystals = player:WaitForChild("leaderstats"):WaitForChild("Crystals")
local camera = workspace.CurrentCamera

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end
local function corner(o, r)
	new("UICorner", { CornerRadius = UDim.new(0, r or 8) }, o)
end
local function pad(o, p)
	new("UIPadding", { PaddingLeft = UDim.new(0, p), PaddingRight = UDim.new(0, p), PaddingTop = UDim.new(0, p), PaddingBottom = UDim.new(0, p) }, o)
end

local PURPLE = Color3.fromRGB(190, 135, 255)
local PANEL = Color3.fromRGB(18, 20, 28)
local ROW = Color3.fromRGB(32, 35, 48)
local WHITE = Color3.new(1, 1, 1)
local GREY = Color3.fromRGB(150, 155, 175)

local gui = new("ScreenGui", { Name = "DungeonUI", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5 }, playerGui)

---------------------------------------------------------------- right column: crystals, upgrades, dungeon
local crystalLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 80), Size = UDim2.fromOffset(240, 24),
	BackgroundColor3 = Color3.fromRGB(20, 22, 30), BackgroundTransparency = 0.25, BorderSizePixel = 0,
	TextColor3 = PURPLE, Font = Enum.Font.GothamBold, TextSize = 14, Text = "",
}, gui)
corner(crystalLabel, 6)
local function refreshCrystals()
	crystalLabel.Text = "Crystals: " .. crystals.Value
end
crystals.Changed:Connect(refreshCrystals)
refreshCrystals()

local upgradesBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 108), Size = UDim2.fromOffset(240, 30),
	BackgroundColor3 = Color3.fromRGB(80, 55, 125), BorderSizePixel = 0, TextColor3 = WHITE,
	Font = Enum.Font.GothamBold, TextSize = 14, Text = "Upgrades", Selectable = false,
}, gui)
corner(upgradesBtn)

local dungeonBtn = new("TextButton", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 142), Size = UDim2.fromOffset(240, 36),
	BackgroundColor3 = Color3.fromRGB(30, 130, 160), BorderSizePixel = 0, TextColor3 = WHITE,
	Font = Enum.Font.GothamBlack, TextSize = 15, Text = "Enter Dungeon", Visible = false, Selectable = false,
}, gui)
corner(dungeonBtn)
new("UIStroke", { Color = Color3.fromRGB(120, 230, 255), Thickness = 1.5, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, dungeonBtn)

-- buffs won from the Warlord (shown under the buttons)
local buffLabel = new("TextLabel", {
	AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 184), Size = UDim2.fromOffset(240, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundColor3 = Color3.fromRGB(70, 25, 20), BackgroundTransparency = 0.15, BorderSizePixel = 0, TextWrapped = true,
	TextColor3 = Color3.fromRGB(255, 170, 120), Font = Enum.Font.GothamBold, TextSize = 13, Text = "", Visible = false,
}, gui)
corner(buffLabel, 6)
new("UIPadding", { PaddingLeft = UDim.new(0, 8), PaddingRight = UDim.new(0, 8), PaddingTop = UDim.new(0, 5), PaddingBottom = UDim.new(0, 5) }, buffLabel)
local function refreshBuffs()
	local list = player:GetAttribute("BuffList") or ""
	buffLabel.Visible = list ~= ""
	buffLabel.Text = "BUFFS: " .. list
end
player:GetAttributeChangedSignal("BuffList"):Connect(refreshBuffs)
refreshBuffs()

---------------------------------------------------------------- popup window helper
local function makeWindow(title, subtitle, width)
	local w = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.5), Size = UDim2.fromOffset(width, 0),
		AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL, BorderSizePixel = 0, Visible = false, Active = true,
	}, gui)
	corner(w, 14)
	new("UIStroke", { Color = Color3.fromRGB(80, 85, 110), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, w)
	pad(w, 16)
	new("UIListLayout", { Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder }, w)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 24), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 20,
		TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, Text = title, LayoutOrder = 1,
	}, w)
	new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true,
		Font = Enum.Font.Gotham, TextSize = 13, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left,
		Text = subtitle, LayoutOrder = 2,
	}, w)
	local body = new("Frame", { Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, LayoutOrder = 3 }, w)
	new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, body)
	local buttons = new("Frame", { Size = UDim2.new(1, 0, 0, 38), BackgroundTransparency = 1, LayoutOrder = 4 }, w)
	new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), HorizontalAlignment = Enum.HorizontalAlignment.Right }, buttons)
	return w, body, buttons
end

local function button(parent, text, color, width)
	local b = new("TextButton", {
		Size = UDim2.fromOffset(width or 140, 38), BackgroundColor3 = color, BorderSizePixel = 0, TextColor3 = WHITE,
		Font = Enum.Font.GothamBold, TextSize = 14, Text = text, Selectable = false,
	}, parent)
	corner(b)
	return b
end

---------------------------------------------------------------- squad picker
local picker, pickerBody, pickerButtons = makeWindow("Choose your dungeon squad",
	"The units you pick walk into the portal and leave your base. The rest stay home to defend. Units that fall in the dungeon have to be revived there.", 400)
local pickerCancel = button(pickerButtons, "Cancel", Color3.fromRGB(70, 74, 92), 110)
local pickerSend = button(pickerButtons, "Send squad", Color3.fromRGB(40, 150, 90), 170)
local chosen = {}

local function myUnits()
	local list = {}
	local folder = workspace:FindFirstChild("Map") and workspace.Map:FindFirstChild("Buildings")
	if not folder then return list end
	for _, m in ipairs(folder:GetChildren()) do
		if m:GetAttribute("Kind") == "Monster" and m:GetAttribute("Owner") == player.UserId and not m:GetAttribute("Building") then
			table.insert(list, m)
		end
	end
	return list
end

local function refreshSendText()
	local n = 0
	for _, on in pairs(chosen) do if on then n += 1 end end
	pickerSend.Text = "Send squad (" .. n .. ")"
	pickerSend.BackgroundColor3 = (n > 0) and Color3.fromRGB(40, 150, 90) or Color3.fromRGB(60, 64, 80)
end

local function openPicker()
	for _, c in ipairs(pickerBody:GetChildren()) do
		if not c:IsA("UIListLayout") then c:Destroy() end
	end
	table.clear(chosen)
	local units = myUnits()
	if #units == 0 then
		new("TextLabel", {
			Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, TextWrapped = true, Font = Enum.Font.GothamMedium,
			TextSize = 14, TextColor3 = Color3.fromRGB(255, 150, 150), Text = "You have no finished Goblin Guards or Ogres yet. Train some first!",
		}, pickerBody)
	end
	for k, m in ipairs(units) do
		local id = m:GetAttribute("Id")
		chosen[id] = true
		local def = Config.ItemsById[m.Name]
		local row = new("TextButton", {
			Size = UDim2.new(1, 0, 0, 36), BackgroundColor3 = ROW, BorderSizePixel = 0, AutoButtonColor = false, Text = "",
			LayoutOrder = k, Selectable = false,
		}, pickerBody)
		corner(row)
		local box = new("Frame", { Position = UDim2.fromOffset(10, 8), Size = UDim2.fromOffset(20, 20), BackgroundColor3 = Color3.fromRGB(60, 200, 110), BorderSizePixel = 0 }, row)
		corner(box, 5)
		new("TextLabel", {
			Position = UDim2.fromOffset(42, 0), Size = UDim2.new(1, -52, 1, 0), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
			TextSize = 14, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left,
			Text = (def and def.Name or m.Name) .. "   #" .. tostring(id),
		}, row)
		row.Activated:Connect(function()
			chosen[id] = not chosen[id]
			box.BackgroundColor3 = chosen[id] and Color3.fromRGB(60, 200, 110) or Color3.fromRGB(70, 74, 92)
			refreshSendText()
		end)
	end
	refreshSendText()
	picker.Visible = true
end

pickerCancel.Activated:Connect(function() picker.Visible = false end)
pickerSend.Activated:Connect(function()
	local ids = {}
	for id, on in pairs(chosen) do
		if on then table.insert(ids, id) end
	end
	if #ids == 0 then return end
	remote:FireServer("Enter", ids)
	picker.Visible = false
end)

---------------------------------------------------------------- upgrades shop
local shop, shopBody, shopButtons = makeWindow("Upgrades",
	"Spend crystals you dig up in the dungeon. Upgrades last until the city falls.", 470)
local shopClose = button(shopButtons, "Close", Color3.fromRGB(70, 74, 92), 110)
shopClose.Activated:Connect(function() shop.Visible = false end)

local shopRows = {}
for k, up in ipairs(Config.Upgrades) do
	local row = new("Frame", { Size = UDim2.new(1, 0, 0, 62), BackgroundColor3 = ROW, BorderSizePixel = 0, LayoutOrder = k }, shopBody)
	corner(row)
	new("TextLabel", {
		Position = UDim2.fromOffset(12, 8), Size = UDim2.new(1, -160, 0, 18), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
		TextSize = 15, TextColor3 = WHITE, TextXAlignment = Enum.TextXAlignment.Left, Text = up.Name,
	}, row)
	new("TextLabel", {
		Position = UDim2.fromOffset(12, 28), Size = UDim2.new(1, -160, 0, 28), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
		TextSize = 12, TextColor3 = GREY, TextXAlignment = Enum.TextXAlignment.Left, TextYAlignment = Enum.TextYAlignment.Top,
		TextWrapped = true, Text = up.Desc,
	}, row)
	local level = new("TextLabel", {
		AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -140, 0, 8), Size = UDim2.fromOffset(60, 18), BackgroundTransparency = 1,
		Font = Enum.Font.GothamBold, TextSize = 12, TextColor3 = PURPLE, TextXAlignment = Enum.TextXAlignment.Right, Text = "",
	}, row)
	local buy = new("TextButton", {
		AnchorPoint = Vector2.new(1, 0.5), Position = UDim2.new(1, -10, 0.5, 0), Size = UDim2.fromOffset(120, 38),
		BackgroundColor3 = Color3.fromRGB(110, 70, 170), BorderSizePixel = 0, TextColor3 = WHITE, Font = Enum.Font.GothamBold,
		TextSize = 13, Text = "", Selectable = false,
	}, row)
	corner(buy)
	buy.Activated:Connect(function() remote:FireServer("Upgrade", up.Id) end)
	shopRows[up.Id] = { Up = up, Level = level, Buy = buy }
end

local function refreshShop()
	for id, r in pairs(shopRows) do
		local lvl = player:GetAttribute("Up_" .. id) or 0
		r.Level.Text = "Lv " .. lvl .. "/" .. r.Up.Max
		if lvl >= r.Up.Max then
			r.Buy.Text = "MAX"
			r.Buy.BackgroundColor3 = Color3.fromRGB(60, 64, 80)
		else
			local cost = Config.UpgradeCost(lvl)
			r.Buy.Text = "Buy - " .. cost .. " crystals"
			r.Buy.BackgroundColor3 = (crystals.Value >= cost) and Color3.fromRGB(110, 70, 170) or Color3.fromRGB(60, 64, 80)
		end
	end
end
crystals.Changed:Connect(refreshShop)
for _, up in ipairs(Config.Upgrades) do
	player:GetAttributeChangedSignal("Up_" .. up.Id):Connect(refreshShop)
end
refreshShop()

upgradesBtn.Activated:Connect(function()
	picker.Visible = false
	shop.Visible = not shop.Visible
end)

---------------------------------------------------------------- dungeon panel (left side, only in the dungeon view)
local dpanel = new("Frame", {
	AnchorPoint = Vector2.new(0, 0.5), Position = UDim2.new(0, 12, 0.5, 0), Size = UDim2.fromOffset(270, 0),
	AutomaticSize = Enum.AutomaticSize.Y, BackgroundColor3 = PANEL, BackgroundTransparency = 0.1, BorderSizePixel = 0,
	Visible = false, Active = true,
}, gui)
corner(dpanel, 12)
new("UIStroke", { Color = Color3.fromRGB(90, 70, 130), Thickness = 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, dpanel)
pad(dpanel, 14)
new("UIListLayout", { Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }, dpanel)
local function line(order, font, size, color)
	return new("TextLabel", {
		Size = UDim2.new(1, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y, BackgroundTransparency = 1, TextWrapped = true,
		Font = font, TextSize = size, TextColor3 = color, TextXAlignment = Enum.TextXAlignment.Left, Text = "", LayoutOrder = order,
	}, dpanel)
end
local dTitle = line(1, Enum.Font.GothamBlack, 18, PURPLE)
local dRooms = line(2, Enum.Font.GothamMedium, 14, WHITE)
local dSquad = line(3, Enum.Font.GothamMedium, 14, WHITE)
local dWave = line(4, Enum.Font.GothamMedium, 14, Color3.fromRGB(140, 230, 160))
local dButtons = new("Frame", { Size = UDim2.new(1, 0, 0, 36), BackgroundTransparency = 1, LayoutOrder = 5 }, dpanel)
new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8) }, dButtons)
local retreatBtn = button(dButtons, "Retreat", Color3.fromRGB(175, 50, 55), 115)
retreatBtn.Size = UDim2.fromOffset(115, 34)
local watchBtn = button(dButtons, "Watch base", Color3.fromRGB(60, 90, 130), 119)
watchBtn.Size = UDim2.fromOffset(119, 34)
local dHint = line(6, Enum.Font.Gotham, 12, GREY)
dHint.Text = "Side rooms open left/right: treasure, crystals, or a Warlord with a buff for the rest of the match\n\nDrag a box: select several units\nClick the floor: move your squad\nClick a unit: command only that one (Shift = add)\nClick gold, crystals or a chest: dig it\nClick a grave: revive the fallen unit\nQ / E / R: unit abilities (aimed at your mouse)\nC: command the whole squad again   -   Scroll: zoom"

local function refreshPanel()
	local rooms = player:GetAttribute("DungeonRooms") or 1
	local cur = player:GetAttribute("DungeonRoom") or 1
	local final = player:GetAttribute("DungeonFinal") == true
	dTitle.Text = final and "Dungeon - FINAL FLOOR" or ("Dungeon - Floor " .. (player:GetAttribute("DungeonFloor") or 1)
		.. " of " .. Config.Dungeon.FinalFloor)
	if final and not player:GetAttribute("DungeonFloorDone") then
		dRooms.Text = "Rooms cleared: " .. math.max(0, cur - 1) .. " / " .. math.max(0, rooms - 1) .. "  -  beat the Overlord in the last room to WIN!"
	elseif player:GetAttribute("DungeonFloorDone") then
		dRooms.Text = "Floor cleared! A deeper floor opens after the next wave."
	else
		dRooms.Text = "Rooms cleared: " .. math.max(0, cur - 1) .. " / " .. math.max(0, rooms - 1)
	end
	local graves = player:GetAttribute("DungeonGraves") or 0
	dSquad.Text = "Squad: " .. (player:GetAttribute("DungeonAlive") or 0) .. " alive" .. ((graves > 0) and (", " .. graves .. " fallen") or "")
	local red = workspace:GetAttribute("NextWaveReduction") or 0
	dWave.Text = (red > 0) and ("Next wave: " .. red .. " fewer enemies") or "Kill enemies here to shrink the next wave"
end
for _, a in ipairs({ "DungeonRooms", "DungeonRoom", "DungeonFloor", "DungeonFloorDone", "DungeonAlive", "DungeonGraves", "DungeonFinal" }) do
	player:GetAttributeChangedSignal(a):Connect(refreshPanel)
end
workspace:GetAttributeChangedSignal("NextWaveReduction"):Connect(refreshPanel)
refreshPanel()

---------------------------------------------------------------- victory screen
local victory = new("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(12, 8, 24), BackgroundTransparency = 0.2,
	BorderSizePixel = 0, Visible = false, Active = true, ZIndex = 50,
}, gui)
new("UIGradient", {
	Color = ColorSequence.new(Color3.fromRGB(70, 40, 120), Color3.fromRGB(10, 6, 20)), Rotation = 90,
}, victory)
local vTitle = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.36), Size = UDim2.new(1, 0, 0, 90),
	BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 84, TextColor3 = Color3.fromRGB(255, 215, 70),
	TextStrokeTransparency = 0.4, Text = "VICTORY!", ZIndex = 51,
}, victory)
local vSub = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.47), Size = UDim2.new(0.8, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Font = Enum.Font.GothamBold, TextSize = 24, TextColor3 = Color3.new(1, 1, 1), TextWrapped = true,
	Text = "", ZIndex = 51,
}, victory)
local vStats = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.56), Size = UDim2.new(0.8, 0, 0, 0), AutomaticSize = Enum.AutomaticSize.Y,
	BackgroundTransparency = 1, Font = Enum.Font.GothamMedium, TextSize = 18, TextColor3 = Color3.fromRGB(200, 190, 230), TextWrapped = true,
	Text = "", ZIndex = 51,
}, victory)
local vTimer = new("TextLabel", {
	AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.fromScale(0.5, 0.68), Size = UDim2.new(1, 0, 0, 24),
	BackgroundTransparency = 1, Font = Enum.Font.Gotham, TextSize = 16, TextColor3 = Color3.fromRGB(150, 145, 175), Text = "", ZIndex = 51,
}, victory)

local function refreshVictory()
	local won = workspace:GetAttribute("Phase") == "Victory"
	victory.Visible = won
	if not won then return end
	local by = workspace:GetAttribute("VictoryBy") or ""
	vSub.Text = ((by == player.Name) and "You" or by) .. " defeated the Overlord. The city is saved!"
	local buffs = player:GetAttribute("BuffList") or ""
	vStats.Text = "Survived to wave " .. tostring(workspace:GetAttribute("VictoryWave") or "?")
		.. "   -   Coins: " .. player.leaderstats.Coins.Value .. "   -   Crystals: " .. crystals.Value
		.. ((buffs ~= "") and ("\nBuffs: " .. buffs) or "")
	vTimer.Text = "A new match starts in " .. tostring(workspace:GetAttribute("Timer") or 0) .. "s"
end
workspace:GetAttributeChangedSignal("Phase"):Connect(refreshVictory)
workspace:GetAttributeChangedSignal("Timer"):Connect(refreshVictory)
refreshVictory()

retreatBtn.Activated:Connect(function() remote:FireServer("Retreat") end)

---------------------------------------------------------------- which view you're looking at
local watchingBase = false
local selected = {}   -- unitId -> true; empty = whole squad
local rings = {}

local function inDungeon()
	return player:GetAttribute("InDungeon") == true
end

local function updateView()
	local quick = player:GetAttribute("QuickView") == true   -- the minimap's full view shows the base
	local v = inDungeon() and not watchingBase and not quick
	if (player:GetAttribute("ViewDungeon") == true) ~= v then
		player:SetAttribute("ViewDungeon", v)
	end
	dpanel.Visible = v
	local portalOpen = workspace:GetAttribute("PortalOpen") == true
	local matchOver = workspace:GetAttribute("Phase") == "Victory" or workspace:GetAttribute("Phase") == "GameOver"
	dungeonBtn.Visible = not matchOver and ((portalOpen and not inDungeon()) or (inDungeon() and (watchingBase or quick)))
	dungeonBtn.Text = inDungeon() and "Back to the Dungeon" or "Enter Dungeon"
	if v then
		picker.Visible = false
	else
		camera.CameraType = Enum.CameraType.Custom
		table.clear(selected)
	end
end
player:GetAttributeChangedSignal("InDungeon"):Connect(function()
	if inDungeon() then
		watchingBase = false
		player:SetAttribute("QuickView", false)
	end
	updateView()
end)
player:GetAttributeChangedSignal("QuickView"):Connect(updateView)
workspace:GetAttributeChangedSignal("PortalOpen"):Connect(updateView)
workspace:GetAttributeChangedSignal("Phase"):Connect(updateView)
updateView()

dungeonBtn.Activated:Connect(function()
	shop.Visible = false
	player:SetAttribute("QuickView", false)
	if inDungeon() then
		watchingBase = false
		updateView()
	else
		openPicker()
	end
end)
watchBtn.Activated:Connect(function()
	watchingBase = true
	updateView()
end)

---------------------------------------------------------------- dungeon camera (quarter-down, follows your squad)
local zoom = 55
local focus = nil

local function myFolder()
	local root = workspace:FindFirstChild("Dungeons")
	return root and root:FindFirstChild(tostring(player.UserId))
end

RunService:BindToRenderStep("DungeonCamera", Enum.RenderPriority.Camera.Value + 2, function(dt)
	if player:GetAttribute("ViewDungeon") ~= true then
		for _, r in pairs(rings) do r.Parent = nil end
		return
	end
	local folder = myFolder()
	local sum, n = Vector3.zero, 0
	local unitsById = {}
	if folder then
		for _, m in ipairs(folder.Units:GetChildren()) do
			local id = m:GetAttribute("UnitId")
			unitsById[id] = m
			if next(selected) == nil or selected[id] then
				sum += m:GetPivot().Position
				n += 1
			end
		end
	end
	local target
	if n > 0 then
		target = sum / n
	else
		target = Vector3.new(player:GetAttribute("DungeonFocusX") or 0, 0, player:GetAttribute("DungeonFocusZ") or 0)
	end
	target = Vector3.new(target.X, 0, target.Z)
	focus = focus and focus:Lerp(target, math.min(1, dt * 4)) or target
	camera.CameraType = Enum.CameraType.Scriptable
	camera.CFrame = CFrame.lookAt(focus + Vector3.new(0, zoom * 0.8, zoom * 0.6), focus)

	-- blue rings under the units you're commanding
	for id, r in pairs(rings) do
		if not selected[id] or not unitsById[id] then
			r:Destroy()
			rings[id] = nil
		end
	end
	for id in pairs(selected) do
		local m = unitsById[id]
		if m then
			local r = rings[id]
			if not r then
				r = new("Part", {
					Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Neon,
					Transparency = 0.3, Shape = Enum.PartType.Cylinder, Color = Color3.fromRGB(80, 170, 255), Size = Vector3.new(0.15, 4, 4),
				}, nil)
				rings[id] = r
			end
			local p = m:GetPivot().Position
			r.CFrame = CFrame.new(p.X, 0.1, p.Z) * CFrame.Angles(0, 0, math.pi / 2)
			if r.Parent ~= workspace then r.Parent = workspace end
		end
	end
end)

UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseWheel and player:GetAttribute("ViewDungeon") == true then
		zoom = math.clamp(zoom - input.Position.Z * 5, 28, 95)
	end
end)

---------------------------------------------------------------- dungeon clicks
local rayParams = RaycastParams.new()
rayParams.FilterType = Enum.RaycastFilterType.Include

local moveFlag = new("Part", {
	Anchored = true, CanCollide = false, CanQuery = false, CanTouch = false, Material = Enum.Material.Neon,
	Transparency = 0.2, Color = Color3.fromRGB(80, 170, 255), Size = Vector3.new(0.4, 3, 0.4),
}, nil)
local flagToken = 0

local function selectedList()
	local ids = {}
	for id in pairs(selected) do table.insert(ids, id) end
	return ids
end

-- a plain click: select a unit, dig, revive, or send the selected units (whole squad if none) there
local function clickAt(ray)
	local folder = myFolder()
	if not folder then return end
	do
		rayParams.FilterDescendantsInstances = { folder }
		local hit = workspace:Raycast(ray.Origin, ray.Direction * 1000, rayParams)
		if not hit then return end
		local inst = hit.Instance
		while inst and inst ~= folder do
			local unitId = inst:GetAttribute("UnitId")
			if unitId then
				if UIS:IsKeyDown(Enum.KeyCode.LeftShift) then
					selected[unitId] = (not selected[unitId]) or nil
				else
					table.clear(selected)
					selected[unitId] = true
				end
				return
			end
			local nodeId = inst:GetAttribute("NodeId")
			if nodeId then
				remote:FireServer("Mine", nodeId, selectedList())
				return
			end
			local graveId = inst:GetAttribute("GraveId")
			if graveId then
				remote:FireServer("Revive", graveId)
				return
			end
			if inst:GetAttribute("EnemyId") then break end   -- clicking an enemy = walk there and fight
			inst = inst.Parent
		end
		local p = hit.Position
		remote:FireServer("Move", p.X, p.Z, selectedList())
		moveFlag.Position = Vector3.new(p.X, 1.5, p.Z)
		moveFlag.Parent = workspace
		flagToken += 1
		local my = flagToken
		task.delay(1, function()
			if flagToken == my then moveFlag.Parent = nil end
		end)
	end
end

-- click-and-drag draws a selection box around units
local SelectBox = require(RS:WaitForChild("Shared"):WaitForChild("SelectBox"))
local box = SelectBox.new(playerGui)

-- Q / E / R abilities for the selected units (the whole squad when none are selected)
local AbilityBar = require(RS:WaitForChild("Shared"):WaitForChild("AbilityBar"))
local dungeonBar = AbilityBar.new(gui, {
	Position = UDim2.new(0.5, 0, 1, -16), IdAttr = "UnitId", PlaneY = 0, InDungeon = true,
	GetUnits = function()
		if player:GetAttribute("ViewDungeon") ~= true then return {} end
		local folder = myFolder()
		if not folder then return {} end
		local list = {}
		for _, m in ipairs(folder.Units:GetChildren()) do
			if next(selected) == nil or selected[m:GetAttribute("UnitId")] then table.insert(list, m) end
		end
		return list
	end,
})

UIS.InputBegan:Connect(function(input, processed)
	if processed or player:GetAttribute("ViewDungeon") ~= true then return end
	local t = input.UserInputType
	if t == Enum.UserInputType.Touch then
		clickAt(camera:ScreenPointToRay(input.Position.X, input.Position.Y))
	elseif t == Enum.UserInputType.MouseButton1 then
		box.begin(UIS:GetMouseLocation())
	elseif t == Enum.UserInputType.Keyboard then
		local k = input.KeyCode
		if k == Enum.KeyCode.Q or k == Enum.KeyCode.E or k == Enum.KeyCode.R then
			dungeonBar:cast(k.Name)
		elseif k == Enum.KeyCode.C then
			table.clear(selected)
		end
	end
end)

UIS.InputChanged:Connect(function(input)
	if input.UserInputType == Enum.UserInputType.MouseMovement then
		box.update(UIS:GetMouseLocation())
	end
end)

UIS.InputEnded:Connect(function(input)
	if input.UserInputType ~= Enum.UserInputType.MouseButton1 or not box.active() then return end
	local mp = UIS:GetMouseLocation()
	local dragged, a, b = box.finish(mp)
	if player:GetAttribute("ViewDungeon") ~= true then return end
	if dragged then
		local folder = myFolder()
		if not folder then return end
		if not UIS:IsKeyDown(Enum.KeyCode.LeftShift) then table.clear(selected) end
		for _, m in ipairs(folder.Units:GetChildren()) do
			local sp, onScreen = camera:WorldToViewportPoint(m:GetPivot().Position)
			if onScreen and box.contains(a, b, sp) then selected[m:GetAttribute("UnitId")] = true end
		end
	else
		clickAt(camera:ViewportPointToRay(mp.X, mp.Y))
	end
end)
