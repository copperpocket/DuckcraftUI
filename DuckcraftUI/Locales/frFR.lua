--[[
 DuckcraftUI - French Locale (frFR)
 Community translation — Edit this file to contribute!

 Guidelines:
 - Use `true` for strings you haven't translated yet (falls back to English)
 - Keep format specifiers like %s, %d, %.1f intact
 - Keep slash commands untranslated (/duckcraftui, /dui, /rl)
 - Keep "DuckcraftUI" as addon name untranslated
 - Keep color codes |cff...|r outside of L[] strings
]]

local L = LibStub("AceLocale-3.0"):NewLocale("DuckcraftUI", "frFR")
if not L then return end

-- Example:
-- L["Cannot toggle editor mode during combat!"] = "Impossible de basculer le mode éditeur en combat !"

-- UnitFrameLayers compatibility popup
L["TooltipWidget"] = true
L["DuckcraftUI - UnitFrameLayers Detected"] = true
L["DuckcraftUI already includes Unit Frame Layers functionality (heal prediction, absorb shields, and animated health loss)."] = true
L["Choose how to resolve this overlap:"] = true
L["Use DuckcraftUI: disable external UnitFrameLayers and enable DuckcraftUI layers."] = true
L["Disable Both: disable external UnitFrameLayers and keep DuckcraftUI layers disabled."] = true
L["Use DuckcraftUI"] = true
L["Disable Both"] = true
L["DuckcraftUI - D3D9Ex Warning"] = "DuckcraftUI - Alerte D3D9Ex"
L["DuckcraftUI detected that your client is using D3D9Ex."] = "DuckcraftUI a détecté que votre client utilise D3D9Ex."
L["DuckcraftUI's action bar system is not compatible with D3D9Ex."] = "Le système de barres d'action de DuckcraftUI n'est pas compatible avec D3D9Ex."
L["Some DuckcraftUI action bar textures will be missing while this mode is active."] = "Certaines textures des barres d'action DuckcraftUI manqueront tant que ce mode est actif."
L["If you want to disable this mode, open WTF\\Config.wtf."] = "Si vous voulez désactiver ce mode, ouvrez WTF\\Config.wtf."
L["Delete this line:"] = "Supprimez cette ligne :"
L["Or replace it with:"] = "Ou remplacez-la par :"
L["Hide Gryphons"] = "Masquer les griffons"
L["Understood"] = "Compris"
L["Buttons"] = "Boutons"
L["Main Bars"] = "Barres principales"

L["Copy Text"] = "Copier le texte"

-- Editor mode labels
L["TargetCastbar"] = "Barre d'incantation de la cible"
L["FocusCastbar"] = "Barre d'incantation du focus"
L["Right-click to reset"] = "Clic droit pour réinitialiser"
