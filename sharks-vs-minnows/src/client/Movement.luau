--!strict
-- Huss Valley-style movement for the local character.
--
--   WASD            run. Keep running in one direction and momentum builds until you break
--                   into a sprint on your own (no sprint key), with the sprint animation.
--   Space + A / D   dash sideways. The dash only charges while you're sprinting.
--   Let go          you keep gliding on your momentum for a moment.
--   Hold S          brake: pulling back against your momentum stops you fast.
--   Left Ctrl       toggle shift lock.
--
-- There is no jumping. The server sends a base speed (player attribute "MoveSpeed") that already
-- includes ability boosts, slows, nets and the pre-crossing freeze; this builds on top of it.
-- The default control script still reads the keys; this overrides what the humanoid is told.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Fx = require(script.Parent.Fx)

local M = Config.Movement
local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local controls: any = nil
task.spawn(function()
	local ok, module = pcall(function()
		return require(player:WaitForChild("PlayerScripts"):WaitForChild("PlayerModule") :: ModuleScript) :: any
	end)
	if ok and module then
		controls = module:GetControls()
	end
end)

local Movement = {}

Movement.Momentum = 0 -- 0..1; at 1 you're sprinting
Movement.Sprinting = false
Movement.DashCharge = 0 -- 0..1; fills while sprinting
Movement.ShiftLock = false

local velocity = Vector3.zero -- the horizontal velocity we're steering the humanoid with
local lastBase = Config.MinnowSpeed
local nextDash = 0
local keepMomentumUntil = 0 -- a dash doesn't cost you your sprint
local sprintTrack: AnimationTrack? = nil

local function flat(v: Vector3): Vector3
	return Vector3.new(v.X, 0, v.Z)
end

local function unitOr(v: Vector3, fallback: Vector3): Vector3
	return if v.Magnitude > 1e-3 then v.Unit else fallback
end

local function moveToward(current: Vector3, target: Vector3, step: number): Vector3
	local delta = target - current
	local d = delta.Magnitude
	if d <= step or d < 1e-4 then
		return target
	end
	return current + delta / d * step
end

local function character(): (Model?, Humanoid?, BasePart?)
	local char = player.Character
	if not char then
		return nil, nil, nil
	end
	local h = char:FindFirstChildOfClass("Humanoid")
	local root = char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if not h or h.Health <= 0 or not root then
		return char, nil, nil
	end
	return char, h, root
end

-- Raw stick / WASD input: X = right, Y = forward.
local function rawInput(): Vector2
	if controls then
		local mv: Vector3 = controls:GetMoveVector()
		return Vector2.new(mv.X, -mv.Z)
	end
	return Vector2.zero
end

local function cameraAxes(): (Vector3, Vector3)
	local cf = camera.CFrame
	local forward = unitOr(flat(cf.LookVector), Vector3.new(0, 0, -1))
	local right = unitOr(flat(cf.RightVector), Vector3.new(1, 0, 0))
	return forward, right
end

local function baseSpeed(): number
	return player:GetAttribute("MoveSpeed") or Config.LobbySpeed
end

local function rooted(): boolean
	return player:GetAttribute("Rooted") == true
end

-- Sprint animation ------------------------------------------------------------------------------

local function loadSprintAnimation(char: Model)
	sprintTrack = nil
	local h = char:WaitForChild("Humanoid", 10) :: Humanoid?
	if not h then
		return
	end
	local animator = h:WaitForChild("Animator", 10) :: Animator?
	if not animator then
		return
	end
	local anim = Instance.new("Animation")
	anim.AnimationId = M.SprintAnimation
	local ok, track = pcall(function()
		return animator:LoadAnimation(anim)
	end)
	if ok and track then
		track.Priority = Enum.AnimationPriority.Movement -- above the default run cycle
		track.Looped = true
		sprintTrack = track
	end
end

local function updateAnimation(speed: number)
	local track = sprintTrack
	if not track then
		return
	end
	if Movement.Sprinting then
		if not track.IsPlaying then
			track:Play(0.25)
		end
		track:AdjustSpeed(math.clamp(speed / (lastBase * M.SprintMultiplier), 0.8, 1.4))
	elseif track.IsPlaying then
		track:Stop(0.25)
	end
end

-- Dash ------------------------------------------------------------------------------------------

function Movement.Dash(side: number)
	local _, h, root = character()
	if not h or not root or rooted() or os.clock() < nextDash then
		return
	end
	if Movement.DashCharge < 1 then
		return -- only a full sprint charges the dash
	end
	Movement.DashCharge = 0
	nextDash = os.clock() + M.DashCooldown
	keepMomentumUntil = os.clock() + 0.5
	local _, right = cameraAxes()
	if Movement.ShiftLock then
		right = unitOr(flat(root.CFrame.RightVector), right)
	end
	-- keep forward momentum, replace sideways momentum with the burst
	local along = velocity - right * velocity:Dot(right)
	velocity = along + right * side * M.DashSpeed
	Fx.Sound("Whoosh", 1.35)
end

function Movement.ToggleShiftLock()
	Movement.ShiftLock = not Movement.ShiftLock
	if not Movement.ShiftLock then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	Fx.Sound("Click")
end

-- Per-frame controller -----------------------------------------------------------------------

