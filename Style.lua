-- CasterKit by DinX: shared flat look
local _, ns = ...
local CK = ns.CK

local S = {}
CK.Style = S

S.flat = "Interface\\Buttons\\WHITE8x8"
S.font = STANDARD_TEXT_FONT
S.colors = {
	bg = { 0.04, 0.05, 0.08, 0.85 },
	border = { 0, 0, 0, 1 },
	edge = { 0.16, 0.19, 0.25, 1 },
	accent = { 0.41, 0.80, 0.94 },    -- mage blue
	text = { 0.91, 0.93, 0.95 },
	muted = { 0.60, 0.65, 0.71 },
	warn = { 0.95, 0.30, 0.30 },
	hint = { 1.00, 0.82, 0.25 },
	proc = { 0.85, 0.45, 1.00 },
	xp = { 0.58, 0.36, 0.86 },
	rested = { 0.25, 0.55, 0.95 },
}

-- 1px black border plus dark fill, the classic "ElvUI" panel.
function S:Backdrop(frame, alpha)
	if not frame.SetBackdrop then Mixin(frame, BackdropTemplateMixin) end
	frame:SetBackdrop({ bgFile = self.flat, edgeFile = self.flat, edgeSize = 1 })
	local c = self.colors.bg
	frame:SetBackdropColor(c[1], c[2], c[3], alpha or c[4])
	frame:SetBackdropBorderColor(0, 0, 0, 1)
end

function S:Font(parent, size, layer)
	local fs = parent:CreateFontString(nil, layer or "OVERLAY")
	fs:SetFont(self.font, size or 12, "OUTLINE")
	fs:SetTextColor(unpack(self.colors.text))
	return fs
end

function S:StatusBar(parent, color)
	local bar = CreateFrame("StatusBar", nil, parent)
	bar:SetStatusBarTexture(self.flat)
	if color then bar:SetStatusBarColor(unpack(color)) end
	local bg = bar:CreateTexture(nil, "BACKGROUND")
	bg:SetAllPoints()
	bg:SetColorTexture(0.1, 0.1, 0.12, 0.9)
	bar.bg = bg
	return bar
end

-- Square icon with border, used for reminders and the rotation hint.
function S:Icon(parent, size)
	local f = CreateFrame("Frame", nil, parent, "BackdropTemplate")
	f:SetSize(size, size)
	self:Backdrop(f, 1)
	local tex = f:CreateTexture(nil, "ARTWORK")
	tex:SetPoint("TOPLEFT", 1, -1)
	tex:SetPoint("BOTTOMRIGHT", -1, 1)
	tex:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	f.icon = tex
	return f
end

local function kill(region)
	if region then
		region:SetAlpha(0)
		if region.Hide then region:Hide() end
	end
end

-- Flatten a LibActionButton / ActionButtonTemplate button.
function S:SkinButton(btn)
	if btn.__ckSkinned then return end
	btn.__ckSkinned = true

	local icon = btn.icon or btn.Icon
	if btn.IconMask and icon then
		icon:RemoveMaskTexture(btn.IconMask)
		btn.IconMask:Hide()
	end
	kill(btn:GetNormalTexture())
	hooksecurefunc(btn, "SetNormalTexture", function(b)
		local nt = b:GetNormalTexture()
		if nt then nt:SetAlpha(0) end
	end)
	if btn.SetNormalAtlas then
		hooksecurefunc(btn, "SetNormalAtlas", function(b)
			local nt = b:GetNormalTexture()
			if nt then nt:SetAlpha(0) end
		end)
	end
	kill(btn.NormalTexture)
	kill(btn.SlotArt)
	kill(btn.SlotBackground)
	kill(btn.Border)
	kill(btn.FloatingBG)
	if btn.RightDivider then kill(btn.RightDivider) end
	if btn.BottomDivider then kill(btn.BottomDivider) end

	if icon then
		icon:ClearAllPoints()
		icon:SetPoint("TOPLEFT", 1, -1)
		icon:SetPoint("BOTTOMRIGHT", -1, 1)
		icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
	end

	local bg = btn:CreateTexture(nil, "BACKGROUND", nil, -8)
	bg:SetAllPoints()
	bg:SetColorTexture(0, 0, 0, 1)
	local inner = btn:CreateTexture(nil, "BACKGROUND", nil, -7)
	inner:SetPoint("TOPLEFT", 1, -1)
	inner:SetPoint("BOTTOMRIGHT", -1, 1)
	inner:SetColorTexture(0.10, 0.12, 0.17, 1)

	if btn.cooldown then
		btn.cooldown:ClearAllPoints()
		btn.cooldown:SetPoint("TOPLEFT", 1, -1)
		btn.cooldown:SetPoint("BOTTOMRIGHT", -1, 1)
		btn.cooldown:SetSwipeColor(0, 0, 0, 0.75)
	end

	local hl = btn:GetHighlightTexture()
	if hl then
		hl:SetColorTexture(1, 1, 1, 0.15)
		hl:SetPoint("TOPLEFT", 1, -1)
		hl:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	local pushed = btn:GetPushedTexture()
	if pushed then
		pushed:SetColorTexture(0.9, 0.8, 0.1, 0.3)
		pushed:SetPoint("TOPLEFT", 1, -1)
		pushed:SetPoint("BOTTOMRIGHT", -1, 1)
	end
	if btn.GetCheckedTexture and btn:GetCheckedTexture() then
		local ch = btn:GetCheckedTexture()
		ch:SetColorTexture(0.41, 0.80, 0.94, 0.25)
		ch:SetPoint("TOPLEFT", 1, -1)
		ch:SetPoint("BOTTOMRIGHT", -1, 1)
	end
end
