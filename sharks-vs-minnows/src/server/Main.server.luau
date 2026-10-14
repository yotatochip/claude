--!strict
-- Sharks Vs Minnows: the round loop.
--
--   Intermission -> pick sharks -> [Ready -> Crossing] x N -> Results -> back to the lobby
--
-- Minnows start on the west beach and must reach the opposite beach before the timer runs out.
-- A minnow who gets chomped, or who doesn't make it across in time, becomes a shark.
-- The round ends when every minnow is gone, when only one is left (the champion), or when
-- the survivors make it through every crossing.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local MapBuilder = require(script.Parent.MapBuilder)
local PlayerData = require(script.Parent.PlayerData)
local Entities = require(script.Parent.Entities)
local Abilities = require(script.Parent.Abilities)
local Bots = require(script.Parent.Bots)

type Entity = Entities.Entity

local now = Entities.Now
local SAFE = Config.SafeLine

Players.RespawnTime = 3
Players.CharacterAutoLoads = true

local map = MapBuilder.Build()
PlayerData.Init()

-- Shared state the client reads from ReplicatedStorage attributes ------------------------

local function setState(fields: { [string]: any })
	for k, v in fields do
		ReplicatedStorage:SetAttribute(k, v)
	end
end

setState({
	Phase = "Waiting", PhaseEndsAt = 0, Crossing = 0, MaxCrossings = Config.MaxCrossings,
	Direction = 1, MinnowsLeft = 0, SharksCount = 0, Status = "Waiting for players",
})

local function setGates(closed: boolean)
	for _, gate in map.Gates do
		gate.CanCollide = closed
		gate.Transparency = if closed then 0.2 else 1
	end
end
setGates(true)

local function banner(target: Player?, title: string, subtitle: string, color: Color3)
	if target then
		Remotes.Banner:FireClient(target, title, subtitle, color)
	else
		Remotes.Banner:FireAllClients(title, subtitle, color)
	end
end

local function notify(e: Entity, text: string, color: Color3?)
	if e.Player then
		Remotes.Notify:FireClient(e.Player, text, color)
	end
end

local function reward(e: Entity, coins: number, reason: string)
	if e.Player and coins > 0 then
		PlayerData.AddCoins(e.Player, coins)
		notify(e, `+{coins} 🪙  {reason}`, Config.Colors.Coins)
	end
end

-- Players -------------------------------------------------------------------------------------

local roundRunning = false
local startingMinnows = 0
local lastSharks: { [string]: boolean } = {}

local function onCharacter(player: Player, character: Model)
	local e = Entities.Get(player)
	if not e then
		return
	end
	-- A new body means any round in progress is over for this player.
	if e.InRound then
		e.InRound = false
	end
	if e.Role ~= "Lobby" then
		Entities.SetRole(e, "Lobby")
	end
	Entities.AttachModel(e, character)
	local data = PlayerData.Get(player)
	if data and data.Trail ~= "" then
		task.defer(Entities.ApplyTrail, e, data.Trail)
	end
	local humanoid = character:WaitForChild("Humanoid") :: Humanoid
	humanoid.Died:Connect(function()
		if e.InRound and e.Model == character then
			e.InRound = false
			Entities.SetRole(e, "Lobby")
			notify(e, "You're out of the round. Next round starts soon!", Color3.fromRGB(255, 150, 150))
		end
	end)
end

local function onPlayerAdded(player: Player)
	-- Shift lock is on Left Ctrl (handled by Movement.luau), like Huss Valley.
	player.DevEnableMouseLock = false
	Entities.AddPlayer(player)
	player.CharacterAdded:Connect(function(character)
		onCharacter(player, character)
	end)
	if player.Character then
		onCharacter(player, player.Character)
	end
	PlayerData.Load(player)
end

Players.PlayerAdded:Connect(onPlayerAdded)
for _, p in Players:GetPlayers() do
	task.spawn(onPlayerAdded, p)
end

Players.PlayerRemoving:Connect(function(player)
	local e = Entities.Get(player)
	if e then
		Entities.Remove(e)
	end
	PlayerData.Release(player)
end)

-- Remotes -----------------------------------------------------------------------------------

Remotes.UseAbility.OnServerEvent:Connect(function(player)
	local e = Entities.Get(player)
	if e then
		Abilities.UseAbility(e)
	end
end)