local function step(dt: number)
	local _, h, root = character()
	if not h or not root then
		velocity = Vector3.zero
		Movement.Momentum = 0
		Movement.Sprinting = false
		return
	end
	local t = os.clock()
	local base = baseSpeed()
	local held = rooted() or base <= 0

	-- Ability boosts (Dart, Lunge, Riptide…) arrive as a jump in base speed: snap to them
	-- so a burst feels like a burst instead of slowly accelerating into it.
	if base - lastBase > 10 then
		local dir = unitOr(flat(velocity), flat(root.CFrame.LookVector))
		velocity = dir * math.max(base, velocity.Magnitude)
	end
	lastBase = base

	local input = rawInput()
	local forward, right = cameraAxes()
	local wish = right * input.X + forward * input.Y
	if wish.Magnitude > 1 then
		wish = wish.Unit
	end
	local pushing = wish.Magnitude > 0.1
	local speedNow = velocity.Magnitude
	local alignment = if pushing and speedNow > 0.5 then wish.Unit:Dot(velocity / speedNow) else 0
	local braking = pushing and speedNow > 2 and alignment < -0.3

	-- Momentum: running steadily one way at full jog builds it; turning hard, braking or
	-- letting go bleeds it away. Full momentum = sprint.
	if held then
		Movement.Momentum = 0
	elseif pushing and alignment > 0.75 and speedNow >= base * 0.9 then
		Movement.Momentum = math.min(1, Movement.Momentum + dt / M.SprintBuildTime)
	elseif t > keepMomentumUntil then
		local loss = if braking then 4 elseif pushing then M.MomentumLoss else M.MomentumLoss * 1.5
		Movement.Momentum = math.max(0, Movement.Momentum - loss * dt)
	end
	if Movement.Sprinting then
		Movement.Sprinting = Movement.Momentum > 0.6 and not held
	else
		Movement.Sprinting = Movement.Momentum >= 1
	end

	-- The dash charges while you sprint, and drains away if you stop sprinting.
	if Movement.Sprinting then
		Movement.DashCharge = math.min(1, Movement.DashCharge + dt / M.DashChargeTime)
	else
		Movement.DashCharge = math.max(0, Movement.DashCharge - dt / M.DashChargeTime * 0.5)
	end

	if held then
		velocity = Vector3.zero
	else
		local top = base * (1 + (M.SprintMultiplier - 1) * (if Movement.Sprinting then 1 else Movement.Momentum * 0.3))
		local target = wish * top
		local rate
		if braking then
			rate = M.Brake
		elseif not pushing then
			rate = M.Glide
		elseif velocity.Magnitude > top + 1 then
			rate = M.Glide -- easing back down after a dash or ability burst
		elseif Movement.Sprinting and velocity.Magnitude > base then
			rate = M.SprintAccel
		else
			rate = M.Accel
		end
		velocity = moveToward(velocity, target, rate * dt)
	end

	local speed = velocity.Magnitude
	h.WalkSpeed = speed
	h:Move(if speed > 0.05 then velocity / speed else Vector3.zero, false)
	-- no jumping in Sharks Vs Minnows
	if h.UseJumpPower then
		h.UseJumpPower = false
	end
	if h.JumpHeight ~= 0 then
		h.JumpHeight = 0
	end

	local wantLock = Movement.ShiftLock and not UserInputService.TouchEnabled
	h.AutoRotate = not wantLock
	h.CameraOffset = Vector3.new(if wantLock then M.ShiftLockOffset else 0, 0, 0)

	updateAnimation(speed)

	-- FOV opens up as you hit full sprint
	local fov = M.FovBase + (M.FovSprint - M.FovBase) * (if Movement.Sprinting then 1 else 0)
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 5)
end

-- Shift lock runs after the camera has updated: lock the mouse to the center and turn the
-- body to face where the camera looks (the over-the-shoulder offset is set in step()).
local function shiftLockStep()
	if not Movement.ShiftLock or UserInputService.TouchEnabled then
		return
	end
	local _, h, root = character()
	if not h or not root then
		return
	end
	UserInputService.MouseBehavior = Enum.MouseBehavior.LockCenter
	local look = unitOr(flat(camera.CFrame.LookVector), flat(root.CFrame.LookVector))
	root.CFrame = CFrame.lookAt(root.Position, root.Position + look)
end

-- Input -------------------------------------------------------------------------------------------

function Movement.Start()
	RunService:BindToRenderStep("SvMMovement", Enum.RenderPriority.Input.Value + 1, step)
	RunService:BindToRenderStep("SvMShiftLock", Enum.RenderPriority.Camera.Value + 2, shiftLockStep)

	-- Space only dashes (with A or D held). It never jumps.
	ContextActionService:BindActionAtPriority("SvMDash", function(_, state)
		if state == Enum.UserInputState.Begin then
			local x = rawInput().X
			if math.abs(x) > 0.5 then
				Movement.Dash(math.sign(x))
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	ContextActionService:BindActionAtPriority("SvMShiftLock", function(_, state)
		if state == Enum.UserInputState.Begin then
			Movement.ToggleShiftLock()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftControl)

	-- Gamepad bumpers dash too.
	ContextActionService:BindActionAtPriority("SvMPadDash", function(_, state, input)
		if state == Enum.UserInputState.Begin then
			Movement.Dash(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)

	local function onCharacter(char: Model)
		velocity = Vector3.zero
		Movement.Momentum = 0
		Movement.DashCharge = 0
		Movement.Sprinting = false
		task.spawn(loadSprintAnimation, char)
	end
	player.CharacterAdded:Connect(onCharacter)
	if player.Character then
		onCharacter(player.Character)
	end
end

return Movement
