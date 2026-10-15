--!strict
-- Q uses your role's equipped ability; F uses your equipped consumable.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Net = require(Shared.Net)
local Arena = require(Shared.Arena)
local Combat = require(script.Parent.Combat)
local DataService = require(script.Parent.DataService)
local Hazards = require(script.Parent.Hazards)
local Phase = require(script.Parent.Phase)
local Roster = require(script.Parent.Roster)
local Status = require(script.Parent.Status)

local Effect = Net.Event("Effect")
local Notify = Net.Event("Notify")

local Abilities = {}

local function flat(v: Vector3): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	return if f.Magnitude > 1e-3 then f.Unit else Vector3.new(0, 0, 1)
end

local function tell(entry: any, payload: { [string]: any })
	if entry.Player then
		Notify:FireClient(entry.Player, payload)
	end
end

---------------------------------------------------------------------------
-- Ability handlers
---------------------------------------------------------------------------
local handlers: { [string]: (entry: any, root: BasePart) -> () } = {}

handlers.OneHitShield = function(entry, _root)
	entry.ShieldUntil = os.clock() + 0.75
	Effect:FireAllClients({ Kind = "Shield", Model = entry.Model, Duration = 0.75 })
end

handlers.PocketDoor = function(entry, root)
	Hazards.PocketDoor(entry, root)
end

handlers.EmergencyAirhorn = function(_entry, root)
	local origin = root.Position
	for _, e in Roster.WithRole("Chaser") do
		local r = Roster.Root(e)
		if r then
			local offset = r.Position - origin
			local d = Vector3.new(offset.X, 0, offset.Z).Magnitude
			if d <= 16 then
				local push = flat(offset) * (78 - d * 2)
				Status.Impulse(e, push, 0.45)
				Status.Slow(e, 0.6, 1.0)
				tell(e, { Kind = "Toast", Text = "AIRHORN!", Color = Color3.fromRGB(255, 214, 60) })
			end
		end
	end
	Effect:FireAllClients({ Kind = "Airhorn", Position = origin })
end

handlers.Cloak = function(entry, _root)
	local untilT = os.clock() + 3
	entry.CloakUntil = untilT
	Roster.SetCloak(entry, true)
	Effect:FireAllClients({ Kind = "Cloak", Model = entry.Model })
	task.delay(3, function()
		if entry.CloakUntil == untilT then
			Roster.SetCloak(entry, false)
		end
	end)
end

handlers.BearTrap = function(entry, root)
	Hazards.BearTrap(entry, root.Position + flat(root.CFrame.LookVector) * 10)
	Effect:FireAllClients({ Kind = "Toss", Model = entry.Model })
end

handlers.BowlingBall = function(entry, root)
	Hazards.BowlingBall(entry, root.Position, root.CFrame.LookVector)
	Effect:FireAllClients({ Kind = "Toss", Model = entry.Model })
end

handlers.BigDagger = function(entry, _root)
	local untilT = os.clock() + 5
	entry.BigDaggerUntil = untilT
	Roster.SetKnifeBig(entry, true)
	task.delay(5, function()
		if entry.BigDaggerUntil == untilT then
			entry.BigDaggerUntil = 0
			Roster.SetKnifeBig(entry, false)
		end
	end)
end

handlers.RocketShoes = function(entry, _root)
	Status.Rocket(entry)
	Effect:FireAllClients({ Kind = "Rocket", Model = entry.Model })
end

handlers.RufusLeash = function(entry, root)
	local origin = root.Position
	local dir = flat(root.CFrame.LookVector)
	local range = 15
	local hit, hitAlong = nil, math.huge
	for _, e in Roster.WithRole("Runner") do
		local r = Roster.Root(e)
		if r and not Arena.InSafeZone(r.Position, "A") and not Arena.InSafeZone(r.Position, "B") then
			local rel = r.Position - origin
			local along = rel:Dot(dir)
			if along > 0 and along <= range + 1 then
				local lateral = (Vector3.new(rel.X, 0, rel.Z) - dir * along).Magnitude
				if lateral <= 3.2 and along < hitAlong then
					hit, hitAlong = e, along
				end
			end
		end
	end
	local endPoint = origin + dir * (if hit then hitAlong else range)
	Effect:FireAllClients({ Kind = "Leash", Model = entry.Model, To = endPoint, Hit = hit and hit.Model })
	if hit then
		-- Friction brings the yank to rest after about 6 studs.
		local pull = flat(origin - (Roster.Root(hit) :: BasePart).Position) * 23.5
		Status.Impulse(hit, pull, 0.35)
		Status.Slow(hit, 0.6, 0.7)
		tell(hit, { Kind = "Toast", Text = "LEASHED!", Color = Color3.fromRGB(120, 220, 120), Sound = "Trap" })
	end
