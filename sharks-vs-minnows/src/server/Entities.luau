--!strict
-- A participant is either a real player or a bot. The round code treats both the same way
-- through this module: roles, speed effects, shields, appearance and per-round stats.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)

export type Role = "Lobby" | "Minnow" | "Shark"

export type Effect = { Add: number, Mult: number, Until: number }

export type Entity = {
	Id: string,
	Name: string,
	Player: Player?,
	IsBot: boolean,
	Model: Model?,
	Role: Role,
	Effects: { Effect },
	Frozen: boolean,
	ShieldUntil: number, -- bubble shield: any number of chomps bounce
	PearlUntil: number, -- pearl: blocks exactly one chomp
	RootedUntil: number, -- caught in a net
	SharkSince: number,
	BiteBonus: number, -- extra tag range (Frenzy)
	BiteBonusUntil: number,
	AbilityReadyAt: number,
	ItemReadyAt: number,
	SafeThisCrossing: boolean,
	RoundTags: number,
	RoundCrossings: number,
	InRound: boolean,
	Bot: any, -- AI state for bots
}

local Entities = {}

local list: { Entity } = {}
local byPlayer: { [Player]: Entity } = {}

local function now(): number
	return workspace:GetServerTimeNow()
end
Entities.Now = now

local function new(name: string, player: Player?, isBot: boolean): Entity
	return {
		Id = if player then "p" .. player.UserId else "b" .. name,
		Name = name,
		Player = player,
		IsBot = isBot,
		Model = nil,
		Role = "Lobby",
		Effects = {},
		Frozen = false,
		ShieldUntil = 0,
		PearlUntil = 0,
		RootedUntil = 0,
		SharkSince = 0,
		BiteBonus = 0,
		BiteBonusUntil = 0,
		AbilityReadyAt = 0,
		ItemReadyAt = 0,
		SafeThisCrossing = false,
		RoundTags = 0,
		RoundCrossings = 0,
		InRound = false,
		Bot = nil,
	}
end

function Entities.AddPlayer(player: Player): Entity
	local e = new(player.DisplayName, player, false)
	byPlayer[player] = e
	table.insert(list, e)
	player:SetAttribute("Role", "Lobby")
	return e
end

function Entities.AddBot(name: string, model: Model): Entity
	local e = new(name, nil, true)
	e.Model = model
	table.insert(list, e)
	model:SetAttribute("Role", "Lobby")
	model:SetAttribute("IsBot", true)
	return e
end

function Entities.Remove(e: Entity)
	local i = table.find(list, e)
	if i then
		table.remove(list, i)
	end
	if e.Player then
		byPlayer[e.Player] = nil
	end
end

function Entities.Get(player: Player): Entity?
	return byPlayer[player]
end

function Entities.All(): { Entity }
	return list
end

function Entities.WithRole(role: Role): { Entity }
	local out = {}
	for _, e in list do
		if e.Role == role then
			table.insert(out, e)
		end
	end
	return out
end

function Entities.Humanoid(e: Entity): Humanoid?
	local model = e.Model
	if not model then
		return nil
	end
	local h = model:FindFirstChildOfClass("Humanoid")
	if h and h.Health > 0 then
		return h
	end
	return nil
end

function Entities.Root(e: Entity): BasePart?
	local model = e.Model
	if not model or not Entities.Humanoid(e) then
		return nil
	end
	return model:FindFirstChild("HumanoidRootPart") :: BasePart?
end

function Entities.Position(e: Entity): Vector3?
	local root = Entities.Root(e)
	return if root then root.Position else nil
end

function Entities.Teleport(e: Entity, cf: CFrame)
	local model = e.Model
	if model and model.PrimaryPart then
		model:PivotTo(cf)
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

-- Speed -------------------------------------------------------------------------------

function Entities.AddEffect(e: Entity, add: number, mult: number, duration: number)
	table.insert(e.Effects, { Add = add, Mult = mult, Until = now() + duration })
end

local function baseSpeed(e: Entity): number
	if e.Role == "Shark" then
		return Config.SharkSpeed
	elseif e.Role == "Minnow" then
		return Config.MinnowSpeed
	end
	return Config.LobbySpeed
end

function Entities.UpdateMovement()
	local t = now()
	for _, e in list do
		local h = Entities.Humanoid(e)
		if not h then
			continue
		end
		local add, mult = 0, 1
		for i = #e.Effects, 1, -1 do
			local fx = e.Effects[i]
			if fx.Until <= t then
				table.remove(e.Effects, i)
			else
				add += fx.Add
				mult *= fx.Mult
			end
		end
		local speed = (baseSpeed(e) + add) * mult
		local held = e.Frozen or e.RootedUntil > t
		if held then
			speed = 0
		end
		local player = e.Player
		if player then
			-- Real players move with the client-side momentum controller (Movement.luau), which
			-- builds sprint, dashes and slides on top of this base speed.
			local current = player:GetAttribute("MoveSpeed")
			if typeof(current) ~= "number" or math.abs(current - speed) > 0.05 then
				player:SetAttribute("MoveSpeed", speed)
			end
			if player:GetAttribute("Rooted") ~= held then
				player:SetAttribute("Rooted", held)
			end
			continue
		end
		if e.Bot then
			speed *= e.Bot.SpeedFactor or 1
		end
		if math.abs(h.WalkSpeed - speed) > 0.05 then
			h.WalkSpeed = speed
		end
		-- nobody jumps in Sharks Vs Minnows
		if h.UseJumpPower then
			h.UseJumpPower = false
		end
		if h.JumpHeight ~= 0 then
			h.JumpHeight = 0
		end
	end
end

