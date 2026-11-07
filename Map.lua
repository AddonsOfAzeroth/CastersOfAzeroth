-- Casters of Azeroth by DinX: world map
-- A light world map upgrade: coordinates bar, fade while moving, a flat frame and
-- coordinates on the minimap. Display only. (The quest route is in Roads of Azeroth.)
local _, ns = ...
local CK = ns.CK
local L = CK.L
local S = CK.Style
local IsSecret = CK.IsSecret

local MP = CK:NewModule("Map")

local PIN_TEMPLATE = "CasterKitRoutePinTemplate"
local PIN_LEVEL = "PIN_FRAME_LEVEL_AREA_POI" -- known to exist (HereBeDragons uses it)
local MASK = "Interface\\CharacterFrame\\TempPortraitAlphaMask"
local DOT, RING = 17, 21
local LINE_WIDTH = 2.5
local TICK = 0.1

local WMF            -- WorldMapFrame, once it exists
local provider       -- map data provider (nil = fallback mode)
local fallbackPins = {}
local lines = {}
local lineHolder
local playerLine     -- line from the player to the first stop, or nil
local playerX, playerY
local targetLine, targetPin -- white line/pin to the arrow's target (when navigation is off)
local coordsBar, border
local ticker
local fails = 0

---------------------------------------------------------------------------
-- Helpers
---------------------------------------------------------------------------
local function db() return CK.char and CK.char.map end

local function on(key)
	local m = db()
	return m and m.enabled and (key == nil or m[key]) and true or false
end

-- Safe number: nil when secret or not a number
local function num(v)
	if IsSecret(v) or type(v) ~= "number" then return nil end
	return v
end

local function report(tag, err)
	fails = fails + 1
	if CK.debug and fails <= 10 then CK:Print("map " .. tag .. ":", tostring(err)) end
end

-- pcall wrapper for every handler
local function guard(tag, fn, ...)
	local ok, err = pcall(fn, ...)
	if not ok then report(tag, err) end
	return ok
end

local function try(fn, ...)
	if not fn then return end
	local ok, a, b, c = pcall(fn, ...)
	if ok then return a, b, c end
end

local function canvas()
	if not WMF then return end
	if WMF.GetCanvas then
		local c = try(WMF.GetCanvas, WMF)
		if c then return c end
	end
	return WMF.ScrollContainer and WMF.ScrollContainer.Child
end

local function shownMapID()
	if not WMF or not WMF.GetMapID then return end
	return num(try(WMF.GetMapID, WMF))
end

local function isMaximized()
	return WMF and WMF.IsMaximized and try(WMF.IsMaximized, WMF) and true or false
end

-- Player position (0..1) on a map, or nil
local function playerPos(mapID)
	if not mapID or not C_Map or not C_Map.GetPlayerMapPosition then return end
	local pos = try(C_Map.GetPlayerMapPosition, mapID, "player")
	if not pos or not pos.GetXY then return end
	local x, y = try(pos.GetXY, pos)
	x, y = num(x), num(y)
	if not x or not y or (x == 0 and y == 0) then return end
	return x, y
end

local function questTitle(id)
	local t
	if C_QuestLog and C_QuestLog.GetTitleForQuestID then t = try(C_QuestLog.GetTitleForQuestID, id) end
	if (IsSecret(t) or type(t) ~= "string" or t == "") and QuestUtils_GetQuestName then t = try(QuestUtils_GetQuestName, id) end
	if IsSecret(t) or type(t) ~= "string" or t == "" then return "#" .. tostring(id) end
	return t
end

---------------------------------------------------------------------------
-- Coordinates bar
---------------------------------------------------------------------------
-- Blizzard's own coords overlay (some clients), hidden while ours shows
local function blizzardCoords()
	for _, f in ipairs(WMF and WMF.overlayFrames or {}) do
		if type(f) == "table" and f.PlayerCoords and f.CursorCoords then return f end
	end
end

local function createCoords()
	if coordsBar or not WMF or not WMF.ScrollContainer then return end
	local sc = WMF.ScrollContainer
	local f = CreateFrame("Frame", nil, WMF, "BackdropTemplate")
	f:SetHeight(18)
	f:SetPoint("BOTTOMLEFT", sc, "BOTTOMLEFT", 0, 0)
	f:SetPoint("BOTTOMRIGHT", sc, "BOTTOMRIGHT", 0, 0)
	f:SetFrameLevel(math.min(9000, sc:GetFrameLevel() + 1000))
	f:EnableMouse(false)
	S:Backdrop(f, 0.6)
	f.text = S:Font(f, 11)
	f.text:SetPoint("CENTER")
	coordsBar = f
end

local function fmt(x, y)
	return ("%.1f, %.1f"):format(x * 100, y * 100)
end

