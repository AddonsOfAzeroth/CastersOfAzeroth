-- CasterKit by DinX: chat
--
-- Flat, IRC-like restyle of the default Blizzard chat (no ElvUI/Prat needed).
--
-- Design notes (secret values / taint):
--  * Chat lines can be secret strings (mostly during encounters). We never run
--    string functions on them: every edit checks CK.IsSecret first and passes
--    secret lines through untouched.
--  * Line edits (grey timestamp, short channel names, URL links) need the final
--    formatted line, so we wrap AddMessage of each chat window (the same spot
--    ElvUI/Prat use). Blizzard globals such as CHAT_GUILD_GET are NOT touched:
--    changing those taints the whole message handler for every line.
--  * Timestamps come from Blizzard's own CVar "showTimestamps"; class colours
--    from Blizzard's per-chat-type setting (SetChatColorNameByClass). Both work
--    for secret lines as well, because Blizzard formats them itself.
--  * Everything else uses hooksecurefunc / HookScript, wrapped in pcall, so a
--    missing frame or a changed API can never start an error stream.
--  * The addon never sends anything to chat.
local _, ns = ...
local CK = ns.CK
local S = CK.Style
local L = CK.L or setmetatable({}, { __index = function(_, k) return k end })

local Chat = CK:NewModule("Chat")

local issecret = CK.IsSecret
local TAB_H, EDIT_H = 20, 22
local TIMESTAMP = "[%H:%M] "
local GetCVar = C_CVar and C_CVar.GetCVar or GetCVar
local SetCVar = C_CVar and C_CVar.SetCVar or SetCVar
local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

local hider = CreateFrame("Frame")
hider:Hide()

