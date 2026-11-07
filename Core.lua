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
		source = "blizzard", -- "blizzard" (Assisted Combat) of "custom" (eigen prioriteit)
		glow = true,
		glowStyle = "blizzard", -- "blizzard" of "pulse"
		secondary = true,
		onlyHostile = true,
		hint = true,
		aoe = false,
		point = nil,
	},
	leveling = {
		xpbar = true,
		hideBlizzardXP = true,
		mobTooltip = true,
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
	points = {}, -- saved positions of movable frames, by key
	class = {},
}

local accountDefaults = {
	minimap = { hide = false, angle = 215 },
	language = "enUS",
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
		for i = 1, #list do list[i](event, ...) end
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
function CK:FindAura(unit, name, filter)
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			local a = C_UnitAuras.GetAuraDataByIndex(unit, i, filter)
			if not a then return end
			if not issecret(a.name) and a.name == name then return a end
		end
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
	CasterKitCharDB = CasterKitCharDB or {}
	CasterKitDB = CasterKitDB or {}
	merge(CasterKitCharDB, charDefaults)
	merge(CasterKitDB, accountDefaults)
	CK.char = CasterKitCharDB
	CK.db = CasterKitDB
	CK.charDefaults = charDefaults
	CK.playerClass = select(2, UnitClass("player"))
	for _, m in ipairs(CK.modules) do
		if m.OnInit then m:OnInit() end
	end
end)

CK:On("PLAYER_LOGIN", function()
	CK:ScanSpellbook()
	local def = CK:GetClass()
	if def and def.OnEnable then def:OnEnable() end
	for _, m in ipairs(CK.modules) do
		if m.OnEnable then m:OnEnable() end
	end
	local conflict = CK:BarConflict()
	if conflict and CK.char.bars.enabled then
		CK:Print(CK.L["%s already manages the action bars. CasterKit bars are off; the rotation helper still lights up those buttons. Type /ck for settings."]:format(conflict))
	end
end)

CK:On("SPELLS_CHANGED", function() CK:ScanSpellbook() end)

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

