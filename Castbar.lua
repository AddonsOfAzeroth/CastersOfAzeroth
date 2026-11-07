-- CasterKit by DinX: castbar
-- Display only: shows your own and your target's casts, automates nothing.
local _, ns = ...
local CK = ns.CK
local S = CK.Style

local CB = CK:NewModule("Castbar")

local IsSecret = CK.IsSecret
-- Locale table from Locale.lua; missing keys fall back to the English text
local L = CK.L or setmetatable({}, { __index = function(_, k) return k end })

local hider = CreateFrame("Frame")
hider:Hide()

local PLAYER_W, PLAYER_H = 300, 20
local TARGET_W, TARGET_H = 220, 14
local FAIL_TIME = 0.5    -- red flash plus fade after an interrupt
local DONE_TIME = 0.2    -- short fade after a finished cast
local CHECK_EVERY = 0.2  -- running bars re-check that the unit still casts
local LOCK_TEXTURE = "Interface\\PetBattles\\PetBattle-LockIcon"

local DARK = { 0.1, 0.1, 0.12, 0.9 }
local colors = {
	cast = S.colors.accent,
	fail = S.colors.warn,
	kick = { 1.00, 0.70, 0.10 },
	shield = { 0.55, 0.55, 0.58 },
	latency = { 1.00, 0.30, 0.10, 0.55 },
}

local EVENTS = {
	"UNIT_SPELLCAST_START", "UNIT_SPELLCAST_STOP", "UNIT_SPELLCAST_FAILED",
	"UNIT_SPELLCAST_INTERRUPTED", "UNIT_SPELLCAST_DELAYED",
	"UNIT_SPELLCAST_CHANNEL_START", "UNIT_SPELLCAST_CHANNEL_UPDATE", "UNIT_SPELLCAST_CHANNEL_STOP",
	"UNIT_SPELLCAST_INTERRUPTIBLE", "UNIT_SPELLCAST_NOT_INTERRUPTIBLE",
}

local function cfg() return CK.char.units end

-- Plain number, or nil when missing or secret.
local function num(v)
	if IsSecret(v) then return nil end
	if type(v) == "number" then return v end
end

-- true/false when both ids can be compared, nil when unknown.
local function sameID(a, b)
	if IsSecret(a) or IsSecret(b) then return nil end
	if a == nil or b == nil then return nil end
	return a == b
end

-- True when a value is present (a secret value counts as present).
local function present(v)
	if IsSecret(v) then return true end
	return v ~= nil
end

-- Decimal separator from the locale: "." (default) or ","
local function decimal()
	local d = type(L) == "table" and L.decimal
	if d == "," then return "," end
	return "."
end

-- Seconds with one decimal: 1.2 (or 1,2)
local function fmt(sec)
	local s = ("%.1f"):format(sec)
	if decimal() == "," then s = s:gsub("%.", ",") end
	return s
end

local function inCombat()
	return CB.combat or InCombatLockdown()
end

---------------------------------------------------------------------------
-- Cast info
---------------------------------------------------------------------------
-- Returns a table describing the unit's current cast or channel, or nil.
local function readCast(unit)
	if not UnitCastingInfo then return end
	local name, _, texture, startMS, endMS, _, castID, notInt, spellID = UnitCastingInfo(unit)
	local channel = false
	if not present(name) then
		if not UnitChannelInfo then return end
		name, _, texture, startMS, endMS, _, notInt, spellID = UnitChannelInfo(unit)
		castID = nil
		channel = true
		if not present(name) then return end
	end
	local info = {
		name = name, texture = texture, channel = channel, castID = castID, spellID = spellID,
		rawStart = startMS, rawStop = endMS,
		start = num(startMS), stop = num(endMS),
	}
	info.shieldKnown = not IsSecret(notInt)
	info.shield = info.shieldKnown and notInt and true or false
	-- plain times that make no sense: treat as unusable
	if info.start and info.stop and info.stop <= info.start then return end
	return info
end

