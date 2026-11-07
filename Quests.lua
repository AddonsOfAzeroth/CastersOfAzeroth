-- CasterKit by DinX: quest tracker
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local Safe = CK.Safe

local Q = CK:NewModule("Quests")

local QL = C_QuestLog
local PAD, INDENT, GAP, BAR = 6, 10, 2, 3
local GREEN = { 0.30, 0.90, 0.30 }
local RED = { 1.00, 0.25, 0.25 }
local ORANGE = { 1.00, 0.55, 0.25 }

-- Sort modes in click order, with their label keys
local MODES = { "smart", "distance", "xp", "xpmin", "level", "progress", "zone" }
local MODE_NAMES = {
	smart = "Smart route", distance = "Distance", xp = "XP reward", xpmin = "XP per minute",
	level = "Level", progress = "Almost done", zone = "Zone",
}

-- Skip suggestions from the plan: tag text and tooltip (label keys)
local SKIP = {
	grey = { "Skip?", "Gives little XP at your level." },
	elite = { "Skip?", "Group or elite quest: hard solo." },
	far = { "Skip?", "Far away or on another continent." },
	red = { "Later", "Much higher level: come back later." },
}


---------------------------------------------------------------------------
-- Small safe helpers: values that are secret or of the wrong type become default
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

-- pcall wrapper that returns up to three results, or nil on error
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

local function setFont(fs, size)
	if fs.ckSize ~= size then
		fs:SetFont(S.font, size, "OUTLINE")
		fs.ckSize = size
	end
end

---------------------------------------------------------------------------
-- Quest log reading (C_QuestLog first, classic functions as fallback)
---------------------------------------------------------------------------
local function logCounts()
	local entries, quests
	if QL and QL.GetNumQuestLogEntries then
		entries, quests = try(QL.GetNumQuestLogEntries)
	elseif GetNumQuestLogEntries then
		entries, quests = try(GetNumQuestLogEntries)
	end
	return num(entries, 0), num(quests, 0)
end

-- Returns a plain table for log line i, or nil.
local entry = {}
local function readEntry(i)
	wipe(entry)
	if QL and QL.GetInfo then
		local info = try(QL.GetInfo, i)
		if type(info) ~= "table" then return end
		entry.title = str(info.title)
		entry.level = num(info.difficultyLevel, 0) > 0 and num(info.difficultyLevel, 0) or num(info.level, 0)
		entry.showLevel = num(info.level, 0)
		entry.isHeader = flag(info.isHeader)
		entry.questID = num(info.questID)
		entry.skip = flag(info.isHidden) or flag(info.isBounty)
		entry.onMap = flag(info.isOnMap)
		entry.group = num(info.suggestedGroup, 0)
		return entry
	elseif GetQuestLogTitle then
		local title, level, tag, isHeader, _, isComplete, _, questID = try(GetQuestLogTitle, i)
		entry.title = str(title)
		entry.level = num(level, 0)
		entry.showLevel = entry.level
		entry.isHeader = flag(isHeader)
		entry.questID = num(questID)
		entry.tag = str(tag)
		entry.classicComplete = num(isComplete)
		return entry
	end
end

local function isWatched(questID, index)
	if QL and QL.GetQuestWatchType then
		local ok, w = pcall(QL.GetQuestWatchType, questID)
		if ok then return Safe(w, nil) ~= nil end
	end
	if IsQuestWatched then
		return flag(try(IsQuestWatched, index))
	end
	return false
end

-- Tag text such as "Dungeon", and whether the quest is elite.
local function questTag(questID, classicTag)
	local name, elite
	if QL and QL.GetQuestTagInfo then
		local info = try(QL.GetQuestTagInfo, questID)
		if type(info) == "table" then
			name = str(info.tagName)
			elite = flag(info.isElite)
		end
	elseif GetQuestTagInfo then
		local _, tagName = try(GetQuestTagInfo, questID)
		name = str(tagName)
	end
	name = name or classicTag
	if name and (name == ELITE or name == "Elite") then
		name, elite = nil, true
	end
	return name, elite
