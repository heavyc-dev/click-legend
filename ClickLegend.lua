-------------------------------------------------------------------------------
--  ClickLegend
--  Draws your click-cast bindings as a small icon grid: one entry per bound
--  key or button, an ally icon and an enemy icon. Hold Shift / Ctrl / Alt to
--  see that modifier's bindings. Two sources, picked automatically:
--    1. EllesmereUI HoverCast (EllesmereUIDB.clickCast), when it is switched on
--    2. the game's own click casting (C_ClickBindings), otherwise
--  EllesmereUI is optional; this is an unofficial companion for it.
--
--  Read-only: it never changes bindings and creates no secure frames, so it
--  cannot taint or block anything in combat.
-------------------------------------------------------------------------------
local ADDON_NAME = ...

local ipairs, pairs, type, tostring, tonumber, pcall = ipairs, pairs, type, tostring, tonumber, pcall
local tsort, tconcat = table.sort, table.concat
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

local PREFIX = "|cff0cd29fClickLegend|r: "
local function Print(msg) print(PREFIX .. tostring(msg)) end

-------------------------------------------------------------------------------
--  Error containment: nothing in here may spam errors once a second or break
--  a tooltip. Each distinct error reaches the error handler once (so BugSack
--  and the like still see it), up to a small cap.
-------------------------------------------------------------------------------
local reported, reportCount = {}, 0
local function Report(err)
    err = tostring(err)
    if reported[err] or reportCount >= 5 then return end
    reported[err] = true
    reportCount = reportCount + 1
    local handler = geterrorhandler and geterrorhandler()
    if type(handler) == "function" then pcall(handler, "ClickLegend: " .. err) end
end
local function Safe(fn, ...)
    local ok, err = pcall(fn, ...)
    if not ok then Report(err) end
    return ok
end

-------------------------------------------------------------------------------
--  Settings
-------------------------------------------------------------------------------
local DEFAULTS = {
    point = "CENTER", relPoint = "CENTER", x = 0, y = -180,
    scale = 1, alpha = 1, iconSize = 28, spacing = 2,
    locked = false, hidden = false, labels = true, labelSize = 9, bars = true,
    labelStyle = "text",        -- text | icon
    visibility = "always",      -- always | group | combat
    background = false, bgR = 0.04, bgG = 0.04, bgB = 0.04, bgA = 0.6, bgPadding = 4,
    tooltip = true, tooltipWorld = false,
    layout = "horizontal",      -- horizontal | vertical
    rows = "both",              -- both | ally | enemy
    enemyFirst = false,
    sort = "mouse",             -- mouse | keyboard | alpha | custom
    reverse = false,
    perLine = 12,               -- keys per line before the legend wraps
    customOrder = {},           -- list of keys, used when sort == "custom"
}
local RANGES = {
    scale = { 0.5, 2 }, alpha = { 0.1, 1 },
    iconSize = { 16, 64, true }, spacing = { 0, 10, true }, perLine = { 2, 24, true },
    labelSize = { 7, 14, true }, bgPadding = { 0, 20, true },
    bgR = { 0, 1 }, bgG = { 0, 1 }, bgB = { 0, 1 }, bgA = { 0, 1 },
}
local CHOICES = {
    layout = { horizontal = true, vertical = true },
    rows = { both = true, ally = true, enemy = true },
    sort = { mouse = true, keyboard = true, alpha = true, custom = true },
    visibility = { always = true, group = true, combat = true },
    labelStyle = { text = true, icon = true },
}
local POINTS = {
    TOPLEFT = true, TOP = true, TOPRIGHT = true, LEFT = true, CENTER = true,
    RIGHT = true, BOTTOMLEFT = true, BOTTOM = true, BOTTOMRIGHT = true,
}
local db

local function Clamp(v, lo, hi) return max(lo, min(hi, v)) end

local function DefaultFor(key)
    local v = DEFAULTS[key]
    if type(v) == "table" then return {} end
    return v
end

