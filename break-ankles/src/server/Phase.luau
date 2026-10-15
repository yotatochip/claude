--!strict
-- The match's current phase, shared by every server system. Match.luau is
-- the only writer; everything else reads. The same values are mirrored as
-- attributes on ReplicatedStorage.MatchState for clients.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local State = Net.State()

local Phase = {}

Phase.Name = "Waiting"
Phase.Crossing = 0
Phase.Direction = 1
Phase.Hero = nil :: any -- the Entry doing a Hero run, if any
Phase.Votes = {} :: { [Player]: string }

-- Phases where knives, abilities and pickups are active.
local LIVE = { Crossing = true, HeroRun = true }
-- Phases where players are in the arena (abilities usable but not knives).
local ACTIVE = { Intro = true, Countdown = true, Crossing = true, Between = true, HeroChoice = true, HeroCountdown = true, HeroRun = true }

function Phase.Set(name: string, duration: number?, status: string?)
	Phase.Name = name
	State:SetAttribute("Phase", name)
	State:SetAttribute("EndsAt", if duration then workspace:GetServerTimeNow() + duration else 0)
	if status then
		State:SetAttribute("Status", status)
	end
end

function Phase.SetStatus(status: string)
	State:SetAttribute("Status", status)
end

function Phase.IsLive(): boolean
	return LIVE[Phase.Name] == true
end

function Phase.InArena(): boolean
	return ACTIVE[Phase.Name] == true
end

function Phase.Attr(name: string, value: any)
	State:SetAttribute(name, value)
end

return Phase
