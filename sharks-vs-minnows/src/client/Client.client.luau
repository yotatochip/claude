--!strict
-- Client entry point: input, remote events, spectating and UI scaling.

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local ReplicatedStorage = game:GetService("ReplicatedStorage")
local RunService = game:GetService("RunService")
local StarterGui = game:GetService("StarterGui")

local Config = require(ReplicatedStorage.Shared.Config)
local Remotes = require(ReplicatedStorage.Shared.Remotes)
local Ui = require(script.Parent:WaitForChild("Ui"))
local Fx = require(script.Parent:WaitForChild("Fx"))
local Hud = require(script.Parent:WaitForChild("Hud"))
local Shop = require(script.Parent:WaitForChild("Shop"))

local player = Players.LocalPlayer
local camera = workspace.CurrentCamera

pcall(function()
	StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
end)

-- Scale the whole HUD down on small screens (phones, small windows).
local scale = Ui.make("UIScale", { Parent = Hud.Gui })
local function rescale()
	local v = camera.ViewportSize
	scale.Scale = math.clamp(math.min(v.X / 1100, v.Y / 720), 0.55, 1)
end
camera:GetPropertyChangedSignal("ViewportSize"):Connect(rescale)
rescale()

-- Input ---------------------------------------------------------------------------------------

local function useAbility()
	Remotes.UseAbility:FireServer()
end

local function useItem(id: string)
	Remotes.UseItem:FireServer(id)
end

ContextActionService:BindAction("SvMAbility", function(_, state)
	if state == Enum.UserInputState.Begin then
		useAbility()
	end
	return Enum.ContextActionResult.Sink
end, false, Enum.KeyCode.E, Enum.KeyCode.ButtonX)

for _, id in Config.ItemOrder do
	local def = Config.Items[id]
	local key = ({ ["1"] = Enum.KeyCode.One, ["2"] = Enum.KeyCode.Two, ["3"] = Enum.KeyCode.Three })[def.Key]
	ContextActionService:BindAction("SvMItem" .. id, function(_, state)
		if state == Enum.UserInputState.Begin then
			useItem(id)
		end
		return Enum.ContextActionResult.Sink
	end, false, key)
	Hud.ItemSlots[id].Button.Activated:Connect(function()
		useItem(id)
	end)
end
Hud.AbilitySlot.Button.Activated:Connect(useAbility)

Hud.ShopButton.Activated:Connect(Shop.ToggleShop)
Hud.CodesButton.Activated:Connect(Shop.ToggleCodes)

-- Spectating -----------------------------------------------------------------------------------

local spectating = false
local specIndex = 0

local function inRoundModels(): { Model }
	local out = {}
	for _, p in Players:GetPlayers() do
		if p ~= player and p.Character and (p:GetAttribute("Role") == "Minnow" or p:GetAttribute("Role") == "Shark") then
			table.insert(out, p.Character)
		end
	end
	local bots = workspace:FindFirstChild("SvMBots")
	if bots then
		for _, m in bots:GetChildren() do
			if m:IsA("Model") and m:GetAttribute("Role") ~= "Lobby" then
				table.insert(out, m)
			end
		end
	end
	return out
end

local function stopSpectating()
	spectating = false
	Hud.SpectateButton.Text = "👀 SPECTATE"
	local h = player.Character and player.Character:FindFirstChildOfClass("Humanoid")
	if h then
		camera.CameraSubject = h
	end
end

local function nextTarget()
	local models = inRoundModels()
	if #models == 0 then
		stopSpectating()
		return
	end
	specIndex = specIndex % #models + 1
	local target = models[specIndex]
	local h = target:FindFirstChildOfClass("Humanoid")
	if h then
		camera.CameraSubject = h
		local name = if h.DisplayName ~= "" then h.DisplayName else target.Name
		Hud.SpectateButton.Text = "👀 " .. name
	end
end

Hud.SpectateButton.Activated:Connect(function()
	Fx.Sound("Click")
	-- first click starts; later clicks cycle; the last one in the list stops
	if not spectating then
		spectating = true
		specIndex = 0
		nextTarget()
	elseif specIndex >= #inRoundModels() then
		stopSpectating()
	else
		nextTarget()
	end
end)

-- Remotes ---------------------------------------------------------------------------------------

Remotes.Notify.OnClientEvent:Connect(function(text: string, color: Color3?)
	Hud.Toast(text, color)
end)

Remotes.Banner.OnClientEvent:Connect(function(title: string, subtitle: string, color: Color3?)
	Hud.Banner(title, subtitle, color)
end)

Remotes.Feed.OnClientEvent:Connect(function(killer: string, victim: string, how: string)
	Hud.Feed(killer, victim, how)
end)

Remotes.Effect.OnClientEvent:Connect(function(kind: string, data: any)
	if kind == "Burst" then
		Fx.Burst(data.Position, data.Color, data.Size)
	elseif kind == "Aura" then
		Fx.Aura(data.Model, data.Color, data.Duration)
	elseif kind == "Chomp" then
		Fx.Chomp(data.Position)
	elseif kind == "Sonar" then
		Fx.Sonar(data.Duration)
	elseif kind == "Inked" then
		Fx.Inked(data.Duration)
		Hud.Toast("🦑 Inked! You can't see!", Color3.fromRGB(190, 140, 255))
	elseif kind == "Go" then
		Fx.Sound("Go")
		Hud.Banner("GO!", "", Color3.fromRGB(120, 255, 160))
	end
end)

-- Close menus when a crossing starts so nobody is stuck behind a window.
ReplicatedStorage:GetAttributeChangedSignal("Phase"):Connect(function()
	local phase = ReplicatedStorage:GetAttribute("Phase")
	local role = player:GetAttribute("Role")
	if phase == "Ready" and role ~= "Lobby" then
		Shop.CloseAll()
	end
	if phase ~= "Ready" and phase ~= "Crossing" and spectating then
		stopSpectating()
	end
end)

player:GetAttributeChangedSignal("Role"):Connect(function()
	if player:GetAttribute("Role") ~= "Lobby" and spectating then
		stopSpectating()
	end
end)

RunService.RenderStepped:Connect(function()
	Hud.Update()
	local phase = ReplicatedStorage:GetAttribute("Phase")
	Hud.SpectateButton.Visible = player:GetAttribute("Role") == "Lobby" and (phase == "Ready" or phase == "Crossing")
end)
