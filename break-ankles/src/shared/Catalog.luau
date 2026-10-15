--!strict
-- Everything players can own: abilities (gems), consumables (coins),
-- knife skins (gems) and titles. Both the shop UI and the server read this.

export type Ability = {
	Id: string,
	Name: string,
	Role: "Runner" | "Chaser",
	Price: number, -- gems, 0 = free starter
	Cooldown: number,
	Description: string,
	Color: Color3,
	Order: number,
}

export type Item = {
	Id: string,
	Name: string,
	Price: number, -- coins per pack
	Charges: number, -- uses per pack
	Cooldown: number,
	Roles: { [string]: boolean },
	Description: string,
	Color: Color3,
	Order: number,
}

export type Knife = {
	Id: string,
	Name: string,
	Price: number,
	Blade: Color3,
	BladeMaterial: Enum.Material,
	Handle: Color3,
	Glow: boolean,
	Order: number,
}

local Catalog = {}

Catalog.Abilities = {
	-- Runner abilities ------------------------------------------------------
	OneHitShield = {
		Id = "OneHitShield", Name = "One Hit Shield", Role = "Runner", Price = 0, Cooldown = 12, Order = 1,
		Description = "Raise a shield that blocks the next knife hit for 0.75 seconds. Time it right.",
		Color = Color3.fromRGB(90, 200, 255),
	},
	PocketDoor = {
		Id = "PocketDoor", Name = "Pocket Door", Role = "Runner", Price = 875, Cooldown = 20, Order = 2,
		Description = "Slam down a door between you and the chaser. Chasers must smash it or go around. Lasts 6 seconds.",
		Color = Color3.fromRGB(196, 138, 80),
	},
	EmergencyAirhorn = {
		Id = "EmergencyAirhorn", Name = "Emergency Airhorn", Role = "Runner", Price = 1450, Cooldown = 25, Order = 3,
		Description = "Blast every nearby chaser backward in all directions.",
		Color = Color3.fromRGB(255, 214, 60),
	},
	Cloak = {
		Id = "Cloak", Name = "Cloak", Role = "Runner", Price = 1625, Cooldown = 22, Order = 4,
		Description = "Vanish for 3 seconds. You can still be hit, and using an item ends it.",
		Color = Color3.fromRGB(170, 120, 255),
	},
	-- Chaser abilities ------------------------------------------------------
	BearTrap = {
		Id = "BearTrap", Name = "Bear Trap", Role = "Chaser", Price = 0, Cooldown = 14, Order = 1,
		Description = "Toss a trap 10 studs ahead. The first runner to step in is stuck for half a second. Lasts 12 seconds.",
		Color = Color3.fromRGB(150, 150, 160),
	},
	BowlingBall = {
		Id = "BowlingBall", Name = "Bowling Ball", Role = "Chaser", Price = 600, Cooldown = 12, Order = 2,
		Description = "Roll a ball along the ground. A direct hit trips the runner.",
		Color = Color3.fromRGB(60, 90, 220),
	},
	BigDagger = {
		Id = "BigDagger", Name = "Big Dagger", Role = "Chaser", Price = 1125, Cooldown = 16, Order = 3,
		Description = "Double your reach for your next swing. Expires after 5 seconds.",
		Color = Color3.fromRGB(230, 80, 80),
	},
	RocketShoes = {
		Id = "RocketShoes", Name = "Rocket Shoes", Role = "Chaser", Price = 1300, Cooldown = 10, Order = 4,
		Description = "Blast forward in the direction you're moving, or where you're looking if you're standing still.",
		Color = Color3.fromRGB(255, 120, 40),
	},
	RufusLeash = {
		Id = "RufusLeash", Name = "Rufus's Leash", Role = "Chaser", Price = 1625, Cooldown = 16, Order = 5,
		Description = "Throw a leash up to 15 studs ahead. A hit yanks the runner 6 studs toward you.",
		Color = Color3.fromRGB(120, 220, 120),
	},
} :: { [string]: Ability }