local function updateCoords()
	if not coordsBar or not coordsBar:IsShown() then return end
	local a = S.colors.accent
	local accent = ("|cff%02x%02x%02x"):format(a[1] * 255, a[2] * 255, a[3] * 255)
	local zone = C_Map and C_Map.GetBestMapForUnit and num(try(C_Map.GetBestMapForUnit, "player"))
	local px, py = playerPos(zone)
	local text = accent .. L["Player"] .. "|r " .. (px and fmt(px, py) or "--")
	local sc = WMF.ScrollContainer
	if sc and sc.GetNormalizedCursorPosition and sc:IsMouseOver() then
		local cx, cy = try(sc.GetNormalizedCursorPosition, sc)
		cx, cy = num(cx), num(cy)
		if cx and cy and cx >= 0 and cx <= 1 and cy >= 0 and cy <= 1 then
			text = text .. "     " .. accent .. L["Cursor"] .. "|r " .. fmt(cx, cy)
		end
	end
	coordsBar.text:SetText(text)
end

---------------------------------------------------------------------------
-- Fade while moving: Blizzard's own fader (CVar mapFade), so we never touch
-- the map's alpha or the fader's frame list
---------------------------------------------------------------------------
local function applyFade()
	local setCVar = C_CVar and C_CVar.SetCVar or SetCVar
	local getCVar = C_CVar and C_CVar.GetCVar or GetCVar
	if not setCVar or not getCVar then return end
	local want = on("fadeMoving") and "1" or "0"
	if not on() then return end
	CK:OutOfCombat("mapFade", function()
		if getCVar("mapFade") ~= want then pcall(setCVar, "mapFade", want) end
	end)
end

---------------------------------------------------------------------------
-- Ticker: one OnUpdate on a child of the map, so it only runs while shown
---------------------------------------------------------------------------
local elapsedTotal = 0
local tickFails = 0

local function tick(elapsed)
	elapsedTotal = elapsedTotal + elapsed
	if elapsedTotal >= TICK then
		elapsedTotal = 0
		if on("coords") then updateCoords() end
	end
end

local function onUpdate(_, elapsed)
	local ok, err = pcall(tick, elapsed)
	if not ok then
		tickFails = tickFails + 1
		report("update", err)
		-- never repeat an error every frame: stop after a few
		if tickFails >= 3 and ticker then ticker:SetScript("OnUpdate", nil) end
	end
end

