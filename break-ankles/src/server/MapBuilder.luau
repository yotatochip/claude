--!strict
-- Builds the lobby and the arena out of parts at runtime, so the place file
-- needs no imported models. Two themes share one layout: a long rectangular
-- field with a line and a safe zone at each end.

local Lighting = game:GetService("Lighting")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Arena = require(Shared.Arena)
local Groups = require(script.Parent.Groups)

local HALF_L = Arena.HalfLength
local HALF_W = Arena.HalfWidth
local DEPTH = Arena.SafeDepth
local WALL_H = Config.Arena.WallHeight
local OUTER_Z = HALF_L + DEPTH

type Theme = {
	Ground: Enum.Material,
	GroundColor: Color3,
	StripeColor: Color3,
	Surround: Enum.Material,
	SurroundColor: Color3,
	SafeMaterial: Enum.Material,
	SafeColor: Color3,
	FenceColor: Color3,
	HillMaterial: Enum.Material,
	HillColor: Color3,
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	Tint: Color3,
	Decor: string,
}

local THEMES: { [string]: Theme } = {
	Valley = {
		Ground = Enum.Material.Grass,
		GroundColor = Color3.fromRGB(86, 158, 64),
		StripeColor = Color3.fromRGB(98, 172, 72),
		Surround = Enum.Material.Grass,
		SurroundColor = Color3.fromRGB(74, 138, 58),
		SafeMaterial = Enum.Material.Ground,
		SafeColor = Color3.fromRGB(176, 150, 108),
		FenceColor = Color3.fromRGB(120, 86, 56),
		HillMaterial = Enum.Material.Grass,
		HillColor = Color3.fromRGB(68, 130, 56),
		Lighting = {
			ClockTime = 14.2,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(88, 92, 104),
			OutdoorAmbient = Color3.fromRGB(140, 142, 152),
		},
		Atmosphere = {
			Density = 0.28,
			Offset = 0.1,
			Color = Color3.fromRGB(199, 222, 255),
			Decay = Color3.fromRGB(108, 140, 182),
			Glare = 0.2,
			Haze = 1.2,
		},
		Tint = Color3.fromRGB(255, 255, 255),
		Decor = "Valley",
	},
	Dunes = {
		Ground = Enum.Material.Sand,
		GroundColor = Color3.fromRGB(222, 192, 136),
		StripeColor = Color3.fromRGB(230, 202, 148),
		Surround = Enum.Material.Sand,
		SurroundColor = Color3.fromRGB(214, 180, 122),
		SafeMaterial = Enum.Material.Sandstone,
		SafeColor = Color3.fromRGB(196, 150, 104),
		FenceColor = Color3.fromRGB(150, 110, 70),
		HillMaterial = Enum.Material.Sand,
		HillColor = Color3.fromRGB(224, 186, 124),
		Lighting = {
			ClockTime = 16.6,
			Brightness = 3.1,
			Ambient = Color3.fromRGB(110, 96, 86),
			OutdoorAmbient = Color3.fromRGB(160, 140, 124),
		},
		Atmosphere = {
			Density = 0.34,
			Offset = 0.15,
			Color = Color3.fromRGB(255, 226, 184),
			Decay = Color3.fromRGB(214, 160, 112),
			Glare = 0.4,
			Haze = 2.0,
		},
		Tint = Color3.fromRGB(255, 244, 230),
		Decor = "Dunes",
	},
}

local SIDE_COLORS = {
	A = Color3.fromRGB(60, 140, 255),
	B = Color3.fromRGB(255, 140, 40),
}

local MapBuilder = {}

local arenaModel: Model? = nil
local gates: { [string]: BasePart } = {}

local function part(props: { [string]: any }, parent: Instance): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Material = Enum.Material.SmoothPlastic
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

local function invisibleWall(size: Vector3, cf: CFrame, parent: Instance, name: string): Part
	return part({
		Name = name,
		Size = size,
		CFrame = cf,
		Transparency = 1,
		CanQuery = false,
		CanTouch = false,
		CastShadow = false,
	}, parent)
end

