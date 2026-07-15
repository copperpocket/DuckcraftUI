local addon = select(2, ...)
local UF = addon.UF

-- ====================================================================
-- DRAGONUI PLAYER FRAME - CUSTOM VISIBILITY MODULE
-- ====================================================================
-- Alpha-based visibility (NOT Show/Hide) so it is 100% taint-safe in combat.
-- PlayerFrame is a protected frame; :Hide()/:Show() during combat is blocked.
-- SetAlpha() and EnableMouse() are NOT protected and are safe at all times.
-- ====================================================================

local PlayerFrame = _G.PlayerFrame
local hoverActive = false
local fadeElapsed = 0
local fadeStartAlpha = 1
local fadeTargetAlpha = 1
local fadeActive = false

local hoverFrame = CreateFrame(
    "Frame",
    "DragonUIPlayerFrameVisibilityHover",
    UIParent
)

hoverFrame:SetFrameStrata("TOOLTIP")
hoverFrame:SetFrameLevel(1)
hoverFrame:SetSize(220, 100)
hoverFrame:SetPoint("CENTER", PlayerFrame, "CENTER", 0, 0)
hoverFrame:EnableMouse(false)
hoverFrame:Show()

local function GetVisConfig()
    local cfg = UF and UF.GetConfig and UF.GetConfig("player")
    return cfg and cfg.visibility
end

-- Evaluate whether the frame should be shown right now.
-- Returns true (show) / false (hide).
local function ShouldShow()
    local v = GetVisConfig()
    if not v then return true end

    -- Single master: "Hidden". If not hidden, behave like normal WoW (always shown).
    if not v.hideByDefault then return true end

    -- Hidden by default: reveal only when a checked "Show When" condition is satisfied.
    if v.showInCombat and (InCombatLockdown() or UnitAffectingCombat("player")) then
        return true
    end
    if v.showWithTarget and UnitExists("target") then
        return true
    end
    if v.showOnHealth then
        local cur, max = UnitHealth("player"), UnitHealthMax("player")
        if max > 0 and cur < max then return true end
    end
    if v.showOnMana then
        local cur, max
        if UnitPower and UnitPowerMax then
            cur, max = UnitPower("player"), UnitPowerMax("player")
        else
            cur, max = UnitMana("player"), UnitManaMax("player")
        end
        if max and max > 0 and cur and cur < max then return true end
    end
    if v.showOnHover and hoverActive then
        return true
    end
    if v.advanced and v.advanced ~= "" then
        local ok, result = pcall(SecureCmdOptionParse, v.advanced)
        if ok and result and result ~= "" then return true end
    end

    return false
end



local Vis = {}
addon.PlayerVisibility = Vis

-- Editor mode / safety override: when true, always fully visible.
Vis.forceVisible = false

local function StopFade(targetAlpha)
    fadeActive = false
    fadeElapsed = 0
    fadeStartAlpha = targetAlpha
    fadeTargetAlpha = targetAlpha

    PlayerFrame:SetAlpha(targetAlpha)

    -- EnableMouse IS protected on PlayerFrame; guard it.
    if not InCombatLockdown() then
        if targetAlpha <= 0 then
            PlayerFrame:EnableMouse(false)
        else
            PlayerFrame:EnableMouse(true)
        end
    end
end

local function StartFade(targetAlpha, duration)
    targetAlpha = targetAlpha or 1
    duration = tonumber(duration) or 0

    local currentAlpha = PlayerFrame:GetAlpha() or 1

    if duration <= 0 or math.abs(currentAlpha - targetAlpha) < 0.001 then
        StopFade(targetAlpha)
        return
    end

    fadeElapsed = 0
    fadeStartAlpha = currentAlpha
    fadeTargetAlpha = targetAlpha
    fadeActive = true

    -- Enable interaction immediately when fading in.
    if targetAlpha > 0 and not InCombatLockdown() then
        PlayerFrame:EnableMouse(true)
    end
end

-- Pre-fade delay: wait N seconds before starting a fade-OUT.
local hideDelayFrame = CreateFrame("Frame")
hideDelayFrame:Hide()
hideDelayFrame._elapsed = 0
hideDelayFrame._target = 0

local function CancelHideDelay()
    hideDelayFrame:Hide()
    hideDelayFrame._elapsed = 0
end

hideDelayFrame:SetScript("OnUpdate", function(self, e)
    self._elapsed = self._elapsed + e
    if self._elapsed < self._target then return end
    self:Hide()
    -- Re-check on expiry: only hide if we STILL should hide.
    local config = GetVisConfig()
    if config and not Vis.forceVisible and not UnitHasVehicleUI("player")
       and not ShouldShow() then
        StartFade(0, tonumber(config.fadeDuration) or 0)
    end
end)

