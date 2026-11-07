-- CasterKit by DinX: one compact bag window with categories, junk selling and bag assignment
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe = CK.Safe

local B = CK:NewModule("Bags")

-- Nothing here plays for you: items are only used, sold or moved when you click.
-- Item buttons use Blizzard's ContainerFrameItemButtonTemplate, so a click works
-- like in the normal bags (also in combat). We never write into those buttons'
-- Lua tables; our own data lives in side tables keyed by button.

local CC = C_Container
local PAD, GAP, HEADER_H, TOP_H, BOTTOM_H, SLOT_H, MIN_W = 6, 2, 15, 26, 18, 24, 250
local SELL_PER_TICK, SELL_INTERVAL = 3, 0.2
local NUM_BAGS = NUM_BAG_SLOTS or 4
local REAGENT_BAG = Enum and Enum.BagIndex and Enum.BagIndex.ReagentBag
if type(REAGENT_BAG) ~= "number" or REAGENT_BAG <= NUM_BAGS then REAGENT_BAG = nil end

local BAGS = {}
for bag = 0, NUM_BAGS do BAGS[#BAGS + 1] = bag end
if REAGENT_BAG then BAGS[#BAGS + 1] = REAGENT_BAG end

local DEFAULTS = {
	enabled = true, view = "category", columns = 10, iconSize = 34,
	itemLevel = true, showNewGlow = true, autoOpenMerchant = true,
}

-- Category sections in display order (label keys).
local SECTIONS = {
	{ key = "new", label = "New" },
	{ key = "equipment", label = "Equipment" },
	{ key = "consumables", label = "Consumables" },
	{ key = "trade", label = "Trade Goods" },
	{ key = "quest", label = "Quest" },
	{ key = "other", label = "Reagents/Other" },
	{ key = "junk", label = "Junk" },
	{ key = "empty", label = "Free slots" },
}
local SECTION_LABEL = {}
for _, s in ipairs(SECTIONS) do SECTION_LABEL[s.key] = s.label end

local IC = Enum and Enum.ItemClass or {}
local CLASS = {
	consumable = IC.Consumable or 0, weapon = IC.Weapon or 2, gem = IC.Gem or 3, armor = IC.Armor or 4,
	projectile = IC.Projectile or 6, trade = IC.Tradegoods or 7, enhance = IC.ItemEnhancement or 8,
	recipe = IC.Recipe or 9, quest = IC.Questitem or 12, glyph = IC.Glyph or 16, profession = IC.Profession or 19,
}

local F = Enum and Enum.BagSlotFlags or {}
local ASSIGN = {
	{ F.ClassEquipment or F.PriorityEquipment, "Equipment" },
	{ F.ClassConsumables or F.PriorityConsumables, "Consumables" },
	{ F.ClassProfessionGoods or F.PriorityTradeGoods, "Trade Goods" },
	{ F.ClassQuestItems or F.PriorityQuestItems, "Quest" },
	{ F.ClassJunk or F.PriorityJunk, "Junk" },
}
local FLAG_NOSORT = F.DisableAutoSort
local FLAG_NOJUNKSELL = F.ExcludeJunkSell

---------------------------------------------------------------------------
-- Small safe helpers (secret or wrong-typed values become the default)
---------------------------------------------------------------------------
local function num(v, default)
	v = Safe(v, nil)
	if type(v) ~= "number" then return default end
	return v
end

local function str(v)
	v = Safe(v, nil)
	if type(v) ~= "string" or v == "" then return nil end
	return v
end

local function flag(v)
	v = Safe(v, nil)
	return v ~= nil and v ~= false and v ~= 0
end

local function clamp(v, lo, hi)
	if v < lo then return lo elseif v > hi then return hi end
	return v
end

-- pcall that passes on every result, or nothing on error
local function pass(ok, ...)
	if ok then return ... end
end
local function try(fn, ...)
	if type(fn) ~= "function" then return end
	return pass(pcall(fn, ...))
end

-- Report the first error once, then stay quiet (no error floods).
local reported = false
local function guard(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok and not reported then
		reported = true
		local handler = geterrorhandler and geterrorhandler()
		if handler then handler(err) end
	end
end

---------------------------------------------------------------------------
-- Settings (read defensively: the group may not exist yet)
---------------------------------------------------------------------------
local function opt(key)
	local c = CK.char and CK.char.bags
	local v = type(c) == "table" and c[key] or nil
	if v == nil then v = DEFAULTS[key] end
	return v
end

local function junkList()
	if not CK.char then return {} end
	if type(CK.char.bags) ~= "table" then CK.char.bags = {} end
	local c = CK.char.bags
	if type(c.junkList) ~= "table" then c.junkList = {} end
	return c.junkList
end

---------------------------------------------------------------------------
-- Blizzard API wrappers (C_Container first, old globals as fallback)
---------------------------------------------------------------------------
local function numSlots(bag)
	return num(try(CC and CC.GetContainerNumSlots or GetContainerNumSlots, bag), 0)
end

local function freeSlots(bag)
	local n, family = try(CC and CC.GetContainerNumFreeSlots or GetContainerNumFreeSlots, bag)
	return num(n, 0), num(family, 0)
end

local function slotInfo(bag, slot)
	local info = try(CK.ItemInfoAt, CK, bag, slot)
	if type(info) == "table" then return info end
end

local function invID(bag)
	return num(try(CC and CC.ContainerIDToInventoryID or ContainerIDToInventoryID, bag))
end

local function bagName(bag)
	if bag == 0 then return L["Backpack"] end
	local name = str(try(CC and CC.GetBagName or GetBagName, bag))
	if name then return name end
	if bag == REAGENT_BAG then return L["Reagent bag"] end
	return L["Bag %d"]:format(bag)
end

local function useItem(bag, slot)
	if CC and CC.UseContainerItem then
		CC.UseContainerItem(bag, slot)
	elseif UseContainerItem then
		UseContainerItem(bag, slot)
	end
end

local function itemPrice(id)
	local getInfo = C_Item and C_Item.GetItemInfo or GetItemInfo
	return num(select(11, try(getInfo, id)), 0)
end

local function qualityColor(q)
	local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
	if c and c.r then return c.r, c.g, c.b end
	local r, g, b = try(C_Item and C_Item.GetItemQualityColor or GetItemQualityColor, q)
	if type(r) == "number" then return r, g, b end
	return 1, 1, 1
end

local function itemLevel(bag, slot, link)
	if C_Item and C_Item.GetCurrentItemLevel and ItemLocation and ItemLocation.CreateFromBagAndSlot then
		local loc = try(ItemLocation.CreateFromBagAndSlot, ItemLocation, bag, slot)
		local lvl = loc and num(try(C_Item.GetCurrentItemLevel, loc))
		if lvl then return lvl end
	end
	if link then
		return num(try(C_Item and C_Item.GetDetailedItemLevelInfo or GetDetailedItemLevelInfo, link))
	end
end

local function getFlag(bag, f)
	if not (f and CC and CC.GetBagSlotFlag) then return false end
	return flag(try(CC.GetBagSlotFlag, bag, f))
end

local function setFlag(bag, f, on)
	if f and CC and CC.SetBagSlotFlag then try(CC.SetBagSlotFlag, bag, f, on and true or false) end
end

local function ignoresCleanup(bag)
	if bag == 0 then return flag(try(CC and CC.GetBackpackAutosortDisabled or GetBackpackAutosortDisabled)) end
	return getFlag(bag, FLAG_NOSORT)
end

local function setIgnoresCleanup(bag, on)
	if bag == 0 then
		try(CC and CC.SetBackpackAutosortDisabled or SetBackpackAutosortDisabled, on and true or false)
	else
		setFlag(bag, FLAG_NOSORT, on)
	end
end

-- Label key of the class flag this bag has, or nil.
local function assignment(bag)
	for _, a in ipairs(ASSIGN) do
		if a[1] and getFlag(bag, a[1]) then return a[2] end
	end
end

local function canAssign(bag)
	return bag ~= 0 and bag ~= REAGENT_BAG and CC and CC.SetBagSlotFlag ~= nil
end

local function eventExists(event)
	if C_EventUtils and C_EventUtils.IsEventValid then
		local ok, valid = pcall(C_EventUtils.IsEventValid, event)
		if ok then return valid and true or false end
	end
	local probe = CreateFrame("Frame")
	local ok = pcall(probe.RegisterEvent, probe, event)
	probe:UnregisterAllEvents()
	return ok
end

---------------------------------------------------------------------------
-- Reading a slot and choosing its category
---------------------------------------------------------------------------
local buttons, holders = {}, {} -- buttons[bag][slot]
local data, deco = {}, {}       -- side tables keyed by button

local function classify(d)
	if not d.id then return "empty" end
	if d.junk then return "junk" end
	if d.new then return "new" end
	local c = d.classID
	if d.isQuest or c == CLASS.quest then return "quest" end
	if d.bag == REAGENT_BAG then return "trade" end
	if c == CLASS.weapon or c == CLASS.armor then return "equipment" end
	if c == CLASS.consumable or c == CLASS.projectile then return "consumables" end
	if c == CLASS.trade or c == CLASS.gem or c == CLASS.enhance or c == CLASS.recipe
		or c == CLASS.glyph or c == CLASS.profession then
		return "trade"
	end
	local loc = d.equipLoc
	if loc and loc ~= "" and loc ~= "INVTYPE_NON_EQUIP_IGNORE" and loc ~= "INVTYPE_NON_EQUIP" and loc ~= "INVTYPE_BAG" then
		return "equipment"
	end
	return "other"
end

local function readSlot(b)
	local d = data[b]
	local bag, slot = d.bag, d.slot
	wipe(d)
	d.bag, d.slot = bag, slot
	local info = slotInfo(bag, slot)
	local id = info and num(info.itemID)
	if not id then
		d.cat = "empty"
		return d
	end
	d.id = id
	d.icon = Safe(info.iconFileID, nil)
	d.count = num(info.stackCount, 1)
	d.quality = num(info.quality, 1)
	d.link = str(info.hyperlink)
	d.locked = flag(info.isLocked)
	d.noValue = flag(info.hasNoValue)
	d.marked = junkList()[id] == true
	d.junk = d.quality == 0 or d.marked

	local _, itemType, subType, equipLoc, _, classID, subID = try(C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant, id)
	d.classID, d.subID, d.equipLoc = num(classID), num(subID), str(equipLoc)

	if CC and CC.GetContainerItemQuestInfo then
		local q = try(CC.GetContainerItemQuestInfo, bag, slot)
		if type(q) == "table" then
			local qid = num(q.questID)
			d.isQuest = flag(q.isQuestItem) or qid ~= nil
			d.questStart = qid ~= nil and not flag(q.isActive)
		end
	elseif GetContainerItemQuestInfo then
		local isQuest, qid, active = try(GetContainerItemQuestInfo, bag, slot)
		d.isQuest = flag(isQuest) or num(qid) ~= nil
		d.questStart = num(qid) ~= nil and not flag(active)
	end

	if not d.junk and C_NewItems and C_NewItems.IsNewItem then
		d.new = flag(try(C_NewItems.IsNewItem, bag, slot))
	end
	d.cat = classify(d)

	local name = d.link and d.link:match("%[(.-)%]") or ""
	d.search = (name .. " " .. (str(itemType) or "") .. " " .. (str(subType) or "") .. " "
		.. L[SECTION_LABEL[d.cat] or "Reagents/Other"]):lower()
	return d
end

-- Uncommon to epic weapons and armour can be disenchanted.
local function disenchantable(d)
	if not d.id or d.locked or not d.quality or d.quality < 2 or d.quality > 4 then return false end
	return d.classID == 2 or d.classID == 4
end

-- Junk the Sell button may sell: greys and items you marked, with a vendor price.
local function sellable(d)
	if not d.id or not d.junk or d.noValue or d.locked then return false end
	if d.quality == 0 and not d.marked and FLAG_NOJUNKSELL and d.bag ~= 0 and getFlag(d.bag, FLAG_NOJUNKSELL) then
		return false
	end
	return true
end

---------------------------------------------------------------------------
-- Item buttons (Blizzard's secure template, pooled per bag holder)
---------------------------------------------------------------------------
local TEMPLATE_BITS = {
	"IconBorder", "IconOverlay", "IconOverlay2", "NewItemTexture", "BattlepayItemTexture", "JunkIcon",
	"UpgradeIcon", "IconQuestTexture", "flash", "ExtendedSlot", "ProfessionQualityOverlay",
}

local function hideRegion(r)
	if r and r.SetAlpha then pcall(r.SetAlpha, r, 0) end
end

local function makeBorder(f)
	local lines = {}
	for i = 1, 4 do
		local t = f:CreateTexture(nil, "OVERLAY", nil, 2)
		t:SetTexture(S.flat)
		t:SetVertexColor(0, 0, 0, 1)
		lines[i] = t
	end
	lines[1]:SetPoint("TOPLEFT"); lines[1]:SetPoint("TOPRIGHT"); lines[1]:SetHeight(1)
	lines[2]:SetPoint("BOTTOMLEFT"); lines[2]:SetPoint("BOTTOMRIGHT"); lines[2]:SetHeight(1)
	lines[3]:SetPoint("TOPLEFT"); lines[3]:SetPoint("BOTTOMLEFT"); lines[3]:SetWidth(1)
	lines[4]:SetPoint("TOPRIGHT"); lines[4]:SetPoint("BOTTOMRIGHT"); lines[4]:SetWidth(1)
	return lines
end

local function setBorder(lines, r, g, b)
	for i = 1, 4 do lines[i]:SetVertexColor(r, g, b, 1) end
end

local function skin(b, name)
	local v = {}
	deco[b] = v
	v.icon = b.icon or b.Icon or _G[name .. "IconTexture"]
	v.count = b.Count or _G[name .. "Count"]
	v.cd = b.Cooldown or _G[name .. "Cooldown"]
	for _, k in ipairs(TEMPLATE_BITS) do hideRegion(b[k]) end
	hideRegion(_G[name .. "IconQuestTexture"])
	hideRegion(_G[name .. "NormalTexture"])
	if b.GetNormalTexture then hideRegion(b:GetNormalTexture()) end

	local bg = b:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0.10, 0.12, 0.17, 1)

	if v.icon then
		v.icon:ClearAllPoints()
		v.icon:SetPoint("TOPLEFT", 1, -1)
		v.icon:SetPoint("BOTTOMRIGHT", -1, 1)
		v.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end
	if v.cd then
		v.cd:ClearAllPoints()
		v.cd:SetPoint("TOPLEFT", 1, -1)
		v.cd:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	local hl = b.GetHighlightTexture and b:GetHighlightTexture()
	if hl then
		hl:SetColorTexture(1, 1, 1, 0.15)
		hl:ClearAllPoints()
		hl:SetPoint("TOPLEFT", 1, -1)
		hl:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	local pushed = b.GetPushedTexture and b:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(0.9, 0.8, 0.1, 0.3)
		pushed:ClearAllPoints()
		pushed:SetPoint("TOPLEFT", 1, -1)
		pushed:SetPoint("BOTTOMRIGHT", -1, 1)
	end

	-- overlay above the cooldown swipe: border, texts, markers
	local ov = CreateFrame("Frame", nil, b)
	ov:SetAllPoints()
	ov:SetFrameLevel(b:GetFrameLevel() + 4)
	v.border = makeBorder(ov)

	if v.count then
		v.count:SetParent(ov)
		v.count:SetFont(S.font, 11, "OUTLINE")
		v.count:ClearAllPoints()
		v.count:SetPoint("BOTTOMRIGHT", -2, 2)
		v.count:SetJustifyH("RIGHT")
	else
		v.count = S:Font(ov, 11)
		v.count:SetPoint("BOTTOMRIGHT", -2, 2)
	end

	v.ilvl = S:Font(ov, 10)
	v.ilvl:SetPoint("TOPLEFT", 2, -2)

	v.quest = S:Font(ov, 14)
	v.quest:SetPoint("TOPRIGHT", -2, -1)
	v.quest:SetText("!")
	v.quest:SetTextColor(unpack(S.colors.hint))
	v.quest:Hide()

	v.junk = ov:CreateTexture(nil, "OVERLAY", nil, 3)
	v.junk:SetSize(12, 12)
	v.junk:SetPoint("TOPLEFT", 1, -1)
	local ok, set = pcall(v.junk.SetAtlas, v.junk, "bags-junkcoin")
	if not ok or set == false then v.junk:SetTexture("Interface\\MoneyFrame\\UI-GoldIcon") end
	v.junk:Hide()

	v.glow = ov:CreateTexture(nil, "OVERLAY", nil, 1)
	v.glow:SetPoint("TOPLEFT", 1, -1)
	v.glow:SetPoint("BOTTOMRIGHT", -1, 1)
	v.glow:SetTexture(S.flat)
	v.glow:SetBlendMode("ADD")
	local a = S.colors.accent
	v.glow:SetVertexColor(a[1], a[2], a[3], 0.35)
	local ag = v.glow:CreateAnimationGroup()
	ag:SetLooping("BOUNCE")
	local anim = ag:CreateAnimation("Alpha")
	anim:SetFromAlpha(1)
	anim:SetToAlpha(0.2)
	anim:SetDuration(0.8)
	v.glowAnim = ag
	v.glow:Hide()
end

local function paintCooldown(b)
	local v, d = deco[b], data[b]
	local cd = v and v.cd
	if not cd then return end
	local start, dur, enable
	if d.id then start, dur, enable = try(CC and CC.GetContainerItemCooldown or GetContainerItemCooldown, d.bag, d.slot) end
	if CK.IsSecret(start) or CK.IsSecret(dur) then
		-- cooldown frames accept hidden values; we just never compute with them
		pcall(cd.SetCooldown, cd, start, dur)
		return
	end
	start, dur = num(start, 0), num(dur, 0)
	local en = Safe(enable, 1)
	if d.id and en ~= 0 and en ~= false and start > 0 and dur > 0 then
		cd:SetCooldown(start, dur)
	elseif cd.Clear then
		cd:Clear()
	else
		cd:Hide()
	end
end

local function paint(b)
	local d, v = data[b], deco[b]
	if not (d and v) then return end
	local has = d.id ~= nil
	if v.icon then
		v.icon:SetTexture(has and d.icon or nil)
		v.icon:SetShown(has)
		v.icon:SetDesaturated(d.locked and true or false)
		local dim = d.junk and 0.6 or 1
		v.icon:SetVertexColor(dim, dim, dim)
	end
	v.count:SetText((has and d.count and d.count > 1) and d.count or "")

	if d.isQuest then
		setBorder(v.border, unpack(S.colors.hint))
	elseif has and d.quality and d.quality >= 2 then
		setBorder(v.border, qualityColor(d.quality))
	else
		setBorder(v.border, 0, 0, 0)
	end

	local lvl
	if has and opt("itemLevel") and not d.junk and (d.classID == CLASS.weapon or d.classID == CLASS.armor)
		and d.equipLoc and d.equipLoc ~= "INVTYPE_BODY" and d.equipLoc ~= "INVTYPE_TABARD" and d.equipLoc ~= "INVTYPE_BAG" then
		lvl = itemLevel(d.bag, d.slot, d.link)
	end
	if lvl and lvl > 1 then
		v.ilvl:SetText(math.floor(lvl + 0.5))
		v.ilvl:SetTextColor(qualityColor(d.quality or 1))
		v.ilvl:Show()
	else
		v.ilvl:Hide()
	end

	v.junk:SetShown(has and d.junk and not d.noValue)
	v.quest:SetShown(has and d.questStart and true or false)

	if has and d.new and opt("showNewGlow") then
		v.glow:Show()
		if not v.glowAnim:IsPlaying() then v.glowAnim:Play() end
	else
		v.glowAnim:Stop()
		v.glow:Hide()
	end
	paintCooldown(b)
end

local function addTooltipLines(tt, d)
	if not d or not d.id then return end
	if junkList()[d.id] then
		tt:AddLine(L["Marked as junk: the Sell junk button sells it."], 1, 0.55, 0.3, true)
		tt:AddLine(L["Alt-click: no longer junk"], 0.6, 0.65, 0.71)
	elseif d.quality ~= 0 then
		tt:AddLine(L["Alt-click: mark as junk"], 0.6, 0.65, 0.71)
	end
end

local function onItemClick(self, button)
	guard(function()
		if button ~= "LeftButton" or not IsAltKeyDown() or IsShiftKeyDown() or IsControlKeyDown() then return end
		local d = data[self]
		if d and d.id then B:ToggleJunk(d.id, d.link) end
	end)
end

local DISENCHANT_ID = 13262
local deButton
local function disenchantName()
	local n = CK.GetSpellName and CK.GetSpellName(DISENCHANT_ID)
	if not n and GetSpellInfo then n = GetSpellInfo(DISENCHANT_ID) end
	return n
end

local function knowsDisenchant()
	local n = disenchantName()
	return n ~= nil and CK:Known(n)
end

local function hideDisenchant()
	if deButton and not InCombatLockdown() then
		deButton:Hide()
		deButton:ClearAllPoints()
	end
end

local function placeDisenchant(itemButton, d)
	if InCombatLockdown() or not B.deMode then return end
	local spell = disenchantName()
	if not spell then return end
	if not deButton then
		deButton = CreateFrame("Button", "CasterKitDisenchantButton", UIParent, "SecureActionButtonTemplate")
		deButton:RegisterForClicks("AnyUp", "AnyDown")
		deButton:SetAttribute("type", "macro")
		local hl = deButton:CreateTexture(nil, "OVERLAY")
		hl:SetAllPoints()
		hl:SetColorTexture(0.64, 0.21, 0.93, 0.35)
		deButton:SetScript("OnEnter", function(self)
			guard(function()
				GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
				if self.bag then GameTooltip:SetBagItem(self.bag, self.slot) end
				GameTooltip:AddLine(L["Click: disenchant"], 0.64, 0.21, 0.93)
				GameTooltip:Show()
			end)
		end)
		deButton:SetScript("OnLeave", function()
			GameTooltip:Hide()
			hideDisenchant()
		end)
		deButton:Hide()
	end
	deButton:SetAttribute("macrotext", "/cast " .. spell .. "\n/use " .. d.bag .. " " .. d.slot)
	deButton.bag, deButton.slot = d.bag, d.slot
	deButton:SetFrameStrata("DIALOG")
	deButton:ClearAllPoints()
	deButton:SetAllPoints(itemButton)
	deButton:Show()
end

local function onItemEnter(self)
	guard(function()
		local dd = data[self]
		if B.deMode and dd and disenchantable(dd) then placeDisenchant(self, dd) end
	end)
	guard(function()
		local d, v = data[self], deco[self]
		if not d then return end
		if d.new then
			if C_NewItems and C_NewItems.RemoveNewItem then try(C_NewItems.RemoveNewItem, d.bag, d.slot) end
			d.new = false
			if v then v.glowAnim:Stop(); v.glow:Hide() end
		end
		if not B.tooltipHooked and GameTooltip:IsOwned(self) then
			addTooltipLines(GameTooltip, d)
			GameTooltip:Show()
		end
	end)
end

-- Only used when the template has no tooltip of its own.
local function ownEnter(self)
	guard(function()
		local d = data[self]
		if not (d and d.id) then return end
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:SetBagItem(d.bag, d.slot)
		if B.atMerchant and ShowContainerSellCursor then try(ShowContainerSellCursor, d.bag, d.slot) end
		GameTooltip:Show()
	end)
	onItemEnter(self)
end

local function ownLeave()
	GameTooltip:Hide()
	if ResetCursor then ResetCursor() end
end

local function holder(bag)
	local h = holders[bag]
	if h then return h end
	-- the template reads the bag from its parent's ID, the slot from its own
	h = CreateFrame("Frame", "CasterKitBagHolder" .. bag, B.content)
	h:SetID(bag)
	h:SetAllPoints(B.content)
	holders[bag] = h
	return h
end

local function createButton(bag, slot)
	local parent = holder(bag)
	local name = ("CasterKitBagItem%d_%d"):format(bag, slot)
	local ok, b = pcall(CreateFrame, "ItemButton", name, parent, "ContainerFrameItemButtonTemplate")
	if not ok or not b then ok, b = pcall(CreateFrame, "Button", name, parent, "ContainerFrameItemButtonTemplate") end
	if not ok or not b then return end
	b:SetID(slot)
	pcall(b.RegisterForClicks, b, "LeftButtonUp", "RightButtonUp")
	data[b] = { bag = bag, slot = slot }
	skin(b, name)
	b:Hide()
	if B.protected == nil then B.protected = b:IsProtected() and true or false end
	b:HookScript("OnClick", onItemClick)
	if b:GetScript("OnEnter") then
		b:HookScript("OnEnter", onItemEnter)
	else
		b:SetScript("OnEnter", ownEnter)
		b:SetScript("OnLeave", ownLeave)
	end
	return b
end

function B:EnsureButtons()
	if not self.content then return end
	if InCombatLockdown() then
		CK:OutOfCombat("bags-buttons", function()
			guard(B.EnsureButtons, B)
			B:RequestUpdate()
		end)
		return
	end
	for _, bag in ipairs(BAGS) do
		buttons[bag] = buttons[bag] or {}
		local list = buttons[bag]
		for slot = 1, numSlots(bag) do
			if not list[slot] then list[slot] = createButton(bag, slot) end
		end
	end
end

-- Moving or showing frames is only blocked in combat when they are protected.
local function frozen()
	return InCombatLockdown() and B.protected
end

---------------------------------------------------------------------------
-- Layout: sections with headers that reflow; empty sections are hidden
---------------------------------------------------------------------------
local headers = {}
local lists = {}
for _, s in ipairs(SECTIONS) do lists[s.key] = {} end
local placed, emptyRep, emptyCount, emptyOrder, bagList = {}, {}, {}, {}, {}

local function sorter(a, b)
	local x, y = data[a], data[b]
	if (x.quality or 0) ~= (y.quality or 0) then return (x.quality or 0) > (y.quality or 0) end
	if (x.classID or 99) ~= (y.classID or 99) then return (x.classID or 99) < (y.classID or 99) end
	if (x.subID or 99) ~= (y.subID or 99) then return (x.subID or 99) < (y.subID or 99) end
	if (x.id or 0) ~= (y.id or 0) then return (x.id or 0) < (y.id or 0) end
	if (x.count or 0) ~= (y.count or 0) then return (x.count or 0) > (y.count or 0) end
	if x.bag ~= y.bag then return x.bag < y.bag end
	return x.slot < y.slot
end

local function header(i)
	if not headers[i] then
		local fs = S:Font(B.content, 11)
		fs:SetTextColor(unpack(S.colors.accent))
		headers[i] = fs
	end
	return headers[i]
end

function B:Layout()
	local f = self.frame
	if not f then return end
	if frozen() then
		CK:OutOfCombat("bags-layout", function() guard(B.Layout, B) end)
		return
	end
	local size = clamp(math.floor(num(opt("iconSize"), 34)), 20, 60)
	local cols = clamp(math.floor(num(opt("columns"), 10)), 4, 30)
	local content = self.content
	wipe(placed)
	local y, hi = 0, 0

	local function place(label, list, total)
		hi = hi + 1
		local h = header(hi)
		h:ClearAllPoints()
		h:SetPoint("TOPLEFT", content, "TOPLEFT", 0, -y)
		h:SetText(("%s  |cff999999%d|r"):format(label, total or #list))
		h:Show()
		y = y + HEADER_H
		for i, b in ipairs(list) do
			local col, row = (i - 1) % cols, math.floor((i - 1) / cols)
			b:SetSize(size, size)
			b:ClearAllPoints()
			b:SetPoint("TOPLEFT", content, "TOPLEFT", col * (size + GAP), -(y + row * (size + GAP)))
			b:Show()
			placed[b] = true
		end
		y = y + math.ceil(#list / cols) * (size + GAP) + 4
	end

	if opt("view") == "bag" then
		for _, bag in ipairs(BAGS) do
			local n, list = numSlots(bag), buttons[bag]
			if n > 0 and list then
				wipe(bagList)
				for slot = 1, n do
					if list[slot] then bagList[#bagList + 1] = list[slot] end
				end
				if #bagList > 0 then place(bagName(bag), bagList) end
			end
		end
	else
		for _, s in ipairs(SECTIONS) do wipe(lists[s.key]) end
		wipe(emptyRep); wipe(emptyCount); wipe(emptyOrder)
		for _, bag in ipairs(BAGS) do
			local list = buttons[bag]
			if list then
				local _, family = freeSlots(bag)
				for slot = 1, numSlots(bag) do
					local b = list[slot]
					local d = b and data[b]
					if d and d.id then
						local target = lists[d.cat] or lists.other
						target[#target + 1] = b
					elseif d then
						-- one free slot per bag type, with the number of free slots on it
						local key = bag == REAGENT_BAG and "reagent" or ("f" .. family)
						emptyCount[key] = (emptyCount[key] or 0) + 1
						if not emptyRep[key] then
							emptyRep[key] = b
							emptyOrder[#emptyOrder + 1] = key
						end
					end
				end
			end
		end
		local totalFree = 0
		for _, key in ipairs(emptyOrder) do
			local b = emptyRep[key]
			lists.empty[#lists.empty + 1] = b
			deco[b].count:SetText(emptyCount[key])
			totalFree = totalFree + emptyCount[key]
		end
		for _, s in ipairs(SECTIONS) do
			local list = lists[s.key]
			if #list > 0 then
				if s.key ~= "empty" then table.sort(list, sorter) end
				place(L[s.label], list, s.key == "empty" and totalFree or nil)
			end
		end
	end

	for _, list in pairs(buttons) do
		for _, b in pairs(list) do
			if not placed[b] then b:Hide() end
		end
	end
	for i = hi + 1, #headers do headers[i]:Hide() end

	local width = cols * size + (cols - 1) * GAP
	content:SetSize(width, math.max(1, y))
	local stripH = self.strip:IsShown() and (SLOT_H + 4) or 0
	content:ClearAllPoints()
	content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TOP_H + stripH + 4))
	f:SetSize(math.max(MIN_W, width + PAD * 2), TOP_H + stripH + 4 + math.max(y, 10) + BOTTOM_H + 2)
end

---------------------------------------------------------------------------
-- Refresh
---------------------------------------------------------------------------
local pump = CreateFrame("Frame")
pump:Hide()
pump:SetScript("OnUpdate", function(self)
	self:Hide()
	guard(B.Refresh, B)
end)

function B:RequestUpdate()
	if self.frame and self.frame:IsShown() then pump:Show() else self.dirty = true end
end

function B:Refresh()
	if not self.active or not self.frame or not self.frame:IsShown() then
		self.dirty = true
		return
	end
	self.dirty = false
	if not InCombatLockdown() then self:EnsureButtons() end
	for _, bag in ipairs(BAGS) do
		local list = buttons[bag]
		if list then
			local n = numSlots(bag)
			for slot, b in pairs(list) do
				if slot <= n then
					readSlot(b)
					paint(b)
				end
			end
		end
	end
	self:Layout()
	self:ApplySearch()
	self:UpdateBar()
	self:UpdateStrip()
end

function B:UpdateCooldowns()
	if not (self.frame and self.frame:IsShown()) then return end
	for _, list in pairs(buttons) do
		for _, b in pairs(list) do
			if b:IsShown() then paintCooldown(b) end
		end
	end
end

function B:UpdateLock(bag, slot)
	local list = buttons[bag]
	local b = list and slot and list[slot]
	if not b or not data[b].id then return end
	local info = slotInfo(bag, slot)
	data[b].locked = info and flag(info.isLocked) or false
	local v = deco[b]
	if v and v.icon then v.icon:SetDesaturated(data[b].locked) end
end

-- Search text and hovered bag slot dim everything that does not match.
function B:ApplySearch()
	local q, hb = self.query, self.hoverBag
	for _, list in pairs(buttons) do
		for _, b in pairs(list) do
			local d = data[b]
			local match = true
			if self.deMode then
				match = disenchantable(d)
			elseif hb ~= nil then
				match = d.bag == hb
			elseif q then
				match = d.search ~= nil and d.search:find(q, 1, true) ~= nil
			end
			b:SetAlpha(match and 1 or 0.25)
		end
	end
end

function B:UpdateBar()
	local f = self.frame
	if not f then return end
	f.gold:SetText(GetCoinTextureString and GetCoinTextureString(num(GetMoney(), 0)) or "")
	local free, rfree = 0, 0
	for _, bag in ipairs(BAGS) do
		local n, family = freeSlots(bag)
		if bag == REAGENT_BAG then rfree = rfree + n elseif family == 0 then free = free + n end
	end
	local text = L["%d free"]:format(free)
	if REAGENT_BAG and numSlots(REAGENT_BAG) > 0 then
		text = text .. "  |cff999999" .. L["reagents %d"]:format(rfree) .. "|r"
	end
	f.free:SetText(text)
	f.free:SetTextColor(unpack(free <= 2 and S.colors.warn or S.colors.text))

	local canSort = (CC and CC.SortBags or SortBags) and not InCombatLockdown()
	self:SetButtonEnabled(f.sortBtn, canSort and true or false)
	if f.deBtn then
		local known = knowsDisenchant()
		if not known then B.deMode = false end
		f.deBtn:SetShown(known)
		self:SetButtonEnabled(f.deBtn, not InCombatLockdown())
		f.deBtn:SetBackdropBorderColor(unpack(B.deMode and { 0.64, 0.21, 0.93, 1 } or { 0, 0, 0, 1 }))
	end
	self:SetButtonEnabled(f.sellBtn, self:MerchantOpen() and not self.selling and self:JunkCount() > 0)
	f.viewBtn.icon:SetTexture(opt("view") == "bag" and "Interface\\Icons\\INV_Misc_Bag_10" or "Interface\\Icons\\INV_Misc_Book_09")
end

---------------------------------------------------------------------------
-- Junk: mark with Alt-click, sell with one click at a merchant
---------------------------------------------------------------------------
function B:ToggleJunk(id, link)
	local list = junkList()
	local label = link or CK:ItemName(id) or ("item:" .. id)
	if list[id] then
		list[id] = nil
		CK:Print(L["%s is no longer junk."]:format(label))
	else
		list[id] = true
		CK:Print(L["%s marked as junk."]:format(label))
	end
	self:RequestUpdate()
end

function B:JunkCount()
	local n, value = 0, 0
	for _, list in pairs(buttons) do
		for _, b in pairs(list) do
			local d = data[b]
			if d.bag ~= nil and sellable(d) and d.slot <= numSlots(d.bag) then
				n = n + 1
				value = value + itemPrice(d.id) * (d.count or 1)
			end
		end
	end
	return n, value
end

function B:MerchantOpen()
	if not self.atMerchant then return false end
	local mf = _G.MerchantFrame
	return mf == nil or mf:IsShown()
end

local seller = CreateFrame("Frame")
seller:Hide()

function B:StopSelling()
	seller:Hide()
	if self.selling then
		self.selling = false
		if (self.sold or 0) > 0 then
			CK:Print(L["Sold %d junk item(s) for %s."]:format(self.sold, GetCoinTextureString(self.soldValue or 0)))
		end
	end
end

function B:SellJunk()
	if self.selling or not self:MerchantOpen() then return end
	local queue = {}
	for _, bag in ipairs(BAGS) do
		for slot = 1, numSlots(bag) do
			local b = buttons[bag] and buttons[bag][slot]
			local d = b and readSlot(b)
			if d and sellable(d) then queue[#queue + 1] = { bag = bag, slot = slot, id = d.id } end
		end
	end
	if #queue == 0 then return end
	self.queue, self.sold, self.soldValue, self.selling = queue, 0, 0, true
	seller.wait = 0
	seller:Show()
	self:UpdateBar()
end

seller:SetScript("OnUpdate", function(self, elapsed)
	self.wait = (self.wait or 0) - elapsed
	if self.wait > 0 then return end
	self.wait = SELL_INTERVAL
	guard(function()
		local queue = B.queue
		for _ = 1, SELL_PER_TICK do
			-- stop at once when the merchant closes: outside a vendor this would use the item
			if not B:MerchantOpen() or not queue or #queue == 0 then
				B:StopSelling()
				B:RequestUpdate()
				return
			end
			local q = table.remove(queue, 1)
			local info = slotInfo(q.bag, q.slot)
			if info and num(info.itemID) == q.id and not flag(info.isLocked) and not flag(info.hasNoValue) then
				B.soldValue = B.soldValue + itemPrice(q.id) * num(info.stackCount, 1)
				B.sold = B.sold + 1
				useItem(q.bag, q.slot)
			end
		end
		if #queue == 0 then
			B:StopSelling()
			B:RequestUpdate()
		end
	end)
end)

---------------------------------------------------------------------------
-- Bag slots: equip bags, assign what goes in them (Blizzard's bag flags)
---------------------------------------------------------------------------
function B:BagMenu(owner, bag)
	if not (MenuUtil and MenuUtil.CreateContextMenu) then
		CK:Print(L["This client has no bag menu."])
		return
	end
	MenuUtil.CreateContextMenu(owner, function(_, root)
		root:CreateTitle(bagName(bag))
		if canAssign(bag) then
			root:CreateTitle(L["Assign to"])
			root:CreateRadio(L["Nothing"], function() return assignment(bag) == nil end, function()
				for _, a in ipairs(ASSIGN) do setFlag(bag, a[1], false) end
				B:UpdateStrip()
			end)
			for _, a in ipairs(ASSIGN) do
				if a[1] then
					root:CreateRadio(L[a[2]], function() return getFlag(bag, a[1]) end, function()
						local was = getFlag(bag, a[1])
						for _, other in ipairs(ASSIGN) do setFlag(bag, other[1], false) end
						if not was then setFlag(bag, a[1], true) end
						B:UpdateStrip()
					end)
				end
			end
			root:CreateDivider()
		end
		if bag == 0 or FLAG_NOSORT then
			root:CreateCheckbox(L["Ignore when sorting"], function() return ignoresCleanup(bag) end, function()
				setIgnoresCleanup(bag, not ignoresCleanup(bag))
				B:UpdateStrip()
			end)
		end
	end)
end

local function slotTooltip(self)
	local bag = self.bag
	GameTooltip:SetOwner(self, "ANCHOR_TOP")
	local inv = bag ~= 0 and invID(bag)
	if not (inv and GameTooltip:SetInventoryItem("player", inv)) then
		GameTooltip:AddLine(bag == 0 and L["Backpack"] or L["Empty bag slot"], 1, 1, 1)
	end
	local a = canAssign(bag) and assignment(bag)
	if a then GameTooltip:AddLine(L["Assigned to: %s"]:format(L[a]), 0.41, 0.8, 0.94) end
	if ignoresCleanup(bag) then GameTooltip:AddLine(L["Ignored when sorting"], 0.41, 0.8, 0.94) end
	GameTooltip:AddLine(L["Right-click: choose what goes in this bag"], 0.6, 0.65, 0.71)
	GameTooltip:Show()
end

local function makeSlotButton(parent, bag)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(SLOT_H, SLOT_H)
	S:Backdrop(b, 1)
	b.bag = bag
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.mark = b:CreateTexture(nil, "OVERLAY")
	b.mark:SetSize(6, 6)
	b.mark:SetPoint("BOTTOMRIGHT", -2, 2)
	b.mark:SetColorTexture(unpack(S.colors.accent))
	b.mark:Hide()
	b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	b:RegisterForDrag("LeftButton")
	b:SetScript("OnClick", function(self, button)
		guard(function()
			if button == "RightButton" then
				B:BagMenu(self, bag)
			elseif bag ~= 0 and not InCombatLockdown() then
				local inv = invID(bag)
				if not inv then return end
				if CursorHasItem and CursorHasItem() then
					if PutItemInBag then PutItemInBag(inv) end
				elseif PickupBagFromSlot then
					PickupBagFromSlot(inv)
				end
			end
		end)
	end)
	b:SetScript("OnDragStart", function()
		guard(function()
			local inv = bag ~= 0 and invID(bag)
			if inv and not InCombatLockdown() and PickupBagFromSlot then PickupBagFromSlot(inv) end
		end)
	end)
	b:SetScript("OnReceiveDrag", function()
		guard(function()
			local inv = bag ~= 0 and invID(bag)
			if inv and not InCombatLockdown() and PutItemInBag then PutItemInBag(inv) end
		end)
	end)
	b:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(S.colors.accent))
		guard(slotTooltip, self)
		B.hoverBag = bag
		guard(B.ApplySearch, B)
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		GameTooltip:Hide()
		B.hoverBag = nil
		guard(B.ApplySearch, B)
	end)
	return b
end

function B:UpdateStrip()
	local strip = self.strip
	if not strip or not strip:IsShown() then return end
	local x = 0
	for _, bag in ipairs(BAGS) do
		local b = strip.slots[bag]
		local inv = bag ~= 0 and invID(bag)
		local show = bag ~= REAGENT_BAG or inv ~= nil
		b:SetShown(show)
		if show then
			b:ClearAllPoints()
			b:SetPoint("LEFT", strip, "LEFT", x, 0)
			x = x + SLOT_H + 4
			local tex
			if bag == 0 then
				tex = "Interface\\Buttons\\Button-Backpack-Up"
			else
				tex = inv and GetInventoryItemTexture("player", inv) or "Interface\\PaperDoll\\UI-PaperDoll-Slot-Bag"
			end
			b.icon:SetTexture(tex)
			b.mark:SetShown((canAssign(bag) and assignment(bag) ~= nil) or ignoresCleanup(bag))
		end
	end
end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function iconButton(parent, texture, onClick, tipFn)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(20, 20)
	S:Backdrop(b, 1)
	b.icon = b:CreateTexture(nil, "ARTWORK")
	b.icon:SetPoint("TOPLEFT", 1, -1)
	b.icon:SetPoint("BOTTOMRIGHT", -1, 1)
	b.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	b.icon:SetTexture(texture)
	b:SetMotionScriptsWhileDisabled(true)
	b:SetScript("OnClick", function(self, button) guard(onClick, self, button) end)
	b:SetScript("OnEnter", function(self)
		self:SetBackdropBorderColor(unpack(S.colors.accent))
		GameTooltip:SetOwner(self, "ANCHOR_TOP")
		guard(tipFn, self)
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", function(self)
		self:SetBackdropBorderColor(0, 0, 0, 1)
		GameTooltip:Hide()
	end)
	return b
end

function B:SetButtonEnabled(b, on)
	b:SetEnabled(on)
	b.icon:SetDesaturated(not on)
	b.icon:SetAlpha(on and 1 or 0.4)
end

function B:CreateWindow()
	local f = CreateFrame("Frame", "CasterKitBags", UIParent, "BackdropTemplate")
	f:SetFrameStrata("MEDIUM")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetSize(MIN_W, 120)
	S:Backdrop(f, 0.92)
	f:Hide()
	tinsert(UISpecialFrames, "CasterKitBags")
	self.frame = f

	local bar = f:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(TOP_H - 2)
	bar:SetColorTexture(0.08, 0.10, 0.14, 1)

	local title = S:Font(f, 12)
	title:SetPoint("TOPLEFT", 8, -7)
	title:SetText(L["Bags"])
	title:SetTextColor(unpack(S.colors.accent))

	-- right side buttons, from right to left
	local close = CreateFrame("Button", nil, f)
	close:SetSize(20, 20)
	close:SetPoint("TOPRIGHT", -3, -3)
	local x = S:Font(close, 14)
	x:SetPoint("CENTER")
	x:SetText("X")
	close:SetScript("OnClick", function() f:Hide() end)

	f.slotsBtn = iconButton(f, "Interface\\Icons\\INV_Misc_Bag_08", function()
		if frozen() then return end
		B.strip:SetShown(not B.strip:IsShown())
		B:UpdateStrip()
		B:Layout()
	end, function()
		GameTooltip:AddLine(L["Bag slots"], 1, 1, 1)
		GameTooltip:AddLine(L["Show your bags. Right-click a bag to choose what goes in it."], 0.6, 0.65, 0.71, true)
	end)
	f.slotsBtn:SetPoint("RIGHT", close, "LEFT", -3, 0)

	f.viewBtn = iconButton(f, "Interface\\Icons\\INV_Misc_Book_09", function()
		if type(CK.char.bags) ~= "table" then CK.char.bags = {} end
		CK.char.bags.view = opt("view") == "bag" and "category" or "bag"
		CK:Fire("SETTINGS", "bags")
	end, function()
		GameTooltip:AddLine(opt("view") == "bag" and L["View: by bag"] or L["View: by category"], 1, 1, 1)
		GameTooltip:AddLine(L["Click to switch."], 0.6, 0.65, 0.71)
	end)
	f.viewBtn:SetPoint("RIGHT", f.slotsBtn, "LEFT", -3, 0)

	f.sellBtn = iconButton(f, "Interface\\Icons\\INV_Misc_Coin_02", function() B:SellJunk() end, function()
		GameTooltip:AddLine(L["Sell junk"], 1, 1, 1)
		GameTooltip:AddLine(L["Grey items and items you marked as junk (Alt-click)."], 0.6, 0.65, 0.71, true)
		local n, value = B:JunkCount()
		if n > 0 then GameTooltip:AddLine(L["%d item(s), worth %s"]:format(n, GetCoinTextureString(value)), 1, 1, 1) end
		if not B:MerchantOpen() then GameTooltip:AddLine(L["Open a merchant first."], 1, 0.3, 0.3) end
	end)
	f.sellBtn:SetPoint("RIGHT", f.viewBtn, "LEFT", -3, 0)

	f.sortBtn = iconButton(f, "Interface\\Icons\\INV_Pet_Broom", function()
		if InCombatLockdown() then return end
		local sort = CC and CC.SortBags or SortBags
		if sort then sort() end
	end, function()
		GameTooltip:AddLine(L["Sort bags"], 1, 1, 1)
		GameTooltip:AddLine(L["Blizzard's own clean-up. Right-click a bag slot to keep a bag out of it."], 0.6, 0.65, 0.71, true)
		if InCombatLockdown() then GameTooltip:AddLine(L["Not in combat."], 1, 0.3, 0.3) end
	end)
	f.sortBtn:SetPoint("RIGHT", f.sellBtn, "LEFT", -3, 0)

	f.deBtn = iconButton(f, "Interface\\Icons\\INV_Enchant_Disenchant", function()
		if InCombatLockdown() then return end
		B.deMode = not B.deMode
		if not B.deMode then hideDisenchant() end
		B:ApplySearch()
		B:UpdateBar()
	end, function()
		GameTooltip:AddLine(L["Disenchant mode"], 1, 1, 1)
		GameTooltip:AddLine(L["Highlights what you can disenchant. Click an item to disenchant it, one per click."], 0.6, 0.65, 0.71, true)
		if InCombatLockdown() then GameTooltip:AddLine(L["Not in combat."], 1, 0.3, 0.3) end
	end)
	f.deBtn:SetPoint("RIGHT", f.sortBtn, "LEFT", -3, 0)

	local search = CreateFrame("EditBox", nil, f, "BackdropTemplate")
	search:SetHeight(18)
	search:SetPoint("LEFT", title, "RIGHT", 8, 0)
	search:SetPoint("RIGHT", f.deBtn, "LEFT", -6, 0)
	S:Backdrop(search, 1)
	search:SetFont(S.font, 11, "")
	search:SetTextColor(unpack(S.colors.text))
	search:SetTextInsets(5, 5, 0, 0)
	search:SetAutoFocus(false)
	search:SetMaxLetters(40)
	local hint = search:CreateFontString(nil, "OVERLAY")
	hint:SetFont(S.font, 11, "")
	hint:SetTextColor(unpack(S.colors.muted))
	hint:SetPoint("LEFT", 6, 0)
	hint:SetText(L["Search"])
	search:SetScript("OnEscapePressed", function(self) self:SetText(""); self:ClearFocus() end)
	search:SetScript("OnEnterPressed", search.ClearFocus)
	search:SetScript("OnEditFocusGained", function() hint:Hide() end)
	search:SetScript("OnEditFocusLost", function(self) hint:SetShown(self:GetText() == "") end)
	search:SetScript("OnTextChanged", function(self)
		local t = strtrim(self:GetText() or ""):lower()
		B.query = t ~= "" and t or nil
		hint:SetShown(t == "" and not self:HasFocus())
		guard(B.ApplySearch, B)
	end)
	f.search = search

	local strip = CreateFrame("Frame", nil, f)
	strip:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TOP_H + 2))
	strip:SetPoint("TOPRIGHT", f, "TOPRIGHT", -PAD, -(TOP_H + 2))
	strip:SetHeight(SLOT_H)
	strip.slots = {}
	for _, bag in ipairs(BAGS) do strip.slots[bag] = makeSlotButton(strip, bag) end
	strip:Hide()
	self.strip = strip

	local content = CreateFrame("Frame", nil, f)
	content:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -(TOP_H + 4))
	content:SetSize(1, 1)
	self.content = content

	f.gold = S:Font(f, 11)
	f.gold:SetPoint("BOTTOMLEFT", 8, 5)
	f.free = S:Font(f, 11)
	f.free:SetPoint("BOTTOMRIGHT", -8, 5)

	f:SetScript("OnShow", function()
		B.shownAt = GetTime()
		guard(B.Refresh, B)
	end)
	f:SetScript("OnHide", function()
		B.deMode = false
		hideDisenchant()
		B.hoverBag = nil
		search:ClearFocus()
		-- like Blizzard's bags: items stop being "new" once you closed your bags
		if C_NewItems and C_NewItems.ClearAll then try(C_NewItems.ClearAll) end
		if B.modern and not B.syncing and B.active and CloseAllBags then
			B.syncing = true
			pcall(CloseAllBags)
			B.syncing = false
		end
	end)

	S:RegisterMover(f, "bags", L["Bags"], function(frame)
		frame:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -6, 60)
	end)
end

---------------------------------------------------------------------------
-- Opening and closing: follow Blizzard's bag functions, keep their frames out of sight
---------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()
local reparented = {}

-- Blizzard frames for the backpack, bags 1-4 and the reagent bag (fixed in modern clients).
local function blizzardFrames()
	local list = {}
	if _G.ContainerFrameCombinedBags then list[#list + 1] = _G.ContainerFrameCombinedBags end
	for i = 1, #BAGS do
		local cf = _G["ContainerFrame" .. i]
		if cf then list[#list + 1] = cf end
	end
	return list
end

local function isPlayerBag(id)
	return id ~= nil and ((id >= 0 and id <= NUM_BAGS) or id == REAGENT_BAG)
end

function B:HideBlizzard()
	if self.modern then
		-- A hidden parent keeps them "open" for Blizzard's logic but never visible,
		-- so B, the backpack button and vendors still toggle bags as usual.
		CK:OutOfCombat("bags-hide", function()
			if not B.active then return end
			for _, cf in ipairs(blizzardFrames()) do
				if cf:GetParent() ~= hider then
					reparented[cf] = cf:GetParent() or UIParent
					cf:SetParent(hider)
				end
			end
		end)
	end
	if not self.showHooked then
		self.showHooked = true
		local frames = {}
		for i = 1, (NUM_CONTAINER_FRAMES or 13) do
			local cf = _G["ContainerFrame" .. i]
			if cf then frames[#frames + 1] = cf end
		end
		if _G.ContainerFrameCombinedBags then frames[#frames + 1] = _G.ContainerFrameCombinedBags end
		for _, cf in ipairs(frames) do
			cf:HookScript("OnShow", function(frame) guard(B.OnBlizzardShow, B, frame) end)
		end
	end
end

-- Only reached when a Blizzard bag frame really becomes visible.
function B:OnBlizzardShow(frame)
	if not self.active then return end
	if self.modern then
		if reparented[frame] or frame == _G.ContainerFrameCombinedBags or frame:GetID() and isPlayerBag(frame:GetID()) then
			self:HideBlizzard()
			self:Sync()
		end
		return
	end
	local id = frame:GetID()
	if frame == _G.ContainerFrameCombinedBags or isPlayerBag(id) then
		frame:Hide()
		if not self.suppressOpen then self:Open() end
	end
end

function B:RestoreBlizzard()
	CK:OutOfCombat("bags-hide", function()
		if B.active then return end
		for cf, parent in pairs(reparented) do
			if cf:GetParent() == hider then cf:SetParent(parent) end
		end
		wipe(reparented)
	end)
end

local function blizzardOpen()
	for _, cf in ipairs(blizzardFrames()) do
		if cf:IsShown() then return true end
	end
	return false
end

function B:Open()
	local f = self.frame
	if not f or f:IsShown() then return end
	if frozen() then
		CK:OutOfCombat("bags-open", function() if B.active then B:Open() end end)
		return
	end
	f:Show()
end

function B:Close()
	local f = self.frame
	if not f or not f:IsShown() then return end
	if frozen() then
		CK:OutOfCombat("bags-close", function() B:Close() end)
		return
	end
	f:Hide()
end

-- Modern clients: our window mirrors whether Blizzard thinks the bags are open.
function B:Sync()
	if not self.active or self.syncing or not self.frame then return end
	local want = blizzardOpen()
	if want == self.frame:IsShown() then return end
	self.syncing = true
	if want then self:Open() else self:Close() end
	self.syncing = false
end

-- True when our window was already open before this frame's key press or click.
function B:WasOpen()
	return self.frame and self.frame:IsShown() and self.shownAt ~= GetTime()
end

function B:OnOpenAll(opener)
	if opener and opener == _G.MerchantFrame and not opt("autoOpenMerchant") and not self:WasOpen() then
		if self.modern then
			self.syncing = true
			pcall(CloseAllBags, opener)
			self.syncing = false
			self:Sync()
		else
			self:Close()
		end
		return
	end
	if self.modern then self:Sync() end
end

function B:InstallHooks()
	local function hook(name, fn)
		if type(_G[name]) == "function" then
			hooksecurefunc(name, function(...)
				if B.active then guard(fn, ...) end
			end)
		end
	end
	local sync = function() B:Sync() end
	if self.modern then
		for _, name in ipairs({ "ToggleAllBags", "ToggleBackpack", "ToggleBag", "OpenBackpack", "OpenBag",
			"CloseAllBags", "CloseBackpack", "CloseBag", "UpdateContainerFrameAnchors" }) do
			hook(name, sync)
		end
	else
		-- older clients: Blizzard frames are hidden on show, so toggle our own window
		local function toggle(id)
			if id ~= nil and not isPlayerBag(id) then return end
			if B:WasOpen() then B:Close() end
		end
		hook("ToggleAllBags", function() toggle() end)
		hook("ToggleBackpack", function() toggle() end)
		hook("ToggleBag", toggle)
		hook("CloseAllBags", function() B:Close() end)
		hook("CloseBackpack", function() B:Close() end)
	end
	hook("OpenAllBags", function(opener) B:OnOpenAll(opener) end)
end

-- For other modules: open/close the bags the Blizzard way, our window follows.
function B:Toggle()
	if not self.active then
		if ToggleAllBags then ToggleAllBags() end
		return
	end
	if self.modern and ToggleAllBags then
		ToggleAllBags()
	elseif self.frame:IsShown() then
		self:Close()
	else
		self:Open()
	end
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function B:Enable()
	if self.active then return end
	self.active = true
	if not self.frame then self:CreateWindow() end
	self:HideBlizzard()
	self:EnsureButtons()
	if self.modern then self:Sync() end
end

function B:Disable()
	if not self.active then return end
	if self.frame and self.frame:IsShown() then self:Close() end
	self.active = false
	self:StopSelling()
	if self.modern and blizzardOpen() and CloseAllBags then pcall(CloseAllBags) end
	self:RestoreBlizzard()
end

function B:ApplySettings()
	local want = opt("enabled") and true or false
	if want and not self.active then
		self:Enable()
	elseif not want and self.active then
		self:Disable()
	elseif self.active then
		self:RequestUpdate()
	end
end

function B:OnInit()
	junkList() -- make sure the per-character junk list exists
end

function B:OnEnable()
	self.modern = _G.ContainerFrameCombinedBags ~= nil

	if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall and Enum and Enum.TooltipDataType then
		local ok = pcall(TooltipDataProcessor.AddTooltipPostCall, Enum.TooltipDataType.Item, function(tt)
			if tt ~= GameTooltip or not B.active then return end
			local owner = tt:GetOwner()
			local d = owner and data[owner]
			if d then
				guard(addTooltipLines, tt, d)
			end
		end)
		self.tooltipHooked = ok
	end

	local function on(event, fn)
		if not eventExists(event) then return end
		CK:On(event, function(...)
			if B.active then guard(fn, ...) end
		end)
	end
	local update = function() B:RequestUpdate() end
	on("BAG_UPDATE_DELAYED", function()
		B:EnsureButtons()
		B:RequestUpdate()
	end)
	on("BAG_CONTAINER_UPDATE", function()
		B:EnsureButtons()
		B:RequestUpdate()
	end)
	on("ITEM_LOCK_CHANGED", function(_, bag, slot) B:UpdateLock(bag, slot) end)
	on("BAG_UPDATE_COOLDOWN", function() B:UpdateCooldowns() end)
	on("BAG_NEW_ITEMS_UPDATED", update)
	on("QUEST_ACCEPTED", update)
	on("QUEST_REMOVED", update)
	on("BAG_SLOT_FLAGS_UPDATED", function() B:UpdateStrip() end)
	on("PLAYER_MONEY", function() B:UpdateBar() end)
	on("MERCHANT_SHOW", function()
		B.atMerchant = true
		B:UpdateBar()
	end)
	on("MERCHANT_CLOSED", function()
		B.atMerchant = false
		B:StopSelling()
		B:UpdateBar()
	end)
	on("PLAYER_REGEN_DISABLED", function()
		if B.deMode then
			B.deMode = false
			hideDisenchant()
			B:ApplySearch()
		end
		B:UpdateBar()
	end)
	on("PLAYER_REGEN_ENABLED", function()
		B:UpdateBar()
		if B.dirty then B:RequestUpdate() end
	end)

	self:InstallHooks()
	CK:Listen("SETTINGS", function(group)
		if group == "bags" then guard(B.ApplySettings, B) end
	end)

	if opt("enabled") then guard(B.Enable, B) end
end
