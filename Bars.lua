-- CasterKit by DinX: all action bars stacked in one frame
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local LAB = LibStub("LibActionButton-1.0")

local Bars = CK:NewModule("Bars")
Bars.buttons = {}   -- every CasterKit action button
Bars.rows = {}      -- rows[r][i] = button

-- Each row maps to a Blizzard bar: its action slots, key binding and frame.
local ROWS = {
	{ binding = "ACTIONBUTTON%d", paging = true, blizzard = { "MainActionBar", "MainMenuBar" }, blizzButton = "ActionButton%d" },
	{ binding = "MULTIACTIONBAR1BUTTON%d", offset = 60, blizzard = { "MultiBarBottomLeft" }, blizzButton = "MultiBarBottomLeftButton%d" },
	{ binding = "MULTIACTIONBAR2BUTTON%d", offset = 48, blizzard = { "MultiBarBottomRight" }, blizzButton = "MultiBarBottomRightButton%d" },
	{ binding = "MULTIACTIONBAR3BUTTON%d", offset = 24, blizzard = { "MultiBarRight" }, blizzButton = "MultiBarRightButton%d" },
}
Bars.MAX_ROWS = #ROWS

local PAGE_DRIVER = "[vehicleui][possessbar][overridebar][shapeshift]possess;[bar:2]2;[bar:3]3;[bar:4]4;[bar:5]5;[bar:6]6;1"

local function buttonConfig(binding)
	return {
		outOfRangeColoring = "button",
		showGrid = true,
		hideElements = { macro = true },
		keyBoundTarget = binding,
		keyBoundClickButton = "Keybind",
		text = {
			hotkey = {
				font = { font = S.font, size = 11, flags = "OUTLINE" },
				position = { anchor = "TOPRIGHT", relAnchor = "TOPRIGHT", offsetX = -1, offsetY = -3 },
			},
			count = {
				font = { font = S.font, size = 12, flags = "OUTLINE" },
				position = { anchor = "BOTTOMRIGHT", relAnchor = "BOTTOMRIGHT", offsetX = -1, offsetY = 2 },
			},
		},
	}
end

---------------------------------------------------------------------------
-- Hiding the Blizzard bars (only the rows we replace)
---------------------------------------------------------------------------
local hider = CreateFrame("Frame")
hider:Hide()

local function hideFrame(frame, clearEvents)
	if not frame then return end
	if clearEvents then frame:UnregisterAllEvents() end
	if frame.HideBase then frame:HideBase() else frame:Hide() end
	frame:SetParent(hider)
end

local function hideBlizzardButton(btn)
	if not btn then return end
	btn:Hide()
	btn:UnregisterAllEvents()
	btn:SetAttribute("statehidden", true)
end

local hiddenRows = {}
function Bars:HideBlizzard()
	for r = 1, CK.char.bars.rows do
		if not hiddenRows[r] then
			hiddenRows[r] = true
			local def = ROWS[r]
			for _, name in ipairs(def.blizzard) do
				hideFrame(_G[name], r > 1)
			end
			for i = 1, 12 do
				hideBlizzardButton(_G[def.blizzButton:format(i)])
			end
		end
	end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
function Bars:CreatePanel()
	local p = CreateFrame("Frame", "CasterKitPanel", UIParent, "BackdropTemplate")
	p:SetMovable(true)
	p:SetClampedToScreen(true)
	p:SetFrameStrata("LOW")
	self.panel = p
	CK.panel = p

	-- Mover overlay, visible when unlocked
	local mover = CreateFrame("Frame", nil, p, "BackdropTemplate")
	mover:SetAllPoints()
	mover:SetFrameStrata("DIALOG")
	mover:EnableMouse(true)
	mover:RegisterForDrag("LeftButton")
	mover:SetBackdrop({ bgFile = S.flat, edgeFile = S.flat, edgeSize = 1 })
	mover:SetBackdropColor(0.41, 0.80, 0.94, 0.25)
	mover:SetBackdropBorderColor(0.41, 0.80, 0.94, 1)
	local label = S:Font(mover, 12)
	label:SetPoint("CENTER")
	label:SetText(L["CasterKit bars: drag me\n/ck lock to lock"])
	mover:SetScript("OnDragStart", function()
		if InCombatLockdown() then return end
		p:StartMoving()
	end)
	mover:SetScript("OnDragStop", function()
		p:StopMovingOrSizing()
		local point, _, relPoint, x, y = p:GetPoint()
		CK.char.bars.point = { point, "UIParent", relPoint, math.floor(x + 0.5), math.floor(y + 0.5) }
	end)
	mover:Hide()
	self.mover = mover
end

