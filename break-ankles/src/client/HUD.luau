--!strict
-- Everything on screen during play: status bar, crossing pips, role badge,
-- big announcements, countdown, feed, popups, the ability/item bar, the
-- downed overlay, map voting, Hero-or-Chicken and the results screen.

local Players = game:GetService("Players")
local RunService = game:GetService("RunService")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Input = require(script.Parent.Input)
local MapPreview = require(script.Parent.MapPreview)
local Movement = require(script.Parent.Movement)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local State = Net.State()
local C = UI.Colors

local HUD = {}

HUD.Profile = nil :: any

local gui: ScreenGui
local refs: { [string]: any } = {}

local ROLE_STYLE = {
	Runner = { Text = "RUNNER", Color = C.Runner },
	Chaser = { Text = "CHASER", Color = C.Chaser },
	Downed = { Text = "DOWNED", Color = Color3.fromRGB(170, 170, 170) },
	Lobby = { Text = "LOBBY", Color = Color3.fromRGB(220, 220, 220) },
}

local function role(): string
	return (player:GetAttribute("Role") :: string?) or "Lobby"
end

local function timeLeft(): number
	local endsAt = State:GetAttribute("EndsAt")
	if type(endsAt) ~= "number" or endsAt == 0 then
		return -1
	end
	return math.max(0, endsAt - workspace:GetServerTimeNow())
end

local function fmtTime(t: number): string
	if t < 0 then
		return ""
	end
	local s = math.ceil(t)
	return ("%d:%02d"):format(s // 60, s % 60)
end

---------------------------------------------------------------------------
-- Build
---------------------------------------------------------------------------
local function buildTop()
	local top = UI.panel({
		Name = "Top",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 8),
		Size = UDim2.fromOffset(420, 78),
		Parent = gui,
	})
	refs.Phase = UI.text({
		Name = "Phase",
		Text = "WAITING",
		TextSize = 30,
		Size = UDim2.new(1, -110, 0, 36),
		Position = UDim2.fromOffset(16, 6),
		TextXAlignment = Enum.TextXAlignment.Left,
		Parent = top,
	})
	refs.Status = UI.text({
		Name = "Status",
		Text = "",
		Font = UI.Body,
		TextSize = 15,
		TextColor3 = C.Muted,
		Size = UDim2.new(1, -110, 0, 20),
		Position = UDim2.fromOffset(16, 44),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1,
		Parent = top,
	})
	refs.Timer = UI.text({
		Name = "Timer",
		Text = "",
		TextSize = 34,
		Size = UDim2.fromOffset(100, 40),
		Position = UDim2.new(1, -110, 0, 6),
		TextXAlignment = Enum.TextXAlignment.Right,
		Parent = top,
	})
	refs.Counts = UI.text({
		Name = "Counts",
		Text = "",
		Font = UI.Body,
		TextSize = 14,
		Size = UDim2.fromOffset(100, 20),
		Position = UDim2.new(1, -110, 0, 46),
		TextXAlignment = Enum.TextXAlignment.Right,
		RichText = true,
		StrokeThickness = 1,
		Parent = top,
	})
	-- Crossing pips under the bar.
	local pips = UI.new("Frame", {
		Name = "Pips",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 92),
		Size = UDim2.fromOffset(200, 26),
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Horizontal, 8, Enum.HorizontalAlignment.Center) })
	refs.Pips = {}
	for i = 1, Config.Match.CrossingsToWin do
		local pip = UI.new("Frame", {
			Size = UDim2.fromOffset(46, 14),
			BackgroundColor3 = Color3.fromRGB(60, 64, 76),
			LayoutOrder = i,
			Parent = pips,
		}, { UI.corner(7) :: any, UI.borderStroke(2, Color3.new(0, 0, 0), 0.3) })
		refs.Pips[i] = pip
	end
	refs.PipsFrame = pips
	-- Role badge.
	local badge = UI.panel({
		Name = "Role",
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 122),
		Size = UDim2.fromOffset(150, 34),
		Color = C.Runner,
		Transparency = 0,
		Radius = 17,
		Parent = gui,
	})
	refs.RoleBadge = badge
	refs.RoleText = UI.text({ Text = "RUNNER", TextSize = 22, Size = UDim2.fromScale(1, 1), Parent = badge })
	refs.Safe = UI.text({
		Name = "Safe",
		Text = "SAFE",
		TextSize = 22,
		TextColor3 = C.Good,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 160),
		Size = UDim2.fromOffset(300, 28),
		Visible = false,
		Parent = gui,
	})
end

