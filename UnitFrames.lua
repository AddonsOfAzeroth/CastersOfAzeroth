-- CasterKit by DinX: unit frames (player, target, target of target, party)
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe, IsSecret = CK.Safe, CK.IsSecret

local UF = CK:NewModule("UnitFrames")
UF.frames = {}

local hider = CreateFrame("Frame")
hider:Hide()

---------------------------------------------------------------------------
-- Formatting (only for values that are not secret)
---------------------------------------------------------------------------
local function short(n)
	if n >= 1e6 then return (("%.1fm"):format(n / 1e6):gsub("%.", L.decimal)) end
	if n >= 1e4 then return ("%dk"):format(n / 1e3) end
	if n >= 1e3 then return (("%.1fk"):format(n / 1e3):gsub("%.", L.decimal)) end
	return tostring(n)
end

local function classColor(unit)
	local _, class = UnitClass(unit)
	class = Safe(class)
	local c = class and (C_ClassColor and C_ClassColor.GetClassColor(class) or RAID_CLASS_COLORS[class])
	if c then return c.r, c.g, c.b end
end

local function healthColor(unit)
	if Safe(UnitIsTapDenied and UnitIsTapDenied(unit), false) then return 0.55, 0.55, 0.55 end
	if Safe(UnitIsPlayer(unit), false) and CK.char.units.classColor then
		local r, g, b = classColor(unit)
		if r then return r, g, b end
	end
	local reaction = Safe(UnitReaction(unit, "player"))
	if reaction then
		if reaction <= 3 then return 0.80, 0.25, 0.22 end
		if reaction == 4 then return 0.90, 0.80, 0.25 end
		return 0.30, 0.75, 0.30
	end
	return 0.30, 0.75, 0.30
end

local function powerColor(unit)
	local ptype, token = UnitPowerType(unit)
	local c = PowerBarColor and (PowerBarColor[Safe(token) or ""] or PowerBarColor[Safe(ptype) or 0])
	if c then return c.r, c.g, c.b end
	return 0.25, 0.45, 0.95
end

local function levelText(unit)
	local lvl = Safe(UnitLevel(unit))
	if not lvl then return "", 1, 1, 1 end
	if lvl < 0 then return "??", 1, 0.2, 0.2 end
	local c = GetCreatureDifficultyColor and GetCreatureDifficultyColor(lvl) or GetQuestDifficultyColor(lvl)
	local cls = Safe(UnitClassification(unit))
	local suffix = (cls == "elite" or cls == "worldboss") and "+" or (cls == "rareelite" and "R+" or (cls == "rare" and "R" or ""))
	return lvl .. suffix, c.r, c.g, c.b
end

---------------------------------------------------------------------------
-- Frame construction
---------------------------------------------------------------------------
local function createFrame(name, unit, w, h, opts)
	opts = opts or {}
	local f = CreateFrame("Button", name, UIParent, "SecureUnitButtonTemplate,BackdropTemplate")
	f:SetSize(w, h)
	f:SetAttribute("unit", unit)
	f:SetAttribute("*type1", "target")
	f:SetAttribute("*type2", "togglemenu")
	f:RegisterForClicks("AnyUp")
	f.unit = unit
	S:Backdrop(f, 0.9)

	local powerH = opts.power and math.max(4, math.floor(h * 0.2)) or 0
	local hp = S:StatusBar(f)
	hp:SetPoint("TOPLEFT", 1, -1)
	hp:SetPoint("BOTTOMRIGHT", -1, 1 + (powerH > 0 and powerH + 1 or 0))
	f.health = hp

	if powerH > 0 then
		local pw = S:StatusBar(f)
		pw:SetPoint("BOTTOMLEFT", 1, 1)
		pw:SetPoint("BOTTOMRIGHT", -1, 1)
		pw:SetHeight(powerH)
		f.power = pw
		local sep = f:CreateTexture(nil, "BORDER")
		sep:SetColorTexture(0, 0, 0, 1)
		sep:SetPoint("BOTTOMLEFT", pw, "TOPLEFT")
		sep:SetPoint("BOTTOMRIGHT", pw, "TOPRIGHT")
		sep:SetHeight(1)
	end

	local textLayer = CreateFrame("Frame", nil, f)
	textLayer:SetAllPoints(hp)
	textLayer:SetFrameLevel(hp:GetFrameLevel() + 2)
	local fs = opts.font or 12
	f.name = S:Font(textLayer, fs)
	f.name:SetPoint("LEFT", 4, 0)
	f.name:SetJustifyH("LEFT")
	f.level = S:Font(textLayer, fs)
	f.hpText = S:Font(textLayer, fs)
	f.hpText:SetPoint("RIGHT", -4, 0)
	if opts.level then
		f.level:SetPoint("LEFT", f.name, "RIGHT", 4, 0)
	else
		f.level:Hide()
	end
	f.name:SetPoint("RIGHT", f.hpText, "LEFT", -28, 0)

	f.raidIcon = textLayer:CreateTexture(nil, "OVERLAY")
	f.raidIcon:SetSize(16, 16)
	f.raidIcon:SetPoint("CENTER", f, "TOP", 0, 0)
	f.raidIcon:SetTexture("Interface\\TargetingFrame\\UI-RaidTargetingIcons")
	f.raidIcon:Hide()

	f:SetScript("OnEnter", function(self)
		GameTooltip_SetDefaultAnchor(GameTooltip, self)
		GameTooltip:SetUnit(self.unit)
		GameTooltip:Show()
	end)
	f:SetScript("OnLeave", GameTooltip_Hide)
	if ClickCastFrames then ClickCastFrames[f] = true end

	UF.frames[unit] = f
	return f
