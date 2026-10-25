-- Builds a graybox pier when the place has none, so the prototype runs right after `rojo serve`.
--
-- Map contract (a hand-built or MCP-built map must follow it, then this builder stays out of the way):
--   Workspace.Pier                      Folder or Model
--   Workspace.Pier.BigSwirl.Nozzle      BasePart, scoops launch from here
--   Workspace.Pier.Deck                 BasePart, its top surface is the ground height
--   Workspace.Pier.Carts.<Name>         one Model per cart, each with
--     .ServePoint                       BasePart (invisible), where the player serves and spawns
--     .Body.Label                       optional BillboardGui with a TextLabel, shows the owner
--   Water (optional)                    any part named "Water", Water material or Terrain water: spilled scoops
--                                       that roll onto it sink (LootService); so do ones with no ground below

local Lighting = game:GetService("Lighting")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local Palette = require(ReplicatedStorage:WaitForChild("Shared"):WaitForChild("Config"):WaitForChild("Palette"))

local GrayboxService = {}

local DECK_SIZE = 200
local CART_COUNT = 10
local CART_RADIUS = 82

local function part(props: { [string]: any }): Part
	local instance = Instance.new("Part")
	instance.Anchored = true
	instance.Material = Enum.Material.SmoothPlastic
	instance.TopSurface = Enum.SurfaceType.Smooth
	instance.BottomSurface = Enum.SurfaceType.Smooth
	for key, value in props do
		instance[key] = value
	end
	return instance
end

local function buildCart(index: number, parent: Instance)
	local angle = (index - 1) / CART_COUNT * math.pi * 2
	local position = Vector3.new(math.cos(angle) * CART_RADIUS, 0, math.sin(angle) * CART_RADIUS)
	local facing = CFrame.lookAt(position, Vector3.new(0, 0, 0))

	local cart = Instance.new("Model")
	cart.Name = string.format("Cart%02d", index)

	local body = part({
		Name = "Body",
		Size = Vector3.new(6, 4, 4),
		CFrame = facing * CFrame.new(0, 3, 0),
		Color = Color3.fromHex(Palette.vanilla),
		Parent = cart,
	})
	part({
		Name = "Awning",
		Size = Vector3.new(7, 0.5, 5),
		CFrame = facing * CFrame.new(0, 7.5, 0.5),
		Color = Color3.fromHex(Palette.awning),
		Parent = cart,
	})
	for _, side in { -1, 1 } do
		part({
			Name = "Pole",
			Size = Vector3.new(0.4, 3, 0.4),
			CFrame = facing * CFrame.new(side * 3, 6.5, 0.5),
			Color = Color3.fromHex(Palette.ink),
			Parent = cart,
		})
	end

	-- ServePoint sits 5 studs in front of the cart, towards the machine, at standing height
	local servePoint = part({
		Name = "ServePoint",
		Size = Vector3.new(4, 1, 4),
		CFrame = facing * CFrame.new(0, 3, -5),
		Transparency = 1,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = cart,
	})
	local mat = part({
		Name = "ServeMat",
		Size = Vector3.new(6, 0.1, 6),
		CFrame = facing * CFrame.new(0, 1.05, -5),
		Color = Color3.fromHex(Palette.lemon),
		Transparency = 0.3,
		CanCollide = false,
		CanQuery = false,
		CanTouch = false,
		Parent = cart,
	})
	mat.Material = Enum.Material.Neon

	local label = Instance.new("BillboardGui")
	label.Name = "Label"
	label.Size = UDim2.fromOffset(160, 40)
	label.StudsOffset = Vector3.new(0, 7, 0)
	label.MaxDistance = 150
	label.Parent = body
	local text = Instance.new("TextLabel")
	text.Name = "Text"
	text.Size = UDim2.fromScale(1, 1)
	text.BackgroundTransparency = 1
	text.Font = Enum.Font.FredokaOne
	text.TextScaled = true
	text.TextColor3 = Color3.fromHex(Palette.ink)
	text.TextStrokeColor3 = Color3.new(1, 1, 1)
	text.TextStrokeTransparency = 0.2
	text.Text = "FREE CART"
	text.Parent = label

	cart.PrimaryPart = servePoint
	cart.Parent = parent
