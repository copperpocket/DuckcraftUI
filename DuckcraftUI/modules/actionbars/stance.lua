local addon = select(2,...);
local config = addon.config;
local event = addon.package;
local class = addon._class;
local unpack = unpack;
local select = select;
local pairs = pairs;
local _G = getfenv(0);

-- ============================================================================
-- STANCE MODULE FOR DUCKCRAFTUI
-- ============================================================================

-- Module state tracking
local StanceModule = {
    initialized = false,
    applied = false,
    originalStates = {},     -- Store original states for restoration
    registeredEvents = {},   -- Track registered events
    hooks = {},             -- Track hooked functions
    stateDrivers = {},      -- Track state drivers
    frames = {}             -- Track created frames
}

-- Register with ModuleRegistry (if available)
if addon.RegisterModule then
    addon:RegisterModule("stance", StanceModule,
        (addon.L and addon.L["Stance Bar"]) or "Stance Bar",
        (addon.L and addon.L["Stance/shapeshift bar positioning and styling"]) or "Stance/shapeshift bar positioning and styling")
end

-- ============================================================================
-- CONFIGURATION FUNCTIONS
-- ============================================================================

local function GetModuleConfig()
    return addon:GetModuleConfig("stance")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("stance")
end

-- Nil-safe accessor for stance-specific config (addon.db.profile.additional.stance)
-- IMPORTANT: Keep in sync with database.lua → additional.stance
local STANCE_DEFAULTS = {
    x_position = -211,
    y_offset = -60,
    button_size = 31,
    button_spacing = 6,
}
local function GetStanceConfig()
    if addon.db and addon.db.profile and addon.db.profile.additional and addon.db.profile.additional.stance then
        return addon.db.profile.additional.stance
    end
    return STANCE_DEFAULTS
end

-- ============================================================================
-- CONSTANTS AND VARIABLES
-- ============================================================================

-- const
local InCombatLockdown = InCombatLockdown;
local GetNumShapeshiftForms = GetNumShapeshiftForms;
local GetShapeshiftFormInfo = GetShapeshiftFormInfo;
local GetShapeshiftFormCooldown = GetShapeshiftFormCooldown;
local CreateFrame = CreateFrame;
local UIParent = UIParent;
local hooksecurefunc = hooksecurefunc;
local UnitAffectingCombat = UnitAffectingCombat;

-- WOTLK 3.3.5a Constants
local NUM_SHAPESHIFT_SLOTS = 10; -- Fixed value for 3.3.5a compatibility

local stance = {
	['DEATHKNIGHT'] = '[vehicleui] hide; show',
	['DRUID'] = '[vehicleui] hide; show',
	['PALADIN'] = '[vehicleui] hide; show',
	['PRIEST'] = '[vehicleui] hide; show',
	['ROGUE'] = '[vehicleui] hide; show',
	['WARLOCK'] = '[vehicleui] hide; show',
	['WARRIOR'] = '[vehicleui] hide; show'
};

-- Module frames (created only when enabled)
local anchor, stancebar

-- Initialize MultiBar references
local MultiBarBottomLeft = _G["MultiBarBottomLeft"]
local MultiBarBottomRight = _G["MultiBarBottomRight"]

-- Simple initialization tracking
local stanceBarInitialized = false;

-- SIMPLE STATIC POSITIONING - NO DYNAMIC LOGIC
local function stancebar_update()
    if not IsModuleEnabled() or not anchor then return end
    if InCombatLockdown() then return end  -- Cannot modify secure frame in combat
    
    -- READ VALUES FROM DATABASE
    local stanceConfig = GetStanceConfig()
    local x_position = stanceConfig.x_position or -230  -- X position from center
    local y_offset = stanceConfig.y_offset or 0         -- Additional Y offset
    local base_y = 200                                  -- Base Y position from bottom
    local final_y = base_y + y_offset                   -- Final Y position
    
    -- Apply dual-bar offset when both XP and Rep bars are visible
    -- Only if stance bar is at its default position (not moved by user)
    -- IMPORTANT: Keep in sync with database.lua → additional.stance
    local defaultYOffset = -58   -- database default for additional.stance.y_offset
    local defaultXPosition = -211  -- database default for additional.stance.x_position
    if addon.GetDualBarVerticalOffset
        and math.abs(x_position - defaultXPosition) <= 1
        and math.abs(y_offset - defaultYOffset) <= 1 then
        final_y = final_y + addon.GetDualBarVerticalOffset()
    end
    
    -- Simple static positioning - no dependencies, no complexity
    anchor:ClearAllPoints()
    anchor:SetPoint('BOTTOM', UIParent, 'BOTTOM', x_position, final_y)
