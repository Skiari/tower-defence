-- Procedural blocky models for buildings, enemies, the city and effects
local TweenService = game:GetService("TweenService")
local Debris = game:GetService("Debris")

local Models = {}

local function newPart(parent, name, size, cf, color, material, canCollide)
	local p = Instance.new("Part")
	p.Name = name
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	p.CanCollide = canCollide ~= false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- Upright cylinder (Roblox cylinders lie along X, so rotate)
local function newCylinder(parent, name, height, diameter, pos, color, material, canCollide)
	local p = newPart(parent, name, Vector3.new(height, diameter, diameter),
		CFrame.new(pos) * CFrame.Angles(0, 0, math.pi / 2), color, material, canCollide)
	p.Shape = Enum.PartType.Cylinder
	return p
end

function Models.AddHealthBar(model, adornee, offsetY, width)
	local gui = Instance.new("BillboardGui")
	gui.Name = "HealthGui"
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(width or 56, 7)
	gui.StudsOffset = Vector3.new(0, offsetY, 0)
	gui.MaxDistance = 140
	gui.Parent = model

	local back = Instance.new("Frame")
	back.Name = "Back"
	back.Size = UDim2.fromScale(1, 1)
	back.BackgroundColor3 = Color3.new(0, 0, 0)
	back.BackgroundTransparency = 0.3
	back.BorderSizePixel = 0
	back.Parent = gui

	local bar = Instance.new("Frame")
	bar.Name = "Bar"
	bar.Size = UDim2.fromScale(1, 1)
	bar.BackgroundColor3 = Color3.fromRGB(80, 220, 80)
	bar.BorderSizePixel = 0
	bar.Parent = back
	return bar
end

function Models.SetBar(bar, frac)
	if not bar then return end
	frac = math.clamp(frac, 0, 1)
	bar.Size = UDim2.fromScale(frac, 1)
	bar.BackgroundColor3 = Color3.fromHSV(frac * 0.33, 0.8, 0.9)
end

