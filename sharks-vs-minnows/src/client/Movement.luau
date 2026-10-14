--!strict
-- Huss Valley-style movement for the local character.
--
--   WASD            momentum: you build up to speed and glide a little when you let go
--   Shift (hold)    sprint, drains stamina
--   Space           vault over low obstacles (a small hop in the open)
--   Space + A / D   dash sideways
--   C               slide (while running)
--   Alt             instant stop: kills your momentum
--   Left Ctrl       toggle shift lock
--
-- The server sends a base speed (player attribute "MoveSpeed") that already includes ability
-- boosts, slows, nets and the pre-crossing freeze. Everything here builds on top of that.
-- The default control script still reads the keys; this overrides what the humanoid is told.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
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

Movement.Stamina = M.StaminaMax
Movement.Exhausted = false
Movement.Sprinting = false
Movement.ShiftLock = false
Movement.SprintToggle = false -- mobile / gamepad toggle

local velocity = Vector3.zero -- the horizontal velocity we're steering the humanoid with
local sprintHeld = false
local lastDrainAt = 0
local lastBase = Config.MinnowSpeed
local slideUntil = 0
local slideDir = Vector3.zero
local nextSlide = 0
local nextDash = 0
local nextVault = 0
local camOffsetY = 0

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

local function grounded(h: Humanoid): boolean
	return h.FloorMaterial ~= Enum.Material.Air
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

local function spend(cost: number): boolean
	if Movement.Stamina < cost then
		return false
	end
	Movement.Stamina -= cost
	lastDrainAt = os.clock()
	return true
end

-- Actions -------------------------------------------------------------------------------------

function Movement.Dash(side: number)
	local _, h, root = character()
	if not h or not root or rooted() or os.clock() < nextDash or not grounded(h) then
		return
	end
	if not spend(M.DashCost) then
		return
	end
	nextDash = os.clock() + M.DashCooldown
	local _, right = cameraAxes()
	if Movement.ShiftLock then
		right = unitOr(flat(root.CFrame.RightVector), right)
	end
	-- keep forward momentum, replace sideways momentum with the burst
	local along = velocity - right * velocity:Dot(right)
	velocity = along + right * side * M.DashSpeed
	Fx.Sound("Whoosh", 1.35)
end

function Movement.Vault()
	local char, h, root = character()
	if not char or not h or not root or rooted() or os.clock() < nextVault or not grounded(h) then
		return
	end
	local forward = unitOr(flat(velocity), flat(root.CFrame.LookVector))
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = { char }
	local feet = root.Position - Vector3.new(0, h.HipHeight + root.Size.Y / 2, 0)
	local low = workspace:Raycast(feet + Vector3.new(0, 1, 0), forward * 5, params)
	local clear = workspace:Raycast(feet + Vector3.new(0, M.VaultMaxHeight, 0), forward * 6, params)
	nextVault = os.clock() + M.VaultCooldown
	if low and not clear and low.Instance.CanCollide then
		if not spend(M.VaultCost) then
			return
		end
		-- Vault: up and over, carrying (and slightly boosting) your speed.
		local speed = math.max(flat(velocity).Magnitude, baseSpeed()) * 1.1
		velocity = forward * speed
		root.AssemblyLinearVelocity = forward * speed + Vector3.new(0, M.VaultUp, 0)
		h:ChangeState(Enum.HumanoidStateType.Freefall)
		Fx.Sound("Whoosh", 0.9)
	elseif h.JumpHeight > 0 then
		h:ChangeState(Enum.HumanoidStateType.Jumping)
	end
end

function Movement.Slide()
	local _, h, root = character()
	local t = os.clock()
	if not h or not root or rooted() or t < nextSlide or not grounded(h) then
		return
	end
	local speed = flat(velocity).Magnitude
	if speed < M.SlideMinSpeed or not spend(M.SlideCost) then
		return
	end
	nextSlide = t + M.SlideCooldown
	slideUntil = t + M.SlideTime
	slideDir = unitOr(flat(velocity), flat(root.CFrame.LookVector))
	velocity = slideDir * math.max(speed, baseSpeed() * M.SprintMultiplier) * M.SlideBoost
	Remotes.Move:FireServer("Slide")
	Fx.Sound("Whoosh", 0.75)
end

function Movement.Stop()
	velocity = Vector3.zero
	slideUntil = 0
	local _, _, root = character()
	if root then
		local v = root.AssemblyLinearVelocity
		root.AssemblyLinearVelocity = Vector3.new(0, v.Y, 0)
	end
end

function Movement.ToggleShiftLock()
	Movement.ShiftLock = not Movement.ShiftLock
	if not Movement.ShiftLock then
		UserInputService.MouseBehavior = Enum.MouseBehavior.Default
	end
	Fx.Sound("Click")
end

function Movement.SetSprintToggle(on: boolean)
	Movement.SprintToggle = on
end

-- Per-frame controller -----------------------------------------------------------------------

local function isSliding(): boolean
	return os.clock() < slideUntil
end

