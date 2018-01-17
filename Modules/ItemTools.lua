-- Path of Building
--
-- Module: Item Tools
-- Various functions for dealing with items.
--
local launch = ...

local t_insert = table.insert
local t_remove = table.remove
local m_min = math.min
local m_max = math.max
local m_floor = math.floor

local dmgTypeList = {"Physical", "Lightning", "Cold", "Fire", "Chaos"}

itemLib = { }

-- Apply range value (0 to 1) to a modifier that has a range: (x to x) or (x-x to x-x)
function itemLib.applyRange(line, range)
	return line:gsub("%((%d+)%-(%d+) to (%d+)%-(%d+)%)", "(%1-%2) to (%3-%4)")
		:gsub("(%+?)%((%-?%d+) to (%d+)%)", "%1(%2-%3)")
		:gsub("(%+?)%((%-?%d+)%-(%d+)%)", 
		function(plus, min, max) 
			local numVal = m_floor(tonumber(min) + range * (tonumber(max) - tonumber(min)) + 0.5)
			if numVal < 0 then
				if plus == "+" then
					plus = ""
				end
			end
			return plus .. tostring(numVal)
		end)
		:gsub("%((%d+%.?%d*)%-(%d+%.?%d*)%)",
		function(min, max) 
			local numVal = m_floor((tonumber(min) + range * (tonumber(max) - tonumber(min))) * 10 + 0.5) / 10
			return tostring(numVal) 
		end)
		:gsub("%-(%d+%%) increased", function(num) return num.." reduced" end)
end

-- Clean item text by removing or replacing unsupported or redundant characters or sequences
function itemLib.sanitiseItemText(text)
	-- Something something unicode support something grumble
	return text:gsub("^%s+",""):gsub("%s+$",""):gsub("\r\n","\n"):gsub("%b<>",""):gsub("�","-"):gsub("\226\128\147","-"):gsub("\226\136\146","-"):gsub("�","o"):gsub("\195\182","o"):gsub("[\128-\255]","?")
end

function itemLib.formatModLine(modLine, dbMode)
	local line = (not dbMode and modLine.range and itemLib.applyRange(modLine.line, modLine.range)) or modLine.line
	if line:match("^%+?0%%? ") or line:match(" %+?0%%? ") or line:match(" 0%-0 ") or line:match(" 0 to 0 ") then -- Hack to hide 0-value modifiers
		return
	end
	local colorCode
	if modLine.extra then
		colorCode = colorCodes.UNSUPPORTED
		if launch.devModeAlt then
			line = line .. "   ^1'" .. modLine.extra .. "'"
		end
	else
		colorCode = (modLine.crafted and colorCodes.CRAFTED) or (modLine.custom and colorCodes.CUSTOM) or colorCodes.MAGIC
	end
	return colorCode..line
end

-- Make an item from raw data
function itemLib.makeItemFromRaw(targetVersion, raw)
	local newItem = {
		targetVersion = targetVersion,
		raw = itemLib.sanitiseItemText(raw)
	}
	itemLib.parseItemRaw(newItem)
	if newItem.baseName then
		return newItem
	end
end