end

---------------------------------------------------------------------------
-- Use
---------------------------------------------------------------------------
function Abilities.Use(entry: any): boolean
	local role = entry.Role
	if (role ~= "Runner" and role ~= "Chaser") or not entry.InMatch or not Phase.IsLive() then
		return false
	end
	if Status.IsStunned(entry) then
		return false
	end
	local root = Roster.Root(entry)
	if not root then
		return false
	end
	local loadout = Roster.Loadout(entry)
	local id = if role == "Runner" then loadout.Runner else loadout.Chaser
	local def = Catalog.Abilities[id]
	if not def or def.Role ~= role then
		return false
	end
	local now = os.clock()
	if now < (entry.AbilityReady[role] or 0) then
		return false
	end
	if role == "Runner" and (Arena.InSafeZone(root.Position, "A") or Arena.InSafeZone(root.Position, "B")) and id ~= "Cloak" then
		tell(entry, { Kind = "Toast", Text = "Step onto the field to use that", Color = Color3.fromRGB(220, 220, 220) })
		return false
	end
	entry.AbilityReady[role] = now + def.Cooldown
	if entry.Player then
		entry.Player:SetAttribute("AbilityReadyAt", workspace:GetServerTimeNow() + def.Cooldown)
		entry.Player:SetAttribute("AbilityCooldown", def.Cooldown)
	end
	if role == "Chaser" and entry.CloakUntil > 0 then
		Roster.SetCloak(entry, false)
	end
	local handler = handlers[id]
	if handler then
		handler(entry, root)
	end
	return true
end

function Abilities.UseItem(entry: any): boolean
	if not entry.InMatch or not Phase.InArena() then
		return false
	end
	local loadout = Roster.Loadout(entry)
	local id = loadout.Item
	local def = Catalog.Items[id]
	if not def then
		return false
	end
	local role = entry.Role
	local now = os.clock()
	if now < entry.ItemReadyAt then
		return false
	end
	if id == "RescueKit" then
		if role ~= "Downed" then
			tell(entry, { Kind = "Toast", Text = "Rescue Kits work when you're downed", Color = Color3.fromRGB(220, 220, 220) })
			return false
		end
	elseif not def.Roles[role] or not Phase.IsLive() or Status.IsStunned(entry) then
		return false
	end
	-- Spend a charge (bots have unlimited).
	if entry.Player then
		local p = DataService.Get(entry.Player)
		if not p or (p.Items[id] or 0) <= 0 then
			tell(entry, { Kind = "Toast", Text = "Out of " .. def.Name .. ". Buy more in the shop.", Color = Color3.fromRGB(255, 160, 160) })
			return false
		end
		DataService.Mutate(entry.Player, function(prof)
			prof.Items[id] -= 1
			if prof.Items[id] <= 0 then
				prof.Items[id] = nil
				prof.Equipped.Item = ""
			end
		end)
		entry.Player:SetAttribute("ItemReadyAt", workspace:GetServerTimeNow() + def.Cooldown)
		entry.Player:SetAttribute("ItemCooldown", def.Cooldown)
	end
	entry.ItemReadyAt = now + def.Cooldown
	-- Using an item ends Cloak.
	if entry.CloakUntil > 0 then
		Roster.SetCloak(entry, false)
	end
	local root = Roster.Root(entry)
	if id == "RescueKit" then
		Combat.Revive(entry, nil)
	elseif id == "BananaPeel" and root then
		Hazards.BananaPeel(entry, root.Position - flat(root.CFrame.LookVector) * 2.5)
	elseif id == "Adrenaline" then
		Status.Boost(entry, 1.25, 5)
		Effect:FireAllClients({ Kind = "Adrenaline", Model = entry.Model })
		tell(entry, { Kind = "Toast", Text = "ADRENALINE!", Color = Color3.fromRGB(80, 230, 160), Sound = "Dash" })
	end
	return true
end

function Abilities.Start()
	Net.Event("UseAbility").OnServerEvent:Connect(function(player)
		local e = Roster.ForPlayer(player)
		if e then
			Abilities.Use(e)
		end
	end)
	Net.Event("UseItem").OnServerEvent:Connect(function(player)
		local e = Roster.ForPlayer(player)
		if e then
			Abilities.UseItem(e)
		end
	end)
end

return Abilities
