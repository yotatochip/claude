--!strict
-- Gem pickups scattered over the field each crossing. Only runners can grab
-- them, which tempts them off the safe line.

local RunService = game:GetService("RunService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Arena = require(Shared.Arena)
local Config = require(Shared.Config)
local Net = require(Shared.Net)
local MapBuilder = require(script.Parent.MapBuilder)
local Phase = require(script.Parent.Phase)
local Rewards = require(script.Parent.Rewards)
local Roster = require(script.Parent.Roster)

local Effect = Net.Event("Effect")

local Gems = {}

local gems: { BasePart } = {}
local rng = Random.new()

function Gems.Spawn(count: number)
	Gems.Clear()
	local folder = MapBuilder.Dynamic()
	for _ = 1, count do
		local x = rng:NextNumber(-Arena.HalfWidth + 6, Arena.HalfWidth - 6)
		local z = rng:NextNumber(-Arena.HalfLength + 14, Arena.HalfLength - 14)
		local gem = Instance.new("Part")
		gem.Name = "Gem"
		gem.Size = Vector3.new(1.3, 1.3, 1.3)
		gem.CFrame = CFrame.new(x, 2.2, z) * CFrame.Angles(math.rad(45), 0, math.rad(45))
		gem.Anchored = true
		gem.CanCollide = false
		gem.CanQuery = false
		gem.CanTouch = false
		gem.Material = Enum.Material.Neon
		gem.Color = Color3.fromRGB(190, 90, 255)
		gem.CastShadow = false
		gem:SetAttribute("Gem", true)
		local light = Instance.new("PointLight")
		light.Color = gem.Color
		light.Range = 7
		light.Brightness = 1.4
		light.Parent = gem
		gem.Parent = folder
		table.insert(gems, gem)
	end
end

function Gems.List(): { BasePart }
	return gems
end

function Gems.Clear()
	for _, g in gems do
		g:Destroy()
	end
	table.clear(gems)
end

local function step()
	if #gems == 0 or not Phase.IsLive() then
		return
	end
	local runners = Roster.WithRole("Runner")
	for i = #gems, 1, -1 do
		local gem = gems[i]
		local p = gem.Position
		for _, e in runners do
			local r = Roster.Root(e)
			if r and Vector3.new(r.Position.X - p.X, 0, r.Position.Z - p.Z).Magnitude < 3.6 then
				Effect:FireAllClients({ Kind = "GemPickup", Position = p, Model = e.Model })
				Rewards.Give(e, Config.Rewards.FieldGemValue, 0, 0, "Gem pickup")
				gem:Destroy()
				table.remove(gems, i)
				break
			end
		end
	end
end

function Gems.Start()
	RunService.Heartbeat:Connect(step)
end

return Gems
