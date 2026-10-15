--!strict
-- Pays out gems, coins and XP the moment they're earned (so leaving early
-- keeps them) and keeps a per-match list for the results screen.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)
local DataService = require(script.Parent.DataService)

local Notify = Net.Event("Notify")

local Rewards = {}

function Rewards.Give(entry: any, gems: number, coins: number, xp: number, reason: string, quiet: boolean?)
	local player: Player? = entry.Player
	if not player then
		return
	end
	local g, c = DataService.Award(player, gems, coins, xp)
	entry.Earned.Gems += g
	entry.Earned.Coins += c
	entry.Earned.XP += xp
	table.insert(entry.Earned.Lines, { Reason = reason, Gems = g, Coins = c, XP = xp })
	if not quiet then
		local parts = {}
		if g > 0 then
			table.insert(parts, ("+%d Gems"):format(g))
		end
		if c > 0 then
			table.insert(parts, ("+%d Coins"):format(c))
		end
		if #parts > 0 then
			Notify:FireClient(player, { Kind = "Popup", Text = table.concat(parts, "  "), Sub = reason })
		end
	end
end

function Rewards.Stat(entry: any, field: string, amount: number)
	local player: Player? = entry.Player
	if not player then
		return
	end
	DataService.Mutate(player, function(p: any)
		p[field] = (p[field] or 0) + amount
		if field == "Catches" and p.Catches >= 25 then
			p.OwnedTitles.Menace = true
		elseif field == "Ankles" and p.Ankles >= 50 then
			p.OwnedTitles.Untouchable = true
		elseif field == "Heroes" then
			p.OwnedTitles.Hero = true
		end
	end)
end

function Rewards.GrantTitle(entry: any, titleId: string)
	local player: Player? = entry.Player
	if not player then
		return
	end
	DataService.Mutate(player, function(p: any)
		p.OwnedTitles[titleId] = true
	end)
end

return Rewards