Remotes.UseItem.OnServerEvent:Connect(function(player, itemId)
	local e = Entities.Get(player)
	if e and typeof(itemId) == "string" then
		Abilities.UseItem(e, itemId)
	end
end)

Remotes.Shop.OnServerInvoke = function(player: Player, action: any, id: any): (boolean, string)
	if typeof(action) ~= "string" or typeof(id) ~= "string" then
		return false, "Bad request"
	end
	local data = PlayerData.Get(player)
	if not data then
		return false, "Your data is still loading"
	end

	if action == "BuyAbility" then
		local def = Config.Abilities[id]
		if not def then
			return false, "Unknown ability"
		end
		if data.OwnedAbilities[id] then
			return false, "Already owned"
		end
		if data.Coins < def.Price then
			return false, "Not enough coins"
		end
		PlayerData.Update(player, function(d)
			d.Coins -= def.Price
			d.OwnedAbilities[id] = true
			if def.Role == "Shark" then
				d.Equipped.Shark = id
			else
				d.Equipped.Minnow = id
			end
		end)
		return true, `Unlocked {def.Name}!`
	elseif action == "EquipAbility" then
		local def = Config.Abilities[id]
		if not def or not data.OwnedAbilities[id] then
			return false, "You don't own that"
		end
		PlayerData.Update(player, function(d)
			if def.Role == "Shark" then
				d.Equipped.Shark = id
			else
				d.Equipped.Minnow = id
			end
		end)
		return true, `Equipped {def.Name}`
	elseif action == "BuyItem" then
		local def = Config.Items[id]
		if not def then
			return false, "Unknown item"
		end
		if data.Coins < def.Price then
			return false, "Not enough coins"
		end
		PlayerData.Update(player, function(d)
			d.Coins -= def.Price
			d.Items[id] = (d.Items[id] or 0) + 1
		end)
		return true, `Bought {def.Name}`
	elseif action == "BuyTrail" then
		local def = Config.Trails[id]
		if not def then
			return false, "Unknown trail"
		end
		if data.OwnedTrails[id] then
			return false, "Already owned"
		end
		if data.Gems < def.Price then
			return false, "Not enough gems"
		end
		PlayerData.Update(player, function(d)
			d.Gems -= def.Price
			d.OwnedTrails[id] = true
			d.Trail = id
		end)
		local e = Entities.Get(player)
		if e then
			Entities.ApplyTrail(e, id)
		end
		return true, `Unlocked the {def.Name} trail!`
	elseif action == "EquipTrail" then
		if id ~= "" and not data.OwnedTrails[id] then
			return false, "You don't own that"
		end
		PlayerData.Update(player, function(d)
			d.Trail = id
		end)
		local e = Entities.Get(player)
		if e then
			Entities.ApplyTrail(e, id)
		end
		return true, if id == "" then "Trail removed" else "Trail equipped"
	end
	return false, "Unknown action"
end

Remotes.RedeemCode.OnServerInvoke = function(player: Player, code: any): (boolean, string)
	if typeof(code) ~= "string" or #code > 40 then
		return false, "Invalid code"
	end
	local key = string.upper((string.gsub(code, "%s", "")))
	local def = Config.Codes[key]
	local data = PlayerData.Get(player)
	if not def then
		return false, "That code doesn't exist"
	end
	if not data then
		return false, "Your data is still loading"
	end
	if data.Codes[key] then
		return false, "Already redeemed"
	end
	local parts = {}
	PlayerData.Update(player, function(d)
		d.Codes[key] = true
		if def.Coins then
			d.Coins += def.Coins
			table.insert(parts, `{def.Coins} coins`)
		end
		if def.Gems then
			d.Gems += def.Gems
			table.insert(parts, `{def.Gems} gems`)
		end
		if def.Items then
			for itemId, n in def.Items do
				d.Items[itemId] = (d.Items[itemId] or 0) + n
				local item = Config.Items[itemId]
				table.insert(parts, `{n}x {if item then item.Name else itemId}`)
			end
		end
	end)
	return true, "Redeemed: " .. table.concat(parts, ", ")
end

-- Round helpers -----------------------------------------------------------------------------

local direction = 1 -- which way the minnows are heading this crossing
local phase = "Waiting"

local function participants(): { Entity }
	local out = {}
	for _, e in Entities.All() do
		if e.InRound then
			table.insert(out, e)
		end
	end
	return out