---------------------------------------------------------------------------
-- Bar methods (copied onto each bar frame)
---------------------------------------------------------------------------
local Bar = {}

local function onUpdate(self, elapsed)
	local ok, err = pcall(self.Tick, self, elapsed)
	if not ok then
		-- never let one bad frame turn into an error stream
		self:SetScript("OnUpdate", nil)
		self.mode = nil
		self:Hide()
		if CK.debug then CK:Print("castbar:", tostring(err)) end
	end
end

function Bar:Enabled()
	local c = cfg()
	if self.isPlayer then return c.castbar end
	return c.targetCastbar
end

function Bar:ApplyLayout()
	local sc = num(cfg().scale) or 1
	if sc <= 0 then sc = 1 end
	local w, h = self.baseW * sc, self.baseH * sc
	self:SetSize(w, h)
	self.innerW = w - 2
	self.icon:SetSize(h, h)
	self.lock:SetSize(h, h)
	local size = math.floor(self.fontSize * sc + 0.5)
	self.text:SetFont(S.font, size, "OUTLINE")
	self.time:SetFont(S.font, size, "OUTLINE")
end

-- Colour the bar; "inverted" is the drain trick for secret channels.
function Bar:ApplyColor(c)
	self.color = c
	local bar = self.bar
	if self.inverted then
		bar:SetStatusBarColor(DARK[1], DARK[2], DARK[3], DARK[4])
		bar.bg:SetColorTexture(c[1], c[2], c[3], 1)
	else
		bar:SetStatusBarColor(c[1], c[2], c[3], 1)
		bar.bg:SetColorTexture(DARK[1], DARK[2], DARK[3], DARK[4])
	end
end

function Bar:ColorFor(info)
	if self.isPlayer then
		self.lock:Hide()
		return colors.cast
	end
	if info.shieldKnown and info.shield then
		self.lock:Show()
		return colors.shield
	end
	self.lock:Hide()
	return colors.kick
end

-- Full bar with just a name, no progress.
function Bar:Static()
	self.static = true
	self.inverted = false
	self.bar:SetReverseFill(false)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(1)
	self.time:SetText("")
	self.latency:Hide()
	self:ApplyColor(self.color or colors.cast)
end

function Bar:UpdateLatency()
	self.latency:Hide()
	if not self.isPlayer or self.channel or self.secret or self.static then return end
	if not cfg().castbarLatency or not GetNetStats then return end
	local _, _, _, world = GetNetStats()
	world = num(world)
	local dur = self.stop - self.start
	if not world or world <= 0 or dur <= 0 then return end
	local w = math.min(world / dur * self.innerW, self.innerW * 0.5)
	if w < 1 then return end
	self.latency:SetWidth(w)
	self.latency:Show()
end

function Bar:Begin(info)
	self.preview = false
	self.mode = info.channel and "channel" or "cast"
	self.channel = info.channel
	self.castID = info.castID
	self.spellID = info.spellID
	self.start, self.stop = info.start, info.stop
	self.secret = (info.start == nil or info.stop == nil)
	self.static = false
	self.inverted = false
	self.stoppedAt = nil
	self.check = 0
	self:SetAlpha(1)
	self.text:SetText(info.name)
	self.icon.icon:SetTexture(info.texture)
	self.icon:Show()
	self.time:SetText("")

	local bar = self.bar
	bar:SetReverseFill(false)
	if self.secret then
		if pcall(bar.SetMinMaxValues, bar, info.rawStart, info.rawStop) then
			-- secret channel: dark reverse fill over a coloured background drains to the left
			if info.channel then
				self.inverted = true
				bar:SetReverseFill(true)
			end
			self:ApplyColor(self:ColorFor(info))
			if not pcall(bar.SetValue, bar, GetTime() * 1000) then self:Static() end
		else
			self.color = self:ColorFor(info)
			self:Static()
		end
	else
		self:ApplyColor(self:ColorFor(info))
		bar:SetMinMaxValues(0, info.stop - info.start)
		bar:SetValue(info.channel and (info.stop - info.start) or 0)
	end
	self:UpdateLatency()
	self:Show()
	self:SetScript("OnUpdate", onUpdate)
