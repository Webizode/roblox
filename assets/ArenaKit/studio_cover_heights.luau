-- Studio (Edit, through the MCP or the command bar), test of 14.11.2026: cover in two heights you can tell apart.
--
-- A jump at JumpPower 40 gets a character onto a block up to about 6.8 high (Roblox's step-up at the edge included,
-- measured 14.11.2026: 6.4 and 6.8 yes, 7.2 no). Cover from 6.5 to 9 high looked like the jumpable ones but was just out
-- of reach. Every such model in Covery is scaled down as a whole (look and Collision box together, Model:ScaleTo) to
-- TARGET high and set back onto its ground; anything stacked on it comes down with it. Afterwards there are two kinds:
-- middle (up to about 6.4: jump on, walk on top) and high (from about 10.9: never from the ground).
-- A copy of Covery goes to ServerStorage (BACKUP) first; RESTORE = true puts it back.

local RESTORE = false
local BACKUP = "MapBackup_2026-11-14_Covery"
local LOW, HIGH = 6.5, 9 -- the heights in between that get scaled
local TARGET = 6.3

local ServerStorage = game:GetService("ServerStorage")
local map = workspace["Ice Cream Map"]

if RESTORE then
	local copy = ServerStorage:FindFirstChild(BACKUP)
	assert(copy, "no backup " .. BACKUP)
	map.Covery:Destroy()
	local restored = copy:Clone()
	restored.Name = "Covery"
	restored.Parent = map
	print("[CoverHeights] restored Covery from " .. BACKUP)
	return "restored"
end

if not ServerStorage:FindFirstChild(BACKUP) then
	local copy = map.Covery:Clone()
	copy.Name = BACKUP
	copy.Parent = ServerStorage
end

local params = RaycastParams.new()
params.FilterType = Enum.RaycastFilterType.Exclude
params.FilterDescendantsInstances = { map.Covery, map.Sperre }

local function box(model: Model): BasePart?
	local b = model:FindFirstChild("Collision")
	return if b and b:IsA("BasePart") then b else nil
end

local function extent(b: BasePart): (number, number)
	local f, s = b.CFrame, b.Size
	local half = (f.RightVector * s.X / 2):Abs() + (f.UpVector * s.Y / 2):Abs() + (f.LookVector * s.Z / 2):Abs()
	return f.Position.Y - half.Y, f.Position.Y + half.Y
end

local function overlaps(a: BasePart, b: BasePart): boolean
	local p = a.CFrame:PointToObjectSpace(b.Position)
	local reach = math.max(b.Size.X, b.Size.Z) / 2
	return math.abs(p.X) <= a.Size.X / 2 + reach and math.abs(p.Z) <= a.Size.Z / 2 + reach
end

local models = {}
for _, d in map.Covery:GetDescendants() do
	if d:IsA("Model") and box(d) then
		table.insert(models, d)
	end
end

local lines = {}
for _, m in models do
	local b = box(m) :: BasePart
	local bottom, top = extent(b)
	local under = workspace:Raycast(Vector3.new(b.Position.X, top + 50, b.Position.Z), Vector3.new(0, -120, 0), params)
	local base = if under then under.Position.Y else bottom
	local height = top - base
	if height > LOW and height < HIGH then
		-- what stands on it (its bottom at this top, over it) comes down by as much as this top does
		local riders = {}
		for _, other in models do
			local ob = box(other)
			if other ~= m and ob then
				local obBottom = extent(ob)
				if math.abs(obBottom - top) < 0.4 and overlaps(b, ob) then
					table.insert(riders, other)
				end
			end
		end
		m:ScaleTo(m:GetScale() * TARGET / height)
		local newBottom, newTop = extent(b)
		m:PivotTo(m:GetPivot() + Vector3.new(0, base - newBottom, 0))
		newTop += base - newBottom
		for _, rider in riders do
			rider:PivotTo(rider:GetPivot() + Vector3.new(0, newTop - top, 0))
		end
		table.insert(
			lines,
			string.format(
				"%s at (%.0f, %.0f): %.2f -> %.2f high%s",
				m.Name,
				b.Position.X,
				b.Position.Z,
				height,
				newTop - base,
				if #riders > 0 then string.format(", %d stacked on it lowered", #riders) else ""
			)
		)
	end
end
table.insert(lines, string.format("[CoverHeights] %d cover models set to %.1f high", #lines, TARGET))
local text = table.concat(lines, "\n")
print(text)
return text
