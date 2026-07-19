local addon = select(2, ...);
local L = addon.L

-- =============================================================================
-- DUCKCRAFTUI QUEST TRACKER MODULE 
-- =============================================================================

local QuestTrackerModule = {
    initialized = false,
    applied = false,
    originalWatchFramePoint = nil,
}
addon.QuestTrackerModule = QuestTrackerModule

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("questtracker", QuestTrackerModule,
        (addon.L and addon.L["Quest Tracker"]) or "Quest Tracker",
        (addon.L and addon.L["Quest tracker positioning and styling"]) or "Quest tracker positioning and styling")
end

QuestTrackerModule.questTrackerFrame = nil

-- =============================================================================
-- MODULE ENABLED CHECK
-- =============================================================================
local function GetModuleConfig()
    return addon:GetModuleConfig("questtracker")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("questtracker")
end

-- =============================================================================
-- CONFIG SYSTEM (DuckcraftUI style using database)
-- =============================================================================
local function GetQuestTrackerConfig()
    if not (addon.db and addon.db.profile and addon.db.profile.questtracker) then
        return -210, -255, "TOPRIGHT", true -- defaults matching database.lua
    end
    local config = addon.db.profile.questtracker
    return config.x or -210, config.y or -255, config.anchor or "TOPRIGHT", config.show_header ~= false
end

