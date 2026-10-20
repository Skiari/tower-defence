-- Dungeon: a chain of rooms behind the portal, one dungeon per player.
-- Main rooms go in a line; side rooms branch off left or right (Treasure Vault, Crystal Cave, Warlord's Lair).
-- Your Goblins/Ogres fight room by room, dig up loot, and every kill removes enemies from the next wave.
local Players = game:GetService("Players")
local TweenService = game:GetService("TweenService")
local RS = game:GetService("ReplicatedStorage")

local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local Models = require(RS:WaitForChild("Shared"):WaitForChild("Models"))

local Dungeon = {}
local API -- functions from GameServer (coins, crystals, notify, buffs, ...)

local CELL = Config.Cell
local D = Config.Dungeon
local RW, RL, CW, CL = 11, 11, 3, 3          -- main room width/length, corridor width/length (tiles)
local HW, HL = RW * CELL / 2, RL * CELL / 2  -- main room half-size (studs)
local SW = 9                                 -- side rooms are 9x9 tiles
local SHW = SW * CELL / 2
local CORR_HALF = CW * CELL / 2
local STEP = (RL + CL) * CELL                -- distance between main room centres
local SIDE_STEP = HW + CL * CELL + SHW       -- distance from a main room centre to its side room centre
local WALL_H = 3.5
local AGGRO = D.AggroTiles * CELL
local ENEMY_REACH = 1.4 * CELL

local SIDE_INFO = {
	Treasure = { Name = "Treasure Vault", Floor = Color3.fromRGB(112, 94, 54), Text = Color3.fromRGB(255, 215, 80) },
	Crystal  = { Name = "Crystal Cave",   Floor = Color3.fromRGB(80, 64, 108), Text = Color3.fromRGB(205, 150, 255) },
	Lair     = { Name = "Warlord's Lair", Floor = Color3.fromRGB(98, 46, 46),  Text = Color3.fromRGB(255, 110, 90) },
}

local states = {}     -- userId -> dungeon state
local rootFolder
local nextId = 0
local nextSlot = 0
local clock = 0       -- dungeon game time (follows the 1x/2x/3x game speed)

local function newId()
	nextId += 1
	return nextId
end
local function flat(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end
local function flatVec(a, b)
	return Vector3.new(b.X - a.X, 0, b.Z - a.Z)
end
local function part(parent, props)
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in pairs(props) do p[k] = v end
	p.Parent = parent
	return p
end
local function reviveCost(def)
	return math.floor(def.Cost * D.ReviveCost)
end

---------------------------------------------------------------- layout
local function roomCenter(st, i)
	return st.Origin + Vector3.new(0, 0, -(i - 1) * STEP)
end

-- main rooms have ids 1, 2, 3...; side rooms 101, 102...
local function getRoom(st, id)
	if id >= 100 then return st.Side[id - 100] end
	return st.Rooms[id]
end

-- can you get into this room yet?
local function roomOpen(st, id)
	if id >= 100 then
		local sr = st.Side[id - 100]
		return sr ~= nil and st.Rooms[sr.Parent].Cleared
	end
	return id == 1 or st.Rooms[id - 1].Cleared
end

-- which room or corridor a point is in: 3 = main room 3, 3.5 = corridor after it, 101 = side room 1, 101.5 = its corridor
local function regionOf(st, pos)
	local dx = math.abs(pos.X - st.Origin.X)
	for i = 1, #st.Rooms do
		local c = roomCenter(st, i)
		if dx <= HW - 1 and math.abs(pos.Z - c.Z) <= HL - 1 then return i end
		if i < #st.Rooms and dx <= CORR_HALF - 0.8 then
			local zTop = c.Z - HL + 1
			local zBottom = c.Z - HL - CL * CELL - 1
			if pos.Z <= zTop and pos.Z >= zBottom then return i + 0.5 end
		end
	end
	for k, sr in ipairs(st.Side) do
		local c = sr.Center
		if math.abs(pos.X - c.X) <= SHW - 1 and math.abs(pos.Z - c.Z) <= SHW - 1 then return 100 + k end
		local pc = roomCenter(st, sr.Parent)
		if math.abs(pos.Z - pc.Z) <= CORR_HALF - 0.8 then
			local x1 = pc.X + sr.Side * (HW - 1)
			local x2 = pc.X + sr.Side * (HW + CL * CELL + 1)
			if (pos.X - x1) * (pos.X - x2) <= 0 then return 100 + k + 0.5 end
		end
	end
	return nil
end

local function canBeAt(st, pos)
	local r = regionOf(st, pos)
	if not r then return false end
	if r >= 100 then return roomOpen(st, math.floor(r)) end
	if r % 1 ~= 0 then return st.Rooms[math.floor(r)].Cleared end
	return roomOpen(st, r)
end

local function clampInRoom(st, id, pos)
	local room = getRoom(st, id)
	local c = room.Center
	return Vector3.new(
		math.clamp(pos.X, c.X - room.HW + 1.5, c.X + room.HW - 1.5), 0,
		math.clamp(pos.Z, c.Z - room.HL + 1.5, c.Z + room.HL - 1.5))
end

-- waypoints along the main line of rooms (through the doors in between)
local function mainRoute(st, fr, tr, to)
	local ox = st.Origin.X
	local pts = {}
	if tr > fr then
		local k = math.floor(fr)
		while k < tr do
			if not st.Rooms[k].Cleared then
				-- the door ahead is shut: wait in front of it
				table.insert(pts, Vector3.new(ox, 0, roomCenter(st, k).Z - HL + 2.5))
				return pts
			end
			if fr <= k then table.insert(pts, Vector3.new(ox, 0, roomCenter(st, k).Z - HL + 2)) end
			table.insert(pts, Vector3.new(ox, 0, roomCenter(st, k + 1).Z + HL - 2))
			k += 1
		end
	elseif tr < fr then
		local k = math.ceil(fr)
		while k > tr do
			if fr >= k then table.insert(pts, Vector3.new(ox, 0, roomCenter(st, k).Z + HL - 2)) end
			table.insert(pts, Vector3.new(ox, 0, roomCenter(st, k - 1).Z - HL + 2))
			k -= 1
		end
	end
	table.insert(pts, to)
	return pts
end

-- the point just inside the parent room, and just inside the side room, on either end of a side corridor
local function sideDoorPoints(st, sr)
	local pc = roomCenter(st, sr.Parent)
	return Vector3.new(pc.X + sr.Side * (HW - 2), 0, pc.Z), Vector3.new(pc.X + sr.Side * (HW + CL * CELL + 2), 0, pc.Z)
end

-- waypoints from one point to another, anywhere in the dungeon
local function route(st, from, to)
	local fr = regionOf(st, from) or st.Current
	local tr = regionOf(st, to)
	if not tr then
		local best, bd = 1, math.huge
		for i = 1, #st.Rooms do
			local d = flat(to, roomCenter(st, i))
			if d < bd then best, bd = i, d end
		end
		tr = best
		to = clampInRoom(st, best, to)
	end
	if fr >= 100 and tr >= 100 and math.floor(fr) == math.floor(tr) then return { to } end
	local pts = {}
	-- leaving a side room: out to its parent room first
	if fr >= 100 then
		local sr = st.Side[math.floor(fr) - 100]
		local inside, outside = sideDoorPoints(st, sr)
		if fr % 1 == 0 then table.insert(pts, outside) end
		table.insert(pts, inside)
		fr = sr.Parent
	end
	-- going into a side room: walk to its parent room, then through the side corridor
	local tail = {}
	if tr >= 100 then
		local sr = st.Side[math.floor(tr) - 100]
		local inside, outside = sideDoorPoints(st, sr)
		tr = sr.Parent
		if st.Rooms[sr.Parent].Cleared then tail = { outside, to } end
		to = inside
	end
	if tr % 1 ~= 0 then tr = math.floor(tr) end
	local main = mainRoute(st, fr, tr, to)
	for _, p in ipairs(main) do table.insert(pts, p) end
	if #tail > 0 and main[#main] == to then
		for _, p in ipairs(tail) do table.insert(pts, p) end
	end
	return pts
end

---------------------------------------------------------------- player info shown on screen
local function syncAttrs(st)
	local p = st.Player
	if not p or not p.Parent then return end
	local alive = 0
	for _, u in ipairs(st.Units) do
		if not u.Dead then alive += 1 end
	end
	p:SetAttribute("InDungeon", st.Active)
	p:SetAttribute("DungeonFloor", st.Floor)
	p:SetAttribute("DungeonRoom", st.Current)
	p:SetAttribute("DungeonRooms", #st.Rooms)
	p:SetAttribute("DungeonAlive", alive)
	p:SetAttribute("DungeonGraves", #st.Graves)
	p:SetAttribute("DungeonFloorDone", st.FloorDone == true)
	p:SetAttribute("DungeonFinal", st.Floor >= D.FinalFloor)
	local c = roomCenter(st, st.Current)
	p:SetAttribute("DungeonFocusX", c.X)
	p:SetAttribute("DungeonFocusZ", c.Z)
end

---------------------------------------------------------------- building a floor
local function buildGeometry(st)
	local geo = st.Folder.Geometry
	geo:ClearAllChildren()
	local n = #st.Rooms
	local ox = st.Origin.X
	local floorColor = Color3.fromRGB(72, 68, 78)
	local wallColor = Color3.fromRGB(58, 50, 60)
	local function wall(size, pos)
		part(geo, { Name = "Wall", Size = size, Position = pos, Color = wallColor, Material = Enum.Material.Brick, CanQuery = false })
	end
	-- a straight wall between two points (along X or Z), leaving gaps { {centre, halfWidth}, ... }
	local function wallLine(a, b, gaps)
		local alongX = math.abs(b.X - a.X) > math.abs(b.Z - a.Z)
		local s0 = alongX and math.min(a.X, b.X) or math.min(a.Z, b.Z)
		local s1 = alongX and math.max(a.X, b.X) or math.max(a.Z, b.Z)
		local fixed = alongX and a.Z or a.X
		local cuts = {}
		for _, g in ipairs(gaps or {}) do table.insert(cuts, { g[1] - g[2], g[1] + g[2] }) end
		table.sort(cuts, function(p, q) return p[1] < q[1] end)
		local function seg(from, to)
			if to - from < 0.2 then return end
			local mid, len = (from + to) / 2, to - from
			if alongX then
				wall(Vector3.new(len, WALL_H, 1), Vector3.new(mid, WALL_H / 2, fixed))
			else
				wall(Vector3.new(1, WALL_H, len), Vector3.new(fixed, WALL_H / 2, mid))
			end
		end
		local cur = s0
		for _, cut in ipairs(cuts) do
			seg(cur, cut[1])
			cur = cut[2]
		end
		seg(cur, s1)
	end
	local function floorPart(c, sx, sz, color)
		part(geo, { Name = "Floor", Size = Vector3.new(sx, 1, sz), Position = c + Vector3.new(0, -0.5, 0), Color = color, Material = Enum.Material.Slate })
	end
	local function torches(c, hw, hl, color)
		for _, sx in ipairs({ -1, 1 }) do
			for _, sz in ipairs({ -1, 1 }) do
				local stick = part(geo, { Size = Vector3.new(0.5, 2.4, 0.5), Position = c + Vector3.new(sx * (hw - 1), 1.2, sz * (hl - 1)),
					Color = Color3.fromRGB(100, 70, 40), Material = Enum.Material.Wood, CanQuery = false })
				local flame = part(geo, { Size = Vector3.new(0.7, 0.7, 0.7), Position = stick.Position + Vector3.new(0, 1.5, 0),
					Color = color or Color3.fromRGB(255, 160, 50), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false })
				local light = Instance.new("PointLight")
				light.Color = color or Color3.fromRGB(255, 170, 80)
				light.Range = 16
				light.Brightness = 1.5
				light.Parent = flame
			end
		end
	end

	for i = 1, n do
		local c = roomCenter(st, i)
		local finalRoom = st.Rooms[i].Final
		floorPart(c, RW * CELL, RL * CELL, finalRoom and Color3.fromRGB(60, 30, 75)
			or ((i % 2 == 0) and floorColor or floorColor:Lerp(Color3.new(0, 0, 0), 0.08)))
		if finalRoom then
			-- big floating warning over the final boss room
			local anchor = part(geo, { Name = "Sign", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CanQuery = false, Position = c + Vector3.new(0, 9, 0) })
			local sg = Instance.new("BillboardGui")
			sg.Size = UDim2.fromOffset(260, 36)
			sg.AlwaysOnTop = true
			sg.MaxDistance = 400
			sg.Adornee = anchor
			local label = Instance.new("TextLabel")
			label.Size = UDim2.fromScale(1, 1)
			label.BackgroundTransparency = 1
			label.Font = Enum.Font.GothamBlack
			label.TextSize = 22
			label.TextColor3 = Color3.fromRGB(200, 120, 255)
			label.TextStrokeTransparency = 0.1
			label.Text = "FINAL BOSS"
			label.Parent = sg
			sg.Parent = anchor
		end
		local westGaps, eastGaps = {}, {}
		for _, sr in ipairs(st.Side) do
			if sr.Parent == i then table.insert((sr.Side < 0) and westGaps or eastGaps, { c.Z, CORR_HALF }) end
		end
		wallLine(Vector3.new(c.X - HW - 0.5, 0, c.Z - HL - 1), Vector3.new(c.X - HW - 0.5, 0, c.Z + HL + 1), westGaps)
		wallLine(Vector3.new(c.X + HW + 0.5, 0, c.Z - HL - 1), Vector3.new(c.X + HW + 0.5, 0, c.Z + HL + 1), eastGaps)
		wallLine(Vector3.new(c.X - HW - 1, 0, c.Z + HL + 0.5), Vector3.new(c.X + HW + 1, 0, c.Z + HL + 0.5), (i > 1) and { { ox, CORR_HALF } } or nil)
		wallLine(Vector3.new(c.X - HW - 1, 0, c.Z - HL - 0.5), Vector3.new(c.X + HW + 1, 0, c.Z - HL - 0.5), (i < n) and { { ox, CORR_HALF } } or nil)
		torches(c, HW, HL)
		if i < n then
			local zc = c.Z - HL - CL * CELL / 2
			floorPart(Vector3.new(ox, 0, zc), CW * CELL, CL * CELL + 0.2, floorColor)
			wall(Vector3.new(1, WALL_H, CL * CELL), Vector3.new(ox - CORR_HALF - 0.5, WALL_H / 2, zc))
			wall(Vector3.new(1, WALL_H, CL * CELL), Vector3.new(ox + CORR_HALF + 0.5, WALL_H / 2, zc))
			if not st.Rooms[i].Cleared then
				st.Rooms[i].Door = part(geo, { Name = "Door", Size = Vector3.new(CW * CELL, WALL_H + 1, 0.8),
					Position = Vector3.new(ox, (WALL_H + 1) / 2, c.Z - HL - 0.5), Color = Color3.fromRGB(100, 62, 35),
					Material = Enum.Material.WoodPlanks, CanQuery = false })
			end
		end
	end

	for _, sr in ipairs(st.Side) do
		local info = SIDE_INFO[sr.Kind]
		local c = sr.Center
		local pc = roomCenter(st, sr.Parent)
		floorPart(c, SW * CELL, SW * CELL, info.Floor)
		local nearX = c.X - sr.Side * (SHW + 0.5)
		local farX = c.X + sr.Side * (SHW + 0.5)
		wallLine(Vector3.new(nearX, 0, c.Z - SHW - 1), Vector3.new(nearX, 0, c.Z + SHW + 1), { { c.Z, CORR_HALF } })
		wallLine(Vector3.new(farX, 0, c.Z - SHW - 1), Vector3.new(farX, 0, c.Z + SHW + 1))
		wallLine(Vector3.new(c.X - SHW - 1, 0, c.Z - SHW - 0.5), Vector3.new(c.X + SHW + 1, 0, c.Z - SHW - 0.5))
		wallLine(Vector3.new(c.X - SHW - 1, 0, c.Z + SHW + 0.5), Vector3.new(c.X + SHW + 1, 0, c.Z + SHW + 0.5))
		torches(c, SHW, SHW, info.Text)
		-- corridor from the parent room
		local xc = pc.X + sr.Side * (HW + CL * CELL / 2)
		floorPart(Vector3.new(xc, 0, pc.Z), CL * CELL + 0.2, CW * CELL, floorColor)
		wall(Vector3.new(CL * CELL, WALL_H, 1), Vector3.new(xc, WALL_H / 2, pc.Z - CORR_HALF - 0.5))
		wall(Vector3.new(CL * CELL, WALL_H, 1), Vector3.new(xc, WALL_H / 2, pc.Z + CORR_HALF + 0.5))
		if not st.Rooms[sr.Parent].Cleared then
			sr.Door = part(geo, { Name = "Door", Size = Vector3.new(0.8, WALL_H + 1, CW * CELL),
				Position = Vector3.new(pc.X + sr.Side * (HW + 0.5), (WALL_H + 1) / 2, pc.Z), Color = Color3.fromRGB(100, 62, 35),
				Material = Enum.Material.WoodPlanks, CanQuery = false })
		end
		-- floating name over the room
		local anchor = part(geo, { Name = "Sign", Size = Vector3.new(1, 1, 1), Transparency = 1, CanCollide = false, CanQuery = false, Position = c + Vector3.new(0, 7, 0) })
		local gui = Instance.new("BillboardGui")
		gui.Size = UDim2.fromOffset(220, 30)
		gui.AlwaysOnTop = true
		gui.MaxDistance = 400
		gui.Adornee = anchor
		local label = Instance.new("TextLabel")
		label.Size = UDim2.fromScale(1, 1)
		label.BackgroundTransparency = 1
		label.Font = Enum.Font.GothamBlack
		label.TextSize = 18
		label.TextColor3 = info.Text
		label.TextStrokeTransparency = 0.2
		label.Text = info.Name
		label.Parent = gui
		gui.Parent = anchor
	end

	local exit = Models.DungeonPortal(roomCenter(st, 1) + Vector3.new(0, 0, HL - 2.5))
	exit.Parent = geo
end

local ENEMY_POOL = { { "Grunt", 1 }, { "Runner", 1 }, { "Swimmer", 2 }, { "Climber", 3 }, { "Tank", 3 } }

-- opts: Elite (gold glow, 5x HP), HP / Dmg / Speed overrides, Name, Glow colour, Scale, Center (spawn in the middle)
local function spawnEnemy(st, room, typeName, opts)
	opts = opts or {}
	local def = Config.Enemies[typeName]
	local c = room.Center
	local pos
	if opts.Center then
		pos = c
	elseif room.Kind == "Main" then
		pos = Vector3.new(c.X + (math.random() - 0.5) * (room.HW * 2 - 8), 0, c.Z + 2 - math.random() * (room.HL - 1))
	else
		-- side rooms: towards the far end, away from the door
		pos = Vector3.new(c.X + room.Side * math.random() * (room.HW - 4), 0, c.Z + (math.random() - 0.5) * (room.HL * 2 - 8))
	end
	local scaleIdx = (room.Kind == "Main") and room.Id or room.Parent
	local model, bar = Models.Enemy(def)
	local hp = opts.HP or def.HP * (1 + 0.3 * (st.Floor - 1) + 0.06 * scaleIdx) * (opts.Elite and 5 or 1)
	local e = {
		Id = newId(), Def = def, Model = model, Bar = bar, HP = hp, MaxHP = hp, Pos = pos, Face = Vector3.new(0, 0, 1),
		Room = room.Id, Cd = math.random(), Bob = math.random() * 6, Elite = opts.Elite,
		Dmg = opts.Dmg or math.max(3, def.AtkDamage or 3) * (1 + 0.15 * (st.Floor - 1)) * (opts.Elite and 2 or 1),
		Speed = opts.Speed or math.min(def.Speed, 8) * 0.9,
	}
	model:SetAttribute("EnemyId", e.Id)
	model:PivotTo(CFrame.lookAt(pos, pos + e.Face))
	if opts.Elite then
		model.Name = opts.Name or ("Boss" .. def.Name)
		model:ScaleTo(opts.Scale or 1.4)
		local hl = Instance.new("Highlight")
		hl.FillColor = opts.Glow or Color3.fromRGB(255, 200, 40)
		hl.FillTransparency = 0.55
		hl.OutlineColor = (opts.Glow or Color3.fromRGB(255, 200, 40)):Lerp(Color3.new(1, 1, 1), 0.4)
		hl.Parent = model
	end
	model.Parent = st.Folder.Enemies
	table.insert(room.Enemies, e)
	return e
end

-- (re)fill a room with fresh enemies
local function fillRoom(st, room)
	for _, e in ipairs(room.Enemies) do
		e.Dead = true
		if e.Model then e.Model:Destroy() end
	end
	room.Enemies = {}
	room.Aggro = false
	local pool = {}
	for _, p in ipairs(ENEMY_POOL) do
		if st.Floor >= p[2] then table.insert(pool, p[1]) end
	end
	if room.Kind == "Main" then
		for _ = 1, 2 + st.Floor + math.floor(room.Id / 2) do spawnEnemy(st, room, pool[math.random(#pool)]) end
		if room.Final then
			-- THE OVERLORD: the final boss of the game, with bodyguards
			spawnEnemy(st, room, "Boss", {
				Elite = true, Center = true, Name = "Overlord", Scale = 1.3, Glow = Color3.fromRGB(170, 60, 255),
				HP = 4000, Dmg = 50, Speed = 4.5,
			})
			for _, g in ipairs({ "Tank", "Tank", "Runner", "Runner" }) do spawnEnemy(st, room, g) end
		elseif room.Boss then
			spawnEnemy(st, room, (st.Floor >= 2) and "Tank" or "Grunt", { Elite = true })
		end
	elseif room.Kind == "Lair" then
		-- the Warlord: a huge boss with two bodyguards
		spawnEnemy(st, room, "Boss", {
			Elite = true, Center = true, Name = "Warlord", Scale = 1, Glow = Color3.fromRGB(255, 70, 50),
			HP = 900 * (1 + 0.5 * (st.Floor - 1)), Dmg = 28 * (1 + 0.2 * (st.Floor - 1)), Speed = 4,
		})
		for _ = 1, 2 do spawnEnemy(st, room, "Tank") end
	else
		for _ = 1, 2 + st.Floor do spawnEnemy(st, room, pool[math.random(#pool)]) end
	end
end

local NODE_NEED = { Gold = 4, Crystal = 6, Chest = 2, Hoard = 45 } -- seconds of digging (one unit; more units dig faster)

local function makeNodeModel(kind, pos)
	local m = Instance.new("Model")
	m.Name = kind
	local main
	if kind == "Gold" then
		main = part(m, { Name = "Rock", Size = Vector3.new(3, 2, 3), Position = pos + Vector3.new(0, 1, 0), Color = Color3.fromRGB(95, 92, 100), Material = Enum.Material.Basalt })
		for _, o in ipairs({ Vector3.new(0.8, 1.9, 0.5), Vector3.new(-0.7, 1.5, -0.9), Vector3.new(0.2, 1.2, 1.4), Vector3.new(-1.3, 0.8, 0.6) }) do
			part(m, { Size = Vector3.new(0.7, 0.6, 0.7), Position = pos + o, Color = Color3.fromRGB(255, 200, 40), Material = Enum.Material.Neon })
		end
	elseif kind == "Crystal" then
		main = part(m, { Name = "Base", Size = Vector3.new(2.4, 0.6, 2.4), Position = pos + Vector3.new(0, 0.3, 0), Color = Color3.fromRGB(70, 65, 80), Material = Enum.Material.Slate })
		for k, o in ipairs({ Vector3.new(0, 1.5, 0), Vector3.new(0.8, 1.1, 0.4), Vector3.new(-0.7, 1, -0.5) }) do
			local cr = part(m, { Size = Vector3.new(0.7, (k == 1) and 2.6 or 1.7, 0.7), Color = Color3.fromRGB(175, 95, 255), Material = Enum.Material.Neon, Transparency = 0.1 })
			cr.CFrame = CFrame.new(pos + o) * CFrame.Angles(math.rad(k * 9 - 9), 0, math.rad((k - 2) * 18))
		end
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(175, 95, 255)
		light.Range = 10
		light.Parent = main
	elseif kind == "Hoard" then
		-- a big pile of gold and crystals
		main = part(m, { Name = "Pile", Size = Vector3.new(5.5, 1.4, 5.5), Position = pos + Vector3.new(0, 0.7, 0), Color = Color3.fromRGB(220, 170, 40), Material = Enum.Material.Neon })
		for k = 1, 9 do
			local a = k / 9 * math.pi * 2
			part(m, { Size = Vector3.new(1.1, 0.8, 1.1), Position = pos + Vector3.new(math.cos(a) * 1.7, 1.6 + (k % 3) * 0.35, math.sin(a) * 1.7),
				Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Neon })
		end
		part(m, { Size = Vector3.new(0.8, 2.2, 0.8), Position = pos + Vector3.new(0.4, 2.6, -0.3), Color = Color3.fromRGB(175, 95, 255), Material = Enum.Material.Neon })
		part(m, { Size = Vector3.new(2.4, 1.5, 1.6), Position = pos + Vector3.new(-1.2, 2.2, 0.9), Color = Color3.fromRGB(120, 75, 40), Material = Enum.Material.WoodPlanks })
		local light = Instance.new("PointLight")
		light.Color = Color3.fromRGB(255, 210, 90)
		light.Range = 18
		light.Brightness = 2
		light.Parent = main
	else
		main = part(m, { Name = "Box", Size = Vector3.new(2.6, 1.6, 1.7), Position = pos + Vector3.new(0, 0.8, 0), Color = Color3.fromRGB(120, 75, 40), Material = Enum.Material.WoodPlanks })
		part(m, { Size = Vector3.new(2.7, 0.3, 1.8), Position = pos + Vector3.new(0, 1.45, 0), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Neon })
		part(m, { Size = Vector3.new(0.4, 0.5, 0.2), Position = pos + Vector3.new(0, 1.05, 0.9), Color = Color3.fromRGB(255, 205, 60), Material = Enum.Material.Metal })
	end
	m.PrimaryPart = main
	local bar = Models.AddHealthBar(m, main, (kind == "Hoard") and 4 or 2.6, (kind == "Hoard") and 80 or 46)
	bar.Parent.Parent.Enabled = false
	return m, bar
end

local function addNode(st, room, kind, pos)
	local c = room.Center
	if not pos then
		if room.Kind == "Main" then
			local side = (math.random() < 0.5) and -1 or 1
			pos = Vector3.new(c.X + side * (CORR_HALF + 2 + math.random() * (HW - CORR_HALF - 5)), 0, c.Z + (math.random() - 0.5) * (RL * CELL - 10))
		else
			pos = Vector3.new(c.X + (math.random() - 0.5) * (room.HW * 2 - 8), 0, c.Z + (math.random() - 0.5) * (room.HL * 2 - 8))
			if flat(pos, c) < 5 then pos = pos + Vector3.new(0, 0, 6) end
		end
	end
	local model, bar = makeNodeModel(kind, pos)
	local node = { Id = newId(), Kind = kind, Model = model, Bar = bar, Pos = pos, Work = 0, Need = NODE_NEED[kind], Done = false, Room = room.Id }
	model:SetAttribute("NodeId", node.Id)
	model.Parent = st.Folder.Nodes
	table.insert(room.Nodes, node)
end

local function placeGrave(st, g)
	if g.Model then g.Model:Destroy() end
	local m = Instance.new("Model")
	m.Name = "Grave"
	local stone = part(m, { Name = "Stone", Size = Vector3.new(1.8, 2.2, 0.6), Position = g.Pos + Vector3.new(0, 1.1, 0), Color = Color3.fromRGB(150, 150, 160), Material = Enum.Material.Slate })
	part(m, { Name = "Mound", Size = Vector3.new(2.2, 0.4, 2.6), Position = g.Pos + Vector3.new(0, 0.2, 1), Color = Color3.fromRGB(90, 70, 50), Material = Enum.Material.Ground })
	local gui = Instance.new("BillboardGui")
	gui.Adornee = stone
	gui.Size = UDim2.fromOffset(160, 34)
	gui.StudsOffset = Vector3.new(0, 2.6, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 13
	label.TextColor3 = Color3.fromRGB(200, 230, 255)
	label.TextStrokeTransparency = 0.3
	label.Text = "Fallen " .. g.Def.Name .. "\nClick to revive ($" .. reviveCost(g.Def) .. ")"
	label.Parent = gui
	gui.Parent = m
	m.PrimaryPart = stone
	m:SetAttribute("GraveId", g.Id)
	m.Parent = st.Folder.Graves
	g.Model = m
end

local function newFloor(st)
	for _, name in ipairs({ "Enemies", "Nodes" }) do st.Folder[name]:ClearAllChildren() end
	st.Floor += 1
	local n = 1 + D.BaseRooms + (st.Floor - 1)
	st.Rooms, st.Side, st.All = {}, {}, {}
	for i = 1, n do
		local r = { Id = i, Kind = "Main", Center = roomCenter(st, i), HW = HW, HL = HL, Cleared = (i == 1), Enemies = {}, Nodes = {}, Boss = (i == n),
			Final = (i == n and st.Floor >= D.FinalFloor) }   -- the very last room of the final floor holds the final boss
		st.Rooms[i] = r
		table.insert(st.All, r)
	end
	-- side rooms branch off the middle rooms, to the left or right
	local hosts = {}
	for i = 2, n - 1 do table.insert(hosts, i) end
	for k = #hosts, 2, -1 do
		local r = math.random(k)
		hosts[k], hosts[r] = hosts[r], hosts[k]
	end
	local first = (math.random() < 0.5) and "Treasure" or "Crystal"
	local kinds = { first }
	if API.hasFreeBuff(st.Player) then
		table.insert(kinds, "Lair")
	else
		table.insert(kinds, (first == "Treasure") and "Crystal" or "Treasure")
	end
	for k, kind in ipairs(kinds) do
		local parent = hosts[k]
		if not parent then break end
		local side = (math.random() < 0.5) and -1 or 1
		local sr = {
			Id = 100 + k, Kind = kind, Parent = parent, Side = side, Center = roomCenter(st, parent) + Vector3.new(side * SIDE_STEP, 0, 0),
			HW = SHW, HL = SHW, Cleared = false, Enemies = {}, Nodes = {},
		}
		st.Side[k] = sr
		table.insert(st.All, sr)
	end
	st.Current = 1
	st.FloorDone = false
	buildGeometry(st)
	for i = 2, n do
		local room = st.Rooms[i]
		fillRoom(st, room)
		for _ = 1, math.random(1, 2) do addNode(st, room, "Gold") end
		if room.Boss or math.random() < 0.6 then addNode(st, room, "Crystal") end
		if room.Boss or math.random() < 0.35 then addNode(st, room, "Chest") end
	end
	for _, sr in ipairs(st.Side) do
		fillRoom(st, sr)
		if sr.Kind == "Treasure" then
			addNode(st, sr, "Hoard", sr.Center)
			addNode(st, sr, "Gold")
			addNode(st, sr, "Chest")
		elseif sr.Kind == "Crystal" then
			for _ = 1, 3 + math.random(0, 1) do addNode(st, sr, "Crystal") end
		else
			addNode(st, sr, "Chest")
		end
	end
	-- graves left on the old floor wait at the new entrance
	for k, g in ipairs(st.Graves) do
		g.Pos = roomCenter(st, 1) + Vector3.new(((k - 1) % 5 - 2) * 3, 0, -4 - math.floor((k - 1) / 5) * 3)
		placeGrave(st, g)
	end
	syncAttrs(st)
end

local function getState(player)
	local st = states[player.UserId]
	if st then return st end
	nextSlot += 1
	-- a Model set to Persistent is always sent to players, even though it's far from their character
	local folder = Instance.new("Model")
	folder.ModelStreamingMode = Enum.ModelStreamingMode.Persistent
	folder.Name = tostring(player.UserId)
	folder:SetAttribute("Owner", player.UserId)
	for _, name in ipairs({ "Geometry", "Enemies", "Units", "Nodes", "Graves" }) do
		local f = Instance.new("Folder")
		f.Name = name
		f.Parent = folder
	end
	folder.Parent = rootFolder
	st = {
		Player = player, Uid = player.UserId, Origin = Vector3.new(4000 + nextSlot * 500, 0, 0),
		Floor = 0, Rooms = {}, Side = {}, All = {}, Units = {}, Graves = {}, Active = false, Folder = folder, Current = 1,
	}
	states[player.UserId] = st
	newFloor(st)
	return st
end

---------------------------------------------------------------- units
local function placeUnitModel(u, bob)
	local p = u.Pos + Vector3.new(0, bob or 0, 0)
	u.Model:PivotTo(CFrame.lookAt(p, p + u.Face) * u.Offset)
end

local function spawnUnit(st, def, hp, maxHp, pos)
	local model, bar = Models.Building(def, Vector3.zero)
	local u = {
		Id = newId(), Def = def, Model = model, Bar = bar, HP = hp, MaxHP = maxHp, Pos = pos,
		Face = Vector3.new(0, 0, -1), Offset = model:GetPivot(), Cd = 0, Bob = 0,
	}
	model:SetAttribute("UnitId", u.Id)
	model:SetAttribute("Owner", st.Uid)
	if bar then Models.SetBar(bar, hp / maxHp) end
	placeUnitModel(u)
	model.Parent = st.Folder.Units
	table.insert(st.Units, u)
	return u
end

local function killUnit(st, u)
	if u.Dead then return end
	u.Dead = true
	Models.Boom(u.Pos + Vector3.new(0, 2, 0), 2.5, Color3.fromRGB(255, 80, 70))
	u.Model:Destroy()
	local k = table.find(st.Units, u)
	if k then table.remove(st.Units, k) end
	local g = { Id = newId(), Def = u.Def, Pos = u.Pos, MaxHP = u.MaxHP }
	table.insert(st.Graves, g)
	placeGrave(st, g)
	if #st.Units == 0 then
		API.notify(st.Player, "Your whole squad fell! Revive them at their graves, or retreat.")
	else
		API.notify(st.Player, u.Def.Name .. " fell! Click its grave to revive it ($" .. reviveCost(u.Def) .. ").")
	end
	syncAttrs(st)
end

---------------------------------------------------------------- enemies, rooms, loot
local function openDoor(door)
	if not door then return end
	TweenService:Create(door, TweenInfo.new(0.8), { Position = door.Position - Vector3.new(0, WALL_H + 1, 0) }):Play()
	task.delay(0.9, function() door:Destroy() end)
end

local function clearRoom(st, room)
	if room.Cleared then return end
	room.Cleared = true
	if room.Kind == "Main" then
		st.Current = math.max(st.Current, room.Id)
		openDoor(room.Door)
		room.Door = nil
		local opened = {}
		for _, sr in ipairs(st.Side) do
			if sr.Parent == room.Id then
				openDoor(sr.Door)
				sr.Door = nil
				table.insert(opened, SIDE_INFO[sr.Kind].Name .. " (" .. ((sr.Side < 0) and "left" or "right") .. ")")
			end
		end
		if room.Final then
			-- beating the final boss wins the whole match
			st.FloorDone = true
			syncAttrs(st)
			API.winGame(st.Player)
			return
		elseif room.Boss then
			st.FloorDone = true
			local bonus = 2 + st.Floor
			API.addCrystals(st.Player, bonus)
			API.notify(st.Player, "Floor " .. st.Floor .. " cleared! +" .. bonus .. " crystals. A deeper floor opens after the next wave.")
		elseif #opened > 0 then
			API.notify(st.Player, "Room cleared! A side room opened: " .. table.concat(opened, ", "))
		else
			API.notify(st.Player, "Room cleared! The next door is open.")
		end
	elseif room.Kind == "Lair" then
		local buff = API.grantBuff(st.Player)
		if buff then
			API.notify(st.Player, "WARLORD DEFEATED! Buff for the rest of the match: " .. buff.Name .. " - " .. buff.Desc)
			Models.Popup(room.Center + Vector3.new(0, 8, 0), buff.Name .. "!", Color3.fromRGB(255, 120, 90))
		else
			API.addCrystals(st.Player, 6)
			API.notify(st.Player, "Warlord defeated! You already have every buff, so: +6 crystals.")
		end
	else
		API.notify(st.Player, SIDE_INFO[room.Kind].Name .. " cleared! Dig up the loot.")
	end
	syncAttrs(st)
end

local function killEnemy(st, e)
	if e.Dead then return end
	e.Dead = true
	Models.Boom(e.Pos + Vector3.new(0, 2, 0), 2 * e.Def.Scale, Color3.fromRGB(255, 220, 120))
	e.Model:Destroy()
	local room = getRoom(st, e.Room)
	local k = table.find(room.Enemies, e)
	if k then table.remove(room.Enemies, k) end
	API.reduceNextWave(D.KillReduces * (e.Elite and 3 or 1))
	API.addCoins(st.Player, math.floor(e.Def.Reward * 0.5))
	if #room.Enemies == 0 then clearRoom(st, room) end
end

local function damageEnemy(st, e, amount)
	if e.Dead then return end
	e.HP -= amount
	getRoom(st, e.Room).Aggro = true
	Models.SetBar(e.Bar, e.HP / e.MaxHP)
	if e.HP <= 0 then killEnemy(st, e) end
end

local function finishNode(st, node)
	node.Done = true
	local p = st.Player
	local text
	if node.Kind == "Gold" then
		local n = 30 + 12 * st.Floor
		API.addCoins(p, n)
		text = "+$" .. n
	elseif node.Kind == "Crystal" then
		local n = 1 + math.random(0, 1) + ((st.Floor >= 3) and 1 or 0)
		API.addCrystals(p, n)
		text = "+" .. n .. " crystal" .. ((n > 1) and "s" or "")
	elseif node.Kind == "Hoard" then
		local coins = 250 + 100 * st.Floor
		local cr = 4 + st.Floor
		API.addCoins(p, coins)
		API.addCrystals(p, cr)
		text = "TREASURE! +$" .. coins .. "  +" .. cr .. " crystals"
		API.notify(p, "You looted the treasure hoard: +$" .. coins .. " and +" .. cr .. " crystals!")
	else
		local n = 50 + 20 * st.Floor
		API.addCoins(p, n)
		text = "+$" .. n
		if math.random() < 0.4 then
			API.addCrystals(p, 1)
			text ..= "  +1 crystal"
		end
	end
	local color = (node.Kind == "Crystal") and Color3.fromRGB(200, 140, 255) or Color3.fromRGB(255, 225, 90)
	Models.Popup(node.Pos + Vector3.new(0, 4, 0), text, color)
	Models.Boom(node.Pos + Vector3.new(0, 1.5, 0), (node.Kind == "Hoard") and 5 or 2.5, color)
	node.Model:Destroy()
end

-- spear / sweep attack of a unit, same shapes as on the surface
local function unitAttack(st, u, target)
	local def = u.Def
	-- Goblin Guard's Long Spear: more range and damage for a while
	local longOn = u.LongUntil ~= nil and clock < u.LongUntil
	local LONG = Config.Abilities.Goblin.E
	local range = def.Range * CELL * (longOn and LONG.Range or 1)
	local fv = flatVec(u.Pos, target.Pos)
	if fv.Magnitude > 0.05 then u.Face = fv.Unit end
	local face = u.Face
	local dmg = def.Damage * API.unitDamageMul(st.Uid) * (longOn and LONG.Damage or 1)
	local victims = {}
	local cosHalf = math.cos(math.rad((def.SweepAngle or 0) / 2))
	for _, e in ipairs(getRoom(st, target.Room).Enemies) do
		local v = flatVec(u.Pos, e.Pos)
		if def.Attack == "Spear" then
			local along = v:Dot(face)
			if along >= -CELL * 0.3 and along <= range and (v - face * along).Magnitude <= (def.SpearWidth or 0.45) * CELL then
				table.insert(victims, e)
			end
		elseif def.Attack == "Sweep" then
			local d = v.Magnitude
			if d <= range and (d < CELL * 0.4 or v.Unit:Dot(face) >= cosHalf) then table.insert(victims, e) end
		end
	end
	if #victims == 0 then victims = { target } end
	if def.Attack == "Spear" then
		Models.Thrust(u.Pos + Vector3.new(0, 2.2, 0), face, range)
	elseif def.Attack == "Sweep" then
		Models.Sweep(u.Pos + Vector3.new(0, 2.5, 0), face, range, def.SweepAngle, Color3.fromRGB(255, 190, 110))
	else
		Models.Beam(u.Pos + Vector3.new(0, 2, 0), target.Pos + Vector3.new(0, 2, 0), Color3.fromRGB(255, 90, 90), 0.4)
	end
	for _, e in ipairs(victims) do damageEnemy(st, e, dmg) end
end

-- move a body towards goal, sliding along walls; returns true if it moved
local function stepTowards(st, body, goal, speed, dt)
	local dir = flatVec(body.Pos, goal)
	local d = dir.Magnitude
	if d < 0.05 then return false end
	local np = body.Pos + dir.Unit * math.min(d, speed * dt)
	body.Face = dir.Unit
	if canBeAt(st, np) then
		body.Pos = np
		return true
	end
	local nx, nz = Vector3.new(np.X, 0, body.Pos.Z), Vector3.new(body.Pos.X, 0, np.Z)
	if canBeAt(st, nx) then body.Pos = nx return true end
	if canBeAt(st, nz) then body.Pos = nz return true end
	return false
end

---------------------------------------------------------------- unit abilities (Q / E / R)
local function openEnemies(st)
	local out = {}
	for _, room in ipairs(st.All) do
		if roomOpen(st, room.Id) then
			for _, e in ipairs(room.Enemies) do table.insert(out, e) end
		end
	end
	return out
end

-- Ogre's Spin Slide / Guard's Charge, one frame at a time
local function updateDungeonDash(st, u, dt)
	local dash = u.Dash
	local ab = dash.Ab
	local step = math.min(dash.Left, dash.Speed * dt)
	local np = u.Pos + dash.Dir * step
	if step <= 0 or not canBeAt(st, np) then
		u.Dash = nil
		return
	end
	u.Pos = np
	dash.Left -= step
	if dash.Kind == "Slide" then
		dash.Tick -= dt
		if dash.Tick <= 0 then
			dash.Tick = 0.3
			local r = 1.6 * CELL
			Models.Sweep(u.Pos + Vector3.new(0, 2.5, 0), dash.Dir, r, 360, Color3.fromRGB(180, 230, 255))
			for _, e in ipairs(openEnemies(st)) do
				if not e.Dead and flat(e.Pos, u.Pos) <= r then damageEnemy(st, e, u.Def.Damage * ab.Damage * dash.DmgMul) end
			end
		end
		dash.Spin += dt * 18
		u.Face = CFrame.Angles(0, dash.Spin, 0):VectorToWorldSpace(Vector3.new(0, 0, -1))
	else
		local r = 1.3 * CELL
		for _, e in ipairs(openEnemies(st)) do
			if not e.Dead and not dash.Hit[e] and flat(e.Pos, u.Pos) <= r then
				dash.Hit[e] = true
				damageEnemy(st, e, u.Def.Damage * ab.Damage * dash.DmgMul)
				if not e.Dead then
					local away = flatVec(u.Pos, e.Pos)
					local side = (away.Magnitude > 0.1) and away.Unit or Vector3.new(-dash.Dir.Z, 0, dash.Dir.X)
					e.Pos = clampInRoom(st, e.Room, e.Pos + (side + dash.Dir).Unit * ab.Push)
				end
				Models.Boom(e.Pos + Vector3.new(0, 2, 0), 1.5, Color3.fromRGB(255, 200, 120))
			end
		end
		u.Face = dash.Dir
	end
	if dash.Left <= 0 then
		u.Dash = nil
		u.Face = dash.Dir
	end
end

local function updateState(st, dt)
	-- units ---------------------------------------------------------
	for _, u in ipairs(table.clone(st.Units)) do
		if u.Dead then continue end
		if u.Dash then
			updateDungeonDash(st, u, dt)
			placeUnitModel(u, 0)
			continue
		end
		u.Cd -= dt
		local moving = false
		local target
		if not u.Route then
			local best, bd = nil, AGGRO
			for _, room in ipairs(st.All) do
				if roomOpen(st, room.Id) then
					for _, e in ipairs(room.Enemies) do
						local d = flat(u.Pos, e.Pos)
						if d < bd then best, bd = e, d end
					end
				end
			end
			target = best
		end
		if u.Route then
			-- walking where the player clicked. Doorway points are shared by the whole squad, so a unit only needs
			-- to get near one (not onto it), and a unit shoved around by the crowd skips ahead after a moment.
			local goal = u.Route[u.Wp]
			local last = u.Wp >= #u.Route
			local d = flat(u.Pos, goal)
			if d < (last and 0.6 or 2.4) then
				u.Wp += 1
				u.StuckT, u.BestD = 0, nil
			else
				if u.BestD == nil or d < u.BestD - 0.05 then
					u.BestD, u.StuckT = d, 0
				else
					u.StuckT = (u.StuckT or 0) + dt
				end
				if u.StuckT > 1.2 then
					-- no progress: move on to the next point (or call it arrived if this was the end)
					u.Wp += 1
					u.StuckT, u.BestD = 0, nil
				end
			end
			if u.Wp > #u.Route then u.Route = nil end
			if u.Route then
				moving = stepTowards(st, u, u.Route[u.Wp], u.Def.WalkSpeed or 6, dt)
				if not moving then
					-- blocked: work out a fresh route once, then give up (e.g. a closed door)
					if u.Dest and not u.Rerouted then
						u.Route, u.Wp, u.Rerouted = route(st, u.Pos, u.Dest), 1, true
					else
						u.Route = nil
					end
				end
			end
		elseif target then
			if flat(u.Pos, target.Pos) > u.Def.Range * CELL * 0.85 * ((u.LongUntil and clock < u.LongUntil) and Config.Abilities.Goblin.E.Range or 1) then
				local goal = (regionOf(st, u.Pos) == target.Room) and target.Pos or route(st, u.Pos, target.Pos)[1]
				moving = stepTowards(st, u, goal, u.Def.WalkSpeed or 6, dt)
			elseif u.Cd <= 0 then
				unitAttack(st, u, target)
				u.Cd = u.Def.Interval
			else
				local fv = flatVec(u.Pos, target.Pos)
				if fv.Magnitude > 0.05 then u.Face = fv.Unit end
			end
		else
			-- digging: the node it was sent to, or anything right next to it
			if not (u.Mine and not u.Mine.Done) then
				u.Mine = nil
				for _, room in ipairs(st.All) do
					if roomOpen(st, room.Id) then
						for _, node in ipairs(room.Nodes) do
							if not node.Done and flat(u.Pos, node.Pos) < ((node.Kind == "Hoard") and 6 or 4.5) then u.Mine = node end
						end
					end
				end
			end
			local node = u.Mine
			if node then
				local reach = (node.Kind == "Hoard") and 6 or 4.5
				if flat(u.Pos, node.Pos) > reach then
					local goal = (regionOf(st, u.Pos) == node.Room) and node.Pos or route(st, u.Pos, node.Pos)[1]
					moving = stepTowards(st, u, goal, u.Def.WalkSpeed or 6, dt)
				else
					node.Work += dt * ((u.Def.Id == "Ogre") and 1.3 or 1)
					local fv = flatVec(u.Pos, node.Pos)
					if fv.Magnitude > 0.05 then u.Face = fv.Unit end
					u.Bob += dt * 10
					if node.Work >= node.Need then finishNode(st, node) end
				end
			end
		end
		if moving then u.Bob += dt * 12 end
		local bob = (moving or (u.Mine and not u.Mine.Done and not u.Route)) and math.abs(math.sin(u.Bob)) * 0.3 or 0
		placeUnitModel(u, bob)
	end
	-- keep units from standing inside each other
	for a = 1, #st.Units do
		for b = a + 1, #st.Units do
			local ua, ub = st.Units[a], st.Units[b]
			local v = flatVec(ua.Pos, ub.Pos)
			local d = v.Magnitude
			if d < 2.4 then
				local push = (d > 0.01) and v.Unit or Vector3.new(1, 0, 0)
				local pa, pb = ua.Pos - push * (2.4 - d) / 2, ub.Pos + push * (2.4 - d) / 2
				if canBeAt(st, pa) then ua.Pos = pa end
				if canBeAt(st, pb) then ub.Pos = pb end
			end
		end
	end

	-- dig progress bars
	for _, room in ipairs(st.All) do
		for k = #room.Nodes, 1, -1 do
			local node = room.Nodes[k]
			if node.Done then
				table.remove(room.Nodes, k)
			elseif node.Work > 0 then
				node.Bar.Parent.Parent.Enabled = true
				node.Bar.Size = UDim2.fromScale(math.clamp(node.Work / node.Need, 0, 1), 1)
				node.Bar.BackgroundColor3 = Color3.fromRGB(255, 210, 80)
			end
		end
	end

	-- enemies -------------------------------------------------------
	for _, room in ipairs(st.All) do
		if not roomOpen(st, room.Id) then continue end
		for _, e in ipairs(table.clone(room.Enemies)) do
			if e.Dead then continue end
			if e.StunUntil and clock < e.StunUntil then continue end   -- stunned: frozen in place
			local best, bd = nil, math.huge
			for _, u in ipairs(st.Units) do
				if not u.Dead then
					local d = flat(e.Pos, u.Pos)
					if d < bd then best, bd = u, d end
				end
			end
			if best and bd < AGGRO + CELL then room.Aggro = true end
			local moving = false
			if room.Aggro and best then
				local fv = flatVec(e.Pos, best.Pos)
				if fv.Magnitude > 0.05 then e.Face = fv.Unit end
				local reach = ENEMY_REACH * ((e.Def.Scale > 2) and 1.5 or 1)
				if bd > reach then
					e.Pos = clampInRoom(st, room.Id, e.Pos + e.Face * e.Speed * dt)
					moving = true
				else
					e.Cd -= dt
					if e.Cd <= 0 then
						e.Cd = e.Def.AtkInterval or 1
						-- Goblin Guard's Shield Up takes most of the hit
						local shielded = best.ShieldUntil ~= nil and clock < best.ShieldUntil
						best.HP -= e.Dmg * (shielded and (1 - Config.Abilities.Goblin.Q.Reduce) or 1)
						if best.Bar then Models.SetBar(best.Bar, best.HP / best.MaxHP) end
						Models.Boom(best.Pos + Vector3.new(0, 2, 0), 0.9, Color3.fromRGB(255, 120, 90))
						if best.HP <= 0 then killUnit(st, best) end
					end
				end
			end
			if moving then e.Bob += dt * e.Speed * 1.4 end
			local bob = moving and math.abs(math.sin(e.Bob)) * 0.4 or 0
			local p = e.Pos + Vector3.new(0, bob, 0)
			e.Model:PivotTo(CFrame.lookAt(p, p + e.Face))
		end
		-- keep enemies apart a little
		local list = room.Enemies
		for a = 1, #list do
			for b = a + 1, #list do
				local v = flatVec(list[a].Pos, list[b].Pos)
				local d = v.Magnitude
				if d < 2.2 then
					local push = (d > 0.01) and v.Unit or Vector3.new(0, 0, 1)
					list[a].Pos = clampInRoom(st, room.Id, list[a].Pos - push * (2.2 - d) / 2)
					list[b].Pos = clampInRoom(st, room.Id, list[b].Pos + push * (2.2 - d) / 2)
				end
			end
		end
	end
end

---------------------------------------------------------------- public
function Dungeon.init(api)
	API = api
	rootFolder = workspace:FindFirstChild("Dungeons")
	if rootFolder then rootFolder:Destroy() end
	rootFolder = Instance.new("Folder")
	rootFolder.Name = "Dungeons"
	rootFolder.Parent = workspace
end

function Dungeon.update(dt)
	clock += dt
	for _, st in pairs(states) do
		if st.Active then updateState(st, dt) end
	end
end

-- Q / E / R pressed for units in the dungeon
function Dungeon.useAbility(player, key, ids, tx, tz)
	local st = states[player.UserId]
	if not st or not st.Active then return end
	local want = {}
	for _, id in ipairs(ids) do want[id] = true end
	local target = (typeof(tx) == "number" and typeof(tz) == "number") and Vector3.new(tx, 0, tz) or nil
	local speed = workspace:GetAttribute("GameSpeed") or 1
	for _, u in ipairs(st.Units) do
		if not u.Dead and want[u.Id] and not u.Dash then
			local kit = Config.Abilities[u.Def.Id]
			local ab = kit and kit[key]
			u.Ready = u.Ready or {}
			if ab and (u.Ready[key] or 0) <= clock then
				local dmgMul = API.unitDamageMul(st.Uid)
				local function aura(name, color, duration)
					local old = u.Model:FindFirstChild(name)
					if old then old:Destroy() end
					local h = Instance.new("Highlight")
					h.Name = name
					h.FillColor, h.OutlineColor, h.FillTransparency = color, color, 0.65
					h.Parent = u.Model
					task.delay(duration / speed, function() if h.Parent then h:Destroy() end end)
				end
				if ab.Id == "Slide" or ab.Id == "Charge" then
					local dir = target and flatVec(u.Pos, target) or u.Face
					if dir.Magnitude < 0.1 then dir = u.Face end
					dir = dir.Unit
					u.Route, u.Mine = nil, nil
					u.Dash = { Kind = ab.Id, Dir = dir, Left = ab.Distance * CELL, Speed = ab.Speed, Ab = ab, Tick = 0, Hit = {}, Spin = 0, DmgMul = dmgMul }
					u.Face = dir
					if ab.Id == "Charge" then Models.StatusMark(u.Model, "AbilityMark", "CHARGE!", Color3.fromRGB(255, 200, 120), 1) end
				elseif ab.Id == "Slam" then
					local r = ab.Radius * CELL
					Models.Boom(u.Pos + Vector3.new(0, 0.5, 0), r, Color3.fromRGB(210, 170, 110))
					Models.Boom(u.Pos + Vector3.new(0, 1.5, 0), r * 0.6, Color3.fromRGB(255, 240, 160))
					for _, e in ipairs(openEnemies(st)) do
						if not e.Dead and flat(e.Pos, u.Pos) <= r then
							damageEnemy(st, e, u.Def.Damage * ab.Damage * dmgMul)
							if not e.Dead then
								e.StunUntil = clock + ab.Stun
								Models.StatusMark(e.Model, "StunMark", "STUNNED", Color3.fromRGB(255, 230, 90), ab.Stun / speed)
							end
						end
					end
				elseif ab.Id == "Heal" then
					u.HP = u.MaxHP
					if u.Bar then Models.SetBar(u.Bar, 1) end
					Models.Boom(u.Pos + Vector3.new(0, 2.5, 0), 4, Color3.fromRGB(120, 255, 140))
					Models.Popup(u.Pos + Vector3.new(0, 7, 0), "FULL HEAL", Color3.fromRGB(120, 255, 140))
				elseif ab.Id == "Shield" then
					u.ShieldUntil = clock + ab.Duration
					aura("ShieldAura", Color3.fromRGB(110, 190, 255), ab.Duration)
					Models.StatusMark(u.Model, "AbilityMark", "SHIELD", Color3.fromRGB(140, 200, 255), ab.Duration / speed)
				elseif ab.Id == "Long" then
					u.LongUntil = clock + ab.Duration
					aura("LongAura", Color3.fromRGB(255, 180, 70), ab.Duration)
					Models.StatusMark(u.Model, "AbilityMark", "LONG SPEAR", Color3.fromRGB(255, 190, 90), ab.Duration / speed)
				end
				u.Ready[key] = clock + ab.Cooldown
				u.Model:SetAttribute("Ready_" .. key, workspace:GetServerTimeNow() + ab.Cooldown / speed)
			end
		end
	end
end

-- a unit stepped through the portal
function Dungeon.addUnit(player, def, hp, maxHp)
	local st = getState(player)
	local c = roomCenter(st, st.Current)
	local n = #st.Units
	local pos = c + Vector3.new(((n % 4) - 1.5) * 3, 0, 2 + math.floor(n / 4) * 3)
	if not canBeAt(st, pos) then pos = Vector3.new(c.X, 0, c.Z) end
	spawnUnit(st, def, hp, maxHp, pos)
	Models.Boom(pos + Vector3.new(0, 2, 0), 2.5, Color3.fromRGB(90, 220, 255))
	if not st.Active then
		st.Active = true
		API.notify(player, "Your squad entered dungeon floor " .. st.Floor .. "! Click to move, click ore to dig.")
	end
	syncAttrs(st)
end

-- leave: living units go back to the base; cleared rooms are remembered
function Dungeon.retreat(player)
	local st = states[player.UserId]
	if not st or not st.Active then return end
	for _, u in ipairs(st.Units) do
		if not u.Dead then
			API.returnUnit(player, u.Def, u.HP / u.MaxHP)
			u.Dead = true
			u.Model:Destroy()
		end
	end
	st.Units = {}
	st.Active = false
	-- rooms you didn't finish start over next time
	for _, room in ipairs(st.All) do
		if not room.Cleared and room.Id ~= 1 then fillRoom(st, room) end
	end
	API.notify(player, "Retreated! Progress saved: " .. (st.Current - 1) .. " of " .. (#st.Rooms - 1) .. " rooms cleared.")
	syncAttrs(st)
end

-- after each surface wave: a finished floor is replaced by a deeper one
function Dungeon.onWaveEnd(player)
	local st = states[player.UserId]
	if st and st.FloorDone and not st.Active then
		newFloor(st)
		if st.Floor >= D.FinalFloor then
			API.notify(player, "THE FINAL FLOOR is open! The Overlord waits in the last room - beat him to win the game!")
		else
			API.notify(player, "Dungeon floor " .. st.Floor .. " is open - tougher enemies, better loot!")
		end
	end
end

-- health buffs/upgrades also boost units already in the dungeon
function Dungeon.scaleUnitHP(uid, factor)
	local st = states[uid]
	if not st then return end
	for _, u in ipairs(st.Units) do
		u.MaxHP *= factor
		u.HP *= factor
	end
end

-- test console: wipe out the first main room that isn't cleared yet
function Dungeon.devClearRoom(player)
	local st = getState(player)
	for _, room in ipairs(st.Rooms) do
		if not room.Cleared then
			for _, e in ipairs(table.clone(room.Enemies)) do killEnemy(st, e) end
			if not room.Cleared then clearRoom(st, room) end
			return true
		end
	end
	return false
end

-- test console: skip straight to the final floor (only while your squad is outside)
function Dungeon.devFinalFloor(player)
	local st = getState(player)
	if st.Active then return false end
	st.Floor = D.FinalFloor - 1
	newFloor(st)
	return true
end

function Dungeon.removePlayer(uid)
	local st = states[uid]
	if st then
		st.Folder:Destroy()
		states[uid] = nil
	end
end

function Dungeon.resetAll()
	for uid, st in pairs(states) do
		st.Folder:Destroy()
		local p = Players:GetPlayerByUserId(uid)
		if p then p:SetAttribute("InDungeon", false) end
	end
	states = {}
end

-- player commands from the dungeon screen
function Dungeon.handle(player, action, a, b, c)
	local st = states[player.UserId]
	if not st or not st.Active then return end
	local function pickUnits(ids)
		local list = {}
		if typeof(ids) == "table" then
			for _, id in ipairs(ids) do
				for _, u in ipairs(st.Units) do
					if u.Id == id and not u.Dead then table.insert(list, u) end
				end
			end
		end
		if #list == 0 then
			for _, u in ipairs(st.Units) do
				if not u.Dead then table.insert(list, u) end
			end
		end
		return list
	end

	if action == "Move" then
		if typeof(a) ~= "number" or typeof(b) ~= "number" then return end
		local to = Vector3.new(a, 0, b)
		local units = pickUnits(c)
		for k, u in ipairs(units) do
			local dest = to
			if #units > 1 then
				local ang = (k - 1) / #units * math.pi * 2
				local off = to + Vector3.new(math.cos(ang), 0, math.sin(ang)) * 2.6
				if canBeAt(st, off) then dest = off end
			end
			u.Route = route(st, u.Pos, dest)
			u.Wp = 1
			u.Mine = nil
			u.Dest, u.Rerouted, u.StuckT, u.BestD = dest, false, 0, nil
		end

	elseif action == "Mine" then
		local node
		for _, room in ipairs(st.All) do
			if roomOpen(st, room.Id) then
				for _, nd in ipairs(room.Nodes) do
					if nd.Id == a and not nd.Done then node = nd end
				end
			end
		end
		if not node then return end
		local units = pickUnits(b)
		for k, u in ipairs(units) do
			-- spread around the node so several units can dig together
			local away = flatVec(node.Pos, u.Pos)
			local dir = (away.Magnitude > 0.1) and away.Unit or Vector3.new(0, 0, 1)
			if #units > 1 then dir = CFrame.Angles(0, (k - 1) / #units * math.pi * 2, 0):VectorToWorldSpace(dir) end
			local spot = node.Pos + dir * ((node.Kind == "Hoard") and 4.5 or 3.2)
			if not canBeAt(st, spot) then spot = node.Pos end
			u.Route = route(st, u.Pos, spot)
			u.Wp = 1
			u.Mine = node
			u.Dest, u.Rerouted, u.StuckT, u.BestD = spot, false, 0, nil
		end

	elseif action == "Revive" then
		for k, g in ipairs(st.Graves) do
			if g.Id == a then
				local cost = reviveCost(g.Def)
				if API.getCoins(player) < cost then
					API.notify(player, "Reviving costs $" .. cost .. " - not enough coins")
					return
				end
				API.addCoins(player, -cost)
				table.remove(st.Graves, k)
				if g.Model then g.Model:Destroy() end
				local pos = canBeAt(st, g.Pos) and g.Pos or roomCenter(st, st.Current)
				spawnUnit(st, g.Def, g.MaxHP * D.ReviveHP, g.MaxHP, pos)
				Models.Boom(pos + Vector3.new(0, 2, 0), 3, Color3.fromRGB(150, 255, 180))
				API.notify(player, g.Def.Name .. " revived!")
				syncAttrs(st)
				return
			end
		end

	elseif action == "Retreat" then
		Dungeon.retreat(player)
	end
end

return Dungeon
