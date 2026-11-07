-- CasterKit by DinX: rotation helper (visual only, never casts anything)
local _, ns = ...
local CK = ns.CK
local S = CK.Style
local LBG = LibStub("LibButtonGlow-1.0", true)

local R = CK:NewModule("Rotation")
R.current = {}

---------------------------------------------------------------------------
-- Racials, shared by every class. Passive ones need nothing.
---------------------------------------------------------------------------
R.racials = {
	burst = { "Berserking", "Blood Fury", "Eureka!" },
	mana = { "Read Leyline", "Cannibalize" },
	escape = { "Escape Artist", "Will of the Forsaken", "Will to Survive", "Every Man for Himself" },
	fall = { "Walk on Air" },
}

---------------------------------------------------------------------------
-- Context handed to class rotations
---------------------------------------------------------------------------
local ctx = {}
R.ctx = ctx

function ctx:Known(name) return CK:Known(name) end

-- Known, castable now (or by the time the current cast/GCD ends), enough mana.
function ctx:Ready(name)
	if not CK:IsActive(name) then return false end
	local usable, noMana = CK:IsUsable(name)
	if noMana or not usable then return false end
	return CK:CooldownRemaining(name) <= self.wait + 0.2
end

function ctx:CooldownRemaining(name) return CK:CooldownRemaining(name) end
function ctx:Buff(name) return CK:FindAura("player", name, "HELPFUL") ~= nil end
function ctx:BuffRemaining(name) return CK:AuraRemaining("player", name, "HELPFUL") end
function ctx:Debuff(name, mine)
	return CK:FindAura("target", name, mine and "HARMFUL|PLAYER" or "HARMFUL") ~= nil
end
function ctx:DebuffRemaining(name, mine)
	return CK:AuraRemaining("target", name, mine and "HARMFUL|PLAYER" or "HARMFUL")
end

local function lossOfControl()
	if not C_LossOfControl or not C_LossOfControl.GetActiveLossOfControlDataCount then return end
	for i = 1, C_LossOfControl.GetActiveLossOfControlDataCount() do
		local d = C_LossOfControl.GetActiveLossOfControlData(i)
		if d and d.locType and d.locType ~= "SCHOOL_INTERRUPT" and d.locType ~= "DISARM" then
			return d.locType
		end
	end
end

local fallStart
function R:BuildContext()
	local now = GetTime()
	ctx.now = now
	ctx.level = UnitLevel("player")
	ctx.inCombat = UnitAffectingCombat("player")
	ctx.hostile = UnitExists("target") and UnitCanAttack("player", "target") and not UnitIsDead("target")
	ctx.targetHealthPct = ctx.hostile and (UnitHealth("target") / math.max(1, UnitHealthMax("target"))) or 0
	ctx.targetIsBoss = ctx.hostile and (UnitClassification("target") == "worldboss" or UnitLevel("target") == -1)
	ctx.healthPct = UnitHealth("player") / math.max(1, UnitHealthMax("player"))
	ctx.manaPct = UnitPower("player", 0) / math.max(1, UnitPowerMax("player", 0))
	ctx.moving = GetUnitSpeed("player") > 0
	ctx.aoe = CK.char.rotation.aoe
	ctx.targetingMe = ctx.hostile and UnitIsUnit("targettarget", "player")

	local name, _, _, _, endMS, _, _, _, spellID = UnitCastingInfo("player")
	ctx.channeling = false
	if not name then
		name, _, _, _, endMS = UnitChannelInfo("player")
		ctx.channeling = name ~= nil
	end
	ctx.casting = name
	ctx.castRemaining = name and math.max(0, endMS / 1000 - now) or 0
	ctx.wait = math.max(CK:GCDRemaining(), ctx.castRemaining)

	if IsFalling() then
		fallStart = fallStart or now
		ctx.fallTime = now - fallStart
	else
		fallStart = nil
		ctx.fallTime = 0
	end
	ctx.control = lossOfControl()
	return ctx
end

