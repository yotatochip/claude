--!strict
-- Plays the sounds named in Config.Sounds, plus looping music.

local SoundService = game:GetService("SoundService")
local TweenService = game:GetService("TweenService")

local Shared = game:GetService("ReplicatedStorage"):WaitForChild("Shared")
local Config = require(Shared.Config)

local Sounds = {}

local cache: { [string]: Sound } = {}
local folder = Instance.new("Folder")
folder.Name = "BA_Sounds"
folder.Parent = SoundService

local VOLUME: { [string]: number } = {
	Swing = 0.6,
	Lunge = 0.4,
	Down = 0.8,
	Dash = 0.35,
	Stop = 0.4,
	AnkleBreak = 0.8,
	Gem = 0.45,
	Click = 0.5,
	Tick = 0.6,
	Win = 0.6,
	Horn = 0.8,
}

local function get(name: string): Sound?
	local id = (Config.Sounds :: any)[name]
	if type(id) ~= "string" or id == "" then
		return nil
	end
	local s = cache[name]
	if not s then
		local created = Instance.new("Sound")
		created.Name = name
		created.SoundId = id
		created.Volume = VOLUME[name] or 0.5
		created.Parent = folder
		cache[name] = created
		return created
	end
	return s
end

function Sounds.Play(name: string?, pitch: number?)
	if not name then
		return
	end
	local s = get(name)
	if not s then
		return
	end
	local clone = s:Clone()
	clone.PlaybackSpeed = pitch or 1
	clone.Parent = folder
	clone:Play()
	clone.Ended:Once(function()
		clone:Destroy()
	end)
	task.delay(6, function()
		if clone.Parent then
			clone:Destroy()
		end
	end)
end

-- 3D sound at a position (others' swings, airhorns, traps).
function Sounds.PlayAt(name: string, position: Vector3, pitch: number?)
	local s = get(name)
	if not s then
		return
	end
	local holder = Instance.new("Attachment")
	holder.WorldPosition = position
	holder.Parent = workspace.Terrain
	local clone = s:Clone()
	clone.PlaybackSpeed = pitch or 1
	clone.RollOffMaxDistance = 140
	clone.RollOffMinDistance = 10
	clone.Parent = holder
	clone:Play()
	task.delay(5, function()
		holder:Destroy()
	end)
end

local music: Sound? = nil
local musicKey: string? = nil

function Sounds.Music(key: string?)
	if key == musicKey then
		return
	end
	musicKey = key
	local old = music
	if old then
		TweenService:Create(old, TweenInfo.new(1), { Volume = 0 }):Play()
		task.delay(1.1, function()
			old:Destroy()
		end)
		music = nil
	end
	local id = if key then (Config.Music :: any)[key] else nil
	if type(id) ~= "string" or id == "" then
		return
	end
	local s = Instance.new("Sound")
	s.SoundId = id
	s.Looped = true
	s.Volume = 0
	s.Parent = folder
	s:Play()
	TweenService:Create(s, TweenInfo.new(1.5), { Volume = 0.35 }):Play()
	music = s
end

return Sounds
