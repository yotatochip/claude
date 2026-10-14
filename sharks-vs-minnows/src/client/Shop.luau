--!strict
-- Shop (abilities, consumables, trails) and the codes window.

local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local TweenService = game:GetService("TweenService")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent.Ui)
local Fx = require(script.Parent.Fx)
local Hud = require(script.Parent.Hud)

local make = Ui.make
local T = Ui.Theme
local player = Players.LocalPlayer

local Shop = {}

local function window(name: string, size: Vector2, title: string): (Frame, Frame)
	local frame = make("Frame", {
		Name = name, AnchorPoint = Vector2.new(0.5, 0.5), Position = UDim2.fromScale(0.5, 0.52), Size = UDim2.fromOffset(size.X, size.Y),
		BackgroundColor3 = T.Panel, Visible = false, ZIndex = 10, Parent = Hud.Gui,
	}, {
		Ui.corner(18), Ui.stroke(4), Ui.gradient(Color3.fromRGB(255, 255, 255), Color3.fromRGB(170, 190, 210)),
		make("UISizeConstraint", { MaxSize = Vector2.new(size.X, size.Y) }),
	})
	Ui.label({ Position = UDim2.fromOffset(20, 10), Size = UDim2.new(1, -90, 0, 40), Text = title, TextXAlignment = Enum.TextXAlignment.Left, ZIndex = 11, StrokeThickness = 3, Parent = frame })
	local close = Ui.button({ AnchorPoint = Vector2.new(1, 0), Position = UDim2.new(1, -12, 0, 10), Size = UDim2.fromOffset(42, 42), Text = "X", ZIndex = 11, Parent = frame }, T.Bad)
	close.Activated:Connect(function()
		Fx.Sound("Click")
		frame.Visible = false
	end)
	local body = make("Frame", { Name = "Body", Position = UDim2.fromOffset(16, 62), Size = UDim2.new(1, -32, 1, -78), BackgroundTransparency = 1, ZIndex = 11, Parent = frame })
	return frame, body
end

local function pop(frame: GuiObject)
	local final = frame.Size
	frame.Size = UDim2.new(final.X.Scale * 0.9, final.X.Offset * 0.9, final.Y.Scale * 0.9, final.Y.Offset * 0.9)
	TweenService:Create(frame, TweenInfo.new(0.25, Enum.EasingStyle.Back), { Size = final }):Play()
end

-- Shop ------------------------------------------------------------------------------------------------

local shopFrame, shopBody = window("Shop", Vector2.new(660, 460), "🛒 SHOP")
local tabs = make("Frame", { Size = UDim2.new(1, 0, 0, 40), BackgroundTransparency = 1, ZIndex = 11, Parent = shopBody }, {
	make("UIListLayout", { FillDirection = Enum.FillDirection.Horizontal, Padding = UDim.new(0, 8), SortOrder = Enum.SortOrder.LayoutOrder }),
})
local list = make("ScrollingFrame", {
	Position = UDim2.fromOffset(0, 50), Size = UDim2.new(1, 0, 1, -50), BackgroundTransparency = 1, BorderSizePixel = 0,
	ScrollBarThickness = 8, AutomaticCanvasSize = Enum.AutomaticSize.Y, CanvasSize = UDim2.new(), ZIndex = 11, Parent = shopBody,
}, {
	make("UIGridLayout", { CellSize = UDim2.fromOffset(195, 200), CellPadding = UDim2.fromOffset(10, 10), SortOrder = Enum.SortOrder.LayoutOrder }),
	make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingLeft = UDim.new(0, 4), PaddingRight = UDim.new(0, 4) }),
})

local currentTab = "Abilities"
local tabButtons: { [string]: TextButton } = {}

local function buy(action: string, id: string)
	Fx.Sound("Click")
	local ok, message = Remotes.Shop:InvokeServer(action, id)
	Hud.Toast(message, if ok then T.Good else T.Bad)
end

type CardInfo = { Icon: string, Name: string, Tag: string?, TagColor: Color3?, Desc: string, Color: Color3, ButtonText: string, ButtonColor: Color3, Enabled: boolean, OnClick: () -> () }

