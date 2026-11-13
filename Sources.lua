-------------------------------------------------------------------------------
--  ClickLegend - Sources.lua
--  Reads the click-cast bindings from each supported system into one
--  shape:  layers[mods] = { keys = {...}, byKey = { [key] = { ally, enemy } } }
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, tonumber, pcall = ipairs, pairs, type, tostring, tonumber, pcall
local tsort, tconcat = table.sort, table.concat

local db
ns.Subscribe("db", function(value) db = value end)

local OrderKeysBy, ParseKey, Report =
    ns.OrderKeysBy, ns.ParseKey, ns.Report

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

-- spellID lets the icon tooltip show the spell; missing marks a binding that
-- cannot fire (spell not learned, macro deleted).
local function Entry(name, icon, spellID, missing)
    return {
        name = (type(name) == "string" and name ~= "") and name or "Unknown",
        icon = ValidIcon(icon) or FALLBACK_ICON,
        spellID = type(spellID) == "number" and spellID or nil,
        missing = missing and true or false,
    }
end

-- Is the spell in the player's spellbook? true, false, or nil when the client
-- offers no way to ask. Several calls are tried because they differ between
-- clients; any one saying yes is enough.
local function SpellKnown(id)
    if type(id) ~= "number" then return nil end
    local asked = false
    local function Try(fn)
        if type(fn) ~= "function" then return false end
        asked = true
        local ok, known = pcall(fn, id)
        return ok and not (issecretvalue and issecretvalue(known)) and known and true or false
    end
    if C_SpellBook and (Try(C_SpellBook.IsSpellKnown) or Try(C_SpellBook.IsSpellInSpellBook)) then return true end
    if Try(IsPlayerSpell) or Try(IsSpellKnownOrOverridesKnown) or Try(IsSpellKnown) then return true end
    if asked then return false end
    return nil
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
                ValidIcon(b.harmfulIcon) or SpellTexture(b.harmfulSpellID) or SpellTexture(b.harmfulSpell),
                b.harmfulSpellID, SpellKnown(b.harmfulSpellID) == false)
        end
        return Entry(b.spell or "Unknown Spell",
            ValidIcon(b.icon) or SpellTexture(b.spellID) or SpellTexture(b.spell),
            b.spellID, SpellKnown(b.spellID) == false)
    elseif t == "macro" then
        local name, tex = MacroInfo(b.macroName)
        local gone = type(b.macroName) == "string" and GetMacroInfo ~= nil and name == nil
        return Entry(b.macroName or "Macro", ValidIcon(b.icon) or tex or TYPE_ICON.macro, nil, gone)
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
                entry = Entry(SpellName(id), SpellTexture(id), id, SpellKnown(id) == false)
                ally, enemy = SpellSides(id)
            elseif info.type == tMacro then
                local name, tex = MacroInfo(id)
                entry = Entry(name or "Macro", tex or TYPE_ICON.macro, nil, GetMacroInfo ~= nil and name == nil)
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
--  Sources 3 to 5: other click-cast addons. Each is read the way it stores
--  its bindings; none of them is changed, and none is required.
-------------------------------------------------------------------------------
-- A spell given by id or by name -> its id, or nil when the game does not
-- know it (by name, that means it is not in the spellbook).
local function SpellIDFor(spell)
    if type(spell) == "number" then return spell end
    if type(spell) ~= "string" or spell == "" then return nil end
    if C_Spell and C_Spell.GetSpellInfo then
        local ok, info = pcall(C_Spell.GetSpellInfo, spell)
        if ok and type(info) == "table" and type(info.spellID) == "number" then return info.spellID end
    end
    if GetSpellInfo then
        local ok, _, _, _, _, _, _, id = pcall(GetSpellInfo, spell)
        if ok and type(id) == "number" then return id end
    end
    return nil
end

-- An entry for something named by text, as VuhDo, Clique and HealBot do: a
-- spell if the game knows one by that name, else a macro of that name, else
-- just the text (an item, or a spell this character does not have).
local function NamedEntry(text)
    local id = SpellIDFor(text)
    if id then return Entry(text, SpellTexture(id) or SpellTexture(text), id, SpellKnown(id) == false) end
    local macroName, macroIcon = MacroInfo(text)
    if macroName then return Entry(text, macroIcon or TYPE_ICON.macro) end
    return Entry(text, SpellTexture(text))
end

