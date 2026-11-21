-------------------------------------------------------------------------------
--  ClickLegend - Options.lua
--  The option list both settings screens are built from, presets, settings
--  as text, and the EllesmereUI settings pages.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tostring, tonumber, pcall = ipairs, pairs, type, tostring, tonumber, pcall
local tsort, tconcat = table.sort, table.concat
local floor = math.floor

local db
ns.Subscribe("db", function(value) db = value end)

local Clamp, DEFAULTS, DefaultFor, InitDB, LongKey =
    ns.Clamp, ns.DEFAULTS, ns.DefaultFor, ns.InitDB, ns.LongKey
local SanitizeDB, ShortKey, AllBoundKeys, ApplyPosition =
    ns.SanitizeDB, ns.ShortKey, ns.AllBoundKeys, ns.ApplyPosition
local Refresh =
    ns.Refresh

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
local SetCharacterProfile       -- defined below the option helpers
local RebuildSettingsPages      -- defined with the settings page

local OPTIONS = {
    Display = {
        { header = "LEGEND" },
        { kind = "toggle", key = "hidden", invert = true, text = "Show the legend" },
        { kind = "toggle", key = "locked", text = "Lock position",
          tip = "Unlock to drag the legend, then lock it again. While unlocked, hovering an icon names its binding." },
        { kind = "choice", key = "visibility", text = "Visible",
          values = { always = "Always", group = "In a group", combat = "In combat",
                     hover = "Hovering a unit frame" },
          order = { "always", "group", "combat", "hover" } },
        { kind = "choice", key = "layers", text = "Shift, Ctrl and Alt keys",
          values = { held = "Show while held", all = "Always show" },
          order = { "held", "all" },
          tip = "Show while held: hold Shift, Ctrl or Alt to see the keys bound with it. "
              .. "Always show stacks them under the plain ones, so nothing has to be held to read them." },
        { kind = "toggle", key = "hideBasics", text = "Hide the plain Target and Menu clicks",
          tip = "Leaves the left click that targets and the right click that opens the menu out of the legend "
              .. "and the tooltip. They keep working; only the display is shorter." },
        { header = "LAYOUT" },
        { kind = "choice", key = "layout", text = "Layout",
          values = { horizontal = "Horizontal", vertical = "Vertical", mouse = "Mouse picture" },
          order = { "horizontal", "vertical", "mouse" },
          tip = "Horizontal runs the keys left to right; vertical runs them top to bottom. "
              .. "Mouse picture draws a mouse with each button's spells beside it; keyboard keys are listed under it." },
        { kind = "range", key = "mouseSize", text = "Mouse picture size", lo = 96, hi = 256, step = 8,
          when = function() return db.layout == "mouse" end },
        { kind = "choice", key = "rows", text = "Show",
          values = { both = "Ally and enemy", ally = "Ally only", enemy = "Enemy only" },
          order = { "both", "ally", "enemy" } },
        { kind = "range", key = "perLine", text = "Keys per line", lo = 2, hi = 24, step = 1,
          when = function() return db.layout ~= "mouse" end },
        { header = "ICONS" },
        { kind = "toggle", key = "hideMissing", text = "Hide spells you have not learned",
          tip = "A key whose spell you have not learned yet, or whose macro is gone, is left out of the legend "
              .. "and the tooltip until it can do something. A starter set has keys for every level, so this "
              .. "keeps the legend to what you can cast. Off: such a key is shown greyed out." },
        -- One switch for two settings (`/clg missing` and `/clg usable` still set them apart).
        { kind = "toggle", text = "Mark spells that cannot be cast", refresh = true,
          get = function() return db.flagMissing or db.flagUnusable end,
          set = function(v) db.flagMissing, db.flagUnusable = v, v end,
          tip = "A spell you have not learned, or a macro that is gone, is greyed out when it is shown at all "
              .. "(see the switch above). A cooldown sweeps over its icon, "
              .. "a spell you lack the mana for turns blue, and one that cannot reach the unit under the cursor "
              .. "turns orange. The three colors are on the Look tab." },
        { kind = "toggle", key = "flash", text = "Flash an icon when its spell is cast",
          tip = "A short flash on the legend each time one of the shown spells goes off." },
        { header = "ACTION BARS" },
        { kind = "choice", key = "barMarks", text = "Mark spells on the action bars",
          values = { off = "No", above = "Above the button", on = "On the button" }, order = { "off", "above", "on" },
          tip = "A small mouse with the button lit, on each action button whose spell a click with no modifier "
              .. "also casts. Only where the spell is the same: Shift, Ctrl and Alt clicks are not marked." },
        { header = "WHILE HOVERING A UNIT" },
        -- One row for two settings (`hoverDim` and `offStyle`).
        { kind = "choice", text = "Spells that do not apply", refresh = true,
          values = { leave = "Leave them", dim = "Dim them", hide = "Hide them" }, order = { "leave", "dim", "hide" },
          get = function() return db.hoverDim and db.offStyle or "leave" end,
          set = function(v)
              if v == "leave" then db.hoverDim = false else db.hoverDim, db.offStyle = true, v end
          end,
          tip = "With the cursor on a friendly unit the enemy spells do not apply, and the other way round. "
              .. "Dim them fades them. Hide them takes the other row away, and leaves an empty place for a spell "
              .. "that cannot reach that unit, so the legend shows only what will work on it." },
        { kind = "toggle", key = "hideNPC", text = "Hide over friendly NPCs",
          tip = "No legend while the cursor is on a vendor, a quest giver, a trainer or another friendly NPC in the "
              .. "world. It stays for friendly players, their pets, enemies and every unit frame." },
        { header = "POSITION" },
        { kind = "choice", key = "anchor", text = "Attach to",
          values = { screen = "Nothing (drag it)", party = "Party frames", cursor = "The cursor" },
          order = { "screen", "party", "cursor" },
          tip = "Party frames: the legend follows them, and uses the dragged position when none are on screen. "
              .. "The cursor: it stays beside the pointer; with Visible set to Hovering a unit frame it only "
              .. "appears where you are about to click." },
        { kind = "choice", key = "anchorSide", text = "Placement",
          values = { above = "Above", below = "Below", left = "Left", right = "Right" },
          order = { "above", "below", "left", "right" },
          when = function() return db.anchor ~= "screen" end,
          tip = "Where the legend sits beside the party frames, or beside the cursor." },
        { kind = "range", key = "anchorGap", text = "Gap", lo = 0, hi = 60, step = 1,
          when = function() return db.anchor ~= "screen" end },
        { header = "TOOLTIP" },
        { kind = "toggle", key = "tooltip", text = "Show bindings in unit tooltips",
          tip = "Hovering a friendly unit frame lists your ally spells; an enemy frame lists your enemy spells." },
        { kind = "toggle", key = "tooltipWorld", text = "Also on units in the world",
          when = function() return db.tooltip end,
          tip = "Adds the bindings to tooltips of units you hover in the world, not only unit frames." },
        { header = "SETTINGS" },
        { kind = "choice", key = "source", text = "Bindings from",
          values = { auto = "Automatic", own = "ClickLegend", eui = "EllesmereUI HoverCast", clique = "Clique",
                     vuhdo = "VuhDo", healbot = "HealBot", blizzard = "Game click casting" },
          order = { "auto", "own", "eui", "clique", "vuhdo", "healbot", "blizzard" },
          tip = "Whose bindings the legend shows. Automatic uses the first of these that has any, in this order. "
              .. "Pick one when you have more than one set up." },
        { kind = "toggle", key = "minimap", text = "Minimap button",
          tip = "A button on the minimap: click for the settings, right click for the guided setup, drag to move it." },
        { kind = "toggle", text = "Separate legend settings for this character",
          tip = "Off: every character shares the legend's settings. On: this character keeps its own, starting as a copy. "
              .. "Your bindings are not part of this: binding sets are always shared.",
          get = function() return type(ClickLegendCharDB) == "table" and ClickLegendCharDB.enabled == true end,
          set = function(v) SetCharacterProfile(v) end },
    },
    Look = {
        { header = "SIZE" },
        { kind = "range", key = "iconSize", text = "Icon size", lo = 16, hi = 64, step = 1 },
        { kind = "range", key = "spacing", text = "Icon spacing", lo = 0, hi = 10, step = 1 },
        { kind = "choice", key = "iconStyle", text = "Icon frame",
          values = { button = "Action button", flat = "Flat" },
          order = { "button", "flat" },
          tip = "Action button: the action bar's own frame around each icon. Flat: a thin black edge." },
        { kind = "range", key = "scale", text = "Scale", lo = 0.5, hi = 2, step = 0.05,
          tip = "Shrinks or grows the whole legend, labels included." },
        { kind = "range", key = "alpha", text = "Opacity", lo = 0.1, hi = 1, step = 0.05 },
        { header = "LABELS" },
        { kind = "toggle", key = "labels", text = "Key labels" },
        { kind = "choice", key = "labelStyle", text = "Label style",
          values = { text = "Text", icon = "Icons", corner = "On the icon" }, order = { "text", "icon", "corner" },
          when = function() return db.labels end,
          tip = "Icons draw a small picture of your mouse with the bound button lit, and a keycap for keyboard keys. "
              .. "On the icon writes the key in the corner of the spell icon, which makes the legend smaller." },
        { kind = "range", key = "labelSize", text = "Label size", lo = 7, hi = 14, step = 1,
          when = function() return db.labels end },
        { kind = "choice", key = "mousePic", text = "Which mouse",
          values = { a = "Rounded", b = "Angular", c = "Simple", d = "Twelve side buttons" },
          order = { "a", "b", "c", "d" },
          tip = "The mouse that is drawn: small, above each spell, with the bound button lit (label style Icons), "
              .. "and large in the Mouse picture layout. For the one with twelve side buttons, the guided setup "
              .. "asks you to press each of them, so that every spell lands on the right one." },
        { kind = "toggle", key = "bars", text = "Ally / enemy color bars" },
        { kind = "toggle", key = "frameTint", text = "Color the button frames by side",
          tip = "With the Action button icon frame: each spell's frame takes the ally or enemy color, "
              .. "the way the game marks an equipped item's button.",
          when = function() return db.iconStyle == "button" end },
        { header = "COLORS" },
        { kind = "color", prefix = "ally", text = "Ally color" },
        { kind = "color", prefix = "enemy", text = "Enemy color" },
        { kind = "color", prefix = "far", text = "Out of range", when = function() return db.flagUnusable end },
        { kind = "color", prefix = "mana", text = "Not enough mana", when = function() return db.flagUnusable end },
        { kind = "color", prefix = "cool", text = "On cooldown", when = function() return db.flagUnusable end },
        { header = "BACKGROUND AND BORDER" },
        { kind = "toggle", key = "background", text = "Show background" },
        { kind = "color", prefix = "bg", alpha = true, text = "Background color and opacity",
          when = function() return db.background end },
        { kind = "choice", key = "border", text = "Border",
          values = { none = "None", tooltip = "Thin, like a tooltip", dialog = "Gold, like a dialog" },
          order = { "none", "tooltip", "dialog" },
          tip = "A frame of the game's own around the legend. With the background on, it reads as one of the "
              .. "game's own panels." },
        { kind = "range", key = "bgPadding", text = "Padding", lo = 0, hi = 20, step = 1,
          when = function() return db.background or db.border ~= "none" end },
    },
    Order = {
        { header = "ORDER" },
        { kind = "choice", key = "sort", text = "Sort keys by",
          values = { mouse = "Mouse buttons first", keyboard = "Keyboard keys first",
                     alpha = "Alphabetical", custom = "Custom" },
          order = { "mouse", "keyboard", "alpha", "custom" },
          tip = "Custom uses the positions below." },
        { kind = "toggle", key = "reverse", text = "Reverse the order" },
        { kind = "toggle", key = "enemyFirst", text = "Enemy spells first",
          tip = "Puts the enemy spells before the ally spells." },
    },
}
local PAGES = { "Display", "Look", "Order" }

