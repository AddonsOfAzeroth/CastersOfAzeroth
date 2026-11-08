-- Casters of Azeroth by DinX: shaman module, Elemental and Restoration (beta:
-- built from the leveling guides, not yet played with). Visual only.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local Safe = CK.Safe

if select(2, UnitClass("player")) ~= "SHAMAN" then return end

local DOT_TIME = { ["Flame Shock"] = 12 }
local SHIELDS = { "Water Shield", "Lightning Shield" }
-- one totem per element, best first (only known ones count); slots: 1 fire, 2 earth, 3 water, 4 air
local TOTEMS = {
	{ slot = 1, list = { "Totem of Wrath", "Searing Totem" } },
	{ slot = 2, list = { "Strength of Earth Totem", "Stoneskin Totem" } },
	{ slot = 3, list = { "Mana Spring Totem", "Healing Stream Totem" } },
	{ slot = 4, list = { "Wrath of Air Totem", "Windfury Totem", "Grace of Air Totem" } },
}

local cast = {}

local function targetGUID()
	local g = Safe(UnitGUID("target"), nil)
	return type(g) == "string" and g or nil
end

local function dotLeft(ctx, name)
	local a, hidden = CK:FindAura("target", name, "HARMFUL|PLAYER")
	if a then return CK:AuraRemaining("target", name, "HARMFUL|PLAYER") end
	if not hidden then return 0 end
	local g = targetGUID()
	local t = g and cast[g] and cast[g][name]
	if not t then return 0 end
	return math.max(0, (DOT_TIME[name] or 12) - (ctx.now - t))
end

local function firstKnown(list)
	for _, n in ipairs(list) do if CK:Known(n) then return n end end
end

-- is a totem of this element down? (official totem info)
local function totemUp(slot)
	if not GetTotemInfo then return true end
	local ok, have, name = pcall(GetTotemInfo, slot)
	if not ok then return true end
	have = Safe(have, true)
	return have and Safe(name, "x") ~= ""
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local function interrupt(ctx, push)
	if ctx.targetInterruptible then
		if ctx:Ready("Wind Shear") then push("Wind Shear", "defensive")
		elseif ctx:Ready("Earth Shock") then push("Earth Shock", "defensive") end
	end
end

local function selfHeal(ctx, push)
	if ctx.healthPct >= 0.4 then return end
	if ctx:Ready("Nature's Swiftness") then push("Nature's Swiftness", "hint") end
	if not ctx.moving then
		if ctx:Ready("Lesser Healing Wave") then push("Lesser Healing Wave", "defensive")
		elseif ctx:Ready("Healing Wave") then push("Healing Wave", "defensive") end
	end
end

-- totems in a fight that lasts: fire first (damage), the rest in a group or on bosses
local function totems(ctx, push)
	if not ctx.inCombat or ctx.moving then return end
	local long = IsInGroup() or ctx.targetIsBoss
	for _, t in ipairs(TOTEMS) do
		if t.slot == 1 or long then
			local n = firstKnown(t.list)
			if n and not totemUp(t.slot) and ctx:Ready(n) then push(n, "hint") end
		end
	end
end

local function manaTools(ctx, push)
	if ctx.inCombat and ctx.manaPct < 0.25 and ctx:Ready("Mana Tide Totem") then push("Mana Tide Totem", "hint") end
end

