-------------------------------------------------------------------------------
--  ClickLegend - Cast.lua
--  ClickLegend's own click-cast bindings, as data: the saved sets, their
--  clean-up, the rules of a binding turned into macro text, and the reader
--  that shows them in the legend.
--
--  Nothing in this file touches a unit frame or a secure attribute. Putting
--  the bindings on frames is Provider.lua's job.
--
--  Sets are shared by every character, in a saved table of their own so the
--  settings table stays settings only:
--  ClickLegendCastDB.sets[name] = { version = 1, bindings = { binding, ... } }
--  binding = { key = "SHIFT-BUTTON1", rules = { rule, ... }, hover = true or nil,
--              pre = { stop = true, trinket1 = true, trinket2 = true } or nil }
--            hover: the key works on any unit under the cursor, not only on
--            unit frames (never plain left or right click)
--            pre: done just before one of the key's spells is cast
--  rule    = { when = { reaction, dead, combat, form, pet, mod, unit }, action = action }
--            unit: who the rule acts on instead of the unit under the cursor
--            ("player", "target", "focus", "targettarget", "pet")
--  action  = { type = "spell", name, spellID, pinned }   pinned: cast this rank
--          | { type = "item", name, itemID }
--          | { type = "macro", name }
--          | { type = "text", text }       macro text written in the editor
--          | { type = "target" | "focus" | "assist" | "menu" | "trinket1" | "trinket2" }
--          | { type = "dispel" | "rez" }   presets: whichever spell of that kind
--                                          the character has (see Preset actions)
--  The first rule whose conditions hold is the one that fires.
--
--  ClickLegendCharDB.cast = { enabled, set = name, specSet = { [specID] = name },
--                             frames = { blizzard, registered }, down = false }
--            down: mouse clicks on unit frames act when the button goes down
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, tonumber, pcall = ipairs, pairs, type, tostring, tonumber, pcall
local tsort, tconcat = table.sort, table.concat
local floor = math.floor

local ParseKey, Print, LongKey, ModsLong =
    ns.ParseKey, ns.Print, ns.LongKey, ns.ModsLong
local CurrentSpecID, Entry, InventoryTexture, MacroInfo =
    ns.CurrentSpecID, ns.Entry, ns.InventoryTexture, ns.MacroInfo
local PutEntry, SpellIDFor, SpellKnown, SpellName =
    ns.PutEntry, ns.SpellIDFor, ns.SpellKnown, ns.SpellName
local SpellTexture, TYPE_ICON, TYPE_NAME, ValidIcon =
    ns.SpellTexture, ns.TYPE_ICON, ns.TYPE_NAME, ns.ValidIcon
local CollectBlizzardLayers, Report, Safe =
    ns.CollectBlizzardLayers, ns.Report, ns.Safe
local OtherSources, SortedMods = ns.OtherSources, ns.SortedMods

local SET_VERSION = 1
local MACRO_LIMIT = 255             -- the longest macro text the game runs
local NAME_LIMIT = 40               -- longest set name
local PROXY_LENGTH = 24             -- room kept for a helper button's name

local ACTION_TYPES = {
    spell = true, item = true, macro = true, target = true, focus = true,
    assist = true, menu = true, trinket1 = true, trinket2 = true,
    dispel = true, rez = true, text = true,
}
local ACTION_NAME = {
    target = TYPE_NAME.target, menu = TYPE_NAME.menu, focus = "Set Focus", assist = "Assist",
    trinket1 = TYPE_NAME.trinket1, trinket2 = TYPE_NAME.trinket2,
    dispel = "Dispel", rez = "Resurrect", text = "Macro text",
}
local PRE_ORDER = { "stop", "trinket1", "trinket2" }
local REACTIONS = { help = true, harm = true }
local RULE_MODS = { shift = true, ctrl = true, alt = true }
local RULE_UNITS = { player = true, target = true, focus = true, targettarget = true, pet = true }
local MAX_FORM = 10

-------------------------------------------------------------------------------
--  Clean-up. Saved data can be anything; what is kept is what the rest of
--  the file can rely on. Sets of a version this file does not know are left
--  exactly as they are and not used.
-------------------------------------------------------------------------------
local function Text(v, limit)
    if type(v) ~= "string" then return nil end
    v = v:match("^%s*(.-)%s*$")
    if v == "" then return nil end
    if limit and #v > limit then v = v:sub(1, limit) end
    return v
end

local function WholeNumber(v, lo, hi)
    if type(v) ~= "number" or v ~= v or v ~= floor(v) or v < lo or v > hi then return nil end
    return v
end

local function Flag(v)
    if v == true or v == false then return v end
    return nil
end

-- A spell or item name is written into a /cast line as it is. One with a
-- line break, ";" or a bracket in it would end that line and start something
-- else, so such a name (only ever seen in a set shared as text) is refused.
local function CastName(v)
    v = Text(v)
    if v and v:find("[%c;%[%]]") then return nil end
    return v
end

local function CleanAction(a)
    if type(a) ~= "table" or not ACTION_TYPES[a.type] then return nil end
    local t = a.type
    if t == "spell" then
        local name, id = CastName(a.name), WholeNumber(a.spellID, 1, 2 ^ 31)
        if Text(a.name) and not name then return nil end
        if not (name or id) then return nil end
        return { type = t, name = name, spellID = id, pinned = (id and a.pinned == true) or nil }
    elseif t == "item" then
        local name, id = CastName(a.name), WholeNumber(a.itemID, 1, 2 ^ 31)
        if Text(a.name) and not name then return nil end
        if not (name or id) then return nil end
        return { type = t, name = name, itemID = id }
    elseif t == "macro" then
        local name = Text(a.name)
        if not name then return nil end
        return { type = t, name = name }
    elseif t == "text" then
        local text = Text(a.text, MACRO_LIMIT)
        if not text then return nil end
        return { type = t, text = text }
    end
    return { type = t }
end

local function CleanWhen(w)
    local out = {}
    if type(w) ~= "table" then return out end
    if REACTIONS[w.reaction] then out.reaction = w.reaction end
    out.dead, out.combat, out.pet = Flag(w.dead), Flag(w.combat), Flag(w.pet)
    out.form = WholeNumber(w.form, 0, MAX_FORM)
    if RULE_MODS[w.mod] then out.mod = w.mod end
    if RULE_UNITS[w.unit] then out.unit = w.unit end
    return out
end

-- A resurrection only ever goes on a dead ally, so a Resurrect rule says so.
-- Macro text carries its own conditions, so a rule of it has none.
local function Normalise(rule)
    if rule.action.type == "rez" then rule.when.reaction, rule.when.dead = "help", true end
    if rule.action.type == "text" then rule.when = {} end
    return rule
end

-- Plain left and right click are what select and steer in the world, so
-- those two stay on unit frames.
local function HoverAllowed(keyStr)
    local mods, key = ParseKey(keyStr)
    return key ~= "" and not (mods == "" and (key == "BUTTON1" or key == "BUTTON2"))
end

