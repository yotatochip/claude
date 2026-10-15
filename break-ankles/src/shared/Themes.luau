--!strict
-- The look of each map: ground, fences, hills, decor and lighting. The
-- server builds the real arena from this and clients build the small vote
-- previews from it, so the two always match.

local Themes = {}

export type Theme = {
	Ground: Enum.Material,
	GroundColor: Color3,
	StripeColor: Color3,
	Surround: Enum.Material,
	SurroundColor: Color3,
	SafeMaterial: Enum.Material,
	SafeColor: Color3,
	FenceColor: Color3,
	HillMaterial: Enum.Material,
	HillColor: Color3,
	Lighting: { [string]: any },
	Atmosphere: { [string]: any },
	Tint: Color3,
	Decor: string,
}

Themes.Themes = ({
	Valley = {
		Ground = Enum.Material.Grass,
		GroundColor = Color3.fromRGB(86, 158, 64),
		StripeColor = Color3.fromRGB(98, 172, 72),
		Surround = Enum.Material.Grass,
		SurroundColor = Color3.fromRGB(74, 138, 58),
		SafeMaterial = Enum.Material.Ground,
		SafeColor = Color3.fromRGB(176, 150, 108),
		FenceColor = Color3.fromRGB(120, 86, 56),
		HillMaterial = Enum.Material.Grass,
		HillColor = Color3.fromRGB(68, 130, 56),
		Lighting = {
			ClockTime = 14.2,
			Brightness = 2.6,
			Ambient = Color3.fromRGB(88, 92, 104),
			OutdoorAmbient = Color3.fromRGB(140, 142, 152),
		},
		Atmosphere = {
			Density = 0.28,
			Offset = 0.1,
			Color = Color3.fromRGB(199, 222, 255),
			Decay = Color3.fromRGB(108, 140, 182),
			Glare = 0.2,
			Haze = 1.2,
		},
		Tint = Color3.fromRGB(255, 255, 255),
		Decor = "Valley",
	},
	Dunes = {
		Ground = Enum.Material.Sand,
		GroundColor = Color3.fromRGB(222, 192, 136),
		StripeColor = Color3.fromRGB(230, 202, 148),
		Surround = Enum.Material.Sand,
		SurroundColor = Color3.fromRGB(214, 180, 122),
		SafeMaterial = Enum.Material.Sandstone,
		SafeColor = Color3.fromRGB(196, 150, 104),
		FenceColor = Color3.fromRGB(150, 110, 70),
		HillMaterial = Enum.Material.Sand,
		HillColor = Color3.fromRGB(224, 186, 124),
		Lighting = {
			ClockTime = 16.6,
			Brightness = 3.1,
			Ambient = Color3.fromRGB(110, 96, 86),
			OutdoorAmbient = Color3.fromRGB(160, 140, 124),
		},
		Atmosphere = {
			Density = 0.34,
			Offset = 0.15,
			Color = Color3.fromRGB(255, 226, 184),
			Decay = Color3.fromRGB(214, 160, 112),
			Glare = 0.4,
			Haze = 2.0,
		},
		Tint = Color3.fromRGB(255, 244, 230),
		Decor = "Dunes",
	},
}) :: { [string]: Theme }

Themes.SideColors = {
	A = Color3.fromRGB(60, 140, 255),
	B = Color3.fromRGB(255, 140, 40),
}

function Themes.Get(id: string): Theme
	return Themes.Themes[id] or Themes.Themes.Valley
end

return Themes
