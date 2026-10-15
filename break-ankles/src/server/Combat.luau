--!strict
-- The knife: swings, hits, shields, ankle breaks, downs, rescues and
-- conversions. All checks happen on the server against server positions,
-- with a little extra reach to cover latency.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Hazards = require(script.Parent.Hazards)
local Phase = require(script.Parent.Phase)
local Rewards = require(script.Parent.Rewards)
local Roster = require(script.Parent.Roster)
local Status = require(script.Parent.Status)

local K = Config.Knife
local R = Config.Rewards
local M = Config.Match

local Effect = Net.Event("Effect")
local Notify = Net.Event("Notify")

local Combat = {}

-- Set by Match so it can count catches toward a flawless run.
Combat.OnCaught = nil :: ((runner: any) -> ())?

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function feed(text: string)
	Notify:FireAllClients({ Kind = "Feed", Text = text })
end

local function tell(entry: any, payload: { [string]: any })
	if entry.Player then
		Notify:FireClient(entry.Player, payload)
	end
end

local function inAnySafeZone(pos: Vector3): boolean
	return Arena.InSafeZone(pos, "A") or Arena.InSafeZone(pos, "B")
end

---------------------------------------------------------------------------
-- Down / revive / convert
---------------------------------------------------------------------------
local function removePrompt(entry: any)
	local model: Model? = entry.Model
	if model then
		local p = model:FindFirstChild("RevivePrompt", true)
		if p then
			p:Destroy()
		end
	end
end

local function clearChanneling()
	for _, e in Roster.InMatch() do
		if e.Model and e.Model:GetAttribute("Channeling") then
			e.Model:SetAttribute("Channeling", nil)
		end
	end
end

function Combat.Revive(target: any, rescuer: any?)
	if target.Role ~= "Downed" then
		return
	end
	removePrompt(target)
	target.ProtectedUntil = os.clock() + 1.2
	Roster.SetRole(target, "Runner")
	Status.Clear(target)
	Effect:FireAllClients({ Kind = "Revive", Model = target.Model })
	if rescuer then
		if rescuer.Model then
			rescuer.Model:SetAttribute("Channeling", nil)
		end
		rescuer.Rescues += 1
		Rewards.Give(rescuer, R.RescueGems, 0, R.RescueXP, "Rescue")
		Rewards.Stat(rescuer, "Rescues", 1)
		feed(("%s rescued %s"):format(rescuer.Name, target.Name))
		tell(target, { Kind = "Announce", Text = "RESCUED!", Sub = rescuer.Name .. " picked you up", Color = Color3.fromRGB(140, 255, 160), Sound = "Safe" })
		tell(rescuer, { Kind = "Toast", Text = "You rescued " .. target.Name .. "!", Color = Color3.fromRGB(140, 255, 160), Sound = "Safe" })
	else
		feed(("%s used a Rescue Kit"):format(target.Name))
		tell(target, { Kind = "Announce", Text = "BACK UP!", Sub = "Rescue Kit used", Color = Color3.fromRGB(140, 255, 160), Sound = "Safe" })
	end
end

function Combat.Convert(entry: any, reason: string?)
	if entry.Role ~= "Runner" and entry.Role ~= "Downed" then
		return
	end
	removePrompt(entry)
	entry.IsHero = false
	entry.GraceUntil = os.clock() + M.ConvertGraceTime
	Status.Clear(entry)
	Roster.SetRole(entry, "Chaser")
	if Combat.OnCaught then
		(Combat.OnCaught :: (any) -> ())(entry)
	end
	local why = if reason == "time" then "ran out of time" else "was converted"
	feed(("%s %s and is now a CHASER"):format(entry.Name, why))
	tell(entry, {
		Kind = "Announce",
		Text = if reason == "time" then "TOO SLOW!" else "YOU'RE A CHASER NOW",
		Sub = "Catch the runners! Click to swing.",
		Color = Color3.fromRGB(255, 90, 90),
		Sound = "Equip",
	})
	Notify:FireAllClients({ Kind = "Counts" })
end

