-- CasterKit by DinX: micro menu and bags in one tidy panel
local _, ns = ...
local CK = ns.CK
local S = CK.Style

local M = CK:NewModule("Micro")

-- Order as shown; buttons this client does not have are skipped.
local MICRO = {
	"CharacterMicroButton", "SpellbookMicroButton", "ProfessionMicroButton", "TalentMicroButton",
	"PlayerSpellsMicroButton", "AchievementMicroButton", "LegacyMicroButton", "QuestLogMicroButton", "GuildMicroButton",
	"SocialsMicroButton", "LFDMicroButton", "LFGMicroButton", "PVPMicroButton", "WorldMapMicroButton",
	"CollectionsMicroButton", "EJMicroButton", "StoreMicroButton", "MainMenuMicroButton", "HelpMicroButton",
}
local BAGS = { "MainMenuBarBackpackButton", "CharacterBag0Slot", "CharacterBag1Slot", "CharacterBag2Slot",
	"CharacterBag3Slot", "CharacterReagentBag0Slot", "KeyRingButton" }

local hider = CreateFrame("Frame")
hider:Hide()

function M:CreatePanel()
	local p = CreateFrame("Frame", "CasterKitMicro", UIParent, "BackdropTemplate")
	p:SetMovable(true)
	p:SetClampedToScreen(true)
	p:SetFrameStrata("LOW")
	S:Backdrop(p)
	p:RegisterForDrag("LeftButton")
	p:SetScript("OnDragStart", function(self)
		if not CK.char.bars.locked and not InCombatLockdown() then self:StartMoving() end
	end)
	p:SetScript("OnDragStop", function(self)
		self:StopMovingOrSizing()
		local pt, _, rp, x, y = self:GetPoint()
		CK.char.micro.point = { pt, "UIParent", rp, math.floor(x + 0.5), math.floor(y + 0.5) }
	end)
	self.panel = p

	local free = S:Font(p, 12)
	self.freeText = free
end

local function strip(btn)
	if btn.ckStripped then return end
	btn.ckStripped = true
	local perf = btn.PerformanceIndicator or btn.MainMenuBarPerformanceBar
	if perf then
		perf:SetAlpha(0)
		perf:SetScale(0.00001)
	end
end

function M:Layout()
	if InCombatLockdown() or self.inLayout then return end
	self.inLayout = true
	self:DoLayout()
	self.inLayout = false
end

function M:DoLayout()
	local cfg = CK.char.micro
	local p = self.panel
	if not cfg.enabled then
		p:Hide()
		return
	end
	p:Show()
	p:SetScale(cfg.scale)
	p:ClearAllPoints()
	local pt = cfg.point
	p:SetPoint(pt[1], UIParent, pt[3], pt[4], pt[5])
	p:EnableMouse(not CK.char.bars.locked)

	local pad, gap = 4, 2
	local x = pad
	local height = 0

	if cfg.bags then
		for _, name in ipairs(BAGS) do
			local b = _G[name]
			if b and (name ~= "KeyRingButton" or b:IsShown()) then
				b:SetParent(p)
				b:ClearAllPoints()
				b:SetSize(28, 28)
				b:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", x, pad)
				x = x + 28 + gap
				height = math.max(height, 28)
			end
		end
		x = x + 6
	end

	local first = true
	-- micro buttons this list does not know yet (new in a patch) go at the end
	local container = _G.MicroMenu or _G.MicroMenuContainer
	if container then
		for _, child in ipairs({ container:GetChildren() }) do
			local name = child:GetName()
			if name and name:find("MicroButton$") and not tContains(MICRO, name) then
				MICRO[#MICRO + 1] = name
			end
		end
	end

	for _, name in ipairs(MICRO) do
		local b = _G[name]
		if b and b:IsShown() then
			strip(b)
			b:SetParent(p)
			b:ClearAllPoints()
			b:SetPoint("BOTTOMLEFT", p, "BOTTOMLEFT", x, pad)
			x = x + b:GetWidth() + (first and gap or gap)
			height = math.max(height, b:GetHeight())
			first = false
		end
	end

	p:SetSize(x - gap + pad, height + pad * 2)

	local backpack = _G.MainMenuBarBackpackButton
	if cfg.bags and backpack then
		self.freeText:ClearAllPoints()
		self.freeText:SetPoint("BOTTOMRIGHT", backpack, "BOTTOMRIGHT", -1, 2)
		self.freeText:Show()
		self:UpdateFree()
	else
		self.freeText:Hide()
	end
end

function M:UpdateFree()
	local n = CK:FreeBagSlots()
	self.freeText:SetText(n)
	if n <= 2 then
		self.freeText:SetTextColor(unpack(S.colors.warn))
	else
		self.freeText:SetTextColor(unpack(S.colors.text))
	end
end

function M:HideContainers()
	local mm = _G.MicroMenu
	if mm then
		if mm.BorderArt then mm.BorderArt:SetAlpha(0) end
		if mm.BackgroundArt then mm.BackgroundArt:SetAlpha(0) end
	end
	if CK.char.micro.bags then
		local bb = _G.BagsBar
		if bb then
			CK.HideBlizzardFrame(bb, hider)
		end
		if _G.BagBarExpandToggle then _G.BagBarExpandToggle:SetParent(hider) end
	end
end

function M:Setup()
	self:HideContainers()
	self:Layout()
end

function M:OnEnable()
	self:CreatePanel()
	CK:OutOfCombat("micro", function() self:Setup() end)

	-- Blizzard re-anchors the buttons on many occasions; take them back.
	local function relayout() CK:OutOfCombat("micro-layout", function() self:Layout() end) end
	if UpdateMicroButtons then hooksecurefunc("UpdateMicroButtons", relayout) end
	if UpdateMicroButtonsParent then hooksecurefunc("UpdateMicroButtonsParent", relayout) end
	if _G.MicroMenu and _G.MicroMenu.Layout then hooksecurefunc(_G.MicroMenu, "Layout", relayout) end

	CK:On("BAG_UPDATE_DELAYED", function() if CK.char.micro.bags then self:UpdateFree() end end)
	CK:Listen("SETTINGS", function(group)
		if group == "micro" or group == "bars" then
			CK:OutOfCombat("micro", function() self:Setup() end)
		end
	end)
end
