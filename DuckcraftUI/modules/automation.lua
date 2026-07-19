local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- AUTOMATION MODULE FOR DUCKCRAFTUI
-- Quest accept/turn-in, gossip auto-select, sell greys, auto-repair.
-- All APIs used here are unprotected in 3.3.5a (safe in and out of combat).
-- ============================================================================

local AutomationModule = { initialized = false }
addon.AutomationModule = AutomationModule

if addon.RegisterModule then
    addon:RegisterModule("automation", AutomationModule,
        (addon.L and addon.L["Automation"]) or "Automation",
        (addon.L and addon.L["Automate quests, gossip, selling junk, and repairs"]) or "Automate quests, gossip, selling junk, and repairs")
end

-- ----------------------------------------------------------------------------
-- CONFIG HELPERS
-- ----------------------------------------------------------------------------
local function GetConfig()
    return addon:GetModuleConfig("automation")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("automation")
end

-- true only if module is enabled AND the given sub-option is on AND shift is up
local function Active(key)
    if IsShiftKeyDown() then return false end   -- manual override
    local cfg = GetConfig()
    return cfg and cfg[key] == true
end

local function Print(msg)
    if addon.Print then addon:Print(msg) else print("|cff1784d1DuckcraftUI:|r " .. msg) end
end

local function AutoOpenBags()
    if not Active("open_bags") then return end
    OpenBackpack()
    for bag = 1, 4 do
        OpenBag(bag)
    end
end

-- ----------------------------------------------------------------------------
-- QUEST AUTOMATION
-- ----------------------------------------------------------------------------
local function AutoQuestGreeting()
    if not Active("automate_quests") then return end
    -- Classic multi-quest greeting frame (QUEST_GREETING)
    local numActive = GetNumActiveQuests and GetNumActiveQuests() or 0
    for i = 1, numActive do
        SelectActiveQuest(i)
    end
    local numAvailable = GetNumAvailableQuests and GetNumAvailableQuests() or 0
    for i = 1, numAvailable do
        SelectAvailableQuest(i)
    end
end

local function AutoQuestDetail()
    if not Active("automate_quests") then return end
    AcceptQuest()
end

local function AutoQuestProgress()
    if not Active("automate_quests") then return end
    if IsQuestCompletable() then
        CompleteQuest()
    end
end

local function AutoQuestComplete()
    if not Active("automate_quests") then return end
    local choices = GetNumQuestChoices() or 0
    -- Only auto-turn-in when there is no meaningful reward choice to make.
    if choices <= 1 then
        GetQuestReward(1)   -- index ignored when 0 choices; picks the single item when 1
    end
end

-- ----------------------------------------------------------------------------
-- GOSSIP AUTOMATION
-- ----------------------------------------------------------------------------
local function AutoGossip()
    if IsShiftKeyDown() then return end
    local cfg = GetConfig()
    if not cfg then return end

    -- If quest automation is on, grab gossip-attached quests first.
    if cfg.automate_quests then
        local numActive = GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
        for i = 1, numActive do
            SelectGossipActiveQuest(i)
        end
        local numAvailable = GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
        for i = 1, numAvailable do
            SelectGossipAvailableQuest(i)
        end
    end

    -- Gossip option auto-select: only when it's unambiguous.
    if cfg.automate_gossip then
        -- GetGossipOptions returns text,type pairs -> option count = returns/2
        local optionCount = select("#", GetGossipOptions()) / 2
        local availQuests  = GetNumGossipAvailableQuests and GetNumGossipAvailableQuests() or 0
        local activeQuests = GetNumGossipActiveQuests and GetNumGossipActiveQuests() or 0
        if optionCount == 1 and availQuests == 0 and activeQuests == 0 then
            SelectGossipOption(1)
        end
    end
end

-- ----------------------------------------------------------------------------
-- MERCHANT: SELL JUNK (throttled) + REPAIR
-- ----------------------------------------------------------------------------
local sellQueueFrame = CreateFrame("Frame")
sellQueueFrame:Hide()
local sellTotal = 0
local sellElapsed = 0
local SELL_INTERVAL = 0.2   -- seconds between sells