end

local function countRole(role: Entities.Role): number
	local n = 0
	for _, e in Entities.All() do
		if e.InRound and e.Role == role then
			n += 1
		end
	end
	return n
end

local function refreshCounts()
	setState({ MinnowsLeft = countRole("Minnow"), SharksCount = countRole("Shark") })
end

local function realPlayersInRound(): number
	local n = 0
	for _, e in Entities.All() do
		if e.InRound and not e.IsBot then
			n += 1
		end
	end
	return n
end

local function becomeShark(e: Entity, how: string, by: Entity?)
	Entities.SetRole(e, "Shark")
	Bots.Configure(e)
	e.SafeThisCrossing = false
	if by then
		banner(e.Player, "CHOMPED!", `{by.Name} got you. You're a shark now — get them back!`, Config.Colors.SharkOutline)
	else
		banner(e.Player, "TOO SLOW!", "You didn't make it across. You're a shark now!", Config.Colors.SharkOutline)
	end
	Remotes.Feed:FireAllClients(if by then by.Name else "🌊", e.Name, how)
	refreshCounts()
end

local blockedAt: { [Entity]: number } = {}

local function tryTags()
	local t = now()
	local sharks = Entities.WithRole("Shark")
	for _, m in Entities.WithRole("Minnow") do
		if not m.InRound then
			continue
		end
		-- the beach is the only safe place, even for minnows who already crossed
		local mr = Entities.Root(m)
		if not mr or not Abilities.InWater(mr.Position) then
			continue
		end
		for _, s in sharks do
			if not s.InRound or t - s.SharkSince < Config.TagGrace then
				continue
			end
			local sr = Entities.Root(s)
			if not sr then
				continue
			end
			local reach = Config.TagRange + (if s.BiteBonusUntil > t then s.BiteBonus else 0)
			if (sr.Position - mr.Position).Magnitude > reach then
				continue
			end
			if Abilities.TryBlock(m) then
				if t - (blockedAt[m] or 0) > 0.6 then
					blockedAt[m] = t
					notify(m, "🛡️ Blocked a chomp!", Config.Abilities.Bubble.Color)
					notify(s, "Your bite bounced off a shield!", Color3.fromRGB(255, 200, 120))
				end
				continue
			end
			-- Chomp!
			s.RoundTags += 1
			Remotes.Effect:FireAllClients("Chomp", { Position = mr.Position })
			if s.Player then
				PlayerData.Update(s.Player, function(d)
					d.Tags += 1
				end)
				reward(s, Config.Rewards.Tag, `Chomped {m.Name}`)
			end
			becomeShark(m, "chomp", s)
			break
		end
	end
end

local function checkArrivals()
	for _, m in Entities.WithRole("Minnow") do
		if m.InRound and not m.SafeThisCrossing then
			local p = Entities.Position(m)
			if p and p.X * direction > SAFE + 1 then
				m.SafeThisCrossing = true
				notify(m, "✅ Safe! Wait for the next crossing.", Color3.fromRGB(120, 255, 160))
			end
		end
	end
end

RunService.Heartbeat:Connect(function()
	Entities.UpdateMovement()
	if not roundRunning then
		return
	end
	Bots.Step(phase == "Crossing", direction)
	if phase == "Crossing" then
		Abilities.Step()
		tryTags()
		checkArrivals()
	end
end)

local function waitPhase(duration: number, stopEarly: (() -> boolean)?)
	local endsAt = now() + duration
	setState({ PhaseEndsAt = endsAt })
	while now() < endsAt do
		if stopEarly and stopEarly() then
			return
		end
		task.wait(0.1)
	end
end