local function card(order: number, info: CardInfo)
	local c = make("Frame", { LayoutOrder = order, BackgroundColor3 = info.Color:Lerp(T.Panel, 0.65), ZIndex = 12, Parent = list }, { Ui.corner(14), Ui.stroke(2.5) })
	Ui.label({ Position = UDim2.fromOffset(8, 8), Size = UDim2.new(1, -16, 0, 44), Text = info.Icon, ZIndex = 13, Parent = c })
	Ui.label({ Position = UDim2.fromOffset(8, 54), Size = UDim2.new(1, -16, 0, 24), Text = info.Name, ZIndex = 13, Parent = c })
	if info.Tag then
		local tag = make("Frame", { Position = UDim2.fromOffset(8, 8), Size = UDim2.fromOffset(66, 20), BackgroundColor3 = info.TagColor or T.Accent, ZIndex = 14, Parent = c }, { Ui.corner(6) })
		Ui.label({ Size = UDim2.fromScale(1, 1), Text = info.Tag, ZIndex = 15, StrokeThickness = 1, Parent = tag })
	end
	make("TextLabel", {
		Position = UDim2.fromOffset(10, 80), Size = UDim2.new(1, -20, 0, 56), BackgroundTransparency = 1, Font = Ui.BodyFont, TextSize = 14,
		TextWrapped = true, TextColor3 = T.Muted, Text = info.Desc, TextYAlignment = Enum.TextYAlignment.Top, ZIndex = 13, Parent = c,
	})
	local b = Ui.button({
		AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, -10), Size = UDim2.new(1, -20, 0, 42),
		Text = info.ButtonText, ZIndex = 13, AutoButtonColor = info.Enabled, Parent = c,
	}, info.ButtonColor)
	if info.Enabled then
		b.Activated:Connect(info.OnClick)
	end
end

local function refresh()
	for _, c in list:GetChildren() do
		if c:IsA("Frame") then
			c:Destroy()
		end
	end
	for name, b in tabButtons do
		b.BackgroundColor3 = if name == currentTab then Color3.fromRGB(255, 170, 40) else T.PanelLight
	end
	local coins = player:GetAttribute("Coins") or 0
	local gems = player:GetAttribute("Gems") or 0

	if currentTab == "Abilities" then
		for i, id in Config.AbilityOrder do
			local def = Config.Abilities[id]
			local owned = player:GetAttribute("Owns_" .. id) == true
			local equipped = player:GetAttribute("Equipped" .. def.Role) == id
			local text, color, enabled, action
			if equipped then
				text, color, enabled, action = "EQUIPPED", T.Good, false, ""
			elseif owned then
				text, color, enabled, action = "EQUIP", T.Accent, true, "EquipAbility"
			else
				text, color, enabled, action = `🪙 {def.Price}`, if coins >= def.Price then Color3.fromRGB(255, 190, 40) else Color3.fromRGB(110, 110, 120), true, "BuyAbility"
			end
			card(i, {
				Icon = def.Icon, Name = def.Name, Tag = string.upper(def.Role), TagColor = if def.Role == "Shark" then Color3.fromRGB(190, 50, 60) else Color3.fromRGB(230, 130, 30),
				Desc = `{def.Description}\nCooldown {def.Cooldown}s`, Color = def.Color, ButtonText = text, ButtonColor = color, Enabled = enabled,
				OnClick = function()
					buy(action, id)
				end,
			})
		end
	elseif currentTab == "Items" then
		for i, id in Config.ItemOrder do
			local def = Config.Items[id]
			local have = player:GetAttribute("Item_" .. id) or 0
			card(i, {
				Icon = def.Icon, Name = `{def.Name}  (x{have})`, Tag = if def.Role == "Any" then "ANYONE" else string.upper(def.Role),
				TagColor = if def.Role == "Shark" then Color3.fromRGB(190, 50, 60) elseif def.Role == "Minnow" then Color3.fromRGB(230, 130, 30) else Color3.fromRGB(70, 150, 90),
				Desc = `{def.Description}\nPress {def.Key} to use.`, Color = def.Color,
				ButtonText = `BUY 🪙 {def.Price}`, ButtonColor = if coins >= def.Price then Color3.fromRGB(255, 190, 40) else Color3.fromRGB(110, 110, 120), Enabled = true,
				OnClick = function()
					buy("BuyItem", id)
				end,
			})
		end
	else
		for i, id in Config.TrailOrder do
			local def = Config.Trails[id]
			local owned = player:GetAttribute("OwnsTrail_" .. id) == true
			local equipped = player:GetAttribute("Trail") == id
			local text, color, action, arg
			if equipped then
				text, color, action, arg = "UNEQUIP", Color3.fromRGB(140, 140, 150), "EquipTrail", ""
			elseif owned then
				text, color, action, arg = "EQUIP", T.Accent, "EquipTrail", id
			else
				text, color, action, arg = `💎 {def.Price}`, if gems >= def.Price then Config.Colors.Gems else Color3.fromRGB(110, 110, 120), "BuyTrail", id
			end
			card(i, {
				Icon = "✨", Name = def.Name, Desc = "A trail that follows you everywhere. Bought with gems from wins.",
				Color = def.Colors[1], ButtonText = text, ButtonColor = color, Enabled = true,
				OnClick = function()
					buy(action, arg)
				end,
			})
		end
	end
