--!strict
-- Builds the whole world from code when the server starts: lobby island, the two shores,
-- the shallow ocean in between, gates, shark barriers, reef obstacles and lighting.
-- No models or decals are needed, so the place works as soon as it's opened.

local Lighting = game:GetService("Lighting")
local PhysicsService = game:GetService("PhysicsService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

local MapBuilder = {}

local HALF_L = Config.ArenaHalfLength
local HALF_W = Config.ArenaHalfWidth
local SAFE = Config.SafeLine

local SAND = Color3.fromRGB(236, 214, 160)
local WET_SAND = Color3.fromRGB(196, 170, 120)
local WATER = Color3.fromRGB(40, 170, 205)
local SEABED = Color3.fromRGB(70, 130, 140)

export type Map = {
	Folder: Folder,
	Gates: { BasePart },
	LobbySpawn: SpawnLocation,
}

local function part(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		if k ~= "Parent" then
			(p :: any)[k] = v
		end
	end
	p.Parent = props.Parent
	return p
end

local function invisibleWall(parent: Instance, name: string, cf: CFrame, size: Vector3, group: string?): Part
	return part({
		Name = name, CFrame = cf, Size = size, Transparency = 1, CanQuery = false, CanTouch = false,
		CollisionGroup = group or "Default", Parent = parent,
	})
end

local function sign(parent: Instance, cf: CFrame, size: Vector3, text: string, color: Color3, face: Enum.NormalId?): Part
	local board = part({
		Name = "Sign", CFrame = cf, Size = size, Color = Color3.fromRGB(60, 40, 30), Material = Enum.Material.Wood, Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = face or Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 40
	gui.LightInfluence = 0.2
	gui.Parent = board
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.Text = text
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.fromRGB(20, 20, 30)
	stroke.Parent = label
	label.Parent = gui
	return board
end

local function floorText(parent: Instance, cf: CFrame, size: Vector2, text: string, color: Color3)
	local p = part({
		Name = "FloorText", CFrame = cf, Size = Vector3.new(size.X, 0.05, size.Y), Transparency = 1,
		CanCollide = false, CanQuery = false, CanTouch = false, Parent = parent,
	})
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Top
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 20
	gui.Parent = p
	local label = Instance.new("TextLabel")
	label.Size = UDim2.fromScale(1, 1)
	label.BackgroundTransparency = 1
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.TextColor3 = color
	label.TextTransparency = 0.25
	label.Text = text
	label.Parent = gui
end

local function palm(parent: Instance, base: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Palm"
	local height = rng:NextNumber(14, 22)
	local lean = rng:NextNumber(-12, 12)
	local segments = 6
	local top = base
	for i = 1, segments do
		local t = i / segments
		local nextPoint = base + Vector3.new(math.sin(math.rad(lean)) * height * t * t, height * t, 0)
		local mid = (top + nextPoint) / 2
		part({
			Name = "Trunk", Shape = Enum.PartType.Cylinder,
			CFrame = CFrame.lookAt(mid, nextPoint) * CFrame.Angles(0, math.rad(90), 0),
			Size = Vector3.new((nextPoint - top).Magnitude + 0.3, 1.6 - t * 0.5, 1.6 - t * 0.5),
			Color = Color3.fromRGB(130, 95, 60), Material = Enum.Material.Wood, Parent = model,
		})
		top = nextPoint
	end
	for i = 0, 6 do
		local yaw = i * (360 / 7) + rng:NextNumber(-10, 10)
		local cf = CFrame.new(top) * CFrame.Angles(0, math.rad(yaw), 0) * CFrame.Angles(math.rad(-25), 0, 0)
		part({
			Name = "Frond", CFrame = cf * CFrame.new(0, -0.6, -4.5), Size = Vector3.new(2.6, 0.3, 9),
			Color = Color3.fromRGB(60, 160, 70), Material = Enum.Material.Grass, CanCollide = false, Parent = model,
		})
	end
	part({
		Name = "Coconuts", Shape = Enum.PartType.Ball, CFrame = CFrame.new(top - Vector3.new(0, 1, 0)), Size = Vector3.new(1.6, 1.6, 1.6),
		Color = Color3.fromRGB(110, 75, 40), Parent = model,
	})
	model.Parent = parent
end

local function umbrella(parent: Instance, base: Vector3, color: Color3)
	local model = Instance.new("Model")
	model.Name = "Umbrella"
	part({
		Name = "Pole", Shape = Enum.PartType.Cylinder, CFrame = CFrame.new(base + Vector3.new(0, 4, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Size = Vector3.new(8, 0.4, 0.4), Color = Color3.fromRGB(240, 240, 240), Parent = model,
	})
	for i = 0, 7 do
		local cf = CFrame.new(base + Vector3.new(0, 8, 0)) * CFrame.Angles(0, math.rad(i * 45), 0) * CFrame.Angles(math.rad(-18), 0, 0)
		part({
			Name = "Canopy", CFrame = cf * CFrame.new(0, 0, -2.4), Size = Vector3.new(3.8, 0.2, 5),
			Color = if i % 2 == 0 then color else Color3.fromRGB(250, 250, 250), CanCollide = false, Parent = model,
		})
	end
	model.Parent = parent
end

local function rock(parent: Instance, pos: Vector3, rng: Random, scale: number)
	local model = Instance.new("Model")
	model.Name = "Rock"
	for _ = 1, rng:NextInteger(2, 4) do
		local s = Vector3.new(rng:NextNumber(4, 8), rng:NextNumber(3, 7), rng:NextNumber(4, 8)) * scale
		part({
			Name = "Stone", Size = s,
			CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2), s.Y / 2 - 0.6, rng:NextNumber(-2, 2)) * scale)
				* CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, math.pi), rng:NextNumber(-0.3, 0.3)),
			Color = Color3.fromRGB(105, 110, 115):Lerp(Color3.fromRGB(80, 95, 90), rng:NextNumber()), Material = Enum.Material.Slate, Parent = model,
		})
	end
	model.Parent = parent
end

local CORAL_COLORS = {
	Color3.fromRGB(255, 110, 140), Color3.fromRGB(255, 160, 80), Color3.fromRGB(190, 110, 255), Color3.fromRGB(255, 230, 110),
}

local function coral(parent: Instance, pos: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Coral"
	local color = CORAL_COLORS[rng:NextInteger(1, #CORAL_COLORS)]
	for _ = 1, rng:NextInteger(3, 6) do
		local h = rng:NextNumber(2, 6)
		local tilt = CFrame.Angles(rng:NextNumber(-0.5, 0.5), 0, rng:NextNumber(-0.5, 0.5))
		local base = CFrame.new(pos + Vector3.new(rng:NextNumber(-2.5, 2.5), 0, rng:NextNumber(-2.5, 2.5))) * tilt
		part({
			Name = "Branch", Shape = Enum.PartType.Cylinder, CFrame = base * CFrame.new(0, h / 2, 0) * CFrame.Angles(0, 0, math.rad(90)),
			Size = Vector3.new(h, 1, 1), Color = color, Material = Enum.Material.SmoothPlastic, Parent = model,
		})
		part({
			Name = "Tip", Shape = Enum.PartType.Ball, CFrame = base * CFrame.new(0, h, 0), Size = Vector3.new(1.6, 1.6, 1.6),
			Color = color:Lerp(Color3.new(1, 1, 1), 0.3), Material = Enum.Material.Neon, CanCollide = false, Parent = model,
		})
	end
	model.Parent = parent
end

local function kelp(parent: Instance, pos: Vector3, rng: Random)
	local model = Instance.new("Model")
	model.Name = "Kelp"
	for _ = 1, rng:NextInteger(3, 5) do
		local h = rng:NextNumber(5, 10)
		part({
			Name = "Blade", CFrame = CFrame.new(pos + Vector3.new(rng:NextNumber(-2, 2), h / 2, rng:NextNumber(-2, 2)))
				* CFrame.Angles(rng:NextNumber(-0.15, 0.15), rng:NextNumber(0, math.pi), rng:NextNumber(-0.15, 0.15)),
			Size = Vector3.new(0.8, h, 0.2), Color = Color3.fromRGB(50, 130, 60), Material = Enum.Material.Grass,
			CanCollide = false, CanQuery = false, Parent = model,
		})
	end
	model.Parent = parent
end

local function setupCollisionGroups()
	PhysicsService:RegisterCollisionGroup("Sharks")
	PhysicsService:RegisterCollisionGroup("SharkWall")
	PhysicsService:CollisionGroupSetCollidable("SharkWall", "Default", false)
	PhysicsService:CollisionGroupSetCollidable("SharkWall", "Sharks", true)
end

local function setupLighting()
	Lighting.ClockTime = 14.5
	Lighting.Brightness = 2.6
	Lighting.Ambient = Color3.fromRGB(110, 120, 130)
	Lighting.OutdoorAmbient = Color3.fromRGB(140, 150, 160)
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	Lighting.GlobalShadows = true

	local atmosphere = Instance.new("Atmosphere")
	atmosphere.Density = 0.28
	atmosphere.Offset = 0.1
	atmosphere.Color = Color3.fromRGB(200, 230, 245)
	atmosphere.Decay = Color3.fromRGB(110, 170, 200)
	atmosphere.Glare = 0.3
	atmosphere.Haze = 1.2
	atmosphere.Parent = Lighting

	local cc = Instance.new("ColorCorrectionEffect")
	cc.Saturation = 0.15
	cc.Contrast = 0.05
	cc.TintColor = Color3.fromRGB(255, 252, 245)
	cc.Parent = Lighting

	local bloom = Instance.new("BloomEffect")
	bloom.Intensity = 0.4
	bloom.Size = 30
	bloom.Threshold = 1.6
	bloom.Parent = Lighting

	local sun = Instance.new("SunRaysEffect")
	sun.Intensity = 0.06
	sun.Spread = 0.6
	sun.Parent = Lighting
end

local function buildArena(folder: Folder, gates: { BasePart })
	local arena = Instance.new("Folder")
	arena.Name = "Arena"
	arena.Parent = folder

	local rng = Random.new(20261013)

	-- Ground
	part({ Name = "Seabed", Size = Vector3.new(SAFE * 2, 2, HALF_W * 2), CFrame = CFrame.new(0, -1, 0), Color = SEABED, Material = Enum.Material.Sand, Parent = arena })
	for _, side in { -1, 1 } do
		local depth = HALF_L - SAFE
		part({
			Name = if side < 0 then "ShoreA" else "ShoreB", Size = Vector3.new(depth, 2, HALF_W * 2),
			CFrame = CFrame.new(side * (SAFE + depth / 2), -0.9, 0), Color = SAND, Material = Enum.Material.Sand, Parent = arena,
		})
		-- wet sand strip where the waves meet the beach
		part({
			Name = "Shoreline", Size = Vector3.new(6, 2, HALF_W * 2), CFrame = CFrame.new(side * (SAFE - 3), -0.95, 0),
			Color = WET_SAND, Material = Enum.Material.Sand, Parent = arena,
		})
		-- glowing safe line
		part({
			Name = "SafeLine", Size = Vector3.new(1, 0.2, HALF_W * 2), CFrame = CFrame.new(side * SAFE, 0.1, 0),
			Color = Color3.fromRGB(120, 255, 170), Material = Enum.Material.Neon, CanCollide = false, CanQuery = false, Parent = arena,
		})
		floorText(arena, CFrame.new(side * (SAFE + depth / 2), 0.15, 0) * CFrame.Angles(0, math.rad(side * 90), 0), Vector2.new(60, 22), "SAFE ZONE", Color3.fromRGB(255, 255, 255))

		-- the gate that holds everyone in place during the countdown
		local gate = part({
			Name = if side < 0 then "GateA" else "GateB", Size = Vector3.new(1, 14, HALF_W * 2), CFrame = CFrame.new(side * SAFE, 7, 0),
			Color = Color3.fromRGB(120, 230, 255), Material = Enum.Material.ForceField, Transparency = 0.2, CanQuery = false, Parent = arena,
		})
		table.insert(gates, gate)

		-- sharks can never climb onto the beach
		invisibleWall(arena, "SharkWall", CFrame.new(side * (SAFE - 0.5), 25, 0), Vector3.new(1, 50, HALF_W * 2), "SharkWall")

		-- beach decoration along the back
		for i = 1, 6 do
			local z = -HALF_W + i * (HALF_W * 2 / 7) + rng:NextNumber(-4, 4)
			palm(arena, Vector3.new(side * (HALF_L - rng:NextNumber(3, 7)), 0, z), rng)
		end
		for i = 1, 3 do
			umbrella(arena, Vector3.new(side * (HALF_L - 12), 0, -HALF_W + i * (HALF_W * 2 / 4) + 10), CORAL_COLORS[i])
		end
		sign(arena, CFrame.new(side * (HALF_L - 2), 9, 0) * CFrame.Angles(0, math.rad(side * 90), 0), Vector3.new(30, 8, 1),
			if side < 0 then "WEST BEACH" else "EAST BEACH", Color3.fromRGB(255, 220, 120))
	end

	-- The ocean: a see-through layer so everyone wades up to the knees
	part({
		Name = "Water", Size = Vector3.new(SAFE * 2 - 2, 2.4, HALF_W * 2), CFrame = CFrame.new(0, 1.2, 0), Color = WATER,
		Material = Enum.Material.Glass, Transparency = 0.45, Reflectance = 0.05, CanCollide = false, CanQuery = false, CanTouch = false, Parent = arena,
	})
	part({
		Name = "CenterLine", Size = Vector3.new(0.6, 0.15, HALF_W * 2), CFrame = CFrame.new(0, 0.1, 0),
		Color = Color3.fromRGB(255, 90, 90), Material = Enum.Material.Neon, Transparency = 0.3, CanCollide = false, CanQuery = false, Parent = arena,
	})

	-- Reef obstacles, kept off the very middle so sharks have open water to start in
	local placed: { Vector3 } = {}
	local function freeSpot(minGap: number): Vector3?
		for _ = 1, 40 do
			local p = Vector3.new(rng:NextNumber(-SAFE + 10, SAFE - 10), 0, rng:NextNumber(-HALF_W + 8, HALF_W - 8))
			if math.abs(p.X) < 12 and math.abs(p.Z) < 20 then
				continue
			end
			local ok = true
			for _, q in placed do
				if (q - p).Magnitude < minGap then
					ok = false
					break
				end
			end
			if ok then
				table.insert(placed, p)
				return p
			end
		end
		return nil
	end
	for _ = 1, 12 do
		local p = freeSpot(22)
		if p then
			rock(arena, p, rng, rng:NextNumber(0.9, 1.5))
		end
	end
	for _ = 1, 14 do
		local p = freeSpot(14)
		if p then
			coral(arena, p, rng)
		end
	end
	for _ = 1, 18 do
		local p = freeSpot(8)
		if p then
			kelp(arena, p, rng)
		end
	end

	-- Boundary
	local wallH = 60
	for _, side in { -1, 1 } do
		invisibleWall(arena, "Boundary", CFrame.new(0, wallH / 2, side * (HALF_W + 0.5)), Vector3.new(HALF_L * 2 + 2, wallH, 1))
		invisibleWall(arena, "Boundary", CFrame.new(side * (HALF_L + 0.5), wallH / 2, 0), Vector3.new(1, wallH, HALF_W * 2 + 2))
		-- low rocky breakwater you can see
		for x = -HALF_L, HALF_L, 12 do
			part({
				Name = "Breakwater", Size = Vector3.new(12, rng:NextNumber(3, 5), 4),
				CFrame = CFrame.new(x + 6, 1.5, side * (HALF_W + 2)) * CFrame.Angles(0, rng:NextNumber(-0.2, 0.2), 0),
				Color = Color3.fromRGB(95, 100, 100), Material = Enum.Material.Slate, Parent = arena,
			})
		end
	end

	-- Big open sea around everything for the horizon
	part({
		Name = "OpenSea", Size = Vector3.new(2048, 1, 2048), CFrame = CFrame.new(0, -1.5, 0), Color = Color3.fromRGB(30, 120, 170),
		Material = Enum.Material.Glass, Transparency = 0.1, CanCollide = false, CanQuery = false, CanTouch = false, Parent = folder,
	})
end

local function buildLobby(folder: Folder): SpawnLocation
	local lobby = Instance.new("Folder")
	lobby.Name = "Lobby"
	lobby.Parent = folder
	local c = Config.LobbyCenter
	local rng = Random.new(77)

	part({ Name = "Island", Shape = Enum.PartType.Cylinder, Size = Vector3.new(4, 110, 110), CFrame = CFrame.new(c - Vector3.new(0, 2, 0)) * CFrame.Angles(0, 0, math.rad(90)), Color = SAND, Material = Enum.Material.Sand, Parent = lobby })
	part({ Name = "Boardwalk", Size = Vector3.new(14, 0.6, 60), CFrame = CFrame.new(c + Vector3.new(0, 0.3, 30)), Color = Color3.fromRGB(150, 110, 70), Material = Enum.Material.WoodPlanks, Parent = lobby })

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(12, 1, 12)
	spawn.CFrame = CFrame.new(c + Vector3.new(0, 0.5, 0))
	spawn.Color = Config.Colors.Minnow
	spawn.Material = Enum.Material.SmoothPlastic
	spawn.Duration = 0
	spawn.Neutral = true
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = lobby

	for i = 0, 9 do
		local a = i / 10 * math.pi * 2 + rng:NextNumber(-0.2, 0.2)
		palm(lobby, c + Vector3.new(math.cos(a) * 44, 0, math.sin(a) * 44), rng)
	end
	for i = 1, 4 do
		local a = i / 4 * math.pi * 2 + 0.4
		umbrella(lobby, c + Vector3.new(math.cos(a) * 26, 0, math.sin(a) * 26), CORAL_COLORS[i])
	end

	sign(lobby, CFrame.new(c + Vector3.new(0, 16, -40)) * CFrame.Angles(0, math.pi, 0), Vector3.new(44, 12, 1.5), "SHARKS VS MINNOWS", Color3.fromRGB(255, 200, 80))
	sign(lobby, CFrame.new(c + Vector3.new(0, 7.5, -40)) * CFrame.Angles(0, math.pi, 0), Vector3.new(44, 5, 1.2),
		"Cross the ocean. Don't get chomped. Last minnow wins!", Color3.fromRGB(230, 245, 255))
	part({ Name = "SignPost", Size = Vector3.new(1.5, 18, 1.5), CFrame = CFrame.new(c + Vector3.new(-18, 9, -40.8)), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood, Parent = lobby })
	part({ Name = "SignPost", Size = Vector3.new(1.5, 18, 1.5), CFrame = CFrame.new(c + Vector3.new(18, 9, -40.8)), Color = Color3.fromRGB(110, 80, 50), Material = Enum.Material.Wood, Parent = lobby })

	-- keep people on the island
	for i = 0, 23 do
		local a = i / 24 * math.pi * 2
		invisibleWall(lobby, "Edge", CFrame.new(c + Vector3.new(math.cos(a) * 55, 20, math.sin(a) * 55)) * CFrame.Angles(0, -a, 0), Vector3.new(2, 40, 15))
	end

	return spawn
end

function MapBuilder.Build(): Map
	setupCollisionGroups()
	setupLighting()

	local existing = workspace:FindFirstChild("SvMMap")
	if existing then
		existing:Destroy()
	end
	local folder = Instance.new("Folder")
	folder.Name = "SvMMap"

	local gates: { BasePart } = {}
	buildArena(folder, gates)
	local spawn = buildLobby(folder)
	folder.Parent = workspace

	return { Folder = folder, Gates = gates, LobbySpawn = spawn }
end

-- Where a minnow should start on a given shore (-1 = west, 1 = east).
function MapBuilder.ShoreSpawn(side: number, index: number, count: number): CFrame
	local span = HALF_W * 2 - 20
	local z = if count <= 1 then 0 else -span / 2 + (index - 1) * span / (count - 1)
	local x = side * (SAFE + 8 + (index % 3) * 4)
	return CFrame.lookAt(Vector3.new(x, 4, z), Vector3.new(0, 4, z))
end

function MapBuilder.SharkSpawn(index: number, count: number): CFrame
	local z = if count <= 1 then 0 else -14 + (index - 1) * 28 / (count - 1)
	return CFrame.new(0, 4, z)
end

function MapBuilder.LobbySpot(): CFrame
	local c = Config.LobbyCenter
	return CFrame.new(c + Vector3.new(math.random(-15, 15), 4, math.random(-10, 15)))
end

return MapBuilder
