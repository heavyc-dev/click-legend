-------------------------------------------------------------------------------
--  ClickLegend
--  Draws your click-cast bindings as a small icon grid: one entry per bound
--  key or button, an ally icon and an enemy icon. Hold Shift / Ctrl / Alt to
--  see that modifier's bindings. The bindings are read from whichever of
--  these has some, in this order (or from the one picked in the settings):
--    1. EllesmereUI HoverCast   2. Clique   3. VuhDo   4. HealBot
--    5. the game's own click casting (C_ClickBindings)
--  None of them is required, and none of them is changed.
--
--  Read-only: it never changes bindings and creates no secure frames, so it
--  cannot taint or block anything in combat.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local ipairs, pairs, type, tostring, tonumber, pcall = ipairs, pairs, type, tostring, tonumber, pcall
local tsort, tconcat = table.sort, table.concat
local floor, max, min = math.floor, math.max, math.min

local PREFIX = "|cff0cd29fClickLegend|r: "
local function Print(msg) print(PREFIX .. tostring(msg)) end

-------------------------------------------------------------------------------
--  State the files share (the settings table, the bindings being shown, the
--  name of their source). Each file keeps its own local copy and is told when
--  the value changes, so a read stays a plain local read.
-------------------------------------------------------------------------------
local subscribers = {}

function ns.Subscribe(what, fn)
    local list = subscribers[what]
    if not list then list = {}; subscribers[what] = list end
    list[#list + 1] = fn
end

function ns.Publish(what, value)
    local list = subscribers[what]
    if not list then return end
    for i = 1, #list do list[i](value) end
end

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
    visibility = "always",      -- always | group | combat | hover
    source = "auto",            -- auto | eui | clique | vuhdo | healbot | blizzard
    layers = "held",            -- held | all: which modifier layers are drawn
    hoverDim = true,            -- dim the row that does not apply to the hovered unit
    flagMissing = true,         -- grey out bindings whose spell or macro is gone
    anchor = "screen",          -- screen | party
    anchorSide = "below",       -- above | below | left | right
    anchorGap = 6,
    allyR = 0.05, allyG = 0.82, allyB = 0.62,
    enemyR = 0.90, enemyG = 0.25, enemyB = 0.25,
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
    allyR = { 0, 1 }, allyG = { 0, 1 }, allyB = { 0, 1 },
    enemyR = { 0, 1 }, enemyG = { 0, 1 }, enemyB = { 0, 1 },
    anchorGap = { 0, 60, true },
}
local CHOICES = {
    layout = { horizontal = true, vertical = true },
    rows = { both = true, ally = true, enemy = true },
    sort = { mouse = true, keyboard = true, alpha = true, custom = true },
    visibility = { always = true, group = true, combat = true, hover = true },
    layers = { held = true, all = true },
    source = { auto = true, eui = true, clique = true, vuhdo = true, healbot = true, blizzard = true },
    anchor = { screen = true, party = true },
    anchorSide = { above = true, below = true, left = true, right = true },
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

-- Settings are shared by every character unless this one has asked for its
-- own (ClickLegendCharDB.enabled); then they live in the per-character table.
local function InitDB()
    if type(ClickLegendDB) ~= "table" then ClickLegendDB = {} end
    if type(ClickLegendCharDB) ~= "table" then ClickLegendCharDB = {} end
    local char = ClickLegendCharDB
    if char.enabled == true then
        if type(char.settings) ~= "table" then char.settings = {} end
        db = char.settings
    else
        db = ClickLegendDB
    end
    ns.Publish("db", db)
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
--  Used by the other files
-------------------------------------------------------------------------------
ns.CHOICES     = CHOICES
ns.Clamp       = Clamp
ns.DEFAULTS    = DEFAULTS
ns.DefaultFor  = DefaultFor
ns.HeldMods    = HeldMods
ns.InitDB      = InitDB
ns.LongKey     = LongKey
ns.ModsLong    = ModsLong
ns.MouseRank   = MouseRank
ns.OrderKeys   = OrderKeys
ns.OrderKeysBy = OrderKeysBy
ns.POINTS      = POINTS
ns.ParseKey    = ParseKey
ns.Print       = Print
ns.Report      = Report
ns.Safe        = Safe
ns.SanitizeDB  = SanitizeDB
ns.ShortKey    = ShortKey
