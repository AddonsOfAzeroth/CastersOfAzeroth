-- CasterKit by DinX: keybind mode
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style

local KB = CK:NewModule("Keybind")
KB.active = false
KB.overlays = {}    -- btn -> overlay frame
KB.hovered = nil    -- btn under the mouse

local ACCOUNT = ACCOUNT_BINDINGS or 1
local CHARACTER = CHARACTER_BINDINGS or 2

-- Keys that never get bound on their own
local IGNORE = {
	LSHIFT = true, RSHIFT = true, LALT = true, RALT = true,
	LCTRL = true, RCTRL = true, LMETA = true, RMETA = true,
	UNKNOWN = true, PRINTSCREEN = true,
}

-- OnMouseDown button names -> binding key names
local MOUSE = { MiddleButton = "BUTTON3", Button4 = "BUTTON4", Button5 = "BUTTON5" }

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function hex(c)
	return ("|cff%02x%02x%02x"):format(c[1] * 255, c[2] * 255, c[3] * 255)
end

-- Modifier prefix in the WoW order: ALT-CTRL-SHIFT-
local function withModifiers(key)
	local p = ""
	if IsAltKeyDown() then p = p .. "ALT-" end
	if IsControlKeyDown() then p = p .. "CTRL-" end
	if IsShiftKeyDown() then p = p .. "SHIFT-" end
	return p .. key
end

local function actionName(action)
	if not action or action == "" then return "?" end
	local n = _G["BINDING_NAME_" .. action]
	if not n and GetBindingName then n = GetBindingName(action) end
	return n or action
end

