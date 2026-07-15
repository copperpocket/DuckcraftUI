--[[
================================================================================
DragonUI Options Panel - Visibility Tab
================================================================================
Centralized master control for frame visibility across all modules.
================================================================================
]]

local addon = DragonUI
if not addon then return end

local L = addon.L
local LO = addon.LO
local C = addon.PanelControls
local Panel = addon.OptionsPanel

-- ============================================================================
-- MASTER VISIBILITY: manifest + propagation
-- ============================================================================

-- Shared refresh closures (identity matters: dedup relies on ==).
local refreshPlayer   = function() if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then addon.PlayerFrame.RefreshPlayerFrame() end end
local refreshTarget   = function() if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then addon.TargetFrame.RefreshTargetFrame() end end
local refreshBars     = function() if addon.RefreshActionBarVisibility then addon.RefreshActionBarVisibility() end end
local refreshBuffs    = function() if addon.RefreshBuffVisibility then addon.RefreshBuffVisibility() end end
local refreshMicro    = function() if addon.RefreshMicromenuVisibility then addon.RefreshMicromenuVisibility() end end
local refreshBags     = function() if addon.RefreshBagBarVisibility then addon.RefreshBagBarVisibility() end end
local refreshMinimap  = function() if addon.RefreshMinimapVisibility then addon.RefreshMinimapVisibility() end end
local refreshXpRep    = function() if addon.RefreshXpRepBars then addon.RefreshXpRepBars() end end

-- Canonical master options. `kind` drives the master widget; sliders carry range.
local MASTER_OPTS = {
    { id = "hidden",           kind = "toggle", label = LO["Hidden"] },
    { id = "show_on_hover",    kind = "toggle", label = LO["Show on Hover"] },
    { id = "show_in_combat",   kind = "toggle", label = LO["Show in Combat"] },
    { id = "show_with_target", kind = "toggle", label = LO["Show with Target"] },
    { id = "show_on_health",   kind = "toggle", label = LO["Show When Health Is Not Full"] },
    { id = "show_on_power",    kind = "toggle", label = LO["Show When Power Is Not Full"] },
    { id = "fade_delay",       kind = "slider", label = LO["Fade Delay"],    min = 0, max = 20, step = 0.5 },
    { id = "fade_duration",    kind = "slider", label = LO["Fade Duration"], min = 0, max = 5,  step = 0.1 },
}

-- Helper: build a snake-case map (buffs / micromenu / bags / minimap / xprep).
local function SnakeMap(base)
    return {
        hidden           = base .. ".hidden",
        show_on_hover    = base .. ".show_on_hover",
        show_in_combat   = base .. ".show_in_combat",
        show_with_target = base .. ".show_with_target",
        show_on_health   = base .. ".show_on_health",
        show_on_power    = base .. ".show_on_power",
        fade_delay       = base .. ".fade_delay",
        fade_duration    = base .. ".fade_duration",
    }
end

-- Helper: build an action-bar map. Toggles are per-bar; fade keys are SHARED.
local function BarMap(barKey)
    return {
        hidden           = "actionbars." .. barKey .. "_hidden",
        show_on_hover    = "actionbars." .. barKey .. "_show_on_hover",
        show_in_combat   = "actionbars." .. barKey .. "_show_in_combat",
        show_with_target = "actionbars." .. barKey .. "_show_with_target",
        show_on_health   = "actionbars." .. barKey .. "_show_on_health",
        show_on_power    = "actionbars." .. barKey .. "_show_on_power",
        fade_delay       = "actionbars.visibility_fade_delay",      -- shared, idempotent
        fade_duration    = "actionbars.visibility_fade_duration",   -- shared, idempotent
    }
end

