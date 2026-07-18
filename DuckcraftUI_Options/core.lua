--[[
================================================================================
DuckcraftUI Options - Core
================================================================================
This file provides the options registration system and initialization.
Based on ElvUI_OptionsUI pattern - accesses DuckcraftUI addon via global.
================================================================================
]]

-- Access the main DuckcraftUI addon (exposed globally in DuckcraftUI/core.lua)
local addon = DuckcraftUI

-- Initialize localization before any fallback/error path uses it.
local L = LibStub("AceLocale-3.0"):GetLocale("DuckcraftUI")
local LO = LibStub("AceLocale-3.0"):GetLocale("DuckcraftUI_Options")

if not addon then
    print("|cFFFF0000[DuckcraftUI_Options]|r " .. ((LO and LO["Error: DuckcraftUI addon not found!"]) or "Error: DuckcraftUI addon not found!"))
    return
end

addon.LO = LO  -- Expose for other option files

-- ============================================================================
-- STATIC POPUP FOR RELOAD
-- ============================================================================

StaticPopupDialogs["DUCKCRAFTUI_RELOAD_UI"] = {
    text = LO["Changing this setting requires a UI reload to apply correctly."],
    button1 = LO["Reload UI"],
    button2 = LO["Not Now"],
    OnAccept = function()
        ReloadUI()
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3
}

StaticPopupDialogs["DUCKCRAFTUI_DELETE_PROFILE"] = {
    text = LO["Are you sure you want to delete the profile '%s'? This cannot be undone."],
    button1 = LO["Delete"],
    button2 = LO["Not Now"],
    OnAccept = function(self)
        local profileName = self.data
        if profileName and addon.db then
            addon.db:DeleteProfile(profileName, true)
            print("|cFF00FF00[DuckcraftUI]|r " .. (LO["Deleted profile: "] or "Deleted profile: ") .. profileName)
            if addon.OptionsPanel then
                addon.OptionsPanel:SelectTab("profiles")
            end
        end
    end,
    timeout = 0,
    whileDead = 1,
    hideOnEscape = 1,
    preferredIndex = 3
}

-- ============================================================================
-- REGISTRATION FUNCTION (kept for backwards compatibility)
-- ============================================================================

-- Register an options group directly to addon.Options.args
-- Retained so any module calling this won't error, but no longer rendered
function addon:RegisterOptionsGroup(name, optionsTable, order)
    if not addon.Options then
        addon.Options = { type = "group", name = "DuckcraftUI", args = {} }
    end
    addon.Options.args[name] = optionsTable
    if order then
        addon.Options.args[name].order = order
    end
end

-- ============================================================================
-- INITIALIZE OPTIONS (called after all option files are loaded)
-- ============================================================================

function addon:InitializeOptions()
    -- Register a minimal BlizzOptions entry that redirects to the custom panel
    addon.Options.args.open_panel = {
        type = "execute",
        name = "|cff1784d1" .. (LO["Open DuckcraftUI Settings"] or "Open DuckcraftUI Settings") .. "|r",
        desc = LO["Open the DuckcraftUI configuration panel."] or "Open the DuckcraftUI configuration panel.",
        func = function()
            local AceConfigDialog = LibStub("AceConfigDialog-3.0")
            if AceConfigDialog then
                AceConfigDialog:Close("DuckcraftUI")
            end
            if addon.OptionsPanel then
                addon.OptionsPanel:Toggle()
            end
        end,
        order = 1,
        width = "full"
    }
    addon.Options.args.info = {
        type = "description",
        name = "\n" .. (LO["Use /duckcraftui to open the full settings panel."] or "Use /duckcraftui to open the full settings panel."),
        order = 2
    }

    LibStub("AceConfig-3.0"):RegisterOptionsTable("DuckcraftUI", addon.Options)
    LibStub("AceConfigDialog-3.0"):AddToBlizOptions("DuckcraftUI", "DuckcraftUI")

    addon.OptionsLoaded = true
end

-- Initialize when this addon finishes loading
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:SetScript("OnEvent", function(self, event, loadedAddon)
    if loadedAddon == "DuckcraftUI_Options" then
        addon:InitializeOptions()
        self:UnregisterAllEvents()
    end
end)
