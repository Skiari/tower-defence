-- Click-and-drag selection rectangle (like on the Windows desktop), used by the base and the dungeon controls.
local SelectBox = {}
local DRAG_PX = 6   -- the mouse has to move this far before a click becomes a drag

function SelectBox.new(playerGui)
	local gui = Instance.new("ScreenGui")
	gui.Name = "SelectBoxUI"
	gui.IgnoreGuiInset = true      -- same coordinates as UserInputService:GetMouseLocation()
	gui.ResetOnSpawn = false
	gui.DisplayOrder = 3
	gui.Parent = playerGui
	local frame = Instance.new("Frame")
	frame.BackgroundColor3 = Color3.fromRGB(80, 170, 255)
	frame.BackgroundTransparency = 0.82
	frame.BorderSizePixel = 0
	frame.Visible = false
	frame.Parent = gui
	local stroke = Instance.new("UIStroke")
	stroke.Color = Color3.fromRGB(140, 210, 255)
	stroke.Thickness = 1.5
	stroke.Parent = frame

	local box = {}
	local start, dragging = nil, false

	function box.begin(pos)
		start, dragging = pos, false
	end
	function box.active()
		return start ~= nil
	end
	function box.update(pos)
		if not start then return end
		if not dragging and (pos - start).Magnitude >= DRAG_PX then dragging = true end
		if dragging then
			frame.Position = UDim2.fromOffset(math.min(start.X, pos.X), math.min(start.Y, pos.Y))
			frame.Size = UDim2.fromOffset(math.abs(pos.X - start.X), math.abs(pos.Y - start.Y))
			frame.Visible = true
		end
	end
	-- returns: was it a drag?, top-left corner, bottom-right corner
	function box.finish(pos)
		box.update(pos)
		local s, d = start, dragging
		start, dragging = nil, false
		frame.Visible = false
		if not s then return false end
		return d, Vector2.new(math.min(s.X, pos.X), math.min(s.Y, pos.Y)), Vector2.new(math.max(s.X, pos.X), math.max(s.Y, pos.Y))
	end
	function box.cancel()
		start, dragging = nil, false
		frame.Visible = false
	end
	-- is a screen point inside the corners returned by finish()?
	function box.contains(a, b, p)
		return p.X >= a.X and p.X <= b.X and p.Y >= a.Y and p.Y <= b.Y
	end
	return box
end

return SelectBox