function Bars:CreateButtons()
	local mainHeader = CreateFrame("Frame", "CasterKitMainHeader", self.panel, "SecureHandlerStateTemplate")
	mainHeader:SetAllPoints()
	mainHeader:SetAttribute("_onstate-page", [[
		if newstate == "possess" then
			if HasVehicleActionBar() then
				newstate = GetVehicleBarIndex()
			elseif HasOverrideActionBar() then
				newstate = GetOverrideBarIndex()
			elseif HasTempShapeshiftActionBar() then
				newstate = GetTempShapeshiftBarIndex()
			elseif HasBonusActionBar() then
				newstate = GetBonusBarIndex()
			else
				newstate = 1
			end
		end
		self:SetAttribute("state", newstate)
		control:ChildUpdate("state", newstate)
	]])
	self.mainHeader = mainHeader

	local staticHeader = CreateFrame("Frame", "CasterKitStaticHeader", self.panel, "SecureHandlerStateTemplate")
	staticHeader:SetAllPoints()
	self.staticHeader = staticHeader

	for r = 1, #ROWS do
		local def = ROWS[r]
		self.rows[r] = {}
		for i = 1, 12 do
			local header = def.paging and mainHeader or staticHeader
			local name = ("CasterKitBar%dButton%d"):format(r, i)
			local btn = LAB:CreateButton(r * 100 + i, name, header, buttonConfig(def.binding:format(i)))
			if def.paging then
				for page = 1, 18 do
					btn:SetState(page, "action", (page - 1) * 12 + i)
				end
			else
				btn:SetState(0, "action", def.offset + i)
			end
			S:SkinButton(btn)
			btn.ckRow = r
			self.rows[r][i] = btn
			self.buttons[#self.buttons + 1] = btn
		end
	end

	RegisterStateDriver(mainHeader, "page", PAGE_DRIVER)
end

---------------------------------------------------------------------------
-- Layout
---------------------------------------------------------------------------
function Bars:Layout()
	local cfg = CK.char.bars
	local p = self.panel
	p:SetScale(cfg.scale)
	p:ClearAllPoints()
	local pt = cfg.point
	p:SetPoint(pt[1], UIParent, pt[3], pt[4], pt[5])

	if not self.active then
		p:SetSize(cfg.perRow * cfg.size + (cfg.perRow - 1) * cfg.spacing + 10, 1)
		p:SetBackdrop(nil)
		return
	end

	local pad = cfg.background and 5 or 0
	local size, gap = cfg.size, cfg.spacing
	local rows, perRow = cfg.rows, cfg.perRow
	p:SetSize(perRow * size + (perRow - 1) * gap + pad * 2, rows * size + (rows - 1) * gap + pad * 2)

	if cfg.background then S:Backdrop(p) else p:SetBackdrop(nil) end

	for r = 1, #ROWS do
		-- visual position: row 1 on top unless mainOnTop is off
		local slot = cfg.mainOnTop and r or (rows - r + 1)
		for i = 1, 12 do
			local btn = self.rows[r][i]
			local show = r <= rows and i <= perRow
			btn:SetSize(size, size)
			btn:ClearAllPoints()
			if show then
				btn:SetPoint("TOPLEFT", p, "TOPLEFT", pad + (i - 1) * (size + gap), -pad - (slot - 1) * (size + gap))
				btn:SetAttribute("statehidden", nil)
				btn:Show()
			else
				btn:SetPoint("CENTER", p, "CENTER")
				btn:SetAttribute("statehidden", true)
				btn:Hide()
			end
		end
	end
	CK:Fire("PANEL_LAYOUT")
end

---------------------------------------------------------------------------
-- Key bindings: the normal Blizzard bindings drive our buttons
---------------------------------------------------------------------------
function Bars:UpdateBindings()
	if not self.active then return end
	CK:OutOfCombat("bindings", function()
		ClearOverrideBindings(self.panel)
		for r = 1, CK.char.bars.rows do
			local def = ROWS[r]
			for i = 1, CK.char.bars.perRow do
				local btn = self.rows[r][i]
				local action = def.binding:format(i)
				for k = 1, select("#", GetBindingKey(action)) do
					local key = select(k, GetBindingKey(action))
					if key and key ~= "" then
						SetOverrideBindingClick(self.panel, false, key, btn:GetName(), "Keybind")
					end
				end
				btn:UpdateConfig(buttonConfig(action))
			end
		end
	end)
end

function Bars:UpdateLock()
	local locked = CK.char.bars.locked or InCombatLockdown()
	self.mover:SetShown(not locked)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function Bars:Setup()
	local cfg = CK.char.bars
	self.active = cfg.enabled and not CK:BarConflict()
	if self.active and not self.buttonsCreated then
		self:CreateButtons()
		self.buttonsCreated = true
	end
	if self.buttonsCreated and not self.active then
		-- disabled after creation: needs a reload to give the bars back to Blizzard
		for _, btn in ipairs(self.buttons) do
			btn:SetAttribute("statehidden", true)
			btn:Hide()
		end
		ClearOverrideBindings(self.panel)
	end
	if self.active and cfg.hideBlizzard then
		self:HideBlizzard()
	end
	self:Layout()
	self:UpdateBindings()
	self:UpdateLock()
end

function Bars:OnEnable()
	self:CreatePanel()
	CK:OutOfCombat("bars-setup", function() self:Setup() end)

	CK:On("UPDATE_BINDINGS", function() self:UpdateBindings() end)
	CK:On("PLAYER_REGEN_DISABLED", function() self.mover:Hide() end)
	CK:On("PLAYER_REGEN_ENABLED", function() self:UpdateLock() end)
	CK:Listen("SETTINGS", function(group)
		if group == "bars" then
			CK:OutOfCombat("bars-setup", function() self:Setup() end)
		end
	end)
end
