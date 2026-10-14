--!strict
-- Every tunable number in Sharks Vs Minnows lives here, shared by the server and the client.

local Config = {}

-- Round flow -----------------------------------------------------------------
Config.MinPlayersToStart = 1 -- real players needed; bots fill the rest
Config.IntermissionTime = 20
Config.ReadyTime = 4 -- countdown before each crossing while the gates are shut
Config.CrossTime = 22 -- seconds the minnows have to reach the far shore
Config.MaxCrossings = 8 -- survive this many and every remaining minnow wins
Config.EndScreenTime = 7
Config.SharksPerPlayers = 7 -- one starting shark for every 7 participants (min 1)

-- Bots keep a small or solo server playable.
Config.BotsEnabled = true
Config.BotFillTarget = 8 -- top the round up to this many participants

-- Movement ---------------------------------------------------------------------
Config.MinnowSpeed = 20
Config.SharkSpeed = 21
Config.LobbySpeed = 18
Config.TagRange = 4.6 -- studs between root parts that counts as a chomp
Config.TagGrace = 1.0 -- seconds a brand-new shark can't tag (no instant chain tags)

-- Map layout (the arena runs along the X axis) --------------------------------
Config.ArenaHalfLength = 120 -- shore edge to shore edge is 2x this
Config.SafeLine = 85 -- |x| beyond this is a shore safe zone
Config.ArenaHalfWidth = 70
Config.LobbyCenter = Vector3.new(0, 0, -220)

-- Rewards ------------------------------------------------------------------------
Config.Rewards = {
	Crossing = 10, -- per crossing survived
	Tag = 15, -- per minnow chomped
	MinnowWin = 60,
	LastMinnowBonus = 40,
	SharkWin = 35, -- each shark when the ocean is cleared
	WinGems = 1,
	Participation = 5,
}

-- Abilities (E) ------------------------------------------------------------------
export type AbilityDef = {
	Id: string,
	Name: string,
	Role: "Minnow" | "Shark",
	Description: string,
	Cooldown: number,
	Price: number, -- coins, 0 = owned by default
	Color: Color3,
	Icon: string,
}

Config.Abilities = {
	-- Minnow
	Dash = {
		Id = "Dash", Name = "Dart", Role = "Minnow", Price = 0, Cooldown = 8,
		Description = "A short burst of speed in the direction you're running.",
		Color = Color3.fromRGB(255, 170, 60), Icon = "💨",
	},
	Bubble = {
		Id = "Bubble", Name = "Bubble Shield", Role = "Minnow", Price = 250, Cooldown = 22,
		Description = "Wrap yourself in a bubble. Chomps bounce off for 2.5s.",
		Color = Color3.fromRGB(120, 220, 255), Icon = "🫧",
	},
	Ink = {
		Id = "Ink", Name = "Ink Cloud", Role = "Minnow", Price = 400, Cooldown = 18,
		Description = "Burst a cloud of ink. Nearby sharks are slowed and blinded.",
		Color = Color3.fromRGB(120, 80, 200), Icon = "🦑",
	},
	Riptide = {
		Id = "Riptide", Name = "Riptide", Role = "Minnow", Price = 750, Cooldown = 20,
		Description = "Ride the current: +9 speed for 3 seconds.",
		Color = Color3.fromRGB(60, 240, 190), Icon = "🌊",
	},
	-- Shark
	Lunge = {
		Id = "Lunge", Name = "Lunge", Role = "Shark", Price = 0, Cooldown = 7,
		Description = "Explode forward to snap up a minnow.",
		Color = Color3.fromRGB(255, 80, 80), Icon = "🦈",
	},
	Sonar = {
		Id = "Sonar", Name = "Sonar", Role = "Shark", Price = 300, Cooldown = 20,
		Description = "Ping the water. See every minnow through walls for 4s.",
		Color = Color3.fromRGB(80, 160, 255), Icon = "📡",
	},
	Frenzy = {
		Id = "Frenzy", Name = "Frenzy", Role = "Shark", Price = 500, Cooldown = 24,
		Description = "Blood in the water: +8 speed and a bigger bite for 3.5s.",
		Color = Color3.fromRGB(220, 30, 60), Icon = "🩸",
	},
	Whirlpool = {
		Id = "Whirlpool", Name = "Whirlpool", Role = "Shark", Price = 850, Cooldown = 26,
		Description = "Spin up a whirlpool. Minnows caught inside are slowed for 3s.",
		Color = Color3.fromRGB(40, 120, 200), Icon = "🌀",
	},
} :: { [string]: AbilityDef }