local function buildCenter()
	local holder = UI.new("Frame", {
		Name = "Announce",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.36),
		Size = UDim2.fromOffset(900, 140),
		Visible = false,
		Parent = gui,
	})
	refs.AnnounceFrame = holder
	refs.AnnounceText = UI.text({ Text = "", TextSize = 72, Size = UDim2.new(1, 0, 0, 84), StrokeThickness = 4, Parent = holder })
	refs.AnnounceSub = UI.text({
		Text = "",
		Font = UI.Body,
		TextSize = 22,
		Position = UDim2.fromOffset(0, 88),
		Size = UDim2.new(1, 0, 0, 30),
		StrokeThickness = 2,
		Parent = holder,
	})
	refs.Count = UI.text({
		Name = "Count",
		Text = "",
		TextSize = 140,
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.45),
		Size = UDim2.fromOffset(300, 160),
		StrokeThickness = 6,
		Visible = false,
		Parent = gui,
	})
	refs.Toast = UI.text({
		Name = "Toast",
		Text = "",
		TextSize = 26,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0, 194),
		Size = UDim2.fromOffset(700, 32),
		Visible = false,
		StrokeThickness = 3,
		Parent = gui,
	})
	refs.Popups = UI.new("Frame", {
		Name = "Popups",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -150),
		Size = UDim2.fromOffset(400, 200),
		Parent = gui,
	})
end

local function buildFeed()
	refs.Feed = UI.new("Frame", {
		Name = "Feed",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 0),
		Position = UDim2.new(1, -14, 0, 70),
		Size = UDim2.fromOffset(330, 240),
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Vertical, 4, Enum.HorizontalAlignment.Right) })
end

local function buildCurrency()
	local panel = UI.panel({
		Name = "Wallet",
		Position = UDim2.fromOffset(14, 70),
		Size = UDim2.fromOffset(190, 104),
		Parent = gui,
	})
	refs.Gems = UI.text({ Text = "0", TextSize = 26, TextColor3 = C.Gem, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 6), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
	refs.Coins = UI.text({ Text = "0", TextSize = 26, TextColor3 = C.Coin, Size = UDim2.new(1, -20, 0, 30), Position = UDim2.fromOffset(12, 36), TextXAlignment = Enum.TextXAlignment.Left, Parent = panel })
	refs.Level = UI.text({ Text = "Level 1", Font = UI.Body, TextSize = 14, Size = UDim2.new(1, -20, 0, 16), Position = UDim2.fromOffset(12, 68), TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 1, Parent = panel })
	local bar = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(50, 54, 66),
		Position = UDim2.fromOffset(12, 88),
		Size = UDim2.new(1, -24, 0, 8),
		Parent = panel,
	}, { UI.corner(4) })
	refs.XPFill = UI.new("Frame", { BackgroundColor3 = C.Good, Size = UDim2.fromScale(0, 1), Parent = bar }, { UI.corner(4) })
	refs.Boost = UI.text({
		Text = "",
		Font = UI.Body,
		TextSize = 13,
		TextColor3 = C.Accent,
		Position = UDim2.fromOffset(14, 178),
		Size = UDim2.fromOffset(240, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1,
		Parent = gui,
	})
end

local function slot(name: string, key: string, color: Color3, order: number, parent: Instance): any
	local f = UI.panel({ Name = name, Size = UDim2.fromOffset(150, 64), LayoutOrder = order, Parent = parent })
	local keyCap = UI.new("Frame", {
		BackgroundColor3 = color,
		Position = UDim2.fromOffset(8, 8),
		Size = UDim2.fromOffset(28, 28),
		Parent = f,
	}, { UI.corner(6) :: any, UI.borderStroke(2, Color3.new(0, 0, 0), 0.2) })
	UI.text({ Text = key, TextSize = 16, Size = UDim2.fromScale(1, 1), Parent = keyCap })
	local label = UI.text({
		Text = "",
		Font = UI.Body,
		TextSize = 14,
		Position = UDim2.fromOffset(42, 6),
		Size = UDim2.new(1, -48, 0, 32),
		TextXAlignment = Enum.TextXAlignment.Left,
		TextWrapped = true,
		StrokeThickness = 1,
		Parent = f,
	})
	local sub = UI.text({
		Text = "",
		Font = UI.Body,
		TextSize = 12,
		TextColor3 = C.Muted,
		Position = UDim2.fromOffset(8, 42),
		Size = UDim2.new(1, -16, 0, 16),
		TextXAlignment = Enum.TextXAlignment.Left,
		StrokeThickness = 1,
		Parent = f,
	})
	local shade = UI.new("Frame", {
		Name = "Cooldown",
		BackgroundColor3 = Color3.new(0, 0, 0),
		BackgroundTransparency = 0.45,
		AnchorPoint = Vector2.new(0, 1),
		Position = UDim2.fromScale(0, 1),
		Size = UDim2.fromScale(1, 0),
		ZIndex = 3,
		Parent = f,
	}, { UI.corner(14) })
	return { Frame = f, Label = label, Sub = sub, Shade = shade }
end

local function buildActionBar()
	local bar = UI.new("Frame", {
		Name = "ActionBar",
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -16),
		Size = UDim2.fromOffset(660, 64),
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Horizontal, 10, Enum.HorizontalAlignment.Center) })
	refs.ActionBar = bar
	refs.AbilitySlot = slot("Ability", "Q", C.Accent, 1, bar)
	refs.ItemSlot = slot("Item", "F", C.Good, 2, bar)
	refs.DashSlot = slot("Dash", "␣", C.Blue, 3, bar)
	refs.DashSlot.Label.Text = "Dash"
	refs.DashSlot.Sub.Text = "Space + A/D"
	refs.StopSlot = slot("Stop", "Alt", Color3.fromRGB(120, 120, 130), 4, bar)
	refs.StopSlot.Label.Text = "Instant stop"
	refs.StopSlot.Sub.Text = "Fake them out"
	refs.SwingSlot = slot("Swing", "🖱", C.Chaser, 5, bar)
	refs.SwingSlot.Label.Text = "Swing knife"
	refs.SwingSlot.Sub.Text = "Click"
	if UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled then
		bar.Visible = false
	end
