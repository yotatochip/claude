--!strict
-- Client-only visuals and sounds: bursts, auras, chomps, camera shake, sonar and ink.

local Debris = game:GetService("Debris")
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Fx = {}

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

local folder = Instance.new("Folder")
folder.Name = "SvMClientFx"
folder.Parent = workspace

-- Built-in sounds that ship with every Roblox client.
local SOUNDS = {
	Tick = { Id = "rbxasset://sounds/electronicpingshort.wav", Volume = 0.5 },
	Go = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.8 },
	Whoosh = { Id = "rbxasset://sounds/swoosh.wav", Volume = 0.5 },
	Chomp = { Id = "rbxasset://sounds/uuhhh.mp3", Volume = 0.6 },
	Click = { Id = "rbxasset://sounds/button.wav", Volume = 0.4 },
}
local soundCache: { [string]: Sound } = {}

function Fx.Sound(name: string, pitch: number?)
	local def = SOUNDS[name]
	if not def then
		return
	end
	local s = soundCache[name]
	if not s then
		local created = Instance.new("Sound")
		created.SoundId = def.Id
		created.Volume = def.Volume
		created.Parent = SoundService
		soundCache[name] = created
		s = created
	end
	s.PlaybackSpeed = pitch or 1
	SoundService:PlayLocalSound(s)
end

function Fx.Burst(pos: Vector3, color: Color3, size: number)
	local ball = Instance.new("Part")
	ball.Shape = Enum.PartType.Ball
	ball.Anchored = true
	ball.CanCollide = false
	ball.CanQuery = false
	ball.CanTouch = false
	ball.Material = Enum.Material.Neon
	ball.Color = color
	ball.Transparency = 0.3
	ball.Size = Vector3.one * 1
	ball.Position = pos
	ball.Parent = folder
	local t = math.clamp(size / 30, 0.35, 1.2)
	TweenService:Create(ball, TweenInfo.new(t, Enum.EasingStyle.Quad, Enum.EasingDirection.Out), { Size = Vector3.one * size, Transparency = 1 }):Play()
	Debris:AddItem(ball, t + 0.1)
end

function Fx.Aura(model: Instance?, color: Color3, duration: number)
	if not model then
		return
	end
	local root = model:FindFirstChild("HumanoidRootPart")
	if not root then
		return
	end
	local emitter = Instance.new("ParticleEmitter")
	emitter.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	emitter.Color = ColorSequence.new(color)
	emitter.LightEmission = 0.8
	emitter.Size = NumberSequence.new({ NumberSequenceKeypoint.new(0, 0.8), NumberSequenceKeypoint.new(1, 0) })
	emitter.Transparency = NumberSequence.new(0.1, 1)
	emitter.Lifetime = NumberRange.new(0.4, 0.8)
	emitter.Rate = 40
	emitter.Speed = NumberRange.new(2, 5)
	emitter.SpreadAngle = Vector2.new(180, 180)
	emitter.Parent = root
	task.delay(duration, function()
		emitter.Enabled = false
		Debris:AddItem(emitter, 1)
	end)
	if model == player.Character then
		Fx.Sound("Whoosh", 1.2)
	end
end

local shakeUntil = 0
local shakeStrength = 0
RunService:BindToRenderStep("SvMShake", Enum.RenderPriority.Camera.Value + 1, function()
	local t = os.clock()
	if t < shakeUntil then
		local k = (shakeUntil - t) * shakeStrength
		camera.CFrame *= CFrame.Angles(math.rad((math.random() - 0.5) * k), math.rad((math.random() - 0.5) * k), 0)
	end
end)

function Fx.Shake(strength: number, duration: number)
	shakeStrength = strength / duration
	shakeUntil = os.clock() + duration
end

function Fx.Chomp(pos: Vector3)
	Fx.Burst(pos, Color3.fromRGB(255, 60, 60), 9)
	-- a little splash of bubbles
	local p = Instance.new("Part")
	p.Anchored = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.Transparency = 1
	p.Size = Vector3.one
	p.Position = pos
	p.Parent = folder
	local e = Instance.new("ParticleEmitter")
	e.Texture = "rbxasset://textures/particles/sparkles_main.dds"
	e.Color = ColorSequence.new(Color3.fromRGB(220, 245, 255))
	e.Size = NumberSequence.new(0.6, 0)
	e.Lifetime = NumberRange.new(0.5, 1)
	e.Speed = NumberRange.new(10, 20)
	e.SpreadAngle = Vector2.new(60, 60)
	e.Acceleration = Vector3.new(0, -30, 0)
	e.Rate = 0
	e.Parent = p
	e:Emit(30)
	Debris:AddItem(p, 1.5)

	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	if root and (root.Position - pos).Magnitude < 40 then
		Fx.Sound("Chomp")
		Fx.Shake(6, 0.35)
	end
end

local sonarHighlights: { Highlight } = {}
function Fx.Sonar(duration: number)
	for _, h in sonarHighlights do
		h:Destroy()
	end
	table.clear(sonarHighlights)
	local function mark(model: Model)
		if model:GetAttribute("Role") == "Minnow" then
			local h = Instance.new("Highlight")
			h.FillColor = Color3.fromRGB(255, 220, 60)
			h.FillTransparency = 0.3
			h.OutlineColor = Color3.new(1, 1, 1)
			h.DepthMode = Enum.HighlightDepthMode.AlwaysOnTop
			h.Adornee = model
			h.Parent = folder
			table.insert(sonarHighlights, h)
		end
	end
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character then
			mark(p.Character)
		end
	end
	local bots = workspace:FindFirstChild("SvMBots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") then
				mark(m)
			end
		end
	end
	Fx.Sound("Tick", 0.6)
	local mine = table.clone(sonarHighlights)
	task.delay(duration, function()
		for _, h in mine do
			h:Destroy()
		end
	end)
end

local inkFrame: Frame? = nil
function Fx.SetInkFrame(frame: Frame)
	inkFrame = frame
end

function Fx.Inked(duration: number)
	local frame = inkFrame
	if not frame then
		return
	end
	frame.Visible = true
	frame.BackgroundTransparency = 0.05
	TweenService:Create(frame, TweenInfo.new(duration, Enum.EasingStyle.Quad, Enum.EasingDirection.In), { BackgroundTransparency = 1 }):Play()
	task.delay(duration, function()
		if frame.BackgroundTransparency > 0.95 then
			frame.Visible = false
		end
	end)
end

return Fx
