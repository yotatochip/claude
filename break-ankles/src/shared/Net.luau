--!strict
-- One place that names every remote. The server creates them, clients wait
-- for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = {
	"Swing", -- client -> server: chaser swings the knife
	"Juke", -- client -> server: runner dashed or stopped (for ankle breaks)
	"UseAbility", -- client -> server
	"UseItem", -- client -> server
	"HeroChoice", -- both ways: offer, then the runner's answer
	"Notify", -- server -> client: banners, feed lines, toasts, sounds
	"Effect", -- server -> all: visual effects other players should see
	"Knock", -- server -> client: impulses applied to your own character
	"ProfileChanged", -- server -> client: your saved data changed
	"Results", -- server -> client: end of match breakdown
}

local FUNCTIONS = {
	"GetProfile",
	"Shop", -- buy, equip, redeem, vote, AFK
}

local Net = {}

local folder: Folder
if RunService:IsServer() then
	local existing = ReplicatedStorage:FindFirstChild("Remotes")
	if existing then
		folder = existing :: Folder
	else
		folder = Instance.new("Folder")
		folder.Name = "Remotes"
		folder.Parent = ReplicatedStorage
	end
	for _, name in EVENTS do
		if not folder:FindFirstChild(name) then
			local e = Instance.new("RemoteEvent")
			e.Name = name
			e.Parent = folder
		end
	end
	for _, name in FUNCTIONS do
		if not folder:FindFirstChild(name) then
			local f = Instance.new("RemoteFunction")
			f.Name = name
			f.Parent = folder
		end
	end
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

function Net.Event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end

function Net.Function(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

-- Match state lives as attributes on this folder so every client sees it.
function Net.State(): Folder
	if RunService:IsServer() then
		local s = ReplicatedStorage:FindFirstChild("MatchState")
		if not s then
			s = Instance.new("Folder")
			s.Name = "MatchState"
			s.Parent = ReplicatedStorage
		end
		return s :: Folder
	end
	return ReplicatedStorage:WaitForChild("MatchState") :: Folder
end

return Net
