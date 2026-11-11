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
			right = function() CK.char.bars.locked = not CK.char.bars.locked CK:Fire("SETTINGS", "bars") CK:Fire("SETTINGS", "micro") end,
			shift = function() if CK.ToggleKeybindMode then CK:ToggleKeybindMode() end end,
			middle = function() if CK.ToggleAoE then CK:ToggleAoE() end end,
			tip = function(tt)
				local L = CK.L
				tt:AddLine(L["Click: settings"], 1, 1, 1)
				tt:AddLine(L["Right-click: lock/unlock frames"], 1, 1, 1)
				tt:AddLine(L["Middle-click: AoE mode"], 1, 1, 1)
				tt:AddLine(L["Shift-click: keybind mode"], 1, 1, 1)
			end,
		})
		-- our own button: the shared one takes its place
		local own = _G.CasterKitMinimapButton
		if own then own:Hide() own:SetScript("OnShow", own.Hide) end
	end)
end)