end

-- ============================================================================
-- UTILITY FUNCTIONS
-- ============================================================================

-- Simple update function - no queues needed
local function UpdateStanceBar()
    if not IsModuleEnabled() then return end
    stancebar_update()
end

-- Export for external modules (mainbars.lua calls this when dual-bar offset changes)
addon.UpdateStanceBarPosition = UpdateStanceBar

-- ============================================================================
-- POSITIONING FUNCTIONS
-- ============================================================================


-- ============================================================================
-- FRAME CREATION FUNCTIONS
-- ============================================================================

local function CreateStanceFrames()
    if StanceModule.frames.anchor or not IsModuleEnabled() then return end
    
    -- Create simple anchor frame
    anchor = CreateFrame('Frame', 'pUiStanceHolder', UIParent)
    anchor:SetSize(37, 37)  -- Visual style matching reference
    StanceModule.frames.anchor = anchor
    
    -- Create stance bar frame
    stancebar = CreateFrame('Frame', 'pUiStanceBar', anchor, 'SecureHandlerStateTemplate')
    stancebar:SetAllPoints(anchor)
    StanceModule.frames.stancebar = stancebar
    
    -- Expose globally for compatibility
    _G.pUiStanceBar = stancebar
    
    -- Create editor overlay using centralized CreateUIFrame (with nineslice support)
    -- Initial size is a placeholder; real size is set in showTest based on active forms
    local editorOverlay = addon.CreateUIFrame(100, 31, 'StanceOverlay')
    editorOverlay:SetFrameStrata('FULLSCREEN')
    editorOverlay:SetFrameLevel(100)
    editorOverlay:Hide()
    StanceModule.frames.editorOverlay = editorOverlay
    
    -- Variables to track drag movement (custom drag like multicast)
    local dragStartX, dragStartY = 0, 0
    local configStartX, configStartY = 0, 0
    local isDragging = false

    function editorOverlay:SyncManualOverlayDeltaToStanceConfig()
        if not anchor then
            return
        end

        if not (addon.db and addon.db.profile and addon.db.profile.additional and addon.db.profile.additional.stance) then
            return
        end

        local overlayX, overlayY = self:GetLeft(), self:GetBottom()
        local anchorX, anchorY = anchor:GetLeft(), anchor:GetBottom()
        if not overlayX or not overlayY or not anchorX or not anchorY then
            return
        end

        local deltaX = overlayX - anchorX
        local deltaY = overlayY - anchorY
        if math.abs(deltaX) < 0.5 and math.abs(deltaY) < 0.5 then
            return
        end

        local stanceCfg = addon.db.profile.additional.stance
        stanceCfg.x_position = math.floor((stanceCfg.x_position or -211) + deltaX + 0.5)
        stanceCfg.y_offset = math.floor((stanceCfg.y_offset or -60) + deltaY + 0.5)

        stancebar_update()

        -- Keep overlay glued to the real anchor after applying DB delta.
        self:ClearAllPoints()
        self:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
    end
    
    -- Make draggable with custom behavior (disable built-in movement)
    editorOverlay:SetMovable(false)
    editorOverlay:EnableMouse(true)
    editorOverlay:RegisterForDrag("LeftButton")
    
    editorOverlay:SetScript("OnDragStart", function(self)
        isDragging = true
        
        -- Show dragging state (orange/yellow, like other editor frames).
        if self.NineSlice and addon.SetNinesliceState then
            addon.SetNinesliceState(self, true)
        end
        if addon.ClearSelectionTint then
            addon.ClearSelectionTint(self)
        end
        
        -- Store mouse position when drag starts
        local scale = self:GetEffectiveScale()
        dragStartX = GetCursorPosition() / scale
        dragStartY = select(2, GetCursorPosition()) / scale
        
        -- Store current config values
        if addon.db and addon.db.profile and addon.db.profile.additional and addon.db.profile.additional.stance then
            configStartX = addon.db.profile.additional.stance.x_position or -230
            configStartY = addon.db.profile.additional.stance.y_offset or 0
        end
    end)
    
    -- Real-time update during drag
    editorOverlay:SetScript("OnUpdate", function(self, elapsed)
        if not isDragging then
            -- Pixel-perfect editor controls move the overlay directly.
            -- Convert that overlay movement into stance DB coordinates.
            if self.DuckcraftUI_WasAdjustedByEditor or self.DuckcraftUI_WasDragged then
                self:SyncManualOverlayDeltaToStanceConfig()
                self.DuckcraftUI_WasAdjustedByEditor = nil
                self.DuckcraftUI_WasDragged = nil
            end
            return
        end
        
        -- Calculate current delta from mouse movement
        local scale = self:GetEffectiveScale()
        local currentX = GetCursorPosition() / scale
        local currentY = select(2, GetCursorPosition()) / scale
        
        local deltaX = currentX - dragStartX
        local deltaY = currentY - dragStartY
        
        -- Update config values in real-time
        if addon.db and addon.db.profile and addon.db.profile.additional and addon.db.profile.additional.stance then
            addon.db.profile.additional.stance.x_position = math.floor(configStartX + deltaX + 0.5)
            addon.db.profile.additional.stance.y_offset = math.floor(configStartY + deltaY + 0.5)
            
            -- Update anchor position in real-time (move the actual stance bar)
            stancebar_update()
            
            -- Keep overlay aligned to BOTTOMLEFT of anchor (buttons start there)
            self:ClearAllPoints()
            self:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
        end
    end)
    
    editorOverlay:SetScript("OnDragStop", function(self)
        isDragging = false
        
        -- Return to selected highlight state.
        if self.NineSlice and addon.SetNinesliceState then
            addon.SetNinesliceState(self, false)
        end
        if addon.ApplySelectionTint then
            addon.ApplySelectionTint(self)
        end
        -- Overlay is already in correct position from OnUpdate
    end)
    
    -- Apply static positioning immediately
    stancebar_update()
    
    
