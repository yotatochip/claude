--!strict
-- Server side of every ability (E) and consumable (1/2/3). The server owns cooldowns,
-- item counts and anything that affects other players; clients only draw the extras.

local Debris = game:GetService("Debris")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Entities = require(script.Parent.Entities)
local PlayerData = require(script.Parent.PlayerData)

type Entity = Entities.Entity

local Abilities = {}

local now = Entities.Now

-- Set by the round loop: abilities only work while minnows are crossing.
Abilities.Active = false

local fxFolder = Instance.new("Folder")
fxFolder.Name = "SvMEffects"
fxFolder.Parent = workspace

type Net = { Part: Part, Owner: Entity, Expires: number }
local nets: { Net } = {}

type Pool = { Center: Vector3, Radius: number, Expires: number, Part: Part }
local pools: { Pool } = {}

local function inWater(pos: Vector3): boolean
	return math.abs(pos.X) < Config.SafeLine
end
Abilities.InWater = inWater

local function equipped(e: Entity): string
	if e.IsBot then
		return (e.Bot and e.Bot.Ability) or Config.DefaultAbility[e.Role] or ""
	end
	local data = e.Player and PlayerData.Get(e.Player)
	if data then
		if e.Role == "Shark" then
			return data.Equipped.Shark
		elseif e.Role == "Minnow" then
			return data.Equipped.Minnow
		end
	end
	return ""
end
Abilities.Equipped = equipped

local function aura(e: Entity, color: Color3, duration: number)
	if e.Model then
		Remotes.Effect:FireAllClients("Aura", { Model = e.Model, Color = color, Duration = duration })
	end
end

local function burst(pos: Vector3, color: Color3, size: number)
	Remotes.Effect:FireAllClients("Burst", { Position = pos, Color = color, Size = size })
end

local function bubble(e: Entity, duration: number, color: Color3, size: number)
	local root = Entities.Root(e)
	if not root then
		return
	end
	local ball = Instance.new("Part")
	ball.Name = "Bubble"
	ball.Shape = Enum.PartType.Ball
	ball.Size = Vector3.one * size
	ball.Material = Enum.Material.ForceField
	ball.Color = color
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Massless = true
	ball.CFrame = root.CFrame
	local weld = Instance.new("WeldConstraint")
	weld.Part0 = root
	weld.Part1 = ball
	weld.Parent = ball
	ball.Parent = e.Model
	Debris:AddItem(ball, duration)
end

local function setReady(e: Entity, field: "AbilityReadyAt" | "ItemReadyAt", at: number)
	(e :: any)[field] = at
	if e.Player then
		e.Player:SetAttribute(field, at)
	end
end

-- Abilities ------------------------------------------------------------------------------

local handlers: { [string]: (Entity, BasePart) -> () } = {}

handlers.Dash = function(e, root)
	Entities.AddEffect(e, 34, 1, 0.4)
	aura(e, Config.Abilities.Dash.Color, 0.5)
	burst(root.Position, Config.Abilities.Dash.Color, 4)
end

handlers.Bubble = function(e, _root)
	e.ShieldUntil = now() + 2.5
	if e.Player then
		e.Player:SetAttribute("ShieldUntil", e.ShieldUntil)
	end
	bubble(e, 2.5, Config.Abilities.Bubble.Color, 7)
end

handlers.Ink = function(e, root)
	local pos = root.Position
	local cloud = Instance.new("Part")
	cloud.Name = "InkCloud"
	cloud.Anchored = true
	cloud.CanCollide = false
	cloud.CanQuery = false
	cloud.CanTouch = false
	cloud.Transparency = 1
	cloud.Size = Vector3.one
	cloud.Position = pos
	local smoke = Instance.new("ParticleEmitter")
	smoke.Texture = "rbxasset://textures/particles/smoke_main.dds"
	smoke.Color = ColorSequence.new(Color3.fromRGB(30, 15, 50))
	smoke.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 6), NumberSequenceKeypoint.new(1, 16) })
	smoke.Transparency = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.2), NumberSequenceKeypoint.new(1, 1) })
	smoke.Lifetime = NumberRange.new(2, 3)
	smoke.Rate = 0
	smoke.Speed = NumberRange.new(8, 14)
	smoke.SpreadAngle = Vector2.new(180, 180)
	smoke.Drag = 3
	smoke.Parent = cloud
	cloud.Parent = fxFolder
	smoke:Emit(60)
	Debris:AddItem(cloud, 4)

	for _, shark in Entities.WithRole("Shark") do
		local p = Entities.Position(shark)
		if p and (p - pos).Magnitude < 18 then
			Entities.AddEffect(shark, 0, 0.5, 2.5)
			if shark.Player then
				Remotes.Effect:FireClient(shark.Player, "Inked", { Duration = 1.8 })
			end
			if shark.Bot then
				shark.Bot.ConfusedUntil = now() + 2
			end
		end
	end
