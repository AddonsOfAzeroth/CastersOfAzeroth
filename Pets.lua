-- Casters of Azeroth by DinX: your minion (warlock demon, water elemental,
-- any pet). A frame with its health and what it attacks, its action bar with
-- autocast at a glance, a button per demon you know with your Soul Shards,
-- and warnings: low health (Health Funnel lights up), gone in combat (Fel
-- Domination), not attacking while you fight (the Attack button glows).
-- Display and your own clicks only: it never commands the pet by itself.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe = CK.Safe

local P = CK:NewModule("Pets")

local LBG = LibStub and LibStub("LibButtonGlow-1.0", true)
local LOW = 0.35        -- pet health that asks for a heal
local IDLE_AFTER = 2    -- seconds without a target while you fight
local SOUL_SHARD = 6265
local BUTTONS = 10      -- NUM_PET_ACTION_SLOTS

local HEALS = { "Health Funnel", "Mend Pet" }
local TAUNTS = { ["Torment"] = true, ["Suffering"] = true, ["Growl"] = true }
-- the summons per class, with the creature family that shows it is out
local SUMMONS = {
	WARLOCK = {
		{ spell = "Summon Imp", family = "Imp" },
		{ spell = "Summon Voidwalker", family = "Voidwalker" },
		{ spell = "Summon Succubus", family = "Succubus" },
		{ spell = "Summon Incubus", family = "Incubus" },
		{ spell = "Summon Felhunter", family = "Felhunter" },
		{ spell = "Summon Felguard", family = "Felguard" },
		{ spell = "Fel Domination" },
	},
	MAGE = { { spell = "Summon Water Elemental", family = "Water Elemental" } },
}

local function cfg() return CK.char.pets end

---------------------------------------------------------------------------
-- What the pet is doing
---------------------------------------------------------------------------
local state = { exists = false }
P.state = state
local hadPet = false -- a pet was out during this fight
local idleSince

local function ratio(a, b)
	a, b = Safe(a), Safe(b)
	if type(a) ~= "number" or type(b) ~= "number" or b <= 0 then return nil end
	return a / b
end

-- fills `state`: exists, dead, hp (0..1 or nil when hidden), family, target, idle, taunt
function P:Read(now)
	now = now or GetTime()
	local s = state
	s.exists = UnitExists("pet") and true or false
	s.dead = s.exists and Safe(UnitIsDead("pet"), false) or false
	s.hp = s.exists and ratio(UnitHealth("pet"), UnitHealthMax("pet")) or nil
	s.family = s.exists and Safe(UnitCreatureFamily and UnitCreatureFamily("pet"), nil) or nil
	s.hasTarget = s.exists and UnitExists("pettarget") and true or false
	local fighting = Safe(UnitAffectingCombat("player"), false)
		and UnitExists("target") and Safe(UnitCanAttack("player", "target"), false)
		and not Safe(UnitIsDead("target"), false)
	if s.exists and not s.dead then
		if fighting then hadPet = true end
	end
	-- idle: you fight, it has no target, for a moment (a fresh pull needs a second)
	if fighting and s.exists and not s.dead and not s.hasTarget then
		idleSince = idleSince or now
	else
		idleSince = nil
	end
	s.idle = idleSince ~= nil and now - idleSince >= IDLE_AFTER
	-- your target attacks you and your pet can taunt it (nil = hidden: no hint)
	s.onMe = fighting and Safe(UnitIsUnit("targettarget", "player"), nil) == true or false
	s.gone = fighting and hadPet and (not s.exists or s.dead)
	return s
end

---------------------------------------------------------------------------
-- Rotation layer: heal the pet, bring it back
---------------------------------------------------------------------------
local lastSummon -- the summon you used last (to suggest it again)

local function firstReady(c, list)
	for _, n in ipairs(list) do if c:Ready(n) then return n end end
end

