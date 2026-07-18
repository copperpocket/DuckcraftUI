local addon = select(2,...);
local L = addon.L

-- ============================================================================
-- DuckcraftUI - Game Menu Button Module
-- Injects a "DuckcraftUI" button into the Escape menu that opens the config panel.
-- ============================================================================

local CreateFrame = CreateFrame
local HideUIPanel = HideUIPanel

local function GetGameMenuFrame()
    return _G and _G.GameMenuFrame
end

local duckcraftUIButton = nil
local buttonAdded = false
local heightAdjustedHost = nil
local hookInstalled = false
local updateHookInstalled = false
local onShowHookInstalled = false
local ascensionHookInstalled = false
local CreateDuckcraftUIButton

local KNOWN_MENU_BUTTON_NAMES = {
    "EscapeMenuButton1", -- Ascension custom: Close
    "GameMenuButtonHelp",
    "GameMenuButtonWhatsNew",
    "GameMenuButtonStore",
    "GameMenuButtonOptions",
    "GameMenuButtonUIOptions",
    "GameMenuButtonKeybindings",
    "GameMenuButtonMacros",
    "GameMenuButtonAddons",
    "GameMenuButtonLogout",
    "GameMenuButtonQuit",
    "GameMenuButtonContinue"
}

local function IsDescendantOf(frame, parent)
    if not frame or not parent then return false end
    local current = frame
    while current do
        if current == parent then return true end
        current = current:GetParent()
    end
    return false
end

local function IsAscensionMenuEnvironment()
    if not _G then return false end

    if _G.EscapeMenu and _G.EscapeMenu.IsShown and _G.EscapeMenu:IsShown() then
        return true
    end

    if _G.EscapeMenuButton1 and _G.EscapeMenuButton1.IsShown and _G.EscapeMenuButton1:IsShown() then
        return true
    end

    return false
end

local function DetectCustomMenuHostFrame()
    if not IsAscensionMenuEnvironment() then return nil end

    -- Ascension custom menu host found via fstack.
    if _G.EscapeMenu and _G.EscapeMenu.IsShown and _G.EscapeMenu:IsShown() then
        return _G.EscapeMenu
    end

    if _G.EscapeMenuButton1 then
        local p = _G.EscapeMenuButton1:GetParent()
        if p then return p end
    end

    return nil
end

local function GetMenuHostFrame()
    if IsAscensionMenuEnvironment() then
        local custom = DetectCustomMenuHostFrame()
        if custom then return custom end
    end
    return GetGameMenuFrame()
end

local function FindClassicInsertButton(menuHost)
    local candidates = {
        -- Prefer bottom-area insertion on classic clients.
        "GameMenuButtonContinue",
        "GameMenuButtonQuit",
        "GameMenuButtonLogout",
        "GameMenuButtonAddons",
        "GameMenuButtonMacros",
        "GameMenuButtonKeybindings",
        "GameMenuButtonUIOptions",
        "GameMenuButtonOptions"
    }

    for _, name in ipairs(candidates) do
        local btn = _G[name]
        if btn and btn.IsShown and btn:IsShown() and IsDescendantOf(btn, menuHost) then
            return btn
        end
    end
    return nil
end

local function FindBottomButtons(menuHost)
    local closeButton = _G["EscapeMenuButton1"] or _G["GameMenuButtonContinue"]
    if closeButton and menuHost and (not IsDescendantOf(closeButton, menuHost)) then
        closeButton = nil
    end

    local bottomMost = nil

    local function considerButton(btn)
        if not btn or btn == duckcraftUIButton then return end
        if not (btn.IsShown and btn:IsShown()) then return end
        if not (btn.IsObjectType and btn:IsObjectType("Button")) then return end
        if not IsDescendantOf(btn, menuHost) then return end

        -- Menu buttons in this frame are usually centered and wide.
        local hostCenterX = menuHost:GetCenter()
        local btnCenterX = btn:GetCenter()
        local btnWidth = btn:GetWidth() or 0
        if hostCenterX and btnCenterX and math.abs(btnCenterX - hostCenterX) > 80 then return end
        if btnWidth < 120 then return end

        if (not bottomMost) or ((btn:GetTop() or 0) < (bottomMost:GetTop() or 0)) then
            bottomMost = btn
        end
    end

    for _, name in ipairs(KNOWN_MENU_BUTTON_NAMES) do
        considerButton(_G[name])
    end

    return closeButton, bottomMost
