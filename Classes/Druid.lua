-- Casters of Azeroth by DinX: druid module, Balance and Restoration (beta:
-- built from the leveling guides, not yet played with). Visual only.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local Safe = CK.Safe

if select(2, UnitClass("player")) ~= "DRUID" then return end

local DOT_TIME = { ["Moonfire"] = 12, ["Insect Swarm"] = 12, ["Faerie Fire"] = 40 }
local MOTW = { "Mark of the Wild", "Gift of the Wild" }
-- shapes that block your spells: leave them yourself, we don't suggest casts then
local SHAPES = { "Bear Form", "Dire Bear Form", "Cat Form", "Travel Form", "Aquatic Form", "Flight Form", "Swift Flight Form" }

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
	return math.max(0, (DOT_TIME[name] or 12) - (ctx.now - t))
end

local function needsDot(ctx, name)
	if not ctx:Ready(name) or ctx.casting == name then return false end
	return dotLeft(ctx, name) < 1.5
end

local function shapeshifted(ctx)
	for _, n in ipairs(SHAPES) do if ctx:Buff(n) then return n end end
end

---------------------------------------------------------------------------
-- Shared pieces
---------------------------------------------------------------------------
local function defensive(ctx, push)
	if not ctx.inCombat then return end
	if ctx.targetingMe ~= false and ctx.healthPct < 0.5 and ctx:Ready("Barkskin") then push("Barkskin", "defensive") end
	-- rooted mob can't hit you from range
	if ctx.targetingMe == true and ctx.healthPct < 0.6 and ctx:Ready("Entangling Roots") and not ctx.moving then
		push("Entangling Roots", "defensive")
	end
end

local function selfHeal(ctx, push)
	if ctx.healthPct >= 0.4 then return end
	if ctx:Ready("Swiftmend") then push("Swiftmend", "defensive") end
	if ctx:Missing("Rejuvenation") and ctx:Ready("Rejuvenation") then push("Rejuvenation", "defensive") end
	if not ctx.moving then
		if ctx:Ready("Regrowth") then push("Regrowth", "defensive")
		elseif ctx:Ready("Healing Touch") then push("Healing Touch", "defensive") end
	end
end

local function manaTools(ctx, push)
	if ctx.inCombat and ctx.manaPct < 0.2 and ctx:Ready("Innervate") then push("Innervate", "hint") end
end

