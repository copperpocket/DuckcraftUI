local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- CHARACTER PANEL ENHANCEMENTS
-- Adds Show Helm / Show Cloak checkboxes directly to the Character panel.
-- APIs used (ShowHelm/ShowCloak/ShowingHelm/ShowingCloak) are unprotected in 3.3.5a.
-- ============================================================================

local CharPanelModule = { initialized = false, applied = false }
addon.CharPanelModule = CharPanelModule

if addon.RegisterModule then
    addon:RegisterModule("charpanel", CharPanelModule,
        (L and L["Character Panel"]) or "Character Panel",
        (L and L["Show Helm / Cloak toggles on the character panel"]) or "Show Helm / Cloak toggles on the character panel")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("charpanel")
end

-- Create a labeled checkbox on the character panel.
local function CreateToggle(name, label, point, relativeTo, relativePoint, x, y, onClick, isChecked)
    local cb = CreateFrame("CheckButton", "DuckcraftUI_" .. name, PaperDollFrame, "UICheckButtonTemplate")
    cb:SetWidth(24); cb:SetHeight(24)
    cb:ClearAllPoints()
    cb:SetPoint(point, relativeTo, relativePoint, x, y)
    cb:SetFrameStrata("HIGH")
    local text = _G[cb:GetName() .. "Text"]
    if text then text:SetText(label) end
    cb:SetScript("OnClick", function(self)
        onClick(self:GetChecked() and true or false)
    end)
    cb._sync = function(self) self:SetChecked(isChecked()) end
    cb:Show()
    return cb
end

local function ApplyCharPanel()
    if CharPanelModule.applied or not IsModuleEnabled() then return end
    if not PaperDollFrame or not CharacterModelFrame then return end

    local helmCB = CreateToggle("ShowHelm", (L and L["Helm"]) or "Helm",
        "BOTTOMLEFT", CharacterModelFrame, "BOTTOMLEFT", 10, 50,
        function(show) ShowHelm(show) end,
        function() return ShowingHelm() and true or false end)

    local cloakCB = CreateToggle("ShowCloak", (L and L["Cloak"]) or "Cloak",
        "BOTTOMLEFT", CharacterModelFrame, "BOTTOMLEFT", 10, 26,
        function(show) ShowCloak(show) end,
        function() return ShowingCloak() and true or false end)

    CharPanelModule.helmCB = helmCB
    CharPanelModule.cloakCB = cloakCB

    -- Sync checkbox states whenever the character panel opens
    -- (covers changes made elsewhere, e.g. Interface Options).
    PaperDollFrame:HookScript("OnShow", function()
        if not IsModuleEnabled() then return end
        if helmCB._sync then helmCB:_sync() end
        if cloakCB._sync then cloakCB:_sync() end
    end)

    CharPanelModule.applied = true
end

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if IsModuleEnabled() then ApplyCharPanel() end
end)

-- Expose apply so it can be called after enabling at runtime.
CharPanelModule.Apply = ApplyCharPanel

local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("PLAYER_LOGIN")
eventFrame:SetScript("OnEvent", function()
    if IsModuleEnabled() then ApplyCharPanel() end
end)

-- Also apply the first time the Character panel is shown, in case the module
-- was enabled after login or PaperDollFrame wasn't ready at PLAYER_LOGIN.
if PaperDollFrame then
    PaperDollFrame:HookScript("OnShow", function()
        if IsModuleEnabled() then ApplyCharPanel() end
    end)
end

CharPanelModule.initialized = true