end

-- ============================================================================
-- POSITIONING FUNCTIONS
-- ============================================================================

--



-- ============================================================================
-- STANCE BUTTON FUNCTIONS
-- ============================================================================

local function stancebutton_update()
    if not IsModuleEnabled() or not anchor then return end
    if InCombatLockdown() then return end

    _G.ShapeshiftButton1:ClearAllPoints()
    _G.ShapeshiftButton1:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
end

local function stancebutton_position()
    if not IsModuleEnabled() or not stancebar or not anchor then return end
    
    -- READ VALUES FROM DATABASE
    local stanceConfig = GetStanceConfig()
    local additionalConfig = (addon.db and addon.db.profile and addon.db.profile.additional) or {}
    local btnsize = stanceConfig.button_size or additionalConfig.size or 36
    local space = stanceConfig.button_spacing or additionalConfig.spacing or 6
    
    -- Use scale for uniform sizing of entire button (icon + border + all textures)
    local nativeSize = 36
    local scale = btnsize / nativeSize
    
    for index=1, NUM_SHAPESHIFT_SLOTS do
		local button = _G['ShapeshiftButton'..index]
		if button then
		    -- Set parent if not already configured
		    if button:GetParent() ~= stancebar then
			    button:SetParent(stancebar)
		    end
		    
		    -- Set native size - buttons.lua will configure textures correctly
		    button:SetSize(nativeSize, nativeSize)
		    
		    -- Apply scale for user-configurable size (scales everything uniformly)
		    button:SetScale(scale)
		    
		    -- Position buttons (spacing in parent coordinates)
		    button:ClearAllPoints()
		    if index == 1 then
			    button:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
		    else
			    local previous = _G['ShapeshiftButton'..index-1]
			    button:SetPoint('LEFT', previous, 'RIGHT', space, 0)
		    end
		    
		    -- Show/hide based on forms
		    local _,name = GetShapeshiftFormInfo(index)
		    if name then
			    button:Show()
		    else
			    button:Hide()
		    end
		end
	end
	
	-- Register state driver only once
	if not StanceModule.stateDrivers.visibility then
	    StanceModule.stateDrivers.visibility = {frame = stancebar, state = 'visibility', condition = stance[class] or 'hide'}
	    RegisterStateDriver(stancebar, 'visibility', stance[class] or 'hide')
	end
end

