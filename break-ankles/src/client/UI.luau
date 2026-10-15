--!strict
-- Small helpers for building UI in code, plus the shared look.

local TweenService = game:GetService("TweenService")

local UI = {}

UI.Colors = {
	Panel = Color3.fromRGB(22, 24, 32),
	Panel2 = Color3.fromRGB(34, 37, 48),
	Stroke = Color3.fromRGB(0, 0, 0),
	Text = Color3.fromRGB(255, 255, 255),
	Muted = Color3.fromRGB(170, 176, 190),
	Gem = Color3.fromRGB(196, 110, 255),
	Coin = Color3.fromRGB(255, 205, 60),
	Runner = Color3.fromRGB(120, 240, 150),
	Chaser = Color3.fromRGB(255, 85, 85),
	Accent = Color3.fromRGB(255, 190, 50),
	Blue = Color3.fromRGB(80, 170, 255),
	Good = Color3.fromRGB(90, 220, 120),
	Bad = Color3.fromRGB(235, 80, 80),
}

UI.Display = Enum.Font.FredokaOne
UI.Body = Enum.Font.GothamBold
UI.Light = Enum.Font.Gotham

-- new("Frame", { Size = ..., Parent = ... }, { children })
function UI.new(className: string, props: { [string]: any }?, children: { any }?): any
	local inst = Instance.new(className)
	if props then
		local parent = props.Parent
		for k, v in props do
			if k ~= "Parent" then
				(inst :: any)[k] = v
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
	elseif children then
		for _, c in children do
			c.Parent = inst
		end
	end
	return inst
end

function UI.corner(radius: number?): UICorner
	return UI.new("UICorner", { CornerRadius = UDim.new(0, radius or 12) })
end

function UI.stroke(thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or UI.Colors.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Contextual,
	})
end

function UI.borderStroke(thickness: number?, color: Color3?, transparency: number?): UIStroke
	return UI.new("UIStroke", {
		Thickness = thickness or 2,
		Color = color or UI.Colors.Stroke,
		Transparency = transparency or 0,
		ApplyStrokeMode = Enum.ApplyStrokeMode.Border,
	})
end

function UI.padding(px: number): UIPadding
	local u = UDim.new(0, px)
	return UI.new("UIPadding", { PaddingTop = u, PaddingBottom = u, PaddingLeft = u, PaddingRight = u })
end

function UI.list(direction: Enum.FillDirection?, gap: number?, align: Enum.HorizontalAlignment?): UIListLayout
	return UI.new("UIListLayout", {
		FillDirection = direction or Enum.FillDirection.Vertical,
		Padding = UDim.new(0, gap or 6),
		HorizontalAlignment = align or Enum.HorizontalAlignment.Left,
		SortOrder = Enum.SortOrder.LayoutOrder,
	})
end

function UI.gradient(top: Color3, bottom: Color3): UIGradient
	return UI.new("UIGradient", {
		Color = ColorSequence.new(top, bottom),
		Rotation = 90,
	})
end

function UI.text(props: { [string]: any }): TextLabel
	local t = UI.new("TextLabel", {
		BackgroundTransparency = 1,
		Font = UI.Display,
		TextColor3 = UI.Colors.Text,
		TextScaled = false,
		TextSize = 20,
	})
	for k, v in props do
		if k ~= "Parent" and k ~= "Stroke" and k ~= "StrokeThickness" then
			(t :: any)[k] = v
		end
	end
	if props.Stroke ~= false then
		UI.stroke(props.StrokeThickness or 2).Parent = t
	end
	if props.Parent then
		t.Parent = props.Parent
	end
	return t
end

-- A chunky button with a press bounce. `onClick` runs on activation.
function UI.button(props: { [string]: any }, onClick: () -> ()): TextButton
	local color: Color3 = props.Color or UI.Colors.Accent
	local b = UI.new("TextButton", {
		AutoButtonColor = false,
		BackgroundColor3 = color,
		Font = UI.Display,
		TextColor3 = props.TextColor or UI.Colors.Text,
		TextSize = props.TextSize or 20,
		Text = props.Text or "",
		Size = props.Size or UDim2.fromOffset(140, 44),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		LayoutOrder = props.LayoutOrder or 0,
		Name = props.Name or "Button",
	})
	UI.corner(props.Radius or 10).Parent = b
	UI.gradient(Color3.new(1, 1, 1), Color3.fromRGB(200, 200, 200)).Parent = b
	UI.borderStroke(2.5, Color3.new(0, 0, 0), 0.2).Parent = b
	local textStroke = UI.stroke(2)
	textStroke.Parent = b
	local scale = UI.new("UIScale", { Scale = 1, Parent = b })
	b.MouseEnter:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1.05 }):Play()
	end)
	b.MouseLeave:Connect(function()
		TweenService:Create(scale, TweenInfo.new(0.1), { Scale = 1 }):Play()
	end)
	b.Activated:Connect(function()
		scale.Scale = 0.92
		TweenService:Create(scale, TweenInfo.new(0.15, Enum.EasingStyle.Back), { Scale = 1 }):Play()
		onClick()
	end)
	if props.Parent then
		b.Parent = props.Parent
	end
	return b
end

function UI.panel(props: { [string]: any }): Frame
	local f = UI.new("Frame", {
		BackgroundColor3 = props.Color or UI.Colors.Panel,
		BackgroundTransparency = props.Transparency or 0.08,
		Size = props.Size or UDim2.fromOffset(200, 100),
		Position = props.Position or UDim2.new(),
		AnchorPoint = props.AnchorPoint or Vector2.zero,
		Name = props.Name or "Panel",
		Visible = if props.Visible == nil then true else props.Visible,
		LayoutOrder = props.LayoutOrder or 0,
	})
	UI.corner(props.Radius or 14).Parent = f
	UI.borderStroke(2, Color3.new(0, 0, 0), 0.35).Parent = f
	if props.Parent then
		f.Parent = props.Parent
	end
	return f
end

function UI.pop(inst: GuiObject, from: number?)
	local scale = inst:FindFirstChildOfClass("UIScale") or UI.new("UIScale", { Parent = inst })
	scale.Scale = from or 0.6
	TweenService:Create(scale, TweenInfo.new(0.35, Enum.EasingStyle.Back, Enum.EasingDirection.Out), { Scale = 1 }):Play()
end

function UI.tween(inst: Instance, time: number, goal: { [string]: any }, style: Enum.EasingStyle?, dir: Enum.EasingDirection?): Tween
	local t = TweenService:Create(inst, TweenInfo.new(time, style or Enum.EasingStyle.Quad, dir or Enum.EasingDirection.Out), goal)
	t:Play()
	return t
end

-- Text labels carry a UIStroke outline; fading only TextTransparency leaves
-- the outline behind. These fade/show both, and hide the label when done.
function UI.showText(label: TextLabel)
	label.TextTransparency = 0
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		stroke.Transparency = 0
	end
	label.Visible = true
end

function UI.fadeText(label: TextLabel, time: number, isCurrent: (() -> boolean)?)
	UI.tween(label, time, { TextTransparency = 1 })
	local stroke = label:FindFirstChildOfClass("UIStroke")
	if stroke then
		UI.tween(stroke, time, { Transparency = 1 })
	end
	task.delay(time, function()
		if not isCurrent or isCurrent() then
			label.Visible = false
		end
	end)
end

function UI.formatNumber(n: number): string
	local s = tostring(math.floor(n))
	local formatted = s:reverse():gsub("(%d%d%d)", "%1,"):reverse()
	if formatted:sub(1, 1) == "," then
		formatted = formatted:sub(2)
	end
	return formatted
end

return UI