end

---------------------------------------------------------------------------
-- Updates (secret-safe: bars and text accept secret values directly)
---------------------------------------------------------------------------
function UF:UpdateHealth(f)
	local u = f.unit
	if not UnitExists(u) then return end
	local cur, max = UnitHealth(u), UnitHealthMax(u)
	pcall(f.health.SetMinMaxValues, f.health, 0, max)
	pcall(f.health.SetValue, f.health, cur)
	f.health:SetStatusBarColor(healthColor(u))

	if Safe(UnitIsDead(u), false) then
		f.hpText:SetText(L["Dead"])
	elseif Safe(UnitIsGhost(u), false) then
		f.hpText:SetText(L["Ghost"])
	elseif not Safe(UnitIsConnected(u), true) then
		f.hpText:SetText("Offline")
	elseif not IsSecret(cur) and not IsSecret(max) then
		if u == "player" or u:find("^party") then
			f.hpText:SetText(f.compact and ("%d%%"):format(cur / math.max(1, max) * 100) or (short(cur) .. " / " .. short(max)))
		else
			local pct = ("%d%%"):format(cur / math.max(1, max) * 100)
			f.hpText:SetText(f.compact and pct or (pct .. " · " .. short(cur)))
		end
	else
		-- secret: let the font string format it, no math on our side
		if not pcall(f.hpText.SetFormattedText, f.hpText, "%s", cur) then f.hpText:SetText("") end
	end
end

function UF:UpdatePower(f)
	if not f.power then return end
	local u = f.unit
	pcall(f.power.SetMinMaxValues, f.power, 0, UnitPowerMax(u))
	pcall(f.power.SetValue, f.power, UnitPower(u))
	f.power:SetStatusBarColor(powerColor(u))
end

function UF:UpdateName(f)
	local u = f.unit
	pcall(f.name.SetText, f.name, UnitName(u))
	local text, r, g, b = levelText(u)
	f.level:SetText(text)
	f.level:SetTextColor(r, g, b)
	local idx = Safe(GetRaidTargetIndex(u))
	if idx then
		SetRaidTargetIconTexture(f.raidIcon, idx)
		f.raidIcon:Show()
	else
		f.raidIcon:Hide()
	end
	if f.role then
		local role = UnitGroupRolesAssigned and Safe(UnitGroupRolesAssigned(u))
		if role and role ~= "NONE" and GetMicroIconForRole then
			f.role:SetAtlas(GetMicroIconForRole(role))
			f.role:Show()
		else
			f.role:Hide()
		end
	end
end

function UF:UpdateAll(f)
	if not UnitExists(f.unit) then return end
	self:UpdateName(f)
	self:UpdateHealth(f)
	self:UpdatePower(f)
	if f.auras then self:UpdateAuras(f) end
	if f.status then self:UpdateStatus(f) end
end

---------------------------------------------------------------------------
-- Player: combat and resting icons
---------------------------------------------------------------------------
function UF:AddStatus(f)
	local t = f:CreateTexture(nil, "OVERLAY")
	t:SetSize(18, 18)
	t:SetPoint("CENTER", f, "TOPLEFT", 2, -2)
	t:SetTexture("Interface\\CharacterFrame\\UI-StateIcon")
	f.status = t
