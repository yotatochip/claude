--!strict
-- Simple AI swimmers so a round is fun with one or two people in the server.
-- Minnow bots head for the far shore and swerve away from sharks; shark bots chase the
-- closest minnow in the water. Shark bots are tuned a little slower than real players.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Config = require(ReplicatedStorage.Shared.Config)
local Entities = require(script.Parent.Entities)
local Abilities = require(script.Parent.Abilities)

type Entity = Entities.Entity

local Bots = {}

local NAMES = {
	"Gill", "Splash", "Reef", "Ripple", "Pebble", "Mako", "Tuna", "Scales", "Pike", "Wave",
	"Kelpie", "Driftwood", "Barnacle", "Sandbar", "Guppy", "Minnie", "Seafoam", "Tide",
}

local SKIN = {
	Color3.fromRGB(255, 220, 180), Color3.fromRGB(234, 184, 146), Color3.fromRGB(198, 140, 100),
	Color3.fromRGB(141, 95, 65), Color3.fromRGB(95, 60, 40),
}
local SHIRT = {
	Color3.fromRGB(230, 70, 70), Color3.fromRGB(60, 140, 230), Color3.fromRGB(80, 190, 110), Color3.fromRGB(250, 200, 60),
	Color3.fromRGB(170, 90, 220), Color3.fromRGB(240, 240, 240), Color3.fromRGB(40, 40, 50),
}

-- Roblox's default R15 animations
local ANIM: { [string]: string } = {
	Idle = "rbxassetid://507766666",
	Run = "rbxassetid://913376220",
	Sprint = Config.Movement.SprintAnimation,
}

local folder = Instance.new("Folder")
folder.Name = "SvMBots"
folder.Parent = workspace

local bots: { Entity } = {}
local used: { [string]: boolean } = {}

local now = Entities.Now
local SAFE = Config.SafeLine