local function startRevivePrompt(entry: any)
	local root = Roster.Root(entry)
	if not root then
		return
	end
	removePrompt(entry)
	local prompt = Instance.new("ProximityPrompt")
	prompt.Name = "RevivePrompt"
	prompt.ActionText = "Revive"
	prompt.ObjectText = entry.Name
	prompt.HoldDuration = M.ReviveHoldTime
	prompt.MaxActivationDistance = M.ReviveRange
	prompt.RequiresLineOfSight = false
	prompt.KeyboardKeyCode = Enum.KeyCode.E
	prompt.GamepadKeyCode = Enum.KeyCode.ButtonX
	prompt.Parent = root
	local function rescuerOf(player: Player): any?
		local e = Roster.ForPlayer(player)
		if e and e ~= entry and e.InMatch and e.Role == "Runner" then
			return e
		end
		return nil
	end
	-- Rescuers are frozen while they hold the prompt; release them if the
	-- prompt goes away mid-hold (revived, converted, or the crossing ended).
	local holders: { [Player]: boolean } = {}
	local function release(player: Player)
		holders[player] = nil
		local e = Roster.ForPlayer(player)
		if e and e.Model then
			e.Model:SetAttribute("Channeling", nil)
		end
	end
	prompt.PromptButtonHoldBegan:Connect(function(player)
		local e = rescuerOf(player)
		if e and e.Model then
			holders[player] = true
			e.Model:SetAttribute("Channeling", true)
		end
	end)
	prompt.PromptButtonHoldEnded:Connect(release)
	prompt.Destroying:Connect(function()
		for player in holders do
			release(player)
		end
	end)
	prompt.Triggered:Connect(function(player)
		local e = rescuerOf(player)
		if not e then
			return
		end
		local r1, r2 = Roster.Root(e), Roster.Root(entry)
		if r1 and r2 and (r1.Position - r2.Position).Magnitude <= M.ReviveRange + 3 then
			Combat.Revive(entry, e)
		end
	end)
end

function Combat.Down(runner: any, by: any)
	if runner.Role ~= "Runner" then
		return
	end
	runner.DownedAt = os.clock()
	runner.DownedBy = by
	runner.ShieldUntil = 0
	if runner.Model and runner.Model:GetAttribute("Cloaked") then
		Roster.SetCloak(runner, false)
	end
	Status.Clear(runner)
	Roster.SetRole(runner, "Downed")
	startRevivePrompt(runner)
	Effect:FireAllClients({ Kind = "Down", Model = runner.Model, By = by.Model })

	by.Catches += 1
	Rewards.Give(by, R.CatchGems, R.CatchCoins, R.CatchXP, "Caught " .. runner.Name)
	Rewards.Stat(by, "Catches", 1)
	feed(("%s caught %s"):format(by.Name, runner.Name))
	tell(by, { Kind = "Toast", Text = "CAUGHT " .. string.upper(runner.Name) .. "!", Color = Color3.fromRGB(255, 90, 90), Sound = "Down" })
	tell(runner, {
		Kind = "Announce",
		Text = "YOU'RE DOWN!",
		Sub = "Wait for a teammate to revive you, or press F to use a Rescue Kit",
		Color = Color3.fromRGB(255, 90, 90),
		Sound = "Down",
	})
	Notify:FireAllClients({ Kind = "Counts" })
end

---------------------------------------------------------------------------
-- Ankle breaks
---------------------------------------------------------------------------
local function ankleBreak(chaser: any, runner: any)
	Status.Stun(chaser, K.AnkleStunTime, "Trip")
	runner.Ankles += 1
	runner.LastJuke = -math.huge -- one break per juke
	Rewards.Give(runner, R.AnkleBreakGems, 0, R.AnkleBreakXP, "Broke " .. chaser.Name .. "'s ankles")
	Rewards.Stat(runner, "Ankles", 1)
	Effect:FireAllClients({ Kind = "AnkleBreak", Chaser = chaser.Model, Runner = runner.Model })
	feed(("%s broke %s's ankles!"):format(runner.Name, chaser.Name))
	tell(runner, { Kind = "Announce", Text = "ANKLES BROKEN!", Sub = "You sent " .. chaser.Name .. " to the floor", Color = Color3.fromRGB(255, 200, 60), Sound = "AnkleBreak" })
	tell(chaser, { Kind = "Announce", Text = "YOUR ANKLES!", Sub = runner.Name .. " juked you", Color = Color3.fromRGB(255, 120, 60), Sound = "AnkleBreak" })
end

