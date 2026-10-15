--!strict
-- Bots fill empty slots so a match always has people to juke and chase.
-- They move with the same momentum rules as players and use the same
-- Combat/Abilities entry points, so they can break ankles and get theirs
-- broken.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local MoveMath = require(Shared.MoveMath)
local Net = require(Shared.Net)
local Abilities = require(script.Parent.Abilities)
local Combat = require(script.Parent.Combat)
local Gems = require(script.Parent.Gems)
local Phase = require(script.Parent.Phase)
local Roster = require(script.Parent.Roster)
local Status = require(script.Parent.Status)

local Mv = Config.Movement
local B = Config.Bots

local Effect = Net.Event("Effect")

local Bots = {}

local bots: { any } = {}
local rng = Random.new()

-- Roblox's default R15 animations (public, owned by Roblox).
local ANIMS = {
	Idle = "rbxassetid://507766666",
	Run = "rbxassetid://507767714",
}

local SKINS = {
	Color3.fromRGB(255, 220, 177), Color3.fromRGB(234, 184, 146), Color3.fromRGB(196, 140, 98),
	Color3.fromRGB(141, 85, 54), Color3.fromRGB(99, 61, 40), Color3.fromRGB(253, 234, 141),
}
local SHIRTS = {
	Color3.fromRGB(230, 60, 60), Color3.fromRGB(50, 120, 230), Color3.fromRGB(60, 190, 90),
	Color3.fromRGB(250, 190, 40), Color3.fromRGB(150, 80, 220), Color3.fromRGB(30, 30, 36),
	Color3.fromRGB(240, 240, 240), Color3.fromRGB(255, 120, 180), Color3.fromRGB(40, 200, 200),
}
local PANTS = {
	Color3.fromRGB(40, 50, 80), Color3.fromRGB(30, 30, 34), Color3.fromRGB(110, 80, 60),
	Color3.fromRGB(70, 70, 76), Color3.fromRGB(200, 200, 205),
}

