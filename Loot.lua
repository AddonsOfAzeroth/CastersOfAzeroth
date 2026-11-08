-- Casters of Azeroth by DinX: loot window, loot feed and group loot rolls
--
-- Rules this module keeps (no automation beyond what Blizzard offers):
--   * items are only looted by the user's click (LootSlot in OnClick) or by
--     Blizzard's own auto loot (CVar autoLootDefault, toggled from our settings);
--   * rolls are only made by the user's click (RollOnLoot in OnClick); Blizzard's
--     confirm popups (LOOT_BIND, CONFIRM_LOOT_ROLL) are left untouched;
--   * no chat messages are sent, the combat log is not used.
--
-- Taint notes:
--   * Blizzard's LootFrame closes the loot (CloseLoot) in its OnHide, so it can
--     not simply be hidden on show. Instead we unregister LOOT_OPENED on it
--     while our window is active (a C method call: no Blizzard table is
--     written). Its other events stay, and with master loot we give the event
--     back so Blizzard's own frame (with the master looter list) is used.
--   * Roll frames are our own: UIParent's START_LOOT_ROLL is unregistered while
--     they are on (same approach as ElvUI), so Blizzard's GroupLootFrames are
--     never created and never touched. CONFIRM_LOOT_ROLL stays with UIParent.
--     If UIParent does not own that event in this client, Blizzard's frames
--     stay in use (no duplicates).
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe, IsSecret = CK.Safe, CK.IsSecret

local M = CK:NewModule("Loot")

local WIDTH, ROW_H, ICON = 230, 26, 22
local HEADER, FOOTER, PAD = 22, 26, 4
local FEED_W, FEED_ROW, FEED_ICON = 260, 20, 16
local ROLL_W, ROLL_H, ROLL_GAP = 300, 32, 4

local ROLL_PASS = LOOT_ROLL_TYPE_PASS or 0
local ROLL_NEED = LOOT_ROLL_TYPE_NEED or 1
local ROLL_GREED = LOOT_ROLL_TYPE_GREED or 2
local ROLL_DE = LOOT_ROLL_TYPE_DISENCHANT or 3
local ROLL_TRANSMOG = LOOT_ROLL_TYPE_TRANSMOG or 4

---------------------------------------------------------------------------
-- Small safe helpers
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

local function try(fn, ...)
	if not fn then return end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
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

-- Settings, read defensively (the group may be missing or incomplete).
local DEFAULTS = {
	enabled = true, window = true, atCursor = true, feed = true, feedDuration = 6, feedMax = 6,
	showMoney = true, rollFrames = true, autoLoot = false, questItems = true, bagsFull = true,
}
local function cfg()
	local c = CK.char and CK.char.loot
	if type(c) ~= "table" then return DEFAULTS end
	return c
end
local function opt(key)
	local v = cfg()[key]
	if v == nil then return DEFAULTS[key] end
	return v
end
local function on(key) return opt("enabled") and opt(key) and true or false end

local function qualityColor(q)
	q = num(q)
	if q then
		if C_Item and C_Item.GetItemQualityColor then
			local r, g, b = try(C_Item.GetItemQualityColor, q)
			if type(r) == "number" then return r, g, b end
		end
		local c = ITEM_QUALITY_COLORS and ITEM_QUALITY_COLORS[q]
		if c and c.r then return c.r, c.g, c.b end
	end
	return 1, 1, 1
end

local function hex(r, g, b)
	return string.format("|cff%02x%02x%02x", r * 255, g * 255, b * 255)
end

local function unlocked()
	local bars = CK.char and CK.char.bars
	return bars and not bars.locked and not InCombatLockdown()
end

local function hideTooltip(owner)
	if GameTooltip and GameTooltip:IsOwned(owner) then GameTooltip:Hide() end
end

-- Flat text button in Casters of Azeroth style.
local function flatButton(parent, label, w, h)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h)
	S:Backdrop(b, 1)
	local t = S:Font(b, 11)
	t:SetPoint("CENTER")
	t:SetText(label)
	b.text = t
	b:SetScript("OnEnter", function(btn) btn:SetBackdropBorderColor(unpack(S.colors.accent)) end)
	b:SetScript("OnLeave", function(btn) btn:SetBackdropBorderColor(0, 0, 0, 1) end)
	return b
end

---------------------------------------------------------------------------
-- Loot window
---------------------------------------------------------------------------
local QUEST_BANG = TEXTURE_ITEM_QUEST_BANG or "Interface\\ContainerFrame\\UI-Icon-QuestBang"
local QUEST_BORDER = TEXTURE_ITEM_QUEST_BORDER or "Interface\\ContainerFrame\\UI-Icon-QuestBorder"

