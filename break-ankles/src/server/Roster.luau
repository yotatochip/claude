--!strict
-- Everyone who can take part in a match, players and bots alike, as one
-- Entry type. Owns roles and the visuals that go with them: collision
-- groups, the chaser highlight, the knife, name tags and the cloak.

local CollectionService = game:GetService("CollectionService")
local Players = game:GetService("Players")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Config = require(Shared.Config)
local Groups = require(script.Parent.Groups)
local DataService = require(script.Parent.DataService)
local Status = require(script.Parent.Status)

export type Earned = { Gems: number, Coins: number, XP: number, Lines: { any } }

export type Entry = {
	Id: number,
	Name: string,
	IsBot: boolean,
	Player: Player?,
	Model: Model?,
	Role: string, -- "Lobby" | "Runner" | "Chaser" | "Downed"
	InMatch: boolean,
	IsHero: boolean,
	Chicken: boolean,
	OriginalChaser: boolean,
	-- combat timers (os.clock)
	LastSwing: number,
	LastJuke: number,
	ShieldUntil: number,
	ProtectedUntil: number,
	CloakUntil: number,
	BigDaggerUntil: number,
	GraceUntil: number,
	DownedAt: number,
	DownedBy: any,
	AbilityReady: { [string]: number },
	ItemReadyAt: number,
	-- this match
	Crossings: number,
	Catches: number,
	Ankles: number,
	Rescues: number,
	Earned: Earned,
	BotLoadout: { Runner: string, Chaser: string, Item: string, Knife: string, Title: string }?,
	Bot: any, -- AI state for bots
}

local Roster = {}

local entries: { [number]: Entry } = {}
local byModel: { [Model]: Entry } = {}
local nextBotId = -1

local ROLE_TAG_COLOR = {
	Lobby = Color3.fromRGB(255, 255, 255),
	Runner = Color3.fromRGB(140, 255, 160),
	Chaser = Color3.fromRGB(255, 90, 90),
	Downed = Color3.fromRGB(170, 170, 170),
}

local function newEntry(id: number, name: string, isBot: boolean, player: Player?): Entry
	return {
		Id = id,
		Name = name,
		IsBot = isBot,
		Player = player,
		Model = nil,
		Role = "Lobby",
		InMatch = false,
		IsHero = false,
		Chicken = false,
		OriginalChaser = false,
		LastSwing = -math.huge,
		LastJuke = -math.huge,
		ShieldUntil = 0,
		ProtectedUntil = 0,
		CloakUntil = 0,
		BigDaggerUntil = 0,
		GraceUntil = 0,
		DownedAt = 0,
		DownedBy = nil,
		AbilityReady = {},
		ItemReadyAt = 0,
		Crossings = 0,
		Catches = 0,
		Ankles = 0,
		Rescues = 0,
		Earned = { Gems = 0, Coins = 0, XP = 0, Lines = {} },
		BotLoadout = nil,
		Bot = nil,
	}
end

---------------------------------------------------------------------------
-- Lookups
---------------------------------------------------------------------------
function Roster.ForPlayer(player: Player): Entry?
	return entries[player.UserId]
end

function Roster.FromModel(model: Instance?): Entry?
	if model and model:IsA("Model") then
		return byModel[model]
	end
	return nil
end

function Roster.All(): { Entry }
	local list = {}
	for _, e in entries do
		table.insert(list, e)
	end
	return list
end

function Roster.InMatch(): { Entry }
	local list = {}
	for _, e in entries do
		if e.InMatch then
			table.insert(list, e)
		end
	end
	return list
end

function Roster.WithRole(role: string): { Entry }
	local list = {}
	for _, e in entries do
		if e.InMatch and e.Role == role then
			table.insert(list, e)
		end
	end
	return list
end

function Roster.Root(entry: Entry): BasePart?
	local m = entry.Model
	if m and m.Parent then
		local r = m:FindFirstChild("HumanoidRootPart")
		if r and r:IsA("BasePart") then
			return r
		end
	end
	return nil
end

function Roster.Humanoid(entry: Entry): Humanoid?
	local m = entry.Model
	return if m then m:FindFirstChildOfClass("Humanoid") else nil
end

-- The equipped loadout, live from the profile so shop changes apply at once.
function Roster.Loadout(entry: Entry): { Runner: string, Chaser: string, Item: string, Knife: string, Title: string }
	if entry.Player then
		local p = DataService.Get(entry.Player)
		if p then
			return p.Equipped
		end
	end
	return entry.BotLoadout or {
		Runner = Catalog.StarterRunnerAbility,
		Chaser = Catalog.StarterChaserAbility,
		Item = "",
		Knife = "Classic",
		Title = "Rookie",
	}