Config.AbilityOrder = { "Dash", "Bubble", "Ink", "Riptide", "Lunge", "Sonar", "Frenzy", "Whirlpool" }
Config.DefaultAbility = { Minnow = "Dash", Shark = "Lunge" }

-- Consumables (1, 2, 3) ----------------------------------------------------------------
export type ItemDef = {
	Id: string,
	Name: string,
	Role: "Any" | "Minnow" | "Shark",
	Description: string,
	Price: number,
	Key: string,
	Color: Color3,
	Icon: string,
}

Config.Items = {
	Kelp = {
		Id = "Kelp", Name = "Speed Kelp", Role = "Any", Price = 30, Key = "1",
		Description = "+7 speed for 4 seconds. Works for minnows and sharks.",
		Color = Color3.fromRGB(90, 200, 80), Icon = "🌿",
	},
	Pearl = {
		Id = "Pearl", Name = "Lucky Pearl", Role = "Minnow", Price = 75, Key = "2",
		Description = "Blocks the next chomp within 8 seconds.",
		Color = Color3.fromRGB(255, 240, 220), Icon = "🦪",
	},
	Net = {
		Id = "Net", Name = "Fishing Net", Role = "Shark", Price = 50, Key = "3",
		Description = "Drop a net. The first minnow through it is stuck for 1.5s.",
		Color = Color3.fromRGB(200, 170, 110), Icon = "🕸️",
	},
} :: { [string]: ItemDef }

Config.ItemOrder = { "Kelp", "Pearl", "Net" }
Config.ItemCooldown = 3 -- shared between all consumables
Config.StarterItems = { Kelp = 2, Pearl = 1, Net = 1 }

-- Trails (bought with gems) ------------------------------------------------------------
export type TrailDef = {
	Id: string,
	Name: string,
	Price: number, -- gems
	Colors: { Color3 },
}

Config.Trails = {
	Bubbles = { Id = "Bubbles", Name = "Bubbles", Price = 2, Colors = { Color3.fromRGB(200, 240, 255), Color3.fromRGB(120, 200, 255) } },
	Coral = { Id = "Coral", Name = "Coral Reef", Price = 4, Colors = { Color3.fromRGB(255, 120, 140), Color3.fromRGB(255, 200, 120) } },
	Toxic = { Id = "Toxic", Name = "Toxic Waste", Price = 6, Colors = { Color3.fromRGB(150, 255, 60), Color3.fromRGB(40, 140, 30) } },
	Gold = { Id = "Gold", Name = "Sunken Gold", Price = 10, Colors = { Color3.fromRGB(255, 220, 90), Color3.fromRGB(200, 140, 30) } },
	Rainbow = {
		Id = "Rainbow", Name = "Rainbow Reef", Price = 15,
		Colors = { Color3.fromRGB(255, 80, 80), Color3.fromRGB(255, 220, 60), Color3.fromRGB(80, 220, 120), Color3.fromRGB(80, 140, 255), Color3.fromRGB(200, 90, 255) },
	},
} :: { [string]: TrailDef }

Config.TrailOrder = { "Bubbles", "Coral", "Toxic", "Gold", "Rainbow" }

-- Codes. Keys are upper case; players can type any case.
Config.Codes = {
	SHARKBAIT = { Coins = 150 },
	MINNOWMANIA = { Gems = 2 },
	FINSUP = { Coins = 100, Items = { Kelp = 3 } },
	RELEASE = { Coins = 250, Gems = 1 },
} :: { [string]: { Coins: number?, Gems: number?, Items: { [string]: number }? } }

-- Colors used across the UI and the world.
Config.Colors = {
	Minnow = Color3.fromRGB(255, 160, 50),
	Shark = Color3.fromRGB(70, 110, 160),
	SharkOutline = Color3.fromRGB(255, 60, 60),
	Coins = Color3.fromRGB(255, 205, 60),
	Gems = Color3.fromRGB(110, 230, 255),
}

Config.DataStoreName = "SharksVsMinnows_v1"

return Config