-- Each element declares ONLY the canonical options it supports.
-- An entry may be a string path, or { path = "...", min = n, max = n } to clamp.
local VisibilityTargets = {
    { refresh = refreshPlayer, map = {
        hidden           = "unitframe.player.visibility.hideByDefault",
        show_on_hover    = "unitframe.player.visibility.showOnHover",
        show_in_combat   = "unitframe.player.visibility.showInCombat",
        show_with_target = "unitframe.player.visibility.showWithTarget",
        show_on_health   = "unitframe.player.visibility.showOnHealth",
        show_on_power    = "unitframe.player.visibility.showOnMana",   -- note: Mana
        fade_delay       = "unitframe.player.visibility.fadeDelay",
        fade_duration    = "unitframe.player.visibility.fadeDuration",
        -- 'advanced' intentionally NOT master-controlled
    }},

    -- Target frame shares only fade_duration, and its slider maxes at 2.
    { refresh = refreshTarget, map = {
        fade_duration = { path = "unitframe.target.fade.duration", min = 0, max = 2 },
    }},

    { refresh = refreshBuffs,   map = SnakeMap("buffs.visibility") },
    { refresh = refreshMicro,   map = SnakeMap("micromenu.visibility") },
    { refresh = refreshBags,    map = SnakeMap("bags.visibility") },
    { refresh = refreshMinimap, map = SnakeMap("minimap.visibility") },  -- 'map_only' not master-controlled

    { refresh = refreshBars, map = BarMap("main") },
    { refresh = refreshBars, map = BarMap("bottom_left") },
    { refresh = refreshBars, map = BarMap("bottom_right") },
    { refresh = refreshBars, map = BarMap("right") },
    { refresh = refreshBars, map = BarMap("left") },

    { refresh = refreshXpRep, map = SnakeMap("xprepbar.visibility.xp") },
    { refresh = refreshXpRep, map = SnakeMap("xprepbar.visibility.rep") },
}

-- Push one canonical option to every element that declares it. Undeclared = skipped.
local function ApplyMaster(optId, value)
    local pending = {}   -- dedup refreshes by function identity (all bars share one)
    for _, t in ipairs(VisibilityTargets) do
        local entry = t.map[optId]
        if entry ~= nil then
            local path, v = entry, value
            if type(entry) == "table" then
                path = entry.path
                if type(v) == "number" then
                    if entry.min and v < entry.min then v = entry.min end
                    if entry.max and v > entry.max then v = entry.max end
                end
            end
            C:SetDBValue(path, v)
            if t.refresh then pending[t.refresh] = true end
        end
    end
    for fn in pairs(pending) do fn() end   -- refreshBars runs once, not five times
end

-- Shared "Hidden + Show When" section for snake_case modules.
local function BuildVisibilitySection(scroll, opts)
    local section = C:AddSection(scroll, opts.label)
    C:AddDescription(section, opts.desc)

    C:AddToggle(section, {
        label = LO["Hidden"],
        desc = "Hide this frame by default. The conditions below reveal it when met.",
        dbPath = opts.base .. ".hidden",
        callback = function()
            opts.refresh()
            Panel:SelectTab("visibility")
        end,
    })

    local function visDisabled()
        return not C:GetDBValue(opts.base .. ".hidden")
    end

    C:AddHeading(section, LO["Show When"])

    C:AddToggle(section, { label = LO["Show on Hover"], dbPath = opts.base .. ".show_on_hover", disabled = visDisabled, callback = opts.refresh })
    C:AddToggle(section, { label = LO["Show in Combat"], dbPath = opts.base .. ".show_in_combat", disabled = visDisabled, callback = opts.refresh })
    C:AddToggle(section, { label = LO["Show with Target"], dbPath = opts.base .. ".show_with_target", disabled = visDisabled, callback = opts.refresh })
    C:AddToggle(section, { label = LO["Show When Health Is Not Full"], dbPath = opts.base .. ".show_on_health", disabled = visDisabled, callback = opts.refresh })
    C:AddToggle(section, { label = LO["Show When Power Is Not Full"], dbPath = opts.base .. ".show_on_power", disabled = visDisabled, callback = opts.refresh })

    if opts.extra then
        opts.extra(section, visDisabled)
    end

    C:AddSlider(section, {
        label = LO["Fade Delay"],
        desc = "Seconds to wait after the condition ends before the frame begins to fade out. 0 = fade immediately.",
        dbPath = opts.base .. ".fade_delay",
        min = 0, max = 20, step = 0.5, width = 200,
        disabled = visDisabled, callback = opts.refresh,
    })

    C:AddSlider(section, {
        label = LO["Fade Duration"],
        desc = "Time in seconds used to fade this frame in or out. Set to 0 for instant visibility changes.",
        dbPath = opts.base .. ".fade_duration",
        min = 0, max = 5, step = 0.1, width = 200,
        disabled = visDisabled, callback = opts.refresh,
    })

    C:AddSpacer(scroll)
    return section