local function pick<T>(list: { T }): T
	return list[rng:NextInteger(1, #list)]
end

local function folder(): Folder
	local f = workspace:FindFirstChild("Bots")
	if not f then
		f = Instance.new("Folder")
		f.Name = "Bots"
		f.Parent = workspace
	end
	return f :: Folder
end

local function makeModel(name: string): Model?
	local desc = Instance.new("HumanoidDescription")
	local skin = pick(SKINS)
	desc.HeadColor = skin
	desc.LeftArmColor = skin
	desc.RightArmColor = skin
	desc.TorsoColor = pick(SHIRTS)
	local legs = pick(PANTS)
	desc.LeftLegColor = legs
	desc.RightLegColor = legs
	local ok, result = pcall(function()
		return Players:CreateHumanoidModelFromDescription(desc, Enum.HumanoidRigType.R15)
	end)
	if not ok or not result then
		warn("[BreakAnkles] Couldn't build a bot: " .. tostring(result))
		return nil
	end
	local model = result :: Model
	model.Name = name
	local animate = model:FindFirstChild("Animate")
	if animate then
		animate:Destroy()
	end
	return model
end

local function randomLoadout(): any
	local runner = Catalog.Sorted(Catalog.Abilities, function(a)
		return a.Role == "Runner"
	end)
	local chaser = Catalog.Sorted(Catalog.Abilities, function(a)
		return a.Role == "Chaser"
	end)
	return {
		Runner = pick(runner).Id,
		Chaser = pick(chaser).Id,
		Item = "",
		Knife = pick({ "Classic", "Classic", "Rusty", "Candy", "Neon" }),
		Title = "Rookie",
	}
end

---------------------------------------------------------------------------
-- Animation
---------------------------------------------------------------------------
local function loadTracks(model: Model, b: any)
	local hum = model:FindFirstChildOfClass("Humanoid")
	if not hum then
		return
	end
	local animator = hum:FindFirstChildOfClass("Animator")
	if not animator then
		local created = Instance.new("Animator")
		created.Parent = hum
		animator = created
	end
	for name, id in ANIMS do
		local anim = Instance.new("Animation")
		anim.AnimationId = id
		local ok, track = pcall(function()
			return (animator :: Animator):LoadAnimation(anim)
		end)
		if ok and track then
			track.Looped = true
			b.Tracks[name] = track
		end
	end
end

local function setAnim(b: any, speed: number)
	local want = if speed > 1.5 then "Run" else "Idle"
	if b.CurrentAnim ~= want then
		local cur = b.Tracks[b.CurrentAnim]
		if cur then
			cur:Stop(0.2)
		end
		local nextTrack = b.Tracks[want]
		if nextTrack then
			nextTrack:Play(0.2)
		end
		b.CurrentAnim = want
	end
	if want == "Run" and b.Tracks.Run then
		b.Tracks.Run:AdjustSpeed(math.clamp(speed / 18, 0.6, 2.2))
	end
end

---------------------------------------------------------------------------
-- Spawning
---------------------------------------------------------------------------
function Bots.Spawn(count: number): { any }
	local created = {}
	local used: { [string]: boolean } = {}
	for _, e in Roster.All() do
		used[e.Name] = true
	end
	for _ = 1, count do
		local name: string = pick(B.Names)
		local tries = 0
		while used[name] and tries < 30 do
			name = pick(B.Names)
			tries += 1
		end
		used[name] = true
		local model = makeModel(name)
		if model then
			model:PivotTo(CFrame.new(0, 4, 0))
			model.Parent = folder()
			local root = model:FindFirstChild("HumanoidRootPart") :: BasePart?
			if root then
				pcall(function()
					(root :: BasePart):SetNetworkOwner(nil)
				end)
			end
			local entry = Roster.AddBot(name, model, randomLoadout())
			entry.Bot = {
				Vel = Vector3.zero,
				Desired = Vector3.zero,
				DashUntil = 0,
				DashDir = Vector3.zero,
				DashSpeed = 0,
				LockUntil = 0,
				NextDash = 0,
				NextThink = 0,
				Started = false,
				StartAt = 0,
				LaneX = 0,
				Side = 1,
				Seed = rng:NextNumber(0, 100),
				Tracks = {},
				CurrentAnim = nil,
				Fallen = false,
				SwingAt = nil,
				SeenJuke = 0,
				Target = nil,
				Rescue = nil,
				ChannelStart = nil,
				Considered = {},
				NoRescueUntil = 0,
			}
			loadTracks(model, entry.Bot)
			table.insert(bots, entry)
			table.insert(created, entry)
		end
	end
	return created
end

function Bots.DespawnAll()
	for _, e in bots do
		Roster.Remove(e)
		if e.Model then
			e.Model:Destroy()
		end
	end
	table.clear(bots)
end

local function startDash(e: any, dir: Vector3, speed: number, duration: number)
	local b = e.Bot
	b.DashDir = MoveMath.FlatUnit(dir, Vector3.new(0, 0, 1))
	b.DashSpeed = speed
	b.DashUntil = os.clock() + duration
	b.Vel = b.DashDir * MoveMath.MaxSpeed(e.Role)
end

Status.BotImpulse = function(e: any, velocity: Vector3, lock: number)
	local b = e.Bot
	if b then
		b.Vel = MoveMath.Flat(velocity)
		b.DashUntil = 0
		b.LockUntil = os.clock() + lock
	end
end

Status.BotRocket = function(e: any)
	local b = e.Bot
	local root = Roster.Root(e)
	if b and root then
		local dir = if b.Desired.Magnitude > 0.1 then b.Desired else root.CFrame.LookVector
		startDash(e, dir, Mv.RocketSpeed, Mv.RocketTime)
	end
end

---------------------------------------------------------------------------
-- Thinking
---------------------------------------------------------------------------
local function inSafe(pos: Vector3): boolean
	return Arena.InSafeZone(pos, "A") or Arena.InSafeZone(pos, "B")
end

local function nearestChaser(pos: Vector3, within: number): (any?, number, Vector3?)
	local best, bestD, bestPos = nil, within, nil
	for _, c in Roster.WithRole("Chaser") do
		local r = Roster.Root(c)
		if r then
			local d = MoveMath.Flat(r.Position - pos).Magnitude
			if d < bestD then
				best, bestD, bestPos = c, d, r.Position
			end
		end
	end
	return best, bestD, bestPos
end

local function stopChannel(e: any)
	local b = e.Bot
	b.ChannelStart = nil
	if e.Model then
		e.Model:SetAttribute("Channeling", nil)
	end
end

local function thinkRescue(e: any, pos: Vector3): boolean
	local b = e.Bot
	local now = os.clock()
	if not b.Rescue and now >= b.NoRescueUntil then
		for _, d in Roster.WithRole("Downed") do
			local r = Roster.Root(d)
			if r and not b.Considered[d] then
				b.Considered[d] = true
				local dist = MoveMath.Flat(r.Position - pos).Magnitude
				local _, threatD = nearestChaser(r.Position, 14)
				if dist < 38 and threatD >= 14 and rng:NextNumber() < 0.6 then
					b.Rescue = d
					break
				end
			end
		end
	end
	local t = b.Rescue
	if not t then
		return false
	end
	local troot = Roster.Root(t)
	if t.Role ~= "Downed" or not t.InMatch or not troot then
		b.Rescue = nil
		stopChannel(e)
		return false
	end
	local _, threatD = nearestChaser(pos, 9)
	if threatD < 9 then
		b.Rescue = nil
		b.NoRescueUntil = now + 3
		stopChannel(e)
		return false
	end
	local d = MoveMath.Flat(troot.Position - pos).Magnitude
	if d > 4.5 then
		stopChannel(e)
		b.Desired = MoveMath.FlatUnit(troot.Position - pos)
		return true
	end
	b.Desired = Vector3.zero
	if not b.ChannelStart then
		b.ChannelStart = now
		if e.Model then
			e.Model:SetAttribute("Channeling", true)
		end
	elseif now - b.ChannelStart >= Config.Match.ReviveHoldTime then
		stopChannel(e)
		b.Rescue = nil
		Combat.Revive(t, e)
	end
	return true
end

local function thinkRunner(e: any, pos: Vector3)
	local b = e.Bot
	local now = os.clock()
	local heroRun = Phase.Name == "HeroRun"
	if not Phase.IsLive() or (heroRun and not e.IsHero) then
		b.Desired = Vector3.zero
		b.Started = false
		stopChannel(e)
		return
	end
	local dir = Phase.Direction
	local start = Arena.StartSide(dir)
	local target = Arena.TargetSide(dir)
	if not b.Started then
		b.Started = true
		b.StartAt = now + (if e.IsHero then 0.2 else rng:NextNumber(0, 4.5))
		b.LaneX = rng:NextNumber(-Arena.HalfWidth + 10, Arena.HalfWidth - 10)
		b.Considered = {}
	end
	if now < b.StartAt and Arena.InSafeZone(pos, start) then
		b.Desired = Vector3.zero
		return
	end
	local lineZ = Arena.LineZ(target)
	local sign = if target == "B" then 1 else -1
	if Arena.InSafeZone(pos, target) and (pos.Z - lineZ) * sign > 6 then
		b.Desired = Vector3.zero
		return
	end
	if thinkRescue(e, pos) then
		return
	end
	local goal = Vector3.new(b.LaneX, 0, lineZ + sign * 12)
	local toGoal = MoveMath.FlatUnit(goal - pos, Vector3.new(0, 0, sign))
	local lateral = Vector3.new(-toGoal.Z, 0, toGoal.X)
	local threat, tdist, tpos = nearestChaser(pos, 32)
	local desired = toGoal
	if threat and tpos then
		local rel = MoveMath.FlatUnit(tpos - pos, toGoal)
		local away = -rel
		if rng:NextNumber() < 0.03 then
			b.Side = if lateral:Dot(away) >= 0 then 1 else -1
		end
		local ahead = rel:Dot(toGoal) > 0.15
		if ahead then
			desired = toGoal * 0.45 + lateral * b.Side + away * 0.35
		else
			desired = toGoal + away * 0.4
		end
		desired = MoveMath.FlatUnit(desired, toGoal)
		-- Cut back the other way when the chaser commits: the ankle breaker.
		if tdist < 9 and now >= b.NextDash and rng:NextNumber() < B.RunnerDashChance then
			b.Side = -b.Side
			startDash(e, lateral * b.Side + toGoal * 0.35, Mv.DashSpeed, Mv.DashTime)
			b.NextDash = now + Mv.DashCooldown + rng:NextNumber(0.1, 0.7)
			Combat.Juke(e)
			Effect:FireAllClients({ Kind = "Dash", Model = e.Model })
		end
		if tdist < 7 and rng:NextNumber() < 0.25 then
			Abilities.Use(e)
		end
	else
		desired = MoveMath.FlatUnit(toGoal + lateral * math.sin(now * 1.3 + b.Seed) * 0.35, toGoal)
		-- Grab a nearby gem if it's roughly on the way.
		for _, gem in Gems.List() do
			local rel = MoveMath.Flat(gem.Position - pos)
			if rel.Magnitude < 14 and rel.Unit:Dot(toGoal) > 0.2 then
				desired = rel.Unit
				break
			end
		end
	end
	b.Desired = desired
end

local function thinkChaser(e: any, pos: Vector3, root: BasePart)
	local b = e.Bot
	local now = os.clock()
	if not Phase.IsLive() then
		b.Desired = Vector3.zero
		b.SwingAt = nil
		return
	end
	local heroOnly = Phase.Name == "HeroRun"
	local best, bestScore = nil, math.huge
	for _, r in Roster.WithRole("Runner") do
		local rr = Roster.Root(r)
		if rr and not inSafe(rr.Position) and not (r.Model and r.Model:GetAttribute("Cloaked")) and (not heroOnly or r.IsHero) then
			local d = MoveMath.Flat(rr.Position - pos).Magnitude
			local score = if r == b.Target then d * 0.75 else d
			if score < bestScore then
				best, bestScore = r, score
			end
		end
	end
	b.Target = best
	if not best then
		-- Hold midfield on the runners' side, ready for the next one out.
		local startZ = Arena.LineZ(Arena.StartSide(Phase.Direction))
		local goal = Vector3.new(math.sin(now * 0.4 + b.Seed) * 25, 0, startZ * 0.4)
		local rel = MoveMath.Flat(goal - pos)
		b.Desired = if rel.Magnitude > 4 then rel.Unit else Vector3.zero
		b.SwingAt = nil
		return
	end
	local troot = Roster.Root(best) :: BasePart
	local tpos = troot.Position
	local tvel = MoveMath.Flat(troot.AssemblyLinearVelocity)
	local d = MoveMath.Flat(tpos - pos).Magnitude
	local lead = math.clamp(d / 40, 0.05, 0.4)
	local aim = tpos + tvel * lead
	aim = Vector3.new(aim.X, 0, math.clamp(aim.Z, -Arena.HalfLength + 1, Arena.HalfLength - 1))
	b.Desired = MoveMath.FlatUnit(aim - pos)

	local reach = Config.Knife.Reach * (if now < e.BigDaggerUntil then 2 else 1)
	if d <= reach * 0.9 then
		if not b.SwingAt then
			b.SwingAt = now + rng:NextNumber(B.ReactionTime[1], B.ReactionTime[2])
		end
	else
		b.SwingAt = nil
	end
	-- Biting on a juke: swing at where the runner was.
	if best.LastJuke > b.SeenJuke and now - best.LastJuke < 0.25 and d < reach * 1.7 then
		b.SeenJuke = best.LastJuke
		if rng:NextNumber() < B.FakeOutChance then
			Combat.Swing(e)
			b.SwingAt = nil
		end
	end
	if b.SwingAt and now >= b.SwingAt then
		Combat.Swing(e)
		b.SwingAt = nil
	end
	-- Abilities, used when the target is at a useful distance and ahead.
	local facing = MoveMath.FlatUnit(root.CFrame.LookVector):Dot(MoveMath.FlatUnit(tpos - pos)) > 0.75
	local id = Roster.Loadout(e).Chaser
	local want = false
	if id == "BearTrap" or id == "BowlingBall" then
		want = facing and d > 8 and d < 22
	elseif id == "RocketShoes" then
		want = facing and d > 14 and d < 30
	elseif id == "RufusLeash" then
		want = facing and d > reach and d < 14
	elseif id == "BigDagger" then
		want = d > reach and d < reach * 1.8
	end
	if want and rng:NextNumber() < 0.3 then
		Abilities.Use(e)
	end
end

---------------------------------------------------------------------------
-- Moving
---------------------------------------------------------------------------
local function stepBot(e: any, dt: number)
	local b = e.Bot
	local model = e.Model
	if not b or not model or not model.Parent then
		return
	end
	local hum = model:FindFirstChildOfClass("Humanoid")
	local root = Roster.Root(e)
	if not hum or not root then
		return
	end
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local stunUntil = model:GetAttribute("StunUntil")
	local stunned = type(stunUntil) == "number" and serverNow < stunUntil
	local fallen = e.Role == "Downed" or (stunned and model:GetAttribute("StunKind") == "Trip")

	if fallen and not b.Fallen then
		b.Fallen = true
		hum.PlatformStand = true
		root.AssemblyAngularVelocity = root.CFrame.RightVector * 7
		root.AssemblyLinearVelocity += Vector3.new(0, 6, 0)
	elseif not fallen and b.Fallen then
		b.Fallen = false
		hum.PlatformStand = false
		local p = root.Position
		local look = MoveMath.FlatUnit(root.CFrame.LookVector, Vector3.new(0, 0, 1))
		model:PivotTo(CFrame.lookAt(Vector3.new(p.X, 3, p.Z), Vector3.new(p.X, 3, p.Z) + look))
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end

	if fallen or stunned or model:GetAttribute("Channeling") then
		b.Vel = Vector3.zero
		b.DashUntil = 0
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero)
		setAnim(b, 0)
		return
	end
	if now < b.DashUntil then
		hum.WalkSpeed = b.DashSpeed
		hum:Move(b.DashDir)
		setAnim(b, b.DashSpeed)
		return
	end
	local maxSpeed = MoveMath.MaxSpeed(e.Role) * MoveMath.SpeedMult(model, serverNow)
	local input = if now < b.LockUntil then Vector3.zero else b.Desired
	local hasInput = input.Magnitude > 0.01
	local accel = MoveMath.Accel(e.Role) * (if MoveMath.Boosted(model, serverNow) then 1.3 else 1)
	b.Vel = MoveMath.Approach(b.Vel, input * maxSpeed, hasInput, accel, dt)
	local speed = b.Vel.Magnitude
	hum.WalkSpeed = speed
	hum:Move(if speed > 0.3 then b.Vel.Unit else Vector3.zero)
	setAnim(b, speed)
end

function Bots.Start()
	RunService.Heartbeat:Connect(function(dt)
		local now = os.clock()
		for _, e in bots do
			if e.InMatch then
				stepBot(e, dt)
				local b = e.Bot
				if b and now >= b.NextThink then
					b.NextThink = now + 0.1 + rng:NextNumber(0, 0.05)
					local root = Roster.Root(e)
					if root then
						if e.Role == "Runner" then
							thinkRunner(e, root.Position)
						elseif e.Role == "Chaser" then
							thinkChaser(e, root.Position, root)
						else
							b.Desired = Vector3.zero
						end
					end
				end
			end
		end
	end)
end

function Bots.List(): { any }
	return bots
end

return Bots
