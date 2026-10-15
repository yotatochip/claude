--!strict
-- Things abilities leave on the field: bear traps, banana peels, bowling
-- balls and pocket doors. Contact is checked by distance every frame,
-- which is steadier than Touched for client-simulated characters.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Net = require(Shared.Net)
local Groups = require(script.Parent.Groups)
local MapBuilder = require(script.Parent.MapBuilder)
local Roster = require(script.Parent.Roster)
local Status = require(script.Parent.Status)

local Effect = Net.Event("Effect")
local Notify = Net.Event("Notify")

type Hazard = {
	Kind: string,
	Model: any, -- a Part or a Model
	Owner: any,
	TargetRole: string,
	Expires: number,
	Radius: number,
	-- bowling ball
	Dir: Vector3?,
	Speed: number?,
	Traveled: number?,
	MaxDistance: number?,
	-- door
	HP: number?,
}

local Hazards = {}

local active: { Hazard } = {}

local function make(className: string, props: { [string]: any }, parent: Instance): BasePart
	local p = Instance.new(className) :: BasePart
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.TopSurface = Enum.SurfaceType.Smooth
	p.BottomSurface = Enum.SurfaceType.Smooth
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = parent
	return p
end

-- Keep things on the field and off the safe zones.
local function clampToField(pos: Vector3, margin: number): Vector3
	local x = math.clamp(pos.X, -Arena.HalfWidth + margin, Arena.HalfWidth - margin)
	local z = math.clamp(pos.Z, -Arena.HalfLength + margin, Arena.HalfLength - margin)
	return Vector3.new(x, pos.Y, z)
end

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, 1)
end

local function opposite(role: string): string
	return if role == "Chaser" then "Runner" else "Chaser"
end

---------------------------------------------------------------------------
-- Spawners
---------------------------------------------------------------------------
function Hazards.BearTrap(owner: any, at: Vector3)
	local pos = clampToField(Vector3.new(at.X, 0.25, at.Z), 2)
	local model = Instance.new("Model")
	model.Name = "BearTrap"
	local base = make("Part", {
		Name = "Base",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.3, 3.4, 3.4),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, 0, math.rad(90)),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(70, 70, 76),
	}, model)
	for i = 0, 7 do
		local a = i / 8 * math.pi * 2
		make("WedgePart", {
			Name = "Tooth",
			Size = Vector3.new(0.15, 0.6, 0.35),
			CFrame = CFrame.new(pos + Vector3.new(math.cos(a) * 1.45, 0.4, math.sin(a) * 1.45)) * CFrame.Angles(0, -a, 0),
			Material = Enum.Material.Metal,
			Color = Color3.fromRGB(190, 190, 196),
		}, model)
	end
	model.PrimaryPart = base
	model.Parent = MapBuilder.Dynamic()
	table.insert(active, {
		Kind = "Trap",
		Model = model,
		Owner = owner,
		TargetRole = "Runner",
		Expires = os.clock() + 12,
		Radius = 2.0,
	})
end

function Hazards.BananaPeel(owner: any, at: Vector3)
	local pos = Vector3.new(at.X, 0.2, at.Z)
	local peel = make("Part", {
		Name = "BananaPeel",
		Size = Vector3.new(1.6, 0.25, 1.1),
		CFrame = CFrame.new(pos) * CFrame.Angles(0, math.random() * math.pi * 2, 0),
		Material = Enum.Material.SmoothPlastic,
		Color = Color3.fromRGB(255, 222, 60),
	}, MapBuilder.Dynamic())
	local mesh = Instance.new("SpecialMesh")
	mesh.MeshType = Enum.MeshType.Sphere
	mesh.Parent = peel
	table.insert(active, {
		Kind = "Peel",
		Model = peel,
		Owner = owner,
		TargetRole = opposite(owner.Role),
		Expires = os.clock() + 20,
		Radius = 2.2,
	})
end

function Hazards.BowlingBall(owner: any, from: Vector3, dir: Vector3)
	local d = flat(dir)
	local ball = make("Part", {
		Name = "BowlingBall",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(3, 3, 3),
		Position = Vector3.new(from.X, 1.55, from.Z) + d * 3,
		Material = Enum.Material.SmoothPlastic,
		Reflectance = 0.15,
		Color = Color3.fromRGB(40, 70, 210),
	}, MapBuilder.Dynamic())
	table.insert(active, {
		Kind = "Ball",
		Model = ball,
		Owner = owner,
		TargetRole = "Runner",
		Expires = os.clock() + 3,
		Radius = 2.8,
		Dir = d,
		Speed = 72,
		Traveled = 0,
		MaxDistance = 130,
	})
end