---------------------------------------------------------------------------
-- Elemental (leveling: Lightning Bolt to pull, Flame Shock, Earth Shock)
---------------------------------------------------------------------------
local function elemental(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	selfHeal(ctx, push)
	if ctx.aoe and not ctx.moving then
		if ctx:Ready("Chain Lightning") then push("Chain Lightning") end
		if ctx:Ready("Fire Nova Totem") then push("Fire Nova Totem") end
	end
	if not ctx.inCombat and not ctx.moving and not ctx.casting and ctx:Ready("Lightning Bolt") then push("Lightning Bolt") end
	if ctx:Ready("Elemental Mastery") and ctx.inCombat then push("Elemental Mastery", "hint") end
	local worth = not (ctx.targetHealthPct and ctx.targetHealthPct < 0.3 and not ctx.targetIsBoss)
	if worth and ctx:Ready("Flame Shock") and dotLeft(ctx, "Flame Shock") < 1.5 then push("Flame Shock")
	elseif ctx:Ready("Earth Shock") and (ctx.targetHealthPct or 1) < 0.4 then push("Earth Shock") end
	totems(ctx, push)
	manaTools(ctx, push)
	if ctx.moving then
		if ctx:Ready("Earth Shock") then push("Earth Shock") end
		return
	end
	if ctx:Ready("Chain Lightning") and ctx.nearby >= 2 then push("Chain Lightning") end
	if ctx:Ready("Lava Burst") and dotLeft(ctx, "Flame Shock") > 0 then push("Lava Burst") end
	push("Lightning Bolt")
end

---------------------------------------------------------------------------
-- Restoration: heal in a group (you pick who), Elemental solo
---------------------------------------------------------------------------
local PARTY = { "player", "party1", "party2", "party3", "party4" }

local function unitPct(u)
	if not UnitExists(u) or Safe(UnitIsDeadOrGhost(u), true) or not Safe(UnitIsConnected(u), true) then return end
	local hp, max = Safe(UnitHealth(u), nil), Safe(UnitHealthMax(u), nil)
	if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return end
	if u ~= "player" and Safe(UnitInRange(u), true) == false then return end
	return hp / max
end

local function heal(ctx, push)
	local known, injured, pct, tank = 0, 0, 1, nil
	for _, u in ipairs(PARTY) do
		local p = unitPct(u)
		if p then
			known = known + 1
			if p < 0.85 then injured = injured + 1 end
			if p < pct then pct = p end
			if u ~= "player" and UnitGroupRolesAssigned and Safe(UnitGroupRolesAssigned(u), "NONE") == "TANK" then tank = u end
		end
	end
	if known == 0 then return false end
	local still, n = not ctx.moving, 0
	local function suggest(s, k) n = n + 1 push(s, k) end
	if pct < 0.3 then
		if ctx:Ready("Nature's Swiftness") then suggest("Nature's Swiftness", "hint") end
		if still and ctx:Ready("Healing Wave") then suggest("Healing Wave") end
	end
	if tank and ctx.inCombat and ctx:Ready("Earth Shield") and not CK:FindAura(tank, "Earth Shield", "HELPFUL|PLAYER") then
		suggest("Earth Shield")
	end
	if injured >= 3 and still and ctx:Ready("Chain Heal") then suggest("Chain Heal") end
	if pct < 0.6 and still then
		if ctx:Ready("Lesser Healing Wave") then suggest("Lesser Healing Wave") end
		if ctx:Ready("Healing Wave") then suggest("Healing Wave") end
	elseif pct < 0.85 and still and ctx:Ready("Chain Heal") then
		suggest("Chain Heal")
	end
	return n > 0
end

local function restoration(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if IsInGroup() then
		manaTools(ctx, push)
		totems(ctx, push)
		if not heal(ctx, push) and ctx.manaPct > 0.6 then elemental(ctx, list, add) end
		return
	end
	elemental(ctx, list, add)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Shaman = {
	beta = true,
	defaultSpec = "ELEMENTAL",
	specs = {
		ELEMENTAL = { name = "Elemental", icon = 136048, rotation = elemental },
		RESTORATION = { name = "Restoration", icon = 136052, rotation = restoration, healer = true },
	},
	specOrder = { "ELEMENTAL", "RESTORATION" },
	partyBuffs = {},
	buffOptions = {
		{ "shield", "Lightning Shield or Water Shield" },
	},
}

function Shaman.Always(ctx, list, add)
	if ctx.control == "FEAR" and ctx:Ready("Tremor Totem") then add(list, "Tremor Totem", "defensive", true) end
end

function Shaman:OnEnable()
	CK:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local id = Safe(spellID, nil)
		local name = id and C_Spell and C_Spell.GetSpellName and C_Spell.GetSpellName(id)
		if not (name and DOT_TIME[name]) then return end
		local g = targetGUID()
		if not g then return end
		cast[g] = cast[g] or {}
		cast[g][name] = GetTime()
	end)
end

CK:RegisterClass("SHAMAN", Shaman)

CK:AddReminderProvider(function(add)
	local cfg = CK.char.leveling
	if cfg.buffsOff.shield then return end
	-- Water Shield for mana in a group or for healers, else Lightning Shield
	local _, key = CK:GetSpec()
	local want = ((IsInGroup() or key == "RESTORATION") and CK:Known("Water Shield") and "Water Shield")
		or (CK:Known("Lightning Shield") and "Lightning Shield")
	if not want then return end
	local found, hidden
	for _, n in ipairs(SHIELDS) do
		local a, h = CK:FindAura("player", n, "HELPFUL")
		if a then found = n break end
		hidden = hidden or h
	end
	local missing = not found and not hidden
	add({ key = "shield", icon = CK:SpellTexture(want), count = missing and "!" or "",
		always = cfg.buffMode == "always" or missing, warn = not InCombatLockdown() and missing,
		spell = want, tooltip = found or L["No shield active."] })
end)