---------------------------------------------------------------------------
-- Evaluation: class rotation + racial layer
---------------------------------------------------------------------------
-- Suggestion list entries: { name = "Frostbolt", kind = "hint" | "proc" | "defensive" }
local function push(list, name, kind, front)
	if not name then return end
	for _, e in ipairs(list) do
		if e.name == name then return end
	end
	local e = { name = name, kind = kind or "hint" }
	if front then table.insert(list, 1, e) else list[#list + 1] = e end
end
R.Push = push

local function firstReady(names)
	for _, n in ipairs(names) do
		if ctx:Ready(n) then return n end
	end
end

function R:Evaluate()
	local cfg = CK.char.rotation
	local spec = CK:GetSpec()
	local c = self:BuildContext()
	local list = {}

	if spec and spec.rotation and (c.hostile or not cfg.onlyHostile) then
		spec.rotation(c, list, push)
	end

	-- racial layer
	if c.control then push(list, firstReady(self.racials.escape), "defensive", true) end
	if c.fallTime > 0.8 then push(list, firstReady(self.racials.fall), "defensive", true) end
	if c.manaPct < (c.inCombat and 0.35 or 0.5) then
		local m = firstReady(self.racials.mana)
		if m then push(list, m, "hint", c.inCombat and #list > 0) end
	end
	if c.inCombat and c.hostile and #list > 0 then
		local b = firstReady(self.racials.burst)
		if b then table.insert(list, math.min(2, #list + 1), { name = b, kind = "hint" }) end
	end

	-- class extras that also apply without a target (e.g. Slow Fall, Blink)
	local def = CK:GetClass()
	if def and def.Always then def.Always(c, list, push) end

	return list
end

---------------------------------------------------------------------------
-- Finding the buttons that hold a spell, on any bar addon
---------------------------------------------------------------------------
local BLIZZARD = { "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
	"MultiBarRightButton", "MultiBarLeftButton", "MultiBar5Button", "MultiBar6Button", "MultiBar7Button" }

local function actionName(slot)
	if not slot or not HasAction(slot) then return end
	local kind, id, sub = GetActionInfo(slot)
	if kind == "spell" then
		return CK.GetSpellName(id)
	elseif kind == "macro" then
		if sub == "spell" then return CK.GetSpellName(id) end
		local sid = GetMacroSpell(id)
		if sid then return CK.GetSpellName(sid) end
		local item = GetMacroItem and GetMacroItem(id)
		return item
	elseif kind == "item" then
		return CK:ItemName(id)
	end
end

local function buttonName(btn)
	if btn._state_type then -- LibActionButton
		if btn._state_type == "action" then return actionName(btn._state_action) end
		if btn._state_type == "spell" then return CK.GetSpellName(btn._state_action) end
		return
	end
	if btn.action then return actionName(btn.action) end
end

local map, mapDirty, mapTime = {}, true, 0
function R:RebuildMap()
	wipe(map)
	local seen = {}
	local function add(btn)
		if seen[btn] or not btn:IsVisible() then return end
		seen[btn] = true
		local n = buttonName(btn)
		if n then
			map[n] = map[n] or {}
			table.insert(map[n], btn)
		end
	end
	for _, btn in ipairs(CK.Bars.buttons) do add(btn) end
	for _, libName in ipairs({ "LibActionButton-1.0", "LibActionButton-1.0-ElvUI" }) do
		local lib = LibStub(libName, true)
		if lib and lib.GetAllButtons then
			for btn in pairs(lib:GetAllButtons()) do add(btn) end
		end
	end
	for _, prefix in ipairs(BLIZZARD) do
		for i = 1, 12 do
			local btn = _G[prefix .. i]
			if btn then add(btn) end
		end
	end
	mapDirty = false
	mapTime = GetTime()
end

function R:ButtonsFor(name)
	return map[name]
end

---------------------------------------------------------------------------
-- Glow overlays
---------------------------------------------------------------------------
local function overlay(btn)
	if btn.ckGlow then return btn.ckGlow end
	local f = CreateFrame("Frame", nil, btn)
	f:SetAllPoints()
	f:SetFrameLevel(btn:GetFrameLevel() + 6)
	f.edges = {}
	local t = 2
	local function edge(p1, p2, w, h)
		local tex = f:CreateTexture(nil, "OVERLAY")
		tex:SetTexture(S.flat)
		tex:SetPoint(p1)
		tex:SetPoint(p2)
		if w then tex:SetWidth(w) end
		if h then tex:SetHeight(h) end
		table.insert(f.edges, tex)
	end
	edge("TOPLEFT", "TOPRIGHT", nil, t)
	edge("BOTTOMLEFT", "BOTTOMRIGHT", nil, t)
	edge("TOPLEFT", "BOTTOMLEFT", t, nil)
	edge("TOPRIGHT", "BOTTOMRIGHT", t, nil)
	local ag = f:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.25)
	a:SetDuration(0.45)
	f.pulse = ag
	f:Hide()
	btn.ckGlow = f
	return f
end

local function setColor(f, c, alpha)
	for _, e in ipairs(f.edges) do e:SetVertexColor(c[1], c[2], c[3], alpha or 1) end
end

local glowing = {} -- btn -> level
local function applyGlow(btn, level)
	local cfg = CK.char.rotation
	local f = overlay(btn)
	if level == "secondary" then
		setColor(f, S.colors.hint, 0.45)
		f.pulse:Stop()
		f:Show()
		if btn.ckLBG and LBG then LBG.HideOverlayGlow(btn); btn.ckLBG = nil end
		return
	end
	local color = level == "proc" and S.colors.proc or (level == "defensive" and S.colors.accent or S.colors.hint)
	if cfg.glowStyle == "blizzard" and LBG then
		LBG.ShowOverlayGlow(btn)
		btn.ckLBG = true
		if level == "hint" then
			f:Hide()
		else
			setColor(f, color, 1)
			f.pulse:Play()
			f:Show()
		end
	else
		setColor(f, color, 1)
		f.pulse:Play()
		f:Show()
	end
end

local function clearGlow(btn)
	if btn.ckGlow then
		btn.ckGlow.pulse:Stop()
		btn.ckGlow:Hide()
	end
	if btn.ckLBG and LBG then
		LBG.HideOverlayGlow(btn)
		btn.ckLBG = nil
	end
end

function R:UpdateGlows(list)
	local cfg = CK.char.rotation
	local want = {}
	if cfg.glow and list[1] then
		for _, btn in ipairs(self:ButtonsFor(list[1].name) or {}) do want[btn] = list[1].kind end
		if cfg.secondary and list[2] then
			for _, btn in ipairs(self:ButtonsFor(list[2].name) or {}) do
				if not want[btn] then want[btn] = "secondary" end
			end
		end
	end
	for btn, level in pairs(glowing) do
		if want[btn] ~= level then
			clearGlow(btn)
			glowing[btn] = nil
		end
	end
	for btn, level in pairs(want) do
		if glowing[btn] ~= level then
			applyGlow(btn, level)
			glowing[btn] = level
		end
	end
end

function R:ClearAll()
	for btn in pairs(glowing) do clearGlow(btn) end
	wipe(glowing)
end

---------------------------------------------------------------------------
-- Hint frame: next spell + the one after
---------------------------------------------------------------------------
function R:CreateHint()
	local f = CreateFrame("Frame", "CasterKitHint", UIParent)
	f:SetSize(80, 42)
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(false)
	f:RegisterForDrag("LeftButton")

	f.main = S:Icon(f, 40)
	f.main:SetPoint("LEFT")
	f.next = S:Icon(f, 26)
	f.next:SetPoint("BOTTOMLEFT", f.main, "BOTTOMRIGHT", 4, 0)
	f.aoe = S:Font(f, 11)
	f.aoe:SetPoint("BOTTOM", f.main, "TOP", 0, 2)
	f.aoe:SetText("AoE")
	f.aoe:SetTextColor(unpack(S.colors.hint))

	f:SetScript("OnDragStart", function(self) self:StartMoving() end)
	f:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local p, _, rp, x, y = self:GetPoint()
		CK.char.rotation.point = { p, "UIParent", rp, math.floor(x + 0.5), math.floor(y + 0.5) }
	end)
	self.hint = f
	self:PlaceHint()
end

function R:PlaceHint()
	local f = self.hint
	f:ClearAllPoints()
	local pt = CK.char.rotation.point
	if pt then
		f:SetPoint(pt[1], UIParent, pt[3], pt[4], pt[5])
	else
		f:SetPoint("BOTTOM", CK.panel, "TOP", 20, 10)
	end
	local unlocked = not CK.char.bars.locked
	f:EnableMouse(unlocked)
end

local function setIcon(icon, entry)
	if not entry then icon:Hide() return end
	local tex = CK:SpellTexture(entry.name)
	if not tex and CK.ItemByName then tex = CK:ItemByName(entry.name) end
	icon.icon:SetTexture(tex or 134400)
	local c = entry.kind == "proc" and S.colors.proc or (entry.kind == "defensive" and S.colors.accent or nil)
	if c then icon:SetBackdropBorderColor(c[1], c[2], c[3], 1) else icon:SetBackdropBorderColor(0, 0, 0, 1) end
	icon:Show()
end

function R:UpdateHint(list)
	local f = self.hint
	local cfg = CK.char.rotation
	local show = cfg.enabled and cfg.hint and (list[1] ~= nil or not CK.char.bars.locked)
	f:SetShown(show)
	if not show then return end
	setIcon(f.main, list[1] or { name = "Frostbolt" })
	setIcon(f.next, cfg.secondary and list[2] or nil)
	f.aoe:SetShown(cfg.aoe)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function R:Tick()
	local cfg = CK.char.rotation
	if not cfg.enabled then
		if next(glowing) then self:ClearAll() end
		self.hint:Hide()
		return
	end
	if mapDirty or GetTime() - mapTime > 1 then self:RebuildMap() end
	local list = self:Evaluate()
	self.current = list
	self:UpdateGlows(list)
	self:UpdateHint(list)
end

function R:OnEnable()
	self:CreateHint()
	local function dirty() mapDirty = true end
	for _, e in ipairs({ "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
		"UPDATE_SHAPESHIFT_FORM", "SPELLS_CHANGED" }) do
		CK:On(e, dirty)
	end
	CK:Listen("SETTINGS", function(group)
		if group == "rotation" or group == "bars" then
			self:ClearAll()
			self:PlaceHint()
			dirty()
		end
	end)
	CK:Listen("PANEL_LAYOUT", function() self:PlaceHint(); dirty() end)
	C_Timer.NewTicker(0.1, function() self:Tick() end)
end