local function CurrentSpecIndex()
    local S = C_SpecializationInfo
    if not (S and S.GetSpecialization) then return nil end
    local ok, index = pcall(S.GetSpecialization)
    if ok and type(index) == "number" and index > 0 then return index end
    return nil
end

--  Clique -------------------------------------------------------------------
--  Clique.db.profile.bindings is a list of
--    { key = "SHIFT-BUTTON1", type = "spell" | "macro" | "target" | "menu",
--      spell = name or id, sets = { default, ooc, friend, enemy, hovercast, ... } }
--  A binding in the "friend" set only fires on friendly units, one in "enemy"
--  only on hostile ones; in neither (or both), the spell decides.
local function CollectCliqueLayers()
    local C = Clique
    if type(C) ~= "table" then return nil end
    local list = type(C.db) == "table" and type(C.db.profile) == "table" and C.db.profile.bindings
    if type(list) ~= "table" then list = C.bindings end
    if type(list) ~= "table" then return nil end
    local specIndex = CurrentSpecIndex()
    local layers = {}
    for _, b in pairs(list) do
        if type(b) == "table" and type(b.key) == "string" and b.key ~= ""
            and type(b.sets) == "table" and next(b.sets) ~= nil then
            -- A binding limited to talent specs only counts in one of them.
            local specOnly, specMatch = false, false
            for set in pairs(b.sets) do
                local n = type(set) == "string" and set:match("^spec(%d+)$")
                if n then
                    specOnly = true
                    if tonumber(n) == specIndex then specMatch = true end
                end
            end
            if not specOnly or specMatch or not specIndex then
                local mods, key = ParseKey(b.key)
                local entry
                local ally, enemy = true, true
                if b.type == "target" then
                    entry = Entry(TYPE_NAME.target, TYPE_ICON.target)
                elseif b.type == "menu" then
                    entry = Entry(TYPE_NAME.menu, TYPE_ICON.menu)
                elseif b.type == "macro" then
                    local label = type(b.macro) == "string" and b.macro or (type(b.name) == "string" and b.name) or "Macro"
                    entry = Entry(label, ValidIcon(b.icon) or TYPE_ICON.macro)
                elseif b.spell ~= nil then
                    local id = SpellIDFor(b.spell)
                    local name = type(b.spell) == "string" and b.spell or (id and SpellName(id)) or "Unknown Spell"
                    entry = Entry(name, ValidIcon(b.icon) or SpellTexture(id) or SpellTexture(b.spell),
                        id, id ~= nil and SpellKnown(id) == false)
                    if id then ally, enemy = SpellSides(id) end
                end
                if b.sets.friend and not b.sets.enemy then
                    ally, enemy = true, false
                elseif b.sets.enemy and not b.sets.friend then
                    ally, enemy = false, true
                end
                if entry and key ~= "" then
                    if ally then PutEntry(layers, mods, key, "ally", entry) end
                    if enemy then PutEntry(layers, mods, key, "enemy", entry) end
                end
            end
        end
    end
    return layers
end

--  VuhDo --------------------------------------------------------------------
--  VUHDO_SPELL_ASSIGNMENTS["alt1"] = { "ALT-", "1", "Rejuvenation" }: modifier
--  prefix, mouse button number, then a spell, macro or item name, or one of
--  VuhDo's own actions. VUHDO_HOSTILE_SPELL_ASSIGNMENTS is the same for hostile
--  units. The wheel lives in VUHDO_SPELLS_KEYBOARD.WHEEL / .HOSTILE_WHEEL,
--  index 1 for wheel up and 2 for wheel down.
local VUHDO_ACTIONS = {
    target = { TYPE_NAME.target, TYPE_ICON.target }, dropdown = { TYPE_NAME.menu, TYPE_ICON.menu },
    focus = { "Set Focus" }, assist = { "Assist" }, menu = { "VuhDo Menu" }, tell = { "Whisper" },
    mouselook = { "Mouse Look" }, ping = { "Ping" }, extraactionbutton = { "Extra Action Button" },
}

local function VuhDoEntry(action)
    if type(action) ~= "string" then return nil end
    action = action:match("^%s*(.-)%s*$")
    if action == "" then return nil end
    local special = VUHDO_ACTIONS[action:lower()]
    if special then return Entry(special[1], special[2]) end
    return NamedEntry(action)
end

