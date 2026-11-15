-- Casters of Azeroth by DinX: a cast log for analysis outside the game.
-- Every spell you cast is written down with what the rotation helper
-- suggested at that moment (when the cast began), your mana and health, the
-- target's health, combat and AoE state, level and spec. The log lives in the
-- account's saved variables (written on logout or /reload), per character,
-- newest kept. Recording only: it reads your own casts, nothing else.
local _, ns = ...
local CK = ns.CK
local Safe = CK.Safe

local C = CK:NewModule("Coach")

local KEEP = 20000 -- casts kept per character (the uploader keeps them all on the site)

local function db()
	local d = CK.db.coach
	if type(d) ~= "table" then d = { version = 1, chars = {} } CK.db.coach = d end
	if type(d.chars) ~= "table" then d.chars = {} end
	return d
end

local function me()
	local guid = Safe(UnitGUID("player"), nil)
	if type(guid) ~= "string" then return end
	local d = db()
	local c = d.chars[guid]
	if not c then
		c = { log = {} }
		d.chars[guid] = c
	end
	c.name = Safe(UnitName("player"), nil) or c.name
	c.class = CK.playerClass
	return c
end

local function pct(v) return type(v) == "number" and math.floor(v * 100 + 0.5) or nil end

-- the helper's first two suggestions right now
local function suggestion()
	local R = CK.Rotation
	local list = R and R.current or {}
	local a, b = list[1], list[2]
	local btn = a and R.ButtonsFor and #(R:ButtonsFor(a.name) or {}) or nil
	return a and a.name, a and a.kind, b and b.name, btn
end

local function number(v)
	v = Safe(v, nil)
	return type(v) == "number" and math.floor(v + 0.5) or nil
end

local function targetName()
	if not UnitExists("target") then return end
	local n = Safe(UnitName("target"), nil)
	return type(n) == "string" and n or nil
end

-- mana a spell costs (at your rank), and its cast time in ms
local costCache, timeCache = {}, {}
local function manaCost(id)
	if costCache[id] == nil then
		local cost = false
		if C_Spell and C_Spell.GetSpellPowerCost then
			local ok, list = pcall(C_Spell.GetSpellPowerCost, id)
			if ok and type(list) == "table" then
				for _, c in ipairs(list) do
					if type(c) == "table" and Safe(c.type, nil) == 0 then cost = number(c.cost) or false end
				end
			end
		end
		costCache[id] = cost
	end
	return costCache[id] or nil
end

local function castTime(id)
	if timeCache[id] == nil then
		local ms = false
		if C_Spell and C_Spell.GetSpellInfo then
			local ok, info = pcall(C_Spell.GetSpellInfo, id)
			if ok and type(info) == "table" then ms = number(info.castTime) or false end
		elseif GetSpellInfo then
			local ok, _, _, _, t = pcall(GetSpellInfo, id)
			if ok then ms = number(t) or false end
		end
		timeCache[id] = ms
	end
	return timeCache[id] or nil
end
CK:On("SPELLS_CHANGED", function() wipe(costCache) wipe(timeCache) end) -- new ranks, new talents

local pending = {} -- [castGUID] = what was suggested when that cast began

function C:Begin(castGUID)
	if type(castGUID) ~= "string" then return end
	local s1, k1, s2, b1 = suggestion()
	pending[castGUID] = { s1 = s1, k1 = k1, s2 = s2, b1 = b1 }
end

-- one entry per cast: short keys keep the saved file small
function C:Record(spellID, castGUID)
	if CK.char.rotation.coach == false then return end
	local id = Safe(spellID, nil)
	if type(id) ~= "number" then return end
	local c = me()
	if not c then return end
	local R = CK.Rotation
	local ctx = R and R.ctx or {}
	local p = type(castGUID) == "string" and pending[castGUID]
	if p then pending[castGUID] = nil end
	local s1, k1, s2, b1
	if p then s1, k1, s2, b1 = p.s1, p.k1, p.s2, p.b1 else s1, k1, s2, b1 = suggestion() end
	local _, specKey = CK:GetSpec()
	local tg = Safe(UnitGUID("target"), nil)
	local log = c.log
	log[#log + 1] = {
		at = time(), gt = math.floor(GetTime() * 10 + 0.5) / 10,
		id = id, sp = CK.GetSpellName and CK.GetSpellName(id) or nil,
		s1 = s1, k1 = k1, s2 = s2, b1 = b1,
		mp = pct(ctx.manaPct), hp = pct(ctx.healthPct), th = pct(ctx.targetHealthPct),
		cb = ctx.inCombat and 1 or 0, ao = ctx.aoe and 1 or 0, nb = ctx.nearby,
		mv = ctx.moving and 1 or 0, boss = ctx.targetIsBoss and 1 or nil,
		lv = Safe(UnitLevel("player"), nil), spec = specKey,
		tg = type(tg) == "string" and tg:match("%-(%x+)$") or nil, -- last part: tells targets apart
		tn = targetName(), tl = Safe(UnitLevel("target"), nil),
		src = CK.char.rotation.source,
		-- mana and health as numbers (nil when the client hides them), the spell's price and cast time
		ma = number(UnitPower("player", 0)), mm = number(UnitPowerMax("player", 0)),
		he = number(UnitHealth("player")), hm = number(UnitHealthMax("player")),
		mc = manaCost(id), ct = castTime(id),
	}
	while #log > KEEP do table.remove(log, 1) end
	-- forget casts that never finished
	if next(pending) then
		local n = 0
		for _ in pairs(pending) do n = n + 1 end
		if n > 20 then wipe(pending) end
	end
end

function C:OnEnable()
	CK:On("UNIT_SPELLCAST_START", function(_, unit, castGUID)
		if unit == "player" then pcall(C.Begin, C, Safe(castGUID, nil)) end
	end)
	CK:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, castGUID)
		if unit == "player" then pcall(C.Begin, C, Safe(castGUID, nil)) end
	end)
	CK:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, castGUID, spellID)
		if unit == "player" then pcall(C.Record, C, spellID, Safe(castGUID, nil)) end
	end)
end
