--!strict
-- Saves each player's gems, coins, unlocks and stats in a DataStore.
-- In Studio, turn on Game Settings > Security > "Enable Studio Access to API
-- Services" to save; otherwise the game runs with fresh data each session.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Catalog = require(Shared.Catalog)
local Net = require(Shared.Net)

export type Profile = {
	Gems: number,
	Coins: number,
	XP: number,
	Level: number,
	Wins: number,
	Ankles: number,
	Catches: number,
	Rescues: number,
	Heroes: number,
	Matches: number,
	OwnedAbilities: { [string]: boolean },
	OwnedKnives: { [string]: boolean },
	OwnedTitles: { [string]: boolean },
	Items: { [string]: number },
	Equipped: { Runner: string, Chaser: string, Item: string, Knife: string, Title: string },
	Redeemed: { [string]: boolean },
	Boosts: { Gems: number, Coins: number }, -- unix expiry times
	Receipts: { string },
}

local function defaultProfile(): Profile
	return {
		Gems = 0,
		Coins = 0,
		XP = 0,
		Level = 1,
		Wins = 0,
		Ankles = 0,
		Catches = 0,
		Rescues = 0,
		Heroes = 0,
		Matches = 0,
		OwnedAbilities = { [Catalog.StarterRunnerAbility] = true, [Catalog.StarterChaserAbility] = true },
		OwnedKnives = { Classic = true },
		OwnedTitles = { Rookie = true },
		Items = {},
		Equipped = {
			Runner = Catalog.StarterRunnerAbility,
			Chaser = Catalog.StarterChaserAbility,
			Item = "",
			Knife = "Classic",
			Title = "Rookie",
		},
		Redeemed = {},
		Boosts = { Gems = 0, Coins = 0 },
		Receipts = {},
	}
end

-- Fill in any fields added since the profile was first saved.
local function reconcile(target: any, template: any)
	for k, v in template do
		if target[k] == nil then
			target[k] = if type(v) == "table" then table.clone(v) else v
		elseif type(v) == "table" and type(target[k]) == "table" and next(v) ~= nil and #v == 0 then
			reconcile(target[k], v)
		end
	end
end

local DataService = {}

local store: DataStore? = nil
local storeOk = pcall(function()
	store = DataStoreService:GetDataStore(Config.DataStoreName)
end)

local profiles: { [Player]: Profile } = {}
local loaded: { [Player]: boolean } = {}
local dirty: { [Player]: boolean } = {}
local listeners: { (Player, Profile) -> () } = {}

local ProfileChanged = Net.Event("ProfileChanged")

local function key(player: Player): string
	return "u_" .. player.UserId
end

-- Studio without "Enable Studio Access to API Services" fails every call;
-- stop asking instead of retrying for each player.
local function isAccessError(err: string): boolean
	return string.find(err, "403") ~= nil
		or string.find(err, "StudioAccess") ~= nil
		or string.find(string.lower(err), "api access") ~= nil
		or string.find(string.lower(err), "api services") ~= nil
end

local function withRetries<T>(fn: () -> T): (boolean, T?)
	for attempt = 1, 4 do
		local ok, result = pcall(fn)
		if ok then
			return true, result
		end
		local err = tostring(result)
		if isAccessError(err) then
			warn("[BreakAnkles] DataStores are off in this session (" .. err .. "). Progress won't save.")
			store = nil
			return false, nil
		end
		warn(("[BreakAnkles] DataStore attempt %d failed: %s"):format(attempt, err))
		task.wait(attempt)
	end
	return false, nil
end

local function snapshot(p: Profile): any
	return {
		Gems = p.Gems,
		Coins = p.Coins,
		XP = p.XP,
		Level = p.Level,
		Wins = p.Wins,
		Ankles = p.Ankles,
		Catches = p.Catches,
		Rescues = p.Rescues,
		Heroes = p.Heroes,
		OwnedAbilities = table.clone(p.OwnedAbilities),
		OwnedKnives = table.clone(p.OwnedKnives),
		OwnedTitles = table.clone(p.OwnedTitles),
		Items = table.clone(p.Items),
		Equipped = table.clone(p.Equipped),
		Boosts = table.clone(p.Boosts),
		XPNeeded = Config.XPForLevel(p.Level),
	}
end

local function applyStats(player: Player, p: Profile)
	player:SetAttribute("Gems", p.Gems)
	player:SetAttribute("Coins", p.Coins)
	player:SetAttribute("Level", p.Level)
	player:SetAttribute("Title", p.Equipped.Title)
	local ls = player:FindFirstChild("leaderstats")
	if ls then
		(ls:FindFirstChild("Gems") :: IntValue).Value = p.Gems;
		(ls:FindFirstChild("Wins") :: IntValue).Value = p.Wins;
		(ls:FindFirstChild("Ankles") :: IntValue).Value = p.Ankles
	end
end

function DataService.Get(player: Player): Profile?
	return profiles[player]
end

function DataService.IsLoaded(player: Player): boolean
	return loaded[player] == true
end

function DataService.Snapshot(player: Player): any
	local p = profiles[player]
	return if p then snapshot(p) else nil
end

function DataService.OnChanged(fn: (Player, Profile) -> ())
	table.insert(listeners, fn)
