-- CasterKit by DinX
local ADDON, ns = ...

local CK = CreateFrame("Frame", "CasterKitCore")
ns.CK = CK
_G.CasterKit = CK

CK.version = (C_AddOns and C_AddOns.GetAddOnMetadata or GetAddOnMetadata)(ADDON, "Version") or "?"
CK.modules = {}
CK.classes = {}

---------------------------------------------------------------------------
-- Defaults
---------------------------------------------------------------------------
local charDefaults = {
	nav = {
		enabled = true,
		followQuests = true, -- smart quest route (QuestPlan) after the own stops
		useFlights = true,   -- suggest known flight paths when they save > 60 s
		showPanel = true,    -- GPS panel (mover "nav"); off = the small arrow frame
		panelScale = 1,
		mapList = true,      -- route list docked to the world map
		minimap = true,      -- current stop + next 3 on the minimap, with lines
		autoAdvance = true,  -- own custom waypoints leave the route on arrival
		queue = {},          -- own stops {mapID, x, y, title, kind, questID}
		taxiKnown = {},      -- flight path node IDs (and "n:<name>") seen at flight masters
	},
	skins = {
		enabled = true,
		character = true,
		spellbook = true,
		quest = true,
		merchant = true,
		mail = true,
		trainer = true,
		friends = true,
		menus = true,
		popups = true,
		other = true,
	},
	bags = {
		enabled = true,
		view = "category", -- "category" or "bag"
		columns = 10,
		iconSize = 34,
		itemLevel = true,
		showNewGlow = true,
		autoOpenMerchant = true,
		junkList = {}, -- [itemID] = true: items marked as junk with Alt-click
	},
	loot = {
		enabled = true,
		window = true,       -- replace Blizzard's loot window
		atCursor = true,     -- open at the cursor; false = fixed spot (mover "loot")
		feed = true,         -- loot feed (mover "lootfeed")
		feedDuration = 6,    -- seconds per line
		feedMax = 6,         -- lines
		showMoney = true,
		questItems = true,   -- quest items in the feed (with a "Quest" tag)
		bagsFull = true,     -- prominent "Bags full!" line on ERR_INV_FULL
		rollFrames = true,   -- own group loot roll frames (mover "lootroll")
		autoLoot = false,    -- mirror of CVar autoLootDefault (read from the CVar at login)
	},
	bars = {
		enabled = true,
		rows = 3,
		perRow = 12,
		size = 36,
		spacing = 4,
		scale = 1,
		mainOnTop = true,
		background = true,
		hideBlizzard = true,
		locked = true,
		point = { "BOTTOM", "UIParent", "BOTTOM", 0, 24 },
	},
	rotation = {
		enabled = true,
		spec = nil, -- nil = standaard van de class-module
		source = "custom", -- "custom" (own guide priority, Blizzard as fallback) or "blizzard"
		glow = true,
		glowStyle = "blizzard", -- "blizzard" of "pulse"
		secondary = true,
		onlyHostile = true,
		hint = true,
		aoe = false,
		autoAoe = true, -- AoE priority by itself with 3+ enemies close by (nameplates)
		point = nil,
	},
	leveling = {
		xpbar = true,
		hideBlizzardXP = true,
		mobTooltip = true,
		buffMode = "always", -- "always" or "missing"
		buffWarnMinutes = 5,
		buffsOff = {}, -- [key] = true hides that buff button
		mobXP = {},
		reminders = true,
		trainer = true,
		talents = true,
		sellGrey = true,
		repair = true,
		trainerPending = nil,
	},
	micro = {
		enabled = true,
		bags = true,
		scale = 0.85,
		point = { "BOTTOMRIGHT", "UIParent", "BOTTOMRIGHT", -6, 6 },
	},
	units = {
		enabled = true,
		player = true,
		target = true,
		tot = true,
		party = true,
		hideBlizzard = true,
		classColor = true,
		scale = 1,
		castbar = true,
		targetCastbar = true,
		hideBlizzardCastbar = true,
		castbarLatency = true,
		partyBuffs = true,
	},
	chat = {
		enabled = true,
		timestamps = true,
		shortChannels = true,
		classColors = true,
		tabsPerChannel = true,
		fadeTabs = true,
		width = 440,
		height = 190,
		fontSize = 13,
	},
	quests = {
		enabled = true,
		hideBlizzard = true,
		hideQuestieTracker = true,
		zoneFirst = true,
		hideDone = true,
		maxQuests = 12,
		width = 260,
		fontSize = 12,
		collapsed = {},
		allCollapsed = false,
		sortMode = "smart", -- smart, distance, xp, xpmin, level, progress, zone
		showEstimates = true,
		arrow = true, -- CasterKit arrow (Arrow.lua) to the next stop
	},
	tooltip = {
		anchor = true,
		hideInCombat = false,
	},
	map = {
		enabled = true,
		route = true,
		coords = true,
		minimapCoords = true,
		skin = true, -- flat look: Blizzard's frame art hidden
		fadeMoving = true,
		fadeAlpha = 0.5,
		scale = 1,
	},
	arrow = {
		enabled = true,
		scale = 1,
		arriveYards = 15,
	},
	questLearn = {}, -- learned kill time, drop rates, run speed (QuestPlan.lua)
	points = {}, -- saved positions of movable frames, by key
	class = {},
}