end

local function buildDowned()
	local overlay = UI.new("Frame", {
		Name = "Downed",
		BackgroundColor3 = Color3.fromRGB(120, 0, 0),
		BackgroundTransparency = 0.75,
		Size = UDim2.fromScale(1, 1),
		Visible = false,
		ZIndex = 0,
		Parent = gui,
	})
	UI.text({
		Text = "YOU'RE DOWN",
		TextSize = 44,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 0),
		Size = UDim2.fromOffset(600, 50),
		Parent = overlay,
	})
	refs.DownedHint = UI.text({
		Text = "",
		Font = UI.Body,
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 54),
		Size = UDim2.fromOffset(700, 24),
		Parent = overlay,
	})
	local barBg = UI.new("Frame", {
		AnchorPoint = Vector2.new(0.5, 0),
		Position = UDim2.new(0.5, 0, 0.62, 86),
		Size = UDim2.fromOffset(360, 14),
		BackgroundColor3 = Color3.fromRGB(30, 30, 30),
		Parent = overlay,
	}, { UI.corner(7) })
	refs.DownedFill = UI.new("Frame", { BackgroundColor3 = C.Bad, Size = UDim2.fromScale(1, 1), Parent = barBg }, { UI.corner(7) })
	refs.Downed = overlay
	refs.Cloaked = UI.text({
		Text = "CLOAKED",
		TextSize = 24,
		TextColor3 = Color3.fromRGB(190, 150, 255),
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -96),
		Size = UDim2.fromOffset(300, 30),
		Visible = false,
		Parent = gui,
	})
end

---------------------------------------------------------------------------
-- Map vote
---------------------------------------------------------------------------
local Shop = Net.Function("Shop")

local previewCams: { Camera } = {}

-- A picture of a map: a live 3D miniature, with the ForgeGUI art on top
-- when Config.Maps has an Image for it.
local function mapPicture(mapId: string, parent: Instance, size: UDim2, position: UDim2): Frame
	local frame = UI.new("Frame", {
		BackgroundColor3 = Color3.fromRGB(120, 180, 230),
		Size = size,
		Position = position,
		ClipsDescendants = true,
		Parent = parent,
	}, { UI.corner(10) :: any, UI.gradient(Color3.fromRGB(150, 200, 255), Color3.fromRGB(220, 235, 255)) })
	local viewport = UI.new("ViewportFrame", {
		BackgroundTransparency = 1,
		Size = UDim2.fromScale(1, 1),
		Parent = frame,
	}, { UI.corner(10) })
	table.insert(previewCams, MapPreview.Build(viewport, mapId))
	local image: string? = nil
	for _, m in Config.Maps do
		if m.Id == mapId then
			image = m.Image
		end
	end
	if image and image ~= "" then
		UI.new("ImageLabel", {
			BackgroundTransparency = 1,
			Size = UDim2.fromScale(1, 1),
			Image = image,
			ScaleType = Enum.ScaleType.Crop,
			ZIndex = 2,
			Parent = frame,
		}, { UI.corner(10) })
	end
	return frame
end

