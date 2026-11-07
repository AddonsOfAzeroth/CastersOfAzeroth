-- CasterKit by DinX: settings window and minimap button
local _, ns = ...
local CK = ns.CK
local S = CK.Style

local C = CK:NewModule("Config")

---------------------------------------------------------------------------
-- Widgets (flat, in CasterKit style)
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

-- Cycling choice: ◀ value ▶
function Page:Choice(label, options, get, set)
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
		local cur = get()
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
	f:SetSize(640, 480)
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

	self:BuildGeneral(newPage("general", "Algemeen"))
	self:BuildBars(newPage("bars", "Actiebalken"))
	self:BuildMicro(newPage("micro", "Micromenu"))
	self:BuildRotation(newPage("rotation", "Rotatie"))
	self:BuildLeveling(newPage("leveling", "Levelen"))
	self:BuildAbout(newPage("about", "Over"))
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
		self.conflictNote:SetText(c and ("|cffff5050%s beheert nu de actiebalken.|r Zet dat uit om de CasterKit-balken te gebruiken; de rotatiehulp werkt intussen op die knoppen."):format(c) or "Geen andere actiebalk-addon actief.")
	end
end

---------------------------------------------------------------------------
-- Pages
---------------------------------------------------------------------------
function C:BuildGeneral(p)
	p:Header("Algemeen")
	p:Check("Kaders vergrendeld", "Zet uit om de balken, het hintblokje en het micromenu te verslepen.",
		function() return CK.char.bars.locked end,
		function(v) CK.char.bars.locked = v; changed("bars"); changed("micro") end)
	p:Check("Minimapknop tonen", nil,
		function() return not CK.db.minimap.hide end,
		function(v) CK.db.minimap.hide = not v; C:UpdateMinimapButton() end)
	p:Gap()
	p:Header("Spec")
	local def = CK:GetClass()
	if def then
		local opts = {}
		for _, key in ipairs(def.specOrder) do opts[#opts + 1] = { key, def.specs[key].name } end
		p:Choice("Rotatie voor", opts,
			function() local _, k = CK:GetSpec(); return k end,
			function(v) CK.char.rotation.spec = v; changed("rotation") end)
	else
		p:Note("Voor jouw class is er nog geen rotatie. De balken en levelhulpjes werken wel.")
	end
	p:Gap()
	p:Header("Opnieuw beginnen")
	p:Button("Posities terugzetten", function()
		CK:OutOfCombat("reset", function()
			CK.char.bars.point = CK.CopyTable(CK.charDefaults.bars.point)
			CK.char.micro.point = CK.CopyTable(CK.charDefaults.micro.point)
			CK.char.rotation.point = nil
			changed("bars"); changed("micro"); changed("rotation")
		end)
	end)
	p:Button("Interface herladen", ReloadUI)
end

function C:BuildBars(p)
	p:Header("Actiebalken")
	self.conflictNote = p:Note("")
	p:Check("CasterKit-actiebalken gebruiken", "Uitzetten vraagt een herlaad om de Blizzard-balken terug te geven.", setting("bars", "enabled"))
	p:Check("Blizzard-balken verbergen", "Verbergt de standaardbalken die CasterKit vervangt.", setting("bars", "hideBlizzard"))
	p:Slider("Aantal rijen", 1, CK.Bars.MAX_ROWS, 1, setting("bars", "rows"))
	p:Slider("Knoppen per rij", 4, 12, 1, setting("bars", "perRow"))
	p:Slider("Knopgrootte", 24, 52, 1, setting("bars", "size"))
	p:Slider("Tussenruimte", 0, 10, 1, setting("bars", "spacing"))
	local getS, setS = setting("bars", "scale")
	p:Slider("Schaal", 0.6, 1.5, 0.05, getS, setS, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Check("Hoofdbalk (1 t/m =) bovenaan", nil, setting("bars", "mainOnTop"))
	p:Check("Achtergrond achter de balken", nil, setting("bars", "background"))
	p:Note("Sneltoetsen stel je in via het gewone Blizzard-menu (Toetsenbord). Rij 1 = Action Bar, rij 2 = Bottom Left, rij 3 = Bottom Right, rij 4 = Right.")
end

function C:BuildMicro(p)
	p:Header("Micromenu en tassen")
	p:Check("Micromenu in een CasterKit-paneel", "Personage, spreukenboek, talenten, quests… netjes in één kader.", setting("micro", "enabled"))
	p:Check("Tassen in hetzelfde paneel", "Met het aantal vrije plaatsen op je rugzak.", setting("micro", "bags"))
	local getS, setS = setting("micro", "scale")
	p:Slider("Schaal", 0.6, 1.2, 0.05, getS, setS, function(v) return ("%d%%"):format(v * 100 + 0.5) end)
	p:Note("Ontgrendel de kaders (Algemeen) om het paneel te verslepen.")
end

function C:BuildRotation(p)
	p:Header("Rotatiehulp")
	p:Note("CasterKit toont alleen welke knop je best indrukt. Jij drukt zelf: er wordt nooit iets automatisch gecast.")
	p:Check("Rotatiehulp aan", nil, setting("rotation", "enabled"))
	p:Check("Knoppen laten oplichten", nil, setting("rotation", "glow"))
	p:Choice("Stijl", { { "blizzard", "Blizzard-glinster" }, { "pulse", "Pulserende rand" } }, setting("rotation", "glowStyle"))
	p:Check("Volgende spreuk ook tonen (zwakke rand)", nil, setting("rotation", "secondary"))
	p:Check("Hintblokje boven de balken", nil, setting("rotation", "hint"))
	p:Check("Alleen bij een vijandig doelwit", nil, setting("rotation", "onlyHostile"))
	p:Check("AoE-modus (meerdere vijanden)", "Ook via /ck aoe, middelklik op de minimapknop of een eigen sneltoets.", setting("rotation", "aoe"))
	p:Gap()
	p:Note("Kleuren: goud = nu indrukken, paars = proc (bv. Fingers of Frost), blauw = defensief (vallen, vastzitten, te dichtbij).")
end

function C:BuildLeveling(p)
	p:Header("Levelen")
	p:Check("XP-balk met XP per uur en tijd tot level", nil, setting("leveling", "xpbar"))
	p:Check("Blizzard-XP-balk verbergen", nil, setting("leveling", "hideBlizzardXP"))
	p:Check("Kills tot level in de tooltip van vijanden", nil, setting("leveling", "mobTooltip"))
	p:Check("Herinneringen (water, food, buffs, tassen…)", nil, setting("leveling", "reminders"))
	p:Check("Melding: nieuwe spreuken bij de trainer", nil, setting("leveling", "trainer"))
	p:Check("Melding: talentpunten vrij", nil, setting("leveling", "talents"))
	p:Gap()
	p:Header("Bij een verkoper")
	p:Check("Grijze items automatisch verkopen", nil, setting("leveling", "sellGrey"))
	p:Check("Automatisch herstellen", nil, setting("leveling", "repair"))
end

function C:BuildAbout(p)
	p:Header("CasterKit")
	p:Note(("Versie %s, gemaakt door DinX."):format(CK.version))
	p:Note("Een caster-interface voor WoW Forever: alle actiebalken in één kader, een rotatiehulp die de juiste knop laat oplichten, en hulpjes voor het levelen.")
	p:Gap()
	p:Header("Binnen de regels")
	p:Note("CasterKit gebruikt alleen de officiële addon-API. Het toont informatie en laat knoppen oplichten, maar cast nooit zelf iets, verstuurt geen chatberichten en werkt niet samen met externe programma's.")
	p:Gap()
	p:Header("Commando's")
	p:Note("/ck  instellingen\n/ck unlock  en  /ck lock  kaders verslepen\n/ck aoe  AoE-modus wisselen\n/ck reset  posities terugzetten")
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
		if button == "RightButton" then
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
		GameTooltip:AddLine("CasterKit")
		GameTooltip:AddLine("Klik: instellingen", 1, 1, 1)
		GameTooltip:AddLine("Rechtsklik: kaders (ont)grendelen", 1, 1, 1)
		GameTooltip:AddLine("Middelklik: AoE-modus", 1, 1, 1)
		local spec = CK:GetSpec()
		if spec then GameTooltip:AddLine("Rotatie: " .. spec.name .. (CK.char.rotation.aoe and " (AoE)" or ""), 0.41, 0.8, 0.94) end
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
	t:SetText("CasterKit")
	local b = CreateFrame("Button", nil, panel, "UIPanelButtonTemplate")
	b:SetSize(200, 26)
	b:SetPoint("TOPLEFT", 16, -50)
	b:SetText("Open CasterKit-instellingen")
	b:SetScript("OnClick", function()
		if SettingsPanel then HideUIPanel(SettingsPanel) end
		CK:ToggleConfig(true)
	end)
	pcall(function()
		local cat = Settings.RegisterCanvasLayoutCategory(panel, "CasterKit")
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