---------------------------------------------------------------------------
-- Balance (leveling: Wrath to pull, Moonfire / Insect Swarm, Starfire filler)
---------------------------------------------------------------------------
local function balance(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if ctx:Missing("Moonkin Form") and ctx:Ready("Moonkin Form") and not shapeshifted(ctx) then push("Moonkin Form") end
	if not ctx.hostile or shapeshifted(ctx) then return end
	defensive(ctx, push)
	selfHeal(ctx, push)
	if ctx.aoe and not ctx.moving then
		if ctx:Ready("Hurricane") then push("Hurricane") end
	end
	-- pull with a long cast out of combat
	if not ctx.inCombat and not ctx.moving and not ctx.casting then
		if ctx:Ready("Starfire") then push("Starfire") elseif ctx:Ready("Wrath") then push("Wrath") end
	end
	if needsDot(ctx, "Faerie Fire") and ctx.targetIsBoss then push("Faerie Fire") end
	local worth = not (ctx.targetHealthPct and ctx.targetHealthPct < 0.25 and not ctx.targetIsBoss)
	if worth and needsDot(ctx, "Insect Swarm") then push("Insect Swarm") end
	if worth and needsDot(ctx, "Moonfire") then push("Moonfire") end
	manaTools(ctx, push)
	if ctx.moving then
		if ctx:Ready("Moonfire") then push("Moonfire") end
		return
	end
	-- Starfire when the mob is still far, Wrath (faster) once it is on you
	if ctx:Ready("Starfire") and ctx.targetingMe ~= true then push("Starfire") end
	push(ctx:Known("Wrath") and "Wrath" or "Starfire")
end

---------------------------------------------------------------------------
-- Restoration: heal in a group (you pick who, e.g. mouseover), Balance solo
---------------------------------------------------------------------------
local PARTY = { "player", "party1", "party2", "party3", "party4" }

local function unitPct(u)
	if not UnitExists(u) or Safe(UnitIsDeadOrGhost(u), true) or not Safe(UnitIsConnected(u), true) then return end
	local hp, max = Safe(UnitHealth(u), nil), Safe(UnitHealthMax(u), nil)
	if type(hp) ~= "number" or type(max) ~= "number" or max <= 0 then return end
	if u ~= "player" and Safe(UnitInRange(u), true) == false then return end
	return hp / max
end

local function myAura(u, name) return CK:FindAura(u, name, "HELPFUL|PLAYER") end

local function heal(ctx, push)
	local known, injured, low, pct, tank, tankPct = 0, 0, nil, 1, nil, nil
	for _, u in ipairs(PARTY) do
		local p = unitPct(u)
		if p then
			known = known + 1
			if p < 0.85 then injured = injured + 1 end
			if p < pct then low, pct = u, p end
			if u ~= "player" and UnitGroupRolesAssigned and Safe(UnitGroupRolesAssigned(u), "NONE") == "TANK" then tank, tankPct = u, p end
		end
	end
	if known == 0 then return false end
	local still, n = not ctx.moving, 0
	local function suggest(s, k) n = n + 1 push(s, k) end
	if pct < 0.3 then
		if ctx:Ready("Nature's Swiftness") then suggest("Nature's Swiftness", "hint") end
		if ctx:Ready("Swiftmend") then suggest("Swiftmend") end
		if ctx:Ready("Regrowth") and still then suggest("Regrowth") end
	end
	if injured >= 3 and still and ctx:Ready("Tranquility") and pct < 0.5 then suggest("Tranquility") end
	if tank and ctx.inCombat and ctx:Ready("Lifebloom") and not myAura(tank, "Lifebloom") then suggest("Lifebloom") end
	if pct < 0.9 and low and not myAura(low, "Rejuvenation") and ctx:Ready("Rejuvenation") then suggest("Rejuvenation") end
	if pct < 0.6 and still then
		if not myAura(low, "Regrowth") and ctx:Ready("Regrowth") then suggest("Regrowth") end
		if ctx:Ready("Healing Touch") then suggest("Healing Touch") end
	end
	return n > 0
end

local function restoration(ctx, list, add)
	local function push(n, k) add(list, n, k) end
	if ctx:Missing("Tree of Life") and ctx:Ready("Tree of Life") and IsInGroup() and not shapeshifted(ctx) then push("Tree of Life") end
	if IsInGroup() then
		manaTools(ctx, push)
		if not heal(ctx, push) and ctx.manaPct > 0.6 then balance(ctx, list, add) end
		return
	end
	balance(ctx, list, add)
end

---------------------------------------------------------------------------
-- Registration
---------------------------------------------------------------------------
local Druid = {
	beta = true,
	defaultSpec = "BALANCE",
	specs = {
		BALANCE = { name = "Balance", icon = 136096, rotation = balance },
		RESTORATION = { name = "Restoration", icon = 136041, rotation = restoration, healer = true },
	},
	specOrder = { "BALANCE", "RESTORATION" },
	partyBuffs = {
		{ spell = "Mark of the Wild", names = MOTW },
		{ spell = "Thorns", names = { "Thorns" } },
	},
	buffOptions = {
		{ "motw", "Mark of the Wild" },
		{ "thorns", "Thorns (solo only)" },
		{ "omen", "Omen of Clarity" },
	},
}

function Druid.Always(ctx, list, add)
	if ctx.control == "ROOT" and ctx:Ready("Travel Form") then add(list, "Travel Form", "defensive", true) end
end

function Druid:OnEnable()
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

CK:RegisterClass("DRUID", Druid)

---------------------------------------------------------------------------
-- Buffs
---------------------------------------------------------------------------
CK:AddReminderProvider(function(add)
	local inCombat = InCombatLockdown()
	local cfg = CK.char.leveling
	local function buff(key, names, spell, missingText, anyTarget)
		if cfg.buffsOff[key] then return end
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
	if CK:Known("Mark of the Wild") then buff("motw", MOTW, "Mark of the Wild", L["Mark of the Wild is missing."], true) end
	if CK:Known("Thorns") and not IsInGroup() then buff("thorns", { "Thorns" }, "Thorns", L["Thorns is missing."], true) end
	if CK:Known("Omen of Clarity") then buff("omen", { "Omen of Clarity" }, "Omen of Clarity", L["Omen of Clarity is missing."]) end
end)
