--!strict
-- Movement effects on a participant: stuns, slows, boosts and impulses.
-- Players simulate their own characters, so effects are written as
-- attributes (in server time) that the owning client reads every frame, or
-- sent as a Knock event. Bots read the same attributes on the server.

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Knock = Net.Event("Knock")

local Status = {}

-- Bots.luau installs these so impulses reach server-driven characters.
Status.BotImpulse = nil :: ((entry: any, velocity: Vector3, lock: number) -> ())?
Status.BotRocket = nil :: ((entry: any) -> ())?

local function now(): number
	return workspace:GetServerTimeNow()
end

-- kind "Trap" freezes you in place; "Trip" knocks you over.
function Status.Stun(entry: any, duration: number, kind: string)
	local model: Model? = entry.Model
	if not model then
		return
	end
	local untilT = now() + duration
	local current = model:GetAttribute("StunUntil")
	if type(current) == "number" and current > untilT then
		return
	end
	model:SetAttribute("StunUntil", untilT)
	model:SetAttribute("StunKind", kind)
end

function Status.IsStunned(entry: any): boolean
	local model: Model? = entry.Model
	if not model then
		return false
	end
	local t = model:GetAttribute("StunUntil")
	return type(t) == "number" and t > now()
end

function Status.Slow(entry: any, mult: number, duration: number)
	local model: Model? = entry.Model
	if model then
		model:SetAttribute("SlowMult", mult)
		model:SetAttribute("SlowUntil", now() + duration)
	end
end

function Status.Boost(entry: any, mult: number, duration: number)
	local model: Model? = entry.Model
	if model then
		model:SetAttribute("BoostMult", mult)
		model:SetAttribute("BoostUntil", now() + duration)
	end
end

-- Sets the character's velocity outright and ignores input for `lock` seconds.
function Status.Impulse(entry: any, velocity: Vector3, lock: number)
	if entry.Player then
		Knock:FireClient(entry.Player, { Kind = "Impulse", Velocity = velocity, Lock = lock })
	elseif Status.BotImpulse then
		Status.BotImpulse(entry, velocity, lock)
	end
end

-- Rocket Shoes: the owner decides the direction from their input/camera.
function Status.Rocket(entry: any)
	if entry.Player then
		Knock:FireClient(entry.Player, { Kind = "Rocket" })
	elseif Status.BotRocket then
		Status.BotRocket(entry)
	end
end

function Status.Clear(entry: any)
	local model: Model? = entry.Model
	if model then
		for _, name in { "StunUntil", "StunKind", "SlowMult", "SlowUntil", "BoostMult", "BoostUntil", "Channeling" } do
			model:SetAttribute(name, nil)
		end
	end
end

return Status