end

handlers.Riptide = function(e, _root)
	Entities.AddEffect(e, 9, 1, 3)
	aura(e, Config.Abilities.Riptide.Color, 3)
end

handlers.Lunge = function(e, root)
	Entities.AddEffect(e, 42, 1, 0.4)
	e.BiteBonus = 1.6
	e.BiteBonusUntil = now() + 0.6
	aura(e, Config.Abilities.Lunge.Color, 0.5)
	burst(root.Position, Config.Abilities.Lunge.Color, 4)
end

handlers.Sonar = function(e, root)
	burst(root.Position, Config.Abilities.Sonar.Color, 40)
	if e.Player then
		Remotes.Effect:FireClient(e.Player, "Sonar", { Duration = 4 })
	end
	for _, m in Entities.WithRole("Minnow") do
		if m.Player then
			Remotes.Notify:FireClient(m.Player, "📡 A shark pinged your location!", Config.Abilities.Sonar.Color)
		end
	end
end

handlers.Frenzy = function(e, _root)
	Entities.AddEffect(e, 8, 1, 3.5)
	e.BiteBonus = 1.5
	e.BiteBonusUntil = now() + 3.5
	aura(e, Config.Abilities.Frenzy.Color, 3.5)
end

handlers.Whirlpool = function(_e, root)
	local center = Vector3.new(root.Position.X, 0.3, root.Position.Z)
	local ring = Instance.new("Part")
	ring.Name = "Whirlpool"
	ring.Shape = Enum.PartType.Cylinder
	ring.Anchored = true
	ring.CanCollide = false
	ring.CanQuery = false
	ring.CanTouch = false
	ring.Material = Enum.Material.Neon
	ring.Color = Config.Abilities.Whirlpool.Color
	ring.Transparency = 0.55
	ring.Size = Vector3.new(0.4, 4, 4)
	ring.CFrame = CFrame.new(center) * CFrame.Angles(0, 0, math.rad(90))
	ring.Parent = fxFolder
	local radius = 20
	TweenService:Create(ring, TweenInfo.new(0.5, Enum.EasingStyle.Back), { Size = Vector3.new(0.4, radius * 2, radius * 2) }):Play()
	TweenService:Create(ring, TweenInfo.new(3, Enum.EasingStyle.Linear), { CFrame = ring.CFrame * CFrame.Angles(math.rad(720), 0, 0) }):Play()
	Debris:AddItem(ring, 3)
	table.insert(pools, { Center = center, Radius = radius, Expires = now() + 3, Part = ring })
end

local function bounds(e: Entity): (BasePart?, boolean)
	if not Abilities.Active or not e.InRound or e.Role == "Lobby" then
		return nil, false
	end
	local root = Entities.Root(e)
	return root, root ~= nil
end

function Abilities.UseAbility(e: Entity): boolean
	local root, ok = bounds(e)
	if not ok or not root then
		return false
	end
	local id = equipped(e)
	local def = Config.Abilities[id]
	if not def or def.Role ~= e.Role then
		return false
	end
	local t = now()
	if t < e.AbilityReadyAt then
		return false
	end
	setReady(e, "AbilityReadyAt", t + def.Cooldown)
	handlers[id](e, root)
	return true
end

-- Consumables ----------------------------------------------------------------------------

local itemHandlers: { [string]: (Entity, BasePart) -> () } = {}

itemHandlers.Kelp = function(e, root)
	Entities.AddEffect(e, 7, 1, 4)
	aura(e, Config.Items.Kelp.Color, 4)
	burst(root.Position, Config.Items.Kelp.Color, 5)
end

itemHandlers.Pearl = function(e, _root)
	e.PearlUntil = now() + 8
	if e.Player then
		e.Player:SetAttribute("ShieldUntil", math.max(e.ShieldUntil, e.PearlUntil))
	end
	bubble(e, 8, Config.Items.Pearl.Color, 5.5)
end