-- Returns the configured font size (defaults to WoW's built-in 11pt if unset)
local function GetQuestFontSize()
    if addon.db and addon.db.profile and addon.db.profile.questtracker then
        return addon.db.profile.questtracker.font_size or 12
    end
    return 12
end

-- Apply the configured font size to all quest tracker text elements.
-- Lines live in WATCHFRAME_QUESTLINES and WATCHFRAME_ACHIEVEMENTLINES as Lua
-- tables each with a .text FontString (and optional .dash FontString).
-- We apply to both to ensure the font change takes effect regardless of type.
local function ApplyQuestTrackerFonts()
    local targetSize = GetQuestFontSize()
    local lineSets = { WATCHFRAME_QUESTLINES, WATCHFRAME_ACHIEVEMENTLINES }
    for _, lineSet in ipairs(lineSets) do
        if lineSet then
            for _, line in ipairs(lineSet) do
                if line then
                    if line.text and line.text.GetFont then
                        local fp, _, fl = line.text:GetFont()
                        if fp then line.text:SetFont(fp, targetSize, fl) end
                    end
                    if line.dash and line.dash.GetFont then
                        local fp, _, fl = line.dash:GetFont()
                        if fp then line.dash:SetFont(fp, targetSize, fl) end
                    end
                end
            end
        end
    end
end

-- =============================================================================
-- TIMER FUNCTIONS FOR 3.3.5 COMPATIBILITY
-- =============================================================================
local timerFrames = {}
local function ScheduleTimer(delay, func)
    local timerFrame = CreateFrame("Frame")
    local elapsed = 0
    timerFrame:SetScript("OnUpdate", function(self, delta)
        elapsed = elapsed + delta
        if elapsed >= delay then
            func()
            self:Hide()
            self:SetScript("OnUpdate", nil)
            timerFrames[self] = nil
        end
    end)
    timerFrame:Show()
    timerFrames[timerFrame] = true
end

-- =============================================================================
-- REPLACE BLIZZARD FRAME (WITH DELAY FIX)
-- =============================================================================
local watchFrameAttached = false

-- Height for quest display — must be set explicitly because SetUserPlaced(true)
-- prevents Blizzard's UIParent_ManageFramePositions from managing WatchFrame size.
-- Without this, WatchFrame_Update calculates maxHeight from tiny/stale bounds
-- and only shows 1-2 quests.
local QUESTTRACKER_MAX_HEIGHT = 600

local function ReplaceBlizzardFrame(frame)
    local watchFrame = WatchFrame
    if not watchFrame then return end

    -- First time: do the full alpha-hide dance to avoid visual glitch
    if not watchFrameAttached then
        watchFrame:SetAlpha(0)
        watchFrame:EnableMouse(false)
        watchFrame:SetMovable(true)
        watchFrame:SetUserPlaced(true)
        watchFrame:ClearAllPoints()
        watchFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        watchFrame:SetHeight(QUESTTRACKER_MAX_HEIGHT)

        -- Reposition WatchFrameLines below header (RetailUI pattern)
        -- This ensures quest lines render below the header background
        if WatchFrameLines and WatchFrameHeader then
            WatchFrameLines:SetPoint("TOPLEFT", WatchFrameHeader, 'BOTTOMLEFT', 0, -15)
        end

        ScheduleTimer(0.1, function()
            if addon.RefreshQuestTrackerVisibility then
                addon.RefreshQuestTrackerVisibility()
            else
                watchFrame:SetAlpha(1)
            end
        end)
        watchFrameAttached = true
    else
        -- Already attached — just silently reposition without alpha flicker
        watchFrame:SetUserPlaced(true)
        watchFrame:ClearAllPoints()
        watchFrame:SetPoint("TOPRIGHT", frame, "TOPRIGHT", 0, 0)
        watchFrame:SetHeight(QUESTTRACKER_MAX_HEIGHT)
    end
end

-- =============================================================================
-- QUEST COUNTING FUNCTIONS (FIXED - includes IsQuestWatched check)
-- =============================================================================
local function GetTrackedQuestsCount()
    local count = 0
    local success, numWatches = pcall(GetNumQuestWatches)
    if success and numWatches then
        for i = 1, numWatches do
            local questIndex = GetQuestIndexForWatch(i)
            if questIndex and IsQuestWatched(questIndex) then
                count = count + 1
            end
        end
    end
    return count
end

-- =============================================================================
-- QUEST TRACKER STYLING (NON-INTRUSIVE APPROACH)
-- =============================================================================
local function ApplyQuestTrackerStyling()
    local watchFrame = WatchFrame
    if not watchFrame or not watchFrame:IsShown() then return end
    if not WatchFrameCollapseExpandButton then return end

    -- Use fixed quest counting
    local trackedQuestsCount = GetTrackedQuestsCount()

    -- Create/update background
    watchFrame.background = watchFrame.background or watchFrame:CreateTexture(nil, 'BACKGROUND')
    local background = watchFrame.background

    -- Apply atlas texture first
    local success, err = pcall(SetAtlasTexture, background, 'QuestTracker-Header')
    if not success then
        return
    end
    
    -- Fixed header positioning (RetailUI pattern)
    -- NOTE: SetSize MUST come AFTER SetAtlasTexture because it overwrites size
    -- Use WatchFrame width to match quest tracker, maintain 8:1 aspect ratio
    local headerWidth = watchFrame:GetWidth() or 230
    local headerHeight = headerWidth / 8  -- Maintain aspect ratio (560/70 = 8)
    background:ClearAllPoints()
    background:SetPoint('RIGHT', WatchFrameCollapseExpandButton, 'RIGHT', 0, 0)
    background:SetSize(headerWidth, headerHeight)  -- Dynamic size matching WatchFrame
    background:SetAlpha(0.9)

    -- Get show_header setting
    local _, _, _, showHeader = GetQuestTrackerConfig()

    -- Hide header when QuestHelper is loaded (its own tracker conflicts visually)
    local questHelperLoaded = IsAddOnLoaded and IsAddOnLoaded("QuestHelper")

    -- Show background only when there are quests, header is enabled, and QuestHelper is not loaded
    if trackedQuestsCount > 0 and showHeader and not questHelperLoaded then
        background:Show()
    else
        background:Hide()
    end
end

-- =============================================================================
-- ENHANCED UPDATE FUNCTION WITH PROTECTION
-- =============================================================================
local updateInProgress = false
local lastUpdateTime = 0

local function ForceUpdateQuestTracker()
    if updateInProgress then return end
    
    local now = GetTime()
    if now - lastUpdateTime < 0.05 then return end -- Faster updates (20/sec max)
    
    updateInProgress = true
    lastUpdateTime = now
    
    -- Ensure WatchFrame has sufficient height BEFORE Blizzard's update runs.
    -- This is critical: WatchFrame_Update calculates maxHeight from GetTop()-GetBottom(),
    -- and without explicit height, the frame shrinks to content → circular limitation.
    if WatchFrame then
        WatchFrame:SetHeight(QUESTTRACKER_MAX_HEIGHT)
    end
    
    -- Trigger Blizzard's native quest tracker update
    -- Our WatchFrame_Update hook handles re-assertion and styling
    if WatchFrame_Update then
        pcall(WatchFrame_Update, WatchFrame)
    end
    
    -- Fallback styling if hooks not yet installed
    if not hooksInstalled then
        pcall(ApplyQuestTrackerStyling)
    end
    
    updateInProgress = false
end

-- =============================================================================
-- POSITION UPDATE
-- =============================================================================
local function UpdateQuestTrackerPosition()
    if QuestTrackerModule.questTrackerFrame then
        local x, y, anchor = GetQuestTrackerConfig()
        QuestTrackerModule.questTrackerFrame:ClearAllPoints()
        QuestTrackerModule.questTrackerFrame:SetPoint(anchor, UIParent, anchor, x, y)
    end
end

-- =============================================================================
-- QUEST TRACKER VISIBILITY / FADE (Option B: independent engine, mirrors stance)
-- Fade WatchFrame itself: it is the real parent of the header, lines, collapse
-- button and background texture, so alpha cascades to all of them. WatchFrame is
-- NOT secure, so SetAlpha is safe in combat. Config: questtracker.visibility
-- =============================================================================

local questVisibilityState = {
    hovered     = false,
    inCombat    = InCombatLockdown(),
    alpha       = 1,
    startAlpha  = 1,
    targetAlpha = 1,
    elapsed     = 0,
    fading      = false,
}

local function GetQuestTrackerVisibilityConfig()
    if addon.db and addon.db.profile and addon.db.profile.questtracker then
        return addon.db.profile.questtracker.visibility
    end
    return nil
end

local function IsCursorOverQuestTracker()
    local wf = WatchFrame
    if not wf then return false end

    local left, right = wf:GetLeft(), wf:GetRight()
    local bottom, top = wf:GetBottom(), wf:GetTop()
    if not left or not right or not bottom or not top then return false end

    local scale = wf:GetEffectiveScale()
    local cursorX, cursorY = GetCursorPosition()
    cursorX = cursorX / scale
    cursorY = cursorY / scale

    return cursorX >= left and cursorX <= right
        and cursorY >= bottom and cursorY <= top
end

local function ShouldShowQuestTracker()
    -- Never fade out while the user is positioning it in editor mode.
    if QuestTrackerModule.editorActive then
        return true
    end

    local config = GetQuestTrackerVisibilityConfig()
    if not config then return true end          -- unconfigured: normal behavior
    if not config.hidden then return true end    -- not hidden by default: normal

    if config.show_on_hover and questVisibilityState.hovered then
        return true
    end
    if config.show_in_combat and questVisibilityState.inCombat then
        return true
    end
    if config.show_with_target and UnitExists("target") then
        return true
    end
    if config.show_on_health then
        local health = UnitHealth("player")
        local maxHealth = UnitHealthMax("player")
        if maxHealth and maxHealth > 0 and health and health < maxHealth then
            return true
        end
    end
    if config.show_on_power then
        local power, maxPower
        if UnitPower and UnitPowerMax then
            power, maxPower = UnitPower("player"), UnitPowerMax("player")
        elseif UnitMana and UnitManaMax then
            power, maxPower = UnitMana("player"), UnitManaMax("player")
        end
        if maxPower and maxPower > 0 and power and power < maxPower then
            return true
        end
    end

    return false
end

local function GetQuestFadeDuration()
    local config = GetQuestTrackerVisibilityConfig()
    return tonumber(config and config.fade_duration) or 0
end

-- Single control point: fade WatchFrame; cascade handles the rest.
local function ApplyQuestTrackerAlpha(alpha)
    if WatchFrame then
        WatchFrame:SetAlpha(alpha)
    end
end

local function StartQuestTrackerFade(shouldShow)
    local state = questVisibilityState
    local targetAlpha = shouldShow and 1 or 0
    local duration = GetQuestFadeDuration()

    local currentAlpha
    if state.fading then
        currentAlpha = state.alpha
    else
        currentAlpha = (WatchFrame and WatchFrame:GetAlpha()) or 1
    end
    currentAlpha = math.max(0, math.min(1, currentAlpha))

    if duration <= 0 or math.abs(currentAlpha - targetAlpha) < 0.001 then
        state.alpha, state.startAlpha, state.targetAlpha = targetAlpha, targetAlpha, targetAlpha
        state.elapsed, state.fading = 0, false
        ApplyQuestTrackerAlpha(targetAlpha)
        return
    end

    state.alpha, state.startAlpha, state.targetAlpha = currentAlpha, currentAlpha, targetAlpha
    state.elapsed, state.fading = 0, true
    ApplyQuestTrackerAlpha(currentAlpha)
end

-- Deferred hide (fade_delay).
local questHideDelay = CreateFrame("Frame")
questHideDelay:Hide()
questHideDelay._elapsed = 0
questHideDelay._target = 0
questHideDelay:SetScript("OnUpdate", function(self, e)
    self._elapsed = self._elapsed + e
    if self._elapsed < self._target then return end
    self:Hide()
    if not ShouldShowQuestTracker() then
        StartQuestTrackerFade(false)
    end
end)

local function RefreshQuestTrackerVisibilityInternal()
    if not IsModuleEnabled() then return end
    if not WatchFrame then return end

    if ShouldShowQuestTracker() then
        questHideDelay:Hide()
        questHideDelay._elapsed = 0
        StartQuestTrackerFade(true)
    else
        local config = GetQuestTrackerVisibilityConfig()
        local delay = tonumber(config and config.fade_delay) or 0
        if delay <= 0 then
            questHideDelay:Hide()
            StartQuestTrackerFade(false)
        elseif not questHideDelay:IsShown() then
            questHideDelay._elapsed = 0
            questHideDelay._target = delay
            questHideDelay:Show()
        end
    end
end

-- Public hook (called by the options manifest, same as stance/buffs).
function addon.RefreshQuestTrackerVisibility()
    if not IsModuleEnabled() then return end
    RefreshQuestTrackerVisibilityInternal()
end

-- Tween engine.
local questFadeFrame = CreateFrame("Frame")
questFadeFrame:Show()
questFadeFrame:SetScript("OnUpdate", function(_, elapsed)
    local state = questVisibilityState
    if not state.fading then return end

    local duration = GetQuestFadeDuration()
    if duration <= 0 then
        state.alpha, state.fading = state.targetAlpha, false
    else
        state.elapsed = state.elapsed + elapsed
        local progress = state.elapsed / duration
        if progress >= 1 then
            state.alpha, state.fading = state.targetAlpha, false
        else
            local eased = progress * progress * (3 - 2 * progress)  -- smoothstep
            state.alpha = state.startAlpha + (state.targetAlpha - state.startAlpha) * eased
        end
    end
    ApplyQuestTrackerAlpha(state.alpha)
end)

-- Hover poll (only active when show_on_hover is enabled).
local questHoverFrame = CreateFrame("Frame")
local questHoverElapsed = 0
questHoverFrame:SetScript("OnUpdate", function(_, elapsed)
    questHoverElapsed = questHoverElapsed + elapsed
    if questHoverElapsed < 0.05 then return end
    questHoverElapsed = 0

    local config = GetQuestTrackerVisibilityConfig()
    if not config or not config.show_on_hover then
        if questVisibilityState.hovered then
            questVisibilityState.hovered = false
            RefreshQuestTrackerVisibilityInternal()
        end
        return
    end

    local hovered = IsCursorOverQuestTracker()
    if hovered ~= questVisibilityState.hovered then
        questVisibilityState.hovered = hovered
        RefreshQuestTrackerVisibilityInternal()
    end
end)

-- Condition drivers (combat / target / health / power).
local questVisibilityEvents = CreateFrame("Frame")
questVisibilityEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
questVisibilityEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
questVisibilityEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
questVisibilityEvents:RegisterEvent("UNIT_HEALTH")
questVisibilityEvents:RegisterEvent("UNIT_MAXHEALTH")
questVisibilityEvents:RegisterEvent("UNIT_HEALTH_FREQUENT")
questVisibilityEvents:RegisterEvent("UNIT_MANA")
questVisibilityEvents:RegisterEvent("UNIT_MAXMANA")
questVisibilityEvents:RegisterEvent("UNIT_RAGE")
questVisibilityEvents:RegisterEvent("UNIT_FOCUS")
questVisibilityEvents:RegisterEvent("UNIT_ENERGY")
questVisibilityEvents:RegisterEvent("UNIT_RUNIC_POWER")
questVisibilityEvents:RegisterEvent("UNIT_MAXPOWER")
questVisibilityEvents:RegisterEvent("UNIT_DISPLAYPOWER")
questVisibilityEvents:SetScript("OnEvent", function(_, event, unit)
    if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        questVisibilityState.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        questVisibilityState.inCombat = false
    end
    RefreshQuestTrackerVisibilityInternal()
end)

-- =============================================================================
-- DUCKCRAFTUI REFRESH FUNCTION
-- =============================================================================
function addon.RefreshQuestTracker()
    if not IsModuleEnabled() then return end
    
    UpdateQuestTrackerPosition()
    ForceUpdateQuestTracker()
    -- A second update after a short delay stabilises font layout:
    -- the first update applies the new font to all FontStrings so their
    -- GetHeight() values are correct; the second update re-runs the
    -- handler layout pass using those correct heights.
    ScheduleTimer(0.05, ForceUpdateQuestTracker)
end

-- =============================================================================
-- INITIALIZATION 
-- =============================================================================
function QuestTrackerModule:Initialize()
    if self.initialized then return end
    
    -- Check if module is enabled
    if not IsModuleEnabled() then
        return
    end

    self.questTrackerFrame = CreateFrame('Frame', 'DuckcraftUI_QuestTrackerFrame', UIParent)
    self.questTrackerFrame:SetSize(230, 32)  -- Anchor frame: minimal height, WatchFrame manages its own size
    self.questTrackerFrame:SetFrameLevel(100)
    self.questTrackerFrame:SetFrameStrata('FULLSCREEN')
    self.questTrackerFrame:EnableMouse(false)
    self.questTrackerFrame:SetMovable(false)
    
    -- Add nineslice overlay for editor mode (DragonflightUI style)
    if addon.AddNineslice then
        addon.AddNineslice(self.questTrackerFrame)
        addon.SetNinesliceState(self.questTrackerFrame, false)
        addon.HideNineslice(self.questTrackerFrame)
        -- Legacy editorTexture reference for compatibility
        self.questTrackerFrame.editorTexture = self.questTrackerFrame.NineSlice and self.questTrackerFrame.NineSlice.Center
    end
    
    -- Create text label for editor mode
    do
        local L = addon.L
        local fontString = self.questTrackerFrame:CreateFontString(nil, "OVERLAY", 'GameFontNormalLarge')
        fontString:SetPoint("CENTER", self.questTrackerFrame, "CENTER", 0, 0)
        fontString:SetText(L and L["Quest Tracker"] or "Quest Tracker")
        fontString:Hide()
        self.questTrackerFrame.editorText = fontString
    end

    -- Save original WatchFrame position for restore
    if WatchFrame then
        local point, relativeTo, relativePoint, x, y = WatchFrame:GetPoint()
        self.originalWatchFramePoint = { point, relativeTo, relativePoint, x, y }
    end

    -- Position the frame
    UpdateQuestTrackerPosition()
    
    -- Replace the frame immediately upon initialization
    ReplaceBlizzardFrame(self.questTrackerFrame)

    -- Register with Editor Mode system
    if addon.RegisterEditableFrame then
        addon:RegisterEditableFrame({
            name = "questtracker",
            frame = self.questTrackerFrame,
            blizzardFrame = WatchFrame,
            configPath = nil,  -- Use custom save logic (handled in OnDragStop)
            showTest = function()
                QuestTrackerModule:ShowEditorTest()
            end,
            hideTest = function()
                QuestTrackerModule:HideEditorTest(true)
            end,
            onShow = function()
                -- Clamp quest tracker to screen when in editor mode
                self.questTrackerFrame:SetClampedToScreen(true)
            end,
            onHide = function()
                -- Remove screen clamp when exiting editor mode
                self.questTrackerFrame:SetClampedToScreen(false)
                -- Position is already saved by OnDragStop
                -- Just update WatchFrame position after editor mode
                UpdateQuestTrackerPosition()
                ReplaceBlizzardFrame(QuestTrackerModule.questTrackerFrame)
                ForceUpdateQuestTracker()
            end,
            module = QuestTrackerModule
        })
    end

    self.initialized = true
    self.applied = true

    -- Apply font immediately so WoW's first render already uses our size
    ApplyQuestTrackerFonts()

    if addon.RefreshQuestTrackerVisibility then
        addon.RefreshQuestTrackerVisibility()
    end

end

-- =============================================================================
-- APPLY/RESTORE SYSTEM
-- =============================================================================
function QuestTrackerModule:ApplySystem()
    if self.applied then return end
    
    if not self.initialized then
        self:Initialize()
        return
    end
    
    if self.questTrackerFrame then
        ReplaceBlizzardFrame(self.questTrackerFrame)
        UpdateQuestTrackerPosition()
        ForceUpdateQuestTracker()
    end
    
    self.applied = true
end

function QuestTrackerModule:RestoreSystem()
    if not self.applied then return end
    
    -- Restore original WatchFrame position
    if WatchFrame and self.originalWatchFramePoint then
        WatchFrame:ClearAllPoints()
        local p = self.originalWatchFramePoint
        WatchFrame:SetPoint(p[1], p[2] or UIParent, p[3], p[4], p[5])
        WatchFrame:SetAlpha(1)
        WatchFrame:EnableMouse(true)
        WatchFrame:SetUserPlaced(false)
    end
    
    -- Hide our frame's background
    if WatchFrame and WatchFrame.background then
        WatchFrame.background:Hide()
    end
    
    self.applied = false
end

-- =============================================================================
-- HOOK SYSTEM WITH PROTECTION (ENHANCED)
-- =============================================================================
local hooksInstalled = false

local function InstallQuestTrackerHooks()
    -- Check that WatchFrame exists and is fully initialized
    if not WatchFrame or hooksInstalled then return end

    -- Hook WatchFrame_Collapse for width adjustment (prevents actual collapse)
    if WatchFrame_Collapse then
        hooksecurefunc('WatchFrame_Collapse', function(self)
            if self then
                self:SetWidth(WATCHFRAME_EXPANDEDWIDTH or 204)
            end
        end)
    end

    -- Hook WatchFrame_Update to keep our visual adjustments without replacing
    -- Blizzard objective layout logic (quests, achievements, timed entries).
    local watchFrameHookActive = false
    if WatchFrame_Update then
        hooksecurefunc('WatchFrame_Update', function()
            if watchFrameHookActive then return end  -- Prevent re-entrancy
            if not IsModuleEnabled() then return end
            if not QuestTrackerModule.initialized then return end

            local watchFrame = WatchFrame
            if not watchFrame then return end

            local lineFrame = WatchFrameLines
            if not lineFrame then return end

            -- Re-assert explicit height (Blizzard may have shrunk it to content)
            watchFrame:SetHeight(QUESTTRACKER_MAX_HEIGHT)

            -- Re-assert WatchFrameLines position (Blizzard may reset it)
            if WatchFrameHeader then
                WatchFrameLines:SetPoint("TOPLEFT", WatchFrameHeader, 'BOTTOMLEFT', 0, -15)
            end

            watchFrameHookActive = true

            -- Apply font after Blizzard layout pass.
            ApplyQuestTrackerFonts()

            -- Apply background styling after layout.
            pcall(ApplyQuestTrackerStyling)

            if addon.RefreshQuestTrackerVisibility then
                addon.RefreshQuestTrackerVisibility()
            end

            watchFrameHookActive = false
        end)
    end

    -- Additional hooks to ensure quests are displayed correctly
    hooksecurefunc('AddQuestWatch', function(questIndex)
        ScheduleTimer(0.05, ForceUpdateQuestTracker)
    end)

    hooksecurefunc('RemoveQuestWatch', function(questIndex)
        ScheduleTimer(0.05, ForceUpdateQuestTracker)
    end)

    -- Keep tracker consistent when tracked achievements are toggled.
    if AddTrackedAchievement then
        hooksecurefunc('AddTrackedAchievement', function()
            ScheduleTimer(0.05, ForceUpdateQuestTracker)
        end)
    end

    if RemoveTrackedAchievement then
        hooksecurefunc('RemoveTrackedAchievement', function()
            ScheduleTimer(0.05, ForceUpdateQuestTracker)
        end)
    end
    
    -- Add hook for abandoning quests
    if AbandonQuest then
        hooksecurefunc('AbandonQuest', function()
            ScheduleTimer(0.05, ForceUpdateQuestTracker)
        end)
    end
    
    -- Add hook for quest log updates
    if QuestLog_Update then
        hooksecurefunc('QuestLog_Update', function()
            ScheduleTimer(0.05, ForceUpdateQuestTracker)
        end)
    end
    
    -- Hook SetCVar for wide/narrow quest tracker toggle (Interface > Display option)
    hooksecurefunc("SetCVar", function(name)
        if name == "watchFrameWidth" then
            ScheduleTimer(0.2, function()
                if not IsModuleEnabled() then return end
                ForceUpdateQuestTracker()
                -- Reattach WatchFrame to our anchor (Blizzard repositions it on width change)
                if QuestTrackerModule.questTrackerFrame then
                    UpdateQuestTrackerPosition()
                    ReplaceBlizzardFrame(QuestTrackerModule.questTrackerFrame)
                end
            end)
        end
    end)

    -- Hook UIParent_ManageFramePositions to prevent Blizzard from overriding our position
    -- WatchFrame is NOT a secure frame, so we can reposition it freely during combat
    if UIParent_ManageFramePositions then
        hooksecurefunc("UIParent_ManageFramePositions", function()
            if not IsModuleEnabled() then return end
            if not QuestTrackerModule.initialized then return end
            if QuestTrackerModule.questTrackerFrame then
                ReplaceBlizzardFrame(QuestTrackerModule.questTrackerFrame)
            end
            -- Re-assert height in case Blizzard touched it
            if WatchFrame then
                WatchFrame:SetHeight(QUESTTRACKER_MAX_HEIGHT)
            end
        end)
    end

    hooksInstalled = true
end

-- =============================================================================
-- EDITOR MODE FUNCTIONS
-- =============================================================================
function QuestTrackerModule:ShowEditorTest()
    if self.questTrackerFrame then
        QuestTrackerModule.editorActive = true
        self.questTrackerFrame:SetMovable(true)
        self.questTrackerFrame:EnableMouse(true)
        self.questTrackerFrame:RegisterForDrag("LeftButton")
        
        -- Update frame size to match WatchFrame dimensions
        if WatchFrame then
            local watchWidth = WatchFrame:GetWidth() or 230
            local watchHeight = WatchFrame:GetHeight() or 200
            self.questTrackerFrame:SetSize(watchWidth, watchHeight)
        end
        
        -- Show nineslice overlay
        if self.questTrackerFrame.NineSlice and addon.ShowNineslice then
            addon.SetNinesliceState(self.questTrackerFrame, false)
            addon.ShowNineslice(self.questTrackerFrame)
        end
        
        -- Show text
        if self.questTrackerFrame.editorText then
            self.questTrackerFrame.editorText:Show()
        end

        -- Click to select in editor panel
        self.questTrackerFrame:SetScript("OnMouseDown", function(frame, button)
            if button == "LeftButton" and addon.SelectEditorFrame then
                addon.SelectEditorFrame(frame)
            end
        end)

        self.questTrackerFrame:SetScript("OnDragStart", function(frame)
            frame:StartMoving()
            -- Ensure selected
            if addon.selectedEditorFrame ~= frame and addon.SelectEditorFrame then
                addon.SelectEditorFrame(frame)
            end
            -- Clear green tint while dragging
            if addon.ClearSelectionTint then
                addon.ClearSelectionTint(frame)
            end
        end)

        self.questTrackerFrame:SetScript("OnDragStop", function(frame)
            frame:StopMovingOrSizing()
            frame:SetScript("OnUpdate", nil)
            -- Re-apply green tint after drop
            if addon.ApplySelectionTint then
                addon.ApplySelectionTint(frame)
            end
            -- Keep quest tracker persistence in TOPRIGHT space so reload position is
            -- stable even when editor-test frame size differs from runtime frame size.
            local screenWidth = UIParent:GetRight()
            local screenHeight = UIParent:GetTop()
            local right = frame:GetRight()
            local top = frame:GetTop()
            if right and top and screenWidth and screenHeight then
                local point = "TOPRIGHT"
                local x = right - screenWidth
                local y = -(screenHeight - top)
                x = math.floor(x + 0.5)
                y = math.floor(y + 0.5)
                -- Re-anchor the frame properly
                frame:ClearAllPoints()
                frame:SetPoint(point, UIParent, point, x, y)
                frame:SetUserPlaced(false)
                -- Save position to DuckcraftUI database
                if addon.db and addon.db.profile then
                    if not addon.db.profile.questtracker then
                        addon.db.profile.questtracker = {}
                    end
                    addon.db.profile.questtracker.anchor = point
                    addon.db.profile.questtracker.x = x
                    addon.db.profile.questtracker.y = y
                end
            end
        end)
    end
end

function QuestTrackerModule:HideEditorTest(savePosition)
    if self.questTrackerFrame then
        QuestTrackerModule.editorActive = false
        self.questTrackerFrame:SetMovable(false)
        self.questTrackerFrame:EnableMouse(false)
        self.questTrackerFrame:SetScript("OnDragStart", nil)
        self.questTrackerFrame:SetScript("OnDragStop", nil)
        self.questTrackerFrame:SetScript("OnMouseDown", nil)
        
        -- Hide nineslice overlay
        if self.questTrackerFrame.NineSlice and addon.HideNineslice then
            addon.HideNineslice(self.questTrackerFrame)
        end
        if self.questTrackerFrame.editorText then
            self.questTrackerFrame.editorText:Hide()
        end

        if savePosition then
            UpdateQuestTrackerPosition()
        end

        if addon.RefreshQuestTrackerVisibility then
            addon.RefreshQuestTrackerVisibility()
        end

    end
end

-- =============================================================================
-- EVENT SYSTEM (WITH DELAYED HOOK INSTALLATION)
-- =============================================================================
local function OnPlayerEnteringWorld()
    -- Check if module is enabled
    if not IsModuleEnabled() then return end

    -- Apply font immediately (before hooks are installed) to avoid visible size jump
    ApplyQuestTrackerFonts()
    ScheduleTimer(0.1, ApplyQuestTrackerFonts)
    ScheduleTimer(0.3, ApplyQuestTrackerFonts)
    ScheduleTimer(0.6, ApplyQuestTrackerFonts)

    -- Reapply position on every world entry (login, reload, zone change)
    -- This counters Blizzard's UIParent_ManageFramePositions overriding us
    ScheduleTimer(0.3, function()
        if QuestTrackerModule.initialized and QuestTrackerModule.questTrackerFrame then
            UpdateQuestTrackerPosition()
            ReplaceBlizzardFrame(QuestTrackerModule.questTrackerFrame)
        end
    end)
    
    -- Set up hooks after world load completion with delay (critical fix)
    if not hooksInstalled then
        ScheduleTimer(1.0, function()
            InstallQuestTrackerHooks()
            ForceUpdateQuestTracker()
        end)
    end
end

-- Quest log update handler with change detection
local lastQuestUpdate = 0
local previousQuestCount = 0

local function OnQuestLogUpdate()
    -- Check if module is enabled
    if not IsModuleEnabled() then return end
    
    local now = GetTime()
    if now - lastQuestUpdate < 0.05 then return end
    lastQuestUpdate = now
    
    -- Only update when quest count actually changes
    local currentQuestCount = GetTrackedQuestsCount()
    if currentQuestCount ~= previousQuestCount then
        previousQuestCount = currentQuestCount
        ScheduleTimer(0.05, ForceUpdateQuestTracker)
    end
end

-- Initialize module
addon.package:RegisterEvents(function()
    if IsModuleEnabled() then
        QuestTrackerModule:Initialize()
    end
end, 'PLAYER_LOGIN')

-- Register PLAYER_ENTERING_WORLD 
addon.package:RegisterEvents(OnPlayerEnteringWorld, 'PLAYER_ENTERING_WORLD')

-- Register quest log update event
addon.package:RegisterEvents(OnQuestLogUpdate, 'QUEST_LOG_UPDATE')

-- Profile change handler
if addon.core and addon.core.RegisterMessage then
    addon.core.RegisterMessage(addon, "DUCKCRAFTUI_PROFILE_CHANGED", function()
        addon.RefreshQuestTracker()
    end)
end
