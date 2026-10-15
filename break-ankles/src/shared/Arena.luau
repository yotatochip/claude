--!strict
-- Arena geometry shared by the server and clients. The field runs along Z.
-- Side A sits at -Z, side B at +Z. Direction 1 means runners go A -> B.

local Config = require(script.Parent.Config)

local A = Config.Arena
local HALF_L = A.Length / 2
local HALF_W = A.Width / 2

local Arena = {}

Arena.HalfLength = HALF_L
Arena.HalfWidth = HALF_W
Arena.SafeDepth = A.SafeDepth

-- Z of the line for a side ("A" or "B").
function Arena.LineZ(side: string): number
	return if side == "A" then -HALF_L else HALF_L
end

function Arena.StartSide(direction: number): string
	return if direction == 1 then "A" else "B"
end

function Arena.TargetSide(direction: number): string
	return if direction == 1 then "B" else "A"
end

function Arena.InSafeZone(pos: Vector3, side: string): boolean
	if math.abs(pos.X) > HALF_W + 1 then
		return false
	end
	if side == "A" then
		return pos.Z < -HALF_L and pos.Z > -HALF_L - A.SafeDepth - 2
	end
	return pos.Z > HALF_L and pos.Z < HALF_L + A.SafeDepth + 2
end

function Arena.OnField(pos: Vector3): boolean
	return math.abs(pos.X) <= HALF_W and math.abs(pos.Z) <= HALF_L
end

-- Anywhere inside the fenced area (field plus both safe zones).
function Arena.InBounds(pos: Vector3): boolean
	return math.abs(pos.X) <= HALF_W + 4
		and math.abs(pos.Z) <= HALF_L + A.SafeDepth + 4
		and pos.Y > -20
		and pos.Y < 60
end

-- A spread of standing spots inside a safe zone.
function Arena.SafeSpot(side: string, index: number, count: number): CFrame
	local cols = math.max(1, math.min(count, 8))
	local row = (index - 1) // cols
	local col = (index - 1) % cols
	local spacing = math.min(12, (A.Width - 20) / cols)
	local x = (col - (cols - 1) / 2) * spacing
	local depth = 8 + row * 6
	local z = if side == "A" then -HALF_L - depth else HALF_L + depth
	local facing = if side == "A" then Vector3.new(0, 0, 1) else Vector3.new(0, 0, -1)
	local pos = Vector3.new(x, 3, z)
	return CFrame.lookAt(pos, pos + facing)
end

-- Where chasers start a crossing: midfield, facing the runners.
function Arena.ChaserSpot(index: number, count: number, direction: number): CFrame
	local spacing = 14
	local x = (index - (count + 1) / 2) * spacing
	local pos = Vector3.new(x, 3, 0)
	local startZ = Arena.LineZ(Arena.StartSide(direction))
	return CFrame.lookAt(pos, Vector3.new(x, 3, startZ))
end

function Arena.LobbyCenter(): Vector3
	return A.LobbyOffset
end

return Arena