function P.Layer(c, list, push)
	if not (cfg().enabled and cfg().warnings) then return end
	local s = state
	if c.inCombat and s.exists and not s.dead and s.hp and s.hp < LOW and not c.moving then
		local heal = firstReady(c, HEALS)
		-- first unless you need the health yourself
		if heal then push(list, heal, "defensive", c.healthPct > 0.5) end
	end
	if s.gone then
		if c:Ready("Fel Domination") then
			push(list, "Fel Domination", "defensive", true)
		elseif c:Buff("Fel Domination") then
			local spell = lastSummon
			if not (spell and c:Ready(spell)) then
				spell = nil
				for _, e in ipairs(SUMMONS[CK.playerClass] or {}) do
					if e.family and c:Ready(e.spell) then spell = e.spell break end
				end
			end
			if spell then push(list, spell, "defensive", true) end
		end
	end
end

---------------------------------------------------------------------------
-- The pet frame (built like the player frame) with a line under it
---------------------------------------------------------------------------
function P:BuildFrame()
	local UF = CK.UnitFrames
	if not (UF and UF.CreateUnitFrame) then return end
	local f = UF.CreateUnitFrame("CasterKitPetFrame", "pet", 160, 30, { power = true, font = 11 })
	f.compact = true
	UF.Wire(f, { "UNIT_PET", "PLAYER_ENTERING_WORLD" })
	f.info = S:Font(f, 10)
	f.info:SetPoint("TOPLEFT", f, "BOTTOMLEFT", 2, -2)
	f.info:SetPoint("TOPRIGHT", f, "BOTTOMRIGHT", -2, -2)
	f.info:SetJustifyH("LEFT")
	f.info:SetWordWrap(false)
	S:RegisterMover(f, "pet", L["Pet"], function(fr)
		local player = UF.frames and UF.frames.player
		if player then
			fr:SetPoint("TOPRIGHT", player, "BOTTOMRIGHT", 0, -8)
		else
			fr:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 200)
		end
	end, nil, S:Sizing(f, "pet", { default = { 160, 30 }, min = { 80, 18 }, max = { 360, 90 } }))
	self.frame = f
end

function P:UpdateFrame()
	local f = self.frame
	if not (f and f:IsShown()) then return end
	local s = state
	local text, color = "", S.colors.muted
	if s.idle then
		text, color = L["Not attacking: click Attack on its bar"], S.colors.warn
	elseif s.exists and not s.dead and s.hp and s.hp < LOW then
		text, color = L["Low health"], S.colors.warn
	elseif s.hasTarget then
		local ok, name = pcall(UnitName, "pettarget")
		if ok and name then
			if not pcall(f.info.SetFormattedText, f.info, "> %s", name) then f.info:SetText("") end
			f.info:SetTextColor(unpack(color))
			f:SetBackdropBorderColor(0, 0, 0, 1)
			return
		end
	end
	f.info:SetText(text)
	f.info:SetTextColor(unpack(color))
	if color == S.colors.warn then
		f:SetBackdropBorderColor(unpack(S.colors.warn))
	else
		f:SetBackdropBorderColor(0, 0, 0, 1)
	end
end

---------------------------------------------------------------------------
-- The pet bar: left-click = the action, right-click = autocast on/off
---------------------------------------------------------------------------
local function actionInfo(i)
	if not GetPetActionInfo then return end
	local name, texture, isToken, isActive, autoAllowed, autoOn = GetPetActionInfo(i)
	if isToken then
		return _G[name] or name, _G[texture] or texture, name, isActive, autoAllowed, autoOn
	end
	return name, texture, nil, isActive, autoAllowed, autoOn
end
P.ActionInfo = actionInfo

local function barTooltip(self)
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	if GameTooltip.SetPetAction and pcall(GameTooltip.SetPetAction, GameTooltip, self.slot) then
		if self.autoAllowed then GameTooltip:AddLine(L["Right-click: autocast on or off"], 0.4, 0.8, 1) end
		GameTooltip:Show()
	else
		GameTooltip:Hide()
	end
end

