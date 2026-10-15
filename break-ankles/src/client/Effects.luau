--!strict
-- Visual and audio effects that every client draws for itself: knife
-- swings, dash trails, shields, airhorns, ankle breaks, gem spin, bleed-out
-- bars, and camera shake.

local CollectionService = game:GetService("CollectionService")
local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer

local Effects = {}

local function rootOf(model: Instance?): BasePart?
	if model and model:IsA("Model") then
		local r = model:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			return r
		end
	end
	return nil
end

local function isMe(model: Instance?): boolean
	return model ~= nil and model == player.Character
end

local function localPart(props: { [string]: any }): Part
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Material = Enum.Material.Neon
	for k, v in props do
		(p :: any)[k] = v
	end
	p.Parent = workspace.CurrentCamera
	return p
end

---------------------------------------------------------------------------
-- Camera shake
---------------------------------------------------------------------------
local shakeUntil = 0
local shakePower = 0

function Effects.Shake(power: number, duration: number)
	shakePower = math.max(shakePower, power)
	shakeUntil = math.max(shakeUntil, os.clock() + duration)
end

---------------------------------------------------------------------------
-- Knife swing: tween the shoulder joint locally and light the trail.
---------------------------------------------------------------------------
local originalC0: { [Motor6D]: CFrame } = {}

local function shoulder(model: Model): (Motor6D?, boolean)
	local r15 = model:FindFirstChild("RightUpperArm")
	if r15 then
		local m = r15:FindFirstChild("RightShoulder")
		if m and m:IsA("Motor6D") then
			return m, false
		end
	end
	local torso = model:FindFirstChild("Torso")
	if torso then
		local m = torso:FindFirstChild("Right Shoulder")
		if m and m:IsA("Motor6D") then
			return m, true
		end
	end
	return nil, false
end