local function buildVote()
	local panel = UI.panel({
		Name = "Vote",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(580, 300),
		Visible = false,
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(580, 300), Parent = panel })
	refs.Vote = panel
	UI.text({ Text = "VOTE FOR THE MAP", TextSize = 24, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 8), Parent = panel })
	UI.button({ Text = "X", TextSize = 18, Size = UDim2.fromOffset(32, 32), Position = UDim2.new(1, -42, 0, 8), Color = C.Bad, Parent = panel }, function()
		Sounds.Play("Click")
		HUD.VoteHidden = true
	end)
	-- Collapsed form: a small button that reopens the vote.
	refs.VotePill = UI.button({
		Name = "VotePill",
		Text = "VOTE FOR THE MAP",
		TextSize = 18,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(300, 42),
		Color = C.Blue,
		Parent = gui,
	}, function()
		Sounds.Play("Click")
		HUD.VoteHidden = false
		UI.pop(panel, 0.85)
	end)
	refs.VotePill.Visible = false
	local row = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 44),
		Size = UDim2.new(1, -28, 1, -56),
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Horizontal, 14, Enum.HorizontalAlignment.Center) })
	refs.VoteButtons = {}
	for i, m in Config.Maps do
		local card = UI.new("TextButton", {
			Name = m.Id,
			Text = "",
			AutoButtonColor = false,
			BackgroundColor3 = C.Panel2,
			Size = UDim2.new(0.5, -7, 1, 0),
			LayoutOrder = i,
			Parent = row,
		}, { UI.corner(12) })
		local outline = UI.borderStroke(3, C.Accent, 1)
		outline.Parent = card
		mapPicture(m.Id, card, UDim2.new(1, -16, 0, 150), UDim2.fromOffset(8, 8))
		UI.text({ Text = m.Name, TextSize = 24, Size = UDim2.new(1, -16, 0, 28), Position = UDim2.fromOffset(8, 162), TextXAlignment = Enum.TextXAlignment.Left, Parent = card })
		UI.text({ Text = m.Blurb, Font = UI.Body, TextSize = 13, TextColor3 = C.Muted, Size = UDim2.new(1, -16, 0, 16), Position = UDim2.fromOffset(8, 192), TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 1, Parent = card })
		local count = UI.text({
			Text = "0 votes",
			TextSize = 18,
			TextColor3 = C.Accent,
			AnchorPoint = Vector2.new(1, 0),
			Size = UDim2.fromOffset(120, 28),
			Position = UDim2.new(1, -8, 0, 162),
			TextXAlignment = Enum.TextXAlignment.Right,
			Parent = card,
		})
		local scale = UI.new("UIScale", { Parent = card })
		card.MouseEnter:Connect(function()
			UI.tween(scale, 0.1, { Scale = 1.03 })
		end)
		card.MouseLeave:Connect(function()
			UI.tween(scale, 0.1, { Scale = 1 })
		end)
		card.Activated:Connect(function()
			Sounds.Play("Click")
			scale.Scale = 0.95
			UI.tween(scale, 0.15, { Scale = 1 }, Enum.EasingStyle.Back)
			HUD.MyVote = m.Id
			task.spawn(function()
				Shop:InvokeServer("Vote", m.Id)
			end)
			-- Get out of the way once you've voted.
			task.delay(0.6, function()
				if HUD.MyVote == m.Id then
					HUD.VoteHidden = true
				end
			end)
		end)
		refs.VoteButtons[m.Id] = { Button = card, Count = count, Outline = outline }
	end
end

-- Shown while the match intro plays: which map won the vote.
local function buildMapChosen()
	local panel = UI.panel({
		Name = "MapChosen",
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, 0, 1, -90),
		Size = UDim2.fromOffset(320, 230),
		Visible = false,
		Parent = gui,
	})
	refs.MapChosen = panel
	refs.MapChosenTitle = UI.text({ Text = "", TextSize = 24, Size = UDim2.new(1, 0, 0, 30), Position = UDim2.fromOffset(0, 190), Parent = panel })
	refs.MapChosenPictures = {}
	for _, m in Config.Maps do
		local pic = mapPicture(m.Id, panel, UDim2.new(1, -16, 0, 176), UDim2.fromOffset(8, 8))
		pic.Visible = false
		refs.MapChosenPictures[m.Id] = pic
	end
end

HUD.MyVote = nil :: string?
HUD.VoteHidden = false

---------------------------------------------------------------------------
-- Hero or Chicken
---------------------------------------------------------------------------
local HeroChoice = Net.Event("HeroChoice")

local function showHeroChoice(data: any)
	if refs.Hero then
		refs.Hero:Destroy()
	end
	local panel = UI.panel({
		Name = "Hero",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.55),
		Size = UDim2.fromOffset(460, 210),
		Parent = gui,
	})
	refs.Hero = panel
	UI.pop(panel)
	UI.text({ Text = "HERO OR CHICKEN?", TextSize = 34, Size = UDim2.new(1, 0, 0, 40), Position = UDim2.fromOffset(0, 10), TextColor3 = Color3.fromRGB(255, 225, 90), Parent = panel })
	UI.text({
		Text = ("Cross alone for +%d gems, or chicken out and stay with the group."):format(data.Reward or 100),
		Font = UI.Body,
		TextSize = 15,
		TextWrapped = true,
		Size = UDim2.new(1, -40, 0, 40),
		Position = UDim2.fromOffset(20, 52),
		Parent = panel,
	})
	local timer = UI.text({ Text = "", Font = UI.Body, TextSize = 14, TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.new(0, 0, 1, -24), Parent = panel })
	local function answer(choice: string)
		HeroChoice:FireServer(choice)
		Sounds.Play("Click")
		panel:Destroy()
		refs.Hero = nil
	end
	UI.button({ Text = "HERO", TextSize = 28, Color = Color3.fromRGB(255, 200, 50), Size = UDim2.fromOffset(190, 64), Position = UDim2.fromOffset(28, 100), Parent = panel }, function()
		answer("Hero")
	end)
	UI.button({ Text = "CHICKEN", TextSize = 28, Color = Color3.fromRGB(150, 150, 160), Size = UDim2.fromOffset(190, 64), Position = UDim2.fromOffset(242, 100), Parent = panel }, function()
		answer("Chicken")
	end)
	local deadline = os.clock() + (data.Time or 7)
	task.spawn(function()
		while panel.Parent and os.clock() < deadline do
			timer.Text = ("Deciding for you in %d..."):format(math.ceil(deadline - os.clock()))
			task.wait(0.2)
		end
		if panel.Parent then
			panel:Destroy()
			refs.Hero = nil
		end
	end)