function P:BuildBar()
	local size, gap = 26, 3
	local bar = CreateFrame("Frame", "CasterKitPetBar", UIParent, "SecureHandlerStateTemplate")
	bar:SetSize(BUTTONS * size + (BUTTONS - 1) * gap, size)
	bar.buttons = {}
	for i = 1, BUTTONS do
		local b = CreateFrame("Button", "CasterKitPetButton" .. i, bar, "SecureActionButtonTemplate,BackdropTemplate")
		b:SetSize(size, size)
		b:SetPoint("LEFT", (i - 1) * (size + gap), 0)
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetAttribute("type1", "pet")
		b:SetAttribute("action", i)
		b.slot = i
		S:Backdrop(b, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.cd = CreateFrame("Cooldown", nil, b, "CooldownFrameTemplate")
		b.cd:SetAllPoints(b.icon)
		b.cd:SetDrawEdge(false)
		-- autocast on: a green corner and a green border
		b.auto = b:CreateTexture(nil, "OVERLAY")
		b.auto:SetSize(7, 7)
		b.auto:SetPoint("TOPRIGHT", -2, -2)
		b.auto:SetColorTexture(0.35, 0.9, 0.45, 1)
		b.auto:Hide()
		b:SetScript("OnEnter", barTooltip)
		b:SetScript("OnLeave", GameTooltip_Hide)
		bar.buttons[i] = b
	end
	S:RegisterMover(bar, "petbar", L["Pet bar"], function(fr)
		if self.frame then
			fr:SetPoint("TOPRIGHT", self.frame, "BOTTOMRIGHT", 0, -18)
		else
			fr:SetPoint("BOTTOM", UIParent, "BOTTOM", -300, 160)
		end
	end)
	self.bar = bar
end

-- right-click macros need names: set out of combat only
function P:UpdateBarMacros()
	if not self.bar or InCombatLockdown() then return end
	for i, b in ipairs(self.bar.buttons) do
		local name, _, _, _, autoAllowed = actionInfo(i)
		if name and autoAllowed then
			b:SetAttribute("type2", "macro")
			b:SetAttribute("macrotext2", "/petautocasttoggle " .. name)
		else
			b:SetAttribute("type2", nil)
			b:SetAttribute("macrotext2", nil)
		end
	end
end

-- which button should glow: Attack while it idles, a taunt when your target hits you
function P:GlowSlot()
	local s = state
	if not (cfg().warnings and s.exists and not s.dead) then return end
	for i = 1, BUTTONS do
		local name, _, token = actionInfo(i)
		if s.idle and token == "PET_ACTION_ATTACK" then return i end
		if s.onMe and name and TAUNTS[name] then
			local start, dur = 0, 0
			if GetPetActionCooldown then start, dur = GetPetActionCooldown(i) end
			start, dur = Safe(start, 0) or 0, Safe(dur, 0) or 0
			if dur <= 1.5 or start + dur - GetTime() <= 0 then return i end
		end
	end
end

function P:UpdateBar()
	local bar = self.bar
	if not (bar and bar:IsShown()) then return end
	local glow = self:GlowSlot()
	for i, b in ipairs(bar.buttons) do
		local name, texture, _, isActive, autoAllowed, autoOn = actionInfo(i)
		b.autoAllowed = autoAllowed
		if name or texture then
			b.icon:SetTexture(texture)
			b.icon:Show()
			local usable = not GetPetActionSlotUsable or Safe(GetPetActionSlotUsable(i), true)
			b.icon:SetDesaturated(not usable)
			if GetPetActionCooldown then
				local start, dur, enable = GetPetActionCooldown(i)
				if not pcall(CooldownFrame_Set, b.cd, start, dur, enable) then b.cd:Hide() end
			end
		else
			b.icon:Hide()
			b.cd:Hide()
		end
		b.auto:SetShown(autoOn and true or false)
		if autoOn then
			b:SetBackdropBorderColor(0.35, 0.9, 0.45, 1)
		elseif isActive then
			b:SetBackdropBorderColor(unpack(S.colors.hint))
		else
			b:SetBackdropBorderColor(0, 0, 0, 1)
		end
		if LBG then
			if glow == i and not b.glowing then
				LBG.ShowOverlayGlow(b)
				b.glowing = true
			elseif glow ~= i and b.glowing then
				LBG.HideOverlayGlow(b)
				b.glowing = nil
			end
		end
	end
end

---------------------------------------------------------------------------
-- Summon buttons: one per demon you know, with your Soul Shards
---------------------------------------------------------------------------
local function shards()
	return (C_Item and C_Item.GetItemCount and C_Item.GetItemCount(SOUL_SHARD)) or (GetItemCount and GetItemCount(SOUL_SHARD)) or 0
end

function P:BuildSummons()
	local list = SUMMONS[CK.playerClass]
	if not list then return end
	local size, gap = 26, 3
	local row = CreateFrame("Frame", "CasterKitSummons", UIParent)
	row:SetSize(#list * (size + gap), size)
	row.buttons = {}
	for i, e in ipairs(list) do
		local b = CreateFrame("Button", nil, row, "SecureActionButtonTemplate,BackdropTemplate")
		b:SetSize(size, size)
		b:RegisterForClicks("AnyUp", "AnyDown")
		b:SetAttribute("type", "spell")
		b:SetAttribute("spell", e.spell)
		b.def = e
		S:Backdrop(b, 1)
		b.icon = b:CreateTexture(nil, "ARTWORK")
		b.icon:SetPoint("TOPLEFT", 1, -1)
		b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		b.text = S:Font(b, 10)
		b.text:SetPoint("CENTER")
		b:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_TOP")
			local id = CK:SpellID(e.spell)
			if id and GameTooltip.SetSpellByID then GameTooltip:SetSpellByID(id) else GameTooltip:AddLine(e.spell, 1, 1, 1) end
			GameTooltip:Show()
		end)
		b:SetScript("OnLeave", GameTooltip_Hide)
		b:Hide()
		row.buttons[i] = b
	end
	row.shards = S:Font(row, 11)
	row.shards:SetPoint("RIGHT", row, "LEFT", -4, 0)
	S:RegisterMover(row, "summons", L["Summons"], function(fr)
		if self.frame then
			fr:SetPoint("RIGHT", self.frame, "LEFT", -40, 0)
		else
			fr:SetPoint("BOTTOM", UIParent, "BOTTOM", -480, 200)
		end
	end)
	self.summons = row
end

-- which buttons exist: the summons you know, side by side (out of combat)
function P:LayoutSummons()
	local row = self.summons
	if not row or InCombatLockdown() then return end
	local n = 0
	for _, b in ipairs(row.buttons) do
		local known = CK:Known(b.def.spell)
		b:SetShown(known)
		if known then
			b:ClearAllPoints()
			b:SetPoint("LEFT", n * 29, 0)
			b.icon:SetTexture(CK:SpellTexture(b.def.spell))
			n = n + 1
		end
	end
	row:SetWidth(math.max(1, n * 29 - 3))
	row.count = n
end

function P:UpdateSummons()
	local row = self.summons
	if not (row and row:IsShown()) then return end
	local family = state.exists and not state.dead and state.family
	for _, b in ipairs(row.buttons) do
		if b:IsShown() then
			local out = family and b.def.family == family
			local cd = CK:CooldownRemaining(b.def.spell) or 0
			b.icon:SetDesaturated(cd > 1.5)
			b.text:SetText(cd > 1.5 and (cd >= 60 and ("%dm"):format(cd / 60 + 0.5) or ("%d"):format(cd)) or "")
			if out then
				b:SetBackdropBorderColor(0.35, 0.9, 0.45, 1)
				b.icon:SetAlpha(1)
			else
				b:SetBackdropBorderColor(0, 0, 0, 1)
				b.icon:SetAlpha(family and 0.6 or 1)
			end
		end
	end
	if CK.playerClass == "WARLOCK" then
		local n = shards()
		row.shards:SetText(("|T134075:14:14:0:0:64:64:5:59:5:59|t %d"):format(n))
		row.shards:SetTextColor(unpack(n == 0 and S.colors.warn or S.colors.text))
	else
		row.shards:SetText("")
	end
end

---------------------------------------------------------------------------
-- Showing, hiding, Blizzard's own pet frame and bar
---------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()

function P:Apply()
	if InCombatLockdown() then return end
	local c = cfg()
	local on = c.enabled
	local units = CK.char.units
	if self.frame then
		self.frame:SetScale(units.scale or 1)
		if on and c.frame and units.enabled then RegisterUnitWatch(self.frame) else UnregisterUnitWatch(self.frame) self.frame:Hide() end
		if self.frame:IsShown() and CK.UnitFrames then CK.UnitFrames:UpdateAll(self.frame) end
	end
	if self.bar then
		if on and c.bar then
			RegisterStateDriver(self.bar, "visibility", "[pet] show; hide")
		else
			UnregisterStateDriver(self.bar, "visibility")
			self.bar:Hide()
		end
		self:UpdateBarMacros()
	end
	if self.summons then
		self:LayoutSummons()
		self.summons:SetShown(on and c.summons and (self.summons.count or 0) > 0)
	end
	if on and c.hideBlizzard and not self.blizzardHidden then
		if c.frame and units.enabled and PetFrame then
			PetFrame:UnregisterAllEvents()
			CK.HideBlizzardFrame(PetFrame, hider)
		end
		if c.bar then
			for _, name in ipairs({ "PetActionBar", "PetActionBarFrame" }) do
				local bar = _G[name]
				if bar then
					bar:UnregisterAllEvents()
					CK.HideBlizzardFrame(bar, hider)
				end
			end
		end
		self.blizzardHidden = true
	end
	for _, key in ipairs({ "pet", "petbar", "summons" }) do
		local m = S.movers[key]
		if m then
			m.hidden = not on
			S:ApplyPoint(m.frame, key)
		end
	end
	S:UpdateMovers()
	self:Tick()
end

function P:Tick()
	self:Read()
	pcall(self.UpdateFrame, self)
	pcall(self.UpdateBar, self)
	pcall(self.UpdateSummons, self)
end

function P:OnEnable()
	local R = CK.Rotation
	if R and R.layers then table.insert(R.layers, P.Layer) end
	CK:OutOfCombat("pets-build", function()
		self:BuildFrame()
		self:BuildBar()
		self:BuildSummons()
		self:Apply()
	end)
	CK:Listen("SETTINGS", function(group)
		if group == "pets" or group == "units" then CK:OutOfCombat("pets-apply", function() self:Apply() end) end
	end)
	local function bar() self:Tick() CK:OutOfCombat("pets-macros", function() self:UpdateBarMacros() end) end
	for _, e in ipairs({ "PET_BAR_UPDATE", "PET_UI_UPDATE", "PET_BAR_UPDATE_USABLE", "PLAYER_CONTROL_LOST",
		"PLAYER_CONTROL_GAINED", "UNIT_PET" }) do
		CK:On(e, bar)
	end
	CK:On("PET_BAR_UPDATE_COOLDOWN", function() self:Tick() end)
	CK:On("SPELLS_CHANGED", function() CK:OutOfCombat("pets-apply", function() self:Apply() end) end)
	CK:On("PLAYER_REGEN_ENABLED", function() hadPet = false end)
	CK:On("UNIT_SPELLCAST_SUCCEEDED", function(_, unit, _, spellID)
		if unit ~= "player" then return end
		local id = Safe(spellID, nil)
		local name = id and CK.GetSpellName and CK.GetSpellName(id)
		for _, e in ipairs(SUMMONS[CK.playerClass] or {}) do
			if e.family and e.spell == name then lastSummon = name end
		end
	end)
	C_Timer.NewTicker(0.25, function() self:Tick() end)
end
