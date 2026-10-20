-- Shared configuration for the city defense game
local Config = {}

-- Grid
Config.GridW = 25
Config.GridH = 25
Config.Cell = 4        -- studs per cell
Config.TileTop = 1     -- y of the tile surface

Config.City = { MinI = 12, MaxI = 14, MinJ = 23, MaxJ = 25 }
Config.Spawns = { { 4, 1 }, { 13, 1 }, { 22, 1 } }

-- Economy / pacing
Config.StartCoins = 400
Config.StartWave = 1     -- dev knob: set higher to jump ahead to later waves when testing
Config.CityHP = 100
Config.FirstBuildTime = 45
Config.BuildTime = 25
Config.WaveBonus = 60
Config.SellRefund = 0.7
Config.MudCost = 3     -- pathfinding cost of mud (grass = 1)
Config.MudSlow = 0.5   -- speed multiplier on mud

-- Things players can place (order = hotbar order)
Config.Items = {
	{ Id = "Wall", Name = "Wall", Kind = "Wall", Cost = 10, Blocks = true, HP = 120,
		Color = Color3.fromRGB(110, 110, 125),
		Desc = "Blocks enemies. Ground enemies detour or smash through it; climbers go over, flyers ignore it." },
	{ Id = "Spikes", Name = "Spikes", Kind = "Trap", Cost = 25, Blocks = false, Damage = 10, Interval = 0.6,
		Color = Color3.fromRGB(120, 120, 130),
		Desc = "Trap: hurts enemies walking over it." },
	{ Id = "Fire", Name = "Fire Trap", Kind = "Trap", Cost = 60, Blocks = false, Damage = 18, Interval = 0.4,
		Color = Color3.fromRGB(200, 90, 30),
		Desc = "Trap: burns enemies walking over it. High damage." },
	{ Id = "Arrow", Name = "Arrow Tower", Kind = "Tower", Cost = 100, Blocks = true, Range = 5, Damage = 14, Interval = 0.6,
		Color = Color3.fromRGB(150, 110, 70),
		Desc = "Tower: fast shots at enemies in range. Enemies that can't get around will attack it." },
	{ Id = "Cannon", Name = "Cannon", Kind = "Tower", Cost = 250, Blocks = true, Range = 6.5, Damage = 55, Interval = 2.2, Splash = 1.5,
		Color = Color3.fromRGB(60, 60, 70),
		Desc = "Tower: slow, long range, splash damage." },
	{ Id = "Goblin", Name = "Goblin Guard", Kind = "Monster", Cost = 80, Blocks = true, HP = 160, Damage = 12, Interval = 1, Range = 1.6,
		Color = Color3.fromRGB(80, 160, 70),
		Desc = "Monster: melee guard. Enemies fight back, so it can die." },
	{ Id = "Ogre", Name = "Ogre", Kind = "Monster", Cost = 220, Blocks = true, HP = 700, Damage = 40, Interval = 1.6, Range = 1.8,
		Color = Color3.fromRGB(170, 105, 60),
		Desc = "Monster: big tanky bruiser with heavy hits." },
	{ Id = "Farm", Name = "Farm", Kind = "Farm", Cost = 120, Blocks = true, HP = 100, Income = 30, Bonus = 10, MaxBonusWaves = 4,
		Color = Color3.fromRGB(200, 160, 60),
		Desc = "Pays you after every cleared wave: $30, +$10 per wave it survives (max $70). Solid; bombers will target it." },
	{ Id = "Mud", Name = "Mud", Kind = "Terrain", Cost = 15, Blocks = false, TerrainType = "Mud",
		Color = Color3.fromRGB(120, 84, 50),
		Desc = "Terrain: slows enemies by half. They avoid it if there's a similar route." },
	{ Id = "Water", Name = "Water", Kind = "Terrain", Cost = 25, Blocks = true, TerrainType = "Water",
		Color = Color3.fromRGB(50, 120, 210),
		Desc = "Terrain: most enemies can't cross it. Climbers go over it, and Swimmers get stronger in it!" },
}

