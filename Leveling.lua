-- CasterKit by DinX: leveling helpers (XP bar, reminders, merchant)
local _, ns = ...
local CK = ns.CK
local S = CK.Style

local L = CK:NewModule("Leveling")
CK.reminderProviders = {}

-- Class modules call this: fn(add) where add{ key, icon, count, warn, always, tooltip, spell, macrotext, onClick }
function CK:AddReminderProvider(fn)
	table.insert(self.reminderProviders, fn)
end

local hider = CreateFrame("Frame")
hider:Hide()

---------------------------------------------------------------------------
-- XP bar with XP/hour, time to level and kills to level
---------------------------------------------------------------------------
local session = { start = GetTime(), gained = 0, gains = {} }

local function maxLevel()
	if GetMaxLevelForPlayerExpansion then return GetMaxLevelForPlayerExpansion() end
	return MAX_PLAYER_LEVEL or 60
end

local function fmtNum(n)
	n = math.floor(n + 0.5)
	local s = tostring(n)
	while true do
		local r, k = s:gsub("^(-?%d+)(%d%d%d)", "%1.%2")
		s = r
		if k == 0 then break end
	end
	return s
end

local function fmtTime(sec)
	if sec >= 3600 then return ("%du%02d"):format(sec / 3600, (sec % 3600) / 60) end
	return ("%d min"):format(math.max(1, sec / 60))
end

function L:CreateXPBar()
	local holder = CreateFrame("Frame", "CasterKitXP", UIParent, "BackdropTemplate")
	holder:SetHeight(12)
	S:Backdrop(holder, 1)
	local rested = S:StatusBar(holder, S.colors.rested)
	rested:SetPoint("TOPLEFT", 1, -1)
	rested:SetPoint("BOTTOMRIGHT", -1, 1)
	rested:SetAlpha(0.5)
	rested.bg:Hide()
	local bar = S:StatusBar(holder, S.colors.xp)
	bar:SetAllPoints(rested)
	bar.bg:Hide()
	local bg = holder:CreateTexture(nil, "BACKGROUND", nil, 1)
	bg:SetAllPoints(rested)
	bg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
	bar:SetFrameLevel(rested:GetFrameLevel() + 1)
	local text = S:Font(bar, 10)
	text:SetPoint("CENTER", holder, "CENTER", 0, 0)
	holder.bar, holder.rested, holder.text = bar, rested, text

	holder:EnableMouse(true)
	holder:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine("Ervaring", 1, 1, 1)
		local cur, max = UnitXP("player"), UnitXPMax("player")
		GameTooltip:AddDoubleLine("Huidig", ("%s / %s"):format(fmtNum(cur), fmtNum(max)))
		GameTooltip:AddDoubleLine("Nog nodig", fmtNum(max - cur))
		local r = GetXPExhaustion() or 0
		if r > 0 then GameTooltip:AddDoubleLine("Rested", fmtNum(r)) end
		GameTooltip:AddDoubleLine("Deze sessie", fmtNum(session.gained))
		GameTooltip:Show()
	end)
	holder:SetScript("OnLeave", GameTooltip_Hide)
	self.xp = holder
end

function L:PlaceXPBar()
	local h = self.xp
	h:ClearAllPoints()
	h:SetPoint("TOPLEFT", CK.panel, "BOTTOMLEFT", 0, -3)
	h:SetPoint("TOPRIGHT", CK.panel, "BOTTOMRIGHT", 0, -3)
	h:SetScale(CK.char.bars.scale)
end

local lastXP
function L:OnXP()
	local cur, max = UnitXP("player"), UnitXPMax("player")
	if lastXP then
		local delta = cur - lastXP.cur
		if delta < 0 then delta = (lastXP.max - lastXP.cur) + cur end -- leveled up
		if delta > 0 then
			session.gained = session.gained + delta
			table.insert(session.gains, delta)
			if #session.gains > 8 then table.remove(session.gains, 1) end
		end
	end
	lastXP = { cur = cur, max = max }
	self:UpdateXPBar()
end

