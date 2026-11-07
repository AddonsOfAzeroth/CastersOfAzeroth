-- CasterKit by DinX: navigation arrow
local _, ns = ...
local CK = ns.CK
local S = CK.Style
local L = CK.L

local AR = CK:NewModule("Arrow")

local IsSecret, Safe = CK.IsSecret, CK.Safe
local atan2 = math.atan2 or function(y, x) return math.atan(y, x) end
local cos, floor, max, min = math.cos, math.floor, math.max, math.min

local ARROW_TEX = "Interface\\Minimap\\MinimapArrow"
local GREEN = { 0.35, 0.85, 0.40 }
local RED = { 0.95, 0.35, 0.30 }
local THROTTLE = 0.05 -- seconds between updates (~20 fps)
local ARRIVE_HOLD = 2 -- seconds of "Arrived" before ARROW_ARRIVED fires
local DEFAULT_SPEED = 7 -- yards per second

local frame, arrow, titleText, infoText
local target -- { mapID, x, y, title, cont, wn, ww, arrivedAt, fired }
local acc = 0
local lastDist
local inCombat = false

-- A plain number, or nil when missing or secret.
local function num(v)
	if v == nil or IsSecret(v) or type(v) ~= "number" then return nil end
	return v
end

---------------------------------------------------------------------------
-- Positions: world coordinates (north, west) plus continent
---------------------------------------------------------------------------
local function worldPosRaw(mapID, x, y)
	local cont, pos = C_Map.GetWorldPosFromMapPos(mapID, CreateVector2D(x, y))
	if not pos then return end
	local n, w = pos:GetXY()
	cont, n, w = num(cont), num(n), num(w)
	if cont and n and w then return cont, n, w end
end

local function worldPos(mapID, x, y)
	if not (mapID and C_Map and C_Map.GetWorldPosFromMapPos and CreateVector2D) then return end
	local ok, cont, n, w = pcall(worldPosRaw, mapID, x, y)
	if ok and cont then return cont, n, w end
end

-- Player's continent and world position; nil in instances or when hidden.
local function playerPos()
	if C_Map and C_Map.GetBestMapForUnit and C_Map.GetPlayerMapPosition then
		local mapID = num(C_Map.GetBestMapForUnit("player"))
		local pos = mapID and C_Map.GetPlayerMapPosition(mapID, "player")
		if pos then
			local x, y = pos:GetXY()
			x, y = num(x), num(y)
			if x and y and (x > 0 or y > 0) then
				local cont, n, w = worldPos(mapID, x, y)
				if cont then return cont, n, w end
			end
		end
	end
	-- fallback: raw world position (may be restricted)
	if UnitPosition then
		local ok, n, w, _, inst = pcall(UnitPosition, "player")
		if ok then
			n, w, inst = num(n), num(w), num(inst)
			if n and w and inst then return inst, n, w end
		end
	end
end

---------------------------------------------------------------------------
-- Display helpers
---------------------------------------------------------------------------
local function blend(a, b, t)
	return a[1] + (b[1] - a[1]) * t, a[2] + (b[2] - a[2]) * t, a[3] + (b[3] - a[3]) * t
end

local function runSpeed()
	local q = CK.char and CK.char.questLearn
	local v = q and num(q.runSpeed)
	if v and v >= 3 and v <= 60 then return v end
	return DEFAULT_SPEED
end

local function formatETA(sec)
	sec = floor(sec + 0.5)
	if sec >= 3600 then
		return "~" .. L["%dh%02d"]:format(floor(sec / 3600), floor(sec % 3600 / 60))
	end
	return ("~%d:%02d"):format(floor(sec / 60), sec % 60)
end

local function distText(d)
	return L["%d yd"]:format(floor(d + 0.5))
end

local function showOther()
	lastDist = nil
	arrow:Hide()
	infoText:SetTextColor(unpack(S.colors.muted))
	infoText:SetText(L["Other zone"])
end

---------------------------------------------------------------------------
-- Update (runs throttled, only while a target is shown)
---------------------------------------------------------------------------
local function update()
	local t = target
	if not t then return end
	if not t.cont then t.cont, t.wn, t.ww = worldPos(t.mapID, t.x, t.y) end
	local cont, pn, pw = playerPos()
	if not cont or not t.cont or cont ~= t.cont then
		t.arrivedAt = nil
		return showOther()
	end

	local dn, dw = t.wn - pn, t.ww - pw
	local dist = (dn * dn + dw * dw) ^ 0.5
	lastDist = dist

	local arrive = num(CK.char.arrow.arriveYards) or 15
	local arrived = dist <= arrive

	-- rotation: 0 = north, counter-clockwise, same as GetPlayerFacing()
	local facing = GetPlayerFacing and num(GetPlayerFacing())
	local r, g, b = unpack(S.colors.accent)
	if facing then
		local rel = atan2(dw, dn) - facing
		arrow:SetRotation(rel)
		arrow:Show()
		local dot = cos(rel) -- 1 = straight ahead, -1 = behind
		if arrived then
			r, g, b = unpack(GREEN)
		elseif dot > 0 then
			r, g, b = blend(S.colors.accent, GREEN, dot * dot * 0.55)
		else
			r, g, b = blend(S.colors.accent, RED, dot * dot * 0.55)
		end
		arrow:SetVertexColor(r, g, b, 1)
	else
		arrow:Hide()
	end

	if arrived then
		local now = GetTime()
		t.arrivedAt = t.arrivedAt or now
		infoText:SetTextColor(unpack(GREEN))
		infoText:SetText(L["Arrived"])
		if not t.fired and now - t.arrivedAt >= ARRIVE_HOLD then
			t.fired = true
			local m, x, y = t.mapID, t.x, t.y
			-- fire outside the protected update so listener errors stay theirs
			C_Timer.After(0, function() CK:Fire("ARROW_ARRIVED", m, x, y) end)
		end
	else
		t.arrivedAt = nil
		infoText:SetTextColor(unpack(S.colors.muted))
		infoText:SetText(distText(dist) .. "  " .. formatETA(dist / runSpeed()))
	end