-- Roles and appearance ---------------------------------------------------------------

local function setCollisionGroup(model: Model, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
end

local function clearDecor(model: Model)
	local old = model:FindFirstChild("SvMDecor")
	if old then
		old:Destroy()
	end
end

local function weldTo(anchor: BasePart, p: BasePart, offset: CFrame)
	p.Anchored = false
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Massless = true
	p.CFrame = anchor.CFrame * offset
	local w = Instance.new("WeldConstraint")
	w.Part0 = anchor
	w.Part1 = p
	w.Parent = p
end

local function decorate(e: Entity)
	local model = e.Model
	if not model then
		return
	end
	clearDecor(model)
	local decor = Instance.new("Folder")
	decor.Name = "SvMDecor"

	local torso = (model:FindFirstChild("UpperTorso") or model:FindFirstChild("Torso")) :: BasePart?
	local lower = (model:FindFirstChild("LowerTorso") or torso) :: BasePart?

	if e.Role == "Shark" then
		local hl = Instance.new("Highlight")
		hl.FillColor = Config.Colors.Shark
		hl.FillTransparency = 0.45
		hl.OutlineColor = Config.Colors.SharkOutline
		hl.OutlineTransparency = 0
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = model
		hl.Parent = decor
		if torso then
			local fin = Instance.new("WedgePart")
			fin.Name = "DorsalFin"
			fin.Size = Vector3.new(0.35, 2.4, 2.2)
			fin.Color = Config.Colors.Shark
			fin.Material = Enum.Material.SmoothPlastic
			weldTo(torso, fin, CFrame.new(0, 1.2, 0.95))
			fin.Parent = decor
		end
	elseif e.Role == "Minnow" then
		local hl = Instance.new("Highlight")
		hl.FillColor = Config.Colors.Minnow
		hl.FillTransparency = 0.7
		hl.OutlineColor = Color3.new(1, 1, 1)
		hl.OutlineTransparency = 0.3
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Adornee = model
		hl.Parent = decor
		if lower then
			local tail = Instance.new("WedgePart")
			tail.Name = "TailFin"
			tail.Size = Vector3.new(0.3, 1.4, 1.2)
			tail.Color = Config.Colors.Minnow
			tail.Material = Enum.Material.SmoothPlastic
			weldTo(lower, tail, CFrame.new(0, 0.1, 0.9) * CFrame.Angles(math.rad(-90), 0, 0))
			tail.Parent = decor
		end
	end
	decor.Parent = model
end

function Entities.SetRole(e: Entity, role: Role)
	e.Role = role
	if role == "Shark" then
		e.SharkSince = now()
	end
	if e.Player then
		e.Player:SetAttribute("Role", role)
	end
	local model = e.Model
	if model then
		model:SetAttribute("Role", role)
		setCollisionGroup(model, if role == "Shark" then "Sharks" else "Default")
		decorate(e)
	end
	-- A new role starts with a fresh ability.
	e.AbilityReadyAt = 0
end

-- Called whenever a new character model appears for an entity.
function Entities.AttachModel(e: Entity, model: Model)
	e.Model = model
	e.Effects = {}
	e.Frozen = false
	model:SetAttribute("Role", e.Role)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") and e.Model == model then
			d.CollisionGroup = if e.Role == "Shark" then "Sharks" else "Default"
		end
	end)
	setCollisionGroup(model, if e.Role == "Shark" then "Sharks" else "Default")
	decorate(e)
end

function Entities.ApplyTrail(e: Entity, trailId: string)
	local model = e.Model
	if not model then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not root then
		return
	end
	local old = root:FindFirstChild("SvMTrail")
	if old then
		old:Destroy()
	end
	for _, name in { "SvMTrailA0", "SvMTrailA1" } do
		local a = root:FindFirstChild(name)
		if a then
			a:Destroy()
		end
	end
	local def = Config.Trails[trailId]
	if not def then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Name = "SvMTrailA0"
	a0.Position = Vector3.new(0, 0.8, 0.4)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Name = "SvMTrailA1"
	a1.Position = Vector3.new(0, -0.8, 0.4)
	a1.Parent = root
	local keys = {}
	for i, c in def.Colors do
		table.insert(keys, ColorSequenceKeypoint.new(if #def.Colors == 1 then 0 else (i - 1) / (#def.Colors - 1), c))
	end
	if #keys == 1 then
		table.insert(keys, ColorSequenceKeypoint.new(1, def.Colors[1]))
	end
	local trail = Instance.new("Trail")
	trail.Name = "SvMTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Color = ColorSequence.new(keys)
	trail.Lifetime = 0.6
	trail.LightEmission = 0.6
	trail.Transparency = NumberSequence.new(0.2, 1)
	trail.FaceCamera = true
	trail.Parent = root
end

function Entities.ResetRoundState(e: Entity)
	e.Effects = {}
	e.Frozen = false
	e.ShieldUntil = 0
	e.PearlUntil = 0
	e.RootedUntil = 0
	e.BiteBonus = 0
	e.BiteBonusUntil = 0
	e.AbilityReadyAt = 0
	e.ItemReadyAt = 0
	e.SafeThisCrossing = false
	e.RoundTags = 0
	e.RoundCrossings = 0
	if e.Player then
		e.Player:SetAttribute("AbilityReadyAt", 0)
		e.Player:SetAttribute("ItemReadyAt", 0)
		e.Player:SetAttribute("ShieldUntil", 0)
	end
end

function Entities.PlayerList(): { Player }
	local out = {}
	for _, p in Players:GetPlayers() do
		if byPlayer[p] then
			table.insert(out, p)
		end
	end
	return out
end

return Entities