-- Placed between the runner and the closest chaser when one is near,
-- otherwise just ahead. Only chasers collide with it.
function Hazards.PocketDoor(owner: any, root: BasePart)
	local pos = root.Position
	local facing = flat(root.CFrame.LookVector)
	local nearest, best = nil, 32
	for _, e in Roster.WithRole("Chaser") do
		local r = Roster.Root(e)
		if r then
			local d = (r.Position - pos).Magnitude
			if d < best then
				nearest, best = r, d
			end
		end
	end
	local toward = if nearest then flat(nearest.Position - pos) else facing
	local dist = if nearest then math.min(5, best * 0.5) else 6
	local at = clampToField(pos + toward * dist, 3)
	local door = make("Part", {
		Name = "PocketDoor",
		Size = Vector3.new(13, 10, 1.2),
		CFrame = CFrame.lookAt(Vector3.new(at.X, 5, at.Z), Vector3.new(at.X, 5, at.Z) + toward),
		Material = Enum.Material.WoodPlanks,
		Color = Color3.fromRGB(176, 120, 70),
		CanCollide = true,
		CanQuery = true,
	}, MapBuilder.Dynamic())
	door.CollisionGroup = Groups.PocketDoor
	local frame = make("Part", {
		Name = "Frame",
		Size = Vector3.new(14, 1, 1.6),
		CFrame = door.CFrame * CFrame.new(0, 5, 0),
		Material = Enum.Material.Metal,
		Color = Color3.fromRGB(60, 60, 66),
	}, door)
	frame.CollisionGroup = Groups.Pickups
	table.insert(active, {
		Kind = "Door",
		Model = door,
		Owner = owner,
		TargetRole = "Chaser",
		Expires = os.clock() + 6,
		Radius = 0,
		HP = 2,
	})
	Effect:FireAllClients({ Kind = "Door", Position = door.Position })
end

---------------------------------------------------------------------------
-- Knife vs doors: returns true if a swing landed on a door.
---------------------------------------------------------------------------
function Hazards.HitDoor(chaserRoot: BasePart, reach: number): boolean
	local origin = chaserRoot.Position
	local look = flat(chaserRoot.CFrame.LookVector)
	for i, h in active do
		if h.Kind == "Door" then
			local door = h.Model :: BasePart
			local rel = door.CFrame:PointToObjectSpace(origin)
			-- distance from the chaser to the door's plane, within its width
			local planeDist = math.abs(rel.Z)
			local facingDoor = look:Dot(flat(door.Position - origin)) > 0.2
			if planeDist <= reach and math.abs(rel.X) <= 8 and facingDoor then
				h.HP = (h.HP or 1) - 1
				Effect:FireAllClients({ Kind = "DoorHit", Position = door.Position })
				if (h.HP :: number) <= 0 then
					door:Destroy()
					table.remove(active, i)
				end
				return true
			end
		end
	end
	return false
end

---------------------------------------------------------------------------
-- Frame step
---------------------------------------------------------------------------
local function trigger(h: Hazard, target: any)
	if h.Kind == "Trap" then
		Status.Stun(target, 0.5, "Trap")
		Effect:FireAllClients({ Kind = "Trap", Position = (h.Model :: Model):GetPivot().Position })
		if target.Player then
			Notify:FireClient(target.Player, { Kind = "Toast", Text = "BEAR TRAP!", Color = Color3.fromRGB(255, 120, 120), Sound = "Trap" })
		end
	elseif h.Kind == "Peel" then
		Status.Stun(target, 1.2, "Trip")
		Effect:FireAllClients({ Kind = "Slip", Model = target.Model })
		if target.Player then
			Notify:FireClient(target.Player, { Kind = "Toast", Text = "SLIPPED ON A BANANA!", Color = Color3.fromRGB(255, 225, 70), Sound = "Trip" })
		end
	elseif h.Kind == "Ball" then
		Status.Stun(target, 1.0, "Trip")
		Effect:FireAllClients({ Kind = "Slip", Model = target.Model })
		if target.Player then
			Notify:FireClient(target.Player, { Kind = "Toast", Text = "STRIKE! You got bowled over", Color = Color3.fromRGB(120, 160, 255), Sound = "Trip" })
		end
	end
end

local function step(dt: number)
	if #active == 0 then
		return
	end
	local now = os.clock()
	local targets: { [string]: { { Entry: any, Pos: Vector3 } } } = { Runner = {}, Chaser = {} }
	for _, e in Roster.InMatch() do
		if e.Role == "Runner" or e.Role == "Chaser" then
			local r = Roster.Root(e)
			if r and Arena.OnField(r.Position) then
				table.insert(targets[e.Role], { Entry = e, Pos = r.Position })
			end
		end
	end
	for i = #active, 1, -1 do
		local h = active[i]
		local alive = now < h.Expires and h.Model.Parent ~= nil
		if alive and h.Kind == "Ball" then
			local ball = h.Model :: BasePart
			local move = (h.Dir :: Vector3) * (h.Speed :: number) * dt
			local nextPos = ball.Position + move
			h.Traveled = (h.Traveled :: number) + move.Magnitude
			-- roll: spin around the axis perpendicular to travel
			local axis = Vector3.new(0, 1, 0):Cross(h.Dir :: Vector3)
			ball.CFrame = CFrame.fromAxisAngle(axis, move.Magnitude / 1.5) * (ball.CFrame - ball.Position) + nextPos
			if (h.Traveled :: number) > (h.MaxDistance :: number) or not Arena.OnField(nextPos) then
				alive = false
			end
		end
		if alive and h.Kind ~= "Door" then
			local pos = if h.Model:IsA("BasePart") then h.Model.Position else (h.Model :: Model):GetPivot().Position
			for _, t in targets[h.TargetRole] do
				local d = Vector3.new(t.Pos.X - pos.X, 0, t.Pos.Z - pos.Z).Magnitude
				if d <= h.Radius then
					trigger(h, t.Entry)
					alive = false
					break
				end
			end
		end
		if not alive then
			if h.Model.Parent then
				h.Model:Destroy()
			end
			table.remove(active, i)
		end
	end
end

function Hazards.Clear()
	for _, h in active do
		if h.Model.Parent then
			h.Model:Destroy()
		end
	end
	table.clear(active)
end

function Hazards.Start()
	RunService.Heartbeat:Connect(step)
end

return Hazards