-- pos = centre of the tile surface. Returns model, healthBar (monsters only)
function Models.Building(def, pos)
	local m = Instance.new("Model")
	m.Name = def.Id
	local id = def.Id
	local function at(x, y, z) return CFrame.new(pos + Vector3.new(x, y, z)) end
	local bar

	if id == "Wall" then
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.8, 4, 3.8), at(0, 2, 0), Color3.fromRGB(125, 125, 138), Enum.Material.Brick)
		newPart(m, "Cap", Vector3.new(4, 0.6, 4), at(0, 4.3, 0), Color3.fromRGB(165, 165, 178), Enum.Material.Concrete)
		for _, x in ipairs({ -1.4, 0, 1.4 }) do
			newPart(m, "Crenel", Vector3.new(0.9, 0.7, 0.9), at(x, 4.95, 0), Color3.fromRGB(165, 165, 178), Enum.Material.Concrete)
		end
		-- health bar stays hidden until the wall is damaged
		bar = Models.AddHealthBar(m, m.PrimaryPart, 3.6, 40)
		bar.Parent.Parent.Enabled = false

	elseif id == "Spikes" then
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.8, 0.3, 3.8), at(0, 0.15, 0), Color3.fromRGB(70, 70, 76), Enum.Material.Metal, false)
		for x = -1, 1 do
			for z = -1, 1 do
				newPart(m, "Spike", Vector3.new(0.5, 1.5, 0.5), at(x * 1.1, 0.9, z * 1.1), Color3.fromRGB(205, 205, 215), Enum.Material.Metal, false)
			end
		end

	elseif id == "Fire" then
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.8, 0.5, 3.8), at(0, 0.25, 0), Color3.fromRGB(55, 35, 35), Enum.Material.Slate, false)
		local core = newPart(m, "Core", Vector3.new(2.2, 0.3, 2.2), at(0, 0.6, 0), Color3.fromRGB(255, 110, 20), Enum.Material.Neon, false)
		local fire = Instance.new("Fire")
		fire.Size = 6
		fire.Heat = 8
		fire.Parent = core

	elseif id == "Arrow" then
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3, 5, 3), at(0, 2.5, 0), Color3.fromRGB(150, 110, 70), Enum.Material.Wood)
		newPart(m, "Deck", Vector3.new(4, 0.6, 4), at(0, 5.3, 0), Color3.fromRGB(110, 80, 50), Enum.Material.WoodPlanks)
		local head = newPart(m, "Head", Vector3.new(1.6, 1.2, 1.6), at(0, 6.2, 0), Color3.fromRGB(200, 60, 60), nil, false)
		newPart(m, "Barrel", Vector3.new(0.4, 0.4, 2.4), CFrame.new(head.Position + Vector3.new(0, 0, -1.4)), Color3.fromRGB(40, 40, 40), nil, false)

	elseif id == "Cannon" then
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.6, 2.4, 3.6), at(0, 1.2, 0), Color3.fromRGB(80, 80, 92), Enum.Material.Slate)
		newPart(m, "Deck", Vector3.new(4, 0.5, 4), at(0, 2.6, 0), Color3.fromRGB(55, 55, 65), Enum.Material.Metal)
		local head = newPart(m, "Head", Vector3.new(2, 1.5, 2), at(0, 3.6, 0), Color3.fromRGB(35, 35, 40), Enum.Material.Metal, false)
		newPart(m, "Barrel", Vector3.new(1, 1, 3.2), CFrame.new(head.Position + Vector3.new(0, 0, -1.4)), Color3.fromRGB(20, 20, 25), Enum.Material.Metal, false)

	elseif id == "Farm" then
		-- soil plot with crop rows and a little red barn
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.8, 0.5, 3.8), at(0, 0.25, 0), Color3.fromRGB(110, 75, 45), Enum.Material.Ground)
		for k, z in ipairs({ 0.5, 1.4 }) do
			newPart(m, "CropRow", Vector3.new(3.2, 0.9, 0.55), at(0, 0.95, z), Color3.fromRGB(70, 170, 60), Enum.Material.Grass, false)
			for _, x in ipairs({ -1.2, -0.4, 0.4, 1.2 }) do
				newPart(m, "Crop", Vector3.new(0.45, 0.45, 0.45), at(x, 1.55, z), Color3.fromRGB(245, 205, 60), Enum.Material.SmoothPlastic, false)
			end
		end
		newPart(m, "Barn", Vector3.new(2.4, 1.8, 1.3), at(0, 1.4, -1.2), Color3.fromRGB(190, 50, 45), Enum.Material.WoodPlanks)
		newPart(m, "BarnRoof", Vector3.new(2.8, 0.35, 1.7), at(0, 2.45, -1.2), Color3.fromRGB(95, 40, 35), Enum.Material.Wood, false)
		newPart(m, "BarnDoor", Vector3.new(0.9, 1.1, 0.1), at(0, 1.05, -0.58), Color3.fromRGB(235, 225, 205), Enum.Material.Wood, false)
		bar = Models.AddHealthBar(m, m.PrimaryPart, 4.5, 40)
		bar.Parent.Parent.Enabled = false

	elseif id == "Goblin" or id == "Ogre" then
		local s = (id == "Ogre") and 1.8 or 1
		local skin = (id == "Ogre") and Color3.fromRGB(190, 120, 70) or Color3.fromRGB(90, 180, 80)
		local dark = skin:Lerp(Color3.new(0, 0, 0), 0.5)
		newPart(m, "LegL", Vector3.new(0.6, 1.1, 0.6) * s, at(-0.45 * s, 0.55 * s, 0), dark, nil, false)
		newPart(m, "LegR", Vector3.new(0.6, 1.1, 0.6) * s, at(0.45 * s, 0.55 * s, 0), dark, nil, false)
		local torso = newPart(m, "Torso", Vector3.new(1.7, 1.6, 1) * s, at(0, 1.9 * s, 0), skin)
		m.PrimaryPart = torso
		local head = newPart(m, "Head", Vector3.new(1.2, 1.2, 1.2) * s, at(0, 3.3 * s, 0), skin, nil, false)
		newPart(m, "EyeL", Vector3.new(0.22, 0.22, 0.1) * s, at(-0.3 * s, 3.4 * s, -0.6 * s), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, false)
		newPart(m, "EyeR", Vector3.new(0.22, 0.22, 0.1) * s, at(0.3 * s, 3.4 * s, -0.6 * s), Color3.fromRGB(255, 40, 40), Enum.Material.Neon, false)
		if id == "Goblin" then
			-- spear held forward (models face -Z)
			newPart(m, "Spear", Vector3.new(0.18, 0.18, 4) * s, at(1.0 * s, 2.2 * s, -1.2 * s), Color3.fromRGB(120, 85, 45), Enum.Material.Wood, false)
			newPart(m, "SpearTip", Vector3.new(0.32, 0.32, 0.7) * s, at(1.0 * s, 2.2 * s, -3.5 * s), Color3.fromRGB(215, 220, 230), Enum.Material.Metal, false)
		else
			newPart(m, "Club", Vector3.new(0.45, 2.2, 0.45) * s, at(1.3 * s, 2.3 * s, -0.3 * s), Color3.fromRGB(110, 75, 40), Enum.Material.Wood, false)
		end
		bar = Models.AddHealthBar(m, head, 1.4 * s, 56)

	else
		m.PrimaryPart = newPart(m, "Base", Vector3.new(3.5, 3.5, 3.5), at(0, 1.75, 0), def.Color or Color3.fromRGB(200, 200, 200))
	end

	return m, bar
