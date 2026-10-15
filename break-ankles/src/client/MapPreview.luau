--!strict
-- Builds a small 3D model of a map inside a ViewportFrame for the vote
-- cards: the striped field, safe zones, lines, arches, fences, hills and
-- trees or cacti, in the same colors the real arena uses.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Themes = require(Shared.Themes)

local HALF_L = Arena.HalfLength
local HALF_W = Arena.HalfWidth
local DEPTH = Arena.SafeDepth

local MapPreview = {}

local function part(parent: Instance, size: Vector3, cf: CFrame, color: Color3, material: Enum.Material?, shape: Enum.PartType?): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.Size = size
	p.CFrame = cf
	p.Color = color
	p.Material = material or Enum.Material.SmoothPlastic
	if shape then
		p.Shape = shape
	end
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	p.Parent = parent
	return p
end

-- A fixed pseudo-random sequence so every client sees the same preview.
local function seq(seed: number): () -> number
	local s = seed
	return function(): number
		s = (s * 16807) % 2147483647
		return s / 2147483647
	end
end

local function decor(model: Model, themeId: string, rand: () -> number)
	local valley = themeId ~= "Dunes"
	for _ = 1, 22 do
		-- pick a spot outside the fence
		local x, z
		repeat
			x = (rand() * 2 - 1) * (HALF_W + 70)
			z = (rand() * 2 - 1) * (HALF_L + DEPTH + 60)
		until math.abs(x) > HALF_W + 8 or math.abs(z) > HALF_L + DEPTH + 8
		if valley then
			local h = 10 + rand() * 6
			part(model, Vector3.new(h, 2.4, 2.4), CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(110, 76, 48), Enum.Material.Wood, Enum.PartType.Cylinder)
			local s = 10 + rand() * 4
			part(model, Vector3.new(s, s, s), CFrame.new(x, h + 2, z), Color3.fromRGB(60 + math.floor(rand() * 30), 130 + math.floor(rand() * 30), 52), Enum.Material.Grass, Enum.PartType.Ball)
		else
			local h = 8 + rand() * 5
			part(model, Vector3.new(h, 2.6, 2.6), CFrame.new(x, h / 2, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 140, 70), Enum.Material.Grass, Enum.PartType.Cylinder)
			part(model, Vector3.new(3.5, 1.6, 1.6), CFrame.new(x + 1.8, h * 0.55, z), Color3.fromRGB(80, 140, 70), Enum.Material.Grass)
			part(model, Vector3.new(3.2, 1.6, 1.6), CFrame.new(x + 3, h * 0.55 + 1.6, z) * CFrame.Angles(0, 0, math.rad(90)), Color3.fromRGB(80, 140, 70), Enum.Material.Grass, Enum.PartType.Cylinder)
		end
	end
	local rockColor = if valley then Color3.fromRGB(120, 120, 124) else Color3.fromRGB(176, 120, 84)
	for _ = 1, 10 do
		local x = (if rand() < 0.5 then -1 else 1) * (HALF_W + 12 + rand() * 50)
		local z = (rand() * 2 - 1) * (HALF_L + DEPTH)
		local s = 4 + rand() * 5
		part(model, Vector3.new(s * 1.3, s * 0.7, s), CFrame.new(x, s * 0.25, z) * CFrame.Angles(0, rand() * 6, 0), rockColor, Enum.Material.Slate)
	end
end

-- Returns the camera so callers can orbit it.
function MapPreview.Build(viewport: ViewportFrame, themeId: string): Camera
	viewport:ClearAllChildren()
	local theme = Themes.Get(themeId)
	local model = Instance.new("Model")
	model.Name = "Preview"

	part(model, Vector3.new(520, 2, 680), CFrame.new(0, -1.1, 0), theme.SurroundColor, theme.Surround)
	part(model, Vector3.new(HALF_W * 2, 1, HALF_L * 2), CFrame.new(0, -0.45, 0), theme.GroundColor, theme.Ground)
	local stripes = 11
	local len = HALF_L * 2 / stripes
	for i = 0, stripes - 1, 2 do
		part(model, Vector3.new(HALF_W * 2, 0.1, len), CFrame.new(0, 0.1, -HALF_L + len * (i + 0.5)), theme.StripeColor, theme.Ground)
	end
	for _, side in { "A", "B" } do
		local sign = if side == "A" then -1 else 1
		part(model, Vector3.new(HALF_W * 2, 1, DEPTH), CFrame.new(0, -0.45, sign * (HALF_L + DEPTH / 2)), theme.SafeColor, theme.SafeMaterial)
		part(model, Vector3.new(HALF_W * 2, 0.2, 2), CFrame.new(0, 0.15, sign * HALF_L), Color3.new(1, 1, 1))
		-- arch
		local color = Themes.SideColors[side]
		for _, sx in { -1, 1 } do
			part(model, Vector3.new(2.6, 20, 2.6), CFrame.new(sx * (HALF_W + 2), 10, sign * HALF_L), Color3.fromRGB(40, 42, 48), Enum.Material.Metal)
		end
		part(model, Vector3.new(HALF_W * 2 + 6, 4, 1.4), CFrame.new(0, 21, sign * HALF_L), color)
	end
	-- fences
	local outer = HALF_L + DEPTH
	for _, sx in { -1, 1 } do
		part(model, Vector3.new(0.6, 3.4, outer * 2), CFrame.new(sx * (HALF_W + 1), 1.7, 0), theme.FenceColor, Enum.Material.Wood)
	end
	for _, sz in { -1, 1 } do
		part(model, Vector3.new(HALF_W * 2 + 2, 3.4, 0.6), CFrame.new(0, 1.7, sz * (outer + 1)), theme.FenceColor, Enum.Material.Wood)
	end
	-- hills
	local rand = seq(if themeId == "Dunes" then 4831 else 1384)
	for i = 1, 12 do
		local a = i / 12 * math.pi * 2
		local s = 120 + rand() * 80
		part(model, Vector3.new(s, s, s), CFrame.new(math.cos(a) * 230, -s * 0.4, math.sin(a) * 300), theme.HillColor, theme.HillMaterial, Enum.PartType.Ball)
	end
	decor(model, themeId, rand)
	model.Parent = viewport

	local cam = Instance.new("Camera")
	cam.FieldOfView = 38
	cam.CFrame = CFrame.lookAt(Vector3.new(210, 190, 260), Vector3.new(0, 0, 0))
	cam.Parent = viewport
	viewport.CurrentCamera = cam
	viewport.Ambient = theme.Lighting.Ambient or Color3.fromRGB(120, 120, 130)
	viewport.LightColor = Color3.fromRGB(255, 248, 235)
	viewport.LightDirection = Vector3.new(-0.6, -1, -0.4)
	return cam
end

-- Orbit the camera around the field; `t` is seconds.
function MapPreview.Orbit(cam: Camera, t: number)
	local a = t * 0.25
	local pos = Vector3.new(math.cos(a) * 330, 190, math.sin(a) * 330)
	cam.CFrame = CFrame.lookAt(pos, Vector3.zero)
end

return MapPreview