local function CollectVuhDoLayers()
    if type(VUHDO_SPELL_ASSIGNMENTS) ~= "table" then return nil end
    local layers = {}
    local function Add(list, side, wheel)
        if type(list) ~= "table" then return end
        for index, t in pairs(list) do
            if type(t) == "table" and type(t[1]) == "string" then
                local entry = VuhDoEntry(t[3])
                local key
                if wheel then
                    local n = tostring(index):match("(%d)$")
                    key = (n == "1" and "MOUSEWHEELUP") or (n == "2" and "MOUSEWHEELDOWN") or nil
                else
                    local n = tonumber(t[2])
                    key = n and n >= 1 and ("BUTTON" .. n) or nil
                end
                if entry and key then
                    local mods = ParseKey(t[1] .. "X")
                    PutEntry(layers, mods, key, side, entry)
                end
            end
        end
    end
    Add(VUHDO_SPELL_ASSIGNMENTS, "ally")
    Add(VUHDO_HOSTILE_SPELL_ASSIGNMENTS, "enemy")
    if type(VUHDO_SPELLS_KEYBOARD) == "table" then
        Add(VUHDO_SPELLS_KEYBOARD.WHEEL, "ally", true)
        Add(VUHDO_SPELLS_KEYBOARD.HOSTILE_WHEEL, "enemy", true)
    end
    return layers
end

--  HealBot ------------------------------------------------------------------
--  HealBot_Config_Spells.EnabledKeyCombo["ShiftLeft1"] = "S:774^Rejuvenation":
--  the key is modifier + button + talent spec number, the value a spell id and
--  name ("S:", the name missing in older saves), an item id ("I:"), a HealBot
--  command ("C:"), an emote ("E:") or plain text.
--  EnemyKeyCombo is the same for hostile units.
local HEALBOT_MODS = {
    { "Alt-Ctrl-Shift", "ALT-CTRL-SHIFT-" }, { "Alt-Shift", "ALT-SHIFT-" }, { "Ctrl-Shift", "CTRL-SHIFT-" },
    { "Alt-Ctrl", "ALT-CTRL-" }, { "Shift", "SHIFT-" }, { "Ctrl", "CTRL-" }, { "Alt", "ALT-" },
}
local HEALBOT_BUTTONS = { Left = "BUTTON1", Right = "BUTTON2", Middle = "BUTTON3" }
local HEALBOT_COMMANDS = {
    ally = {
        A = { TYPE_NAME.target, TYPE_ICON.target }, B = { "Assist" }, C = { "Set Focus" },
        D = { TYPE_NAME.menu, TYPE_ICON.menu }, E = { "HealBot Menu" }, F = { "Stop Casting" },
    },
    enemy = { A = { TYPE_NAME.target, TYPE_ICON.target }, B = { "Set Focus" } },
}

