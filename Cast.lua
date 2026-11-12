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
--  binding = { key = "SHIFT-BUTTON1", rules = { rule, ... } }
--  rule    = { when = { reaction, dead, combat, form, pet, mod }, action = action }
--  action  = { type = "spell", name, spellID, pinned }   pinned: cast this rank
--          | { type = "item", name, itemID }
--          | { type = "macro", name }
--          | { type = "target" | "focus" | "assist" | "menu" | "trinket1" | "trinket2" }
--  The first rule whose conditions hold is the one that fires.
--
--  ClickLegendCharDB.cast = { enabled, set = name, specSet = { [specID] = name },
--                             frames = { blizzard, registered } }
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

local SET_VERSION = 1
local MACRO_LIMIT = 255             -- the longest macro text the game runs
local NAME_LIMIT = 40               -- longest set name
local PROXY_LENGTH = 24             -- room kept for a helper button's name

local ACTION_TYPES = {
    spell = true, item = true, macro = true, target = true, focus = true,
    assist = true, menu = true, trinket1 = true, trinket2 = true,
}
local ACTION_NAME = {
    target = TYPE_NAME.target, menu = TYPE_NAME.menu, focus = "Set Focus", assist = "Assist",
    trinket1 = TYPE_NAME.trinket1, trinket2 = TYPE_NAME.trinket2,
}
local REACTIONS = { help = true, harm = true }
local RULE_MODS = { shift = true, ctrl = true, alt = true }
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

local function CleanAction(a)
    if type(a) ~= "table" or not ACTION_TYPES[a.type] then return nil end
    local t = a.type
    if t == "spell" then
        local name, id = Text(a.name), WholeNumber(a.spellID, 1, 2 ^ 31)
        if not (name or id) then return nil end
        return { type = t, name = name, spellID = id, pinned = (id and a.pinned == true) or nil }
    elseif t == "item" then
        local name, id = Text(a.name), WholeNumber(a.itemID, 1, 2 ^ 31)
        if not (name or id) then return nil end
        return { type = t, name = name, itemID = id }
    elseif t == "macro" then
        local name = Text(a.name)
        if not name then return nil end
        return { type = t, name = name }
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
    return out
end