end

-- "Red Leather Bandana: 4/15" (classic) becomes "4/15 Red Leather Bandana".
local function objectiveText(text, have, need)
	if not text then return "", have, need end
	local name, a, b = text:match("^(.-):%s*(%d+)%s*/%s*(%d+)$")
	if name and name ~= "" then
		return a .. "/" .. b .. " " .. name, have or tonumber(a), need or tonumber(b)
	end
	local a2, b2 = text:match("^(%d+)%s*/%s*(%d+)")
	if a2 then return text, have or tonumber(a2), need or tonumber(b2) end
	return text, have, need
end

local function addObjective(q, text, done, have, need, pct)
	local shown
	shown, have, need = objectiveText(text, have, need)
	q.numObj = q.numObj + 1
	local o = q.objectives[q.numObj] or {}
	q.objectives[q.numObj] = o
	o.text, o.done, o.have, o.need, o.pct = shown, done, have, need, pct
end

local function readObjectives(q)
	q.numObj = 0
	if QL and QL.GetQuestObjectives then
		local list = try(QL.GetQuestObjectives, q.id)
		if type(list) ~= "table" then return end
		for _, o in ipairs(list) do
			if type(o) == "table" then
				local pct
				if Safe(o.type, nil) == "progressbar" and GetQuestProgressBarPercent then
					pct = num(try(GetQuestProgressBarPercent, q.id))
				end
				addObjective(q, str(o.text), flag(o.finished), num(o.numFulfilled), num(o.numRequired), pct)
			end
		end
	elseif GetNumQuestLeaderBoards and GetQuestLogLeaderBoard then
		for j = 1, num(try(GetNumQuestLeaderBoards, q.index), 0) do
			local text, _, finished = try(GetQuestLogLeaderBoard, j, q.index)
			addObjective(q, str(text), flag(finished))
		end
	end
end

local function questState(q, classicComplete)
	local complete, failed
	if QL and QL.IsComplete then complete = flag(try(QL.IsComplete, q.id)) end
	if not complete and QL and QL.ReadyForTurnIn then complete = flag(try(QL.ReadyForTurnIn, q.id)) end
	if QL and QL.IsFailed then failed = flag(try(QL.IsFailed, q.id)) end
	if classicComplete == 1 then complete = true end
	if classicComplete == -1 then failed = true end
	return complete and not failed, failed
end

local function currentZones()
	local z = str(GetZoneText and try(GetZoneText))
	local m = C_Map and C_Map.GetBestMapForUnit and num(try(C_Map.GetBestMapForUnit, "player"))
	local info = m and C_Map.GetMapInfo and try(C_Map.GetMapInfo, m)
	return z, type(info) == "table" and str(info.name) or nil
end

---------------------------------------------------------------------------
-- Collect and sort
---------------------------------------------------------------------------
local list, spare = {}, {}

local function sorter(a, b)
	if a.complete ~= b.complete then return a.complete end
	if a.zone ~= b.zone then return a.zone end
	if a.level ~= b.level then return a.level < b.level end
	if a.title ~= b.title then return a.title < b.title end
	return a.id < b.id
end

-- Route plan (QuestPlan.lua): every call is guarded, nil means "use the built-in sort"
local function planList(mode)
	local QP = CK.QuestPlan
	if not (QP and QP.Get) then return end
	Q.inPlan = true
	local ok, res = pcall(QP.Get, QP, mode)
	Q.inPlan = false
	if ok and type(res) == "table" then return res end
end

local function nextStop()
	local QP = CK.QuestPlan
	if not (QP and QP.NextStop) then return end
	Q.inPlan = true
	local ok, res = pcall(QP.NextStop, QP)
	Q.inPlan = false
	if ok and type(res) == "table" then return res end
end

-- Plan order first; quests the plan does not know follow in the built-in order.
local function planSorter(a, b)
	local pa, pb = a.planPos, b.planPos
	if pa and pb then return pa < pb end
	if pa or pb then return pa ~= nil end
	return sorter(a, b)
end