local function label(p: BasePart, face: Enum.NormalId, text: string, color: Color3, ppsOverride: number?): TextLabel
	local gui = Instance.new("SurfaceGui")
	gui.Face = face
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = ppsOverride or 30
	gui.LightInfluence = 0.2
	gui.Parent = p
	local t = Instance.new("TextLabel")
	t.BackgroundTransparency = 1
	t.Size = UDim2.fromScale(1, 1)
	t.Text = text
	t.TextScaled = true
	t.Font = Enum.Font.FredokaOne
	t.TextColor3 = color
	t.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 4
	stroke.Color = Color3.new(0, 0, 0)
	stroke.Parent = t
	return t
end

---------------------------------------------------------------------------
-- Lighting
---------------------------------------------------------------------------
local function ensure(className: string, name: string): Instance
	local inst = Lighting:FindFirstChild(name)
	if not inst then
		inst = Instance.new(className)
		inst.Name = name;
		(inst :: Instance).Parent = Lighting
	end
	return inst :: Instance
end

function MapBuilder.ApplyLighting(themeId: string)
	local theme = THEMES[themeId] or THEMES.Valley
	for k, v in theme.Lighting do
		(Lighting :: any)[k] = v
	end
	Lighting.GlobalShadows = true
	Lighting.EnvironmentDiffuseScale = 0.6
	Lighting.EnvironmentSpecularScale = 0.6
	local atmo = ensure("Atmosphere", "BA_Atmosphere") :: Atmosphere
	for k, v in theme.Atmosphere do
		(atmo :: any)[k] = v
	end
	local cc = ensure("ColorCorrectionEffect", "BA_Color") :: ColorCorrectionEffect
	cc.Saturation = 0.14
	cc.Contrast = 0.06
	cc.Brightness = 0.01
	cc.TintColor = theme.Tint
	local bloom = ensure("BloomEffect", "BA_Bloom") :: BloomEffect
	bloom.Intensity = 0.35
	bloom.Size = 24
	bloom.Threshold = 1.7
	local rays = ensure("SunRaysEffect", "BA_SunRays") :: SunRaysEffect
	rays.Intensity = 0.05
	rays.Spread = 0.8
end

---------------------------------------------------------------------------
-- Decor
---------------------------------------------------------------------------
local function tree(at: Vector3, rng: Random, parent: Instance)
	local h = rng:NextNumber(10, 18)
	part({
		Name = "Trunk",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, 2.2, 2.2),
		CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Wood,
		Color = Color3.fromRGB(110, 76, 48),
	}, parent)
	for i = 1, 3 do
		local s = rng:NextNumber(8, 13)
		part({
			Name = "Leaves",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			Position = at + Vector3.new(rng:NextNumber(-2.5, 2.5), h + rng:NextNumber(-1, 3) + i * 0.6, rng:NextNumber(-2.5, 2.5)),
			Material = Enum.Material.Grass,
			Color = Color3.fromRGB(56 + rng:NextInteger(0, 30), 120 + rng:NextInteger(0, 40), 50),
			CastShadow = true,
		}, parent)
	end
end

