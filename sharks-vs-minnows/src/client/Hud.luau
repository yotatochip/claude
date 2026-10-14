--!strict
-- The in-game HUD. Everything here is driven by attributes the server sets on
-- ReplicatedStorage (round state) and on the local Player (role, coins, cooldowns).

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")

local Config = require(ReplicatedStorage.Shared.Config)
local Ui = require(script.Parent.Ui)
local Fx = require(script.Parent.Fx)

local make = Ui.make
local T = Ui.Theme

local player = Players.LocalPlayer

local Hud = {}

local gui = make("ScreenGui", {
	Name = "SvMHud", ResetOnSpawn = false, ZIndexBehavior = Enum.ZIndexBehavior.Sibling, DisplayOrder = 5,
	Parent = player:WaitForChild("PlayerGui"),
})
Hud.Gui = gui

local overlay = make("ScreenGui", {
	Name = "SvMOverlay", ResetOnSpawn = false, IgnoreGuiInset = true, DisplayOrder = 1, Parent = player.PlayerGui,
})
local ink = make("Frame", {
	Name = "Ink", Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(25, 10, 40), BackgroundTransparency = 1, Visible = false, Parent = overlay,
})
Fx.SetInkFrame(ink)

-- Status bar ------------------------------------------------------------------------------------

local status = make("Frame", {
	Name = "Status", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 6), Size = UDim2.fromOffset(380, 70),
	BackgroundColor3 = T.Panel, BackgroundTransparency = 0.1, Parent = gui,
}, { Ui.corner(16), Ui.stroke(3) })
local phaseLabel = Ui.label({ Name = "Phase", Position = UDim2.fromOffset(16, 6), Size = UDim2.new(1, -120, 0, 32), TextXAlignment = Enum.TextXAlignment.Left, Text = "WAITING", Parent = status })
local timerLabel = Ui.label({ Name = "Timer", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 4), Size = UDim2.fromOffset(100, 36), TextXAlignment = Enum.TextXAlignment.Right, Text = "", TextColor3 = Color3.fromRGB(255, 230, 120), Parent = status })
local countsLabel = Ui.label({ Name = "Counts", Position = UDim2.fromOffset(16, 40), Size = UDim2.new(1, -32, 0, 22), TextXAlignment = Enum.TextXAlignment.Left, Text = "", TextColor3 = T.Muted, Font = Ui.BodyFont, StrokeThickness = 1, Parent = status })

local roleChip = make("Frame", {
	Name = "Role", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 82), Size = UDim2.fromOffset(240, 32),
	BackgroundColor3 = T.PanelLight, Parent = gui,
}, { Ui.corner(16), Ui.stroke(2.5) })
local roleLabel = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "IN THE LOBBY", Parent = roleChip, StrokeThickness = 1.5 })
make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), Parent = roleChip })

local directionLabel = Ui.label({
	Name = "Direction", AnchorPoint = Vector2.new(0.5, 0), Position = UDim2.new(0.5, 0, 0, 120), Size = UDim2.fromOffset(420, 34),
	Text = "", TextColor3 = Color3.fromRGB(140, 255, 180), StrokeThickness = 2.5, Parent = gui,
})

local countdown = Ui.label({
	Name = "Countdown", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.38), Size = UDim2.fromOffset(300, 140),
	Text = "", StrokeThickness = 5, Parent = gui,
})

-- Currency + menu buttons ------------------------------------------------------------------------

local leftColumn = make("Frame", {
	Name = "Left", Position = UDim2.fromOffset(12, 8), Size = UDim2.fromOffset(170, 300), BackgroundTransparency = 1, Parent = gui,
}, { make("UIListLayout", { Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }) })

local function pill(order: number, icon: string, color: Color3): TextLabel
	local f = make("Frame", { LayoutOrder = order, Size = UDim2.fromOffset(160, 38), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.1, Parent = leftColumn }, { Ui.corner(19), Ui.stroke(2.5) })
	Ui.label({ Position = UDim2.fromOffset(6, 4), Size = UDim2.fromOffset(30, 30), Text = icon, Parent = f })
	return Ui.label({ Position = UDim2.fromOffset(42, 5), Size = UDim2.new(1, -54, 0, 28), Text = "0", TextXAlignment = Enum.TextXAlignment.Left, TextColor3 = color, Parent = f })