end

-- Turn a tower's head + barrel towards a world position
function Models.Aim(model, target)
	local head = model:FindFirstChild("Head")
	if not head then return end
	local pos = head.Position
	local flat = Vector3.new(target.X, pos.Y, target.Z)
	if (flat - pos).Magnitude < 0.1 then return end
	local cf = CFrame.lookAt(pos, flat)
	head.CFrame = cf
	local barrel = model:FindFirstChild("Barrel")
	if barrel then
		barrel.CFrame = cf * CFrame.new(0, 0, -1.4)
	end
end

-- Enemy model built around the origin (ground level); move with PivotTo
function Models.Enemy(def)
	local m = Instance.new("Model")
	m.Name = def.Name
	local s = def.Scale
	local col = def.Color
	local dark = col:Lerp(Color3.new(0, 0, 0), 0.5)
	local light = col:Lerp(Color3.new(1, 1, 1), 0.25)

	if def.Style == "Flyer" then
		newPart(m, "Torso", Vector3.new(1.3, 1.2, 1.8) * s, CFrame.new(0, 2.2 * s, 0), col, nil, false)
		local fhead = newPart(m, "Head", Vector3.new(1, 1, 1) * s, CFrame.new(0, 2.5 * s, -1.2 * s), light, nil, false)
		newPart(m, "EyeL", Vector3.new(0.2, 0.2, 0.1) * s, CFrame.new(-0.25 * s, 2.6 * s, -1.72 * s), Color3.fromRGB(255, 60, 60), Enum.Material.Neon, false)
		newPart(m, "EyeR", Vector3.new(0.2, 0.2, 0.1) * s, CFrame.new(0.25 * s, 2.6 * s, -1.72 * s), Color3.fromRGB(255, 60, 60), Enum.Material.Neon, false)
		newPart(m, "WingL", Vector3.new(3, 0.15, 1.6) * s, CFrame.new(-2 * s, 2.7 * s, 0) * CFrame.Angles(0, 0, 0.35), dark, nil, false)
		newPart(m, "WingR", Vector3.new(3, 0.15, 1.6) * s, CFrame.new(2 * s, 2.7 * s, 0) * CFrame.Angles(0, 0, -0.35), dark, nil, false)
		newPart(m, "Tail", Vector3.new(0.4, 0.4, 1.2) * s, CFrame.new(0, 2.1 * s, 1.4 * s), dark, nil, false)
		m.WorldPivot = CFrame.new()
		return m, Models.AddHealthBar(m, fhead, 1.2 * s, 48)
	end

	newPart(m, "LegL", Vector3.new(0.7, 1.2, 0.7) * s, CFrame.new(-0.5 * s, 0.6 * s, 0), dark, nil, false)
	newPart(m, "LegR", Vector3.new(0.7, 1.2, 0.7) * s, CFrame.new(0.5 * s, 0.6 * s, 0), dark, nil, false)
	newPart(m, "Torso", Vector3.new(1.8, 1.8, 1) * s, CFrame.new(0, 2.1 * s, 0), col, nil, false)
	local head = newPart(m, "Head", Vector3.new(1.3, 1.3, 1.3) * s, CFrame.new(0, 3.65 * s, 0), light, nil, false)
	newPart(m, "ArmL", Vector3.new(0.5, 1.5, 0.5) * s, CFrame.new(-1.2 * s, 2.2 * s, 0), dark, nil, false)
	newPart(m, "ArmR", Vector3.new(0.5, 1.5, 0.5) * s, CFrame.new(1.2 * s, 2.2 * s, 0), dark, nil, false)
	newPart(m, "EyeL", Vector3.new(0.25, 0.25, 0.1) * s, CFrame.new(-0.3 * s, 3.75 * s, -0.68 * s), Color3.new(0, 0, 0), nil, false)
	newPart(m, "EyeR", Vector3.new(0.25, 0.25, 0.1) * s, CFrame.new(0.3 * s, 3.75 * s, -0.68 * s), Color3.new(0, 0, 0), nil, false)

	if def.Style == "Bomber" then
		newPart(m, "Strap", Vector3.new(1.9, 0.3, 1.1) * s, CFrame.new(0, 2.5 * s, 0), Color3.fromRGB(40, 30, 20), nil, false)
		local bomb = newPart(m, "Bomb", Vector3.new(1.5, 1.5, 1.5) * s, CFrame.new(0, 2.3 * s, 0.95 * s), Color3.fromRGB(20, 20, 20), Enum.Material.Metal, false)
		bomb.Shape = Enum.PartType.Ball
		newPart(m, "Fuse", Vector3.new(0.18, 0.7, 0.18) * s, CFrame.new(0, 3.2 * s, 0.95 * s), Color3.fromRGB(255, 160, 40), Enum.Material.Neon, false)
	end

	if def.Style == "Climber" then
		newPart(m, "Ladder", Vector3.new(0.4, 3.2, 0.9) * s, CFrame.new(0, 2.4 * s, 0.75 * s), Color3.fromRGB(130, 90, 50), Enum.Material.Wood, false)
		newPart(m, "HookL", Vector3.new(0.25, 1.1, 0.25) * s, CFrame.new(-1.25 * s, 3.3 * s, -0.1 * s), Color3.fromRGB(210, 210, 220), Enum.Material.Metal, false)
		newPart(m, "HookR", Vector3.new(0.25, 1.1, 0.25) * s, CFrame.new(1.25 * s, 3.3 * s, -0.1 * s), Color3.fromRGB(210, 210, 220), Enum.Material.Metal, false)
	end

	if def.Style == "Swimmer" then
		local finColor = Color3.fromRGB(70, 200, 210)
		newPart(m, "Fin", Vector3.new(0.25, 1.2, 1.1) * s, CFrame.new(0, 3.3 * s, 0.35 * s), finColor, nil, false)
		newPart(m, "HeadFin", Vector3.new(0.2, 0.6, 0.7) * s, CFrame.new(0, 4.5 * s, 0.1 * s), finColor, nil, false)
		newPart(m, "Tail", Vector3.new(0.7, 0.5, 1.6) * s, CFrame.new(0, 1.4 * s, 1.2 * s), dark, nil, false)
		newPart(m, "TailFin", Vector3.new(1.4, 0.15, 0.6) * s, CFrame.new(0, 1.4 * s, 2.1 * s), finColor, nil, false)
	end

	m.WorldPivot = CFrame.new()
	local bar = Models.AddHealthBar(m, head, 1.3 * s, 52)
	return m, bar
