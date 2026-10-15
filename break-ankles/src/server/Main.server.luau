--!strict
-- Break Ankles server entry point.

local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
require(Shared.Net) -- creates the remotes before anything else runs

local Groups = require(script.Parent.Groups)
local MapBuilder = require(script.Parent.MapBuilder)
local DataService = require(script.Parent.DataService)
local Roster = require(script.Parent.Roster)
local Hazards = require(script.Parent.Hazards)
local Combat = require(script.Parent.Combat)
local Abilities = require(script.Parent.Abilities)
local Gems = require(script.Parent.Gems)
local Bots = require(script.Parent.Bots)
local Match = require(script.Parent.Match)
local Shop = require(script.Parent.Shop)
local Phase = require(script.Parent.Phase)

Players.RespawnTime = 1.5
Players.CharacterAutoLoads = true

-- Remove the template baseplate if this place still has one.
local baseplate = workspace:FindFirstChild("Baseplate")
if baseplate then
	baseplate:Destroy()
end

Groups.Setup()
MapBuilder.BuildLobby()
MapBuilder.BuildArena("Valley")
Phase.Set("Waiting", nil, "Starting up")

DataService.Start()
Roster.Start()
Hazards.Start()
Combat.Start()
Abilities.Start()
Gems.Start()
Bots.Start()
Shop.Start()
Match.Start()

print("[BreakAnkles] Server ready")
