-- Written by studio_rollout_gen.luau, do not edit. Runs in Studio (Studio MCP execute_luau or the command bar, Edit
-- mode): turns the imported rollout scoops (build_rollout.py, FBX from Desktop\roblox-assets\TowerScoops\proto2,
-- imported into the Workspace as TS_<flavor>_<LOD>) into the templates in ReplicatedStorage.TowerScoops, like
-- studio_proto.luau: the mesh, the baked maps as a SurfaceAppearance, the attribute Centre (the importer turns the FBX
-- half round the up axis, so X and Z of the report's centre flip). A flavor's old folder goes to
-- ServerStorage.TowerScoopsBefore_Proto2 (once). Flavors not imported yet are skipped. Save the place afterwards.

local ReplicatedStorage = game:GetService("ReplicatedStorage")
local ServerStorage = game:GetService("ServerStorage")

-- per flavor and LOD: ColorMap, NormalMap, RoughnessMap ids and the report's bounding box centre
local MAPS = {
	arctic_coconut = { LOD0 = { "120286219115776", "138207931710781", "88089446183454", Vector3.new(0.0130, 0.0733, 0.0216) }, LOD1 = { "77483958187396", "92043234113557", "109443166748837", Vector3.new(0.0160, 0.0669, 0.0309) } },
	birthday_cake = { LOD0 = { "103701542924460", "132700278088302", "118746865129292", Vector3.new(-0.0147, 0.0725, 0.0095) }, LOD1 = { "119250654790812", "121838509102469", "104548993644913", Vector3.new(0.0004, 0.0720, 0.0173) } },
	black_cherry = { LOD0 = { "127543138812236", "75066038143886", "108650682505996", Vector3.new(0.0099, 0.0752, 0.0798) }, LOD1 = { "77524132155384", "86047233774453", "129285012019400", Vector3.new(-0.0004, 0.0668, 0.0846) } },
	blue_raspberry = { LOD0 = { "73251479344899", "118791434443809", "125908985624402", Vector3.new(0.0005, 0.0776, -0.0509) }, LOD1 = { "102138567071570", "102734473727592", "133243676175511", Vector3.new(-0.0130, 0.0777, 0.0683) } },
	blueberry = { LOD0 = { "91210979285564", "104268202663786", "99734238654457", Vector3.new(0.0099, 0.0729, 0.0772) }, LOD1 = { "128967654480846", "126745863621891", "75876667449606", Vector3.new(-0.0013, 0.0799, 0.0130) } },
	brownie = { LOD0 = { "86706488553164", "135542550546509", "126088666962016", Vector3.new(0.0007, 0.0764, 0.0277) }, LOD1 = { "112344204241829", "83111158613443", "70708722613318", Vector3.new(-0.0018, 0.0725, 0.0253) } },
	bubblegum = { LOD0 = { "99100724462829", "93828443604322", "71552252420217", Vector3.new(-0.0231, 0.0717, -0.0021) }, LOD1 = { "122019526296929", "93160949797615", "89224798663943", Vector3.new(0.0097, 0.0739, -0.0096) } },
	caramel = { LOD0 = { "121663454062919", "138428516740067", "131902722664032", Vector3.new(0.0023, 0.0632, 0.0250) }, LOD1 = { "103741163897921", "123952668412937", "134435896757812", Vector3.new(0.0066, 0.0730, 0.0217) } },
	cheesecake = { LOD0 = { "74297063394404", "95320710266623", "112610506796166", Vector3.new(0.0023, 0.0697, 0.0007) }, LOD1 = { "76960954351064", "71333305163913", "124132744436877", Vector3.new(-0.0018, 0.0696, 0.0042) } },
	chocolate = { LOD0 = { "134112099869043", "116863871584048", "119869763078539", Vector3.new(-0.0022, 0.0697, 0.0235) }, LOD1 = { "115181201841711", "107089787271247", "132147591709052", Vector3.new(-0.0040, 0.0830, 0.0384) } },
	cinnamon_roll = { LOD0 = { "87425914229490", "107438355190148", "134755885091002", Vector3.new(-0.0002, 0.1096, -0.0006) }, LOD1 = { "100761579248389", "98000328713970", "88172289566107", Vector3.new(-0.0124, 0.0940, -0.0004) } },
	coconut = { LOD0 = { "120703843826240", "108711403950014", "138931033025073", Vector3.new(0.0030, 0.0828, 0.0088) }, LOD1 = { "92704288801492", "135911596976436", "104357669288316", Vector3.new(0.0002, 0.0680, -0.0046) } },
	coffee = { LOD0 = { "94668376153707", "80300397715844", "87068986094916", Vector3.new(0.0006, 0.0762, -0.0045) }, LOD1 = { "99016602656661", "76594853074931", "70512893239002", Vector3.new(0.0004, 0.1015, -0.0034) } },
	cotton_candy = { LOD0 = { "107147083814490", "85712436802419", "121731672649109", Vector3.new(-0.0054, 0.2288, 0.0088) }, LOD1 = { "70674352775738", "95839336962644", "91925246162212", Vector3.new(0.0054, 0.2225, -0.0002) } },
	crimson_velvet = { LOD0 = { "108624303576367", "73030073639716", "137432109015389", Vector3.new(0.0099, 0.1022, -0.0006) }, LOD1 = { "101932526523033", "97158980209037", "105487106825011", Vector3.new(0.0159, 0.0897, -0.0187) } },
	dragon_fruit = { LOD0 = { "126169879389293", "77741101274609", "107370149219994", Vector3.new(-0.0024, 0.0647, 0.0178) }, LOD1 = { "133802664335760", "135036621304148", "135923483245374", Vector3.new(-0.0050, 0.0596, 0.0188) } },
	frosted_melon = { LOD0 = { "73925613702507", "71302147798500", "108531271788322", Vector3.new(0.0054, 0.1030, 0.0659) }, LOD1 = { "82435285695978", "130638136216090", "137063706762761", Vector3.new(0.0314, 0.1163, 0.0168) } },
	grape = { LOD0 = { "115819975361075", "118551549817631", "73880455823567", Vector3.new(0.0043, 0.0739, 0.0413) }, LOD1 = { "73534505032211", "119766284117639", "80202199562914", Vector3.new(0.0312, 0.0806, -0.0112) } },
	honey = { LOD0 = { "111931659907244", "126110956577519", "125406366942769", Vector3.new(0.0028, 0.1009, 0.0040) }, LOD1 = { "139815073694867", "95704768596102", "116663507892402", Vector3.new(-0.0098, 0.0931, 0.0133) } },
	honey_blossom = { LOD0 = { "137301708437828", "125586164189303", "71966480961791", Vector3.new(0.0167, 0.1023, 0.0071) }, LOD1 = { "73898681878318", "96741712147606", "90386379741805", Vector3.new(0.0152, 0.0951, 0.0130) } },
	lemon = { LOD0 = { "124120475866311", "132971079875548", "97928147185350", Vector3.new(0.0129, 0.0682, 0.0022) }, LOD1 = { "109084355544441", "75864018223340", "106738237579624", Vector3.new(0.0083, 0.0843, 0.0133) } },
	lime = { LOD0 = { "93522679803459", "87940980814114", "99914294230617", Vector3.new(-0.0126, 0.0754, 0.0155) }, LOD1 = { "72262222198728", "129254893558519", "77545797132572", Vector3.new(-0.0179, 0.0650, 0.0105) } },
	mango = { LOD0 = { "119520140017216", "132660976017580", "71226317728111", Vector3.new(-0.0036, 0.0708, 0.0188) }, LOD1 = { "74045103349931", "93208191787300", "96360362561306", Vector3.new(-0.0089, 0.0581, 0.0057) } },
	maple_syrup = { LOD0 = { "131250848652017", "125888918601465", "106167929233137", Vector3.new(-0.0031, 0.1079, 0.0134) }, LOD1 = { "89034425832961", "122011017872842", "85878292640083", Vector3.new(0.0041, 0.0979, -0.0083) } },
	marzipan = { LOD0 = { "100241146137488", "103040282597983", "90083053394449", Vector3.new(-0.0131, 0.1089, 0.0042) }, LOD1 = { "136757854330480", "119713124940441", "124519272577073", Vector3.new(-0.0207, 0.0986, 0.0108) } },
	midnight_berry = { LOD0 = { "71255865162053", "85196586621071", "122080117093596", Vector3.new(0.0418, 0.1081, 0.0713) }, LOD1 = { "95157442125312", "99371086169385", "100806380413527", Vector3.new(0.0618, 0.1179, 0.0013) } },
	mint = { LOD0 = { "90130709708633", "136573290402987", "95424069747499", Vector3.new(0.0155, 0.0775, 0.0302) }, LOD1 = { "135724282720005", "132864674080759", "101248091384868", Vector3.new(0.0130, 0.0733, 0.0416) } },
	mocha = { LOD0 = { "111894571034094", "104830757148806", "119405579683149", Vector3.new(0.0066, 0.2663, -0.0086) }, LOD1 = { "82219289880181", "98644568372767", "121926571974422", Vector3.new(0.0054, 0.2876, -0.0071) } },
	mystic_plum = { LOD0 = { "83583520480870", "138594269864024", "97435900092850", Vector3.new(-0.0087, 0.1100, 0.0453) }, LOD1 = { "139101480942024", "78235365157379", "80043913293319", Vector3.new(0.0032, 0.0958, 0.0458) } },
	orange = { LOD0 = { "98657403486937", "109727372273703", "123448681720843", Vector3.new(-0.0013, 0.0701, -0.0030) }, LOD1 = { "105148520002345", "112650723336952", "124100512660091", Vector3.new(0.0115, 0.0751, -0.0276) } },
	passion_fruit = { LOD0 = { "85858884292976", "80636626483804", "96690900404327", Vector3.new(-0.0032, 0.1060, 0.0166) }, LOD1 = { "129151508722347", "125552326585641", "129905569779323", Vector3.new(-0.0200, 0.0951, -0.0004) } },
	peach = { LOD0 = { "111470695531177", "83556658090410", "99914344229691", Vector3.new(0.0007, 0.0688, 0.0025) }, LOD1 = { "96351575288578", "71560092498344", "130516565639993", Vector3.new(0.0099, 0.0615, -0.0030) } },
	pineapple = { LOD0 = { "96129420038654", "77744761239703", "100642630780184", Vector3.new(0.0167, 0.0802, 0.0060) }, LOD1 = { "116715210745477", "113227508564252", "108948425877363", Vector3.new(0.0207, 0.0765, 0.0040) } },
	pistachio = { LOD0 = { "73822721785240", "75724999502242", "81961724348385", Vector3.new(-0.0217, 0.0851, -0.0099) }, LOD1 = { "107818918282777", "108416136352104", "88542602878832", Vector3.new(-0.0242, 0.0793, -0.0197) } },
	pistachio_cream = { LOD0 = { "138711372283943", "82681380268877", "130385988645016", Vector3.new(-0.0100, 0.2074, 0.0082) }, LOD1 = { "120632604540768", "109935196396656", "135252295989523", Vector3.new(-0.0219, 0.1115, -0.0036) } },
	pomegranate = { LOD0 = { "90111132108032", "129209031378679", "84695852981772", Vector3.new(-0.0081, 0.0805, 0.0091) }, LOD1 = { "113253408454533", "123506774770578", "106265016673324", Vector3.new(-0.0075, 0.0864, 0.0130) } },
	raspberry = { LOD0 = { "132266129440489", "81056249897652", "84929432085251", Vector3.new(0.0916, 0.0696, 0.1197) }, LOD1 = { "108076408786404", "102371511087910", "96745395690178", Vector3.new(-0.0095, 0.0659, 0.1069) } },
	red_velvet = { LOD0 = { "136833142162973", "112720417968604", "89075428424620", Vector3.new(0.0001, 0.2454, -0.0071) }, LOD1 = { "103226492669096", "113257657976400", "115791173544278", Vector3.new(0.0315, 0.2585, -0.0116) } },
	salted_caramel = { LOD0 = { "83462751317318", "100668684261829", "102533189018760", Vector3.new(0.0125, 0.1053, 0.0151) }, LOD1 = { "78844122011404", "136219149648642", "74988586476576", Vector3.new(0.0146, 0.0901, 0.0050) } },
	sapphire_cream = { LOD0 = { "115207225441452", "79248072834912", "118722627357993", Vector3.new(0.0069, 0.0655, -0.0074) }, LOD1 = { "103662695451161", "92489752785019", "101535754499363", Vector3.new(0.0001, 0.0691, -0.0150) } },
	stracciatella = { LOD0 = { "86441825657203", "90539383508178", "122374907923599", Vector3.new(0.0061, 0.0790, -0.0081) }, LOD1 = { "118098065624395", "79039644802167", "95962935545860", Vector3.new(0.0083, 0.0855, -0.0063) } },
	strawberry = { LOD0 = { "107116077920063", "135463596634219", "127115809696673", Vector3.new(0.0001, 0.0773, 0.0220) }, LOD1 = { "85021745002045", "106328263825077", "82777832844603", Vector3.new(0.0107, 0.0949, 0.0097) } },
	tiramisu = { LOD0 = { "100243566837901", "91258848617399", "118040092259331", Vector3.new(-0.0118, 0.2374, 0.0191) }, LOD1 = { "139612545863264", "85215124413671", "109873422659859", Vector3.new(-0.0306, 0.2491, 0.0259) } },
	velvet_dream = { LOD0 = { "120405517406386", "109861722338324", "110389426882996", Vector3.new(0.0157, 0.2569, -0.0054) }, LOD1 = { "87080583572383", "96329836829041", "86133327068322", Vector3.new(0.0363, 0.2622, -0.0133) } },
	velvet_mocha = { LOD0 = { "73561498132854", "118575889395061", "110959798761734", Vector3.new(0.0202, 0.2189, -0.0043) }, LOD1 = { "72016303524997", "74825640026763", "84137485331133", Vector3.new(0.0338, 0.0990, -0.0261) } },
	watermelon = { LOD0 = { "83307095320635", "104366305265186", "97033146484152", Vector3.new(-0.0019, 0.0733, 0.0125) }, LOD1 = { "82628118904014", "93567966104573", "134790361802101", Vector3.new(0.0118, 0.0843, 0.0114) } },
	white_chocolate = { LOD0 = { "90896304553651", "114728364985481", "139706969959567", Vector3.new(0.0015, 0.0745, -0.0102) }, LOD1 = { "72734503100318", "82980605698373", "118519194628021", Vector3.new(0.0218, 0.0682, -0.0121) } },
}

local found = {}
for _, item in workspace:GetDescendants() do
	if item:IsA("MeshPart") and string.match(item.Name, "^TS_") then
		found[item.Name] = item
	end
end
local root = ReplicatedStorage:WaitForChild("TowerScoops")
local before = ServerStorage:FindFirstChild("TowerScoopsBefore_Proto2")
if not before then
	before = Instance.new("Folder")
	before.Name = "TowerScoopsBefore_Proto2"
	before.Parent = ServerStorage
end
local made, skipped = {}, {}
for flavorId, lods in MAPS do
	local sources = { LOD0 = found[`TS_{flavorId}_LOD0`], LOD1 = found[`TS_{flavorId}_LOD1`] }
	if not sources.LOD0 or not sources.LOD1 then
		table.insert(skipped, flavorId)
		continue
	end
	local folder = Instance.new("Folder")
	folder.Name = flavorId
	for _, lod in { "LOD0", "LOD1" } do
		local source = sources[lod]
		local maps = lods[lod]
		local part = source:Clone()
		for _, child in part:GetChildren() do
			child:Destroy()
		end
		part.Name = lod
		part.Anchored = true
		part.CanCollide = false
		part.CanQuery = false
		part.CanTouch = false
		part.Massless = true
		part.Material = Enum.Material.SmoothPlastic
		part.CFrame = CFrame.identity
		local c = maps[4]
		part:SetAttribute("Centre", -Vector3.new(-c.X, c.Y, -c.Z))
		local look = Instance.new("SurfaceAppearance")
		look.ColorMap = "rbxassetid://" .. maps[1]
		look.NormalMap = "rbxassetid://" .. maps[2]
		look.RoughnessMap = "rbxassetid://" .. maps[3]
		look.AlphaMode = Enum.AlphaMode.Overlay
		look.Parent = part
		part.Parent = folder
		local model = source:FindFirstAncestorOfClass("Model")
		if model and model.Parent == workspace then
			model:Destroy()
		else
			source:Destroy()
		end
	end
	local old = root:FindFirstChild(flavorId)
	if old then
		if before:FindFirstChild(flavorId) then
			old:Destroy()
		else
			old.Parent = before
		end
	end
	folder.Parent = root
	table.insert(made, flavorId)
end
table.sort(made)
table.sort(skipped)
return `made {#made}: {table.concat(made, ", ")}; skipped {#skipped}: {table.concat(skipped, ", ")}`
