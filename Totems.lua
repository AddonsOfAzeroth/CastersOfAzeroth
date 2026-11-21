-- Casters of Azeroth by DinX: a totem bar for shamans. One button per element
-- with the totem you picked for it (hover out of combat to pick another), how
-- long the totem still stands, a "drop all" button that puts down the next
-- totem of your set with every click, a warning when you walked out of a
-- totem's reach, a glow on the element the rotation helper suggests, and
-- Totemic Recall. Your own clicks only: one click is one cast.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe = CK.Safe

local T = CK:NewModule("Totems")

local LBG = LibStub and LibStub("LibButtonGlow-1.0", true)
local SIZE, GAP = 30, 3
local RANGE = 20 -- yards a totem reaches

-- slots as GetTotemInfo numbers them: 1 fire, 2 earth, 3 water, 4 air
local ELEMENTS = {
	{ slot = 2, key = "earth", color = { 0.75, 0.55, 0.3 }, list = { "Strength of Earth Totem", "Stoneskin Totem",
		"Tremor Totem", "Earthbind Totem", "Stoneclaw Totem", "Earth Elemental Totem" } },
	{ slot = 1, key = "fire", color = { 1, 0.4, 0.2 }, list = { "Totem of Wrath", "Searing Totem", "Flametongue Totem",
		"Magma Totem", "Fire Nova Totem", "Frost Resistance Totem", "Fire Elemental Totem" } },
	{ slot = 3, key = "water", color = { 0.3, 0.65, 1 }, list = { "Mana Spring Totem", "Healing Stream Totem",
		"Cleansing Totem", "Poison Cleansing Totem", "Disease Cleansing Totem", "Fire Resistance Totem", "Mana Tide Totem" } },
	{ slot = 4, key = "air", color = { 0.7, 0.9, 1 }, list = { "Wrath of Air Totem", "Windfury Totem", "Grace of Air Totem",
		"Grounding Totem", "Nature Resistance Totem", "Windwall Totem", "Tranquil Air Totem", "Sentry Totem" } },
}
T.ELEMENTS = ELEMENTS
local RECALLS = { "Totemic Recall", "Totemic Call" }

-- how long a totem stands when the client hides it (seconds; most last 2 minutes)
local DURATION = {
	["Searing Totem"] = 55, ["Fire Nova Totem"] = 5, ["Magma Totem"] = 20, ["Stoneclaw Totem"] = 15,
	["Earthbind Totem"] = 45, ["Healing Stream Totem"] = 60, ["Mana Spring Totem"] = 60, ["Mana Tide Totem"] = 12,
	["Grounding Totem"] = 45, ["Sentry Totem"] = 300,
}
T.DURATION = DURATION

local elementOf = {} -- totem name -> element
for _, e in ipairs(ELEMENTS) do
	for _, n in ipairs(e.list) do elementOf[n] = e end
end
T.elementOf = elementOf

local function cfg() return CK.char.totems end

---------------------------------------------------------------------------
-- Which totem stands where, and for how long
---------------------------------------------------------------------------
local placed = {} -- [slot] = { name, at, dur, y, x } from your own casts
T.placed = placed

local function position()
	if not UnitPosition then return end
	local ok, y, x = pcall(UnitPosition, "player")
	if not ok then return end
	y, x = Safe(y, nil), Safe(x, nil)
	if type(y) == "number" and type(x) == "number" then return y, x end
end
T.Position = position