-- The Share page: presets, and import / export of the settings as text. The
-- addon's own window builds it by hand (it needs a text box); the EllesmereUI
-- panel gets the preset picker and a button that opens that window.
local function OpenShareTab() ns.OpenShareTab() end       -- Window.lua
local ApplyPreset               -- defined with the share functions
local PRESETS = {
    default = { name = "Default", set = {
        layout = "vertical", rows = "both", layers = "held", iconSize = 28, spacing = 2, perLine = 12,
        scale = 1, labels = true, labelStyle = "icon", labelSize = 9, bars = true, background = true,
        border = "tooltip" } },
    compact = { name = "Compact", set = {
        layout = "horizontal", rows = "both", layers = "held", iconSize = 20, spacing = 1, perLine = 12,
        labels = false, bars = true, background = false } },
    sidebar = { name = "Sidebar", set = {
        layout = "vertical", rows = "both", layers = "held", iconSize = 24, spacing = 2, perLine = 12,
        labels = true, labelStyle = "icon", labelSize = 9, bars = true, background = false } },
    full = { name = "Everything", set = {
        layout = "horizontal", rows = "both", layers = "all", iconSize = 26, spacing = 2, perLine = 12,
        labels = true, labelStyle = "icon", labelSize = 9, bars = true, background = true } },
    -- Out of the way: beside the cursor, only while it is on a unit frame,
    -- and only what works on that unit.
    minimal = { name = "Minimal", set = {
        layout = "horizontal", rows = "both", layers = "held", iconSize = 22, spacing = 1, perLine = 12,
        labels = true, labelStyle = "corner", labelSize = 8, bars = false, background = false,
        anchor = "cursor", anchorSide = "right", anchorGap = 6, visibility = "hover",
        hoverDim = true, offStyle = "hide" } },
}
local PRESET_ORDER = { "default", "compact", "sidebar", "full", "minimal" }
local PRESET_NOTE = "A preset changes the layout only; colors and order stay as they are. Minimal also puts the "
    .. "legend beside the cursor and shows it only on a unit frame; any other preset puts it back."

