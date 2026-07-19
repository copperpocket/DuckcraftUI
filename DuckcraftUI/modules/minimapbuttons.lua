local addon = select(2, ...)
local L = addon.L

-- ============================================================================
-- MINIMAP BUTTON COLLECTOR
-- Gathers addon minimap buttons into a single collapsible list/grid.
-- ============================================================================

local MinimapButtonsModule = { initialized = false, applied = false, collected = {} }
addon.MinimapButtonsModule = MinimapButtonsModule

if addon.RegisterModule then
    addon:RegisterModule("minimapbuttons", MinimapButtonsModule,
        (L and L["Minimap Button Bag"]) or "Minimap Button Bag",
        (L and L["Collect addon minimap icons into a single button"]) or "Collect addon minimap icons into a single button")
end

local function IsModuleEnabled()
    return addon:IsModuleEnabled("minimapbuttons")
end

-- Blizzard-owned minimap children we must NEVER collect.
local BLIZZARD_IGNORE = {
    MinimapZoomIn = true, MinimapZoomOut = true,
    MiniMapTracking = true, MiniMapTrackingButton = true, MiniMapTrackingFrame = true,
    MiniMapMailFrame = true, MiniMapMailBorder = true,
    MinimapBackdrop = true, GameTimeFrame = true,
    MiniMapWorldMapButton = true, TimeManagerClockButton = true,
    MiniMapLFGFrame = true, MiniMapBattlefieldFrame = true,
    MiniMapVoiceChatFrame = true, QueueStatusMinimapButton = true,
    MinimapZoneTextButton = true, MinimapNorthTag = true,
    MiniMapInstanceDifficulty = true, GuildInstanceDifficulty = true,
    MinimapCompassTexture = true,
    -- DuckcraftUI's own collector button (set after creation)
}

-- Heuristic: is this an addon minimap button we should collect?
local function IsCollectibleButton(child)
    if not child then return false end
    local name = child:GetName()
    if not name then return false end                 -- unnamed = skip (usually Blizzard art)
    if BLIZZARD_IGNORE[name] then return false end
    if name == "DuckcraftUI_MinimapCollector" then return false end

    -- LibDBIcon buttons are the common, safe case.
    if name:find("LibDBIcon") then return true end

    -- Generic heuristic: a Button/Frame with a click handler, sized like an icon.
    local otype = child:GetObjectType()
    if otype ~= "Button" and otype ~= "Frame" then return false end
    local w = child:GetWidth() or 0
    if w < 15 or w > 40 then return false end          -- icon-sized only

    if otype == "Button" then
        return true
    end
    if child:GetScript("OnClick") or child:GetScript("OnMouseDown") or child:GetScript("OnMouseUp") then
        return true
    end
    return false
end

-- The collector container (the popup grid) + the minimap button that opens it.
local function GetOrCreateCollector()
    if MinimapButtonsModule.container then
        return MinimapButtonsModule.container, MinimapButtonsModule.collectorButton
    end

    -- Popup container that holds collected buttons.
    local container = CreateFrame("Frame", "DuckcraftUI_MinimapCollectorBag", UIParent)
    container:SetFrameStrata("DIALOG")
    container:SetBackdrop({
        bgFile = "Interface\\ChatFrame\\ChatFrameBackground",
        edgeFile = "Interface\\Tooltips\\UI-Tooltip-Border",
        tile = false, edgeSize = 12,
        insets = { left = 3, right = 3, top = 3, bottom = 3 },
    })
    container:SetBackdropColor(0.05, 0.05, 0.07, 0.95)
    container:SetBackdropBorderColor(0.3, 0.3, 0.35, 1)
    container:Hide()
    container:EnableMouse(true)
    MinimapButtonsModule.container = container

    -- The single collector button on the minimap.
    local btn = CreateFrame("Button", "DuckcraftUI_MinimapCollector", Minimap)
    btn:SetSize(31, 31)
    btn:SetFrameStrata("MEDIUM")
    btn:SetFrameLevel(Minimap:GetFrameLevel() + 8)

    -- Position the button on the minimap ring at a saved angle.
    local function GetAngle()
        local cfg = addon.db and addon.db.profile and addon.db.profile.modules
                    and addon.db.profile.modules.minimapbuttons
        return (cfg and cfg.angle) or 135
    end

    local function UpdateButtonPosition()
        local angle = math.rad(GetAngle())
        local radius = (Minimap:GetWidth() / 2) - 5
        btn:ClearAllPoints()
        btn:SetPoint("CENTER", Minimap, "CENTER",
            math.cos(angle) * radius,
            math.sin(angle) * radius)
    end
    MinimapButtonsModule.UpdateButtonPosition = UpdateButtonPosition

    -- Drag around the ring: convert cursor position to an angle from minimap center.
    btn:SetMovable(true)
    btn:RegisterForDrag("LeftButton")

    btn:SetScript("OnDragStart", function(self)
        self.isDragging = true
        self:SetScript("OnUpdate", function()
            local mx, my = Minimap:GetCenter()
            local scale = Minimap:GetEffectiveScale()
            local cx, cy = GetCursorPosition()
            cx, cy = cx / scale, cy / scale

            local angle = math.deg(math.atan2(cy - my, cx - mx))
            if angle < 0 then angle = angle + 360 end

            -- Save and apply live.
            local cfg = addon.db and addon.db.profile and addon.db.profile.modules
                        and addon.db.profile.modules.minimapbuttons
            if cfg then cfg.angle = angle end
            UpdateButtonPosition()
        end)
    end)

    btn:SetScript("OnDragStop", function(self)
        self.isDragging = false
        self:SetScript("OnUpdate", nil)
    end)

    UpdateButtonPosition()


    local icon = btn:CreateTexture(nil, "BACKGROUND")
    icon:SetAllPoints()
    icon:SetTexture("Interface\\Icons\\INV_Misc_Bag_08")  -- placeholder; swap for a DuckcraftUI atlas later
    icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)

    local hl = btn:CreateTexture(nil, "HIGHLIGHT")
    hl:SetAllPoints()
    hl:SetTexture("Interface\\Buttons\\ButtonHilight-Square")
    hl:SetBlendMode("ADD")
    hl:SetAlpha(0.4)

    -- Hover opens; leaving both button and container closes (with small delay).
    local function OpenBag()
        MinimapButtonsModule:LayoutContainer()
        container:Show()
    end
    local closeTimer
    local function ScheduleClose()
        if addon.core and addon.core.ScheduleTimer then
            closeTimer = addon.core:ScheduleTimer(function()
                if not (btn:IsMouseOver() or container:IsMouseOver()) then
                    container:Hide()
                end
            end, 0.3)
        else
            container:Hide()
        end
    end

    btn:SetScript("OnEnter", OpenBag)
    btn:SetScript("OnLeave", ScheduleClose)
    container:SetScript("OnLeave", ScheduleClose)
    container:SetScript("OnEnter", function() end)  -- keep open while hovered

    MinimapButtonsModule.collectorButton = btn
    return container, btn
