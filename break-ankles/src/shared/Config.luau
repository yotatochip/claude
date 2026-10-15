--!strict
-- Every tuning number in Break Ankles lives here, so you can rebalance the
-- game without touching the systems that use them.

local Config = {}

Config.GameName = "Break Ankles"
Config.DataStoreName = "BreakAnkles_Profiles_v1"

---------------------------------------------------------------------------
-- Match flow
---------------------------------------------------------------------------
Config.Match = {
	MinPlayers = 2, -- real players needed to start when bots are off
	Intermission = 20, -- seconds of lobby time between matches
	CrossingsToWin = 3, -- runners must survive this many crossings
	Countdown = 3, -- "3, 2, 1, RUN!!" before each crossing
	CrossingTime = 40, -- seconds to reach the far side
	BetweenCrossings = 5,
	BleedOutTime = 10, -- how long a downed runner waits for a rescue
	ReviveHoldTime = 2.5, -- hold E this long next to a downed teammate
	ReviveRange = 8,
	ResultsTime = 9,
	PlayersPerChaser = 8, -- one starting chaser per this many players (min 1)
	ConvertGraceTime = 1.5, -- a freshly converted chaser can't swing for this long
	-- Hero or Chicken: before crossing 2 or 3 one runner may be offered a solo run
	HeroChance = 0.45,
	HeroChoiceTime = 7,
	HeroCrossingTime = 20,
}

---------------------------------------------------------------------------
-- Bots fill empty slots so the game is playable solo and in quiet servers.
---------------------------------------------------------------------------
Config.Bots = {
	Enabled = true,
	FillTo = 6, -- bots top the match up to this many participants
	Names = {
		"Kenji", "Mara", "Dex", "Lulu", "Tobi", "Rook", "Zia", "Bo",
		"Nico", "Pip", "Juno", "Rex", "Ivy", "Otto", "Sage", "Quinn",
	},
	ReactionTime = { 0.12, 0.3 }, -- chaser bots wait this long before swinging
	FakeOutChance = 0.4, -- chance a chaser bot bites on a runner's juke
	RunnerDashChance = 0.75, -- chance a runner bot jukes when a chaser closes in
}

---------------------------------------------------------------------------
-- Movement: acceleration-based momentum, lateral dash, instant stop.
---------------------------------------------------------------------------
Config.Movement = {
	RunnerSpeed = 22,
	ChaserSpeed = 22.5,
	LobbySpeed = 20,
	RunnerAccel = 80, -- studs/s² toward the input direction
	ChaserAccel = 66, -- chasers turn a little wider, which is what makes jukes work
	Friction = 46, -- studs/s² of slowdown after you let go (the slide)

	DashSpeed = 64,
	DashTime = 0.16,
	DashCooldown = 0.9,
	StopCooldown = 0.35,

	LungeSpeed = 34, -- chaser's forward burst on a swing
	LungeTime = 0.12,

	RocketSpeed = 82, -- Rocket Shoes
	RocketTime = 0.24,
}

---------------------------------------------------------------------------
-- The knife and ankle breaking
---------------------------------------------------------------------------
Config.Knife = {
	Reach = 6,
	Leniency = 1.5, -- extra server-side reach to cover ping
	HalfAngle = 80, -- degrees either side of where the chaser faces
	CloseRange = 3.5, -- inside this, any angle hits
	Windup = 0.1,
	Cooldown = 1.0,
	MissSlowMult = 0.5,
	MissSlowTime = 0.55,
	-- Ankle break: the swing misses a runner who juked (dash or instant stop)
	-- within JukeWindow seconds while inside JukeRange studs.
	JukeWindow = 0.8,
	JukeRange = 12,
	AnkleStunTime = 1.25,
}

