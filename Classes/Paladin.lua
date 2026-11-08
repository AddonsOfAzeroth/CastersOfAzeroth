-- Casters of Azeroth by DinX: paladin module, Holy (beta: built from the
-- leveling guides, not yet played with). Heals in a group, seals and
-- judgements solo. Visual only.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local Safe = CK.Safe

if select(2, UnitClass("player")) ~= "PALADIN" then return end

local SEALS = { "Seal of Righteousness", "Seal of Command", "Seal of Wisdom", "Seal of Light", "Seal of the Crusader",
	"Seal of Justice", "Seal of Vengeance", "Seal of Blood" }
local AURAS = { "Devotion Aura", "Retribution Aura", "Concentration Aura" }
local BLESSINGS = { "Blessing of Wisdom", "Greater Blessing of Wisdom", "Blessing of Might", "Greater Blessing of Might",
	"Blessing of Kings", "Greater Blessing of Kings" }

local function hasSeal(ctx)
	for _, n in ipairs(SEALS) do
		local a, hidden = CK:FindAura("player", n, "HELPFUL")
		if a or hidden then return true end
	end
end

local function creatureType()
	return Safe(UnitCreatureType("target"), nil)
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local function emergency(ctx, push)
	if not ctx.inCombat then return end
	if ctx.healthPct < 0.15 and ctx:Ready("Lay on Hands") then push("Lay on Hands", "defensive") end
	if ctx.healthPct < 0.25 and ctx:Ready("Divine Shield") then push("Divine Shield", "defensive")
	elseif ctx.healthPct < 0.25 and ctx:Ready("Divine Protection") then push("Divine Protection", "defensive") end
end

local function selfHeal(ctx, push)
	if ctx.healthPct >= 0.4 or ctx.moving then return end
	if ctx:Ready("Holy Shock") then push("Holy Shock", "defensive") end
	if ctx:Ready("Flash of Light") then push("Flash of Light", "defensive")
	elseif ctx:Ready("Holy Light") then push("Holy Light", "defensive") end
end

local function interrupt(ctx, push)
	if ctx.targetInterruptible and ctx:Ready("Hammer of Justice") then push("Hammer of Justice", "defensive") end
end

---------------------------------------------------------------------------
-- Solo: a seal, judge it, keep swinging (auto attack); Exorcism on undead/demons
---------------------------------------------------------------------------
local function damage(ctx, push)
	if not ctx.hostile then return end
	interrupt(ctx, push)
	emergency(ctx, push)
	selfHeal(ctx, push)
	if not hasSeal(ctx) then
		if ctx:Ready("Seal of Righteousness") then push("Seal of Righteousness")
		elseif ctx:Ready("Seal of Command") then push("Seal of Command") end
	end
	if ctx:Ready("Judgement") and hasSeal(ctx) then push("Judgement") end
	local ct = creatureType()
	if (ct == "Undead" or ct == "Demon") and ctx:Ready("Exorcism") then push("Exorcism") end
	if ctx.targetHealthPct and ctx.targetHealthPct < 0.2 and ctx:Ready("Hammer of Wrath") then push("Hammer of Wrath") end
	if ctx.aoe and ctx.nearby >= 3 and ctx:Ready("Consecration") then push("Consecration") end
	if ctx:Ready("Holy Shock") and ctx.manaPct > 0.5 then push("Holy Shock") end
end

---------------------------------------------------------------------------
-- Holy: heal in a group (you pick who), damage solo
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
	local known, pct = 0, 1
	for _, u in ipairs(PARTY) do
		local p = unitPct(u)
		if p then
			known = known + 1
			if p < pct then pct = p end
		end
	end
	if known == 0 then return false end
	local still, n = not ctx.moving, 0
	local function suggest(s, k) n = n + 1 push(s, k) end
	if pct < 0.2 and ctx:Ready("Lay on Hands") then suggest("Lay on Hands", "defensive") end
	if pct < 0.4 then
		if ctx:Ready("Divine Favor") then suggest("Divine Favor", "hint") end
		if ctx:Ready("Holy Shock") then suggest("Holy Shock") end
		if still and ctx:Ready("Holy Light") then suggest("Holy Light") end
	end
	if pct < 0.8 then
		if ctx:Ready("Holy Shock") then suggest("Holy Shock") end
		if still and ctx:Ready("Flash of Light") then suggest("Flash of Light") end
	end
	if pct < 0.6 and still and ctx:Ready("Holy Light") then suggest("Holy Light") end
	if ctx.inCombat and ctx.manaPct < 0.4 and ctx:Ready("Divine Plea") then suggest("Divine Plea", "hint") end
	return n > 0
end

local function holy(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if IsInGroup() then
		if not heal(ctx, push) then damage(ctx, push) end
		return
	end
	damage(ctx, push)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Paladin = {
	beta = true,
	defaultSpec = "HOLY",
	specs = {
		HOLY = { name = "Holy", icon = 135920, rotation = holy, healer = true },
	},
	specOrder = { "HOLY" },
	partyBuffs = {
		{ spell = "Blessing of Wisdom", names = { "Blessing of Wisdom", "Greater Blessing of Wisdom" },
			filter = function(unit) return Safe(UnitPowerType(unit), 0) == 0 end },
		{ spell = "Blessing of Might", names = { "Blessing of Might", "Greater Blessing of Might" },
			filter = function(unit) return Safe(UnitPowerType(unit), 0) ~= 0 end },
	},
	buffOptions = {
		{ "aura", "Aura (Devotion, Retribution or Concentration)" },
		{ "blessing", "A blessing on yourself" },
	},
}

function Paladin.Always(ctx, list, add)
	if (ctx.control == "STUN" or ctx.control == "FEAR") and ctx:Ready("Divine Shield") and ctx.healthPct < 0.5 then
		add(list, "Divine Shield", "defensive", true)
	end
end

CK:RegisterClass("PALADIN", Paladin)

CK:AddReminderProvider(function(add)
	local cfg = CK.char.leveling
	local inCombat = InCombatLockdown()
	local function remind(key, names, spell, missingText, anyTarget)
		if cfg.buffsOff[key] or not spell then return end
		local found, hidden
		for _, n in ipairs(names) do
			local a, h = CK:FindAura("player", n, "HELPFUL")
			if a then found = n break end
			hidden = hidden or h
		end
		local missing = not found and not hidden
		add({ key = key, icon = CK:SpellTexture(spell), count = missing and "!" or "",
			always = cfg.buffMode == "always" or missing, warn = not inCombat and missing,
			spell = spell, tooltip = found or missingText, anyTarget = anyTarget })
	end
	local aura = (IsInGroup() and CK:Known("Concentration Aura") and "Concentration Aura")
		or (CK:Known("Devotion Aura") and "Devotion Aura")
	remind("aura", AURAS, aura, L["No aura active."])
	local blessing = (CK:Known("Blessing of Wisdom") and "Blessing of Wisdom") or (CK:Known("Blessing of Might") and "Blessing of Might")
	remind("blessing", BLESSINGS, blessing, L["No blessing on you."], true)
end)
