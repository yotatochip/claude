--!strict
-- The match loop: intermission and map vote -> pick the chaser -> three
-- crossings (with the odd Hero or Chicken offer) -> results -> lobby.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Bots = require(script.Parent.Bots)
local Combat = require(script.Parent.Combat)
local DataService = require(script.Parent.DataService)
local Gems = require(script.Parent.Gems)
local Hazards = require(script.Parent.Hazards)
local MapBuilder = require(script.Parent.MapBuilder)
local Phase = require(script.Parent.Phase)
local Rewards = require(script.Parent.Rewards)
local Roster = require(script.Parent.Roster)

local M = Config.Match
local R = Config.Rewards

local Notify = Net.Event("Notify")
local HeroChoice = Net.Event("HeroChoice")
local ResultsEvent = Net.Event("Results")

local Match = {}

local rng = Random.new()
local anyCaught = false
local heroAnswer: { [Player]: string } = {}

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function announce(text: string, sub: string?, color: Color3?, sound: string?)
	Notify:FireAllClients({ Kind = "Announce", Text = text, Sub = sub, Color = color, Sound = sound })
end

local function feed(text: string)
	Notify:FireAllClients({ Kind = "Feed", Text = text })
end

local function counts(): (number, number)
	local runners, chasers = 0, 0
	for _, e in Roster.InMatch() do
		if e.Role == "Runner" or e.Role == "Downed" then
			runners += 1
		elseif e.Role == "Chaser" then
			chasers += 1
		end
	end
	Phase.Attr("Runners", runners)
	Phase.Attr("Chasers", chasers)
	return runners, chasers
end

local function eligiblePlayers(): { Player }
	local list = {}
	for _, p in Players:GetPlayers() do
		local e = Roster.ForPlayer(p)
		local char = p.Character
		local hum = char and char:FindFirstChildOfClass("Humanoid")
		if e and hum and hum.Health > 0 and not p:GetAttribute("AFK") and DataService.Get(p) then
			table.insert(list, p)
		end
	end
	return list
end

local function shuffle<T>(list: { T }): { T }
	for i = #list, 2, -1 do
		local j = rng:NextInteger(1, i)
		list[i], list[j] = list[j], list[i]
	end
	return list
end