end

-- Builder worker (built around the origin at ground level, front faces -Z; move with PivotTo)
function Models.Builder()
	local m = Instance.new("Model")
	m.Name = "Builder"
	local skin = Color3.fromRGB(235, 190, 150)
	local yellow = Color3.fromRGB(255, 210, 40)
	newPart(m, "LegL", Vector3.new(0.45, 0.9, 0.45), CFrame.new(-0.3, 0.45, 0), Color3.fromRGB(50, 70, 120), nil, false)
	newPart(m, "LegR", Vector3.new(0.45, 0.9, 0.45), CFrame.new(0.3, 0.45, 0), Color3.fromRGB(50, 70, 120), nil, false)
	newPart(m, "Torso", Vector3.new(1.2, 1.1, 0.7), CFrame.new(0, 1.45, 0), Color3.fromRGB(255, 140, 30), nil, false)
	newPart(m, "Stripe", Vector3.new(1.22, 0.15, 0.72), CFrame.new(0, 1.55, 0), Color3.fromRGB(230, 230, 230), Enum.Material.Neon, false)
	local head = newPart(m, "Head", Vector3.new(0.8, 0.8, 0.8), CFrame.new(0, 2.4, 0), skin, nil, false)
	newPart(m, "Hat", Vector3.new(0.95, 0.35, 0.95), CFrame.new(0, 2.92, 0), yellow, nil, false)
	newPart(m, "HatBrim", Vector3.new(1.05, 0.1, 1.2), CFrame.new(0, 2.76, -0.1), yellow, nil, false)
	newPart(m, "EyeL", Vector3.new(0.14, 0.14, 0.05), CFrame.new(-0.17, 2.45, -0.42), Color3.new(0, 0, 0), nil, false)
	newPart(m, "EyeR", Vector3.new(0.14, 0.14, 0.05), CFrame.new(0.17, 2.45, -0.42), Color3.new(0, 0, 0), nil, false)
	newPart(m, "Handle", Vector3.new(0.16, 1.1, 0.16), CFrame.new(0.78, 1.45, -0.3), Color3.fromRGB(120, 80, 40), Enum.Material.Wood, false)
	newPart(m, "HammerHead", Vector3.new(0.5, 0.3, 0.3), CFrame.new(0.78, 2.0, -0.3), Color3.fromRGB(110, 110, 120), Enum.Material.Metal, false)
	m.WorldPivot = CFrame.new()
	local bar = Models.AddHealthBar(m, head, 1.4, 30)
	return m, bar