end
local coinsLabel = pill(1, "🪙", Config.Colors.Coins)
local gemsLabel = pill(2, "💎", Config.Colors.Gems)

Hud.ShopButton = Ui.button({ LayoutOrder = 3, Size = UDim2.fromOffset(160, 44), Text = "🛒 SHOP", Parent = leftColumn }, Color3.fromRGB(255, 170, 40))
Hud.CodesButton = Ui.button({ LayoutOrder = 4, Size = UDim2.fromOffset(160, 40), Text = "🎁 CODES", Parent = leftColumn }, Color3.fromRGB(150, 90, 230))
Hud.SpectateButton = Ui.button({ LayoutOrder = 5, Size = UDim2.fromOffset(160, 40), Text = "👀 SPECTATE", Visible = false, Parent = leftColumn }, Color3.fromRGB(60, 150, 230))

-- Ability + item bar -------------------------------------------------------------------------------

local bar = make("Frame", {
	Name = "Abilities", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -16), Size = UDim2.fromOffset(340, 100),
	BackgroundTransparency = 1, Parent = gui,
}, {
	make("UIListLayout", {
		FillDirection = Enum.FillDirection.Horizontal, HorizontalAlignment = Enum.HorizontalAlignment.Center,
		VerticalAlignment = Enum.VerticalAlignment.Bottom, Padding = UDim.new(0, 10), SortOrder = Enum.SortOrder.LayoutOrder,
	}),
})

type Slot = { Button: TextButton, Icon: TextLabel, Name: TextLabel, Key: TextLabel, Count: TextLabel?, Cooldown: Frame, CooldownText: TextLabel }

local function slot(order: number, size: number, key: string, withCount: boolean): Slot
	local b = make("TextButton", {
		LayoutOrder = order, Size = UDim2.fromOffset(size, size), BackgroundColor3 = T.Panel, AutoButtonColor = true, Text = "", Parent = bar,
	}, { Ui.corner(14), Ui.stroke(3) })
	local icon = Ui.label({ AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.42), Size = UDim2.fromScale(0.55, 0.5), Text = "", Parent = b })
	local name = Ui.label({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -4), Size = UDim2.new(1, -8, 0, 14), Text = "", Font = Ui.BodyFont, StrokeThickness = 1, Parent = b })
	local keyChip = make("Frame", { Position = UDim2.fromOffset(-6, -6), Size = UDim2.fromOffset(24, 24), BackgroundColor3 = Color3.fromRGB(250, 250, 250), ZIndex = 3, Parent = b }, { Ui.corner(6), Ui.stroke(2) })
	local keyLabel = make("TextLabel", { Size = UDim2.fromScale(1, 1), BackgroundTransparency = 1, Font = Ui.Font, TextScaled = true, TextColor3 = T.Stroke, Text = key, ZIndex = 3, Parent = keyChip })
	local count = nil
	if withCount then
		count = Ui.label({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -4, 0, 2), Size = UDim2.fromOffset(30, 18), Text = "0", TextXAlignment = Enum.TextXAlignment.Right, ZIndex = 3, Parent = b })
	end
	local cd = make("Frame", {
		AnchorPoint = Vector2.new(0, 1), Position = UDim2.fromScale(0, 1), Size = UDim2.fromScale(1, 0), BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.35, ZIndex = 2, Parent = b,
	}, { Ui.corner(14) })
	local cdText = Ui.label({ Size = UDim2.fromScale(1, 1), Text = "", ZIndex = 4, Parent = b })
	return { Button = b, Icon = icon, Name = name, Key = keyLabel, Count = count, Cooldown = cd, CooldownText = cdText }
end

Hud.AbilitySlot = slot(1, 96, "Q", false)
Hud.ItemSlots = {} :: { [string]: Slot }
for i, id in Config.ItemOrder do
	local def = Config.Items[id]
	local s = slot(i + 1, 70, def.Key, true)
	s.Icon.Text = def.Icon
	s.Name.Text = def.Name
	s.Button.BackgroundColor3 = T.Panel
	Hud.ItemSlots[id] = s
end

-- Stamina ----------------------------------------------------------------------------------------------

