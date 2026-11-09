-- Studio command bar / MCP: two invisible name plates on every plot sign, so the owner's name sits ON the sign
-- (09.11.2026, kill-test feedback "the name floats over the sign"). Safe to run again.
--
-- In Ice Cream Map.Plots.Plot_k.PlotKit.PlotSign:
--   NamePlate_Front   just in front of PlotSign_Face_Cream (the cream name field), its Front face outwards
--   NamePlate_Back    just behind the sign's back (the waffle), found by a ray, its Front face backwards
-- Both are thin, invisible, without collision, queries or touch. PlotService puts a SurfaceGui with the name on
-- their Front face (src/server/Services/PlotService.luau) and turns the old floating BillboardGui off.

local GAP = 0.03 -- how far a plate stands off its surface, against z-fighting
local THICK = 0.04

local made = 0
local tmp = Instance.new("Folder")
tmp.Parent = workspace
for _, plot in workspace["Ice Cream Map"].Plots:GetChildren() do
	local sign = plot:FindFirstChild("PlotKit") and plot.PlotKit:FindFirstChild("PlotSign")
	local face = sign and sign:FindFirstChild("PlotSign_Face_Cream")
	if face then
		for _, name in { "NamePlate_Front", "NamePlate_Back" } do
			if sign:FindFirstChild(name) then
				sign[name]:Destroy()
			end
		end
		local look = face.CFrame.LookVector -- the face's Front: out of the sign, towards the bridge
		local size = Vector3.new(face.Size.X, face.Size.Y, THICK)

		-- the meshes cannot be hit (CanQuery off), so the ray goes against queryable copies
		tmp:ClearAllChildren()
		for _, part in sign:GetChildren() do
			if part:IsA("MeshPart") then
				local copy = part:Clone()
				copy.CanQuery = true
				copy.Parent = tmp
			end
		end
		local only = RaycastParams.new()
		only.FilterType = Enum.RaycastFilterType.Include
		only.FilterDescendantsInstances = { tmp }
		local behind = workspace:Raycast(face.Position - look * 8, look * 8, only)

		local function plate(name, at, outwards)
			local p = Instance.new("Part")
			p.Name = name
			p.Size = size
			p.CFrame = CFrame.lookAt(at, at + outwards, Vector3.yAxis)
			p.Transparency = 1
			p.Anchored, p.CanCollide, p.CanQuery, p.CanTouch = true, false, false, false
			p.CastShadow = false
			p.Locked = true
			p.Parent = sign
		end
		plate("NamePlate_Front", face.Position + look * (face.Size.Z / 2 + GAP + THICK / 2), look)
		if behind then
			plate("NamePlate_Back", behind.Position - look * (GAP + THICK / 2), -look)
		end
		made += 1
	end
end
tmp:Destroy()
return `{made} plot signs have name plates`