-- Look starts with the ready-made styles: they set most of what follows.
do
    local values, order = { none = "Pick one..." }, { "none" }
    for _, id in ipairs(PRESET_ORDER) do
        values[id] = PRESETS[id].name
        order[#order + 1] = id
    end
    table.insert(OPTIONS.Look, 1, { header = "STYLE" })
    table.insert(OPTIONS.Look, 2, {
        kind = "choice", text = "Start from a style", values = values, order = order, tip = PRESET_NOTE,
        get = function() return "none" end,
        set = function(v) if v ~= "none" then ns.ApplyPreset(v) end end,
    })
end

OPTIONS.Share = {
    { header = "PRESETS" },
    { kind = "preset", text = "Apply a layout preset", tip = PRESET_NOTE },
    { header = "IMPORT / EXPORT" },
    { kind = "button", text = "Open import and export", click = function() OpenShareTab() end },
}
-- The Bindings page: ClickLegend's own click casting. The keys and their
-- rules are edited in the addon's own window; the EllesmereUI panel gets the
-- switches and a button that opens it.
local function OpenBindingsTab() ns.OpenBindingsTab() end     -- Window.lua
local function CastOn() local s = ns.CastSettings(); return s and s.enabled end
local function CastFrames(group) local s = ns.CastSettings(); return s and s.frames[group] end

OPTIONS.Bindings = {
    { header = "CLICK CASTING" },
    { kind = "toggle", text = "Click casting",
      tip = "On: clicks and keys on unit frames cast the bindings you set up in ClickLegend. "
          .. "Off: ClickLegend only shows bindings and changes nothing.",
      get = CastOn, set = function(v) ns.SetCastEnabled(v) end },
    { kind = "toggle", text = "On the game's unit frames",
      get = function() return CastFrames("blizzard") end, set = function(v) ns.SetCastFrames("blizzard", v) end },
    { kind = "toggle", text = "On other addons' unit frames",
      tip = "Unit frames from other addons that offer themselves for click casting, EllesmereUI's among them.",
      get = function() return CastFrames("registered") end, set = function(v) ns.SetCastFrames("registered", v) end },
    { header = "KEYS" },
    { kind = "button", text = "Open the binding editor", click = function() OpenBindingsTab() end },
}
local PANEL_PAGES = { "Bindings", "Display", "Look", "Order", "Share" }

local function RefreshWindow() ns.RefreshWindow() end     -- Window.lua

local function OptGet(o)
    if o.get and o.kind == "choice" then return o.get() end
    if o.get then return o.get() and true or false end
    if o.kind == "toggle" then return (not o.invert) == (db[o.key] and true or false) end
    return db[o.key]
end

-- Every change, from either settings surface or a slash command, lands here.
local function OptSet(o, v)
    if not db then return end
    if o.set then
        -- An option that manages its own state; `refresh` when it writes settings the legend draws from.
        if o.kind == "choice" then
            if not o.values[v] then return end
            o.set(v)
        else
            o.set(v and true or false)
        end
        if not o.refresh then return end
    elseif o.kind == "toggle" then
        db[o.key] = (not o.invert) == (v and true or false)
    elseif o.kind == "choice" then
        if not o.values[v] then return end
        db[o.key] = v
    elseif o.kind == "range" then
        if type(v) ~= "number" then return end
        db[o.key] = floor(v / o.step + 0.5) * o.step      -- no drift from repeated steps
    end
    SanitizeDB()
    ApplyPosition()
    Refresh(true)
    RefreshWindow()
end

-- A color option stores <prefix>R, G, B and, for the background, A.
local function GetColor(prefix)
    return db[prefix .. "R"], db[prefix .. "G"], db[prefix .. "B"], db[prefix .. "A"] or 1
end

local function SetColor(prefix, r, g, b, a)
    if not db then return end
    if type(r) == "number" then db[prefix .. "R"] = r end
    if type(g) == "number" then db[prefix .. "G"] = g end
    if type(b) == "number" then db[prefix .. "B"] = b end
    if type(a) == "number" and DEFAULTS[prefix .. "A"] then db[prefix .. "A"] = a end
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

-- Switches between shared settings and this character's own. Turning it on
-- starts the character from a copy of the shared settings.
SetCharacterProfile = function(on)
    local char = ClickLegendCharDB
    if type(char) ~= "table" then return end
    if on and char.enabled ~= true then
        local copy = {}
        for k, v in pairs(ClickLegendDB) do
            if type(v) == "table" then
                copy[k] = {}
                for i, item in ipairs(v) do copy[k][i] = item end
            else
                copy[k] = v
            end
        end
        char.settings = copy
    end
    char.enabled = on and true or false
    InitDB()
    ApplyPosition()
    ns.Invalidate()
    Refresh(true)
    RefreshWindow()
    RebuildSettingsPages()
end

-------------------------------------------------------------------------------
--  Presets, and settings as text. The text is plain "key=value" pairs, e.g.
--  CL1;alpha=1;iconSize=28;...  so it can be read, and a newer or older
--  version just skips the keys it does not know.
-------------------------------------------------------------------------------
local SHARE_TAG = "CL1"

local function AfterBulkChange()
    SanitizeDB()
    ApplyPosition()
    Refresh(true)
    RefreshWindow()
    if C_Timer and C_Timer.After then
        C_Timer.After(0, RebuildSettingsPages)      -- not from inside a widget's own callback
    else
        RebuildSettingsPages()
    end
end

ApplyPreset = function(id)
    local preset = PRESETS[id]
    if not (db and preset) then return false end
    -- Minimal is the one preset that moves the legend to the cursor and shows
    -- it only on a unit frame. Leaving it for another puts those back, or the
    -- legend would seem to have gone.
    if id ~= "minimal" and db.anchor == "cursor" then
        db.anchor, db.visibility, db.offStyle = "screen", "always", "dim"
    end
    for key, value in pairs(preset.set) do db[key] = value end
    AfterBulkChange()
    return true
end

-- Anything but letters, digits, "_", "-" and "." is written as %XX, so a key
-- name such as ";" or "," cannot break the format.
local function Escape(text)
    return (tostring(text):gsub("[^%w_%-%.]", function(c) return ("%%%02X"):format(c:byte()) end))
end
local function Unescape(text)
    return (text:gsub("%%(%x%x)", function(hex) return string.char(tonumber(hex, 16)) end))
end

local function ExportSettings()
    local keys = {}
    for key in pairs(DEFAULTS) do keys[#keys + 1] = key end
    tsort(keys)
    local parts = { SHARE_TAG }
    for _, key in ipairs(keys) do
        local value, kind = db[key], type(DEFAULTS[key])
        local text
        if kind == "boolean" then
            text = value and "1" or "0"
        elseif kind == "number" then
            text = (("%.4f"):format(value):gsub("%.?0+$", ""))
            if text == "" or text == "-" then text = "0" end
        elseif kind == "table" then
            local items = {}
            for i, item in ipairs(value) do items[i] = Escape(item) end
            text = tconcat(items, ",")
        else
            text = Escape(value)
        end
        parts[#parts + 1] = key .. "=" .. text
    end
    return tconcat(parts, ";")
end

-- Returns true and a summary, or false and why not. Nothing is changed unless
-- the text is a ClickLegend string; values are validated like saved settings.
local function ImportSettings(text)
    if type(text) ~= "string" then return false, "nothing to import." end
    text = text:gsub("%s+", "")
    local fields = {}
    for part in text:gmatch("[^;]+") do fields[#fields + 1] = part end
    if fields[1] ~= SHARE_TAG then return false, "that is not a ClickLegend settings string." end
    local staged, count = {}, 0
    for i = 2, #fields do
        local key, raw = fields[i]:match("^([%w_]+)=(.*)$")
        local default = key and DEFAULTS[key]
        if default ~= nil then
            local kind, value = type(default), nil
            if kind == "boolean" then
                if raw == "1" or raw == "0" then value = (raw == "1") end
            elseif kind == "number" then
                value = tonumber(raw)
            elseif kind == "table" then
                value = {}
                for item in raw:gmatch("[^,]+") do value[#value + 1] = Unescape(item) end
            else
                value = Unescape(raw)
            end
            if value ~= nil then staged[key] = value; count = count + 1 end
        end
    end
    if count == 0 then return false, "no settings found in that string." end
    for key, value in pairs(staged) do db[key] = value end
    AfterBulkChange()
    return true, count .. " settings imported."
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
                function()
                    if o.get then return db and OptGet(o) or o.order[1] end
                    return db and db[o.key] or DEFAULTS[o.key]
                end,
                function(v) OptSet(o, v) end, o.order, o.tip)
        elseif o.kind == "range" then
            _, h = W:Slider(parent, o.text, y, o.lo, o.hi, o.step,
                function() return db and db[o.key] or DEFAULTS[o.key] end,
                function(v) OptSet(o, v) end)
        elseif o.kind == "preset" then
            local values, order = { none = "Choose a preset" }, { "none" }
            for _, id in ipairs(PRESET_ORDER) do
                values[id] = PRESETS[id].name
                order[#order + 1] = id
            end
            _, h = W:Dropdown(parent, o.text, y, values,
                function() return "none" end,
                function(v) if v ~= "none" then ApplyPreset(v) end end, order, o.tip)
        elseif o.kind == "button" then
            local make = W.WideButton or W.Button
            if make then _, h = make(W, parent, o.text, y, o.click) else h = 0 end
        elseif o.kind == "color" then
            local prefix = o.prefix
            _, h = W:ColorPicker(parent, o.text, y,
                function()
                    if db then return GetColor(prefix) end
                    return DEFAULTS[prefix .. "R"], DEFAULTS[prefix .. "G"], DEFAULTS[prefix .. "B"],
                        DEFAULTS[prefix .. "A"] or 1
                end,
                function(r, g, b, a) SetColor(prefix, r, g, b, a) end, o.alpha and true or false)
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
                description = "Click casting with rules per key, and an on-screen legend of your bindings: its own, "
                    .. "or those read from EllesmereUI HoverCast, Clique, VuhDo, HealBot or the game's own Click Casting.",
                pages = PANEL_PAGES,
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
--  Used by the other files
-------------------------------------------------------------------------------
ns.ApplyPreset          = ApplyPreset
-- Several settings at once, from a screen of its own (the guided setup).
ns.SetSettings          = function(values)
    if not db then return end
    for key, value in pairs(values) do db[key] = value end
    AfterBulkChange()
end
ns.ExportSettings       = ExportSettings
ns.GetColor             = GetColor
ns.ImportSettings       = ImportSettings
ns.OPTIONS              = OPTIONS
ns.OpenSettings         = OpenSettings
ns.OptGet               = OptGet
ns.OptSet               = OptSet
ns.PAGES                = PAGES
ns.PANEL_PAGES          = PANEL_PAGES
ns.PRESETS              = PRESETS
ns.PRESET_NOTE          = PRESET_NOTE
ns.PRESET_ORDER         = PRESET_ORDER
ns.RebuildSettingsPages = RebuildSettingsPages
ns.RegisterSettingsPage = RegisterSettingsPage
ns.ResetSettings        = ResetSettings
ns.ResolveKeyToken      = ResolveKeyToken
ns.SetCharacterProfile  = SetCharacterProfile
ns.SetColor             = SetColor
ns.SetCustomPosition    = SetCustomPosition