Catalog.Items = {
	BananaPeel = {
		Id = "BananaPeel", Name = "Banana Peel", Price = 135, Charges = 3, Cooldown = 3, Order = 1,
		Roles = { Runner = true, Chaser = true },
		Description = "Drop a peel. The first opponent to step on it slips and falls.",
		Color = Color3.fromRGB(255, 225, 70),
	},
	RescueKit = {
		Id = "RescueKit", Name = "Rescue Kit", Price = 203, Charges = 3, Cooldown = 1, Order = 2,
		Roles = { Runner = true },
		Description = "Picks you back up when you're downed. No teammate needed.",
		Color = Color3.fromRGB(240, 70, 70),
	},
	Adrenaline = {
		Id = "Adrenaline", Name = "Adrenaline", Price = 135, Charges = 3, Cooldown = 3, Order = 3,
		Roles = { Runner = true, Chaser = true },
		Description = "Five seconds of extra speed and sharper cornering.",
		Color = Color3.fromRGB(80, 230, 160),
	},
} :: { [string]: Item }

Catalog.Knives = {
	Classic = { Id = "Classic", Name = "Classic", Price = 0, Order = 1,
		Blade = Color3.fromRGB(205, 210, 215), BladeMaterial = Enum.Material.Metal, Handle = Color3.fromRGB(60, 40, 30), Glow = false },
	Rusty = { Id = "Rusty", Name = "Rusty", Price = 300, Order = 2,
		Blade = Color3.fromRGB(150, 90, 50), BladeMaterial = Enum.Material.CorrodedMetal, Handle = Color3.fromRGB(80, 60, 40), Glow = false },
	Candy = { Id = "Candy", Name = "Candy Cane", Price = 600, Order = 3,
		Blade = Color3.fromRGB(255, 90, 110), BladeMaterial = Enum.Material.SmoothPlastic, Handle = Color3.fromRGB(255, 255, 255), Glow = false },
	Neon = { Id = "Neon", Name = "Neon", Price = 900, Order = 4,
		Blade = Color3.fromRGB(60, 255, 200), BladeMaterial = Enum.Material.Neon, Handle = Color3.fromRGB(25, 25, 30), Glow = true },
	Gold = { Id = "Gold", Name = "Gold", Price = 1500, Order = 5,
		Blade = Color3.fromRGB(255, 200, 60), BladeMaterial = Enum.Material.Foil, Handle = Color3.fromRGB(120, 20, 20), Glow = false },
	Ghost = { Id = "Ghost", Name = "Ghost", Price = 2500, Order = 6,
		Blade = Color3.fromRGB(170, 200, 255), BladeMaterial = Enum.Material.ForceField, Handle = Color3.fromRGB(200, 220, 255), Glow = true },
} :: { [string]: Knife }

-- Titles show above your head. Most are earned, not bought.
Catalog.Titles = {
	Rookie = { Id = "Rookie", Name = "Rookie", Color = Color3.fromRGB(220, 220, 220), Order = 1, Hint = "Everyone starts here" },
	AnkleBreaker = { Id = "AnkleBreaker", Name = "Ankle Breaker", Color = Color3.fromRGB(255, 170, 60), Order = 2, Hint = "Code reward" },
	Flawless = { Id = "Flawless", Name = "Flawless", Color = Color3.fromRGB(120, 230, 255), Order = 3, Hint = "Win a match where nobody gets caught" },
	Hero = { Id = "Hero", Name = "Hero", Color = Color3.fromRGB(255, 225, 90), Order = 4, Hint = "Finish a Hero run" },
	Menace = { Id = "Menace", Name = "Menace", Color = Color3.fromRGB(255, 80, 80), Order = 5, Hint = "Catch 25 runners" },
	Untouchable = { Id = "Untouchable", Name = "Untouchable", Color = Color3.fromRGB(190, 140, 255), Order = 6, Hint = "Break 50 ankles" },
	Veteran = { Id = "Veteran", Name = "Veteran", Color = Color3.fromRGB(150, 255, 150), Order = 7, Hint = "Reach level 15" },
}

-- Sorted list helper for UIs.
function Catalog.Sorted<T>(map: { [string]: T }, filter: ((T) -> boolean)?): { T }
	local list = {}
	for _, v in map do
		if not filter or filter(v) then
			table.insert(list, v)
		end
	end
	table.sort(list, function(a: any, b: any)
		return a.Order < b.Order
	end)
	return list
end

Catalog.StarterRunnerAbility = "OneHitShield"
Catalog.StarterChaserAbility = "BearTrap"

return Catalog
