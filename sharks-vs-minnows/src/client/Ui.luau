--!strict
-- Tiny helpers for building GUI in code.

local Ui = {}

Ui.Font = Enum.Font.FredokaOne
Ui.BodyFont = Enum.Font.GothamMedium

Ui.Theme = {
	Panel = Color3.fromRGB(18, 38, 58),
	PanelLight = Color3.fromRGB(30, 60, 88),
	Stroke = Color3.fromRGB(10, 20, 32),
	Text = Color3.fromRGB(245, 250, 255),
	Muted = Color3.fromRGB(170, 195, 215),
	Good = Color3.fromRGB(90, 220, 130),
	Bad = Color3.fromRGB(255, 95, 95),
	Accent = Color3.fromRGB(70, 190, 255),
}

-- make("Frame", { Size = ..., Parent = ... }, { children })
function Ui.make(className: string, props: { [string]: any }?, children: { Instance }?): any
	local inst = Instance.new(className)
	local parent = nil
	if props then
		for k, v in props do
			if k == "Parent" then
				parent = v
			else
				(inst :: any)[k] = v
			end
		end
	end
	if children then
		for _, c in children do
			c.Parent = inst
		end
	end
	if parent then
		inst.Parent = parent
	end
	return inst
end

function Ui.corner(radius: number?): Instance
	return Ui.make("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function Ui.stroke(thickness: number?, color: Color3?, transparency: number?): Instance
	return Ui.make("UIStroke", {
		Thickness = thickness or 2,
		Color = color or Ui.Theme.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function Ui.textStroke(thickness: number?): Instance
	return Ui.make("UIStroke", { Thickness = thickness or 2, Color = Ui.Theme.Stroke, ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual })
end

function Ui.padding(px: number): Instance
	local u = UDim.new(0, px)
	return Ui.make("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function Ui.gradient(top: Color3, bottom: Color3): Instance
	return Ui.make("UIGradient", { Color = ColorSequence.new(top, bottom), Rotation = 90 })
end

function Ui.label(props: { [string]: any }): TextLabel
	local defaults = {
		BackgroundTransparency = 1,
		Font = Ui.Font,
		TextColor3 = Ui.Theme.Text,
		TextScaled = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	local children: { Instance } = { Ui.textStroke(props.StrokeThickness) }
	defaults.StrokeThickness = nil
	return Ui.make("TextLabel", defaults, children)
end

-- A chunky rounded button with a darker bottom edge.
function Ui.button(props: { [string]: any }, color: Color3): TextButton
	local defaults = {
		AutoButtonColor = true,
		BackgroundColor3 = color,
		Font = Ui.Font,
		TextColor3 = Ui.Theme.Text,
		TextScaled = true,
	}
	for k, v in props do
		defaults[k] = v
	end
	return Ui.make("TextButton", defaults, {
		Ui.corner(10),
		Ui.stroke(2.5),
		Ui.gradient(Color3.new(1, 1, 1), Color3.fromRGB(190, 190, 190)),
		Ui.textStroke(1.5),
		Ui.make("UIPadding", { PaddingTop = UDim.new(0, 4), PaddingBottom = UDim.new(0, 4), PaddingLeft = UDim.new(0, 6), PaddingRight = UDim.new(0, 6) }),
	})
end

function Ui.formatTime(seconds: number): string
	seconds = math.max(0, math.ceil(seconds))
	return string.format("%d:%02d", seconds // 60, seconds % 60)
end

function Ui.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return Ui