-- Group loot method is master loot (Blizzard's frame then handles the loot).
local function masterLoot()
	local m
	if C_PartyInfo and C_PartyInfo.GetLootMethod then
		m = try(C_PartyInfo.GetLootMethod)
	elseif GetLootMethod then
		m = try(GetLootMethod)
	end
	m = Safe(m, nil)
	if m == "master" then return true end
	local E = Enum and Enum.LootMethod
	if type(m) == "number" and E and (m == E.Masterlooter or m == E.MasterLooter) then return true end
	return false
end

function M:WindowActive() return on("window") end

-- Take LOOT_OPENED away from Blizzard's LootFrame while our window is used.
function M:SyncBlizzardLoot()
	if self.lootOpen then return end -- never switch in the middle of looting
	local lf = LootFrame
	if not (lf and lf.IsEventRegistered) then return end
	local want = self:WindowActive() and not masterLoot()
	if want and not self.tookLoot then
		if lf:IsEventRegistered("LOOT_OPENED") then
			lf:UnregisterEvent("LOOT_OPENED")
			self.tookLoot = true
		elseif CK.debug then
			CK:Print("loot: LootFrame does not own LOOT_OPENED, using Blizzard's window")
		end
	elseif not want and self.tookLoot then
		lf:RegisterEvent("LOOT_OPENED")
		self.tookLoot = false
	end
end

function M:CreateWindow()
	local f = CreateFrame("Frame", "CasterKitLootFrame", UIParent, "BackdropTemplate")
	f:SetSize(WIDTH, HEADER + FOOTER)
	f:SetFrameStrata("HIGH")
	f:SetToplevel(true)
	f:EnableMouse(true)
	f:SetClampedToScreen(true)
	S:Backdrop(f, 0.92)
	f:Hide()

	local title = S:Font(f, 12)
	title:SetPoint("TOPLEFT", 6, -5)
	title:SetText(L["Loot"])
	title:SetTextColor(unpack(S.colors.accent))
	f.title = title

	local close = CreateFrame("Button", nil, f)
	close:SetSize(HEADER, HEADER)
	close:SetPoint("TOPRIGHT", 0, 0)
	local x = S:Font(close, 13)
	x:SetPoint("CENTER")
	x:SetText("X")
	close:SetScript("OnClick", function() f:Hide() end)

	local all = flatButton(f, L["Loot all"], WIDTH - PAD * 2, 18)
	all:SetPoint("BOTTOMLEFT", PAD, PAD)
	all:SetScript("OnClick", function() guard(M.LootAll, M) end)
	f.lootAll = all

	f:SetScript("OnHide", function() guard(M.OnWindowHide, M) end)
	-- Esc closes the window (and with it the loot)
	if UISpecialFrames then tinsert(UISpecialFrames, "CasterKitLootFrame") end

	self.window = f
	self.rows = {}
	S:RegisterMover(f, "loot", L["Loot window"], function(fr)
		fr:SetPoint("TOPLEFT", UIParent, "TOPLEFT", 320, -220)
	end, true)
end

function M:Row(i)
	local r = self.rows[i]
	if r then return r end
	r = CreateFrame("Button", nil, self.window)
	r:SetSize(WIDTH - PAD * 2, ROW_H - 2)
	r:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	local hl = r:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.08)
	local icon = S:Icon(r, ICON)
	icon:SetPoint("LEFT", 0, 0)
	r.iconFrame = icon
	local count = S:Font(icon, 10)
	count:SetPoint("BOTTOMRIGHT", -1, 1)
	r.count = count
	local quest = icon:CreateTexture(nil, "OVERLAY")
	quest:SetAllPoints()
	r.quest = quest
	-- quest items: gold tint behind the row and a tag on the right
	local qbg = r:CreateTexture(nil, "BACKGROUND")
	qbg:SetAllPoints()
	qbg:SetColorTexture(1, 0.82, 0, 0.14)
	qbg:Hide()
	r.questBg = qbg
	local tag = S:Font(r, 10)
	tag:SetPoint("RIGHT", r, "RIGHT", -3, 0)
	tag:SetTextColor(1, 0.82, 0)
	r.tag = tag
	local name = S:Font(r, 12)
	name:SetPoint("LEFT", icon, "RIGHT", 6, 0)
	name:SetPoint("RIGHT", tag, "LEFT", -4, 0)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	r.name = name
	r:SetScript("OnClick", function(btn) guard(M.ClickSlot, M, btn) end)
	r:SetScript("OnEnter", function(btn) guard(M.SlotTooltip, M, btn) end)
	r:SetScript("OnLeave", function(btn)
		hideTooltip(btn)
		if ResetCursor then ResetCursor() end
	end)
	self.rows[i] = r
	return r
end

-- Reads one loot slot; nil when the slot is empty.
local slotData = {}
local function readSlot(slot)
	local ok, tex, name, qty, currencyID, quality, locked, isQuest, questID, isActive = pcall(GetLootSlotInfo, slot)
	if not ok then return end
	if not IsSecret(tex) and tex == nil then return end
	wipe(slotData)
	slotData.slot = slot
	slotData.tex = tex
	slotData.name = name
	slotData.qty = num(qty, 1)
	slotData.quality = num(quality)
	slotData.locked = flag(locked)
	slotData.isQuest = flag(isQuest)
	slotData.questID = num(questID)
	slotData.isActive = flag(isActive)
	slotData.kind = num(GetLootSlotType and try(GetLootSlotType, slot), 1)
	-- quest class items count too, even when the loot API does not flag them
	if not slotData.isQuest and GetLootSlotLink then
		local link = try(GetLootSlotLink, slot)
		if type(link) == "string" and not IsSecret(link) then
			local getInstant = C_Item and C_Item.GetItemInfoInstant or GetItemInfoInstant
			local classID = getInstant and select(7, pcall(getInstant, link)) -- ok, id, type, subType, equipLoc, icon, classID
			local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
			if num(classID) == questClass then slotData.isQuest = true end
		end
	end
	return slotData
end

function M:FillRow(r, d)
	r.slot = d.slot
	r.kind = d.kind
	r.iconFrame.icon:SetTexture(d.tex)
	r.iconFrame.icon:SetDesaturated(d.locked)
	local name = d.name
	if IsSecret(name) then
		r.name:SetText(name) -- allowed: secret text may be shown, not changed
	else
		name = type(name) == "string" and name:gsub("\n", " ") or "?"
		r.name:SetText(name)
	end
	if d.locked then
		r.name:SetTextColor(0.5, 0.5, 0.5)
	else
		r.name:SetTextColor(qualityColor(d.quality))
	end
	r.count:SetText(d.qty > 1 and d.qty or "")
	local starts = d.questID and not d.isActive
	local isQuest = starts or d.isQuest or d.questID
	if starts then
		r.quest:SetTexture(QUEST_BANG) -- starts a quest
		r.quest:Show()
	elseif isQuest then
		r.quest:SetTexture(QUEST_BORDER)
		r.quest:Show()
	else
		r.quest:Hide()
	end
	r.questBg:SetShown(isQuest and true or false)
	r.tag:SetText(starts and L["Starts a quest"] or (isQuest and L["Quest"] or ""))
	if isQuest and not d.locked and not IsSecret(d.name) then r.name:SetTextColor(1, 0.82, 0) end
	-- 1px border in the quality colour for green and better
	if d.quality and d.quality >= 2 and not d.locked then
		r.iconFrame:SetBackdropBorderColor(qualityColor(d.quality))
	else
		r.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
	end
	if isQuest and not d.locked then r.iconFrame:SetBackdropBorderColor(1, 0.82, 0, 1) end