local function CleanBinding(b)
    if type(b) ~= "table" or type(b.key) ~= "string" or type(b.rules) ~= "table" then return nil end
    local mods, key = ParseKey(b.key)
    if key == "" then return nil end
    local rules = {}
    for _, r in ipairs(b.rules) do
        local action = type(r) == "table" and CleanAction(r.action)
        if action then rules[#rules + 1] = Normalise({ when = CleanWhen(r.when), action = action }) end
    end
    if #rules == 0 then return nil end
    local pre
    if type(b.pre) == "table" then
        for _, what in ipairs(PRE_ORDER) do
            if b.pre[what] == true then pre = pre or {}; pre[what] = true end
        end
    end
    local hover = (b.hover == true and HoverAllowed(mods .. key)) or nil
    return { key = mods .. key, rules = rules, pre = pre, hover = hover,
             orTarget = (hover and b.orTarget == true) or nil }
end

local function CleanSet(set)
    local seen, bindings = {}, {}
    if type(set.bindings) == "table" then
        for _, b in ipairs(set.bindings) do
            local clean = CleanBinding(b)
            if clean and not seen[clean.key] then          -- first one wins the key
                seen[clean.key] = true
                bindings[#bindings + 1] = clean
            end
        end
    end
    set.bindings = bindings
end

local sets, cast                -- ClickLegendCastDB.sets, ClickLegendCharDB.cast

-- Clique writes its bindings to the same unit frames and keeps the frames
-- other addons register. With both on, some frames follow one and some the
-- other, so ClickLegend's click casting stays off while Clique is loaded.
-- Returns why it cannot be on, or nil.
local function Blocked()
    if type(Clique) == "table" then
        return "Clique is loaded and binds the same unit frames, so ClickLegend's click casting stays off. "
            .. "To use ClickLegend's, switch Clique off in the game's AddOns list and reload; "
            .. "New... can copy your Clique bindings into a set first."
    end
    return nil
end

local function SanitizeCast()
    for name, set in pairs(sets) do
        if type(name) ~= "string" or name == "" or #name > NAME_LIMIT or type(set) ~= "table" then
            sets[name] = nil
        elseif set.version == SET_VERSION then
            CleanSet(set)
        end
    end
    cast.enabled = cast.enabled == true
    cast.down = cast.down == true
    cast.set = Text(cast.set, NAME_LIMIT)
    local specSet = {}
    if type(cast.specSet) == "table" then
        for specID, name in pairs(cast.specSet) do
            if type(specID) == "number" and Text(name, NAME_LIMIT) then specSet[specID] = Text(name, NAME_LIMIT) end
        end
    end
    cast.specSet = specSet
    local frames = type(cast.frames) == "table" and cast.frames or {}
    cast.frames = { blizzard = frames.blizzard ~= false, registered = frames.registered ~= false }
end

local function InitCast()
    if type(ClickLegendCharDB) ~= "table" then return end           -- InitDB did not run
    if type(ClickLegendCastDB) ~= "table" then ClickLegendCastDB = {} end
    if type(ClickLegendCastDB.sets) ~= "table" then ClickLegendCastDB.sets = {} end
    if type(ClickLegendCharDB.cast) ~= "table" then ClickLegendCharDB.cast = {} end
    sets, cast = ClickLegendCastDB.sets, ClickLegendCharDB.cast
    SanitizeCast()
    if cast.enabled and Blocked() then cast.enabled, cast.heldBack = false, true end   -- said at login
    -- The extra mouse buttons this player has (4 and up), shown to the guided
    -- setup by clicking them. Shared by every character: it is one mouse.
    local buttons, seen = {}, {}
    if type(ClickLegendCastDB.buttons) == "table" then
        for _, n in ipairs(ClickLegendCastDB.buttons) do
            if WholeNumber(n, 4, 31) and not seen[n] then
                seen[n] = true
                buttons[#buttons + 1] = n
            end
        end
    end
    tsort(buttons)
    ClickLegendCastDB.buttons = buttons
    -- What each button of a block of side buttons sends, learned by pressing
    -- them in the guided setup: [1 to 12] = a key with no modifier.
    local sideKeys, used = {}, {}
    if type(ClickLegendCastDB.sideKeys) == "table" then
        for n, key in pairs(ClickLegendCastDB.sideKeys) do
            local mods, name = "", ""
            if type(key) == "string" then mods, name = ParseKey(key) end
            if WholeNumber(n, 1, 12) and mods == "" and name ~= "" and not used[name] then
                used[name] = true
                sideKeys[n] = name
            end
        end
    end
    ClickLegendCastDB.sideKeys = sideKeys
end

-- [n] = the key side button n sends. Empty when the player has not said.
local function SideKeys()
    return type(ClickLegendCastDB) == "table" and ClickLegendCastDB.sideKeys or {}
end

-- Notes what side button n sends (nil: forget it). Returns true, or false and
-- the number of the button that already sends that key.
local function SetSideKey(n, key)
    local keys = SideKeys()
    if not WholeNumber(n, 1, 12) then return false end
    if key ~= nil then
        local mods, name = "", ""
        if type(key) == "string" then mods, name = ParseKey(key) end
        if mods ~= "" or name == "" then return false end
        for other, has in pairs(keys) do
            if has == name and other ~= n then return false, other end
        end
        key = name
    end
    keys[n] = key
    ns.Refresh(true)                -- Display.lua: the mouse picture follows
    return true
end

local function ClearSideKeys()
    if type(ClickLegendCastDB) == "table" then ClickLegendCastDB.sideKeys = {} end
    ns.Refresh(true)
end

local function KnownButtons()
    return type(ClickLegendCastDB) == "table" and ClickLegendCastDB.buttons or {}
end

-- Returns true when the button was not in the list yet.
local function AddKnownButton(n)
    local buttons = KnownButtons()
    if not WholeNumber(n, 4, 31) then return false end
    for _, known in ipairs(buttons) do
        if known == n then return false end
    end
    buttons[#buttons + 1] = n
    tsort(buttons)
    return true
end

-------------------------------------------------------------------------------
--  Sets
-------------------------------------------------------------------------------
local function SetNames()
    local names = {}
    if sets then
        for name in pairs(sets) do names[#names + 1] = name end
    end
    tsort(names)
    return names
end

-- The name of the set this character uses now: the one picked for the
-- current spec when there is one, else the character's set.
local function ActiveSetName()
    if not cast then return nil end
    local specID = CurrentSpecID()
    local own = specID and cast.specSet[specID]
    if own and sets[own] then return own end
    return cast.set
end

-- The current spec: its id, its name, and whether it has a set of its own.
-- Nil for a character with no spec.
local function SpecState()
    local specID = cast and CurrentSpecID()
    if not specID then return nil end
    local name
    local S = C_SpecializationInfo
    local ok, index = pcall(S.GetSpecialization)
    if ok and index then
        local ok2, _, specName = pcall(S.GetSpecializationInfo, index)
        if ok2 and type(specName) == "string" and specName ~= "" then name = specName end
    end
    local own = cast.specSet[specID]
    return specID, name or ("Spec " .. specID), (own and sets[own]) and true or false
end

-- Makes `name` the set in use: for the current spec when that spec has a set
-- of its own, else for the character.
local pickScope = nil               -- { old, new }: the character's set was just changed from one to the other
local function UseSet(name)
    local specID, _, own = SpecState()
    if specID and own then
        cast.specSet[specID] = name
    else
        local old = cast.set
        cast.set = name
        -- Every spec without a set of its own now uses the new one. The
        -- editor says so and offers to keep it to this spec (PickScope).
        pickScope = (specID and old and old ~= name and sets and sets[old]) and { old = old, new = name } or nil
    end
end

-- After the character's set was changed: the spec's name and the new set,
-- while "this spec only" can still be chosen for it; else nil.
local function PickScope()
    local specID, specName, own = SpecState()
    if not (pickScope and specID and not own and cast.set == pickScope.new and sets and sets[pickScope.old]) then return nil end
    return specName, pickScope.new
end


-- The set in use, or nil (none picked, deleted, or of an unknown version).
local function ActiveSet()
    local name = ActiveSetName()
    local set = name and sets[name]
    if type(set) ~= "table" or set.version ~= SET_VERSION then return nil end
    return set, name
end

local function NewSet(name)
    name = Text(name, NAME_LIMIT)
    if not (sets and name) or sets[name] then return false end
    sets[name] = { version = SET_VERSION, bindings = {} }
    return true, name
end

local function CopyTable(t)
    local out = {}
    for k, v in pairs(t) do out[k] = type(v) == "table" and CopyTable(v) or v end
    return out
end

local function CopySet(from, to)
    to = Text(to, NAME_LIMIT)
    local source = sets and sets[from]
    if not (source and to) or sets[to] or source.version ~= SET_VERSION then return false end
    sets[to] = CopyTable(source)
    return true, to
end

local function DeleteSet(name)
    if not (sets and sets[name]) then return false end
    sets[name] = nil
    for specID, own in pairs(cast.specSet) do              -- a spec that used it goes back to the character's set
        if own == name then cast.specSet[specID] = nil end
    end
    return true
end

-- Gives a set another name. This character follows it; another character that
-- used the old name has to pick the set again (its choice is saved with it).
local function RenameSet(from, to)
    to = Text(to, NAME_LIMIT)
    if not (sets and sets[from] and to) or sets[to] then return false end
    sets[to], sets[from] = sets[from], nil
    if cast.set == from then cast.set = to end
    for specID, name in pairs(cast.specSet) do
        if name == from then cast.specSet[specID] = to end
    end
    return true, to
end

-- "Name", or "Name 2", "Name 3"... when that is taken.
local function FreeName(name)
    name = Text(name, NAME_LIMIT - 4) or "Set"
    if not sets[name] then return name end
    local n = 2
    while sets[name .. " " .. n] do n = n + 1 end
    return name .. " " .. n
end

-- A new set from a table in the saved shape (a template, an import). It is
-- cleaned like a saved one. Returns the name it was given, or false.
local function AddSet(name, set)
    if not (sets and type(set) == "table") then return false end
    local clean = { version = SET_VERSION, bindings = set.bindings }
    CleanSet(clean)
    if #clean.bindings == 0 then return false end
    name = FreeName(name)
    sets[name] = clean
    return name
end

-------------------------------------------------------------------------------
--  A set as text, to share:  CLB1;name;key|rule|rule;key|rule...
--  A key may be followed by "+" and letters: h works anywhere, t else on the
--  target, s stop the current cast first, 1 and 2 use that trinket first.
--  rule = conditions~action, conditions = words joined by ",", action =
--  kind:name:id:p (p: that exact rank). Names are written with anything but
--  letters, digits, "_", "-" and "." as %XX, so they cannot break the format.
-------------------------------------------------------------------------------
local SHARE_TAG = "CLB1"

local function Escape(text)
    return (tostring(text):gsub("[^%w_%-%.]", function(ch) return ("%%%02X"):format(ch:byte()) end))
end
local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local WHEN_WORD = {
    reaction = { help = "help", harm = "harm" },
    dead = { [true] = "dead", [false] = "alive" },
    combat = { [true] = "combat", [false] = "nocombat" },
    pet = { [true] = "pet", [false] = "nopet" },
    mod = { shift = "shift", ctrl = "ctrl", alt = "alt" },
    unit = { player = "@player", target = "@target", focus = "@focus", targettarget = "@targettarget", pet = "@pet" },
}
local WORD_WHEN = {}
for field, words in pairs(WHEN_WORD) do
    for value, word in pairs(words) do WORD_WHEN[word] = { field, value } end
end

local function ExportSet(name)
    local set = sets and sets[name]
    if type(set) ~= "table" or set.version ~= SET_VERSION then return nil end
    local parts = { SHARE_TAG, Escape(name) }
    for _, binding in ipairs(set.bindings) do
        local pre = binding.pre or {}
        local marks = (binding.hover and "h" or "") .. (binding.orTarget and "t" or "") .. (pre.stop and "s" or "")
            .. (pre.trinket1 and "1" or "") .. (pre.trinket2 and "2" or "")
        local fields = { Escape(binding.key) .. (marks ~= "" and ("+" .. marks) or "") }
        for _, rule in ipairs(binding.rules) do
            local words = {}
            for _, field in ipairs({ "reaction", "dead", "combat", "pet", "mod", "unit" }) do
                local word = WHEN_WORD[field][rule.when[field]]
                if word then words[#words + 1] = word end
            end
            if rule.when.form then words[#words + 1] = "form" .. rule.when.form end
            local a = rule.action
            fields[#fields + 1] = tconcat(words, ",") .. "~" .. tconcat({
                a.type, Escape(a.name or a.text or ""), tostring(a.spellID or a.itemID or ""), a.pinned and "p" or "",
            }, ":")
        end
        parts[#parts + 1] = tconcat(fields, "|")
    end
    return tconcat(parts, ";")
end

-- Returns the new set's name, or false and why not. Nothing is changed unless
-- the text is a ClickLegend set with at least one usable key.
local function ImportSet(text)
    if type(text) ~= "string" then return false, "Nothing to import." end
    text = text:gsub("%s+", "")
    local parts = {}
    for part in text:gmatch("[^;]+") do parts[#parts + 1] = part end
    if parts[1] ~= SHARE_TAG or not parts[2] then return false, "That is not a ClickLegend binding set." end
    local bindings = {}
    for i = 3, #parts do
        local fields = {}
        for field in parts[i]:gmatch("[^|]+") do fields[#fields + 1] = field end
        local rules = {}
        for r = 2, #fields do
            local words, kind, name, id, pinned = fields[r]:match("^([^~]*)~([^:]*):([^:]*):([^:]*):([^:]*)$")
            if kind then
                local when = {}
                for word in words:gmatch("[^,]+") do
                    local pair, form = WORD_WHEN[word], word:match("^form(%d+)$")
                    if pair then when[pair[1]] = pair[2] elseif form then when.form = tonumber(form) end
                end
                local number = tonumber(id)
                rules[#rules + 1] = { when = when, action = {
                    type = kind, name = Unescape(name), pinned = pinned == "p",
                    text = kind == "text" and Unescape(name) or nil,
                    spellID = kind == "spell" and number or nil, itemID = kind == "item" and number or nil,
                } }
            end
        end
        if fields[1] then
            local keyText, marks = fields[1]:match("^([^+]*)%+?(.*)$")
            bindings[#bindings + 1] = {
                key = Unescape(keyText), rules = rules, hover = marks:find("h", 1, true) ~= nil,
                orTarget = marks:find("t", 1, true) ~= nil,
                pre = { stop = marks:find("s", 1, true) ~= nil, trinket1 = marks:find("1", 1, true) ~= nil,
                        trinket2 = marks:find("2", 1, true) ~= nil },
            }
        end
    end
    local name = AddSet(Unescape(parts[2]), { bindings = bindings })
    if not name then return false, "No usable keys in that text." end
    return name
end

-------------------------------------------------------------------------------
--  Rules to macro text
-------------------------------------------------------------------------------
local function HasConditions(when)
    return next(when) ~= nil
end

-- A rule that fits whatever happens: no condition at all, or nothing but
-- "on myself" (there is always a player).
local function Always(when)
    for field, value in pairs(when) do
        if not (field == "unit" and value == "player") then return false end
    end
    return true
end

-- "[@mouseover,help,dead]": the unit under the cursor, and the rule's
-- conditions in a fixed order. "exists" is only spelled out when nothing else
-- already implies it; macro text is short of room.
-- With `onTarget` the clause is for the player's target instead (no unit
-- named, which is what a macro takes as the target): "[help,nodead]", "[]".
-- A rule that names its own unit (`when.unit`) is about that unit instead:
-- "[@focus,help]", "[@player]".
local function Clause(when, onTarget)
    local parts = {}
    if not onTarget then
        parts[1] = "@" .. (when.unit or "mouseover")
        if not when.reaction and when.dead == nil and when.unit ~= "player" then parts[#parts + 1] = "exists" end
    end
    if when.reaction then parts[#parts + 1] = when.reaction end
    if when.dead ~= nil then parts[#parts + 1] = when.dead and "dead" or "nodead" end
    if when.combat ~= nil then parts[#parts + 1] = when.combat and "combat" or "nocombat" end
    if when.form then parts[#parts + 1] = "form:" .. when.form end
    if when.pet ~= nil then parts[#parts + 1] = when.pet and "pet" or "nopet" end
    if when.mod then parts[#parts + 1] = "mod:" .. when.mod end
    return "[" .. tconcat(parts, ",") .. "]"
end

local function ActionSpellID(action)
    return action.spellID or SpellIDFor(action.name)
end

-- A rule the editor has added and the player has not filled in yet.
local NEEDS_NAME = { spell = true, item = true, macro = true, text = true }
local function Incomplete(action)
    return NEEDS_NAME[action.type] and not (action.name or action.spellID or action.itemID or action.text) or false
end

-------------------------------------------------------------------------------
--  Preset actions. "Dispel" and "Resurrect" stand for whichever spell of
--  that kind the character has, so one set works on any class and keeps
--  working as better spells are learned. Spells are named in English, like
--  the templates; a name the game does not know is passed over.
--    dispel  the first one known, in this order. One only: a dispel casts
--            even with nothing to remove, so a second could never fire.
--    rez     on a dead ally: the combat resurrection while in combat, else
--            the ordinary one. With only one of the two, that one.
-------------------------------------------------------------------------------
local PRESET_SPELLS = {
    dispel = { "Dispel Magic", "Cleanse", "Purify", "Remove Curse", "Abolish Disease", "Abolish Poison",
               "Cure Poison", "Cure Disease", "Remove Lesser Curse" },
    rez = { "Resurrection", "Redemption", "Ancestral Spirit", "Revive" },
    battlerez = { "Rebirth" },
}

local function FirstKnown(kind)
    for _, name in ipairs(PRESET_SPELLS[kind]) do
        local id = SpellIDFor(name)
        if id and SpellKnown(id) ~= false then return name end
    end
    return nil
end

-- The spell a preset stands for right now, or nil when the character has none.
local function PresetSpell(action)
    if action.type == "dispel" then return FirstKnown("dispel") end
    if action.type == "rez" then return FirstKnown("rez") or FirstKnown("battlerez") end
    return nil
end

-- A rule as the rules that are compiled: itself, or what its preset stands for.
local function Expand(rule, out)
    local kind = rule.action.type
    if kind == "dispel" then
        local name = FirstKnown("dispel")
        out[#out + 1] = name and { when = rule.when, action = { type = "spell", name = name } } or rule
    elseif kind == "rez" then
        local when = {}
        for k, v in pairs(rule.when) do when[k] = v end
        when.reaction, when.dead = "help", true
        local battle, normal = FirstKnown("battlerez"), FirstKnown("rez")
        local count = #out
        if battle and not normal then
            -- The combat resurrection is the only one this character has: it
            -- is cast whenever the rule fits, in combat or out of it.
            out[#out + 1] = { when = when, action = { type = "spell", name = battle } }
        elseif battle and when.combat ~= false then
            local fighting = {}
            for k, v in pairs(when) do fighting[k] = v end
            fighting.combat = true
            out[#out + 1] = { when = fighting, action = { type = "spell", name = battle } }
        end
        if normal and when.combat ~= true then
            out[#out + 1] = { when = when, action = { type = "spell", name = normal } }
        end
        if #out == count then out[#out + 1] = { when = when, action = rule.action } end
    else
        out[#out + 1] = rule
    end
end

local function Expanded(rules)
    local out = {}
    for _, rule in ipairs(rules) do Expand(rule, out) end
    return out
end

-- A spell this character does not have. Such a rule is skipped, so the next
-- rule on the key takes over: that is how "this spell, or else that one" works.
-- (Left in, the game would pick the rule and then cast nothing.) A spell saved
-- by name only is one the character has when the game can find it by that
-- name: a name lookup only ever finds spells in the spellbook.
local function Unavailable(action)
    if action.type == "dispel" or action.type == "rez" then return PresetSpell(action) == nil end
    if action.type ~= "spell" then return false end
    if action.spellID then return SpellKnown(action.spellID) == false end
    local canAsk = (C_Spell and C_Spell.GetSpellInfo) or GetSpellInfo
    if not canAsk then return false end
    local id = SpellIDFor(action.name)
    return id == nil or SpellKnown(id) == false
end

-- What /cast is given for an action it can carry, else nil.
local function CastToken(action)
    local t = action.type
    if t == "spell" and not action.pinned then
        return action.name or (action.spellID and SpellName(action.spellID))
    elseif t == "item" then
        return action.name or ("item:" .. action.itemID)
    elseif t == "trinket1" then
        return "13"
    elseif t == "trinket2" then
        return "14"
    end
    return nil
end

local COMMAND = { target = "/target", focus = "/focus", assist = "/assist" }
-- The wheel zooms the camera in the game. A wheel key that works anywhere is
-- therefore only held while a unit is under the cursor (Provider.lua), and
-- the game has the wheel the rest of the time. (Zooming from the key's own
-- macro text was tried first; the client runs no script from it.)
local ZOOM = { MOUSEWHEELUP = true, MOUSEWHEELDOWN = true }
local ActionEntry                  -- defined with the legend's reader, below

-- Turns a binding into what has to be put on a frame.
--   kind = "none"       nothing can fire (every rule skipped)
--        = "macro"      run the player's macro `macro`
--        = "macrotext"  run `text`. "{menu}" stands for the frame's menu
--                       helper and "{rank:ID}" for the helper that casts that
--                       exact spell rank; Provider.lua fills them in.
--   length, tooLong     size of the text once the helpers are named
--   onTarget            the key also casts on the target (see binding.orTarget)
--   zoom                a wheel key to be held only while a unit is under the cursor
--   skipped             rules left out because the spell is not known
--   problems            what the editor should tell the player
--   fix                 how to mend the first problem of order, in terms of
--                       the binding's own rules: { rule = index, before =
--                       index } or { rule = index, last = true }
local function CompileBinding(binding)
    local out = { kind = "none", skipped = 0, problems = {} }
    local live, from = {}, {}               -- from[i]: the saved rule live[i] came from
    local unfinished = false
    for index, saved in ipairs(binding.rules) do
        for _, rule in ipairs(Expanded({ saved })) do
            if Incomplete(rule.action) then
                unfinished = true
            elseif Unavailable(rule.action) then
                out.skipped = out.skipped + 1
            else
                live[#live + 1] = rule
                from[#live] = index
            end
        end
    end
    if unfinished then out.problems[#out.problems + 1] = "A rule has nothing chosen yet." end
    if #live == 0 then return out end

    -- A rule with no condition takes every unit under the cursor, so a later
    -- rule about that unit can never fire and is left out. A later rule about
    -- a unit of its own still can, on a key that works anywhere: with nothing
    -- under the cursor the first one does not fit. (On a unit frame something
    -- always is under the cursor; that case is caught in the loop below.)
    if binding.hover then
        local kept, keptFrom, taker, lost = {}, {}, nil, 0
        for i, rule in ipairs(live) do
            if taker and not rule.when.unit then
                lost = lost + 1
                out.fix = out.fix or { rule = from[i], before = taker }
            else
                kept[#kept + 1], keptFrom[#kept + 1] = rule, from[i]
                if not taker and not HasConditions(rule.when) then taker = from[i] end
            end
        end
        if lost > 0 then
            out.problems[#out.problems + 1] = lost .. " rule(s) after an unconditional rule can never fire."
            live, from = kept, keptFrom
        end
    end

    if live[1].action.type == "macro" and not HasConditions(live[1].when) then
        if #live > 1 then out.problems[#out.problems + 1] = "Rules after an unconditional macro can never fire." end
        out.kind, out.macro = "macro", live[1].action.name
        return out
    end

    -- Consecutive spells and items share one /cast line, which picks the first
    -- clause that holds. Anything else gets a line of its own, after a
    -- /stopmacro naming every earlier clause, so one rule fires at most.
    -- A line with an item or trinket on it is written as /use.
    local lines, earlier, castParts, castVerb = {}, {}, nil, nil
    local function CloseCast()
        if castParts then lines[#lines + 1] = castVerb .. " " .. tconcat(castParts, "; "); castParts = nil end
    end
    local ownLines = false
    local function OwnLine(text)
        ownLines = true
        CloseCast()
        if #earlier > 0 then lines[#lines + 1] = "/stopmacro " .. tconcat(earlier) end
        lines[#lines + 1] = text
    end
    -- A rule whose conditions include every condition of an earlier rule can
    -- never fire: whenever it fits, the earlier one fits too and wins. (The
    -- very same conditions are the usual shape of "this spell, or else that
    -- one" and are left out quietly, below.)
    local function Covers(earlierWhen, when)
        if earlierWhen.unit ~= when.unit then return false end      -- about different units
        local same = true
        for field, value in pairs(earlierWhen) do
            if when[field] ~= value then return false end
        end
        for field in pairs(when) do
            if earlierWhen[field] == nil then same = false end
        end
        return not same
    end
    local seen, castClauses = {}, {}          -- castClauses: when a spell of this key is cast
    local elseParts, elseClauses = {}, {}     -- the same again for the player's target
    for i, rule in ipairs(live) do
        local action, clause = rule.action, Clause(rule.when)
        local token = CastToken(action)
        for j = 1, i - 1 do
            if Covers(live[j].when, rule.when) then
                out.problems[#out.problems + 1] = ActionEntry(action).name .. " can never fire here: "
                    .. ActionEntry(live[j].action).name .. " above it fits every time it would. Move it up, or give the one above another condition."
                if from[i] ~= from[j] then out.fix = out.fix or { rule = from[i], before = from[j] } end
                break
            end
        end
        if seen[clause] then
            -- The same conditions as an earlier rule: that one always wins. This is
            -- the usual shape of a fallback whose first choice is known, so it is
            -- left out quietly; it would only use up room.
            token = nil
        elseif token then
            if not castParts then
                if #earlier > 0 and #lines > 0 then lines[#lines + 1] = "/stopmacro " .. tconcat(earlier) end
                castParts, castVerb = {}, "/cast"
            end
            -- A rule with a unit of its own has nothing to add for the target:
            -- it never was about the unit under the cursor.
            local onTarget = not rule.when.unit and Clause(rule.when, true)
            if action.type ~= "spell" then
                castVerb = "/use"
            else
                castClauses[#castClauses + 1] = clause
                if onTarget then elseClauses[#elseClauses + 1] = onTarget end
            end
            castParts[#castParts + 1] = clause .. " " .. token
            if onTarget then elseParts[#elseParts + 1] = onTarget .. " " .. token end
        elseif action.type == "spell" then
            OwnLine("/click " .. clause .. " {rank:" .. action.spellID .. "}")
            castClauses[#castClauses + 1] = clause
        elseif action.type == "text" then
            -- The player's own text runs as written, once no earlier rule has fired.
            if HasConditions(rule.when) then
                out.problems[#out.problems + 1] = "Macro text cannot have conditions here: write them in the text, like [@mouseover,help]."
            else
                OwnLine(action.text)
            end
        elseif action.type == "menu" then
            OwnLine("/click " .. clause .. " {menu}")
        elseif COMMAND[action.type] then
            OwnLine(COMMAND[action.type] .. " " .. clause)
        elseif not seen[clause] then
            out.problems[#out.problems + 1] = "A macro can only be the single rule of a key, with no conditions."
        end
        if not seen[clause] then earlier[#earlier + 1] = clause end
        seen[clause] = true
        if Always(rule.when) and (rule.when.unit or not binding.hover) then
            if i < #live then
                out.problems[#out.problems + 1] = (#live - i) .. " rule(s) after "
                    .. (rule.when.unit and "a rule that always casts on yourself" or "an unconditional rule") .. " can never fire."
                out.fix = out.fix or { rule = from[i], last = true }
            end
            break
        end
    end
    CloseCast()
    if #lines == 0 then return out end
    -- Before a spell is cast: stop the cast in progress, use a trinket. Only
    -- under the conditions of the key's spell rules, so that a click that
    -- targets or opens the menu does neither.
    -- With `onTarget` the key's one /cast line goes on to the player's
    -- target: the same spells under the same conditions, tried when none of
    -- them fits the unit under the cursor or nothing is there. That is what
    -- keeps a key that works anywhere from being dead away from a unit.
    local function Build(onTarget)
        local all = {}
        for i, line in ipairs(lines) do all[i] = line end
        local when = tconcat(castClauses)
        if onTarget and #elseParts > 0 then
            all[1] = all[1] .. "; " .. tconcat(elseParts, "; ")
            when = when .. tconcat(elseClauses)
        end
        if binding.pre and #castClauses > 0 then
            local at = 1
            for _, what in ipairs(PRE_ORDER) do
                if binding.pre[what] then
                    table.insert(all, at, what == "stop" and ("/stopcasting " .. when)
                        or ("/use " .. when .. " " .. (what == "trinket1" and "13" or "14")))
                    at = at + 1
                end
            end
        end
        local text = tconcat(all, "\n")
        return text, #(text:gsub("{[^}]*}", ("x"):rep(PROXY_LENGTH)))
    end

    out.kind = "macrotext"
    if binding.hover and binding.orTarget then
        if ownLines or #lines ~= 1 then
            out.problems[#out.problems + 1] = "\"Else my target\" needs a key whose rules are all spells or items; "
                .. "this key works on the unit under the cursor only."
        else
            local text, length = Build(true)
            if length > MACRO_LIMIT then
                out.problems[#out.problems + 1] = "No room left for \"else my target\" on this key; "
                    .. "it works on the unit under the cursor only."
            else
                out.text, out.length, out.onTarget = text, length, true
            end
        end
    end
    -- A wheel key that works anywhere would take the camera's zoom away for
    -- good. It is the game's again when nothing is under the cursor. Not
    -- together with "else my target": there the turn of the wheel is a cast.
    local _, bare = ParseKey(binding.key)
    if binding.hover and not binding.orTarget and ZOOM[bare] then
        out.zoom = true
    elseif binding.hover and binding.orTarget and ZOOM[bare] then
        out.problems[#out.problems + 1] = "With \"else my target\" the wheel no longer zooms the camera. "
            .. "\"Any unit under the cursor\" keeps the zoom when nothing is under the cursor."
    end
    if not out.text then out.text, out.length = Build(false) end
    out.tooLong = out.length > MACRO_LIMIT
    if out.tooLong then
        out.problems[#out.problems + 1] = "Too many rules for one key: " .. out.length
            .. " characters, the game allows " .. MACRO_LIMIT .. "."
    end
    return out
end

-------------------------------------------------------------------------------
--  The legend's reader
-------------------------------------------------------------------------------
local function ItemIcon(action)
    local what = action.itemID or action.name
    if what and C_Item and C_Item.GetItemIconByID then
        local ok, tex = pcall(C_Item.GetItemIconByID, what)
        if ok and ValidIcon(tex) then return tex end
    end
    return nil
end

function ActionEntry(action)
    local t = action.type
    if t == "spell" then
        local id = ActionSpellID(action)
        local name = action.name or (id and SpellName(id)) or "Unknown Spell"
        local entry = Entry(name, SpellTexture(id) or SpellTexture(action.name), id, Unavailable(action))
        if action.pinned and C_Spell and C_Spell.GetSpellSubtext then
            -- "Rank 2" -> 2: the legend marks an icon that casts one exact rank.
            local ok, text = pcall(C_Spell.GetSpellSubtext, action.spellID)
            entry.rank = ok and type(text) == "string" and tonumber(text:match("(%d+)")) or nil
        end
        return entry
    elseif t == "item" then
        return Entry(action.name or "Item", ItemIcon(action))
    elseif t == "macro" then
        local found, tex = MacroInfo(action.name)
        return Entry(action.name, tex or TYPE_ICON.macro, nil, GetMacroInfo ~= nil and found == nil)
    elseif t == "trinket1" or t == "trinket2" then
        return Entry(ACTION_NAME[t], InventoryTexture(t == "trinket1" and 13 or 14))
    elseif t == "text" then
        return Entry(ACTION_NAME.text, TYPE_ICON.macro)
    elseif t == "dispel" or t == "rez" then
        local name = PresetSpell(action)
        local id = name and SpellIDFor(name)
        if name then return Entry(name, SpellTexture(id) or SpellTexture(name), id) end
        return Entry(ACTION_NAME[t], TYPE_ICON[t == "rez" and "dynamicrez" or t], nil, true)
    end
    return Entry(ACTION_NAME[t], TYPE_ICON[t])
end

-- What the legend knows about the moment: the player's own state, and
-- whether the unit under the cursor is dead. Read once per collection.
local function Moment()
    local now = { hoverSide = nil, hoverDead = false }
    if ns.HoverState then now.hoverSide, now.hoverDead = ns.HoverState() end      -- Display.lua
    if InCombatLockdown then now.combat = InCombatLockdown() and true or false end
    if GetShapeshiftForm then
        local ok, form = pcall(GetShapeshiftForm)
        if ok and type(form) == "number" then now.form = form end
    end
    if UnitExists then
        local ok, pet = pcall(UnitExists, "pet")
        if ok and not (issecretvalue and issecretvalue(pet)) then now.pet = pet and true or false end
    end
    return now
end

-- Would this rule be the one to fire on a unit of `side`, with the extra
-- modifier `mod` held ("" for none)? A state that cannot be read counts as
-- fitting. A unit is taken to be alive unless it is the dead one under the
-- cursor.
local function Fits(when, side, mod, now)
    if when.reaction and when.reaction ~= (side == "ally" and "help" or "harm") then return false end
    -- A rule about a unit of its own: that unit is taken to be alive.
    local dead = not when.unit and now.hoverSide == side and now.hoverDead or false
    if when.dead ~= nil and when.dead ~= dead then return false end
    if when.combat ~= nil and now.combat ~= nil and when.combat ~= now.combat then return false end
    if when.form and now.form and when.form ~= now.form then return false end
    if when.pet ~= nil and now.pet ~= nil and when.pet ~= now.pet then return false end
    if when.mod and when.mod ~= mod then return false end
    return true
end

-- The rule the legend shows for a side: the first that would fire right now,
-- preferring a spell the character has. With none the character has, the
-- first is shown as missing.
local function RuleFor(binding, side, mod, now)
    local fallback
    for _, rule in ipairs(Expanded(binding.rules)) do
        if not Incomplete(rule.action) and Fits(rule.when, side, mod, now) then
            if not Unavailable(rule.action) then return rule end
            fallback = fallback or rule
        end
    end
    return fallback
end

local RULE_MOD_PREFIX = { shift = "SHIFT-", ctrl = "CTRL-", alt = "ALT-" }

-- Returns nil unless this character has switched its own bindings on and has
-- a set with something in it. What is shown follows the rules: it is what each
-- key would do at this moment.
local function CollectOwnLayers()
    if not (cast and cast.enabled) then return nil end
    local set = ActiveSet()
    if not set then return nil end
    local layers, now = {}, Moment()
    local function Put(binding, mods, key, mod)
        for _, side in ipairs({ "ally", "enemy" }) do
            local rule = RuleFor(binding, side, mod, now)
            if rule then
                local entry = ActionEntry(rule.action)
                entry.unit = rule.when.unit         -- the legend asks about range to this unit
                PutEntry(layers, mods, key, side, entry)
            end
        end
    end
    for _, binding in ipairs(set.bindings) do
        local mods, key = ParseKey(binding.key)
        Put(binding, mods, key, "")
    end
    -- A rule with an extra modifier shows on that modifier's layer, unless a
    -- key of its own is bound there (first one wins the key).
    for _, binding in ipairs(set.bindings) do
        local mods, key = ParseKey(binding.key)
        local done = {}
        for _, rule in ipairs(binding.rules) do
            local mod = rule.when.mod
            local extra = mod and RULE_MOD_PREFIX[mod]
            if extra and not done[mod] and not mods:find(extra, 1, true) then
                done[mod] = true
                Put(binding, (ParseKey(mods .. extra .. "X")), key, mod)
            end
        end
    end
    return layers
end

-- True when a rule of the binding asks for an extra modifier.
local function UsesExtraModifier(binding)
    for _, rule in ipairs(binding.rules) do
        if rule.when.mod then return true end
    end
    return false
end

-------------------------------------------------------------------------------
--  Other click casting on the same frames. ClickLegend never changes what
--  another addon or the game has bound; it says what it found.
-------------------------------------------------------------------------------
local function KeyName(keyStr)
    local mods, key = ParseKey(keyStr)
    return (mods ~= "" and (ModsLong(mods) .. "+") or "") .. LongKey(key)
end

-- The keys of the set in use that work anywhere and are also one of the
-- game's key bindings, which then never fires: { key = name, action = what
-- the game had on it }.
local function Shadowed()
    local out = {}
    local set = ActiveSet()
    if not (set and GetBindingAction) then return out end
    for _, binding in ipairs(set.bindings) do
        if binding.hover then
            local ok, action = pcall(GetBindingAction, binding.key)
            if ok and type(action) == "string" and action ~= "" and not action:find("ClickLegend", 1, true) then
                local named = _G["BINDING_NAME_" .. action]
                out[#out + 1] = { key = KeyName(binding.key), action = type(named) == "string" and named or action }
            end
        end
    end
    return out
end

local function Conflicts()
    local found = {}
    local eui = type(EllesmereUIDB) == "table" and EllesmereUIDB.clickCast
    if type(eui) == "table" and eui.enabled then
        found[#found + 1] = "EllesmereUI HoverCast is on and binds the same frames. Use one or the other: "
            .. "to keep ClickLegend, switch off Enable Click Casting on EllesmereUI's HoverCast page."
    end
    -- VuhDo hands its frames to a click-cast addon when its "Clique Support"
    -- option is ticked, and binds them itself otherwise.
    if type(VUHDO_CONFIG) == "table" and cast.frames.registered then
        if VUHDO_CONFIG.IS_CLIQUE_COMPAT_MODE then
            if type(Clique) ~= "table" then
                found[#found + 1] = "VuhDo: its frames are bound by ClickLegend. "
                    .. "(VuhDo's message about Clique not being loaded can be ignored.)"
            end
        else
            found[#found + 1] = "VuhDo: to use ClickLegend on VuhDo's frames, tick Clique Support in VuhDo's "
                .. "options (General, Misc) and reload. Until then VuhDo uses its own bindings there."
        end
    end
    -- Frame addons that can be set to act when a mouse button goes down.
    -- ClickLegend's clicks act when it comes up, so those two do not meet.
    local okGrid, gridDown = pcall(function() return Grid2.db.global.clickOnMouseDown end)
    if okGrid and gridDown and cast.frames.registered then
        found[#found + 1] = "Grid2: switch off its option to click on mouse down, or ClickLegend's clicks will not fire on Grid2's frames."
    end
    local okElv, elvDown = pcall(function() return ElvUI[1].db.unitframe.targetOnMouseDown end)
    if okElv and elvDown and cast.frames.registered then
        found[#found + 1] = "ElvUI: switch off Target On Mouse-Down in its unit frame options, or ClickLegend's clicks will not fire on ElvUI's frames."
    end
    -- HealBot always does its own click casting on its own frames.
    if type(HealBot_Config_Spells) == "table" then
        found[#found + 1] = "HealBot does its own click casting on its own frames; ClickLegend's bindings "
            .. "work on the game's frames and other unit frames, not on HealBot's."
    end
    local set = ActiveSet()
    for _, taken in ipairs(Shadowed()) do
        found[#found + 1] = taken.key .. " works anywhere, so ClickLegend has that key all the time. "
            .. "It is also one of the game's key bindings (" .. taken.action .. "), which will not fire while click casting is on."
    end
    local ok, game = pcall(CollectBlizzardLayers)
    if set and ok and type(game) == "table" then
        for _, binding in ipairs(set.bindings) do
            local mods, key = ParseKey(binding.key)
            local slot = game[mods] and game[mods].byKey[key]
            local entry = slot and (slot.ally or slot.enemy)
            if entry then
                found[#found + 1] = "The game's own Click Casting also binds " .. KeyName(binding.key) .. " ("
                    .. entry.name .. ") and can override ClickLegend. Remove it in the game's Click Casting screen."
            end
        end
    end
    return found
end

-------------------------------------------------------------------------------
--  Provider.lua puts the bindings on frames, and reads everything it needs
--  through this table. Global so that its state can be looked at in game
--  (/dump ClickLegendAPI.provider.Count()).
-------------------------------------------------------------------------------
ClickLegendAPI = {
    Print = Print, Report = Report, Safe = Safe, ParseKey = ParseKey,
    ActiveSet = ActiveSet, CompileBinding = CompileBinding, UsesExtraModifier = UsesExtraModifier,
    HoverAllowed = HoverAllowed,
    Settings = function() return cast end,
}

-- Tells the provider to bring the frames in line with the settings. The
-- provider ignores this until a character has had its bindings on.
local function UpdateProvider()
    if cast and (cast.enabled or cast.heldBack) then
        local why = Blocked()
        if why then
            cast.enabled = false
            Print(why)
        end
        cast.heldBack = nil
    end
    local provider = ClickLegendAPI.provider
    if cast and provider then Safe(provider.Apply) end
end

-------------------------------------------------------------------------------
--  Changes made from the settings screens. Every one ends in CastChanged,
--  which brings the frames, the legend and the open window up to date.
-------------------------------------------------------------------------------
local function CastChanged()
    UpdateProvider()
    ns.Refresh(true)                -- Display.lua
    ns.RefreshWindow()              -- Window.lua, which redraws the Bindings tab
end

local function CastSettings() return cast end

local function SetCastEnabled(on)
    if not cast then return end
    cast.enabled = on and true or false
    CastChanged()
end

local function SetCastDown(on)
    if not cast then return end
    cast.down = on and true or false
    CastChanged()
end

local function SetCastFrames(group, on)
    if not cast or cast.frames[group] == nil then return end
    cast.frames[group] = on and true or false
    CastChanged()
end

local function SelectSet(name)
    local set = sets and sets[name]
    if type(set) ~= "table" or set.version ~= SET_VERSION then return false end
    UseSet(name)
    CastChanged()
    return true
end

-- on: the set in use becomes this spec's own, and other specs keep theirs.
-- off: the set in use becomes the one for every spec.
local function SetSpecOnly(on)
    local specID = SpecState()
    local name = ActiveSetName()
    if not (specID and name and sets[name]) then return false end
    if on then
        cast.specSet[specID] = name
    else
        cast.set, cast.specSet = name, {}
    end
    CastChanged()
    return true
end

local function CanonicalKey(keyStr)
    if type(keyStr) ~= "string" then return nil end
    local mods, key = ParseKey(keyStr)
    if key == "" then return nil end
    return mods .. key
end

local function FindBinding(set, key)
    for i, b in ipairs(set.bindings) do
        if b.key == key then return i end
    end
    return nil
end

-- What each condition can be set to, in the order the editor steps through.
-- false stands for "does not matter" (the condition is left out).
local CONDITION_VALUES = {
    reaction = { false, "help", "harm" },
    dead = { false, "alive", "dead" },
    combat = { false, "in", "out" },
    pet = { false, "pet", "nopet" },
    mod = { false, "shift", "ctrl", "alt" },
    form = { false, 0, 1, 2, 3, 4, 5, 6 },
    unit = { false, "player", "target", "focus", "targettarget", "pet" },
}
local CONDITION_STORED = {          -- editor value -> what is saved
    alive = false, dead = true, ["in"] = true, out = false, pet = true, nopet = false,
}
local ACTION_ORDER = { "spell", "item", "macro", "text", "dispel", "rez", "target", "focus", "assist", "menu",
                       "trinket1", "trinket2" }

-- The editor value of a rule's condition (see CONDITION_VALUES).
local function ConditionValue(when, field)
    local v = when[field]
    if v == nil then return false end
    if field == "dead" then return v and "dead" or "alive" end
    if field == "combat" then return v and "in" or "out" end
    if field == "pet" then return v and "pet" or "nopet" end
    return v
end

-- Edits to the set in use. Each returns true, or false and why not.
local Edit = {}

local function Target(bindingIndex, ruleIndex)
    local set = ActiveSet()
    local binding = set and set.bindings[bindingIndex]
    if not binding then return nil end
    if ruleIndex == nil then return set, binding end
    return set, binding, binding.rules[ruleIndex]
end

function Edit.AddBinding(keyStr)
    local set = ActiveSet()
    local key = CanonicalKey(keyStr)
    if not set then return false, "Make or pick a set first." end
    if not key then return false, "That is not a key." end
    if FindBinding(set, key) then return false, KeyName(key) .. " is already in this set." end
    set.bindings[#set.bindings + 1] = { key = key, rules = { { when = { reaction = "help" }, action = { type = "spell" }, fresh = true } } }
    CastChanged()
    return true, #set.bindings
end

function Edit.SetKey(bindingIndex, keyStr)
    local set, binding = Target(bindingIndex)
    local key = CanonicalKey(keyStr)
    if not binding then return false, "No such key." end
    if not key then return false, "That is not a key." end
    local taken = FindBinding(set, key)
    if taken and taken ~= bindingIndex then return false, KeyName(key) .. " is already in this set." end
    binding.key = key
    if not HoverAllowed(key) then binding.hover, binding.orTarget = nil, nil end
    CastChanged()
    return true
end

-- Whether the key works on any unit under the cursor, or on unit frames only.
-- With `orTarget` it goes on to the player's target when the unit under the
-- cursor does not fit or nothing is there.
function Edit.SetHover(bindingIndex, on, orTarget)
    local _, binding = Target(bindingIndex)
    if not binding then return false, "No such key." end
    if on and not HoverAllowed(binding.key) then
        return false, "Plain left and right click stay on unit frames: the game needs them everywhere else."
    end
    binding.hover = on and true or nil
    binding.orTarget = (on and orTarget) and true or nil
    CastChanged()
    return true
end

-- Moves a key up or down the set's list.
function Edit.MoveBinding(bindingIndex, delta)
    local set, binding = Target(bindingIndex)
    local to = bindingIndex + delta
    if not binding or not set.bindings[to] then return false end
    set.bindings[bindingIndex], set.bindings[to] = set.bindings[to], binding
    CastChanged()
    return true
end

-- The keys in the order of a mouse and then the keyboard: left, right,
-- middle, the extra buttons, the wheel, then keys by name; each one plain
-- first, then with Shift, Ctrl, Alt.
local MOD_RANK = { [""] = 0, ["SHIFT-"] = 1, ["CTRL-"] = 2, ["ALT-"] = 3 }
local function KeyRank(keyStr)
    local mods, key = ParseKey(keyStr)
    local n = tonumber(key:match("^BUTTON(%d+)$"))
    return n or (key == "MOUSEWHEELUP" and 100) or (key == "MOUSEWHEELDOWN" and 101) or 200, key, MOD_RANK[mods] or 4, mods
end

function Edit.SortKeys()
    local set = ActiveSet()
    if not set or #set.bindings < 2 then return false end
    local was = {}
    for i, binding in ipairs(set.bindings) do was[i] = binding end
    table.sort(set.bindings, function(a, b)
        local a1, a2, a3, a4 = KeyRank(a.key)
        local b1, b2, b3, b4 = KeyRank(b.key)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if a3 ~= b3 then return a3 < b3 end
        return a4 < b4
    end)
    local changed = false
    for i, binding in ipairs(set.bindings) do changed = changed or was[i] ~= binding end
    if not changed then return false end
    CastChanged()
    return true
end

function Edit.RemoveBinding(bindingIndex)
    local set, binding = Target(bindingIndex)
    if not binding then return false, "No such key." end
    table.remove(set.bindings, bindingIndex)
    CastChanged()
    return true
end

-- Several keys taken out of the set in one go (one Undo step). Returns how many.
function Edit.RemoveKeys(keyList)
    local set = ActiveSet()
    if not (set and type(keyList) == "table") then return false end
    local gone, count = {}, 0
    for _, key in ipairs(keyList) do gone[key] = true end
    for i = #set.bindings, 1, -1 do
        if gone[set.bindings[i].key] then
            table.remove(set.bindings, i)
            count = count + 1
        end
    end
    if count == 0 then return false end
    CastChanged()
    return count
end

-- Something done just before a spell of the key is cast: "stop" (the cast in
-- progress), "trinket1", "trinket2".
function Edit.SetPre(bindingIndex, what, on)
    local _, binding = Target(bindingIndex)
    local known = false
    for _, name in ipairs(PRE_ORDER) do known = known or name == what end
    if not (binding and known) then return false end
    local pre = binding.pre or {}
    pre[what] = on and true or nil
    binding.pre = next(pre) and pre or nil
    CastChanged()
    return true
end

-- The kinds of rule the editor offers by name. Each is put where it can
-- fire: a resurrection first, "else on myself" last, the others in front of
-- the first rule that always fits.
local RECIPES = {
    ally = { when = { reaction = "help" } },
    enemy = { when = { reaction = "harm" } },
    rez = { when = { reaction = "help", dead = true }, action = "rez", first = true },
    self = { when = { unit = "player" }, last = true },
    target = { when = { unit = "target" } },
    focus = { when = { unit = "focus" } },
    targettarget = { when = { unit = "targettarget" } },
    pet = { when = { unit = "pet" } },
    blank = { when = {}, last = true },
}
local RECIPE_ORDER = { "ally", "enemy", "rez", "self", "target", "focus", "targettarget", "pet", "blank" }

-- A new rule: one of RECIPES, or with none the side the key does not cover
-- yet. Returns true and where the rule now is.
function Edit.AddRule(bindingIndex, recipe)
    local _, binding = Target(bindingIndex)
    if not binding then return false, "No such key." end
    local made = recipe and RECIPES[recipe]
    if recipe and not made then return false end
    if not made then
        local has = {}
        for _, rule in ipairs(binding.rules) do has[rule.when.reaction or "any"] = true end
        local reaction = (not has.help and "help") or (not has.harm and "harm") or nil
        binding.rules[#binding.rules + 1] = { when = { reaction = reaction }, action = { type = "spell" } }
        CastChanged()
        return true, #binding.rules
    end
    local at = #binding.rules + 1
    if made.first then
        at = 1
    elseif not made.last then
        for i, rule in ipairs(binding.rules) do
            if Always(rule.when) then at = i; break end
        end
    end
    -- "Else on myself" is nearly always the spell the key already casts on an
    -- ally, so it starts as that one (third return: nothing left to choose).
    local action, filled = { type = made.action or "spell" }, made.action ~= nil
    if recipe == "self" then
        for _, rule in ipairs(binding.rules) do
            local a, w = rule.action, rule.when
            if a.type == "spell" and (a.name or a.spellID) and w.reaction ~= "harm" and w.dead ~= true and not w.unit then
                action, filled = CopyTable(a), true
                break
            end
        end
    end
    table.insert(binding.rules, at, Normalise({ when = CopyTable(made.when), action = action }))
    CastChanged()
    return true, at, filled
end

function Edit.RemoveRule(bindingIndex, ruleIndex)
    local _, binding, rule = Target(bindingIndex, ruleIndex)
    if not rule then return false, "No such rule." end
    if #binding.rules == 1 then return false, "A key needs at least one rule. Remove the key instead." end
    table.remove(binding.rules, ruleIndex)
    CastChanged()
    return true
end

function Edit.MoveRule(bindingIndex, ruleIndex, delta)
    local _, binding, rule = Target(bindingIndex, ruleIndex)
    local to = ruleIndex + delta
    if not rule or not binding.rules[to] then return false end
    binding.rules[ruleIndex], binding.rules[to] = binding.rules[to], rule
    CastChanged()
    return true
end

-- Mends the first problem of order the compiler found (see `fix` there): the
-- rule that can never fire goes above the one in its way, or the rule that
-- always fits goes last.
function Edit.FixOrder(bindingIndex)
    local _, binding = Target(bindingIndex)
    if not binding then return false end
    local moved = false
    for _ = 1, 12 do                    -- one move may uncover the next problem
        local fix = CompileBinding(binding).fix
        if not (fix and binding.rules[fix.rule]) then break end
        local rule = table.remove(binding.rules, fix.rule)
        if fix.last then
            binding.rules[#binding.rules + 1] = rule
        else
            table.insert(binding.rules, fix.before, rule)   -- `before` is above `rule`, so it has not moved
        end
        moved = true
    end
    if not moved then return false end
    CastChanged()
    return true
end

-- A condition set straight to one of its values (see CONDITION_VALUES).
function Edit.SetCondition(bindingIndex, ruleIndex, field, value)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    local values = CONDITION_VALUES[field]
    if not (rule and values) then return false end
    local known = false
    for _, v in ipairs(values) do
        if v == value then known = true end
    end
    if not known then return false end
    if rule.action.type == "text" and value ~= false then
        return false, "Macro text takes no conditions here: write them in the text, like [@mouseover,help]."
    end
    rule.fresh = nil                    -- the player has said who it is for
    if value == false then
        rule.when[field] = nil
    elseif CONDITION_STORED[value] ~= nil then
        rule.when[field] = CONDITION_STORED[value]
    else
        rule.when[field] = value
    end
    Normalise(rule)
    CastChanged()
    return true
end

-- The first rule of a key just added starts as "ally" (`fresh`). The spell
-- then picked for it says who it is for: a harmful one goes on enemies, one
-- that is both on anyone, a resurrection on dead allies. Once only: after
-- that the conditions are the player's.
local QuickSlots                -- defined with Quickbind, below
local function FreshSide(rule)
    if not rule.fresh then return end
    rule.fresh = nil
    local slots = QuickSlots(rule.action)
    if #slots == 2 then
        rule.when = {}
    elseif slots[1] == "enemy" then
        rule.when = { reaction = "harm" }
    elseif slots[1] == "dead" then
        rule.when = { reaction = "help", dead = true }
    end
end

-- What a rule does, set to a kind (nothing chosen yet for the kinds that
-- need a name) or to a whole action picked from a list.
function Edit.SetActionType(bindingIndex, ruleIndex, kind)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    if not (rule and ACTION_TYPES[kind]) then return false end
    if rule.action.type ~= kind then
        rule.action = { type = kind }
        Normalise(rule)
        CastChanged()
    end
    return true
end

function Edit.SetAction(bindingIndex, ruleIndex, action)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    local clean = rule and CleanAction(action)
    if not clean then return false end
    rule.action = clean
    FreshSide(rule)
    Normalise(rule)
    CastChanged()
    return true
end

-- A spell, item or macro dropped from the spellbook, bags or macro window:
-- what GetCursorInfo() returned. A dropped spell keeps its id, so that exact
-- rank can be pinned.
local function CursorAction(kind, a, b, c)
    if kind == "spell" then
        local id = WholeNumber(c, 1, 2 ^ 31) or WholeNumber(a, 1, 2 ^ 31)
        if not id then return nil end
        return { type = "spell", spellID = id, name = SpellName(id) }
    elseif kind == "item" then
        local id = WholeNumber(a, 1, 2 ^ 31)
        if not id then return nil end
        local name
        if C_Item and C_Item.GetItemNameByID then
            local ok, n = pcall(C_Item.GetItemNameByID, id)
            name = ok and Text(n) or nil
        end
        return { type = "item", itemID = id, name = name }
    elseif kind == "macro" then
        local name = MacroInfo(a)
        if not Text(name) then return nil end
        return { type = "macro", name = name }
    end
    return nil
end

function Edit.SetActionFromCursor(bindingIndex, ruleIndex, kind, a, b, c)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    local action = rule and CursorAction(kind, a, b, c)
    if not action then return false end
    rule.action = action
    FreshSide(rule)
    CastChanged()
    return true
end

-------------------------------------------------------------------------------
--  The simple view of a key, for the guided setup: four slots.
--    ally   what it does on a living ally
--    dead   what it does on a dead ally (nothing: same as a living one)
--    enemy  what it does on an enemy
--    self   what it casts on the player when none of those fits
--  A slot is the rule, or chain of fallback rules, with exactly that
--  condition. Rules with other conditions (combat, form, pet, modifier) are
--  not part of any slot and are left as they are.
-------------------------------------------------------------------------------
local SLOT_WHEN = {
    ally = { reaction = "help" }, dead = { reaction = "help", dead = true }, enemy = { reaction = "harm" },
    self = { unit = "player" },
}

local function Plain(when)             -- no combat, form, pet or modifier condition, no unit of its own
    return when.combat == nil and when.form == nil and when.pet == nil and when.mod == nil and when.unit == nil
end

local function InSlot(when, slot)
    if slot == "self" then                              -- on the player, whatever else
        return when.unit == "player" and Always(when)
    end
    if slot == "dead" then                              -- a dead-ally rule, in or out of combat
        return when.reaction == "help" and when.dead == true and when.form == nil
            and when.pet == nil and when.mod == nil
    end
    if not Plain(when) or when.dead ~= nil then return false end
    return when.reaction == (slot == "ally" and "help" or "harm")
end

-- The action a slot of a key has now: the first rule of the slot whose spell
-- the character has, else its first rule. A rule for anyone counts for both
-- the ally and the enemy slot. Nil when the slot is empty.
local function SlotAction(keyStr, slot)
    local set = ActiveSet()
    local key = CanonicalKey(keyStr)
    local index = set and key and FindBinding(set, key)
    if not index then return nil end
    local fallback
    for _, rule in ipairs(set.bindings[index].rules) do
        local when = rule.when
        local anyone = slot ~= "dead" and slot ~= "self" and when.reaction == nil and when.dead == nil and Plain(when)
        if (anyone or InSlot(when, slot)) and not Incomplete(rule.action) then
            if not Unavailable(rule.action) then return rule.action end
            fallback = fallback or rule.action
        end
    end
    return fallback
end

-- Sets a slot of a key to one action, or empties it (action nil). The key is
-- made when it does not exist yet and removed when nothing is left on it.
function Edit.SetSlot(keyStr, slot, action)
    local set = ActiveSet()
    local key = CanonicalKey(keyStr)
    local clean = action and CleanAction(action)
    if not (set and key and SLOT_WHEN[slot]) then return false, "Make or pick a set first." end
    if action and not clean then return false end
    local index = FindBinding(set, key)
    local old = index and set.bindings[index].rules or {}
    local rules = {}
    for _, rule in ipairs(old) do
        local when = rule.when
        if when.reaction == nil and when.dead == nil and Plain(when) then
            -- A rule for anyone becomes one for allies and one for enemies, so
            -- that one side can be changed without the other.
            if slot ~= "ally" then rules[#rules + 1] = { when = { reaction = "help" }, action = rule.action } end
            if slot ~= "enemy" then rules[#rules + 1] = { when = { reaction = "harm" }, action = CopyTable(rule.action) } end
        elseif not InSlot(when, slot) then
            rules[#rules + 1] = rule
        end
    end
    if clean then
        -- Dead-ally rules go first, then the ally rule, then the enemy rule;
        -- the rule on the player is the last of all, since it always fits.
        local at = #rules + 1
        if slot == "enemy" then
            for i, rule in ipairs(rules) do
                if InSlot(rule.when, "self") then at = i; break end
            end
        elseif slot ~= "self" then
            at = 1
            for i, rule in ipairs(rules) do
                local w = rule.when
                if w.reaction == "help" and (w.dead == true or (slot == "dead" and false)) then at = i + 1 end
            end
            if slot == "dead" then at = 1 end
        end
        table.insert(rules, at, Normalise({ when = CopyTable(SLOT_WHEN[slot]), action = clean }))
    end
    if #rules == 0 then
        if index then table.remove(set.bindings, index) end
    elseif index then
        set.bindings[index].rules = rules
    else
        set.bindings[#set.bindings + 1] = { key = key, rules = rules }
    end
    CastChanged()
    return true
end

-------------------------------------------------------------------------------
--  Quickbind: a spell put on a key in one go. Where it lands follows the
--  spell: a resurrection on dead allies, a harmful spell on enemies, a spell
--  that is both on both, anything else on allies.
-------------------------------------------------------------------------------
QuickSlots = function(action)
    if action.type == "rez" then return { "dead" } end
    if action.type ~= "spell" then return { "ally" } end
    for _, kind in ipairs({ "rez", "battlerez" }) do
        for _, name in ipairs(PRESET_SPELLS[kind]) do
            if action.name == name then return { "dead" } end
        end
    end
    local id = ActionSpellID(action)
    local helpful, harmful = false, false
    if id and C_Spell and C_Spell.IsSpellHelpful and C_Spell.IsSpellHarmful then
        local ok1, a = pcall(C_Spell.IsSpellHelpful, id)
        local ok2, b = pcall(C_Spell.IsSpellHarmful, id)
        helpful, harmful = (ok1 and a) and true or false, (ok2 and b) and true or false
    end
    if helpful and harmful then return { "ally", "enemy" } end
    return { harmful and "enemy" or "ally" }
end

local SLOT_WORDS = { ally = "allies", dead = "dead allies", enemy = "enemies", self = "yourself" }

-- Returns true and where it went ("allies and enemies"), or false and why not.
-- With no set in use, one is made.
function Edit.Quickbind(keyStr, action)
    local clean = CleanAction(action)
    if not (cast and clean) then return false, "Nothing to put on the key." end
    if not CanonicalKey(keyStr) then return false, "That is not a key." end
    if not ActiveSet() then
        local ok, name = NewSet(FreeName("My bindings"))
        if not ok then return false, "Make or pick a set first." end
        UseSet(name)
    end
    local words = {}
    for _, slot in ipairs(QuickSlots(clean)) do
        local ok, why = Edit.SetSlot(keyStr, slot, CopyTable(clean))
        if not ok then return false, why end
        words[#words + 1] = SLOT_WORDS[slot]
    end
    return true, tconcat(words, " and ")
end

local function SameActionOf(a, action)
    return a.type == action.type and a.name == action.name
        and (a.pinned or false) == (action.pinned or false)
        and (not a.pinned or a.spellID == action.spellID)
end

-- The keys of the set in use that carry this action, by name: "Shift+Left, F".
local function BoundKeys(action)
    local set = ActiveSet()
    local names = {}
    if not set then return "" end
    for _, binding in ipairs(set.bindings) do
        for _, rule in ipairs(binding.rules) do
            if SameActionOf(rule.action, action) then
                names[#names + 1] = KeyName(binding.key)
                break
            end
        end
    end
    return tconcat(names, ", ")
end

-- Takes an action off every key of the set in use. A key left with no rule
-- goes too.
function Edit.RemoveAction(action)
    local set = ActiveSet()
    if not (set and type(action) == "table") then return false end
    local removed = false
    for b = #set.bindings, 1, -1 do
        local rules = set.bindings[b].rules
        for r = #rules, 1, -1 do
            if SameActionOf(rules[r].action, action) then table.remove(rules, r); removed = true end
        end
        if #rules == 0 then table.remove(set.bindings, b) end
    end
    if removed then CastChanged() end
    return removed
end

-- Another spell, item or macro in the place of `action`, on every key it is
-- on. Returns how many rules were changed.
function Edit.ReplaceAction(action, with)
    local set = ActiveSet()
    local clean = type(with) == "table" and CleanAction(with)
    if not (set and type(action) == "table" and clean) then return false end
    local count = 0
    for _, binding in ipairs(set.bindings) do
        for _, rule in ipairs(binding.rules) do
            if SameActionOf(rule.action, action) then
                rule.action = CopyTable(clean)
                Normalise(rule)
                count = count + 1
            end
        end
    end
    if count == 0 then return false end
    CastChanged()
    return count
end

-- True for a key that "hover casting" as a whole is about: a keyboard key,
-- the wheel or a mouse button past the third. Left, right and middle click
-- have a use in the world that a player would miss. Second: it is the wheel,
-- which never goes on to the target, so that it keeps zooming the camera
-- when no unit is under the cursor (see ZOOM).
local function HoverKey(keyStr)
    local _, key = ParseKey(keyStr)
    if key:match("^MOUSEWHEEL") then return true, true end
    local n = tonumber(key:match("^BUTTON(%d+)$"))
    return n == nil or n > 3, false
end

-- Those keys of the set in use: how many there are, how many of them work
-- anywhere, and how many of those go on to the target (or are the wheel,
-- which goes as far as it ever does).
local function KeyboardKeys()
    local set = ActiveSet()
    local count, anywhere, onTarget = 0, 0, 0
    for _, binding in ipairs(set and set.bindings or {}) do
        local is, wheel = HoverKey(binding.key)
        if is then
            count = count + 1
            if binding.hover then anywhere = anywhere + 1 end
            if binding.hover and (binding.orTarget or wheel) then onTarget = onTarget + 1 end
        end
    end
    return count, anywhere, onTarget
end

-- Every such key of the set in use: anywhere, or on unit frames only. Anywhere
-- goes on to the target (so that the key is not dead away from a unit) unless
-- `orTarget` is false. False when nothing had to change.
function Edit.SetHoverKeys(on, orTarget)
    local set = ActiveSet()
    if not set then return false end
    local hover = on and true or nil
    local target = on and orTarget ~= false and true or nil
    local changed = false
    for _, binding in ipairs(set.bindings) do
        local is, wheel = HoverKey(binding.key)
        local want = not wheel and target or nil
        if is and (binding.hover ~= hover or binding.orTarget ~= want) then
            binding.hover, binding.orTarget = hover, want
            changed = true
        end
    end
    if changed then CastChanged() end
    return changed
end

-- Every key that works anywhere set the way one of them is: off, on, or on
-- and else the target. The wheel never goes on to the target.
function Edit.SetHoverAll(on, orTarget)
    local set = ActiveSet()
    if not set then return false end
    local hover, target = on and true or nil, on and orTarget and true or nil
    local changed = false
    for _, binding in ipairs(set.bindings) do
        if binding.hover then
            local _, wheel = HoverKey(binding.key)
            local want = not wheel and target or nil
            if binding.hover ~= hover or binding.orTarget ~= want then
                binding.hover, binding.orTarget = hover, want
                changed = true
            end
        end
    end
    if not changed then return false end
    CastChanged()
    return true
end

-------------------------------------------------------------------------------
--  A set copied from another click-cast addon, or from the game's own Click
--  Casting: what the legend reads from them (Sources.lua), turned into rules.
--  One spell for allies and another for enemies become two rules; the same
--  on both becomes one rule for anyone. What cannot be carried over (an
--  addon's own actions, an item known by name only) is left out and counted.
-------------------------------------------------------------------------------
local SOURCE_ACTION = {
    [TYPE_NAME.target] = "target", [TYPE_NAME.menu] = "menu", ["Set Focus"] = "focus", ["Assist"] = "assist",
}

local function SourceAction(entry)
    if type(entry) ~= "table" then return nil end
    if SOURCE_ACTION[entry.name] then return { type = SOURCE_ACTION[entry.name] } end
    -- A spell goes by its own name: some sources show a label of their own.
    local id = entry.spellID or SpellIDFor(entry.name)
    if id then return CleanAction({ type = "spell", name = SpellName(id) or entry.name }) end
    if MacroInfo(entry.name) then return { type = "macro", name = entry.name } end
    return nil
end

-- The sources a set can be copied from right now: { id, name }.
local function CopySources()
    local out = {}
    for _, source in ipairs(OtherSources()) do out[#out + 1] = { id = source.id, name = source.name } end
    return out
end

-- Returns the new set's name, how many keys it has and how many bindings
-- were left out; or false and why not.
-- Clique's own list says more than the legend's layers carry: a binding in
-- its "hovercast" set works on any unit under the cursor, one in "ooc" only
-- out of combat, and a macro binding holds its text. Read here, so that a
-- copy keeps all three. (Clique.db.profile.bindings: { key, type, spell,
-- macrotext, sets = { default, ooc, friend, enemy, hovercast, specN } }.)
-- Bindings limited to another talent spec are left where they are.
local function CopyFromClique()
    local C = Clique
    if type(C) ~= "table" then return nil end
    local list = type(C.db) == "table" and type(C.db.profile) == "table" and C.db.profile.bindings
    if type(list) ~= "table" then list = C.bindings end
    if type(list) ~= "table" then return nil end
    local specIndex
    local S = C_SpecializationInfo
    if S and S.GetSpecialization then
        local ok, index = pcall(S.GetSpecialization)
        if ok and type(index) == "number" and index > 0 then specIndex = index end
    end
    local byKey, order, left = {}, {}, 0
    for _, b in pairs(list) do
        if type(b) == "table" and type(b.key) == "string" and type(b.sets) == "table" and next(b.sets) ~= nil then
            local specOnly, specMatch = false, false
            for set in pairs(b.sets) do
                local n = type(set) == "string" and set:match("^spec(%d+)$")
                if n then
                    specOnly = true
                    specMatch = specMatch or tonumber(n) == specIndex
                end
            end
            local key = CanonicalKey(b.key)
            if key and (not specOnly or specMatch or not specIndex) then
                local action
                if b.type == "target" or b.type == "menu" then
                    action = { type = b.type }
                elseif b.type == "macro" then
                    local text = type(b.macrotext) == "string" and #b.macrotext <= MACRO_LIMIT and Text(b.macrotext, MACRO_LIMIT)
                    if text then
                        action = { type = "text", text = text }
                    elseif Text(b.macro) and MacroInfo(b.macro) then
                        action = { type = "macro", name = b.macro }
                    end
                elseif b.spell ~= nil then
                    local id = SpellIDFor(b.spell)
                    local name = id and SpellName(id) or (type(b.spell) == "string" and b.spell) or nil
                    action = name and CleanAction({ type = "spell", name = name }) or nil
                end
                if not action then
                    left = left + 1
                else
                    local when = {}
                    if action.type == "spell" then
                        if b.sets.friend and not b.sets.enemy then
                            when.reaction = "help"
                        elseif b.sets.enemy and not b.sets.friend then
                            when.reaction = "harm"
                        else
                            local slots = QuickSlots(action)
                            if #slots == 1 then
                                when.reaction = slots[1] == "enemy" and "harm" or "help"
                                if slots[1] == "dead" then when.dead = true end
                            end
                        end
                        if b.sets.ooc and not b.sets.default then when.combat = false end
                    end
                    local binding = byKey[key]
                    if not binding then
                        binding = { key = key, rules = {} }
                        byKey[key] = binding
                        order[#order + 1] = key
                    end
                    if b.sets.hovercast and HoverAllowed(key) then binding.hover = true end
                    binding.rules[#binding.rules + 1] = Normalise({ when = when, action = action })
                end
            end
        end
    end
    if #order == 0 then return nil end
    -- Clique keeps no order. Keys as a mouse and then a keyboard have them; in
    -- a key, the rule that asks for most first, so that none hides another.
    table.sort(order, function(a, b)
        local a1, a2, a3, a4 = KeyRank(a)
        local b1, b2, b3, b4 = KeyRank(b)
        if a1 ~= b1 then return a1 < b1 end
        if a2 ~= b2 then return a2 < b2 end
        if a3 ~= b3 then return a3 < b3 end
        return a4 < b4
    end)
    local function Rank(rule)
        local w = rule.when
        if rule.action.type == "text" then return 9 end
        local n = 0
        for _ in pairs(w) do n = n + 1 end
        return 4 - n + (w.reaction == "harm" and 0.5 or 0)
    end
    local bindings = {}
    for i, key in ipairs(order) do
        local binding = byKey[key]
        for n, rule in ipairs(binding.rules) do rule.at = n end
        table.sort(binding.rules, function(a, b)
            local ra, rb = Rank(a), Rank(b)
            if ra ~= rb then return ra < rb end
            local na, nb = tostring(a.action.name or a.action.type), tostring(b.action.name or b.action.type)
            if na ~= nb then return na < nb end
            return a.at < b.at
        end)
        for _, rule in ipairs(binding.rules) do rule.at = nil end
        bindings[i] = binding
    end
    local name = AddSet("From Clique", { bindings = bindings })
    if not name then return nil end
    return name, #sets[name].bindings, left
end

local function CopyFromSource(id)
    if id == "clique" then
        local name, count, left = CopyFromClique()
        if name then return name, count, left end
    end
    for _, source in ipairs(OtherSources()) do
        if source.id == id then
            local bindings, left = {}, 0
            for _, mods in ipairs(SortedMods(source.layers)) do
                local layer = source.layers[mods]
                for _, key in ipairs(layer.keys) do
                    local slot = layer.byKey[key]
                    local ally, enemy = SourceAction(slot.ally), SourceAction(slot.enemy)
                    if slot.ally and not ally then left = left + 1 end
                    if slot.enemy and not enemy and slot.enemy ~= slot.ally then left = left + 1 end
                    local rules = {}
                    if ally and enemy and ally.type == enemy.type and ally.name == enemy.name then
                        rules[1] = { when = {}, action = ally }
                    else
                        if ally then rules[#rules + 1] = { when = { reaction = "help" }, action = ally } end
                        if enemy then rules[#rules + 1] = { when = { reaction = "harm" }, action = enemy } end
                    end
                    if #rules > 0 then bindings[#bindings + 1] = { key = mods .. key, rules = rules } end
                end
            end
            local name = AddSet("From " .. source.name, { bindings = bindings })
            if not name then return false, "Nothing in " .. source.name .. " could be copied." end
            return name, #sets[name].bindings, left
        end
    end
    return false, "Nothing to copy from."
end

-------------------------------------------------------------------------------
--  Undo: the set as it was before each of the last few changes made from a
--  settings screen. Gone at the next reload. One step is one thing the
--  player did: an edit that calls other edits (Quickbind sets slots) counts
--  once.
-------------------------------------------------------------------------------
local UNDO_STEPS = 8
local undo = {}                 -- the newest last: { name = set name, set = a copy of it }
local depth = 0

for name, fn in pairs(Edit) do
    Edit[name] = function(...)
        local set, setName = ActiveSet()
        local before = depth == 0 and set and CopyTable(set)
        depth = depth + 1
        local ok, a, b, c = pcall(fn, ...)
        depth = depth - 1
        if not ok then error(a, 0) end
        if depth == 0 then pickScope = nil end          -- the set is being worked on: no longer "just picked"
        local _, nowName = ActiveSet()
        if a and before and nowName == setName then
            undo[#undo + 1] = { name = setName, set = before }
            if #undo > UNDO_STEPS then table.remove(undo, 1) end
        end
        return a, b, c
    end
end

local function CanUndo()
    -- A step for a set that is gone (deleted, renamed) cannot be taken.
    while #undo > 0 and not (sets and sets[undo[#undo].name]) do undo[#undo] = nil end
    return #undo > 0
end

local function Undo()
    if not CanUndo() then return false end
    local step = table.remove(undo)
    sets[step.name] = step.set
    CastChanged()
    return true
end

-- Keeps the set just picked to the current spec: the other specs go back to
-- the set they had.
local function ScopePick()
    if not PickScope() then return false end
    local specID = SpecState()
    cast.specSet[specID] = pickScope.new
    cast.set = pickScope.old
    pickScope = nil
    CastChanged()
    return true
end

-------------------------------------------------------------------------------
--  /clg cast
-------------------------------------------------------------------------------

local function Status()
    local set, name = ActiveSet()
    Print("own bindings are " .. (cast.enabled and "on" or "off") .. ". Set: "
        .. (name and (name .. " (" .. #set.bindings .. " keys)") or "none"))
    if not set then return end
    for _, binding in ipairs(set.bindings) do
        local compiled = CompileBinding(binding)
        local what = compiled.kind == "macro" and ("macro " .. compiled.macro)
            or compiled.kind == "macrotext" and compiled.text:gsub("\n", " | ")
            or "nothing (no rule can fire)"
        print("  " .. KeyName(binding.key) .. (binding.hover and (compiled.onTarget and " (anywhere, else target)" or compiled.zoom and " (anywhere, else zoom)" or " (anywhere)") or "") .. ": " .. what)
        for _, problem in ipairs(compiled.problems) do print("    ! " .. problem) end
    end
    if cast.enabled then
        for _, conflict in ipairs(Conflicts()) do print("  ! " .. conflict) end
        local provider = ClickLegendAPI.provider
        if provider and provider.Started() then
            local frames, bound = provider.Count()
            print("  " .. bound .. " of " .. frames .. " unit frames bound"
                .. (provider.Pending() and "; changes are waiting for combat to end." or "."))
        end
    end
end

-- Returns true when the legend has to be redrawn.
local function CastCommand(arg, rawArg)
    if not cast then return false end
    local sub = arg:match("^(%S*)")
    local rest = Text((rawArg or ""):match("^%s*%S+%s+(.*)$"))
    if sub == "on" and Blocked() then
        Print(Blocked())
    elseif sub == "on" or sub == "off" then
        cast.enabled = sub == "on"
        Print("own bindings " .. sub .. ".")
        if cast.enabled then
            for _, conflict in ipairs(Conflicts()) do Print(conflict) end
        end
        UpdateProvider()
        return true
    elseif sub == "sets" then
        local names = SetNames()
        Print(#names > 0 and ("sets: " .. tconcat(names, ", ")) or "no sets yet.")
    elseif sub == "set" then
        if rest and type(sets[rest]) == "table" and sets[rest].version == SET_VERSION then
            UseSet(rest)
            Print("this character now uses the set " .. rest .. ".")
            UpdateProvider()
            return true
        end
        Print("no usable set of that name. /clg cast sets lists them.")
    else
        Status()
    end
    return false
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.ACTION_NAME      = ACTION_NAME
ns.ACTION_ORDER     = ACTION_ORDER
ns.CONDITION_VALUES = CONDITION_VALUES
ns.ActionEntry      = ActionEntry
ns.ActiveSet        = ActiveSet
ns.AddKnownButton   = AddKnownButton
ns.AddSet           = AddSet
ns.BoundKeys        = BoundKeys
ns.ActiveSetName    = ActiveSetName
ns.CastCommand      = CastCommand
ns.CollectOwnLayers = CollectOwnLayers
ns.CastChanged      = CastChanged
ns.ClearSideKeys    = ClearSideKeys
ns.CastConflicts    = Conflicts
ns.CastCanUndo      = CanUndo
ns.CastEdit         = Edit
ns.CursorAction     = CursorAction
ns.CastPickScope    = PickScope
ns.CastScopePick    = ScopePick
ns.RECIPE_ORDER     = RECIPE_ORDER
ns.CastUndo         = Undo
ns.CastKeyName      = KeyName
ns.CastSettings     = CastSettings
ns.ConditionValue   = ConditionValue
ns.CompileBinding   = CompileBinding
ns.CastBlocked      = Blocked
ns.CastShadowed     = Shadowed
ns.CopyFromSource   = CopyFromSource
ns.CopySet          = CopySet
ns.CopySources      = CopySources
ns.DeleteSet        = DeleteSet
ns.ExportSet        = ExportSet
ns.ImportSet        = ImportSet
ns.RuleUnavailable  = function(rule) return Unavailable(rule.action) end
ns.InitCast         = InitCast
ns.KeyboardKeys     = KeyboardKeys
ns.KnownButtons     = KnownButtons
ns.NewSet           = NewSet
ns.PRE_ORDER        = PRE_ORDER
ns.PresetSpell      = PresetSpell
ns.RenameSet        = RenameSet
ns.SanitizeCast     = SanitizeCast
ns.SelectSet        = SelectSet
ns.SetCastDown      = SetCastDown
ns.SetCastEnabled   = SetCastEnabled
ns.SetCastFrames    = SetCastFrames
ns.SetSideKey       = SetSideKey
ns.SideKeys         = SideKeys
ns.SetNames         = SetNames
ns.SetSpecOnly      = SetSpecOnly
ns.SpecState        = SpecState
ns.SlotAction       = SlotAction
ns.UpdateProvider   = UpdateProvider