end

-- The city castle (center = middle of the 3x3 city area, at tile-surface height)
function Models.City(center)
	local m = Instance.new("Model")
	m.Name = "City"
	local function at(x, y, z) return CFrame.new(center + Vector3.new(x, y, z)) end
	local stone = Color3.fromRGB(175, 175, 185)
	local darkStone = Color3.fromRGB(125, 125, 138)

	m.PrimaryPart = newPart(m, "Floor", Vector3.new(12, 0.6, 12), at(0, 0.3, 0), Color3.fromRGB(120, 120, 132), Enum.Material.Cobblestone)

	-- outer walls
	newPart(m, "WallN", Vector3.new(12, 3, 1), at(0, 1.5, -5.5), stone, Enum.Material.Brick)
	newPart(m, "WallS", Vector3.new(12, 3, 1), at(0, 1.5, 5.5), stone, Enum.Material.Brick)
	newPart(m, "WallW", Vector3.new(1, 3, 12), at(-5.5, 1.5, 0), stone, Enum.Material.Brick)
	newPart(m, "WallE", Vector3.new(1, 3, 12), at(5.5, 1.5, 0), stone, Enum.Material.Brick)

	-- corner towers with red roofs
	for _, cx in ipairs({ -5, 5 }) do
		for _, cz in ipairs({ -5, 5 }) do
			newCylinder(m, "Tower", 8, 3, center + Vector3.new(cx, 4, cz), darkStone, Enum.Material.Brick)
			newPart(m, "Roof", Vector3.new(3.6, 1.2, 3.6), at(cx, 8.6, cz), Color3.fromRGB(190, 55, 55), nil)
		end
	end

	-- keep
	newPart(m, "Keep", Vector3.new(5, 7, 5), at(0, 3.5, 0), stone, Enum.Material.Brick)
	newPart(m, "KeepRoof", Vector3.new(6, 1.2, 6), at(0, 7.6, 0), Color3.fromRGB(190, 55, 55), nil)
	newPart(m, "Door", Vector3.new(1.8, 2.8, 0.3), at(0, 1.4, -2.6), Color3.fromRGB(80, 50, 30), Enum.Material.Wood, false)
	newPart(m, "Pole", Vector3.new(0.25, 4, 0.25), at(0, 10.2, 0), Color3.fromRGB(60, 60, 60), nil, false)
	newPart(m, "Flag", Vector3.new(2, 1.2, 0.1), at(1.1, 11.4, 0), Color3.fromRGB(70, 130, 255), nil, false)
	return m