end

-- Call after changing a profile: updates leaderstats and the client's copy.
function DataService.Changed(player: Player)
	local p = profiles[player]
	if not p then
		return
	end
	dirty[player] = true
	applyStats(player, p)
	ProfileChanged:FireClient(player, snapshot(p))
	for _, fn in listeners do
		task.spawn(fn, player, p)
	end
end

function DataService.Mutate(player: Player, fn: (Profile) -> ()): boolean
	local p = profiles[player]
	if not p then
		return false
	end
	fn(p)
	DataService.Changed(player)
	return true
end

local function boostActive(p: Profile, kind: "Gems" | "Coins"): boolean
	return (p.Boosts[kind] or 0) > os.time()
end

function DataService.BoostActive(player: Player, kind: "Gems" | "Coins"): boolean
	local p = profiles[player]
	return p ~= nil and boostActive(p, kind)
end

-- Adds currency and XP with any active 2x boosts applied. Returns what was given.
function DataService.Award(player: Player, gems: number, coins: number, xp: number): (number, number)
	local p = profiles[player]
	if not p then
		return 0, 0
	end
	if boostActive(p, "Gems") then
		gems *= 2
	end
	if boostActive(p, "Coins") then
		coins *= 2
	end
	p.Gems += gems
	p.Coins += coins
	p.XP += xp
	local leveled = false
	while p.XP >= Config.XPForLevel(p.Level) do
		p.XP -= Config.XPForLevel(p.Level)
		p.Level += 1
		leveled = true
	end
	if p.Level >= 15 then
		p.OwnedTitles.Veteran = true
	end
	if leveled then
		Net.Event("Notify"):FireClient(player, { Kind = "Toast", Text = ("LEVEL UP! You're level %d"):format(p.Level), Color = Color3.fromRGB(150, 255, 150), Sound = "Win" })
	end
	DataService.Changed(player)
	return gems, coins
end

local function save(player: Player): boolean
	local p = profiles[player]
	if not p or not loaded[player] or not store then
		return false
	end
	local data = table.clone(p)
	local ok = withRetries(function()
		(store :: DataStore):UpdateAsync(key(player), function()
			return data
		end)
		return true
	end)
	if ok then
		dirty[player] = false
	end
	return ok
end

local function load(player: Player)
	local data: any = nil
	local fetched = false
	if store then
		local ok, result = withRetries(function()
			return (store :: DataStore):GetAsync(key(player))
		end)
		if ok then
			data = result
			fetched = true
		else
			warn("[BreakAnkles] Could not load data for " .. player.Name .. "; progress won't save this session.")
		end
	end
	local profile: Profile = if type(data) == "table" then data else defaultProfile()
	reconcile(profile, defaultProfile())
	-- Drop anything the catalog no longer has.
	for id in profile.OwnedAbilities do
		if not Catalog.Abilities[id] then
			profile.OwnedAbilities[id] = nil
		end
	end
	if not Catalog.Abilities[profile.Equipped.Runner] then
		profile.Equipped.Runner = Catalog.StarterRunnerAbility
	end
	if not Catalog.Abilities[profile.Equipped.Chaser] then
		profile.Equipped.Chaser = Catalog.StarterChaserAbility
	end
	if not Catalog.Knives[profile.Equipped.Knife] then
		profile.Equipped.Knife = "Classic"
	end
	if not Catalog.Titles[profile.Equipped.Title] then
		profile.Equipped.Title = "Rookie"
	end
	if player.Parent ~= Players then
		return
	end
	profiles[player] = profile
	-- Only save profiles the store actually answered for, so a failed load
	-- never overwrites real progress with a blank profile.
	loaded[player] = fetched
	DataService.Changed(player)
end

local function onPlayerAdded(player: Player)
	local ls = Instance.new("Folder")
	ls.Name = "leaderstats"
	for _, name in { "Gems", "Wins", "Ankles" } do
		local v = Instance.new("IntValue")
		v.Name = name
		v.Parent = ls
	end
	ls.Parent = player
	load(player)
end

function DataService.Start()
	if not storeOk then
		warn("[BreakAnkles] DataStores unavailable; progress won't save.")
	end
	Players.PlayerAdded:Connect(onPlayerAdded)
	for _, player in Players:GetPlayers() do
		task.spawn(onPlayerAdded, player)
	end
	Players.PlayerRemoving:Connect(function(player)
		save(player)
		profiles[player] = nil
		loaded[player] = nil
		dirty[player] = nil
	end)
	Net.Function("GetProfile").OnServerInvoke = function(player)
		local deadline = os.clock() + 15
		while not profiles[player] and os.clock() < deadline do
			task.wait(0.2)
		end
		return DataService.Snapshot(player)
	end
	task.spawn(function()
		while true do
			task.wait(120)
			for player, isDirty in dirty do
				if isDirty then
					task.spawn(save, player)
				end
			end
		end
	end)
	game:BindToClose(function()
		if RunService:IsStudio() and not store then
			return
		end
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				save(player)
				pending -= 1
			end)
		end
		local deadline = os.clock() + 25
		while pending > 0 and os.clock() < deadline do
			task.wait(0.1)
		end
	end)
end

return DataService
