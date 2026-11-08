-- Casters of Azeroth by DinX: settings window and minimap button
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style

local C = CK:NewModule("Config")

---------------------------------------------------------------------------
-- Widgets (flat, in Casters of Azeroth style)
---------------------------------------------------------------------------
local function changed(group)
	CK:Fire("SETTINGS", group)
	if C.frame and C.frame:IsShown() then C:Refresh() end
end

local function tooltip(frame, text)
	if not text then return end
	frame:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
		GameTooltip:AddLine(text, 1, 1, 1, true)
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", GameTooltip_Hide)
end

local Page = {}
Page.__index = Page

function Page:Header(text)
	local fs = S:Font(self.frame, 14)
	fs:SetPoint("TOPLEFT", 0, self.y)
	fs:SetText(text)
	fs:SetTextColor(unpack(S.colors.accent))
	self.y = self.y - 24
end

function Page:Note(text)
	local fs = self.frame:CreateFontString(nil, "OVERLAY")
	fs:SetFont(S.font, 11, "")
	fs:SetTextColor(unpack(S.colors.muted))
	fs:SetPoint("TOPLEFT", 0, self.y)
	fs:SetWidth(430)
	fs:SetJustifyH("LEFT")
	fs:SetText(text)
	self.y = self.y - math.max(16, fs:GetStringHeight() + 6)
	return fs
end

function Page:Check(label, tip, get, set)
	local b = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
	b:SetSize(16, 16)
	b:SetPoint("TOPLEFT", 0, self.y)
	S:Backdrop(b, 1)
	local mark = b:CreateTexture(nil, "OVERLAY")
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	mark:SetColorTexture(unpack(S.colors.accent))
	local fs = S:Font(b, 12)
	fs:SetPoint("LEFT", b, "RIGHT", 8, 0)
	fs:SetText(label)
	b:SetHitRectInsets(0, -fs:GetStringWidth() - 10, 0, 0)
	b.refresh = function() mark:SetShown(get() and true or false) end
	b:SetScript("OnClick", function() set(not get()); b.refresh() end)
	tooltip(b, tip)
	table.insert(self.widgets, b)
	self.y = self.y - 24
	return b
end

function Page:Slider(label, minV, maxV, step, get, set, fmt)
	local fs = S:Font(self.frame, 12)
	fs:SetPoint("TOPLEFT", 0, self.y)
	local s = CreateFrame("Slider", nil, self.frame, "BackdropTemplate")
	s:SetOrientation("HORIZONTAL")
	s:SetSize(220, 10)
	s:SetPoint("TOPLEFT", 200, self.y - 2)
	S:Backdrop(s, 1)
	s:SetThumbTexture(S.flat)
	local thumb = s:GetThumbTexture()
	thumb:SetSize(10, 14)
	thumb:SetVertexColor(unpack(S.colors.accent))
	s:SetMinMaxValues(minV, maxV)
	s:SetValueStep(step)
	s:SetObeyStepOnDrag(true)
	local val = S:Font(self.frame, 12)
	val:SetPoint("LEFT", s, "RIGHT", 10, 0)
	local function show(v) val:SetText(fmt and fmt(v) or tostring(v)); fs:SetText(label) end
	s.refresh = function()
		s.updating = true
		s:SetValue(get())
		show(get())
		s.updating = false
	end
	s:SetScript("OnValueChanged", function(_, v)
		if s.updating then return end
		v = math.floor(v / step + 0.5) * step
		show(v)
		set(v)
	end)
	table.insert(self.widgets, s)
	self.y = self.y - 28
	return s
end

-- Cycling choice: ◀ value ▶ (options may be a function returning the list)
function Page:Choice(label, opts, get, set)
	local options = opts
	local fs = S:Font(self.frame, 12)
	fs:SetPoint("TOPLEFT", 0, self.y)
	fs:SetText(label)
	local holder = CreateFrame("Frame", nil, self.frame, "BackdropTemplate")
	holder:SetSize(220, 20)
	holder:SetPoint("TOPLEFT", 200, self.y + 3)
	S:Backdrop(holder, 1)
	local text = S:Font(holder, 12)
	text:SetPoint("CENTER")
	local function step(dir)
		if type(opts) == "function" then options = opts() end
		if #options == 0 then return end
		local cur = get()
		local idx = 1
		for i, o in ipairs(options) do if o[1] == cur then idx = i end end
		idx = (idx - 1 + dir) % #options + 1
		set(options[idx][1])
		holder.refresh()
	end
	for _, d in ipairs({ { -1, "LEFT", "<" }, { 1, "RIGHT", ">" } }) do
		local a = CreateFrame("Button", nil, holder)
		a:SetSize(20, 20)
		a:SetPoint(d[2])
		local t = S:Font(a, 13)
		t:SetPoint("CENTER")
		t:SetText(d[3])
		t:SetTextColor(unpack(S.colors.accent))
		a:SetScript("OnClick", function() step(d[1]) end)
	end
	holder.refresh = function()
		if type(opts) == "function" then options = opts() end
		local cur = get()
		text:SetText("-")
		for _, o in ipairs(options) do if o[1] == cur then text:SetText(o[2]) end end
	end
	table.insert(self.widgets, holder)
	self.y = self.y - 28
	return holder