end

-- Player frame: camelCase keys, aligned to the master standard order/labels.
local function BuildPlayerVisibilitySection(scroll)
    local refreshPlayer = function()
        if addon.PlayerFrame and addon.PlayerFrame.RefreshPlayerFrame then
            addon.PlayerFrame.RefreshPlayerFrame()
        end
    end

    local section = C:AddSection(scroll, LO["Player Frame"])
    C:AddDescription(section,
        "The player frame is always visible by default, like the standard UI. Check Hidden to hide it and reveal it only under the conditions below. Uses alpha fading so it is safe in combat.")

    C:AddToggle(section, {
        label = LO["Hidden"],
        desc = "Hide this frame by default. The conditions below reveal it when met.",
        dbPath = "unitframe.player.visibility.hideByDefault",
        callback = function()
            refreshPlayer()
            Panel:SelectTab("visibility")
        end,
    })

    local function visDisabled()
        return not C:GetDBValue("unitframe.player.visibility.hideByDefault")
    end

    C:AddHeading(section, LO["Show When"])

    -- Order matches MASTER_OPTS: hover, combat, target, health, power.
    C:AddToggle(section, { label = LO["Show on Hover"], dbPath = "unitframe.player.visibility.showOnHover", disabled = visDisabled, callback = refreshPlayer })
    C:AddToggle(section, { label = LO["Show in Combat"], dbPath = "unitframe.player.visibility.showInCombat", disabled = visDisabled, callback = refreshPlayer })
    C:AddToggle(section, { label = LO["Show with Target"], dbPath = "unitframe.player.visibility.showWithTarget", disabled = visDisabled, callback = refreshPlayer })
    C:AddToggle(section, { label = LO["Show When Health Is Not Full"], dbPath = "unitframe.player.visibility.showOnHealth", disabled = visDisabled, callback = refreshPlayer })
    C:AddToggle(section, { label = LO["Show When Power Is Not Full"], dbPath = "unitframe.player.visibility.showOnMana", disabled = visDisabled, callback = refreshPlayer })

    C:AddSlider(section, {
        label = LO["Fade Delay"],
        desc = "Seconds to wait after the condition ends before the frame begins to fade out. 0 = fade immediately.",
        dbPath = "unitframe.player.visibility.fadeDelay",
        min = 0, max = 20, step = 0.5, width = 200,
        disabled = visDisabled, callback = refreshPlayer,
    })

    C:AddSlider(section, {
        label = LO["Fade Duration"],
        desc = "Time in seconds used to fade the player frame in or out. Set to 0 for instant visibility changes.",
        dbPath = "unitframe.player.visibility.fadeDuration",
        min = 0, max = 5, step = 0.1, width = 200,
        disabled = visDisabled, callback = refreshPlayer,
    })

    C:AddSpacer(scroll)
end

-- Action bars use flat <bar>_* keys with a shared fade duration.
local function BuildActionBarSection(scroll, barKey, label)
    local refreshBars = function()
        if addon.RefreshActionBarVisibility then addon.RefreshActionBarVisibility() end
    end

    local section = C:AddSection(scroll, label)

    C:AddToggle(section, {
        label = LO["Hidden"],
        desc = "Hide this bar by default. The conditions below reveal it when met.",
        dbPath = "actionbars." .. barKey .. "_hidden",
        callback = function()
            refreshBars()
            Panel:SelectTab("visibility")
        end,
    })

    local function visDisabled()
        return not C:GetDBValue("actionbars." .. barKey .. "_hidden")
    end

    C:AddHeading(section, LO["Show When"])

    C:AddToggle(section, { label = LO["Show on Hover"],  dbPath = "actionbars."..barKey.."_show_on_hover",   disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show in Combat"], dbPath = "actionbars."..barKey.."_show_in_combat",  disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show with Target"], dbPath = "actionbars."..barKey.."_show_with_target", disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show When Health Is Not Full"], dbPath = "actionbars."..barKey.."_show_on_health", disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show When Power Is Not Full"], dbPath = "actionbars."..barKey.."_show_on_power", disabled = visDisabled, callback = refreshBars })

    C:AddSlider(section, {
        label = LO["Fade Delay"],
        desc = "Seconds to wait after conditions end before the bar begins to fade out. Shared across all bars.",
        dbPath = "actionbars.visibility_fade_delay",
        min = 0, max = 20, step = 0.5, width = 200,
        disabled = visDisabled,
        callback = refreshBars,
    })

    C:AddSlider(section, {
        label = LO["Fade Duration"],
        desc = "Shared fade time for all action bars. Set to 0 for instant visibility changes.",
        dbPath = "actionbars.visibility_fade_duration",
        min = 0, max = 5, step = 0.1, width = 200,     -- max 3 -> 5
        disabled = visDisabled,
        callback = refreshBars,
    })

    C:AddSpacer(scroll)