end

function Bar:StartFade(len, hold)
	self.mode = "fade"
	self.fadeLen = len
	self.fadeEnd = GetTime() + len + (hold or 0)
	self.stoppedAt = GetTime()
	self:SetScript("OnUpdate", onUpdate)
end

-- Cast or channel ended normally.
function Bar:Finish()
	if not self.secret and not self.static and not self.channel then
		self.bar:SetValue(self.stop - self.start)
	end
	self.latency:Hide()
	self.failed = false
	self:StartFade(DONE_TIME)
end

function Bar:Fail(label)
	self.failed = true
	self.inverted = false
	self.static = true
	self.bar:SetReverseFill(false)
	self.bar:SetMinMaxValues(0, 1)
	self.bar:SetValue(1)
	self:ApplyColor(colors.fail)
	self.text:SetText(label)
	self.time:SetText("")
	self.latency:Hide()
	self.lock:Hide()
	self:SetAlpha(1)
	self:Show()
	self:StartFade(FAIL_TIME * 0.6, FAIL_TIME * 0.4)
end

-- No cast: hide, or show a placeholder while the frames are unlocked.
function Bar:Idle()
	self.mode = nil
	self.failed = false
	self:SetScript("OnUpdate", nil)
	self.latency:Hide()
	self.lock:Hide()
	if self:Enabled() and not CK.char.bars.locked and not inCombat() then
		self.preview = true
		self.inverted = false
		self.static = true
		self.bar:SetReverseFill(false)
		self.bar:SetMinMaxValues(0, 1)
		self.bar:SetValue(0.6)
		self:ApplyColor(self.isPlayer and colors.cast or colors.kick)
		self.text:SetText(self.label)
		self.time:SetText(self.isPlayer and (fmt(1.5) .. " / " .. fmt(2.5)) or fmt(1))
		self.icon.icon:SetTexture(self.isPlayer and 135846 or 136243)
		self:SetAlpha(1)
		self:Show()
	else
		self.preview = false
		self:Hide()
	end
end

function Bar:Tick(elapsed)
	local now = GetTime()
	if self.mode == "fade" then
		local left = self.fadeEnd - now
		if left <= 0 then return self:Idle() end
		self:SetAlpha(math.min(1, left / self.fadeLen))
		return
	end
	if self.mode ~= "cast" and self.mode ~= "channel" then
		self:SetScript("OnUpdate", nil)
		return
	end

	-- hide when the cast vanished without a stop event
	self.check = self.check + elapsed
	if self.check >= CHECK_EVERY then
		self.check = 0
		if not readCast(self.unit) then return self:Idle() end
	end

	if self.static then return end
	local nowMS = now * 1000
	local bar = self.bar
	if self.secret then
		if not pcall(bar.SetValue, bar, nowMS) then self:Static() end
		return
	end

	local dur = self.stop - self.start
	local v
	if self.channel then
		v = self.stop - nowMS
	else
		v = nowMS - self.start
	end
	if v < 0 then v = 0 elseif v > dur then v = dur end
	bar:SetValue(v)
	if self.isPlayer then
		self.time:SetText(fmt(v / 1000) .. " / " .. fmt(dur / 1000))
	else
		local left = self.channel and v or (dur - v)
		self.time:SetText(fmt(left / 1000))
	end
	-- safety: well past the end and still no stop event
	if nowMS > self.stop + 1000 then self:Idle() end
end

-- Re-read the unit and show whatever it is casting now.
function Bar:Refresh()
	if not self:Enabled() then return self:Idle() end
	if not self.isPlayer then
		local exists = UnitExists(self.unit)
		if not IsSecret(exists) and not exists then return self:Idle() end
	end
	local info = readCast(self.unit)
	if info then
		self:Begin(info)
	elseif self.mode ~= "fade" then
		self:Idle()
	end