local function pickName(): string
	for _ = 1, 30 do
		local n = NAMES[math.random(1, #NAMES)]
		if not used[n] then
			used[n] = true
			return n
		end
	end
	return "Fish" .. math.random(100, 999)
end

local function makeModel(name: string): Model
	local desc = Instance.new("HumanoidDescription")
	local skin = SKIN[math.random(1, #SKIN)]
	local shirt = SHIRT[math.random(1, #SHIRT)]
	local pants = SHIRT[math.random(1, #SHIRT)]:Lerp(Color3.new(0, 0, 0), 0.4)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = shirt
	desc.LeftLegColor = pants
	desc.RightLegColor = pants
	local model = Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	model.Name = name
	local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
	humanoid.DisplayName = "🤖 " .. name
	humanoid.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.Viewer
	humanoid.NameDisplayDistance = 60
	humanoid.BreakJointsOnDeath = false
	return model
end

local function setupAnimations(e: Entity, humanoid: Humanoid)
	local animator = humanoid:FindFirstChildOfClass("Animator") or Instance.new("Animator")
	animator.Parent = humanoid
	local tracks = {}
	for key, id in ANIM do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return animator:LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = true
			tracks[key] = track
		end
	end
	e.Bot.Tracks = tracks
	e.Bot.Playing = ""
end

local function animate(e: Entity, root: BasePart)
	local tracks = e.Bot.Tracks
	if not tracks then
		return
	end
	local v = root.AssemblyLinearVelocity
	local speed = Vector3.new(v.X, 0, v.Z).Magnitude
	local want = if speed > Config.MinnowSpeed * 1.12 and tracks.Sprint then "Sprint" elseif speed > 2 then "Run" else "Idle"
	if e.Bot.Playing ~= want then
		local old = tracks[e.Bot.Playing]
		if old then
			old:Stop(0.2)
		end
		local track = tracks[want]
		if track then
			track:Play(0.2)
			if want == "Run" then
				track:AdjustSpeed(1.25)
			end
		end
		e.Bot.Playing = want
	end
end

function Bots.Spawn(count: number): { Entity }
	local made = {}
	for _ = 1, count do
		local name = pickName()
		local model = makeModel(name)
		local e = Entities.AddBot(name, model)
		e.Bot = {
			SpeedFactor = 1,
			Lane = 0,
			NextThink = 0,
			StuckSince = 0,
			DodgeUntil = 0,
			DodgeDir = 1,
			ConfusedUntil = 0,
			Ability = "",
			Reaction = math.random(15, 35) / 100,
			Skill = math.random(70, 100) / 100,
		}
		model:PivotTo(CFrame.new(math.random(-20, 20), 5, math.random(-20, 20)))
		model.Parent = folder
		local root = model:FindFirstChild("HumanoidRootPart") :: BasePart
		root:SetNetworkOwner(nil)
		Entities.AttachModel(e, model)
		local humanoid = model:FindFirstChildOfClass("Humanoid") :: Humanoid
		setupAnimations(e, humanoid)
		table.insert(bots, e)
		table.insert(made, e)
	end
	return made
end

-- Called when a bot's role changes so it picks a matching ability and pace.
function Bots.Configure(e: Entity)
	if not e.Bot then
		return
	end
	if e.Role == "Shark" then
		e.Bot.Ability = if math.random() < 0.3 then "Frenzy" else "Lunge"
		e.Bot.SpeedFactor = 1.06 + 0.08 * e.Bot.Skill
	else
		e.Bot.Ability = if math.random() < 0.5 then "Bubble" else "Dash"
		e.Bot.SpeedFactor = 1.12 + 0.1 * e.Bot.Skill
	end
	e.Bot.Lane = math.random(-Config.ArenaHalfWidth + 10, Config.ArenaHalfWidth - 10)
end

function Bots.NewCrossing()
	for _, e in bots do
		e.Bot.Lane = math.clamp(e.Bot.Lane + math.random(-25, 25), -Config.ArenaHalfWidth + 10, Config.ArenaHalfWidth - 10)
	end
end

function Bots.Clear()
	for _, e in bots do
		Entities.Remove(e)
		if e.Model then
			e.Model:Destroy()
		end
	end
	table.clear(bots)
	table.clear(used)
end

function Bots.Count(): number
	return #bots
end

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function thinkMinnow(e: Entity, root: BasePart, humanoid: Humanoid, dir: number, crossing: boolean)
	local pos = root.Position
	if not crossing or e.SafeThisCrossing then
		-- mill around on the beach
		local idle = Vector3.new(dir * (SAFE + 15), 0, e.Bot.Lane)
		if not crossing then
			idle = Vector3.new(math.sign(pos.X) * (SAFE + 15), 0, e.Bot.Lane)
		end
		if flat(pos - idle).Magnitude > 6 then
			humanoid:MoveTo(idle)
		end
		return
	end

	local goal = Vector3.new(dir * (SAFE + 16), 0, e.Bot.Lane)
	local toGoal = flat(goal - pos)
	local desire = if toGoal.Magnitude > 0 then toGoal.Unit else Vector3.zero

	local nearest, nearestDist = nil :: Vector3?, math.huge
	for _, s in Entities.WithRole("Shark") do
		local sp = Entities.Position(s)
		if sp then
			local d = flat(sp - pos).Magnitude
			if d < nearestDist then
				nearest, nearestDist = sp, d
			end
		end
	end

	local t = now()
	if nearest and nearestDist < 30 then
		local away = flat(pos - nearest)
		away = if away.Magnitude > 0 then away.Unit else Vector3.xAxis
		local weight = (1 - nearestDist / 30) * 1.8 * e.Bot.Skill
		-- swerve sideways rather than running straight back
		local side = Vector3.new(-away.Z, 0, away.X)
		if side:Dot(desire) < 0 then
			side = -side
		end
		desire = (desire + away * weight * 0.6 + side * weight).Unit
		if nearestDist < 9 then
			Abilities.UseAbility(e)
		end
	end

	-- unstick from rocks: if we're barely moving, sidestep for a moment
	local speed = flat(root.AssemblyLinearVelocity).Magnitude
	if speed < 3 and humanoid.WalkSpeed > 5 then
		if e.Bot.StuckSince == 0 then
			e.Bot.StuckSince = t
		elseif t - e.Bot.StuckSince > 0.7 then
			e.Bot.DodgeUntil = t + 1
			e.Bot.DodgeDir = if math.random() < 0.5 then -1 else 1
			e.Bot.StuckSince = 0
		end
	else
		e.Bot.StuckSince = 0
	end
	if t < e.Bot.DodgeUntil then
		desire = Vector3.new(0, 0, e.Bot.DodgeDir) + desire * 0.2
	end

	humanoid:MoveTo(pos + desire * 12)
end

local function thinkShark(e: Entity, root: BasePart, humanoid: Humanoid, dir: number, crossing: boolean)
	local pos = root.Position
	local t = now()
	if t < e.Bot.ConfusedUntil then
		humanoid:MoveTo(pos + Vector3.new(math.random(-10, 10), 0, math.random(-10, 10)))
		return
	end

	local best, bestDist, bestVel = nil :: Vector3?, math.huge, Vector3.zero
	for _, m in Entities.WithRole("Minnow") do
		local r = Entities.Root(m)
		if r and Abilities.InWater(r.Position) then
			local d = flat(r.Position - pos).Magnitude
			if d < bestDist then
				best, bestDist, bestVel = r.Position, d, r.AssemblyLinearVelocity
			end
		end
	end

	if best and crossing then
		local lead = math.clamp(bestDist / 30, 0.1, 0.6) * e.Bot.Skill
		local target = best + flat(bestVel) * lead
		target = Vector3.new(math.clamp(target.X, -SAFE + 2, SAFE - 2), 0, target.Z)
		humanoid:MoveTo(target)
		if bestDist < 11 then
			Abilities.UseAbility(e)
		end
	else
		-- wait in the middle of the lane the minnows are coming from
		local guard = Vector3.new(-dir * 25, 0, math.clamp(e.Bot.Lane * 0.6, -40, 40))
		if flat(guard - pos).Magnitude > 5 then
			humanoid:MoveTo(guard)
		end
	end
end

-- dir: the direction minnows are crossing this time (1 = toward east beach).
function Bots.Step(crossing: boolean, dir: number)
	local t = now()
	for _, e in bots do
		local root = Entities.Root(e)
		local humanoid = Entities.Humanoid(e)
		if not root or not humanoid then
			continue
		end
		animate(e, root)
		if not e.InRound or e.Frozen or t < e.Bot.NextThink then
			continue
		end
		e.Bot.NextThink = t + e.Bot.Reaction * 0.6
		if e.Role == "Minnow" then
			thinkMinnow(e, root, humanoid, dir, crossing)
		elseif e.Role == "Shark" then
			thinkShark(e, root, humanoid, dir, crossing)
		end
	end
end

return Bots