end

local function build(): Folder
	local pier = Instance.new("Folder")
	pier.Name = "Pier"

	part({
		Name = "Deck",
		Size = Vector3.new(DECK_SIZE, 2, DECK_SIZE),
		CFrame = CFrame.new(0, 0, 0),
		Color = Color3.fromHex(Palette.waffle),
		Material = Enum.Material.WoodPlanks,
		Parent = pier,
	})
	part({
		Name = "Water",
		Size = Vector3.new(800, 1, 800),
		CFrame = CFrame.new(0, -4, 0),
		Color = Color3.fromHex(Palette.sea),
		Transparency = 0.15,
		Parent = pier,
	})

	-- invisible railing so nobody walks off the graybox
	local half = DECK_SIZE / 2
	for _, wall in
		{
			{ Vector3.new(DECK_SIZE, 8, 1), Vector3.new(0, 5, half) },
			{ Vector3.new(DECK_SIZE, 8, 1), Vector3.new(0, 5, -half) },
			{ Vector3.new(1, 8, DECK_SIZE), Vector3.new(half, 5, 0) },
			{ Vector3.new(1, 8, DECK_SIZE), Vector3.new(-half, 5, 0) },
		}
	do
		part({ Name = "Railing", Size = wall[1], CFrame = CFrame.new(wall[2]), Transparency = 1, Parent = pier })
	end

	local machine = Instance.new("Model")
	machine.Name = "BigSwirl"
	part({
		Name = "Body",
		Shape = Enum.PartType.Cylinder,
		Size = Vector3.new(22, 16, 16),
		CFrame = CFrame.new(0, 12, 0) * CFrame.Angles(0, 0, math.rad(90)),
		Color = Color3.fromHex(Palette.strawberry),
		Parent = machine,
	})
	local nozzle = part({
		Name = "Nozzle",
		Shape = Enum.PartType.Ball,
		Size = Vector3.new(7, 7, 7),
		CFrame = CFrame.new(0, 26, 0),
		Color = Color3.fromHex(Palette.vanilla),
		Parent = machine,
	})
	machine.PrimaryPart = nozzle
	machine.Parent = pier

	local carts = Instance.new("Folder")
	carts.Name = "Carts"
	carts.Parent = pier
	for index = 1, CART_COUNT do
		buildCart(index, carts)
	end

	Lighting.ClockTime = 17.4 -- golden hour, long shadows make Greg's warning readable later
	pier.Parent = workspace
	return pier
end

function GrayboxService.Init()
	local pier = workspace:FindFirstChild("Pier")
	if pier then
		print("[Graybox] using the map in Workspace.Pier")
	else
		pier = build()
		print("[Graybox] no Workspace.Pier in the place, built the graybox pier")
	end

	local machine = pier:FindFirstChild("BigSwirl")
	local nozzle = machine and machine:FindFirstChild("Nozzle")
	local deck = pier:FindFirstChild("Deck")
	local carts = pier:FindFirstChild("Carts")
	if not (nozzle and deck and carts) then
		local missing = {}
		for name, found in { ["BigSwirl.Nozzle"] = nozzle, Deck = deck, Carts = carts } do
			if not found then
				table.insert(missing, name)
			end
		end
		table.sort(missing)
		error(
			`Workspace.Pier does not follow the map contract (top of GrayboxService): missing {table.concat(
				missing,
				", "
			)}. ` .. "Rename or remove that Pier to get the graybox instead."
		)
	end

	GrayboxService.pier = pier
	GrayboxService.nozzle = nozzle
	GrayboxService.groundY = deck.Position.Y + deck.Size.Y / 2
	GrayboxService.center = Vector3.new(nozzle.Position.X, GrayboxService.groundY, nozzle.Position.Z)
	GrayboxService.carts = carts:GetChildren()
	table.sort(GrayboxService.carts, function(a, b)
		return a.Name < b.Name
	end)
end

return GrayboxService