end

-- Dungeon portal: a stone arch with a glowing cyan swirl (pos = ground centre)
function Models.DungeonPortal(pos)
	local m = Instance.new("Model")
	m.Name = "DungeonPortal"
	local stone = Color3.fromRGB(80, 75, 95)
	newPart(m, "PillarL", Vector3.new(0.9, 6, 0.9), CFrame.new(pos + Vector3.new(-2.2, 3, 0)), stone, Enum.Material.Slate)
	newPart(m, "PillarR", Vector3.new(0.9, 6, 0.9), CFrame.new(pos + Vector3.new(2.2, 3, 0)), stone, Enum.Material.Slate)
	newPart(m, "Top", Vector3.new(5.6, 0.9, 1.1), CFrame.new(pos + Vector3.new(0, 6.3, 0)), stone, Enum.Material.Slate)
	local swirl = newPart(m, "Swirl", Vector3.new(0.3, 4.6, 4.6), CFrame.new(pos + Vector3.new(0, 3.1, 0)) * CFrame.Angles(0, math.pi / 2, 0),
		Color3.fromRGB(90, 220, 255), Enum.Material.Neon, false)
	swirl.Shape = Enum.PartType.Cylinder
	swirl.Transparency = 0.15
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(90, 220, 255)
	light.Range = 16
	light.Brightness = 2
	light.Parent = swirl
	m.PrimaryPart = swirl
	return m
end

-- Enemy spawn gate (purple portal on the ground)
function Models.Portal(pos)
	local m = Instance.new("Model")
	m.Name = "SpawnGate"
	newCylinder(m, "Ring", 0.3, 6.5, pos + Vector3.new(0, 0.15, 0), Color3.fromRGB(170, 70, 255), Enum.Material.Neon, false)
	local inner = newCylinder(m, "Inner", 0.4, 4.5, pos + Vector3.new(0, 0.25, 0), Color3.fromRGB(25, 10, 40), nil, false)
	local light = Instance.new("PointLight")
	light.Color = Color3.fromRGB(170, 70, 255)
	light.Range = 14
	light.Brightness = 2
	light.Parent = inner
	return m
end