end

-- Anchors the button below its reference and extends GameMenuFrame height once.
local function PositionDuckcraftUIButton()
    local menuHost = GetMenuHostFrame()
    if not menuHost then return end
    if not duckcraftUIButton then return end

    duckcraftUIButton:SetParent(menuHost)
    duckcraftUIButton:SetFrameStrata(menuHost:GetFrameStrata())
    duckcraftUIButton:SetFrameLevel((menuHost:GetFrameLevel() or 1) + 20)

    if IsAscensionMenuEnvironment() then
        local closeButton, bottomMost = FindBottomButtons(menuHost)

        -- Ascension: keep DuckcraftUI near the bottom around Close.
        if closeButton and closeButton:IsShown() then
            duckcraftUIButton:ClearAllPoints()
            duckcraftUIButton:SetPoint("BOTTOM", closeButton, "TOP", 0, -2)
        elseif bottomMost then
            duckcraftUIButton:ClearAllPoints()
            duckcraftUIButton:SetPoint("TOP", bottomMost, "BOTTOM", 0, -2)
        else
            duckcraftUIButton:ClearAllPoints()
            duckcraftUIButton:SetPoint("TOP", menuHost, "TOP", 0, -200)
        end
    else
        -- Classic clients: use original-style insertion anchor.
        local afterButton = FindClassicInsertButton(menuHost)
        duckcraftUIButton:ClearAllPoints()
        if afterButton then
            duckcraftUIButton:SetPoint("TOP", afterButton, "BOTTOM", 0, -2)
        else
            duckcraftUIButton:SetPoint("TOP", menuHost, "TOP", 0, -200)
        end
    end

    -- Grow the frame to accommodate the new button (runs exactly once).
    if heightAdjustedHost ~= menuHost then
        local buttonHeight = duckcraftUIButton:GetHeight() or 16
        local spacing = 1
        local currentHeight = menuHost:GetHeight()
        menuHost:SetHeight(currentHeight + buttonHeight + spacing)
        heightAdjustedHost = menuHost
    end

    -- Custom servers can reset frame height after layout updates.
    -- Ensure our injected button remains inside visible bounds.
    local frameBottom = menuHost:GetBottom()
    local buttonBottom = duckcraftUIButton:GetBottom()
    local bottomPadding = 10
    if frameBottom and buttonBottom and buttonBottom < (frameBottom + bottomPadding) then
        local deficit = (frameBottom + bottomPadding) - buttonBottom
        menuHost:SetHeight(menuHost:GetHeight() + deficit + 2)
    end
end

local function EnsureDuckcraftUIButton()
    if not buttonAdded then
        CreateDuckcraftUIButton()
    elseif duckcraftUIButton then
        duckcraftUIButton:Show()
        PositionDuckcraftUIButton()
    end
end

local function QueueEnsureAfterShow()
    -- Some custom clients re-skin/re-layout asynchronously after opening menu.
    -- Re-apply our button a few times shortly after show.
    local delays = { 0, 0.05, 0.15, 0.35, 0.7 }
    for _, delay in ipairs(delays) do
        addon:After(delay, function()
            local menuHost = GetMenuHostFrame()
            if menuHost and menuHost:IsShown() then
                EnsureDuckcraftUIButton()
            end
        end)
    end
end

local function OpenDuckcraftUIConfig()
    local menuHost = GetMenuHostFrame()
    if menuHost then
        HideUIPanel(menuHost)
    end

    if addon and addon.ToggleOptionsUI then
        addon:ToggleOptionsUI()
        return
    end

    -- ToggleOptionsUI not available yet; fall back to slash command.
    if SlashCmdList and SlashCmdList["DUCKCRAFTUI"] then
        SlashCmdList["DUCKCRAFTUI"]("config")
        return
    end

    print("|cFFFF0000[DuckcraftUI]|r " .. L["Unable to open configuration"])
end

-- ============================================================================
-- BUTTON CREATION
-- ============================================================================

