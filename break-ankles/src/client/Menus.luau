--!strict
-- Lobby menus: the shop (abilities, items, knives, titles), codes, and the
-- AFK toggle.

local Players = game:GetService("Players")
local ProximityPromptService = game:GetService("ProximityPromptService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Catalog = require(Shared.Catalog)
local Net = require(Shared.Net)
local HUD = require(script.Parent.HUD)
local Sounds = require(script.Parent.Sounds)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer
local ShopRemote = Net.Function("Shop")
local C = UI.Colors

local Menus = {}

local gui: ScreenGui
local shopWindow: Frame
local codesWindow: Frame
local grid: ScrollingFrame
local tabButtons: { [string]: TextButton } = {}
local currentTab = "Runner"
local message: TextLabel

local function invoke(action: string, a: any?, b: any?): any
	local ok, result = pcall(function()
		return ShopRemote:InvokeServer(action, a, b)
	end)
	if not ok or type(result) ~= "table" then
		return { Ok = false, Message = "Couldn't reach the server" }
	end
	return result
end

local function flash(text: string, good: boolean)
	message.Text = text
	message.TextColor3 = if good then C.Good else C.Bad
	message.TextTransparency = 0
	UI.pop(message, 0.8)
	Sounds.Play(if good then "Gem" else "Click", if good then 1.2 else 0.8)
end

---------------------------------------------------------------------------
-- Shop cards
---------------------------------------------------------------------------
local function card(order: number, title: string, desc: string, accent: Color3): (Frame, Frame)
	local f = UI.panel({ Size = UDim2.fromOffset(250, 170), Color = C.Panel2, LayoutOrder = order, Parent = grid })
	UI.new("Frame", {
		BackgroundColor3 = accent,
		Size = UDim2.new(1, 0, 0, 6),
		BorderSizePixel = 0,
		Parent = f,
	}, { UI.corner(3) })
	UI.text({ Text = title, TextSize = 21, Size = UDim2.new(1, -20, 0, 26), Position = UDim2.fromOffset(10, 12), TextXAlignment = Enum.TextXAlignment.Left, Parent = f })
	UI.text({
		Text = desc,
		Font = UI.Body,
		TextSize = 13,
		TextColor3 = C.Muted,
		TextWrapped = true,
		TextXAlignment = Enum.TextXAlignment.Left,
		TextYAlignment = Enum.TextYAlignment.Top,
		Size = UDim2.new(1, -20, 0, 70),
		Position = UDim2.fromOffset(10, 42),
		StrokeThickness = 1,
		Parent = f,
	})
	local footer = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.new(0, 10, 1, -48),
		Size = UDim2.new(1, -20, 0, 40),
		Parent = f,
	})
	return f, footer
end

local function priceLabel(text: string, color: Color3, parent: Instance)
	UI.text({ Text = text, TextSize = 18, TextColor3 = color, Size = UDim2.new(0.5, 0, 1, 0), TextXAlignment = Enum.TextXAlignment.Left, Parent = parent })
end

local function actionButton(text: string, color: Color3, parent: Instance, fn: () -> ())
	UI.button({ Text = text, TextSize = 17, Size = UDim2.new(0.5, 0, 1, 0), Position = UDim2.fromScale(0.5, 0), Color = color, Parent = parent }, fn)
end