-- Effects
function Models.Beam(a, b, color, width)
	local d = (b - a).Magnitude
	if d < 0.1 then return end
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 240, 150)
	p.Size = Vector3.new(width or 0.25, width or 0.25, d)
	p.CFrame = CFrame.lookAt(a, b) * CFrame.new(0, 0, -d / 2)
	p.Parent = workspace
	Debris:AddItem(p, 0.1)
end

function Models.Boom(pos, radius, color)
	local p = Instance.new("Part")
	p.Shape = Enum.PartType.Ball
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Material = Enum.Material.Neon
	p.Color = color or Color3.fromRGB(255, 150, 50)
	p.Transparency = 0.3
	p.Size = Vector3.new(0.5, 0.5, 0.5)
	p.Position = pos
	p.Parent = workspace
	TweenService:Create(p, TweenInfo.new(0.25), { Size = Vector3.new(radius * 2, radius * 2, radius * 2), Transparency = 1 }):Play()
	Debris:AddItem(p, 0.3)
end

-- a little floating status text over a model (e.g. STUNNED), removed after `duration` seconds
function Models.StatusMark(model, name, text, color, duration)
	local adornee = model.PrimaryPart or model:FindFirstChild("Head") or model:FindFirstChildWhichIsA("BasePart")
	if not adornee then return end
	local old = model:FindFirstChild(name)
	if old then old:Destroy() end
	local gui = Instance.new("BillboardGui")
	gui.Name = name
	gui.Adornee = adornee
	gui.Size = UDim2.fromOffset(90, 22)
	gui.StudsOffset = Vector3.new(0, 5, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 200
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 14
	label.TextColor3 = color
	label.TextStrokeTransparency = 0.2
	label.Text = text
	label.Parent = gui
	gui.Parent = model
	Debris:AddItem(gui, duration)
end

-- spear stab: a quick bright streak along the stab line
function Models.Thrust(from, dir, length)
	local tip = from + dir * length
	Models.Beam(from, tip, Color3.fromRGB(225, 240, 255), 0.35)
	Models.Boom(tip, 1.1, Color3.fromRGB(210, 230, 255))
end

-- club sweep: a curved slash that sweeps from one side to the other
function Models.Sweep(center, face, radius, angleDeg, color)
	local half = math.rad(angleDeg / 2)
	local steps = 8
	local segLen = radius * (2 * half / steps) * 1.15
	task.spawn(function()
		for k = 0, steps do
			local a = half - (2 * half) * k / steps
			local dir = CFrame.Angles(0, a, 0):VectorToWorldSpace(face)
			local pos = center + dir * radius * 0.85
			local tangent = Vector3.new(dir.Z, 0, -dir.X)
			local p = Instance.new("Part")
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.Material = Enum.Material.Neon
			p.Color = color or Color3.fromRGB(255, 200, 120)
			p.Transparency = 0.15
			p.Size = Vector3.new(0.35, 0.7, segLen)
			p.CFrame = CFrame.lookAt(pos, pos + tangent)
			p.Parent = workspace
			TweenService:Create(p, TweenInfo.new(0.3), { Transparency = 1, Size = Vector3.new(0.1, 0.2, segLen) }):Play()
			Debris:AddItem(p, 0.35)
			task.wait(0.012)
		end
	end)
end

-- the trade truck (built around the origin at ground level, front faces -Z)
function Models.Truck()
	local m = Instance.new("Model")
	m.Name = "TradeTruck"
	local function at(x, y, z) return CFrame.new(x, y, z) end
	newPart(m, "Chassis", Vector3.new(2.6, 0.5, 5.6), at(0, 1.1, 0), Color3.fromRGB(60, 60, 70), Enum.Material.Metal, false)
	newPart(m, "Cab", Vector3.new(2.4, 2, 1.8), at(0, 2.35, -1.9), Color3.fromRGB(50, 110, 200), nil, false)
	newPart(m, "Window", Vector3.new(2, 0.8, 0.1), at(0, 2.7, -2.82), Color3.fromRGB(170, 220, 255), Enum.Material.Glass, false)
	local cargo = newPart(m, "Cargo", Vector3.new(2.6, 2.4, 3.2), at(0, 2.55, 1.0), Color3.fromRGB(150, 105, 60), Enum.Material.WoodPlanks, false)
	newPart(m, "Stripe", Vector3.new(2.7, 0.35, 3.3), at(0, 3.5, 1.0), Color3.fromRGB(255, 205, 60), Enum.Material.Neon, false)
	for _, x in ipairs({ -1.35, 1.35 }) do
		for _, z in ipairs({ -1.9, 1.5 }) do
			local w = newPart(m, "Wheel", Vector3.new(0.6, 1.3, 1.3), at(x, 0.65, z), Color3.fromRGB(25, 25, 25), nil, false)
			w.Shape = Enum.PartType.Cylinder
		end
	end
	m.WorldPivot = CFrame.new()

	local bar = Models.AddHealthBar(m, cargo, 3.4, 80)

	local gui = Instance.new("BillboardGui")
	gui.Name = "TruckLabel"
	gui.Adornee = cargo
	gui.Size = UDim2.fromOffset(140, 20)
	gui.StudsOffset = Vector3.new(0, 4.7, 0)
	gui.MaxDistance = 220
	gui.Parent = m
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "TRADE TRUCK"
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 14
	label.TextColor3 = Color3.fromRGB(255, 215, 70)
	label.TextStrokeTransparency = 0.4
	label.Parent = gui

	return m, bar
end

-- sign marking where the trade route begins
function Models.RouteSign(pos)
	local m = Instance.new("Model")
	m.Name = "TradeRouteSign"
	newPart(m, "Post", Vector3.new(0.4, 6, 0.4), CFrame.new(pos + Vector3.new(0, 3, 0)), Color3.fromRGB(110, 75, 45), Enum.Material.Wood, false)
	local board = newPart(m, "Board", Vector3.new(4, 1.4, 0.3), CFrame.new(pos + Vector3.new(0, 6.2, 0)), Color3.fromRGB(235, 200, 90), Enum.Material.Wood, false)
	local gui = Instance.new("BillboardGui")
	gui.Adornee = board
	gui.Size = UDim2.fromOffset(160, 28)
	gui.StudsOffset = Vector3.new(0, 2, 0)
	gui.AlwaysOnTop = true
	gui.MaxDistance = 400
	gui.Parent = m
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = "TRADE ROUTE"
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 18
	label.TextColor3 = Color3.fromRGB(255, 225, 90)
	label.TextStrokeTransparency = 0.2
	label.Parent = gui
	return m
end

-- floating text that rises and fades (e.g. "+$30")
function Models.Popup(pos, text, color)
	local anchor = Instance.new("Part")
	anchor.Anchored = true
	anchor.CanCollide = false
	anchor.CanQuery = false
	anchor.CanTouch = false
	anchor.Transparency = 1
	anchor.Size = Vector3.new(0.2, 0.2, 0.2)
	anchor.Position = pos
	anchor.Parent = workspace

	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(120, 36)
	gui.AlwaysOnTop = true
	gui.Adornee = anchor
	gui.Parent = anchor

	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Text = text
	label.Font = Enum.Font.GothamBlack
	label.TextSize = 24
	label.TextColor3 = color or Color3.fromRGB(255, 225, 90)
	label.TextStrokeTransparency = 0.3
	label.Parent = gui

	TweenService:Create(anchor, TweenInfo.new(1.4), { Position = pos + Vector3.new(0, 5, 0) }):Play()
	TweenService:Create(label, TweenInfo.new(1.4, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { TextTransparency = 1, TextStrokeTransparency = 1 }):Play()
	Debris:AddItem(anchor, 1.5)
end

return Models