end

function Bar:OnCastEvent(event, unit, castID, spellID)
	if not self:Enabled() then
		if self.mode or self:IsShown() then self:Idle() end
		return
	end
	if event == "UNIT_SPELLCAST_STOP" or event == "UNIT_SPELLCAST_CHANNEL_STOP" then
		if self.mode ~= "cast" and self.mode ~= "channel" then return end
		local isChannelEvent = (event == "UNIT_SPELLCAST_CHANNEL_STOP")
		if isChannelEvent ~= self.channel then return end
		if not isChannelEvent and sameID(castID, self.castID) == false then return end
		self:Finish()
	elseif event == "UNIT_SPELLCAST_FAILED" or event == "UNIT_SPELLCAST_INTERRUPTED" then
		local recent = self.mode == "fade" and not self.failed and self.stoppedAt and (GetTime() - self.stoppedAt) < 0.5
		if self.mode ~= "cast" and self.mode ~= "channel" and not recent then return end
		-- a failed attempt at another spell must not touch a running channel
		if self.channel and event == "UNIT_SPELLCAST_FAILED" then return end
		if sameID(castID, self.castID) == false then return end
		if sameID(spellID, self.spellID) == false then return end
		self:Fail(event == "UNIT_SPELLCAST_INTERRUPTED" and L["Interrupted"] or L["Failed"])
	else
		-- start, delayed, channel start/update, (not) interruptible
		self:Refresh()
	end
end

---------------------------------------------------------------------------
-- Frames
---------------------------------------------------------------------------
local function safeCall(self, fn, ...)
	local ok, err = pcall(fn, self, ...)
	if not ok then
		self:SetScript("OnUpdate", nil)
		self.mode = nil
		pcall(self.Hide, self)
		if CK.debug then CK:Print("castbar:", tostring(err)) end
	end
end

local function CreateBar(name, unit, w, h, fontSize, label)
	local f = CreateFrame("Frame", name, UIParent, "BackdropTemplate")
	for k, v in pairs(Bar) do f[k] = v end
	f.unit, f.isPlayer, f.label = unit, unit == "player", label
	f.baseW, f.baseH, f.fontSize = w, h, fontSize
	f:SetFrameStrata("MEDIUM")
	S:Backdrop(f, 0.85)

	local bar = S:StatusBar(f, colors.cast)
	bar:SetPoint("TOPLEFT", 1, -1)
	bar:SetPoint("BOTTOMRIGHT", -1, 1)
	f.bar = bar

	-- latency zone at the end of the bar
	local lat = bar:CreateTexture(nil, "OVERLAY", nil, -1)
	lat:SetPoint("TOPRIGHT")
	lat:SetPoint("BOTTOMRIGHT")
	lat:SetColorTexture(colors.latency[1], colors.latency[2], colors.latency[3], colors.latency[4])
	lat:Hide()
	f.latency = lat

	local icon = S:Icon(f, h)
	icon:SetPoint("TOPRIGHT", f, "TOPLEFT", -2, 0)
	f.icon = icon

	local time = S:Font(bar, fontSize)
	time:SetPoint("RIGHT", -4, 0)
	time:SetJustifyH("RIGHT")
	f.time = time

	local text = S:Font(bar, fontSize)
	text:SetPoint("LEFT", 4, 0)
	text:SetPoint("RIGHT", time, "LEFT", -4, 0)
	text:SetJustifyH("LEFT")
	text:SetWordWrap(false)
	f.text = text

	-- padlock for casts you cannot interrupt (target only)
	local lock = f:CreateTexture(nil, "OVERLAY")
	lock:SetPoint("LEFT", f, "RIGHT", 2, 0)
	lock:SetTexture(LOCK_TEXTURE)
	lock:Hide()
	f.lock = lock

	f:ApplyLayout()
	f:Hide()

	for _, e in ipairs(EVENTS) do pcall(f.RegisterUnitEvent, f, e, unit) end
	f:SetScript("OnEvent", function(self, event, ...) safeCall(self, self.OnCastEvent, event, ...) end)
	return f
