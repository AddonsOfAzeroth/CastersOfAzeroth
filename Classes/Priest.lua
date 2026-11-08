-- Casters of Azeroth by DinX: priest module (Forever leveling and Shadow guide priorities)
local _, ns = ...
local CK = ns.CK
local L = CK.L
local Safe = CK.Safe

if select(2, UnitClass("player")) ~= "PRIEST" then return end

-- Sources (Nov 2026): Warcraft Tavern Forever Shadow Priest guide and priest leveling
-- guide, wowtbc.gg Forever Shadow guide. Forever adds Devouring Plague and Shadow
-- Word: Death for everyone, Vampiric Embrace with full uptime, Silence as interrupt.

local DOT_TIME = { ["Shadow Word: Pain"] = 18, ["Devouring Plague"] = 24, ["Vampiric Embrace"] = 60 }
local FORTITUDE = { "Power Word: Fortitude", "Prayer of Fortitude" }
local SHADOW_PROT = { "Shadow Protection", "Prayer of Shadow Protection" }
local SPIRIT = { "Divine Spirit", "Prayer of Spirit" }

---------------------------------------------------------------------------
-- DoTs: in combat the target's auras can be hidden; then we fall back to
-- when you last cast the DoT on that target (your own casts, official event).
---------------------------------------------------------------------------
local cast = {} -- [guid] = { [spell] = time }

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
	return math.max(0, (DOT_TIME[name] or 15) - (ctx.now - t))
end

local function needsDot(ctx, name)
	if not ctx:Ready(name) then return false end
	if ctx.casting == name then return false end
	return dotLeft(ctx, name) < 1.5
end

local function weakenedSoul()
	return CK:FindAura("player", "Weakened Soul", "HARMFUL") ~= nil
end

local function shadowform(ctx)
	return ctx:Buff("Shadowform")
end

---------------------------------------------------------------------------
-- Shared pieces of the rotations
---------------------------------------------------------------------------
-- Silence (Forever: also an interrupt) when the target casts something interruptible
local function interrupt(ctx, push)
	if ctx.targetInterruptible and ctx:Ready("Silence") then push("Silence", "defensive") end
end

local function defensive(ctx, push)
	local onMe = ctx.targetingMe ~= false and ctx.inCombat
	-- shield: no pushback on your casts; Weakened Soul blocks a new one
	if onMe and ctx.healthPct < 0.8 and ctx:Missing("Power Word: Shield") and not weakenedSoul()
		and ctx:Ready("Power Word: Shield") then
		push("Power Word: Shield", "defensive")
	end
	-- two or more on you and low: fear them off (careful, they can run into more mobs)
	if ctx.inCombat and ctx.healthPct < 0.35 and ctx.attackers >= 2 and ctx:Ready("Psychic Scream") then
		push("Psychic Scream", "defensive")
	end
	-- in a group: Fade drops threat when the mob is on you
	if IsInGroup() and ctx.targetingMe == true and ctx:Ready("Fade") then push("Fade", "defensive") end
end

-- heal yourself when it gets close (Shadowform blocks healing: leave it yourself)
local function selfHeal(ctx, push)
	if shadowform(ctx) or ctx.healthPct >= 0.35 then return end
	if ctx:Ready("Flash Heal") then push("Flash Heal", "defensive")
	elseif ctx:Ready("Heal") and not ctx.moving then push("Heal", "defensive")
	elseif ctx:Ready("Lesser Heal") and not ctx.moving then push("Lesser Heal", "defensive") end
	if ctx:Missing("Renew") and ctx:Ready("Renew") then push("Renew", "defensive") end
end

local function manaTools(ctx, push)
	if ctx.inCombat and ctx.manaPct < 0.35 and ctx:Ready("Shadowfiend") then push("Shadowfiend", "hint") end
end

