-- Casters of Azeroth by DinX: an estimate of your own mana.
-- The Forever client hides your current mana from addons (the maximum stays
-- visible), so the rotation helper would always think you are full. This keeps
-- a running estimate instead: it starts full, takes off each spell's real cost,
-- adds regeneration (faster while drinking), Life Tap and Evocation, and corrects
-- itself whenever the client says a spell has or lacks the mana to be cast.
-- Reading only: it never casts anything.
local _, ns = ...
local CK = ns.CK
local Safe = CK.Safe

local M = CK:NewModule("Mana")

local FIVE_SEC = 5        -- the five-second rule: little regen right after spending mana
local DRINK_TIME = 30     -- longest a drink lasts
local DRINK_RATE = 1 / 20 -- share of your maximum mana a drink gives per second
local EVO_TICK, EVO_GAIN = 2, 0.15 -- Evocation: 15 % of your mana every 2 seconds

local est            -- estimated mana right now
local spentAt = -100 -- when mana was last spent
local drinkUntil = 0
local evoStart
local lastTick
local failed         -- { id, at } of the last spell that failed to cast
local outOfMana      -- when the client last said "Not enough mana"

local function num(v)
	v = Safe(v, nil)
	return type(v) == "number" and v or nil
end

local function maxMana() return num(UnitPowerMax("player", 0)) end

-- the client's own value, when it shows it
local function realMana()
	local cur, max = num(UnitPower("player", 0)), maxMana()
	if cur and max and max > 0 then return cur, max end
end

local costs = {}
function M:Cost(id)
	if costs[id] == nil then
		local cost = false
		if C_Spell and C_Spell.GetSpellPowerCost then
			local ok, list = pcall(C_Spell.GetSpellPowerCost, id)
			if ok and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and Safe(c.type, nil) == 0 then cost = num(c.cost) or false end
				end
			end
		end
		costs[id] = cost
	end
	return costs[id] or nil
end

local function spellName(id)
	return CK.GetSpellName and CK.GetSpellName(id) or nil
end

-- mana a Life Tap gives: the number before "mana" in its tooltip text, else a share of your maximum
local function lifeTapGain(id, max)
	local text = C_Spell and C_Spell.GetSpellDescription and Safe(C_Spell.GetSpellDescription(id), nil)
	if type(text) == "string" then
		local n = tonumber(text:match("(%d+) mana"))
		if n then return n end
	end
	return max * 0.1
end

local function clamp(max)
	if est < 0 then est = 0 elseif est > max then est = max end
end

-- regeneration per second: the client's own numbers when it shows them, else a guess
local function regen(now, max)
	local base, casting
	if GetManaRegen then base, casting = GetManaRegen() end
	base, casting = num(base), num(casting)
	local inFive = now - spentAt < FIVE_SEC
	local r
	if base then r = inFive and (casting or 0) or base
	else r = inFive and 0 or max * 0.01 end
	if now < drinkUntil then r = r + max * DRINK_RATE end
	return r
end

function M:Tick(now)
	local max = maxMana()
	if not max or max <= 0 then return end
	local cur = realMana()
	if cur then est = cur lastTick = now return end
	if not est then est = max end
	if lastTick then
		local dt = math.max(0, now - lastTick)
		-- a drink stops when you move or start fighting
		if now < drinkUntil and ((num(GetUnitSpeed("player")) or 0) > 0 or Safe(UnitAffectingCombat("player"), false)) then
			drinkUntil = 0
		end
		est = est + regen(now, max) * dt
	end
	lastTick = now
	self:Calibrate()
	clamp(max)
end

-- the client tells whether a spell lacks the mana for it: that pins the estimate
-- between the costs of spells you can and cannot afford
function M:Calibrate()
	if not est then return end
	local lo, hi = 0, math.huge
	for _, id in pairs(CK.known or {}) do
		local cost = self:Cost(id)
		if cost and cost > 0 then
			local usable, noMana
			if C_Spell and C_Spell.IsSpellUsable then usable, noMana = C_Spell.IsSpellUsable(id)
			elseif IsUsableSpell then usable, noMana = IsUsableSpell(id) end
			usable, noMana = Safe(usable, nil), Safe(noMana, nil)
			if noMana == true then hi = math.min(hi, cost - 1)
			elseif usable == true and noMana == false then lo = math.max(lo, cost) end
		end
	end
	if est > hi then est = hi end
	if est < lo then est = lo end
end

-- mana as a share of the maximum, and whether it is the client's own value
function M:Pct()
	local cur, max = realMana()
	if cur then return cur / max, true end
	max = maxMana()
	if not max or max <= 0 then return 1, false end
	if not est then est = max end
	return math.max(0, math.min(1, est / max)), false
end

function M:Spent(id, now)
	local max = maxMana()
	if not max or not est then return end
	local cost = self:Cost(id)
	if cost and cost > 0 then
		est = est - cost
		spentAt = now
	end
	local name = spellName(id)
	if name == "Life Tap" then
		est = est + lifeTapGain(id, max)
	elseif type(name) == "string" and (name:find("Drink") or name:find("Refreshment")) then
		drinkUntil = now + DRINK_TIME
	end
	clamp(max)
end

local function lackedMana(id)
	local cost = id and M:Cost(id)
	if est and cost then est = math.min(est, cost - 1) clamp(maxMana() or est) end
end

function M:OnEnable()
	CK:On("PLAYER_ENTERING_WORLD", function() est = nil lastTick = nil end)
	CK:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, id)
		if unit ~= "player" then return end
		M:Tick(GetTime())
		M:Spent(id, GetTime())
	end)
	CK:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, id)
		if unit == "player" and spellName(id) == "Evocation" then evoStart = GetTime() end
	end)
	CK:On("UNIT_SPELLCAST_CHANNEL_STOP", function(_, unit)
		if unit ~= "player" or not evoStart then return end
		local max = maxMana()
		if max and est then
			est = est + math.min(4, math.floor((GetTime() - evoStart) / EVO_TICK)) * EVO_GAIN * max
			clamp(max)
		end
		evoStart = nil
	end)
	-- "Not enough mana": the spell that just failed costs more than you have
	CK:On("UNIT_SPELLCAST_FAILED", function(_, unit, _, id)
		if unit ~= "player" then return end
		failed = { id = id, at = GetTime() }
		if outOfMana and GetTime() - outOfMana < 0.5 then lackedMana(id) end
	end)
	CK:On("UI_ERROR_MESSAGE", function(_, _, msg)
		msg = Safe(msg, nil)
		if msg == nil or msg ~= _G.ERR_OUT_OF_MANA then return end
		outOfMana = GetTime()
		if failed and GetTime() - failed.at < 0.5 then lackedMana(failed.id) end
	end)
	if C_Timer and C_Timer.NewTicker then
		C_Timer.NewTicker(1, function() M:Tick(GetTime()) end)
	end
end
