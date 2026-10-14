--!strict
-- One place that defines every remote. The server creates them; clients wait for them.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")

local EVENTS = { "UseAbility", "UseItem", "Notify", "Feed", "Effect", "Banner" }
local FUNCTIONS = { "Shop", "RedeemCode" }

local folder: Folder
if RunService:IsServer() then
	folder = Instance.new("Folder")
	folder.Name = "Remotes"
	for _, name in EVENTS do
		local e = Instance.new("RemoteEvent")
		e.Name = name
		e.Parent = folder
	end
	for _, name in FUNCTIONS do
		local f = Instance.new("RemoteFunction")
		f.Name = name
		f.Parent = folder
	end
	folder.Parent = ReplicatedStorage
else
	folder = ReplicatedStorage:WaitForChild("Remotes") :: Folder
end

local function event(name: string): RemoteEvent
	return folder:WaitForChild(name) :: RemoteEvent
end
local function func(name: string): RemoteFunction
	return folder:WaitForChild(name) :: RemoteFunction
end

return {
	UseAbility = event("UseAbility"), -- client -> server
	UseItem = event("UseItem"), -- client -> server (itemId)
	Notify = event("Notify"), -- server -> client (text, color?)
	Feed = event("Feed"), -- server -> all (killer, victim, kind)
	Effect = event("Effect"), -- server -> client(s) (kind, data)
	Banner = event("Banner"), -- server -> client(s) (title, subtitle, color)
	Shop = func("Shop"), -- client -> server (action, id) -> (ok, message)
	RedeemCode = func("RedeemCode"), -- client -> server (code) -> (ok, message)
}