---------------------------------------------------------------------------
-- Shadow
---------------------------------------------------------------------------
local function shadow(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if ctx:Missing("Shadowform") and ctx:Ready("Shadowform") then push("Shadowform") end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	defensive(ctx, push)
	selfHeal(ctx, push)
	local lowMana = ctx.manaPct < 0.2
	local execute = ctx.targetHealthPct and ctx.targetHealthPct < 0.2
	-- target health hidden in combat: Shadow Word: Death on cooldown (the guides say so)
	local deathNow = execute or ctx.targetHealthPct == nil or ctx.targetIsBoss
	-- a nearly dead mob is not worth a new DoT
	local dotWorth = not (ctx.targetHealthPct and ctx.targetHealthPct < 0.25 and not ctx.targetIsBoss)

	if ctx.aoe then
		-- Shadow Word: Pain on every target (tab yourself), Plague on the main one,
		-- Mind Sear when you have it, Holy Nova outside Shadowform when they are on you
		if needsDot(ctx, "Shadow Word: Pain") then push("Shadow Word: Pain") end
		if needsDot(ctx, "Devouring Plague") then push("Devouring Plague") end
		if not ctx.moving and ctx:Ready("Mind Sear") then push("Mind Sear") end
		if not shadowform(ctx) and ctx.nearby >= 3 and ctx:Ready("Holy Nova") then push("Holy Nova") end
		if ctx.autoAoe or ctx.nearby >= 2 or #list > 0 then
			if ctx:Ready("Mind Blast") and not ctx.moving then push("Mind Blast") end
			if ctx:Ready("Shadow Word: Death") then push("Shadow Word: Death") end
			if not ctx.moving and ctx:Known("Mind Flay") then push("Mind Flay") end
			manaTools(ctx, push)
			return
		end
	end

	-- out of combat: open with Mind Blast (Starshards for a Night Elf without it)
	if not ctx.inCombat and not ctx.moving then
		if ctx:Ready("Mind Blast") then push("Mind Blast") end
	end
	-- 1. DoTs up (they tag the mob at once)
	if dotWorth and needsDot(ctx, "Shadow Word: Pain") then push("Shadow Word: Pain") end
	if dotWorth and needsDot(ctx, "Devouring Plague") then push("Devouring Plague") end
	-- 2. Vampiric Embrace on the target (heals you, Forever: full uptime)
	if dotWorth and needsDot(ctx, "Vampiric Embrace") then push("Vampiric Embrace") end
	-- 3. Inner Focus right before Mind Blast (free and more crit)
	if ctx.inCombat and ctx:Ready("Inner Focus") and ctx:Ready("Mind Blast") then push("Inner Focus") end
	-- 4. Mind Blast on cooldown
	if not ctx.moving and ctx:Ready("Mind Blast") then push("Mind Blast") end
	-- 5. Shadow Word: Death (execute, or on cooldown when health is hidden)
	if deathNow and ctx:Ready("Shadow Word: Death") then push("Shadow Word: Death") end
	-- 6. Night Elf: Starshards (channel, no mana)
	if not ctx.moving and ctx:Ready("Starshards") then push("Starshards") end
	manaTools(ctx, push)
	-- moving: instants only
	if ctx.moving then
		if ctx:Ready("Shadow Word: Death") then push("Shadow Word: Death") end
		if needsDot(ctx, "Shadow Word: Pain") then push("Shadow Word: Pain") end
	end
	-- 7. wand when mana is low (Spirit Tap and regen do the rest)
	if not ctx.moving and ctx:Known("Shoot") and lowMana then push("Shoot") end
	-- 8. filler: Mind Flay (let it finish: Forever puts most damage in the last tick)
	if not ctx.moving then
		if ctx:Known("Mind Flay") then push("Mind Flay")
		elseif ctx:Known("Shoot") and ctx.inCombat then push("Shoot")
		else push("Smite") end
	end
end

---------------------------------------------------------------------------
-- Holy / Discipline (solo leveling: Smite, Holy Fire, Shadow Word: Pain, wand)
---------------------------------------------------------------------------
local function holy(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	defensive(ctx, push)
	selfHeal(ctx, push)
	local lowMana = ctx.manaPct < 0.3
	if ctx.aoe and ctx.nearby >= 3 and ctx:Ready("Holy Nova") then push("Holy Nova") end
	if not ctx.inCombat and not ctx.moving and ctx:Ready("Holy Fire") then push("Holy Fire") end
	if needsDot(ctx, "Shadow Word: Pain") then push("Shadow Word: Pain") end
	if not ctx.moving and ctx:Ready("Mind Blast") then push("Mind Blast") end
	if ctx.targetHealthPct and ctx.targetHealthPct < 0.2 and ctx:Ready("Shadow Word: Death") then push("Shadow Word: Death") end
	if not ctx.moving and ctx:Ready("Starshards") then push("Starshards") end
	if not ctx.moving and ctx:Known("Shoot") and (lowMana or ctx.inCombat) then push("Shoot") end
	if not ctx.moving then push("Smite") end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Priest = {
	defaultSpec = "SHADOW",
	specs = {
		SHADOW = { name = "Shadow", icon = 136207, rotation = shadow },
		DISCIPLINE = { name = "Discipline", icon = 135940, rotation = holy },
		HOLY = { name = "Holy", icon = 237542, rotation = holy },
	},
	specOrder = { "SHADOW", "DISCIPLINE", "HOLY" },
	partyBuffs = {
		{ spell = "Power Word: Fortitude", names = FORTITUDE },
	},
	buffOptions = {
		{ "innerfire", "Inner Fire" },
		{ "fortitude", "Power Word: Fortitude" },
		{ "shadowprot", "Shadow Protection" },
		{ "spirit", "Divine Spirit" },
	},
}

function Priest.Always(ctx, list, add)
	if ctx.fallTime > 1 and ctx:Ready("Levitate") then add(list, "Levitate", "defensive", true) end
	-- Night Elf: Elune's Grace (less ranged damage taken) when a caster or archer is on you
	if ctx.inCombat and ctx.healthPct < 0.5 and ctx.targetingMe == true and ctx:Ready("Elune's Grace") then
		add(list, "Elune's Grace", "defensive", true)
	end
	if ctx.control == "FEAR" and ctx:Ready("Will of the Forsaken") then add(list, "Will of the Forsaken", "defensive", true) end
end

function Priest:OnEnable()
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
	-- forget old targets now and then
	CK:On("PLAYER_REGEN_ENABLED", function()
		local now = GetTime()
		for g, t in pairs(cast) do
			local keep = false
			for _, v in pairs(t) do if now - v < 60 then keep = true end end
			if not keep then cast[g] = nil end
		end
	end)
end

CK:RegisterClass("PRIEST", Priest)

---------------------------------------------------------------------------
-- Buffs
---------------------------------------------------------------------------
CK:AddReminderProvider(function(add)
	local inCombat = InCombatLockdown()

	-- shown always (or only when low, per setting), red when missing or running low
	local function buff(key, names, spell, missingText)
		if CK.char.leveling.buffsOff[key] then return end
		local found, hidden
		for _, n in ipairs(names) do
			local a, h = CK:FindAura("player", n, "HELPFUL")
			if a then found = n break end
			hidden = hidden or h
		end
		local cfg = CK.char.leveling
		if not found and hidden then
			-- auras hidden (combat): keep the button, don't call it missing
			add({ key = key, icon = CK:SpellTexture(spell), count = "", always = cfg.buffMode == "always",
				warn = false, spell = spell, tooltip = spell })
			return
		end
		local left = found and CK:AuraRemaining("player", found, "HELPFUL")
		local text = not found and "!" or ""
		if left and left ~= math.huge and left ~= 1 then
			text = left >= 3600 and ("%dh"):format(left / 3600) or (left >= 60 and ("%dm"):format(left / 60) or ("%ds"):format(left))
		end
		local low = not found or (left and left ~= 1 and left < cfg.buffWarnMinutes * 60)
		add({ key = key, icon = CK:SpellTexture(spell), count = text, always = cfg.buffMode == "always" or low,
			warn = not inCombat and low, spell = spell, tooltip = found and found or missingText })
	end

	if CK:Known("Inner Fire") then buff("innerfire", { "Inner Fire" }, "Inner Fire", L["Inner Fire is missing."]) end
	if CK:Known("Power Word: Fortitude") then
		buff("fortitude", FORTITUDE, "Power Word: Fortitude", L["Power Word: Fortitude is missing."])
	end
	if CK:Known("Shadow Protection") then
		buff("shadowprot", SHADOW_PROT, "Shadow Protection", L["Shadow Protection is missing."])
	end
	if CK:Known("Divine Spirit") then buff("spirit", SPIRIT, "Divine Spirit", L["Divine Spirit is missing."]) end
end)
