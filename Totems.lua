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

-- the totem picked for an element: your choice when you still know it, else the first you know
function T:Chosen(e)
	local pick = cfg().chosen[e.key]
	if pick and CK:Known(pick) then return pick end
	return self:Known(e)[1]
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

-- the set for "drop all": your pick per element, earth fire water air
function T:Set()
	local out = {}
	for _, e in ipairs(ELEMENTS) do
		local n = self:Chosen(e)
		if n then out[#out + 1] = n end
	end
	return out
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
	bar:SetSize(6 * (SIZE + GAP) - GAP, SIZE)
	bar.elements = {}
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
	b.hint = L["Click: cast it and keep it on this button."]
	b:SetScript("OnEnter", function(self)
		spellTooltip(self)
		T.keepFlyout = true
	end)
	b:SetScript("OnLeave", function()
		GameTooltip_Hide()
		T.keepFlyout = nil
		T:CloseFlyoutSoon()
	end)
	b:SetScript("PostClick", function(self)
		local n = self:GetAttribute("spell")
		local e = n and elementOf[n]
		if e then
			cfg().chosen[e.key] = n
			CK:OutOfCombat("totems-layout", function() T:Layout() end)
		end
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
	if #known < 2 then return end
	for i, n in ipairs(known) do
		local b = self:FlyoutButton(i)
		b:SetAttribute("spell", n)
		b.icon:SetTexture(CK:SpellTexture(n))
		b:ClearAllPoints()
		b:SetPoint("BOTTOM", fly, "BOTTOM", 0, (i - 1) * (SIZE + GAP))
		b:SetBackdropBorderColor(unpack(n == self:Chosen(e) and S.colors.hint or { 0, 0, 0, 1 }))
		b:Show()
	end
	for i = #known + 1, #fly.buttons do fly.buttons[i]:Hide() end
	fly:SetSize(SIZE, #known * (SIZE + GAP) - GAP)
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
	local n = 0
	for _, b in ipairs(bar.elements) do
		local pick = self:Chosen(b.element)
		b:SetShown(pick ~= nil)
		if pick then
			b:SetAttribute("spell", pick)
			b.icon:SetTexture(CK:SpellTexture(pick))
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
	for _, b in ipairs(bar.elements) do
		if b:IsShown() then
			local slot = b.element.slot
			local name, left, dur = self:Remaining(slot, now)
			if name then
				b.icon:SetDesaturated(false)
				b.icon:SetAlpha(1)
				b.time:SetText(clock(left))
				pcall(CooldownFrame_Set, b.cd, now - (dur - left), dur, 1)
				-- the totem that stands, when it is not your pick
				local tex = CK:SpellTexture(name)
				if tex then b.icon:SetTexture(tex) end
			else
				b.icon:SetDesaturated(true)
				b.icon:SetAlpha(0.6)
				b.time:SetText("")
				b.cd:Hide()
				local pick = b:GetAttribute("spell")
				if pick then b.icon:SetTexture(CK:SpellTexture(pick)) end
			end
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
	if c.enabled and c.hideBlizzard and not self.blizzardHidden and _G.MultiCastActionBarFrame then
		local hider = CreateFrame("Frame")
		hider:Hide()
		_G.MultiCastActionBarFrame:UnregisterAllEvents()
		CK.HideBlizzardFrame(_G.MultiCastActionBarFrame, hider)
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
	if type(c.chosen) ~= "table" then c.chosen = {} end
	CK:OutOfCombat("totems-build", function()
		self:Build()
		self:Apply()
	end)
	CK:Listen("SETTINGS", function(group)
		if group == "totems" then CK:OutOfCombat("totems-apply", function() self:Apply() end) end
	end)
	CK:On("SPELLS_CHANGED", function() CK:OutOfCombat("totems-apply", function() self:Apply() end) end)
	CK:On("PLAYER_TOTEM_UPDATE", function() self:Update() end)
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
