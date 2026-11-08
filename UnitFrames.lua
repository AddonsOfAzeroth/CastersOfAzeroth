-- Casters of Azeroth by DinX: unit frames (player, target, target of target, party)
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
-- Buffs and debuffs on the player and target frames.
-- Debuffs: the row right above the frame (bigger); buffs: a smaller row above
-- that. In combat this client can hide aura data: icons and timers are then
-- passed straight to the widgets (allowed for hidden values), never compared.
---------------------------------------------------------------------------
local ROWS = {
	debuffs = { filter = "HARMFUL", size = 24, max = 10 },
	buffs = { filter = "HELPFUL", size = 18, max = 12 },
}
local DEBUFF_COLORS = {
	Magic = { 0.2, 0.6, 1 }, Curse = { 0.6, 0, 1 }, Disease = { 0.6, 0.4, 0 }, Poison = { 0, 0.6, 0 },
}

local function auraTooltip(a)
	if not (a.unit and a:IsShown()) then return end
	GameTooltip:SetOwner(a, "ANCHOR_BOTTOMRIGHT")
	local id = a.auraInstanceID
	if id and GameTooltip.SetUnitAuraByAuraInstanceID and pcall(GameTooltip.SetUnitAuraByAuraInstanceID, GameTooltip, a.unit, id) then
		return GameTooltip:Show()
	end
	if a.index and GameTooltip.SetUnitAura then pcall(GameTooltip.SetUnitAura, GameTooltip, a.unit, a.index, a.filter) end
	GameTooltip:Show()
end

local function makeRow(f, key, y)
	local r = ROWS[key]
	local row = {}
	for i = 1, r.max do
		local a = S:Icon(f, r.size)
		a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (r.size + 2), y)
		a.cd = CreateFrame("Cooldown", nil, a, "CooldownFrameTemplate")
		a.cd:SetPoint("TOPLEFT", 1, -1)
		a.cd:SetPoint("BOTTOMRIGHT", -1, 1)
		a.cd:SetDrawEdge(false)
		a.cd:SetReverse(true)
		a.cd:SetHideCountdownNumbers(r.size < 20)
		a.count = S:Font(a, r.size < 20 and 9 or 10)
		a.count:SetPoint("BOTTOMRIGHT", -1, 1)
		a:EnableMouse(true)
		a:SetScript("OnEnter", auraTooltip)
		a:SetScript("OnLeave", function() GameTooltip:Hide() end)
		a:Hide()
		row[i] = a
	end
	return row
end

function UF:AddAuras(f)
	f.auras = {
		debuffs = makeRow(f, "debuffs", 4),
		buffs = makeRow(f, "buffs", 4 + ROWS.debuffs.size + 3),
	}
end