end

---------------------------------------------------------------------------
-- Results
---------------------------------------------------------------------------
local function showResults(data: any)
	if refs.Results then
		refs.Results:Destroy()
	end
	local panel = UI.panel({
		Name = "Results",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.52),
		Size = UDim2.fromOffset(520, 400),
		Parent = gui,
	})
	refs.Results = panel
	UI.pop(panel, 0.7)
	UI.text({ Text = data.Headline, TextSize = 38, TextColor3 = data.Color, Size = UDim2.new(1, 0, 0, 44), Position = UDim2.fromOffset(0, 12), Parent = panel })
	UI.text({
		Text = if data.YouWon then "YOU WON!" else "Better luck next time",
		Font = UI.Body,
		TextSize = 18,
		Size = UDim2.new(1, 0, 0, 22),
		Position = UDim2.fromOffset(0, 58),
		Parent = panel,
	})
	local statsLine = ("Crossings %d   •   Ankles broken %d   •   Catches %d   •   Rescues %d"):format(data.Crossings, data.Ankles, data.Catches, data.Rescues)
	UI.text({ Text = statsLine, Font = UI.Body, TextSize = 14, TextColor3 = C.Muted, Size = UDim2.new(1, 0, 0, 18), Position = UDim2.fromOffset(0, 88), StrokeThickness = 1, Parent = panel })
	if data.MVP then
		UI.text({ Text = "MVP: " .. data.MVP, TextSize = 20, TextColor3 = C.Accent, Size = UDim2.new(1, 0, 0, 24), Position = UDim2.fromOffset(0, 112), Parent = panel })
	end
	-- Group the earnings by reason.
	local grouped: { [string]: { Gems: number, Coins: number, XP: number, Order: number } } = {}
	local order = 0
	for _, line in data.Lines or {} do
		local key = if string.find(line.Reason, "^Caught ") then "Catches" elseif string.find(line.Reason, "ankles") then "Ankle breaks" else line.Reason
		local g = grouped[key]
		if not g then
			order += 1
			g = { Gems = 0, Coins = 0, XP = 0, Order = order }
			grouped[key] = g
		end
		g.Gems += line.Gems
		g.Coins += line.Coins
		g.XP += line.XP
	end
	local list = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(30, 146),
		Size = UDim2.new(1, -60, 0, 170),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 4,
		BorderSizePixel = 0,
		Parent = panel,
	}, { UI.list(Enum.FillDirection.Vertical, 2) })
	for reason, g in grouped do
		local row = UI.new("Frame", { BackgroundTransparency = 1, Size = UDim2.new(1, -8, 0, 22), LayoutOrder = g.Order, Parent = list })
		UI.text({ Text = reason, Font = UI.Body, TextSize = 15, Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, StrokeThickness = 1, Parent = row })
		local parts = {}
		if g.Gems > 0 then
			table.insert(parts, ('<font color="#C46EFF">+%d gems</font>'):format(g.Gems))
		end
		if g.Coins > 0 then
			table.insert(parts, ('<font color="#FFCD3C">+%d coins</font>'):format(g.Coins))
		end
		if g.XP > 0 then
			table.insert(parts, ('<font color="#5ADC78">+%d xp</font>'):format(g.XP))
		end
		UI.text({ Text = table.concat(parts, "  "), RichText = true, Font = UI.Body, TextSize = 15, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), TextXAlignment = Enum.TextXAlignment.Right, StrokeThickness = 1, Parent = row })
	end
	UI.text({
		Text = ('Total  <font color="#C46EFF">+%d gems</font>   <font color="#FFCD3C">+%d coins</font>   <font color="#5ADC78">+%d xp</font>'):format(data.Gems, data.Coins, data.XP),
		RichText = true,
		TextSize = 20,
		Size = UDim2.new(1, 0, 0, 26),
		Position = UDim2.new(0, 0, 1, -66),
		Parent = panel,
	})
	UI.button({ Text = "CLOSE", TextSize = 18, Size = UDim2.fromOffset(120, 34), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -8), Color = Color3.fromRGB(90, 96, 110), Parent = panel }, function()
		panel:Destroy()
		refs.Results = nil
	end)
	task.delay(data.Time or 9, function()
		if panel.Parent then
			panel:Destroy()
			refs.Results = nil
		end
	end)
end

---------------------------------------------------------------------------
-- Notifications
---------------------------------------------------------------------------
local announceToken = 0