end

function Page:Button(label, onClick, width)
	local b = CreateFrame("Button", nil, self.frame, "BackdropTemplate")
	b:SetSize(width or 160, 22)
	b:SetPoint("TOPLEFT", 0, self.y)
	S:Backdrop(b, 1)
	local t = S:Font(b, 12)
	t:SetPoint("CENTER")
	t:SetText(label)
	b:SetScript("OnEnter", function() b:SetBackdropBorderColor(unpack(S.colors.accent)) end)
	b:SetScript("OnLeave", function() b:SetBackdropBorderColor(0, 0, 0, 1) end)
	b:SetScript("OnClick", onClick)
	self.y = self.y - 30
	return b
end

function Page:Edit(label, width)
	local fs = S:Font(self.frame, 12)
	fs:SetPoint("TOPLEFT", 0, self.y)
	fs:SetText(label)
	local e = CreateFrame("EditBox", nil, self.frame, "BackdropTemplate")
	e:SetSize(width or 220, 20)
	e:SetPoint("TOPLEFT", 200, self.y + 3)
	S:Backdrop(e, 1)
	e:SetFont(S.font, 12, "")
	e:SetTextInsets(6, 6, 0, 0)
	e:SetAutoFocus(false)
	e:SetMaxLetters(32)
	e:SetScript("OnEscapePressed", e.ClearFocus)
	e:SetScript("OnEnterPressed", e.ClearFocus)
	self.y = self.y - 28
	return e
end

-- Button placed next to the previous row instead of below it.
function Page:ButtonRight(label, onClick, x, width)
	local b = self:Button(label, onClick, width)
	self.y = self.y + 30
	b:ClearAllPoints()
	b:SetPoint("TOPLEFT", x, self.y)
	self.y = self.y - 30
	return b
end

function Page:Gap(h) self.y = self.y - (h or 8) end

---------------------------------------------------------------------------
-- Window
---------------------------------------------------------------------------
local function setting(group, key)
	return function() return CK.char[group][key] end,
		function(v) CK.char[group][key] = v; changed(group) end
end

