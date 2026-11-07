-- Casters of Azeroth by DinX: tooltips (spell explanations etc.) at a fixed, movable spot
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style

local T = CK:NewModule("Tooltip")

local function isActionButton(owner)
	return owner and owner.ckRow ~= nil
end

function T:OnEnable()
	local a = CreateFrame("Frame", "CasterKitTooltipAnchor", UIParent)
	a:SetSize(220, 60)
	self.anchor = a
	S:RegisterMover(a, "tooltip", L["Tooltips"], function(f)
		-- bottom right, above the micro menu panel
		f:SetPoint("BOTTOMRIGHT", UIParent, "BOTTOMRIGHT", -8, 64)
	end)

	-- Every tooltip that uses Blizzard's default anchor (action buttons, unit frames,
	-- units in the world) goes to our anchor instead of next to the mouse.
	hooksecurefunc("GameTooltip_SetDefaultAnchor", function(tooltip, parent)
		if tooltip ~= GameTooltip or tooltip:IsForbidden() then return end
		if not CK.char.tooltip.anchor then return end
		tooltip:SetOwner(parent, "ANCHOR_NONE")
		tooltip:ClearAllPoints()
		tooltip:SetPoint("BOTTOMRIGHT", a, "BOTTOMRIGHT", 0, 0)
	end)

	-- Optional: no spell tooltips from the action bars while fighting
	GameTooltip:HookScript("OnShow", function(tooltip)
		if tooltip:IsForbidden() or not CK.char.tooltip.hideInCombat then return end
		if InCombatLockdown() and isActionButton(tooltip:GetOwner()) then tooltip:Hide() end
	end)

	CK:Listen("SETTINGS", function(group)
		if group == "tooltip" or group == "bars" then
			S:ApplyPoint(a, "tooltip")
			S:UpdateMovers()
		end
	end)
end