CreateDuckcraftUIButton = function()
    if duckcraftUIButton or buttonAdded then return true end
    local menuHost = GetMenuHostFrame()
    if not menuHost then return false end

    -- Swap to nil to disable and fall back to the solid-color path.
    local TEX_CUSTOM_NORMAL = addon._dir .. "gamemenu_btn.tga"
    local TEX_CUSTOM_HOVER  = nil
    local TEX_CUSTOM_PUSHED = nil

    local FONT      = (addon.Fonts and addon.Fonts.PRIMARY) or "Fonts\\FRIZQT__.TTF"
    local FONT_SIZE = 12

    -- GameMenuButtonTemplate sets the correct hit rect and default sizing.
    duckcraftUIButton = CreateFrame("Button", "DuckcraftUIGameMenuButton", menuHost, "GameMenuButtonTemplate")
    duckcraftUIButton:SetWidth(144)

    local useCustom = TEX_CUSTOM_NORMAL ~= nil

    -- Hide the template's built-in textures so our layers are the only visuals.
    local function hideTemplateTexture(tex)
        if tex then tex:SetAlpha(0) end
    end
    hideTemplateTexture(duckcraftUIButton:GetNormalTexture())
    hideTemplateTexture(duckcraftUIButton:GetHighlightTexture())
    hideTemplateTexture(duckcraftUIButton:GetPushedTexture())

    -- Background layer: 1.5px inset on each edge to leave a thin border gap.
    local bgTex = duckcraftUIButton:CreateTexture(nil, "BACKGROUND")
    bgTex:SetPoint("TOPLEFT",     duckcraftUIButton, "TOPLEFT",     0,  1.5)
    bgTex:SetPoint("BOTTOMRIGHT", duckcraftUIButton, "BOTTOMRIGHT", 0, -1.5)

    if useCustom then
        bgTex:SetTexture(TEX_CUSTOM_NORMAL)
        bgTex:SetTexCoord(0, 1, 0, 1)
        bgTex:SetVertexColor(0.40, 0.65, 1.00)
    else
        local WHITE = "Interface\\Buttons\\WHITE8X8"
        bgTex:SetTexture(WHITE)
        bgTex:SetBlendMode("ADD")
        bgTex:SetVertexColor(0.05, 0.22, 0.60, 1.0)
    end
    duckcraftUIButton._bgTex = bgTex

    -- Hover overlay: additive layer that fades in on mouse-enter.
    local hovTex = duckcraftUIButton:CreateTexture(nil, "ARTWORK")
    hovTex:SetPoint("TOPLEFT",     duckcraftUIButton, "TOPLEFT",     0,  1.5)
    hovTex:SetPoint("BOTTOMRIGHT", duckcraftUIButton, "BOTTOMRIGHT", 0, -1.5)
    if useCustom then
        hovTex:SetTexture(TEX_CUSTOM_NORMAL)
        hovTex:SetTexCoord(0, 1, 0, 1)
        hovTex:SetBlendMode("ADD")
    else
        hovTex:SetTexture("Interface\\Buttons\\WHITE8X8")
        hovTex:SetBlendMode("ADD")
    end
    hovTex:SetVertexColor(0.30, 0.50, 1.00, 0.0)  -- starts transparent
    duckcraftUIButton._hovTex = hovTex

    -- Label
    local label = duckcraftUIButton:GetFontString()
    if label then
        label:SetFont(FONT, FONT_SIZE, "OUTLINE")
        label:SetTextColor(1.0, 1.0, 1.0, 1.0)
        label:SetShadowColor(0.0, 0.10, 0.45, 1.0)
        label:SetShadowOffset(1, -1)
        label:ClearAllPoints()
        label:SetPoint("CENTER", duckcraftUIButton, "CENTER", 0, 1)
        label:SetText(L["DuckcraftUI"])
    end

    -- ============================================================================
    -- HOVER ANIMATION
    -- ============================================================================

    -- RGB tuples for interpolation
    local NRM   = {0.40, 0.65, 1.00}  -- bgTex base color (custom texture)
    local HOV   = {0.70, 0.90, 1.00}  -- bgTex hover color (custom texture)
    local OVR   = {0.05, 0.22, 0.60}  -- bgTex base color (solid fallback)
    local OVR_H = {0.12, 0.40, 0.95}  -- bgTex hover color (solid fallback)
    local TXT   = {1.00, 1.00, 1.00}
    local TXT_H = {1.00, 1.00, 1.00}

    local hoverProgress = 0
    local hoverTarget   = 0
    local ANIM_SPEED    = 5  -- progress units per second (0→1 in ~0.2s)

    duckcraftUIButton:SetScript("OnUpdate", function(self, elapsed)
        if hoverProgress == hoverTarget then return end
        local step = ANIM_SPEED * elapsed
        if hoverTarget > hoverProgress then
            hoverProgress = math.min(hoverProgress + step, 1)
        else
            hoverProgress = math.max(hoverProgress - step, 0)
        end
        local p = hoverProgress
        -- Tint background
        if useCustom then
            self._bgTex:SetVertexColor(
                NRM[1] + (HOV[1] - NRM[1]) * p,
                NRM[2] + (HOV[2] - NRM[2]) * p,
                NRM[3] + (HOV[3] - NRM[3]) * p)
        else
            self._bgTex:SetVertexColor(
                OVR[1] + (OVR_H[1] - OVR[1]) * p,
                OVR[2] + (OVR_H[2] - OVR[2]) * p,
                OVR[3] + (OVR_H[3] - OVR[3]) * p,
                1.0)
        end
        -- Fade in additive glow overlay
        self._hovTex:SetVertexColor(0.30, 0.50, 1.00, 0.25 * p)
        -- Tint label text
        if label then
            label:SetTextColor(
                TXT[1] + (TXT_H[1] - TXT[1]) * p,
                TXT[2] + (TXT_H[2] - TXT[2]) * p,
                TXT[3] + (TXT_H[3] - TXT[3]) * p,
                1.0)
        end
    end)

    duckcraftUIButton:SetScript("OnEnter", function(self) hoverTarget = 1 end)
    duckcraftUIButton:SetScript("OnLeave", function(self) hoverTarget = 0 end)

    duckcraftUIButton:SetScript("OnClick", function(self, button)
        if button == "LeftButton" then OpenDuckcraftUIConfig() end
    end)

    PositionDuckcraftUIButton()
    buttonAdded = true
    return true
