--!strict
-- The local movement controller. Roblox's default controls still read your
-- keys or thumbstick; this script turns that input into momentum and hands
-- the humanoid a direction and speed every frame, after the default
-- controls have run.
--
--   * acceleration and a short slide when you let go
--   * Space + A/D: lateral dash (runners), keeps your facing so it reads as a juke
--   * Alt: instant stop
--   * stuns, trips, slows and boosts set by the server

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local MoveMath = require(Shared.MoveMath)
local Net = require(Shared.Net)

local Mv = Config.Movement
local player = Players.LocalPlayer
local Juke = Net.Event("Juke")

local Movement = {}

Movement.DashReadyAt = 0
Movement.OnDash = nil :: ((dir: Vector3) -> ())?
Movement.OnStop = nil :: (() -> ())?

local controls: any = nil
local vel = Vector3.zero
local dashUntil = 0
local dashDir = Vector3.zero
local dashSpeed = 0
local dashKeepsFacing = false
local lockUntil = 0
local nextStop = 0
local fallen = false

local function getControls(): any
	if controls then
		return controls
	end
	local ok, result = pcall(function()
		local module = player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule", 10)
		return (require :: any)(module):GetControls()
	end)
	if ok then
		controls = result
	end
	return controls
end

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local hum = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	return char, hum, root
end

-- Camera-relative basis on the ground plane.
local function cameraBasis(): (Vector3, Vector3)
	local cam = workspace.CurrentCamera
	local look = MoveMath.FlatUnit(cam.CFrame.LookVector, MoveMath.FlatUnit(cam.CFrame.UpVector, Vector3.new(0, 0, -1)))
	local right = Vector3.new(-look.Z, 0, look.X)
	return look, right
end

local function rawInput(): Vector3
	local c = getControls()
	if not c then
		return Vector3.zero
	end
	local ok, mv = pcall(function()
		return c:GetMoveVector()
	end)
	return if ok and typeof(mv) == "Vector3" then mv else Vector3.zero
end

local function worldInput(): Vector3
	local mv = rawInput()
	if mv.Magnitude < 0.05 then
		return Vector3.zero
	end
	local look, right = cameraBasis()
	local world = right * mv.X + look * -mv.Z
	if world.Magnitude > 1 then
		world = world.Unit
	end
	return world
end

local function role(): string
	return (player:GetAttribute("Role") :: string?) or "Lobby"
end