-- the totems you know of an element, in list order
function T:Known(e)
	local out = {}
	for _, n in ipairs(e.list) do if CK:Known(n) then out[#out + 1] = n end end
	return out
end

---------------------------------------------------------------------------
-- Sets: which totem per element in which situation. An entry is a totem name,
-- false (that element is left out) or missing (the defaults below).
---------------------------------------------------------------------------
local SETS = { "solo", "elite", "boss", "group", "aoe" }
T.SETS = SETS
local EARTH = { "Strength of Earth Totem", "Stoneskin Totem" }
local FIRE = { "Totem of Wrath", "Searing Totem" }
local AIR = { "Wrath of Air Totem", "Windfury Totem", "Grace of Air Totem" }
local SET_DEFAULT = {
	solo = { fire = { "Searing Totem" } },
	elite = { earth = EARTH, fire = FIRE, water = { "Healing Stream Totem", "Mana Spring Totem" } },
	boss = { earth = EARTH, fire = FIRE, water = { "Mana Spring Totem", "Healing Stream Totem" }, air = AIR },
	group = { earth = EARTH, fire = FIRE, water = { "Mana Spring Totem", "Healing Stream Totem" }, air = AIR },
	aoe = { earth = EARTH, fire = { "Magma Totem", "Fire Nova Totem", "Searing Totem" }, water = { "Healing Stream Totem" } },
}
T.SET_DEFAULT = SET_DEFAULT

-- the situation right now: your fixed choice, or (auto) boss, many enemies, group, elite, solo
function T:SetKey(ctx)
	local mode = cfg().mode
	if mode and mode ~= "auto" and SET_DEFAULT[mode] then return mode end
	local class = UnitExists("target") and Safe(UnitClassification("target"), nil)
	local lvl = UnitExists("target") and Safe(UnitLevel("target"), nil)
	if class == "worldboss" or lvl == -1 or (ctx and ctx.targetIsBoss) then return "boss" end
	if ctx and ctx.aoe then return "aoe" end
	if IsInGroup and IsInGroup() then return "group" end
	if class == "elite" or class == "rareelite" then return "elite" end
	return "solo"
end

-- the totem of an element in a set, or nil when the set leaves that element out
function T:Pick(e, key)
	local c = cfg()
	local set = c.sets[key]
	local v = set and set[e.key]
	if v == false then return end
	if type(v) == "string" and CK:Known(v) then return v end
	local d = SET_DEFAULT[key] and SET_DEFAULT[key][e.key]
	if not d then return end
	for _, n in ipairs(d) do if CK:Known(n) then return n end end
	local old = c.chosen[e.key] -- the single pick from before sets
	if old and CK:Known(old) then return old end
	return self:Known(e)[1]
end

-- the totem on an element's button: the set's pick, else the first you know (the button always works)
function T:Chosen(e)
	return self:Pick(e, self.setKey or "solo") or self:Known(e)[1]
end

-- what the rotation helper puts down in this situation
function T:ForRotation(ctx)
	local key, out = self:SetKey(ctx), {}
	for _, e in ipairs(ELEMENTS) do
		local n = self:Pick(e, key)
		if n then out[#out + 1] = { name = n, slot = e.slot } end
	end
	return out, key
end

-- name and seconds left of the totem in a slot (nil when none stands)
function T:Remaining(slot, now)
	now = now or GetTime()
	if GetTotemInfo then
		local ok, have, name, start, dur = pcall(GetTotemInfo, slot)
		if ok then
			have, name, start, dur = Safe(have, nil), Safe(name, nil), Safe(start, nil), Safe(dur, nil)
			if have == false or name == "" then placed[slot] = nil return end
			if have and type(name) == "string" and type(start) == "number" and type(dur) == "number" and dur > 0 then
				local left = start + dur - now
				if left <= 0 then return end
				return name, left, dur
			end
		end
	end
	-- hidden: count from your own cast
	local p = placed[slot]
	if not p then return end
	local left = p.at + p.dur - now
	if left <= 0 then placed[slot] = nil return end
	return p.name, left, p.dur
end

-- yards from where you put the totem down (nil when unknown)
function T:Distance(slot)
	local p = placed[slot]
	if not (p and p.y) then return end
	local y, x = position()
	if not y then return end
	local dy, dx = y - p.y, x - p.x
	return math.sqrt(dy * dy + dx * dx)
end

function T:Placed(name, now)
	local e = elementOf[name]
	if not e then return end
	local y, x = position()
	placed[e.slot] = { name = name, at = now or GetTime(), dur = DURATION[name] or 120, y = y, x = x }
end

function T:Recalled()
	for k in pairs(placed) do placed[k] = nil end
end

-- the element of the totem the rotation helper suggests first
function T:Suggested()
	local R = CK.Rotation
	local list = R and R.current
	for i = 1, math.min(2, list and #list or 0) do
		local e = list[i] and elementOf[list[i].name]
		if e then return e end
	end
end

-- the set for "drop all": the set's pick per element, earth fire water air
function T:Set()
	local out, key = {}, self.setKey or "solo"
	for _, e in ipairs(ELEMENTS) do
		local n = self:Pick(e, key)
		if n then out[#out + 1] = n end
	end
	return out
end

local MODES = { "auto", "solo", "elite", "boss", "group", "aoe" }
local LABEL = { auto = "Auto", solo = "Solo", elite = "Elite", boss = "Boss", group = "Group", aoe = "AoE",
	earth = "Earth", fire = "Fire", water = "Water", air = "Air" }
local SHORT = { auto = "A", solo = "S", elite = "E", boss = "B", group = "G", aoe = "AoE" }
T.MODES = MODES

-- the set button: auto, or one set you fix (out of combat: the buttons change)
function T:CycleMode(dir)
	if InCombatLockdown() then return end
	local c = cfg()
	local i = 1
	for k, m in ipairs(MODES) do if m == (c.mode or "auto") then i = k end end
	c.mode = MODES[(i - 1 + dir) % #MODES + 1]
	self:Layout()
	self:Update()
end

function T:SetTooltip(owner)
	local c = cfg()
	local key = self.setKey or "solo"
	GameTooltip:SetOwner(owner, "ANCHOR_TOP")
	if (c.mode or "auto") == "auto" then
		GameTooltip:AddLine(L["Totem set"] .. ": " .. L["Auto"] .. " (" .. L[LABEL[key]] .. ")", 1, 1, 1)
		GameTooltip:AddLine(L["Auto picks the set from your target and group: boss, many enemies (AoE), group, elite, else solo."], 0.8, 0.8, 0.8, true)
	else
		GameTooltip:AddLine(L["Totem set"] .. ": " .. L[LABEL[key]], 1, 1, 1)
	end
	for _, e in ipairs(ELEMENTS) do
		local n = self:Pick(e, key)
		GameTooltip:AddDoubleLine(L[LABEL[e.key]], n or L["left out"], e.color[1], e.color[2], e.color[3], 1, 1, 1)
	end
	GameTooltip:AddLine(L["Click: next set. Right-click: previous. Pick a totem in an element's list to change the set shown."], 0.4, 0.8, 1, true)
	GameTooltip:Show()
end

function T:DropAllMacro()
	local set = self:Set()
	if #set == 0 then return end
	return "/castsequence reset=15 " .. table.concat(set, ", ")
end

---------------------------------------------------------------------------
-- Buttons
---------------------------------------------------------------------------
local function clock(s)
	if s >= 60 then return ("%d:%02d"):format(math.floor(s / 60), math.floor(s % 60)) end
	return ("%d"):format(math.floor(s + 0.5))
end
T.Clock = clock

local function spellTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local n = self:GetAttribute("spell")
	local id = n and CK:SpellID(n)
	if id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(id) elseif n then GameTooltip:AddLine(n, 1, 1, 1) end
	if self.hint then GameTooltip:AddLine(self.hint, 0.4, 0.8, 1, true) end
	GameTooltip:Show()
end

local function newButton(parent, name)
	local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate,BackdropTemplate")
	b:SetSize(SIZE, SIZE)
	b:RegisterForClicks("AnyUp", "AnyDown")
	S:Backdrop(b, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	return b
end

function T:Build()
	local bar = CreateFrame("Frame", "CasterKitTotemBar", UIParent)
	bar:SetSize(7 * (SIZE + GAP) - GAP, SIZE)
	bar.elements = {}
	-- the set in use (not a cast: a plain button)
	local mode = CreateFrame("Button", "CasterKitTotemSet", bar, "BackdropTemplate")
	mode:SetSize(SIZE, SIZE)
	mode:SetPoint("LEFT", 0, 0)
	S:Backdrop(mode, 1)
	mode.text = S:Font(mode, 10)
	mode.text:SetPoint("CENTER")
	mode:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	mode:SetScript("OnClick", function(_, button) T:CycleMode(button == "RightButton" and -1 or 1) end)
	mode:SetScript("OnEnter", function(self) T:SetTooltip(self) end)
	mode:SetScript("OnLeave", GameTooltip_Hide)
	bar.mode = mode
	for i, e in ipairs(ELEMENTS) do
		local b = newButton(bar, "CasterKitTotem" .. e.key)
		b:SetPoint("LEFT", (i - 1) * (SIZE + GAP), 0)
		b:SetAttribute("type", "spell")
		b.element = e
		b.hint = L["Hover out of combat to pick another totem."]
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints(b.icon)
		b.cd:SetDrawEdge(false)
		if b.cd.SetHideCountdownNumbers then b.cd:SetHideCountdownNumbers(true) end
		b.time = S:Font(b, 11)
		b.time:SetPoint("BOTTOM", b, "BOTTOM", 0, 2)
		b.strip = b:CreateTexture(nil, "OVERLAY")
		b.strip:SetPoint("TOPLEFT", 1, -1)
		b.strip:SetPoint("TOPRIGHT", -1, -1)
		b.strip:SetHeight(3)
		b.strip:SetColorTexture(e.color[1], e.color[2], e.color[3], 1)
		b:SetScript("OnEnter", function(self)
			spellTooltip(self)
			T:OpenFlyout(self)
		end)
		b:SetScript("OnLeave", function()
			GameTooltip_Hide()
			T:CloseFlyoutSoon()
		end)
		bar.elements[i] = b
	end
	-- drop all: every click the next totem of your set
	local all = newButton(bar, "CasterKitTotemAll")
	all:SetPoint("LEFT", 4 * (SIZE + GAP), 0)
	all:SetAttribute("type", "macro")
	all.icon:SetTexture(136232) -- Spell_Nature_StoneClawTotem
	all:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(L["Drop all"], 1, 1, 1)
		GameTooltip:AddLine(L["Each click puts down the next totem of your set: earth, fire, water, air. Starts over after 15 seconds without a click."], 0.8, 0.8, 0.8, true)
		GameTooltip:Show()
	end)
	all:SetScript("OnLeave", GameTooltip_Hide)
	bar.all = all
	-- Totemic Recall
	local recall = newButton(bar, "CasterKitTotemRecall")
	recall:SetPoint("LEFT", 5 * (SIZE + GAP), 0)
	recall:SetAttribute("type", "spell")
	recall:SetScript("OnEnter", spellTooltip)
	recall:SetScript("OnLeave", GameTooltip_Hide)
	bar.recall = recall

	-- the flyout: the totems you know of one element, above its button
	local fly = CreateFrame("Frame", "CasterKitTotemFlyout", bar, "BackdropTemplate")
	fly:SetFrameStrata("DIALOG")
	fly:Hide()
	fly.buttons = {}
	fly:SetScript("OnLeave", function() T:CloseFlyoutSoon() end)
	bar.fly = fly

	S:RegisterMover(bar, "totems", L["Totem bar"], function(fr)
		fr:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 230)
	end)
	self.bar = bar
end

function T:FlyoutButton(i)
	local fly = self.bar.fly
	local b = fly.buttons[i]
	if b then return b end
	b = newButton(fly, "CasterKitTotemPick" .. i)
	b:SetAttribute("type", "spell")
	-- right-click only marks it, it does not cast
	b:SetAttribute("type2", "macro")
	b:SetAttribute("macrotext2", "/stopmacro")
	b:SetScript("OnEnter", function(self)
		spellTooltip(self)
		T.keepFlyout = true
	end)
	b:SetScript("OnLeave", function()
		GameTooltip_Hide()
		T.keepFlyout = nil
		T:CloseFlyoutSoon()
	end)
	b:SetScript("PostClick", function(self, button)
		local fly = T.bar.fly
		local e = fly.owner and fly.owner.element
		if not e then return end
		local c = cfg()
		local key = T.setKey or "solo"
		local n = self:GetAttribute("spell")
		if self.none then
			c.sets[key] = c.sets[key] or {}
			c.sets[key][e.key] = false
		elseif button == "RightButton" then
			c.alt[e.key] = n
		else
			c.sets[key] = c.sets[key] or {}
			c.sets[key][e.key] = n
		end
		CK:OutOfCombat("totems-layout", function() T:Layout() T:Update() end)
	end)
	fly.buttons[i] = b
	return b
end

-- flyouts are secure buttons: they can only open and close out of combat
function T:OpenFlyout(owner)
	if InCombatLockdown() or not cfg().enabled then return end
	local e = owner.element
	local fly = self.bar.fly
	local known = self:Known(e)
	if #known < 1 then return end
	local pick, alt = self:Pick(e, self.setKey or "solo"), cfg().alt[e.key]
	local setName = L[LABEL[self.setKey or "solo"]]
	for i, n in ipairs(known) do
		local b = self:FlyoutButton(i)
		b.none = nil
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", n)
		b.icon:SetTexture(CK:SpellTexture(n))
		b.hint = L["Click: cast it and use it in the set %s. Right-click: make it this element's right-click totem."]:format(setName)
			.. (n == alt and ("\n" .. L["Right-click totem now."]) or "")
		b:ClearAllPoints()
		b:SetPoint("BOTTOM", fly, "BOTTOM", 0, (i - 1) * (SIZE + GAP))
		b:SetBackdropBorderColor(unpack(n == pick and S.colors.hint or n == alt and { 0.4, 0.8, 1 } or { 0, 0, 0, 1 }))
		b:Show()
	end
	-- last: leave this element out of the set
	local none = self:FlyoutButton(#known + 1)
	none.none = true
	none:SetAttribute("type", "macro")
	none:SetAttribute("macrotext", "/stopmacro")
	none:SetAttribute("spell", nil)
	none.icon:SetTexture("Interface\\Buttons\\UI-GroupLoot-Pass-Up")
	none.hint = L["Leave this element out of the set %s: the rotation helper will not suggest it there."]:format(setName)
	none:ClearAllPoints()
	none:SetPoint("BOTTOM", fly, "BOTTOM", 0, #known * (SIZE + GAP))
	none:SetBackdropBorderColor(unpack(pick == nil and S.colors.hint or { 0, 0, 0, 1 }))
	none:Show()
	for i = #known + 2, #fly.buttons do fly.buttons[i]:Hide() end
	fly:SetSize(SIZE, (#known + 1) * (SIZE + GAP) - GAP)
	fly:ClearAllPoints()
	fly:SetPoint("BOTTOM", owner, "TOP", 0, GAP)
	fly.owner = owner
	fly:Show()
	self.flyCloseAt = nil
end

function T:CloseFlyoutSoon()
	self.flyCloseAt = GetTime() + 0.4
end

function T:CheckFlyout(now)
	local fly = self.bar and self.bar.fly
	if not (fly and fly:IsShown() and self.flyCloseAt) or now < self.flyCloseAt then return end
	if self.keepFlyout or (fly.owner and fly.owner:IsMouseOver()) or fly:IsMouseOver() then
		self.flyCloseAt = nil
		return
	end
	if not InCombatLockdown() then fly:Hide() end
	self.flyCloseAt = nil
end

-- which buttons and spells: out of combat only (secure attributes)
function T:Layout()
	local bar = self.bar
	if not bar or InCombatLockdown() then return end
	local c = cfg()
	self.setKey = self:SetKey()
	local n = 1 -- the set button comes first
	for _, b in ipairs(bar.elements) do
		local pick = self:Chosen(b.element)
		b:SetShown(pick ~= nil)
		if pick then
			b.off = self:Pick(b.element, self.setKey) == nil
			b:SetAttribute("spell", pick)
			b.icon:SetTexture(CK:SpellTexture(pick))
			-- right-click: this element's second totem
			local alt = c.alt[b.element.key]
			if alt and alt ~= pick and CK:Known(alt) then
				b:SetAttribute("type2", "spell")
				b:SetAttribute("spell2", alt)
				b.hint = L["Hover out of combat to pick another totem."] .. "\n" .. L["Right-click: %s"]:format(alt)
			else
				b:SetAttribute("type2", nil)
				b:SetAttribute("spell2", nil)
				b.hint = L["Hover out of combat to pick another totem."]
			end
			b:ClearAllPoints()
			b:SetPoint("LEFT", n * (SIZE + GAP), 0)
			n = n + 1
		end
	end
	local macro = c.dropAll and self:DropAllMacro()
	bar.all:SetShown(macro and n > 1 or false)
	if bar.all:IsShown() then
		bar.all:SetAttribute("macrotext", macro)
		bar.all:ClearAllPoints()
		bar.all:SetPoint("LEFT", n * (SIZE + GAP) + 6, 0)
		n = n + 1
	end
	local recall
	if c.recall then
		for _, r in ipairs(RECALLS) do if CK:Known(r) then recall = r break end end
	end
	bar.recall:SetShown(recall ~= nil)
	if recall then
		bar.recall:SetAttribute("spell", recall)
		bar.recall.icon:SetTexture(CK:SpellTexture(recall))
		bar.recall:ClearAllPoints()
		bar.recall:SetPoint("LEFT", n * (SIZE + GAP) + 6, 0)
		n = n + 1
	end
	bar:SetWidth(math.max(SIZE, n * (SIZE + GAP) + 6))
	bar.count = n
end

function T:Update(now)
	local bar = self.bar
	if not (bar and bar:IsShown()) then return end
	now = now or GetTime()
	local c = cfg()
	local glowFor = c.glow and self:Suggested()
	-- the set the rotation helper uses right now (in combat too)
	local R = CK.Rotation
	local key = self:SetKey(R and R.ctx)
	local auto = (c.mode or "auto") == "auto"
	bar.mode.text:SetText(auto and ("A:" .. SHORT[key]) or SHORT[key])
	for _, b in ipairs(bar.elements) do
		if b:IsShown() then
			local slot = b.element.slot
			local name, left, dur = self:Remaining(slot, now)
			if name then
				b.icon:Show()
				b.time:SetText(clock(left))
				pcall(CooldownFrame_Set, b.cd, now - (dur - left), dur, 1)
				-- the totem that stands, when it is not your pick
				local tex = CK:SpellTexture(name)
				if tex then b.icon:SetTexture(tex) end
			else
				-- nothing stands: a dark tile with only the element's colour strip
				b.icon:Hide()
				b.time:SetText("")
				b.cd:Hide()
			end
			-- an element left out of the set: a fainter strip
			b.strip:SetAlpha(b.off and 0.35 or 1)
			local far = name and c.range and (self:Distance(slot) or 0) > RANGE
			if far then
				b:SetBackdropBorderColor(unpack(S.colors.warn))
				b.time:SetTextColor(unpack(S.colors.warn))
			else
				b:SetBackdropBorderColor(0, 0, 0, 1)
				b.time:SetTextColor(unpack(S.colors.text))
			end
			local glow = glowFor == b.element
			if LBG then
				if glow and not b.glowing then LBG.ShowOverlayGlow(b) b.glowing = true
				elseif not glow and b.glowing then LBG.HideOverlayGlow(b) b.glowing = nil end
			end
		end
	end
	self:CheckFlyout(now)
end

---------------------------------------------------------------------------
-- Showing and hiding
---------------------------------------------------------------------------
function T:Apply()
	if InCombatLockdown() or not self.bar then return end
	local c = cfg()
	self:Layout()
	local on = c.enabled and CK.playerClass == "SHAMAN" and (self.bar.count or 0) > 0
	self.bar:SetShown(on)
	if not on then self.bar.fly:Hide() end
	-- Blizzard's totem bar and the totem timers under the player frame: this bar shows both
	if on and c.hideBlizzard and not self.blizzardHidden then
		local hider = CreateFrame("Frame")
		hider:Hide()
		for _, name in ipairs({ "MultiCastActionBarFrame", "TotemFrame" }) do
			local f = _G[name]
			if f then
				f:UnregisterAllEvents()
				CK.HideBlizzardFrame(f, hider)
			end
		end
		self.blizzardHidden = true
	end
	local m = S.movers.totems
	if m then
		m.hidden = not on
		S:ApplyPoint(m.frame, "totems")
	end
	S:UpdateMovers()
	self:Update()
end

function T:OnEnable()
	if CK.playerClass ~= "SHAMAN" then return end
	local c = cfg()
	for _, k in ipairs({ "chosen", "sets", "alt" }) do
		if type(c[k]) ~= "table" then c[k] = {} end
	end
	c.mode = c.mode or "auto"
	CK:OutOfCombat("totems-build", function()
		self:Build()
		self:Apply()
	end)
	CK:Listen("SETTINGS", function(group)
		if group == "totems" then CK:OutOfCombat("totems-apply", function() self:Apply() end) end
	end)
	CK:On("SPELLS_CHANGED", function() CK:OutOfCombat("totems-apply", function() self:Apply() end) end)
	CK:On("PLAYER_TOTEM_UPDATE", function() self:Update() end)
	-- a new target or group out of combat: the buttons follow the set
	local function follow()
		if self.bar and not InCombatLockdown() and self:SetKey() ~= self.setKey then
			self:Layout()
			self:Update()
		end
	end
	for _, ev in ipairs({ "PLAYER_TARGET_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_REGEN_ENABLED" }) do CK:On(ev, follow) end
	CK:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local id = Safe(spellID, nil)
		local name = id and CK.GetSpellName and CK.GetSpellName(id)
		if not name then return end
		if name == "Totemic Recall" or name == "Totemic Call" then self:Recalled()
		else self:Placed(name) end
		self:Update()
	end)
	C_Timer.NewTicker(0.2, function() pcall(self.Update, self) end)
end