local function keysOf(action)
	local keys = {}
	for k = 1, select("#", GetBindingKey(action)) do
		local key = select(k, GetBindingKey(action))
		if key and key ~= "" then keys[#keys + 1] = key end
	end
	return keys
end

local function bindingSet()
	return KB.perChar and CHARACTER or ACCOUNT
end

local function save()
	SaveBindings(bindingSet())
end

---------------------------------------------------------------------------
-- Panel
---------------------------------------------------------------------------
local function flatButton(parent, w, h)
	local b = CreateFrame("Button", nil, parent, "BackdropTemplate")
	b:SetSize(w, h)
	S:Backdrop(b, 1)
	b:SetBackdropBorderColor(unpack(S.colors.edge))
	b.text = S:Font(b, 12)
	b.text:SetPoint("CENTER")
	b:SetScript("OnEnter", function(self) self:SetBackdropBorderColor(unpack(S.colors.accent)) end)
	b:SetScript("OnLeave", function(self) self:SetBackdropBorderColor(unpack(S.colors.edge)) end)
	return b
end

function KB:CreatePanel()
	local p = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	p:SetSize(400, 132)
	p:SetPoint("TOP", UIParent, "TOP", 0, -110)
	p:SetFrameStrata("DIALOG")
	p:SetClampedToScreen(true)
	p:EnableMouse(true)
	S:Backdrop(p, 0.95)
	p:Hide()
	self.panel = p

	-- accent line on top
	local line = p:CreateTexture(nil, "ARTWORK")
	line:SetTexture(S.flat)
	line:SetVertexColor(unpack(S.colors.accent))
	line:SetPoint("TOPLEFT", 1, -1)
	line:SetPoint("TOPRIGHT", -1, -1)
	line:SetHeight(2)

	p.title = S:Font(p, 14)
	p.title:SetPoint("TOPLEFT", 10, -10)
	p.title:SetTextColor(unpack(S.colors.accent))

	p.body = S:Font(p, 11)
	p.body:SetPoint("TOPLEFT", p.title, "BOTTOMLEFT", 0, -6)
	p.body:SetPoint("RIGHT", p, "RIGHT", -10, 0)
	p.body:SetJustifyH("LEFT")
	p.body:SetTextColor(unpack(S.colors.muted))

	p.status = S:Font(p, 11)
	p.status:SetPoint("TOPLEFT", p.body, "BOTTOMLEFT", 0, -8)
	p.status:SetPoint("RIGHT", p, "RIGHT", -10, 0)
	p.status:SetJustifyH("LEFT")

	-- flat checkbox: save for this character only
	local check = CreateFrame("Button", nil, p, "BackdropTemplate")
	check:SetSize(14, 14)
	check:SetPoint("BOTTOMLEFT", 10, 10)
	S:Backdrop(check, 1)
	check:SetBackdropBorderColor(unpack(S.colors.edge))
	local mark = check:CreateTexture(nil, "ARTWORK")
	mark:SetTexture(S.flat)
	mark:SetVertexColor(unpack(S.colors.accent))
	mark:SetPoint("TOPLEFT", 3, -3)
	mark:SetPoint("BOTTOMRIGHT", -3, 3)
	check.mark = mark
	check.label = S:Font(check, 11)
	check.label:SetPoint("LEFT", check, "RIGHT", 6, 0)
	check:SetHitRectInsets(0, -200, 0, 0)
	check:SetScript("OnClick", function()
		if InCombatLockdown() then return end
		KB.perChar = not KB.perChar
		KB:UpdateCheck()
	end)
	p.check = check

	local done = flatButton(p, 70, 20)
	done:SetPoint("BOTTOMRIGHT", -10, 8)
	done:SetScript("OnClick", function() KB:Exit() end)
	p.done = done

	-- Invisible keyboard catcher
	local cap = CreateFrame("Frame", nil, UIParent)
	cap:SetFrameStrata("DIALOG")
	cap:EnableKeyboard(true)
	cap:Hide()
	cap:SetScript("OnKeyDown", function(f, key) KB:OnKey(f, key) end)
	self.capture = cap
end

function KB:UpdateCheck()
	self.panel.check.mark:SetShown(self.perChar)
end

function KB:SetStatus(text, color)
	local s = self.panel.status
	s:SetText(text or "")
	s:SetTextColor(unpack(color or S.colors.text))
end

---------------------------------------------------------------------------
-- Overlays on the action buttons
---------------------------------------------------------------------------
function KB:GetOverlay(btn)
	local o = self.overlays[btn]
	if o then return o end
	o = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	o:SetFrameStrata("DIALOG")
	o:SetBackdrop({ bgFile = S.flat, edgeFile = S.flat, edgeSize = 1 })
	o:EnableMouse(true)
	o:EnableMouseWheel(true)
	o.btn = btn
	o:SetScript("OnEnter", function(f) KB:SetHovered(f.btn) end)
	o:SetScript("OnLeave", function(f) if KB.hovered == f.btn then KB:SetHovered(nil) end end)
	o:SetScript("OnMouseDown", function(f, button)
		local key = MOUSE[button]
		if key then KB:Bind(f.btn, withModifiers(key)) end
	end)
	o:SetScript("OnMouseWheel", function(f, delta)
		KB:Bind(f.btn, withModifiers(delta > 0 and "MOUSEWHEELUP" or "MOUSEWHEELDOWN"))
	end)
	o:Hide()
	self.overlays[btn] = o
	return o
end

function KB:PaintOverlay(o)
	local c = S.colors.accent
	if self.hovered == o.btn then
		o:SetBackdropColor(c[1], c[2], c[3], 0.35)
		o:SetBackdropBorderColor(c[1], c[2], c[3], 1)
	else
		o:SetBackdropColor(c[1], c[2], c[3], 0.08)
		o:SetBackdropBorderColor(c[1], c[2], c[3], 0.45)
	end
end

-- Show an overlay on every visible CasterKit button; returns how many.
function KB:ShowOverlays()
	local n = 0
	for _, o in pairs(self.overlays) do o:Hide() end
	for _, btn in ipairs(CK.Bars and CK.Bars.buttons or {}) do
		if btn:IsVisible() and btn.config and btn.config.keyBoundTarget then
			local o = self:GetOverlay(btn)
			o:ClearAllPoints()
			o:SetAllPoints(btn)
			self:PaintOverlay(o)
			o:Show()
			n = n + 1
		end
	end
	return n
end

function KB:HideOverlays()
	for _, o in pairs(self.overlays) do o:Hide() end
end

function KB:SetHovered(btn)
	self.hovered = btn
	for _, o in pairs(self.overlays) do
		if o:IsShown() then self:PaintOverlay(o) end
	end
	self:UpdateTooltip()
end

---------------------------------------------------------------------------
-- Tooltip
---------------------------------------------------------------------------
function KB:UpdateTooltip()
	local btn = self.hovered
	if not btn then
		GameTooltip:Hide()
		return
	end
	local action = btn.config.keyBoundTarget
	GameTooltip:SetOwner(self.overlays[btn], "ANCHOR_TOP")
	GameTooltip:ClearLines()
	local a = S.colors.accent
	GameTooltip:AddLine(actionName(action), a[1], a[2], a[3])
	local keys = keysOf(action)
	if #keys > 0 then
		GameTooltip:AddLine(L["Keys: %s"]:format(table.concat(keys, ", ")), 1, 1, 1)
	else
		local m = S.colors.muted
		GameTooltip:AddLine(L["No key bound"], m[1], m[2], m[3])
	end
	GameTooltip:Show()
end

---------------------------------------------------------------------------
-- Binding
---------------------------------------------------------------------------
function KB:Bind(btn, key)
	if not self.active or not btn or InCombatLockdown() then return end
	local action = btn.config.keyBoundTarget
	local old = GetBindingAction(key)
	if old == action then
		self:SetStatus(L["%s is already bound to %s."]:format(key, actionName(action)), S.colors.muted)
		return
	end
	if not SetBinding(key, action) then
		self:SetStatus(L["Could not bind %s."]:format(key), S.colors.warn)
		return
	end
	save()
	if old and old ~= "" then
		self:SetStatus(L["%s replaced: %s"]:format(key, actionName(old)), S.colors.hint)
	else
		self:SetStatus(L["%s bound to %s."]:format(key, actionName(action)), S.colors.accent)
	end
	self:UpdateTooltip()
end

function KB:Clear(btn)
	if not self.active or not btn or InCombatLockdown() then return end
	local action = btn.config.keyBoundTarget
	local keys = keysOf(action)
	if #keys == 0 then
		self:SetStatus(L["No key bound"], S.colors.muted)
		return
	end
	for _, key in ipairs(keys) do SetBinding(key, nil) end
	save()
	self:SetStatus(L["Keys cleared: %s"]:format(actionName(action)), S.colors.hint)
	self:UpdateTooltip()
end

function KB:OnKey(frame, key)
	-- Only swallow keys while a button is hovered (and Esc to finish).
	local handle = self.active and (self.hovered ~= nil or key == "ESCAPE") and not IGNORE[key]
	if not InCombatLockdown() then frame:SetPropagateKeyboardInput(not handle) end
	if not handle then return end
	if key == "ESCAPE" then
		self:Exit()
	elseif key == "DELETE" or key == "BACKSPACE" then
		self:Clear(self.hovered)
	else
		self:Bind(self.hovered, withModifiers(key))
	end
end

---------------------------------------------------------------------------
-- Enter / exit
---------------------------------------------------------------------------
function KB:Enter()
	if self.active then return end
	if InCombatLockdown() then
		CK:Print(L["Keybind mode is not available in combat."])
		return
	end
	if not self.panel then self:CreatePanel() end
	if self:ShowOverlays() == 0 then
		CK:Print(L["No CasterKit action buttons to bind."])
		return
	end
	self.active = true
	self.hovered = nil
	self.perChar = GetCurrentBindingSet() == CHARACTER

	-- texts are set here so a language change applies
	local p = self.panel
	p.title:SetText(L["Keybind mode"])
	p.body:SetText(L["Hover a button and press a key. Shift, Alt and Ctrl work too. Delete clears. Esc to finish."])
	p.check.label:SetText(L["Save for this character only"])
	p.done.text:SetText(L["Done"])
	self:UpdateCheck()
	self:SetStatus(hex(S.colors.muted) .. L["Mouse buttons 4/5, middle click and the mouse wheel work too."] .. "|r")
	p:SetHeight(math.max(p.body:GetStringHeight(), 28) + 96)
	p:Show()
	self.capture:SetPropagateKeyboardInput(true)
	self.capture:Show()
end

function KB:Exit()
	if not self.active then return end
	self.active = false
	self.hovered = nil
	GameTooltip:Hide()
	self:HideOverlays()
	if self.capture then self.capture:Hide() end
	if self.panel then self.panel:Hide() end
end

function CK:ToggleKeybindMode()
	if KB.active then KB:Exit() else KB:Enter() end
end

function KB:OnEnable()
	CK:On("PLAYER_REGEN_DISABLED", function()
		if KB.active then
			KB:Exit()
			CK:Print(L["Keybind mode closed: you entered combat."])
		end
	end)
	-- bars changed while the mode is open: redo the overlays
	CK:Listen("PANEL_LAYOUT", function()
		if KB.active then
			if KB:ShowOverlays() == 0 then KB:Exit() end
		end
	end)
	CK:On("UPDATE_BINDINGS", function()
		if KB.active then KB:UpdateTooltip() end
	end)
end

---------------------------------------------------------------------------
-- Slash command (/ck itself belongs to Core.lua)
---------------------------------------------------------------------------
SLASH_CASTERKITKB1 = "/ckkb"
SlashCmdList.CASTERKITKB = function() CK:ToggleKeybindMode() end
