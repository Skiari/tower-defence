-- City Defense: main server logic
local Players = game:GetService("Players")
local RS = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local SSS = game:GetService("ServerScriptService")
local Debris = game:GetService("Debris")
local TweenService = game:GetService("TweenService")
local HttpService = game:GetService("HttpService")
local Lighting = game:GetService("Lighting")

---------------------------------------------------------------- game speed (1x / 2x / 3x)
-- Every task.wait / task.delay in this script runs on a game clock that ticks faster at 2x or 3x.
local gameSpeed = 1
local gameTime = 0
local timers = {}
local realTask = task
local function sdelay(t, fn, ...)
	table.insert(timers, { At = gameTime + (t or 0), Fn = fn, Args = table.pack(...) })
end
local function swait(t)
	local thread = coroutine.running()
	local start = gameTime
	sdelay(t or 0, function() realTask.spawn(thread, gameTime - start) end)
	return coroutine.yield()
end
local task = setmetatable({ wait = swait, delay = sdelay }, { __index = realTask })
local function runTimers()
	if #timers == 0 then return end
	local due = {}
	for k = #timers, 1, -1 do
		if timers[k].At <= gameTime then table.insert(due, table.remove(timers, k)) end
	end
	for k = #due, 1, -1 do
		local tm = due[k]
		realTask.spawn(tm.Fn, table.unpack(tm.Args, 1, tm.Args.n))
	end
end
workspace:SetAttribute("GameSpeed", 1)

local Config = require(RS:WaitForChild("Shared"):WaitForChild("Config"))
local Models = require(RS:WaitForChild("Shared"):WaitForChild("Models"))
local Dungeon = require(SSS:WaitForChild("Dungeon"))

local W, H, CELL, TOP = Config.GridW, Config.GridH, Config.Cell, Config.TileTop
local N = W * H
local DIRS = { { 1, 0 }, { -1, 0 }, { 0, 1 }, { 0, -1 } }

---------------------------------------------------------------- remotes
local oldRemotes = RS:FindFirstChild("Remotes")
if oldRemotes then oldRemotes:Destroy() end
local remotes = Instance.new("Folder")
remotes.Name = "Remotes"
local function makeRemote(name)
	local r = Instance.new("RemoteEvent")
	r.Name = name
	r.Parent = remotes
	return r
end
local placeRemote = makeRemote("PlaceItem")
local sellRemote = makeRemote("SellItem")
local readyRemote = makeRemote("ReadyUp")
local notifyRemote = makeRemote("Notify")
local moveRemote = makeRemote("MoveUnit")
local dungeonRemote = makeRemote("Dungeon")
local speedRemote = makeRemote("SetSpeed")
local abilityRemote = makeRemote("UnitAbility")
local devRemote = makeRemote("DevCommand")
remotes.Parent = RS

---------------------------------------------------------------- grid helpers
local function toIdx(i, j) return (j - 1) * W + i end
local function fromIdx(idx) return (idx - 1) % W + 1, (idx - 1) // W + 1 end
local function inBounds(i, j) return i >= 1 and i <= W and j >= 1 and j <= H end
local function cellCenter(i, j)
	return Vector3.new((i - (W + 1) / 2) * CELL, TOP, (j - (H + 1) / 2) * CELL)
end
local function flatDist(a, b)
	return math.sqrt((a.X - b.X) ^ 2 + (a.Z - b.Z) ^ 2)
end

---------------------------------------------------------------- state
local terrain, terrainOwner = {}, {}
local buildings = {}      -- idx -> record
local buildingList = {}   -- record -> true
local enemies = {}        -- id -> record
local tiles = {}
local flows = { ground = {}, climb = {}, fly = {}, bomb = {}, swim = {} }  -- distance-to-city fields per movement type
local flowsDirty = false
local cityIdx, spawnIdx, spawnList = {}, {}, {}
local nextEnemyId = 0
local enemyCount = 0
local cityHP = Config.CityHP
local phase = "Build"
local ready = {}

-- construction + unit bookkeeping
local nextBuildingId = 0
local recById = {}      -- id -> building record (so clients can command units)
local buildJobs = {}    -- userId -> list of records waiting for / under construction, in order
local builders = {}     -- userId -> list of builder workers
local nextBuilderId = 0

-- dungeon portal + how many enemies dungeon kills will remove from the next wave
local waveReduction = 0
local portalIdx = toIdx(Config.Portal[1], Config.Portal[2])
local portalOpen = false
local portalModel = nil

-- test console switches
local devGod, devInstantBuild, devSkipBuild, devJumpWave = false, false, false, nil
-- set when someone beats the final dungeon boss
local gameWon, winnerName = false, nil
local finishBuilding -- defined further down (construction section)

-- global modifiers changed by random events
local mods = { EnemySpeed = 1, EnemyAtk = 1, TowerRange = 1, TowerRate = 1, Reward = 1 }

-- trade route event state
local routeCells = {}   -- idx -> true while a trade route is open
local trade = { Active = false, Moving = false, Truck = nil, Sign = nil, NextWave = 0 }

for idx = 1, N do terrain[idx] = "Grass" end
for i = Config.City.MinI, Config.City.MaxI do
	for j = Config.City.MinJ, Config.City.MaxJ do
		cityIdx[toIdx(i, j)] = true
	end
end
for _, s in ipairs(Config.Spawns) do
	local idx = toIdx(s[1], s[2])
	spawnIdx[idx] = true
	table.insert(spawnList, idx)
end

local mapFolder, tilesFolder, buildingsFolder, enemiesFolder, buildersFolder

---------------------------------------------------------------- coins
local function getCoins(p)
	local ls = p:FindFirstChild("leaderstats")
	return ls and ls.Coins.Value or 0
end
local function addCoins(p, n)
	local ls = p:FindFirstChild("leaderstats")
	if ls then ls.Coins.Value += n end
end
local function notify(p, msg)
	notifyRemote:FireClient(p, msg)
end
local function aliveBuilders(uid)
	local n = 0
	for _, b in ipairs(builders[uid] or {}) do
		if not b.Dead then n += 1 end
	end
	return n
end

-- upgrades bought with crystals (levels live in player attributes Up_<Id>)
local UP_PER = {}
for _, u in ipairs(Config.Upgrades) do UP_PER[u.Id] = u.Per end
local function upMul(uid, key)
	local p = Players:GetPlayerByUserId(uid)
	local level = p and (p:GetAttribute("Up_" .. key) or 0) or 0
	return 1 + level * (UP_PER[key] or 0)
end
-- buffs from beating the dungeon Warlord (player attributes Buff_<Id>)
local function hasBuff(uid, id)
	local p = Players:GetPlayerByUserId(uid)
	return p ~= nil and p:GetAttribute("Buff_" .. id) == true
end
local function damageMul(rec)
	local k = rec.Def.Kind
	if k == "Tower" then return upMul(rec.Owner, "Towers") * (hasBuff(rec.Owner, "Eagle") and 1.25 or 1) end
	if k == "Trap" then return upMul(rec.Owner, "Traps") end
	if k == "Monster" then return upMul(rec.Owner, "Units") * (hasBuff(rec.Owner, "Might") and 1.5 or 1) end
	return 1
end
local function hpMul(uid, def)
	if def.Kind == "Monster" then return upMul(uid, "Units") * (hasBuff(uid, "Might") and 1.5 or 1) end
	if def.Kind == "Terrain" then return 1 end
	return upMul(uid, "Walls") * (hasBuff(uid, "Fortress") and 1.4 or 1)
end

---------------------------------------------------------------- pathfinding
-- Movement modes:
--   ground: blocked by water, towers, monsters. Walls are passable but costly (the enemy must break them).
--   climb:  same, but walls are cheap to cross (the enemy walks over them).
--   fly:    nothing blocks it.
-- the solid building enemies would have to break at idx (ignores construction sites of terrain and walking units)
local function solidAt(idx)
	local b = buildings[idx]
	if b and b.Def.Blocks and b.Def.Kind ~= "Terrain" and not b.Moving then return b end
	return nil
end

-- Only water can truly block: buildings are always passable because enemies break (or climb) through them.
-- Climbers and swimmers cross water too.
local function isBlocked(idx, mode, extra)
	if cityIdx[idx] then return false end
	if mode == "fly" then return false end
	if idx == extra then return true end
	if terrain[idx] == "Water" then return mode ~= "climb" and mode ~= "swim" end
	return false
end

local function enterCost(idx, mode)
	if mode == "fly" then return 1 end
	local c = 1
	local ter = terrain[idx]
	if ter == "Mud" then
		c = Config.MudCost
	elseif ter == "Water" then
		if mode == "climb" then c += Config.WallClimbCost end
		if mode == "swim" then c = Config.SwimWaterCost end
	end
	local b = solidAt(idx)
	if b then
		if b.Def.Kind == "Wall" then
			if mode == "climb" then
				c += Config.WallClimbCost
			elseif mode ~= "bomb" then   -- bombers go *to* walls on purpose
				c += Config.WallBreakCost
			end
		else
			c += Config.BuildingBreakCost
		end
	end
	return c
end

-- Distance-to-city field (Dijkstra from the city outwards)
-- Bomber target priority: 1 walls, 2 other buildings (towers/traps), 3 units (guards/monsters), 4 the city
local bombTier = 4
local function bombTierOf(rec)
	local k = rec.Def.Kind
	if k == "Wall" then return 1 end
	if k == "Tower" or k == "Trap" or k == "Farm" then return 2 end
	if k == "Monster" then return 3 end
	return nil
end

-- binary min-heap used by the pathfinder
local function heapPush(h, d, idx)
	local n = #h + 1
	h[n] = { d, idx }
	while n > 1 do
		local p = n // 2
		if h[p][1] <= h[n][1] then break end
		h[p], h[n] = h[n], h[p]
		n = p
	end
end

local function heapPop(h)
	local top = h[1]
	local last = table.remove(h)
	local n = #h
	if n > 0 then
		h[1] = last
		local i = 1
		while true do
			local l, r, s = i * 2, i * 2 + 1, i
			if l <= n and h[l][1] < h[s][1] then s = l end
			if r <= n and h[r][1] < h[s][1] then s = r end
			if s == i then break end
			h[i], h[s] = h[s], h[i]
			i = s
		end
	end
	return top
end

-- "bomb" mode: the field leads to the nearest wall (falls back to the city if there are no walls)
local function computeFlow(mode, extra)
	local dist = table.create(N, math.huge)
	local done = table.create(N, false)
	local heap = {}
	local seeded = false
	if mode == "bomb" then
		local tier = 4
		for _, b in pairs(buildings) do
			local t = bombTierOf(b)
			if t and t < tier then tier = t end
		end
		bombTier = tier
		if tier < 4 then
			for idx, b in pairs(buildings) do
				if bombTierOf(b) == tier then
					dist[idx] = 0
					heapPush(heap, 0, idx)
					seeded = true
				end
			end
		end
	end
	if not seeded then
		for idx in pairs(cityIdx) do
			dist[idx] = 0
			heapPush(heap, 0, idx)
		end
	end
	while true do
		local best, bd
		while #heap > 0 do
			local top = heapPop(heap)
			if not done[top[2]] then best = top[2]; bd = top[1]; break end
		end
		if not best then break end
		done[best] = true
		local i, j = fromIdx(best)
		local step = enterCost(best, mode)
		for _, d in ipairs(DIRS) do
			local ni, nj = i + d[1], j + d[2]
			if inBounds(ni, nj) then
				local n = toIdx(ni, nj)
				if not done[n] and not isBlocked(n, mode, extra) then
					local nd = bd + step
					if nd < dist[n] then dist[n] = nd; heapPush(heap, nd, n) end
				end
			end
		end
	end
	return dist
end

local function refreshFlows()
	flows.ground = computeFlow("ground")
	flows.climb = computeFlow("climb")
	flows.fly = computeFlow("fly")
	flows.bomb = computeFlow("bomb")
	flows.swim = computeFlow("swim")
	flowsDirty = false
end

local function markDirty()
	flowsDirty = true
end

local function pathExists(dist)
	for _, s in ipairs(spawnList) do
		if dist[s] == math.huge then return false end
	end
	return true
end

---------------------------------------------------------------- tiles
local function baseColor(idx)
	local i, j = fromIdx(idx)
	if cityIdx[idx] then return Color3.fromRGB(130, 130, 140) end
	if spawnIdx[idx] then return Color3.fromRGB(110, 45, 45) end
	if (i + j) % 2 == 0 then return Color3.fromRGB(106, 190, 72) end
	return Color3.fromRGB(96, 176, 64)
end

local function refreshTile(idx)
	local t = tiles[idx]
	if not t then return end
	local ter = terrain[idx]
	local rec = buildings[idx]
	t:SetAttribute("Terrain", ter)
	t:SetAttribute("Occupied", rec ~= nil)
	t:SetAttribute("BOwner", rec and rec.Owner or 0)
	t:SetAttribute("BId", rec and rec.Id or 0)
	t:SetAttribute("BKind", rec and rec.Def.Kind or "")
	t:SetAttribute("TOwner", terrainOwner[idx] or 0)
	t:SetAttribute("Route", routeCells[idx] == true)
	if ter == "Mud" then
		t.Color = Color3.fromRGB(120, 84, 50)
		t.Material = Enum.Material.Ground
	elseif ter == "Water" then
		t.Color = Color3.fromRGB(50, 120, 210)
		t.Material = Enum.Material.SmoothPlastic
	elseif routeCells[idx] then
		t.Color = Color3.fromRGB(205, 175, 115)
		t.Material = Enum.Material.Cobblestone
	else
		t.Color = baseColor(idx)
		t.Material = Enum.Material.Grass
	end
end

local function buildWorld()
	local old = workspace:FindFirstChild("Map")
	if old then old:Destroy() end
	mapFolder = Instance.new("Folder")
	mapFolder.Name = "Map"
	tilesFolder = Instance.new("Folder"); tilesFolder.Name = "Tiles"; tilesFolder.Parent = mapFolder
	buildingsFolder = Instance.new("Folder"); buildingsFolder.Name = "Buildings"; buildingsFolder.Parent = mapFolder
	enemiesFolder = Instance.new("Folder"); enemiesFolder.Name = "Enemies"; enemiesFolder.Parent = mapFolder
	buildersFolder = Instance.new("Folder"); buildersFolder.Name = "Builders"; buildersFolder.Parent = mapFolder

	for idx = 1, N do
		local i, j = fromIdx(idx)
		local c = cellCenter(i, j)
		local t = Instance.new("Part")
		t.Name = i .. "_" .. j
		t.Anchored = true
		t.Size = Vector3.new(CELL, 1, CELL)
		t.Position = Vector3.new(c.X, TOP - 0.5, c.Z)
		t.TopSurface = Enum.SurfaceType.Smooth
		t.BottomSurface = Enum.SurfaceType.Smooth
		t.Parent = tilesFolder
		tiles[idx] = t
		refreshTile(idx)
		if idx % 125 == 0 then task.wait() end
	end

	-- city
	local cc = cellCenter((Config.City.MinI + Config.City.MaxI) / 2, (Config.City.MinJ + Config.City.MaxJ) / 2)
	Models.City(cc).Parent = mapFolder

	-- spawn gates
	for _, s in ipairs(Config.Spawns) do
		Models.Portal(cellCenter(s[1], s[2])).Parent = mapFolder
	end

	mapFolder.Parent = workspace
