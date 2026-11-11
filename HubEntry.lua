-- Casters of Azeroth by DinX: its line in the "Addons of Azeroth" minimap list (Hub.lua).
local ADDON, ns = ...

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
	C_Timer.After(0, function()
		local hub = _G.AddonsOfAzerothHub
		if not hub then return end
		local CK = ns.CK
		hub:Register({
			key = "casters", addon = ADDON,
			click = function() CK:ToggleConfig() end,
			minimap = function() return CK.db and CK.db.minimap end,
		})
		-- our own button: the shared one takes its place
		local own = _G.CasterKitMinimapButton
		if own then own:Hide() own:SetScript("OnShow", own.Hide) end
	end)
end)