local function step(dt: number)
	local char, h, root = character()
	if not char or not h or not root then
		velocity = Vector3.zero
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

	-- stamina + sprint
	if Movement.Exhausted and Movement.Stamina >= M.ExhaustRecover then
		Movement.Exhausted = false
	end
	local wantsSprint = sprintHeld or Movement.SprintToggle
	Movement.Sprinting = wantsSprint and wish.Magnitude > 0.1 and not Movement.Exhausted and not held
	if Movement.Sprinting then
		Movement.Stamina -= M.SprintDrain * dt
		lastDrainAt = t
		if Movement.Stamina <= 0 then
			Movement.Stamina = 0
			Movement.Exhausted = true
		end
	elseif t - lastDrainAt > M.RegenDelay then
		Movement.Stamina = math.min(M.StaminaMax, Movement.Stamina + M.StaminaRegen * dt)
	end

	local sliding = t < slideUntil
	local onGround = grounded(h)
	if held then
		velocity = Vector3.zero
		slideUntil = 0
		sliding = false
	elseif sliding then
		-- committed to the slide: glide in a straight line, bleeding speed
		local floor = base * 0.8
		local speed = math.max(floor, velocity.Magnitude - M.SlideDecel * dt)
		velocity = slideDir * speed
	else
		local target = wish * base * (if Movement.Sprinting then M.SprintMultiplier else 1)
		local rate = if wish.Magnitude > 0.05 then M.Accel else M.Decel
		-- above your normal top speed (after a dash or slide), ease back down gently
		if velocity.Magnitude > target.Magnitude + 1 and wish.Magnitude > 0.05 then
			rate = math.max(M.Decel, M.Accel * 0.6)
		end
		if not onGround then
			rate *= M.AirControl
		end
		velocity = moveToward(velocity, target, rate * dt)
	end

	local speed = velocity.Magnitude
	h.WalkSpeed = speed
	h:Move(if speed > 0.05 then velocity / speed else Vector3.zero, false)
	if h.UseJumpPower then
		h.UseJumpPower = false
	end
	h.JumpHeight = if held then 0 else 4.5

	local wantLock = Movement.ShiftLock and not UserInputService.TouchEnabled
	h.AutoRotate = not (wantLock or sliding)
	if sliding then
		root.CFrame = CFrame.lookAt(root.Position, root.Position + slideDir)
	end
	camOffsetY += ((if sliding then -1.6 else 0) - camOffsetY) * math.min(1, dt * 14)
	h.CameraOffset = Vector3.new(if wantLock then M.ShiftLockOffset else 0, camOffsetY, 0)

	-- sprint FOV kick
	local over = math.clamp((speed - base) / math.max(base * (M.SprintMultiplier - 1), 1), 0, 1)
	local fov = M.FovBase + (M.FovSprint - M.FovBase) * over
	camera.FieldOfView += (fov - camera.FieldOfView) * math.min(1, dt * 8)
end

-- Shift lock runs after the camera has updated: lock the mouse to the center and turn the
-- body to face where the camera looks (the over-the-shoulder offset is set in step()).
local function shiftLockStep()
	if not Movement.ShiftLock or UserInputService.TouchEnabled or isSliding() then
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

local function begin(state: Enum.UserInputState): boolean
	return state == Enum.UserInputState.Begin
end

function Movement.Start()
	RunService:BindToRenderStep("SvMMovement", Enum.RenderPriority.Input.Value + 1, step)
	RunService:BindToRenderStep("SvMShiftLock", Enum.RenderPriority.Camera.Value + 2, shiftLockStep)

	ContextActionService:BindActionAtPriority("SvMSprint", function(_, state)
		if state == Enum.UserInputState.Begin then
			sprintHeld = true
		elseif state == Enum.UserInputState.End or state == Enum.UserInputState.Cancel then
			sprintHeld = false
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftShift, Enum.KeyCode.RightShift)

	-- Space replaces the normal jump: dash if A/D is held, otherwise vault.
	ContextActionService:BindActionAtPriority("SvMVault", function(_, state)
		if begin(state) then
			local x = rawInput().X
			if math.abs(x) > 0.5 then
				Movement.Dash(math.sign(x))
			else
				Movement.Vault()
			end
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)

	ContextActionService:BindActionAtPriority("SvMSlide", function(_, state)
		if begin(state) then
			Movement.Slide()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.C, Enum.KeyCode.ButtonB)

	ContextActionService:BindActionAtPriority("SvMStop", function(_, state)
		if begin(state) then
			Movement.Stop()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt, Enum.KeyCode.DPadDown)

	ContextActionService:BindActionAtPriority("SvMShiftLock", function(_, state)
		if begin(state) then
			Movement.ToggleShiftLock()
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.LeftControl)

	-- Gamepad: click the left stick to toggle sprint, bumpers dash.
	ContextActionService:BindActionAtPriority("SvMPadSprint", function(_, state)
		if begin(state) then
			Movement.SprintToggle = not Movement.SprintToggle
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL3)
	ContextActionService:BindActionAtPriority("SvMPadDash", function(_, state, input)
		if begin(state) then
			Movement.Dash(if input.KeyCode == Enum.KeyCode.ButtonL1 then -1 else 1)
		end
		return Enum.ContextActionResult.Sink
	end, false, Enum.ContextActionPriority.High.Value, Enum.KeyCode.ButtonL1, Enum.KeyCode.ButtonR1)

	player.CharacterAdded:Connect(function()
		velocity = Vector3.zero
		slideUntil = 0
		Movement.Stamina = M.StaminaMax
		Movement.Exhausted = false
	end)
end

return Movement
