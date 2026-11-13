-- Casters of Azeroth by DinX: warlock module (beta: built from the Forever
-- leveling guides of Warcraft Tavern and Method, not yet played with).
-- Forever split the curses: Banes are the DoTs (Bane of Agony, Bane of Doom),
-- Curses the utility (Curse of the Elements); one of each fits on a target.
-- Visual suggestions only, like every class.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local Safe = CK.Safe

if select(2, UnitClass("player")) ~= "WARLOCK" then return end

local DOT_TIME = { ["Corruption"] = 18, ["Bane of Agony"] = 24, ["Immolate"] = 15, ["Siphon Life"] = 30,
	["Unstable Affliction"] = 18, ["Bane of Doom"] = 60, ["Curse of the Elements"] = 300,
	-- the old names, for a client that still uses them
	["Curse of Agony"] = 24, ["Curse of Doom"] = 60,
	-- Demonic Brand: Searing Pain marks the target for your Sayaad (estimate)
	["Searing Pain"] = 12 }
local SOUL_SHARD = 6265
local HEALTHSTONES = { 5512, 19004, 19005, 5511, 19006, 19007, 5509, 19008, 19009, 5510, 19010, 19011, 9421, 19012, 19013 }
local ARMORS = { "Fel Armor", "Demon Armor", "Demon Skin" }
-- the pet to have out, best first per spec (only the ones you know count)
-- (Forever guides: the Voidwalker tanks up to 20, then the Sayaad does the most damage)
local PETS = {
	AFFLICTION = { "Summon Succubus", "Summon Incubus", "Summon Voidwalker", "Summon Imp" },
	DEMONOLOGY = { "Summon Succubus", "Summon Incubus", "Summon Felguard", "Summon Voidwalker", "Summon Imp" },
	DESTRUCTION = { "Summon Succubus", "Summon Incubus", "Summon Voidwalker", "Summon Imp" },
}

---------------------------------------------------------------------------
-- DoTs: in combat the target's auras can be hidden; then we fall back to
-- when you last cast it on that target (your own casts, official event).
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
	if not ctx:Ready(name) or ctx.casting == name then return false end
	return dotLeft(ctx, name) < 1.5
end

local function shards()
	return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(SOUL_SHARD)) or (GetItemCount and GetItemCount(SOUL_SHARD)) or 0
end

local function hasHealthstone()
	for _, id in ipairs(HEALTHSTONES) do
		local n = (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(id)) or (GetItemCount and GetItemCount(id)) or 0
		if n > 0 then return id end
	end
end

local function firstKnown(list)
	for _, n in ipairs(list or {}) do if CK:Known(n) then return n end end
end

local function petAlive()
	return UnitExists("pet") and not Safe(UnitIsDead("pet"), false)
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local function defensive(ctx, push)
	if not ctx.inCombat then return end
	if ctx.healthPct < 0.3 then
		local stone = hasHealthstone()
		local stoneName = stone and ((C_Item and C_Item.GetItemNameByID and C_Item.GetItemNameByID(stone))
			or (GetItemInfo and GetItemInfo(stone)))
		if stoneName then push(stoneName, "defensive") end
		if ctx:Ready("Death Coil") then push("Death Coil", "defensive") end
	end
	if ctx.healthPct < 0.35 and ctx.attackers >= 2 and ctx:Ready("Howl of Terror") then push("Howl of Terror", "defensive") end
end

-- an elite or a boss: worth Curse of the Elements and the long DoTs
local function tough(ctx)
	if ctx.targetIsBoss then return true end
	local c = UnitClassification and Safe(UnitClassification("target"), nil)
	return c == "elite" or c == "rareelite" or c == "worldboss"
end

-- Life Tap when you have more health than mana, Drain Life when health runs low
local function sustain(ctx, push)
	if ctx.manaPct < 0.7 and ctx.healthPct > ctx.manaPct + 0.2 and ctx.healthPct > 0.5 and ctx:Ready("Life Tap") then
		push("Life Tap", "hint")
	end
	if ctx.inCombat and ctx.healthPct < 0.45 and not ctx.moving and ctx:Ready("Drain Life") then push("Drain Life") end
end