-- Ways to read one filter's auras. Each returns a list of aura data, or nil
-- when it is missing or refused. Clients differ: some return nothing (no error)
-- for other units through one way and do through another, so all are tried.
local SOURCES = {
	{ "byIndex", function(unit, filter)
		if not (C_UnitAuras and C_UnitAuras.GetAuraDataByIndex) then return end
		local out = {}
		for i = 1, 40 do
			local ok, d = pcall(C_UnitAuras.GetAuraDataByIndex, unit, i, filter)
			if not ok then return end
			if not d then break end
			out[#out + 1] = d
		end
		return out
	end },
	{ "unitAuras", function(unit, filter)
		if not (C_UnitAuras and C_UnitAuras.GetUnitAuras) then return end
		local ok, auras = pcall(C_UnitAuras.GetUnitAuras, unit, filter)
		if ok and type(auras) == "table" then return auras end
	end },
	{ "slots", function(unit, filter)
		if not (C_UnitAuras and C_UnitAuras.GetAuraSlots and C_UnitAuras.GetAuraDataBySlot) then return end
		local r = { pcall(C_UnitAuras.GetAuraSlots, unit, filter) }
		if not r[1] then return end
		local out = {}
		for i = 3, #r do -- r[2] is the continuation token
			local ok, d = pcall(C_UnitAuras.GetAuraDataBySlot, unit, r[i])
			if ok and d then out[#out + 1] = d end
		end
		return out
	end },
	{ "unitAura", function(unit, filter)
		if not UnitAura then return end
		local out = {}
		for i = 1, 40 do
			local ok, name, icon, count, kind, dur, exp, source, _, _, spellId = pcall(UnitAura, unit, i, filter)
			if not ok then return end
			if not IsSecret(name) and name == nil then break end
			local src = Safe(source, nil)
			out[#out + 1] = { name = name, icon = icon, applications = count, dispelName = kind, duration = dur,
				expirationTime = exp, sourceUnit = source, spellId = spellId,
				isFromPlayerOrPlayerPet = type(src) == "string" and (src == "player" or src == "pet") or nil }
		end
		return out
	end },
}

-- Full read of a unit's auras: a list of { d, id, harmful, index, filter },
-- or nil when this client refuses right now (enemy auras in combat).
-- Second value: the way that worked (or the filter that was refused).
local function scan(unit)
	local list, used = {}, nil
	for _, filter in ipairs({ "HARMFUL", "HELPFUL" }) do
		local best
		for _, src in ipairs(SOURCES) do
			local got = src[2](unit, filter)
			if got and (not best or #got > #best) then best, used = got, src[1] end
			if best and #best > 0 then break end
		end
		if not best then return nil, filter end
		for i, d in ipairs(best) do
			list[#list + 1] = { d = d, id = Safe(d.auraInstanceID), harmful = filter == "HARMFUL", index = i, filter = filter }
		end
	end
	return list, used
end
UF.ScanAuras = scan

-- harmful or not for an aura handed over by UNIT_AURA (its flags can be hidden)
local function isHarmful(unit, d)
	local h = Safe(d.isHarmful)
	if type(h) == "boolean" then return h end
	local helpful = Safe(d.isHelpful)
	if type(helpful) == "boolean" then return not helpful end
	-- unknown: on an enemy it is most likely your debuff, on you a buff
	return unit ~= "player" and Safe(UnitCanAttack("player", unit), false) and true or false
end

local function fillIcon(a, unit, d, index, filter, isDebuff)
	a.unit, a.index, a.filter = unit, index, filter
	local id = d.auraInstanceID
	a.auraInstanceID = (not IsSecret(id)) and id or nil
	pcall(a.icon.SetTexture, a.icon, d.icon)
	-- stacks
	local apps = Safe(d.applications)
	if type(apps) == "number" then
		a.count:SetText(apps > 1 and apps or "")
	elseif a.auraInstanceID and C_UnitAuras.GetAuraApplicationDisplayCount then
		local ok, txt = pcall(C_UnitAuras.GetAuraApplicationDisplayCount, unit, a.auraInstanceID, 2, 99)
		pcall(a.count.SetText, a.count, ok and txt or "")
	else
		a.count:SetText("")
	end
	-- timer
	local dur, exp = Safe(d.duration), Safe(d.expirationTime)
	local timed = false
	if type(dur) == "number" and type(exp) == "number" then
		if dur > 0 then
			a.cd:SetCooldown(exp - dur, dur)
			timed = true
		end
	else
		-- hidden timer: hand it to the cooldown widget as it is
		if a.auraInstanceID and C_UnitAuras.GetAuraDuration and a.cd.SetCooldownFromDurationObject then
			timed = pcall(function()
				a.cd:SetCooldownFromDurationObject(C_UnitAuras.GetAuraDuration(unit, a.auraInstanceID))
			end) and true or false
		end
		if not timed and a.cd.SetCooldownFromExpirationTime then
			timed = pcall(a.cd.SetCooldownFromExpirationTime, a.cd, d.expirationTime, d.duration) and true or false
		end
	end
	a.cd:SetShown(timed)
	-- border: debuff type colour, red for other debuffs
	if isDebuff then
		local kind = Safe(d.dispelName)
		local c = type(kind) == "string" and DEBUFF_COLORS[kind] or { 0.8, 0.1, 0.1 }
		a:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	else
		a:SetBackdropBorderColor(0, 0, 0, 1)
	end
	a:Show()
end

-- info: UNIT_AURA's update info. While the client refuses a full read (enemy
-- in combat) the list is kept up to date from the auras that event hands over.
function UF:UpdateAuras(f, info)
	if not f.auras then return end
	local cfg = CK.char.units
	local unit = f.unit
	local cache = f.auraCache or {}
	f.auraCache = cache
	local partial = type(info) == "table" and Safe(info.isFullUpdate, true) == false
	local list = not partial and scan(unit)
	if list then
		wipe(cache)
		for i, r in ipairs(list) do cache[i] = r end
	elseif partial then
		for _, id in ipairs(info.removedAuraInstanceIDs or {}) do
			id = Safe(id)
			for i = #cache, 1, -1 do if id and cache[i].id == id then table.remove(cache, i) end end
		end
		for _, id in ipairs(info.updatedAuraInstanceIDs or {}) do
			id = Safe(id)
			if id and C_UnitAuras and C_UnitAuras.GetAuraDataByAuraInstanceID then
				local ok, d = pcall(C_UnitAuras.GetAuraDataByAuraInstanceID, unit, id)
				if ok and d then
					for _, r in ipairs(cache) do if r.id == id then r.d = d end end
				end
			end
		end
		for _, d in ipairs(info.addedAuras or {}) do
			local id = Safe(d.auraInstanceID)
			if id then
				for i = #cache, 1, -1 do if cache[i].id == id then table.remove(cache, i) end end
			end
			local h = isHarmful(unit, d)
			cache[#cache + 1] = { d = d, id = id, harmful = h, filter = h and "HARMFUL" or "HELPFUL" }
		end
	end

	local count = { debuffs = 0, buffs = 0 }
	if cfg.auras ~= false and UnitExists(unit) then
		for _, r in ipairs(cache) do
			local key = r.harmful and "debuffs" or "buffs"
			local row = f.auras[key]
			-- on an enemy you can show only your own debuffs (DoTs)
			local mine = Safe(r.d.isFromPlayerOrPlayerPet)
			local wanted = not (r.harmful and cfg.onlyMyDebuffs and unit ~= "player" and mine == false)
			if wanted and count[key] < #row then
				count[key] = count[key] + 1
				fillIcon(row[count[key]], unit, r.d, r.index, r.filter, r.harmful)
			end
		end
	end
	for key, row in pairs(f.auras) do
		for i = count[key] + 1, #row do row[i]:Hide() end
	end
	-- buffs sit right above the frame when there are no debuffs
	local up = count.debuffs > 0 and (ROWS.debuffs.size + 3) or 0
	if f.auraShift ~= up then
		f.auraShift = up
		for i, a in ipairs(f.auras.buffs) do
			a:ClearAllPoints()
			a:SetPoint("BOTTOMLEFT", f, "TOPLEFT", (i - 1) * (ROWS.buffs.size + 2), 4 + up)
		end
	end
end

-- /coaauras: what this client allows for your target's auras (for bug reports)
SLASH_CASTERSAURAS1 = "/coaauras"
SlashCmdList.CASTERSAURAS = function()
	local unit = UnitExists("target") and "target" or "player"
	local counts = {}
	for _, src in ipairs(SOURCES) do
		local h, b = src[2](unit, "HARMFUL"), src[2](unit, "HELPFUL")
		counts[#counts + 1] = src[1] .. " " .. (h and #h or "-") .. "/" .. (b and #b or "-")
	end
	local f = UF.frames[unit]
	local shown = 0
	if f and f.auras then
		for _, row in pairs(f.auras) do for _, a in ipairs(row) do if a:IsShown() then shown = shown + 1 end end end
	end
	CK:Print(("auras %s (debuffs/buffs): %s; kept %d, shown %d, frame %s"):format(unit, table.concat(counts, ", "),
		f and f.auraCache and #f.auraCache or 0, shown, tostring(f and f:IsVisible())))
end

---------------------------------------------------------------------------
-- Events
---------------------------------------------------------------------------
local function wire(f, unitEvents)
	f:SetScript("OnEvent", function(self, event, unit, info)
		if event == "UNIT_HEALTH" or event == "UNIT_MAXHEALTH" or event == "UNIT_CONNECTION" then
			UF:UpdateHealth(self)
		elseif event == "UNIT_POWER_FREQUENT" or event == "UNIT_MAXPOWER" or event == "UNIT_DISPLAYPOWER" then
			UF:UpdatePower(self)
		elseif event == "UNIT_AURA" then
			if self.auras then UF:UpdateAuras(self, info) end
		elseif event == "UNIT_NAME_UPDATE" or event == "UNIT_LEVEL" or event == "RAID_TARGET_UPDATE" or event == "UNIT_FACTION" then
			UF:UpdateName(self)
			UF:UpdateHealth(self)
		elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" or event == "PLAYER_UPDATE_RESTING" then
			if self.status then UF:UpdateStatus(self) end
			if self.auras then UF:UpdateAuras(self) end
		else
			-- a new target: forget the old one's auras (in combat they come back with UNIT_AURA)
			if event == "PLAYER_TARGET_CHANGED" and self.auraCache then wipe(self.auraCache) end
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
	CK.HideBlizzardFrame(frame, hider)
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
	self:AddAuras(player)
	wire(player, { "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_UPDATE_RESTING", "PLAYER_ENTERING_WORLD" })
	player:RegisterUnitEvent("UNIT_AURA", "player")
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
		self:AddPartyBuffs(pf)
	end

	self.built = true
end

---------------------------------------------------------------------------
-- Party: buttons for the buffs you can give (click = cast on that member)
---------------------------------------------------------------------------
local function fmtLeft(left)
	if left >= 3600 then return ("%dh"):format(left / 3600) end
	if left >= 60 then return ("%dm"):format(left / 60) end
	return ("%ds"):format(left)
end

function UF:AddPartyBuffs(pf)
	local def = CK:GetClass()
	pf.buffButtons = {}
	for i, b in ipairs(def and def.partyBuffs or {}) do
		local btn = CreateFrame("Button", nil, pf, "SecureActionButtonTemplate,BackdropTemplate")
		btn:SetSize(20, 20)
		btn:SetPoint("LEFT", pf, "RIGHT", 4 + (i - 1) * 23, 0)
		btn:RegisterForClicks("AnyUp", "AnyDown")
		btn:SetAttribute("type", "spell")
		btn:SetAttribute("spell", b.spell)
		btn:SetAttribute("unit", pf.unit)
		S:Backdrop(btn, 1)
		btn.icon = btn:CreateTexture(nil, "ARTWORK")
		btn.icon:SetPoint("TOPLEFT", 1, -1)
		btn.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		btn.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
		btn.text = S:Font(btn, 9)
		btn.text:SetPoint("BOTTOM", 0, 1)
		local ag = btn:CreateAnimationGroup()
		ag:SetLooping("BOUNCE")
		local a = ag:CreateAnimation("Alpha")
		a:SetFromAlpha(1)
		a:SetToAlpha(0.4)
		a:SetDuration(0.6)
		btn.pulse = ag
		btn.def = b
		btn:SetScript("OnEnter", function(self)
			GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
			GameTooltip:AddLine(self.def.spell, 1, 1, 1)
			GameTooltip:AddLine(L["Click: cast on %s"]:format(Safe(UnitName(pf.unit)) or "?"), 0.4, 0.8, 1)
			GameTooltip:Show()
		end)
		btn:SetScript("OnLeave", GameTooltip_Hide)
		btn:Hide()
		pf.buffButtons[i] = btn
	end
end

function UF:UpdatePartyBuffs()
	if not self.built then return end
	local cfg = CK.char.leveling
	local inCombat = InCombatLockdown()
	for n = 1, 4 do
		local pf = self.frames["party" .. n]
		for _, btn in ipairs(pf.buffButtons or {}) do
			local b, u = btn.def, pf.unit
			local wanted = CK.char.units.partyBuffs and CK:Known(b.spell) and UnitExists(u)
				and Safe(UnitIsConnected(u), true) and not Safe(UnitIsDeadOrGhost(u), false)
				and (not b.filter or b.filter(u))
			local found, hidden
			if wanted then
				for _, name in ipairs(b.names) do
					local a, h = CK:FindAura(u, name, "HELPFUL")
					if a then found = name break end
					hidden = hidden or h
				end
			end
			-- auras hidden (combat): leave the button as it is
			local unknown = hidden and not found
			local left = found and CK:AuraRemaining(u, found, "HELPFUL")
			local low = not unknown and (not found or (left and left ~= 1 and left < cfg.buffWarnMinutes * 60))
			local show = wanted and (cfg.buffMode == "always" or low or (unknown and btn:IsShown()))
			-- secure buttons cannot be shown or hidden in combat: only refresh looks then
			if not inCombat then btn:SetShown(show and true or false) end
			if btn:IsShown() then
				btn.icon:SetTexture(CK:SpellTexture(b.spell))
				btn.text:SetText(found and left and left ~= 1 and left ~= math.huge and fmtLeft(left) or ((found or unknown) and "" or "!"))
				local inRange = C_Spell and C_Spell.IsSpellInRange and Safe(C_Spell.IsSpellInRange(b.spell, u))
				btn.icon:SetDesaturated(inRange == false)
				if low then
					btn:SetBackdropBorderColor(unpack(S.colors.warn))
					btn.icon:SetAlpha(1)
					if not btn.pulse:IsPlaying() then btn.pulse:Play() end
				else
					btn:SetBackdropBorderColor(0, 0, 0, 1)
					btn.icon:SetAlpha(0.6)
					btn.pulse:Stop()
				end
			end
		end
	end
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
	C_Timer.NewTicker(1, function() pcall(self.UpdatePartyBuffs, self) end)
end