local staminaFrame = make("Frame", {
	Name = "Stamina", AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -124), Size = UDim2.fromOffset(320, 16),
	BackgroundColor3 = T.Panel, BackgroundTransparency = 0.15, Parent = gui,
}, { Ui.corner(8), Ui.stroke(2.5) })
local staminaFill = make("Frame", {
	Size = UDim2.fromScale(1, 1), BackgroundColor3 = Color3.fromRGB(110, 230, 255), Parent = staminaFrame,
}, { Ui.corner(8), Ui.gradient(Color3.new(1, 1, 1), Color3.fromRGB(170, 170, 170)) })
local staminaText = Ui.label({
	AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 0, -2), Size = UDim2.fromOffset(200, 16),
	Text = "STAMINA", Font = Ui.BodyFont, StrokeThickness = 1, Parent = staminaFrame,
})

function Hud.SetStamina(fraction: number, exhausted: boolean, sprinting: boolean)
	staminaFill.Size = UDim2.fromScale(math.clamp(fraction, 0, 1), 1)
	staminaFill.BackgroundColor3 = if exhausted then T.Bad elseif sprinting then Color3.fromRGB(255, 210, 80) else Color3.fromRGB(110, 230, 255)
	staminaText.Text = if exhausted then "WINDED" elseif sprinting then "SPRINTING" else "STAMINA"
	staminaText.TextColor3 = if exhausted then T.Bad else T.Text
end

Ui.label({
	Name = "Keys", AnchorPoint = Vector2.new(0, 1), Position = UDim2.new(0, 12, 1, -10), Size = UDim2.fromOffset(560, 18),
	TextXAlignment = Enum.TextXAlignment.Left, Font = Ui.BodyFont, StrokeThickness = 1, TextColor3 = T.Muted,
	Text = "Shift sprint · Space vault · Space+A/D dash · C slide · Alt stop · Ctrl shift lock · Q ability",
	Visible = not UserInputService.TouchEnabled, Parent = gui,
})

