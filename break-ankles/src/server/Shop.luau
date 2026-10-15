--!strict
-- The shop remote: buying and equipping, codes, map votes and AFK. Also
-- grants Robux gem packs configured in Config.Products.

local MarketplaceService = game:GetService("MarketplaceService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)
local Match = require(script.Parent.Match)
local Phase = require(script.Parent.Phase)
local Roster = require(script.Parent.Roster)

local Shop = {}

type Result = { Ok: boolean, Message: string }

local function ok(message: string): Result
	return { Ok = true, Message = message }
end

local function fail(message: string): Result
	return { Ok = false, Message = message }
end

local actions: { [string]: (Player, any, any) -> Result } = {}

actions.BuyAbility = function(player, id)
	local def = Catalog.Abilities[id]
	if not def then
		return fail("Unknown ability")
	end
	local p = DataService.Get(player)
	if not p then
		return fail("Still loading your data")
	end
	if p.OwnedAbilities[id] then
		return fail("You already own " .. def.Name)
	end
	if p.Gems < def.Price then
		return fail(("You need %d more gems"):format(def.Price - p.Gems))
	end
	DataService.Mutate(player, function(prof)
		prof.Gems -= def.Price
		prof.OwnedAbilities[id] = true
		prof.Equipped[def.Role] = id
	end)
	return ok("Unlocked " .. def.Name .. "!")
end

actions.EquipAbility = function(player, id)
	local def = Catalog.Abilities[id]
	local p = DataService.Get(player)
	if not def or not p or not p.OwnedAbilities[id] then
		return fail("You don't own that")
	end
	DataService.Mutate(player, function(prof)
		prof.Equipped[def.Role] = id
	end)
	return ok(def.Name .. " equipped")
end

actions.BuyItem = function(player, id)
	local def = Catalog.Items[id]
	local p = DataService.Get(player)
	if not def or not p then
		return fail("Unknown item")
	end
	if p.Coins < def.Price then
		return fail(("You need %d more coins"):format(def.Price - p.Coins))
	end
	DataService.Mutate(player, function(prof)
		prof.Coins -= def.Price
		prof.Items[id] = (prof.Items[id] or 0) + def.Charges
		if prof.Equipped.Item == "" then
			prof.Equipped.Item = id
		end
	end)
	return ok(("+%d %s"):format(def.Charges, def.Name))
end

actions.EquipItem = function(player, id)
	local p = DataService.Get(player)
	if not p then
		return fail("Still loading")
	end
	if id ~= "" and (not Catalog.Items[id] or (p.Items[id] or 0) <= 0) then
		return fail("You don't have any of those")
	end
	DataService.Mutate(player, function(prof)
		prof.Equipped.Item = id
	end)
	return ok(if id == "" then "Item unequipped" else Catalog.Items[id].Name .. " equipped")
end

actions.BuyKnife = function(player, id)
	local def = Catalog.Knives[id]
	local p = DataService.Get(player)
	if not def or not p then
		return fail("Unknown knife")
	end
	if p.OwnedKnives[id] then
		return fail("Already owned")
	end
	if p.Gems < def.Price then
		return fail(("You need %d more gems"):format(def.Price - p.Gems))
	end
	DataService.Mutate(player, function(prof)
		prof.Gems -= def.Price
		prof.OwnedKnives[id] = true
		prof.Equipped.Knife = id
	end)
	local e = Roster.ForPlayer(player)
	if e then
		Roster.RefreshKnife(e)
	end
	return ok(def.Name .. " knife unlocked!")
end

actions.EquipKnife = function(player, id)
	local p = DataService.Get(player)
	if not p or not p.OwnedKnives[id] then
		return fail("You don't own that")
	end
	DataService.Mutate(player, function(prof)
		prof.Equipped.Knife = id
	end)
	local e = Roster.ForPlayer(player)
	if e then
		Roster.RefreshKnife(e)
	end
	return ok(Catalog.Knives[id].Name .. " equipped")
end

actions.EquipTitle = function(player, id)
	local p = DataService.Get(player)
	if not p or not p.OwnedTitles[id] or not Catalog.Titles[id] then
		return fail("You haven't earned that title yet")
	end
	DataService.Mutate(player, function(prof)
		prof.Equipped.Title = id
	end)
	return ok("Title set to " .. Catalog.Titles[id].Name)
end

actions.Redeem = function(player, code)
	if type(code) ~= "string" then
		return fail("Enter a code")
	end
	local key = string.upper((string.gsub(code, "%s+", "")))
	local reward = (Config.Codes :: any)[key]
	if not reward then
		return fail("That code doesn't exist")
	end
	local p = DataService.Get(player)
	if not p then
		return fail("Still loading")
	end
	if p.Redeemed[key] then
		return fail("You already used that code")
	end
	local parts = {}
	DataService.Mutate(player, function(prof)
		prof.Redeemed[key] = true
		if reward.Gems then
			prof.Gems += reward.Gems
			table.insert(parts, reward.Gems .. " gems")
		end
		if reward.Coins then
			prof.Coins += reward.Coins
			table.insert(parts, reward.Coins .. " coins")
		end
		if reward.Boosts then
			local now = os.time()
			for kind, seconds in reward.Boosts do
				prof.Boosts[kind] = math.max(prof.Boosts[kind] or 0, now) + seconds
				table.insert(parts, ("2x %s (%d min)"):format(string.lower(kind), seconds // 60))
			end
		end
		if reward.Title and Catalog.Titles[reward.Title] then
			prof.OwnedTitles[reward.Title] = true
			table.insert(parts, "the " .. Catalog.Titles[reward.Title].Name .. " title")
		end
	end)
	return ok("Redeemed: " .. table.concat(parts, ", "))
end

actions.Vote = function(player, mapId)
	if Phase.Name ~= "Intermission" and Phase.Name ~= "Waiting" then
		return fail("Voting is closed")
	end
	for _, m in Config.Maps do
		if m.Id == mapId then
			Phase.Votes[player] = mapId
			Match.UpdateVotes()
			return ok("Voted for " .. m.Name)
		end
	end
	return fail("Unknown map")
end

actions.SetAFK = function(player, value)
	local afk = value == true
	player:SetAttribute("AFK", afk)
	return ok(if afk then "You'll sit out the next match" else "You're back in")
end

---------------------------------------------------------------------------
-- Robux gem packs
---------------------------------------------------------------------------
local function processReceipt(info: any): Enum.ProductPurchaseDecision
	local product = (Config.Products :: any)[info.ProductId]
	local player = Players:GetPlayerByUserId(info.PlayerId)
	if not product or not player then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	local p = DataService.Get(player)
	if not p then
		return Enum.ProductPurchaseDecision.NotProcessedYet
	end
	if table.find(p.Receipts, info.PurchaseId) then
		return Enum.ProductPurchaseDecision.PurchaseGranted
	end
	DataService.Mutate(player, function(prof)
		prof.Gems += product.Gems or 0
		prof.Coins += product.Coins or 0
		table.insert(prof.Receipts, info.PurchaseId)
		while #prof.Receipts > 50 do
			table.remove(prof.Receipts, 1)
		end
	end)
	return Enum.ProductPurchaseDecision.PurchaseGranted
end

function Shop.Start()
	Net.Function("Shop").OnServerInvoke = function(player, action, a, b)
		local fn = actions[action]
		if type(action) ~= "string" or not fn then
			return fail("Unknown action")
		end
		local success, result = pcall(fn, player, a, b)
		if not success then
			warn("[BreakAnkles] Shop error: " .. tostring(result))
			return fail("Something went wrong")
		end
		return result
	end
	if next(Config.Products) ~= nil then
		MarketplaceService.ProcessReceipt = processReceipt
	end
end

return Shop