function HUD.Announce(text: string, sub: string?, color: Color3?)
	announceToken += 1
	local token = announceToken
	local frame = refs.AnnounceFrame :: Frame
	refs.AnnounceText.Text = text
	refs.AnnounceText.TextColor3 = color or C.Text
	refs.AnnounceSub.Text = sub or ""
	frame.Visible = true
	UI.showText(refs.AnnounceText)
	UI.showText(refs.AnnounceSub)
	UI.pop(refs.AnnounceText, 0.4)
	local function current(): boolean
		return token == announceToken
	end
	task.delay(2.4, function()
		if current() then
			UI.fadeText(refs.AnnounceText, 0.35, current)
			UI.fadeText(refs.AnnounceSub, 0.35, current)
			task.delay(0.36, function()
				if current() then
					frame.Visible = false
				end
			end)
		end
	end)
end

local toastToken = 0
function HUD.Toast(text: string, color: Color3?)
	toastToken += 1
	local token = toastToken
	local t = refs.Toast :: TextLabel
	t.Text = text
	t.TextColor3 = color or C.Text
	UI.showText(t)
	UI.pop(t, 0.7)
	local function current(): boolean
		return token == toastToken
	end
	task.delay(1.8, function()
		if current() then
			UI.fadeText(t, 0.3, current)
		end
	end)
end

local countToken = 0
function HUD.Count(text: string)
	countToken += 1
	local token = countToken
	local c = refs.Count :: TextLabel
	c.Text = text
	UI.showText(c)
	UI.pop(c, 1.6)
	Sounds.Play("Tick")
	local function current(): boolean
		return token == countToken
	end
	task.delay(0.8, function()
		if current() then
			UI.fadeText(c, 0.2, current)
		end
	end)
end

function HUD.Feed(text: string)
	local feed = refs.Feed :: Frame
	local item = UI.new("Frame", {
		BackgroundColor3 = C.Panel,
		BackgroundTransparency = 0.3,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		LayoutOrder = math.floor(os.clock() * 100),
		Parent = feed,
	}, { UI.corner(8), UI.new("UIPadding", { PaddingLeft = UDim.new(0, 10), PaddingRight = UDim.new(0, 10) }) })
	UI.text({
		Text = text,
		Font = UI.Body,
		TextSize = 15,
		Size = UDim2.fromOffset(0, 26),
		AutomaticSize = Enum.AutomaticSize.X,
		StrokeThickness = 1,
		Parent = item,
	})
	local items = {}
	for _, c in feed:GetChildren() do
		if c:IsA("Frame") then
			table.insert(items, c)
		end
	end
	table.sort(items, function(a, b)
		return a.LayoutOrder < b.LayoutOrder
	end)
	while #items > 6 do
		(table.remove(items, 1) :: Frame):Destroy()
	end
	task.delay(8, function()
		if item.Parent then
			item:Destroy()
		end
	end)
end

function HUD.Popup(text: string, sub: string?)
	local holder = refs.Popups :: Frame
	local label = UI.text({
		Text = if sub then ('%s  <font size="15" color="#DDDDDD">%s</font>'):format(text, sub) else text,
		RichText = true,
		TextSize = 24,
		TextColor3 = C.Gem,
		AnchorPoint = Vector2.new(0.5, 1),
		Position = UDim2.new(0.5, math.random(-40, 40), 1, 0),
		Size = UDim2.fromOffset(400, 30),
		Parent = holder,
	})
	if string.find(text, "Coins") and not string.find(text, "Gems") then
		label.TextColor3 = C.Coin
	end
	UI.pop(label, 0.5)
	UI.tween(label, 1.4, { Position = UDim2.new(0.5, label.Position.X.Offset, 1, -120) })
	task.delay(1.0, function()
		UI.fadeText(label, 0.4)
	end)
	task.delay(1.5, function()
		label:Destroy()
	end)
end

---------------------------------------------------------------------------
-- Profile
---------------------------------------------------------------------------
function HUD.SetProfile(p: any)
	HUD.Profile = p
	if not p then
		return
	end
	refs.Gems.Text = "💎 " .. UI.formatNumber(p.Gems)
	refs.Coins.Text = "🪙 " .. UI.formatNumber(p.Coins)
	refs.Level.Text = ("Level %d   %d / %d xp"):format(p.Level, p.XP, p.XPNeeded)
	refs.XPFill.Size = UDim2.fromScale(math.clamp(p.XP / math.max(1, p.XPNeeded), 0, 1), 1)
end

---------------------------------------------------------------------------
-- Per-frame refresh
---------------------------------------------------------------------------
local PHASE_TEXT = {
	Waiting = "WAITING",
	Intermission = "INTERMISSION",
	Intro = "GET READY",
	Countdown = "GET READY",
	Crossing = "RUN!",
	Between = "CROSSING DONE",
	HeroChoice = "HERO OR CHICKEN?",
	HeroCountdown = "HERO RUN",
	HeroRun = "HERO RUN",
	Results = "MATCH OVER",
}