local function swingArm(model: Model)
	local motor, r6 = shoulder(model)
	if not motor then
		return
	end
	local base = originalC0[motor]
	if not base then
		base = motor.C0
		originalC0[motor] = base
		motor.Destroying:Connect(function()
			originalC0[motor] = nil
		end)
	end
	local function pose(raise: number, twist: number): CFrame
		if r6 then
			return base * CFrame.Angles(0, 0, math.rad(raise))
		end
		return base * CFrame.Angles(math.rad(raise), 0, math.rad(twist))
	end
	local m = motor :: Motor6D
	local up = TweenService:Create(m, TweenInfo.new(0.06, Enum.EasingStyle.Quad), { C0 = pose(150, -20) })
	local down = TweenService:Create(m, TweenInfo.new(0.12, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { C0 = pose(30, 35) })
	local back = TweenService:Create(m, TweenInfo.new(0.22, Enum.EasingStyle.Quad), { C0 = base })
	up:Play()
	up.Completed:Once(function()
		down:Play()
		down.Completed:Once(function()
			back:Play()
		end)
	end)
	local knife = model:FindFirstChild("BA_Knife")
	local blade = knife and knife:FindFirstChild("Blade")
	local trail = blade and blade:FindFirstChild("SwingTrail")
	if trail and trail:IsA("Trail") then
		trail.Enabled = true
		task.delay(0.3, function()
			trail.Enabled = false
		end)
	end
end

function Effects.LocalSwing()
	local char = player.Character
	if char then
		swingArm(char)
		Sounds.Play("Swing", 1 + math.random() * 0.15)
	end
end

---------------------------------------------------------------------------
-- Trails
---------------------------------------------------------------------------
local function dashTrail(model: Model, color: Color3, duration: number)
	local root = rootOf(model)
	if not root then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Position = Vector3.new(0, 1.2, 0)
	a0.Parent = root
	local a1 = Instance.new("Attachment")
	a1.Position = Vector3.new(0, -1.6, 0)
	a1.Parent = root
	local trail = Instance.new("Trail")
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.22
	trail.Color = ColorSequence.new(color)
	trail.Transparency = NumberSequence.new(0.35, 1)
	trail.LightEmission = 0.5
	trail.FaceCamera = true
	trail.Parent = root
	task.delay(duration, function()
		trail.Enabled = false
	end)
	Debris:AddItem(trail, duration + 0.5)
	Debris:AddItem(a0, duration + 0.5)
	Debris:AddItem(a1, duration + 0.5)
end

local function dust(position: Vector3, color: Color3?)
	local p = localPart({ Size = Vector3.new(0.2, 0.2, 0.2), Position = position, Transparency = 1 })
	local e = Instance.new("ParticleEmitter")
	e.Color = ColorSequence.new(color or Color3.fromRGB(220, 210, 190))
	e.Size = NumberSequence.new(1.2, 2.6)
	e.Transparency = NumberSequence.new(0.3, 1)
	e.Lifetime = NumberRange.new(0.4, 0.7)
	e.Speed = NumberRange.new(6, 12)
	e.SpreadAngle = Vector2.new(180, 30)
	e.Drag = 4
	e.Rate = 0
	e.Parent = p
	e:Emit(14)
	Debris:AddItem(p, 1.5)
end

function Effects.LocalDash()
	local char = player.Character
	if char then
		dashTrail(char, Color3.fromRGB(255, 255, 255), 0.25)
		local root = rootOf(char)
		if root then
			dust(root.Position - Vector3.new(0, 2.5, 0))
		end
	end
end

---------------------------------------------------------------------------
-- Pop-up text over a character
---------------------------------------------------------------------------
local function worldText(model: Model, text: string, color: Color3, duration: number)
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local gui = Instance.new("BillboardGui")
	gui.Size = UDim2.fromOffset(320, 70)
	gui.StudsOffset = Vector3.new(0, 4.5, 0)
	gui.AlwaysOnTop = true
	gui.Adornee = head
	gui.Parent = player:WaitForChild("PlayerGui")
	local label = Instance.new("TextLabel")
	label.BackgroundTransparency = 1
	label.Size = UDim2.fromScale(1, 1)
	label.Font = Enum.Font.FredokaOne
	label.TextScaled = true
	label.Text = text
	label.TextColor3 = color
	label.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Thickness = 3
	stroke.Parent = label
	local scale = Instance.new("UIScale")
	scale.Scale = 0.3
	scale.Parent = label
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Scale = 1 }):Play()
	TweenService:Create(gui, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { StudsOffset = Vector3.new(0, 7, 0) }):Play()
	task.delay(duration * 0.6, function()
		TweenService:Create(label, TweenInfo.new(duration * 0.4), { TextTransparency = 1 }):Play()
		TweenService:Create(stroke, TweenInfo.new(duration * 0.4), { Transparency = 1 }):Play()
	end)
	Debris:AddItem(gui, duration + 0.1)
end

---------------------------------------------------------------------------
-- Server effect events
---------------------------------------------------------------------------
local handlers: { [string]: (any) -> () } = {}

handlers.Swing = function(e)
	local model = e.Model
	if not model or isMe(model) then
		return
	end
	swingArm(model)
	local root = rootOf(model)
	if root then
		Sounds.PlayAt("Swing", root.Position, if e.Big then 0.75 else 1)
	end
end

handlers.Dash = function(e)
	if e.Model and not isMe(e.Model) then
		dashTrail(e.Model, Color3.fromRGB(255, 255, 255), 0.25)
		local root = rootOf(e.Model)
		if root then
			dust(root.Position - Vector3.new(0, 2.5, 0))
		end
	end
end

handlers.Down = function(e)
	local root = rootOf(e.Model)
	if root then
		Sounds.PlayAt("Down", root.Position)
		dust(root.Position - Vector3.new(0, 2, 0), Color3.fromRGB(255, 120, 120))
	end
	if isMe(e.By) then
		Effects.Shake(0.25, 0.2)
	end
end

handlers.AnkleBreak = function(e)
	local chaser = e.Chaser
	if chaser then
		worldText(chaser, "ANKLES BROKEN!", Color3.fromRGB(255, 200, 60), 1.8)
		local root = rootOf(chaser)
		if root then
			Sounds.PlayAt("AnkleBreak", root.Position)
			dust(root.Position - Vector3.new(0, 2.5, 0))
		end
	end
	if isMe(chaser) then
		Effects.Shake(0.9, 0.5)
	elseif isMe(e.Runner) then
		Effects.Shake(0.3, 0.25)
	end
