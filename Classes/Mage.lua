-- Casters of Azeroth by DinX: mage module (Forever leveling guide priorities)
local _, ns = ...
local CK = ns.CK
local L = CK.L

if select(2, UnitClass("player")) ~= "MAGE" then return end

-- Conjured items, best rank last.
local WATER = { 5350, 2288, 2136, 3772, 8077, 8078, 8079 }
local FOOD = { 5349, 1113, 1114, 1487, 8075, 8076, 22895 }
local GEMS = { [5514] = "Mana Agate", [5513] = "Mana Jade", [8007] = "Mana Citrine", [8008] = "Mana Ruby" }
local GEM_SPELLS = { "Conjure Mana Ruby", "Conjure Mana Citrine", "Conjure Mana Jade", "Conjure Mana Agate" }
local ARMORS = { "Frost Armor", "Ice Armor", "Mage Armor", "Molten Armor" }
local FROZEN = { "Frost Nova", "Frostbite", "Freeze" }
local BETTER_WATER = { [5] = "Ice Cold Milk", [15] = "Melon Juice", [25] = "Sweet Nectar", [35] = "Moonberry Juice", [45] = "Morning Glory Dew" }

local function indexOf(t, v)
	for i, x in ipairs(t) do if x == v then return i end end
end

-- Count conjured water/food/gems in the bags and remember the best of each.
local bags = { water = 0, food = 0, gems = 0 }
local function scanBags()
	bags.water, bags.food, bags.gems = 0, 0, 0
	bags.bestWater, bags.bestFood, bags.gem = nil, nil, nil
	local wRank, fRank = 0, 0
	CK:ForEachBagItem(function(_, _, info)
		local id, n = info.itemID, info.stackCount or 1
		local w, f = indexOf(WATER, id), indexOf(FOOD, id)
		if w then
			bags.water = bags.water + n
			if w > wRank then wRank, bags.bestWater = w, id end
		elseif f then
			bags.food = bags.food + n
			if f > fRank then fRank, bags.bestFood = f, id end
		elseif GEMS[id] then
			bags.gems = bags.gems + 1
			bags.gem = id
		end
	end)
end

local function firstKnown(list)
	for _, n in ipairs(list) do
		if CK:Known(n) then return n end
	end
end

local function hasAnyBuff(list)
	for _, n in ipairs(list) do
		if CK:FindAura("player", n, "HELPFUL") then return true end
	end
end

local function gemReady()
	if not bags.gem then return end
	local s, d = C_Container and C_Container.GetItemCooldown and C_Container.GetItemCooldown(bags.gem)
	if not s and GetItemCooldown then s, d = GetItemCooldown(bags.gem) end
	if s and s > 0 and d > 1.5 then return end
	return GEMS[bags.gem]
end

local function frozen(ctx)
	local best = 0
	for _, n in ipairs(FROZEN) do
		best = math.max(best, ctx:DebuffRemaining(n))
	end
	return best
end

-- target within about 10 yards (official range checks, see Rotation.lua)
local function inMelee()
	local R = CK.Rotation
	return R and R.IsClose and R.IsClose("target") or false
end

---------------------------------------------------------------------------
-- Shared pieces of the rotations
---------------------------------------------------------------------------
local function manaTools(ctx, push)
	if ctx.manaPct < 0.15 then
		local gem = gemReady()
		if gem then push(gem, "hint") end
		if ctx:Ready("Evocation") and ctx.targetingMe == false then push("Evocation", "hint") end
	end
end

local function defensive(ctx, push)
	if ctx.targetingMe ~= false and ctx.inCombat and ctx:Ready("Frost Nova") and inMelee() then
		push("Frost Nova", "defensive")
	end
end

-- Counterspell (silences the school) when the target casts something interruptible
local function interrupt(ctx, push)
	if ctx.targetInterruptible and ctx:Ready("Counterspell") then push("Counterspell", "defensive") end
end