local function stancebutton_updatestate()
    if not IsModuleEnabled() then return end
    
	local numForms = GetNumShapeshiftForms()
	local texture, name, isActive, isCastable;
	local button, icon, cooldown;
	local start, duration, enable;
	for index=1, NUM_SHAPESHIFT_SLOTS do
		button = _G['ShapeshiftButton'..index]
		icon = _G['ShapeshiftButton'..index..'Icon']
		if index <= numForms then
			texture, name, isActive, isCastable = GetShapeshiftFormInfo(index)
			icon:SetTexture(texture)
			cooldown = _G['ShapeshiftButton'..index..'Cooldown']
			if texture then
				cooldown:SetAlpha(1)
			else
				cooldown:SetAlpha(0)
			end
			start, duration, enable = GetShapeshiftFormCooldown(index)
			CooldownFrame_SetTimer(cooldown, start, duration, enable)
			if isActive then
				ShapeshiftBarFrame.lastSelected = button:GetID()
				button:SetChecked(1)
			else
				button:SetChecked(0)
			end
			if isCastable then
				icon:SetVertexColor(255/255, 255/255, 255/255)
			else
				icon:SetVertexColor(102/255, 102/255, 102/255)
			end
		end
	end
end

local function stancebutton_setup()
    if not IsModuleEnabled() then return end
    
	if InCombatLockdown() then return end
	
	-- First apply button textures (from buttons.lua)
	if addon.stancebuttons_template then
	    addon.stancebuttons_template()
	end
	
	-- Then apply positioning and scaling
	stancebutton_position()
	
	-- Then show/hide based on available forms
	for index=1, NUM_SHAPESHIFT_SLOTS do
		local button = _G['ShapeshiftButton'..index]
		local _, name = GetShapeshiftFormInfo(index)
		if name then
			button:Show()
		else
			button:Hide()
		end
	end
	stancebutton_updatestate();

    if addon.RefreshStanceVisibility then
        addon.RefreshStanceVisibility()
    end

end

-- ============================================================================
-- EVENT HANDLING
-- ============================================================================

local function OnEvent(self,event,...)
    if not IsModuleEnabled() then return end
    
	if GetNumShapeshiftForms() < 1 then return; end
	if event == 'PLAYER_LOGIN' then
		stancebutton_position();
	elseif event == 'UPDATE_SHAPESHIFT_FORMS' then
		stancebutton_setup();
	elseif event == 'PLAYER_ENTERING_WORLD' then
		self:UnregisterEvent('PLAYER_ENTERING_WORLD');
		if addon.stancebuttons_template then
		    addon.stancebuttons_template();
		end
	else
		stancebutton_updatestate();
	end
end

-- ============================================================================
-- STANCE BAR VISIBILITY / FADE
-- Fades ONLY the anchor (pUiStanceHolder). Alpha cascades to pUiStanceBar and
-- all ShapeshiftButtons, so we must NOT also set button alpha (double-fade).
-- Alpha-only: safe under combat lockdown; never Show/Hide the secure frame here.
-- Config lives at addon.db.profile.additional.stance.visibility
-- ============================================================================

local stanceVisibilityState = {
    hovered     = false,
    inCombat    = InCombatLockdown(),
    alpha       = 1,
    startAlpha  = 1,
    targetAlpha = 1,
    elapsed     = 0,
    fading      = false,
}

local function GetStanceVisibilityConfig()
    if addon.db and addon.db.profile and addon.db.profile.additional
        and addon.db.profile.additional.stance then
        return addon.db.profile.additional.stance.visibility
    end
    return nil
end