end

handlers.Shield = function(e)
	local root = rootOf(e.Model)
	if not root then
		return
	end
	local bubble = localPart({
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		Material = Enum.Material.ForceField,
		Color = Color3.fromRGB(90, 200, 255),
		CFrame = root.CFrame,
	})
	local follow = RunService.RenderStepped:Connect(function()
		bubble.CFrame = root.CFrame
	end)
	task.delay(e.Duration or 0.75, function()
		follow:Disconnect()
		bubble:Destroy()
	end)
	Sounds.PlayAt("Equip", root.Position, 1.4)
end

handlers.ShieldBreak = function(e)
	local root = rootOf(e.Model)
	if root then
		Sounds.PlayAt("AnkleBreak", root.Position, 1.5)
		dust(root.Position, Color3.fromRGB(90, 200, 255))
	end
end

handlers.Airhorn = function(e)
	local pos: Vector3 = e.Position
	local ring = localPart({
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(0.4, 2, 2),
		CFrame = CFrame.new(pos.X, 0.6, pos.Z) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromRGB(255, 220, 70),
		Transparency = 0.2,
	})
	TweenService:Create(ring, TweenInfo.new(0.45, Enum.EasingStyle.Quad), { Size = Vector3.new(0.4, 34, 34), Transparency = 1 }):Play()
	Debris:AddItem(ring, 0.6)
	Sounds.PlayAt("Horn", pos, 1.6)
	local root = rootOf(player.Character)
	if root and (root.Position - pos).Magnitude < 30 then
		Effects.Shake(0.5, 0.35)
	end
end

handlers.Cloak = function(e)
	local root = rootOf(e.Model)
	if root then
		dust(root.Position, Color3.fromRGB(170, 120, 255))
	end
	-- Let the cloaked player still see a ghost of themselves.
	if isMe(e.Model) then
		task.delay(0.15, function()
			local char = player.Character
			if char and char:GetAttribute("Cloaked") then
				for _, d in char:GetDescendants() do
					if (d:IsA("BasePart") or d:IsA("Decal")) and d:GetAttribute("BA_OrigT") ~= nil and d.Name ~= "HumanoidRootPart" then
						d.Transparency = 0.75
					end
				end
			end
		end)
	end
end

handlers.Toss = function(e)
	local root = rootOf(e.Model)
	if root then
		Sounds.PlayAt("Lunge", root.Position, 0.8)
	end
end

handlers.Rocket = function(e)
	if e.Model then
		dashTrail(e.Model, Color3.fromRGB(255, 140, 40), 0.35)
		local root = rootOf(e.Model)
		if root then
			Sounds.PlayAt("Horn", root.Position, 2.2)
		end
	end
end