end

function UF:UpdateStatus(f)
	if Safe(UnitAffectingCombat("player"), false) then
		f.status:SetTexCoord(0.5, 1, 0, 0.49)
		f.status:Show()
	elseif IsResting() then
		f.status:SetTexCoord(0, 0.5, 0, 0.421875)
		f.status:Show()
	else
		f.status:Hide()
	end
end

---------------------------------------------------------------------------
-- Target: your debuffs with timers
---------------------------------------------------------------------------
local MAX_AURAS = 8

function UF:AddAuras(f)
	f.auras = {}
	for i = 1, MAX_AURAS do
		local a = S:Icon(f, 22)
		a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * 24, 4)
		a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
		a.cd:SetPoint("TOPLEFT", 1, -1)
		a.cd:SetPoint("BOTTOMRIGHT", -1, 1)
		a.cd:SetDrawEdge(false)
		a.cd:SetReverse(true)
		a.count = S:Font(a, 10)
		a.count:SetPoint("BOTTOMRIGHT", -1, 1)
		a:Hide()
		f.auras[i] = a
	end
end

function UF:UpdateAuras(f)
	local shown = 0
	if C_UnitAuras and C_UnitAuras.GetAuraDataByIndex then
		for i = 1, 40 do
			local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, f.unit, i, "HARMFUL|PLAYER")
			if not ok or not d then break end
			shown = shown + 1
			if shown > MAX_AURAS then break end
			local a = f.auras[shown]
			pcall(a.icon.SetTexture, a.icon, d.icon)
			local apps = Safe(d.applications, 0)
			a.count:SetText(apps and apps > 1 and apps or "")
			local dur, exp = Safe(d.duration), Safe(d.expirationTime)
			if dur and exp and dur > 0 then
				a.cd:SetCooldown(exp - dur, dur)
				a.cd:Show()
			else
				a.cd:Hide()
			end
			a:Show()
		end
	end
	for i = math.min(shown, MAX_AURAS) + 1, MAX_AURAS do f.auras[i]:Hide() end
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function wire(f, unitEvents)
	f:SetScript("OnEvent", function(self, event, unit)
		if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION" then
			UF:UpdateHealth(self)
		elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			UF:UpdatePower(self)
		elseif event == "UNIT_AURA" then
			if self.auras then UF:UpdateAuras(self) end
		elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "RAID_TARGET_UPDATE" or event == "UNIT_FACTION" then
			UF:UpdateName(self)
			UF:UpdateHealth(self)
		elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" then
			if self.status then UF:UpdateStatus(self) end
		else
			UF:UpdateAll(self)
		end
	end)
	for _, e in ipairs({ "UNIT_HEALTH", "UNIT_MAXHEALTH", "UNIT_POWER_FREQUENT", "UNIT_MAXPOWER",
		"UNIT_DISPLAYPOWER", "UNIT_NAME_UPDATE", "UNIT_LEVEL", "UNIT_FACTION", "UNIT_CONNECTION" }) do
		f:RegisterUnitEvent(e, f.unit)
	end
	f:RegisterEvent("RAID_TARGET_UPDATE")
	for _, e in ipairs(unitEvents or {}) do f:RegisterEvent(e) end
end

---------------------------------------------------------------------------
-- Hide Blizzard frames we replace
---------------------------------------------------------------------------
local function hideBlizzard(frame)
	if not frame then return end
	frame:UnregisterAllEvents()
	frame:Hide()
	frame:SetParent(hider)
	for _, child in ipairs({ "healthbar", "manabar", "powerBarAlt", "spellbar", "HealthBar", "ManaBar" }) do
		if frame[child] and frame[child].UnregisterAllEvents then frame[child]:UnregisterAllEvents() end
	end
end

function UF:HideBlizzard()
	local cfg = CK.char.units
	if not cfg.hideBlizzard or self.blizzardHidden then return end
	self.blizzardHidden = true
	if cfg.player then hideBlizzard(PlayerFrame) end
	if cfg.target then
		hideBlizzard(TargetFrame)
		if cfg.tot then hideBlizzard(TargetFrameToT) end
	end
	if cfg.party then
		if PartyFrame then
			hideBlizzard(PartyFrame)
			if PartyFrame.PartyMemberFramePool then
				for member in PartyFrame.PartyMemberFramePool:EnumerateActive() do hideBlizzard(member) end
			end
		end
		for i = 1, 4 do hideBlizzard(_G["PartyMemberFrame" .. i]) end
	end