-- "Alt-CtrlButton41" -> "ALT-CTRL-", "BUTTON4", spec 1. nil when the key is
-- not in that shape.
local function ParseHealBotKey(combo)
    if type(combo) ~= "string" then return nil end
    local mods, rest = "", combo
    for _, m in ipairs(HEALBOT_MODS) do
        if combo:sub(1, #m[1]) == m[1] then mods, rest = m[2], combo:sub(#m[1] + 1); break end
    end
    local name, digits = rest:match("^(%a+)(%d+)")
    if not name then return nil end
    local fixed = HEALBOT_BUTTONS[name]
    if fixed then return mods, fixed, tonumber(digits:sub(1, 1)) end
    if name ~= "Button" then return nil end
    -- "Button" is followed by the button number (4 to 20) and then the spec.
    for len = 2, 1, -1 do
        local n, spec = tonumber(digits:sub(1, len)), tonumber(digits:sub(len + 1, len + 1))
        if n and spec and n >= 4 and n <= 20 then return mods, "BUTTON" .. n, spec end
    end
    return nil
end

local function HealBotEntry(value, side)
    if type(value) ~= "string" or value == "" then return nil end
    local kind, rest = value:match("^(%u):(.+)$")
    if kind == "S" then
        local idText, name = rest:match("^(%d+)%^?(.*)$")
        local id = tonumber(idText)
        if not id then return nil end
        return Entry(name ~= "" and name or SpellName(id), SpellTexture(id), id, SpellKnown(id) == false)
    elseif kind == "C" then
        local command = HEALBOT_COMMANDS[side][rest]
        return command and Entry(command[1], command[2]) or nil
    elseif kind == "I" then
        local id, name, icon = tonumber(rest), nil, nil
        if id and C_Item then
            if C_Item.GetItemNameByID then
                local ok, n = pcall(C_Item.GetItemNameByID, id)
                name = ok and type(n) == "string" and n or nil
            end
            if C_Item.GetItemIconByID then
                local ok, tex = pcall(C_Item.GetItemIconByID, id)
                icon = ok and ValidIcon(tex) or nil
            end
        end
        return Entry(name or "Item", icon)
    elseif kind == "E" then
        return Entry("Emote: " .. rest)
    end
    return NamedEntry(value)
end

local function CollectHealBotLayers()
    local spells = HealBot_Config_Spells
    if type(spells) ~= "table" or type(spells.EnabledKeyCombo) ~= "table" then return nil end
    local spec = type(HealBot_Config) == "table" and tonumber(HealBot_Config.CurrentSpec) or 1
    local layers = {}
    local function Add(list, side)
        if type(list) ~= "table" then return end
        for combo, value in pairs(list) do
            local mods, key, keySpec = ParseHealBotKey(combo)
            if mods and keySpec == spec then
                local entry = HealBotEntry(value, side)
                if entry then PutEntry(layers, mods, key, side, entry) end
            end
        end
    end
    Add(spells.EnabledKeyCombo, "ally")
    Add(spells.EnemyKeyCombo, "enemy")
    return layers
end

-------------------------------------------------------------------------------
--  Current bindings
-------------------------------------------------------------------------------

-- In the order "Automatic" tries them: ClickLegend's own bindings when they are
-- switched on, then an addon the player installed for click casting, then the
-- game's own, which most profiles have
-- something in even when it is not what they use.
local function CollectOwnLayers() return ns.CollectOwnLayers() end      -- Cast.lua

local SOURCES = {
    { id = "own", name = "ClickLegend", collect = CollectOwnLayers },
    { id = "eui", name = "EllesmereUI HoverCast", collect = CollectEUILayers },
    { id = "clique", name = "Clique", collect = CollectCliqueLayers },
    { id = "vuhdo", name = "VuhDo", collect = CollectVuhDoLayers },
    { id = "healbot", name = "HealBot", collect = CollectHealBotLayers },
    { id = "blizzard", name = "Click Casting", collect = CollectBlizzardLayers },
}

-- Which system the legend is showing ("Clique", "VuhDo", ...), or nil.
local activeSource

local function SetSource(name)
    activeSource = name
    ns.Publish("source", name)
end

local function CollectLayers()
    for _, source in ipairs(SOURCES) do
        if db.source == "auto" or db.source == source.id then
            local ok, layers = pcall(source.collect)
            if not ok then Report(layers); layers = nil end
            if layers and next(layers) then SetSource(source.name); return layers end
        end
    end
    SetSource(nil)
    return nil
end

local function SortedMods(layers)
    local list = {}
    for mods in pairs(layers) do list[#list + 1] = mods end
    tsort(list)
    return list
end

local function EntrySignature(entry)
    if not entry then return "" end
    return tostring(entry.icon) .. entry.name .. (entry.missing and "!" or "") .. (entry.rank or "")
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
            parts[#parts + 1] = mods .. key .. "<" .. EntrySignature(slot.ally) .. ">" .. EntrySignature(slot.enemy)
        end
    end
    local keys = {}
    for key in pairs(keySet) do keys[#keys + 1] = key end
    tsort(keys)
    return tconcat(parts, "|"), tconcat(keys, "|")
end

-- The layers on screen; Display.lua owns them and publishes each change.
local layers
ns.Subscribe("layers", function(value) layers = value end)

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
--  Used by the other files
-------------------------------------------------------------------------------
ns.AllBoundKeys     = AllBoundKeys
ns.CollectBlizzardLayers = CollectBlizzardLayers
ns.CollectLayers    = CollectLayers
ns.CurrentSpecID    = CurrentSpecID
ns.Entry            = Entry
ns.InventoryTexture = InventoryTexture
ns.MacroInfo        = MacroInfo
ns.PutEntry         = PutEntry
ns.Signatures       = Signatures
ns.SortedMods       = SortedMods
ns.SpellIDFor       = SpellIDFor
ns.SpellKnown       = SpellKnown
ns.SpellName        = SpellName
ns.SpellTexture     = SpellTexture
ns.TYPE_ICON        = TYPE_ICON
ns.TYPE_NAME        = TYPE_NAME
ns.ValidIcon        = ValidIcon