-- a shard when the mob is about to die (Drain Soul), up to a few in the bags
local function shardFarm(ctx, push)
	if ctx.targetHealthPct and ctx.targetHealthPct < 0.25 and shards() < 5 and not ctx.moving and ctx:Ready("Drain Soul") then
		push("Drain Soul")
	end
end

local function dots(ctx, push, list)
	local worth = not (ctx.targetHealthPct and ctx.targetHealthPct < 0.3 and not ctx.targetIsBoss)
	if not worth then return end
	for _, n in ipairs(list) do
		if needsDot(ctx, n) then push(n) end
	end
end

-- the Bane (a DoT): Bane of Doom only on long fights (bosses), else Bane of Agony
local function bane(ctx, push)
	local worth = not (ctx.targetHealthPct and ctx.targetHealthPct < 0.3 and not ctx.targetIsBoss)
	if not worth then return end
	if ctx.targetIsBoss then
		for _, n in ipairs({ "Bane of Doom", "Curse of Doom" }) do
			if needsDot(ctx, n) then push(n) return end
		end
	end
	for _, n in ipairs({ "Bane of Agony", "Curse of Agony" }) do
		if ctx:Known(n) then
			if needsDot(ctx, n) then push(n) end
			return
		end
	end
end

-- the Curse (utility, next to the Bane): Curse of the Elements first on elites and bosses
local function curse(ctx, push)
	if tough(ctx) and needsDot(ctx, "Curse of the Elements") then push("Curse of the Elements") end
end

local function filler(ctx, push)
	if ctx.moving then return end
	if ctx:Known("Shoot") and ctx.manaPct < 0.1 then push("Shoot") return end
	push(ctx:Known("Shadow Bolt") and "Shadow Bolt" or "Shoot")
end