end

local SAMPLES = {
	{ tex = 134939, name = "Mirror Lake Water Sample", qty = 1, quality = 1, isQuest = true },
	{ tex = 133784, name = "12 Silver", qty = 1, quality = 1 },
	{ tex = 134939, name = "Linen Cloth", qty = 3, quality = 1 },
	{ tex = 135145, name = "Sample Staff", qty = 1, quality = 3 },
}

function M:RenderWindow()
	local f = self.window
	local shown = 0
	if self.preview then
		for _, s in ipairs(SAMPLES) do
			shown = shown + 1
			local d = { slot = nil, tex = s.tex, name = s.name, qty = s.qty, quality = s.quality, kind = 1 }
			self:FillRow(self:Row(shown), d)
		end
	else
		local n = num(GetNumLootItems and try(GetNumLootItems), 0)
		for slot = 1, n do
			local d = readSlot(slot)
			if d then
				shown = shown + 1
				self:FillRow(self:Row(shown), d)
			end
		end
	end
	for i = 1, shown do
		local r = self.rows[i]
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f, "TOPLEFT", PAD, -HEADER - (i - 1) * ROW_H)
		r:Show()
	end
	for i = shown + 1, #self.rows do
		self.rows[i]:Hide()
		self.rows[i].slot = nil
	end
	f.lootAll:SetShown(shown > 1)
	local foot = shown > 1 and FOOTER or PAD
	f:SetHeight(HEADER + math.max(1, shown) * ROW_H + foot)
	return shown
end

function M:PlaceWindow()
	local f = self.window
	if opt("atCursor") and GetCursorPosition then
		local x, y = GetCursorPosition()
		local s = f:GetEffectiveScale()
		if type(x) == "number" and type(y) == "number" and s and s > 0 then
			f:ClearAllPoints()
			-- first row under the cursor
			f:SetPoint("TOPLEFT", UIParent, "BOTTOMLEFT", x / s - 20, y / s + HEADER + ROW_H / 2)
			return
		end
	end
	S:ApplyPoint(f, "loot")
end

function M:ShowWindow()
	if not self.lootOpen then return end
	self.preview = false
	self:RenderWindow()
	self:PlaceWindow()
	self.window:Show()
end

function M:ClickSlot(btn)
	local slot = btn.slot
	if not slot or not self.lootOpen then return end
	if IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick and GetLootSlotLink then
		local link = try(GetLootSlotLink, slot)
		if link and not IsSecret(link) then
			HandleModifiedItemClick(link)
			return
		end
	end
	-- the user's own click: loot this slot (BoP goes through Blizzard's LOOT_BIND popup)
	LootSlot(slot)
end

function M:SlotTooltip(btn)
	if not (GameTooltip and btn.slot) then return end
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	if btn.kind == 3 and GameTooltip.SetLootCurrency then
		GameTooltip:SetLootCurrency(btn.slot)
	elseif btn.kind ~= 2 and GameTooltip.SetLootItem then
		GameTooltip:SetLootItem(btn.slot)
	else
		GameTooltip:Hide()
		return
	end
	GameTooltip:Show()
	if CursorUpdate then CursorUpdate(btn) end
end

-- One user click loots every slot, like Blizzard's shift-click / auto loot.
function M:LootAll()
	if not self.lootOpen then return end
	local n = num(GetNumLootItems and try(GetNumLootItems), 0)
	for slot = n, 1, -1 do
		local d = readSlot(slot)
		if d and not d.locked then LootSlot(slot) end
	end
end

function M:OnWindowHide()
	hideTooltip(self.window)
	if self.preview then
		self.preview = false
		return
	end
	-- closed by the user (X or Esc) while looting: close the loot too
	if self.lootOpen and not self.closing then
		self.lootOpen = false
		if CloseLoot then CloseLoot() end
	end
end

function M:OnLootOpened(autoLoot)
	self.lootOpen = true
	if self.preview then self.window:Hide() end -- OnWindowHide only ends the preview
	if not (self.tookLoot and self:WindowActive()) then return end
	if flag(autoLoot) then
		-- Blizzard's auto loot is busy: only show what is left a moment later
		local token = {}
		self.autoToken = token
		C_Timer.After(0.35, function()
			if self.autoToken == token and self.lootOpen and not self.window:IsShown() then
				guard(M.ShowWindow, M)
			end
		end)
		return
	end
	self:ShowWindow()
end

function M:OnLootChanged()
	if self.window:IsShown() and not self.preview then self:RenderWindow() end
end

function M:OnLootClosed()
	self.lootOpen = false
	self.autoToken = nil
	if self.window:IsShown() and not self.preview then
		self.closing = true
		self.window:Hide()
		self.closing = false
	end
	self:SyncBlizzardLoot()
	self:UpdatePreview()
end

---------------------------------------------------------------------------
-- Loot feed
---------------------------------------------------------------------------
-- "You receive loot: %sx%d." -> "^You receive loot: (.+)x(%d+)%.$"
local function toPattern(s)
	if type(s) ~= "string" or s == "" then return end
	s = s:gsub("%%%d%$([sd])", "%%%1") -- positional args (order does not matter for enUS)
	s = s:gsub("([%(%)%.%+%-%*%?%[%]%^%$])", "%%%1")
	s = s:gsub("%%s", "(.+)")
	s = s:gsub("%%d", "(%%d+)")
	return "^" .. s .. "$"
end