-- Parse raw item data and extract item name, base type, quality, and modifiers
function itemLib.parseItemRaw(item)
	local verData = data[item.targetVersion]
	item.name = "?"
	item.rarity = "UNIQUE"
	item.quality = nil
	item.rawLines = { }
	for line in string.gmatch(item.raw .. "\r\n", "([^\r\n]*)\r?\n") do
		line = line:gsub("^%s+",""):gsub("%s+$","")
		if #line > 0 then
			t_insert(item.rawLines, line)
		end
	end
	local mode = "WIKI"
	local l = 1
	if item.rawLines[l] then
		local rarity = item.rawLines[l]:match("^Rarity: (%a+)")
		if rarity then
			mode = "GAME"
			if colorCodes[rarity:upper()] then
				item.rarity = rarity:upper()
			end
			if item.rarity == "NORMAL" then
				-- Hack for relics
				for _, line in ipairs(item.rawLines) do
					if line == "Relic Unique" then
						item.rarity = "RELIC"
						break
					end
				end
			end
			l = l + 1
		end
	end
	if item.rawLines[l] then
		item.name = item.rawLines[l]
		l = l + 1
	end
	item.namePrefix = ""
	item.nameSuffix = ""
	if item.rarity == "NORMAL" or item.rarity == "MAGIC" then
		for baseName, baseData in pairs(verData.itemBases) do
			local s, e = item.name:find(baseName, 1, true)
			if s then
				item.baseName = baseName
				item.namePrefix = item.name:sub(1, s - 1)
				item.nameSuffix = item.name:sub(e + 1)
				item.type = baseData.type
				break
			end
		end
		if not item.baseName then
			local s, e = item.name:find("Two-Toned Boots", 1, true)
			if s then
				-- Hack for Two-Toned Boots
				item.baseName = "Two-Toned Boots (Armour/Energy Shield)"
				item.namePrefix = item.name:sub(1, s - 1)
				item.nameSuffix = item.name:sub(e + 1)
				item.type = "Boots"
			end
		end
		item.name = item.name:gsub(" %(.+%)","")
	elseif item.rawLines[l] and not item.rawLines[l]:match("^%-") then
		if item.rawLines[l] == "Two-Toned Boots" then
			item.rawLines[l] = "Two-Toned Boots (Armour/Energy Shield)"
		end
		if verData.itemBases[item.rawLines[l]] then
			item.baseName = item.rawLines[l]
			item.title = item.name
			item.name = item.title .. ", " .. item.baseName:gsub(" %(.+%)","")
			item.type = verData.itemBases[item.baseName].type
			l = l + 1
		end
	end
	item.base = verData.itemBases[item.baseName]
	item.sockets = { }
	item.modLines = { }
	item.implicitLines = 0
	item.buffLines = 0
	if item.base then
		item.affixes = (item.base.subType and verData.itemMods[item.base.type..item.base.subType])
			or verData.itemMods[item.base.type] 
			or verData.itemMods.Item
		item.enchantments = verData.enchantments[item.base.type]
		item.corruptable = item.base.type ~= "Flask"
		item.shaperElderTags = data.specialBaseTags[item.type]
		item.canBeShaperElder = (item.rarity ~= "UNIQUE" and item.rarity ~= "RELIC") and item.shaperElderTags
	end
	item.variantList = nil
	item.prefixes = { }
	item.suffixes = { }
	item.requirements = { }
	if item.base then
		item.requirements.str = item.base.req.str or 0
		item.requirements.dex = item.base.req.dex or 0
		item.requirements.int = item.base.req.int or 0
		local maxReq = m_max(item.requirements.str, item.requirements.dex, item.requirements.int)
		item.defaultSocketColor = (maxReq == item.requirements.dex and "G") or (maxReq == item.requirements.int and "B") or "R"
	end
	local importedLevelReq
	local flaskBuffLines = { }
	if item.base and item.base.flask and item.base.flask.buff then
		item.buffLines = #item.base.flask.buff
		for _, line in ipairs(item.base.flask.buff) do
			flaskBuffLines[line] = true
			local modList, extra = modLib.parseMod[item.targetVersion](line)
			t_insert(item.modLines, { line = line, extra = extra, modList = modList or { }, buff = true })
		end
	end
	local gameModeStage = "FINDIMPLICIT"
	local gameModeSection = 1
	local foundExplicit
	while item.rawLines[l] do
		local line = item.rawLines[l]
		if flaskBuffLines[line] then
			flaskBuffLines[line] = nil
		elseif line == "--------" then
			gameModeSection = gameModeSection + 1
			if gameModeStage == "IMPLICIT" then
				item.implicitLines = #item.modLines - item.buffLines
				gameModeStage = "FINDEXPLICIT"
			elseif gameModeStage == "EXPLICIT" then
				gameModeStage = "DONE"
			end
		elseif line == "Corrupted" then
			item.corrupted = true
		elseif line == "Shaper Item" then
			item.shaper = true
		elseif line == "Elder Item" then
			item.elder = true
		else
			local specName, specVal = line:match("^([%a ]+): (%x+)$")
			if not specName then
				specName, specVal = line:match("^([%a ]+): %+?([%d%-%.]+)")
				if not tonumber(specVal) then
					specName = nil
				end
			end
			if not specName then
				specName, specVal = line:match("^([%a ]+): (.+)$")
			end
			if not specName then
				specName, specVal = line:match("^(Requires) (.+)$")
			end
			if specName then
				if specName == "Unique ID" then
					item.uniqueID = specVal
				elseif specName == "Item Level" then
					item.itemLevel = tonumber(specVal)
				elseif specName == "Quality" then
					item.quality = tonumber(specVal)
				elseif specName == "Sockets" then
					local group = 0
					for c in specVal:gmatch(".") do
						if c:match("[RGBWA]") then
							t_insert(item.sockets, { color = c, group = group })
						elseif c == " " then
							group = group + 1
						end
					end
				elseif specName == "Radius" and item.type == "Jewel" then
					for index, data in pairs(verData.jewelRadius) do
						if specVal:match("^%a+") == data.label then
							item.jewelRadiusIndex = index
							break
						end
					end
				elseif specName == "Limited to" and item.type == "Jewel" then
					item.limit = tonumber(specVal)
				elseif specName == "Variant" then
					if not item.variantList then
						item.variantList = { }
					end
					local ver, name = specVal:match("{([%w_]+)}(.+)")
					if ver then
						t_insert(item.variantList, name)
						if ver == item.targetVersion then
							item.defaultVariant = #item.variantList
						end
					else
						t_insert(item.variantList, specVal)
					end
				elseif specName == "Requires" then
					item.requirements.level = tonumber(specVal:match("Level (%d+)"))
				elseif specName == "Level" then
					-- Requirements from imported items can't always be trusted
					importedLevelReq = tonumber(specVal)
				elseif specName == "LevelReq" then
					item.requirements.level = tonumber(specVal)
				elseif specName == "Has Alt Variant" then
					item.hasAltVariant = true
				elseif specName == "Selected Variant" then
					item.variant = tonumber(specVal)
				elseif specName == "Selected Alt Variant" then
					item.variantAlt = tonumber(specVal)
				elseif specName == "League" then
					item.league = specVal
				elseif specName == "Crafted" then
					item.crafted = true
				elseif specName == "Prefix" then
					local range, affix = specVal:match("{range:([%d.]+)}(.+)")
					t_insert(item.prefixes, {
						modId = affix or specVal,
						range = tonumber(range),
					})
				elseif specName == "Suffix" then
					local range, affix = specVal:match("{range:([%d.]+)}(.+)")
					t_insert(item.suffixes, {
						modId = affix or specVal,
						range = tonumber(range),
					})
				elseif specName == "Implicits" then
					item.implicitLines = tonumber(specVal) or 0
					gameModeStage = "EXPLICIT"
				elseif specName == "Unreleased" then
					item.unreleased = (specVal == "true")
				elseif specName == "Evasion Rating" then
					if item.baseName == "Two-Toned Boots (Armour/Energy Shield)" then
						-- Another hack for Two-Toned Boots
						item.baseName = "Two-Toned Boots (Armour/Evasion)"
						item.base = verData.itemBases[item.baseName]
					end
				elseif specName == "Energy Shield" then
					if item.baseName == "Two-Toned Boots (Armour/Evasion)" then
						-- Yet another hack for Two-Toned Boots
						item.baseName = "Two-Toned Boots (Evasion/Energy Shield)"
						item.base = verData.itemBases[item.baseName]
					end
				end
			end
			if line == "Prefixes:" then
				foundExplicit = true
				gameModeStage = "EXPLICIT"
			end
			if not specName or foundExplicit then
				local varSpec = line:match("{variant:([%d,]+)}")
				local variantList
				if varSpec then
					variantList = { }
					for varId in varSpec:gmatch("%d+") do
						variantList[tonumber(varId)] = true
					end
				end
				local rangeSpec = line:match("{range:([%d.]+)}")
				local crafted = line:match("{crafted}")
				local custom = line:match("{custom}")
				line = line:gsub("%b{}", "")
				local rangedLine
				if line:match("%(%d+%-%d+ to %d+%-%d+%)") or line:match("%(%-?[%d%.]+ to %-?[%d%.]+%)") or line:match("%(%-?[%d%.]+%-[%d%.]+%)") then
					rangedLine = itemLib.applyRange(line, 1)
				end
				local modList, extra = modLib.parseMod[item.targetVersion](rangedLine or line)
				if (not modList or extra) and item.rawLines[l+1] then
					-- Try to combine it with the next line
					local combLine = line.." "..item.rawLines[l+1]
					if combLine:match("%(%d+%-%d+ to %d+%-%d+%)") or combLine:match("%(%-?[%d%.]+ to %-?[%d%.]+%)") or combLine:match("%(%-?[%d%.]+%-[%d%.]+%)") then
						rangedLine = itemLib.applyRange(combLine, 1)
					end
					modList, extra = modLib.parseMod[item.targetVersion](rangedLine or combLine, true)
					if modList and not extra then
						line = line.."\n"..item.rawLines[l+1]
						l = l + 1
					else
						modList, extra = modLib.parseMod[item.targetVersion](rangedLine or line)
					end
				end
				if modList then
					t_insert(item.modLines, { line = line, extra = extra, modList = modList, variantList = variantList, crafted = crafted, custom = custom, range = rangedLine and (tonumber(rangeSpec) or 0.5) })
					if mode == "GAME" then
						if gameModeStage == "FINDIMPLICIT" then
							gameModeStage = "IMPLICIT"
						elseif gameModeStage == "FINDEXPLICIT" then
							foundExplicit = true
							gameModeStage = "EXPLICIT"
						elseif gameModeStage == "EXPLICIT" then
							foundExplicit = true
						end
					else
						foundExplicit = true
					end
				elseif mode == "GAME" then
					if gameModeStage == "IMPLICIT" or gameModeStage == "EXPLICIT" then
						t_insert(item.modLines, { line = line, extra = line, modList = { }, variantList = variantList, crafted = crafted, custom = custom })
					elseif gameModeStage == "FINDEXPLICIT" then
						gameModeStage = "DONE"
					end
				elseif foundExplicit then
					t_insert(item.modLines, { line = line, extra = line, modList = { }, variantList = variantList, crafted = crafted, custom = custom })
				end
			end
		end
		l = l + 1
	end
	if item.base and not item.requirements.level then
		if importedLevelReq and #item.sockets == 0 then
			-- Requirements on imported items can only be trusted for items with no sockets
			item.requirements.level = importedLevelReq
		else
			item.requirements.level = item.base.req.level
		end
	end
	if item.base and item.base.implicit then
		if item.implicitLines == 0 then
			item.implicitLines = 1 + #item.base.implicit:gsub("[^\n]","")
		end
	elseif mode == "GAME" and not foundExplicit then
		item.implicitLines = 0
	end
	item.affixLimit = 0
	if item.crafted then
		if not item.affixes then 
			item.crafted = false
		elseif item.rarity == "MAGIC" then
			item.affixLimit = 2
		elseif item.rarity == "RARE" then
			item.affixLimit = (item.type == "Jewel" and 4 or 6)
		else
			item.crafted = false
		end
		if item.crafted then
			for _, list in ipairs({item.prefixes,item.suffixes}) do
				for i = 1, item.affixLimit/2 do
					if not list[i] then
						list[i] = { modId = "None" }
					elseif list[i].modId ~= "None" and not item.affixes[list[i].modId] then
						for modId, mod in pairs(item.affixes) do
							if list[i].modId == mod.affix then
								list[i].modId = modId
								break
							end
						end
						if not item.affixes[list[i].modId] then
							list[i].modId = "None"
						end
					end
				end
			end
		end
	end
	if item.base and item.base.socketLimit then
		if #item.sockets == 0 then
			for i = 1, item.base.socketLimit do
				t_insert(item.sockets, {
					color = item.defaultSocketColor,
					group = 0,
				})
			end
		end
	end
	item.abyssalSocketCount = 0
	if item.variantList then
		item.variant = m_min(#item.variantList, item.variant or item.defaultVariant or #item.variantList)
		if item.hasAltVariant then
			item.variantAlt = m_min(#item.variantList, item.variantAlt or item.defaultVariant or #item.variantList)
		end
	end
	if not item.quality then
		itemLib.normaliseQuality(item)
	end
	itemLib.buildItemModList(item)
end

function itemLib.normaliseQuality(item)
	if item.base and (item.base.armour or item.base.weapon or item.base.flask) then
		if not item.quality then
			item.quality = item.corrupted and 0 or 20 
		elseif not item.uniqueID and not item.corrupted then
			item.quality = 20
		end
	end	
end

function itemLib.getModSpawnWeight(item, mod, extraTags)
	if item.base then
		for i, key in ipairs(mod.weightKey) do
			if item.base.tags[key] or (extraTags and extraTags[key]) or (item.shaperElderTags and (item.shaper and item.shaperElderTags.shaper == key) or (item.elder and item.shaperElderTags.elder == key)) then
				return mod.weightVal[i]
			end
		end
	end
	return 0
end

-- Create raw item data for given item
function itemLib.createItemRaw(item)
	local rawLines = { }
	t_insert(rawLines, "Rarity: "..item.rarity)
	if item.title then
		t_insert(rawLines, item.title)
		t_insert(rawLines, item.baseName)
	else
		t_insert(rawLines, (item.namePrefix or "")..item.baseName..(item.nameSuffix or ""))
	end
	if item.uniqueID then
		t_insert(rawLines, "Unique ID: "..item.uniqueID)
	end
	if item.league then
		t_insert(rawLines, "League: "..item.league)
	end
	if item.unreleased then
		t_insert(rawLines, "Unreleased: true")
	end
	if item.shaper then
		t_insert(rawLines, "Shaper Item")
	end
	if item.elder then
		t_insert(rawLines, "Elder Item")
	end
	if item.crafted then
		t_insert(rawLines, "Crafted: true")
		for i, affix in ipairs(item.prefixes or { }) do
			t_insert(rawLines, "Prefix: "..(affix.range and ("{range:"..round(affix.range,3).."}") or "")..affix.modId)
		end
		for i, affix in ipairs(item.suffixes or { }) do
			t_insert(rawLines, "Suffix: "..(affix.range and ("{range:"..round(affix.range,3).."}") or "")..affix.modId)
		end
	end
	if item.itemLevel then
		t_insert(rawLines, "Item Level: "..item.itemLevel)
	end
	if item.variantList then
		for _, variantName in ipairs(item.variantList) do
			t_insert(rawLines, "Variant: "..variantName)
		end
		t_insert(rawLines, "Selected Variant: "..item.variant)
		if item.hasAltVariant then
			t_insert(rawLines, "Has Alt Variant: true")
			t_insert(rawLines, "Selected Alt Variant: "..item.variantAlt)
		end
	end
	if item.quality then
		t_insert(rawLines, "Quality: "..item.quality)
	end
	if item.sockets and #item.sockets > 0 then
		local line = "Sockets: "
		for i, socket in pairs(item.sockets) do
			line = line .. socket.color
			if item.sockets[i+1] then
				line = line .. (socket.group == item.sockets[i+1].group and "-" or " ")
			end
		end
		t_insert(rawLines, line)
	end
	if item.requirements and item.requirements.level then
		t_insert(rawLines, "LevelReq: "..item.requirements.level)
	end
	if item.jewelRadiusIndex then
		t_insert(rawLines, "Radius: "..data.jewelRadius[item.jewelRadiusIndex].label)
	end
	if item.limit then
		t_insert(rawLines, "Limited to: "..item.limit)
	end
	t_insert(rawLines, "Implicits: "..item.implicitLines)
	for _, modLine in ipairs(item.modLines) do
		if not modLine.buff then
			local line = modLine.line
			if modLine.range then
				line = "{range:"..round(modLine.range,3).."}" .. line
			end
			if modLine.crafted then
				line = "{crafted}" .. line
			end
			if modLine.custom then
				line = "{custom}" .. line
			end
			if modLine.variantList then
				local varSpec
				for varId in pairs(modLine.variantList) do
					varSpec = (varSpec and varSpec.."," or "") .. varId
				end
				line = "{variant:"..varSpec.."}"..line
			end
			t_insert(rawLines, line)
		end
	end
	if item.corrupted then
		t_insert(rawLines, "Corrupted")
	end
	return table.concat(rawLines, "\n")
end

-- Rebuild explicit modifiers using the item's affixes
function itemLib.craftItem(item)
	local custom = { }
	for l = item.buffLines + item.implicitLines + 1, #item.modLines do
		local modLine = item.modLines[l]
		if modLine.custom or modLine.crafted then
			t_insert(custom, modLine)
		end
		item.modLines[l] = nil
	end
	item.namePrefix = ""
	item.nameSuffix = ""
	item.requirements.level = item.base.req.level
	local statOrder = { }
	for _, list in ipairs({item.prefixes,item.suffixes}) do
		for i = 1, item.affixLimit/2 do
			local affix = list[i]
			if not affix then
				list[i] = { modId = "None" }
			end
			local mod = item.affixes[affix.modId]
			if mod then
				if mod.type == "Prefix" then
					item.namePrefix = mod.affix .. " "
				elseif mod.type == "Suffix" then
					item.nameSuffix = " " .. mod.affix
				end
				item.requirements.level = m_max(item.requirements.level or 0, m_floor(mod.level * 0.8))
				for i, line in ipairs(mod) do
					line = itemLib.applyRange(line, affix.range or 0.5)
					local order = mod.statOrder[i]
					if statOrder[order] then
						-- Combine stats
						local start = 1
						statOrder[order].line = statOrder[order].line:gsub("%d+", function(num)
							local s, e, other = line:find("(%d+)", start)
							start = e + 1
							return tonumber(num) + tonumber(other)
						end)
					else
						local modLine = { line = line, order = order }
						for l = item.buffLines + item.implicitLines + 1, #item.modLines + 1 do
							if not item.modLines[l] or item.modLines[l].order > order then
								t_insert(item.modLines, l, modLine)
								break
							end
						end
						statOrder[order] = modLine
					end	
				end
			end
		end
	end
	for _, line in ipairs(custom) do
		t_insert(item.modLines, line)
	end
	item.raw = itemLib.createItemRaw(item)
	itemLib.parseItemRaw(item)
end

function itemLib.checkModLineVariant(item, modLine)
	return not modLine.variantList 
		or modLine.variantList[item.variant]
		or (item.hasAltVariant and modLine.variantList[item.variantAlt])
end

-- Return the name of the slot this item is equipped in
function itemLib.getPrimarySlotForItem(item)
	if item.base.weapon then
		return "Weapon 1"
	elseif item.type == "Quiver" or item.type == "Shield" then
		return "Weapon 2"
	elseif item.type == "Ring" then
		return "Ring 1"
	elseif item.type == "Flask" then
		return "Flask 1"
	else
		return item.type
	end
end

-- Add up local modifiers, and removes them from the modifier list
-- To be considered local, a modifier must be an exact flag match, and cannot have any tags (e.g conditions, multipliers)
-- Only the InSlot tag is allowed (for Adds x to x X Damage in X Hand modifiers)
local function sumLocal(modList, name, type, flags)
	local result
	if type == "FLAG" then
		result = false
	else
		result = 0
	end
	local i = 1
	while modList[i] do
		local mod = modList[i]
		if mod.name == name and mod.type == type and mod.flags == flags and mod.keywordFlags == 0 and (not mod[1] or mod[1].type == "InSlot") then
			if type == "FLAG" then
				result = result or mod.value
			else	
				result = result + mod.value
			end
			t_remove(modList, i)
		else
			i = i + 1
		end
	end
	return result
end

-- Build list of modifiers for an item in a given slot number (1 or 2) while applying local modifers and adding quality
function itemLib.buildItemModListForSlotNum(item, baseList, slotNum)
	local slotName = itemLib.getPrimarySlotForItem(item)
	if slotNum == 2 then
		slotName = slotName:gsub("1", "2")
	end
	local modList = common.New("ModList")
	for _, baseMod in ipairs(baseList) do
		local mod = copyTable(baseMod)
		local add = true
		for _, tag in ipairs(mod) do
			if tag.type == "SlotNumber" or tag.type == "InSlot" then
				if tag.num ~= slotNum then
					add = false
					break
				end
			end
			for k, v in pairs(tag) do
				if type(v) == "string" then
					tag[k] = v:gsub("{SlotName}", slotName)
							  :gsub("{Hand}", (slotNum == 1) and "MainHand" or "OffHand")
				end
			end
		end
		if add then
			mod.sourceSlot = slotName
			modList:AddMod(mod)
		end
	end
	if #item.sockets > 0 then
		local multiName = {
			R = "Multiplier:RedSocketIn"..slotName,
			G = "Multiplier:GreenSocketIn"..slotName,
			B = "Multiplier:BlueSocketIn"..slotName,
			W = "Multiplier:WhiteSocketIn"..slotName,
		}
		for _, socket in ipairs(item.sockets) do
			if multiName[socket.color] then
				modList:NewMod(multiName[socket.color], "BASE", 1, "Item Sockets")
			end
		end
	end
	if item.base.weapon then
		local weaponData = { }
		item.weaponData[slotNum] = weaponData
		weaponData.type = item.base.type
		weaponData.name = item.name
		weaponData.AttackSpeedInc = sumLocal(modList, "Speed", "INC", ModFlag.Attack)
		weaponData.AttackRate = round(item.base.weapon.AttackRateBase * (1 + weaponData.AttackSpeedInc / 100), 2)
		for _, dmgType in pairs(dmgTypeList) do
			local min = (item.base.weapon[dmgType.."Min"] or 0) + sumLocal(modList, dmgType.."Min", "BASE", 0)
			local max = (item.base.weapon[dmgType.."Max"] or 0) + sumLocal(modList, dmgType.."Max", "BASE", 0)
			if dmgType == "Physical" then
				local physInc = sumLocal(modList, "PhysicalDamage", "INC", 0)
				min = round(min * (1 + (physInc + item.quality) / 100))
				max = round(max * (1 + (physInc + item.quality) / 100))
			end
			if min > 0 and max > 0 then
				weaponData[dmgType.."Min"] = min
				weaponData[dmgType.."Max"] = max
				local dps = (min + max) / 2 * weaponData.AttackRate
				weaponData[dmgType.."DPS"] = dps
				if dmgType ~= "Physical" and dmgType ~= "Chaos" then
					weaponData.ElementalDPS = (weaponData.ElementalDPS or 0) + dps
				end
			end
		end
		weaponData.CritChance = round(item.base.weapon.CritChanceBase * (1 + sumLocal(modList, "CritChance", "INC", 0) / 100), 2)
		for _, value in ipairs(modList:Sum("LIST", nil, "WeaponData")) do
			weaponData[value.key] = value.value
		end
		weaponData.AccuracyInc = sumLocal(modList, "Accuracy", "INC", 0)
		if weaponData.AccuracyInc > 0 then
			modList:NewMod("Accuracy", "MORE", weaponData.AccuracyInc, item.modSource, { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" })
		end
		if data[item.targetVersion].weaponTypeInfo[item.base.type].range then
			weaponData.range = data[item.targetVersion].weaponTypeInfo[item.base.type].range + sumLocal(modList, "WeaponRange", "BASE", 0)
		end
		for _, mod in ipairs(modList) do
			-- Convert accuracy, L/MGoH and PAD Leech modifiers to local
			if (
				(mod.name == "Accuracy" and mod.flags == 0) or
				((mod.name == "LifeOnHit" or mod.name == "ManaOnHit") and mod.flags == ModFlag.Attack) or
				((mod.name == "PhysicalDamageLifeLeech" or mod.name == "PhysicalDamageManaLeech") and mod.flags == ModFlag.Attack)
			   ) and mod.keywordFlags == 0 and not mod[1] then
				mod[1] = { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" }
			elseif item.targetVersion ~= "2_6" and (mod.name == "PoisonChance" or mod.name == "BleedChance") and (not mod[1] or (mod[1].type == "Condition" and mod[1].var == "CriticalStrike" and not mod[2])) then
				t_insert(mod, { type = "Condition", var = (slotNum == 1) and "MainHandAttack" or "OffHandAttack" })
			end
		end
		weaponData.TotalDPS = 0
		for _, dmgType in pairs(dmgTypeList) do
			weaponData.TotalDPS = weaponData.TotalDPS + (weaponData[dmgType.."DPS"] or 0)
		end
	elseif item.base.armour then
		local armourData = item.armourData
		local armourBase = sumLocal(modList, "Armour", "BASE", 0) + (item.base.armour.ArmourBase or 0)
		local evasionBase = sumLocal(modList, "Evasion", "BASE", 0) + (item.base.armour.EvasionBase or 0)
		local energyShieldBase = sumLocal(modList, "EnergyShield", "BASE", 0) + (item.base.armour.EnergyShieldBase or 0)
		local armourInc = sumLocal(modList, "Armour", "INC", 0)
		local armourEvasionInc = sumLocal(modList, "ArmourAndEvasion", "INC", 0)
		local evasionInc = sumLocal(modList, "Evasion", "INC", 0)
		local evasionEnergyShieldInc = sumLocal(modList, "EvasionAndEnergyShield", "INC", 0)
		local energyShieldInc = sumLocal(modList, "EnergyShield", "INC", 0)
		local armourEnergyShieldInc = sumLocal(modList, "ArmourAndEnergyShield", "INC", 0)
		local defencesInc = sumLocal(modList, "Defences", "INC", 0)
		armourData.Armour = round(armourBase * (1 + (armourInc + armourEvasionInc + armourEnergyShieldInc + defencesInc + item.quality) / 100))
		armourData.Evasion = round(evasionBase * (1 + (evasionInc + armourEvasionInc + evasionEnergyShieldInc + defencesInc + item.quality) / 100))
		armourData.EnergyShield = round(energyShieldBase * (1 + (energyShieldInc + armourEnergyShieldInc + evasionEnergyShieldInc + defencesInc + item.quality) / 100))
		if item.base.armour.BlockChance then
			armourData.BlockChance = item.base.armour.BlockChance + sumLocal(modList, "BlockChance", "BASE", 0)
		end
		if item.base.armour.MovementPenalty then
			modList:NewMod("MovementSpeed", "INC", -item.base.armour.MovementPenalty, item.modSource, { type = "Condition", var = "IgnoreMovementPenalties", neg = true })
		end
		for _, value in ipairs(modList:Sum("LIST", nil, "ArmourData")) do
			armourData[value.key] = value.value
		end
	elseif item.base.flask then
		local flaskData = item.flaskData
		local durationInc = sumLocal(modList, "Duration", "INC", 0)
		if item.base.flask.life or item.base.flask.mana then
			-- Recovery flask
			flaskData.instantPerc = sumLocal(modList, "FlaskInstantRecovery", "BASE", 0)
			local recoveryMod = 1 + sumLocal(modList, "FlaskRecovery", "INC", 0) / 100
			local rateMod = 1 + sumLocal(modList, "FlaskRecoveryRate", "INC", 0) / 100
			flaskData.duration = item.base.flask.duration * (1 + durationInc / 100) / rateMod
			if item.base.flask.life then
				flaskData.lifeBase = item.base.flask.life * (1 + item.quality / 100) * recoveryMod
				flaskData.lifeInstant = flaskData.lifeBase * flaskData.instantPerc / 100
				flaskData.lifeGradual = flaskData.lifeBase * (1 - flaskData.instantPerc / 100) * (1 + durationInc / 100)
				flaskData.lifeTotal = flaskData.lifeInstant + flaskData.lifeGradual
			end
			if item.base.flask.mana then
				flaskData.manaBase = item.base.flask.mana * (1 + item.quality / 100) * recoveryMod
				flaskData.manaInstant = flaskData.manaBase * flaskData.instantPerc / 100
				flaskData.manaGradual = flaskData.manaBase * (1 - flaskData.instantPerc / 100) * (1 + durationInc / 100)
				flaskData.manaTotal = flaskData.manaInstant + flaskData.manaGradual
			end
		else
			-- Utility flask
			flaskData.duration = item.base.flask.duration * (1 + (durationInc + item.quality) / 100)
		end
		flaskData.chargesMax = item.base.flask.chargesMax + sumLocal(modList, "FlaskCharges", "BASE", 0)
		flaskData.chargesUsed = m_floor(item.base.flask.chargesUsed * (1 + sumLocal(modList, "FlaskChargesUsed", "INC", 0) / 100))
		flaskData.gainMod = 1 + sumLocal(modList, "FlaskChargeRecovery", "INC", 0) / 100
		flaskData.effectInc = sumLocal(modList, "FlaskEffect", "INC", 0)
		for _, value in ipairs(modList:Sum("LIST", nil, "FlaskData")) do
			flaskData[value.key] = value.value
		end
	elseif item.type == "Jewel" then
		local jewelData = item.jewelData
		for _, func in ipairs(modList:Sum("LIST", nil, "JewelFunc")) do
			jewelData.funcList = jewelData.funcList or { }
			t_insert(jewelData.funcList, func)
		end
		for _, value in ipairs(modList:Sum("LIST", nil, "JewelData")) do
			jewelData[value.key] = value.value
		end
	end	
	return { unpack(modList) }
end

-- Build lists of modifiers for each slot an item can occupy
function itemLib.buildItemModList(item)
	if not item.base then
		return
	end
	local baseList = common.New("ModList")
	if item.base.weapon then
		item.weaponData = { }
	elseif item.base.armour then
		item.armourData = { }
	elseif item.base.flask then
		item.flaskData = { }
		item.buffModList = { }
	elseif item.type == "Jewel" then
		item.jewelData = { }
	end
	item.baseModList = baseList
	item.rangeLineList = { }
	item.modSource = "Item:"..(item.id or -1)..":"..item.name
	for _, modLine in ipairs(item.modLines) do
		if not modLine.extra and itemLib.checkModLineVariant(item, modLine) then
			if modLine.range then
				local line = itemLib.applyRange(modLine.line:gsub("\n"," "), modLine.range)
				local list, extra = modLib.parseMod[item.targetVersion](line)
				if list and not extra then
					modLine.modList = list
					t_insert(item.rangeLineList, modLine)
				end
			end
			for _, mod in ipairs(modLine.modList) do
				mod.source = item.modSource
				if type(mod.value) == "table" and mod.value.mod then
					mod.value.mod.source = mod.source
				end
				if modLine.buff then
					t_insert(item.buffModList, mod)
				else
					baseList:AddMod(mod)
				end
			end
		end
	end
	if sumLocal(baseList, "NoAttributeRequirements", "FLAG", 0) then
		item.requirements.strMod = 0
		item.requirements.dexMod = 0
		item.requirements.intMod = 0
	else
		item.requirements.strMod = m_floor((item.requirements.str + sumLocal(baseList, "StrRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "StrRequirement", "INC", 0) / 100))
		item.requirements.dexMod = m_floor((item.requirements.dex + sumLocal(baseList, "DexRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "DexRequirement", "INC", 0) / 100))
		item.requirements.intMod = m_floor((item.requirements.int + sumLocal(baseList, "IntRequirement", "BASE", 0)) * (1 + sumLocal(baseList, "IntRequirement", "INC", 0) / 100))
	end
	item.grantedSkills = { }
	for _, skill in ipairs(baseList:Sum("LIST", nil, "ExtraSkill")) do
		if skill.name ~= "Unknown" then
			t_insert(item.grantedSkills, {
				name = skill.name,
				level = skill.level,
				noSupports = skill.noSupports,
				source = item.modSource,
			})
		end
	end
	local socketCount = sumLocal(baseList, "SocketCount", "BASE", 0)
	item.abyssalSocketCount = sumLocal(baseList, "AbyssalSocketCount", "BASE", 0)
	item.selectableSocketCount = m_max(item.base.socketLimit or 0, #item.sockets) - item.abyssalSocketCount
	if sumLocal(baseList, "NoSockets", "FLAG", 0) then
		-- Remove all sockets
		wipeTable(item.sockets)
		item.selectableSocketCount = 0
	elseif socketCount > 0 then
		-- Force the socket count to be equal to the stated number
		item.selectableSocketCount = socketCount
		local group = 0
		for i = 1, m_max(socketCount, #item.sockets) do 
			if i > socketCount then
				item.sockets[i] = nil
			elseif not item.sockets[i] then
				item.sockets[i] = {
					color = item.defaultSocketColor,
					group = group
				}
			else
				group = item.sockets[i].group
			end
		end
	elseif item.abyssalSocketCount > 0 then
		-- Ensure that there are the correct number of abyssal sockets present
		local newSockets = { }
		local group = 0
		if item.sockets then
			for i, socket in ipairs(item.sockets) do
				if socket.color ~= "A" then
					t_insert(newSockets, socket)
					group = socket.group
					if #newSockets >= item.selectableSocketCount then
						break
					end
				end
			end
		end
		for i = 1, item.abyssalSocketCount do
			group = group + 1
			t_insert(newSockets, {
				color = "A",
				group = group
			})
		end
		item.sockets = newSockets
	end
	item.socketedJewelEffectModifier = 1 + sumLocal(baseList, "SocketedJewelEffect", "INC", 0) / 100
	if item.name == "Tabula Rasa, Simple Robe" or item.name == "Skin of the Loyal, Simple Robe" or item.name == "Skin of the Lords, Simple Robe" then
		-- Hack to remove the energy shield
		baseList:NewMod("ArmourData", "LIST", { key = "EnergyShield", value = 0 })
	end
	if item.base.weapon or item.type == "Ring" then
		item.slotModList = { }
		for i = 1, 2 do
			item.slotModList[i] = itemLib.buildItemModListForSlotNum(item, baseList, i)
		end
	else
		item.modList = itemLib.buildItemModListForSlotNum(item, baseList)
	end
end