local unread = {}   -- chat frame -> "msg" | "whisper"
local skinned = {}  -- chat frame -> true
local hover = false
local anchoring = false

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local errors = 0
local function safe(fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then
		errors = errors + 1
		if CK.debug and errors <= 10 then CK:Print("chat:", tostring(err)) end
	end
	return ok
end

-- Hide a Blizzard region without destroying it.
local function hide(region)
	if not region then return end
	if region.SetAlpha then region:SetAlpha(0) end
	if region.Hide then region:Hide() end
	if region.SetParent then pcall(region.SetParent, region, hider) end
end

local function hook(name, fn)
	if type(_G[name]) == "function" then
		hooksecurefunc(name, function(...) safe(fn, ...) end)
	end
end

-- Non-protected frames may be touched in combat; protected ones must wait.
local function canTouch(f)
	return not InCombatLockdown() or not (f and f.IsProtected and f:IsProtected())
end

local function eachFrame(fn)
	local list = _G.CHAT_FRAMES
	if type(list) == "table" then
		for _, name in ipairs(list) do
			local f = _G[name]
			if f then fn(f) end
		end
	else
		for i = 1, (NUM_CHAT_WINDOWS or 10) do
			local f = _G["ChatFrame" .. i]
			if f then fn(f) end
		end
	end
end

local function tabOf(frame)
	local name = frame and frame.GetName and frame:GetName()
	return name and _G[name .. "Tab"]
end

local function isDocked(frame)
	return frame == _G.ChatFrame1 or frame.isDocked
end

local function selectedFrame()
	local dm = _G.GeneralDockManager
	if dm and FCFDock_GetSelectedWindow then
		local f = FCFDock_GetSelectedWindow(dm)
		if f then return f end
	end
	return _G.SELECTED_CHAT_FRAME or _G.ChatFrame1
end

local function isSelected(frame)
	if isDocked(frame) then return selectedFrame() == frame end
	return frame:IsShown()
end

local function chatFont()
	local file = ChatFontNormal and ChatFontNormal:GetFont()
	return file or S.font
end

local function hex(c)
	return ("ff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Escape Lua pattern magic characters.
local function esc(s)
	return (s:gsub("[%^%$%(%)%%%.%[%]%*%+%-%?]", "%%%0"))
end

local function conflict()
	if IsLoaded("Prat-3.0") then return "Prat" end
	if IsLoaded("Chattynator") then return "Chattynator" end
	if IsLoaded("ElvUI") and ElvUI then
		local E = ElvUI[1]
		if not (E and E.private and E.private.chat) or E.private.chat.enable then return "ElvUI" end
	end
end

---------------------------------------------------------------------------
-- Line edits (only ever called with non-secret strings)
---------------------------------------------------------------------------
local TOKENS = {
	GUILD = "g", OFFICER = "O", PARTY = "P", PARTY_LEADER = "PL", PARTY_GUIDE = "PG",
	RAID = "R", RAID_LEADER = "RL", INSTANCE_CHAT = "I", INSTANCE_CHAT_LEADER = "IL",
}
local CHANNELS = {
	General = "G", Trade = "T", LocalDefense = "LD", LookingForGroup = "LFG", WorldDefense = "WD",
	Services = "S", ["Trade (Services)"] = "S", NewcomerChat = "N", GuildRecruitment = "GR",
}
local SYSTEM_CHANNELS = {
	General = true, Trade = true, LocalDefense = true, LookingForGroup = true, WorldDefense = true,
	Services = true, ["Trade (Services)"] = true, NewcomerChat = true, GuildRecruitment = true,
}

-- Words taken from Blizzard's own format strings (enUS fallbacks).
local function suffixOf(fmt, fallback)
	local s = type(fmt) == "string" and fmt:match("^%%s(.+)$")
	return esc(s or fallback)
end
local SAYS = suffixOf(CHAT_SAY_GET, " says: ")
local YELLS = suffixOf(CHAT_YELL_GET, " yells: ")
local WHISPERS = suffixOf(CHAT_WHISPER_GET, " whispers: ")
local TO = esc(type(CHAT_WHISPER_INFORM_GET) == "string" and CHAT_WHISPER_INFORM_GET:match("^(.-)%%s") or "To ")
local RW = "%[" .. esc(RAID_WARNING or "Raid Warning") .. "%]"
local PLAYER = "(|HB?N?player:.-%]|h)"

local function shortName(token, label)
	local short = TOKENS[token:upper()]
	if short then return short end
	local name = label:gsub("^%d+%.%s*", ""):gsub("%s+%-%s+.*$", "")
	return CHANNELS[name] or name
end

local function shortChannels(msg)
	msg = msg:gsub("|Hchannel:([^|]-)|h%[([^%]]-)%]|h", function(token, label)
		return "|Hchannel:" .. token .. "|h[" .. shortName(token, label) .. "]|h"
	end)
	msg = msg:gsub(RW, "[RW]", 1)
	local n
	msg, n = msg:gsub("^(.-)" .. TO .. PLAYER .. ": ", "%1>> %2: ", 1)
	if n > 0 then return msg end
	msg, n = msg:gsub("^(.-)" .. PLAYER .. WHISPERS, "%1<< %2: ", 1)
	if n > 0 then return msg end
	msg, n = msg:gsub("^(.-)" .. PLAYER .. YELLS, "%1[Y] %2: ", 1)
	if n > 0 then return msg end
	return (msg:gsub(PLAYER .. SAYS, "%1: ", 1))
end

local function urlLink(url)
	return "|c" .. hex(S.colors.accent) .. "|Haddon:CasterKit:url:" .. url .. "|h[" .. url .. "]|h|r"
end

local function linkWord(word)
	if word:find("|", 1, true) then return end
	if not (word:match("^https?://.") or word:match("^www%.[%w%-]+%.%w")) then return end
	local url, tail = word:match("^(.-)([%.,;:!%?%)]*)$")
	return urlLink(url) .. tail
end

local function linkURLs(msg)
	if not (msg:find("://", 1, true) or msg:find("www.", 1, true)) then return msg end
	-- keep existing links and textures intact
	local stash = {}
	local s = msg:gsub("|H.-|h.-|h", function(l)
		stash[#stash + 1] = l
		return "\001" .. #stash .. "\001"
	end)
	s = s:gsub("[^%s\001]+", linkWord)
	return (s:gsub("\001(%d+)\001", function(i) return stash[tonumber(i)] end))
end

local function editLine(msg)
	if msg == "" then return msg end
	local cfg = CK.char.chat
	msg = msg:gsub("^(%[%d%d?:%d%d%]) ", "|cff8a8f99%1|r ", 1)
	if cfg.shortChannels then msg = shortChannels(msg) end
	return linkURLs(msg)
end

---------------------------------------------------------------------------
-- Unread tabs
---------------------------------------------------------------------------
local refreshTab

local function markUnread(frame, whisper)
	if not frame or frame == _G.ChatFrame2 or frame:IsVisible() then return end
	if whisper then
		unread[frame] = "whisper"
	elseif not unread[frame] then
		unread[frame] = "msg"
	end
	refreshTab(frame)
end

local function noteMessage(frame, ...)
	local event = select(7, ...)
	if issecret(event) or type(event) ~= "string" then
		markUnread(frame, false)
		return
	end
	if event:find("^CHAT_MSG_") then
		markUnread(frame, event == "CHAT_MSG_WHISPER" or event == "CHAT_MSG_BN_WHISPER")
	end
end

---------------------------------------------------------------------------
-- AddMessage wrapper
---------------------------------------------------------------------------
local function skipFrame(frame)
	local id = frame.GetID and frame:GetID()
	return frame == _G.ChatFrame2 or id == 2 or (VOICE_WINDOW_ID and id == VOICE_WINDOW_ID)
end

local function wrapAddMessage(frame)
	if frame.ckOrigAdd or skipFrame(frame) then return end
	local orig = frame.AddMessage
	if type(orig) ~= "function" then return end
	frame.ckOrigAdd = orig
	frame.AddMessage = function(self, msg, ...)
		if not issecret(msg) and type(msg) == "string" then
			local ok, out = pcall(editLine, msg)
			if ok and type(out) == "string" then msg = out end
		end
		pcall(noteMessage, self, ...)
		return orig(self, msg, ...)
	end
end

---------------------------------------------------------------------------
-- URL clicks: native "addon:" link routing
---------------------------------------------------------------------------
local function toEditBox(text)
	local choose = (ChatFrameUtil and ChatFrameUtil.ChooseBoxForSend) or ChatEdit_ChooseBoxForSend
	local activate = (ChatFrameUtil and ChatFrameUtil.ActivateChat) or ChatEdit_ActivateChat
	local eb = choose and choose()
	if not eb then return end
	if not eb:HasFocus() and activate then activate(eb) end
	eb:SetText(text)
	eb:HighlightText()
end

local function onLink(link)
	if issecret(link) or type(link) ~= "string" then return end
	local url = link:match("^addon:CasterKit:url:(.+)$")
	if url then toEditBox(url) end
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function iconButton(parent, texture, size)
	local b = CreateFrame("Button", nil, parent)
	b:SetSize(size, size)
	b:SetFrameStrata("MEDIUM")
	local t = b:CreateTexture(nil, "ARTWORK")
	t:SetAllPoints()
	t:SetTexture(texture)
	b.icon = t
	b:SetAlpha(0.6)
	b:SetScript("OnLeave", function(self)
		self:SetAlpha(0.6)
		GameTooltip:Hide()
	end)
	return b
end

function Chat:CreatePanel()
	local p = CreateFrame("Frame", "CasterKitChat", UIParent, "BackdropTemplate")
	p:SetFrameStrata("BACKGROUND")
	p:SetFrameLevel(1)
	S:Backdrop(p)
	self.panel = p

	-- line under the tab strip
	local sep = p:CreateTexture(nil, "BORDER")
	sep:SetColorTexture(0, 0, 0, 1)
	sep:SetHeight(1)
	sep:SetPoint("TOPLEFT", 1, -(TAB_H + 1))
	sep:SetPoint("TOPRIGHT", -1, -(TAB_H + 1))

	-- input row
	local row = CreateFrame("Frame", nil, p, "BackdropTemplate")
	row:SetPoint("BOTTOMLEFT")
	row:SetPoint("BOTTOMRIGHT")
	row:SetHeight(EDIT_H)
	S:Backdrop(row, 0.5)
	local strip = row:CreateTexture(nil, "ARTWORK")
	strip:SetPoint("TOPLEFT", 1, -1)
	strip:SetPoint("BOTTOMLEFT", 1, 1)
	strip:SetWidth(2)
	strip:SetColorTexture(unpack(S.colors.muted))
	row.strip = strip
	local hint = S:Font(row, 11)
	hint:SetPoint("LEFT", 8, 0)
	hint:SetTextColor(unpack(S.colors.muted))
	row.hint = hint
	self.row = row

	-- copy button (top right)
	local copy = iconButton(p, "Interface\\Buttons\\UI-GuildButton-PublicNote-Up", 16)
	copy:SetPoint("TOPRIGHT", -4, -2)
	copy:SetScript("OnClick", function() safe(self.CopyChat, self) end)
	copy:SetScript("OnEnter", function(b)
		b:SetAlpha(1)
		GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Copy chat"])
		GameTooltip:AddLine(L["Shows the last 100 lines of this tab, ready to copy."], 1, 1, 1, true)
		GameTooltip:Show()
	end)
	self.copyButton = copy

	-- jump to the newest line
	local down = iconButton(p, "Interface\\ChatFrame\\UI-ChatIcon-ScrollEnd-Up", 18)
	down:SetPoint("BOTTOMRIGHT", -4, EDIT_H + 4)
	down:SetScript("OnClick", function()
		local f = selectedFrame()
		if f and f.ScrollToBottom then f:ScrollToBottom() end
	end)
	down:SetScript("OnEnter", function(b)
		b:SetAlpha(1)
		GameTooltip:SetOwner(b, "ANCHOR_TOPLEFT")
		GameTooltip:SetText(L["Scroll to the bottom"])
		GameTooltip:Show()
	end)
	down:Hide()
	self.downButton = down

	local cfg = CK.char.chat
	p:SetSize(cfg.width, cfg.height)
	S:RegisterMover(p, "chat", L["Chat"], function(f)
		f:SetPoint("BOTTOMLEFT", UIParent, "BOTTOMLEFT", 8, 8)
	end)
end

---------------------------------------------------------------------------
-- Skinning Blizzard chat windows
---------------------------------------------------------------------------
local FRAME_TEXTURES = {
	"Background", "TopLeftTexture", "BottomLeftTexture", "TopRightTexture", "BottomRightTexture",
	"LeftTexture", "RightTexture", "BottomTexture", "TopTexture",
}

local function wheel(self, delta)
	pcall(function()
		if delta > 0 then
			if IsShiftKeyDown() then self:ScrollToTop() else for _ = 1, 3 do self:ScrollUp() end end
		else
			if IsShiftKeyDown() then self:ScrollToBottom() else for _ = 1, 3 do self:ScrollDown() end end
		end
	end)
end

local function applyFont(frame)
	local size = CK.char.chat.fontSize
	if frame.SetFont then frame:SetFont(chatFont(), size, "OUTLINE") end
	if frame.SetShadowOffset then frame:SetShadowOffset(0, 0) end
	local eb = frame.editBox
	if eb and eb.SetFont then
		eb:SetFont(chatFont(), size, "OUTLINE")
		if eb.header and eb.header.SetFont then eb.header:SetFont(chatFont(), size, "OUTLINE") end
	end
end

local function desiredTabAlpha(tab)
	if not CK.char.chat.fadeTabs or hover then return 1 end
	if tab.ckFrame and unread[tab.ckFrame] then return 1 end
	return 0.3
end

local function tabAlphaHook(tab, alpha)
	if tab.ckSetting or issecret(alpha) then return end
	local want = desiredTabAlpha(tab)
	if math.abs((alpha or 1) - want) > 0.01 then
		tab.ckSetting = true
		tab:SetAlpha(want)
		tab.ckSetting = false
	end
end

refreshTab = function(frame)
	local tab = tabOf(frame)
	if not tab or not tab.ckLine then return end
	local state = unread[frame]
	local color
	if state == "whisper" then
		color = S.colors.proc
	elseif state then
		color = S.colors.accent
	elseif isSelected(frame) then
		color = S.colors.text
	else
		color = S.colors.muted
	end
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	if text then text:SetTextColor(color[1], color[2], color[3]) end
	tab.ckLine:SetShown(isSelected(frame))
	tab.ckDot:SetShown(state ~= nil)
	tab.ckDot:SetVertexColor(color[1], color[2], color[3])
	tabAlphaHook(tab, tab:GetAlpha())
end

local function refreshAllTabs()
	eachFrame(function(f) safe(refreshTab, f) end)
end

local function skinTab(frame)
	local tab = tabOf(frame)
	if not tab then return end
	tab.ckFrame = frame
	local text = tab.Text or _G[tab:GetName() .. "Text"]
	if not tab.ckLine then
		for _, r in ipairs({ tab:GetRegions() }) do
			if r:IsObjectType("Texture") then hide(r) end
		end
		local line = tab:CreateTexture(nil, "OVERLAY")
		line:SetTexture(S.flat)
		line:SetVertexColor(unpack(S.colors.accent))
		line:SetHeight(1)
		line:SetPoint("BOTTOMLEFT", 4, 1)
		line:SetPoint("BOTTOMRIGHT", -4, 1)
		tab.ckLine = line
		local dot = tab:CreateTexture(nil, "OVERLAY")
		dot:SetTexture("Interface\\COMMON\\Indicator-Gray")
		dot:SetSize(10, 10)
		if text then dot:SetPoint("RIGHT", text, "LEFT", 0, 0) else dot:SetPoint("LEFT", 2, 0) end
		dot:Hide()
		tab.ckDot = dot
		hooksecurefunc(tab, "SetAlpha", function(t, a) safe(tabAlphaHook, t, a) end)
	end
	tab:SetHeight(TAB_H)
	if text then
		S:ApplyFont(text, 11)
		text:SetShadowOffset(0, 0)
		text:ClearAllPoints()
		text:SetPoint("CENTER", tab, "CENTER", 0, 0)
	end
	if PanelTemplates_TabResize and not isDocked(frame) then PanelTemplates_TabResize(tab, 10) end
	refreshTab(frame)
end

local function updateHeader(eb)
	if not eb or not Chat.row then return end
	local chatType = eb:GetAttribute("chatType")
	local info = ChatTypeInfo and chatType and ChatTypeInfo[chatType]
	if chatType == "CHANNEL" and GetChannelName and ChatTypeInfo then
		local target = eb:GetAttribute("channelTarget")
		local index = target and GetChannelName(target)
		if index and index ~= 0 then info = ChatTypeInfo["CHANNEL" .. index] or info end
	end
	local c = info and info.r and { info.r, info.g, info.b } or S.colors.muted
	Chat.row.strip:SetColorTexture(c[1], c[2], c[3])
end

-- Tab key with an empty input cycles /s, /p, /g, /i.
local CYCLE = { SAY = "/s ", PARTY = "/p ", GUILD = "/g ", INSTANCE_CHAT = "/i " }
local function cycleChat(eb)
	local text = eb:GetText()
	if issecret(text) or text ~= "" then return end
	local cur = eb:GetAttribute("chatType")
	if cur == "WHISPER" or cur == "BN_WHISPER" then return end -- Blizzard cycles tell targets
	local list = { "SAY" }
	if IsInGroup and IsInGroup() then list[#list + 1] = "PARTY" end
	if IsInGuild and IsInGuild() then list[#list + 1] = "GUILD" end
	if IsInGroup and LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then list[#list + 1] = "INSTANCE_CHAT" end
	local nextType = list[1]
	for i, t in ipairs(list) do
		if t == cur then nextType = list[i % #list + 1] break end
	end
	eb:SetText(CYCLE[nextType])
	if eb.ParseText then
		eb:ParseText(0)
	elseif ChatEdit_ParseText then
		ChatEdit_ParseText(eb, 0)
	end
end

local function anchorEditBox(eb)
	local frame = eb.chatFrame
	if not Chat.row or not frame or not isDocked(frame) or not canTouch(eb) then return end
	eb:ClearAllPoints()
	eb:SetPoint("TOPLEFT", Chat.row, "TOPLEFT", 4, 0)
	eb:SetPoint("BOTTOMRIGHT", Chat.row, "BOTTOMRIGHT", -4, 0)
end

local function updateHint()
	local row = Chat.row
	if not row then return end
	local shown = false
	eachFrame(function(f)
		local eb = f.editBox
		if eb and isDocked(f) and eb:IsShown() then shown = true end
	end)
	row.hint:SetText(L["Press Enter to chat"])
	row.hint:SetShown(not shown)
end

local function skinEditBox(frame)
	local eb = frame.editBox or _G[frame:GetName() .. "EditBox"]
	if not eb then return end
	eb.chatFrame = eb.chatFrame or frame
	if not eb.ckSkinned then
		eb.ckSkinned = true
		local name = eb:GetName()
		for _, k in ipairs({ "Left", "Mid", "Right", "focusLeft", "focusMid", "focusRight" }) do hide(eb[k]) end
		if name then
			for _, k in ipairs({ "Left", "Mid", "Right", "FocusLeft", "FocusMid", "FocusRight" }) do hide(_G[name .. k]) end
		end
		for _, r in ipairs({ eb:GetRegions() }) do
			if r:IsObjectType("Texture") then hide(r) end
		end
		eb:HookScript("OnTabPressed", function(self) safe(cycleChat, self) end)
		eb:HookScript("OnShow", function(self) safe(anchorEditBox, self) safe(updateHint) end)
		eb:HookScript("OnHide", function() safe(updateHint) end)
		if eb.UpdateHeader then
			hooksecurefunc(eb, "UpdateHeader", function(self) safe(updateHeader, self) end)
		end
	end
	anchorEditBox(eb)
end

local function skinFrame(frame)
	local name = frame:GetName()
	if not name then return end
	wrapAddMessage(frame)
	applyFont(frame)
	skinTab(frame)
	skinEditBox(frame)
	if skinned[frame] then return end
	skinned[frame] = true

	local list = _G.CHAT_FRAME_TEXTURES or FRAME_TEXTURES
	for _, suffix in ipairs(list) do hide(_G[name .. suffix] or frame[suffix]) end
	hide(frame.Background)
	hide(frame.buttonFrame or _G[name .. "ButtonFrame"])
	hide(frame.ScrollBar)
	hide(frame.ScrollToBottomButton)
	hide(_G[name .. "ThumbTexture"])
	hide(_G[name .. "MinimizeButton"])
	if frame == _G.ChatFrame1 then
		hide(_G[name .. "ResizeButton"])
		hide(frame.EditModeResizeButton)
	end
	if frame.SetClampRectInsets then frame:SetClampRectInsets(0, 0, 0, 0) end

	-- own background for windows that are torn off the dock
	local bg = CreateFrame("Frame", nil, frame, "BackdropTemplate")
	bg:SetPoint("TOPLEFT", -4, 4)
	bg:SetPoint("BOTTOMRIGHT", 4, -4)
	bg:SetFrameLevel(math.max(0, frame:GetFrameLevel() - 1))
	S:Backdrop(bg)
	frame.ckBg = bg

	if frame.EnableMouseWheel then frame:EnableMouseWheel(true) end
	frame:SetScript("OnMouseWheel", wheel)
	hooksecurefunc(frame, "SetScript", function(f, script, fn)
		if script == "OnMouseWheel" and fn ~= wheel then f:SetScript("OnMouseWheel", wheel) end
	end)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
local function anchorChat()
	local cf, p = _G.ChatFrame1, Chat.panel
	if not cf or not p or not canTouch(cf) then return end
	anchoring = true
	cf:SetClampedToScreen(false)
	cf:ClearAllPoints()
	cf:SetPoint("TOPLEFT", p, "TOPLEFT", 5, -(TAB_H + 4))
	cf:SetPoint("BOTTOMRIGHT", p, "BOTTOMRIGHT", -5, EDIT_H + 3)
	anchoring = false
end

local function anchorDock()
	local dm, p = _G.GeneralDockManager, Chat.panel
	if not dm or not p or not canTouch(dm) then return end
	dm:ClearAllPoints()
	dm:SetPoint("TOPLEFT", p, "TOPLEFT", 2, -1)
	dm:SetPoint("TOPRIGHT", p, "TOPRIGHT", -24, -1)
	dm:SetHeight(TAB_H)
	local sf = _G.GeneralDockManagerScrollFrame
	if sf then sf:SetHeight(TAB_H) end
	local child = _G.GeneralDockManagerScrollFrameChild
	if child then child:SetHeight(TAB_H) end
end

function Chat:Layout()
	local cfg = CK.char.chat
	local p = self.panel
	p:SetSize(math.max(200, cfg.width), math.max(80, cfg.height))
	anchorChat()
	anchorDock()
	eachFrame(function(f)
		safe(skinFrame, f)
		if f.ckBg then f.ckBg:SetShown(not isDocked(f)) end
	end)
	updateHint()
	refreshAllTabs()
end

function Chat:Setup()
	local qj = _G.QuickJoinToastButton
	if qj then hide(qj) end
	if _G.TextToSpeechButtonFrame then hide(_G.TextToSpeechButtonFrame) end
	self:Layout()
	local f = selectedFrame()
	if f and f.editBox then updateHeader(f.editBox) end
end

local function relayout()
	CK:OutOfCombat("chat-layout", function() safe(Chat.Layout, Chat) end)
end

---------------------------------------------------------------------------
-- Blizzard chat settings: timestamps and class colours
---------------------------------------------------------------------------
local function applyTimestamps()
	if not GetCVar or not SetCVar then return end
	local cfg = CK.char.chat
	local cur = GetCVar("showTimestamps")
	if cfg.timestamps then
		if cur ~= TIMESTAMP then
			cfg.prevTimestamps = cur
			SetCVar("showTimestamps", TIMESTAMP)
		end
	elseif cur == TIMESTAMP then
		local prev = cfg.prevTimestamps
		SetCVar("showTimestamps", (prev and prev ~= TIMESTAMP) and prev or "none")
	end
end

local NAME_TYPES = {
	"SAY", "EMOTE", "YELL", "WHISPER", "WHISPER_INFORM", "BN_WHISPER", "PARTY", "PARTY_LEADER",
	"RAID", "RAID_LEADER", "RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "OFFICER",
}
local function applyClassColors()
	if not SetChatColorNameByClass or not ChatTypeInfo then return end
	local on = CK.char.chat.classColors and true or false
	local function set(chatType)
		local info = ChatTypeInfo[chatType]
		if info and (info.colorNameByClass and true or false) ~= on then
			SetChatColorNameByClass(chatType, on)
		end
	end
	for _, t in ipairs(NAME_TYPES) do pcall(set, t) end
	for i = 1, (MAX_WOW_CHAT_CHANNELS or 20) do pcall(set, "CHANNEL" .. i) end
end

---------------------------------------------------------------------------
-- One tab per channel (asked once, out of combat)
---------------------------------------------------------------------------
local function addGroups(frame, groups)
	for _, g in ipairs(groups) do
		if not ChatTypeGroup or ChatTypeGroup[g] then
			if frame.AddMessageGroup then frame:AddMessageGroup(g)
			elseif ChatFrame_AddMessageGroup then ChatFrame_AddMessageGroup(frame, g) end
		end
	end
end

local function clearFrame(frame)
	if frame.RemoveAllMessageGroups then frame:RemoveAllMessageGroups()
	elseif ChatFrame_RemoveAllMessageGroups then ChatFrame_RemoveAllMessageGroups(frame) end
	if frame.RemoveAllChannels then frame:RemoveAllChannels()
	elseif ChatFrame_RemoveAllChannels then ChatFrame_RemoveAllChannels(frame) end
end

local function addChannel(frame, name)
	if frame.AddChannel then frame:AddChannel(name)
	elseif ChatFrame_AddChannel then ChatFrame_AddChannel(frame, name) end
end

local function removeChannel(frame, name)
	if frame.RemoveChannel then frame:RemoveChannel(name)
	elseif ChatFrame_RemoveChannel then ChatFrame_RemoveChannel(frame, name) end
end

local windowInfo = FCF_GetChatWindowInfo or GetChatWindowInfo

local function findWindow(name)
	if not windowInfo then return end
	for i = 1, (NUM_CHAT_WINDOWS or 10) do
		local n, _, _, _, _, _, shown, _, docked = windowInfo(i)
		if n == name and (shown or docked) then return _G["ChatFrame" .. i] end
	end
end

local noRoom = false
local function openTab(name)
	local f = findWindow(name)
	if f then return f end
	if not FCF_OpenNewWindow then return end
	f = FCF_OpenNewWindow(name)
	if type(f) ~= "table" then f = findWindow(name) end
	if not f and not noRoom then
		noRoom = true
		CK:Print(L["No free chat window left for more tabs."])
	end
	return f
end

local GENERAL_GROUPS = {
	"SAY", "EMOTE", "YELL", "WHISPER", "BN_WHISPER", "PARTY", "PARTY_LEADER", "RAID", "RAID_LEADER",
	"RAID_WARNING", "INSTANCE_CHAT", "INSTANCE_CHAT_LEADER", "GUILD", "SYSTEM", "ERRORS", "AFK", "DND",
	"IGNORED", "CHANNEL", "PING", "MONSTER_SAY", "MONSTER_YELL", "MONSTER_EMOTE", "MONSTER_WHISPER",
	"MONSTER_BOSS_EMOTE", "MONSTER_BOSS_WHISPER", "BG_HORDE", "BG_ALLIANCE", "BG_NEUTRAL", "ACHIEVEMENT",
	"BN_INLINE_TOAST_ALERT", "COMBAT_XP_GAIN", "COMBAT_HONOR_GAIN", "COMBAT_FACTION_CHANGE", "SKILL",
	"LOOT", "CURRENCY", "MONEY",
}

local function customChannels()
	local out = {}
	if not GetChannelList then return out end
	local list = { GetChannelList() }
	for i = 1, #list, 3 do
		local name = list[i + 1]
		if type(name) == "string" and not issecret(name) and not SYSTEM_CHANNELS[name] then
			out[#out + 1] = name
		end
	end
	return out
end

local function channelTab(name)
	local cfg = CK.char.chat
	cfg.channelTabs = cfg.channelTabs or {}
	local f = openTab(name)
	if not f then return end
	clearFrame(f)
	addChannel(f, name)
	removeChannel(_G.ChatFrame1, name)
	cfg.channelTabs[name] = true
end

function Chat:SetupTabs()
	local cf = _G.ChatFrame1
	if not cf then return end
	noRoom = false

	if FCF_SetWindowName then FCF_SetWindowName(cf, L["General"]) end
	clearFrame(cf)
	addGroups(cf, GENERAL_GROUPS)
	addChannel(cf, GENERAL or "General")
	addChannel(cf, "LocalDefense")

	local f = openTab(L["Guild"])
	if f then clearFrame(f) addGroups(f, { "GUILD", "OFFICER", "GUILD_ACHIEVEMENT", "GUILD_DISCORD" }) end
	f = openTab(L["Whisper"])
	if f then clearFrame(f) addGroups(f, { "WHISPER", "BN_WHISPER", "AFK", "DND" }) end
	f = openTab(L["Trade"])
	if f then clearFrame(f) addChannel(f, TRADE or "Trade") addChannel(f, "Services") end
	f = openTab(L["LFG"])
	if f then clearFrame(f) addChannel(f, "LookingForGroup") end
	for _, name in ipairs(customChannels()) do channelTab(name) end

	if FCF_SelectDockFrame then FCF_SelectDockFrame(cf) end
	self:Layout()
	CK:Print(L["Chat tabs are set up."])
end

-- Joined a new custom channel later: give it its own tab once.
function Chat:CheckNewChannels()
	local cfg = CK.char.chat
	if cfg.setupDone ~= "accepted" or not cfg.tabsPerChannel then return end
	cfg.channelTabs = cfg.channelTabs or {}
	local added = false
	for _, name in ipairs(customChannels()) do
		if not cfg.channelTabs[name] then
			channelTab(name)
			added = true
		end
	end
	if added then self:Layout() end
end

StaticPopupDialogs["CASTERKIT_CHAT_SETUP"] = {
	text = "CasterKit will set up your chat with one tab per channel. Continue?",
	button1 = YES or "Yes",
	button2 = NO or "No",
	OnAccept = function()
		CK.char.chat.setupDone = "accepted"
		CK:OutOfCombat("chat-tabs", function() safe(Chat.SetupTabs, Chat) end)
	end,
	OnCancel = function(_, _, reason)
		if reason == "clicked" then CK.char.chat.setupDone = "declined" end
	end,
	timeout = 0,
	whileDead = true,
	hideOnEscape = true,
	preferredIndex = 3,
}

function Chat:MaybeAskSetup()
	local cfg = CK.char.chat
	if not self.started or not cfg.tabsPerChannel or cfg.setupDone ~= nil then return end
	if InCombatLockdown() then
		CK:OutOfCombat("chat-ask", function() safe(self.MaybeAskSetup, self) end)
		return
	end
	if not StaticPopup_Show then return end
	-- language is chosen at runtime, so set the text right before showing
	StaticPopupDialogs["CASTERKIT_CHAT_SETUP"].text = L["CasterKit will set up your chat with one tab per channel. Continue?"]
	StaticPopup_Show("CASTERKIT_CHAT_SETUP")
end

---------------------------------------------------------------------------
-- Copy chat
---------------------------------------------------------------------------
local function plain(msg)
	msg = msg:gsub("|T.-|t", ""):gsub("|A.-|a", "")
	msg = msg:gsub("|H.-|h(.-)|h", "%1")
	msg = msg:gsub("|c%x%x%x%x%x%x%x%x", ""):gsub("|cn[^:]-:", ""):gsub("|r", "")
	return msg
end

function Chat:BuildCopyFrame()
	local f = CreateFrame("Frame", "CasterKitChatCopy", UIParent, "BackdropTemplate")
	f:SetSize(560, 340)
	f:SetPoint("CENTER")
	f:SetFrameStrata("DIALOG")
	f:SetMovable(true)
	f:SetClampedToScreen(true)
	f:EnableMouse(true)
	f:RegisterForDrag("LeftButton")
	f:SetScript("OnDragStart", f.StartMoving)
	f:SetScript("OnDragStop", f.StopMovingOrSizing)
	S:Backdrop(f, 0.95)
	f:Hide()

	local title = S:Font(f, 13)
	title:SetPoint("TOPLEFT", 8, -7)
	title:SetTextColor(unpack(S.colors.accent))
	f.title = title
	local help = S:Font(f, 11)
	help:SetPoint("BOTTOMLEFT", 8, 6)
	help:SetTextColor(unpack(S.colors.muted))
	f.help = help

	local close = CreateFrame("Button", nil, f)
	close:SetSize(18, 18)
	close:SetPoint("TOPRIGHT", -4, -4)
	local x = S:Font(close, 13)
	x:SetPoint("CENTER")
	x:SetText("x")
	close:SetScript("OnClick", function() f:Hide() end)
	close:SetScript("OnEnter", function() x:SetTextColor(unpack(S.colors.warn)) end)
	close:SetScript("OnLeave", function() x:SetTextColor(unpack(S.colors.text)) end)

	local ok, sf = pcall(CreateFrame, "ScrollFrame", nil, f, "UIPanelScrollFrameTemplate")
	if not ok or not sf then
		sf = CreateFrame("ScrollFrame", nil, f)
		sf:EnableMouseWheel(true)
		sf:SetScript("OnMouseWheel", function(self, delta)
			local v = math.max(0, math.min(self:GetVerticalScrollRange(), self:GetVerticalScroll() - delta * 40))
			self:SetVerticalScroll(v)
		end)
	end
	sf:SetPoint("TOPLEFT", 8, -28)
	sf:SetPoint("BOTTOMRIGHT", -28, 24)

	local eb = CreateFrame("EditBox", nil, sf)
	eb:SetMultiLine(true)
	eb:SetAutoFocus(false)
	eb:SetMaxLetters(0)
	eb:SetFont(chatFont(), 12, "")
	eb:SetWidth(520)
	eb:SetScript("OnEscapePressed", function() f:Hide() end)
	sf:SetScrollChild(eb)
	f.edit = eb

	if type(UISpecialFrames) == "table" then tinsert(UISpecialFrames, "CasterKitChatCopy") end
	self.copyFrame = f
	return f
end

function Chat:CopyChat()
	local f = self.copyFrame or self:BuildCopyFrame()
	if f:IsShown() then
		f:Hide()
		return
	end
	local chat = selectedFrame()
	if not chat or not chat.GetNumMessages or not chat.GetMessageInfo then return end
	local n = chat:GetNumMessages() or 0
	local lines, skipped = {}, 0
	for i = math.max(1, n - 99), n do
		local msg = chat:GetMessageInfo(i)
		if issecret(msg) then
			skipped = skipped + 1
		elseif type(msg) == "string" then
			local ok, line = pcall(plain, msg)
			if ok then lines[#lines + 1] = line end
		end
	end
	local tab = tabOf(chat)
	local tabText = tab and (tab.Text or _G[tab:GetName() .. "Text"])
	local name = tabText and tabText:GetText()
	f.title:SetText(L["Copy chat"] .. ((name and not issecret(name)) and (": " .. name) or ""))
	local help = L["Select all with Ctrl+A, copy with Ctrl+C."]
	if skipped > 0 then help = help .. "  " .. L["%d protected lines were left out."]:format(skipped) end
	f.help:SetText(help)
	f:Show()
	f.edit:SetText(table.concat(lines, "\n"))
	f.edit:SetFocus()
	f.edit:HighlightText()
end

---------------------------------------------------------------------------
-- Ticker: hover fade, unread clearing, scroll button (cheap, self-stopping)
---------------------------------------------------------------------------
local function tick()
	local p = Chat.panel
	if not p then return end
	local over = p:IsMouseOver() or false
	if not over then
		eachFrame(function(f)
			local eb = f.editBox
			if eb and isDocked(f) and eb:HasFocus() then over = true end
		end)
	end
	local changed = over ~= hover
	hover = over
	for frame in pairs(unread) do
		if frame:IsVisible() then
			unread[frame] = nil
			changed = true
			refreshTab(frame)
		end
	end
	if changed then
		eachFrame(function(f)
			local tab = tabOf(f)
			if tab and tab.ckLine then tabAlphaHook(tab, tab:GetAlpha()) end
		end)
	end
	local sel = selectedFrame()
	local atBottom = not (sel and sel.AtBottom) or sel:AtBottom()
	Chat.downButton:SetShown(not atBottom)
end

function Chat:StartTicker()
	if self.ticker or not C_Timer or not C_Timer.NewTicker then return end
	local fails = 0
	self.ticker = C_Timer.NewTicker(0.25, function()
		if not pcall(tick) then
			fails = fails + 1
			if fails >= 5 and self.ticker then
				self.ticker:Cancel()
				self.ticker = nil
			end
		end
	end)
end

---------------------------------------------------------------------------
-- Hooks
---------------------------------------------------------------------------
function Chat:InstallHooks()
	local cf = _G.ChatFrame1
	if cf then
		-- FCF / Edit Mode may move the main window back; take it back afterwards.
		hooksecurefunc(cf, "SetPoint", function()
			if anchoring then return end
			C_Timer.After(0, function()
				CK:OutOfCombat("chat-anchor", function() safe(anchorChat) end)
			end)
		end)
	end

	hook("FCF_OpenNewWindow", relayout)
	hook("FCF_OpenTemporaryWindow", relayout)
	hook("FCF_DockFrame", relayout)
	hook("FCF_UnDockFrame", relayout)
	hook("FCF_Close", relayout)
	hook("FCF_SetChatWindowFontSize", function()
		eachFrame(function(f) safe(applyFont, f) end)
	end)
	hook("FCFTab_UpdateColors", function(tab)
		if tab and tab.ckFrame then refreshTab(tab.ckFrame) end
	end)
	hook("FCFDock_SelectWindow", function(_, frame)
		if frame then unread[frame] = nil end
		refreshAllTabs()
		if frame and frame.editBox then updateHeader(frame.editBox) end
	end)
	hook("FCF_StartAlertFlash", function(frame) markUnread(frame, false) end)
	if not (cf and cf.editBox and cf.editBox.UpdateHeader) then
		hook("ChatEdit_UpdateHeader", updateHeader)
	end

	-- URL clicks via Blizzard's "addon:" hyperlink routing
	if EventRegistry and EventRegistry.RegisterCallback then
		EventRegistry:RegisterCallback("SetItemRef", function(_, link) safe(onLink, link) end, self)
	else
		hook("SetItemRef", onLink)
	end
end

---------------------------------------------------------------------------
-- Settings and startup
---------------------------------------------------------------------------
function Chat:Start()
	if self.started then return end
	local other = conflict()
	if other then
		CK:Print(L["%s already manages the chat; the CasterKit chat stays off."]:format(other))
		return
	end
	self.started = true
	self:CreatePanel()
	self:InstallHooks()
	-- wrap AddMessage right away so the first lines are already formatted
	eachFrame(function(f) safe(wrapAddMessage, f) end)
	CK:OutOfCombat("chat", function() safe(self.Setup, self) end)
	safe(applyTimestamps)
	safe(applyClassColors)
	self:StartTicker()
	C_Timer.After(5, function() safe(self.MaybeAskSetup, self) end)
end

function Chat:OnSettings()
	local cfg = CK.char.chat
	if not self.started then
		if cfg.enabled then self:Start() end
		return
	end
	if not cfg.enabled then
		CK:Print(L["Turning the chat off takes effect after /reload."])
		return
	end
	relayout()
	safe(applyTimestamps)
	safe(applyClassColors)
	refreshAllTabs()
	self:MaybeAskSetup()
end

function Chat:OnEnable()
	CK:Listen("SETTINGS", function(group)
		if group == "chat" then safe(self.OnSettings, self) end
	end)
	local function later(fn, delay)
		return function()
			if not self.started then return end
			C_Timer.After(delay, function() CK:OutOfCombat("chat-" .. delay, function() safe(fn, self) end) end)
		end
	end
	CK:On("PLAYER_ENTERING_WORLD", later(self.Layout, 1))
	CK:On("UPDATE_CHAT_WINDOWS", later(self.Layout, 0.5))
	CK:On("UPDATE_FLOATING_CHAT_WINDOWS", later(self.Layout, 0.5))
	CK:On("CHANNEL_UI_UPDATE", later(self.CheckNewChannels, 2))

	if CK.char.chat.enabled then self:Start() end
end

-- For the settings menu: ask for the tab setup again.
function Chat:ResetTabSetup()
	CK.char.chat.setupDone = nil
	self:MaybeAskSetup()
end
