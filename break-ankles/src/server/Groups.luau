--!strict
-- Collision groups. Players never collide with each other (no body
-- blocking). Invisible barriers only stop the group they're meant for.

local PhysicsService = game:GetService("PhysicsService")

local Groups = {}

Groups.Lobby = "BA_Lobby"
Groups.Runners = "BA_Runners"
Groups.Hero = "BA_Hero"
Groups.Chasers = "BA_Chasers"
Groups.ChaserBarrier = "BA_ChaserBarrier"
Groups.RunnerGate = "BA_RunnerGate"
Groups.PocketDoor = "BA_PocketDoor"
Groups.Pickups = "BA_Pickups"

local PLAYER_GROUPS = { Groups.Lobby, Groups.Runners, Groups.Hero, Groups.Chasers }

function Groups.Setup()
	local all = { Groups.Lobby, Groups.Runners, Groups.Hero, Groups.Chasers, Groups.ChaserBarrier, Groups.RunnerGate, Groups.PocketDoor, Groups.Pickups }
	for _, name in all do
		pcall(function()
			PhysicsService:RegisterCollisionGroup(name)
		end)
	end
	-- Players pass through each other.
	for _, a in PLAYER_GROUPS do
		for _, b in PLAYER_GROUPS do
			PhysicsService:CollisionGroupSetCollidable(a, b, false)
		end
	end
	-- Barriers: collide with exactly one kind of player, and nothing else.
	local only = {
		[Groups.ChaserBarrier] = { [Groups.Chasers] = true },
		[Groups.RunnerGate] = { [Groups.Runners] = true },
		[Groups.PocketDoor] = { [Groups.Chasers] = true },
		[Groups.Pickups] = {},
	}
	for barrier, allowed in only do
		for _, g in all do
			if g ~= barrier then
				PhysicsService:CollisionGroupSetCollidable(barrier, g, allowed[g] == true)
			end
		end
		PhysicsService:CollisionGroupSetCollidable(barrier, "Default", false)
	end
end

function Groups.SetModel(model: Model, group: string)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") then
			d.CollisionGroup = group
		end
	end
	model:SetAttribute("CollisionGroup", group)
end

-- Keep accessories that load late in the right group.
function Groups.Track(model: Model)
	model.DescendantAdded:Connect(function(d)
		if d:IsA("BasePart") then
			local g = model:GetAttribute("CollisionGroup")
			if type(g) == "string" then
				d.CollisionGroup = g
			end
		end
	end)
end

return Groups