local accountDefaults = {
	minimap = { hide = false, angle = 215 },
	language = "enUS",
	profiles = {},
}

local function merge(dst, src)
	for k, v in pairs(src) do
		if type(v) == "table" then
			if type(dst[k]) ~= "table" then dst[k] = {} end
			merge(dst[k], v)
		elseif dst[k] == nil then
			dst[k] = v
		end
	end
end

local function copy(t)
	local r = {}
	for k, v in pairs(t) do r[k] = type(v) == "table" and copy(v) or v end
	return r
end
CK.CopyTable = copy

---------------------------------------------------------------------------
-- Printing, events, modules
---------------------------------------------------------------------------
function CK:Print(...)
	print("|cff69ccf0CasterKit|r:", ...)
end

local handlers = {}
function CK:On(event, fn)
	if not handlers[event] then
		handlers[event] = {}
		self:RegisterEvent(event)
	end
	table.insert(handlers[event], fn)
end

CK:SetScript("OnEvent", function(self, event, ...)
	local list = handlers[event]
	if list then
		local prev = CK.where
		CK.where = (prev and prev .. " > " or "") .. event
		for i = 1, #list do list[i](event, ...) end
		CK.where = prev
	end
end)

-- Modules get :OnInit() at ADDON_LOADED and :OnEnable() at PLAYER_LOGIN.
function CK:NewModule(name)
	local m = { name = name }
	self.modules[#self.modules + 1] = m
	self[name] = m
	return m
end

-- Run fn now, or as soon as combat ends (secure frames cannot change in combat).
local afterCombat = {}
function CK:OutOfCombat(key, fn)
	if not InCombatLockdown() then
		fn()
	else
		afterCombat[key] = fn
	end
end
CK:On("PLAYER_REGEN_ENABLED", function()
	for k, fn in pairs(afterCombat) do
		afterCombat[k] = nil
		fn()
	end
end)

-- Simple callback bus so modules can react to settings changes.
local callbacks = {}
function CK:Listen(msg, fn)
	callbacks[msg] = callbacks[msg] or {}
	table.insert(callbacks[msg], fn)
end
function CK:Fire(msg, ...)
	for _, fn in ipairs(callbacks[msg] or {}) do fn(...) end
end

---------------------------------------------------------------------------
-- Secret values: in combat Blizzard hides some numbers from addons.
-- We may show them but never compute with them, so check first.
---------------------------------------------------------------------------
local issecret = issecretvalue or function() return false end
CK.IsSecret = issecret

-- Returns v, or default when v is a secret value.
function CK.Safe(v, default)
	if issecret(v) then return default end
	return v
end
local Safe = CK.Safe

---------------------------------------------------------------------------
-- Spell helpers (spellbook scan; names are enUS)
---------------------------------------------------------------------------
local known = {}     -- name -> highest spellID
local passive = {}   -- name -> true
CK.known = known

local function GetName(id)
	if C_Spell and C_Spell.GetSpellName then return C_Spell.GetSpellName(id) end
	return (GetSpellInfo(id))
end
CK.GetSpellName = GetName

local function addKnown(name, id, isPassive)
	if not name or not id then return end
	if not known[name] or id > known[name] then known[name] = id end
	if isPassive then passive[name] = true end
end

function CK:ScanSpellbook()
	wipe(known)
	wipe(passive)
	if C_SpellBook and C_SpellBook.GetNumSpellBookSkillLines then
		local bank = Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player or 0
		for line = 1, C_SpellBook.GetNumSpellBookSkillLines() do
			local info = C_SpellBook.GetSpellBookSkillLineInfo(line)
			if info and not info.shouldHide then
				for i = info.itemIndexOffset + 1, info.itemIndexOffset + info.numSpellBookItems do
					local item = C_SpellBook.GetSpellBookItemInfo(i, bank)
					if item and item.spellID and item.itemType == Enum.SpellBookItemType.Spell and not item.isOffSpec then
						addKnown(item.name, item.spellID, item.isPassive)
					end
				end
			end
		end
	elseif GetNumSpellTabs then
		for tab = 1, GetNumSpellTabs() do
			local _, _, offset, num = GetSpellTabInfo(tab)
			for i = offset + 1, offset + num do
				local kind, id = GetSpellBookItemInfo(i, BOOKTYPE_SPELL)
				if kind == "SPELL" and id then
					addKnown(GetName(id), id, IsPassiveSpell and IsPassiveSpell(i, BOOKTYPE_SPELL))
				end
			end
		end
	end
	self:Fire("SPELLS")
end

function CK:Known(name) return known[name] ~= nil end
function CK:IsActive(name) return known[name] ~= nil and not passive[name] end
function CK:SpellID(name) return known[name] end

function CK:SpellTexture(name)
	local id = known[name] or name
	if C_Spell and C_Spell.GetSpellTexture then return C_Spell.GetSpellTexture(id) end
	return GetSpellTexture(id)
end

-- Returns start, duration; nil, nil when the values are secret.
local function rawCooldown(id)
	local s, d
	if C_Spell and C_Spell.GetSpellCooldown then
		local cd = C_Spell.GetSpellCooldown(id)
		if not cd then return 0, 0 end
		s, d = cd.startTime, cd.duration
	else
		s, d = GetSpellCooldown(id)
	end
	if issecret(s) or issecret(d) then return nil, nil end
	return s or 0, d or 0
end

-- Seconds left on the global cooldown (0 when unknown).
function CK:GCDRemaining()
	local s, d = rawCooldown(61304)
	if s and s > 0 then return math.max(0, s + d - GetTime()) end
	return 0
end

-- Seconds left on a spell's own cooldown (GCD ignored); math.huge when unknown.
function CK:CooldownRemaining(name)
	local id = known[name]
	if not id then return math.huge end
	local s, d = rawCooldown(id)
	if not s then return math.huge end
	if s == 0 or d == 0 then return 0 end
	local _, gd = rawCooldown(61304)
	if gd and gd > 0 and d <= gd + 0.05 then return 0 end
	return math.max(0, s + d - GetTime())
end

function CK:IsUsable(name)
	local id = known[name]
	if not id then return false, false end
	local usable, noMana
	if C_Spell and C_Spell.IsSpellUsable then
		usable, noMana = C_Spell.IsSpellUsable(id)
	else
		usable, noMana = IsUsableSpell(id)
	end
	if issecret(usable) or issecret(noMana) then return false, false end
	return usable, noMana
end

---------------------------------------------------------------------------
-- Aura helpers
---------------------------------------------------------------------------
-- Auras whose data is secret are skipped (treated as not found).
-- Returns the aura (or nil) and, as second value, true when auras are hidden
-- right now (secret in combat): then "nil" means unknown, not missing.
function CK:FindAura(unit, name, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataBySpellName then
		local ok, a = pcall(C_UnitAuras.GetAuraDataBySpellName, unit, name, filter)
		if ok and not issecret(a) then return a, false end
	end
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			-- errors while auras are secret ("cannot be accessed when secret")
			local ok, a = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok or issecret(a) then return nil, true end
			if not a then return nil, false end
			if issecret(a.name) then return nil, true end
			if a.name == name then return a, false end
		end
		return nil, false
	elseif UnitAura then
		for i = 1, 40 do
			local n, _, count, _, dur, exp = UnitAura(unit, i, filter)
			if not n then return end
			if not issecret(n) and n == name then return { name = n, applications = count, duration = dur, expirationTime = exp } end
		end
	end
end

function CK:AuraRemaining(unit, name, filter)
	local a = self:FindAura(unit, name, filter)
	if not a then return 0 end
	local exp = Safe(a.expirationTime)
	if not exp then return 1 end -- present, duration hidden
	if exp == 0 then return math.huge end
	return math.max(0, exp - GetTime())
end

---------------------------------------------------------------------------
-- Bag helpers
---------------------------------------------------------------------------
local GetNumSlots = C_Container and C_Container.GetContainerNumSlots or GetContainerNumSlots
local GetSlotInfo = C_Container and C_Container.GetContainerItemInfo

function CK:ItemInfoAt(bag, slot)
	if GetSlotInfo then return GetSlotInfo(bag, slot) end
	local tex, count, _, quality, _, _, link, _, noValue, id = GetContainerItemInfo(bag, slot)
	if not tex then return end
	return { iconFileID = tex, stackCount = count, quality = quality, hyperlink = link, hasNoValue = noValue, itemID = id }
end

-- Calls fn(bag, slot, info) for every filled bag slot.
function CK:ForEachBagItem(fn)
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		for slot = 1, GetNumSlots(bag) or 0 do
			local info = self:ItemInfoAt(bag, slot)
			if info and info.itemID then fn(bag, slot, info) end
		end
	end
end

function CK:FreeBagSlots()
	local free = 0
	for bag = 0, (NUM_BAG_SLOTS or 4) do
		local n, family
		if C_Container and C_Container.GetContainerNumFreeSlots then
			n, family = C_Container.GetContainerNumFreeSlots(bag)
		else
			n, family = GetContainerNumFreeSlots(bag)
		end
		if family == 0 then free = free + (n or 0) end
	end
	return free
end

function CK:ItemName(id)
	if C_Item and C_Item.GetItemNameByID then return C_Item.GetItemNameByID(id) end
	return (GetItemInfo(id))
end

-- Icon of a bag item by name (for item suggestions such as mana gems).
function CK:ItemByName(name)
	local icon
	self:ForEachBagItem(function(_, _, info)
		if not icon and self:ItemName(info.itemID) == name then icon = info.iconFileID end
	end)
	return icon
end

function CK:ItemIcon(id)
	if C_Item and C_Item.GetItemIconByID then return C_Item.GetItemIconByID(id) end
	return GetItemIcon(id)
end

---------------------------------------------------------------------------
-- Class / spec registry
---------------------------------------------------------------------------
-- def = { defaultSpec = "FROST", specs = { FROST = { name, icon, rotation = fn(ctx) } }, OnEnable = fn }
function CK:RegisterClass(token, def)
	self.classes[token] = def
end

function CK:GetClass()
	return self.classes[self.playerClass]
end

function CK:GetSpec()
	local def = self:GetClass()
	if not def then return end
	local key = self.char.rotation.spec
	if not key or not def.specs[key] then key = def.defaultSpec end
	return def.specs[key], key
end

-- Points per talent tree, for modules that want to auto-detect.
function CK:TalentPoints(tab)
	if not GetTalentTabInfo then return 0 end
	local a, b, c, d, e = GetTalentTabInfo(tab)
	if type(a) == "number" then return e or 0 end
	return c or 0
end

function CK:UnspentTalentPoints()
	if UnitCharacterPoints then return (UnitCharacterPoints("player")) or 0 end
	if GetUnspentTalentPoints then return GetUnspentTalentPoints() or 0 end
	return 0
end

---------------------------------------------------------------------------
-- Conflicts: other addons that own the action bars
---------------------------------------------------------------------------
local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

function CK:BarConflict()
	if IsLoaded("Bartender4") then return "Bartender4" end
	if IsLoaded("Dominos") then return "Dominos" end
	if IsLoaded("ElvUI") and ElvUI then
		local E = ElvUI[1]
		if E and E.private and E.private.actionbar and E.private.actionbar.enable then
			return CK.L["ElvUI (action bars)"]
		end
	end
end

---------------------------------------------------------------------------
-- Startup
---------------------------------------------------------------------------
CK:On("ADDON_LOADED", function(_, name)
	if name ~= ADDON then return end
	local newCharacter = CasterKitCharDB == nil
	CasterKitCharDB = CasterKitCharDB or {}
	CasterKitDB = CasterKitDB or {}
	merge(CasterKitDB, accountDefaults)
	CK.char = CasterKitCharDB
	CK.db = CasterKitDB
	-- a new alt starts from the default profile, if one is set
	local default = CK.db.defaultProfile
	if newCharacter and default and CK.db.profiles[default] then
		for group, v in pairs(copy(CK.db.profiles[default])) do CasterKitCharDB[group] = v end
		CasterKitCharDB.profile = default
	end
	merge(CasterKitCharDB, charDefaults)
	-- 0.2.2: the guide priority became the default rotation source (once per character)
	if not CasterKitCharDB.rotation.customDefault then
		CasterKitCharDB.rotation.source = "custom"
		CasterKitCharDB.rotation.customDefault = true
	end
	CK.charDefaults = charDefaults
	CK.playerClass = select(2, UnitClass("player"))
	for _, m in ipairs(CK.modules) do
		if m.OnInit then m:OnInit() end
	end
end)

CK:On("PLAYER_LOGIN", function()
	CK:ScanSpellbook()
	local def = CK:GetClass()
	CK.where = "PLAYER_LOGIN class"
	if def and def.OnEnable then def:OnEnable() end
	for _, m in ipairs(CK.modules) do
		CK.where = "PLAYER_LOGIN " .. m.name
		if m.OnEnable then m:OnEnable() end
	end
	CK.where = "PLAYER_LOGIN"
	local conflict = CK:BarConflict()
	if conflict and CK.char.bars.enabled then
		CK:Print(CK.L["%s already manages the action bars. CasterKit bars are off; the rotation helper still lights up those buttons. Type /ck for settings."]:format(conflict))
	end
end)

CK:On("SPELLS_CHANGED", function() CK:ScanSpellbook() end)

---------------------------------------------------------------------------
-- Profiles: named copies of the settings, shared by all characters
---------------------------------------------------------------------------
-- Keys that stay with the character, never copied between profiles.
local PERSONAL = {
	leveling = { trainerPending = true, mobXP = true },
	chat = { setupDone = true, channelTabs = true, prevTimestamps = true },
	rotation = { spec = true },
	bags = { junkList = true },
	loot = { autoLoot = true },
	nav = { queue = true, taxiKnown = true },
}

local function profileCopy(src)
	local out = {}
	for group, v in pairs(src) do
		-- learned play data stays with the character
		if group ~= "profile" and group ~= "questLearn" then
			out[group] = type(v) == "table" and copy(v) or v
			local skip = PERSONAL[group]
			if skip and type(out[group]) == "table" then
				for k in pairs(skip) do out[group][k] = nil end
			end
		end
	end
	return out
end

function CK:ProfileNames()
	local names = {}
	for name in pairs(self.db.profiles) do names[#names + 1] = name end
	table.sort(names)
	return names
end

function CK:SaveProfile(name)
	name = strtrim(name or "")
	if name == "" then return false end
	self.db.profiles[name] = profileCopy(self.char)
	self.char.profile = name
	return true
end

-- Copies a profile into this character, keeping the personal keys.
function CK:LoadProfile(name)
	local p = self.db.profiles[name]
	if not p then return false end
	local keep = {}
	for group, keys in pairs(PERSONAL) do
		keep[group] = {}
		for k in pairs(keys) do keep[group][k] = self.char[group] and self.char[group][k] end
	end
	for group, v in pairs(copy(p)) do self.char[group] = v end
	for group, vals in pairs(keep) do
		self.char[group] = self.char[group] or {}
		for k, v in pairs(vals) do self.char[group][k] = v end
	end
	merge(self.char, charDefaults)
	self.char.profile = name
	return true
end

function CK:DeleteProfile(name)
	self.db.profiles[name] = nil
	if self.db.defaultProfile == name then self.db.defaultProfile = nil end
end

-- Reset a settings group to defaults.
function CK:ResetGroup(group)
	self.char[group] = copy(charDefaults[group])
	self:Fire("SETTINGS", group)
end

---------------------------------------------------------------------------
-- Slash commands
---------------------------------------------------------------------------
SLASH_CASTERKIT1 = "/ck"
SLASH_CASTERKIT2 = "/casterkit"
SlashCmdList.CASTERKIT = function(msg)
	msg = strtrim(msg or ""):lower()
	if msg == "lock" or msg == "unlock" then
		CK.char.bars.locked = (msg == "lock")
		CK:Fire("SETTINGS", "bars")
		CK:Print(CK.char.bars.locked and CK.L["Frames locked."] or CK.L["Frames unlocked: drag them where you like, type /ck lock when done."])
	elseif msg == "debug" then
		CK.debug = not CK.debug
		CK:Print("debug", CK.debug and CK.L["on"] or CK.L["off"])
	elseif msg == "rot" then
		if CK.Rotation and CK.Rotation.Diagnose then CK.Rotation:Diagnose() end
	elseif msg == "aoe" then
		CK:ToggleAoE()
	elseif msg == "reset" then
		CK:OutOfCombat("reset", function()
			CK:ResetGroup("bars")
			CK.char.rotation.point = nil
			CK:Fire("SETTINGS", "rotation")
			CK:Print(CK.L["Positions and bar settings reset."])
		end)
	else
		CK:ToggleConfig()
	end
end

function CK:ToggleAoE()
	self.char.rotation.aoe = not self.char.rotation.aoe
	self:Print(self.char.rotation.aoe and CK.L["AoE mode on."] or CK.L["AoE mode off (single target)."])
	self:Fire("SETTINGS", "rotation")
end


-- Remove a key we may have tainted and make the table slot secure again
-- (same trick Bartender4 uses for Edit Mode frames).
function CK.PurgeKey(t, k)
	t[k] = nil
	local c = 42
	repeat
		if t[c] == nil then t[c] = nil end
		c = c + 1
	until issecurevariable(t, k)
end

-- Hide a Blizzard (Edit Mode) frame without tainting it: Edit Mode replaces
-- Hide() with its own version, so use HideBase and clear its show state.
function CK.HideBlizzardFrame(frame, parent)
	if not frame then return end
	if frame.system then pcall(CK.PurgeKey, frame, "isShownExternal") end
	if frame.HideBase then frame:HideBase() else frame:Hide() end
	if parent then frame:SetParent(parent) end
end

-- Report which function Blizzard blocked (taint), so it can be fixed.
do
	local f = CreateFrame("Frame")
	f:RegisterEvent("ADDON_ACTION_BLOCKED")
	f:RegisterEvent("ADDON_ACTION_FORBIDDEN")
	f:SetScript("OnEvent", function(_, event, addon, func)
		if addon ~= ADDON then return end
		local where = tostring(CK.where)
		local line = date("%H:%M:%S") .. " " .. event .. " " .. tostring(func)
			.. " | in: " .. where .. " | " .. tostring(debugstack and debugstack(2, 12, 0))
		if type(CasterKitDB) == "table" then
			CasterKitDB.blocked = CasterKitDB.blocked or {}
			table.insert(CasterKitDB.blocked, line)
			while #CasterKitDB.blocked > 20 do table.remove(CasterKitDB.blocked, 1) end
		end
		C_Timer.After(3, function() CK:Print("|cffff5555blocked:|r " .. tostring(func) .. " (" .. where .. ")") end)
	end)
end