local function patterns(...)
	local out = {}
	for i = 1, select("#", ...) do
		local p = toPattern(select(i, ...))
		if p then out[#out + 1] = p end
	end
	return out
end

-- multiple first: "(.+)" would otherwise swallow the "x3"
local ITEM_PATTERNS = patterns(LOOT_ITEM_SELF_MULTIPLE, LOOT_ITEM_PUSHED_SELF_MULTIPLE, LOOT_ITEM_CREATED_SELF_MULTIPLE,
	LOOT_ITEM_BONUS_ROLL_SELF_MULTIPLE, LOOT_ITEM_SELF, LOOT_ITEM_PUSHED_SELF, LOOT_ITEM_CREATED_SELF, LOOT_ITEM_BONUS_ROLL_SELF)
local MONEY_PATTERNS = patterns(YOU_LOOT_MONEY_GUILD, LOOT_MONEY_SPLIT_GUILD, YOU_LOOT_MONEY, LOOT_MONEY_SPLIT)
local CURRENCY_PATTERNS = patterns(CURRENCY_GAINED_MULTIPLE_BONUS, CURRENCY_GAINED_MULTIPLE, CURRENCY_GAINED)
local GOLD_P = toPattern(GOLD_AMOUNT or "%d Gold")
local SILVER_P = toPattern(SILVER_AMOUNT or "%d Silver")
local COPPER_P = toPattern(COPPER_AMOUNT or "%d Copper")
-- the money patterns above are anchored for a whole line; strip the anchors
local function unanchor(p) return p and p:gsub("^%^", ""):gsub("%$$", "") end
GOLD_P, SILVER_P, COPPER_P = unanchor(GOLD_P), unanchor(SILVER_P), unanchor(COPPER_P)

local function parseMoney(s)
	local g = GOLD_P and tonumber(s:match(GOLD_P)) or 0
	local sv = SILVER_P and tonumber(s:match(SILVER_P)) or 0
	local c = COPPER_P and tonumber(s:match(COPPER_P)) or 0
	local total = g * 10000 + sv * 100 + c
	if total > 0 then return total end
end

local function moneyText(copper)
	return CK.MoneyText(copper)
end

local entries = {} -- newest first

function M:CreateFeed()
	local f = CreateFrame("Frame", "CasterKitLootFeed", UIParent)
	f:SetSize(FEED_W, FEED_ROW * 6)
	f:SetFrameStrata("MEDIUM")
	f:Hide()
	self.feed = f
	self.feedRows = {}
	f:SetScript("OnUpdate", function(_, elapsed)
		self.feedTick = (self.feedTick or 0) + elapsed
		if self.feedTick < 0.05 then return end
		self.feedTick = 0
		local ok = pcall(M.FeedUpdate, M)
		if not ok then
			wipe(entries)
			f:Hide()
		end
	end)
	S:RegisterMover(f, "lootfeed", L["Loot feed"], function(fr)
		fr:SetPoint("TOPRIGHT", UIParent, "RIGHT", -260, 40)
	end, true)
end

function M:FeedRow(i)
	local r = self.feedRows[i]
	if r then return r end
	r = CreateFrame("Frame", nil, self.feed)
	r:SetSize(FEED_W, FEED_ROW)
	local icon = S:Icon(r, FEED_ICON)
	icon:SetPoint("LEFT", 0, 0)
	r.iconFrame = icon
	local text = S:Font(r, 12)
	text:SetPoint("LEFT", icon, "RIGHT", 5, 0)
	text:SetPoint("RIGHT", r, "RIGHT", 0, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	r.text = text
	self.feedRows[i] = r
	return r
end

local function entryText(e)
	local muted = hex(unpack(S.colors.muted))
	if e.kind == "money" then
		local s = moneyText(e.count)
		if e.total then s = s .. "  " .. muted .. "(" .. moneyText(e.total) .. ")|r" end
		return s
	end
	if e.kind == "warn" then return e.name end
	local s = hex(e.r, e.g, e.b) .. (e.name or "?") .. "|r"
	if e.count and e.count > 1 then s = s .. " x" .. e.count end
	if e.tag then s = s .. " " .. hex(unpack(S.colors.hint)) .. e.tag .. "|r" end
	if e.total and e.total > 0 then s = s .. "  " .. muted .. "(" .. e.total .. ")|r" end
	return s
end

function M:FeedRender()
	local f = self.feed
	local y = 0
	local shown = 0
	for i, e in ipairs(entries) do
		shown = i
		local r = self:FeedRow(i)
		local big = e.kind == "warn"
		local h = big and FEED_ROW + 4 or FEED_ROW
		S:ApplyFont(r.text, big and 15 or 12)
		if big then
			r.text:SetTextColor(unpack(S.colors.warn))
		else
			r.text:SetTextColor(unpack(S.colors.text))
		end
		r.text:SetText(entryText(e))
		r.iconFrame.icon:SetTexture(e.icon or 134400)
		if e.quality and e.quality >= 2 then
			r.iconFrame:SetBackdropBorderColor(e.r, e.g, e.b, 1)
		else
			r.iconFrame:SetBackdropBorderColor(0, 0, 0, 1)
		end
		r:SetHeight(h)
		r:SetAlpha(math.max(0, math.min(1, e.expire - GetTime())))
		r:ClearAllPoints()
		r:SetPoint("TOPLEFT", f, "TOPLEFT", 0, y)
		r:Show()
		e.row = r
		y = y - h - 1
	end
	for i = shown + 1, #self.feedRows do self.feedRows[i]:Hide() end
	f:SetHeight(math.max(FEED_ROW, num(opt("feedMax"), 6) * (FEED_ROW + 1)))
	if shown > 0 then f:Show() elseif not self.feedPreview then f:Hide() end
end

function M:FeedUpdate()
	if self.feedPreview then return end
	local now = GetTime()
	local removed = false
	for i = #entries, 1, -1 do
		local e = entries[i]
		local left = e.expire - now
		if left <= 0 then
			table.remove(entries, i)
			removed = true
		elseif e.row then
			e.row:SetAlpha(math.min(1, left))
		end
	end
	if removed then self:FeedRender() end
end

-- e = { kind, key, icon, name, r, g, b, quality, count, total, tag }
function M:FeedAdd(e)
	local now = GetTime()
	local dur = num(opt("feedDuration"), 6)
	if e.kind == "warn" then dur = dur + 3 end
	if self.feedPreview then self:EndFeedPreview() end
	if e.key then
		for i, old in ipairs(entries) do
			if old.key == e.key then
				old.count = (old.count or 0) + (e.count or 0)
				old.total = e.total or old.total
				old.expire = now + dur
				if old.row then old.row:SetAlpha(1) end
				table.remove(entries, i)
				table.insert(entries, 1, old)
				self:FeedRender()
				return old
			end
		end
	end
	e.expire = now + dur
	table.insert(entries, 1, e)
	local max = math.max(1, num(opt("feedMax"), 6))
	while #entries > max do table.remove(entries) end
	self:FeedRender()
	return e
end

-- The bag count is only right after the bag update: read it a moment later.
function M:FeedCountLater(e, itemID)
	C_Timer.After(0.5, function()
		guard(function()
			if not (C_Item and C_Item.GetItemCount) then return end
			local n = num(try(C_Item.GetItemCount, itemID), nil)
			if n and e.expire and e.expire > GetTime() then
				e.total = n
				self:FeedRender()
			end
		end)
	end)
end

function M:AddItem(link, count)
	local itemID, icon, classID
	local instant = (C_Item and C_Item.GetItemInfoInstant) or GetItemInfoInstant
	if instant then
		local ok, id, _, _, _, ic, cls = pcall(instant, link)
		if ok then itemID, icon, classID = num(id), Safe(ic, nil), num(cls) end
	end
	local quality
	if C_Item and C_Item.GetItemQualityByID then quality = num(try(C_Item.GetItemQualityByID, link)) end
	if not quality and GetItemInfo then quality = num(select(3, try(GetItemInfo, link))) end
	local name = link:match("|h%[(.-)%]|h") or link
	local r, g, b = qualityColor(quality)
	if not quality then
		-- colour straight from the link
		local hx = link:match("|c%x%x(%x%x%x%x%x%x)")
		if hx then
			r, g, b = tonumber(hx:sub(1, 2), 16) / 255, tonumber(hx:sub(3, 4), 16) / 255, tonumber(hx:sub(5, 6), 16) / 255
		end
	end
	local questClass = (Enum and Enum.ItemClass and Enum.ItemClass.Questitem) or 12
	local isQuest = classID == questClass
	if isQuest and not opt("questItems") then return end
	local e = self:FeedAdd({
		kind = "item", key = itemID and ("i" .. itemID) or link, icon = icon, name = name,
		r = r, g = g, b = b, quality = quality, count = count, tag = isQuest and L["Quest"] or nil,
	})
	if itemID then self:FeedCountLater(e, itemID) end
end

function M:OnLootMsg(msg)
	if not on("feed") or IsSecret(msg) or type(msg) ~= "string" then return end
	for _, p in ipairs(ITEM_PATTERNS) do
		local link, n = msg:match(p)
		if link then
			self:AddItem(link, tonumber(n) or 1)
			return
		end
	end
end

function M:OnMoneyMsg(msg)
	if not (on("feed") and opt("showMoney")) or IsSecret(msg) or type(msg) ~= "string" then return end
	for _, p in ipairs(MONEY_PATTERNS) do
		local m = msg:match(p)
		if m then
			local copper = parseMoney(m)
			if not copper then return end
			local total = GetMoney and num(try(GetMoney))
			self:FeedAdd({ kind = "money", key = "money", icon = 133784, count = copper, total = total })
			return
		end
	end
end

function M:OnCurrencyMsg(msg)
	if not on("feed") or IsSecret(msg) or type(msg) ~= "string" then return end
	for _, p in ipairs(CURRENCY_PATTERNS) do
		local link, n = msg:match(p)
		if link then
			local info = C_CurrencyInfo and C_CurrencyInfo.GetCurrencyInfoFromLink and try(C_CurrencyInfo.GetCurrencyInfoFromLink, link)
			local name = link:match("|h%[(.-)%]|h") or link
			local icon, quality, total
			if type(info) == "table" then
				name = str(info.name) or name
				icon = Safe(info.iconFileID, nil)
				quality = num(info.quality)
				total = num(info.quantity)
			end
			local id = link:match("currency:(%d+)")
			local r, g, b = qualityColor(quality)
			self:FeedAdd({
				kind = "currency", key = id and ("c" .. id) or link, icon = icon, name = name,
				r = r, g = g, b = b, quality = quality, count = tonumber(n) or 1, total = total,
			})
			return
		end
	end
end

function M:OnUIError(a, b)
	if not (opt("enabled") and opt("bagsFull")) then return end
	local full = ERR_INV_FULL or "Inventory is full."
	a, b = Safe(a, nil), Safe(b, nil)
	if a ~= full and b ~= full then return end
	local now = GetTime()
	if self.lastFull and now - self.lastFull < 4 then return end
	self.lastFull = now
	self:FeedAdd({ kind = "warn", key = "bagsfull", icon = 133639, name = L["Bags full!"], count = 0 })
end

---------------------------------------------------------------------------
-- Group loot rolls (own frames; RollOnLoot only from the user's click)
---------------------------------------------------------------------------
local ROLL_BUTTONS = {
	-- type, texture base / atlas, label
	{ ROLL_NEED, "Interface\\Buttons\\UI-GroupLoot-Dice", nil, NEED or "Need", "reasonNeed", "canNeed" },
	{ ROLL_GREED, "Interface\\Buttons\\UI-GroupLoot-Coin", nil, GREED or "Greed", "reasonGreed", "canGreed" },
	{ ROLL_TRANSMOG, nil, "lootroll-toast-icon-transmog", TRANSMOGRIFICATION or "Transmog", nil, "canTransmog" },
	{ ROLL_DE, "Interface\\Buttons\\UI-GroupLoot-DE", nil, ROLL_DISENCHANT or "Disenchant", "reasonDE", "canDE" },
	{ ROLL_PASS, "Interface\\Buttons\\UI-GroupLoot-Pass", nil, PASS or "Pass", nil, nil },
}

local function atlasExists(atlas)
	if C_Texture and C_Texture.GetAtlasInfo then return try(C_Texture.GetAtlasInfo, atlas) ~= nil end
	return false
end

local rolls = {} -- active roll frames in display order

function M:CreateRollAnchor()
	local a = CreateFrame("Frame", "CasterKitLootRoll", UIParent)
	a:SetSize(ROLL_W, ROLL_H)
	self.rollAnchor = a
	self.rollPool = {}
	S:RegisterMover(a, "lootroll", L["Loot rolls"], function(fr)
		fr:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 280)
	end)
end

function M:NewRollFrame()
	local f = CreateFrame("Frame", nil, self.rollAnchor, "BackdropTemplate")
	f:SetSize(ROLL_W, ROLL_H)
	f:SetFrameStrata("HIGH")
	S:Backdrop(f, 0.92)
	f:EnableMouse(true)

	local icon = S:Icon(f, ROLL_H - 4)
	icon:SetPoint("LEFT", 2, 0)
	icon:EnableMouse(true)
	icon:SetScript("OnEnter", function(ic) guard(M.RollTooltip, M, ic, f) end)
	icon:SetScript("OnLeave", function(ic) hideTooltip(ic) end)
	icon:SetScript("OnMouseUp", function() guard(M.RollModifiedClick, M, f) end)
	f.iconFrame = icon
	local count = S:Font(icon, 10)
	count:SetPoint("BOTTOMRIGHT", -1, 1)
	f.count = count

	-- buttons right to left
	f.buttons = {}
	local x = -4
	for i = #ROLL_BUTTONS, 1, -1 do
		local def = ROLL_BUTTONS[i]
		local b = CreateFrame("Button", nil, f)
		b:SetSize(22, 22)
		b.def = def
		local okAtlas = def[3] and atlasExists(def[3] .. "-up")
		if okAtlas then
			b:SetNormalAtlas(def[3] .. "-up")
			if atlasExists(def[3] .. "-down") then b:SetPushedAtlas(def[3] .. "-down") end
			if atlasExists(def[3] .. "-highlight") then b:SetHighlightAtlas(def[3] .. "-highlight") end
		elseif def[2] then
			b:SetNormalTexture(def[2] .. "-Up")
			b:SetPushedTexture(def[2] .. "-Down")
			b:SetHighlightTexture(def[2] .. "-Highlight", "ADD")
		else
			-- no art for this button in this client: plain letter
			local t = S:Font(b, 13)
			t:SetPoint("CENTER")
			t:SetText(def[4]:sub(1, 1))
			t:SetTextColor(unpack(S.colors.proc))
			b.letter = t
		end
		b:SetScript("OnClick", function(btn) guard(M.DoRoll, M, f, btn.def[1]) end)
		b:SetScript("OnEnter", function(btn) guard(M.RollButtonTooltip, M, btn, f) end)
		b:SetScript("OnLeave", function(btn) hideTooltip(btn) end)
		b:SetMotionScriptsWhileDisabled(true)
		f.buttons[i] = b
		b.xRight = x
		x = x - 24
	end

	local name = S:Font(f, 12)
	name:SetPoint("TOPLEFT", icon, "TOPRIGHT", 6, -2)
	name:SetJustifyH("LEFT")
	name:SetWordWrap(false)
	f.name = name
	local bind = S:Font(f, 10)
	bind:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 7)
	bind:SetTextColor(unpack(S.colors.hint))
	f.bind = bind

	local bar = S:StatusBar(f, S.colors.accent)
	bar:SetHeight(3)
	bar:SetPoint("BOTTOMLEFT", icon, "BOTTOMRIGHT", 6, 1)
	bar:SetPoint("BOTTOMRIGHT", f, "BOTTOMRIGHT", -4, 3)
	bar:SetMinMaxValues(0, 1)
	f.bar = bar

	f:SetScript("OnUpdate", function(frame, elapsed)
		frame.tick = (frame.tick or 0) + elapsed
		if frame.tick < 0.1 then return end
		frame.tick = 0
		local ok = pcall(M.RollTick, M, frame)
		if not ok then M:HideRoll(frame) end
	end)
	return f
end

function M:RollFrame()
	local f = table.remove(self.rollPool)
	return f or self:NewRollFrame()
end

function M:LayoutRolls()
	for i, f in ipairs(rolls) do
		f:ClearAllPoints()
		f:SetPoint("BOTTOM", self.rollAnchor, "BOTTOM", 0, (i - 1) * (ROLL_H + ROLL_GAP))
	end
end

-- Reads roll info into frame f; false when the roll is unknown.
function M:ReadRoll(f, rollID)
	if not GetLootRollItemInfo then return false end
	local ok, tex, name, count, quality, bop, canNeed, canGreed, canDE, rNeed, rGreed, rDE, _, canTransmog =
		pcall(GetLootRollItemInfo, rollID)
	if not ok or (not IsSecret(tex) and tex == nil) then return false end
	f.tex, f.itemName = tex, name
	f.itemCount = num(count, 1)
	f.quality = num(quality)
	f.bop = flag(bop)
	f.canNeed, f.canGreed, f.canDE, f.canTransmog = flag(canNeed), flag(canGreed), flag(canDE), flag(canTransmog)
	f.reasonNeed, f.reasonGreed, f.reasonDE = num(rNeed), num(rGreed), num(rDE)
	return true
end

function M:FillRoll(f)
	f.iconFrame.icon:SetTexture(f.tex)
	f.iconFrame:SetBackdropBorderColor(qualityColor(f.quality))
	f.count:SetText(f.itemCount > 1 and f.itemCount or "")
	f.name:SetText(f.itemName or "?")
	f.name:SetTextColor(qualityColor(f.quality))
	f.bind:SetText(f.bop and (ITEM_BIND_ON_PICKUP or "Binds when picked up") or "")
	f.rolled = nil
	f:SetAlpha(1)
	-- which buttons: transmog replaces greed when greed is not possible
	local x = -4
	for i = #ROLL_BUTTONS, 1, -1 do
		local b = f.buttons[i]
		local def = b.def
		local show = true
		if def[1] == ROLL_TRANSMOG then show = f.canTransmog end
		if def[1] == ROLL_GREED then show = not f.canTransmog or f.canGreed end
		if def[1] == ROLL_DE then show = f.canDE end
		b:SetShown(show)
		if show then
			b:ClearAllPoints()
			b:SetPoint("RIGHT", f, "RIGHT", x, 1)
			x = x - 24
			local can = def[6] == nil or f[def[6]]
			b:SetEnabled(can and true or false)
			local nt = b:GetNormalTexture()
			if nt then nt:SetDesaturated(not can) end
			b:SetAlpha(can and 1 or 0.4)
		end
	end
	f.name:SetPoint("RIGHT", f, "RIGHT", x - 2, 0)
end

function M:StartRoll(rollID, rollTime)
	rollID = num(rollID)
	if not rollID then return end
	for _, f in ipairs(rolls) do
		if f.rollID == rollID then return end
	end
	self:EndRollPreview()
	local f = self:RollFrame()
	if not self:ReadRoll(f, rollID) then
		table.insert(self.rollPool, f)
		return
	end
	f.rollID = rollID
	local ms = num(rollTime)
	if not ms or ms <= 0 then ms = num(GetLootRollTimeLeft and try(GetLootRollTimeLeft, rollID), 60000) end
	f.rollTime = math.max(1, ms)
	f.started = GetTime()
	f.bar:SetMinMaxValues(0, f.rollTime)
	f.bar:SetValue(f.rollTime)
	self:FillRoll(f)
	table.insert(rolls, f)
	self:LayoutRolls()
	f:Show()
end

function M:HideRoll(f)
	for i, r in ipairs(rolls) do
		if r == f then
			table.remove(rolls, i)
			break
		end
	end
	hideTooltip(f.iconFrame)
	f:Hide()
	f.rollID = nil
	table.insert(self.rollPool, f)
	self:LayoutRolls()
end

function M:CancelRoll(rollID)
	rollID = num(rollID)
	if not rollID then return end
	for _, f in ipairs(rolls) do
		if f.rollID == rollID then
			self:HideRoll(f)
			return
		end
	end
end

function M:RollTick(f)
	if not f.rollID then return end
	local left = num(GetLootRollTimeLeft and try(GetLootRollTimeLeft, f.rollID))
	if left then
		f.bar:SetValue(math.max(0, left))
		if left <= 0 and GetTime() - f.started > 2 then self:HideRoll(f) end
	else
		f.bar:SetValue(math.max(0, f.rollTime - (GetTime() - f.started) * 1000))
	end
end

-- The user's click on Need/Greed/...: one RollOnLoot, Blizzard confirms BoP itself.
function M:DoRoll(f, rollType)
	if not f.rollID or not RollOnLoot then return end
	RollOnLoot(f.rollID, rollType)
	if f.bop and rollType ~= ROLL_PASS then
		-- Blizzard asks for confirmation; stay visible (dimmed) so a cancel can be undone
		f.rolled = rollType
		f:SetAlpha(0.6)
	else
		self:HideRoll(f)
	end
end

function M:RollTooltip(owner, f)
	if not (GameTooltip and f.rollID) then return end
	GameTooltip:SetOwner(owner, "ANCHOR_RIGHT")
	if GameTooltip.SetLootRollItem then
		GameTooltip:SetLootRollItem(f.rollID)
	end
	GameTooltip:Show()
	if CursorUpdate then CursorUpdate(owner) end
end

function M:RollModifiedClick(f)
	if not (f.rollID and IsModifiedClick and IsModifiedClick() and HandleModifiedItemClick and GetLootRollItemLink) then return end
	local link = try(GetLootRollItemLink, f.rollID)
	if link and not IsSecret(link) then HandleModifiedItemClick(link) end
end

function M:RollButtonTooltip(btn, f)
	if not GameTooltip then return end
	local def = btn.def
	GameTooltip:SetOwner(btn, "ANCHOR_RIGHT")
	GameTooltip:SetText(def[4], 1, 1, 1)
	if not btn:IsEnabled() and def[5] then
		local reason = f[def[5]]
		local why = reason and _G["LOOT_ROLL_INELIGIBLE_REASON" .. reason]
		if type(why) == "string" then GameTooltip:AddLine(why, 1, 0.3, 0.3, true) end
	end
	GameTooltip:Show()
end

-- Take START_LOOT_ROLL from UIParent while our roll frames are on.
function M:SyncBlizzardRolls()
	CK:OutOfCombat("loot-rolls", function()
		guard(function()
			if not (UIParent and UIParent.IsEventRegistered) then return end
			local want = on("rollFrames")
			if want and not self.tookRoll then
				if UIParent:IsEventRegistered("START_LOOT_ROLL") then
					UIParent:UnregisterEvent("START_LOOT_ROLL")
					self.tookRoll = true
					self:PickUpActiveRolls()
				elseif CK.debug then
					CK:Print("loot: UIParent does not own START_LOOT_ROLL, using Blizzard's roll frames")
				end
			elseif not want and self.tookRoll then
				-- rolls already on screen stay ours until they end; new ones go to Blizzard
				UIParent:RegisterEvent("START_LOOT_ROLL")
				self.tookRoll = false
			end
		end)
	end)
end

-- Rolls that started before we took over (e.g. after /reload).
function M:PickUpActiveRolls()
	if not GetActiveLootRollIDs then return end
	local ok, ids = pcall(GetActiveLootRollIDs)
	if not ok or type(ids) ~= "table" then return end
	for _, id in ipairs(ids) do
		local left = num(GetLootRollTimeLeft and try(GetLootRollTimeLeft, id))
		self:StartRoll(id, left)
	end
end

---------------------------------------------------------------------------
-- Previews while the frames are unlocked (so they can be dragged)
---------------------------------------------------------------------------
function M:EndFeedPreview()
	if not self.feedPreview then return end
	self.feedPreview = false
	wipe(entries)
	self:FeedRender()
end

function M:EndRollPreview()
	local p = self.rollPreviewFrame
	if p then
		self.rollPreviewFrame = nil
		self:HideRoll(p)
	end
end

function M:UpdatePreview()
	local show = unlocked()
	-- loot window (only useful at a fixed spot)
	local w = self.window
	if show and self:WindowActive() and not opt("atCursor") and not self.lootOpen then
		self.preview = true
		self:RenderWindow()
		S:ApplyPoint(w, "loot")
		w:Show()
	elseif self.preview then
		w:Hide()
	end
	-- feed
	if show and (on("feed") or on("bagsFull")) then
		if not self.feedPreview and #entries == 0 then
			self.feedPreview = true
			local far = GetTime() + 1e6
			local r, g, b = qualityColor(3)
			entries[1] = { kind = "item", icon = 135145, name = "Sample Staff", r = r, g = g, b = b, quality = 3, count = 1, total = 1, expire = far }
			entries[2] = { kind = "money", icon = 133784, count = 1234, expire = far }
			self:FeedRender()
			for _, e in ipairs(entries) do if e.row then e.row:SetAlpha(1) end end
		end
	else
		self:EndFeedPreview()
	end
	-- rolls
	if show and on("rollFrames") then
		if not self.rollPreviewFrame and #rolls == 0 then
			local f = self:RollFrame()
			f.tex, f.itemName, f.itemCount, f.quality, f.bop = 135145, "Sample Staff", 1, 3, true
			f.canNeed, f.canGreed, f.canDE, f.canTransmog = true, true, false, false
			f.rollID, f.rollTime, f.started = nil, 60000, GetTime()
			self:FillRoll(f)
			f.bar:SetMinMaxValues(0, 1)
			f.bar:SetValue(0.6)
			table.insert(rolls, f)
			self:LayoutRolls()
			f:Show()
			self.rollPreviewFrame = f
		end
	else
		self:EndRollPreview()
	end
end

---------------------------------------------------------------------------
-- Auto loot: Blizzard's own CVar, changed only when the user changes our setting
---------------------------------------------------------------------------
local function autoLootCVar()
	if C_CVar and C_CVar.GetCVarBool then return try(C_CVar.GetCVarBool, "autoLootDefault") and true or false end
	if GetCVarBool then return try(GetCVarBool, "autoLootDefault") and true or false end
end

function M:ReadAutoLoot()
	local v = autoLootCVar()
	if v == nil then return end
	self.autoApplied = v
	if type(CK.char.loot) == "table" then CK.char.loot.autoLoot = v end
end

function M:ApplyAutoLoot()
	local want = opt("autoLoot") and true or false
	if self.autoApplied == nil then
		-- CVar could not be read: only record, never overwrite the user's Blizzard setting blindly
		self.autoApplied = want
		return
	end
	if want == self.autoApplied then return end
	CK:OutOfCombat("loot-autoloot", function()
		guard(function()
			local value = (opt("autoLoot") and true or false)
			if C_CVar and C_CVar.SetCVar then
				C_CVar.SetCVar("autoLootDefault", value and "1" or "0")
			elseif SetCVar then
				SetCVar("autoLootDefault", value and "1" or "0")
			end
			self.autoApplied = value
		end)
	end)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
function M:Refresh()
	self:SyncBlizzardLoot()
	self:SyncBlizzardRolls()
	self:ApplyAutoLoot()
	if not self:WindowActive() and self.window:IsShown() and not self.preview then
		-- our window was turned off while looting: close it (Blizzard takes the next one)
		self.window:Hide()
	end
	if not (on("feed") or on("bagsFull")) then
		wipe(entries)
		self:FeedRender()
	end
	self:UpdatePreview()
end

function M:OnEnable()
	self:CreateWindow()
	self:CreateFeed()
	self:CreateRollAnchor()
	guard(M.ReadAutoLoot, M)

	CK:On("LOOT_OPENED", function(_, autoLoot) guard(M.OnLootOpened, M, autoLoot) end)
	CK:On("LOOT_READY", function() guard(M.OnLootChanged, M) end)
	CK:On("LOOT_SLOT_CLEARED", function() guard(M.OnLootChanged, M) end)
	CK:On("LOOT_SLOT_CHANGED", function() guard(M.OnLootChanged, M) end)
	CK:On("LOOT_CLOSED", function() guard(M.OnLootClosed, M) end)
	-- LOOT_BIND_CONFIRM: Blizzard's StaticPopup (LOOT_BIND) handles it, we stay out.

	CK:On("CHAT_MSG_LOOT", function(_, msg) guard(M.OnLootMsg, M, msg) end)
	CK:On("CHAT_MSG_MONEY", function(_, msg) guard(M.OnMoneyMsg, M, msg) end)
	CK:On("CHAT_MSG_CURRENCY", function(_, msg) guard(M.OnCurrencyMsg, M, msg) end)
	CK:On("UI_ERROR_MESSAGE", function(_, a, b) guard(M.OnUIError, M, a, b) end)

	CK:On("START_LOOT_ROLL", function(_, rollID, rollTime)
		if M.tookRoll then guard(M.StartRoll, M, rollID, rollTime) end
	end)
	CK:On("CANCEL_LOOT_ROLL", function(_, rollID) guard(M.CancelRoll, M, rollID) end)

	local function sync() guard(M.SyncBlizzardLoot, M) end
	for _, ev in ipairs({ "PARTY_LOOT_METHOD_CHANGED", "GROUP_ROSTER_UPDATE", "PLAYER_ENTERING_WORLD" }) do
		guard(CK.On, CK, ev, sync)
	end
	guard(CK.On, CK, "CVAR_UPDATE", function(_, name)
		name = Safe(name, nil)
		if type(name) == "string" and name:lower() == "autolootdefault" then guard(M.ReadAutoLoot, M) end
	end)

	CK:Listen("SETTINGS", function(group)
		if group == "loot" then
			guard(M.Refresh, M)
		elseif group == "bars" then
			guard(M.UpdatePreview, M)
		end
	end)
	CK:On("PLAYER_REGEN_DISABLED", function() guard(M.UpdatePreview, M) end)
	CK:On("PLAYER_REGEN_ENABLED", function() guard(M.UpdatePreview, M) end)

	guard(M.Refresh, M)
end