-- Frost leveling (Warcraft Tavern / Icy Veins Forever guides, Nov 2026)
local function frost(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	local lowMana = ctx.manaPct < 0.25
	local execute = ctx.targetHealthPct and ctx.targetHealthPct < 0.2
	-- target health hidden in combat: the guides say Fire Blast on cooldown then
	local fireBlastNow = execute or (ctx.inCombat and ctx.targetHealthPct == nil)
	local melee = inMelee()

	if ctx.aoe then
		-- Nova the pack, Cone of Cold for Fingers of Frost, Ice Lance the frozen,
		-- Arcane Explosion in melee, Flamestrike / Blizzard from range
		-- close = enemies within ~10 yd (nameplates), or at least the target
		local close = ctx.nearby >= 2 or melee
		if ctx:Ready("Ice Barrier") and ctx:Missing("Ice Barrier") then push("Ice Barrier") end
		if close and ctx:Ready("Frost Nova") then push("Frost Nova", "defensive") end
		if close and ctx:Ready("Cone of Cold") then push("Cone of Cold") end
		if (ctx:Buff("Fingers of Frost") or frozen(ctx) > 0) and ctx:Ready("Ice Lance")
			and ctx:InRange("Ice Lance") ~= false then
			push("Ice Lance", "proc")
		end
		if close and ctx:Ready("Arcane Explosion") then push("Arcane Explosion") end
		-- nothing close yet: ground AoE from range
		if not ctx.moving and not close and ctx:Ready("Blizzard") then push("Blizzard") end
		if not ctx.moving and ctx:Ready("Flamestrike") then push("Flamestrike") end
		if not ctx.moving and ctx:Ready("Blizzard") then push("Blizzard") end
		-- AoE mode with a single enemy left: fall through to the single-target priority
		if ctx.autoAoe or ctx.nearby >= 2 or #list > 0 then
			manaTools(ctx, push)
			return
		end
	end

	-- 1. Ice Barrier up (absorb, no pushback, more Frost damage)
	if ctx:Ready("Ice Barrier") and ctx:Missing("Ice Barrier") then push("Ice Barrier") end
	-- 2. in trouble: Mana Shield when low on health and the mob is on you
	if ctx.targetingMe ~= false and ctx.healthPct < 0.4 and ctx:Missing("Ice Barrier")
		and ctx:Missing("Mana Shield") and ctx:Ready("Mana Shield") then
		push("Mana Shield", "defensive")
	end
	-- 3. Frost Nova in melee (then step back yourself); Cold Snap resets it
	defensive(ctx, push)
	if ctx.targetingMe ~= false and melee and frozen(ctx) == 0 and ctx:Known("Frost Nova")
		and not ctx:Ready("Frost Nova") and ctx:Ready("Cold Snap") then
		push("Cold Snap", "defensive")
	end
	-- 4. finisher: Fire Blast on a nearly dead target
	if fireBlastNow and ctx:Ready("Fire Blast") then push("Fire Blast") end
	-- 5. Fingers of Frost: spend it on Ice Lance
	if ctx:Buff("Fingers of Frost") and ctx:Ready("Ice Lance") then push("Ice Lance", "proc") end
	-- 6. frozen target: Frostbolt, then Ice Lance so both shatter
	local fz = frozen(ctx)
	if fz > 0 and ctx:Known("Ice Lance") then
		local castingBolt = ctx.casting == "Frostbolt"
		if castingBolt or fz < 2.5 then
			if ctx:Ready("Ice Lance") then push("Ice Lance", "proc") end
		else
			push("Frostbolt")
			if ctx:Ready("Ice Lance") then push("Ice Lance", "proc") end
		end
	end
	-- 7. procs: Missile Barrage, Clearcasting (free Frostbolt)
	if ctx:Buff("Missile Barrage") and ctx:Ready("Arcane Missiles") then push("Arcane Missiles", "proc") end
	if ctx:Buff("Clearcasting") and ctx:Known("Frostbolt") then push("Frostbolt", "proc") end
	-- moving: instants only
	if ctx.moving then
		if ctx:Ready("Fire Blast") then push("Fire Blast") end
		if ctx:Ready("Ice Lance") then push("Ice Lance") end
		if melee and ctx:Ready("Arcane Explosion") then push("Arcane Explosion") end
	end
	manaTools(ctx, push)
	-- 8. wand: save mana when low, or finish a low target while Fire Blast cools down
	if not ctx.moving and ctx:Known("Shoot") and (lowMana or execute) then push("Shoot") end
	-- 9. filler
	if ctx:Known("Frostbolt") then push("Frostbolt") else push("Fireball") end
	if ctx:Ready("Fire Blast") then push("Fire Blast") end
end

local function fire(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	if ctx.aoe then
		if not ctx.moving and ctx:Ready("Flamestrike") then push("Flamestrike") end
		if not ctx.moving and ctx:Ready("Blizzard") then push("Blizzard") end
		if ctx:Ready("Arcane Explosion") then push("Arcane Explosion") end
		manaTools(ctx, push)
		return
	end
	defensive(ctx, push)
	if not ctx.inCombat and ctx:Ready("Pyroblast") then push("Pyroblast") end
	if ctx:Buff("Missile Barrage") and ctx:Ready("Arcane Missiles") then push("Arcane Missiles", "proc") end
	if ctx:Ready("Fire Blast") then push("Fire Blast") end
	manaTools(ctx, push)
	if not ctx.moving then push("Fireball") end
end

local function arcane(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if not ctx.hostile then return end
	interrupt(ctx, push)
	if ctx.aoe then
		if ctx:Ready("Arcane Explosion") then push("Arcane Explosion") end
		if not ctx.moving and ctx:Ready("Blizzard") then push("Blizzard") end
		manaTools(ctx, push)
		return
	end
	defensive(ctx, push)
	if ctx:Buff("Missile Barrage") and ctx:Ready("Arcane Missiles") then push("Arcane Missiles", "proc") end
	if ctx.inCombat and ctx:Ready("Arcane Power") then push("Arcane Power") end
	if ctx.inCombat and ctx:Ready("Presence of Mind") then push("Presence of Mind") end
	if ctx.moving and ctx:Ready("Fire Blast") then push("Fire Blast") end
	manaTools(ctx, push)
	if not ctx.moving then
		if ctx:Ready("Arcane Missiles") then push("Arcane Missiles") else push(ctx:Known("Frostbolt") and "Frostbolt" or "Fireball") end
	end
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Mage = {
	defaultSpec = "FROST",
	specs = {
		FROST = { name = "Frost", icon = 135846, rotation = frost },
		FIRE = { name = "Fire", icon = 135810, rotation = fire },
		ARCANE = { name = "Arcane", icon = 135932, rotation = arcane },
	},
	specOrder = { "FROST", "FIRE", "ARCANE" },
	-- buffs you can give to party members (buttons next to the party frames)
	partyBuffs = {
		{ spell = "Arcane Intellect", names = { "Arcane Intellect", "Arcane Brilliance" },
			filter = function(unit) return CK.Safe(UnitPowerType(unit), 0) == 0 end }, -- mana users only
	},
	-- buff buttons the settings can switch on/off: { key, label }
	buffOptions = {
		{ "armor", "Armor (Frost, Ice or Mage Armor)" },
		{ "intellect", "Arcane Intellect" },
		{ "dampen", "Dampen Magic (solo only)" },
	},
}

-- Applies with or without a target.
function Mage.Always(ctx, list, add)
	if ctx.fallTime > 1 and ctx:Ready("Slow Fall") then add(list, "Slow Fall", "defensive", true) end
	if (ctx.control == "STUN" or ctx.control == "STUN_MECHANIC" or ctx.control == "ROOT") and ctx:Ready("Blink") then
		add(list, "Blink", "defensive", true)
	end
end

function Mage:OnEnable()
	scanBags()
	CK:On("BAG_UPDATE_DELAYED", scanBags)
	CK:On("PLAYER_LEVEL_UP", function(_, level)
		local drink = BETTER_WATER[level]
		if drink then
			CK:Print(L["Tip: the innkeeper now sells %s, better than your own Conjure Water until your next rank."]:format(drink))
		end
	end)
end

CK:RegisterClass("MAGE", Mage)

---------------------------------------------------------------------------
-- Conjured food and drink, buffs
---------------------------------------------------------------------------
CK:AddReminderProvider(function(add)
	local inCombat = InCombatLockdown()

	if CK:Known("Conjure Water") then
		add({ key = "water", icon = bags.bestWater and CK:ItemIcon(bags.bestWater) or CK:SpellTexture("Conjure Water"),
			count = bags.water, always = true, warn = not inCombat and bags.water < 10,
			tooltip = L["Conjured water: %d"]:format(bags.water), spell = "Conjure Water", use = bags.bestWater })
	end
	if CK:Known("Conjure Food") then
		add({ key = "food", icon = bags.bestFood and CK:ItemIcon(bags.bestFood) or CK:SpellTexture("Conjure Food"),
			count = bags.food, always = true, warn = not inCombat and bags.food < 5,
			tooltip = L["Conjured food: %d"]:format(bags.food), spell = "Conjure Food", use = bags.bestFood })
	end

	local gemSpell = firstKnown(GEM_SPELLS)
	if gemSpell then
		add({ key = "gem", icon = CK:SpellTexture(gemSpell), count = bags.gems > 0 and bags.gems or nil,
			warn = not inCombat and bags.gems == 0, spell = gemSpell, use = bags.gem,
			tooltip = bags.gem and L["Mana gem"] or L["No mana gem in your bags."] })
	end

	-- Eat and drink with one click (out of combat, when you need it)
	if not inCombat and (bags.bestWater or bags.bestFood) then
		local Safe = CK.Safe
		local hp = (Safe(UnitHealth("player"), 1) or 1) / math.max(1, Safe(UnitHealthMax("player"), 1) or 1)
		local mp = (Safe(UnitPower("player", 0), 1) or 1) / math.max(1, Safe(UnitPowerMax("player", 0), 1) or 1)
		if (mp < 0.7 and bags.bestWater) or (hp < 0.7 and bags.bestFood) then
			local lines = {}
			if hp < 0.95 and bags.bestFood then lines[#lines + 1] = "/use item:" .. bags.bestFood end
			if mp < 0.95 and bags.bestWater then lines[#lines + 1] = "/use item:" .. bags.bestWater end
			add({ key = "eatdrink", icon = 132799, always = true, macrotext = table.concat(lines, "\n"),
				tooltip = L["Eat and drink: click to use your conjured food and water."] })
		end
	end

	-- buffs: shown always (or only when low, per setting), red when missing or running low
	local function buff(key, names, spell, missingText)
		if CK.char.leveling.buffsOff[key] then return end
		local found, hidden
		for _, n in ipairs(names) do
			local a, h = CK:FindAura("player", n, "HELPFUL")
			if a then found = n break end
			hidden = hidden or h
		end
		if not found and hidden then
			-- auras hidden (combat): keep the button, don't call it missing
			local cfg = CK.char.leveling
			add({ key = key, icon = CK:SpellTexture(spell), count = "", always = cfg.buffMode == "always",
				warn = false, spell = spell, tooltip = spell })
			return
		end
		local left = found and CK:AuraRemaining("player", found, "HELPFUL")
		local text = not found and "!" or ""
		if left and left ~= math.huge and left ~= 1 then
			text = left >= 3600 and ("%dh"):format(left / 3600) or (left >= 60 and ("%dm"):format(left / 60) or ("%ds"):format(left))
		end
		local cfg = CK.char.leveling
		local low = not found or (left and left ~= 1 and left < cfg.buffWarnMinutes * 60)
		add({ key = key, icon = CK:SpellTexture(spell), count = text, always = cfg.buffMode == "always" or low,
			warn = not inCombat and low, spell = spell,
			tooltip = found and found or missingText })
	end

	local armor = (IsInInstance() and CK:Known("Mage Armor") and "Mage Armor") or firstKnown({ "Ice Armor", "Frost Armor" })
	if armor then buff("armor", ARMORS, armor, L["No armor buff active."]) end
	if CK:Known("Arcane Intellect") then
		buff("intellect", { "Arcane Intellect", "Arcane Brilliance" }, "Arcane Intellect", L["Arcane Intellect is missing."])
	end
	-- Dampen Magic only solo: it also lowers healing you receive
	if CK:Known("Dampen Magic") and not IsInGroup() then
		buff("dampen", { "Dampen Magic", "Amplify Magic" }, "Dampen Magic", L["Dampen Magic is missing (solo: less magic damage taken)."])
	end
end)