end

---------------------------------------------------------------- enemies
local function setEnemyCount()
	workspace:SetAttribute("Enemies", enemyCount)
end

-- choose the next cell to walk to. Ground enemies that want to go through a wall stop and break it.
local function pickNextWith(e, field)
	local mode = e.Mode

	-- bombers: if we're standing next to something of the current target tier, light the fuse
	if mode == "bomb" and bombTier < 4 then
		local ci, cj = fromIdx(e.Cell)
		for _, d in ipairs(DIRS) do
			local ni, nj = ci + d[1], cj + d[2]
			if inBounds(ni, nj) then
				local b = buildings[toIdx(ni, nj)]
				if b and not b.Moving and bombTierOf(b) == bombTier then
					e.Breaking = b
					e.FuseT = e.Def.Fuse
					e.Target = e.Cell
					return
				end
			end
		end
	end
	local i, j = fromIdx(e.Cell)
	local best, bv = nil, math.huge
	for _, d in ipairs(DIRS) do
		local ni, nj = i + d[1], j + d[2]
		if inBounds(ni, nj) then
			local n = toIdx(ni, nj)
			if not isBlocked(n, mode) then
				local v = field[n] + enterCost(n, mode)
				if v < bv or (v == bv and math.random() < 0.5) then
					bv = v
					best = n
				end
			end
		end
	end
	e.Target = best or e.Cell
	e.Breaking = nil
	if best and mode ~= "fly" then
		local b = solidAt(best)
		-- anything solid in the way gets attacked (climbers just walk over walls)
		if b and not (mode == "climb" and b.Def.Kind == "Wall") then
			e.Breaking = b
			e.FuseT = e.Def.Fuse
			e.Target = e.Cell
		end
	end
end

local function pickNext(e)
	pickNextWith(e, flows[e.Mode])
	-- a bomber that can't find a wall falls back to the normal ground route
	if e.Mode == "bomb" and e.Target == e.Cell and not e.Breaking then
		pickNextWith(e, flows.ground)
	end
end

local function removeEnemy(e)
	if e.Dead then return end
	e.Dead = true
	enemies[e.Id] = nil
	enemyCount -= 1
	setEnemyCount()
	if e.Model then e.Model:Destroy() end
end

local function killEnemy(e, ownerId)
	if e.Dead then return end
	Models.Boom(e.Pos + Vector3.new(0, 2 + e.Lift, 0), 2 * e.Def.Scale, Color3.fromRGB(255, 220, 120))
	if ownerId then
		local p = Players:GetPlayerByUserId(ownerId)
		if p then addCoins(p, math.floor(e.Def.Reward * mods.Reward * (e.RewardMul or 1))) end
	end
	removeEnemy(e)
end

local function damageEnemy(e, amount, ownerId)
	if e.Dead then return end
	e.HP -= amount
	Models.SetBar(e.Bar, e.HP / e.MaxHP)
	if e.HP <= 0 then killEnemy(e, ownerId) end
end