end

---------------------------------------------------------------------------
-- Knife
---------------------------------------------------------------------------
local function knifePart(name: string, size: Vector3, color: Color3, material: Enum.Material, parent: Instance, wedge: boolean?): BasePart
	local p: BasePart = if wedge then Instance.new("WedgePart") else Instance.new("Part")
	p.Name = name
	p.Size = size
	p.Color = color
	p.Material = material
	p.Massless = true
	p.CanCollide = false
	p.CanQuery = false
	p.CanTouch = false
	p.CastShadow = false
	p.Parent = parent
	return p
end

local function attach(handle: BasePart, part: BasePart, offset: CFrame)
	part.CFrame = handle.CFrame * offset
	local w = Instance.new("Weld")
	w.Name = "Mount"
	w.Part0 = handle
	w.Part1 = part
	w.C0 = offset
	w.Parent = part
end

-- Blade and tip sizes/offsets (along the knife's +Y) for normal and Big Dagger.
local BLADE = {
	[false] = { Blade = Vector3.new(0.1, 1.9, 0.5), BladeY = 1.62, Tip = Vector3.new(0.1, 0.55, 0.5), TipY = 2.845, Trail = 0.95 },
	[true] = { Blade = Vector3.new(0.16, 3.8, 0.9), BladeY = 2.57, Tip = Vector3.new(0.16, 1.0, 0.9), TipY = 4.97, Trail = 1.9 },
}

local function shapeBlade(knife: Model, big: boolean)
	local spec = BLADE[big]
	local blade = knife:FindFirstChild("Blade") :: BasePart?
	local tip = knife:FindFirstChild("Tip") :: BasePart?
	if not blade or not tip then
		return
	end
	blade.Size = spec.Blade
	tip.Size = spec.Tip;
	(blade:FindFirstChild("Mount") :: Weld).C0 = CFrame.new(0, spec.BladeY, 0);
	(tip:FindFirstChild("Mount") :: Weld).C0 = CFrame.new(0, spec.TipY, 0)
	local top = blade:FindFirstChild("TrailTop") :: Attachment?
	local bottom = blade:FindFirstChild("TrailBottom") :: Attachment?
	if top and bottom then
		top.Position = Vector3.new(0, spec.Trail, 0)
		bottom.Position = Vector3.new(0, -spec.Trail * 0.85, 0)
	end
	knife:SetAttribute("Big", big)
end

local function buildKnife(skinId: string): Model
	local skin = Catalog.Knives[skinId] or Catalog.Knives.Classic
	local m = Instance.new("Model")
	m.Name = "BA_Knife"
	local handle = knifePart("Handle", Vector3.new(0.32, 1.1, 0.32), skin.Handle, Enum.Material.SmoothPlastic, m)
	local guard = knifePart("Guard", Vector3.new(0.75, 0.14, 0.34), Color3.fromRGB(40, 40, 44), Enum.Material.Metal, m)
	local blade = knifePart("Blade", BLADE[false].Blade, skin.Blade, skin.BladeMaterial, m)
	-- A wedge narrows along one edge, which reads as a single-edged tip.
	local tip = knifePart("Tip", BLADE[false].Tip, skin.Blade, skin.BladeMaterial, m, true)
	attach(handle, guard, CFrame.new(0, 0.6, 0))
	attach(handle, blade, CFrame.new(0, BLADE[false].BladeY, 0))
	attach(handle, tip, CFrame.new(0, BLADE[false].TipY, 0))
	if skin.Glow then
		local light = Instance.new("PointLight")
		light.Color = skin.Blade
		light.Range = 6
		light.Brightness = 1.2
		light.Parent = blade
	end
	-- Trail endpoints; clients switch the trail on during a swing.
	local a0 = Instance.new("Attachment")
	a0.Name = "TrailBottom"
	a0.Parent = blade
	local a1 = Instance.new("Attachment")
	a1.Name = "TrailTop"
	a1.Parent = blade
	local trail = Instance.new("Trail")
	trail.Name = "SwingTrail"
	trail.Attachment0 = a0
	trail.Attachment1 = a1
	trail.Lifetime = 0.16
	trail.Color = ColorSequence.new(Color3.new(1, 1, 1), skin.Blade)
	trail.Transparency = NumberSequence.new(0.25, 1)
	trail.LightEmission = 0.6
	trail.Enabled = false
	trail.Parent = blade
	m.PrimaryPart = handle
	shapeBlade(m, false)
	return m
end

local function removeKnife(model: Model)
	local k = model:FindFirstChild("BA_Knife")
	if k then
		k:Destroy()
	end
end

local function giveKnife(entry: Entry)
	local model = entry.Model
	if not model then
		return
	end
	removeKnife(model)
	local hand = model:FindFirstChild("RightHand") or model:FindFirstChild("Right Arm")
	if not hand or not hand:IsA("BasePart") then
		return
	end
	local knife = buildKnife(Roster.Loadout(entry).Knife)
	local handle = knife.PrimaryPart :: BasePart
	local isR15 = hand.Name == "RightHand"
	local grip = if isR15 then CFrame.new(0, -0.15, 0) else CFrame.new(0, -0.9, 0)
	-- Point the blade forward out of the fist.
	knife:PivotTo(hand.CFrame * grip * CFrame.Angles(math.rad(-90), 0, 0) * CFrame.new(0, -0.3, 0))
	local w = Instance.new("Weld")
	w.Name = "KnifeGrip"
	w.Part0 = hand
	w.Part1 = handle
	w.C0 = hand.CFrame:ToObjectSpace(handle.CFrame)
	w.Parent = handle
	knife.Parent = model
end

function Roster.RefreshKnife(entry: Entry)
	if entry.Role == "Chaser" then
		giveKnife(entry)
	end
end

function Roster.SetKnifeBig(entry: Entry, big: boolean)
	local model = entry.Model
	local knife = model and model:FindFirstChild("BA_Knife")
	if not knife or not knife:IsA("Model") then
		return
	end
	if knife:GetAttribute("Big") ~= big then
		shapeBlade(knife, big)
	end
end

---------------------------------------------------------------------------
-- Name tag
---------------------------------------------------------------------------
local function buildTag(entry: Entry)
	local model = entry.Model
	if not model then
		return
	end
	local head = model:FindFirstChild("Head")
	if not head or not head:IsA("BasePart") then
		return
	end
	local old = head:FindFirstChild("BA_Tag")
	if old then
		old:Destroy()
	end
	local gui = Instance.new("BillboardGui")
	gui.Name = "BA_Tag"
	gui.Size = UDim2.fromOffset(220, 64)
	gui.StudsOffset = Vector3.new(0, 2.7, 0)
	gui.MaxDistance = 140
	gui.LightInfluence = 0
	gui.ResetOnSpawn = false
	gui.Parent = head

	local name = Instance.new("TextLabel")
	name.Name = "NameLabel"
	name.BackgroundTransparency = 1
	name.Size = UDim2.new(1, 0, 0, 26)
	name.Position = UDim2.fromOffset(0, 18)
	name.Font = Enum.Font.FredokaOne
	name.TextSize = 22
	name.TextColor3 = ROLE_TAG_COLOR.Lobby
	name.Text = entry.Name
	name.Parent = gui
	local s1 = Instance.new("UIStroke")
	s1.Thickness = 2
	s1.Parent = name

	local title = Instance.new("TextLabel")
	title.Name = "TitleLabel"
	title.BackgroundTransparency = 1
	title.Size = UDim2.new(1, 0, 0, 18)
	title.Position = UDim2.fromOffset(0, 0)
	title.Font = Enum.Font.GothamBold
	title.TextSize = 15
	title.Parent = gui
	local s2 = Instance.new("UIStroke")
	s2.Thickness = 1.5
	s2.Parent = title

	-- Bleed-out bar, driven locally on each client from DownedUntil.
	local bar = Instance.new("Frame")
	bar.Name = "BleedBar"
	bar.Size = UDim2.new(0.5, 0, 0, 7)
	bar.Position = UDim2.new(0.25, 0, 0, 47)
	bar.BackgroundColor3 = Color3.fromRGB(30, 30, 30)
	bar.BorderSizePixel = 0
	bar.Visible = false
	bar.Parent = gui
	local fill = Instance.new("Frame")
	fill.Name = "Fill"
	fill.Size = UDim2.fromScale(1, 1)
	fill.BackgroundColor3 = Color3.fromRGB(255, 70, 70)
	fill.BorderSizePixel = 0
	fill.Parent = bar
	Roster.RefreshTag(entry)
end

function Roster.RefreshTag(entry: Entry)
	local model = entry.Model
	local head = model and model:FindFirstChild("Head")
	local gui = head and head:FindFirstChild("BA_Tag")
	if not gui then
		return
	end
	local loadout = Roster.Loadout(entry)
	local t = Catalog.Titles[loadout.Title] or Catalog.Titles.Rookie
	local level = if entry.Player then (entry.Player:GetAttribute("Level") :: number?) or 1 else 1
	local titleLabel = gui:FindFirstChild("TitleLabel") :: TextLabel
	titleLabel.Text = ("%s  •  Lv %d"):format(t.Name, level)
	titleLabel.TextColor3 = t.Color
	local nameLabel = gui:FindFirstChild("NameLabel") :: TextLabel
	nameLabel.TextColor3 = ROLE_TAG_COLOR[entry.Role] or ROLE_TAG_COLOR.Lobby
	local bar = gui:FindFirstChild("BleedBar") :: Frame
	bar.Visible = entry.Role == "Downed"
end

---------------------------------------------------------------------------
-- Highlight and cloak
---------------------------------------------------------------------------
local function setHighlight(model: Model, role: string)
	local existing = model:FindFirstChild("BA_Highlight") :: Highlight?
	if role ~= "Chaser" and role ~= "Downed" then
		if existing then
			existing:Destroy()
		end
		return
	end
	local hl: Highlight
	if existing then
		hl = existing
	else
		hl = Instance.new("Highlight")
		hl.Name = "BA_Highlight"
		hl.DepthMode = Enum.HighlightDepthMode.Occluded
		hl.Parent = model
	end
	if role == "Chaser" then
		hl.FillColor = Color3.fromRGB(255, 40, 40)
		hl.OutlineColor = Color3.fromRGB(255, 70, 70)
		hl.FillTransparency = 0.78
		hl.OutlineTransparency = 0.1
	else
		hl.FillColor = Color3.fromRGB(120, 120, 120)
		hl.OutlineColor = Color3.fromRGB(220, 220, 220)
		hl.FillTransparency = 0.55
		hl.OutlineTransparency = 0.4
	end
end

function Roster.SetCloak(entry: Entry, on: boolean)
	local model = entry.Model
	if not model then
		return
	end
	if (model:GetAttribute("Cloaked") == true) == on then
		return
	end
	model:SetAttribute("Cloaked", on)
	for _, d in model:GetDescendants() do
		if d:IsA("BasePart") or d:IsA("Decal") then
			local v = d :: any
			if on then
				v:SetAttribute("BA_OrigT", v.Transparency)
				v.Transparency = 1
			else
				local orig = v:GetAttribute("BA_OrigT")
				if type(orig) == "number" then
					v.Transparency = orig
					v:SetAttribute("BA_OrigT", nil)
				end
			end
		elseif d:IsA("BillboardGui") and d.Name == "BA_Tag" then
			d.Enabled = not on
		end
	end
	if not on then
		entry.CloakUntil = 0
	end
end

---------------------------------------------------------------------------
-- Roles
---------------------------------------------------------------------------
local function groupFor(entry: Entry, role: string): string
	if role == "Chaser" then
		return Groups.Chasers
	elseif role == "Runner" or role == "Downed" then
		return if entry.IsHero then Groups.Hero else Groups.Runners
	end
	return Groups.Lobby
end

function Roster.SetRole(entry: Entry, role: string)
	local previous = entry.Role
	entry.Role = role
	if entry.Player then
		entry.Player:SetAttribute("Role", role)
	end
	local model = entry.Model
	if not model then
		return
	end
	model:SetAttribute("Role", role)
	Groups.SetModel(model, groupFor(entry, role))
	setHighlight(model, role)
	if role == "Chaser" then
		if previous ~= "Chaser" or not model:FindFirstChild("BA_Knife") then
			giveKnife(entry)
		end
	else
		removeKnife(model)
	end
	if role ~= "Runner" and model:GetAttribute("Cloaked") then
		Roster.SetCloak(entry, false)
	end
	if role == "Downed" then
		model:SetAttribute("DownedUntil", workspace:GetServerTimeNow() + Config.Match.BleedOutTime)
	else
		model:SetAttribute("DownedUntil", nil)
	end
	Roster.RefreshTag(entry)
end

-- Re-apply the collision group (used when a runner starts or ends a Hero run).
function Roster.RefreshGroup(entry: Entry)
	if entry.Model then
		Groups.SetModel(entry.Model, groupFor(entry, entry.Role))
	end
end

function Roster.Place(entry: Entry, cf: CFrame)
	local model = entry.Model
	if model and model.Parent then
		model:PivotTo(cf)
		local root = Roster.Root(entry)
		if root then
			root.AssemblyLinearVelocity = Vector3.zero
		end
	end
end

function Roster.BeginMatch(entry: Entry)
	entry.InMatch = true
	entry.IsHero = false
	entry.Chicken = false
	entry.OriginalChaser = false
	entry.LastSwing = -math.huge
	entry.LastJuke = -math.huge
	entry.ShieldUntil = 0
	entry.ProtectedUntil = 0
	entry.CloakUntil = 0
	entry.BigDaggerUntil = 0
	entry.GraceUntil = 0
	entry.DownedAt = 0
	entry.DownedBy = nil
	entry.AbilityReady = {}
	entry.ItemReadyAt = 0
	entry.Crossings = 0
	entry.Catches = 0
	entry.Ankles = 0
	entry.Rescues = 0
	entry.Earned = { Gems = 0, Coins = 0, XP = 0, Lines = {} }
	if entry.Player then
		entry.Player:SetAttribute("AbilityReadyAt", 0)
		entry.Player:SetAttribute("ItemReadyAt", 0)
	end
	if entry.Model then
		Status.Clear(entry)
	end
end

function Roster.EndMatch(entry: Entry)
	entry.InMatch = false
	entry.IsHero = false
	if entry.Model then
		Roster.SetCloak(entry, false)
		Status.Clear(entry)
		local prompt = entry.Model:FindFirstChild("RevivePrompt", true)
		if prompt then
			prompt:Destroy()
		end
	end
	Roster.SetRole(entry, "Lobby")
end

---------------------------------------------------------------------------
-- Characters
---------------------------------------------------------------------------
local onCharacter: ((Entry) -> ())? = nil

-- Match.luau hooks this to put respawned participants back in the arena.
function Roster.OnCharacter(fn: (Entry) -> ())
	onCharacter = fn
end

function Roster.SetupModel(entry: Entry, model: Model)
	if entry.Model and byModel[entry.Model] == entry then
		byModel[entry.Model] = nil
	end
	entry.Model = model
	byModel[model] = entry
	CollectionService:AddTag(model, "BA_Character")
	local hum = model:FindFirstChildOfClass("Humanoid") or model:WaitForChild("Humanoid", 10)
	if hum and hum:IsA("Humanoid") then
		hum.DisplayDistanceType = Enum.HumanoidDisplayDistanceType.None
		hum.HealthDisplayType = Enum.HumanoidHealthDisplayType.AlwaysOff
		hum.BreakJointsOnDeath = false
		hum.MaxHealth = 1e6
		hum.Health = 1e6
		hum.UseJumpPower = true
		hum.JumpPower = 0
	end
	Groups.Track(model)
	model:WaitForChild("Head", 5)
	buildTag(entry)
	Roster.SetRole(entry, entry.Role)
	model.Destroying:Connect(function()
		if byModel[model] == entry then
			byModel[model] = nil
		end
	end)
	if onCharacter then
		task.spawn(onCharacter :: (Entry) -> (), entry)
	end
end

function Roster.AddBot(name: string, model: Model, loadout: any): Entry
	local id = nextBotId
	nextBotId -= 1
	local entry = newEntry(id, name, true, nil)
	entry.BotLoadout = loadout
	entries[id] = entry
	Roster.SetupModel(entry, model)
	return entry
end

function Roster.Remove(entry: Entry)
	entries[entry.Id] = nil
	if entry.Model then
		byModel[entry.Model] = nil
	end
	entry.InMatch = false
end

function Roster.Start()
	local function added(player: Player)
		local entry = newEntry(player.UserId, player.DisplayName, false, player)
		entries[player.UserId] = entry
		player:SetAttribute("Role", "Lobby")
		player.CharacterAdded:Connect(function(character)
			Roster.SetupModel(entry, character)
		end)
		if player.Character then
			task.spawn(Roster.SetupModel, entry, player.Character)
		end
		-- Title or level changes update the name tag.
		player:GetAttributeChangedSignal("Title"):Connect(function()
			Roster.RefreshTag(entry)
		end)
		player:GetAttributeChangedSignal("Level"):Connect(function()
			Roster.RefreshTag(entry)
		end)
	end
	Players.PlayerAdded:Connect(added)
	for _, p in Players:GetPlayers() do
		added(p)
	end
	Players.PlayerRemoving:Connect(function(player)
		local e = entries[player.UserId]
		if e then
			Roster.Remove(e)
		end
	end)
end

return Roster