itemHandlers.Net = function(e, root)
	local pos = Vector3.new(root.Position.X, 0.25, root.Position.Z)
	local net = Instance.new("Part")
	net.Name = "Net"
	net.Anchored = true
	net.CanCollide = false
	net.CanQuery = false
	net.CanTouch = false
	net.Size = Vector3.new(9, 0.3, 9)
	net.CFrame = CFrame.new(pos)
	net.Color = Config.Items.Net.Color
	net.Material = Enum.Material.Fabric
	net.Transparency = 0.35
	local sel = Instance.new("SelectionBox")
	sel.Adornee = net
	sel.Color3 = Color3.fromRGB(120, 90, 50)
	sel.LineThickness = 0.08
	sel.Transparency = 0.2
	sel.Parent = net
	net.Parent = fxFolder
	table.insert(nets, { Part = net, Owner = e, Expires = now() + 20 })
end

function Abilities.UseItem(e: Entity, itemId: string): boolean
	local root, ok = bounds(e)
	if not ok or not root then
		return false
	end
	local def = Config.Items[itemId]
	if not def then
		return false
	end
	if def.Role ~= "Any" and def.Role ~= e.Role then
		if e.Player then
			Remotes.Notify:FireClient(e.Player, `{def.Name} is for {def.Role}s only.`, Color3.fromRGB(255, 120, 120))
		end
		return false
	end
	local t = now()
	if t < e.ItemReadyAt then
		return false
	end
	if e.Player then
		local data = PlayerData.Get(e.Player)
		if not data or (data.Items[itemId] or 0) <= 0 then
			Remotes.Notify:FireClient(e.Player, `Out of {def.Name}! Buy more in the shop.`, Color3.fromRGB(255, 120, 120))
			return false
		end
		PlayerData.Update(e.Player, function(d)
			d.Items[itemId] -= 1
		end)
	end
	setReady(e, "ItemReadyAt", t + Config.ItemCooldown)
	itemHandlers[itemId](e, root)
	return true
end

-- Returns true if a chomp on this minnow is blocked (and consumes a pearl if that's what blocked it).
function Abilities.TryBlock(minnow: Entity): boolean
	local t = now()
	if minnow.ShieldUntil > t then
		return true
	end
	if minnow.PearlUntil > t then
		minnow.PearlUntil = 0
		if minnow.Player then
			minnow.Player:SetAttribute("ShieldUntil", minnow.ShieldUntil)
		end
		if minnow.Model then
			for _, child in minnow.Model:GetChildren() do
				if child.Name == "Bubble" then
					child:Destroy()
				end
			end
		end
		local p = Entities.Position(minnow)
		if p then
			burst(p, Config.Items.Pearl.Color, 8)
		end
		return true
	end
	return false
end

-- Nets and whirlpools act on minnows that wander into them.
function Abilities.Step()
	local t = now()
	for i = #nets, 1, -1 do
		local net = nets[i]
		local hit = false
		if t < net.Expires then
			for _, m in Entities.WithRole("Minnow") do
				local p = Entities.Position(m)
				if p and inWater(p) and (Vector3.new(p.X, 0, p.Z) - Vector3.new(net.Part.Position.X, 0, net.Part.Position.Z)).Magnitude < 4.8 then
					m.RootedUntil = t + 1.5
					if m.Player then
						Remotes.Notify:FireClient(m.Player, "🕸️ Caught in a net!", Config.Items.Net.Color)
					end
					burst(p, Config.Items.Net.Color, 6)
					hit = true
					break
				end
			end
		end
		if hit or t >= net.Expires then
			net.Part:Destroy()
			table.remove(nets, i)
		end
	end

	for i = #pools, 1, -1 do
		local pool = pools[i]
		if t >= pool.Expires then
			table.remove(pools, i)
			continue
		end
		for _, m in Entities.WithRole("Minnow") do
			local p = Entities.Position(m)
			if p and inWater(p) and (Vector3.new(p.X, 0, p.Z) - Vector3.new(pool.Center.X, 0, pool.Center.Z)).Magnitude < pool.Radius then
				-- a short slow that keeps getting refreshed while they stay inside
				local refreshed = false
				for _, fx in m.Effects do
					if fx.Mult == 0.55 and fx.Add == 0 then
						fx.Until = t + 0.3
						refreshed = true
					end
				end
				if not refreshed then
					Entities.AddEffect(m, 0, 0.55, 0.3)
				end
			end
		end
	end
end

function Abilities.Clear()
	for _, net in nets do
		net.Part:Destroy()
	end
	table.clear(nets)
	for _, pool in pools do
		pool.Part:Destroy()
	end
	table.clear(pools)
	fxFolder:ClearAllChildren()
end

return Abilities
