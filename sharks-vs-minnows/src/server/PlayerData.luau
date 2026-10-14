--!strict
-- Saves coins, gems, wins, unlocks and items. Values the client needs to show are mirrored
-- onto Player attributes and leaderstats, so the UI just listens for attribute changes.

local DataStoreService = game:GetService("DataStoreService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local Config = require(ReplicatedStorage.Shared.Config)

export type Data = {
	Coins: number,
	Gems: number,
	Wins: number,
	Tags: number,
	Crossings: number,
	OwnedAbilities: { [string]: boolean },
	Equipped: { Minnow: string, Shark: string },
	Items: { [string]: number },
	OwnedTrails: { [string]: boolean },
	Trail: string,
	Codes: { [string]: boolean },
}

local PlayerData = {}

local store: DataStore? = nil
do
	local ok, result = pcall(function()
		return DataStoreService:GetDataStore(Config.DataStoreName)
	end)
	if ok then
		store = result
	else
		warn("[SvM] DataStores unavailable, progress won't save this session:", result)
	end
end

local cache: { [Player]: Data } = {}
local loaded: { [Player]: boolean } = {}

local function defaultData(): Data
	local owned = {}
	for id, def in Config.Abilities do
		if def.Price == 0 then
			owned[id] = true
		end
	end
	return {
		Coins = 100,
		Gems = 0,
		Wins = 0,
		Tags = 0,
		Crossings = 0,
		OwnedAbilities = owned,
		Equipped = { Minnow = Config.DefaultAbility.Minnow, Shark = Config.DefaultAbility.Shark },
		Items = table.clone(Config.StarterItems),
		OwnedTrails = {},
		Trail = "",
		Codes = {},
	}
end

-- Fill in any fields added since the player last saved.
local function reconcile(saved: any): Data
	local data = defaultData()
	if typeof(saved) ~= "table" then
		return data
	end
	for key, value in saved do
		local current = (data :: any)[key]
		if current ~= nil and typeof(value) == typeof(current) then
			if typeof(value) == "table" then
				for k, v in value do
					current[k] = v
				end
			else
				(data :: any)[key] = value
			end
		end
	end
	return data
end

local function mirror(player: Player, data: Data)
	player:SetAttribute("Coins", data.Coins)
	player:SetAttribute("Gems", data.Gems)
	player:SetAttribute("EquippedMinnow", data.Equipped.Minnow)
	player:SetAttribute("EquippedShark", data.Equipped.Shark)
	player:SetAttribute("Trail", data.Trail)
	for id in Config.Abilities do
		player:SetAttribute("Owns_" .. id, data.OwnedAbilities[id] == true)
	end
	for id in Config.Items do
		player:SetAttribute("Item_" .. id, data.Items[id] or 0)
	end
	for id in Config.Trails do
		player:SetAttribute("OwnsTrail_" .. id, data.OwnedTrails[id] == true)
	end

	local stats = player:FindFirstChild("leaderstats")
	if stats then
		(stats:FindFirstChild("Wins") :: IntValue).Value = data.Wins;
		(stats:FindFirstChild("Coins") :: IntValue).Value = data.Coins
	end
end

function PlayerData.Load(player: Player)
	local stats = Instance.new("Folder")
	stats.Name = "leaderstats"
	local wins = Instance.new("IntValue")
	wins.Name = "Wins"
	wins.Parent = stats
	local coins = Instance.new("IntValue")
	coins.Name = "Coins"
	coins.Parent = stats
	stats.Parent = player

	local saved = nil
	local readOk = false
	if store then
		for attempt = 1, 3 do
			local ok, result = pcall(function()
				return store:GetAsync("p_" .. player.UserId)
			end)
			if ok then
				saved = result
				readOk = true
				break
			end
			warn(`[SvM] Load attempt {attempt} failed for {player.Name}: {result}`)
			if RunService:IsStudio() then
				break -- usually "API access disabled"; don't stall Studio tests
			end
			task.wait(attempt)
		end
	end
	if not player.Parent then
		return
	end

	local data = reconcile(saved)
	cache[player] = data
	-- Only save back what we successfully read, so a failed load never wipes real progress.
	loaded[player] = readOk
	mirror(player, data)
end

function PlayerData.Save(player: Player)
	local data = cache[player]
	if not (store and data and loaded[player]) then
		return
	end
	local ok, err = pcall(function()
		store:SetAsync("p_" .. player.UserId, data)
	end)
	if not ok then
		warn(`[SvM] Save failed for {player.Name}: {err}`)
	end
end

function PlayerData.Get(player: Player): Data?
	return cache[player]
end

function PlayerData.Release(player: Player)
	PlayerData.Save(player)
	cache[player] = nil
	loaded[player] = nil
end

-- Apply a change and push the result to attributes/leaderstats.
function PlayerData.Update(player: Player, fn: (Data) -> ())
	local data = cache[player]
	if not data then
		return
	end
	fn(data)
	mirror(player, data)
end

function PlayerData.AddCoins(player: Player, amount: number)
	PlayerData.Update(player, function(d)
		d.Coins += amount
	end)
end

function PlayerData.AddGems(player: Player, amount: number)
	PlayerData.Update(player, function(d)
		d.Gems += amount
	end)
end

function PlayerData.Init()
	task.spawn(function()
		while true do
			task.wait(120)
			for _, player in Players:GetPlayers() do
				task.spawn(PlayerData.Save, player)
			end
		end
	end)
	game:BindToClose(function()
		local pending = 0
		for _, player in Players:GetPlayers() do
			pending += 1
			task.spawn(function()
				PlayerData.Save(player)
				pending -= 1
			end)
		end
		local start = os.clock()
		while pending > 0 and os.clock() - start < 20 do
			task.wait(0.1)
		end
	end)
end

return PlayerData