Config.ItemsById = {}
Config.TerrainDefs = {}
for _, item in ipairs(Config.Items) do
	Config.ItemsById[item.Id] = item
	if item.TerrainType then
		Config.TerrainDefs[item.TerrainType] = item
	end
end

-- Construction: everything takes time to build, and a builder has to walk to the site and stay there
-- while it's being built. Times are in seconds.
Config.Builders = 3       -- builders you start with (and the most you can have)
Config.BuilderHits = 2    -- enemy hits that kill a builder
Config.BuilderSpeed = 8   -- builder walking speed (studs/second)
-- you get 1 new builder after each cleared wave (up to Config.Builders)
-- (units - Goblin Guards and Ogres - don't need building: they appear right away)
local buildTimes = { Wall = 2, Spikes = 2, Fire = 3, Arrow = 5, Cannon = 9, Farm = 6, Mud = 1.5, Water = 3 }
for id, t in pairs(buildTimes) do Config.ItemsById[id].BuildTime = t end

-- One-line descriptions for the build bar tooltip
local shortDesc = {
	Wall = "Cheap block. Ground enemies must break it; climbers go over.",
	Spikes = "Trap. Hurts ground enemies walking over it.",
	Fire = "Trap. Burns ground enemies hard.",
	Arrow = "Tower. Fast shots at one enemy at a time.",
	Cannon = "Tower. Slow, long range, hits groups with splash damage.",
	Goblin = "Unit. Spear guard: stabs every enemy in a line up to 2.5 tiles ahead.",
	Ogre = "Unit. Tanky bruiser: swings his club in a wide arc, hitting every enemy in front.",
	Farm = "Earns coins after every wave. Bombers love to target it.",
	Mud = "Slows enemies walking through it by half.",
	Water = "Most enemies can't cross it. Climbers go over, Swimmers get stronger in it.",
}
for id, text in pairs(shortDesc) do Config.ItemsById[id].Short = text end

-- How units attack
--   Spear: hits every enemy in a straight line in front, up to Range tiles (SpearWidth = half-width in tiles)
--   Sweep: hits every enemy within Range tiles inside a wide arc in front (SweepAngle in degrees)
local goblin, ogre = Config.ItemsById.Goblin, Config.ItemsById.Ogre
goblin.Attack, goblin.Range, goblin.SpearWidth = "Spear", 2.5, 0.45
ogre.Attack, ogre.Range, ogre.SweepAngle = "Sweep", 1.8, 150

-- Units you can move: walking speed in studs/second
Config.ItemsById.Goblin.WalkSpeed = 7
Config.ItemsById.Ogre.WalkSpeed = 5
Config.ItemsById.Goblin.Desc = "Unit: melee guard. Click it, then click a tile to walk there. Enemies fight back."
Config.ItemsById.Ogre.Desc = "Unit: big tanky bruiser with heavy hits. Click it, then click a tile to walk there."

-- Enemies (Speed in studs/second, 4 studs = 1 cell)
Config.Enemies = {
	Grunt  = { Name = "Grunt",  HP = 60,   Speed = 6,  Reward = 8,   CityDamage = 4,  AtkDamage = 4,  AtkInterval = 1.0, Scale = 1.0, Color = Color3.fromRGB(190, 70, 70) },
	Runner = { Name = "Runner", HP = 35,   Speed = 11, Reward = 10,  CityDamage = 3,  AtkDamage = 2,  AtkInterval = 1.0, Scale = 0.8, Color = Color3.fromRGB(240, 190, 60) },
	Tank   = { Name = "Tank",   HP = 320,  Speed = 3.5, Reward = 30, CityDamage = 12, AtkDamage = 15, AtkInterval = 1.2, Scale = 1.5, Color = Color3.fromRGB(90, 100, 140) },
	Boss   = { Name = "Boss",   HP = 2500, Speed = 3,  Reward = 250, CityDamage = 40, AtkDamage = 40, AtkInterval = 1.5, Scale = 2.6, Color = Color3.fromRGB(130, 50, 170) },
}

-- Movement behaviour -------------------------------------------------
-- Move: "ground" (blocked by walls it must break), "climb" (walks over walls), "fly" (ignores everything)
for _, e in pairs(Config.Enemies) do e.Move = "ground" end
Config.Enemies.Grunt.BreakDamage = 10   -- damage per hit vs walls
Config.Enemies.Runner.BreakDamage = 5
Config.Enemies.Tank.BreakDamage = 40
Config.Enemies.Boss.BreakDamage = 150

Config.Enemies.Climber = {
	Name = "Climber", Move = "climb", Style = "Climber", HP = 90, Speed = 6.5, Reward = 14, CityDamage = 6,
	AtkDamage = 5, AtkInterval = 1.0, Scale = 0.9, Color = Color3.fromRGB(60, 170, 170),
}
Config.Enemies.Flyer = {
	Name = "Flyer", Move = "fly", Style = "Flyer", Flying = true, FlyHeight = 6, HP = 50, Speed = 8, Reward = 12,
	CityDamage = 5, AtkDamage = 0, AtkInterval = 1.0, Scale = 0.9, Color = Color3.fromRGB(110, 60, 150),
}

Config.Enemies.Bomber = {
	Name = "Bomber", Move = "bomb", Style = "Bomber", HP = 40, Speed = 11, Reward = 15, CityDamage = 8,
	AtkDamage = 0, AtkInterval = 999, BreakDamage = 0, Scale = 0.85, Color = Color3.fromRGB(230, 90, 40),
	Fuse = 1.2,          -- seconds spent next to a wall before self-destructing
	BlastRadius = 1.8,   -- cells
	BlastDamage = 200,   -- damage to walls at the centre (falls off to half at the edge; guards take half)
}

Config.Enemies.Climber.BreakDamage = 8

-- Swimmer: walks through water. Every water tile it enters heals it and raises its max HP,
-- and while in water (and a few seconds after) it moves faster and hits harder.
Config.Enemies.Swimmer = {
	Name = "Swimmer", Move = "swim", Style = "Swimmer", HP = 85, Speed = 5.5, Reward = 15, CityDamage = 6,
	AtkDamage = 6, AtkInterval = 1.0, BreakDamage = 12, Scale = 1.0, Color = Color3.fromRGB(35, 95, 170),
	WaterHeal = 0.25,      -- heals this fraction of its max HP per water tile
	WaterHPGain = 0.12,    -- +12% max HP per water tile...
	WaterHPCap = 2,        -- ...up to 2x its starting HP
	BuffTime = 5,          -- seconds the speed/attack boost lasts after leaving water
	BuffSpeed = 1.5,
	BuffAttack = 1.6,
}

-- durability of defenses (so bombers can destroy them)
Config.ItemsById.Spikes.HP = 60
Config.ItemsById.Fire.HP = 60
Config.ItemsById.Arrow.HP = 150
Config.ItemsById.Cannon.HP = 250

-- Trade route event: a road appears and a truck rolls to the city
Config.Trade = {
	MinGap = 2, MaxGap = 4,                 -- waves between trade routes
	Hits = 3,           -- enemy hits before the truck is destroyed (flyers can't hit it)
	Speed = 2.5,                              -- truck speed (studs/second)
	BaseReward = 250, RewardPerWave = 40,   -- paid to EVERY player when the truck arrives
	MinPayout = 0.5,                        -- fraction of the payout if it arrives with almost no health
	RiskBonus = 0.5,                        -- up to +50% payout for the most dangerous roads
}

Config.WallBreakCost = 6   -- extra path cost for ground enemies to go through a wall (they detour up to ~6 cells)
Config.BuildingBreakCost = 8   -- extra path cost to break through a tower/guard/farm (enemies prefer to go around)
Config.SwimWaterCost = 0.6     -- swimmers like water: it's cheaper for them than grass
Config.WallClimbCost = 1   -- extra path cost for climbers
Config.ClimbSlow = 0.6     -- speed multiplier while climbing a wall
Config.WallTopLift = 4.7   -- how high climbers rise when on a wall

-- Difficulty ----------------------------------------------------------
Config.Difficulty = {
	HPPerWave = 0.15,  -- enemy HP grows +15% per wave
	CountMul = 1.25,   -- multiplier on the number of grunts per wave
}

-- Random wave events --------------------------------------------------
-- How many events hit during a wave
function Config.EventCount(wave)
	if wave < 2 then return 0 end
	if wave < 5 then return 1 end
	if wave < 8 then return math.random(1, 2) end
	if wave < 12 then return 2 end
	return math.random(2, 3)
end

-- Weight = how likely it is to be picked, MinWave = first wave it can appear,
-- Duration = how long it lasts (and how long it shows on screen)
Config.Events = {
	-- bad
	{ Id = "Meteor",    Name = "Meteor Shower",   Weight = 10, MinWave = 2, Duration = 10, Desc = "Meteors are raining down and smashing buildings!" },
	{ Id = "Ambush",    Name = "Ambush!",         Weight = 10, MinWave = 3, Duration = 8,  Desc = "A new portal ripped open on the side of the map." },
	{ Id = "Stampede",  Name = "Stampede",        Weight = 8,  MinWave = 3, Duration = 6,  Desc = "A pack of runners charges out of the gates." },
	{ Id = "Fog",       Name = "Thick Fog",       Weight = 8,  MinWave = 3, Duration = 18, Desc = "Towers can barely see: -40% range." },
	{ Id = "Sabotage",  Name = "Sabotage",        Weight = 7,  MinWave = 3, Duration = 10, Desc = "Saboteurs jammed some of your towers!" },
	{ Id = "BloodMoon", Name = "Blood Moon",      Weight = 8,  MinWave = 4, Duration = 15, Desc = "Enemies are enraged: +40% speed, +50% damage." },
	{ Id = "Quake",     Name = "Earthquake",      Weight = 6,  MinWave = 4, Duration = 6,  Desc = "The ground shakes - every building takes damage." },
	{ Id = "Champion",  Name = "Champion",        Weight = 7,  MinWave = 4, Duration = 8,  Desc = "A golden champion joins the attack. 5x HP, big reward." },
	{ Id = "Burrow",    Name = "Tunnelers",       Weight = 7,  MinWave = 5, Duration = 8,  Desc = "Enemies are digging up in the middle of your maze!" },
	{ Id = "Lightning", Name = "Lightning Storm", Weight = 6,  MinWave = 6, Duration = 12, Desc = "Lightning strikes enemies and buildings alike." },
	{ Id = "AirRaid",   Name = "Air Raid",        Weight = 5,  MinWave = 7, Duration = 8,  Desc = "A flock of flyers ignores your walls." },
	-- good (rarer, the game is meant to be hard)
	{ Id = "GoldRush",  Name = "Gold Rush",       Weight = 4,  MinWave = 2, Duration = 15, Good = true, Desc = "Kills pay double coins!" },
	{ Id = "Supply",    Name = "Supply Drop",     Weight = 3,  MinWave = 2, Duration = 6,  Good = true, Desc = "The city sends coins to every defender." },
	{ Id = "Overcharge",Name = "Overcharge",      Weight = 4,  MinWave = 3, Duration = 12, Good = true, Desc = "Towers fire twice as fast!" },
}

-- Unit abilities: select units, then Q / E (normal) and R (ultimate). Distances are in tiles,
-- Damage is a multiplier on the unit's normal hit, Cooldown in seconds.
Config.Abilities = {
	Ogre = {
		Q = { Id = "Slide", Name = "Spin Slide", Cooldown = 8, Distance = 5, Speed = 16, Damage = 0.7,
			Desc = "Spins and slides toward your mouse like an ice cube, hitting everything around him the whole way." },
		E = { Id = "Slam", Name = "Ground Slam", Cooldown = 12, Radius = 2.6, Damage = 3, Stun = 2.5,
			Desc = "A huge hit that damages every enemy around him and stuns them for 2.5 seconds." },
		R = { Id = "Heal", Name = "Second Wind", Cooldown = 45, Ultimate = true,
			Desc = "ULTIMATE: heals him back to full health." },
	},
	Goblin = {
		Q = { Id = "Shield", Name = "Shield Up", Cooldown = 14, Duration = 6, Reduce = 0.6,
			Desc = "Takes 60% less damage for 6 seconds." },
		E = { Id = "Long", Name = "Long Spear", Cooldown = 14, Duration = 8, Range = 1.8, Damage = 1.6,
			Desc = "+80% attack range and +60% damage for 8 seconds." },
		R = { Id = "Charge", Name = "Charge", Cooldown = 40, Distance = 6, Speed = 22, Damage = 4, Push = 7, Ultimate = true,
			Desc = "ULTIMATE: rushes toward your mouse, damaging and knocking away every enemy in his path." },
	},
}

-- Long waves + dungeon -------------------------------------------------
Config.WaveLength = 60       -- seconds a wave's enemies are spread over (+4s per wave)
Config.Portal = { 17, 24 }   -- tile where the dungeon portal opens after wave 1 (right of the city)
Config.Dungeon = {
	BaseRooms = 4,             -- fighting rooms on floor 1 (+1 per deeper floor)
	AggroTiles = 6,            -- units notice enemies this many tiles away
	ReviveCost = 0.5,          -- reviving a fallen unit costs this share of its price (coins)
	ReviveHP = 0.5,            -- revived units come back with this much health
	KillReduces = 1,           -- each dungeon kill removes this many enemies from the next wave...
	MaxWaveReduction = 0.5,    -- ...but never more than half of the wave
	FinalFloor = 4,            -- after clearing 3 floors, floor 4 has the final boss in its last room - beat it to win
}

-- Upgrades bought with dungeon crystals (Per = bonus per level)
Config.Upgrades = {
	{ Id = "Towers", Name = "Sharper Arrows", Desc = "Towers deal +20% damage per level.", Per = 0.2, Max = 5 },
	{ Id = "Traps",  Name = "Hotter Traps",   Desc = "Traps deal +25% damage per level.", Per = 0.25, Max = 5 },
	{ Id = "Walls",  Name = "Stone Masons",   Desc = "Walls, towers, traps and farms get +25% health per level.", Per = 0.25, Max = 5 },
	{ Id = "Units",  Name = "Veteran Units",  Desc = "Goblins and Ogres get +20% damage and health per level.", Per = 0.2, Max = 5 },
}
-- Buffs from beating the Warlord in a dungeon side room (last the rest of the match, one of each)
Config.Buffs = {
	{ Id = "Might",    Name = "Warlord's Might", Desc = "Goblins and Ogres deal +50% damage and have +50% health." },
	{ Id = "Eagle",    Name = "Eagle Eye",       Desc = "Towers get +30% range and +25% damage." },
	{ Id = "Fortress", Name = "Fortress",        Desc = "The city gets +50 max health (and heals up); buildings get +40% health." },
	{ Id = "Hands",    Name = "Quick Hands",     Desc = "Builders walk 50% faster and build twice as fast." },
}

-- crystals needed to go from `level` to the next one
function Config.UpgradeCost(level)
	return 3 + level * 2
end

function Config.IsCity(i, j)
	local c = Config.City
	return i >= c.MinI and i <= c.MaxI and j >= c.MinJ and j <= c.MaxJ
end

function Config.IsSpawn(i, j)
	for _, s in ipairs(Config.Spawns) do
		if s[1] == i and s[2] == j then return true end
	end
	return false
end

return Config
