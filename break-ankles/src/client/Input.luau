--!strict
-- Key, gamepad and touch bindings.
--
--   Space + A/D  dash        (gamepad A + stick)
--   Alt          stop        (gamepad B)
--   Q            ability     (gamepad Y)
--   F            item        (gamepad R1)
--   Click        swing       (gamepad R2)
--   E            revive      (prompt; gamepad X)

local ContextActionService = game:GetService("ContextActionService")
local Players = game:GetService("Players")
local UserInputService = game:GetService("UserInputService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local Movement = require(script.Parent.Movement)
local UI = require(script.Parent.UI)

local player = Players.LocalPlayer

local Input = {}

Input.OnSwing = nil :: (() -> ())?

local SwingRemote = Net.Event("Swing")
local AbilityRemote = Net.Event("UseAbility")
local ItemRemote = Net.Event("UseItem")

local lastSwing = -math.huge

local function role(): string
	return (player:GetAttribute("Role") :: string?) or "Lobby"
end

function Input.Swing()
	if role() ~= "Chaser" then
		return
	end
	local now = os.clock()
	if now - lastSwing < Config.Knife.Cooldown then
		return
	end
	local char = player.Character
	local stun = char and char:GetAttribute("StunUntil")
	if type(stun) == "number" and workspace:GetServerTimeNow() < stun then
		return
	end
	lastSwing = now
	SwingRemote:FireServer()
	Movement.Lunge()
	if Input.OnSwing then
		(Input.OnSwing :: () -> ())()
	end
end

function Input.SwingReadyFraction(): number
	return math.clamp((os.clock() - lastSwing) / Config.Knife.Cooldown, 0, 1)
end

function Input.Ability()
	AbilityRemote:FireServer()
end

function Input.Item()
	ItemRemote:FireServer()
end

local function bind(name: string, fn: () -> (), ...: Enum.KeyCode | Enum.UserInputType)
	ContextActionService:BindActionAtPriority(name, function(_, state)
		if state == Enum.UserInputState.Begin then
			fn()
		end
		return Enum.ContextActionResult.Sink
	end, false, 3000, ...)
end

---------------------------------------------------------------------------
-- Touch controls
---------------------------------------------------------------------------
local function buildTouch()
	local gui = UI.new("ScreenGui", {
		Name = "BA_Touch",
		ResetOnSpawn = false,
		ZIndexBehavior = Enum.ZIndexBehavior.Sibling,
		Parent = player:WaitForChild("PlayerGui"),
	})
	local holder = UI.new("Frame", {
		BackgroundTransparency = 1,
		AnchorPoint = Vector2.new(1, 1),
		Position = UDim2.new(1, -20, 1, -20),
		Size = UDim2.fromOffset(270, 230),
		Parent = gui,
	})
	local function circle(text: string, pos: UDim2, size: number, color: Color3, fn: () -> ()): TextButton
		local b = UI.button({ Text = text, Size = UDim2.fromOffset(size, size), Position = pos, Color = color, TextSize = math.floor(size * 0.24), Radius = size // 2, Parent = holder }, fn)
		b.BackgroundTransparency = 0.15
		return b
	end
	local swing = circle("SWING", UDim2.fromOffset(150, 110), 110, UI.Colors.Chaser, Input.Swing)
	local left = circle("◀", UDim2.fromOffset(20, 140), 64, UI.Colors.Blue, function()
		Movement.Dash(-1)
	end)
	local right = circle("▶", UDim2.fromOffset(150, 140), 64, UI.Colors.Blue, function()
		Movement.Dash(1)
	end)
	local stop = circle("STOP", UDim2.fromOffset(84, 160), 58, Color3.fromRGB(120, 120, 130), function()
		Movement.Stop()
	end)
	circle("Q", UDim2.fromOffset(70, 40), 58, UI.Colors.Accent, Input.Ability)
	circle("F", UDim2.fromOffset(0, 70), 54, UI.Colors.Good, Input.Item)
	local function refresh()
		local r = role()
		swing.Visible = r == "Chaser"
		left.Visible = r ~= "Chaser"
		right.Visible = r ~= "Chaser"
		stop.Visible = r ~= "Chaser"
	end
	player:GetAttributeChangedSignal("Role"):Connect(refresh)
	refresh()
end

function Input.Start()
	bind("BA_Dash", function()
		Movement.Dash(nil)
	end, Enum.KeyCode.Space, Enum.KeyCode.ButtonA)
	bind("BA_Stop", function()
		Movement.Stop()
	end, Enum.KeyCode.LeftAlt, Enum.KeyCode.RightAlt, Enum.KeyCode.ButtonB)
	bind("BA_Ability", Input.Ability, Enum.KeyCode.Q, Enum.KeyCode.ButtonY)
	bind("BA_Item", Input.Item, Enum.KeyCode.F, Enum.KeyCode.ButtonR1)
	bind("BA_Swing", Input.Swing, Enum.KeyCode.ButtonR2)
	UserInputService.InputBegan:Connect(function(input, processed)
		if processed then
			return
		end
		if input.UserInputType == Enum.UserInputType.MouseButton1 then
			Input.Swing()
		end
	end)
	if UserInputService.TouchEnabled then
		task.spawn(buildTouch)
	end
end

return Input