local function refreshShop()
	if not shopWindow or not shopWindow.Visible then
		return
	end
	for _, c in grid:GetChildren() do
		if c:IsA("GuiObject") then
			c:Destroy()
		end
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == currentTab then C.Accent else Color3.fromRGB(70, 74, 88)
	end
	local p = HUD.Profile
	if not p then
		return
	end
	local function act(action: string, id: string)
		task.spawn(function()
			local result = invoke(action, id)
			flash(result.Message, result.Ok)
		end)
	end
	if currentTab == "Runner" or currentTab == "Chaser" then
		for i, def in Catalog.Sorted(Catalog.Abilities, function(a)
			return a.Role == currentTab
		end) do
			local owned = p.OwnedAbilities[def.Id]
			local equipped = p.Equipped[def.Role] == def.Id
			local _, footer = card(i, def.Name, def.Description .. ("\nCooldown %ds"):format(def.Cooldown), def.Color)
			if owned then
				priceLabel("Owned", C.Good, footer)
			else
				priceLabel(("💎 %s"):format(UI.formatNumber(def.Price)), C.Gem, footer)
			end
			if equipped then
				actionButton("EQUIPPED", Color3.fromRGB(70, 74, 88), footer, function() end)
			elseif owned then
				actionButton("EQUIP", C.Blue, footer, function()
					act("EquipAbility", def.Id)
				end)
			else
				actionButton("BUY", if p.Gems >= def.Price then C.Good else Color3.fromRGB(110, 110, 120), footer, function()
					act("BuyAbility", def.Id)
				end)
			end
		end
	elseif currentTab == "Items" then
		for i, def in Catalog.Sorted(Catalog.Items) do
			local count = p.Items[def.Id] or 0
			local roles = {}
			for r in def.Roles do
				table.insert(roles, r)
			end
			table.sort(roles)
			local desc = def.Description .. ("\n%d per pack • %s • You have %d"):format(def.Charges, table.concat(roles, "/"), count)
			local f, footer = card(i, def.Name, desc, def.Color)
			priceLabel(("🪙 %d"):format(def.Price), C.Coin, footer)
			actionButton("BUY", if p.Coins >= def.Price then C.Good else Color3.fromRGB(110, 110, 120), footer, function()
				act("BuyItem", def.Id)
			end)
			if count > 0 then
				local equipped = p.Equipped.Item == def.Id
				UI.button({
					Text = if equipped then "EQUIPPED" else "EQUIP",
					TextSize = 14,
					Size = UDim2.fromOffset(90, 26),
					Position = UDim2.new(1, -100, 0, 12),
					Color = if equipped then Color3.fromRGB(70, 74, 88) else C.Blue,
					Parent = f,
				}, function()
					if not equipped then
						act("EquipItem", def.Id)
					end
				end)
			end
		end
	elseif currentTab == "Knives" then
		for i, def in Catalog.Sorted(Catalog.Knives) do
			local owned = p.OwnedKnives[def.Id]
			local equipped = p.Equipped.Knife == def.Id
			local _, footer = card(i, def.Name .. " Knife", "A cosmetic blade for when you're chasing.", def.Blade)
			if owned then
				priceLabel("Owned", C.Good, footer)
			else
				priceLabel(("💎 %s"):format(UI.formatNumber(def.Price)), C.Gem, footer)
			end
			if equipped then
				actionButton("EQUIPPED", Color3.fromRGB(70, 74, 88), footer, function() end)
			elseif owned then
				actionButton("EQUIP", C.Blue, footer, function()
					act("EquipKnife", def.Id)
				end)
			else
				actionButton("BUY", if p.Gems >= def.Price then C.Good else Color3.fromRGB(110, 110, 120), footer, function()
					act("BuyKnife", def.Id)
				end)
			end
		end
	elseif currentTab == "Titles" then
		for i, def in Catalog.Sorted(Catalog.Titles) do
			local owned = p.OwnedTitles[def.Id]
			local equipped = p.Equipped.Title == def.Id
			local _, footer = card(i, def.Name, def.Hint, def.Color)
			priceLabel(if owned then "Unlocked" else "Locked", if owned then C.Good else C.Muted, footer)
			if equipped then
				actionButton("EQUIPPED", Color3.fromRGB(70, 74, 88), footer, function() end)
			elseif owned then
				actionButton("EQUIP", C.Blue, footer, function()
					act("EquipTitle", def.Id)
				end)
			end
		end
	end
end

local function buildShop()
	shopWindow = UI.panel({
		Name = "Shop",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.53),
		Size = UDim2.fromScale(0.94, 0.82),
		Visible = false,
		Parent = gui,
	})
	UI.new("UISizeConstraint", { MaxSize = Vector2.new(860, 520), Parent = shopWindow })
	UI.text({ Text = "SHOP", TextSize = 34, Size = UDim2.fromOffset(200, 40), Position = UDim2.fromOffset(20, 10), TextXAlignment = Enum.TextXAlignment.Left, Parent = shopWindow })
	UI.button({ Text = "X", TextSize = 20, Size = UDim2.fromOffset(40, 40), Position = UDim2.new(1, -52, 0, 12), Color = C.Bad, Parent = shopWindow }, function()
		shopWindow.Visible = false
		Sounds.Play("Click")
	end)
	message = UI.text({ Text = "", Font = UI.Body, TextSize = 16, Size = UDim2.new(1, -320, 0, 24), Position = UDim2.fromOffset(160, 18), Parent = shopWindow })
	local tabs = UI.new("Frame", {
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(20, 58),
		Size = UDim2.new(1, -40, 0, 38),
		Parent = shopWindow,
	}, { UI.list(Enum.FillDirection.Horizontal, 8) })
	local tabNames = { { "Runner", "Runner Abilities" }, { "Chaser", "Chaser Abilities" }, { "Items", "Items" }, { "Knives", "Knives" }, { "Titles", "Titles" } }
	for i, t in tabNames do
		local id, label = t[1], t[2]
		tabButtons[id] = UI.button({ Text = label, TextSize = 16, Size = UDim2.fromOffset(152, 36), LayoutOrder = i, Color = Color3.fromRGB(70, 74, 88), Parent = tabs }, function()
			currentTab = id
			Sounds.Play("Click")
			refreshShop()
		end)
	end
	grid = UI.new("ScrollingFrame", {
		BackgroundTransparency = 1,
		BorderSizePixel = 0,
		Position = UDim2.fromOffset(20, 106),
		Size = UDim2.new(1, -40, 1, -120),
		CanvasSize = UDim2.new(),
		AutomaticCanvasSize = Enum.AutomaticSize.Y,
		ScrollBarThickness = 6,
		Parent = shopWindow,
	})
	UI.new("UIGridLayout", {
		CellSize = UDim2.fromOffset(256, 176),
		CellPadding = UDim2.fromOffset(12, 12),
		SortOrder = Enum.SortOrder.LayoutOrder,
		Parent = grid,
	})
	UI.new("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), Parent = grid })
end

---------------------------------------------------------------------------
-- Codes
---------------------------------------------------------------------------
local function buildCodes()
	codesWindow = UI.panel({
		Name = "Codes",
		AnchorPoint = Vector2.new(0.5, 0.5),
		Position = UDim2.fromScale(0.5, 0.5),
		Size = UDim2.fromOffset(400, 220),
		Visible = false,
		Parent = gui,
	})
	UI.text({ Text = "CODES", TextSize = 30, Size = UDim2.new(1, 0, 0, 36), Position = UDim2.fromOffset(0, 10), Parent = codesWindow })
	UI.button({ Text = "X", TextSize = 18, Size = UDim2.fromOffset(34, 34), Position = UDim2.new(1, -44, 0, 10), Color = C.Bad, Parent = codesWindow }, function()
		codesWindow.Visible = false
	end)
	local box = UI.new("TextBox", {
		PlaceholderText = "Enter code",
		Text = "",
		ClearTextOnFocus = false,
		Font = UI.Display,
		TextSize = 22,
		TextColor3 = Color3.new(0, 0, 0),
		BackgroundColor3 = Color3.new(1, 1, 1),
		Position = UDim2.fromOffset(30, 60),
		Size = UDim2.new(1, -60, 0, 46),
		Parent = codesWindow,
	}, { UI.corner(10) })
	local result = UI.text({ Text = "", Font = UI.Body, TextSize = 15, TextWrapped = true, Size = UDim2.new(1, -40, 0, 36), Position = UDim2.fromOffset(20, 112), Parent = codesWindow })
	UI.button({ Text = "REDEEM", TextSize = 22, Size = UDim2.fromOffset(180, 46), AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -14), Color = C.Good, Parent = codesWindow }, function()
		task.spawn(function()
			local r = invoke("Redeem", box.Text)
			result.Text = r.Message
			result.TextColor3 = if r.Ok then C.Good else C.Bad
			Sounds.Play(if r.Ok then "Win" else "Click")
		end)
	end)
