-- Ability bar for the units you have selected: shows each unit type's Q / E / R abilities with cooldowns,
-- and casts them toward the mouse. Used by both the base screen and the dungeon screen.
local RS = game:GetService("ReplicatedStorage")
local UIS = game:GetService("UserInputService")
local RunService = game:GetService("RunService")

local Config = require(script.Parent:WaitForChild("Config"))

local AbilityBar = {}
AbilityBar.__index = AbilityBar

local KEYS = { "Q", "E", "R" }
local TYPES = { { Id = "Ogre", Name = "OGRE" }, { Id = "Goblin", Name = "GUARD" } }

local function new(class, props, parent)
	local o = Instance.new(class)
	for k, v in pairs(props) do o[k] = v end
	o.Parent = parent
	return o
end

-- opts:
--   Position  UDim2 for the bottom-centre of the bar
--   GetUnits  function returning the unit models the abilities apply to
--   IdAttr    attribute holding each model's id ("Id" on the map, "UnitId" in the dungeon)
--   PlaneY    ground height used to find where the mouse points
--   InDungeon true for the dungeon bar
function AbilityBar.new(parentGui, opts)
	local self = setmetatable({}, AbilityBar)
	self.Opts = opts
	self.Shown = true
	self.Remote = RS:WaitForChild("Remotes"):WaitForChild("UnitAbility")
	self.Frame = new("Frame", {
		AnchorPoint = Vector2.new(0.5, 1), Position = opts.Position, Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY,
		BackgroundTransparency = 1, Visible = false,
	}, parentGui)
	new("UIListLayout", { Padding = UDim.new(0, 5), HorizontalAlignment = Enum.HorizontalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, self.Frame)

	-- description shown while hovering a button
	self.Hint = new("TextLabel", {
		Size = UDim2.fromOffset(0, 24), AutomaticSize = Enum.AutomaticSize.X, BackgroundColor3 = Color3.fromRGB(16, 18, 26),
		BackgroundTransparency = 0.1, BorderSizePixel = 0, Font = Enum.Font.GothamMedium, TextSize = 13,
		TextColor3 = Color3.fromRGB(230, 232, 245), Text = "", Visible = false, LayoutOrder = 0,
	}, self.Frame)
	new("UICorner", { CornerRadius = UDim.new(0, 6) }, self.Hint)
	new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }, self.Hint)

	self.Rows = {}
	for order, t in ipairs(TYPES) do
		local kit = Config.Abilities[t.Id]
		local row = new("Frame", { Size = UDim2.new(), AutomaticSize = Enum.AutomaticSize.XY, BackgroundTransparency = 1, LayoutOrder = order, Visible = false }, self.Frame)
		new("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 6), VerticalAlignment = Enum.VerticalAlignment.Center, SortOrder = Enum.SortOrder.LayoutOrder }, row)
		local tag = new("TextLabel", {
			Size = UDim2.fromOffset(62, 46), BackgroundColor3 = Color3.fromRGB(16, 18, 26), BackgroundTransparency = 0.15, BorderSizePixel = 0,
			Font = Enum.Font.GothamBlack, TextSize = 13, TextColor3 = Color3.fromRGB(150, 230, 160), Text = t.Name, LayoutOrder = 0,
		}, row)
		new("UICorner", { CornerRadius = UDim.new(0, 8) }, tag)
		local slots = {}
		for k, key in ipairs(KEYS) do
			local ab = kit[key]
			local ult = ab.Ultimate == true
			local btn = new("TextButton", {
				Size = UDim2.fromOffset(134, 46), BackgroundColor3 = ult and Color3.fromRGB(70, 40, 105) or Color3.fromRGB(32, 35, 48),
				BorderSizePixel = 0, AutoButtonColor = true, Text = "", LayoutOrder = k, Selectable = false,
			}, row)
			new("UICorner", { CornerRadius = UDim.new(0, 8) }, btn)
			new("UIStroke", { Color = ult and Color3.fromRGB(200, 140, 255) or Color3.fromRGB(70, 75, 95), Thickness = ult and 1.5 or 1, ApplyStrokeMode = Enum.ApplyStrokeMode.Border }, btn)
			local badge = new("TextLabel", {
				Position = UDim2.fromOffset(6, 6), Size = UDim2.fromOffset(22, 22), BackgroundColor3 = ult and Color3.fromRGB(200, 140, 255) or Color3.fromRGB(255, 210, 90),
				BorderSizePixel = 0, Font = Enum.Font.GothamBlack, TextSize = 14, TextColor3 = Color3.fromRGB(20, 20, 26), Text = key,
			}, btn)
			new("UICorner", { CornerRadius = UDim.new(0, 5) }, badge)
			new("TextLabel", {
				Position = UDim2.fromOffset(34, 4), Size = UDim2.new(1, -38, 0, 20), BackgroundTransparency = 1, Font = Enum.Font.GothamBold,
				TextScaled = true, TextColor3 = Color3.new(1, 1, 1), TextXAlignment = Enum.TextXAlignment.Left, Text = ab.Name,
			}, btn)
			new("TextLabel", {
				Position = UDim2.fromOffset(34, 24), Size = UDim2.new(1, -38, 0, 16), BackgroundTransparency = 1, Font = Enum.Font.Gotham,
				TextSize = 11, TextColor3 = Color3.fromRGB(160, 165, 185), TextXAlignment = Enum.TextXAlignment.Left,
				Text = (ult and "ULTIMATE  -  " or "") .. ab.Cooldown .. "s cooldown",
			}, btn)
			-- dark cover with seconds left while it recharges
			local cover = new("Frame", { Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.new(0, 0, 0), BackgroundTransparency = 0.35, BorderSizePixel = 0, Visible = false, ZIndex = 3 }, btn)
			new("UICorner", { CornerRadius = UDim.new(0, 8) }, cover)
			local cdText = new("TextLabel", {
				Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Enum.Font.GothamBlack, TextSize = 18,
				TextColor3 = Color3.new(1, 1, 1), Text = "", ZIndex = 4,
			}, cover)
			btn.Activated:Connect(function() self:cast(key) end)
			btn.MouseEnter:Connect(function()
				self.Hint.Text = ab.Name .. ": " .. ab.Desc
				self.Hint.Visible = true
			end)
			btn.MouseLeave:Connect(function() self.Hint.Visible = false end)
			slots[key] = { Cover = cover, Text = cdText }
		end
		self.Rows[t.Id] = { Frame = row, Slots = slots }
	end

	RunService.RenderStepped:Connect(function() self:refresh() end)
	return self
end

function AbilityBar:setShown(v)
	self.Shown = v
end

function AbilityBar:units()
	local list = {}
	for _, m in ipairs(self.Opts.GetUnits() or {}) do
		if m.Parent then table.insert(list, m) end
	end
	return list
end

-- show the rows for the unit types you have selected, with cooldowns
function AbilityBar:refresh()
	local units = self.Shown and self:units() or {}
	local now = workspace:GetServerTimeNow()
	local any = false
	for typeId, row in pairs(self.Rows) do
		local list = {}
		for _, m in ipairs(units) do
			if m.Name == typeId then table.insert(list, m) end
		end
		row.Frame.Visible = #list > 0
		if #list > 0 then
			any = true
			for key, slot in pairs(row.Slots) do
				-- ready as soon as any selected unit of this type is ready
				local wait = math.huge
				for _, m in ipairs(list) do
					wait = math.min(wait, (m:GetAttribute("Ready_" .. key) or 0) - now)
				end
				slot.Cover.Visible = wait > 0
				if wait > 0 then slot.Text.Text = tostring(math.ceil(wait)) .. "s" end
			end
		end
	end
	self.Frame.Visible = any
	if not any then self.Hint.Visible = false end
end

-- fire Q / E / R for every selected unit, aimed at the ground under the mouse
function AbilityBar:cast(key)
	local ids = {}
	for _, m in ipairs(self:units()) do
		local id = m:GetAttribute(self.Opts.IdAttr)
		if id then table.insert(ids, id) end
	end
	if #ids == 0 then return false end
	local cam = workspace.CurrentCamera
	local mp = UIS:GetMouseLocation()
	local ray = cam:ViewportPointToRay(mp.X, mp.Y)
	local x, z
	if math.abs(ray.Direction.Y) > 1e-3 then
		local t = (self.Opts.PlaneY - ray.Origin.Y) / ray.Direction.Y
		if t > 0 then
			local p = ray.Origin + ray.Direction * t
			x, z = p.X, p.Z
		end
	end
	self.Remote:FireServer(key, ids, x, z, self.Opts.InDungeon == true)
	return true
end

return AbilityBar