-- Saved settings can be anything (hand edits, an older version, a crash mid
-- write): every value is brought back to its type, range and choice list.
local function SanitizeDB()
    for k, v in pairs(DEFAULTS) do
        if type(db[k]) ~= type(v) then db[k] = DefaultFor(k) end
    end
    for k, r in pairs(RANGES) do
        local v = db[k]
        if v ~= v then v = DEFAULTS[k] end                -- NaN
        v = Clamp(v, r[1], r[2])
        if r[3] then v = floor(v + 0.5) end
        db[k] = v
    end
    for k, set in pairs(CHOICES) do
        if not set[db[k]] then db[k] = DEFAULTS[k] end
    end
    if not POINTS[db.point] then db.point = DEFAULTS.point end
    if not POINTS[db.relPoint] then db.relPoint = DEFAULTS.relPoint end
    if db.x ~= db.x or db.y ~= db.y then db.x, db.y = DEFAULTS.x, DEFAULTS.y end
    local seen, clean = {}, {}
    for _, key in ipairs(db.customOrder) do
        if type(key) == "string" and key ~= "" and not seen[key] then
            seen[key] = true
            clean[#clean + 1] = key
        end
    end
    db.customOrder = clean
end

local function InitDB()
    if type(ClickLegendDB) ~= "table" then ClickLegendDB = {} end
    db = ClickLegendDB
    SanitizeDB()
end

-------------------------------------------------------------------------------
--  Keys: any mouse button, wheel direction or keyboard key can be bound
-------------------------------------------------------------------------------
local KEY_SHORT = {
    BUTTON1 = "L", BUTTON2 = "R", BUTTON3 = "M",
    MOUSEWHEELUP = "WUp", MOUSEWHEELDOWN = "WDn",
    SPACE = "Spc", BACKSPACE = "Bksp", DELETE = "Del", INSERT = "Ins",
    PAGEUP = "PgUp", PAGEDOWN = "PgDn", HOME = "Home", END = "End",
    ESCAPE = "Esc", ENTER = "Ent", TAB = "Tab", CAPSLOCK = "Caps",
    NUMLOCK = "NumL", SCROLLLOCK = "ScrL", PRINTSCREEN = "PrSc", PAUSE = "Paus",
    UP = "Up", DOWN = "Dn", LEFT = "Lt", RIGHT = "Rt",
    NUMPADPLUS = "N+", NUMPADMINUS = "N-", NUMPADMULTIPLY = "N*",
    NUMPADDIVIDE = "N/", NUMPADDECIMAL = "N.",
}
local KEY_LONG = {
    BUTTON1 = "Left Click", BUTTON2 = "Right Click", BUTTON3 = "Middle Click",
    BUTTON4 = "Mouse 4", BUTTON5 = "Mouse 5",
    MOUSEWHEELUP = "Wheel Up", MOUSEWHEELDOWN = "Wheel Down",
}
local MOD_PREFIXES = { "ALT-", "CTRL-", "SHIFT-", "META-" }
local MOD_LONG = { ["ALT-"] = "Alt", ["CTRL-"] = "Ctrl", ["SHIFT-"] = "Shift", ["META-"] = "Cmd" }

-- The label drawn next to an icon: short enough to sit over a 28px icon.
local function ShortKey(key)
    local short = KEY_SHORT[key]
    if short then return short end
    local n = key:match("^BUTTON(%d+)$")
    if n then return "M" .. n end
    n = key:match("^NUMPAD(%d)$")
    if n then return "N" .. n end
    if #key <= 4 then return key end                      -- A, 1, F12, `...
    return key:sub(1, 1) .. key:sub(2, 4):lower()
end

-- The name used in tooltips, chat and the settings page.
local function LongKey(key)
    local long = KEY_LONG[key]
    if long then return long end
    local n = key:match("^BUTTON(%d+)$")
    if n then return "Mouse " .. n end
    if GetBindingText then
        local ok, text = pcall(GetBindingText, key)
        if ok and type(text) == "string" and text ~= "" then return text end
    end
    return key
end

-- "SHIFT-ALT-KEY" -> "ALT-SHIFT-", "KEY". Modifiers are peeled off the front
-- as known prefixes (the key itself can be "-") and rebuilt in the canonical
-- ALT-CTRL-SHIFT-META order, whatever order they were saved in.
local function ParseKey(keyStr)
    local rest, has = keyStr:upper(), {}
    while true do
        local hit
        for _, pre in ipairs(MOD_PREFIXES) do
            if #rest > #pre and rest:sub(1, #pre) == pre then hit = pre; break end
        end
        if not hit then break end
        has[hit] = true
        rest = rest:sub(#hit + 1)
    end
    local mods = ""
    for _, pre in ipairs(MOD_PREFIXES) do
        if has[pre] then mods = mods .. pre end
        if rest == pre then rest = "" end              -- a modifier with no key
    end
    return mods, rest
end

local function ModsLong(mods)
    local parts = {}
    for _, pre in ipairs(MOD_PREFIXES) do
        if mods:find(pre, 1, true) then parts[#parts + 1] = MOD_LONG[pre] end
    end
    return tconcat(parts, "+")
end

local function HeldMods()
    local p = ""
    if IsAltKeyDown() then p = p .. "ALT-" end
    if IsControlKeyDown() then p = p .. "CTRL-" end
    if IsShiftKeyDown() then p = p .. "SHIFT-" end
    if IsMetaKeyDown and IsMetaKeyDown() then p = p .. "META-" end
    return p
end

-------------------------------------------------------------------------------
--  Key order
-------------------------------------------------------------------------------
local function MouseRank(key)
    local n = key:match("^BUTTON(%d+)$")
    if n then return tonumber(n) end
    if key == "MOUSEWHEELUP" then return 1000 end
    if key == "MOUSEWHEELDOWN" then return 1001 end
    return nil
end

-- F2 before F10, NUMPAD2 before NUMPAD10.
local function NaturalLess(a, b)
    local pa, na = a:match("^(.-)(%d*)$")
    local pb, nb = b:match("^(.-)(%d*)$")
    if pa ~= pb then return pa < pb end
    na, nb = tonumber(na) or -1, tonumber(nb) or -1
    if na ~= nb then return na < nb end
    return a < b
end

local function MouseFirstLess(a, b)
    local ra, rb = MouseRank(a), MouseRank(b)
    if ra and rb then return ra < rb end
    if ra or rb then return ra ~= nil end
    return NaturalLess(a, b)
end

local function KeyboardFirstLess(a, b)
    local ra, rb = MouseRank(a), MouseRank(b)
    if ra and rb then return ra < rb end
    if ra or rb then return rb ~= nil end
    return NaturalLess(a, b)
end

local function AlphaLess(a, b)
    local la, lb = ShortKey(a):lower(), ShortKey(b):lower()
    if la ~= lb then return NaturalLess(la, lb) end
    return a < b
end

-- A sorted copy of keys. Keys the custom list does not name follow it in the
-- default (mouse first) order.
local function OrderKeysBy(keys, mode, reverse)
    local out = {}
    for i, key in ipairs(keys) do out[i] = key end
    local less = MouseFirstLess
    if mode == "keyboard" then
        less = KeyboardFirstLess
    elseif mode == "alpha" then
        less = AlphaLess
    elseif mode == "custom" then
        local pos = {}
        for i, key in ipairs(db.customOrder) do
            if not pos[key] then pos[key] = i end
        end
        less = function(a, b)
            local pa, pb = pos[a], pos[b]
            if pa and pb then return pa < pb end
            if pa or pb then return pa ~= nil end
            return MouseFirstLess(a, b)
        end
    end
    if not pcall(tsort, out, less) then pcall(tsort, out) end
    if reverse then
        local n = #out
        for i = 1, floor(n / 2) do out[i], out[n + 1 - i] = out[n + 1 - i], out[i] end
    end
    return out
end

local function OrderKeys(keys)
    return OrderKeysBy(keys, db.sort, db.reverse)
end

-------------------------------------------------------------------------------
--  Entries
-------------------------------------------------------------------------------
local FALLBACK_ICON = 134400
local TYPE_ICON = {
    target = 132212, menu = 5341597, macro = 134400,
    dispel = 135894, external = 135966, dynamicrez = 136080,
}
local TYPE_NAME = {
    target = "Target Unit", menu = "Context Menu", dispel = "Dispel",
    external = "External Defensive", dynamicrez = "Dynamic Rez",
    trinket1 = "Trinket 1", trinket2 = "Trinket 2",
}

local function ValidIcon(icon)
    local t = type(icon)
    if t == "number" or (t == "string" and icon ~= "") then return icon end
    return nil
end

local function SpellTexture(idOrName)
    if not idOrName then return nil end
    if C_Spell and C_Spell.GetSpellTexture then
        local ok, tex = pcall(C_Spell.GetSpellTexture, idOrName)
        if ok and ValidIcon(tex) then return tex end
    end
    if GetSpellTexture then
        local ok, tex = pcall(GetSpellTexture, idOrName)
        if ok and ValidIcon(tex) then return tex end
    end
    return nil
end

local function SpellName(id)
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" and name ~= "" then return name end
    end
    return "Unknown Spell"
end

local function MacroInfo(idOrName)
    if not (idOrName and GetMacroInfo) then return nil end
    local index = idOrName
    if type(idOrName) == "string" then
        if not GetMacroIndexByName then return nil end
        local ok, idx = pcall(GetMacroIndexByName, idOrName)
        if not ok or not idx or idx == 0 then return nil end
        index = idx
    end
    local ok, name, tex = pcall(GetMacroInfo, index)
    if not ok then return nil end
    return name, ValidIcon(tex)
end

local function InventoryTexture(slot)
    if not (slot and GetInventoryItemTexture) then return nil end
    local ok, tex = pcall(GetInventoryItemTexture, "player", slot)
    return ok and ValidIcon(tex) or nil
end

local function Entry(name, icon)
    return {
        name = (type(name) == "string" and name ~= "") and name or "Unknown",
        icon = ValidIcon(icon) or FALLBACK_ICON,
    }
end

-- layers[mods] = { keys = { key, ... }, byKey = { [key] = { ally = entry, enemy = entry } } }
local function PutEntry(layers, mods, key, side, entry)
    local layer = layers[mods]
    if not layer then layer = { keys = {}, byKey = {} }; layers[mods] = layer end
    local slot = layer.byKey[key]
    if not slot then slot = {}; layer.byKey[key] = slot; layer.keys[#layer.keys + 1] = key end
    if not slot[side] then slot[side] = entry end      -- first one wins the key
end

-------------------------------------------------------------------------------
--  Source 1: EllesmereUI HoverCast
-------------------------------------------------------------------------------
local function EUIEntry(b, harmful)
    local t = b.type
    if t == "spell" then
        if harmful then
            return Entry(b.harmfulSpell,
                ValidIcon(b.harmfulIcon) or SpellTexture(b.harmfulSpellID) or SpellTexture(b.harmfulSpell))
        end
        return Entry(b.spell or "Unknown Spell",
            ValidIcon(b.icon) or SpellTexture(b.spellID) or SpellTexture(b.spell))
    elseif t == "macro" then
        local _, tex = MacroInfo(b.macroName)
        return Entry(b.macroName or "Macro", ValidIcon(b.icon) or tex or TYPE_ICON.macro)
    elseif t == "item" then
        return Entry(b.itemName or "Item", InventoryTexture(b.itemSlot) or b.icon)
    elseif t == "trinket1" or t == "trinket2" then
        return Entry(TYPE_NAME[t], InventoryTexture(t == "trinket1" and 13 or 14))
    end
    return Entry(TYPE_NAME[t] or tostring(t), ValidIcon(b.icon) or TYPE_ICON[t])
end

-- Which sides a binding belongs on. Mirrors EllesmereUI: the Friendly toggle
-- is on unless switched off, the Enemy toggle is opt-in.
local function EUISides(b)
    local t = b.type
    if t == "spell" or t == "item" or (t == "macro" and b.hovercast) then
        if t == "spell" and b.harmfulSpell then return true, true, true end
        return b.hoverFriendly ~= false, b.hoverEnemy == true, false
    elseif t == "dispel" or t == "external" or t == "dynamicrez" then
        return true, false, false
    end
    return true, true, false      -- target, menu, trinkets, frame macros
end

local function CurrentContext()
    local ok, _, instType = pcall(IsInInstance)
    if ok and (instType == "pvp" or instType == "arena") then return "pvp" end
    if IsInRaid and IsInRaid() then return "raid" end
    if IsInGroup and IsInGroup() then return "party" end
    return "solo"
end

local function CurrentSpecID()
    local S = C_SpecializationInfo
    if not (S and S.GetSpecialization and S.GetSpecializationInfo) then return nil end
    local ok, idx = pcall(S.GetSpecialization)
    if not ok or not idx then return nil end
    local ok2, id = pcall(S.GetSpecializationInfo, idx)
    if ok2 and type(id) == "number" and id ~= 0 then return id end
    return nil
end

-- Returns nil when HoverCast is switched off, has never been set up, or
-- EllesmereUI is not installed.
local function CollectEUILayers()
    local root = EllesmereUIDB
    local cc = type(root) == "table" and root.clickCast
    if type(cc) ~= "table" or not cc.enabled then return nil end
    local layers, ctx = {}, CurrentContext()

    local function AddList(list)
        if type(list) ~= "table" then return end
        for _, b in ipairs(list) do
            if type(b) == "table" and b.enabled ~= false
                and type(b.key) == "string" and b.key ~= ""
                and (type(b.groupCtx) ~= "table" or b.groupCtx[ctx] == true) then
                local mods, key = ParseKey(b.key)
                if key ~= "" then
                    local ally, enemy, split = EUISides(b)
                    if ally then PutEntry(layers, mods, key, "ally", EUIEntry(b, false)) end
                    if enemy then PutEntry(layers, mods, key, "enemy", EUIEntry(b, split)) end
                end
            end
        end
    end

    -- Spec bindings win a key over global ones, as in EllesmereUI.
    local specID = CurrentSpecID()
    if specID and type(cc.specs) == "table" then AddList(cc.specs[specID]) end
    AddList(cc.globals)
    return layers
end

-------------------------------------------------------------------------------
--  Source 2: the game's own click casting (C_ClickBindings)
-------------------------------------------------------------------------------
local BLIZZ_BUTTON = {
    LEFTBUTTON = "BUTTON1", RIGHTBUTTON = "BUTTON2", MIDDLEBUTTON = "BUTTON3",
}

-- "LeftButton" / "Button4" -> "BUTTON1" / "BUTTON4"
local function BlizzardKey(button)
    if type(button) ~= "string" or button == "" then return nil end
    local up = button:upper()
    return BLIZZ_BUTTON[up] or up
end

-- The profile stores modifiers as a bit field; the game turns it into text
-- ("ALT-SHIFT"). Rebuilt here in the canonical order.
local function BlizzardMods(modifiers)
    if type(modifiers) ~= "number" or modifiers == 0 then return "" end
    local fn = C_ClickBindings.GetStringFromModifiers
    if type(fn) ~= "function" then return nil end
    local ok, text = pcall(fn, modifiers)
    if not ok or type(text) ~= "string" then return nil end
    text = text:upper()
    local mods = ""
    if text:find("ALT", 1, true) then mods = mods .. "ALT-" end
    if text:find("CTRL", 1, true) then mods = mods .. "CTRL-" end
    if text:find("SHIFT", 1, true) then mods = mods .. "SHIFT-" end
    if text:find("META", 1, true) then mods = mods .. "META-" end
    return mods
end

-- The game's click casting has no ally/enemy split: one spell per click, cast
-- on whatever is clicked. A helpful spell goes on the ally side, a harmful one
-- on the enemy side, and one that is neither (or both) on both.
local function SpellSides(id)
    local helpful, harmful = false, false
    if C_Spell and C_Spell.IsSpellHelpful and C_Spell.IsSpellHarmful then
        local ok1, a = pcall(C_Spell.IsSpellHelpful, id)
        local ok2, b = pcall(C_Spell.IsSpellHarmful, id)
        helpful, harmful = (ok1 and a) and true or false, (ok2 and b) and true or false
    end
    if helpful == harmful then return true, true end
    return helpful, harmful
end

-- Returns nil when the client has no click casting or nothing is bound.
local function CollectBlizzardLayers()
    if not (C_ClickBindings and C_ClickBindings.GetProfileInfo) then return nil end
    local ok, profile = pcall(C_ClickBindings.GetProfileInfo)
    if not ok or type(profile) ~= "table" or #profile == 0 then return nil end
    local T = Enum and Enum.ClickBindingType or {}
    local I = Enum and Enum.ClickBindingInteraction or {}
    local tSpell, tMacro = T.Spell or 1, T.Macro or 2
    local tInteraction, tPet = T.Interaction or 3, T.PetAction or 4
    local iTarget, iMenu = I.Target or 1, I.OpenContextMenu or 2

    local layers, any = {}, false
    for _, info in ipairs(profile) do
        local key = type(info) == "table" and BlizzardKey(info.button)
        local mods = key and BlizzardMods(info.modifiers)
        local id = key and info.actionID
        if key and mods and id then
            local entry
            local ally, enemy = true, true
            if info.type == tSpell or info.type == tPet then
                entry = Entry(SpellName(id), SpellTexture(id))
                ally, enemy = SpellSides(id)
            elseif info.type == tMacro then
                local name, tex = MacroInfo(id)
                entry = Entry(name or "Macro", tex or TYPE_ICON.macro)
            elseif info.type == tInteraction then
                if id == iTarget then
                    entry = Entry(TYPE_NAME.target, TYPE_ICON.target)
                elseif id == iMenu then
                    entry = Entry(TYPE_NAME.menu, TYPE_ICON.menu)
                end
            end
            if entry then
                if ally then PutEntry(layers, mods, key, "ally", entry) end
                if enemy then PutEntry(layers, mods, key, "enemy", entry) end
                any = true
            end
        end
    end
    if not any then return nil end
    return layers
end

-------------------------------------------------------------------------------
--  Current bindings
-------------------------------------------------------------------------------
-- Which system the legend is showing: "EllesmereUI HoverCast", "Click Casting", or nil.
local activeSource

local function CollectLayers()
    local ok, layers = pcall(CollectEUILayers)
    if not ok then Report(layers); layers = nil end
    if layers and next(layers) then activeSource = "EllesmereUI HoverCast"; return layers end
    ok, layers = pcall(CollectBlizzardLayers)
    if not ok then Report(layers); layers = nil end
    if layers and next(layers) then activeSource = "Click Casting"; return layers end
    activeSource = nil
    return nil
end

local function SortedMods(layers)
    local list = {}
    for mods in pairs(layers) do list[#list + 1] = mods end
    tsort(list)
    return list
end

-- Signature of everything drawn, and of the set of bound keys alone (the
-- settings page lists the keys, so it is rebuilt only when that set changes).
local function Signatures(layers)
    if not layers then return "off", "" end
    local parts, keySet = { activeSource or "" }, {}
    for _, mods in ipairs(SortedMods(layers)) do
        local layer = layers[mods]
        for _, key in ipairs(OrderKeysBy(layer.keys, "mouse", false)) do
            local slot = layer.byKey[key]
            keySet[key] = true
            parts[#parts + 1] = mods .. key
                .. "<" .. (slot.ally and (tostring(slot.ally.icon) .. slot.ally.name) or "")
                .. ">" .. (slot.enemy and (tostring(slot.enemy.icon) .. slot.enemy.name) or "")
        end
    end
    local keys = {}
    for key in pairs(keySet) do keys[#keys + 1] = key end
    tsort(keys)
    return tconcat(parts, "|"), tconcat(keys, "|")
end

local layers, lastSig, lastKeySig = nil, nil, nil

-- Every bound key across all modifier layers, in the custom order.
local function AllBoundKeys()
    local set, list = {}, {}
    if layers then
        for _, layer in pairs(layers) do
            for _, key in ipairs(layer.keys) do
                if not set[key] then set[key] = true; list[#list + 1] = key end
            end
        end
    end
    return OrderKeysBy(list, "custom", false)
end

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local ALLY_COLOR  = { 0.05, 0.82, 0.62 }
local ENEMY_COLOR = { 0.90, 0.25, 0.25 }
local BAR_W, BAR_GAP, BLOCK_GAP = 3, 3, 8

local panel = CreateFrame("Frame", "ClickLegendPanel", UIParent)
panel:SetSize(120, 28)
panel:SetFrameStrata("MEDIUM")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:Hide()

local bg = panel:CreateTexture(nil, "BACKGROUND")

-- Shown only while unlocked: a tint that marks the area to drag.
local mover = panel:CreateTexture(nil, "OVERLAY")
mover:SetColorTexture(ALLY_COLOR[1], ALLY_COLOR[2], ALLY_COLOR[3], 0.25)

-- The background and the drag tint cover the legend plus the chosen padding.
local function ApplyBackground()
    local pad = db.bgPadding
    for _, tex in ipairs({ bg, mover }) do
        tex:ClearAllPoints()
        tex:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
        tex:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    end
    bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.bgA)
end

local layerText = panel:CreateFontString(nil, "OVERLAY")
layerText:SetPoint("RIGHT", panel, "LEFT", -6, 0)

local bars, cells, labels = {}, {}, {}

-- EllesmereUI's own font and outline when it can be read, the game font otherwise.
local function ApplyFont(fs, size)
    local path, flags
    local E = EllesmereUI
    if type(E) == "table" then
        if type(E.GetFontPath) == "function" then
            local ok, p = pcall(E.GetFontPath)
            if ok and type(p) == "string" and p ~= "" then path = p end
        end
        if type(E.GetFontOutlineFlag) == "function" then
            local ok, f = pcall(E.GetFontOutlineFlag)
            if ok and type(f) == "string" then flags = f end
        end
    end
    local ok, set = pcall(fs.SetFont, fs, path or STANDARD_TEXT_FONT, size, flags or "OUTLINE")
    if not ok or set == false then
        fs:SetFont(STANDARD_TEXT_FONT, size, "OUTLINE")
        flags = "OUTLINE"
    end
    if flags == "" then
        fs:SetShadowColor(0, 0, 0, 1)
        fs:SetShadowOffset(1, -1)
    else
        fs:SetShadowOffset(0, 0)
    end
end

local function GetBar(i)
    local bar = bars[i]
    if not bar then
        bar = panel:CreateTexture(nil, "ARTWORK")
        bars[i] = bar
    end
    return bar
end

local function GetCell(i)
    local cell = cells[i]
    if not cell then
        cell = CreateFrame("Frame", nil, panel)
        cell.border = cell:CreateTexture(nil, "BACKGROUND")
        cell.border:SetAllPoints()
        cell.border:SetColorTexture(0, 0, 0, 1)
        cell.icon = cell:CreateTexture(nil, "ARTWORK")
        cell.icon:SetPoint("TOPLEFT", 1, -1)
        cell.icon:SetPoint("BOTTOMRIGHT", -1, 1)
        cell.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        cells[i] = cell
    end
    return cell
end

local function GetLabel(i)
    local fs = labels[i]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY")
        labels[i] = fs
    end
    return fs
end

-------------------------------------------------------------------------------
--  Mouse glyphs: the "Icons" label style draws a small mouse with the bound
--  button lit, built from plain colored rectangles (no image files). Keyboard
--  keys keep their text label.
-------------------------------------------------------------------------------
local glyphs = {}

-- Width, height, half width and button-zone height of the mouse body.
local function GlyphSize()
    local gh = db.labelSize + 5
    local half = floor(gh * 0.36 + 0.5)
    return half * 2 + 1, gh, half, floor(gh * 0.45 + 0.5)
end

-- The height the label row needs (horizontal layout) for the current style.
local function LabelHeight()
    if not db.labels then return 0 end
    if db.labelStyle == "icon" then return db.labelSize + 9 end
    return db.labelSize + 3
end

local function GetGlyph(i)
    local g = glyphs[i]
    if not g then
        g = CreateFrame("Frame", nil, panel)
        local function Rect(layer, r, gr, b, a)
            local t = g:CreateTexture(nil, layer)
            t:SetColorTexture(r, gr, b, a or 1)
            return t
        end
        g.outline = Rect("BACKGROUND", 0, 0, 0)
        g.outline:SetAllPoints()
        g.body = Rect("BORDER", 0.42, 0.44, 0.48)
        g.divider = Rect("ARTWORK", 0, 0, 0, 0.8)
        g.line = Rect("ARTWORK", 0, 0, 0, 0.8)
        g.lit = Rect("OVERLAY", 1, 1, 1)
        g.tri = { Rect("OVERLAY", 1, 1, 1), Rect("OVERLAY", 1, 1, 1), Rect("OVERLAY", 1, 1, 1) }
        g.num = g:CreateFontString(nil, "OVERLAY")
        glyphs[i] = g
    end
    return g
end

-- Places a rectangle inside the glyph, measured from the body's top left.
local function GlyphRect(g, tex, x, y, w, h)
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", g, "TOPLEFT", 1 + x, -(1 + y))
    tex:SetSize(w, h)
    tex:Show()
end

local function DrawGlyph(g, key)
    local gw, gh, half, bh = GlyphSize()
    g:SetSize(gw + 2, gh + 2)
    GlyphRect(g, g.body, 0, 0, gw, gh)
    GlyphRect(g, g.divider, half, 0, 1, bh)
    GlyphRect(g, g.line, 0, bh, gw, 1)
    g.lit:Hide()
    g.num:Hide()
    for _, t in ipairs(g.tri) do t:Hide() end

    if key == "BUTTON1" then
        GlyphRect(g, g.lit, 0, 0, half, bh)
    elseif key == "BUTTON2" then
        GlyphRect(g, g.lit, half + 1, 0, half, bh)
    elseif key == "BUTTON3" or key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN" then
        GlyphRect(g, g.lit, half - 1, 1, 3, bh - 2)                -- the wheel
        if key ~= "BUTTON3" then
            -- An arrow under the buttons: pointing up for wheel up, down for wheel down.
            local top = bh + 2 + max(0, floor((gh - bh - 2 - 3) / 2) - 1)
            for row = 1, 3 do
                local w = (key == "MOUSEWHEELUP") and (row * 2 - 1) or (7 - row * 2)
                GlyphRect(g, g.tri[row], half - (w - 1) / 2, top + row - 1, w, 1)
            end
        end
    elseif key == "BUTTON4" then
        GlyphRect(g, g.lit, 0, bh + 5, 2, 3)                       -- back: lower side button
    elseif key == "BUTTON5" then
        GlyphRect(g, g.lit, 0, bh + 1, 2, 3)                       -- forward: upper side button
    else
        local n = key:match("^BUTTON(%d+)$")                        -- extra buttons show their number
        ApplyFont(g.num, max(6, db.labelSize - 2))
        g.num:ClearAllPoints()
        g.num:SetPoint("CENTER", g, "TOPLEFT", 1 + gw / 2, -(1 + bh + (gh - bh) / 2))
        g.num:SetText(n or "")
        g.num:Show()
    end
end

-- A key's label: a mouse glyph for mouse buttons in the icon style, text otherwise.
local function PlaceLabel(i, key, point, x, y, alpha)
    if db.labelStyle == "icon" and MouseRank(key) then
        local g = GetGlyph(i)
        DrawGlyph(g, key)
        g:ClearAllPoints()
        g:SetPoint(point, panel, "TOPLEFT", x, y)
        g:SetAlpha(alpha)
        g:Show()
        return
    end
    local fs = GetLabel(i)
    ApplyFont(fs, db.labelSize)
    fs:ClearAllPoints()
    fs:SetPoint(point, panel, "TOPLEFT", x, y)
    fs:SetText(ShortKey(key))
    fs:SetAlpha(alpha)
    fs:Show()
end

-- The sides to draw for a layer, in display order. A side with nothing bound
-- on the whole layer is left out.
local function SidesFor(layer)
    local has = { ally = false, enemy = false }
    for _, key in ipairs(layer.keys) do
        local slot = layer.byKey[key]
        if slot.ally then has.ally = true end
        if slot.enemy then has.enemy = true end
    end
    local order = db.enemyFirst and { "enemy", "ally" } or { "ally", "enemy" }
    local sides = {}
    for _, side in ipairs(order) do
        if has[side] and (db.rows == "both" or db.rows == side) then sides[#sides + 1] = side end
    end
    return sides
end

-- Keys that have something to show on the visible sides.
local function VisibleKeys(layer, sides)
    local keys = {}
    for _, key in ipairs(OrderKeys(layer.keys)) do
        local slot = layer.byKey[key]
        for _, side in ipairs(sides) do
            if slot[side] then keys[#keys + 1] = key; break end
        end
    end
    return keys
end

local function PlaceCell(index, x, y, size, entry, alpha)
    local cell = GetCell(index)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    cell:SetSize(size, size)
    if entry then
        cell.icon:SetTexture(entry.icon)
        cell.icon:Show()
        cell:SetAlpha(alpha)
    else
        cell.icon:Hide()                    -- empty slot keeps the grid aligned
        cell:SetAlpha(0.2 * alpha)
    end
    cell:Show()
end

local function PlaceBar(index, x, y, w, h, side, alpha)
    local bar = GetBar(index)
    local col = side == "ally" and ALLY_COLOR or ENEMY_COLOR
    bar:SetColorTexture(col[1], col[2], col[3], 1)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    bar:SetSize(w, h)
    bar:SetAlpha(alpha)
    bar:Show()
end

-- Horizontal: keys run left to right, one row per side, the key label above.
-- Past perLine keys the legend wraps into another block underneath.
local function LayoutHorizontal(layer, keys, sides, alpha, labelAlpha)
    local size, gap, per = db.iconSize, db.spacing, db.perLine
    local labelH = LabelHeight()
    local left = db.bars and (BAR_W + BAR_GAP) or 0
    local blocks = ceil(#keys / per)
    local blockH = labelH + #sides * (size + gap) - gap
    panel:SetSize(left + min(#keys, per) * (size + gap) - gap,
        blocks * blockH + (blocks - 1) * BLOCK_GAP)

    local cellIndex, barIndex = 0, 0
    for i, key in ipairs(keys) do
        local block, col = floor((i - 1) / per), (i - 1) % per
        local x, y0 = left + col * (size + gap), -block * (blockH + BLOCK_GAP)
        local slot = layer.byKey[key]
        for r, side in ipairs(sides) do
            local y = y0 - labelH - (r - 1) * (size + gap)
            if col == 0 and db.bars then
                barIndex = barIndex + 1
                PlaceBar(barIndex, 0, y, BAR_W, size, side, alpha)
            end
            cellIndex = cellIndex + 1
            PlaceCell(cellIndex, x, y, size, slot[side], alpha)
        end
        if db.labels then
            PlaceLabel(i, key, "BOTTOM", x + size / 2, y0 - labelH + 1, labelAlpha)
        end
    end
end

-- Vertical: keys run top to bottom, one column per side, the key label to the
-- left. Past perLine keys the legend wraps into another block to the right.
local function LayoutVertical(layer, keys, sides, alpha, labelAlpha)
    local size, gap, per = db.iconSize, db.spacing, db.perLine
    local labelW = db.labels and (db.labelSize * 3 + 7) or 0
    local top = db.bars and (BAR_W + BAR_GAP) or 0
    local blocks = ceil(#keys / per)
    local blockW = labelW + #sides * (size + gap) - gap
    panel:SetSize(blocks * blockW + (blocks - 1) * BLOCK_GAP,
        top + min(#keys, per) * (size + gap) - gap)

    local cellIndex, barIndex = 0, 0
    for i, key in ipairs(keys) do
        local block, row = floor((i - 1) / per), (i - 1) % per
        local x0, y = block * (blockW + BLOCK_GAP), -(top + row * (size + gap))
        local slot = layer.byKey[key]
        for c, side in ipairs(sides) do
            local x = x0 + labelW + (c - 1) * (size + gap)
            if row == 0 and db.bars then
                barIndex = barIndex + 1
                PlaceBar(barIndex, x, 0, size, BAR_W, side, alpha)
            end
            cellIndex = cellIndex + 1
            PlaceCell(cellIndex, x, y, size, slot[side], alpha)
        end
        if db.labels then
            PlaceLabel(i, key, "RIGHT", x0 + labelW - 4, y - size / 2, labelAlpha)
        end
    end
end

-- The "Visible" setting: always, only in a group, or only in combat.
local function VisibleNow()
    if db.visibility == "group" then
        return (IsInGroup and IsInGroup()) and true or false
    elseif db.visibility == "combat" then
        return ((InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))) and true or false
    end
    return true
end

local function RenderNow()
    for _, c in ipairs(cells) do c:Hide() end
    for _, l in ipairs(labels) do l:Hide() end
    for _, g in ipairs(glyphs) do g:Hide() end
    for _, b in ipairs(bars) do b:Hide() end

    local unlocked = not db.locked
    ApplyBackground()
    mover:SetShown(unlocked)
    bg:SetShown(db.background)
    panel:EnableMouse(unlocked)

    -- Pick the layer for the modifiers held right now. A modifier with nothing
    -- bound keeps the unmodified layer on screen, dimmed.
    local held = HeldMods()
    local layer, dim = layers and layers[held], false
    if not layer and held ~= "" then
        layer, dim = layers and layers[""], true
    end

    local sides = layer and SidesFor(layer) or {}
    local keys = layer and VisibleKeys(layer, sides) or {}
    local empty = #keys == 0

    -- While unlocked the legend stays up whatever the visibility rule says,
    -- so there is always something to drag.
    if db.hidden or ((empty or not VisibleNow()) and not unlocked) then
        panel:Hide()
        return
    end
    panel:Show()
    panel:SetScale(db.scale)
    panel:SetAlpha(db.alpha)
    ApplyFont(layerText, 10)

    if empty then
        -- Unlocked with nothing to draw: keep a box on screen to drag.
        panel:SetSize(140, db.iconSize)
        layerText:SetText(layers and "" or "No click-cast bindings")
        layerText:SetShown(not layers)
        return
    end

    if db.layout == "vertical" then
        LayoutVertical(layer, keys, sides, dim and 0.3 or 1, dim and 0.4 or 1)
    else
        LayoutHorizontal(layer, keys, sides, dim and 0.3 or 1, dim and 0.4 or 1)
    end

    -- Name the modifier layer being shown ("Shift", or "Shift: none" when the
    -- held modifier has nothing bound).
    if held ~= "" then
        layerText:SetText(dim and (ModsLong(held) .. ": none") or ModsLong(held))
        layerText:Show()
    else
        layerText:Hide()
    end
end

local function Render()
    if db then Safe(RenderNow) end
end

local RebuildSettingsPages      -- defined with the settings page

local function Refresh(force)
    if not db then return end
    local fresh = CollectLayers()
    local ok, sig, keySig = pcall(Signatures, fresh)
    if not ok then Report(sig); return end
    if force or sig ~= lastSig then
        layers, lastSig = fresh, sig
        Render()
    end
    if keySig ~= lastKeySig then
        local first = lastKeySig == nil
        lastKeySig = keySig
        if not first then RebuildSettingsPages() end
    end
end

local function ApplyPosition()
    panel:ClearAllPoints()
    if not pcall(panel.SetPoint, panel, db.point, UIParent, db.relPoint, db.x, db.y) then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

panel:SetScript("OnDragStart", function(self)
    if db and not db.locked then self:StartMoving() end
end)
panel:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    if not db then return end
    local point, _, relPoint, x, y = self:GetPoint(1)
    if POINTS[point] then
        db.point = point
        db.relPoint = POINTS[relPoint] and relPoint or point
        db.x, db.y = tonumber(x) or 0, tonumber(y) or 0
    end
    ApplyPosition()
end)

-------------------------------------------------------------------------------
--  Unit tooltip: the bindings that apply to the unit under the cursor.
--  A friendly unit lists the ally spells, an attackable one the enemy spells,
--  for the modifiers held when the tooltip is built.
-------------------------------------------------------------------------------
local function OverWorld()
    local focus
    if GetMouseFoci then
        local ok, foci = pcall(GetMouseFoci)
        focus = ok and type(foci) == "table" and foci[1] or nil
    elseif GetMouseFocus then
        local ok, f = pcall(GetMouseFocus)
        focus = ok and f or nil
    end
    return focus == nil or focus == WorldFrame
end

local function TooltipUnit(tooltip)
    if UnitExists and UnitExists("mouseover") then return "mouseover" end
    if tooltip.GetUnit then
        local ok, _, unit = pcall(tooltip.GetUnit, tooltip)
        if ok and type(unit) == "string" then return unit end
    end
    return nil
end

local function AddTooltipBindingsNow(tooltip)
    if tooltip ~= GameTooltip or not db or not db.tooltip or not layers then return end
    if tooltip.IsForbidden and tooltip:IsForbidden() then return end
    if not db.tooltipWorld and OverWorld() then return end
    local unit = TooltipUnit(tooltip)
    if not unit then return end
    local ok, hostile = pcall(UnitCanAttack, "player", unit)
    if not ok or (issecretvalue and issecretvalue(hostile)) then return end
    local side = hostile and "enemy" or "ally"
    local col = hostile and ENEMY_COLOR or ALLY_COLOR

    local held = HeldMods()
    local layer = layers[held]
    if not layer then return end
    local added = false
    for _, key in ipairs(OrderKeys(layer.keys)) do
        local entry = layer.byKey[key][side]
        if entry then
            if not added then tooltip:AddLine(" "); added = true end
            local keyName = (held ~= "" and (ModsLong(held) .. "+") or "") .. LongKey(key)
            tooltip:AddDoubleLine(keyName,
                "|T" .. tostring(entry.icon) .. ":14:14:0:0:64:64:5:59:5:59|t " .. entry.name,
                0.7, 0.7, 0.7, col[1], col[2], col[3])
        end
    end
    if added then tooltip:Show() end
end

local function AddTooltipBindings(tooltip)
    Safe(AddTooltipBindingsNow, tooltip)
end

-- Some unit frames (party and raid frames among them) build their tooltip once
-- and never refresh it, so a modifier pressed while hovering would leave the
-- old layer's lines up. Rebuild the unit tooltip when the modifiers change.
local function RefreshUnitTooltipNow()
    local tip = GameTooltip
    if not (tip and db and db.tooltip and layers) then return end
    if tip.IsForbidden and tip:IsForbidden() then return end
    if not (tip.IsShown and tip:IsShown()) then return end
    if not db.tooltipWorld and OverWorld() then return end
    if not tip.GetUnit then return end
    local name, unit = tip:GetUnit()
    if not name then return end                            -- not a unit tooltip
    if tip.RefreshData then
        tip:RefreshData()
    elseif tip.SetUnit then
        if type(unit) ~= "string" then unit = TooltipUnit(tip) end
        if unit then tip:SetUnit(unit) end
    end
end

-- Silent on failure: this runs on every modifier press, and a tooltip that
-- cannot be rebuilt right now just keeps its old lines.
local function RefreshUnitTooltip()
    pcall(RefreshUnitTooltipNow)
end

local function HookTooltip()
    if TooltipDataProcessor and TooltipDataProcessor.AddTooltipPostCall
        and Enum and Enum.TooltipDataType and Enum.TooltipDataType.Unit then
        TooltipDataProcessor.AddTooltipPostCall(Enum.TooltipDataType.Unit, AddTooltipBindings)
    elseif GameTooltip and GameTooltip.HookScript then
        pcall(GameTooltip.HookScript, GameTooltip, "OnTooltipSetUnit", AddTooltipBindings)
    end
end

-------------------------------------------------------------------------------
--  Changing the order
-------------------------------------------------------------------------------
-- Moves a key to a position in the custom order and switches to that order.
local function SetCustomPosition(key, position)
    local list = AllBoundKeys()
    for i = #list, 1, -1 do
        if list[i] == key then table.remove(list, i) end
    end
    table.insert(list, Clamp(position, 1, #list + 1), key)
    -- Keys named earlier that are not bound right now keep their place after.
    local seen = {}
    for _, k in ipairs(list) do seen[k] = true end
    for _, k in ipairs(db.customOrder) do
        if not seen[k] then seen[k] = true; list[#list + 1] = k end
    end
    db.customOrder = list
    db.sort = "custom"
end

-- "l", "m4", "wheel up", "BUTTON5", "f" -> the bound key it names, or nil.
local function ResolveKeyToken(token, bound)
    token = token:lower()
    for _, key in ipairs(bound) do
        if key:lower() == token or ShortKey(key):lower() == token
            or LongKey(key):lower():gsub("%s+", "") == token then
            return key
        end
    end
    return nil
end

-------------------------------------------------------------------------------
--  Options: one list, shown two ways. With EllesmereUI installed it becomes
--  pages in the EllesmereUI options panel; with or without it, the same list
--  drives the addon's own settings window (/clg).
-------------------------------------------------------------------------------
local OPTIONS = {
    Display = {
        { header = "LEGEND" },
        { kind = "toggle", key = "hidden", invert = true, text = "Show the legend" },
        { kind = "toggle", key = "locked", text = "Lock position",
          tip = "Unlock to drag the legend, then lock it again." },
        { kind = "choice", key = "visibility", text = "Visible",
          values = { always = "Always", group = "In a group", combat = "In combat" },
          order = { "always", "group", "combat" } },
        { kind = "choice", key = "layout", text = "Layout",
          values = { horizontal = "Horizontal", vertical = "Vertical" },
          order = { "horizontal", "vertical" },
          tip = "Horizontal runs the buttons left to right; vertical runs them top to bottom." },
        { kind = "choice", key = "rows", text = "Show",
          values = { both = "Ally and enemy", ally = "Ally only", enemy = "Enemy only" },
          order = { "both", "ally", "enemy" } },
        { kind = "range", key = "perLine", text = "Buttons per line", lo = 2, hi = 24, step = 1 },
        { kind = "range", key = "iconSize", text = "Icon size", lo = 16, hi = 64, step = 1 },
        { kind = "range", key = "spacing", text = "Icon spacing", lo = 0, hi = 10, step = 1 },
        { kind = "range", key = "scale", text = "Scale", lo = 0.5, hi = 2, step = 0.05 },
        { kind = "range", key = "alpha", text = "Opacity", lo = 0.1, hi = 1, step = 0.05 },
        { kind = "toggle", key = "labels", text = "Button labels" },
        { kind = "choice", key = "labelStyle", text = "Label style",
          values = { text = "Text", icon = "Icons" }, order = { "text", "icon" },
          tip = "Icons draw a small mouse with the bound button lit. Keyboard keys keep their text." },
        { kind = "range", key = "labelSize", text = "Label size", lo = 7, hi = 14, step = 1 },
        { kind = "toggle", key = "bars", text = "Ally / enemy color bars" },
        { header = "BACKGROUND" },
        { kind = "toggle", key = "background", text = "Show background" },
        { kind = "color", text = "Background color and opacity" },
        { kind = "range", key = "bgPadding", text = "Background padding", lo = 0, hi = 20, step = 1 },
        { header = "TOOLTIP" },
        { kind = "toggle", key = "tooltip", text = "Show bindings in unit tooltips",
          tip = "Hovering a friendly unit frame lists your ally spells; an enemy frame lists your enemy spells." },
        { kind = "toggle", key = "tooltipWorld", text = "Also on units in the world",
          tip = "Adds the bindings to tooltips of units you hover in the world, not only unit frames." },
    },
    Order = {
        { header = "ORDER" },
        { kind = "choice", key = "sort", text = "Sort buttons by",
          values = { mouse = "Mouse buttons first", keyboard = "Keyboard keys first",
                     alpha = "Alphabetical", custom = "Custom" },
          order = { "mouse", "keyboard", "alpha", "custom" },
          tip = "Custom uses the positions below." },
        { kind = "toggle", key = "reverse", text = "Reverse the order" },
        { kind = "toggle", key = "enemyFirst", text = "Enemy spells first",
          tip = "Puts the enemy spells before the ally spells." },
    },
}
local PAGES = { "Display", "Order" }

local RefreshWindow             -- defined with the settings window

local function OptGet(o)
    if o.kind == "toggle" then return (not o.invert) == (db[o.key] and true or false) end
    return db[o.key]
end

-- Every change, from either settings surface or a slash command, lands here.
local function OptSet(o, v)
    if not db then return end
    if o.kind == "toggle" then
        db[o.key] = (not o.invert) == (v and true or false)
    elseif o.kind == "choice" then
        if not o.values[v] then return end
        db[o.key] = v
    elseif o.kind == "range" then
        if type(v) ~= "number" then return end
        db[o.key] = floor(v / o.step + 0.5) * o.step      -- no drift from repeated steps
    end
    SanitizeDB()
    Refresh(true)
    RefreshWindow()
end

local function GetBgColor()
    return db.bgR, db.bgG, db.bgB, db.bgA
end

local function SetBgColor(r, g, b, a)
    if not db then return end
    if type(r) == "number" then db.bgR = r end
    if type(g) == "number" then db.bgG = g end
    if type(b) == "number" then db.bgB = b end
    if type(a) == "number" then db.bgA = a end
    SanitizeDB()
    Refresh(true)
    RefreshWindow()
end

local function ResetSettings()
    for k in pairs(DEFAULTS) do db[k] = DefaultFor(k) end
    ApplyPosition()
    Refresh(true)
    RefreshWindow()
end

-------------------------------------------------------------------------------
--  Settings pages inside the EllesmereUI options panel, through EllesmereUI's
--  documented plugin API (PLUGINS_API.md). It gets a sidebar section of its own.
-------------------------------------------------------------------------------
local PLUGIN_ID, MODULE_KEY = "ClickLegend", "General"
local pluginRegistered = false

local function BuildSettingsPage(pageName, parent, yOffset)
    local W = EllesmereUI.Widgets
    local y = yOffset
    local _, h
    for _, o in ipairs(OPTIONS[pageName] or OPTIONS.Display) do
        if o.header then
            _, h = W:SectionHeader(parent, o.header, y)
        elseif o.kind == "toggle" then
            _, h = W:Toggle(parent, o.text, y,
                function() return db ~= nil and OptGet(o) end,
                function(v) OptSet(o, v) end, o.tip)
        elseif o.kind == "choice" then
            _, h = W:Dropdown(parent, o.text, y, o.values,
                function() return db and db[o.key] or DEFAULTS[o.key] end,
                function(v) OptSet(o, v) end, o.order, o.tip)
        elseif o.kind == "range" then
            _, h = W:Slider(parent, o.text, y, o.lo, o.hi, o.step,
                function() return db and db[o.key] or DEFAULTS[o.key] end,
                function(v) OptSet(o, v) end)
        elseif o.kind == "color" then
            _, h = W:ColorPicker(parent, o.text, y,
                function()
                    if db then return GetBgColor() end
                    return DEFAULTS.bgR, DEFAULTS.bgG, DEFAULTS.bgB, DEFAULTS.bgA
                end,
                function(r, g, b, a) SetBgColor(r, g, b, a) end, true)
        end
        y = y - (h or 0)
    end

    if pageName == "Order" then
        -- One row per bound key. Picking a key for a position moves it there
        -- and switches the sort to Custom.
        local bound = db and AllBoundKeys() or {}
        if #bound > 0 then
            _, h = W:SectionHeader(parent, "CUSTOM ORDER", y); y = y - h
            local values, order = {}, {}
            for i, key in ipairs(bound) do
                values[key] = LongKey(key)
                order[i] = key
            end
            for i = 1, #bound do
                _, h = W:Dropdown(parent, "Position " .. i, y, values,
                    function() return (AllBoundKeys())[i] end,
                    function(v)
                        if not (db and values[v]) then return end
                        SetCustomPosition(v, i)
                        Refresh(true)
                        RefreshWindow()
                        -- The other rows now show different keys: rebuild the
                        -- page, after this dropdown has finished closing.
                        if C_Timer and C_Timer.After then
                            C_Timer.After(0, RebuildSettingsPages)
                        end
                    end, order)
                y = y - h
            end
        end
    end
    return math.abs(y)
end

-- Drops the cached settings pages (the Order page lists the bound keys) and
-- rebuilds the visible one when it is ours.
RebuildSettingsPages = function()
    RefreshWindow()
    local E = EllesmereUI
    if not pluginRegistered or type(E) ~= "table" then return end
    if InCombatLockdown and InCombatLockdown() then return end
    if type(E.GetPluginModuleKey) ~= "function" then return end
    local ok, key = pcall(E.GetPluginModuleKey, PLUGIN_ID, MODULE_KEY)
    if not ok or not key then return end
    if type(E.InvalidateModulePageCache) == "function" then
        pcall(E.InvalidateModulePageCache, E, key)
    end
    if type(E.GetActiveModule) == "function" and type(E.RefreshPage) == "function" then
        local ok2, active = pcall(E.GetActiveModule, E)
        if ok2 and active == key then pcall(E.RefreshPage, E, true) end
    end
end

local function RegisterSettingsPage()
    local E = EllesmereUI
    if type(E) ~= "table" or type(E.RegisterPlugin) ~= "function" then return end
    local ok, registered = pcall(E.RegisterPlugin, PLUGIN_ID, {
        label = "ClickLegend",
        modules = {
            {
                key = MODULE_KEY,
                title = "ClickLegend",
                description = "An on-screen legend of your click-cast bindings: EllesmereUI HoverCast when it is on, the game's own Click Casting otherwise.",
                pages = PAGES,
                buildPage = BuildSettingsPage,
                onReset = function() if db then ResetSettings() end end,
            },
        },
    })
    pluginRegistered = ok and registered == true
end

local function OpenSettings()
    local E = EllesmereUI
    if not pluginRegistered or type(E) ~= "table" or type(E.OpenPlugin) ~= "function" then return false end
    local ok, opened = pcall(E.OpenPlugin, PLUGIN_ID)
    return ok and opened == true
end

-------------------------------------------------------------------------------
--  The addon's own settings window. Built from plain frames and textures (no
--  templates), so it works on any client, with or without EllesmereUI.
-------------------------------------------------------------------------------
local WIN_W, WIN_H, ROW_H, WIN_PAD = 400, 520, 26, 16
local window                    -- created on first open
local activeTab = "Display"

local function NewText(parent, size, r, g, b)
    local fs = parent:CreateFontString(nil, "OVERLAY")
    ApplyFont(fs, size)
    fs:SetTextColor(r or 1, g or 1, b or 1)
    return fs
end

local function NewButton(parent, w, h, text)
    local b = CreateFrame("Button", nil, parent)
    b:SetSize(w, h)
    b.bg = b:CreateTexture(nil, "BACKGROUND")
    b.bg:SetAllPoints()
    b.bg:SetColorTexture(0.16, 0.17, 0.19, 1)
    b.label = NewText(b, 11)
    b.label:SetPoint("CENTER")
    b.label:SetText(text or "")
    b:SetScript("OnEnter", function(self) self.bg:SetColorTexture(0.26, 0.28, 0.31, 1) end)
    b:SetScript("OnLeave", function(self) self.bg:SetColorTexture(0.16, 0.17, 0.19, 1) end)
    return b
end

-- The game's color picker, in its current form and the older one.
local function OpenColorPicker(r, g, b, a, onChange)
    local CP = ColorPickerFrame
    if not CP then return end
    local function Apply()
        local nr, ng, nb = CP:GetColorRGB()
        local na = a
        if CP.GetColorAlpha then
            na = CP:GetColorAlpha()
        elseif OpacitySliderFrame and OpacitySliderFrame.GetValue then
            na = 1 - OpacitySliderFrame:GetValue()
        end
        onChange(nr, ng, nb, na)
    end
    local function Cancel() onChange(r, g, b, a) end
    if CP.SetupColorPickerAndShow then
        CP:SetupColorPickerAndShow({
            r = r, g = g, b = b, opacity = a, hasOpacity = true,
            swatchFunc = Apply, opacityFunc = Apply, cancelFunc = Cancel,
        })
    else
        CP.hasOpacity, CP.opacity = true, 1 - a
        CP.func, CP.opacityFunc, CP.cancelFunc = Apply, Apply, Cancel
        CP:SetColorRGB(r, g, b)
        CP:Hide()
        CP:Show()
    end
end

local function FormatNumber(o, v)
    if o.step >= 1 then return tostring(floor(v + 0.5)) end
    return ("%.2f"):format(v)
end

local function AttachTip(row, tip)
    if not tip then return end
    row:EnableMouse(true)
    row:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_RIGHT")
        GameTooltip:SetText(tip, 1, 1, 1, 1, true)
        GameTooltip:Show()
    end)
    row:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
end

-- One row of the window for one option. row.Update redraws its value.
local function NewOptionRow(parent, o)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - WIN_PAD * 2, ROW_H)
    if o.header then
        local text = NewText(row, 11, ALLY_COLOR[1], ALLY_COLOR[2], ALLY_COLOR[3])
        text:SetPoint("BOTTOMLEFT", 0, 5)
        text:SetText(o.header)
        row.Update = function() end
        return row
    end
    local label = NewText(row, 12)
    label:SetPoint("LEFT")
    label:SetText(o.text)
    AttachTip(row, o.tip)

    if o.kind == "toggle" then
        local b = NewButton(row, 46, 20)
        b:SetPoint("RIGHT")
        b:SetScript("OnClick", function() OptSet(o, not OptGet(o)) end)
        row.Update = function()
            local on = OptGet(o)
            b.label:SetText(on and "On" or "Off")
            if on then
                b.label:SetTextColor(ALLY_COLOR[1], ALLY_COLOR[2], ALLY_COLOR[3])
            else
                b.label:SetTextColor(0.6, 0.6, 0.6)
            end
        end
    elseif o.kind == "choice" then
        -- Left click steps forward through the choices, right click back.
        local b = NewButton(row, 160, 20)
        b:SetPoint("RIGHT")
        b:RegisterForClicks("LeftButtonUp", "RightButtonUp")
        b:SetScript("OnClick", function(_, button)
            local index = 1
            for i, value in ipairs(o.order) do
                if value == db[o.key] then index = i; break end
            end
            index = index + (button == "RightButton" and -1 or 1)
            if index > #o.order then index = 1 elseif index < 1 then index = #o.order end
            OptSet(o, o.order[index])
        end)
        row.Update = function() b.label:SetText(o.values[db[o.key]] or "?") end
    elseif o.kind == "range" then
        -- Minus and plus step the value; hold Shift for steps of five.
        local plus = NewButton(row, 20, 20, "+")
        plus:SetPoint("RIGHT")
        local value = NewText(row, 12)
        value:SetPoint("RIGHT", plus, "LEFT", -6, 0)
        value:SetWidth(44)
        value:SetJustifyH("CENTER")
        local minus = NewButton(row, 20, 20, "-")
        minus:SetPoint("RIGHT", value, "LEFT", -6, 0)
        local function Step(dir)
            local step = o.step * (IsShiftKeyDown() and 5 or 1)
            OptSet(o, Clamp(db[o.key] + dir * step, o.lo, o.hi))
        end
        plus:SetScript("OnClick", function() Step(1) end)
        minus:SetScript("OnClick", function() Step(-1) end)
        row.Update = function() value:SetText(FormatNumber(o, db[o.key])) end
    elseif o.kind == "color" then
        local b = NewButton(row, 46, 20)
        b:SetPoint("RIGHT")
        b.swatch = b:CreateTexture(nil, "ARTWORK")
        b.swatch:SetPoint("TOPLEFT", 2, -2)
        b.swatch:SetPoint("BOTTOMRIGHT", -2, 2)
        local percent = NewText(row, 11, 0.7, 0.7, 0.7)
        percent:SetPoint("RIGHT", b, "LEFT", -8, 0)
        b:SetScript("OnClick", function()
            local r, g, bl, a = GetBgColor()
            OpenColorPicker(r, g, bl, a, SetBgColor)
        end)
        row.Update = function()
            local r, g, bl, a = GetBgColor()
            b.swatch:SetColorTexture(r, g, bl, 1)
            percent:SetText(floor(a * 100 + 0.5) .. "%")
        end
    end
    return row
end

-- One row per bound key on the Order tab, with Up and Down to move it.
local function NewOrderRow(parent)
    local row = CreateFrame("Frame", nil, parent)
    row:SetSize(WIN_W - WIN_PAD * 2, ROW_H)
    row.label = NewText(row, 12)
    row.label:SetPoint("LEFT")
    row.down = NewButton(row, 46, 20, "Down")
    row.down:SetPoint("RIGHT")
    row.up = NewButton(row, 46, 20, "Up")
    row.up:SetPoint("RIGHT", row.down, "LEFT", -6, 0)
    local function Move(delta)
        if not (db and row.key) then return end
        SetCustomPosition(row.key, row.index + delta)
        Refresh(true)
        RebuildSettingsPages()
    end
    row.up:SetScript("OnClick", function() Move(-1) end)
    row.down:SetScript("OnClick", function() Move(1) end)
    return row
end

local function BuildWindow()
    local f = CreateFrame("Frame", "ClickLegendOptions", UIParent)
    f:SetSize(WIN_W, WIN_H)
    f:SetPoint("CENTER")
    f:SetFrameStrata("DIALOG")
    f:SetClampedToScreen(true)
    f:SetMovable(true)
    f:EnableMouse(true)
    f:RegisterForDrag("LeftButton")
    f:SetScript("OnDragStart", f.StartMoving)
    f:SetScript("OnDragStop", f.StopMovingOrSizing)
    f:Hide()
    if type(UISpecialFrames) == "table" then
        UISpecialFrames[#UISpecialFrames + 1] = "ClickLegendOptions"      -- Escape closes it
    end

    local edge = f:CreateTexture(nil, "BACKGROUND")
    edge:SetAllPoints()
    edge:SetColorTexture(0, 0, 0, 1)
    local fill = f:CreateTexture(nil, "BORDER")
    fill:SetPoint("TOPLEFT", 1, -1)
    fill:SetPoint("BOTTOMRIGHT", -1, 1)
    fill:SetColorTexture(0.07, 0.08, 0.09, 0.97)

    local title = NewText(f, 14)
    title:SetPoint("TOPLEFT", WIN_PAD, -12)
    title:SetText("ClickLegend")
    f.source = NewText(f, 10, 0.6, 0.6, 0.6)
    f.source:SetPoint("LEFT", title, "RIGHT", 10, 0)

    local close = NewButton(f, 22, 22, "X")
    close:SetPoint("TOPRIGHT", -8, -8)
    close:SetScript("OnClick", function() f:Hide() end)

    f.tabs = {}
    for i, name in ipairs(PAGES) do
        local tab = NewButton(f, 90, 22, name)
        tab:SetPoint("TOPLEFT", WIN_PAD + (i - 1) * 96, -40)
        tab:SetScript("OnClick", function()
            activeTab = name
            f.scroll:SetVerticalScroll(0)
            RefreshWindow()
        end)
        f.tabs[name] = tab
    end

    -- Scrolling area: the Order tab grows with the number of bound keys.
    local scroll = CreateFrame("ScrollFrame", nil, f)
    scroll:SetPoint("TOPLEFT", WIN_PAD, -72)
    scroll:SetPoint("BOTTOMRIGHT", -WIN_PAD, 48)
    local content = CreateFrame("Frame", nil, scroll)
    content:SetSize(WIN_W - WIN_PAD * 2, 10)
    scroll:SetScrollChild(content)
    scroll:EnableMouseWheel(true)
    scroll:SetScript("OnMouseWheel", function(self, delta)
        local range = max(0, (content:GetHeight() or 0) - (self:GetHeight() or 0))
        self:SetVerticalScroll(Clamp((self:GetVerticalScroll() or 0) - delta * 40, 0, range))
    end)
    f.scroll, f.content = scroll, content

    f.rows = {}
    for _, name in ipairs(PAGES) do
        f.rows[name] = {}
        for i, o in ipairs(OPTIONS[name]) do
            f.rows[name][i] = NewOptionRow(content, o)
        end
    end
    f.orderHeader = NewOptionRow(content, { header = "CUSTOM ORDER" })
    f.orderRows = {}

    local reset = NewButton(f, 110, 24, "Reset to defaults")
    reset:SetPoint("BOTTOMLEFT", WIN_PAD, 14)
    reset:SetScript("OnClick", function() if db then ResetSettings() end end)
    f.hint = NewText(f, 10, 0.6, 0.6, 0.6)
    f.hint:SetPoint("BOTTOMRIGHT", -WIN_PAD, 20)
    f.hint:SetText("Shift-click + or - for bigger steps")
    return f
end

local function RefreshWindowNow()
    local f = window
    f.source:SetText(activeSource and ("showing " .. activeSource) or "no bindings found")
    for name, tab in pairs(f.tabs) do
        if name == activeTab then
            tab.label:SetTextColor(ALLY_COLOR[1], ALLY_COLOR[2], ALLY_COLOR[3])
        else
            tab.label:SetTextColor(1, 1, 1)
        end
    end

    local y = 0
    local function Place(row)
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", f.content, "TOPLEFT", 0, -y)
        row:Show()
        y = y + ROW_H
    end
    for name, rows in pairs(f.rows) do
        for _, row in ipairs(rows) do
            if name == activeTab then
                row.Update()
                Place(row)
            else
                row:Hide()
            end
        end
    end

    f.orderHeader:Hide()
    for _, row in ipairs(f.orderRows) do row:Hide() end
    if activeTab == "Order" then
        local bound = AllBoundKeys()
        if #bound > 0 then Place(f.orderHeader) end
        for i, key in ipairs(bound) do
            local row = f.orderRows[i]
            if not row then
                row = NewOrderRow(f.content)
                f.orderRows[i] = row
            end
            row.key, row.index = key, i
            row.label:SetText(i .. ".  " .. LongKey(key))
            Place(row)
        end
    end

    f.content:SetHeight(max(y, 10))
    local range = max(0, y - (f.scroll:GetHeight() or 0))
    if (f.scroll:GetVerticalScroll() or 0) > range then f.scroll:SetVerticalScroll(range) end
    f.hint:SetShown(activeTab == "Display")
end

RefreshWindow = function()
    if window and window:IsShown() and db then Safe(RefreshWindowNow) end
end

-- Opens the window, or closes it when it is already open (unless forced open).
local function ToggleWindow(forceOpen)
    if not db then return end
    if not window then
        local ok, built = pcall(BuildWindow)
        if not ok then Report(built); return end
        window = built
    end
    if window:IsShown() and not forceOpen then
        window:Hide()
        return
    end
    window:Show()
    RefreshWindow()
end

-- An entry in the game's own AddOns options list that opens the window.
local function RegisterGameOptions()
    if not (Settings and Settings.RegisterCanvasLayoutCategory and Settings.RegisterAddOnCategory) then return end
    local holder = CreateFrame("Frame")
    holder:Hide()
    local text = NewText(holder, 13)
    text:SetPoint("TOPLEFT", 16, -16)
    text:SetText("ClickLegend settings open in their own window.")
    local open = NewButton(holder, 200, 26, "Open ClickLegend settings")
    open:SetPoint("TOPLEFT", 16, -44)
    open:SetScript("OnClick", function() ToggleWindow(true) end)
    local ok, category = pcall(Settings.RegisterCanvasLayoutCategory, holder, "ClickLegend")
    if ok and category then pcall(Settings.RegisterAddOnCategory, category) end
end

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
local function ListBindings()
    if not layers then
        Print("no click-cast bindings found. Set them up in EllesmereUI (Raid Frames > HoverCast) or in the game's Click Casting settings.")
        return
    end
    Print("current bindings (" .. (activeSource or "?") .. ")")
    for _, mods in ipairs(SortedMods(layers)) do
        local layer = layers[mods]
        for _, key in ipairs(OrderKeys(layer.keys)) do
            local slot = layer.byKey[key]
            local keyName = (mods ~= "" and (ModsLong(mods) .. "+") or "") .. LongKey(key)
            local ally = slot.ally and slot.ally.name
            local enemy = slot.enemy and slot.enemy.name
            local text
            if ally and enemy and ally == enemy then
                text = ally
            else
                text = "|cff0cd29f" .. (ally or "-") .. "|r / |cffe64040" .. (enemy or "-") .. "|r"
            end
            print("  " .. keyName .. ": " .. text)
        end
    end
end

local function Help()
    Print("commands")
    print("  /clg menu - open the ClickLegend settings window")
    print("  /clg config - open the settings in EllesmereUI (or the window without it)")
    print("  /clg lock | unlock - lock in place, or unlock to drag")
    print("  /clg show | hide - toggle the legend")
    print("  /clg visible always | group | combat (now " .. db.visibility .. ")")
    print("  /clg layout horizontal | vertical (now " .. db.layout .. ")")
    print("  /clg rows both | ally | enemy (now " .. db.rows .. ")")
    print("  /clg flip - enemy spells first, or ally spells first")
    print("  /clg sort mouse | keyboard | alpha | custom (now " .. db.sort .. ")")
    print("  /clg order <keys> - custom order, e.g. /clg order M4 M5 L R")
    print("  /clg reverse - reverse the order")
    print("  /clg wrap <2-24> - buttons per line (now " .. db.perLine .. ")")
    print("  /clg size <16-64> | scale <0.5-2> | alpha <0.1-1>")
    print("  /clg labels | bars | tooltip - toggle labels, color bars, tooltip lines")
    print("  /clg labelstyle text | icon (now " .. db.labelStyle .. ")")
    print("  /clg labelsize <7-14> - label size (now " .. db.labelSize .. ")")
    print("  /clg bg - toggle the background")
    print("  /clg bgcolor <RRGGBB> - background color, e.g. /clg bgcolor 101418")
    print("  /clg bgalpha <0-1> | pad <0-20> - background opacity and padding")
    print("  /clg list - print every binding to chat")
    print("  /clg reset - default position and settings")
end

local function SetChoice(key, value)
    if CHOICES[key][value] then db[key] = value; return true end
    local options = {}
    for option in pairs(CHOICES[key]) do options[#options + 1] = option end
    tsort(options)
    Print("use one of: " .. tconcat(options, ", "))
    return false
end

local function HandleSlash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local num = tonumber(arg)
    if cmd == "lock" then
        db.locked = true; Print("locked.")
    elseif cmd == "unlock" then
        db.locked = false; db.hidden = false; Print("unlocked - drag it, then /clg lock.")
    elseif cmd == "show" then
        db.hidden = false
    elseif cmd == "hide" then
        db.hidden = true
    elseif cmd == "size" and num then
        db.iconSize = num
    elseif cmd == "scale" and num then
        db.scale = num
    elseif cmd == "alpha" and num then
        db.alpha = num
    elseif cmd == "wrap" and num then
        db.perLine = num
    elseif cmd == "labelsize" and num then
        db.labelSize = num
    elseif cmd == "bgalpha" and num then
        db.bgA = num
    elseif cmd == "pad" and num then
        db.bgPadding = num
    elseif cmd == "bgcolor" then
        local r, g, b = arg:match("^#?(%x%x)(%x%x)(%x%x)$")
        if not r then Print("use six hex digits, e.g. /clg bgcolor 101418"); return end
        db.bgR, db.bgG, db.bgB = tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
        db.background = true
    elseif cmd == "bars" then
        db.bars = not db.bars
    elseif cmd == "visible" then
        if not SetChoice("visibility", arg) then return end
    elseif cmd == "labelstyle" then
        if not SetChoice("labelStyle", arg) then return end
    elseif cmd == "labels" then
        db.labels = not db.labels
    elseif cmd == "bg" then
        db.background = not db.background
    elseif cmd == "flip" then
        db.enemyFirst = not db.enemyFirst
    elseif cmd == "reverse" then
        db.reverse = not db.reverse
    elseif cmd == "layout" or cmd == "rows" or cmd == "sort" then
        if not SetChoice(cmd, arg) then return end
    elseif cmd == "order" then
        local bound = AllBoundKeys()
        local picked, seen, unknown = {}, {}, {}
        for token in arg:gmatch("%S+") do
            local key = ResolveKeyToken(token, bound)
            if key and not seen[key] then
                seen[key] = true
                picked[#picked + 1] = key
            elseif not key then
                unknown[#unknown + 1] = token
            end
        end
        if #unknown > 0 then Print("not a bound key: " .. tconcat(unknown, ", ")) end
        if #picked == 0 then
            local names = {}
            for i, key in ipairs(bound) do names[i] = ShortKey(key) end
            Print("name the keys in the order you want. Bound now: " .. tconcat(names, " "))
            return
        end
        for _, key in ipairs(bound) do
            if not seen[key] then picked[#picked + 1] = key end
        end
        db.customOrder = picked
        db.sort = "custom"
        RebuildSettingsPages()
    elseif cmd == "tooltip" then
        db.tooltip = not db.tooltip
        Print("tooltip bindings " .. (db.tooltip and "on." or "off."))
    elseif cmd == "list" then
        Refresh(true); ListBindings(); return
    elseif cmd == "menu" then
        ToggleWindow()
        return
    elseif cmd == "config" or cmd == "options" then
        -- EllesmereUI's panel when it is there (it does not open in combat),
        -- the addon's own window otherwise.
        if not OpenSettings() then ToggleWindow(true) end
        return
    elseif cmd == "reset" then
        ResetSettings(); Print("reset."); return
    elseif cmd == "help" or cmd == "?" then
        Help(); return
    elseif cmd == "" then
        ToggleWindow(); return
    else
        Help(); return
    end
    SanitizeDB()
    Refresh(true)
    RefreshWindow()
end

SLASH_CLICKLEGEND1 = "/clg"
SLASH_CLICKLEGEND2 = "/clicklegend"
SlashCmdList["CLICKLEGEND"] = function(msg)
    if db then Safe(HandleSlash, msg) end
end

-------------------------------------------------------------------------------
--  Events
-------------------------------------------------------------------------------
local events = CreateFrame("Frame")
for _, event in ipairs({
    "ADDON_LOADED", "PLAYER_LOGIN", "PLAYER_ENTERING_WORLD", "MODIFIER_STATE_CHANGED",
    "GROUP_ROSTER_UPDATE", "PLAYER_EQUIPMENT_CHANGED", "SPELLS_CHANGED", "UPDATE_MACROS",
    "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED",      -- combat state, for the "Visible" setting
}) do
    pcall(events.RegisterEvent, events, event)      -- an event a client lacks must not stop the rest
end

-- Neither source has a "bindings changed" callback, so poll once a second.
-- Bindings cannot change in combat, so skip then.
local function Poll()
    if not (InCombatLockdown and InCombatLockdown()) then Safe(Refresh, false) end
end

local function StartPolling()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(1, Poll)
        return
    end
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= 1 then elapsed = 0; Poll() end
    end)
end

events:SetScript("OnEvent", function(_, event, arg1)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            Safe(InitDB)
            if db then
                Safe(HookTooltip)
                Safe(RegisterSettingsPage)
                Safe(RegisterGameOptions)
            end
        end
        return
    end
    if not db then return end
    if event == "PLAYER_LOGIN" then
        Safe(ApplyPosition)
        Safe(Refresh, true)
        StartPolling()
        if not db.locked then
            Print("drag the legend where you want it, then type /clg lock. /clg for settings.")
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        Render()
        RefreshUnitTooltip()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        Render()
    elseif event == "GROUP_ROSTER_UPDATE" then
        Safe(Refresh, false)
        Render()
    else
        Safe(Refresh, false)
    end
end)