end

---------------------------------------------------------------------------
-- Side buttons
---------------------------------------------------------------------------
function Menus.OpenShop(tab: string?)
	if tab then
		currentTab = tab
	end
	codesWindow.Visible = false
	shopWindow.Visible = true
	UI.pop(shopWindow, 0.85)
	refreshShop()
end

local function buildSide()
	local side = UI.new("Frame", {
		Name = "Side",
		BackgroundTransparency = 1,
		Position = UDim2.fromOffset(14, 204),
		Size = UDim2.fromOffset(120, 200),
		Parent = gui,
	}, { UI.list(Enum.FillDirection.Vertical, 8) })
	UI.button({ Text = "SHOP", TextSize = 22, Size = UDim2.fromOffset(120, 46), Color = C.Accent, LayoutOrder = 1, Parent = side }, function()
		Sounds.Play("Click")
		if shopWindow.Visible then
			shopWindow.Visible = false
		else
			local r = player:GetAttribute("Role")
			Menus.OpenShop(if r == "Chaser" then "Chaser" else nil)
		end
	end)
	UI.button({ Text = "CODES", TextSize = 22, Size = UDim2.fromOffset(120, 46), Color = C.Blue, LayoutOrder = 2, Parent = side }, function()
		Sounds.Play("Click")
		shopWindow.Visible = false
		codesWindow.Visible = not codesWindow.Visible
		if codesWindow.Visible then
			UI.pop(codesWindow, 0.85)
		end
	end)
	local afk: TextButton
	afk = UI.button({ Text = "AFK: OFF", TextSize = 18, Size = UDim2.fromOffset(120, 40), Color = Color3.fromRGB(90, 96, 110), LayoutOrder = 3, Parent = side }, function()
		Sounds.Play("Click")
		local want = not player:GetAttribute("AFK")
		task.spawn(function()
			invoke("SetAFK", want)
		end)
	end)
	local function refreshAfk()
		local on = player:GetAttribute("AFK") == true
		afk.Text = if on then "AFK: ON" else "AFK: OFF"
		afk.BackgroundColor3 = if on then C.Bad else Color3.fromRGB(90, 96, 110)
	end
	player:GetAttributeChangedSignal("AFK"):Connect(refreshAfk)
	refreshAfk()
end

function Menus.Start()
	gui = UI.new("ScreenGui", {
		Name = "BA_Menus",
		ResetOnSpawn = false,
		DisplayOrder = 5,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	buildShop()
	buildCodes()
	buildSide()
	Net.Event("ProfileChanged").OnClientEvent:Connect(function()
		task.defer(refreshShop)
	end)
	-- The shop stall in the lobby opens the shop.
	ProximityPromptService.PromptTriggered:Connect(function(prompt, who)
		if who == player and prompt.Name == "ShopPrompt" then
			Menus.OpenShop()
		end
	end)
end

return Menus
