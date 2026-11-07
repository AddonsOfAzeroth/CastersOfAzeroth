-- CasterKit by DinX: skins
-- Gives Blizzard's windows the CasterKit look: flat dark panels, 1px borders and
-- the accent colour instead of the gold and stone frame art.
--
-- Visual only, written to stay out of taint:
--   * Blizzard regions are only faded (SetAlpha(0)). Blizzard frames are never
--     hidden, shown, moved, resized or reparented.
--   * Our look is drawn with our own textures (BACKGROUND -8/-7, under all of
--     Blizzard's art) and our own font strings. Our state lives in local weak
--     tables keyed by frame: no key is ever written into a Blizzard table.
--     (Our own textures get ignoreInLayout so layout frames skip them.)
--   * Only hooksecurefunc and HookScript, never replaced functions.
--   * Skinning runs out of combat, each frame once. Protected frames are skipped.
--   * Windows ElvUI already skins are left to ElvUI.
--   * Settings are read once at login: switching a skin off needs a /reload.
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style

local SK = CK:NewModule("Skins")

local IsLoaded = C_AddOns and C_AddOns.IsAddOnLoaded or IsAddOnLoaded

local AREAS = { "character", "spellbook", "quest", "merchant", "mail", "trainer", "friends", "menus", "popups", "other" }

local weak = { __mode = "k" }
local done = setmetatable({}, weak)    -- Blizzard object -> true once handled
local looks = setmetatable({}, weak)   -- Blizzard object -> our panel { fill, top, bottom, left, right }
local ours = setmetatable({}, weak)    -- our own textures / font strings
local tabs = setmetatable({}, weak)    -- skinned tabs
local hovered = setmetatable({}, weak) -- tab or button under the mouse
local closeText = setmetatable({}, weak) -- close button -> our "x"

local active = {}     -- area -> true, snapshot at login
local failed = {}     -- tag -> true after an error (never retried)
local reported = {}   -- tag -> true once the error was shown
local hooked = {}     -- one-time hooks by key
local started = false
local hinted = false

local FILL = { 0.04, 0.05, 0.08, 0.92 }       -- window
local INNER = { 0, 0, 0, 0.25 }               -- inset panels
local BUTTON = { 0.10, 0.12, 0.17, 1 }        -- buttons
local TAB = { 0.04, 0.05, 0.08, 0.90 }        -- tabs
local TAB_ON = { 0.10, 0.13, 0.18, 0.95 }     -- selected tab
local INPUT = { 0, 0, 0, 0.50 }               -- edit boxes
local TRACK = { 0, 0, 0, 0.35 }               -- scroll bar track
local BLACK = { 0, 0, 0, 1 }

---------------------------------------------------------------------------
-- Guards
---------------------------------------------------------------------------
-- pcall wrapper: the first error of a tag is reported once, after that the
-- tag is switched off so an error can never repeat.
local function guard(tag, fn, ...)
	if failed[tag] then return false end
	local ok, err = pcall(fn, ...)
	if not ok then
		failed[tag] = true
		if not reported[tag] then
			reported[tag] = true
			local handler = geterrorhandler and geterrorhandler()
			if handler then handler("CasterKit skins (" .. tostring(tag) .. "): " .. tostring(err)) end
		end
	end
	return ok
end

local function cfg()
	local c = CK.char and CK.char.skins
	if type(c) ~= "table" then return {} end
	return c
end

-- True when ElvUI skins this kind of window itself (then we stay out).
local function elvOwns(key)
	if not key or not (IsLoaded and IsLoaded("ElvUI")) then return false end
	local E = type(_G.ElvUI) == "table" and _G.ElvUI[1]
	local skins = type(E) == "table" and type(E.private) == "table" and E.private.skins
	local b = type(skins) == "table" and skins.blizzard
	if type(b) ~= "table" then return true end -- loaded but unknown: do not fight it
	return b.enable ~= false and b[key] ~= false
end

---------------------------------------------------------------------------
-- Small safe helpers
---------------------------------------------------------------------------
local function usable(obj)
	if type(obj) ~= "table" then return false end
	if obj.IsForbidden and obj:IsForbidden() then return false end
	return true
end

local function isType(obj, kind)
	return usable(obj) and obj.IsObjectType ~= nil and obj:IsObjectType(kind) and true or false
end

local function protected(frame)
	return frame.IsProtected ~= nil and (frame:IsProtected()) and true or false
end

-- frame.Key, or the global <FrameName><Key> (older templates name their parts).
local function get(frame, key)
	if not usable(frame) then return end
	local v = frame[key]
	if v == nil and frame.GetName then
		local name = frame:GetName()
		if name then v = _G[name .. key] end
	end
	if usable(v) then return v end
end

local function fade(obj)
	if usable(obj) and obj.SetAlpha and not ours[obj] then obj:SetAlpha(0) end
end

local function fadeKeys(frame, keys, keep)
	for _, k in ipairs(keys) do
		if not (keep and keep[k]) then fade(get(frame, k)) end
	end
end

-- Fades the frame's own textures (not those of its children).
local function fadeTextures(frame)
	if not (usable(frame) and frame.GetRegions) then return end
	for _, r in ipairs({ frame:GetRegions() }) do
		if not ours[r] and isType(r, "Texture") then r:SetAlpha(0) end
	end
end

local function pixel(frame)
	if PixelUtil and PixelUtil.GetNearestPixelSize and frame.GetEffectiveScale then
		local ok, v = pcall(PixelUtil.GetNearestPixelSize, 1, frame:GetEffectiveScale(), 1)
		if ok and type(v) == "number" and v > 0 then return v end
	end
	return 1
end

---------------------------------------------------------------------------
-- Our panel: a flat fill with a 1px border, drawn as our own textures on the
-- BACKGROUND layer (sublevels -8/-7), so every Blizzard region stays on top.
---------------------------------------------------------------------------
local function tex(frame, sub)
	local t = frame:CreateTexture(nil, "BACKGROUND", nil, sub)
	t:SetColorTexture(1, 1, 1, 1)
	t.ignoreInLayout = true -- our own object: layout frames must not size around it
	ours[t] = true
	return t
end

local function setLook(p, fill, border)
	if not p then return end
	if fill then p.fill:SetVertexColor(fill[1], fill[2], fill[3], fill[4] or 1) end
	if border then
		local r, g, b, a = border[1], border[2], border[3], border[4] or 1
		p.top:SetVertexColor(r, g, b, a)
		p.bottom:SetVertexColor(r, g, b, a)
		p.left:SetVertexColor(r, g, b, a)
		p.right:SetVertexColor(r, g, b, a)
	end
end

-- inset = { left, top, right, bottom } offsets from the frame's edges.
local function panel(frame, fill, border, inset)
	if looks[frame] then return looks[frame] end
	local l, t, r, b = 0, 0, 0, 0
	if inset then l, t, r, b = inset[1] or 0, inset[2] or 0, inset[3] or 0, inset[4] or 0 end
	local px = pixel(frame)
	local p = {}
	p.fill = tex(frame, -8)
	p.fill:SetPoint("TOPLEFT", frame, "TOPLEFT", l, t)
	p.fill:SetPoint("BOTTOMRIGHT", frame, "BOTTOMRIGHT", r, b)
	p.top = tex(frame, -7)
	p.top:SetPoint("TOPLEFT", p.fill, "TOPLEFT")
	p.top:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT")
	p.top:SetHeight(px)
	p.bottom = tex(frame, -7)
	p.bottom:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT")
	p.bottom:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT")
	p.bottom:SetHeight(px)
	p.left = tex(frame, -7)
	p.left:SetPoint("TOPLEFT", p.fill, "TOPLEFT")
	p.left:SetPoint("BOTTOMLEFT", p.fill, "BOTTOMLEFT")
	p.left:SetWidth(px)
	p.right = tex(frame, -7)
	p.right:SetPoint("TOPRIGHT", p.fill, "TOPRIGHT")
	p.right:SetPoint("BOTTOMRIGHT", p.fill, "BOTTOMRIGHT")
	p.right:SetWidth(px)
	looks[frame] = p
	setLook(p, fill or FILL, border or BLACK)
	return p
end

local function accent(alpha)
	local a = S.colors.accent
	return { a[1], a[2], a[3], alpha or 1 }
end

local function edge()
	local e = S.colors.edge
	return { e[1], e[2], e[3], 1 }
end

---------------------------------------------------------------------------
-- Hover (HookScript only)
---------------------------------------------------------------------------
local paintTab -- forward

local function hoverOn(self)
	hovered[self] = true
	if tabs[self] then paintTab(self) return end
	local p = looks[self]
	if p then setLook(p, nil, accent()) end
	local x = closeText[self]
	if x then local a = S.colors.accent; x:SetTextColor(a[1], a[2], a[3]) end
end

local function hoverOff(self)
	hovered[self] = nil
	if tabs[self] then paintTab(self) return end
	local p = looks[self]
	if p then setLook(p, nil, BLACK) end
	local x = closeText[self]
	if x then local c = S.colors.text; x:SetTextColor(c[1], c[2], c[3]) end
end

local function hookHover(btn)
	btn:HookScript("OnEnter", function(b) guard("hover", hoverOn, b) end)
	btn:HookScript("OnLeave", function(b) guard("hover", hoverOff, b) end)
end

---------------------------------------------------------------------------
-- Building blocks
---------------------------------------------------------------------------
local FRAME_ART = {
	"NineSlice", "Bg", "TitleBg", "TopTileStreaks", "Portrait", "portrait", "PortraitContainer",
	"PortraitFrame", "PortraitOverlay", "ArtOverlayFrame", "BorderTexture", "Border",
	-- pre-NineSlice ButtonFrameTemplate pieces (named $parentX)
	"TopLeftCorner", "TopRightCorner", "TopBorder", "BotLeftCorner", "BotRightCorner", "BottomBorder",
	"LeftBorder", "RightBorder", "BtnCornerLeft", "BtnCornerRight", "ButtonBottomBorder",
}
local INSET_KEYS = { "Inset", "LeftInset", "RightInset", "InsetFrame", "BottomInset", "bottomInset", "InsetRight" }
local INSET_ART = {
	"NineSlice", "Bg", "InsetBorderTop", "InsetBorderTopLeft", "InsetBorderTopRight", "InsetBorderBottom",
	"InsetBorderBottomLeft", "InsetBorderBottomRight", "InsetBorderLeft", "InsetBorderRight",
}
local BUTTON_ART = { "Left", "Middle", "Right", "Center", "Mid" }

local function skinInset(inset, plain)
	if not usable(inset) or done[inset] then return end
	done[inset] = true
	fadeKeys(inset, INSET_ART)
	if not plain then panel(inset, INNER, edge()) end
end

local function skinTitle(frame)
	local fs = get(frame, "TitleText")
	local tc = get(frame, "TitleContainer")
	if not fs and tc then fs = get(tc, "TitleText") end
	if not fs and type(frame.GetTitleText) == "function" then
		local ok, v = pcall(frame.GetTitleText, frame)
		if ok then fs = v end
	end
	if isType(fs, "FontString") then
		local c = S.colors.text
		fs:SetTextColor(c[1], c[2], c[3])
	end
end

local function skinClose(btn)
	if not isType(btn, "Button") or done[btn] or protected(btn) then return end
	done[btn] = true
	for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetHighlightTexture", "GetDisabledTexture" }) do
		if type(btn[getter]) == "function" then fade(btn[getter](btn)) end
	end
	local w, h = btn:GetWidth() or 0, btn:GetHeight() or 0
	local px, py = math.max(0, (w - 16) / 2), math.max(0, (h - 16) / 2)
	panel(btn, { 0.10, 0.12, 0.17, 0.95 }, BLACK, { px, -py, -px, py })
	local x = btn:CreateFontString(nil, "OVERLAY")
	x:SetFont(S.font, 12, "OUTLINE")
	x:SetPoint("CENTER", btn, "CENTER", 0.5, 1)
	x:SetText("x")
	local c = S.colors.text
	x:SetTextColor(c[1], c[2], c[3])
	ours[x] = true
	closeText[btn] = x
	hookHover(btn)
end

local function looksLikeTab(btn)
	return get(btn, "LeftActive") ~= nil or get(btn, "LeftDisabled") ~= nil or get(btn, "LeftHighlight") ~= nil
end

local function looksLikePanelButton(btn)
	if not isType(btn, "Button") or isType(btn, "CheckButton") then return false end
	if looksLikeTab(btn) then return false end
	if not (isType(get(btn, "Left"), "Texture") and isType(get(btn, "Right"), "Texture")) then return false end
	return btn.GetFontString ~= nil and btn:GetFontString() ~= nil
end

local function skinButton(btn)
	if not isType(btn, "Button") or done[btn] or protected(btn) then return end
	done[btn] = true
	fadeKeys(btn, BUTTON_ART)
	if not get(btn, "Left") then
		-- templates without a three-slice: the art is the normal/pushed/disabled texture
		for _, getter in ipairs({ "GetNormalTexture", "GetPushedTexture", "GetDisabledTexture" }) do
			if type(btn[getter]) == "function" then fade(btn[getter](btn)) end
		end
	end
	if type(btn.GetHighlightTexture) == "function" then fade(btn:GetHighlightTexture()) end
	panel(btn, BUTTON, BLACK)
	hookHover(btn)
end

local function looksLikeInput(eb)
	return isType(eb, "EditBox") and isType(get(eb, "Left"), "Texture") and isType(get(eb, "Right"), "Texture")
end

local function skinInput(eb)
	if not isType(eb, "EditBox") or done[eb] or protected(eb) then return end
	done[eb] = true
	fadeKeys(eb, BUTTON_ART)
	-- InputBoxTemplate draws its art about 5px left of the text area
	panel(eb, INPUT, BLACK, { -5, 0, 0, 0 })
end

local function looksLikeScrollBar(f)
	return get(f, "Track") ~= nil and (get(f, "Back") ~= nil or get(f, "Forward") ~= nil or get(f, "Background") ~= nil)
end

-- Modern ScrollBox scroll bars: only the track art goes, thumb and arrows stay.
local function skinScrollBar(sb)
	if not usable(sb) or done[sb] or protected(sb) then return end
	done[sb] = true
	fade(get(sb, "Background"))
	local track = get(sb, "Track")
	if track then
		fadeTextures(track)
		panel(track, TRACK, BLACK)
	end
end

local function isCloseButton(c, parent)
	if get(parent, "CloseButton") == c then return true end
	local name = c.GetName and c:GetName()
	return type(name) == "string" and name:find("CloseButton$") ~= nil
end

-- Walks a frame's children and skins the standard pieces it recognises.
-- Protected frames and their children are left alone.
local function walk(frame, depth)
	depth = depth or 0
	if depth > 7 or not usable(frame) or not frame.GetChildren then return end
	for _, c in ipairs({ frame:GetChildren() }) do
		if usable(c) and not protected(c) then
			if looksLikePanelButton(c) then
				skinButton(c)
			elseif looksLikeInput(c) then
				skinInput(c)
				walk(c, depth + 1)
			elseif looksLikeScrollBar(c) then
				skinScrollBar(c)
			elseif isType(c, "Button") and isCloseButton(c, frame) then
				skinClose(c)
			else
				walk(c, depth + 1)
			end
		end
	end
end

---------------------------------------------------------------------------
-- Tabs (PanelTemplates bottom tabs and TabSystem top tabs)
---------------------------------------------------------------------------
local function tabSelected(tab)
	if tab.isSelected ~= nil then return tab.isSelected and true or false end -- TabSystem
	local la = get(tab, "LeftActive")
	if la and la.IsShown then return la:IsShown() and true or false end   -- modern PanelTemplates
	if tab.IsEnabled then return not tab:IsEnabled() end                   -- classic: selected = disabled
	return false
end

paintTab = function(tab)
	local p = looks[tab]
	if not p then return end
	fadeTextures(tab) -- Blizzard swaps the tab art on (de)selection: keep it faded
	if tabSelected(tab) then
		setLook(p, TAB_ON, accent())
	elseif hovered[tab] then
		setLook(p, TAB, accent(0.6))
	else
		setLook(p, TAB, BLACK)
	end
end

local function paintAllTabs()
	for tab in pairs(tabs) do
		if usable(tab) then paintTab(tab) end
	end
end

local function paintAllSoon()
	if C_Timer and C_Timer.After then
		C_Timer.After(0, function() guard("tabs", paintAllTabs) end)
	else
		guard("tabs", paintAllTabs)
	end
end

local function skinTab(tab)
	if not isType(tab, "Button") or done[tab] or protected(tab) then return end
	if get(tab, "Icon") or get(tab, "icon") then return end -- side tabs with an icon stay Blizzard's
	if not (tab.GetFontString and tab:GetFontString()) and not get(tab, "Text") then return end
	done[tab] = true
	tabs[tab] = true
	panel(tab, TAB, BLACK, { 3, -1, -3, 3 })
	hookHover(tab)
	tab:HookScript("OnClick", function() paintAllSoon() end)
	tab:HookScript("OnShow", function() paintAllSoon() end)
	paintTab(tab)
end

local function skinTabsOf(frame)
	if not usable(frame) then return end
	local name = frame.GetName and frame:GetName()
	if name then
		for i = 1, 12 do
			local t = _G[name .. "Tab" .. i]
			if not t then break end
			skinTab(t)
		end
	end
	if type(frame.Tabs) == "table" then
		for _, t in ipairs(frame.Tabs) do skinTab(t) end
	end
	local ts = get(frame, "TabSystem")
	if ts and ts.GetChildren then
		for _, t in ipairs({ ts:GetChildren() }) do skinTab(t) end
	end
end

local function hookTabTemplates()
	if hooked.tabs then return end
	hooked.tabs = true
	for _, fn in ipairs({ "PanelTemplates_SelectTab", "PanelTemplates_DeselectTab", "PanelTemplates_UpdateTabs", "PanelTemplates_SetTab" }) do
		if type(_G[fn]) == "function" then hooksecurefunc(fn, paintAllSoon) end
	end
end

---------------------------------------------------------------------------
-- Windows
---------------------------------------------------------------------------
-- Generic window (PortraitFrameTemplate / ButtonFrameTemplate and friends).
-- opts: keep = { Key = true } art to leave alone, plainInsets, inset, fill, noClose.
-- Returns true the first time, so callers can do their extra work once.
local function skinWindow(frame, opts)
	if not usable(frame) or done[frame] or protected(frame) then return false end
	done[frame] = true
	opts = opts or {}
	fadeKeys(frame, FRAME_ART, opts.keep)
	for _, k in ipairs(INSET_KEYS) do skinInset(get(frame, k), opts.plainInsets) end
	panel(frame, opts.fill or FILL, BLACK, opts.inset)
	skinTitle(frame)
	if not opts.noClose then
		local close = get(frame, "CloseButton")
		if close then skinClose(close) end
	end
	return true
end

local function window(frame, opts)
	if skinWindow(frame, opts) then
		skinTabsOf(frame)
		walk(frame)
		return true
	end
	return false
end

---------------------------------------------------------------------------
-- Areas
---------------------------------------------------------------------------
local function skinCharacter()
	local cf = _G.CharacterFrame
	if skinWindow(cf) then
		skinTabsOf(cf)
		-- Forever: two panes, the right one with a stone background
		local lp, rp = get(cf, "LeftPaneHost"), get(cf, "RightPaneHost")
		if lp then fadeTextures(lp) end
		if rp then
			fadeTextures(rp)
			fade(get(rp, "StoneBg"))
			panel(rp, INNER, edge(), { 6, -6, -6, 6 })
		end
		walk(cf)
	end
	-- small dialogs of the reputation / currency tabs
	local rep = _G.ReputationFrame
	window(_G.ReputationDetailFrame or get(rep, "ReputationDetailFrame"))
	local token = _G.TokenFrame
	window(_G.TokenFramePopup or get(token, "Popup"))
end

local function skinSpellbook()
	local psf = _G.PlayerSpellsFrame
	if skinWindow(psf) then
		skinTabsOf(psf)
		local tf = get(psf, "TalentsFrame")
		if tf then
			fadeKeys(tf, { "Background", "BackgroundBorder", "DividerHorizontalLeft", "DividerHorizontalRight",
				"DividerVerticalLeft", "DividerVerticalRight", "BlackBG", "BottomBar" })
			skinTabsOf(tf)
			local cd = get(tf, "ClassCurrencyDisplay")
			if cd then fade(get(cd, "Border")) end
		end
		local sb = get(psf, "SpellBookFrame")
		if sb then
			done[sb] = true -- handled here, not as a window of its own
			fadeKeys(sb, { "TopBar", "BookCornerFlipbook" })
		end
		walk(psf) -- spell buttons are protected and skipped
	end
	-- older layouts, if this client has them instead
	local legacy = { inset = { 11, -12, -32, 76 } }
	if not psf then
		local book = _G.SpellBookFrame
		if skinWindow(book, legacy) then
			if not get(book, "NineSlice") then fadeTextures(book) end
			skinTabsOf(book)
			for i = 1, 8 do skinTab(_G["SpellBookFrameTabButton" .. i]) end
			walk(book)
		end
	end
	for _, name in ipairs({ "PlayerTalentFrame", "TalentFrame", "ClassTalentFrame" }) do
		local f = _G[name]
		if f and f ~= psf and skinWindow(f, not get(f, "NineSlice") and legacy or nil) then
			if not get(f, "NineSlice") then fadeTextures(f) end
			skinTabsOf(f)
			walk(f)
		end
	end
end

local function skinQuest()
	-- the parchment inside these windows stays: their text is dark
	window(_G.QuestFrame, { plainInsets = true })
	window(_G.QuestLogPopupDetailFrame, { keep = { Bg = true }, plainInsets = true })
	if not elvOwns("gossip") then
		window(_G.GossipFrame, { plainInsets = true })
		window(_G.ItemTextFrame, { plainInsets = true })
	end
end

local function skinMerchant()
	local mf = _G.MerchantFrame
	if skinWindow(mf) then
		skinTabsOf(mf)
		skinInset(_G.MerchantMoneyInset)
		skinInset(_G.MerchantExtraCurrencyInset)
		fade(_G.MerchantMoneyBg)
		fade(_G.MerchantExtraCurrencyBg)
		for i = 1, 12 do
			local item = _G["MerchantItem" .. i]
			if usable(item) then
				fade(_G["MerchantItem" .. i .. "SlotTexture"])
				fade(_G["MerchantItem" .. i .. "NameFrame"])
				panel(item, INNER, edge())
			end
		end
		local bb = _G.MerchantBuyBackItem
		if usable(bb) then
			fade(_G.MerchantBuyBackItemSlotTexture)
			fade(_G.MerchantBuyBackItemNameFrame)
			panel(bb, INNER, edge())
		end
		walk(mf)
	end
end

local function skinMail()
	local mf = _G.MailFrame
	if skinWindow(mf) then
		skinTabsOf(mf)
		walk(mf)
	end
	local inbox = _G.InboxFrame
	if usable(inbox) and not done[inbox] then
		done[inbox] = true
		fadeTextures(inbox)
	end
	-- send mail: stationery stays (dark text), only the money box art goes
	fade(_G.SendMailMoneyBg)
	skinInset(_G.SendMailMoneyInset, true)
	window(_G.OpenMailFrame, { plainInsets = true })
end

local function skinTrainer()
	window(_G.ClassTrainerFrame)
end

local function skinFriends()
	local ff = _G.FriendsFrame
	if skinWindow(ff) then
		skinTabsOf(ff)
		skinTabsOf(_G.FriendsTabHeader)
		walk(ff)
	end
	window(_G.WhoFrame)          -- a FriendsFrame child on most clients, not on Forever
	window(_G.ChannelFrame)
	window(_G.RaidInfoFrame)
end

local function skinGameMenuButtons()
	local gm = _G.GameMenuFrame
	if not usable(gm) then return end
	local pool = gm.buttonPool
	if type(pool) == "table" and type(pool.EnumerateActive) == "function" then
		for b in pool:EnumerateActive() do skinButton(b) end
	end
	walk(gm) -- older clients: named buttons
end

local function skinMenus()
	if not elvOwns("misc") then
		local gm = _G.GameMenuFrame
		if usable(gm) and not done[gm] and not protected(gm) then
			done[gm] = true
			fadeTextures(gm)
			fadeKeys(gm, { "Border", "NineSlice", "Bg" })
			local header = get(gm, "Header")
			if header then fadeTextures(header) end
			panel(gm, FILL, BLACK)
			gm:HookScript("OnShow", function()
				CK:OutOfCombat("skins-gamemenu", function() guard("menus-buttons", skinGameMenuButtons) end)
			end)
			skinGameMenuButtons()
		end
	end
	if not elvOwns("addonManager") then
		window(_G.AddonList)
	end
	if not elvOwns("blizzardOptions") then
		-- light touch: the settings panel is taint-sensitive, so only its frame art
		local sp = _G.SettingsPanel
		if usable(sp) and not done[sp] and not protected(sp) then
			done[sp] = true
			fadeKeys(sp, { "NineSlice", "Bg" })
			panel(sp, { 0.04, 0.05, 0.08, 0.96 }, BLACK)
			skinTitle(sp)
		end
	end
end

local function skinPopup(p)
	if not usable(p) or done[p] or protected(p) then return end
	done[p] = true
	fadeKeys(p, { "Border", "BG", "Bg", "NineSlice", "Background" })
	panel(p, { 0.04, 0.05, 0.08, 0.95 }, BLACK)
	local container = get(p, "ButtonContainer")
	for i = 1, 4 do
		local b = get(p, "button" .. i) or get(p, "Button" .. i) or (container and get(container, "Button" .. i))
		if b then skinButton(b) end
	end
	local extra = get(p, "extraButton") or get(p, "ExtraButton")
	if extra then skinButton(extra) end
	local eb = get(p, "editBox") or get(p, "EditBox")
	if looksLikeInput(eb) then skinInput(eb) end
	local close = get(p, "CloseButton")
	if close then skinClose(close) end
end

local function skinPopups()
	for i = 1, 4 do skinPopup(_G["StaticPopup" .. i]) end
end

local function skinOther()
	if not elvOwns("dressingroom") then window(_G.DressUpFrame) end
	if not elvOwns("bags") then window(_G.BankFrame) end
	if not elvOwns("trade") then
		local tf = _G.TradeFrame
		if window(tf) then
			fade(_G.TradeFramePlayerPortrait)
			fade(_G.TradeFrameRecipientPortrait)
			fade(_G.TradeRecipientMoneyBg)
			for _, n in ipairs({ "TradePlayerItemsInset", "TradeRecipientItemsInset", "TradePlayerEnchantInset",
				"TradeRecipientEnchantInset", "TradePlayerInputMoneyInset", "TradeRecipientMoneyInset" }) do
				skinInset(_G[n])
			end
		end
	end
	if not elvOwns("loot") then window(_G.GroupLootHistoryFrame) end
	if not elvOwns("lfg") then
		window(_G.PVEFrame)
		window(_G.LFGParentFrame)
		-- Forever's group finder: listing, browse and who list are portrait frames inside it
		local sub = { fill = { 0, 0, 0, 0.30 }, noClose = true }
		window(_G.LFGListingFrame, sub)
		window(_G.LFGBrowseFrame, sub)
		window(_G.LFGWhoListFrame, sub)
	end
end

-- area, ElvUI skin key (nil = checked inside), function
local STEPS = {
	{ "character", "character", skinCharacter },
	{ "spellbook", "talent", skinSpellbook },
	{ "quest", "quest", skinQuest },
	{ "merchant", "merchant", skinMerchant },
	{ "mail", "mail", skinMail },
	{ "trainer", "trainer", skinTrainer },
	{ "friends", "friends", skinFriends },
	{ "menus", nil, skinMenus },
	{ "popups", "misc", skinPopups },
	{ "other", nil, skinOther },
}

local function tryAll()
	if not started then return end
	for _, step in ipairs(STEPS) do
		local area, elvKey, fn = step[1], step[2], step[3]
		if active[area] and not elvOwns(elvKey) then guard(area, fn) end
	end
end

local function trySoon()
	if started then CK:OutOfCombat("skins", function() guard("skins", tryAll) end) end
end

---------------------------------------------------------------------------
-- Module
---------------------------------------------------------------------------
local function enable()
	local c = cfg()
	if c.enabled == false then return end
	local any = false
	for _, area in ipairs(AREAS) do
		active[area] = c[area] ~= false
		any = any or active[area]
	end
	if not any then return end
	started = true
	hookTabTemplates()
	-- windows that are created or loaded later
	if not hooked.show and type(_G.ShowUIPanel) == "function" then
		hooked.show = true
		hooksecurefunc("ShowUIPanel", trySoon)
	end
	trySoon()
end

function SK:OnEnable()
	guard("enable", enable)
end

-- Load-on-demand Blizzard UIs (trainer, talents, mail…): skin them once loaded.
CK:On("ADDON_LOADED", function() trySoon() end)

CK:Listen("SETTINGS", function(group)
	if group == "skins" and not hinted then
		hinted = true
		CK:Print(L["Skin changes apply after a reload (/reload)."])
	end
end)

-- True when ElvUI's own Blizzard skins are on (used by the settings page).
function SK:ElvUIActive()
	return elvOwns("character") or elvOwns("misc")
end