---------------------------------------------------------------------------
-- Specs (Forever leveling guides: DoTs first, Shadow Bolt filler, Life Tap)
---------------------------------------------------------------------------
local function affliction(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	defensive(ctx, push)
	-- Nightfall: a free instant Shadow Bolt
	if ctx:Buff("Shadow Trance") and ctx:Ready("Shadow Bolt") then push("Shadow Bolt", "proc") end
	if ctx.aoe and ctx:Ready("Seed of Corruption") and not ctx.moving then push("Seed of Corruption") end
	curse(ctx, push)
	-- Bane of Agony and Corruption; Immolate while leveling (from level 1), until
	-- Unstable Affliction takes its place; Siphon Life on what lives long enough
	bane(ctx, push)
	local wanted = { "Corruption" }
	if not ctx:Known("Unstable Affliction") then wanted[#wanted + 1] = "Immolate" end
	wanted[#wanted + 1] = "Unstable Affliction"
	wanted[#wanted + 1] = "Siphon Life"
	dots(ctx, push, wanted)
	shardFarm(ctx, push)
	sustain(ctx, push)
	if ctx.targetHealthPct and ctx.targetHealthPct < 0.25 and ctx:Ready("Shadowburn") then push("Shadowburn") end
	-- finish: Wrack with health and mana to spare, Drain Life from level 30, else wand or Shadow Bolt
	if not ctx.moving then
		if ctx:Ready("Wrack") and ctx.healthPct > 0.6 and ctx.manaPct > 0.4 then push("Wrack") end
		if (Safe(ctx.level, 0) or 0) >= 30 and ctx:Ready("Drain Life") then push("Drain Life") end
	end
	filler(ctx, push)
end

local function demonology(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	defensive(ctx, push)
	if ctx:Buff("Shadow Trance") and ctx:Ready("Shadow Bolt") then push("Shadow Bolt", "proc") end
	-- Decimation: Soul Fire without a shard
	if ctx:Buff("Decimation") and ctx:Ready("Soul Fire") and not ctx.moving then push("Soul Fire", "proc") end
	if ctx.inCombat and ctx:Ready("Soul Link") and ctx:Missing("Soul Link") and petAlive() then push("Soul Link", "hint") end
	-- Demonic Brand: Searing Pain on your demon's target, again before the brand runs out
	if ctx:Known("Demonic Brand") and petAlive() and needsDot(ctx, "Searing Pain") then push("Searing Pain") end
	curse(ctx, push)
	bane(ctx, push)
	dots(ctx, push, { "Immolate", "Corruption" })
	shardFarm(ctx, push)
	sustain(ctx, push)
	filler(ctx, push)
end

local function destruction(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	defensive(ctx, push)
	if ctx.aoe and not ctx.moving then
		if ctx:Ready("Seed of Corruption") then push("Seed of Corruption") end
		if ctx:Ready("Rain of Fire") then push("Rain of Fire") end
	end
	curse(ctx, push)
	if needsDot(ctx, "Immolate") then push("Immolate") end
	-- Conflagrate on your Immolate, best right before it runs out
	local imm = dotLeft(ctx, "Immolate")
	if ctx:Ready("Conflagrate") and imm > 0 and imm < 5 then push("Conflagrate") end
	bane(ctx, push)
	if needsDot(ctx, "Corruption") then push("Corruption") end
	if ctx:Ready("Conflagrate") and imm > 0 then push("Conflagrate") end
	if ctx.targetHealthPct and ctx.targetHealthPct < 0.25 and ctx:Ready("Shadowburn") then push("Shadowburn") end
	shardFarm(ctx, push)
	sustain(ctx, push)
	if not ctx.moving then
		if ctx:Ready("Incinerate") and dotLeft(ctx, "Immolate") > 0 then push("Incinerate") end
		filler(ctx, push)
	end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Warlock = {
	beta = true,
	defaultSpec = "AFFLICTION",
	specs = {
		AFFLICTION = { name = "Affliction", icon = 136145, rotation = affliction },
		DEMONOLOGY = { name = "Demonology", icon = 136172, rotation = demonology },
		DESTRUCTION = { name = "Destruction", icon = 136186, rotation = destruction },
	},
	specOrder = { "AFFLICTION", "DEMONOLOGY", "DESTRUCTION" },
	partyBuffs = {},
	buffOptions = {
		{ "armor", "Armor (Demon Skin, Demon Armor or Fel Armor)" },
		{ "pet", "Your demon" },
		{ "healthstone", "Healthstone" },
	},
}

function Warlock.Always(ctx, list, add)
	if ctx.control == "FEAR" and ctx:Ready("Will of the Forsaken") then add(list, "Will of the Forsaken", "defensive", true) end
	-- no demon out of combat: summon the one for your spec
	if not ctx.inCombat and not petAlive() and not CK.char.leveling.buffsOff.pet then
		local _, key = CK:GetSpec()
		local pet = firstKnown(PETS[key or "AFFLICTION"])
		if pet and ctx:Ready(pet) and not ctx.moving then add(list, pet, "hint", true) end
	end
end

function Warlock:OnEnable()
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
	CK:On("PLAYER_REGEN_ENABLED", function()
		local now = GetTime()
		for g, t in pairs(cast) do
			local keep = false
			for _, v in pairs(t) do if now - v < 60 then keep = true end end
			if not keep then cast[g] = nil end
		end
	end)
end

CK:RegisterClass("WARLOCK", Warlock)

---------------------------------------------------------------------------
-- Reminders: armor, healthstone
---------------------------------------------------------------------------
CK:AddReminderProvider(function(add)
	local inCombat = InCombatLockdown()
	local off = CK.char.leveling.buffsOff
	local armor = firstKnown(ARMORS)
	if armor and not off.armor then
		local found, hidden
		for _, n in ipairs(ARMORS) do
			local a, h = CK:FindAura("player", n, "HELPFUL")
			if a then found = n break end
			hidden = hidden or h
		end
		local cfg = CK.char.leveling
		add({ key = "armor", icon = CK:SpellTexture(armor), count = (found or hidden) and "" or "!",
			always = cfg.buffMode == "always" or not (found or hidden), warn = not inCombat and not (found or hidden),
			spell = armor, tooltip = found or L["No armor buff active."] })
	end
	local stoneSpell = CK:Known("Create Healthstone") and "Create Healthstone"
	if stoneSpell and not off.healthstone and not hasHealthstone() and not inCombat then
		add({ key = "healthstone", icon = CK:SpellTexture(stoneSpell), count = "!", always = true, warn = true,
			spell = stoneSpell, tooltip = L["No healthstone in your bags."] })
	end
end)