end

---------------------------------------------------------------------------
-- Building and layout
---------------------------------------------------------------------------
function UF:Build()
	local panel = CK.panel

	local player = createFrame("CasterKitPlayerFrame", "player", 220, 48, { power = true, level = true })
	self:AddStatus(player)
	wire(player, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" })
	S:RegisterMover(player, "player", L["Player"], function(f)
		f:SetPoint("BOTTOMRIGHT", panel, "TOPLEFT", -12, 64)
	end)

	local target = createFrame("CasterKitTargetFrame", "target", 220, 48, { power = true, level = true })
	self:AddAuras(target)
	wire(target, { "PLAYER_TARGET_CHANGED" })
	target:RegisterUnitEvent("UNIT_AURA", "target")
	S:RegisterMover(target, "target", L["Target"], function(f)
		f:SetPoint("BOTTOMLEFT", panel, "TOPRIGHT", 12, 64)
	end)

	local tot = createFrame("CasterKitToTFrame", "targettarget", 110, 24, { font = 10 })
	tot.compact = true
	wire(tot, { "PLAYER_TARGET_CHANGED" })
	tot:RegisterUnitEvent("UNIT_TARGET", "target")
	-- target of target has no events of its own
	tot.elapsed = 0
	tot:HookScript("OnUpdate", function(self, el)
		self.elapsed = self.elapsed + el
		if self.elapsed > 0.25 then
			self.elapsed = 0
			UF:UpdateAll(self)
		end
	end)
	S:RegisterMover(tot, "tot", "ToT", function(f)
		f:SetPoint("BOTTOMLEFT", target, "BOTTOMRIGHT", 6, 0)
	end)

	local party = CreateFrame("Frame", "CasterKitPartyAnchor", UIParent)
	party:SetSize(180, 4 * 36 + 3 * 8)
	S:RegisterMover(party, "party", L["Party"], function(f)
		f:SetPoint("LEFT", UIParent, "LEFT", 16, 60)
	end)
	self.partyAnchor = party
	for i = 1, 4 do
		local pf = createFrame("CasterKitParty" .. i, "party" .. i, 180, 36, { power = true, font = 11 })
		pf:SetPoint("TOPLEFT", party, "TOPLEFT", 0, -(i - 1) * 44)
		pf.role = pf:CreateTexture(nil, "OVERLAY")
		pf.role:SetSize(14, 14)
		pf.role:SetPoint("CENTER", pf, "TOPLEFT", 2, -2)
		pf.role:Hide()
		wire(pf, { "GROUP_ROSTER_UPDATE", "PLAYER_ROLES_ASSIGNED" })
	end

	self.built = true
end

function UF:Apply()
	local cfg = CK.char.units
	local on = cfg.enabled
	local function set(f, show, watched)
		f:SetScale(cfg.scale)
		if watched then
			if show then RegisterUnitWatch(f) else UnregisterUnitWatch(f); f:Hide() end
		else
			f:SetShown(show)
		end
		if show then UF:UpdateAll(f) end
	end
	set(self.frames.player, on and cfg.player, false)
	set(self.frames.target, on and cfg.target, true)
	set(self.frames.targettarget, on and cfg.target and cfg.tot, true)
	self.partyAnchor:SetScale(cfg.scale)
	for i = 1, 4 do set(self.frames["party" .. i], on and cfg.party, true) end
	if on then self:HideBlizzard() end
	for _, key in ipairs({ "player", "target", "tot", "party" }) do
		local m = S.movers[key]
		if m then S:ApplyPoint(m.frame, key) end
	end
	S:UpdateMovers()
end

function UF:OnEnable()
	CK:OutOfCombat("units-build", function()
		self:Build()
		self:Apply()
	end)
	CK:Listen("SETTINGS", function(group)
		if (group == "units" or group == "bars") and self.built then
			CK:OutOfCombat("units-apply", function() self:Apply() end)
		end
	end)
	CK:Listen("PANEL_LAYOUT", function()
		if self.built then CK:OutOfCombat("units-apply", function() self:Apply() end) end
	end)
end