local function pickSharks(pool: { Entity }, count: number): { [Entity]: boolean }
	-- Real players who were shark last round get a lower chance, so the role moves around.
	local weighted = {}
	for _, e in pool do
		local w = if lastSharks[e.Id] then 1 else 4
		for _ = 1, w do
			table.insert(weighted, e)
		end
	end
	local chosen: { [Entity]: boolean } = {}
	local picked = 0
	while picked < count and #weighted > 0 do
		local e = weighted[math.random(1, #weighted)]
		chosen[e] = true
		picked += 1
		for i = #weighted, 1, -1 do
			if weighted[i] == e then
				table.remove(weighted, i)
			end
		end
	end
	table.clear(lastSharks)
	for e in chosen do
		lastSharks[e.Id] = true
	end
	return chosen
end

local function placeSharksAtCenter()
	local sharks = Entities.WithRole("Shark")
	for i, s in sharks do
		if s.InRound then
			local cf = MapBuilder.SharkSpawn(i, #sharks)
			Entities.Teleport(s, CFrame.lookAt(cf.Position, cf.Position - Vector3.new(direction, 0, 0)))
		end
	end
end

-- The loop -------------------------------------------------------------------------------------

local function readyPlayers(): { Entity }
	local out = {}
	for _, p in Players:GetPlayers() do
		local e = Entities.Get(p)
		if e and PlayerData.Get(p) and Entities.Root(e) then
			table.insert(out, e)
		end
	end
	return out
end

local function intermission()
	while true do
		local ready = readyPlayers()
		local needed = if Config.BotsEnabled then Config.MinPlayersToStart else math.max(2, Config.MinPlayersToStart)
		if #ready >= needed then
			break
		end
		phase = "Waiting"
		setState({ Phase = "Waiting", Status = `Waiting for players ({#ready}/{needed})`, PhaseEndsAt = 0 })
		task.wait(1)
	end
	phase = "Intermission"
	setState({ Phase = "Intermission", Status = "Next round starting", Crossing = 0 })
	waitPhase(Config.IntermissionTime, function()
		return #readyPlayers() == 0
	end)
end

local function endRound(title: string, subtitle: string, color: Color3)
	phase = "Ended"
	Abilities.Active = false
	setState({ Phase = "Ended", Status = title })
	banner(nil, title, subtitle, color)
	waitPhase(Config.EndScreenTime)

	for _, e in participants() do
		e.InRound = false
		Entities.ResetRoundState(e)
		Entities.SetRole(e, "Lobby")
		if not e.IsBot then
			Entities.Teleport(e, MapBuilder.LobbySpot())
		end
	end
	Bots.Clear()
	Abilities.Clear()
	table.clear(blockedAt)
	setGates(true)
	roundRunning = false
	refreshCounts()
end

local function runRound()
	local players = readyPlayers()
	if #players == 0 then
		return
	end
	local everyone = table.clone(players)
	if Config.BotsEnabled and #everyone < Config.BotFillTarget then
		for _, b in Bots.Spawn(Config.BotFillTarget - #everyone) do
			table.insert(everyone, b)
		end
	end

	local sharkCount = math.max(1, math.floor(#everyone / Config.SharksPerPlayers))
	local sharks = pickSharks(everyone, sharkCount)

	direction = 1
	roundRunning = true
	for _, e in everyone do
		Entities.ResetRoundState(e)
		e.InRound = true
		Entities.SetRole(e, if sharks[e] then "Shark" else "Minnow")
		Bots.Configure(e)
	end
	startingMinnows = countRole("Minnow")

	local minnowsList = Entities.WithRole("Minnow")
	for i, m in minnowsList do
		Entities.Teleport(m, MapBuilder.ShoreSpawn(-1, i, #minnowsList))
	end
	placeSharksAtCenter()
	refreshCounts()

	for e in sharks do
		banner(e.Player, "YOU ARE THE SHARK 🦈", "Chomp every minnow before they cross!", Config.Colors.SharkOutline)
	end
	for _, m in minnowsList do
		banner(m.Player, "YOU ARE A MINNOW 🐟", "Cross to the other beach without getting chomped!", Config.Colors.Minnow)
	end

	local function minnowsGone(): boolean
		return countRole("Minnow") == 0
	end
	local function hasChampion(): boolean
		return startingMinnows >= 3 and countRole("Minnow") == 1
	end
	local function abandoned(): boolean
		return realPlayersInRound() == 0
	end

	for crossing = 1, Config.MaxCrossings do
		-- Ready: gates shut, sharks reset to the middle and held still
		phase = "Ready"
		Abilities.Active = false
		setGates(true)
		setState({ Phase = "Ready", Crossing = crossing, Direction = direction, Status = `Crossing {crossing} of {Config.MaxCrossings}` })
		placeSharksAtCenter()
		for _, m in Entities.WithRole("Minnow") do
			local p = Entities.Position(m)
			if m.InRound and p and math.abs(p.X) < SAFE + 5 then
				local side = if math.abs(p.X) > SAFE - 0.5 then math.sign(p.X) else -direction
				Entities.Teleport(m, CFrame.lookAt(Vector3.new(side * (SAFE + 10), 4, p.Z), Vector3.new(0, 4, p.Z)))
			end
		end
		for _, e in participants() do
			e.SafeThisCrossing = false
			e.Frozen = e.Role == "Shark"
		end
		Bots.NewCrossing()
		waitPhase(Config.ReadyTime, abandoned)
		if abandoned() then
			break
		end

		-- Crossing: gates drop and it's a race to the far beach
		phase = "Crossing"
		Abilities.Active = true
		setGates(false)
		for _, e in participants() do
			e.Frozen = false
		end
		setState({ Phase = "Crossing", Status = "SWIM!" })
		Remotes.Effect:FireAllClients("Go", {})
		-- shorter timer later in the round keeps the pace up
		local crossTime = math.max(12, Config.CrossTime - (crossing - 1))
		waitPhase(crossTime, function()
			if minnowsGone() or hasChampion() or abandoned() then
				return true
			end
			for _, m in Entities.WithRole("Minnow") do
				if m.InRound and not m.SafeThisCrossing then
					return false
				end
			end
			return true -- everyone made it
		end)
		Abilities.Active = false

		-- Anyone still in the water (or who never left) becomes a shark, unless they're the
		-- last minnow standing — that's a win, not a timeout.
		if not hasChampion() then
			for _, m in Entities.WithRole("Minnow") do
				if m.InRound and not m.SafeThisCrossing then
					becomeShark(m, "timeout", nil)
				end
			end
		end
		for _, m in Entities.WithRole("Minnow") do
			if m.InRound and m.SafeThisCrossing then
				m.RoundCrossings += 1
				reward(m, Config.Rewards.Crossing, `Crossing {crossing} survived`)
				if m.Player then
					PlayerData.Update(m.Player, function(d)
						d.Crossings += 1
					end)
				end
			end
		end

		if minnowsGone() or hasChampion() or abandoned() then
			break
		end
		direction = -direction
	end

	-- Results
	local survivors = {}
	for _, m in Entities.WithRole("Minnow") do
		if m.InRound then
			table.insert(survivors, m)
		end
	end

	for _, e in participants() do
		reward(e, Config.Rewards.Participation, "Thanks for playing")
	end

	if abandoned() then
		endRound("ROUND OVER", "Everyone left the ocean.", Color3.fromRGB(200, 200, 200))
		return
	end

	if #survivors == 0 then
		-- Sharks cleared the ocean. The starting sharks take the win.
		local names = {}
		for e in sharks do
			if e.InRound then
				table.insert(names, e.Name)
				if e.Player then
					PlayerData.Update(e.Player, function(d)
						d.Wins += 1
						d.Gems += Config.Rewards.WinGems
					end)
					notify(e, `+{Config.Rewards.WinGems} 💎  Shark victory`, Config.Colors.Gems)
				end
			end
		end
		for _, s in Entities.WithRole("Shark") do
			if s.InRound then
				reward(s, Config.Rewards.SharkWin, "The ocean is cleared")
			end
		end
		endRound("SHARKS WIN 🦈", `{table.concat(names, ", ")} cleared the ocean!`, Config.Colors.SharkOutline)
	else
		local names = {}
		for _, m in survivors do
			table.insert(names, m.Name)
			reward(m, Config.Rewards.MinnowWin, "Survived the round")
			if #survivors == 1 then
				reward(m, Config.Rewards.LastMinnowBonus, "Last minnow standing")
			end
			if m.Player then
				PlayerData.Update(m.Player, function(d)
					d.Wins += 1
					d.Gems += Config.Rewards.WinGems
				end)
				notify(m, `+{Config.Rewards.WinGems} 💎  Minnow victory`, Config.Colors.Gems)
			end
		end
		local title = if #survivors == 1 then "LAST MINNOW STANDING 🐟" else "MINNOWS WIN 🐟"
		endRound(title, `{table.concat(names, ", ")} survived the sharks!`, Config.Colors.Minnow)
	end
end

while true do
	intermission()
	local ok, err = pcall(function()
		runRound()
	end)
	if not ok then
		warn("[SvM] Round crashed:", err)
		if roundRunning then
			pcall(endRound, "ROUND OVER", "Something went wrong — starting a new round.", Color3.fromRGB(200, 200, 200))
		end
	end
end