local fadeFrame = CreateFrame("Frame")

fadeFrame:SetScript("OnUpdate", function(_, elapsed)
    if not fadeActive or not PlayerFrame then
        return
    end

    local config = GetVisConfig()
    local duration = config and tonumber(config.fadeDuration) or 0

    if duration <= 0 then
        StopFade(fadeTargetAlpha)
        return
    end

    fadeElapsed = fadeElapsed + elapsed

    local progress = fadeElapsed / duration
    if progress >= 1 then
        StopFade(fadeTargetAlpha)
        return
    end

    -- Smooth ease-in/ease-out interpolation.
    local smoothProgress = progress * progress * (3 - 2 * progress)
    local alpha = fadeStartAlpha +
        (fadeTargetAlpha - fadeStartAlpha) * smoothProgress

    PlayerFrame:SetAlpha(alpha)
end)

function Vis.Apply()
    if not PlayerFrame then return end

    local config = GetVisConfig()
    if not config then CancelHideDelay(); StartFade(1, 0); return end

    -- Editor mode / vehicle: always fully visible, no delay.
    if Vis.forceVisible or UnitHasVehicleUI("player") then
        CancelHideDelay()
        StartFade(1, 0)
        return
    end

    if ShouldShow() then
        -- Reveal is always immediate; cancel any pending hide.
        CancelHideDelay()
        StartFade(1, tonumber(config.fadeDuration) or 0)
    else
        -- Hide: honor the pre-fade delay.
        local delay = tonumber(config.fadeDelay) or 0
        if delay <= 0 then
            CancelHideDelay()
            StartFade(0, tonumber(config.fadeDuration) or 0)
        elseif (PlayerFrame:GetAlpha() or 1) > 0.001 and not hideDelayFrame:IsShown() then
            -- Only start a countdown if currently visible and not already counting.
            hideDelayFrame._elapsed = 0
            hideDelayFrame._target = delay
            hideDelayFrame:Show()
        end
    end
end


hoverFrame:SetScript("OnUpdate", function(self)
    if not self:IsShown() then
        return
    end

    local isOver = self:IsMouseOver()

    if isOver ~= hoverActive then
        hoverActive = isOver

        if addon.PlayerVisibility and addon.PlayerVisibility.Apply then
            addon.PlayerVisibility.Apply()
        end
    end
end)

-- ====================================================================
-- EVENTS
-- ====================================================================

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_ENTERING_WORLD")
f:RegisterEvent("PLAYER_REGEN_ENABLED")   -- left combat
f:RegisterEvent("PLAYER_REGEN_DISABLED")  -- entered combat
f:RegisterEvent("PLAYER_TARGET_CHANGED")
-- Health events
f:RegisterEvent("UNIT_HEALTH")
f:RegisterEvent("UNIT_MAXHEALTH")
f:RegisterEvent("UNIT_HEALTH_FREQUENT")

-- WotLK 3.3.5a power events
f:RegisterEvent("UNIT_MANA")
f:RegisterEvent("UNIT_MAXMANA")
f:RegisterEvent("UNIT_RAGE")
f:RegisterEvent("UNIT_FOCUS")
f:RegisterEvent("UNIT_ENERGY")
f:RegisterEvent("UNIT_RUNIC_POWER")

-- Keep these if your AzerothCore client exposes them
f:RegisterEvent("UNIT_POWER_UPDATE")
f:RegisterEvent("UNIT_MAXPOWER")
f:RegisterEvent("UNIT_DISPLAYPOWER")
f:RegisterEvent("UNIT_ENTERED_VEHICLE")
f:RegisterEvent("UNIT_EXITED_VEHICLE")

f:SetScript("OnEvent", function(_, event, unit)
    if unit and event:sub(1, 5) == "UNIT_" and unit ~= "player" then
        return
    end

    Vis.Apply()
end)

-- Public refresh hook for the options panel.
function Vis.Refresh()
    Vis.Apply()
end

-- Force full visibility while the DragonUI editor is active, if the addon
-- exposes an editor-state query. Falls back to a slash-command toggle.
local function HookEditorState()
    if addon.IsEditorMode then
        -- Poll lightly on the frame we already have.
        local poll = CreateFrame("Frame")
        local t = 0
        poll:SetScript("OnUpdate", function(self, e)
            t = t + e
            if t < 0.25 then return end
            t = 0
            local editing = addon.IsEditorMode()
            if editing ~= Vis.forceVisible then
                Vis.forceVisible = editing
                Vis.Apply()
            end
        end)
    end
end
HookEditorState()