---------------------------------------------------------------------------
-- Economy. Gems buy abilities, coins buy consumables.
---------------------------------------------------------------------------
Config.Rewards = {
	CrossingGems = 15,
	CrossingCoins = 25,
	SurviveGems = 60,
	SurviveCoins = 80,
	FlawlessGems = 40, -- every runner survived every crossing
	CatchGems = 20,
	CatchCoins = 30,
	ChaserWinGems = 60,
	ChaserWinCoins = 80,
	AnkleBreakGems = 15,
	RescueGems = 20,
	HeroGems = 100,
	ParticipationCoins = 10,
	FieldGemValue = 5,
	FieldGemsPerCrossing = 14,

	CrossingXP = 30,
	SurviveXP = 120,
	CatchXP = 40,
	AnkleBreakXP = 25,
	RescueXP = 50, -- rescuing gives a big XP boost
	ChaserWinXP = 100,
	ParticipationXP = 20,
}

-- XP needed to go from `level` to `level + 1`.
function Config.XPForLevel(level: number): number
	return 100 + (level - 1) * 40
end

---------------------------------------------------------------------------
-- Codes. Each reward table can grant Gems, Coins, timed Boosts (seconds of
-- 2x gems / 2x coins) and a Title (an id from Catalog.Titles).
---------------------------------------------------------------------------
Config.Codes = {
	BREAKANKLES = { Gems = 250, Boosts = { Gems = 15 * 60, Coins = 15 * 60 }, Title = "AnkleBreaker" },
	FIRSTCROSSING = { Gems = 150, Coins = 200 },
}

---------------------------------------------------------------------------
-- Developer products for Robux gem packs. Create them under the experience's
-- Monetization > Developer Products page and paste the IDs in here.
---------------------------------------------------------------------------
Config.Products = {
	-- [1234567890] = { Gems = 1000 },
}

---------------------------------------------------------------------------
-- Sounds. Built-in Roblox sounds are used by default. Upload your own audio
-- and paste "rbxassetid://<id>" here to replace any of them.
---------------------------------------------------------------------------
Config.Sounds = {
	Swing = "rbxasset://sounds/swordslash.wav",
	Lunge = "rbxasset://sounds/swordlunge.wav",
	Equip = "rbxasset://sounds/unsheath.wav",
	Down = "rbxasset://sounds/uuhhh.mp3",
	Dash = "rbxasset://sounds/Rocket whoosh 01.wav",
	Stop = "rbxasset://sounds/action_jump_land.mp3",
	AnkleBreak = "rbxasset://sounds/glassbreak.wav",
	Gem = "rbxasset://sounds/electronicpingshort.wav",
	Click = "rbxasset://sounds/button.wav",
	Tick = "rbxasset://sounds/clickfast.wav",
	Safe = "rbxasset://sounds/electronicpingshort.wav",
	Win = "rbxasset://sounds/victory.wav",
	Horn = "rbxasset://sounds/Launching rocket.wav",
	Trap = "rbxasset://sounds/collide.wav",
	Trip = "rbxasset://sounds/action_falling.mp3",
	GetUp = "rbxasset://sounds/action_get_up.mp3",
}

-- Background music. Leave empty for none, or paste "rbxassetid://<id>".
Config.Music = {
	Lobby = "",
	Chase = "",
}

---------------------------------------------------------------------------
-- Art made with ForgeGUI and uploaded to the creator's Roblox account.
-- The lobby poster shows Poster; if it ever fails to load, the text title
-- underneath shows instead.
---------------------------------------------------------------------------
Config.Art = {
	Poster = "rbxassetid://91723483788506", -- game thumbnail art
	Icon = "rbxassetid://98979542296379", -- game icon art
}

---------------------------------------------------------------------------
-- Arena dimensions (studs). The field runs along Z: side A is at -Z.
---------------------------------------------------------------------------
Config.Arena = {
	Length = 220, -- line to line
	Width = 120,
	SafeDepth = 32, -- depth of each safe zone beyond its line
	WallHeight = 40,
	LobbyOffset = Vector3.new(-150, 26, 0),
}

Config.Maps = {
	{ Id = "Valley", Name = "The Valley", Blurb = "Rolling green field" },
	{ Id = "Dunes", Name = "The Dunes", Blurb = "Sun-baked sand flats" },
}

return Config
