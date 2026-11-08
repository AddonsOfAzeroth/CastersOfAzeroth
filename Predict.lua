-- Casters of Azeroth by DinX: what will this spell do? An estimate on the health
-- bar for the spell you are casting, or the one under your mouse (action bars,
-- spellbook). Damage: a dark part at the end of the target's bar ("KILL" when
-- it should die); heals and shields: a green / blue part on the friendly target
-- or on you. The number comes from the spell's own tooltip (average, no crits).
-- Display only: it reads tooltips and health, nothing else.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe, IsSecret = CK.Safe, CK.IsSecret

local P = CK:NewModule("Predict")

local COLORS = {
	damage = { 0.55, 0.05, 0.05, 0.85 },
	heal = { 0.25, 1, 0.35, 0.55 },
	absorb = { 0.45, 0.8, 1, 0.55 },
}

local function on()
	local u = CK.char and CK.char.units
	return u and u.enabled ~= false and u.predict ~= false
end

---------------------------------------------------------------------------
-- Reading the spell tooltip
---------------------------------------------------------------------------
local cache, cacheAt = {}, 0

local function tooltipText(spellID)
	local out = {}
	if C_TooltipInfo and C_TooltipInfo.GetSpellByID then
		local ok, data = pcall(C_TooltipInfo.GetSpellByID, spellID)
		if ok and type(data) == "table" and type(data.lines) == "table" then
			for _, line in ipairs(data.lines) do
				local t = Safe(line.leftText, nil)
				if type(t) == "string" then out[#out + 1] = t end
			end
		end
	end
	return out
end

-- { kind = "damage"|"heal"|"absorb", amount = n, over = seconds or nil } or false
local function parse(lines)
	for _, raw in ipairs(lines) do
		local t = raw:lower():gsub("(%d),(%d)", "%1%2"):gsub("%d+%%", "") -- 1,234 -> 1234; drop percentages
		local kind = (t:find("absorb") and "absorb") or (t:find("heal") and "heal") or (t:find("damage") and "damage")
		if kind then
			local lo, hi = t:match("(%d+) to (%d+)")
			local amount
			if lo then
				amount = (tonumber(lo) + tonumber(hi)) / 2
			elseif kind == "damage" then
				amount = tonumber(t:match("(%d+)%s+%a*%s*damage") or t:match("(%d+)%s+damage"))
			elseif kind == "heal" then
				amount = tonumber(t:match("for (%d+)") or t:match("(%d+) health") or t:match("(%d+)"))
			else
				amount = tonumber(t:match("absorb%a*%s+(%d+)") or t:match("(%d+) damage") or t:match("(%d+)"))
			end
			if amount and amount > 0 then
				return { kind = kind, amount = math.floor(amount + 0.5), over = tonumber(t:match("over (%d+) sec")) }
			end
		end
	end
	return false
end

function P:Estimate(spellID)
	spellID = Safe(spellID, nil)
	if type(spellID) ~= "number" then return end
	local now = GetTime()
	if now - cacheAt > 10 then wipe(cache) cacheAt = now end -- spell power and ranks change
	if cache[spellID] == nil then cache[spellID] = parse(tooltipText(spellID)) end
	return cache[spellID] or nil
end
P.Parse = parse -- for tests

---------------------------------------------------------------------------
-- Which spell: the one you cast, else the one under the mouse
---------------------------------------------------------------------------
local casting, hover

local function spellOfAction(slot)
	if not (slot and GetActionInfo) then return end
	local ok, kind, id = pcall(GetActionInfo, slot)
	if not ok then return end
	if kind == "spell" then return id end
	if kind == "macro" and GetMacroSpell then return (GetMacroSpell(id)) end
end

---------------------------------------------------------------------------
-- Drawing on the unit frames
---------------------------------------------------------------------------
local function overlay(f)
	if f.predict then return f.predict end
	local o = CreateFrame("Frame", nil, f.health)
	o:SetAllPoints(f.health)
	o:SetFrameLevel(f.health:GetFrameLevel() + 1)
	o.bar = o:CreateTexture(nil, "ARTWORK")
	o.bar:SetTexture(S.flat)
	o.text = S:Font(o, 12)
	o.text:SetPoint("CENTER", o, "CENTER", 0, 0)
	o:Hide()
	f.predict = o
	return o
end

local function clear(f)
	if f and f.predict then f.predict:Hide() end
end

local function show(f, est)
	local o = overlay(f)
	local u = f.unit
	local cur, max = Safe(UnitHealth(u), nil), Safe(UnitHealthMax(u), nil)
	local a = est.amount
	local c = COLORS[est.kind]
	local sign = est.kind == "damage" and "-" or "+"
	local label = sign .. a .. (est.over and (" / " .. est.over .. "s") or "")
	o.bar:Hide()
	if type(cur) == "number" and type(max) == "number" and max > 0 then
		local w = f.health:GetWidth()
		local x0, x1
		if est.kind == "damage" then
			x0, x1 = math.max(0, cur - a), cur
			if not est.over and a >= cur then label = L["KILL"] end
		else
			x0, x1 = cur, math.min(max, cur + a)
		end
		if x1 > x0 then
			o.bar:ClearAllPoints()
			o.bar:SetPoint("TOPLEFT", f.health, "TOPLEFT", x0 / max * w, 0)
			o.bar:SetPoint("BOTTOMLEFT", f.health, "BOTTOMLEFT", x0 / max * w, 0)
			o.bar:SetWidth(math.max(1, (x1 - x0) / max * w))
			o.bar:SetVertexColor(c[1], c[2], c[3], c[4])
			o.bar:Show()
		end
	end
	-- health hidden (combat): the number alone
	o.text:SetText(label)
	local tc = est.kind == "damage" and { 1, 0.45, 0.45 } or (est.kind == "heal" and { 0.5, 1, 0.55 } or { 0.6, 0.85, 1 })
	o.text:SetTextColor(tc[1], tc[2], tc[3])
	o:Show()
end

-- mana cost of a spell (0 or nil when free)
local function manaCost(spellID)
	local costs
	if C_Spell and C_Spell.GetSpellPowerCost then
		local ok, c = pcall(C_Spell.GetSpellPowerCost, spellID)
		costs = ok and c
	elseif GetSpellPowerCost then
		local ok, c = pcall(GetSpellPowerCost, spellID)
		costs = ok and c
	end
	if type(costs) ~= "table" then return end
	for _, c in ipairs(costs) do
		local kind, cost = Safe(c.type, nil), Safe(c.cost, nil)
		if kind == 0 and type(cost) == "number" and cost > 0 then return cost end
	end
end

-- the cost as a lighter part at the end of your mana bar; "OOM" when it does not fit
local function showMana(f, cost)
	local bar = f.power
	if not bar then return end
	local o = f.predictMana
	if not o then
		o = CreateFrame("Frame", nil, bar)
		o:SetAllPoints(bar)
		o:SetFrameLevel(bar:GetFrameLevel() + 1)
		o.bar = o:CreateTexture(nil, "ARTWORK")
		o.bar:SetTexture(S.flat)
		o.bar:SetVertexColor(1, 1, 1, 0.45)
		o.text = S:Font(o, 10)
		f.predictMana = o
	end
	local cur, max = Safe(UnitPower("player", 0), nil), Safe(UnitPowerMax("player", 0), nil)
	o.bar:Hide()
	o.text:ClearAllPoints()
	o.text:SetPoint("CENTER", bar, "CENTER", 0, 0)
	if type(cur) == "number" and type(max) == "number" and max > 0 then
		local w = bar:GetWidth()
		local x0 = math.max(0, cur - cost)
		o.bar:ClearAllPoints()
		o.bar:SetPoint("TOPLEFT", bar, "TOPLEFT", x0 / max * w, 0)
		o.bar:SetPoint("BOTTOMLEFT", bar, "BOTTOMLEFT", x0 / max * w, 0)
		o.bar:SetWidth(math.max(1, (cur - x0) / max * w))
		o.bar:Show()
		if cost > cur then
			o.text:SetText(L["OOM"])
			o.text:SetTextColor(1, 0.3, 0.3)
		else
			o.text:SetText(("-%d %s"):format(cost, L["mana"]))
			o.text:SetTextColor(0.55, 0.75, 1)
		end
	else
		o.text:SetText(("-%d %s"):format(cost, L["mana"]))
		o.text:SetTextColor(0.55, 0.75, 1)
	end
	o.text:Show()
	o:Show()
end

local function frames()
	local UF = CK.UnitFrames
	return UF and UF.frames or {}
end

local function update()
	local fr = frames()
	local spell = casting or hover
	local est = on() and spell and P:Estimate(spell)
	local target = fr.target
	local player = fr.player
	local done = {}
	if est then
		local unit
		if est.kind == "damage" then
			if UnitExists("target") and Safe(UnitCanAttack("player", "target"), false) then unit = "target" end
		elseif UnitExists("target") and Safe(UnitIsFriend("player", "target"), false) and not Safe(UnitIsDead("target"), false) then
			unit = "target"
		else
			unit = "player"
		end
		local f = unit and fr[unit]
		if f and f:IsShown() and f.health then
			show(f, est)
			done[f] = true
		end
	end
	for _, f in ipairs({ target, player }) do
		if f and not done[f] then clear(f) end
	end
	-- mana: what this spell costs, on your own mana bar
	local cost = on() and spell and Safe(UnitPowerType("player"), 0) == 0 and manaCost(spell)
	if player and player.predictMana then player.predictMana:Hide() player.predictMana.text:Hide() end
	if cost and player and player:IsShown() then showMana(player, cost) end
end

function P:OnEnable()
	CK:On("UNIT_SPELLCAST_START", function(_, unit, _, spellID)
		if unit == "player" then casting = Safe(spellID, nil) end
	end)
	CK:On("UNIT_SPELLCAST_CHANNEL_START", function(_, unit, _, spellID)
		if unit == "player" then casting = Safe(spellID, nil) end
	end)
	for _, e in ipairs({ "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED", "UNIT_SPELLCAST_INTERRUPTED",
		"UNIT_SPELLCAST_CHANNEL_STOP" }) do
		CK:On(e, function(_, unit) if unit == "player" then casting = nil end end)
	end

	-- the spell under the mouse: any tooltip that shows a spell
	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Spell, function(tt, data)
			if tt == GameTooltip and type(data) == "table" then hover = Safe(data.id, nil) end
		end)
	end
	if GameTooltip.SetAction then
		hooksecurefunc(GameTooltip, "SetAction", function(_, slot) hover = spellOfAction(slot) or hover end)
	end
	GameTooltip:HookScript("OnHide", function() hover = nil end)

	-- light ticker: only draws while a spell is cast or hovered
	local f = CreateFrame("Frame")
	local wait, active = 0, false
	f:SetScript("OnUpdate", function(_, elapsed)
		wait = wait - elapsed
		if wait > 0 then return end
		wait = 0.1
		if casting or hover or active then
			active = (casting or hover) and true or false
			local ok, err = pcall(update)
			if not ok and CK.debug then CK:Print("predict: " .. tostring(err)) end
		end
	end)
end
