--!strict
-- Momentum math shared by the player controller and the bots, so both move
-- the same way.

local Config = require(script.Parent.Config)

local Mv = Config.Movement

local MoveMath = {}

-- Speed multiplier from slows and boosts written as attributes (server time).
function MoveMath.SpeedMult(model: Instance, serverNow: number): number
	local mult = 1
	local slowUntil = model:GetAttribute("SlowUntil")
	if type(slowUntil) == "number" and serverNow < slowUntil then
		mult *= (model:GetAttribute("SlowMult") :: number?) or 1
	end
	local boostUntil = model:GetAttribute("BoostUntil")
	if type(boostUntil) == "number" and serverNow < boostUntil then
		mult *= (model:GetAttribute("BoostMult") :: number?) or 1
	end
	return mult
end

function MoveMath.Boosted(model: Instance, serverNow: number): boolean
	local boostUntil = model:GetAttribute("BoostUntil")
	return type(boostUntil) == "number" and serverNow < boostUntil
end

function MoveMath.MaxSpeed(role: string?): number
	if role == "Chaser" then
		return Mv.ChaserSpeed
	elseif role == "Runner" then
		return Mv.RunnerSpeed
	end
	return Mv.LobbySpeed
end

function MoveMath.Accel(role: string?): number
	return if role == "Chaser" then Mv.ChaserAccel else Mv.RunnerAccel
end

-- Move `vel` toward `desired`, accelerating while there's input and sliding
-- to a stop under friction when there isn't.
function MoveMath.Approach(vel: Vector3, desired: Vector3, hasInput: boolean, accel: number, dt: number): Vector3
	local rate = if hasInput then accel else Mv.Friction
	-- Above top speed (after a knockback) always bleed off with friction.
	if vel.Magnitude > desired.Magnitude + 0.5 and vel.Magnitude > MoveMath.MaxSpeed("Chaser") * 1.4 then
		rate = math.max(rate, Mv.Friction)
	end
	local diff = desired - vel
	local step = rate * dt
	if diff.Magnitude <= step then
		return desired
	end
	return vel + diff.Unit * step
end

function MoveMath.Flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

function MoveMath.FlatUnit(v: Vector3, fallback: Vector3?): Vector3
	local f = Vector3.new(v.X, 0, v.Z)
	if f.Magnitude < 1e-3 then
		return fallback or Vector3.zero
	end
	return f.Unit
end

return MoveMath