sellQueueFrame:SetScript("OnUpdate", function(self, e)
    sellElapsed = sellElapsed + e
    if sellElapsed < SELL_INTERVAL then return end
    sellElapsed = 0

    -- Merchant window may have closed mid-sale.
    if not MerchantFrame or not MerchantFrame:IsShown() then
        self:Hide()
        return
    end

    -- Find and sell the next grey with a sell price.
    for bag = 0, 4 do
        local slots = GetContainerNumSlots(bag) or 0
        for slot = 1, slots do
            local _, count, locked = GetContainerItemInfo(bag, slot)
            if not locked then
                local link = GetContainerItemLink(bag, slot)
                if link then
                    local _, _, quality, _, _, _, _, _, _, _, sellPrice = GetItemInfo(link)
                    if quality == 0 and sellPrice and sellPrice > 0 then
                        sellTotal = sellTotal + (sellPrice * (count or 1))
                        UseContainerItem(bag, slot)
                        return
                    end
                end
            end
        end
    end

    -- Nothing left to sell: finish and report.
    self:Hide()
    if sellTotal > 0 then
        Print(format((L and L["Sold junk for %s"]) or "Sold junk for %s",
            GetCoinTextureString and GetCoinTextureString(sellTotal) or (sellTotal .. "c")))
    end
    sellTotal = 0
end)

local function StartSellJunk()
    if not Active("sell_junk") then return end
    sellTotal = 0
    sellElapsed = SELL_INTERVAL   -- sell first item immediately on next tick
    sellQueueFrame:Show()
end

local function AutoRepair()
    if not Active("repair") then return end
    if not (CanMerchantRepair and CanMerchantRepair()) then return end

    local cost = GetRepairAllCost()
    if not cost or cost <= 0 then return end

    local cfg = GetConfig()
    local coin = GetCoinTextureString and GetCoinTextureString(cost) or (cost .. "c")

    -- Guild funds first, if requested and available.
    if cfg and cfg.repair_use_guild and CanGuildBankRepair and CanGuildBankRepair() then
        local guildAvailable = GetGuildBankWithdrawMoney and GetGuildBankWithdrawMoney() or 0
        -- -1 means unlimited withdraw for guild leader.
        if guildAvailable == -1 or guildAvailable >= cost then
            RepairAllItems(true)
            Print(format((L and L["Repaired with guild funds (%s)"]) or "Repaired with guild funds (%s)", coin))
            return
        end
    end

    -- Personal gold fallback.
    if GetMoney() >= cost then
        RepairAllItems(false)
        Print(format((L and L["Repaired for %s"]) or "Repaired for %s", coin))
    else
        Print((L and L["Not enough money to repair."]) or "Not enough money to repair.")
    end
end

-- ----------------------------------------------------------------------------
-- EVENTS
-- ----------------------------------------------------------------------------
local eventFrame = CreateFrame("Frame")
eventFrame:RegisterEvent("QUEST_GREETING")
eventFrame:RegisterEvent("QUEST_DETAIL")
eventFrame:RegisterEvent("QUEST_PROGRESS")
eventFrame:RegisterEvent("QUEST_COMPLETE")
eventFrame:RegisterEvent("GOSSIP_SHOW")
eventFrame:RegisterEvent("MERCHANT_SHOW")

eventFrame:SetScript("OnEvent", function(_, event)
    if event == "QUEST_GREETING" then
        AutoQuestGreeting()
    elseif event == "QUEST_DETAIL" then
        AutoQuestDetail()
    elseif event == "QUEST_PROGRESS" then
        AutoQuestProgress()
    elseif event == "QUEST_COMPLETE" then
        AutoQuestComplete()
    elseif event == "GOSSIP_SHOW" then
        AutoGossip()
    elseif event == "MERCHANT_SHOW" then
        AutoRepair()      -- repair first so junk-sale gold isn't needed for it
        StartSellJunk()
        AutoOpenBags()
    end
end)

AutomationModule.initialized = true