---------------------------------------------------------------------------
-- Swing
---------------------------------------------------------------------------
local function resolve(chaser: any, big: boolean)
	if chaser.Role ~= "Chaser" or not Phase.IsLive() then
		return
	end
	local root = Roster.Root(chaser)
	if not root then
		return
	end
	local origin = root.Position
	local look = flat(root.CFrame.LookVector)
	look = if look.Magnitude > 1e-3 then look.Unit else Vector3.new(0, 0, 1)
	local reach = K.Reach * (if big then 2 else 1) + K.Leniency
	local cosLimit = math.cos(math.rad(K.HalfAngle))
	local now = os.clock()

	local best, bestDist = nil, math.huge
	for _, e in Roster.WithRole("Runner") do
		local r = Roster.Root(e)
		if r and now >= e.ProtectedUntil and not inAnySafeZone(r.Position) then
			local offset = r.Position - origin
			local f = flat(offset)
			local d = f.Magnitude
			if d <= reach and math.abs(offset.Y) < 8 then
				local inFront = d <= K.CloseRange or look:Dot(f.Unit) >= cosLimit
				if inFront and d < bestDist then
					best, bestDist = e, d
				end
			end
		end
	end

	if best then
		if now < best.ShieldUntil then
			best.ShieldUntil = 0
			Effect:FireAllClients({ Kind = "ShieldBreak", Model = best.Model })
			tell(best, { Kind = "Toast", Text = "BLOCKED!", Color = Color3.fromRGB(90, 200, 255), Sound = "Stop" })
			tell(chaser, { Kind = "Toast", Text = "Blocked by a shield", Color = Color3.fromRGB(90, 200, 255) })
			Status.Slow(chaser, K.MissSlowMult, K.MissSlowTime)
			return
		end
		Combat.Down(best, chaser)
		return
	end

	if Hazards.HitDoor(root, reach) then
		return
	end

	-- Missed. Did somebody juke this swing?
	Status.Slow(chaser, K.MissSlowMult, K.MissSlowTime)
	local juker, jukeDist = nil, math.huge
	for _, e in Roster.WithRole("Runner") do
		local r = Roster.Root(e)
		if r and now - e.LastJuke <= K.JukeWindow then
			local d = flat(r.Position - origin).Magnitude
			if d <= K.JukeRange and d < jukeDist then
				juker, jukeDist = e, d
			end
		end
	end
	if juker then
		ankleBreak(chaser, juker)
	end
end

function Combat.Swing(chaser: any)
	if chaser.Role ~= "Chaser" or not chaser.InMatch or not Phase.IsLive() then
		return
	end
	local now = os.clock()
	-- 10% slack so network jitter doesn't eat swings the client allowed.
	if now - chaser.LastSwing < K.Cooldown * 0.9 or now < chaser.GraceUntil then
		return
	end
	if Status.IsStunned(chaser) then
		return
	end
	chaser.LastSwing = now
	local big = now < chaser.BigDaggerUntil
	if big then
		chaser.BigDaggerUntil = 0
		task.delay(0.35, function()
			Roster.SetKnifeBig(chaser, false)
		end)
	end
	Effect:FireAllClients({ Kind = "Swing", Model = chaser.Model, Big = big })
	task.delay(K.Windup, resolve, chaser, big)
end

-- Runners report dashes and instant stops; a swing that misses right after
-- one breaks the chaser's ankles.
function Combat.Juke(runner: any)
	if runner.Role == "Runner" and runner.InMatch then
		local now = os.clock()
		if now - runner.LastJuke > 0.2 then
			runner.LastJuke = now
		end
	end
end

---------------------------------------------------------------------------
-- Ticking: bleed-outs
---------------------------------------------------------------------------
function Combat.Tick()
	local now = os.clock()
	for _, e in Roster.WithRole("Downed") do
		if now - e.DownedAt >= M.BleedOutTime then
			Combat.Convert(e)
		end
	end
	if #Roster.WithRole("Downed") == 0 then
		clearChanneling()
	end
end

function Combat.Start()
	Net.Event("Swing").OnServerEvent:Connect(function(player)
		local e = Roster.ForPlayer(player)
		if e then
			Combat.Swing(e)
		end
	end)
	Net.Event("Juke").OnServerEvent:Connect(function(player, kind)
		local e = Roster.ForPlayer(player)
		if e then
			Combat.Juke(e)
			if kind == "Dash" and e.Model then
				Effect:FireAllClients({ Kind = "Dash", Model = e.Model })
			end
		end
	end)
end

return Combat