local function fovKick(amount: number)
	local cam = workspace.CurrentCamera
	local base = 70
	cam.FieldOfView = base + amount
	TweenService:Create(cam, TweenInfo.new(0.35, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { FieldOfView = base }):Play()
end

local function startDash(dir: Vector3, speed: number, duration: number, keepFacing: boolean)
	local _, hum = character()
	dashDir = MoveMath.FlatUnit(dir, Vector3.new(0, 0, -1))
	dashSpeed = speed
	dashUntil = os.clock() + duration
	dashKeepsFacing = keepFacing
	if hum and keepFacing then
		hum.AutoRotate = false
	end
end

local function stunnedNow(char: Model): (boolean, string?)
	local t = char:GetAttribute("StunUntil")
	if type(t) == "number" and workspace:GetServerTimeNow() < t then
		return true, char:GetAttribute("StunKind") :: string?
	end
	return false, nil
end

local function canAct(): boolean
	local char, hum = character()
	if not char or not hum or role() == "Downed" or fallen then
		return false
	end
	if char:GetAttribute("Channeling") then
		return false
	end
	local stunned = stunnedNow(char)
	return not stunned
end

---------------------------------------------------------------------------
-- Actions
---------------------------------------------------------------------------
-- side: -1 left, 1 right; nil reads it from the keys being held.
function Movement.Dash(side: number?): boolean
	local r = role()
	if r == "Chaser" or not canAct() then
		return false
	end
	local now = os.clock()
	if now < Movement.DashReadyAt then
		return false
	end
	local mv = rawInput()
	local lateral = side
	if not lateral then
		if math.abs(mv.X) < 0.3 then
			return false -- no forward dash: hold A or D
		end
		lateral = if mv.X > 0 then 1 else -1
	end
	local look, right = cameraBasis()
	local forward = math.clamp(-mv.Z, -1, 1)
	local dir = right * (lateral :: number) + look * forward * 0.55
	startDash(dir, Mv.DashSpeed, Mv.DashTime, true)
	Movement.DashReadyAt = now + Mv.DashCooldown
	if r == "Runner" then
		Juke:FireServer("Dash")
	end
	fovKick(6)
	if Movement.OnDash then
		(Movement.OnDash :: (Vector3) -> ())(dashDir)
	end
	return true
end

function Movement.Stop(): boolean
	if not canAct() then
		return false
	end
	local now = os.clock()
	if now < nextStop then
		return false
	end
	nextStop = now + Mv.StopCooldown
	vel = Vector3.zero
	dashUntil = 0
	local _, hum, root = character()
	if root then
		root.AssemblyLinearVelocity = Vector3.new(0, root.AssemblyLinearVelocity.Y, 0)
	end
	if hum then
		hum:Move(Vector3.zero)
		hum.AutoRotate = true
	end
	if role() == "Runner" then
		Juke:FireServer("Stop")
	end
	if Movement.OnStop then
		(Movement.OnStop :: () -> ())()
	end
	return true
end

-- Chaser's little forward burst on a swing.
function Movement.Lunge()
	local _, _, root = character()
	if root and canAct() then
		startDash(root.CFrame.LookVector, Mv.LungeSpeed, Mv.LungeTime, false)
	end
end

-- Rocket Shoes: where you're moving, or where the camera looks if standing still.
function Movement.Rocket()
	local input = worldInput()
	local dir = input
	if dir.Magnitude < 0.1 then
		dir = (cameraBasis())
	end
	startDash(dir, Mv.RocketSpeed, Mv.RocketTime, false)
	fovKick(12)
end

function Movement.Impulse(velocity: Vector3, lock: number)
	vel = MoveMath.Flat(velocity)
	dashUntil = 0
	lockUntil = os.clock() + lock
	local _, hum = character()
	if hum then
		hum.AutoRotate = true
	end
end

---------------------------------------------------------------------------
-- Frame step
---------------------------------------------------------------------------
local function setFallen(want: boolean, hum: Humanoid, root: BasePart)
	if want == fallen then
		return
	end
	fallen = want
	if want then
		hum.PlatformStand = true
		root.AssemblyAngularVelocity = root.CFrame.RightVector * 7
		root.AssemblyLinearVelocity += Vector3.new(0, 6, 0)
	else
		hum.PlatformStand = false
		local p = root.Position
		local look = MoveMath.FlatUnit(root.CFrame.LookVector, Vector3.new(0, 0, -1))
		local char = player.Character
		if char then
			char:PivotTo(CFrame.lookAt(Vector3.new(p.X, p.Y + 2, p.Z), Vector3.new(p.X, p.Y + 2, p.Z) + look))
		end
		root.AssemblyAngularVelocity = Vector3.zero
		hum:ChangeState(Enum.HumanoidStateType.GettingUp)
	end
end

local function step(dt: number)
	local char, hum, root = character()
	if not char or not hum or not root or hum.Health <= 0 then
		return
	end
	local now = os.clock()
	local serverNow = workspace:GetServerTimeNow()
	local r = role()
	local stunned, kind = stunnedNow(char)
	local wantFallen = r == "Downed" or (stunned and kind == "Trip")
	setFallen(wantFallen, hum, root)

	if wantFallen or stunned or char:GetAttribute("Channeling") then
		vel = Vector3.zero
		dashUntil = 0
		hum.WalkSpeed = 0
		hum:Move(Vector3.zero)
		return
	end

	local maxSpeed = MoveMath.MaxSpeed(r) * MoveMath.SpeedMult(char, serverNow)
	if now < dashUntil then
		hum.WalkSpeed = dashSpeed
		hum:Move(dashDir)
		vel = dashDir * maxSpeed -- carry momentum out of the dash
		return
	end
	if dashKeepsFacing then
		dashKeepsFacing = false
		hum.AutoRotate = true
	end

	local input = if now < lockUntil then Vector3.zero else worldInput()
	local hasInput = input.Magnitude > 0.01
	local accel = MoveMath.Accel(r) * (if MoveMath.Boosted(char, serverNow) then 1.3 else 1)
	vel = MoveMath.Approach(vel, input * maxSpeed, hasInput, accel, dt)
	local speed = vel.Magnitude
	hum.WalkSpeed = speed
	hum:Move(if speed > 0.3 then vel.Unit else Vector3.zero)
end

local function onCharacter(char: Model)
	vel = Vector3.zero
	dashUntil = 0
	fallen = false
	local hum = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if hum then
		hum:SetStateEnabled(Enum.HumanoidStateType.Jumping, false)
		hum.UseJumpPower = true
		hum.JumpPower = 0
		hum.AutoRotate = true
	end
end

function Movement.Start()
	if player.Character then
		task.spawn(onCharacter, player.Character)
	end
	player.CharacterAdded:Connect(onCharacter)
	RunService:BindToRenderStep("BA_Movement", Enum.RenderPriority.Character.Value + 5, step)
	task.spawn(getControls)
end

return Movement