local function cactus(at: Vector3, rng: Random, parent: Instance)
	local h = rng:NextNumber(7, 13)
	local green = Color3.fromRGB(80, 140, 70)
	part({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(h, 2.4, 2.4),
		CFrame = CFrame.new(at + Vector3.new(0, h / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Grass,
		Color = green,
	}, parent)
	for _, side in { -1, 1 } do
		if rng:NextNumber() < 0.75 then
			local armH = rng:NextNumber(2.5, 4.5)
			local y = rng:NextNumber(h * 0.35, h * 0.7)
			part({
				Size = Vector3.new(3, 1.6, 1.6),
				CFrame = CFrame.new(at + Vector3.new(side * 1.8, y, 0)),
				Material = Enum.Material.Grass,
				Color = green,
			}, parent)
			part({
				Shape = Enum.PartType.Cylinder,
				Size = Vector3.new(armH, 1.6, 1.6),
				CFrame = CFrame.new(at + Vector3.new(side * 3, y + armH / 2, 0)) * CFrame.Angles(0, 0, math.rad(90)),
				Material = Enum.Material.Grass,
				Color = green,
			}, parent)
		end
	end
end

local function rock(at: Vector3, rng: Random, color: Color3, parent: Instance)
	local s = rng:NextNumber(3, 8)
	part({
		Name = "Rock",
		Size = Vector3.new(s * rng:NextNumber(0.9, 1.6), s * 0.7, s),
		CFrame = CFrame.new(at + Vector3.new(0, s * 0.25, 0)) * CFrame.Angles(rng:NextNumber(-0.3, 0.3), rng:NextNumber(0, 6.28), rng:NextNumber(-0.3, 0.3)),
		Material = Enum.Material.Slate,
		Color = color,
	}, parent)
end

local function outsideSpot(rng: Random, margin: number, spread: number): Vector3
	-- A random spot outside the fence, within `spread` studs of it.
	while true do
		local x = rng:NextNumber(-HALF_W - spread, HALF_W + spread)
		local z = rng:NextNumber(-OUTER_Z - spread, OUTER_Z + spread)
		if math.abs(x) > HALF_W + margin or math.abs(z) > OUTER_Z + margin then
			-- keep the lobby side clear
			local lobby = Arena.LobbyCenter()
			if (Vector3.new(x, 0, z) - Vector3.new(lobby.X, 0, lobby.Z)).Magnitude > 60 then
				return Vector3.new(x, 0, z)
			end
		end
	end
end

local function buildDecor(theme: Theme, parent: Instance)
	local rng = Random.new(if theme.Decor == "Valley" then 1384 else 4831)
	-- Rolling hills ring the arena.
	for i = 1, 26 do
		local angle = (i / 26) * math.pi * 2 + rng:NextNumber(-0.1, 0.1)
		local r = rng:NextNumber(260, 330)
		local s = rng:NextNumber(120, 220)
		local pos = Vector3.new(math.cos(angle) * r * 0.8, -s * 0.38, math.sin(angle) * r * 1.15)
		part({
			Name = "Hill",
			Shape = Enum.PartType.Ball,
			Size = Vector3.new(s, s, s),
			Position = pos,
			Material = theme.HillMaterial,
			Color = theme.HillColor:Lerp(Color3.new(0, 0, 0), rng:NextNumber(0, 0.12)),
			CastShadow = false,
			CanCollide = false,
		}, parent)
	end
	local rockColor = if theme.Decor == "Valley" then Color3.fromRGB(120, 120, 124) else Color3.fromRGB(176, 120, 84)
	for _ = 1, 40 do
		local at = outsideSpot(rng, 10, 120)
		if theme.Decor == "Valley" then
			tree(at, rng, parent)
		else
			cactus(at, rng, parent)
		end
	end
	for _ = 1, 30 do
		rock(outsideSpot(rng, 6, 110), rng, rockColor, parent)
	end
end

---------------------------------------------------------------------------
-- Arena
---------------------------------------------------------------------------
local function fenceLine(from: Vector3, to: Vector3, color: Color3, parent: Instance)
	local delta = to - from
	local len = delta.Magnitude
	local dir = delta.Unit
	local count = math.floor(len / 10)
	for i = 0, count do
		local p = from + dir * (len * i / count)
		part({
			Name = "Post",
			Size = Vector3.new(0.9, 4.4, 0.9),
			Position = p + Vector3.new(0, 2.2, 0),
			Material = Enum.Material.Wood,
			Color = color,
		}, parent)
	end
	for _, y in { 1.6, 3.4 } do
		local mid = (from + to) / 2 + Vector3.new(0, y, 0)
		part({
			Name = "Rail",
			Size = Vector3.new(0.35, 0.5, len),
			CFrame = CFrame.lookAt(mid, mid + dir),
			Material = Enum.Material.Wood,
			Color = color,
		}, parent)
	end
end

local function arch(side: string, parent: Instance)
	local z = Arena.LineZ(side)
	local color = SIDE_COLORS[side]
	local outward = if side == "A" then -1 else 1
	for _, sx in { -1, 1 } do
		part({
			Name = "ArchPost",
			Size = Vector3.new(2.4, 20, 2.4),
			Position = Vector3.new(sx * (HALF_W + 2), 10, z),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(40, 42, 48),
		}, parent)
	end
	local beam = part({
		Name = "ArchBanner",
		Size = Vector3.new(HALF_W * 2 + 6, 4, 1.2),
		Position = Vector3.new(0, 21, z),
		Material = Enum.Material.SmoothPlastic,
		Color = color,
	}, parent)
	-- Text faces the field on one side and the safe zone on the other.
	local fieldFace = if outward == -1 then Enum.NormalId.Back else Enum.NormalId.Front
	local zoneFace = if outward == -1 then Enum.NormalId.Front else Enum.NormalId.Back
	label(beam, fieldFace, "SIDE " .. side .. "  •  SAFE ZONE", Color3.new(1, 1, 1), 12)
	label(beam, zoneFace, "SIDE " .. side, Color3.new(1, 1, 1), 12)
	-- A colored strip on the ground just inside the safe zone.
	part({
		Name = "SideStrip",
		Size = Vector3.new(HALF_W * 2, 0.12, 2.4),
		Position = Vector3.new(0, 0.12, z + outward * 2.4),
		Color = color,
		Material = Enum.Material.SmoothPlastic,
		CanCollide = false,
	}, parent)
end

function MapBuilder.BuildArena(themeId: string): Model
	local theme = THEMES[themeId] or THEMES.Valley
	if arenaModel then
		arenaModel:Destroy()
	end
	gates = {}
	local model = Instance.new("Model")
	model.Name = "Arena"
	model:SetAttribute("Theme", themeId)

	local ground = Instance.new("Folder")
	ground.Name = "Ground"
	ground.Parent = model

	-- World floor.
	part({
		Name = "Surround",
		Size = Vector3.new(900, 4, 1000),
		Position = Vector3.new(0, -2.05, 0),
		Material = theme.Surround,
		Color = theme.SurroundColor,
	}, ground)

	-- The field with mowing stripes.
	part({
		Name = "Field",
		Size = Vector3.new(HALF_W * 2, 1, HALF_L * 2),
		Position = Vector3.new(0, -0.45, 0),
		Material = theme.Ground,
		Color = theme.GroundColor,
	}, ground)
	local stripes = 11
	local stripeLen = HALF_L * 2 / stripes
	for i = 0, stripes - 1, 2 do
		part({
			Name = "Stripe",
			Size = Vector3.new(HALF_W * 2, 0.1, stripeLen),
			Position = Vector3.new(0, 0.1, -HALF_L + stripeLen * (i + 0.5)),
			Material = theme.Ground,
			Color = theme.StripeColor,
			CanCollide = false,
		}, ground)
	end
	-- Safe zones.
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		part({
			Name = "SafeZone" .. side,
			Size = Vector3.new(HALF_W * 2, 1, DEPTH),
			Position = Vector3.new(0, -0.45, sign * (HALF_L + DEPTH / 2)),
			Material = theme.SafeMaterial,
			Color = theme.SafeColor,
		}, ground)
		-- The line.
		part({
			Name = "Line" .. side,
			Size = Vector3.new(HALF_W * 2, 0.14, 1.6),
			Position = Vector3.new(0, 0.14, sign * HALF_L),
			Color = Color3.fromRGB(250, 250, 250),
			CanCollide = false,
		}, ground)
	end

	-- Fence, arches and invisible walls.
	local bounds = Instance.new("Folder")
	bounds.Name = "Bounds"
	bounds.Parent = model
	fenceLine(Vector3.new(-HALF_W - 1, 0, -OUTER_Z), Vector3.new(-HALF_W - 1, 0, OUTER_Z), theme.FenceColor, bounds)
	fenceLine(Vector3.new(HALF_W + 1, 0, -OUTER_Z), Vector3.new(HALF_W + 1, 0, OUTER_Z), theme.FenceColor, bounds)
	fenceLine(Vector3.new(-HALF_W - 1, 0, -OUTER_Z - 1), Vector3.new(HALF_W + 1, 0, -OUTER_Z - 1), theme.FenceColor, bounds)
	fenceLine(Vector3.new(-HALF_W - 1, 0, OUTER_Z + 1), Vector3.new(HALF_W + 1, 0, OUTER_Z + 1), theme.FenceColor, bounds)
	arch("A", bounds)
	arch("B", bounds)
	local wallLen = OUTER_Z * 2 + 4
	invisibleWall(Vector3.new(2, WALL_H, wallLen), CFrame.new(-HALF_W - 2.5, WALL_H / 2, 0), bounds, "WallLeft")
	invisibleWall(Vector3.new(2, WALL_H, wallLen), CFrame.new(HALF_W + 2.5, WALL_H / 2, 0), bounds, "WallRight")
	invisibleWall(Vector3.new(HALF_W * 2 + 8, WALL_H, 2), CFrame.new(0, WALL_H / 2, -OUTER_Z - 2.5), bounds, "WallBackA")
	invisibleWall(Vector3.new(HALF_W * 2 + 8, WALL_H, 2), CFrame.new(0, WALL_H / 2, OUTER_Z + 2.5), bounds, "WallBackB")
	invisibleWall(Vector3.new(HALF_W * 2 + 8, 2, wallLen), CFrame.new(0, WALL_H + 1, 0), bounds, "Ceiling")

	-- Chaser barriers sit just inside each safe zone; runner gates hold the
	-- runners back during the countdown.
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		local barrier = invisibleWall(Vector3.new(HALF_W * 2 + 4, WALL_H, 1), CFrame.new(0, WALL_H / 2, sign * (HALF_L + 1.6)), bounds, "ChaserBarrier" .. side)
		barrier.CollisionGroup = Groups.ChaserBarrier
		local gate = part({
			Name = "RunnerGate" .. side,
			Size = Vector3.new(HALF_W * 2 + 4, 12, 0.6),
			Position = Vector3.new(0, 6, sign * (HALF_L + 0.5)),
			Material = Enum.Material.ForceField,
			Color = SIDE_COLORS[side],
			Transparency = 1,
			CanCollide = false,
			CanQuery = false,
			CanTouch = false,
			CastShadow = false,
		}, bounds)
		gate.CollisionGroup = Groups.RunnerGate
		gates[side] = gate
	end

	local decor = Instance.new("Folder")
	decor.Name = "Decor"
	decor.Parent = model
	buildDecor(theme, decor)

	local dynamic = Instance.new("Folder")
	dynamic.Name = "Dynamic" -- gems, traps, doors, peels
	dynamic.Parent = model

	model.Parent = workspace
	arenaModel = model
	MapBuilder.ApplyLighting(themeId)
	return model
end

function MapBuilder.Dynamic(): Folder
	local m = arenaModel
	if m then
		local f = m:FindFirstChild("Dynamic")
		if f then
			return f :: Folder
		end
	end
	return workspace
end

function MapBuilder.ClearDynamic()
	local f = MapBuilder.Dynamic()
	if f ~= workspace then
		f:ClearAllChildren()
	end
end

-- Closed gates are visible and stop runners; open ones vanish.
function MapBuilder.SetGate(side: string, closed: boolean)
	local g = gates[side]
	if g then
		g.CanCollide = closed
		g.Transparency = if closed then 0.35 else 1
	end
end

---------------------------------------------------------------------------
-- Lobby: a raised deck beside the field, so waiting players can watch.
---------------------------------------------------------------------------
local lobbySpawn: SpawnLocation? = nil

function MapBuilder.BuildLobby(): Model
	local old = workspace:FindFirstChild("Lobby")
	if old then
		old:Destroy()
	end
	local model = Instance.new("Model")
	model.Name = "Lobby"
	local c = Arena.LobbyCenter()
	local w, d = 70, 84

	part({
		Name = "Deck",
		Size = Vector3.new(w, 2, d),
		Position = c - Vector3.new(0, 1, 0),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(150, 112, 78),
	}, model)
	-- Supports down to the ground.
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local h = c.Y
			part({
				Name = "Pillar",
				Size = Vector3.new(3, h, 3),
				Position = Vector3.new(c.X + sx * (w / 2 - 3), h / 2 - 2, c.Z + sz * (d / 2 - 3)),
				Material = Enum.Material.Concrete,
				Color = Color3.fromRGB(190, 190, 196),
			}, model)
		end
	end
	-- Glass rail (visible) with a tall invisible wall so nobody falls off.
	local railColor = Color3.fromRGB(200, 230, 255)
	local function rail(size: Vector3, pos: Vector3)
		part({ Name = "Rail", Size = size, Position = pos + Vector3.new(0, 1.8, 0), Material = Enum.Material.Glass, Transparency = 0.6, Color = railColor }, model)
		invisibleWall(Vector3.new(size.X, 16, size.Z), CFrame.new(pos + Vector3.new(0, 8, 0)), model, "LobbyWall")
	end
	rail(Vector3.new(0.5, 3.6, d), c + Vector3.new(w / 2, 0, 0))
	rail(Vector3.new(0.5, 3.6, d), c + Vector3.new(-w / 2, 0, 0))
	rail(Vector3.new(w, 3.6, 0.5), c + Vector3.new(0, 0, d / 2))
	rail(Vector3.new(w, 3.6, 0.5), c + Vector3.new(0, 0, -d / 2))

	-- Poster board at the back of the deck, facing the field: the thumbnail
	-- art, with a text title behind it in case the image doesn't load.
	local board = part({
		Name = "TitleBoard",
		Size = Vector3.new(1, 18, 32),
		Position = c + Vector3.new(-w / 2 + 2, 11, 0),
		Color = Color3.fromRGB(24, 26, 34),
	}, model)
	local title = label(board, Enum.NormalId.Right, "BREAK ANKLES", Color3.fromRGB(255, 200, 60), 16)
	title.Size = UDim2.fromScale(1, 0.62)
	local sub = Instance.new("TextLabel")
	sub.BackgroundTransparency = 1
	sub.Position = UDim2.fromScale(0.04, 0.62)
	sub.Size = UDim2.fromScale(0.92, 0.32)
	sub.TextScaled = true
	sub.Font = Enum.Font.GothamBold
	sub.TextColor3 = Color3.new(1, 1, 1)
	sub.Text = "Cross the field 3 times. Juke the knife. Don't get caught."
	sub.Parent = title.Parent
	local poster = Instance.new("ImageLabel")
	poster.Name = "Poster"
	poster.BackgroundTransparency = 1
	poster.Size = UDim2.fromScale(1, 1)
	poster.ScaleType = Enum.ScaleType.Crop
	poster.Image = Config.Art.Poster
	poster.ZIndex = 2
	poster.Parent = title.Parent

	-- How-to board on the side.
	local howto = part({
		Name = "HowToBoard",
		Size = Vector3.new(26, 12, 1),
		Position = c + Vector3.new(0, 7.5, d / 2 - 2),
		Color = Color3.fromRGB(24, 26, 34),
	}, model)
	local gui = Instance.new("SurfaceGui")
	gui.Face = Enum.NormalId.Front
	gui.SizingMode = Enum.SurfaceGuiSizingMode.PixelsPerStud
	gui.PixelsPerStud = 24
	gui.LightInfluence = 0.2
	gui.Parent = howto
	local text = Instance.new("TextLabel")
	text.BackgroundTransparency = 1
	text.Size = UDim2.new(1, -40, 1, -30)
	text.Position = UDim2.fromOffset(20, 15)
	text.TextScaled = true
	text.TextXAlignment = Enum.TextXAlignment.Left
	text.TextYAlignment = Enum.TextYAlignment.Top
	text.Font = Enum.Font.GothamBold
	text.TextColor3 = Color3.new(1, 1, 1)
	text.RichText = true
	text.Text = table.concat({
		'<font color="#FFC83C">HOW TO PLAY</font>',
		"RUNNERS: cross to the other side 3 times.",
		"CHASER: one knife hit downs a runner.",
		"Downed runners can be revived (hold E).",
		"Nobody saves you? You become a chaser.",
		"",
		'<font color="#7FD4FF">Space + A/D</font>  dash     <font color="#7FD4FF">Alt</font>  instant stop',
		'<font color="#7FD4FF">Q</font>  ability     <font color="#7FD4FF">F</font>  item     <font color="#7FD4FF">Click</font>  swing',
	}, "\n")
	text.Parent = gui
	howto.CFrame = CFrame.lookAt(howto.Position, howto.Position + Vector3.new(0, 0, -1))

	-- Shop stall with a prompt the client turns into the shop menu.
	local stall = part({
		Name = "ShopStall",
		Size = Vector3.new(10, 4, 4),
		Position = c + Vector3.new(-14, 2, -d / 2 + 6),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(196, 92, 60),
	}, model)
	local awning = part({
		Name = "Awning",
		Size = Vector3.new(11, 0.6, 6),
		Position = stall.Position + Vector3.new(0, 6, 0),
		Color = Color3.fromRGB(255, 220, 90),
	}, model)
	label(awning, Enum.NormalId.Back, "SHOP", Color3.new(1, 1, 1), 20)
	label(awning, Enum.NormalId.Top, "SHOP", Color3.fromRGB(196, 92, 60), 6)
	for _, sx in { -1, 1 } do
		part({ Size = Vector3.new(0.6, 6, 0.6), Position = stall.Position + Vector3.new(sx * 5, 3, 2.5), Material = Enum.Material.Wood, Color = Color3.fromRGB(110, 76, 48) }, model)
	end
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "ShopPrompt"
	prompt.ActionText = "Open Shop"
	prompt.ObjectText = "Gems & Coins"
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.MaxActivationDistance = 10
	prompt.RequiresLineOfSight = false
	prompt.Parent = stall

	-- Canopy over the middle of the deck.
	part({
		Name = "Canopy",
		Size = Vector3.new(w - 10, 0.6, 30),
		Position = c + Vector3.new(0, 16, 0),
		Material = Enum.Material.Glass,
		Transparency = 0.45,
		Color = Color3.fromRGB(150, 210, 255),
		CastShadow = false,
	}, model)
	for _, sx in { -1, 1 } do
		for _, sz in { -1, 1 } do
			local post = part({
				Name = "CanopyPost",
				Size = Vector3.new(1, 16, 1),
				Position = c + Vector3.new(sx * (w / 2 - 6), 8, sz * 14),
				Material = Enum.Material.Metal,
				Color = Color3.fromRGB(60, 62, 70),
			}, model)
			local light = Instance.new("PointLight")
			light.Range = 18
			light.Brightness = 0.8
			light.Color = Color3.fromRGB(255, 236, 200)
			light.Parent = post
		end
	end

	local spawn = Instance.new("SpawnLocation")
	spawn.Name = "LobbySpawn"
	spawn.Anchored = true
	spawn.Size = Vector3.new(10, 1, 10)
	spawn.Position = c + Vector3.new(4, 0.5, 0)
	spawn.Transparency = 0
	spawn.Material = Enum.Material.Neon
	spawn.Color = Color3.fromRGB(255, 200, 60)
	spawn.Neutral = true
	spawn.Duration = 0
	spawn.TopSurface = Enum.SurfaceType.Smooth
	spawn.Parent = model
	local decal = spawn:FindFirstChildOfClass("Decal")
	if decal then
		decal:Destroy()
	end
	lobbySpawn = spawn

	model.Parent = workspace
	return model
end

function MapBuilder.LobbyCFrame(index: number?): CFrame
	local c = Arena.LobbyCenter()
	local i = index or math.random(1, 12)
	local angle = (i % 12) / 12 * math.pi * 2
	local pos = c + Vector3.new(6 + math.cos(angle) * 9, 3, math.sin(angle) * 14)
	-- Face the field (+X).
	return CFrame.lookAt(pos, pos + Vector3.new(1, 0, 0))
end

function MapBuilder.InLobby(pos: Vector3): boolean
	local c = Arena.LobbyCenter()
	return math.abs(pos.X - c.X) < 36 and math.abs(pos.Z - c.Z) < 43 and pos.Y > c.Y - 6 and pos.Y < c.Y + 30
end

function MapBuilder.Spawn(): SpawnLocation?
	return lobbySpawn
end

return MapBuilder