end

local function placePlayer(f)
	if CK.panel then
		f:SetPoint("BOTTOM", CK.panel, "TOP", 0, 62)
	else
		f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 220)
	end
end

-- Looked up lazily: the target frame may not exist yet at load time.
local function placeTarget(f)
	local tf = _G.CasterKitTargetFrame
	local sc = num(cfg().scale) or 1
	if tf then
		f:SetPoint("TOP", tf, "BOTTOM", 0, -4)
	elseif CK.panel then
		f:SetPoint("BOTTOMRIGHT", CK.panel, "TOPRIGHT", 0, 62 + PLAYER_H * sc + 8)
	else
		f:SetPoint("BOTTOM", UIParent, "BOTTOM", 0, 260)
	end
end

---------------------------------------------------------------------------
-- Blizzard castbars
---------------------------------------------------------------------------
local function killFrame(f)
	if not f or f.__ckHidden then return end
	pcall(function()
		f:UnregisterAllEvents()
		f:Hide()
		f:SetParent(hider)
	end)
	f.__ckHidden = true
	CB.blizzHidden = true
end

function CB:HideBlizzard()
	local c = cfg()
	if not c.hideBlizzardCastbar then
		if self.blizzHidden and not self.toldReload then
			self.toldReload = true
			CK:Print(L["Reload your UI (/reload) to see the Blizzard cast bar again."])
		end
		return
	end
	CK:OutOfCombat("castbar-blizzard", function()
		killFrame(_G.PlayerCastingBarFrame or _G.CastingBarFrame)
		-- only drop the target's spellbar when ours replaces it
		if c.targetCastbar then killFrame(_G.TargetFrameSpellBar) end
	end)
end

---------------------------------------------------------------------------
-- Lifecycle
---------------------------------------------------------------------------
function CB:Place()
	S:ApplyPoint(self.player, "castbar")
	S:ApplyPoint(self.target, "targetcastbar")
end

function CB:ApplyAll()
	for _, f in ipairs({ self.player, self.target }) do
		safeCall(f, f.ApplyLayout)
		safeCall(f, f.Refresh)
	end
	self:Place()
	self:HideBlizzard()
end

function CB:UpdatePreview()
	for _, f in ipairs({ self.player, self.target }) do
		if f.mode == nil then safeCall(f, f.Idle) end
	end
end

function CB:OnEnable()
	self.player = CreateBar("CasterKitCastbar", "player", PLAYER_W, PLAYER_H, 11, L["Cast bar"])
	self.target = CreateBar("CasterKitTargetCastbar", "target", TARGET_W, TARGET_H, 9, L["Target cast bar"])
	S:RegisterMover(self.player, "castbar", L["Cast bar"], placePlayer)
	S:RegisterMover(self.target, "targetcastbar", L["Target cast bar"], placeTarget)

	self:ApplyAll()
	-- the target unit frame may be created later in the login
	C_Timer.After(0, function() self:Place() end)

	CK:On("PLAYER_TARGET_CHANGED", function()
		local f = self.target
		f.mode = nil
		safeCall(f, f.Refresh)
	end)
	CK:On("PLAYER_ENTERING_WORLD", function()
		safeCall(self.player, self.player.Refresh)
		safeCall(self.target, self.target.Refresh)
	end)
	CK:On("PLAYER_REGEN_DISABLED", function()
		self.combat = true
		self:UpdatePreview()
	end)
	CK:On("PLAYER_REGEN_ENABLED", function()
		self.combat = false
		self:UpdatePreview()
	end)
	CK:Listen("PANEL_LAYOUT", function() self:Place() end)
	CK:Listen("SETTINGS", function(group)
		if group == "units" then
			self:ApplyAll()
		elseif group == "bars" then
			self:UpdatePreview()
		end
	end)
end