local function placeRunners(side: string)
	local runners = {}
	for _, e in Roster.InMatch() do
		if e.Role == "Runner" or e.Role == "Downed" then
			table.insert(runners, e)
		end
	end
	for i, e in runners do
		Roster.Place(e, Arena.SafeSpot(side, i, #runners))
	end
end

local function placeChasers()
	local chasers = Roster.WithRole("Chaser")
	for i, e in chasers do
		Roster.Place(e, Arena.ChaserSpot(i, #chasers, Phase.Direction))
	end
end

local function sendToLobby(e: any, i: number)
	Roster.Place(e, MapBuilder.LobbyCFrame(i))
end

-- If every chaser left, hand the knife to a random runner.
local function ensureChaser()
	local runners, chasers = counts()
	if chasers == 0 and runners >= 2 then
		local pool = Roster.WithRole("Runner")
		if #pool > 0 then
			local e = pool[rng:NextInteger(1, #pool)]
			Combat.Convert(e)
			feed(e.Name .. " picked up the knife")
		end
	end
end

local function cancelMatchIfEmpty(): boolean
	local runners, chasers = counts()
	if runners == 0 or (chasers == 0 and runners < 2) then
		return true
	end
	-- Don't keep a bots-only match running after the last player leaves.
	for _, e in Roster.InMatch() do
		if e.Player then
			return false
		end
	end
	return true
end

---------------------------------------------------------------------------
-- Intermission
---------------------------------------------------------------------------
local function tallyVotes(): string
	local tally: { [string]: number } = {}
	for _, m in Config.Maps do
		tally[m.Id] = 0
	end
	for player, id in Phase.Votes do
		if player.Parent == Players and tally[id] then
			tally[id] += 1
		end
	end
	local best, bestCount, ties = Config.Maps[1].Id, -1, {}
	for _, m in Config.Maps do
		local c = tally[m.Id]
		if c > bestCount then
			best, bestCount, ties = m.Id, c, { m.Id }
		elseif c == bestCount then
			table.insert(ties, m.Id)
		end
	end
	if #ties > 1 then
		best = ties[rng:NextInteger(1, #ties)]
	end
	return best
end

function Match.UpdateVotes()
	for _, m in Config.Maps do
		local c = 0
		for player, id in Phase.Votes do
			if id == m.Id and player.Parent == Players then
				c += 1
			end
		end
		Phase.Attr("Vote_" .. m.Id, c)
	end
end

local function needed(): number
	return if Config.Bots.Enabled then 1 else M.MinPlayers
end

local function intermission()
	table.clear(Phase.Votes)
	Match.UpdateVotes()
	while true do
		if #eligiblePlayers() < needed() then
			Phase.Set("Waiting", nil, if Config.Bots.Enabled then "Waiting for players" else ("Waiting for %d players"):format(M.MinPlayers))
			repeat
				task.wait(1)
			until #eligiblePlayers() >= needed()
		end
		Phase.Set("Intermission", M.Intermission, "Intermission")
		local ok = true
		for _ = 1, M.Intermission do
			task.wait(1)
			if #eligiblePlayers() < needed() then
				ok = false
				break
			end
		end
		if ok then
			return
		end
	end
end

---------------------------------------------------------------------------
-- Crossings
---------------------------------------------------------------------------
local function resolveCrossing(target: string)
	for _, e in Roster.WithRole("Downed") do
		Combat.Convert(e)
	end
	for _, e in Roster.WithRole("Runner") do
		local root = Roster.Root(e)
		if root and Arena.InSafeZone(root.Position, target) then
			e.Crossings += 1
			Rewards.Give(e, R.CrossingGems, R.CrossingCoins, R.CrossingXP, ("Crossing %d"):format(Phase.Crossing))
			if e.Player then
				Notify:FireClient(e.Player, { Kind = "Toast", Text = ("CROSSING %d COMPLETE"):format(Phase.Crossing), Color = Color3.fromRGB(140, 255, 160), Sound = "Safe" })
			end
		else
			Combat.Convert(e, "time")
		end
	end
	Gems.Clear()
	Hazards.Clear()
	counts()
end

local function allRunnersSafe(target: string): boolean
	if #Roster.WithRole("Downed") > 0 then
		return false
	end
	local any = false
	for _, e in Roster.WithRole("Runner") do
		local root = Roster.Root(e)
		if not root or not Arena.InSafeZone(root.Position, target) then
			return false
		end
		any = true
	end
	return any
end

local function runCrossing()
	local start = Arena.StartSide(Phase.Direction)
	local target = Arena.TargetSide(Phase.Direction)
	Phase.Attr("Crossing", Phase.Crossing)
	Phase.Attr("Direction", Phase.Direction)

	-- Anyone who isn't in the start zone (only possible after a respawn) goes there.
	for i, e in Roster.WithRole("Runner") do
		local root = Roster.Root(e)
		if root and not Arena.InSafeZone(root.Position, start) and not Arena.InSafeZone(root.Position, target) then
			Roster.Place(e, Arena.SafeSpot(start, i, 8))
		end
	end
	placeChasers()
	MapBuilder.SetGate(start, true)
	Phase.Set("Countdown", M.Countdown, ("Crossing %d of %d"):format(Phase.Crossing, M.CrossingsToWin))
	for i = M.Countdown, 1, -1 do
		Notify:FireAllClients({ Kind = "Count", Text = tostring(i) })
		task.wait(1)
	end
	MapBuilder.SetGate(start, false)
	Gems.Spawn(R.FieldGemsPerCrossing)
	Phase.Set("Crossing", M.CrossingTime, ("Crossing %d of %d"):format(Phase.Crossing, M.CrossingsToWin))
	announce("RUN!!", "Get to side " .. target, Color3.fromRGB(255, 255, 255), "Tick")

	local deadline = os.clock() + M.CrossingTime
	local safeSince: number? = nil
	while os.clock() < deadline do
		task.wait(0.1)
		Combat.Tick()
		ensureChaser()
		if cancelMatchIfEmpty() then
			break
		end
		if allRunnersSafe(target) then
			safeSince = safeSince or os.clock()
			if os.clock() - (safeSince :: number) > 0.6 then
				break
			end
		else
			safeSince = nil
		end
	end
	resolveCrossing(target)
end

local function heroPhase()
	local runners = Roster.WithRole("Runner")
	if #runners < 2 then
		return
	end
	local pick = runners[rng:NextInteger(1, #runners)]
	local start = Arena.StartSide(Phase.Direction)
	local target = Arena.TargetSide(Phase.Direction)
	Phase.Attr("Crossing", Phase.Crossing)
	Phase.Attr("Direction", Phase.Direction)
	Phase.Set("HeroChoice", M.HeroChoiceTime, pick.Name .. " is deciding: HERO or CHICKEN?")
	announce("HERO OR CHICKEN?", pick.Name .. " can cross alone for a bonus", Color3.fromRGB(255, 225, 90), "Tick")

	local choice = "Chicken"
	if pick.Player then
		heroAnswer[pick.Player] = nil
		HeroChoice:FireClient(pick.Player, { Time = M.HeroChoiceTime, Reward = R.HeroGems })
		local deadline = os.clock() + M.HeroChoiceTime
		while os.clock() < deadline and not heroAnswer[pick.Player] and pick.Player.Parent do
			task.wait(0.1)
		end
		choice = heroAnswer[pick.Player] or "Chicken"
		heroAnswer[pick.Player] = nil
	else
		task.wait(rng:NextNumber(1.5, 3))
		choice = if rng:NextNumber() < 0.5 then "Hero" else "Chicken"
	end
	if pick.Role ~= "Runner" then
		return
	end
	if choice ~= "Hero" then
		pick.Chicken = true
		announce("CHICKEN!", pick.Name .. " stays with the group", Color3.fromRGB(255, 255, 255))
		task.wait(1.5)
		return
	end

	Phase.Hero = pick
	placeChasers()
	MapBuilder.SetGate(start, true) -- stays shut for everyone except the hero
	Phase.Set("HeroCountdown", 3, pick.Name .. " is going solo!")
	announce("HERO RUN!", pick.Name .. " crosses alone", Color3.fromRGB(255, 225, 90), "Tick")
	for i = 3, 1, -1 do
		Notify:FireAllClients({ Kind = "Count", Text = tostring(i) })
		task.wait(1)
	end
	-- Only now does the hero's collision group let them through the gate.
	pick.IsHero = true
	Roster.RefreshGroup(pick)
	Phase.Set("HeroRun", M.HeroCrossingTime, pick.Name .. "'s Hero run")
	if pick.Player then
		Notify:FireClient(pick.Player, { Kind = "Announce", Text = "GO, HERO!", Sub = "Reach side " .. target .. " alone", Color = Color3.fromRGB(255, 225, 90) })
	end
	local deadline = os.clock() + M.HeroCrossingTime
	local made = false
	while os.clock() < deadline do
		task.wait(0.1)
		Combat.Tick()
		ensureChaser()
		if pick.Role ~= "Runner" or not pick.InMatch then
			break
		end
		local root = Roster.Root(pick)
		if root and Arena.InSafeZone(root.Position, target) then
			made = true
			break
		end
	end
	pick.IsHero = false
	Phase.Hero = nil
	if made then
		Rewards.Give(pick, R.HeroGems, 0, R.SurviveXP, "Hero run")
		Rewards.Stat(pick, "Heroes", 1)
		announce("HERO!", pick.Name .. " made it across alone", Color3.fromRGB(255, 225, 90), "Win")
	elseif pick.Role == "Runner" then
		Combat.Convert(pick, "time")
		announce("FALLEN HERO", pick.Name .. " ran out of time", Color3.fromRGB(255, 120, 120))
	elseif pick.Role == "Downed" then
		Combat.Convert(pick)
		announce("FALLEN HERO", pick.Name .. " got caught", Color3.fromRGB(255, 120, 120))
	else
		announce("FALLEN HERO", pick.Name .. " got caught", Color3.fromRGB(255, 120, 120))
	end
	Roster.RefreshGroup(pick)
	Hazards.Clear()
	task.wait(2)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local function finish(runnersWin: boolean, cancelled: boolean)
	local survivors = {}
	for _, e in Roster.WithRole("Runner") do
		table.insert(survivors, e.Name)
	end
	local flawless = runnersWin and not anyCaught
	local mvp, mvpScore = nil, 0
	for _, e in Roster.InMatch() do
		local score = e.Ankles * 2 + e.Catches * 2 + e.Rescues * 3 + e.Crossings
		if score > mvpScore then
			mvp, mvpScore = e, score
		end
		if not cancelled then
			if runnersWin and e.Role == "Runner" then
				Rewards.Give(e, R.SurviveGems, R.SurviveCoins, R.SurviveXP, "Survived")
				Rewards.Stat(e, "Wins", 1)
				if flawless then
					Rewards.Give(e, R.FlawlessGems, 0, 0, "Flawless")
					Rewards.GrantTitle(e, "Flawless")
				end
			elseif not runnersWin and e.Role == "Chaser" then
				Rewards.Give(e, R.ChaserWinGems, R.ChaserWinCoins, R.ChaserWinXP, "Chasers win")
				Rewards.Stat(e, "Wins", 1)
			end
			Rewards.Give(e, 0, R.ParticipationCoins, R.ParticipationXP, "Played a match", true)
			Rewards.Stat(e, "Matches", 1)
		end
	end
	local headline = if cancelled then "MATCH ENDED" elseif runnersWin then (if flawless then "FLAWLESS! RUNNERS WIN" else "RUNNERS WIN") else "CHASERS WIN"
	local color = if cancelled then Color3.fromRGB(220, 220, 220) elseif runnersWin then Color3.fromRGB(140, 255, 160) else Color3.fromRGB(255, 90, 90)
	Phase.Set("Results", M.ResultsTime, headline)
	announce(headline, if runnersWin then (#survivors .. " survived") else nil, color, if cancelled then nil else "Win")
	for _, e in Roster.InMatch() do
		if e.Player then
			ResultsEvent:FireClient(e.Player, {
				Headline = headline,
				Color = color,
				RunnersWin = runnersWin,
				YouWon = not cancelled and ((runnersWin and e.Role == "Runner") or (not runnersWin and e.Role == "Chaser")),
				Survivors = survivors,
				MVP = if mvp then mvp.Name else nil,
				Crossings = e.Crossings,
				Ankles = e.Ankles,
				Catches = e.Catches,
				Rescues = e.Rescues,
				Gems = e.Earned.Gems,
				Coins = e.Earned.Coins,
				XP = e.Earned.XP,
				Lines = e.Earned.Lines,
				Time = M.ResultsTime,
			})
		end
	end
	task.wait(M.ResultsTime)
end

local function cleanup()
	local i = 0
	for _, e in Roster.InMatch() do
		i += 1
		Roster.EndMatch(e)
		if not e.IsBot then
			sendToLobby(e, i)
		end
	end
	Bots.DespawnAll()
	Gems.Clear()
	Hazards.Clear()
	MapBuilder.SetGate("A", false)
	MapBuilder.SetGate("B", false)
	Phase.Hero = nil
	Phase.Crossing = 0
	Phase.Attr("Crossing", 0)
	counts()
end

---------------------------------------------------------------------------
-- A whole match
---------------------------------------------------------------------------
local function runMatch()
	local mapId = tallyVotes()
	Phase.Attr("Map", mapId)
	MapBuilder.BuildArena(mapId)

	local humans = eligiblePlayers()
	local participants = {}
	for _, p in humans do
		local e = Roster.ForPlayer(p)
		if e then
			Roster.BeginMatch(e)
			table.insert(participants, e)
		end
	end
	if Config.Bots.Enabled and #participants < Config.Bots.FillTo then
		for _, e in Bots.Spawn(Config.Bots.FillTo - #participants) do
			Roster.BeginMatch(e)
			table.insert(participants, e)
		end
	end
	if #participants < 2 then
		for _, e in participants do
			Roster.EndMatch(e)
		end
		Bots.DespawnAll()
		return
	end

	anyCaught = false
	Phase.Direction = 1
	Phase.Crossing = 1
	Phase.Attr("Direction", 1)
	Phase.Attr("Crossing", 1)

	-- Pick the chaser(s). Prefer real players for the knife only by chance.
	shuffle(participants)
	local chaserCount = math.max(1, math.floor(#participants / M.PlayersPerChaser))
	for i, e in participants do
		if i <= chaserCount then
			e.OriginalChaser = true
			Roster.SetRole(e, "Chaser")
		else
			Roster.SetRole(e, "Runner")
		end
	end
	placeRunners("A")
	placeChasers()
	MapBuilder.SetGate("A", true)
	counts()

	local mapName = mapId
	for _, m in Config.Maps do
		if m.Id == mapId then
			mapName = m.Name
		end
	end
	Phase.Set("Intro", 4, mapName)
	for _, e in participants do
		if e.Player then
			if e.Role == "Chaser" then
				Notify:FireClient(e.Player, { Kind = "Announce", Text = "YOU'RE THE CHASER", Sub = "One knife hit downs a runner. Click to swing.", Color = Color3.fromRGB(255, 90, 90), Sound = "Equip" })
			else
				Notify:FireClient(e.Player, { Kind = "Announce", Text = "YOU'RE A RUNNER", Sub = ("Cross the field %d times. Break some ankles."):format(M.CrossingsToWin), Color = Color3.fromRGB(140, 255, 160), Sound = "Tick" })
			end
		end
	end
	local chaserNames = {}
	for _, e in Roster.WithRole("Chaser") do
		table.insert(chaserNames, e.Name)
	end
	feed(table.concat(chaserNames, ", ") .. " has the knife")
	task.wait(4)

	local completed = false
	for c = 1, M.CrossingsToWin do
		Phase.Crossing = c
		if c >= 2 and rng:NextNumber() < M.HeroChance then
			heroPhase()
			if cancelMatchIfEmpty() then
				break
			end
		end
		runCrossing()
		if cancelMatchIfEmpty() then
			break
		end
		if c == M.CrossingsToWin then
			completed = true
		else
			Phase.Direction = -Phase.Direction
			Phase.Attr("Direction", Phase.Direction)
			Phase.Set("Between", M.BetweenCrossings, ("Crossing %d done - %d runners left"):format(c, (counts())))
			task.wait(M.BetweenCrossings)
		end
	end

	local runners, chasers = counts()
	local cancelled = runners > 0 and chasers == 0
	finish(completed and runners > 0, cancelled)
	cleanup()
end

---------------------------------------------------------------------------
-- Respawns and strays
---------------------------------------------------------------------------
local function onCharacter(e: any)
	if not e.InMatch or not Phase.InArena() then
		return
	end
	task.wait(0.2)
	if e.Role == "Chaser" then
		Roster.Place(e, Arena.ChaserSpot(1, 1, Phase.Direction))
	else
		-- A respawned runner goes back to the start zone of this crossing.
		Roster.Place(e, Arena.SafeSpot(Arena.StartSide(Phase.Direction), rng:NextInteger(1, 8), 8))
	end
end

local function watchdog()
	while true do
		task.wait(0.5)
		for i, e in Roster.All() do
			local root = Roster.Root(e)
			if root then
				local pos = root.Position
				if e.InMatch then
					if not Arena.InBounds(pos) then
						if e.Role == "Chaser" then
							Roster.Place(e, Arena.ChaserSpot(1, 1, Phase.Direction))
						else
							Roster.Place(e, Arena.SafeSpot(Arena.StartSide(Phase.Direction), 1, 8))
						end
					end
				elseif not e.IsBot and not MapBuilder.InLobby(pos) then
					sendToLobby(e, i)
				end
			end
		end
	end
end

function Match.Answer(player: Player, choice: string)
	if choice == "Hero" or choice == "Chicken" then
		heroAnswer[player] = choice
	end
end

function Match.Start()
	Combat.OnCaught = function(_runner)
		anyCaught = true
	end
	Roster.OnCharacter(onCharacter)
	HeroChoice.OnServerEvent:Connect(function(player, choice)
		if type(choice) == "string" then
			Match.Answer(player, choice)
		end
	end)
	Players.PlayerRemoving:Connect(function(player)
		Phase.Votes[player] = nil
		Match.UpdateVotes()
		task.defer(counts)
	end)
	task.spawn(watchdog)
	task.spawn(function()
		while true do
			intermission()
			local ok, err = pcall(function()
				runMatch()
			end)
			if not ok then
				warn("[BreakAnkles] Match error: " .. tostring(err))
				pcall(cleanup)
			end
			task.wait(1)
		end
	end)
end

return Match