end

for i, name in { "Abilities", "Items", "Trails" } do
	local b = Ui.button({ LayoutOrder = i, Size = UDim2.fromOffset(150, 38), Text = name:upper(), ZIndex = 12, Parent = tabs }, T.PanelLight)
	tabButtons[name] = b
	b.Activated:Connect(function()
		Fx.Sound("Click")
		currentTab = name
		refresh()
	end)
end

player.AttributeChanged:Connect(function(attr)
	if shopFrame.Visible and attr ~= "AbilityReadyAt" and attr ~= "ItemReadyAt" and attr ~= "ShieldUntil" then
		refresh()
	end
end)

-- Codes ---------------------------------------------------------------------------------------------

local codesFrame, codesBody = window("Codes", Vector2.new(400, 230), "🎁 CODES")
local box = make("TextBox", {
	Size = UDim2.new(1, 0, 0, 50), BackgroundColor3 = Color3.fromRGB(240, 245, 250), Font = Ui.Font, TextScaled = true,
	PlaceholderText = "Enter code", Text = "", TextColor3 = T.Stroke, ClearTextOnFocus = false, ZIndex = 12, Parent = codesBody,
}, { Ui.corner(10), Ui.stroke(2.5), Ui.padding(8) })
local result = Ui.label({ Position = UDim2.fromOffset(0, 58), Size = UDim2.new(1, 0, 0, 24), Text = "Codes drop with updates. Try SHARKBAIT!", Font = Ui.BodyFont, TextColor3 = T.Muted, StrokeThickness = 1, ZIndex = 12, Parent = codesBody })
local redeem = Ui.button({ AnchorPoint = Vector2.new(0.5, 1), Position = UDim2.new(0.5, 0, 1, 0), Size = UDim2.fromOffset(200, 46), Text = "REDEEM", ZIndex = 12, Parent = codesBody }, T.Good)
redeem.Activated:Connect(function()
	Fx.Sound("Click")
	local ok, message = Remotes.RedeemCode:InvokeServer(box.Text)
	result.Text = message
	result.TextColor3 = if ok then T.Good else T.Bad
	if ok then
		box.Text = ""
		Hud.Toast("🎁 " .. message, T.Good)
	end
end)

-- Public ----------------------------------------------------------------------------------------------

function Shop.ToggleShop()
	Fx.Sound("Click")
	codesFrame.Visible = false
	shopFrame.Visible = not shopFrame.Visible
	if shopFrame.Visible then
		refresh()
		pop(shopFrame)
	end
end

function Shop.ToggleCodes()
	Fx.Sound("Click")
	shopFrame.Visible = false
	codesFrame.Visible = not codesFrame.Visible
	if codesFrame.Visible then
		pop(codesFrame)
	end
end

function Shop.CloseAll()
	shopFrame.Visible = false
	codesFrame.Visible = false
end

return Shop