handlers.Leash = function(e)
	local model = e.Model
	local hand = model and (model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm"))
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local a0 = Instance.new("Attachment")
	a0.Parent = hand
	local target = localPart({ Size = Vector3.new(0.6, 0.6, 0.6), Position = e.To, Transparency = 1 })
	local a1 = Instance.new("Attachment")
	a1.Parent = target
	local beam = Instance.new("Beam")
	beam.Attachment0 = a0
	beam.Attachment1 = a1
	beam.Width0 = 0.35
	beam.Width1 = 0.35
	beam.Color = ColorSequence.new(Color3.fromRGB(120, 220, 120))
	beam.LightEmission = 0.4
	beam.FaceCamera = true
	beam.Segments = 8
	beam.CurveSize0 = 2
	beam.Parent = target
	Sounds.PlayAt("Lunge", hand.Position, 1.3)
	Debris:AddItem(target, 0.4)
	Debris:AddItem(a0, 0.4)
end

handlers.Trap = function(e)
	Sounds.PlayAt("Trap", e.Position, 0.8)
	dust(e.Position, Color3.fromRGB(150, 150, 160))
end

handlers.Slip = function(e)
	local root = rootOf(e.Model)
	if root then
		Sounds.PlayAt("Trip", root.Position)
		worldText(e.Model, "WHOA!", Color3.fromRGB(255, 225, 70), 1.0)
	end
end

handlers.GemPickup = function(e)
	if isMe(e.Model) then
		Sounds.Play("Gem", 1.5)
	end
	dust(e.Position, Color3.fromRGB(196, 110, 255))
end

handlers.Door = function(e)
	Sounds.PlayAt("Trap", e.Position, 0.6)
	dust(e.Position - Vector3.new(0, 4, 0))
end

handlers.DoorHit = function(e)
	Sounds.PlayAt("Trap", e.Position, 1.1)
	dust(e.Position, Color3.fromRGB(176, 120, 70))
end

handlers.Revive = function(e)
	local root = rootOf(e.Model)
	if root then
		dust(root.Position, Color3.fromRGB(140, 255, 160))
		Sounds.PlayAt("Safe", root.Position)
	end
end

handlers.Adrenaline = function(e)
	if e.Model then
		dashTrail(e.Model, Color3.fromRGB(80, 230, 160), 5)
	end
end

function Effects.Handle(payload: any)
	local fn = handlers[payload.Kind]
	if fn then
		fn(payload)
	end
end

---------------------------------------------------------------------------
-- Per-frame: gem spin, bleed bars, revive prompt visibility, shake
---------------------------------------------------------------------------
local function eachGem(fn: (BasePart) -> ())
	local arena = workspace:FindFirstChild("Arena")
	local dyn = arena and arena:FindFirstChild("Dynamic")
	if not dyn then
		return
	end
	for _, c in dyn:GetChildren() do
		if c:IsA("BasePart") and c:GetAttribute("Gem") then
			fn(c)
		end
	end
end

function Effects.Start()
	Net.Event("Effect").OnClientEvent:Connect(Effects.Handle)

	local t = 0
	RunService.RenderStepped:Connect(function(dt)
		t += dt
		local spin = CFrame.Angles(0, dt * 2.2, 0)
		eachGem(function(g)
			local cf = g.CFrame
			local bob = math.sin(t * 3 + cf.Position.X) * 0.006
			g.CFrame = (CFrame.new(cf.Position + Vector3.new(0, bob, 0)) * spin) * (cf - cf.Position)
		end)
		local serverNow = workspace:GetServerTimeNow()
		for _, model in CollectionService:GetTagged("BA_Character") do
			if model:GetAttribute("Role") == "Downed" then
				local head = model:FindFirstChild("Head")
				local tag = head and head:FindFirstChild("BA_Tag")
				local bar = tag and tag:FindFirstChild("BleedBar")
				local fill = bar and bar:FindFirstChild("Fill")
				local untilT = model:GetAttribute("DownedUntil")
				if fill and fill:IsA("Frame") and type(untilT) == "number" then
					local frac = math.clamp((untilT - serverNow) / Config.Match.BleedOutTime, 0, 1)
					fill.Size = UDim2.fromScale(frac, 1)
				end
			end
		end
	end)

	-- Only runners see (and can use) revive prompts, and never their own.
	task.spawn(function()
		while true do
			task.wait(0.25)
			local myRole = player:GetAttribute("Role")
			for _, model in CollectionService:GetTagged("BA_Character") do
				local root = model:FindFirstChild("HumanoidRootPart")
				local prompt = root and root:FindFirstChild("RevivePrompt")
				if prompt and prompt:IsA("ProximityPrompt") then
					prompt.Enabled = myRole == "Runner" and model ~= player.Character
				end
			end
		end
	end)

	RunService:BindToRenderStep("BA_Shake", Enum.RenderPriority.Camera.Value + 1, function()
		local now = os.clock()
		if now < shakeUntil then
			local remaining = (shakeUntil - now)
			local p = shakePower * math.min(1, remaining * 4)
			local cam = workspace.CurrentCamera
			cam.CFrame = cam.CFrame * CFrame.Angles(math.rad((math.random() - 0.5) * p * 3), math.rad((math.random() - 0.5) * p * 3), 0)
		else
			shakePower = 0
		end
	end)
end

return Effects
