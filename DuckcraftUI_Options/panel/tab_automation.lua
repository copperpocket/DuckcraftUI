--[[
================================================================================
DuckcraftUI Options Panel - Automation Tab
================================================================================
Auto quest accept/turn-in, gossip auto-select, sell junk, auto-repair.
================================================================================
]]

local addon = DuckcraftUI
if not addon then return end

local L = addon.L
local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

local function BuildAutomationTab(scroll)
    C:AddLabel(scroll, "|cffFFD700" .. LO["Automation"] .. "|r", { color = C.Theme.textGold })
    C:AddDescription(scroll, LO["Automate common interactions with NPCs and merchants. Hold Shift when interacting to bypass automation."])
    C:AddSpacer(scroll)

    -- Quests / gossip
    local questSection = C:AddSection(scroll, LO["Quests & Gossip"])
    C:AddToggle(questSection, {
        label = LO["Automate Quests"],
        desc  = LO["Automatically accept, complete, and turn in quests. Quests with a reward choice are left for you to pick."],
        dbPath = "modules.automation.automate_quests",
    })
    C:AddToggle(questSection, {
        label = LO["Automate Gossip"],
        desc  = LO["Automatically select an NPC gossip option when there is only one and no quests are attached."],
        dbPath = "modules.automation.automate_gossip",
    })

    -- Merchant
    local merchantSection = C:AddSection(scroll, LO["Merchant"])
    C:AddToggle(merchantSection, {
        label = LO["Sell Junk"],
        desc  = LO["Automatically sell all grey-quality items when visiting a merchant."],
        dbPath = "modules.automation.sell_junk",
    })
    C:AddToggle(merchantSection, {
        label = LO["Repair"],
        desc  = LO["Automatically repair all equipment when visiting a merchant that offers repairs."],
        dbPath = "modules.automation.repair",
    })
    C:AddToggle(merchantSection, {
        label = LO["Open All Bags"],
        desc  = LO["Open all your bags automatically when visiting a merchant."],
        dbPath = "modules.automation.open_bags",
    })
    C:AddToggle(merchantSection, {
        label = LO["Use Guild Bank for Repairs"],
        desc  = LO["Try guild bank funds before your own gold when repairing."],
        dbPath = "modules.automation.repair_use_guild",
        disabled = function()
            local a = addon.db.profile.modules and addon.db.profile.modules.automation
            return not (a and a.repair)
        end,
    })

    C:AddSpacer(scroll)
end

-- Order 30: alphabetical slot between "Additional Bars" (20) and "Bags".
Panel:RegisterTab("automation", LO["Automation"], BuildAutomationTab, 25)