function C:CreateWindow()
	local f = CreateFrame("Frame", "CasterKitConfig", UIParent, "BackdropTemplate")
	f:SetSize(680, 600)
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
	tinsert(UISpecialFrames, "CasterKitConfig")

	local bar = f:CreateTexture(nil, "ARTWORK")
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("TOPRIGHT", -1, -1)
	bar:SetHeight(28)
	bar:SetColorTexture(0.08, 0.10, 0.14, 1)
	local title = S:Font(f, 14)
	title:SetPoint("TOPLEFT", 12, -8)
	title:SetText(("|cff69ccf0CasterKit|r  |cff999999v%s|r"):format(CK.version))

	local close = CreateFrame("Button", nil, f)
	close:SetSize(28, 28)
	close:SetPoint("TOPRIGHT", 0, 0)
	local x = S:Font(close, 16)
	x:SetPoint("CENTER")
	x:SetText("X")
	close:SetScript("OnClick", function() f:Hide() end)

	local nav = CreateFrame("Frame", nil, f, "BackdropTemplate")
	nav:SetPoint("TOPLEFT", 1, -29)
	nav:SetPoint("BOTTOMLEFT", 1, 1)
	nav:SetWidth(140)
	nav:SetBackdrop({ bgFile = S.flat })
	nav:SetBackdropColor(0.06, 0.07, 0.10, 1)

	self.frame = f
	self.pages = {}
	self.tabs = {}

	local function newPage(key, label)
		local container = CreateFrame("Frame", nil, f)
		container:SetPoint("TOPLEFT", 164, -44)
		container:SetPoint("BOTTOMRIGHT", -16, 16)
		container:Hide()
		local page = setmetatable({ frame = container, y = 0, widgets = {} }, Page)
		self.pages[key] = page

		local tab = CreateFrame("Button", nil, nav)
		tab:SetSize(138, 26)
		tab:SetPoint("TOPLEFT", 1, -8 - (#self.tabs) * 28)
		local hl = tab:CreateTexture(nil, "BACKGROUND")
		hl:SetAllPoints()
		hl:SetColorTexture(0.41, 0.80, 0.94, 0.18)
		hl:Hide()
		local t = S:Font(tab, 12)
		t:SetPoint("LEFT", 12, 0)
		t:SetText(label)
		tab.hl = hl
		tab:SetScript("OnClick", function() self:Show(key) end)
		tab.key = key
		table.insert(self.tabs, tab)
		return page
	end

	self:BuildGeneral(newPage("general", L["General"]))
	self:BuildBars(newPage("bars", L["Action bars"]))
	self:BuildMicro(newPage("micro", L["Micro menu"]))
	self:BuildBags(newPage("bags", L["Bags"]))
	self:BuildUnits(newPage("units", "Frames"))
	self:BuildRotation(newPage("rotation", L["Rotation"]))
	self:BuildLeveling(newPage("leveling", L["Leveling"]))
	self:BuildMap(newPage("map", L["Map"]))
	self:BuildSkins(newPage("skins", L["Skins"]))
	self:BuildChat(newPage("chat", L["Chat"]))
	self:BuildLoot(newPage("loot", L["Loot"]))
	-- pages from optional add-ons: CK.configPages = { { key, label, build = function(page) end } }
	if type(CK.configPages) == "table" then
		for _, def in ipairs(CK.configPages) do
			if type(def) == "table" and type(def.key) == "string" and type(def.build) == "function" and not self.pages[def.key] then
				local ok, err = pcall(def.build, newPage(def.key, def.label or def.key))
				if not ok and CK.debug then CK:Print("config page " .. def.key .. ":", tostring(err)) end
			end
		end
	end
	self:BuildProfiles(newPage("profiles", L["Profiles"]))
	self:BuildAbout(newPage("about", L["About"]))
end

function C:Show(key)
	for k, page in pairs(self.pages) do page.frame:SetShown(k == key) end
	for _, tab in ipairs(self.tabs) do tab.hl:SetShown(tab.key == key) end
	self.currentPage = key
	self:Refresh()
end

function C:Refresh()
	for _, page in pairs(self.pages) do
		for _, w in ipairs(page.widgets) do if w.refresh then w.refresh() end end
	end
	if self.conflictNote then
		local c = CK:BarConflict()
		self.conflictNote:SetText(c and L["|cffff5050%s currently manages the action bars.|r Disable it to use the Casters of Azeroth bars; meanwhile the rotation helper works on those buttons."]:format(c) or L["No other action bar addon active."])
	end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function C:BuildGeneral(p)
	p:Header(L["General"])
	p:Check(L["Frames locked"], L["Turn off to drag the bars, hint box, frames and micro menu."],
		function() return CK.char.bars.locked end,
		function(v) CK.char.bars.locked = v; changed("bars"); changed("micro") end)
	p:Check(L["Show minimap button"], nil,
		function() return not CK.db.minimap.hide end,
		function(v) CK.db.minimap.hide = not v; C:UpdateMinimapButton() end)
	p:Choice(L["Language"], CK.languages,
		function() return CK.db.language end,
		function(v) CK.db.language = v end)
	p:Note(L["Reload the UI to apply the language everywhere."])
	p:Choice(L["Font"], { { "roboto", "Roboto" }, { "wow", L["Game font"] } },
		function() return CK.db.font end,
		function(v) CK.db.font = v end)
	p:Check(L["Thick outline on text"], L["Off: clean text with a soft shadow, easier to read."],
		function() return CK.db.fontOutline end,
		function(v) CK.db.fontOutline = v end)
	p:Note(L["Reload the UI to apply the font."])
	p:Gap()
	p:Header("Spec")
	local def = CK:GetClass()
	if def then
		local opts = {}
		for _, key in ipairs(def.specOrder) do opts[#opts + 1] = { key, def.specs[key].name } end
		p:Choice(L["Rotation for"], opts,
			function() local _, k = CK:GetSpec(); return k end,
			function(v) CK.char.rotation.spec = v; changed("rotation") end)
	else
		p:Note(L["There is no rotation for your class yet. Bars and leveling helpers still work."])
	end
	p:Gap()
	p:Header(L["Start over"])
	p:Button(L["Reset positions"], function()
		CK:OutOfCombat("reset", function()
			CK.char.bars.point = CK.CopyTable(CK.charDefaults.bars.point)
			CK.char.micro.point = CK.CopyTable(CK.charDefaults.micro.point)
			CK.char.rotation.point = nil
			S:ResetMovers()
			changed("bars"); changed("micro"); changed("rotation"); changed("units"); changed("chat")
		end)
	end)
	p:Button(L["Reload UI"], ReloadUI)
end

function C:BuildBars(p)
	p:Header(L["Action bars"])
	self.conflictNote = p:Note("")
	p:Check(L["Use Casters of Azeroth action bars"], L["Turning this off needs a reload to give the Blizzard bars back."], setting("bars", "enabled"))
	p:Check(L["Hide Blizzard bars"], L["Hides the default bars that Casters of Azeroth replaces."], setting("bars", "hideBlizzard"))
	p:Slider(L["Rows"], 1, CK.Bars.MAX_ROWS, 1, setting("bars", "rows"))
	p:Slider(L["Buttons per row"], 4, 12, 1, setting("bars", "perRow"))
	p:Slider(L["Button size"], 24, 52, 1, setting("bars", "size"))
	p:Slider(L["Spacing"], 0, 10, 1, setting("bars", "spacing"))
	local getS, setS = setting("bars", "scale")
	p:Slider(L["Scale"], 0.6, 1.5, 0.05, getS, setS, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Check(L["Main bar (1 to =) on top"], nil, setting("bars", "mainOnTop"))
	p:Check(L["Background behind the bars"], nil, setting("bars", "background"))
	p:Button(L["Keybind mode"], function()
		if CK.ToggleKeybindMode then C.frame:Hide(); CK:ToggleKeybindMode() end
	end)
	p:Note(L["Hover a button and press a key (Shift, Alt, Ctrl work too). Or use the Blizzard key bindings: row 1 = Action Bar, row 2 = Bottom Left, row 3 = Bottom Right, row 4 = Right."])
end

function C:BuildMicro(p)
	p:Header(L["Micro menu and bags"])
	p:Check(L["Micro menu in a Casters of Azeroth panel"], L["Character, spellbook, talents, quests… tidy in one panel."], setting("micro", "enabled"))
	p:Check(L["Bags in the same panel"], L["With the number of free slots on your backpack."], setting("micro", "bags"))
	local getS, setS = setting("micro", "scale")
	p:Slider(L["Scale"], 0.6, 1.2, 0.05, getS, setS, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Note(L["Unlock the frames (General) to drag the panel."])
end

function C:BuildUnits(p)
	p:Header("Unit frames")
	p:Check(L["Use Casters of Azeroth frames"], L["Replaces Blizzard's player, target and party frames."], setting("units", "enabled"))
	p:Check(L["Player"], nil, setting("units", "player"))
	p:Check(L["Target (with your debuffs)"], nil, setting("units", "target"))
	p:Check("Target of target", nil, setting("units", "tot"))
	p:Check(L["Party"], nil, setting("units", "party"))
	p:Check(L["Class color on the health bar"], nil, setting("units", "classColor"))
	p:Check(L["Buff buttons next to party members"], L["Buffs you can give, e.g. Arcane Intellect. Red = missing, click = cast on that member."], setting("units", "partyBuffs"))
	local getS, setS = setting("units", "scale")
	p:Slider(L["Scale"], 0.6, 1.5, 0.05, getS, setS, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Gap()
	p:Header("Castbar")
	p:Check(L["Own cast bar"], nil, setting("units", "castbar"))
	p:Check(L["Target cast bar"], L["Orange = interruptible (Counterspell), grey with lock = not."], setting("units", "targetCastbar"))
	p:Check(L["Show latency at the end"], L["The red part: from there you can already press your next spell."], setting("units", "castbarLatency"))
	p:Check(L["Hide Blizzard cast bar"], nil, setting("units", "hideBlizzardCastbar"))
	p:Gap()
	p:Header(L["Tooltips"])
	p:Check(L["Show tooltips at a fixed spot"], L["Spell explanations and unit info appear in a corner instead of over your screen. Unlock the frames to move the spot."], setting("tooltip", "anchor"))
	p:Check(L["No action bar tooltips in combat"], nil, setting("tooltip", "hideInCombat"))
	p:Note(L["Hidden Blizzard frames only come back after a reload. Unlock the frames (General) to drag them."])
end

function C:BuildMap(p)
	p:Header(L["World map"])
	p:Check(L["Casters of Azeroth map upgrade"], nil, setting("map", "enabled"))
	p:Check(L["Flat map frame"], L["Hides Blizzard's frame art (borders, title bar, portrait)."], setting("map", "skin"))
	p:Check(L["Coordinates (player and cursor)"], nil, setting("map", "coords"))
	p:Check(L["Coordinates on the minimap"], L["Unlock the frames to move them."], setting("map", "minimapCoords"))
	p:Check(L["Fade the map while moving"], nil, setting("map", "fadeMoving"))
end

function C:BuildBags(p)
	p:Header(L["Bags"])
	p:Check(L["Casters of Azeroth bags (one window for all bags)"], L["Replaces Blizzard's bags. Turning this off gives them back right away."], setting("bags", "enabled"))
	p:Choice(L["View"], { { "category", L["By category"] }, { "bag", L["By bag"] } }, setting("bags", "view"))
	local getC, setC = setting("bags", "columns")
	p:Slider(L["Columns"], 6, 20, 1, getC, setC)
	local getI, setI = setting("bags", "iconSize")
	p:Slider(L["Icon size"], 24, 48, 1, getI, setI)
	p:Check(L["Item level on gear"], nil, setting("bags", "itemLevel"))
	p:Check(L["Glow on new items"], L["New items also get their own section until you close your bags."], setting("bags", "showNewGlow"))
	p:Check(L["Open the bags at a vendor"], nil, setting("bags", "autoOpenMerchant"))
	p:Gap()
	p:Header(L["Junk"])
	p:Note(L["Alt-click an item to mark it as junk (or unmark it). At a vendor the Sell junk button sells grey items and your marked items, a few at a time. Right-click a bag slot (bag button at the top) to choose what goes in that bag."])
	p:Button(L["Clear junk list"], function()
		if type(CK.char.bags) == "table" and type(CK.char.bags.junkList) == "table" then
			wipe(CK.char.bags.junkList)
		end
		changed("bags")
		CK:Print(L["Junk list cleared."])
	end, 200)
	p:Note(L["Unlock the frames (General) to drag the bag window."])
end

function C:BuildLoot(p)
	p:Header(L["Loot"])
	p:Check(L["Casters of Azeroth loot module"], nil, setting("loot", "enabled"))
	p:Check(L["Replace the loot window"], L["A compact list: click an item to loot it, or use Loot all. With master loot Blizzard's window is used."], setting("loot", "window"))
	p:Check(L["Open the loot window at the cursor"], L["Off: at a fixed spot. Unlock the frames to move it."], setting("loot", "atCursor"))
	p:Check(L["Auto loot (Blizzard setting)"], L["Blizzard's own auto loot: everything is picked up when you open a corpse. Off: the loot window opens, with buttons per kind (quest, gear, reagents, money, trash), and Shift-click loots everything. Applied after combat."], setting("loot", "autoLoot"))
	p:Gap()
	p:Header(L["Loot feed"])
	p:Check(L["Show what you receive"], L["Items, money and currency with your new bag total. Each line fades out after a few seconds."], setting("loot", "feed"))
	p:Check(L["Show money"], nil, setting("loot", "showMoney"))
	p:Check(L["Show quest items"], nil, setting("loot", "questItems"))
	p:Check(L["Warn when your bags are full"], nil, setting("loot", "bagsFull"))
	local getD, setD = setting("loot", "feedDuration")
	p:Slider(L["Seconds per line"], 2, 20, 1, getD, setD)
	local getM, setM = setting("loot", "feedMax")
	p:Slider(L["Lines"], 2, 12, 1, getM, setM)
	p:Gap()
	p:Header(L["Group loot"])
	p:Check(L["Compact roll frames"], L["Need, Greed, Transmog and Pass with a timer bar. You always choose yourself; Blizzard still asks to confirm Bind on Pickup."], setting("loot", "rollFrames"))
	p:Note(L["Unlock the frames (/ck unlock) to move the loot window, feed and roll frames."])
end

function C:BuildSkins(p)
	p:Header(L["Skins"])
	p:Note(L["Gives Blizzard's windows the Casters of Azeroth look: flat dark panels, thin borders and the accent colour instead of the gold and stone frame art. Only the look changes."])
	if CK.Skins and CK.Skins.ElvUIActive and CK.Skins:ElvUIActive() then
		p:Note(L["ElvUI skins Blizzard's windows itself: Casters of Azeroth leaves those windows to ElvUI. Turn off ElvUI's Blizzard skins to use these."])
	end
	p:Check(L["Skin Blizzard windows"], L["Turning a skin off needs a reload (/reload)."], setting("skins", "enabled"))

	p:Header(L["Windows"])
	p:Check(L["Character, reputation and currency"], nil, setting("skins", "character"))
	p:Check(L["Spellbook and talents"], nil, setting("skins", "spellbook"))
	p:Check(L["Quest and gossip windows"], L["The parchment behind quest text stays, so the text remains readable."], setting("skins", "quest"))
	p:Check(L["Vendor"], nil, setting("skins", "merchant"))
	p:Check(L["Mailbox"], nil, setting("skins", "mail"))
	p:Check(L["Class trainer"], nil, setting("skins", "trainer"))
	p:Check(L["Friends, who and raid"], nil, setting("skins", "friends"))
	p:Check(L["Game menu, addon list and settings"], nil, setting("skins", "menus"))
	p:Check(L["Pop-up dialogs"], nil, setting("skins", "popups"))
	p:Check(L["Other windows (bank, trade, dressing room, group finder…)"], nil, setting("skins", "other"))
	p:Note(L["Changes apply after a reload (/reload)."])
end

function C:BuildChat(p)
	p:Header("Chat")
	p:Check(L["Casters of Azeroth chat (IRC style)"], nil, setting("chat", "enabled"))
	p:Check(L["Timestamps [14:03]"], nil, setting("chat", "timestamps"))
	p:Check(L["Short channel names ([T], [G], [g]…)"], nil, setting("chat", "shortChannels"))
	p:Check(L["Names in class color"], nil, setting("chat", "classColors"))
	p:Check(L["One tab per channel"], L["General, Guild, Whisper, Trade, LFG, Combat. Asked once."], setting("chat", "tabsPerChannel"))
	p:Check(L["Fade tabs until you hover them"], nil, setting("chat", "fadeTabs"))
	p:Slider(L["Width"], 300, 800, 10, setting("chat", "width"))
	p:Slider(L["Height"], 120, 400, 10, setting("chat", "height"))
	p:Slider(L["Font size"], 10, 18, 1, setting("chat", "fontSize"))
end

function C:BuildRotation(p)
	p:Header(L["Rotation helper"])
	p:Note(L["Casters of Azeroth only shows which button to press. You press it yourself: nothing is ever cast automatically."])
	p:Check(L["Rotation helper on"], nil, setting("rotation", "enabled"))
	p:Choice(L["Suggestion source"], { { "blizzard", "Blizzard (Assisted Combat)" }, { "custom", L["Own priority (guide)"] } }, setting("rotation", "source"))
	p:Note(L["In combat Blizzard hides many values from addons. Blizzard's own suggestion always works; the own priority falls back to Blizzard when something is hidden."])
	p:Check(L["Light up buttons"], nil, setting("rotation", "glow"))
	p:Choice(L["Style"], { { "blizzard", L["Blizzard glow"] }, { "pulse", L["Pulsing border"] } }, setting("rotation", "glowStyle"))
	p:Check(L["Also show the next spell (faint border)"], nil, setting("rotation", "secondary"))
	p:Check(L["Hint box above the bars"], nil, setting("rotation", "hint"))
	p:Check(L["Only with a hostile target"], nil, setting("rotation", "onlyHostile"))
	p:Check(L["AoE mode (multiple enemies)"], L["Also via /ck aoe, middle-click on the minimap button or your own key binding."], setting("rotation", "aoe"))
	p:Check(L["Automatic AoE with 3+ enemies close by"], L["Counts enemies within about 10 yards from their nameplates. Turn enemy nameplates on (V)."], setting("rotation", "autoAoe"))
	p:Gap()
	p:Note(L["Colors: gold = press now, purple = proc (e.g. Fingers of Frost), blue = defensive (falling, rooted, too close)."])
end

function C:BuildLeveling(p)
	p:Header(L["Leveling"])
	p:Check(L["XP bar with XP per hour and time to level"], nil, setting("leveling", "xpbar"))
	p:Check(L["Hide Blizzard XP bar"], nil, setting("leveling", "hideBlizzardXP"))
	p:Check(L["Kills to level in enemy tooltips"], nil, setting("leveling", "mobTooltip"))
	p:Check(L["Reminders (water, food, buffs, bags…)"], nil, setting("leveling", "reminders"))
	p:Choice(L["Buff buttons"], { { "always", L["Always, with timer"] }, { "missing", L["Only when missing or running low"] } }, setting("leveling", "buffMode"))
	local getB, setB = setting("leveling", "buffWarnMinutes")
	p:Slider(L["Running low below"], 1, 15, 1, getB, setB, function(v) return L["%d min"]:format(v) end)
	local def = CK:GetClass()
	for _, opt in ipairs(def and def.buffOptions or {}) do
		local key = opt[1]
		p:Check("   " .. L[opt[2]], nil,
			function() return not CK.char.leveling.buffsOff[key] end,
			function(v) CK.char.leveling.buffsOff[key] = (not v) or nil; changed("leveling") end)
	end
	p:Check(L["Notify: new spells at the trainer"], nil, setting("leveling", "trainer"))
	p:Check(L["Notify: talent points available"], nil, setting("leveling", "talents"))
	p:Gap()
	p:Header(L["At a vendor"])
	p:Check(L["Sell grey items automatically"], nil, setting("leveling", "sellGrey"))
	p:Check(L["Repair automatically"], nil, setting("leveling", "repair"))
end

function C:BuildProfiles(p)
	p:Header(L["Profiles"])
	p:Note(L["Save the settings of this character under a name and use them on your alts. Personal things (spec, measured XP, chat setup) stay with each character."])
	local current = p:Note("")
	current.refresh = function()
		current:SetText(L["Current profile: %s"]:format(CK.char.profile or L["none"]))
	end
	table.insert(p.widgets, current)
	p:Gap()

	p:Header(L["Save"])
	local nameBox = p:Edit(L["Profile name"])
	p:Button(L["Save current settings"], function()
		local name = strtrim(nameBox:GetText() or "")
		if name == "" then name = CK.char.profile or UnitName("player") end
		if CK:SaveProfile(name) then
			C.selected = name
			nameBox:SetText("")
			CK:Print(L["Profile saved: %s"]:format(name))
			C:Refresh()
		end
	end, 200)
	p:Gap()

	p:Header(L["Use a profile"])
	p:Choice(L["Profile"], function()
		local opts = {}
		for _, n in ipairs(CK:ProfileNames()) do opts[#opts + 1] = { n, n } end
		return opts
	end, function()
		if not C.selected or not CK.db.profiles[C.selected] then C.selected = CK:ProfileNames()[1] end
		return C.selected
	end, function(v) C.selected = v; C:Refresh() end)
	p:Button(L["Load into this character"], function()
		if not C.selected then return end
		CK:OutOfCombat("profile", function()
			if CK:LoadProfile(C.selected) then
				CK:Print(L["Profile loaded: %s. Reloading the UI…"]:format(C.selected))
				C_Timer.After(0.5, ReloadUI)
			end
		end)
	end, 200)
	p:ButtonRight(L["Delete"], function()
		if C.selected then
			CK:DeleteProfile(C.selected)
			C.selected = nil
			C:Refresh()
		end
	end, 210, 100)
	p:Check(L["Use this profile for new characters"], L["A new alt starts with these settings at its first login."],
		function() return C.selected ~= nil and CK.db.defaultProfile == C.selected end,
		function(v) CK.db.defaultProfile = v and C.selected or nil end)
end

function C:BuildAbout(p)
	p:Header("Casters of Azeroth")
	p:Note(L["Version %s, made by DinX."]:format(CK.version))
	p:Note(L["A caster interface for WoW Forever: all action bars in one frame, a rotation helper that lights up the right button, and leveling helpers."])
	p:Gap()
	p:Header(L["Within the rules"])
	p:Note(L["Casters of Azeroth only uses the official addon API. It shows information and lights up buttons, but never casts anything itself, never sends chat messages and does not work with external programs."])
	p:Gap()
	p:Header(L["Commands"])
	p:Note(L["/ck  settings\n/ck unlock  and  /ck lock  drag frames\n/ck aoe  toggle AoE mode\n/ck reset  reset positions"])
end

---------------------------------------------------------------------------
-- Minimap button
---------------------------------------------------------------------------
function C:CreateMinimapButton()
	local b = CreateFrame("Button", "CasterKitMinimapButton", Minimap)
	b:SetSize(31, 31)
	b:SetFrameStrata("MEDIUM")
	b:SetFrameLevel(8)
	b:RegisterForClicks("AnyUp")
	b:RegisterForDrag("LeftButton")
	b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight")

	local bg = b:CreateTexture(nil, "BACKGROUND")
	bg:SetSize(20, 20)
	bg:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
	bg:SetPoint("TOPLEFT", 7, -5)
	local icon = b:CreateTexture(nil, "ARTWORK")
	icon:SetSize(18, 18)
	icon:SetTexture("Interface\\Icons\\Spell_Frost_FrostBolt02")
	icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	icon:SetPoint("TOPLEFT", 7, -6)
	local border = b:CreateTexture(nil, "OVERLAY")
	border:SetSize(53, 53)
	border:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
	border:SetPoint("TOPLEFT")

	local function place()
		local a = math.rad(CK.db.minimap.angle)
		local r = Minimap:GetWidth() / 2 + 5
		b:ClearAllPoints()
		b:SetPoint("CENTER", Minimap, "CENTER", math.cos(a) * r, math.sin(a) * r)
	end
	b:SetScript("OnDragStart", function(self)
		self:SetScript("OnUpdate", function()
			local mx, my = Minimap:GetCenter()
			local cx, cy = GetCursorPosition()
			local s = Minimap:GetEffectiveScale()
			CK.db.minimap.angle = math.deg(math.atan2(cy / s - my, cx / s - mx))
			place()
		end)
	end)
	b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
	b:SetScript("OnClick", function(_, button)
		if button == "LeftButton" and IsShiftKeyDown() and CK.ToggleKeybindMode then
			CK:ToggleKeybindMode()
		elseif button == "RightButton" then
			CK.char.bars.locked = not CK.char.bars.locked
			changed("bars"); changed("micro")
		elseif button == "MiddleButton" then
			CK:ToggleAoE()
		else
			CK:ToggleConfig()
		end
	end)
	b:SetScript("OnEnter", function(self)
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine("Casters of Azeroth")
		GameTooltip:AddLine(L["Click: settings"], 1, 1, 1)
		GameTooltip:AddLine(L["Right-click: lock/unlock frames"], 1, 1, 1)
		GameTooltip:AddLine(L["Middle-click: AoE mode"], 1, 1, 1)
		GameTooltip:AddLine(L["Shift-click: keybind mode"], 1, 1, 1)
		local spec = CK:GetSpec()
		if spec then GameTooltip:AddLine(L["Rotation: "] .. spec.name .. (CK.char.rotation.aoe and " (AoE)" or ""), 0.41, 0.8, 0.94) end
		GameTooltip:Show()
	end)
	b:SetScript("OnLeave", GameTooltip_Hide)
	self.minimapButton = b
	place()
	self:UpdateMinimapButton()
end

function C:UpdateMinimapButton()
	if self.minimapButton then self.minimapButton:SetShown(not CK.db.minimap.hide) end
end

---------------------------------------------------------------------------
-- Blizzard settings entry (opens our own window)
---------------------------------------------------------------------------
function C:RegisterBlizzardSettings()
	if not (Settings and Settings.RegisterCanvasLayoutCategory) then return end
	local panel = CreateFrame("Frame")
	local t = panel:CreateFontString(nil, "OVERLAY", "GameFontHighlightLarge")
	t:SetPoint("TOPLEFT", 16, -16)
	t:SetText("Casters of Azeroth")
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(200, 26)
	b:SetPoint("TOPLEFT", 16, -50)
	b:SetText(L["Open Casters of Azeroth settings"])
	b:SetScript("OnClick", function()
		if SettingsPanel then HideUIPanel(SettingsPanel) end
		CK:ToggleConfig(true)
	end)
	pcall(function()
		local cat = Settings.RegisterCanvasLayoutCategory(panel, "Casters of Azeroth")
		Settings.RegisterAddOnCategory(cat)
	end)
end

function CK:ToggleConfig(forceShow)
	if not C.frame then C:CreateWindow() end
	if C.frame:IsShown() and not forceShow then
		C.frame:Hide()
	else
		C.frame:Show()
		C:Show(C.currentPage or "general")
	end
end

function C:OnEnable()
	self:CreateMinimapButton()
	self:RegisterBlizzardSettings()
end