-- Scale-correct hover test: work in raw screen pixels so per-button SetScale()
-- does not throw the math off (buff module assumes UIParent scale; stance
-- buttons are scaled, so we multiply by each region's effective scale).
local function IsCursorOverStanceBar()
    if not anchor then return false end

    local cursorX, cursorY = GetCursorPosition()  -- already in pixels
    local minL, minB, maxR, maxT
    local found = false

    for index = 1, NUM_SHAPESHIFT_SLOTS do
        local button = _G['ShapeshiftButton' .. index]
        if button and button:IsShown() then
            local s = button:GetEffectiveScale()
            local l, r = button:GetLeft(), button:GetRight()
            local b, t = button:GetBottom(), button:GetTop()
            if l and r and b and t then
                l, r, b, t = l * s, r * s, b * s, t * s
                if not found then
                    minL, minB, maxR, maxT = l, b, r, t
                    found = true
                else
                    if l < minL then minL = l end
                    if b < minB then minB = b end
                    if r > maxR then maxR = r end
                    if t > maxT then maxT = t end
                end
            end
        end
    end

    if not found then
        -- Fallback to the anchor bounds when no buttons are visible.
        local s = anchor:GetEffectiveScale()
        local l, r = anchor:GetLeft(), anchor:GetRight()
        local b, t = anchor:GetBottom(), anchor:GetTop()
        if not (l and r and b and t) then return false end
        minL, minB, maxR, maxT = l * s, b * s, r * s, t * s
    end

    return cursorX >= minL and cursorX <= maxR
        and cursorY >= minB and cursorY <= maxT
end

local function ShouldShowStanceBar()
    local config = GetStanceVisibilityConfig()

    -- No custom visibility configured: behave like the normal UI (fully shown).
    if not config then return true end

    -- Not hidden by default: normal behavior.
    if not config.hidden then return true end

    -- Hidden by default: reveal only when a checked condition is satisfied.
    if config.show_on_hover and stanceVisibilityState.hovered then
        return true
    end
    if config.show_in_combat and stanceVisibilityState.inCombat then
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

local function GetStanceFadeDuration()
    local config = GetStanceVisibilityConfig()
    return tonumber(config and config.fade_duration) or 0
end

-- Single control point: fade ONLY the anchor. Cascade handles the rest.
local function ApplyStanceAlpha(alpha)
    if anchor then
        anchor:SetAlpha(alpha)
    end
end

local function StartStanceFade(shouldShow)
    local state = stanceVisibilityState
    local targetAlpha = shouldShow and 1 or 0
    local duration = GetStanceFadeDuration()

    local currentAlpha
    if state.fading then
        currentAlpha = state.alpha
    else
        currentAlpha = (anchor and anchor:GetAlpha()) or 1
    end
    currentAlpha = math.max(0, math.min(1, currentAlpha))

    if duration <= 0 or math.abs(currentAlpha - targetAlpha) < 0.001 then
        state.alpha       = targetAlpha
        state.startAlpha  = targetAlpha
        state.targetAlpha = targetAlpha
        state.elapsed     = 0
        state.fading      = false
        ApplyStanceAlpha(targetAlpha)
        return
    end

    state.alpha       = currentAlpha
    state.startAlpha  = currentAlpha
    state.targetAlpha = targetAlpha
    state.elapsed     = 0
    state.fading      = true
    ApplyStanceAlpha(currentAlpha)
end

-- Deferred hide (fade_delay) frame.
local stanceHideDelay = CreateFrame("Frame")
stanceHideDelay:Hide()
stanceHideDelay._elapsed = 0
stanceHideDelay._target = 0
stanceHideDelay:SetScript("OnUpdate", function(self, e)
    self._elapsed = self._elapsed + e
    if self._elapsed < self._target then return end
    self:Hide()
    if not ShouldShowStanceBar() then
        StartStanceFade(false)
    end
end)

local function RefreshStanceVisibilityInternal()
    if not IsModuleEnabled() then return end
    if not anchor then return end

    if ShouldShowStanceBar() then
        stanceHideDelay:Hide()
        stanceHideDelay._elapsed = 0
        StartStanceFade(true)
    else
        local config = GetStanceVisibilityConfig()
        local delay = tonumber(config and config.fade_delay) or 0
        if delay <= 0 then
            stanceHideDelay:Hide()
            StartStanceFade(false)
        elseif not stanceHideDelay:IsShown() then
            stanceHideDelay._elapsed = 0
            stanceHideDelay._target = delay
            stanceHideDelay:Show()
        end
    end
end

-- Public refresh hook (called by the options manifest, same as buffs).
function addon.RefreshStanceVisibility()
    if not IsModuleEnabled() then return end
    RefreshStanceVisibilityInternal()
end

-- Tween engine.
local stanceFadeFrame = CreateFrame("Frame")
stanceFadeFrame:Show()
stanceFadeFrame:SetScript("OnUpdate", function(_, elapsed)
    local state = stanceVisibilityState
    if not state.fading then return end

    local duration = GetStanceFadeDuration()
    if duration <= 0 then
        state.alpha  = state.targetAlpha
        state.fading = false
    else
        state.elapsed = state.elapsed + elapsed
        local progress = state.elapsed / duration
        if progress >= 1 then
            state.alpha  = state.targetAlpha
            state.fading = false
        else
            local eased = progress * progress * (3 - 2 * progress)  -- smoothstep
            state.alpha = state.startAlpha
                + (state.targetAlpha - state.startAlpha) * eased
        end
    end
    ApplyStanceAlpha(state.alpha)
end)

-- Hover poll (only active when show_on_hover is enabled).
local stanceHoverFrame = CreateFrame("Frame")
local stanceHoverElapsed = 0
stanceHoverFrame:SetScript("OnUpdate", function(_, elapsed)
    stanceHoverElapsed = stanceHoverElapsed + elapsed
    if stanceHoverElapsed < 0.05 then return end
    stanceHoverElapsed = 0

    local config = GetStanceVisibilityConfig()
    if not config or not config.show_on_hover then
        if stanceVisibilityState.hovered then
            stanceVisibilityState.hovered = false
            RefreshStanceVisibilityInternal()
        end
        return
    end

    local hovered = IsCursorOverStanceBar()
    if hovered ~= stanceVisibilityState.hovered then
        stanceVisibilityState.hovered = hovered
        RefreshStanceVisibilityInternal()
    end
end)

-- Condition drivers (combat / target / health / power).
local stanceVisibilityEvents = CreateFrame("Frame")
stanceVisibilityEvents:RegisterEvent("PLAYER_TARGET_CHANGED")
stanceVisibilityEvents:RegisterEvent("PLAYER_REGEN_DISABLED")
stanceVisibilityEvents:RegisterEvent("PLAYER_REGEN_ENABLED")
stanceVisibilityEvents:RegisterEvent("UNIT_HEALTH")
stanceVisibilityEvents:RegisterEvent("UNIT_MAXHEALTH")
stanceVisibilityEvents:RegisterEvent("UNIT_HEALTH_FREQUENT")
stanceVisibilityEvents:RegisterEvent("UNIT_MANA")
stanceVisibilityEvents:RegisterEvent("UNIT_MAXMANA")
stanceVisibilityEvents:RegisterEvent("UNIT_RAGE")
stanceVisibilityEvents:RegisterEvent("UNIT_FOCUS")
stanceVisibilityEvents:RegisterEvent("UNIT_ENERGY")
stanceVisibilityEvents:RegisterEvent("UNIT_RUNIC_POWER")
stanceVisibilityEvents:RegisterEvent("UNIT_POWER_UPDATE")   -- harmless if never fired on 3.3.5a
stanceVisibilityEvents:RegisterEvent("UNIT_MAXPOWER")
stanceVisibilityEvents:RegisterEvent("UNIT_DISPLAYPOWER")
stanceVisibilityEvents:SetScript("OnEvent", function(_, event, unit)
    if event:sub(1, 5) == "UNIT_" and unit ~= "player" then return end
    if event == "PLAYER_REGEN_DISABLED" then
        stanceVisibilityState.inCombat = true
    elseif event == "PLAYER_REGEN_ENABLED" then
        stanceVisibilityState.inCombat = false
    end
    RefreshStanceVisibilityInternal()
end)


-- ============================================================================
-- INITIALIZATION FUNCTIONS
-- ============================================================================

-- Simple initialization function
local function InitializeStanceBar()
    if not IsModuleEnabled() then return end
    
    -- IMPORTANT: Apply button textures FIRST (from buttons.lua)
    if addon.stancebuttons_template then
        addon.stancebuttons_template()
    end
    
    -- Then position and scale
    stancebutton_position()
    stancebar_update()
    
    if stancebar then
        stancebar:Show()
    end
    
    stanceBarInitialized = true

    if addon.RefreshStanceVisibility then
        addon.RefreshStanceVisibility()
    end

end

-- ============================================================================
-- APPLY/RESTORE FUNCTIONS
-- ============================================================================

local function ApplyStanceSystem()
    if StanceModule.applied or not IsModuleEnabled() then return end
    
    -- Create frames
    CreateStanceFrames()
    
    if not anchor or not stancebar then return end
    
    -- Register only essential events
    local events = {
        'PLAYER_LOGIN',
        'UPDATE_SHAPESHIFT_FORMS',
        'UPDATE_SHAPESHIFT_FORM',
        'UPDATE_SHAPESHIFT_USABLE',   -- Druid: fires when entering/leaving water, flyable zones, etc.
        'UPDATE_SHAPESHIFT_COOLDOWN', -- Cooldown changes
        'SPELL_UPDATE_USABLE',        -- General spell usability changes (zone transitions)
        'ACTIONBAR_UPDATE_USABLE',    -- Action bar usability updates
    }
    
    for _, eventName in ipairs(events) do
        stancebar:RegisterEvent(eventName)
        StanceModule.registeredEvents[eventName] = stancebar
    end
    stancebar:SetScript('OnEvent', OnEvent)
    
    -- Simple hook for Blizzard updates - REGISTER ONLY ONCE
    if not StanceModule.hooks.ShapeshiftBar_Update then
        StanceModule.hooks.ShapeshiftBar_Update = true
        hooksecurefunc('ShapeshiftBar_Update', function()
            if IsModuleEnabled() then
                stancebutton_update()
            end
        end)
    end
    
    -- Initial setup
    InitializeStanceBar()
    
    StanceModule.applied = true
    
    -- Register with editor mode system
    if addon.RegisterEditableFrame and StanceModule.frames.editorOverlay then
        local editorOverlay = StanceModule.frames.editorOverlay
        
        addon:RegisterEditableFrame({
            name = "stance",
            frame = editorOverlay,
            configPath = {"additional", "stance"},
            
            showTest = function()
                -- Only show overlay if the player actually has stance/shapeshift forms
                local numForms = GetNumShapeshiftForms() or 0
                if numForms < 1 or not anchor then return end
                
                -- Position overlay at anchor location, matching the visual button area
                local stanceConfig = GetStanceConfig()
                local btnSize = stanceConfig.button_size or 31
                local spacing = stanceConfig.button_spacing or 6
                -- Buttons use SetScale(btnSize/36) so visual size = btnSize
                local totalWidth = numForms * btnSize + (numForms - 1) * spacing
                totalWidth = math.max(totalWidth, btnSize)
                editorOverlay:SetSize(totalWidth, btnSize)
                
                -- Buttons start at BOTTOMLEFT of anchor, so align overlay there
                editorOverlay:ClearAllPoints()
                editorOverlay:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
                editorOverlay:Show()
                
                -- Show nineslice overlay
                if addon.ShowNineslice then
                    addon.SetNinesliceState(editorOverlay, false)
                    addon.ShowNineslice(editorOverlay)
                end
                if editorOverlay.editorText then
                    editorOverlay.editorText:Show()
                end
            end,
            
            hideTest = function()
                -- Ensure manual editor adjustments are persisted before hiding.
                if editorOverlay and editorOverlay.SyncManualOverlayDeltaToStanceConfig then
                    editorOverlay:SyncManualOverlayDeltaToStanceConfig()
                end
                editorOverlay:Hide()
                -- Hide nineslice overlay
                if addon.HideNineslice then
                    addon.HideNineslice(editorOverlay)
                end
                if editorOverlay.editorText then
                    editorOverlay.editorText:Hide()
                end
            end,

            onHide = function()
                if editorOverlay and editorOverlay.SyncManualOverlayDeltaToStanceConfig then
                    editorOverlay:SyncManualOverlayDeltaToStanceConfig()
                end
                if editorOverlay then
                    editorOverlay.DuckcraftUI_WasAdjustedByEditor = nil
                    editorOverlay.DuckcraftUI_WasDragged = nil
                end
            end,
            
            module = StanceModule
        })
    end
    
end

local function RestoreStanceSystem()
    if not StanceModule.applied then return end
    
    -- Unregister all events
    for eventName, frame in pairs(StanceModule.registeredEvents) do
        if frame and frame.UnregisterEvent then
            frame:UnregisterEvent(eventName)
        end
    end
    StanceModule.registeredEvents = {}
    
    -- Unregister all state drivers
    for name, data in pairs(StanceModule.stateDrivers) do
        if data.frame then
            UnregisterStateDriver(data.frame, data.state)
        end
    end
    StanceModule.stateDrivers = {}
    
    -- Hide custom frames
    if anchor then anchor:Hide() end
    if stancebar then stancebar:Hide() end
    
    -- Reset stance button parents to default
    for index=1, NUM_SHAPESHIFT_SLOTS do
        local button = _G['ShapeshiftButton'..index]
        if button then
            button:SetParent(ShapeshiftBarFrame or UIParent)
            button:ClearAllPoints()
            -- Don't reset positions here - let Blizzard handle it
        end
    end
    
    -- Clear global reference
    _G.pUiStanceBar = nil
    
    -- Reset variables
    stanceBarInitialized = false
    
    StanceModule.applied = false
end

-- ============================================================================
-- PUBLIC API
-- ============================================================================

-- Enhanced refresh function with module control
function addon.RefreshStanceSystem()
    if IsModuleEnabled() then
        ApplyStanceSystem()
        -- Call original refresh for settings
        if addon.RefreshStance then
            addon.RefreshStance()
        end
    else
        if addon:ShouldDeferModuleDisable("stance", StanceModule) then
            return
        end
        RestoreStanceSystem()
    end
end

-- Original refresh function for configuration changes
function addon.RefreshStance()
    if not IsModuleEnabled() then return end
    
	if InCombatLockdown() or UnitAffectingCombat('player') then 
		return 
	end
	
	-- Ensure frames exist
	if not anchor or not stancebar then
	    return
	end
	
	-- First apply button textures (from buttons.lua)
	if addon.stancebuttons_template then
	    addon.stancebuttons_template()
	end
	
	-- Update button size and spacing (scale-based - matching stancebutton_position)
	local stanceConfig = GetStanceConfig()
	local additionalConfig = (addon.db and addon.db.profile and addon.db.profile.additional) or {}
	local btnsize = stanceConfig.button_size or additionalConfig.size or 36
	local space = stanceConfig.button_spacing or additionalConfig.spacing or 6
	
	-- Reposition stance buttons with scale for proper texture sizing
	-- Native Blizzard button size is 36x36
	local nativeSize = 36
	local scale = btnsize / nativeSize
	
	for i = 1, NUM_SHAPESHIFT_SLOTS do
		local button = _G["ShapeshiftButton"..i]
		if button then
			-- Set native size and apply scale (buttons.lua handles textures)
			button:SetSize(nativeSize, nativeSize)
			button:SetScale(scale)
			button:ClearAllPoints()
			if i == 1 then
				button:SetPoint('BOTTOMLEFT', anchor, 'BOTTOMLEFT', 0, 0)
			else
				local prevButton = _G["ShapeshiftButton"..(i-1)]
				if prevButton then
					button:SetPoint('LEFT', prevButton, 'RIGHT', space, 0)
				end
			end
		end
	end
	
	-- Update position
	stancebar_update()
end

-- Debug function for troubleshooting stance bar issues
function addon.DebugStanceBar()
    if not IsModuleEnabled() then
        
        return {enabled = false}
    end
    
	local info = {
		stanceBarInitialized = stanceBarInitialized,
		moduleEnabled = IsModuleEnabled(),
		inCombat = InCombatLockdown(),
		unitInCombat = UnitAffectingCombat('player'),
		anchorExists = anchor and true or false,
		stanceBarExists = _G.pUiStanceBar and true or false,
		numShapeshiftForms = GetNumShapeshiftForms(),
		stanceConfig = GetStanceConfig()
	};
	
	
	for k, v in pairs(info) do
	
	end
	
	if anchor then
		local point, relativeTo, relativePoint, x, y = anchor:GetPoint();
	
	end
	
	return info;
end

-- ============================================================================
-- INITIALIZATION
-- ============================================================================

local function Initialize()
    if StanceModule.initialized then return end
    
    -- Only apply if module is enabled
    if IsModuleEnabled() then
        ApplyStanceSystem()
    end
    
    StanceModule.initialized = true
end

-- Auto-initialize when addon loads
local initFrame = CreateFrame("Frame")
initFrame:RegisterEvent("ADDON_LOADED")
initFrame:RegisterEvent("PLAYER_LOGIN")
initFrame:SetScript("OnEvent", function(self, event, addonName)
    if event == "ADDON_LOADED" and addonName == "DuckcraftUI" then
        -- Just mark as loaded, don't initialize yet
        self.addonLoaded = true
    elseif event == "PLAYER_LOGIN" and self.addonLoaded then
        -- Initialize after both addon is loaded and player is logged in
        Initialize()
        self:UnregisterAllEvents()
    end
end)
-- End of stance module