---------------------------------------------------------------------------
-- Look: scale, border, coords visibility
---------------------------------------------------------------------------
local skinBg
local skinned = {}
local function setArtAlpha(a)
	local bf = WMF.BorderFrame
	if not bf then return end
	local function fade(region)
		if region and region.SetAlpha then
			region:SetAlpha(a)
			skinned[region] = true
		end
	end
	-- textures directly on the border frame (background, title bar, streaks)
	for _, r in ipairs({ bf:GetRegions() }) do
		if r.GetObjectType and r:GetObjectType() == "Texture" then fade(r) end
	end
	fade(bf.NineSlice)
	fade(bf.PortraitContainer)
	fade(bf.Portrait)
	fade(bf.portrait)
	fade(bf.TopTileStreaks)
	fade(bf.InsetBorderTop)
	fade(bf.Tutorial)
	local function fadeTextures(frame)
		if not frame or not frame.GetRegions then return end
		for _, r in ipairs({ frame:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "Texture" then fade(r) end
		end
	end
	-- the map window itself and the quest log side panel
	fadeTextures(WMF)
	local qm = QuestMapFrame
	if qm then
		fadeTextures(qm)
		fade(qm.VerticalSeparator)
		fade(qm.Background)
		local qs = QuestScrollFrame or qm.QuestsFrame and qm.QuestsFrame.ScrollFrame
		if qs then fade(qs.BorderFrame); fade(qs.Background); fade(qs.Edge) end
		if qm.QuestsFrame then fade(qm.QuestsFrame.Background); fade(qm.QuestsFrame.BorderFrame) end
		if qm.DetailsFrame then fade(qm.DetailsFrame.BorderFrame) end
		if qm.MapLegend then fade(qm.MapLegend.BorderFrame) end
		if qm.EventsFrame then fade(qm.EventsFrame.BorderFrame) end
		if qm.CampaignOverview then fade(qm.CampaignOverview.BorderFrame) end
		local count = QuestLogCount or (qm.QuestsFrame and qm.QuestsFrame.QuestLogCount)
		fadeTextures(count)
	end
	-- navigation bar art (its buttons stay)
	local nav = WMF.NavBar
	if nav then
		for _, r in ipairs({ nav:GetRegions() }) do
			if r.GetObjectType and r:GetObjectType() == "Texture" then fade(r) end
		end
		fadeTextures(nav.overlay)
		fade(nav.InsetBorderBottomLeft)
		fade(nav.InsetBorderBottomRight)
		fade(nav.InsetBorderBottom)
		fade(nav.InsetBorderLeft)
		fade(nav.InsetBorderRight)
	end
end

local function applySkin()
	if not WMF then return end
	local want = on() and on("skin")
	if want then
		if not skinBg then
			skinBg = CreateFrame("Frame", nil, WMF, "BackdropTemplate")
			skinBg:SetAllPoints(WMF)
			skinBg:SetFrameLevel(math.max(0, WMF:GetFrameLevel() - 1))
			skinBg:EnableMouse(false)
			S:Backdrop(skinBg)
		end
		skinBg:Show()
		setArtAlpha(0)
	elseif skinBg then
		skinBg:Hide()
		for region in pairs(skinned) do region:SetAlpha(1) end
	end
end

local function applyLook()
	if not WMF then return end
	local enabled = on()
	applySkin()
	createCoords()
	if coordsBar then coordsBar:SetShown(on("coords")) end
	local bc = blizzardCoords()
	if bc then bc:SetAlpha(on("coords") and 0 or 1) end

	if not border and WMF.ScrollContainer then
		border = CreateFrame("Frame", nil, WMF, "BackdropTemplate")
		border:SetPoint("TOPLEFT", WMF.ScrollContainer, "TOPLEFT", -1, 1)
		border:SetPoint("BOTTOMRIGHT", WMF.ScrollContainer, "BOTTOMRIGHT", 1, -1)
		border:SetFrameLevel(math.min(9000, WMF.ScrollContainer:GetFrameLevel() + 999))
		border:EnableMouse(false)
		border:SetBackdrop({ edgeFile = S.flat, edgeSize = 1 })
		border:SetBackdropBorderColor(0, 0, 0, 1)
	end
	if border then border:SetShown(enabled) end

	if ticker then
		if enabled then
			tickFails = 0
			ticker:SetScript("OnUpdate", onUpdate)
		else
			ticker:SetScript("OnUpdate", nil)
		end
	end
	applyFade()
end

function MP:Apply()
	guard("apply", applyLook)
end

---------------------------------------------------------------------------
-- Setup
---------------------------------------------------------------------------
local function setup()
	if WMF or not WorldMapFrame then return end
	WMF = WorldMapFrame
	ticker = CreateFrame("Frame", nil, WMF)
	WMF:HookScript("OnShow", function()
		guard("show", function()
			applyLook()
			if on("coords") then updateCoords() end
		end)
	end)
	MP:Apply()
end

---------------------------------------------------------------------------
-- Coordinates on the minimap (replaces TomTom's coords box)
---------------------------------------------------------------------------
local mmCoords
local function updateMinimapCoords()
	local m = C_Map and C_Map.GetBestMapForUnit and num(try(C_Map.GetBestMapForUnit, "player"))
	local pos = m and C_Map.GetPlayerMapPosition and try(C_Map.GetPlayerMapPosition, m, "player")
	local x, y
	if pos and not IsSecret(pos) and pos.GetXY then x, y = try(pos.GetXY, pos) end
	x, y = num(x), num(y)
	if x and y and (x > 0 or y > 0) then
		mmCoords.text:SetText(("%.1f, %.1f"):format(x * 100, y * 100))
	else
		mmCoords.text:SetText("--")
	end
end

local function applyMinimapCoords()
	if not mmCoords then return end
	if db().minimapCoords then
		S:ApplyPoint(mmCoords, "mmcoords")
		mmCoords:Show()
		updateMinimapCoords()
	else
		mmCoords:Hide()
	end
end

local function setupMinimapCoords()
	if mmCoords or not Minimap then return end
	local f = CreateFrame("Frame", "CasterKitMinimapCoords", UIParent, "BackdropTemplate")
	f:SetSize(70, 16)
	f:SetFrameStrata("MEDIUM")
	f:SetFrameLevel((Minimap:GetFrameLevel() or 1) + 10)
	S:Backdrop(f)
	f.text = S:Font(f, 11)
	f.text:SetPoint("CENTER")
	f.text:SetTextColor(1, 1, 1)
	mmCoords = f
	S:RegisterMover(f, "mmcoords", L["Coordinates"], function(fr)
		fr:SetPoint("BOTTOM", Minimap, "BOTTOM", 0, 4)
	end)
	local elapsed = 0
	f:SetScript("OnUpdate", function(_, e)
		elapsed = elapsed + e
		if elapsed < 0.2 then return end
		elapsed = 0
		if not pcall(updateMinimapCoords) then f.text:SetText("--") end
	end)
	applyMinimapCoords()
end

function MP:OnEnable()
	guard("minimapcoords", setupMinimapCoords)
	if WorldMapFrame then
		guard("setup", setup)
	else
		CK:On("ADDON_LOADED", function(_, name)
			if name == "Blizzard_WorldMap" then guard("setup", setup) end
		end)
	end
end

CK:Listen("SETTINGS", function(group)
	if group == "map" then guard("minimapcoords", applyMinimapCoords) end
	if group == "map" and WMF then MP:Apply() end
end)