end

local function InstallGameMenuHook()
    if hookInstalled then return true end
    local gameMenuFrame = GetGameMenuFrame()
    if not gameMenuFrame then return false end

    -- Hook Show instead of overriding it to avoid UI taint on the secure frame.
    hooksecurefunc(gameMenuFrame, "Show", function(self)
        EnsureDuckcraftUIButton()
        QueueEnsureAfterShow()
    end)

    if not onShowHookInstalled then
        gameMenuFrame:HookScript("OnShow", function(self)
            EnsureDuckcraftUIButton()
            QueueEnsureAfterShow()
        end)
        onShowHookInstalled = true
    end

    -- Many custom clients rebuild button layout every time the menu is shown.
    -- Hook the update routine so our button is re-shown/repositioned afterwards.
    if not updateHookInstalled and _G.GameMenuFrame_UpdateVisibleButtons then
        hooksecurefunc("GameMenuFrame_UpdateVisibleButtons", function()
            EnsureDuckcraftUIButton()
        end)
        updateHookInstalled = true
    end

    if ToggleGameMenu then
        hooksecurefunc("ToggleGameMenu", function()
            QueueEnsureAfterShow()
        end)
    end

    if IsAscensionMenuEnvironment() and (not ascensionHookInstalled) and _G.EscapeMenu and _G.EscapeMenu.HookScript then
        _G.EscapeMenu:HookScript("OnShow", function(self)
            EnsureDuckcraftUIButton()
            QueueEnsureAfterShow()
        end)
        ascensionHookInstalled = true
    end

    hookInstalled = true
    return true
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

-- Retries up to maxAttempts times in case GameMenuFrame isn't ready yet.
local function TryCreateButton()
    local attempts = 0
    local maxAttempts = 20

    local function attempt()
        attempts = attempts + 1
        InstallGameMenuHook()
        if CreateDuckcraftUIButton() then
            QueueEnsureAfterShow()
            return
        end
        if attempts < maxAttempts then
            addon:After(0.5, attempt)
        end
    end

    attempt()
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("ADDON_LOADED")
eventFrame:RegisterEvent("PLAYER_LOGIN")

eventFrame:SetScript("OnEvent", function(self, event, arg1)
    if event == "ADDON_LOADED" and arg1 == "DuckcraftUI" then
        InstallGameMenuHook()
        TryCreateButton()

    elseif event == "PLAYER_LOGIN" then
        -- Second attempt in case the first ran before GameMenuFrame existed.
        addon:After(1.0, function()
            InstallGameMenuHook()
            if not buttonAdded then TryCreateButton() end
        end)
        self:UnregisterEvent("PLAYER_LOGIN")
    end
end)