function L:UpdateXPBar()
	local h = self.xp
	local show = CK.char.leveling.xpbar and UnitLevel("player") < maxLevel()
	h:SetShown(show)
	if not show then return end
	local cur, max = UnitXP("player"), math.max(1, UnitXPMax("player"))
	local rest = GetXPExhaustion() or 0
	h.bar:SetMinMaxValues(0, max)
	h.bar:SetValue(cur)
	h.rested:SetMinMaxValues(0, max)
	h.rested:SetValue(math.min(max, cur + rest))

	local parts = { ("Level %d"):format(UnitLevel("player")), ("%d%%"):format(cur / max * 100) }
	local elapsed = GetTime() - session.start
	if session.gained > 0 and elapsed > 120 then
		local perSec = session.gained / elapsed
		parts[#parts + 1] = ("%s XP/u"):format(fmtNum(perSec * 3600))
		parts[#parts + 1] = ("±%s"):format(fmtTime((max - cur) / perSec))
	end
	if #session.gains > 0 then
		local sum = 0
		for _, g in ipairs(session.gains) do sum = sum + g end
		parts[#parts + 1] = ("±%d kills"):format(math.ceil((max - cur) / (sum / #session.gains)))
	end
	if rest > 0 then parts[#parts + 1] = "rested" end
	h.text:SetText(table.concat(parts, "  ·  "))
end

function L:HideBlizzardXP()
	if not CK.char.leveling.hideBlizzardXP or not CK.char.leveling.xpbar then return end
	for _, name in ipairs({ "StatusTrackingBarManager", "MainStatusTrackingBarContainer", "SecondaryStatusTrackingBarContainer" }) do
		local f = _G[name]
		if f then
			f:UnregisterAllEvents()
			f:Hide()
			f:SetParent(hider)
		end
	end
end

---------------------------------------------------------------------------
-- Reminder strip (secure buttons so a click can cast e.g. Conjure Water)
---------------------------------------------------------------------------
local slots = {}

local function slot(i)
	if slots[i] then return slots[i] end
	local b = CreateFrame("Button", "CasterKitReminder" .. i, L.strip, "SecureActionButtonTemplate,BackdropTemplate")
	b:SetSize(26, 26)
	b:RegisterForClicks("AnyUp", "AnyDown")
	S:Backdrop(b, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.count = S:Font(b, 11)
	b.count:SetPoint("BOTTOMRIGHT", -1, 1)
	local ag = b:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local a = ag:CreateAnimation("Alpha")
	a:SetFromAlpha(1)
	a:SetToAlpha(0.4)
	a:SetDuration(0.6)
	b.pulse = ag
	b:SetScript("OnEnter", function(self)
		if not self.entry then return end
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		GameTooltip:AddLine(self.entry.tooltip or "", 1, 1, 1, true)
		if self.entry.spell then GameTooltip:AddLine("Klik: " .. self.entry.spell, 0.4, 0.8, 1) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	b:SetScript("PostClick", function(self)
		if self.entry and self.entry.onClick and not InCombatLockdown() then self.entry.onClick() end
	end)
	slots[i] = b
	return b
end

function L:CreateStrip()
	local f = CreateFrame("Frame", "CasterKitReminders", UIParent)
	f:SetSize(1, 26)
	self.strip = f
end

function L:PlaceStrip()
	local f = self.strip
	f:ClearAllPoints()
	f:SetPoint("BOTTOMLEFT", CK.panel, "TOPLEFT", 0, 10)
	f:SetScale(CK.char.bars.scale)
end

function L:CollectEntries()
	local list = {}
	local function add(e) list[#list + 1] = e end
	for _, fn in ipairs(CK.reminderProviders) do pcall(fn, add) end
	local out = {}
	for _, e in ipairs(list) do
		if e.always or e.warn then out[#out + 1] = e end
	end
	return out
end

function L:UpdateStrip()
	if not CK.char.leveling.reminders then
		if not InCombatLockdown() then self.strip:Hide() end
		return
	end
	local entries = self:CollectEntries()
	if InCombatLockdown() then
		-- secure buttons are frozen in combat: refresh what is shown, nothing else
		for _, b in ipairs(slots) do
			if b:IsShown() and b.entry then
				for _, e in ipairs(entries) do
					if e.key == b.entry.key then b.count:SetText(e.count or "") end
				end
			end
		end
		return
	end
	self.strip:Show()
	for i, e in ipairs(entries) do
		local b = slot(i)
		b.entry = e
		b.icon:SetTexture(e.icon or 134400)
		b.count:SetText(e.count or "")
		b:SetAttribute("type", e.spell and "spell" or (e.macrotext and "macro") or nil)
		b:SetAttribute("spell", e.spell)
		b:SetAttribute("unit", e.spell and "player" or nil)
		b:SetAttribute("macrotext", e.macrotext)
		if e.warn then
			b:SetBackdropBorderColor(unpack(S.colors.warn))
			b.pulse:Play()
		else
			b:SetBackdropBorderColor(0, 0, 0, 1)
			b.pulse:Stop()
		end
		b:ClearAllPoints()
		b:SetPoint("BOTTOMLEFT", self.strip, "BOTTOMLEFT", (i - 1) * 29, 0)
		b:Show()
	end
	for i = #entries + 1, #slots do
		slots[i].entry = nil
		slots[i]:Hide()
	end
end

---------------------------------------------------------------------------
-- Generic reminders
---------------------------------------------------------------------------
local function lowestDurability()
	local low
	for s = 1, 18 do
		local cur, max = GetInventoryItemDurability(s)
		if cur and max and max > 0 then
			local p = cur / max
			if not low or p < low then low = p end
		end
	end
	return low
end

CK:AddReminderProvider(function(add)
	local cfg = CK.char.leveling
	local free = CK:FreeBagSlots()
	add({ key = "bags", icon = 133633, count = free, warn = free <= 2, tooltip = ("Nog %d vrije plaatsen in je tassen."):format(free) })

	local dur = lowestDurability()
	if dur then
		add({ key = "durability", icon = 136241, count = ("%d%%"):format(dur * 100), warn = dur < 0.3,
			tooltip = "Je uitrusting is versleten. Laat herstellen bij een verkoper." })
	end

	if cfg.trainer and cfg.trainerPending then
		add({ key = "trainer", icon = 136234, warn = true,
			tooltip = ("Level %d: er zijn nieuwe spreuken bij je trainer."):format(cfg.trainerPending) })
	end

	if cfg.talents then
		local pts = CK:UnspentTalentPoints()
		if pts > 0 then
			add({ key = "talents", icon = 132222, count = pts, warn = true,
				tooltip = ("%d talentpunt(en) vrij. Klik om je talenten te openen."):format(pts),
				onClick = function()
					if ToggleTalentFrame then ToggleTalentFrame()
					elseif PlayerSpellsUtil and PlayerSpellsUtil.ToggleClassTalentFrame then PlayerSpellsUtil.ToggleClassTalentFrame() end
				end })
		end
	end
end)

---------------------------------------------------------------------------
-- Merchant: sell grey items and repair (only when you open a vendor)
---------------------------------------------------------------------------
local function onMerchant()
	local cfg = CK.char.leveling
	if cfg.sellGrey then
		local sold, value = 0, 0
		CK:ForEachBagItem(function(bag, slotIndex, info)
			if sold < 12 and info.quality == 0 and not info.hasNoValue and not info.isLocked then
				local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
				local price = select(11, getInfo(info.itemID)) or 0
				value = value + price * (info.stackCount or 1)
				if C_Container and C_Container.UseContainerItem then
					C_Container.UseContainerItem(bag, slotIndex)
				else
					UseContainerItem(bag, slotIndex)
				end
				sold = sold + 1
			end
		end)
		if sold > 0 then
			CK:Print(("%d grijze item(s) verkocht voor %s."):format(sold, GetCoinTextureString(value)))
		end
	end
	if cfg.repair and CanMerchantRepair and CanMerchantRepair() then
		local cost, needed = GetRepairAllCost()
		if needed and cost > 0 and cost <= GetMoney() then
			RepairAllItems()
			CK:Print("Uitrusting hersteld voor " .. GetCoinTextureString(cost) .. ".")
		end
	end
end

---------------------------------------------------------------------------
-- Mob tooltip: how many of these until the next level
---------------------------------------------------------------------------
-- Classic "zero difference" table: mobs this many levels below you give no XP.
local function zeroDiff(pl)
	if pl <= 7 then return 5 elseif pl <= 9 then return 6 elseif pl <= 11 then return 7
	elseif pl <= 15 then return 8 elseif pl <= 19 then return 9 elseif pl <= 29 then return 11
	elseif pl <= 39 then return 12 elseif pl <= 44 then return 13 elseif pl <= 49 then return 14
	elseif pl <= 54 then return 15 elseif pl <= 59 then return 16 end
	return 17
end

local function grayLevel(pl)
	if pl <= 5 then return 0 elseif pl <= 39 then return pl - 5 - math.floor(pl / 10) end
	return pl - 1 - math.floor(pl / 5)
end

-- Classic formula; Forever may differ, so measured values win when we have them.
function L:EstimateMobXP(unit)
	local pl, ml = UnitLevel("player"), UnitLevel(unit)
	if ml < 0 then ml = pl + 10 end
	if ml <= grayLevel(pl) then return 0 end
	local base = ml * 5 + 45
	local xp
	if ml >= pl then
		xp = base * (1 + 0.05 * math.min(4, ml - pl))
	else
		xp = base * (1 - (pl - ml) / zeroDiff(pl))
	end
	local cls = UnitClassification(unit)
	if cls == "elite" or cls == "rareelite" or cls == "worldboss" then xp = xp * 2 end
	return math.floor(xp)
end

local XP_PATTERN = "^(.+) dies, you gain (%d+) experience"

function L:OnXPMessage(msg)
	if CK.IsSecret(msg) or type(msg) ~= "string" then return end
	local name, amount = msg:match(XP_PATTERN)
	amount = tonumber(amount)
	if not name or not amount then return end
	-- strip the rested bonus so the stored value is the plain kill XP
	local bonus = tonumber(msg:match("%+(%d+) exp [Rr]ested bonus")) or tonumber(msg:match("%((%d+) exp [Rr]ested bonus")) or 0
	local key = ("%s:%d"):format(name, UnitLevel("player"))
	CK.char.leveling.mobXP = CK.char.leveling.mobXP or {}
	CK.char.leveling.mobXP[key] = amount - bonus
end

function L:TooltipUnit(tooltip, unit)
	if not CK.char.leveling.mobTooltip or not unit then return end
	if not UnitCanAttack("player", unit) or UnitIsPlayer(unit) or UnitIsDead(unit) then return end
	if UnitLevel("player") >= maxLevel() then return end
	if UnitIsTapDenied and UnitIsTapDenied(unit) then return end

	local name = UnitName(unit)
	local key = name and ("%s:%d"):format(name, UnitLevel("player"))
	local measured = key and CK.char.leveling.mobXP and CK.char.leveling.mobXP[key]
	local xp = measured or self:EstimateMobXP(unit)
	if xp <= 0 then
		tooltip:AddLine("Geeft geen XP meer", 0.6, 0.6, 0.6)
		return
	end
	local need = UnitXPMax("player") - UnitXP("player")
	local rested = GetXPExhaustion() or 0
	-- rested doubles kill XP until the rested pool runs out
	local kills
	if rested >= need / 2 then
		kills = math.ceil(need / (xp * 2))
	else
		local restedKills = math.floor(rested / xp)
		kills = restedKills + math.ceil((need - restedKills * xp * 2) / xp)
	end
	local tag = measured and "gemeten" or "geschat"
	local group = IsInGroup() and ", solo-waarde" or ""
	tooltip:AddLine(("±%d kills tot level %d (%s%s)"):format(kills, UnitLevel("player") + 1, tag, group), 0.58, 0.36, 0.86)
	tooltip:Show()
end

function L:HookTooltip()
	if TooltipDataProcessor and Enum.TooltipDataType then
		TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, function(tooltip)
			if tooltip ~= GameTooltip then return end
			local _, unit = tooltip:GetUnit()
			pcall(self.TooltipUnit, self, tooltip, unit)
		end)
	else
		GameTooltip:HookScript("OnTooltipSetUnit", function(tooltip)
			local _, unit = tooltip:GetUnit()
			pcall(self.TooltipUnit, self, tooltip, unit)
		end)
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function L:OnEnable()
	self:CreateXPBar()
	self:CreateStrip()
	self:PlaceXPBar()
	self:PlaceStrip()
	self:HideBlizzardXP()
	self:OnXP()
	self:HookTooltip()
	CK:On("CHAT_MSG_COMBAT_XP_GAIN", function(_, msg) self:OnXPMessage(msg) end)

	CK:On("PLAYER_XP_UPDATE", function() self:OnXP() end)
	CK:On("UPDATE_EXHAUSTION", function() self:UpdateXPBar() end)
	CK:On("PLAYER_LEVEL_UP", function(_, level)
		if level % 2 == 0 then
			CK.char.leveling.trainerPending = level
			if CK.char.leveling.trainer then
				UIErrorsFrame:AddMessage(("Level %d: nieuwe spreuken bij je trainer!"):format(level), 1, 0.82, 0.25)
			end
		end
		C_Timer.After(1, function() self:UpdateXPBar() end)
	end)
	CK:On("TRAINER_SHOW", function() CK.char.leveling.trainerPending = nil end)
	CK:On("MERCHANT_SHOW", onMerchant)
	CK:On("PLAYER_REGEN_ENABLED", function() self:UpdateStrip() end)
	CK:Listen("PANEL_LAYOUT", function() self:PlaceXPBar(); self:PlaceStrip() end)
	CK:Listen("SETTINGS", function(group)
		if group == "leveling" or group == "bars" then
			self:HideBlizzardXP()
			self:PlaceXPBar()
			self:PlaceStrip()
			self:UpdateXPBar()
			self:UpdateStrip()
		end
	end)
	C_Timer.NewTicker(1, function() self:UpdateStrip() end)
	C_Timer.NewTicker(5, function() self:UpdateXPBar() end)
end