end

-- Reparent collectible buttons into the container.
function MinimapButtonsModule:CollectButtons()
    if not IsModuleEnabled() then return end
    local container = GetOrCreateCollector()

    for _, child in ipairs({ Minimap:GetChildren() }) do
        if IsCollectibleButton(child) and not child._duiCollected then
            -- Remember original state so we can restore on disable.
            child._duiOrig = {
                parent = child:GetParent(),
                points = {},
            }
            for i = 1, child:GetNumPoints() do
                child._duiOrig.points[i] = { child:GetPoint(i) }
            end

            child:SetParent(container)
            child._duiCollected = true
            table.insert(self.collected, child)
        end
    end
end

-- Arrange collected buttons in a grid inside the container.
function MinimapButtonsModule:LayoutContainer()
    local container = self.container
    if not container then return end

    local visible = {}
    for _, b in ipairs(self.collected) do
        if b and b.SetParent then table.insert(visible, b) end
    end

    local perRow = 5
    local size, pad = 31, 4
    local n = #visible
    if n == 0 then
        container:SetSize(size + pad * 2, size + pad * 2)
        return
    end

    local cols = math.min(perRow, n)
    local rows = math.ceil(n / perRow)

    for i, b in ipairs(visible) do
        local col = (i - 1) % perRow
        local row = math.floor((i - 1) / perRow)
        b:ClearAllPoints()
        b:SetParent(container)
        b:Show()
        b:SetPoint("TOPLEFT", container, "TOPLEFT",
            pad + col * (size + pad),
            -(pad + row * (size + pad)))
    end

    container:SetSize(cols * (size + pad) + pad, rows * (size + pad) + pad)
    container:ClearAllPoints()
    container:SetPoint("TOPRIGHT", self.collectorButton, "BOTTOMLEFT", 0, 0)
end

function MinimapButtonsModule:Apply()
    if self.applied or not IsModuleEnabled() then return end
    GetOrCreateCollector()
    if self.UpdateButtonPosition then self.UpdateButtonPosition() end

    -- Buttons appear at staggered times after login; sweep a few times.
    self:CollectButtons()
    if addon.core and addon.core.ScheduleTimer then
        for _, delay in ipairs({ 1, 3, 6, 10 }) do
            addon.core:ScheduleTimer(function()
                if IsModuleEnabled() then self:CollectButtons() end
            end, delay)
        end
    end

    self.applied = true
end

function MinimapButtonsModule:Restore()
    if not self.applied then return end
    for _, b in ipairs(self.collected) do
        if b and b._duiOrig then
            b:SetParent(b._duiOrig.parent or Minimap)
            b:ClearAllPoints()
            for _, p in ipairs(b._duiOrig.points) do
                b:SetPoint(unpack(p))
            end
            b._duiCollected = nil
            b._duiOrig = nil
        end
    end
    self.collected = {}
    if self.container then self.container:Hide() end
    if self.collectorButton then self.collectorButton:Hide() end
    self.applied = false
end

function addon.RefreshMinimapButtons()
    if IsModuleEnabled() then
        MinimapButtonsModule:Apply()
    else
        MinimapButtonsModule:Restore()
    end
end

local f = CreateFrame("Frame")
f:RegisterEvent("PLAYER_LOGIN")
f:SetScript("OnEvent", function()
    if IsModuleEnabled() then MinimapButtonsModule:Apply() end
end)

MinimapButtonsModule.initialized = true