end

-- Target frame: fades in/out with the target. It only has content when a
-- target exists, so it uses the existing fade system, not Hidden/conditions.
local function BuildTargetVisibilitySection(scroll)
    local refreshTarget = function()
        if addon.TargetFrame and addon.TargetFrame.RefreshTargetFrame then
            addon.TargetFrame.RefreshTargetFrame()
        end
    end

    local section = C:AddSection(scroll, LO["Target Frame"])
    C:AddDescription(section,
        "The target frame appears when you have a target and hides when you clear it. Enable fading to smoothly fade it in and out instead of instantly showing/hiding.")

    C:AddToggle(section, {
        label = LO["Fade In/Out"],
        desc = "Fade the target frame in when you select a target and out when you clear it.",
        dbPath = "unitframe.target.fade.enabled",
        callback = refreshTarget,
    })

    C:AddSlider(section, {
        label = LO["Fade Duration"],
        desc = "Time in seconds for the target frame to fade in or out.",
        dbPath = "unitframe.target.fade.duration",
        min = 0, max = 2, step = 0.05,
        width = 200,
        disabled = function()
            return not C:GetDBValue("unitframe.target.fade.enabled")
        end,
        callback = refreshTarget,
    })

    C:AddSpacer(scroll)
end

local function BuildXpRepBarSection(scroll, subKey, label)
    local refreshBars = function()
        if addon.RefreshXpRepBars then addon.RefreshXpRepBars() end
    end
    local base = "xprepbar.visibility." .. subKey

    local section = C:AddSection(scroll, label)

    C:AddToggle(section, {
        label = LO["Hidden"],
        desc = "Hide this bar by default. The conditions below reveal it when met.",
        dbPath = base .. ".hidden",
        callback = function() refreshBars(); Panel:SelectTab("visibility") end,
    })

    local function visDisabled() return not C:GetDBValue(base .. ".hidden") end

    C:AddHeading(section, LO["Show When"])
    C:AddToggle(section, { label = LO["Show on Hover"],  dbPath = base..".show_on_hover",   disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show in Combat"], dbPath = base..".show_in_combat",  disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show with Target"], dbPath = base..".show_with_target", disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show When Health Is Not Full"], dbPath = base..".show_on_health", disabled = visDisabled, callback = refreshBars })
    C:AddToggle(section, { label = LO["Show When Power Is Not Full"], dbPath = base..".show_on_power", disabled = visDisabled, callback = refreshBars })

    C:AddSlider(section, {
        label = LO["Fade Delay"], dbPath = base..".fade_delay",
        min = 0, max = 20, step = 0.5, width = 200,
        disabled = visDisabled, callback = refreshBars,
    })
    C:AddSlider(section, {
        label = LO["Fade Duration"], dbPath = base..".fade_duration",
        min = 0, max = 5, step = 0.1, width = 200,
        disabled = visDisabled, callback = refreshBars,
    })

    C:AddSpacer(scroll)
end

-- Master section: live-bound. Its own values persist under visibility_master.*
local function BuildMasterVisibilitySection(scroll)
    local section = C:AddSection(scroll, "|cffFFD700Master Visibility|r")
    C:AddDescription(section,
        "Set a value here and it is pushed to every frame below that supports it. Frames that lack an option are skipped automatically. You can still fine-tune any individual frame afterward.")

    local function RebuildTab() Panel:SelectTab("visibility") end

    for _, opt in ipairs(MASTER_OPTS) do
        local masterPath = "visibility_master." .. opt.id
        if opt.kind == "toggle" then
            C:AddToggle(section, {
                label = opt.label,
                dbPath = masterPath,
                callback = function(value)
                    ApplyMaster(opt.id, value)
                    RebuildTab()   -- discrete: re-sync child checkboxes + disabled states
                end,
            })
        else
            C:AddSlider(section, {
                label = opt.label,
                dbPath = masterPath,
                min = opt.min, max = opt.max, step = opt.step, width = 200,
                callback = function(value)
                    ApplyMaster(opt.id, value)
                    -- No rebuild here: slider fires per drag tick. Values still
                    -- apply live; child sliders re-sync on next tab rebuild.
                end,
            })
        end
    end

    C:AddSpacer(scroll)
    return section
end

-- The ONE tab builder.
local function BuildVisibilityTab(scroll)
    C:AddLabel(scroll, "|cffFFD700Visibility|r", { color = C.Theme.textGold })
    C:AddDescription(scroll, "Master control for frame visibility. Check Hidden to hide a frame and reveal it only under the chosen conditions. Unchecked means the frame behaves like the standard UI.")
    C:AddSpacer(scroll)

    -- Master Section
    BuildMasterVisibilitySection(scroll)

    -- Target Frame
    BuildTargetVisibilitySection(scroll)

    -- Player Frame
    BuildPlayerVisibilitySection(scroll)

    -- Buffs
    BuildVisibilitySection(scroll, {
        label = "Buff Visibility",
        base  = "buffs.visibility",
        desc  = "Buffs are always visible by default. The collapse arrow works independently of this.",
        refresh = function()
            if addon.RefreshBuffVisibility then addon.RefreshBuffVisibility() end
        end,
    })

    -- Micro Menu
    BuildVisibilitySection(scroll, {
        label = "Micro Menu Visibility",
        base  = "micromenu.visibility",
        desc  = "The micro menu is always visible by default. Check Hidden to hide it and reveal it only under the conditions below. The bag bar is configured separately.",
        refresh = function()
            if addon.RefreshMicromenuVisibility then addon.RefreshMicromenuVisibility() end
        end,
    })

    -- Bag Bar
    BuildVisibilitySection(scroll, {
        label = "Bag Bar Visibility",
        base  = "bags.visibility",
        desc  = "The bag bar is always visible by default. The inventory and bank windows are not affected.",
        refresh = function()
            if addon.RefreshBagBarVisibility then addon.RefreshBagBarVisibility() end
        end,
    })

    -- Minimap
    BuildVisibilitySection(scroll, {
        label = "Minimap Visibility",
        base  = "minimap.visibility",
        desc  = "The minimap is always visible by default. Check Hidden to hide it and reveal it only under the conditions below.",
        refresh = function()
            if addon.RefreshMinimapVisibility then addon.RefreshMinimapVisibility() end
        end,
        extra = function(section, visDisabled)
            C:AddToggle(section, {
                label = LO["Keep Map Visible"],
                desc = "Fade only the minimap buttons, zone text, calendar, clock and tracking. The map itself and its blips stay fully visible.",
                dbPath = "minimap.visibility.map_only",
                disabled = visDisabled,
                callback = function()
                    if addon.RefreshMinimap then addon:RefreshMinimap() end
                end,
            })
        end,
    })

    BuildXpRepBarSection(scroll, "xp",  "Experience Bar")
    BuildXpRepBarSection(scroll, "rep", "Reputation Bar")

    BuildActionBarSection(scroll, "main",         "Main Action Bar")
    BuildActionBarSection(scroll, "bottom_left",  "Bottom Left Bar")
    BuildActionBarSection(scroll, "bottom_right", "Bottom Right Bar")
    BuildActionBarSection(scroll, "right",        "Right Bar")
    BuildActionBarSection(scroll, "left",         "Left Bar")



end


Panel:RegisterTab("visibility", "Visibility", BuildVisibilityTab, 130)