end

local function onUpdate(self, elapsed)
	acc = acc + elapsed
	if acc < THROTTLE then return end
	acc = 0
	local ok, err = pcall(update)
	if not ok then
		-- stop at the first error; never repeat it every frame
		self:SetScript("OnUpdate", nil)
		if CK.debug then CK:Print("Arrow:", tostring(err)) end
		geterrorhandler()(err)
	end
end

---------------------------------------------------------------------------
-- Frame
---------------------------------------------------------------------------
local function refresh()
	if not frame then return end
	local cfg = CK.char.arrow
	local scale = num(cfg.scale)
	frame:SetScale((scale and scale > 0.3 and scale < 3) and scale or 1)
	if cfg.enabled and target then
		titleText:SetText(target.title or L["Navigation arrow"])
		frame:Show()
		acc = THROTTLE
		frame:SetScript("OnUpdate", onUpdate)
	else
		frame:SetScript("OnUpdate", nil)
		lastDist = nil
		-- show an empty panel while unlocked so it can be dragged
		if not CK.char.bars.locked and not inCombat and not InCombatLockdown() then
			titleText:SetText(L["Navigation arrow"])
			infoText:SetTextColor(unpack(S.colors.muted))
			infoText:SetText("—")
			arrow:SetRotation(0)
			arrow:SetVertexColor(unpack(S.colors.accent))
			arrow:Show()
			frame:Show()
		else
			frame:Hide()
		end
	end
end

local function build()
	if frame or not CK.char then return end
	frame = CreateFrame("Frame", nil, UIParent, "BackdropTemplate")
	frame:SetSize(186, 52)
	frame:SetFrameStrata("MEDIUM")
	S:Backdrop(frame, 0.55)
	frame:Hide()

	arrow = frame:CreateTexture(nil, "ARTWORK")
	arrow:SetSize(42, 42)
	arrow:SetPoint("LEFT", 5, 0)
	arrow:SetTexture(ARROW_TEX)
	arrow:SetDesaturated(true)
	arrow:SetVertexColor(unpack(S.colors.accent))

	titleText = S:Font(frame, 12)
	titleText:SetPoint("TOPLEFT", arrow, "TOPRIGHT", 4, -4)
	titleText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
	titleText:SetJustifyH("LEFT")
	titleText:SetWordWrap(false)
	if titleText.SetMaxLines then titleText:SetMaxLines(1) end

	infoText = S:Font(frame, 11)
	infoText:SetPoint("BOTTOMLEFT", arrow, "BOTTOMRIGHT", 4, 5)
	infoText:SetPoint("RIGHT", frame, "RIGHT", -6, 0)
	infoText:SetJustifyH("LEFT")
	infoText:SetWordWrap(false)
	infoText:SetTextColor(unpack(S.colors.muted))

	frame:EnableMouse(true)
	frame:SetScript("OnMouseUp", function(_, button)
		if button == "RightButton" then AR:Clear() end
	end)
	frame:SetScript("OnEnter", function(self)
		if not target then return end
		GameTooltip:SetOwner(self, "ANCHOR_LEFT")
		GameTooltip:AddLine(target.title or L["Navigation arrow"], 1, 1, 1)
		GameTooltip:AddLine(lastDist and distText(lastDist) or L["Other zone"], unpack(S.colors.text))
		GameTooltip:AddLine(L["Right-click to clear"], unpack(S.colors.muted))
		GameTooltip:Show()
	end)
	frame:SetScript("OnLeave", function() GameTooltip:Hide() end)

	S:RegisterMover(frame, "arrow", L["Navigation arrow"], function(f)
		f:SetPoint("RIGHT", UIParent, "RIGHT", -260, 120)
	end)
	refresh()
end

---------------------------------------------------------------------------
-- Public API
---------------------------------------------------------------------------
-- x, y normalized 0..1 on mapID.
function AR:SetTarget(mapID, x, y, title)
	mapID, x, y = num(mapID), num(x), num(y)
	if not mapID or not x or not y then return end
	-- tolerate 0..100 coordinates
	if x > 1 or y > 1 then x, y = x / 100, y / 100 end
	x, y = max(0, min(1, x)), max(0, min(1, y))
	if type(title) ~= "string" or IsSecret(title) then title = nil end
	target = { mapID = mapID, x = x, y = y, title = title }
	target.cont, target.wn, target.ww = worldPos(mapID, x, y)
	if CK.debug then
		CK:Print(("Arrow: %d %.3f %.3f %s"):format(mapID, x, y, title or ""))
	end
	build()
	refresh()
	CK:Fire("ARROW_TARGET")
end

function AR:Clear()
	target = nil
	lastDist = nil
	if frame and GameTooltip:GetOwner() == frame then GameTooltip:Hide() end
	refresh()
	CK:Fire("ARROW_TARGET")
end

function AR:GetTarget()
	if not target then return nil end
	return target.mapID, target.x, target.y, target.title
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function AR:OnInit()
	build()
end

CK:Listen("SETTINGS", function(group)
	if group == "arrow" or group == "bars" then refresh() end
end)
CK:On("PLAYER_REGEN_DISABLED", function() inCombat = true; refresh() end)
CK:On("PLAYER_REGEN_ENABLED", function() inCombat = false; refresh() end)