local function CleanBinding(b)
    if type(b) ~= "table" or type(b.key) ~= "string" or type(b.rules) ~= "table" then return nil end
    local mods, key = ParseKey(b.key)
    if key == "" then return nil end
    local rules = {}
    for _, r in ipairs(b.rules) do
        local action = type(r) == "table" and CleanAction(r.action)
        if action then rules[#rules + 1] = { when = CleanWhen(r.when), action = action } end
    end
    if #rules == 0 then return nil end
    return { key = mods .. key, rules = rules }
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

local function SanitizeCast()
    for name, set in pairs(sets) do
        if type(name) ~= "string" or name == "" or #name > NAME_LIMIT or type(set) ~= "table" then
            sets[name] = nil
        elseif set.version == SET_VERSION then
            CleanSet(set)
        end
    end
    cast.enabled = cast.enabled == true
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
    return (specID and cast.specSet[specID]) or cast.set
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
        local fields = { Escape(binding.key) }
        for _, rule in ipairs(binding.rules) do
            local words = {}
            for _, field in ipairs({ "reaction", "dead", "combat", "pet", "mod" }) do
                local word = WHEN_WORD[field][rule.when[field]]
                if word then words[#words + 1] = word end
            end
            if rule.when.form then words[#words + 1] = "form" .. rule.when.form end
            local a = rule.action
            fields[#fields + 1] = tconcat(words, ",") .. "~" .. tconcat({
                a.type, Escape(a.name or ""), tostring(a.spellID or a.itemID or ""), a.pinned and "p" or "",
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
                    spellID = kind == "spell" and number or nil, itemID = kind == "item" and number or nil,
                } }
            end
        end
        if fields[1] then bindings[#bindings + 1] = { key = Unescape(fields[1]), rules = rules } end
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

-- "[@mouseover,help,dead]": the unit under the cursor, and the rule's
-- conditions in a fixed order. "exists" is only spelled out when nothing else
-- already implies it; macro text is short of room.
local function Clause(when)
    local parts = { "@mouseover" }
    if not when.reaction and when.dead == nil then parts[#parts + 1] = "exists" end
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
local NEEDS_NAME = { spell = true, item = true, macro = true }
local function Incomplete(action)
    return NEEDS_NAME[action.type] and not (action.name or action.spellID or action.itemID) or false
end

-- A spell this character does not have. Such a rule is skipped, so the next
-- rule on the key takes over: that is how "this spell, or else that one" works.
-- (Left in, the game would pick the rule and then cast nothing.) A spell saved
-- by name only is one the character has when the game can find it by that
-- name: a name lookup only ever finds spells in the spellbook.
local function Unavailable(action)
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

-- Turns a binding into what has to be put on a frame.
--   kind = "none"       nothing can fire (every rule skipped)
--        = "macro"      run the player's macro `macro`
--        = "macrotext"  run `text`. "{menu}" stands for the frame's menu
--                       helper and "{rank:ID}" for the helper that casts that
--                       exact spell rank; Provider.lua fills them in.
--   length, tooLong     size of the text once the helpers are named
--   skipped             rules left out because the spell is not known
--   problems            what the editor should tell the player
local function CompileBinding(binding)
    local out = { kind = "none", skipped = 0, problems = {} }
    local live = {}
    local unfinished = false
    for _, rule in ipairs(binding.rules) do
        if Incomplete(rule.action) then
            unfinished = true
        elseif Unavailable(rule.action) then
            out.skipped = out.skipped + 1
        else
            live[#live + 1] = rule
        end
    end
    if unfinished then out.problems[#out.problems + 1] = "A rule has nothing chosen yet." end
    if #live == 0 then return out end

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
    local function OwnLine(text)
        CloseCast()
        if #earlier > 0 then lines[#lines + 1] = "/stopmacro " .. tconcat(earlier) end
        lines[#lines + 1] = text
    end
    local seen = {}
    for i, rule in ipairs(live) do
        local action, clause = rule.action, Clause(rule.when)
        local token = CastToken(action)
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
            if action.type ~= "spell" then castVerb = "/use" end
            castParts[#castParts + 1] = clause .. " " .. token
        elseif action.type == "spell" then
            OwnLine("/click " .. clause .. " {rank:" .. action.spellID .. "}")
        elseif action.type == "menu" then
            OwnLine("/click " .. clause .. " {menu}")
        elseif COMMAND[action.type] then
            OwnLine(COMMAND[action.type] .. " " .. clause)
        elseif not seen[clause] then
            out.problems[#out.problems + 1] = "A macro can only be the single rule of a key, with no conditions."
        end
        if not seen[clause] then earlier[#earlier + 1] = clause end
        seen[clause] = true
        if not HasConditions(rule.when) then
            if i < #live then
                out.problems[#out.problems + 1] = (#live - i) .. " rule(s) after an unconditional rule can never fire."
            end
            break
        end
    end
    CloseCast()
    if #lines == 0 then return out end

    out.kind, out.text = "macrotext", tconcat(lines, "\n")
    out.length = #(out.text:gsub("{[^}]*}", ("x"):rep(PROXY_LENGTH)))
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

local function ActionEntry(action)
    local t = action.type
    if t == "spell" then
        local id = ActionSpellID(action)
        local name = action.name or (id and SpellName(id)) or "Unknown Spell"
        return Entry(name, SpellTexture(id) or SpellTexture(action.name), id, Unavailable(action))
    elseif t == "item" then
        return Entry(action.name or "Item", ItemIcon(action))
    elseif t == "macro" then
        local found, tex = MacroInfo(action.name)
        return Entry(action.name, tex or TYPE_ICON.macro, nil, GetMacroInfo ~= nil and found == nil)
    elseif t == "trinket1" or t == "trinket2" then
        return Entry(ACTION_NAME[t], InventoryTexture(t == "trinket1" and 13 or 14))
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
    local dead = now.hoverSide == side and now.hoverDead or false
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
    for _, rule in ipairs(binding.rules) do
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
            if rule then PutEntry(layers, mods, key, side, ActionEntry(rule.action)) end
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

local function Conflicts()
    local found = {}
    local eui = type(EllesmereUIDB) == "table" and EllesmereUIDB.clickCast
    if type(eui) == "table" and eui.enabled then
        found[#found + 1] = "EllesmereUI HoverCast is on and binds the same frames. Use one or the other."
    end
    if type(Clique) == "table" then
        found[#found + 1] = "Clique is loaded and binds the same frames. Use one or the other."
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
    Settings = function() return cast end,
}

-- Tells the provider to bring the frames in line with the settings. The
-- provider ignores this until a character has had its bindings on.
local function UpdateProvider()
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

local function SetCastFrames(group, on)
    if not cast or cast.frames[group] == nil then return end
    cast.frames[group] = on and true or false
    CastChanged()
end

local function SelectSet(name)
    local set = sets and sets[name]
    if type(set) ~= "table" or set.version ~= SET_VERSION then return false end
    cast.set = name
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
}
local CONDITION_STORED = {          -- editor value -> what is saved
    alive = false, dead = true, ["in"] = true, out = false, pet = true, nopet = false,
}
local ACTION_ORDER = { "spell", "item", "macro", "target", "focus", "assist", "menu", "trinket1", "trinket2" }

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
    set.bindings[#set.bindings + 1] = { key = key, rules = { { when = { reaction = "help" }, action = { type = "spell" } } } }
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

function Edit.RemoveBinding(bindingIndex)
    local set, binding = Target(bindingIndex)
    if not binding then return false, "No such key." end
    table.remove(set.bindings, bindingIndex)
    CastChanged()
    return true
end

-- A new rule starts as the side the key does not cover yet.
function Edit.AddRule(bindingIndex)
    local _, binding = Target(bindingIndex)
    if not binding then return false, "No such key." end
    local has = {}
    for _, rule in ipairs(binding.rules) do has[rule.when.reaction or "any"] = true end
    local reaction = (not has.help and "help") or (not has.harm and "harm") or nil
    binding.rules[#binding.rules + 1] = { when = { reaction = reaction }, action = { type = "spell" } }
    CastChanged()
    return true, #binding.rules
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
    if value == false then
        rule.when[field] = nil
    elseif CONDITION_STORED[value] ~= nil then
        rule.when[field] = CONDITION_STORED[value]
    else
        rule.when[field] = value
    end
    CastChanged()
    return true
end

-- What a rule does, set to a kind (nothing chosen yet for the kinds that
-- need a name) or to a whole action picked from a list.
function Edit.SetActionType(bindingIndex, ruleIndex, kind)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    if not (rule and ACTION_TYPES[kind]) then return false end
    if rule.action.type ~= kind then
        rule.action = { type = kind }
        CastChanged()
    end
    return true
end

function Edit.SetAction(bindingIndex, ruleIndex, action)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    local clean = rule and CleanAction(action)
    if not clean then return false end
    rule.action = clean
    CastChanged()
    return true
end

-- A spell, item or macro dropped from the spellbook, bags or macro window:
-- what GetCursorInfo() returned. A dropped spell keeps its id, so that exact
-- rank can be pinned.
function Edit.SetActionFromCursor(bindingIndex, ruleIndex, kind, a, b, c)
    local _, _, rule = Target(bindingIndex, ruleIndex)
    if not rule then return false end
    if kind == "spell" then
        local id = WholeNumber(c, 1, 2 ^ 31) or WholeNumber(a, 1, 2 ^ 31)
        if not id then return false end
        rule.action = { type = "spell", spellID = id, name = SpellName(id) }
    elseif kind == "item" then
        local id = WholeNumber(a, 1, 2 ^ 31)
        if not id then return false end
        local name
        if C_Item and C_Item.GetItemNameByID then
            local ok, n = pcall(C_Item.GetItemNameByID, id)
            name = ok and Text(n) or nil
        end
        rule.action = { type = "item", itemID = id, name = name }
    elseif kind == "macro" then
        local name = MacroInfo(a)
        if not Text(name) then return false end
        rule.action = { type = "macro", name = name }
    else
        return false
    end
    CastChanged()
    return true
end

-------------------------------------------------------------------------------
--  The simple view of a key, for the guided setup: three slots.
--    ally   what it does on a living ally
--    dead   what it does on a dead ally (nothing: same as a living one)
--    enemy  what it does on an enemy
--  A slot is the rule, or chain of fallback rules, with exactly that
--  condition. Rules with other conditions (combat, form, pet, modifier) are
--  not part of any slot and are left as they are.
-------------------------------------------------------------------------------
local SLOT_WHEN = {
    ally = { reaction = "help" }, dead = { reaction = "help", dead = true }, enemy = { reaction = "harm" },
}

local function Plain(when)             -- no combat, form, pet or modifier condition
    return when.combat == nil and when.form == nil and when.pet == nil and when.mod == nil
end

local function InSlot(when, slot)
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
        local anyone = slot ~= "dead" and when.reaction == nil and when.dead == nil and Plain(when)
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
        -- Dead-ally rules go first, then the ally rule, the enemy rule last.
        local at = #rules + 1
        if slot ~= "enemy" then
            at = 1
            for i, rule in ipairs(rules) do
                local w = rule.when
                if w.reaction == "help" and (w.dead == true or (slot == "dead" and false)) then at = i + 1 end
            end
            if slot == "dead" then at = 1 end
        end
        table.insert(rules, at, { when = CopyTable(SLOT_WHEN[slot]), action = clean })
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
        print("  " .. KeyName(binding.key) .. ": " .. what)
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
    if sub == "on" or sub == "off" then
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
            cast.set = rest
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
ns.ActiveSetName    = ActiveSetName
ns.CastCommand      = CastCommand
ns.CollectOwnLayers = CollectOwnLayers
ns.CastChanged      = CastChanged
ns.CastConflicts    = Conflicts
ns.CastEdit         = Edit
ns.CastKeyName      = KeyName
ns.CastSettings     = CastSettings
ns.ConditionValue   = ConditionValue
ns.CompileBinding   = CompileBinding
ns.CopySet          = CopySet
ns.DeleteSet        = DeleteSet
ns.ExportSet        = ExportSet
ns.ImportSet        = ImportSet
ns.RuleUnavailable  = function(rule) return Unavailable(rule.action) end
ns.InitCast         = InitCast
ns.KnownButtons     = KnownButtons
ns.NewSet           = NewSet
ns.RenameSet        = RenameSet
ns.SanitizeCast     = SanitizeCast
ns.SelectSet        = SelectSet
ns.SetCastEnabled   = SetCastEnabled
ns.SetCastFrames    = SetCastFrames
ns.SetNames         = SetNames
ns.SlotAction       = SlotAction
ns.UpdateProvider   = UpdateProvider