-- Touch controls for the movement moves (phones and tablets only).
Hud.Touch = {} :: { [string]: TextButton }
if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
	local pad = make("Frame", {
		Name = "TouchMoves", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -150, 1, -150), Size = UDim2.fromOffset(150, 210),
		BackgroundTransparency = 1, Parent = gui,
	}, {
		make("UIGridLayout", { CellSize = UDim2.fromOffset(70, 62), CellPadding = UDim2.fromOffset(8, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
	})
	for i, info in { { "Sprint", "SPRINT" }, { "Slide", "SLIDE" }, { "DashL", "◀ DASH" }, { "DashR", "DASH ▶" }, { "Vault", "VAULT" }, { "Stop", "STOP" } } do
		Hud.Touch[info[1]] = Ui.button({ LayoutOrder = i, Text = info[2], BackgroundTransparency = 0.15, Parent = pad }, T.PanelLight)
	end
end

-- Banner, toasts, feed ---------------------------------------------------------------------------

local bannerFrame = make("Frame", {
	Name = "Banner", AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.3), Size = UDim2.fromOffset(640, 120),
	BackgroundTransparency = 1, Visible = false, Parent = gui,
})
local bannerTitle = Ui.label({ Size = UDim2.new(1, 0, 0, 70), Text = "", StrokeThickness = 4, Parent = bannerFrame })
local bannerSub = Ui.label({ Position = UDim2.fromOffset(0, 74), Size = UDim2.new(1, 0, 0, 30), Text = "", Font = Ui.BodyFont, StrokeThickness = 2, Parent = bannerFrame })
local bannerToken = 0

function Hud.Banner(title: string, subtitle: string, color: Color3?)
	bannerToken += 1
	local token = bannerToken
	bannerTitle.Text = title
	bannerTitle.TextColor3 = color or T.Text
	bannerSub.Text = subtitle
	bannerFrame.Visible = true
	bannerFrame.Size = UDim2.fromOffset(500, 90)
	TweenService:Create(bannerFrame, TweenInfo.new(0.35, Enum.EasingStyle.Back), { Size = UDim2.fromOffset(640, 120) }):Play()
	task.delay(3.5, function()
		if bannerToken == token then
			bannerFrame.Visible = false
		end
	end)
end

local toasts = make("Frame", {
	Name = "Toasts", AnchorPoint = Vector2.new(1, 1), Position = UDim2.new(1, -14, 1, -130), Size = UDim2.fromOffset(330, 260),
	BackgroundTransparency = 1, Parent = gui,
}, {
	make("UIListLayout", { VerticalAlignment = Enum.VerticalAlignment.Bottom, HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 6), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local toastOrder = 0

function Hud.Toast(text: string, color: Color3?)
	toastOrder += 1
	local f = make("Frame", {
		LayoutOrder = toastOrder, Size = UDim2.fromOffset(320, 34), BackgroundColor3 = T.Panel, BackgroundTransparency = 0.15, Parent = toasts,
	}, { Ui.corner(10), Ui.stroke(2) })
	local l = Ui.label({ Position = UDim2.fromOffset(10, 5), Size = UDim2.new(1, -20, 1, -10), Text = text, TextColor3 = color or T.Text, TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.BodyFont, StrokeThickness = 1, Parent = f })
	local kids = toasts:GetChildren()
	local frames = 0
	for _, k in kids do
		if k:IsA("Frame") then
			frames += 1
		end
	end
	if frames > 6 then
		for _, k in kids do
			if k:IsA("Frame") and k ~= f then
				k:Destroy()
				break
			end
		end
	end
	task.delay(3.5, function()
		if f.Parent then
			TweenService:Create(f, TweenInfo.new(0.4), { BackgroundTransparency = 1 }):Play()
			TweenService:Create(l, TweenInfo.new(0.4), { TextTransparency = 1 }):Play()
			task.wait(0.4)
			f:Destroy()
		end
	end)
end

local feed = make("Frame", {
	Name = "Feed", AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -14, 0, 8), Size = UDim2.fromOffset(300, 200),
	BackgroundTransparency = 1, Parent = gui,
}, { make("UIListLayout", { HorizontalAlignment = Enum.HorizontalAlignment.Right, Padding = UDim.new(0, 4), SortOrder = Enum.SortOrder.LayoutOrder }) })
local feedOrder = 0

function Hud.Feed(killer: string, victim: string, how: string)
	feedOrder += 1
	local text = if how == "timeout" then `⏱️ {victim} was too slow` else `🦈 {killer}  chomped  🐟 {victim}`
	local f = make("Frame", { LayoutOrder = feedOrder, Size = UDim2.fromOffset(300, 28), BackgroundColor3 = Color3.fromRGB(60, 20, 30), BackgroundTransparency = 0.25, Parent = feed }, { Ui.corner(8) })
	Ui.label({ Position = UDim2.fromOffset(8, 4), Size = UDim2.new(1, -16, 1, -8), Text = text, TextXAlignment = Enum.TextXAlignment.Right, Font = Ui.BodyFont, StrokeThickness = 1, Parent = f })
	local frames = {}
	for _, k in feed:GetChildren() do
		if k:IsA("Frame") then
			table.insert(frames, k)
		end
	end
	if #frames > 5 then
		table.sort(frames, function(a, b)
			return a.LayoutOrder < b.LayoutOrder
		end)
		frames[1]:Destroy()
	end
	task.delay(6, function()
		if f.Parent then
			f:Destroy()
		end
	end)
end

-- Per-frame refresh --------------------------------------------------------------------------------

local PHASE_TEXT = {
	Waiting = "WAITING",
	Intermission = "INTERMISSION",
	Ready = "GET READY",
	Crossing = "SWIM!",
	Ended = "ROUND OVER",
}

local lastCount = -1

local function setCooldown(s: Slot, readyAt: number, total: number, t: number)
	local left = readyAt - t
	if left > 0 and total > 0 then
		s.Cooldown.Size = UDim2.fromScale(1, math.clamp(left / total, 0, 1))
		s.CooldownText.Text = tostring(math.ceil(left))
	else
		s.Cooldown.Size = UDim2.fromScale(1, 0)
		s.CooldownText.Text = ""
	end
end

function Hud.Update()
	local t = workspace:GetServerTimeNow()
	local phase = ReplicatedStorage:GetAttribute("Phase") or "Waiting"
	local endsAt = ReplicatedStorage:GetAttribute("PhaseEndsAt") or 0
	local crossing = ReplicatedStorage:GetAttribute("Crossing") or 0
	local maxCrossings = ReplicatedStorage:GetAttribute("MaxCrossings") or Config.MaxCrossings
	local direction = ReplicatedStorage:GetAttribute("Direction") or 1
	local role = player:GetAttribute("Role") or "Lobby"
	local left = math.max(0, endsAt - t)

	phaseLabel.Text = if phase == "Waiting" then (ReplicatedStorage:GetAttribute("Status") or "WAITING") else PHASE_TEXT[phase] or phase
	timerLabel.Text = if endsAt > 0 and phase ~= "Waiting" then Ui.formatTime(left) else ""
	if phase == "Ready" or phase == "Crossing" then
		countsLabel.Text = `🐟 {ReplicatedStorage:GetAttribute("MinnowsLeft") or 0} minnows   🦈 {ReplicatedStorage:GetAttribute("SharksCount") or 0} sharks   ·   crossing {crossing}/{maxCrossings}`
	elseif phase == "Intermission" then
		countsLabel.Text = "Shop up while you wait!"
	else
		countsLabel.Text = ReplicatedStorage:GetAttribute("Status") or ""
	end
	timerLabel.TextColor3 = if phase == "Crossing" and left < 5 then T.Bad else Color3.fromRGB(255, 230, 120)

	-- role chip
	if role == "Shark" then
		roleLabel.Text = "🦈 YOU'RE A SHARK"
		roleChip.BackgroundColor3 = Color3.fromRGB(150, 40, 50)
	elseif role == "Minnow" then
		roleLabel.Text = "🐟 YOU'RE A MINNOW"
		roleChip.BackgroundColor3 = Color3.fromRGB(220, 120, 30)
	else
		roleLabel.Text = if phase == "Ready" or phase == "Crossing" then "WATCHING · NEXT ROUND SOON" else "IN THE LOBBY"
		roleChip.BackgroundColor3 = T.PanelLight
	end

	-- where to go
	local root = player.Character and player.Character:FindFirstChild("HumanoidRootPart") :: BasePart?
	local safe = root ~= nil and root.Position.X * direction > Config.SafeLine
	if role == "Minnow" and (phase == "Ready" or phase == "Crossing") then
		if phase == "Crossing" and safe then
			directionLabel.Text = "✅ SAFE — hang tight"
		else
			directionLabel.Text = if direction > 0 then "SWIM TO THE EAST BEACH  ➜" else "⬅  SWIM TO THE WEST BEACH"
		end
	elseif role == "Shark" and phase == "Crossing" then
		directionLabel.Text = "CHOMP THE MINNOWS!"
	elseif role == "Shark" and phase == "Ready" then
		directionLabel.Text = "Get ready to hunt…"
	else
		directionLabel.Text = ""
	end

	-- big countdown in the last 3 seconds of Ready
	if phase == "Ready" and left <= 3.2 then
		local n = math.ceil(left)
		countdown.Text = tostring(n)
		if n ~= lastCount and n > 0 then
			lastCount = n
			Fx.Sound("Tick")
		end
	else
		countdown.Text = ""
		lastCount = -1
	end

	-- currency
	coinsLabel.Text = Ui.formatNumber(player:GetAttribute("Coins") or 0)
	gemsLabel.Text = Ui.formatNumber(player:GetAttribute("Gems") or 0)

	-- ability slot
	local active = phase == "Crossing" and role ~= "Lobby"
	local abilityId = if role == "Shark" then player:GetAttribute("EquippedShark") else player:GetAttribute("EquippedMinnow")
	local def = Config.Abilities[abilityId or ""]
	local a = Hud.AbilitySlot
	a.Icon.Text = if def then def.Icon else "?"
	a.Name.Text = if def then def.Name else ""
	a.Button.BackgroundColor3 = if def and role ~= "Lobby" then def.Color:Lerp(T.Panel, 0.55) else T.Panel
	setCooldown(a, player:GetAttribute("AbilityReadyAt") or 0, if def then def.Cooldown else 1, t)
	a.Button.BackgroundTransparency = if active then 0 else 0.45

	for id, s in Hud.ItemSlots do
		local item = Config.Items[id]
		local count = player:GetAttribute("Item_" .. id) or 0
		local usable = active and count > 0 and (item.Role == "Any" or item.Role == role)
		if s.Count then
			s.Count.Text = "x" .. count
		end
		s.Button.BackgroundTransparency = if usable then 0 else 0.5
		s.Button.BackgroundColor3 = if usable then item.Color:Lerp(T.Panel, 0.6) else T.Panel
		setCooldown(s, player:GetAttribute("ItemReadyAt") or 0, Config.ItemCooldown, t)
	end
end

return Hud