-- Links each quest in `list` to its plan entry; returns true when a plan was used.
local planIndex = {}
local function applyPlan(mode)
	local plan = planList(mode)
	if not plan then return false end
	wipe(planIndex)
	for pos, e in ipairs(plan) do
		local id = type(e) == "table" and num(e.questID) or nil
		if id and not planIndex[id] then planIndex[id] = pos end
	end
	for _, q in ipairs(list) do
		local pos = planIndex[q.id]
		q.planPos, q.plan = pos, pos and plan[pos] or nil
	end
	return true
end

-- Fills `list`; returns number of quests in the log and how many are tracked.
function Q:Collect()
	for i = #list, 1, -1 do
		spare[#spare + 1] = list[i]
		list[i] = nil
	end
	local cfg = CK.char.quests
	local entries, total = logCounts()
	local zone1, zone2 = currentZones()
	local header
	local anyWatched = false
	local playerLevel = num(UnitLevel("player"), 1)

	for i = 1, entries do
		local e = readEntry(i)
		if e then
			if e.isHeader then
				header = e.title
			elseif e.questID and e.title and not e.skip then
				local q = table.remove(spare) or { objectives = {} }
				q.id, q.index, q.title = e.questID, i, e.title
				q.level = e.level > 0 and e.level or playerLevel
				q.showLevel = e.showLevel > 0 and e.showLevel or q.level
				q.watched = isWatched(e.questID, i)
				q.complete, q.failed = questState(q, e.classicComplete)
				q.tag, q.elite = questTag(e.questID, e.tag)
				if not q.tag and (e.group or 0) > 1 then q.tag = L["Group"] .. " " .. e.group end
				q.zone = cfg.zoneFirst and ((header ~= nil and (header == zone1 or header == zone2)) or e.onMap) or false
				q.zone = q.zone and true or false
				readObjectives(q)
				if q.watched then anyWatched = true end
				list[#list + 1] = q
			end
		end
	end

	-- Watched quests only, when the player watches any
	if anyWatched then
		for i = #list, 1, -1 do
			if not list[i].watched then
				spare[#spare + 1] = table.remove(list, i)
			end
		end
	end
	for _, q in ipairs(list) do q.planPos, q.plan = nil, nil end
	self.usingPlan = applyPlan(cfg.sortMode or "smart")
	table.sort(list, self.usingPlan and planSorter or sorter)
	if total < #list then total = #list end
	return total, #list
end

---------------------------------------------------------------------------
-- Actions on a quest title
---------------------------------------------------------------------------
local function openQuest(questID, index)
	if InCombatLockdown() then return end
	if QuestMapFrame_OpenToQuestDetails then
		try(QuestMapFrame_OpenToQuestDetails, questID)
	elseif QuestLog_OpenToQuest and index then
		try(QuestLog_OpenToQuest, index)
	else
		if index and SelectQuestLogEntry then try(SelectQuestLogEntry, index) end
		if ShowQuestLog then try(ShowQuestLog)
		elseif OpenQuestLog then try(OpenQuestLog, questID)
		elseif ToggleQuestLog then try(ToggleQuestLog) end
	end
end

-- Position of a quest from Blizzard's map data.
local function questPosition(questID)
	if QL and QL.GetNextWaypoint then
		local m, x, y = try(QL.GetNextWaypoint, questID)
		m, x, y = num(m), num(x), num(y)
		if m and m > 0 and x and y then return m, x, y end
	end
	if not (QL and QL.GetQuestsOnMap) then return end
	local playerMap = C_Map and C_Map.GetBestMapForUnit and num(try(C_Map.GetBestMapForUnit, "player"))
	local questMap = GetQuestUiMapID and num(try(GetQuestUiMapID, questID, true))
	for _, mapID in ipairs({ playerMap or 0, questMap or 0 }) do
		if mapID > 0 then
			local pins = try(QL.GetQuestsOnMap, mapID)
			if type(pins) == "table" then
				for _, info in ipairs(pins) do
					if num(info.questID) == questID and num(info.x) and num(info.y) then
						return mapID, info.x, info.y
					end
				end
			end
		end
	end
end

-- Right-click: point the CasterKit arrow at this quest (stays until arrival or cleared).
local function setWaypoint(questID, title)
	local A = CK.Arrow
	if not (A and A.SetTarget) then return end
	local m, x, y = questPosition(questID)
	if m then
		local ok = pcall(A.SetTarget, A, m, x, y, title)
		if ok then
			Q.manualArrow = true
			Q.arrowKey = nil
		end
	end
end

-- Keep the CasterKit arrow on the plan's next stop (display only).
function Q:UpdateArrow()
	local A = CK.Arrow
	if not (A and A.SetTarget and A.Clear) then return end
	-- a target the player picked with right-click wins until reached or cleared
	if self.manualArrow then
		local m = A.GetTarget and try(A.GetTarget, A)
		if m then return end
		self.manualArrow = false
	end
	local cfg = CK.char.quests
	local stop = cfg.enabled and cfg.arrow and nextStop()
	local m, x, y = stop and num(stop.mapID), stop and num(stop.x), stop and num(stop.y)
	if not (m and x and y) then
		if self.arrowKey then
			pcall(A.Clear, A)
			self.arrowKey = nil
		end
		return
	end
	local key = string.format("%d:%.4f:%.4f", m, x, y)
	if key == self.arrowKey then return end
	local title
	local ids = stop.questIDs
	local first = type(ids) == "table" and num(ids[1]) or nil
	if first then
		for _, q in ipairs(list) do
			if q.id == first then title = q.title break end
		end
		if not title and QL and QL.GetTitleForQuestID then title = str(try(QL.GetTitleForQuestID, first)) end
		if title and #ids > 1 then title = title .. " (+" .. (#ids - 1) .. ")" end
	end
	if pcall(A.SetTarget, A, m, x, y, title or L["Next stop"]) then
		self.arrowKey = key
	end
end

---------------------------------------------------------------------------
-- Frames (pooled: created once, re-used on every redraw)
---------------------------------------------------------------------------
local titles, lines = {}, {}

local function onTitleClick(self, button)
	guard(function()
		local id = self.questID
		if not id then return end
		if button == "RightButton" then
			setWaypoint(id, self.questTitle)
		elseif IsShiftKeyDown() then
			openQuest(id, self.logIndex)
		else
			local c = CK.char.quests.collapsed
			c[id] = not c[id] or nil
			Q:Redraw()
		end
	end)
end

-- Tooltip on a skip suggestion
local function onTitleEnter(self)
	guard(function()
		local s = self.skip and SKIP[self.skip]
		if not (s and GameTooltip) then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:SetText(L[s[1]], 1, 0.82, 0)
		GameTooltip:AddLine(L[s[2]], 1, 1, 1, true)
		GameTooltip:Show()
	end)
end

local function onTitleLeave(self)
	guard(function()
		if GameTooltip and GameTooltip:IsOwned(self) then GameTooltip:Hide() end
	end)
end

function Q:TitleRow(i)
	local t = titles[i]
	if t then return t end
	t = CreateFrame("Button", nil, self.panel)
	t:RegisterForClicks("LeftButtonUp", "RightButtonUp")
	t:SetScript("OnClick", onTitleClick)
	local hl = t:CreateTexture(nil, "HIGHLIGHT")
	hl:SetAllPoints()
	hl:SetColorTexture(1, 1, 1, 0.06)
	t:SetScript("OnEnter", onTitleEnter)
	t:SetScript("OnLeave", onTitleLeave)
	t.tag = S:Font(t, 10)
	t.tag:SetPoint("RIGHT", -12, 0)
	t.text = S:Font(t, 12)
	t.text:SetPoint("LEFT", 0, 0)
	t.text:SetPoint("RIGHT", t.tag, "LEFT", -3, 0)
	t.text:SetJustifyH("LEFT")
	t.text:SetWordWrap(false)
	t.mark = S:Font(t, 12)
	t.mark:SetPoint("RIGHT", 0, 0)
	t.mark:SetTextColor(unpack(S.colors.muted))
	titles[i] = t
	return t
end

function Q:LineRow(i)
	local o = lines[i]
	if o then return o end
	o = CreateFrame("Frame", nil, self.panel)
	o.text = S:Font(o, 12)
	o.text:SetPoint("TOPLEFT", 0, 0)
	o.text:SetJustifyH("LEFT")
	o.bar = S:StatusBar(o, S.colors.accent)
	o.bar:SetHeight(BAR)
	o.bar:SetPoint("TOPLEFT", o.text, "BOTTOMLEFT", 0, -1)
	o.bar:SetPoint("RIGHT", o, "RIGHT", 0, 0)
	lines[i] = o
	return o
end

function Q:CreatePanel()
	local p = CreateFrame("Frame", "CasterKitQuests", UIParent, "BackdropTemplate")
	p:SetFrameStrata("LOW")
	p:SetSize(CK.char.quests.width or 260, 40)
	S:Backdrop(p)
	self.panel = p

	local h = CreateFrame("Button", nil, p)
	h:RegisterForClicks("LeftButtonUp")
	h:SetPoint("TOPLEFT", PAD, -PAD)
	h:SetPoint("TOPRIGHT", -PAD, -PAD)
	h:SetScript("OnClick", function()
		guard(function()
			local cfg = CK.char.quests
			cfg.allCollapsed = not cfg.allCollapsed or nil
			Q:Redraw()
		end)
	end)
	h.text = S:Font(h, 12)
	h.text:SetPoint("LEFT", 0, 0)
	h.text:SetTextColor(unpack(S.colors.accent))
	h.mark = S:Font(h, 12)
	h.mark:SetPoint("RIGHT", 0, 0)
	h.mark:SetTextColor(unpack(S.colors.muted))
	self.header = h

	-- Sort mode label in the header: left-click cycles the mode
	local m = CreateFrame("Button", nil, h)
	m:RegisterForClicks("LeftButtonUp")
	m:SetPoint("LEFT", h.text, "RIGHT", 4, 0)
	local mhl = m:CreateTexture(nil, "HIGHLIGHT")
	mhl:SetAllPoints()
	mhl:SetColorTexture(1, 1, 1, 0.06)
	m.text = S:Font(m, 10)
	m.text:SetPoint("LEFT", 0, 0)
	m.text:SetTextColor(unpack(S.colors.muted))
	m:SetScript("OnClick", function()
		guard(function()
			local cfg = CK.char.quests
			local cur = 1
			for i, mode in ipairs(MODES) do
				if mode == cfg.sortMode then cur = i end
			end
			cfg.sortMode = MODES[cur % #MODES + 1]
			CK:Fire("SETTINGS", "quests")
		end)
	end)
	m:SetScript("OnEnter", function(btn)
		guard(function()
			if not GameTooltip then return end
			GameTooltip:SetOwner(btn, "ANCHOR_LEFT")
			GameTooltip:SetText(L["Sort by"], 1, 0.82, 0)
			GameTooltip:AddLine(L["Click to change the sort order."], 1, 1, 1, true)
			GameTooltip:Show()
		end)
	end)
	m:SetScript("OnLeave", function(btn)
		guard(function()
			if GameTooltip and GameTooltip:IsOwned(btn) then GameTooltip:Hide() end
		end)
	end)
	self.modeButton = m

	-- Accent bar left of the next stop
	local bar = p:CreateTexture(nil, "ARTWORK")
	local a = S.colors.accent
	bar:SetColorTexture(a[1], a[2], a[3], 0.7)
	bar:SetWidth(2)
	bar:Hide()
	self.nextBar = bar

	S:RegisterMover(p, "quests", L["Quests"], function(f)
		-- under the minimap
		f:SetPoint("TOPRIGHT", UIParent, "TOPRIGHT", -10, -230)
	end)
end

local function titleString(q)
	local lvl = "[" .. q.showLevel .. (q.elite and "+" or "") .. "] "
	local s = lvl .. q.title
	if q.tag then s = s .. " (" .. q.tag .. ")" end
	return s
end

local function levelColor(level)
	local fn = GetQuestDifficultyColor or GetCreatureDifficultyColor
	local c = fn and try(fn, level)
	if type(c) == "table" and c.r then return c.r, c.g, c.b end
	return 1, 0.82, 0
end

local function hex(c)
	return string.format("%02x%02x%02x", c[1] * 255, c[2] * 255, c[3] * 255)
end

-- 12345 -> "12,345" (separator from the locale)
local function groupDigits(n)
	local s = tostring(math.floor(n + 0.5))
	local sign, digits = s:match("^(-?)(%d+)$")
	if not digits then return s end
	local sep = L["thousands"]
	local out = digits:reverse():gsub("(%d%d%d)", "%1" .. sep):reverse()
	if out:sub(1, #sep) == sep then out = out:sub(#sep + 1) end
	return sign .. out
end

-- 4200 -> "4.2k", 950 -> "950"
local function shortNum(n)
	local suffix, v = "", n
	if n >= 999950 then
		suffix, v = "M", n / 1000000
	elseif n >= 100000 then
		return groupDigits(n / 1000) .. "k"
	elseif n >= 1000 then
		suffix, v = "k", n / 1000
	else
		return groupDigits(n)
	end
	local s = string.format("%.1f", v):gsub("%.0$", "")
	s = s:gsub("%.", L["decimal"])
	return s .. suffix
end

-- "~6 min · 4.2k XP/h · 120 yd" from a plan entry; nil when nothing is known
local parts = {}
local function estimateString(e)
	wipe(parts)
	local m = num(e.minutes)
	if m and m > 0 and m < 100000 then
		if m < 1 then
			parts[#parts + 1] = "<1 min"
		elseif m < 60 then
			parts[#parts + 1] = "~" .. math.floor(m + 0.5) .. " min"
		else
			local r = math.floor(m + 0.5)
			parts[#parts + 1] = "~" .. string.format(L["%dh%02d"], math.floor(r / 60), r % 60)
		end
	end
	local xph = num(e.xpPerHour)
	if xph and xph > 0 and xph < 1e9 then
		parts[#parts + 1] = string.format(L["%s XP/h"], shortNum(xph))
	end
	local d = num(e.distance)
	if d and d >= 0 and d < 1e6 then
		parts[#parts + 1] = groupDigits(d) .. " yd"
	end
	if #parts == 0 then return end
	return table.concat(parts, " · ")
end

-- One text line under a quest; returns the new y.
local lineCount = 0
local function placeLine(self, y, inner, size, text, color, have, need, pct)
	lineCount = lineCount + 1
	local o = self:LineRow(lineCount)
	setFont(o.text, size)
	local w = inner - INDENT
	o.text:SetWidth(w)
	o.text:SetText(text)
	o.text:SetTextColor(color[1], color[2], color[3])
	local h = o.text:GetStringHeight() or size
	local barH = 0
	if pct then
		o.bar:SetMinMaxValues(0, 100)
		o.bar:SetValue(math.max(0, math.min(100, pct)))
		barH = BAR + 2
	elseif have and need and need > 1 then
		o.bar:SetMinMaxValues(0, need)
		o.bar:SetValue(math.max(0, math.min(need, have)))
		barH = BAR + 2
	end
	if barH > 0 then
		local done = color == GREEN
		local c = done and GREEN or S.colors.accent
		o.bar:SetStatusBarColor(c[1], c[2], c[3])
		o.bar:Show()
	else
		o.bar:Hide()
	end
	o:ClearAllPoints()
	o:SetPoint("TOPLEFT", self.panel, "TOPLEFT", PAD + INDENT, y)
	o:SetSize(w, h + barH)
	o:Show()
	return y - (h + barH + GAP)
end

function Q:Render(total, tracked)
	local cfg = CK.char.quests
	local p = self.panel
	local size = num(cfg.fontSize, 12)
	local width = num(cfg.width, 260)
	local maxQ = num(cfg.maxQuests, 12)
	local inner = width - PAD * 2
	cfg.collapsed = cfg.collapsed or {}
	p:SetWidth(width)

	local h = self.header
	setFont(h.text, size)
	setFont(h.mark, size)
	h.text:SetText(L["Quests"] .. "  " .. tracked .. "/" .. total)
	h.mark:SetText(cfg.allCollapsed and "+" or "-")
	h:SetHeight(size + 4)
	local mode = cfg.sortMode or "smart"
	local mb = self.modeButton
	setFont(mb.text, math.max(8, size - 2))
	mb.text:SetText("· " .. L[MODE_NAMES[mode] or MODE_NAMES.smart])
	mb:SetSize((mb.text:GetStringWidth() or 40) + 4, size + 4)
	local y = -PAD - (size + 6)

	local smart = mode == "smart" and self.usingPlan
	local accentHex = hex(S.colors.accent)
	local small = math.max(8, size - 2)
	self.nextBar:Hide()

	local ti
	ti, lineCount = 0, 0
	if not cfg.allCollapsed then
		local text = S.colors.text
		for qi = 1, math.min(#list, maxQ) do
			local q = list[qi]
			local plan = q.plan
			local top = y
			ti = ti + 1
			local t = self:TitleRow(ti)
			setFont(t.text, size)
			setFont(t.mark, size)
			setFont(t.tag, small)
			t.questID, t.logIndex, t.questTitle = q.id, q.index, q.title
			local rank = smart and plan and num(plan.rank)
			local s = titleString(q)
			if rank then s = "|cff" .. accentHex .. rank .. ".|r " .. s end
			t.text:SetText(s)
			t.text:SetTextColor(levelColor(q.level))
			local skip = plan and Safe(plan.skip, nil)
			t.skip = SKIP[skip] and skip or nil
			if t.skip then
				t.tag:SetText(L[SKIP[t.skip][1]])
				local c = t.skip == "red" and ORANGE or S.colors.muted
				t.tag:SetTextColor(c[1], c[2], c[3])
			else
				t.tag:SetText("")
			end
			local collapsed = cfg.collapsed[q.id]
			t.mark:SetText(collapsed and "+" or "")
			t:ClearAllPoints()
			t:SetPoint("TOPLEFT", p, "TOPLEFT", PAD, y)
			t:SetSize(inner, size + 4)
			t:Show()
			y = y - (size + 4)

			if not collapsed and plan and cfg.showEstimates then
				local est = estimateString(plan)
				if est then y = placeLine(self, y, inner, small, est, S.colors.muted) end
			end

			if not collapsed then
				if q.failed then
					y = placeLine(self, y, inner, size, L["Failed"], RED)
				elseif q.complete then
					y = placeLine(self, y, inner, size, L["Ready to turn in"], GREEN)
				else
					for oi = 1, q.numObj do
						local o = q.objectives[oi]
						if not (o.done and cfg.hideDone) and o.text ~= "" then
							y = placeLine(self, y, inner, size, o.text, o.done and GREEN or text, o.have, o.need, o.pct)
						end
					end
				end
			end
			-- the next stop of the smart route gets an accent bar on the left
			if smart and qi == 1 then
				local bar = self.nextBar
				bar:ClearAllPoints()
				bar:SetPoint("TOPLEFT", p, "TOPLEFT", PAD - 4, top)
				bar:SetHeight(math.max(1, top - y - GAP))
				bar:Show()
			end
			y = y - GAP * 2
		end
	end

	for i = ti + 1, #titles do titles[i]:Hide() end
	for i = lineCount + 1, #lines do lines[i]:Hide() end
	p:SetHeight(-y + PAD - GAP * 2)
end

---------------------------------------------------------------------------
-- Hiding Blizzard's and Questie's trackers. Only Hide() on show: re-parenting
-- the tracker taints Edit Mode's frame layout (blocked actions).
---------------------------------------------------------------------------
local function keepHidden(frame)
	if not frame or not frame.Hide then return end
	if not frame.ckQuestHidden then
		frame.ckQuestHidden = true
		frame:HookScript("OnShow", function(f)
			if f.ckQuestHidden then f:Hide() end
		end)
	end
	frame:Hide()
end

local BLIZZARD = { "ObjectiveTrackerFrame", "QuestWatchFrame", "WatchFrame" }
local QUESTIE = { "Questie_BaseFrame" }

function Q:ApplyHiding()
	local cfg = CK.char.quests
	local wantBlizz = cfg.enabled and cfg.hideBlizzard
	local wantQuestie = cfg.enabled and cfg.hideQuestieTracker
	-- turned off after hiding: Blizzard/Questie must rebuild their own frames
	if (self.hidBlizzard and not wantBlizz) or (self.hidQuestie and not wantQuestie) then
		if not self.askedReload then
			self.askedReload = true
			CK:Print(L["Type /reload to bring back the other quest trackers."])
		end
		return
	end
	if not (wantBlizz or wantQuestie) then return end
	CK:OutOfCombat("quests-hide", function()
		guard(function()
			if wantBlizz then
				for _, name in ipairs(BLIZZARD) do
					if _G[name] then
						keepHidden(_G[name])
						self.hidBlizzard = true
					end
				end
			end
			if wantQuestie then
				for _, name in ipairs(QUESTIE) do
					if _G[name] then
						keepHidden(_G[name])
						self.hidQuestie = true
					end
				end
			end
		end)
	end)
end

-- Questie builds its tracker some seconds after login; check until found.
function Q:QuestieMissing()
	local cfg = CK.char.quests
	if not (cfg.enabled and cfg.hideQuestieTracker) then return false end
	for _, name in ipairs(QUESTIE) do
		local f = _G[name]
		if f and not f.ckQuestHidden then return true end
	end
	return false
end

---------------------------------------------------------------------------
-- Updates
---------------------------------------------------------------------------
function Q:Redraw()
	if not self.panel then return end
	local cfg = CK.char.quests
	if not cfg.enabled then
		self.panel:Hide()
		guard(self.UpdateArrow, self)
		return
	end
	guard(function()
		local total, tracked = self:Collect()
		self:Render(total, tracked)
		self.panel:Show()
	end)
	guard(self.UpdateArrow, self)
	if self:QuestieMissing() then self:ApplyHiding() end
end

-- At most one redraw every 0.2 s.
function Q:Schedule()
	if self.pending then return end
	self.pending = true
	if C_Timer and C_Timer.After then
		C_Timer.After(0.2, function()
			self.pending = false
			self:Redraw()
		end)
	else
		self.pending = false
		self:Redraw()
	end
end

function Q:Refresh()
	if not self.panel then return end
	S:ApplyPoint(self.panel, "quests")
	self:ApplyHiding()
	self:Redraw()
end

function Q:OnEnable()
	self:CreatePanel()
	local function update(event, unit)
		if event == "UNIT_QUEST_LOG_CHANGED" and Safe(unit, nil) ~= "player" then return end
		guard(self.Schedule, self)
	end
	for _, ev in ipairs({ "QUEST_LOG_UPDATE", "QUEST_WATCH_LIST_CHANGED", "UNIT_QUEST_LOG_CHANGED",
		"ZONE_CHANGED_NEW_AREA", "QUEST_TURNED_IN", "PLAYER_ENTERING_WORLD" }) do
		guard(CK.On, CK, ev, update)
	end
	CK:On("ADDON_LOADED", function(_, name)
		if name == "Blizzard_ObjectiveTracker" or name == "Questie" then guard(self.ApplyHiding, self) end
	end)
	CK:Listen("SETTINGS", function(group)
		if group == "quests" then guard(self.Refresh, self) end
	end)
	-- the route changed (ignored while we are asking the plan ourselves: no redraw loops)
	CK:Listen("QUESTPLAN", function()
		if not self.inPlan then guard(self.Schedule, self) end
	end)
	-- arrived at the arrow's target: point at the plan's next stop when it changed
	CK:Listen("ARROW_ARRIVED", function()
		self.manualArrow = false
		guard(self.Schedule, self)
	end)
	self:Refresh()
end