local function refresh()
	local phase = (State:GetAttribute("Phase") :: string?) or "Waiting"
	local r = role()
	local inMatch = r ~= "Lobby"
	local t = timeLeft()

	local crossing = (State:GetAttribute("Crossing") :: number?) or 0
	if (phase == "Crossing" or phase == "Countdown" or phase == "Between" or phase == "HeroRun") and crossing > 0 then
		refs.Phase.Text = ("CROSSING %d/%d"):format(crossing, Config.Match.CrossingsToWin)
	else
		refs.Phase.Text = PHASE_TEXT[phase] or string.upper(phase)
	end
	local status = (State:GetAttribute("Status") :: string?) or ""
	if r == "Lobby" and phase ~= "Waiting" and phase ~= "Intermission" and phase ~= "Results" then
		status = if player:GetAttribute("AFK") then "You're AFK - turn it off to play" else "Match in progress - you'll play the next one"
	elseif phase == "Intermission" and player:GetAttribute("AFK") then
		status = "You're AFK and will sit this one out"
	end
	refs.Status.Text = status
	refs.Timer.Text = fmtTime(t)
	refs.Timer.TextColor3 = if t >= 0 and t <= 5 and (phase == "Crossing" or phase == "HeroRun") then C.Bad else C.Text
	local runners = (State:GetAttribute("Runners") :: number?) or 0
	local chasers = (State:GetAttribute("Chasers") :: number?) or 0
	refs.Counts.Text = if runners + chasers > 0
		then ('<font color="#78F096">%d run</font>  <font color="#FF5555">%d chase</font>'):format(runners, chasers)
		else ""

	-- Crossing pips.
	local showPips = inMatch or (phase ~= "Waiting" and phase ~= "Intermission")
	refs.PipsFrame.Visible = showPips and crossing > 0
	for i, pip in refs.Pips do
		local done = i < crossing or (i == crossing and phase == "Between")
		pip.BackgroundColor3 = if done then C.Good elseif i == crossing then C.Accent else Color3.fromRGB(60, 64, 76)
	end

	-- Role badge.
	local style = ROLE_STYLE[r] or ROLE_STYLE.Lobby
	refs.RoleBadge.Visible = inMatch
	refs.RoleBadge.BackgroundColor3 = style.Color
	refs.RoleText.Text = style.Text

	-- Safe indicator.
	local char = player.Character
	local root = char and char:FindFirstChild("HumanoidRootPart") :: BasePart?
	local dir = (State:GetAttribute("Direction") :: number?) or 1
	local target = Arena.TargetSide(dir)
	refs.Safe.Visible = r == "Runner" and root ~= nil and (phase == "Crossing" or phase == "HeroRun") and Arena.InSafeZone((root :: BasePart).Position, target)
	if refs.Safe.Visible then
		refs.Safe.Text = "SAFE ON SIDE " .. target
	end

	-- Action bar.
	local profile = HUD.Profile
	local bar = refs.ActionBar :: Frame
	bar.Visible = inMatch and not (UserInputService.TouchEnabled and not UserInputService.KeyboardEnabled)
	local isChaser = r == "Chaser"
	refs.DashSlot.Frame.Visible = not isChaser
	refs.StopSlot.Frame.Visible = not isChaser
	refs.SwingSlot.Frame.Visible = isChaser
	if profile then
		local abilityId = if isChaser then profile.Equipped.Chaser else profile.Equipped.Runner
		local def = Catalog.Abilities[abilityId]
		refs.AbilitySlot.Label.Text = if def then def.Name else "No ability"
		local readyAt = (player:GetAttribute("AbilityReadyAt") :: number?) or 0
		local cd = (player:GetAttribute("AbilityCooldown") :: number?) or 1
		local remain = readyAt - workspace:GetServerTimeNow()
		refs.AbilitySlot.Shade.Size = UDim2.fromScale(1, math.clamp(remain / cd, 0, 1))
		refs.AbilitySlot.Sub.Text = if remain > 0 then ("%.1fs"):format(remain) else "Ready"
		local itemId = profile.Equipped.Item
		local item = Catalog.Items[itemId]
		refs.ItemSlot.Label.Text = if item then item.Name else "No item"
		local charges = if item then (profile.Items[itemId] or 0) else 0
		local itemReady = (player:GetAttribute("ItemReadyAt") :: number?) or 0
		local itemCd = (player:GetAttribute("ItemCooldown") :: number?) or 1
		local itemRemain = itemReady - workspace:GetServerTimeNow()
		refs.ItemSlot.Shade.Size = UDim2.fromScale(1, math.clamp(itemRemain / itemCd, 0, 1))
		refs.ItemSlot.Sub.Text = if item then ("x%d left"):format(charges) else "Buy items in the shop"
	end
	local dashRemain = Movement.DashReadyAt - os.clock()
	refs.DashSlot.Shade.Size = UDim2.fromScale(1, math.clamp(dashRemain / Config.Movement.DashCooldown, 0, 1))
	refs.SwingSlot.Shade.Size = UDim2.fromScale(1, 1 - Input.SwingReadyFraction())

	-- Downed overlay.
	local downed = r == "Downed"
	refs.Downed.Visible = downed
	if downed and char then
		local untilT = char:GetAttribute("DownedUntil")
		if type(untilT) == "number" then
			local remain = untilT - workspace:GetServerTimeNow()
			refs.DownedFill.Size = UDim2.fromScale(math.clamp(remain / Config.Match.BleedOutTime, 0, 1), 1)
		end
		local kits = if profile then (profile.Items.RescueKit or 0) else 0
		local kitEquipped = profile and profile.Equipped.Item == "RescueKit"
		refs.DownedHint.Text = if kits > 0 and kitEquipped
			then ("Press F to use a Rescue Kit (%d left), or wait for a teammate"):format(kits)
			else "Wait for a teammate to revive you, or you'll join the chasers"
	end
	refs.Cloaked.Visible = char ~= nil and char:GetAttribute("Cloaked") == true

	-- Vote panel.
	local voting = phase == "Intermission" and not player:GetAttribute("AFK")
	refs.Vote.Visible = voting and not HUD.VoteHidden
	refs.VotePill.Visible = voting and HUD.VoteHidden
	if voting then
		local voted = nil
		for _, m in Config.Maps do
			if m.Id == HUD.MyVote then
				voted = m.Name
			end
		end
		refs.VotePill.Text = if voted then ("VOTED: %s  •  CHANGE"):format(string.upper(voted)) else "VOTE FOR THE MAP"
		for id, v in refs.VoteButtons do
			local n = (State:GetAttribute("Vote_" .. id) :: number?) or 0
			v.Count.Text = ("%d vote%s"):format(n, if n == 1 then "" else "s")
			v.Outline.Transparency = if HUD.MyVote == id then 0 else 1
		end
	elseif phase ~= "Intermission" then
		HUD.MyVote = nil
		HUD.VoteHidden = false
	end
	local mapId = State:GetAttribute("Map")
	refs.MapChosen.Visible = phase == "Intro"
	if refs.MapChosen.Visible then
		for id, pic in refs.MapChosenPictures do
			pic.Visible = id == mapId
		end
		local name = mapId
		for _, m in Config.Maps do
			if m.Id == mapId then
				name = m.Name
			end
		end
		refs.MapChosenTitle.Text = "MAP: " .. string.upper(tostring(name))
	end

	-- Boosts.
	if profile and profile.Boosts then
		local now = os.time()
		local parts = {}
		if (profile.Boosts.Gems or 0) > now then
			table.insert(parts, ("2x Gems %d:%02d"):format((profile.Boosts.Gems - now) // 60, (profile.Boosts.Gems - now) % 60))
		end
		if (profile.Boosts.Coins or 0) > now then
			table.insert(parts, ("2x Coins %d:%02d"):format((profile.Boosts.Coins - now) // 60, (profile.Boosts.Coins - now) % 60))
		end
		refs.Boost.Text = table.concat(parts, "   ")
	end
end

---------------------------------------------------------------------------
-- Start
---------------------------------------------------------------------------
function HUD.Start()
	gui = UI.new("ScreenGui", {
		Name = "BA_HUD",
		ResetOnSpawn = false,
		IgnoreGuiInset = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildTop()
	buildCurrency()
	buildFeed()
	buildCenter()
	buildActionBar()
	buildDowned()
	buildVote()
	buildMapChosen()

	local Notify = Net.Event("Notify")
	Notify.OnClientEvent:Connect(function(n)
		if n.Kind == "Announce" then
			HUD.Announce(n.Text, n.Sub, n.Color)
			Sounds.Play(n.Sound)
		elseif n.Kind == "Toast" then
			HUD.Toast(n.Text, n.Color)
			Sounds.Play(n.Sound)
		elseif n.Kind == "Feed" then
			HUD.Feed(n.Text)
		elseif n.Kind == "Popup" then
			HUD.Popup(n.Text, n.Sub)
		elseif n.Kind == "Count" then
			HUD.Count(n.Text)
		end
	end)
	HeroChoice.OnClientEvent:Connect(showHeroChoice)
	Net.Event("Results").OnClientEvent:Connect(showResults)
	Net.Event("ProfileChanged").OnClientEvent:Connect(HUD.SetProfile)
	task.spawn(function()
		local ok, p = pcall(function()
			return Net.Function("GetProfile"):InvokeServer()
		end)
		if ok and p and not HUD.Profile then
			HUD.SetProfile(p)
		end
	end)

	local acc = 0
	local orbitT = 0
	RunService.RenderStepped:Connect(function(dt)
		if refs.Vote.Visible or refs.MapChosen.Visible then
			orbitT += dt
			for _, cam in previewCams do
				MapPreview.Orbit(cam, orbitT)
			end
		end
		acc += dt
		if acc >= 0.05 then
			acc = 0
			refresh()
		end
	end)
end

return HUD
