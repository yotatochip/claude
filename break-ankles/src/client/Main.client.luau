--!strict
-- Break Ankles client entry point.

local Players = game:GetService("Players")
local StarterGui = game:GetService("StarterGui")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Net = require(Shared.Net)

local Effects = require(script.Parent.Effects)
local HUD = require(script.Parent.HUD)
local Input = require(script.Parent.Input)
local Menus = require(script.Parent.Menus)
local Movement = require(script.Parent.Movement)
local Sounds = require(script.Parent.Sounds)

local player = Players.LocalPlayer
local State = Net.State()

-- Hide the bits of the default UI this game doesn't use, and turn off the
-- reset button (resetting would let you dodge a catch).
local function core()
	pcall(function()
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Backpack, false)
		StarterGui:SetCoreGuiEnabled(Enum.CoreGuiType.Health, false)
	end)
	for _ = 1, 20 do
		local ok = pcall(function()
			StarterGui:SetCore("ResetButtonCallback", false)
		end)
		if ok then
			break
		end
		task.wait(0.5)
	end
end
task.spawn(core)

Movement.Start()
Input.Start()
Effects.Start()
HUD.Start()
Menus.Start()

Movement.OnDash = function()
	Sounds.Play("Dash", 1.1)
	Effects.LocalDash()
end
Movement.OnStop = function()
	Sounds.Play("Stop", 1.3)
end
Input.OnSwing = function()
	Effects.LocalSwing()
end

-- Server impulses aimed at this character.
Net.Event("Knock").OnClientEvent:Connect(function(k)
	if k.Kind == "Impulse" then
		Movement.Impulse(k.Velocity, k.Lock or 0.3)
	elseif k.Kind == "Rocket" then
		Movement.Rocket()
	end
end)

-- Music follows the match phase.
local function music()
	local phase = State:GetAttribute("Phase")
	local role = player:GetAttribute("Role")
	if role ~= "Lobby" and (phase == "Crossing" or phase == "HeroRun" or phase == "Countdown") then
		Sounds.Music("Chase")
	else
		Sounds.Music("Lobby")
	end
end
State:GetAttributeChangedSignal("Phase"):Connect(music)
player:GetAttributeChangedSignal("Role"):Connect(music)
music()