-- atIdx: optional spawn cell (events); opts.Elite makes a golden champion
local function spawnEnemy(typeName, wave, atIdx, opts)
	local def = Config.Enemies[typeName]
	local sp = atIdx or spawnList[math.random(#spawnList)]
	local i, j = fromIdx(sp)
	local pos = cellCenter(i, j)
	local model, bar = Models.Enemy(def)
	model.Parent = enemiesFolder
	nextEnemyId += 1
	local hp = def.HP * (1 + (wave - 1) * Config.Difficulty.HPPerWave)
	local e = {
		BaseMaxHP = def.HP * (1 + (wave - 1) * Config.Difficulty.HPPerWave),
		Id = nextEnemyId, Def = def, Model = model, Bar = bar, Mode = def.Move or "ground",
		HP = hp, MaxHP = hp, Pos = pos, Cell = sp, Target = sp, Breaking = nil,
		Face = Vector3.new(0, 0, 1), AtkCd = 0, Dead = false, Bob = math.random() * 6,
		Lift = def.Flying and def.FlyHeight or 0,
	}
	enemies[e.Id] = e
	enemyCount += 1
	setEnemyCount()
	pickNext(e)
	model:PivotTo(CFrame.new(pos + Vector3.new(0, e.Lift, 0)))

	if def.Style == "Swimmer" then
		local glow = Instance.new("Highlight")
		glow.Name = "WaterBuff"
		glow.FillColor = Color3.fromRGB(60, 200, 255)
		glow.OutlineColor = Color3.fromRGB(160, 240, 255)
		glow.FillTransparency = 0.5
		glow.Enabled = false
		glow.Parent = model
		e.Glow = glow
	end

	if opts and opts.Elite then
		e.HP *= 5
		e.MaxHP = e.HP
		e.RewardMul = 6
		e.CityMul = 2
		model.Name = "Champion" .. def.Name
		model:ScaleTo(1.35)
		local hl = Instance.new("Highlight")
		hl.FillColor = Color3.fromRGB(255, 200, 40)
		hl.FillTransparency = 0.55
		hl.OutlineColor = Color3.fromRGB(255, 230, 120)
		hl.Parent = model
	end
	return e
end

local function hitCity(e)
	if not devGod then
		cityHP = math.max(0, cityHP - e.Def.CityDamage * (e.CityMul or 1))
	end
	workspace:SetAttribute("CityHP", cityHP)
	Models.Boom(e.Pos + Vector3.new(0, 3 + e.Lift, 0), 3, Color3.fromRGB(255, 80, 80))
	removeEnemy(e)
end

---------------------------------------------------------------- buildings
-- progress bar shown over a construction site
local function makeBuildGui(rec)
	local gui = Instance.new("BillboardGui")
	gui.Name = "BuildGui"
	gui.Adornee = rec.Model.PrimaryPart
	gui.Size = UDim2.fromOffset(74, 24)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.MaxDistance = 160
	gui.AlwaysOnTop = true
	local label = Instance.new("TextLabel")
	label.Size = UDim2.new(1, 0, 0, 13)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBold
	label.TextSize = 12
	label.TextColor3 = Color3.new(1, 1, 1)
	label.TextStrokeTransparency = 0.3
	label.Text = "Queued"
	label.Parent = gui
	local back = Instance.new("Frame")
	back.Position = UDim2.fromOffset(0, 15)
	back.Size = UDim2.new(1, 0, 0, 7)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = gui
	local fill = Instance.new("Frame")
	fill.Size = UDim2.fromScale(0, 1)
	fill.BackgroundColor3 = Color3.fromRGB(90, 180, 255)
	fill.BorderSizePixel = 0
	fill.Parent = back
	gui.Parent = rec.Model
	rec.BuildLabel, rec.BuildFill = label, fill
end

-- Everything starts as a construction site: see-through, not working yet, 30% HP, and it can be attacked.
local function createBuilding(player, def, i, j)
	local idx = toIdx(i, j)
	local pos = cellCenter(i, j)
	local model, bar
	if def.Kind == "Terrain" then
		model = Instance.new("Model")
		model.Name = def.Id .. "Site"
		local p = Instance.new("Part")
		p.Name = "Base"
		p.Anchored, p.CanCollide = true, false
		p.Size = Vector3.new(CELL - 0.4, 0.3, CELL - 0.4)
		p.Position = pos + Vector3.new(0, 0.15, 0)
		p.Color = def.Color
		p.Material = Enum.Material.SmoothPlastic
		p.Transparency = 0.45
		p.Parent = model
		model.PrimaryPart = p
	else
		model, bar = Models.Building(def, pos)
	end
	nextBuildingId += 1
	local maxHP = (def.HP or 0) * hpMul(player.UserId, def)
	local rec = {
		Id = nextBuildingId, Def = def, Owner = player.UserId, I = i, J = j, Idx = idx, Pos = pos,
		Model = model, Bar = bar, HP = maxHP * 0.3, MaxHP = maxHP, Cd = 0, Dead = false, Age = 0,
		Building = true, BuildT = 0, BuildTime = def.BuildTime or 2,
		Face = Vector3.new(0, 0, -1), PivotOffset = CFrame.new(pos):Inverse() * model:GetPivot(),
		Ghost = {}, Effects = {},
	}
	if def.Kind ~= "Terrain" then
		for _, d in ipairs(model:GetDescendants()) do
			if d:IsA("BasePart") then
				rec.Ghost[d] = d.Transparency
				d.Transparency = math.max(d.Transparency, 0.65)
			elseif d:IsA("Fire") or d:IsA("Light") then
				d.Enabled = false
				table.insert(rec.Effects, d)
			end
		end
	end
	if bar then Models.SetBar(bar, 0.3) end
	model:SetAttribute("Id", rec.Id)
	model:SetAttribute("Owner", rec.Owner)
	model:SetAttribute("Kind", def.Kind)
	model:SetAttribute("Building", true)
	makeBuildGui(rec)
	model.Parent = buildingsFolder

	buildings[idx] = rec
	buildingList[rec] = true
	recById[rec.Id] = rec
	buildJobs[rec.Owner] = buildJobs[rec.Owner] or {}
	table.insert(buildJobs[rec.Owner], rec)
	return rec
end

local function removeBuilding(rec)
	rec.Dead = true
	if buildings[rec.Idx] == rec then buildings[rec.Idx] = nil end
	buildingList[rec] = nil
	recById[rec.Id] = nil
	if rec.Model then rec.Model:Destroy() end
	refreshTile(rec.Idx)
	markDirty()
end

local function damageBuilding(rec, amount)
	if rec.Dead then return end
	-- Goblin Guard's Shield Up
	if rec.ShieldUntil and gameTime < rec.ShieldUntil then
		amount *= 1 - Config.Abilities.Goblin.Q.Reduce
	end
	rec.HP -= amount
	if not rec.Bar and rec.MaxHP > 0 and rec.Model and rec.Model.PrimaryPart then
		rec.Bar = Models.AddHealthBar(rec.Model, rec.Model.PrimaryPart, 7, 44)
	end
	if rec.Bar then
		local g = rec.Bar.Parent and rec.Bar.Parent.Parent
		if g and g:IsA("BillboardGui") then g.Enabled = true end
		Models.SetBar(rec.Bar, rec.HP / rec.MaxHP)
	end
	if rec.HP <= 0 then
		Models.Boom(rec.Pos + Vector3.new(0, 2, 0), 3, Color3.fromRGB(200, 200, 200))
		removeBuilding(rec)
	end
end

local function enemyNearCell(idx)
	local i, j = fromIdx(idx)
	local c = cellCenter(i, j)
	for _, e in pairs(enemies) do
		if not e.Def.Flying then
			if e.Cell == idx or e.Target == idx then return true end
			if flatDist(e.Pos, c) < CELL * 0.9 then return true end
		end
	end
	return false
end

local function tryPlace(player, itemId, i, j)
	if phase == "GameOver" or phase == "Victory" then return false, "The match is over - a new one starts soon" end
	local def = Config.ItemsById[itemId]
	if not def then return false end
	-- units don't need builders; everything else does
	if def.Kind ~= "Monster" and aliveBuilders(player.UserId) == 0 then
		return false, "All your builders are dead - no building until the next wave"
	end
	if not inBounds(i, j) then return false end
	local idx = toIdx(i, j)
	if cityIdx[idx] then return false, "You can't build on the city" end
	if idx == portalIdx then return false, "That spot is for the dungeon portal" end
	if spawnIdx[idx] then return false, "You can't build on a spawn gate" end
	if routeCells[idx] then return false, "Keep the trade route clear!" end
	if getCoins(player) < def.Cost then return false, "Not enough coins" end

	if def.Kind == "Terrain" then
		if buildings[idx] then return false, "Something is built here" end
		if terrain[idx] ~= "Grass" then return false, "Sell the current terrain first" end
	else
		if buildings[idx] then return false, "That tile is occupied" end
		if terrain[idx] == "Water" then return false, "You can't build on water" end
	end

	if def.Blocks then
		if enemyNearCell(idx) then return false, "An enemy is in the way" end
		-- Buildings can be broken, so only water has to leave a route open.
		if def.Kind == "Terrain" then
			if not pathExists(computeFlow("ground", idx)) then
				return false, "You can't completely block the path with water!"
			end
		end
	end

	addCoins(player, -def.Cost)
	local rec = createBuilding(player, def, i, j)   -- terrain too: it becomes real when construction finishes
	-- units are ready right away (no builder needed); the test console's instant build finishes everything
	if def.Kind == "Monster" or devInstantBuild then finishBuilding(rec) end
	refreshTile(idx)
	markDirty()
	return true
end

local function trySell(player, i, j)
	if phase == "GameOver" then return false end
	if not inBounds(i, j) then return false end
	local idx = toIdx(i, j)
	local rec = buildings[idx]
	if rec then
		if rec.Owner ~= player.UserId then return false, "That's not yours" end
		if rec.Building then
			-- cancelling a construction gives everything back
			addCoins(player, rec.Def.Cost)
		else
			-- refund scales with remaining health for damaged buildings
			local frac = (rec.MaxHP > 0) and (rec.HP / rec.MaxHP) or 1
			addCoins(player, math.floor(rec.Def.Cost * Config.SellRefund * frac))
		end
		removeBuilding(rec)
		return true
	end
	if terrain[idx] ~= "Grass" then
		if terrainOwner[idx] ~= player.UserId then return false, "That's not yours" end
		if enemyNearCell(idx) then return false, "An enemy is standing there" end
		local def = Config.TerrainDefs[terrain[idx]]
		addCoins(player, math.floor(def.Cost * Config.SellRefund))
		terrain[idx] = "Grass"
		terrainOwner[idx] = nil
		refreshTile(idx)
		markDirty()
		return true
	end
	return false, "Nothing to sell here"
end

---------------------------------------------------------------- remote handlers
local lastAction = {}
local function rateOk(player)
	local now = os.clock()
	if lastAction[player] and now - lastAction[player] < 0.05 then return false end
	lastAction[player] = now
	return true
end

local function validCell(i, j)
	return typeof(i) == "number" and typeof(j) == "number" and i % 1 == 0 and j % 1 == 0
end

placeRemote.OnServerEvent:Connect(function(player, itemId, i, j)
	if typeof(itemId) ~= "string" or not validCell(i, j) or not rateOk(player) then return end
	local ok, msg = tryPlace(player, itemId, i, j)
	if not ok and msg then notify(player, msg) end
end)

sellRemote.OnServerEvent:Connect(function(player, i, j)
	if not validCell(i, j) or not rateOk(player) then return end
	local ok, msg = trySell(player, i, j)
	if not ok and msg then notify(player, msg) end
end)

---------------------------------------------------------------- unit movement
local function posToIdx(p)
	local i = math.clamp(math.floor(p.X / CELL + W / 2) + 1, 1, W)
	local j = math.clamp(math.floor(p.Z / CELL + H / 2) + 1, 1, H)
	return toIdx(i, j)
end

-- shortest walk for a unit: around water and solid buildings, over traps
local function unitPath(rec, start, dest)
	local function passable(idx)
		if terrain[idx] == "Water" then return false end
		local b = buildings[idx]
		if b and b ~= rec and b.Def.Blocks and b.Def.Kind ~= "Terrain" and not b.Moving then return false end
		return true
	end
	-- 8 directions: diagonal steps cost a bit more (1.41) so paths stay natural
	local DIRS8 = {
		{ 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
		{ 1, 1, 1.41 }, { 1, -1, 1.41 }, { -1, 1, 1.41 }, { -1, -1, 1.41 },
	}
	local prev = { [start] = false }
	local dist = { [start] = 0 }
	local done = {}
	local heap = {}
	heapPush(heap, 0, start)
	while #heap > 0 do
		local top = heapPop(heap)
		local d, cur = top[1], top[2]
		if not done[cur] then
			done[cur] = true
			if cur == dest then break end
			local ci, cj = fromIdx(cur)
			for _, dd in ipairs(DIRS8) do
				local ni, nj = ci + dd[1], cj + dd[2]
				if inBounds(ni, nj) then
					local n = toIdx(ni, nj)
					local ok = not done[n] and passable(n)
					-- don't cut corners past walls or water
					if ok and dd[1] ~= 0 and dd[2] ~= 0 then
						ok = passable(toIdx(ci + dd[1], cj)) and passable(toIdx(ci, cj + dd[2]))
					end
					if ok then
						local nd = d + dd[3]
						if nd < (dist[n] or math.huge) then
							dist[n] = nd
							prev[n] = cur
							heapPush(heap, nd, n)
						end
					end
				end
			end
		end
	end
	if prev[dest] == nil then return nil end
	local path, c = {}, dest
	while c do
		table.insert(path, 1, c)
		c = prev[c]
	end
	return path
end

-- send one unit to tile (i, j)
local function moveOne(player, rec, i, j)
	local dest = toIdx(i, j)
	if dest == rec.Idx and not rec.Moving then return end
	if cityIdx[dest] or spawnIdx[dest] or routeCells[dest] or terrain[dest] == "Water" or dest == portalIdx then
		notify(player, "Units can't stand there")
		return
	end
	local other = buildings[dest]
	if other and other ~= rec then notify(player, "That tile is taken") return end
	local path = unitPath(rec, posToIdx(rec.Pos), dest)
	if not path then notify(player, "Your unit can't find a way there") return end

	-- leave the old tile, reserve the new one (nothing can be built there while it walks)
	if buildings[rec.Idx] == rec then
		buildings[rec.Idx] = nil
		refreshTile(rec.Idx)
	end
	rec.Idx, rec.I, rec.J = dest, i, j
	buildings[dest] = rec
	refreshTile(dest)

	local wps = { rec.Pos }
	for k = 2, #path do
		local pi, pj = fromIdx(path[k])
		table.insert(wps, cellCenter(pi, pj))
	end
	if #wps == 1 then table.insert(wps, cellCenter(i, j)) end
	rec.Path, rec.Wp, rec.Moving = wps, 2, true
	markDirty()
end

-- move one or several of your units; a group spreads over the clicked tile and the free tiles around it
moveRemote.OnServerEvent:Connect(function(player, ids, i, j)
	if not validCell(i, j) or not rateOk(player) then return end
	if phase == "GameOver" or phase == "Victory" or not inBounds(i, j) then return end
	if typeof(ids) == "number" then ids = { ids } end
	if typeof(ids) ~= "table" then return end
	local units = {}
	for _, id in ipairs(ids) do
		local rec = (typeof(id) == "number") and recById[id] or nil
		if rec and not rec.Dead and rec.Owner == player.UserId and rec.Def.Kind == "Monster"
			and not rec.Building and not rec.EnterDungeon and not table.find(units, rec) then
			table.insert(units, rec)
		end
		if #units >= 40 then break end
	end
	if #units == 0 then return end
	if #units == 1 then
		moveOne(player, units[1], i, j)
		return
	end
	-- find a free tile for every unit, starting at the clicked tile and spreading outwards
	local function canStand(idx)
		if cityIdx[idx] or spawnIdx[idx] or routeCells[idx] or terrain[idx] == "Water" or idx == portalIdx then return false end
		return buildings[idx] == nil
	end
	local start = toIdx(i, j)
	local spots, seen = {}, { [start] = true }
	local queue, head = { start }, 1
	while head <= #queue and #spots < #units and head <= 300 do
		local cur = queue[head]
		head += 1
		if canStand(cur) then table.insert(spots, cur) end
		local ci, cj = fromIdx(cur)
		for _, d in ipairs(DIRS) do
			local ni, nj = ci + d[1], cj + d[2]
			if inBounds(ni, nj) then
				local n = toIdx(ni, nj)
				if not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	if #spots == 0 then notify(player, "Units can't stand there") return end
	-- each spot goes to the closest unit that doesn't have one yet
	local left = table.clone(units)
	for _, spot in ipairs(spots) do
		local si, sj = fromIdx(spot)
		local c = cellCenter(si, sj)
		local best, bd = 1, math.huge
		for k, rec in ipairs(left) do
			local d = flatDist(rec.Pos, c)
			if d < bd then best, bd = k, d end
		end
		local rec = table.remove(left, best)
		moveOne(player, rec, si, sj)
		if #left == 0 then break end
	end
end)

---------------------------------------------------------------- builders
-- Each player has builder workers. They walk from the city to construction sites and build them.
-- A few enemy hits kill one; you get one new builder after each cleared wave.
local function builderPassable(idx)
	if terrain[idx] == "Water" then return false end
	return solidAt(idx) == nil
end

-- shortest walk from start to any tile in goals
local function builderPath(start, goals)
	if goals[start] then return { start } end
	-- 8 directions: diagonal steps cost 1.41, and never cut the corner of a wall or water
	local DIRS8 = {
		{ 1, 0, 1 }, { -1, 0, 1 }, { 0, 1, 1 }, { 0, -1, 1 },
		{ 1, 1, 1.41 }, { 1, -1, 1.41 }, { -1, 1, 1.41 }, { -1, -1, 1.41 },
	}
	local prev = { [start] = false }
	local dist = { [start] = 0 }
	local done = {}
	local heap = {}
	heapPush(heap, 0, start)
	local found
	while #heap > 0 do
		local top = heapPop(heap)
		local d, cur = top[1], top[2]
		if not done[cur] then
			done[cur] = true
			if goals[cur] then found = cur break end
			local ci, cj = fromIdx(cur)
			for _, dd in ipairs(DIRS8) do
				local ni, nj = ci + dd[1], cj + dd[2]
				if inBounds(ni, nj) then
					local n = toIdx(ni, nj)
					local ok = not done[n] and builderPassable(n)
					if ok and dd[1] ~= 0 and dd[2] ~= 0 then
						ok = builderPassable(toIdx(ci + dd[1], cj)) and builderPassable(toIdx(ci, cj + dd[2]))
					end
					if ok then
						local nd = d + dd[3]
						if nd < (dist[n] or math.huge) then
							dist[n] = nd
							prev[n] = cur
							heapPush(heap, nd, n)
						end
					end
				end
			end
		end
	end
	if not found then return nil end
	local path, c = {}, found
	while c do
		table.insert(path, 1, c)
		c = prev[c]
	end
	return path
end

-- start walking towards goals (job = the construction site, or nil when going home)
local function sendBuilder(b, goals, job)
	local path = builderPath(posToIdx(b.Pos), goals)
	if not path then return false end
	local wps = { b.Pos }
	for k = 2, #path do
		local pi, pj = fromIdx(path[k])
		table.insert(wps, cellCenter(pi, pj))
	end
	if #path == 1 then
		local pi, pj = fromIdx(path[1])
		table.insert(wps, cellCenter(pi, pj))
	end
	b.Path, b.Wp, b.Goals, b.Job, b.Working = wps, 2, goals, job, false
	return true
end

local function homeCell(n)
	local c = Config.City
	local width = c.MaxI - c.MinI + 1
	return toIdx(c.MinI + ((n - 1) % width), c.MaxJ)   -- back row of the city, away from the gate
end

local function spawnBuilder(player)
	local uid = player.UserId
	builders[uid] = builders[uid] or {}
	nextBuilderId += 1
	local home = homeCell(nextBuilderId)
	local hi, hj = fromIdx(home)
	local model, bar = Models.Builder()
	model.Name = "Builder_" .. player.Name
	model:SetAttribute("Owner", uid)
	local b = {
		Id = nextBuilderId, Owner = uid, Pos = cellCenter(hi, hj), Face = Vector3.new(0, 0, -1),
		HP = Config.BuilderHits, Model = model, Bar = bar, Home = home, Dead = false, Bob = 0,
	}
	model:PivotTo(CFrame.new(b.Pos + Vector3.new(0, 0.6, 0)))
	model.Parent = buildersFolder
	table.insert(builders[uid], b)
	return b
end

local function clearBuilders(uid)
	for _, b in ipairs(builders[uid] or {}) do
		b.Dead = true
		if b.Job then b.Job.Builder = nil end
		if b.Model then b.Model:Destroy() end
	end
	builders[uid] = nil
end

local function hitBuilder(b)
	if not b or b.Dead then return end
	b.HP -= 1
	Models.SetBar(b.Bar, b.HP / Config.BuilderHits)
	Models.Boom(b.Pos + Vector3.new(0, 1.5, 0), 1, Color3.fromRGB(255, 120, 90))
	if b.HP > 0 then return end
	b.Dead = true
	Models.Boom(b.Pos + Vector3.new(0, 1.5, 0), 2.2, Color3.fromRGB(255, 70, 60))
	if b.Model then b.Model:Destroy() end
	if b.Job then
		b.Job.Builder = nil
		b.Job = nil
	end
	local list = builders[b.Owner]
	if list then
		local k = table.find(list, b)
		if k then table.remove(list, k) end
	end
	local p = Players:GetPlayerByUserId(b.Owner)
	if p then
		local left = aliveBuilders(b.Owner)
		p:SetAttribute("BuildersAlive", left)
		if left > 0 then
			notify(p, "A builder was killed! " .. left .. " left.")
		else
			notify(p, "All your builders are dead! No building until the next wave.")
		end
	end
end

-- nearest builder (of any player) an enemy can hit right now
local function builderInReach(e)
	if e.Def.Flying or (e.Def.AtkDamage or 0) <= 0 then return nil end
	local best, bd = nil, CELL * 1.5
	for _, list in pairs(builders) do
		for _, b in ipairs(list) do
			if not b.Dead then
				local d = flatDist(b.Pos, e.Pos)
				if d < bd then best, bd = b, d end
			end
		end
	end
	return best
end

-- builders caught in an explosion take one hit
local function hitBuildersInRadius(pos, radius)
	local victims = {}
	for _, list in pairs(builders) do
		for _, b in ipairs(list) do
			if not b.Dead and flatDist(b.Pos, pos) <= radius then table.insert(victims, b) end
		end
	end
	for _, b in ipairs(victims) do hitBuilder(b) end
end

local function readyNeeded()
	return math.max(1, math.ceil(#Players:GetPlayers() / 2))
end
local function readyCount()
	local c = 0
	for uid in pairs(ready) do
		if Players:GetPlayerByUserId(uid) then c += 1 end
	end
	return c
end
local function updateReady()
	workspace:SetAttribute("ReadyCount", readyCount())
	workspace:SetAttribute("ReadyNeed", readyNeeded())
end

readyRemote.OnServerEvent:Connect(function(player)
	if phase ~= "Build" then return end
	ready[player.UserId] = (not ready[player.UserId]) or nil
	updateReady()
end)

---------------------------------------------------------------- players
local function setupPlayer(p)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	local c = Instance.new("IntValue")
	c.Name = "Coins"
	c.Value = Config.StartCoins + math.max(0, (workspace:GetAttribute("Wave") or 1) - 1) * Config.WaveBonus
	c.Parent = ls
	local cr = Instance.new("IntValue")
	cr.Name = "Crystals"
	cr.Value = 0
	cr.Parent = ls
	ls.Parent = p
	-- the test console is only for Studio and the game's owner
	p:SetAttribute("IsDev", RunService:IsStudio() or p.UserId == game.CreatorId)
	updateReady()
	-- players joining a running game get their builders right away
	if buildersFolder then
		for _ = 1, Config.Builders do spawnBuilder(p) end
	end
end
Players.PlayerAdded:Connect(setupPlayer)
for _, p in ipairs(Players:GetPlayers()) do setupPlayer(p) end
Players.PlayerRemoving:Connect(function(p)
	ready[p.UserId] = nil
	lastAction[p] = nil
	clearBuilders(p.UserId)
	Dungeon.removePlayer(p.UserId)
	task.defer(updateReady)
end)

---------------------------------------------------------------- simulation
---------------------------------------------------------------- trade route
local function setTradeAttrs()
	local tr = trade.Truck
	workspace:SetAttribute("TradeActive", trade.Active)
	workspace:SetAttribute("TradeMoving", trade.Moving)
	workspace:SetAttribute("TradeHP", tr and math.max(0, math.floor(tr.HP)) or 0)
	workspace:SetAttribute("TradeMax", tr and math.floor(tr.MaxHP) or 0)
	workspace:SetAttribute("TradeRisk", tr and tr.Risk or 0)
end

local function clearRoute()
	for idx in pairs(routeCells) do
		routeCells[idx] = nil
		refreshTile(idx)
	end
	if trade.Sign then
		trade.Sign:Destroy()
		trade.Sign = nil
	end
end

local function finishTrade()
	trade.Active = false
	trade.Moving = false
	if trade.Truck and trade.Truck.Model then trade.Truck.Model:Destroy() end
	trade.Truck = nil
	clearRoute()
	setTradeAttrs()
end

local function findRouteSimple()
	local function free(idx)
		return not spawnIdx[idx] and not buildings[idx] and terrain[idx] ~= "Water"
	end
	local sides = (math.random(2) == 1) and { 1, W } or { W, 1 }
	local rows = {}
	for j = 4, 20 do table.insert(rows, j) end
	for k = #rows, 2, -1 do
		local r = math.random(k)
		rows[k], rows[r] = rows[r], rows[k]
	end
	for _, side in ipairs(sides) do
		for _, j in ipairs(rows) do
			local start = toIdx(side, j)
			if free(start) then
				local prev = { [start] = false }
				local queue, head, goal = { start }, 1, nil
				while head <= #queue and not goal do
					local cur = queue[head]
					head += 1
					local ci, cj = fromIdx(cur)
					local dirs = { DIRS[1], DIRS[2], DIRS[3], DIRS[4] }
					for k = 4, 2, -1 do
						local r = math.random(k)
						dirs[k], dirs[r] = dirs[r], dirs[k]
					end
					for _, d in ipairs(dirs) do
						local ni, nj = ci + d[1], cj + d[2]
						if inBounds(ni, nj) then
							local n = toIdx(ni, nj)
							if prev[n] == nil then
								if cityIdx[n] then
									prev[n] = cur
									goal = n
									break
								elseif free(n) then
									prev[n] = cur
									table.insert(queue, n)
								end
							end
						end
					end
				end
				if goal then
					local path, cur = {}, goal
					while cur do
						table.insert(path, 1, cur)
						cur = prev[cur]
					end
					return path
				end
			end
		end
	end
	return nil
end

-- How dangerous is each tile? Traces the routes enemies will take from every gate and marks the
-- tiles around them; tiles inside tower/guard range count as safer. Returns idx -> 0..1
local function computeRisk()
	if flowsDirty then refreshFlows() end
	local heat = table.create(N, 0)

	local function trace(mode, weight)
		local field = flows[mode]
		for _, sIdx in ipairs(spawnList) do
			local cur, steps = sIdx, 0
			while not cityIdx[cur] and steps < N do
				steps += 1
				local ci, cj = fromIdx(cur)
				for di = -2, 2 do
					for dj = -2, 2 do
						local dd = math.abs(di) + math.abs(dj)
						local ni, nj = ci + di, cj + dj
						if dd <= 2 and inBounds(ni, nj) then
							local w = weight * ((dd == 0) and 1 or ((dd == 1) and 0.6 or 0.3))
							local n = toIdx(ni, nj)
							if w > heat[n] then heat[n] = w end
						end
					end
				end
				local best, bv = nil, math.huge
				for _, d in ipairs(DIRS) do
					local ni, nj = ci + d[1], cj + d[2]
					if inBounds(ni, nj) then
						local n = toIdx(ni, nj)
						if not isBlocked(n, mode) then
							local v = field[n] + enterCost(n, mode)
							if v < bv then bv = v; best = n end
						end
					end
				end
				if not best then break end
				cur = best
			end
		end
	end
	trace("ground", 1.0)
	trace("climb", 0.6)
	trace("fly", 0.6)

	-- defended ground is safer
	local safe = table.create(N, 0)
	for rec in pairs(buildingList) do
		local def = rec.Def
		if def.Kind == "Tower" or def.Kind == "Monster" then
			local r = def.Range * CELL
			for idx = 1, N do
				local i, j = fromIdx(idx)
				if flatDist(cellCenter(i, j), rec.Pos) <= r then
					safe[idx] = math.min(1, safe[idx] + 0.35)
				end
			end
		end
	end
	for idx = 1, N do
		heat[idx] = heat[idx] * (1 - 0.7 * safe[idx])
	end
	return heat
end

-- cheapest road from start to the city where risky tiles are cheaper than quiet ones
local function weightedRoute(start, heat, free)
	local dist = table.create(N, math.huge)
	local prev, done, heap = {}, {}, {}
	dist[start] = 0
	heapPush(heap, 0, start)
	while #heap > 0 do
		local top = heapPop(heap)
		local d, cur = top[1], top[2]
		if not done[cur] then
			done[cur] = true
			if cityIdx[cur] then
				local path, c = {}, cur
				while c do
					table.insert(path, 1, c)
					c = prev[c]
				end
				return path
			end
			local ci, cj = fromIdx(cur)
			for _, dd in ipairs(DIRS) do
				local ni, nj = ci + dd[1], cj + dd[2]
				if inBounds(ni, nj) then
					local n = toIdx(ni, nj)
					if not done[n] and (cityIdx[n] or free(n)) then
						local nd = d + 1 + 3 * (1 - heat[n])
						if nd < dist[n] then
							dist[n] = nd
							prev[n] = cur
							heapPush(heap, nd, n)
						end
					end
				end
			end
		end
	end
	return nil
end

-- Risk-aware route: tries every free start on the side edges, keeps the most dangerous roads and
-- picks one of the top three. Returns path, averageRisk (0..1)
local function findRoute()
	local heat = computeRisk()
	-- keep the road a few tiles clear of the spawn gates so the truck isn't born into a crowd
	local function nearGate(idx)
		local i, j = fromIdx(idx)
		for _, s in ipairs(Config.Spawns) do
			if math.abs(i - s[1]) + math.abs(j - s[2]) <= 2 then return true end
		end
		return false
	end
	local function free(idx)
		return not spawnIdx[idx] and not buildings[idx] and terrain[idx] ~= "Water" and not nearGate(idx) and idx ~= portalIdx
	end
	local candidates = {}
	for _, side in ipairs({ 1, W }) do
		for j = 3, 16 do
			local start = toIdx(side, j)
			if free(start) then
				local path = weightedRoute(start, heat, free)
				if path and #path >= 2 then
					local sum = 0
					for k = 1, #path - 1 do sum += heat[path[k]] end
					table.insert(candidates, { path = path, risk = sum / (#path - 1) })
				end
			end
		end
	end
	if #candidates == 0 then
		return findRouteSimple(), 0
	end
	table.sort(candidates, function(a, b) return a.risk > b.risk end)
	local pick = candidates[math.random(math.min(3, #candidates))]
	return pick.path, pick.risk
end

-- Opens a trade route and parks the truck at its start. Returns false if there's no room.
local function startTrade(wave)
	local path, risk = findRoute()
	if not path then return false end
	local wps = {}
	for k, idx in ipairs(path) do
		local i, j = fromIdx(idx)
		table.insert(wps, cellCenter(i, j))
		if k < #path then   -- the last cell is the city itself
			routeCells[idx] = true
			refreshTile(idx)
		end
	end

	local hp = Config.Trade.Hits
	local model, bar = Models.Truck()
	model.Parent = mapFolder
	local face = (wps[2] - wps[1]) * Vector3.new(1, 0, 1)
	face = (face.Magnitude > 0.01) and face.Unit or Vector3.new(0, 0, 1)
	model:PivotTo(CFrame.lookAt(wps[1], wps[1] + face))

	trade.Truck = { Model = model, Bar = bar, HP = hp, MaxHP = hp, Pos = wps[1], Wps = wps, Wp = 2, Face = face, Dead = false, Wave = wave, Risk = risk or 0 }
	trade.Sign = Models.RouteSign(wps[1] + Vector3.new(0, 0, 0))
	trade.Sign.Parent = mapFolder
	trade.Active = true
	trade.Moving = false
	setTradeAttrs()
	return true
end

local function damageTruck(amount)
	local tr = trade.Truck
	if not tr or tr.Dead then return end
	tr.HP -= amount
	Models.SetBar(tr.Bar, tr.HP / tr.MaxHP)
	if tr.HP <= 0 then
		tr.Dead = true
		Models.Boom(tr.Pos + Vector3.new(0, 2, 0), 6, Color3.fromRGB(255, 120, 30))
		Models.Popup(tr.Pos + Vector3.new(0, 6, 0), "Truck destroyed!", Color3.fromRGB(255, 90, 90))
		for _, p in ipairs(Players:GetPlayers()) do
			notify(p, "The trade truck was destroyed! No payout.")
		end
		finishTrade()
	else
		setTradeAttrs()
	end
end

-- can this enemy hit the truck right now? (flyers can't)
local function truckInReach(e)
	local tr = trade.Truck
	if not tr or tr.Dead or e.Def.Flying or (e.Def.AtkDamage or 0) <= 0 then return false end
	return flatDist(tr.Pos, e.Pos) < CELL * 1.6
end

local function updateTruck(dt)
	local tr = trade.Truck
	if not tr or tr.Dead or not trade.Moving then return end
	local target = tr.Wps[tr.Wp]
	local dir = Vector3.new(target.X - tr.Pos.X, 0, target.Z - tr.Pos.Z)
	local d = dir.Magnitude
	local step = Config.Trade.Speed * dt
	if d <= step then
		tr.Pos = Vector3.new(target.X, TOP, target.Z)
		tr.Wp += 1
		if tr.Wp > #tr.Wps then
			-- arrived at the city: pay everyone
			local frac = math.clamp(tr.HP / tr.MaxHP, 0, 1)
			local base = Config.Trade.BaseReward + Config.Trade.RewardPerWave * tr.Wave
			local amount = math.floor(base * (Config.Trade.MinPayout + (1 - Config.Trade.MinPayout) * frac) * (1 + Config.Trade.RiskBonus * (tr.Risk or 0)))
			for _, p in ipairs(Players:GetPlayers()) do
				addCoins(p, amount)
				notify(p, "Trade truck delivered! +" .. amount .. " coins")
			end
			Models.Popup(tr.Pos + Vector3.new(0, 7, 0), "+$" .. amount, Color3.fromRGB(255, 225, 90))
			finishTrade()
			return
		end
	else
		tr.Face = dir.Unit
		tr.Pos += dir.Unit * step
	end
	local bob = math.sin(os.clock() * 8) * 0.06
	local p = tr.Pos + Vector3.new(0, bob, 0)
	tr.Model:PivotTo(CFrame.lookAt(p, p + tr.Face))
end

-- Bomber self-destruct: area damage to walls (full) and guards (half), falling off with distance
local function explode(e)
	local radius = e.Def.BlastRadius * CELL
	local centre = e.Pos + Vector3.new(0, 2, 0)
	Models.Boom(centre, radius, Color3.fromRGB(255, 120, 30))
	Models.Boom(centre, radius * 0.55, Color3.fromRGB(255, 230, 120))
	local victims = {}
	for rec in pairs(buildingList) do
		local k = rec.Def.Kind
		if k == "Wall" or k == "Monster" or k == "Tower" or k == "Trap" or k == "Farm" then
			local d = flatDist(rec.Pos, e.Pos)
			if d <= radius then table.insert(victims, { rec, d }) end
		end
	end
	for _, v in ipairs(victims) do
		local rec, d = v[1], v[2]
		local scale = ({ Wall = 1, Monster = 0.5, Tower = 0.6, Trap = 0.6, Farm = 0.6 })[rec.Def.Kind] or 1
		damageBuilding(rec, e.Def.BlastDamage * (1 - 0.5 * d / radius) * scale)
	end
	hitBuildersInRadius(e.Pos, radius)
	local truck = trade.Truck
	if truck and not truck.Dead then
		local td = flatDist(truck.Pos, e.Pos)
		if td <= radius then damageTruck(1) end
	end
	removeEnemy(e)
end

local function updateEnemies(dt)
	for _, e in pairs(enemies) do
		if not e.Dead and not (e.StunUntil and gameTime < e.StunUntil) then   -- stunned enemies stand still
			local ci, cj = fromIdx(e.Cell)
			local cc = cellCenter(ci, cj)
			local ti, tj = fromIdx(e.Target)
			local tp = cellCenter(ti, tj)
			local nearIdx = (flatDist(e.Pos, cc) < CELL / 2) and e.Cell or e.Target
			local nearB = buildings[nearIdx]
			local onWall = nearB ~= nil and nearB.Def.Kind == "Wall"
			local reachedCity = false
			local moving = false
			local slow = 1
			local inWater = terrain[nearIdx] == "Water"

			-- swimmers: each new water tile heals them and raises max HP; water gives a speed/attack boost
			local atkMul = mods.EnemyAtk
			local spdMul = 1
			if e.Mode == "swim" then
				local d = e.Def
				if inWater then
					if e.LastWater ~= nearIdx then
						e.LastWater = nearIdx
						e.MaxHP = math.min(e.BaseMaxHP * d.WaterHPCap, e.MaxHP + e.BaseMaxHP * d.WaterHPGain)
						e.HP = math.min(e.MaxHP, e.HP + e.MaxHP * d.WaterHeal)
						Models.SetBar(e.Bar, e.HP / e.MaxHP)
					end
					e.BuffUntil = gameTime + d.BuffTime
				else
					e.LastWater = nil
				end
				local buffed = e.BuffUntil ~= nil and gameTime < e.BuffUntil
				if buffed then
					spdMul = d.BuffSpeed
					atkMul *= d.BuffAttack
				end
				if e.Glow then e.Glow.Enabled = buffed end
			end

			if e.Breaking then
				-- standing in front of a wall, smashing it
				local rec = e.Breaking
				if rec.Dead or rec.Moving then
					pickNext(e)
				else
					local dv = Vector3.new(rec.Pos.X - e.Pos.X, 0, rec.Pos.Z - e.Pos.Z)
					if dv.Magnitude > 0.1 then e.Face = dv.Unit end
					if e.Def.Fuse then
						e.FuseT -= dt
						local bomb = e.Model:FindFirstChild("Bomb")
						if bomb then
							bomb.Color = (math.floor(e.FuseT * 8) % 2 == 0) and Color3.fromRGB(255, 40, 20) or Color3.fromRGB(20, 20, 20)
						end
						if e.FuseT <= 0 then explode(e) end
					end
					e.AtkCd -= dt
					if e.AtkCd <= 0 then
						e.AtkCd = e.Def.AtkInterval
						if truckInReach(e) then
							damageTruck(1)   -- the truck comes first
						elseif builderInReach(e) then
							hitBuilder(builderInReach(e))   -- then builders
						else
							Models.Boom(rec.Pos + Vector3.new(0, 2.5, 0), 1.2, Color3.fromRGB(190, 170, 130))
							damageBuilding(rec, (e.Def.BreakDamage or 5) * atkMul)
						end
					end
				end
			else
				if e.Mode ~= "fly" and terrain[nearIdx] == "Mud" then slow = Config.MudSlow end
				if e.Mode == "climb" and (onWall or inWater) then slow *= Config.ClimbSlow end
				slow *= spdMul

				local dir = Vector3.new(tp.X - e.Pos.X, 0, tp.Z - e.Pos.Z)
				local d = dir.Magnitude
				local step = e.Def.Speed * slow * mods.EnemySpeed * dt
				if d <= step then
					e.Pos = Vector3.new(tp.X, TOP, tp.Z)
					e.Cell = e.Target
					if cityIdx[e.Cell] then
						reachedCity = true
					else
						pickNext(e)
					end
				else
					e.Face = dir.Unit
					e.Pos += dir.Unit * step
					moving = true
				end
			end

			if reachedCity then
				hitCity(e)
			elseif not e.Dead then
				-- height: flyers hover, climbers rise onto walls
				local liftTarget = 0
				if e.Def.Flying then
					liftTarget = e.Def.FlyHeight
				elseif e.Mode == "climb" and onWall then
					liftTarget = Config.WallTopLift
				elseif e.Mode == "swim" and inWater then
					liftTarget = -0.9   -- half under water
				end
				e.Lift += math.clamp(liftTarget - e.Lift, -14 * dt, 14 * dt)

				-- animation
				local bob
				if e.Def.Flying then
					e.Bob += dt * 4
					bob = math.sin(e.Bob) * 0.5
				else
					if moving then e.Bob += dt * e.Def.Speed * slow * 1.4 end
					bob = moving and math.abs(math.sin(e.Bob)) * 0.4 or 0
				end
				local p = Vector3.new(e.Pos.X, TOP + e.Lift + bob, e.Pos.Z)
				e.Model:PivotTo(CFrame.lookAt(p, p + e.Face))

				-- attack: the trade truck first, otherwise nearby guards (flyers have no attack)
				if not e.Breaking and (e.Def.AtkDamage or 0) > 0 then
					e.AtkCd -= dt
					if e.AtkCd <= 0 then
						if truckInReach(e) then
							damageTruck(1)
							e.AtkCd = e.Def.AtkInterval
						elseif builderInReach(e) then
							hitBuilder(builderInReach(e))
							e.AtkCd = e.Def.AtkInterval
						else
							local target, td = nil, CELL * 1.5
							for rec in pairs(buildingList) do
								if rec.Def.Kind == "Monster" then
									local dd = flatDist(rec.Pos, e.Pos)
									if dd < td then target = rec; td = dd end
								end
							end
							if target then
								damageBuilding(target, e.Def.AtkDamage * atkMul)
								e.AtkCd = e.Def.AtkInterval
							end
						end
					end
				end
			end
		end
	end
end

local function updateBuildings(dt)
	for rec in pairs(buildingList) do
		local def = rec.Def
		if rec.Building then continue end   -- construction sites don't work yet
		local dmgMul = damageMul(rec)       -- crystal upgrades
		rec.Cd -= dt
		if def.Kind == "Tower" then
			local jammed = rec.JamUntil ~= nil and gameTime < rec.JamUntil
			if rec.Cd <= 0 and not jammed then
				local range = def.Range * CELL * mods.TowerRange * (hasBuff(rec.Owner, "Eagle") and 1.3 or 1)
				local target, bestFlow, bestDist = nil, math.huge, math.huge
				for _, e in pairs(enemies) do
					local d = flatDist(rec.Pos, e.Pos)
					if d <= range then
						local f = flows[e.Mode][e.Cell] or math.huge
						if f < bestFlow or (f == bestFlow and d < bestDist) then
							target = e; bestFlow = f; bestDist = d
						end
					end
				end
				if target then
					local tpos = target.Pos + Vector3.new(0, 2 * target.Def.Scale + target.Lift, 0)
					Models.Aim(rec.Model, tpos)
					local head = rec.Model:FindFirstChild("Head")
					local from = (head and head.Position or rec.Pos + Vector3.new(0, 5, 0))
					if def.Splash then
						Models.Beam(from, tpos, Color3.fromRGB(255, 150, 60), 0.6)
						Models.Boom(tpos, def.Splash * CELL / 2, Color3.fromRGB(255, 150, 50))
						local tp = target.Pos
						for _, e in pairs(enemies) do
							if e == target then
								damageEnemy(e, def.Damage * dmgMul, rec.Owner)
							elseif flatDist(e.Pos, tp) <= def.Splash * CELL then
								damageEnemy(e, def.Damage * 0.75 * dmgMul, rec.Owner)
							end
						end
					else
						Models.Beam(from, tpos, Color3.fromRGB(255, 240, 150), 0.2)
						damageEnemy(target, def.Damage * dmgMul, rec.Owner)
					end
					rec.Cd = def.Interval / mods.TowerRate
				end
			end

		elseif def.Kind == "Trap" then
			if rec.Cd <= 0 then
				local hit = false
				for _, e in pairs(enemies) do
					if not e.Def.Flying and flatDist(rec.Pos, e.Pos) <= CELL * 0.5 then
						damageEnemy(e, def.Damage * dmgMul, rec.Owner)
						hit = true
					end
				end
				rec.Cd = hit and def.Interval or 0
			end

		elseif def.Kind == "Monster" then
			if rec.Cd <= 0 and not rec.Dash then
				-- Goblin Guard's Long Spear: more range and damage for a while
				local longOn = rec.LongUntil ~= nil and gameTime < rec.LongUntil
				local LONG = Config.Abilities.Goblin.E
				local range = def.Range * CELL * (longOn and LONG.Range or 1)
				local target, td = nil, range
				for _, e in pairs(enemies) do
					if not e.Def.Flying then
						local d = flatDist(rec.Pos, e.Pos)
						if d <= td then target = e; td = d end
					end
				end
				if target then
					-- turn to face the target
					local fv = Vector3.new(target.Pos.X - rec.Pos.X, 0, target.Pos.Z - rec.Pos.Z)
					if fv.Magnitude > 0.05 then rec.Face = fv.Unit end
					local face = rec.Face or Vector3.new(0, 0, -1)
					if not rec.Moving and rec.PivotOffset then
						rec.Model:PivotTo(CFrame.lookAt(rec.Pos, rec.Pos + face) * rec.PivotOffset)
					end

					-- who gets hit
					local victims = {}
					local cosHalf = math.cos(math.rad((def.SweepAngle or 0) / 2))
					for _, e in pairs(enemies) do
						if not e.Dead and not e.Def.Flying then
							local v = Vector3.new(e.Pos.X - rec.Pos.X, 0, e.Pos.Z - rec.Pos.Z)
							if def.Attack == "Spear" then
								-- everything in a straight line in front
								local along = v:Dot(face)
								local side = (v - face * along).Magnitude
								if along >= -CELL * 0.3 and along <= range and side <= def.SpearWidth * CELL then
									table.insert(victims, e)
								end
							elseif def.Attack == "Sweep" then
								-- everything inside the arc in front
								local d = v.Magnitude
								if d <= range and (d < CELL * 0.4 or v.Unit:Dot(face) >= cosHalf) then
									table.insert(victims, e)
								end
							end
						end
					end
					if #victims == 0 then table.insert(victims, target) end

					-- effects
					if def.Attack == "Spear" then
						Models.Thrust(rec.Pos + Vector3.new(0, 2.2, 0), face, range)
					elseif def.Attack == "Sweep" then
						Models.Sweep(rec.Pos + Vector3.new(0, 2.5, 0), face, range, def.SweepAngle, Color3.fromRGB(255, 190, 110))
					else
						Models.Beam(rec.Pos + Vector3.new(0, 2, 0), target.Pos + Vector3.new(0, 2 + target.Lift, 0), Color3.fromRGB(255, 90, 90), 0.4)
					end
					for _, e in ipairs(victims) do damageEnemy(e, def.Damage * dmgMul * (longOn and LONG.Damage or 1), rec.Owner) end
					rec.Cd = def.Interval
				end
			end
		end
	end
end

---------------------------------------------------------------- construction
-- returns true when the site is done (or was cancelled)
function finishBuilding(rec)
	if rec.Def.Kind == "Terrain" then
		local idx = rec.Idx
		if rec.Def.TerrainType == "Water" then
			if enemyNearCell(idx) then return false end   -- wait until nobody is standing there
			if not pathExists(computeFlow("ground", idx)) then
				local p = Players:GetPlayerByUserId(rec.Owner)
				if p then
					addCoins(p, rec.Def.Cost)
					notify(p, "Water cancelled: it would completely block the path. Refunded.")
				end
				removeBuilding(rec)
				return true
			end
		end
		rec.Dead = true
		buildings[idx] = nil
		buildingList[rec] = nil
		recById[rec.Id] = nil
		rec.Model:Destroy()
		terrain[idx] = rec.Def.TerrainType
		terrainOwner[idx] = rec.Owner
		refreshTile(idx)
		markDirty()
		return true
	end
	rec.Building = false
	rec.HP = rec.MaxHP
	for part, t in pairs(rec.Ghost) do
		if part.Parent then part.Transparency = t end
	end
	for _, fx in ipairs(rec.Effects) do fx.Enabled = true end
	local g = rec.Model:FindFirstChild("BuildGui")
	if g then g:Destroy() end
	rec.Model:SetAttribute("Building", false)
	if rec.Bar then Models.SetBar(rec.Bar, 1) end
	Models.Boom(rec.Pos + Vector3.new(0, 2, 0), 2.5, Color3.fromRGB(120, 200, 255))
	return true
end

-- where a builder can stand to work on a site: on it (traps, terrain) or right next to it
local function goalsForSite(rec)
	local goals = {}
	if not (rec.Def.Blocks and rec.Def.Kind ~= "Terrain") then goals[rec.Idx] = true end
	local i, j = fromIdx(rec.Idx)
	for _, d in ipairs(DIRS) do
		local ni, nj = i + d[1], j + d[2]
		if inBounds(ni, nj) then
			local n = toIdx(ni, nj)
			if builderPassable(n) then goals[n] = true end
		end
	end
	return goals
end

-- hands out construction jobs to idle builders and updates the site labels (5x per second)
local buildGuiTimer = 0
local function updateConstruction(dt)
	buildGuiTimer += dt
	if buildGuiTimer < 0.2 then return end
	buildGuiTimer = 0
	for _, p in ipairs(Players:GetPlayers()) do
		local uid = p.UserId
		local list = buildJobs[uid] or {}
		local blist = builders[uid] or {}
		local alive = aliveBuilders(uid)
		local k = 1
		while k <= #list do
			if list[k].Dead or not list[k].Building then table.remove(list, k) else k += 1 end
		end
		local working, waiting = 0, 0
		for _, rec in ipairs(list) do
			if rec.Builder and (rec.Builder.Dead or rec.Builder.Job ~= rec) then rec.Builder = nil end
			if not rec.Builder then
				local best, bd = nil, math.huge
				for _, b in ipairs(blist) do
					if not b.Dead and not b.Job then
						local d = flatDist(b.Pos, rec.Pos)
						if d < bd then best, bd = b, d end
					end
				end
				if best then
					if sendBuilder(best, goalsForSite(rec), rec) then
						rec.Builder = best
						rec.Unreachable = nil
					else
						rec.Unreachable = true
					end
				end
			end
			local f = rec.BuildT / rec.BuildTime
			rec.BuildFill.Size = UDim2.fromScale(f, 1)
			if rec.Builder then
				working += 1
				if rec.Builder.Working then
					rec.BuildLabel.Text = ((rec.Def.Kind == "Monster") and "Training " or "Building ") .. math.floor(f * 100) .. "%"
				else
					rec.BuildLabel.Text = "Builder coming"
				end
			else
				waiting += 1
				if alive == 0 then
					rec.BuildLabel.Text = "No builders!"
				elseif rec.Unreachable then
					rec.BuildLabel.Text = "Can't reach!"
				else
					rec.BuildLabel.Text = "Waiting #" .. waiting
				end
			end
			if rec.Bar and rec.MaxHP > 0 then Models.SetBar(rec.Bar, rec.HP / rec.MaxHP) end
		end
		p:SetAttribute("BuildersAlive", alive)
		p:SetAttribute("Building", working)
		p:SetAttribute("Queued", waiting)
	end
end

-- builders walking, building, and heading home when there's nothing to do
local function updateBuilders(dt)
	for _, list in pairs(builders) do
		for _, b in ipairs(list) do
			if b.Dead then continue end
			local job = b.Job
			if job and (job.Dead or not job.Building) then
				b.Job, job, b.Path, b.Working = nil, nil, nil, false
			end
			if not job and not b.Path then
				b.Working = false
				if posToIdx(b.Pos) ~= b.Home then
					b.RetryT = (b.RetryT or 0) - dt
					if b.RetryT <= 0 and not sendBuilder(b, { [b.Home] = true }, nil) then b.RetryT = 1 end
				end
			end

			local moving = false
			if b.Path then
				local target = b.Path[b.Wp]
				local dir = Vector3.new(target.X - b.Pos.X, 0, target.Z - b.Pos.Z)
				local d = dir.Magnitude
				local step = Config.BuilderSpeed * dt * (hasBuff(b.Owner, "Hands") and 1.5 or 1)
				if d <= step then
					b.Pos = Vector3.new(target.X, TOP, target.Z)
					b.Wp += 1
					if b.Wp > #b.Path then
						b.Path = nil
						if b.Job then b.Working = true end
					else
						-- something got built in the way: find a new route
						local nextIdx = posToIdx(b.Path[b.Wp])
						if not builderPassable(nextIdx) and not (b.Goals and b.Goals[nextIdx]) then
							if not sendBuilder(b, b.Goals, b.Job) then
								b.Path = nil
								if b.Job then b.Job.Builder = nil end
								b.Job = nil
							end
						end
					end
				else
					b.Face = dir.Unit
					b.Pos += dir.Unit * step
					moving = true
				end
			end

			local bob = 0
			job = b.Job
			if b.Working and job then
				local bt = dt * (hasBuff(b.Owner, "Hands") and 2 or 1)   -- Quick Hands buff builds twice as fast
				job.BuildT = math.min(job.BuildTime, job.BuildT + bt)
				if job.MaxHP > 0 then
					job.HP = math.min(job.MaxHP, job.HP + job.MaxHP * 0.7 * bt / job.BuildTime)
				end
				local fd = Vector3.new(job.Pos.X - b.Pos.X, 0, job.Pos.Z - b.Pos.Z)
				if fd.Magnitude > 0.1 then b.Face = fd.Unit end
				b.Bob += dt * 10
				bob = math.abs(math.sin(b.Bob)) * 0.35
				b.SparkT = (b.SparkT or 0) - dt
				if b.SparkT <= 0 then
					b.SparkT = 0.6
					Models.Boom(job.Pos + Vector3.new(0, 1.5, 0), 0.8, Color3.fromRGB(255, 220, 120))
				end
				if job.BuildT >= job.BuildTime and finishBuilding(job) then
					b.Job, b.Working = nil, false
				end
			elseif moving then
				b.Bob += dt * 14
				bob = math.abs(math.sin(b.Bob)) * 0.25
			end
			local lift = cityIdx[posToIdx(b.Pos)] and 0.6 or 0   -- stand on the city floor
			local p = b.Pos + Vector3.new(0, lift + bob, 0)
			b.Model:PivotTo(CFrame.lookAt(p, p + b.Face))
		end
	end
end

---------------------------------------------------------------- dungeon portal
local function openPortal()
	if portalOpen then return end
	portalOpen = true
	portalModel = Models.DungeonPortal(cellCenter(Config.Portal[1], Config.Portal[2]))
	portalModel.Parent = mapFolder
	workspace:SetAttribute("PortalOpen", true)
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, "A DUNGEON PORTAL opened next to the city! Send units in for loot, crystals and a weaker next wave.")
	end
end

local function closePortal()
	portalOpen = false
	if portalModel then portalModel:Destroy() end
	portalModel = nil
	workspace:SetAttribute("PortalOpen", false)
end

-- a unit reached the portal: it leaves the base and appears in its owner's dungeon
local function enterDungeon(rec)
	local p = Players:GetPlayerByUserId(rec.Owner)
	rec.Dead = true
	buildingList[rec] = nil
	recById[rec.Id] = nil
	if buildings[rec.Idx] == rec then
		buildings[rec.Idx] = nil
		refreshTile(rec.Idx)
	end
	Models.Boom(rec.Pos + Vector3.new(0, 2, 0), 2.5, Color3.fromRGB(90, 220, 255))
	if rec.Model then rec.Model:Destroy() end
	if p then Dungeon.addUnit(p, rec.Def, math.max(1, rec.HP), rec.MaxHP) end
end

-- units walking to where their owner sent them
---------------------------------------------------------------- unit abilities (Q / E / R)
local function stunEnemy(e, t)
	if e.Dead then return end
	e.StunUntil = gameTime + t
	Models.StatusMark(e.Model, "StunMark", "STUNNED", Color3.fromRGB(255, 230, 90), t / gameSpeed)
end

-- shove an enemy (it stays on the map and out of water/the city), then it finds its way again
local function knockEnemy(e, push)
	if e.Dead then return end
	local np = e.Pos + push
	np = Vector3.new(math.clamp(np.X, -W * CELL / 2 + 1, W * CELL / 2 - 1), e.Pos.Y, math.clamp(np.Z, -H * CELL / 2 + 1, H * CELL / 2 - 1))
	local idx = posToIdx(np)
	if cityIdx[idx] or (not e.Def.Flying and isBlocked(idx, e.Mode)) then return end
	e.Pos = np
	e.Cell, e.Target, e.Breaking = idx, idx, nil
end

local function addAura(rec, name, color, duration)
	local old = rec.Model:FindFirstChild(name)
	if old then old:Destroy() end
	local h = Instance.new("Highlight")
	h.Name = name
	h.FillColor = color
	h.OutlineColor = color
	h.FillTransparency = 0.65
	h.Parent = rec.Model
	task.delay(duration, function() if h.Parent then h:Destroy() end end)
end

local function startCooldown(rec, key, cd)
	rec.Ready = rec.Ready or {}
	rec.Ready[key] = gameTime + cd
	rec.Model:SetAttribute("Ready_" .. key, workspace:GetServerTimeNow() + cd / gameSpeed)
end

-- can a dashing unit pass this tile?
local function dashPassable(rec, idx)
	if terrain[idx] == "Water" or cityIdx[idx] then return false end
	local b = buildings[idx]
	return not (b and b ~= rec and b.Def.Blocks and b.Def.Kind ~= "Terrain" and not b.Moving)
end

-- after a slide/charge: claim the nearest free tile and step onto it
local function landUnit(rec)
	rec.Dash = nil
	local start = posToIdx(rec.Pos)
	local seen = { [start] = true }
	local queue, head = { start }, 1
	local spot
	while head <= #queue do
		local cur = queue[head]
		head += 1
		local b = buildings[cur]
		if (not b or b == rec) and terrain[cur] ~= "Water" and not cityIdx[cur] and not spawnIdx[cur] and not routeCells[cur] and cur ~= portalIdx then
			spot = cur
			break
		end
		local ci, cj = fromIdx(cur)
		for _, d in ipairs(DIRS) do
			local ni, nj = ci + d[1], cj + d[2]
			if inBounds(ni, nj) then
				local n = toIdx(ni, nj)
				if not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	spot = spot or start
	rec.Idx = spot
	rec.I, rec.J = fromIdx(spot)
	buildings[spot] = rec
	refreshTile(spot)
	rec.Path, rec.Wp, rec.Moving = { rec.Pos, cellCenter(rec.I, rec.J) }, 2, true
	markDirty()
end

local function updateDash(rec, dt)
	local dash = rec.Dash
	local ab = dash.Ab
	local step = math.min(dash.Left, dash.Speed * dt)
	local np = rec.Pos + dash.Dir * step
	local inside = math.abs(np.X) < W * CELL / 2 - 0.5 and math.abs(np.Z) < H * CELL / 2 - 0.5
	if step <= 0 or not inside or not dashPassable(rec, posToIdx(np)) then
		landUnit(rec)
		return
	end
	rec.Pos = np
	dash.Left -= step
	if dash.Kind == "Slide" then
		-- Ogre: spins like a top and keeps hitting everything around him
		dash.Tick -= dt
		if dash.Tick <= 0 then
			dash.Tick = 0.3
			local r = 1.6 * CELL
			Models.Sweep(rec.Pos + Vector3.new(0, 2.5, 0), dash.Dir, r, 360, Color3.fromRGB(180, 230, 255))
			for _, e in pairs(enemies) do
				if not e.Dead and not e.Def.Flying and flatDist(e.Pos, rec.Pos) <= r then
					damageEnemy(e, rec.Def.Damage * ab.Damage * dash.DmgMul, rec.Owner)
				end
			end
		end
		dash.Spin += dt * 18
		rec.Face = CFrame.Angles(0, dash.Spin, 0):VectorToWorldSpace(Vector3.new(0, 0, -1))
	else
		-- Guard: charges, hitting each enemy in the way once and shoving it aside
		local r = 1.3 * CELL
		for _, e in pairs(enemies) do
			if not e.Dead and not dash.Hit[e] and flatDist(e.Pos, rec.Pos) <= r then
				dash.Hit[e] = true
				damageEnemy(e, rec.Def.Damage * ab.Damage * dash.DmgMul, rec.Owner)
				if not e.Dead then
					local away = Vector3.new(e.Pos.X - rec.Pos.X, 0, e.Pos.Z - rec.Pos.Z)
					local side = (away.Magnitude > 0.1) and away.Unit or Vector3.new(-dash.Dir.Z, 0, dash.Dir.X)
					knockEnemy(e, (side + dash.Dir).Unit * ab.Push)
				end
				Models.Boom(e.Pos + Vector3.new(0, 2, 0), 1.5, Color3.fromRGB(255, 200, 120))
			end
		end
		rec.Face = dash.Dir
	end
	local p = rec.Pos
	rec.Model:PivotTo(CFrame.lookAt(p, p + rec.Face) * rec.PivotOffset)
	if dash.Left <= 0 then landUnit(rec) end
end

local function useAbilityBase(player, key, ids, tx, tz)
	local target = (typeof(tx) == "number" and typeof(tz) == "number") and Vector3.new(tx, TOP, tz) or nil
	for _, id in ipairs(ids) do
		local rec = (typeof(id) == "number") and recById[id] or nil
		if rec and not rec.Dead and rec.Owner == player.UserId and rec.Def.Kind == "Monster" and not rec.Building and not rec.EnterDungeon and not rec.Dash then
			local kit = Config.Abilities[rec.Def.Id]
			local ab = kit and kit[key]
			if ab and (not rec.Ready or (rec.Ready[key] or 0) <= gameTime) then
				local dmgMul = damageMul(rec)
				if ab.Id == "Slide" or ab.Id == "Charge" then
					local dir = target and Vector3.new(target.X - rec.Pos.X, 0, target.Z - rec.Pos.Z) or (rec.Face or Vector3.new(0, 0, -1))
					if dir.Magnitude < 0.1 then dir = rec.Face or Vector3.new(0, 0, -1) end
					dir = dir.Unit
					-- leave the tile while dashing
					if buildings[rec.Idx] == rec then
						buildings[rec.Idx] = nil
						refreshTile(rec.Idx)
					end
					rec.Path, rec.Moving = nil, true
					rec.Dash = { Kind = ab.Id, Dir = dir, Left = ab.Distance * CELL, Speed = ab.Speed, Ab = ab, Tick = 0, Hit = {}, Spin = 0, DmgMul = dmgMul }
					rec.Face = dir
					if ab.Id == "Charge" then Models.StatusMark(rec.Model, "AbilityMark", "CHARGE!", Color3.fromRGB(255, 200, 120), 1) end
					markDirty()
				elseif ab.Id == "Slam" then
					local r = ab.Radius * CELL
					Models.Boom(rec.Pos + Vector3.new(0, 0.5, 0), r, Color3.fromRGB(210, 170, 110))
					Models.Boom(rec.Pos + Vector3.new(0, 1.5, 0), r * 0.6, Color3.fromRGB(255, 240, 160))
					for _, e in pairs(enemies) do
						if not e.Dead and not e.Def.Flying and flatDist(e.Pos, rec.Pos) <= r then
							damageEnemy(e, rec.Def.Damage * ab.Damage * dmgMul, rec.Owner)
							stunEnemy(e, ab.Stun)
						end
					end
				elseif ab.Id == "Heal" then
					rec.HP = rec.MaxHP
					if rec.Bar then Models.SetBar(rec.Bar, 1) end
					Models.Boom(rec.Pos + Vector3.new(0, 2.5, 0), 4, Color3.fromRGB(120, 255, 140))
					Models.Popup(rec.Pos + Vector3.new(0, 7, 0), "FULL HEAL", Color3.fromRGB(120, 255, 140))
				elseif ab.Id == "Shield" then
					rec.ShieldUntil = gameTime + ab.Duration
					addAura(rec, "ShieldAura", Color3.fromRGB(110, 190, 255), ab.Duration)
					Models.StatusMark(rec.Model, "AbilityMark", "SHIELD", Color3.fromRGB(140, 200, 255), ab.Duration / gameSpeed)
				elseif ab.Id == "Long" then
					rec.LongUntil = gameTime + ab.Duration
					addAura(rec, "LongAura", Color3.fromRGB(255, 180, 70), ab.Duration)
					Models.StatusMark(rec.Model, "AbilityMark", "LONG SPEAR", Color3.fromRGB(255, 190, 90), ab.Duration / gameSpeed)
				end
				startCooldown(rec, key, ab.Cooldown)
			end
		end
	end
end

local function updateUnits(dt)
	for rec in pairs(buildingList) do
		if rec.Dash and not rec.Dead then
			updateDash(rec, dt)
		elseif rec.Moving and not rec.Dead then
			local target = rec.Path[rec.Wp]
			local dir = Vector3.new(target.X - rec.Pos.X, 0, target.Z - rec.Pos.Z)
			local d = dir.Magnitude
			local step = (rec.Def.WalkSpeed or 6) * dt
			if d <= step then
				rec.Pos = Vector3.new(target.X, TOP, target.Z)
				rec.Wp += 1
				if rec.Wp > #rec.Path then
					rec.Moving = false
					rec.Path = nil
					markDirty()   -- it blocks its new tile now
					if rec.EnterDungeon then enterDungeon(rec) end
				end
			else
				rec.Face = dir.Unit
				rec.Pos += dir.Unit * step
			end
			rec.WalkBob = (rec.WalkBob or 0) + dt * 12
			local bob = rec.Moving and math.abs(math.sin(rec.WalkBob)) * 0.3 or 0
			local p = rec.Pos + Vector3.new(0, bob, 0)
			if not rec.Dead then rec.Model:PivotTo(CFrame.lookAt(p, p + rec.Face) * rec.PivotOffset) end
		end
	end
end

RunService.Heartbeat:Connect(function(dt)
	dt = math.min(dt, 0.1) * gameSpeed   -- everything below runs on game time
	gameTime += dt
	runTimers()
	if flowsDirty then refreshFlows() end
	updateConstruction(dt)
	updateBuilders(dt)
	updateUnits(dt)
	Dungeon.update(dt)
	updateEnemies(dt)
	updateTruck(dt)
	updateBuildings(dt)
end)

---------------------------------------------------------------- random events
local eventToken = 0      -- bumps on every reset; stale event timers check it and quit
local activeEvents = {}   -- what the HUD shows
local pendingEvents = 0   -- events/spawns still to come; the wave doesn't end while > 0
local lightingDefaults = {
	Ambient = Lighting.Ambient, OutdoorAmbient = Lighting.OutdoorAmbient, ColorShift_Top = Lighting.ColorShift_Top,
	FogStart = Lighting.FogStart, FogEnd = Lighting.FogEnd, FogColor = Lighting.FogColor,
}
local atmosphere = Lighting:FindFirstChildOfClass("Atmosphere")
local atmoDensity = atmosphere and atmosphere.Density or 0

local function publishEvents()
	local list = {}
	for _, a in ipairs(activeEvents) do
		table.insert(list, { Name = a.Name, Desc = a.Desc, Good = a.Good == true, EndsAt = a.EndsAt })
	end
	workspace:SetAttribute("Events", HttpService:JSONEncode(list))
end

local function announce(def)
	local duration = def.Duration or 6
	local entry = { Name = def.Name, Desc = def.Desc, Good = def.Good, EndsAt = workspace:GetServerTimeNow() + duration / gameSpeed }
	table.insert(activeEvents, entry)
	publishEvents()
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, (def.Good and "BONUS: " or "EVENT: ") .. def.Name .. " - " .. def.Desc)
	end
	task.delay(duration, function()
		local k = table.find(activeEvents, entry)
		if k then
			table.remove(activeEvents, k)
			publishEvents()
		end
	end)
end

local function resetEvents()
	eventToken += 1
	table.clear(activeEvents)
	publishEvents()
	mods.EnemySpeed, mods.EnemyAtk, mods.TowerRange, mods.TowerRate, mods.Reward = 1, 1, 1, 1, 1
	for k, v in pairs(lightingDefaults) do Lighting[k] = v end
	if atmosphere then atmosphere.Density = atmoDensity end
	for rec in pairs(buildingList) do rec.JamUntil = nil end
end

-- run fn after t seconds unless the events were reset in between
local function later(t, fn)
	local tok = eventToken
	task.delay(t, function()
		if tok == eventToken then fn() end
	end)
end

local function listBuildings(filter)
	local out = {}
	for rec in pairs(buildingList) do
		if not filter or filter(rec) then table.insert(out, rec) end
	end
	return out
end

local function listEnemies()
	local out = {}
	for _, e in pairs(enemies) do
		if not e.Dead then table.insert(out, e) end
	end
	return out
end

-- an empty cell enemies could walk to the city from
local function openCell(idx)
	return not cityIdx[idx] and not spawnIdx[idx] and not routeCells[idx] and terrain[idx] ~= "Water"
		and not buildings[idx] and (flows.ground[idx] or math.huge) < math.huge
end

local function flatDisc(pos, radius, color, material, transparency)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Cylinder
	p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
	p.Material = material or Enum.Material.Neon
	p.Color = color
	p.Transparency = transparency or 0.45
	p.Size = Vector3.new(0.15, radius * 2, radius * 2)
	p.CFrame = CFrame.new(pos + Vector3.new(0, 0.1, 0)) * CFrame.Angles(0, 0, math.pi / 2)
	p.Parent = mapFolder
	return p
end

local function currentWave()
	return workspace:GetAttribute("Wave") or 1
end

-- spawn a list of enemies one after another (from the normal gates unless atIdx is given)
local function burst(types, gap, atIdx, opts, onDone)
	local tok = eventToken
	pendingEvents += 1
	task.spawn(function()
		for _, typeName in ipairs(types) do
			if tok ~= eventToken or cityHP <= 0 then break end
			spawnEnemy(typeName, currentWave(), atIdx, opts)
			task.wait(gap)
		end
		pendingEvents -= 1
		if onDone then onDone() end
	end)
end

-- opens a temporary spawn point (portal or hole) at idx and pushes enemies out of it after a warning
local function temporaryGate(idx, types, gap, style)
	spawnIdx[idx] = true
	refreshTile(idx)
	local i, j = fromIdx(idx)
	local pos = cellCenter(i, j)
	local gate
	if style == "Burrow" then
		gate = flatDisc(pos, CELL * 0.55, Color3.fromRGB(70, 45, 25), Enum.Material.Ground, 0)
		local dust = Instance.new("Smoke")
		dust.Color = Color3.fromRGB(140, 110, 80)
		dust.Size = 3
		dust.RiseVelocity = 2
		dust.Parent = gate
	else
		gate = Models.Portal(pos)
		gate.Parent = mapFolder
	end
	local function close()
		gate:Destroy()
		spawnIdx[idx] = nil
		refreshTile(idx)
	end
	local tok = eventToken
	pendingEvents += 1
	task.delay(2, function()
		pendingEvents -= 1
		if tok ~= eventToken then close() return end
		burst(types, gap, idx, nil, function()
			task.wait(2)
			close()
		end)
	end)
end

local EventFns = {}

EventFns.Meteor = function(def, wave)
	local count = 8 + math.floor(wave / 2)
	local tok = eventToken
	task.spawn(function()
		for _ = 1, count do
			if tok ~= eventToken then return end
			local blds = listBuildings()
			local target
			if #blds > 0 and math.random() < 0.6 then
				target = blds[math.random(#blds)].Pos
			else
				target = cellCenter(math.random(1, W), math.random(1, H))
			end
			local radius = CELL * 1.3
			local warn = flatDisc(target, radius, Color3.fromRGB(255, 60, 40))
			local rock = Instance.new("Part")
			rock.Shape = Enum.PartType.Ball
			rock.Anchored, rock.CanCollide, rock.CanQuery, rock.CanTouch = true, false, false, false
			rock.Size = Vector3.new(3, 3, 3)
			rock.Material = Enum.Material.Basalt
			rock.Color = Color3.fromRGB(70, 50, 45)
			rock.Position = target + Vector3.new(14, 60, 10)
			local fire = Instance.new("Fire")
			fire.Size = 7
			fire.Parent = rock
			rock.Parent = mapFolder
			TweenService:Create(rock, TweenInfo.new(1.4 / gameSpeed, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { Position = target + Vector3.new(0, 1, 0) }):Play()
			task.delay(1.4, function()
				rock:Destroy()
				warn:Destroy()
				if tok ~= eventToken then return end
				Models.Boom(target + Vector3.new(0, 1, 0), radius, Color3.fromRGB(255, 130, 40))
				for _, rec in ipairs(listBuildings()) do
					local d = flatDist(rec.Pos, target)
					if d <= radius then damageBuilding(rec, 70 * (1 - 0.4 * d / radius)) end
				end
				for _, e in ipairs(listEnemies()) do
					if flatDist(e.Pos, target) <= radius then damageEnemy(e, 80) end
				end
				hitBuildersInRadius(target, radius)
			end)
			task.wait(def.Duration / count)
		end
	end)
end

EventFns.Ambush = function(def, wave)
	local cands = {}
	for _, side in ipairs({ 1, W }) do
		for j = 4, 20 do
			local idx = toIdx(side, j)
			if openCell(idx) then table.insert(cands, idx) end
		end
	end
	if #cands == 0 then return false end
	local types = {}
	for _ = 1, 4 + math.floor(wave / 2) do
		local r = math.random()
		table.insert(types, (wave >= 6 and r < 0.15) and "Tank" or ((r < 0.45) and "Runner" or "Grunt"))
	end
	temporaryGate(cands[math.random(#cands)], types, 0.5)
end

EventFns.Burrow = function(def, wave)
	local cands = {}
	for i = 3, W - 2 do
		for j = 7, 19 do
			local idx = toIdx(i, j)
			if openCell(idx) then table.insert(cands, idx) end
		end
	end
	if #cands == 0 then return false end
	local types = {}
	for _ = 1, 3 + math.floor(wave / 3) do
		table.insert(types, (math.random() < 0.35) and "Climber" or "Grunt")
	end
	temporaryGate(cands[math.random(#cands)], types, 0.6, "Burrow")
end

EventFns.Stampede = function(def, wave)
	local types = {}
	for _ = 1, 5 + math.floor(wave / 2) do table.insert(types, "Runner") end
	burst(types, 0.25)
end

EventFns.AirRaid = function(def, wave)
	local types = {}
	for _ = 1, 3 + math.floor(wave / 3) do table.insert(types, "Flyer") end
	burst(types, 0.5)
end

EventFns.Champion = function(def, wave)
	local typeName = (wave >= 6) and "Tank" or "Grunt"
	local types = {}
	for _ = 1, (wave >= 9) and 2 or 1 do table.insert(types, typeName) end
	burst(types, 1.5, nil, { Elite = true })
end

EventFns.Fog = function(def)
	mods.TowerRange = 0.6
	Lighting.FogColor = Color3.fromRGB(175, 180, 190)
	Lighting.FogStart = 0
	Lighting.FogEnd = 70
	if atmosphere then atmosphere.Density = 0.75 end
	later(def.Duration, function()
		mods.TowerRange = 1
		Lighting.FogColor, Lighting.FogStart, Lighting.FogEnd = lightingDefaults.FogColor, lightingDefaults.FogStart, lightingDefaults.FogEnd
		if atmosphere then atmosphere.Density = atmoDensity end
	end)
end

EventFns.BloodMoon = function(def)
	mods.EnemySpeed, mods.EnemyAtk = 1.4, 1.5
	Lighting.Ambient = Color3.fromRGB(120, 35, 35)
	Lighting.OutdoorAmbient = Color3.fromRGB(160, 50, 50)
	Lighting.ColorShift_Top = Color3.fromRGB(255, 60, 60)
	later(def.Duration, function()
		mods.EnemySpeed, mods.EnemyAtk = 1, 1
		Lighting.Ambient, Lighting.OutdoorAmbient, Lighting.ColorShift_Top = lightingDefaults.Ambient, lightingDefaults.OutdoorAmbient, lightingDefaults.ColorShift_Top
	end)
end

EventFns.Sabotage = function(def, wave)
	local towers = listBuildings(function(r) return r.Def.Kind == "Tower" end)
	if #towers == 0 then return false end
	local until_ = gameTime + def.Duration
	for _ = 1, math.min(#towers, (wave >= 8) and 4 or 3) do
		local rec = table.remove(towers, math.random(#towers))
		rec.JamUntil = until_
		if rec.Model and rec.Model.PrimaryPart then
			local sm = Instance.new("Smoke")
			sm.Color = Color3.fromRGB(40, 40, 40)
			sm.Size = 2
			sm.Parent = rec.Model.PrimaryPart
			local sp = Instance.new("Sparkles")
			sp.SparkleColor = Color3.fromRGB(255, 220, 80)
			sp.Parent = rec.Model.PrimaryPart
			Debris:AddItem(sm, def.Duration)
			Debris:AddItem(sp, def.Duration)
		end
	end
end

EventFns.Quake = function(def)
	workspace:SetAttribute("Quake", workspace:GetServerTimeNow())
	for _, rec in ipairs(listBuildings()) do
		if rec.MaxHP > 0 then damageBuilding(rec, rec.MaxHP * 0.2) end
	end
end

EventFns.Lightning = function(def)
	local tok = eventToken
	task.spawn(function()
		local t = 0
		while t < def.Duration and tok == eventToken do
			local es, bs = listEnemies(), listBuildings()
			local pos
			if #es > 0 and (#bs == 0 or math.random() < 0.55) then
				local e = es[math.random(#es)]
				pos = e.Pos + Vector3.new(0, e.Lift + 2, 0)
				damageEnemy(e, 90)
			elseif #bs > 0 then
				local rec = bs[math.random(#bs)]
				pos = rec.Pos + Vector3.new(0, 3, 0)
				damageBuilding(rec, 45)
			end
			if pos then
				Models.Beam(pos + Vector3.new(math.random(-6, 6), 60, math.random(-6, 6)), pos, Color3.fromRGB(190, 220, 255), 0.7)
				Models.Boom(pos, 2.5, Color3.fromRGB(200, 230, 255))
			end
			t += task.wait(0.9)
		end
	end)
end

EventFns.GoldRush = function(def)
	mods.Reward = 2
	later(def.Duration, function() mods.Reward = 1 end)
end

EventFns.Overcharge = function(def)
	mods.TowerRate = 2
	later(def.Duration, function() mods.TowerRate = 1 end)
end

EventFns.Supply = function(def, wave)
	local amount = 40 + 8 * wave
	for _, p in ipairs(Players:GetPlayers()) do addCoins(p, amount) end
	local c = Config.City
	Models.Popup(cellCenter((c.MinI + c.MaxI) / 2, (c.MinJ + c.MaxJ) / 2) + Vector3.new(0, 12, 0), "+$" .. amount .. " each", Color3.fromRGB(120, 255, 140))
end

local function pickEvents(wave)
	local pool = {}
	for _, ev in ipairs(Config.Events) do
		if wave >= ev.MinWave then table.insert(pool, ev) end
	end
	local picked = {}
	for _ = 1, Config.EventCount(wave) do
		local total = 0
		for _, ev in ipairs(pool) do total += ev.Weight end
		if total <= 0 then break end
		local r = math.random() * total
		for k, ev in ipairs(pool) do
			r -= ev.Weight
			if r <= 0 then
				table.insert(picked, ev)
				table.remove(pool, k)   -- no repeats within one wave
				break
			end
		end
	end
	return picked
end

local function triggerEvent(def, wave)
	local fn = EventFns[def.Id]
	if not fn then return end
	if fn(def, wave) == false then return end   -- couldn't happen right now (e.g. no towers to sabotage)
	announce(def)
end

-- Studio-only dev tool: set workspace attribute DebugEvent = "Meteor" (etc.) from the server command bar to fire it
if RunService:IsStudio() then
	workspace:GetAttributeChangedSignal("DebugEvent"):Connect(function()
		local id = workspace:GetAttribute("DebugEvent")
		if not id then return end
		workspace:SetAttribute("DebugEvent", nil)   -- clear it so the same event can be fired again
		local spawnType = string.match(id, "^Spawn:(%a+)$")
		if spawnType and Config.Enemies[spawnType] then
			spawnEnemy(spawnType, currentWave())
		end
		if id == "HitBuilder" then
			for _, list in pairs(builders) do
				if list[1] then hitBuilder(list[1]) break end
			end
		end
		if id == "Trade" and not trade.Active then
			startTrade(currentWave())
			trade.Moving = (phase == "Wave")
			setTradeAttrs()
		end
		for _, ev in ipairs(Config.Events) do
			if ev.Id == id then triggerEvent(ev, currentWave()) end
		end
	end)
end

-- spread this wave's events over its spawning time
local function scheduleEvents(wave, spawnTime)
	local tok = eventToken
	for _, def in ipairs(pickEvents(wave)) do
		pendingEvents += 1
		task.delay(1.5 + math.random() * math.max(2, spawnTime * 0.8), function()
			pendingEvents -= 1
			if tok == eventToken and phase == "Wave" and cityHP > 0 then triggerEvent(def, wave) end
		end)
	end
end

---------------------------------------------------------------- waves
local function buildWaveList(n)
	local list = {}
	for _ = 1, math.floor((4 + n * 2) * Config.Difficulty.CountMul) do table.insert(list, "Grunt") end
	if n >= 3 then for _ = 1, n do table.insert(list, "Runner") end end
	if n >= 4 then for _ = 1, math.floor(n / 2) - 1 do table.insert(list, "Climber") end end
	if n >= 3 then for _ = 1, math.floor((n - 1) / 2) do table.insert(list, "Bomber") end end
	if n >= 5 then for _ = 1, math.floor((n - 3) / 2) do table.insert(list, "Tank") end end
	if n >= 6 then for _ = 1, math.floor((n - 4) / 2) do table.insert(list, "Flyer") end end
	if n >= 4 then for _ = 1, math.floor((n - 2) / 2) do table.insert(list, "Swimmer") end end
	if n % 10 == 0 then table.insert(list, "Boss") end
	for k = #list, 2, -1 do
		local r = math.random(k)
		list[k], list[r] = list[r], list[k]
	end
	-- dungeon kills thin out this wave (never the boss, and at most half of it)
	local cut = math.min(waveReduction, math.floor(#list * Config.Dungeon.MaxWaveReduction))
	local k = #list
	while cut > 0 and k >= 1 do
		if list[k] ~= "Boss" then
			table.remove(list, k)
			cut -= 1
		end
		k -= 1
	end
	return list
end

local function clearEnemies()
	for _, e in pairs(enemies) do removeEnemy(e) end
end

local function resetBoard()
	finishTrade()
	clearEnemies()
	for rec in pairs(buildingList) do
		rec.Dead = true
		buildings[rec.Idx] = nil
		buildingList[rec] = nil
		if rec.Model then rec.Model:Destroy() end
	end
	table.clear(buildJobs)
	table.clear(recById)
	-- fresh crew of builders for everyone
	for uid in pairs(builders) do clearBuilders(uid) end
	for _, p in ipairs(Players:GetPlayers()) do
		for _ = 1, Config.Builders do spawnBuilder(p) end
	end
	-- dungeon, portal, crystals and upgrades start over too
	gameWon, winnerName = false, nil
	Dungeon.resetAll()
	closePortal()
	waveReduction = 0
	workspace:SetAttribute("NextWaveReduction", 0)
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		if ls and ls:FindFirstChild("Crystals") then ls.Crystals.Value = 0 end
		for _, u in ipairs(Config.Upgrades) do p:SetAttribute("Up_" .. u.Id, 0) end
		for _, b in ipairs(Config.Buffs) do p:SetAttribute("Buff_" .. b.Id, nil) end
		p:SetAttribute("BuffList", "")
	end
	for idx = 1, N do
		terrain[idx] = "Grass"
		terrainOwner[idx] = nil
		refreshTile(idx)
	end
	refreshFlows()
	cityHP = Config.CityHP
	workspace:SetAttribute("CityHP", cityHP)
	workspace:SetAttribute("CityMaxHP", Config.CityHP)
	for _, p in ipairs(Players:GetPlayers()) do
		local ls = p:FindFirstChild("leaderstats")
		if ls then ls.Coins.Value = Config.StartCoins end
		p:SetAttribute("Building", 0)
		p:SetAttribute("Queued", 0)
	end
end

local function runGame()
	buildWorld()
	while true do
		resetBoard()
		local wave = (Config.StartWave or 1) - 1
		trade.NextWave = wave + math.random(Config.Trade.MinGap, Config.Trade.MaxGap)
		while cityHP > 0 and not gameWon do
			while #Players:GetPlayers() == 0 do task.wait(1) end
			wave += 1
			workspace:SetAttribute("Wave", wave)

			-- build phase
			phase = "Build"
			workspace:SetAttribute("Phase", phase)
			table.clear(ready)
			updateReady()

			-- trade route event every 2-4 waves
			if wave >= trade.NextWave and not trade.Active then
				if startTrade(wave) then
					trade.NextWave = wave + math.random(Config.Trade.MinGap, Config.Trade.MaxGap)
					for _, p in ipairs(Players:GetPlayers()) do
						notify(p, "TRADE ROUTE opened through " .. ((trade.Truck.Risk >= 0.55) and "HIGH" or ((trade.Truck.Risk >= 0.3) and "MEDIUM" or "LOW")) .. " risk territory - bigger payout, protect the truck!")
					end
				else
					trade.NextWave = wave + 1   -- no room for a road, try again next wave
				end
			end
			local t = (wave == 1) and Config.FirstBuildTime or Config.BuildTime
			while t > 0 do
				workspace:SetAttribute("Timer", math.ceil(t))
				if readyCount() >= readyNeeded() or devSkipBuild or gameWon then break end
				t -= task.wait(0.25)
			end

			-- wave phase
			phase = "Wave"
			workspace:SetAttribute("Phase", phase)
			if trade.Active then
				trade.Moving = true
				setTradeAttrs()
			end
			devSkipBuild = false
			-- test console: jump to a chosen wave
			if devJumpWave then
				wave = devJumpWave
				devJumpWave = nil
				workspace:SetAttribute("Wave", wave)
			end
			local list = buildWaveList(wave)
			if waveReduction > 0 then
				for _, p in ipairs(Players:GetPlayers()) do
					notify(p, "Your dungeon hunting weakened this wave! (" .. #list .. " enemies)")
				end
			end
			waveReduction = 0
			workspace:SetAttribute("NextWaveReduction", 0)
			-- long waves: enemies are spread out over about a minute
			local interval = math.clamp((Config.WaveLength + 4 * wave) / math.max(1, #list), 0.5, 6)
			scheduleEvents(wave, #list * interval)
			for _, typeName in ipairs(list) do
				if cityHP <= 0 or gameWon then break end
				spawnEnemy(typeName, wave)
				task.wait(interval)
			end
			while (enemyCount > 0 or trade.Active or pendingEvents > 0) and cityHP > 0 and not gameWon do task.wait(0.25) end
			resetEvents()

			if cityHP > 0 and not gameWon then
				-- farms pay out first
				local farmPay = {}
				for rec in pairs(buildingList) do
					if rec.Def.Kind == "Farm" and not rec.Building then
						local amount = rec.Def.Income + math.min(rec.Age, rec.Def.MaxBonusWaves) * rec.Def.Bonus
						rec.Age += 1
						farmPay[rec.Owner] = (farmPay[rec.Owner] or 0) + amount
						Models.Popup(rec.Pos + Vector3.new(0, 4, 0), "+$" .. amount, Color3.fromRGB(255, 225, 90))
						local owner = Players:GetPlayerByUserId(rec.Owner)
						if owner then addCoins(owner, amount) end
					end
				end
				for _, p in ipairs(Players:GetPlayers()) do
					local bonus = Config.WaveBonus + wave * 5
					addCoins(p, bonus)
					-- one new builder per cleared wave
					local newBuilder = ""
					if aliveBuilders(p.UserId) < Config.Builders then
						spawnBuilder(p)
						newBuilder = " A new builder arrived!"
					end
					local fp = farmPay[p.UserId]
					notify(p, "Wave " .. wave .. " cleared! +" .. bonus .. " coins" .. (fp and (" (+" .. fp .. " from farms)") or "") .. newBuilder)
				end
				-- the dungeon portal opens after the first wave; finished dungeon floors get replaced
				openPortal()
				for _, p in ipairs(Players:GetPlayers()) do Dungeon.onWaveEnd(p) end
			end
		end

		if gameWon then
			-- VICTORY: someone beat the final dungeon boss
			phase = "Victory"
			workspace:SetAttribute("VictoryBy", winnerName or "")
			workspace:SetAttribute("VictoryWave", workspace:GetAttribute("Wave") or 0)
			workspace:SetAttribute("Phase", phase)
			resetEvents()
			finishTrade()
			clearEnemies()
			Dungeon.resetAll()
			for t = 20, 1, -1 do
				workspace:SetAttribute("Timer", t)
				realTask.wait(1)   -- real seconds, whatever the game speed
			end
		else
			-- game over
			phase = "GameOver"
			workspace:SetAttribute("Phase", phase)
			resetEvents()
			finishTrade()
			clearEnemies()
			task.wait(10)
		end
	end
end

---------------------------------------------------------------- dungeon hookup
-- a unit coming back out of the dungeon appears on a free tile next to the portal
local function returnUnitToBase(player, def, hpFrac)
	local seen = { [portalIdx] = true }
	local queue, head = { portalIdx }, 1
	local spot
	while head <= #queue do
		local cur = queue[head]
		head += 1
		if cur ~= portalIdx and not buildings[cur] and terrain[cur] ~= "Water" and not cityIdx[cur] and not spawnIdx[cur] and not routeCells[cur] then
			spot = cur
			break
		end
		local ci, cj = fromIdx(cur)
		for _, d in ipairs(DIRS) do
			local ni, nj = ci + d[1], cj + d[2]
			if inBounds(ni, nj) then
				local n = toIdx(ni, nj)
				if not seen[n] then
					seen[n] = true
					table.insert(queue, n)
				end
			end
		end
	end
	if not spot then
		addCoins(player, def.Cost)
		notify(player, "No room for your " .. def.Name .. " - refunded.")
		return
	end
	local i, j = fromIdx(spot)
	local rec = createBuilding(player, def, i, j)
	finishBuilding(rec)
	rec.HP = math.max(1, rec.MaxHP * math.clamp(hpFrac, 0, 1))
	if rec.Bar then Models.SetBar(rec.Bar, rec.HP / rec.MaxHP) end
	refreshTile(spot)
	markDirty()
end

-- send the chosen units walking into the portal
local function enterRequest(player, ids)
	if not portalOpen or phase == "GameOver" or phase == "Victory" or typeof(ids) ~= "table" then return end
	local n = 0
	for _, id in ipairs(ids) do
		if n >= 30 then break end
		local rec = (typeof(id) == "number") and recById[id] or nil
		if rec and not rec.Dead and rec.Owner == player.UserId and rec.Def.Kind == "Monster" and not rec.Building and not rec.EnterDungeon then
			n += 1
			rec.EnterDungeon = true
			local path = unitPath(rec, posToIdx(rec.Pos), portalIdx)
			if buildings[rec.Idx] == rec then
				buildings[rec.Idx] = nil
				refreshTile(rec.Idx)
			end
			rec.Idx = portalIdx
			if path then
				local wps = { rec.Pos }
				for k = 2, #path do
					local pi, pj = fromIdx(path[k])
					table.insert(wps, cellCenter(pi, pj))
				end
				if #wps == 1 then table.insert(wps, cellCenter(Config.Portal[1], Config.Portal[2])) end
				rec.Path, rec.Wp, rec.Moving = wps, 2, true
			else
				enterDungeon(rec)
			end
		end
	end
	if n > 0 then
		markDirty()
		notify(player, n .. " unit" .. ((n > 1) and "s" or "") .. " heading into the dungeon portal!")
	end
end

local function buyUpgrade(player, key)
	local up
	for _, u in ipairs(Config.Upgrades) do
		if u.Id == key then up = u end
	end
	if not up then return end
	local uid = player.UserId
	local level = player:GetAttribute("Up_" .. key) or 0
	if level >= up.Max then notify(player, up.Name .. " is already maxed") return end
	local cost = Config.UpgradeCost(level)
	local cr = player.leaderstats:FindFirstChild("Crystals")
	if not cr or cr.Value < cost then notify(player, "Not enough crystals (need " .. cost .. ")") return end
	cr.Value -= cost
	local oldWalls, oldUnits = upMul(uid, "Walls"), upMul(uid, "Units")
	player:SetAttribute("Up_" .. key, level + 1)
	-- health upgrades also apply to what you already have
	if key == "Walls" or key == "Units" then
		local factor = (key == "Walls") and (upMul(uid, "Walls") / oldWalls) or (upMul(uid, "Units") / oldUnits)
		for rec in pairs(buildingList) do
			if rec.Owner == uid and rec.MaxHP > 0 and ((rec.Def.Kind == "Monster") == (key == "Units")) and rec.Def.Kind ~= "Terrain" then
				rec.MaxHP *= factor
				rec.HP *= factor
			end
		end
		if key == "Units" then Dungeon.scaleUnitHP(uid, factor) end
	end
	notify(player, up.Name .. " is now level " .. (level + 1) .. "!")
end

-- the dungeon Warlord gives a random buff you don't have yet, for the rest of the match
local function grantBuff(player)
	local free = {}
	for _, b in ipairs(Config.Buffs) do
		if not player:GetAttribute("Buff_" .. b.Id) then table.insert(free, b) end
	end
	if #free == 0 then return nil end
	local b = free[math.random(#free)]
	local uid = player.UserId
	player:SetAttribute("Buff_" .. b.Id, true)
	-- health buffs also apply to what you already have
	if b.Id == "Might" then
		for rec in pairs(buildingList) do
			if rec.Owner == uid and rec.Def.Kind == "Monster" then
				rec.MaxHP *= 1.5
				rec.HP *= 1.5
			end
		end
		Dungeon.scaleUnitHP(uid, 1.5)
	elseif b.Id == "Fortress" then
		for rec in pairs(buildingList) do
			if rec.Owner == uid and rec.MaxHP > 0 and rec.Def.Kind ~= "Monster" and rec.Def.Kind ~= "Terrain" then
				rec.MaxHP *= 1.4
				rec.HP *= 1.4
			end
		end
		local max = (workspace:GetAttribute("CityMaxHP") or Config.CityHP) + 50
		cityHP = max
		workspace:SetAttribute("CityMaxHP", max)
		workspace:SetAttribute("CityHP", cityHP)
	end
	local names = {}
	for _, x in ipairs(Config.Buffs) do
		if player:GetAttribute("Buff_" .. x.Id) then table.insert(names, x.Name) end
	end
	player:SetAttribute("BuffList", table.concat(names, ", "))
	return b
end

Dungeon.init({
	addCoins = addCoins,
	getCoins = getCoins,
	notify = notify,
	addCrystals = function(p, n)
		local ls = p:FindFirstChild("leaderstats")
		local cr = ls and ls:FindFirstChild("Crystals")
		if cr then cr.Value += n end
	end,
	unitDamageMul = function(uid) return upMul(uid, "Units") * (hasBuff(uid, "Might") and 1.5 or 1) end,
	hasFreeBuff = function(p)
		for _, b in ipairs(Config.Buffs) do
			if not p:GetAttribute("Buff_" .. b.Id) then return true end
		end
		return false
	end,
	grantBuff = function(p) return grantBuff(p) end,
	reduceNextWave = function(n)
		waveReduction += n
		workspace:SetAttribute("NextWaveReduction", waveReduction)
	end,
	returnUnit = returnUnitToBase,
	-- the final boss is dead: everyone wins
	winGame = function(p)
		if gameWon or phase == "GameOver" then return end
		gameWon = true
		winnerName = p.Name
		for _, other in ipairs(Players:GetPlayers()) do
			notify(other, "VICTORY! " .. p.Name .. " defeated the Overlord! The city is saved!")
		end
	end,
})

dungeonRemote.OnServerEvent:Connect(function(player, action, a, b, c)
	if typeof(action) ~= "string" or not rateOk(player) then return end
	if action == "Upgrade" then
		buyUpgrade(player, a)
	elseif action == "Enter" then
		enterRequest(player, a)
	else
		Dungeon.handle(player, action, a, b, c)
	end
end)

---------------------------------------------------------------- test console
local DEV = {}
DEV.Coins = function(p) addCoins(p, 1000) end
DEV.Crystals = function(p)
	local cr = p.leaderstats:FindFirstChild("Crystals")
	if cr then cr.Value += 10 end
end
DEV.MaxUpgrades = function(p)
	for _, u in ipairs(Config.Upgrades) do p:SetAttribute("Up_" .. u.Id, u.Max) end
	notify(p, "DEV: all upgrades maxed")
end
DEV.StartWave = function(p)
	if phase == "Build" then devSkipBuild = true else notify(p, "DEV: a wave is already running") end
end
DEV.KillAll = function(p)
	for _, e in pairs(enemies) do killEnemy(e, p.UserId) end
end
DEV.JumpWave = function(p, n)
	n = tonumber(n)
	if not n or n < 1 or n > 500 then notify(p, "DEV: type a wave number first") return end
	devJumpWave = math.floor(n)
	if phase == "Build" then devSkipBuild = true end
	notify(p, "DEV: the next wave will be wave " .. devJumpWave)
end
DEV.HealCity = function()
	cityHP = workspace:GetAttribute("CityMaxHP") or Config.CityHP
	workspace:SetAttribute("CityHP", cityHP)
end
DEV.God = function(p)
	devGod = not devGod
	workspace:SetAttribute("DevGod", devGod)
end
DEV.Instant = function(p)
	devInstantBuild = not devInstantBuild
	workspace:SetAttribute("DevInstant", devInstantBuild)
	if devInstantBuild then
		for rec in pairs(buildingList) do
			if rec.Building then finishBuilding(rec) end
		end
	end
end
DEV.AddBuilder = function(p) spawnBuilder(p) end
DEV.KillBuilder = function(p)
	local list = builders[p.UserId]
	local b = list and list[1]
	if b then
		b.HP = 1
		hitBuilder(b)
	end
end
DEV.Spawn = function(p, typeName)
	if typeName == "Champion" then
		spawnEnemy("Tank", currentWave(), nil, { Elite = true })
	elseif typeof(typeName) == "string" and Config.Enemies[typeName] then
		spawnEnemy(typeName, currentWave())
	end
end
DEV.Event = function(p, id)
	for _, ev in ipairs(Config.Events) do
		if ev.Id == id then triggerEvent(ev, currentWave()) end
	end
end
DEV.Trade = function(p)
	if trade.Active then notify(p, "DEV: a trade route is already open") return end
	if startTrade(currentWave()) then
		trade.Moving = (phase == "Wave")
		setTradeAttrs()
	else
		notify(p, "DEV: no room for a trade road")
	end
end
DEV.Portal = function(p) openPortal() end
DEV.FinalFloor = function(p)
	if Dungeon.devFinalFloor(p) then
		notify(p, "DEV: your dungeon is now the final floor (the Overlord is in the last room)")
	else
		notify(p, "DEV: retreat from the dungeon first")
	end
end
DEV.Buff = function(p)
	local b = grantBuff(p)
	notify(p, b and ("DEV: buff " .. b.Name .. " - " .. b.Desc) or "DEV: you already have every buff")
end
DEV.DungeonRoom = function(p)
	if not Dungeon.devClearRoom(p) then notify(p, "DEV: every room on this floor is already cleared") end
end

devRemote.OnServerEvent:Connect(function(player, cmd, arg)
	if not player:GetAttribute("IsDev") or typeof(cmd) ~= "string" then return end
	local fn = DEV[cmd]
	if fn then fn(player, arg) end
end)

abilityRemote.OnServerEvent:Connect(function(player, key, ids, tx, tz, inDungeon)
	if key ~= "Q" and key ~= "E" and key ~= "R" then return end
	if typeof(ids) ~= "table" or #ids > 60 then return end
	if phase == "GameOver" or phase == "Victory" then return end
	if inDungeon then
		Dungeon.useAbility(player, key, ids, tx, tz)
	else
		useAbilityBase(player, key, ids, tx, tz)
	end
end)

speedRemote.OnServerEvent:Connect(function(player, s)
	if s ~= 1 and s ~= 2 and s ~= 3 then return end
	if s == gameSpeed then return end
	gameSpeed = s
	workspace:SetAttribute("GameSpeed", s)
	for _, p in ipairs(Players:GetPlayers()) do
		notify(p, "Game speed: " .. s .. "x" .. ((p ~= player) and (" (set by " .. player.Name .. ")") or ""))
	end
end)

task.spawn(runGame)
