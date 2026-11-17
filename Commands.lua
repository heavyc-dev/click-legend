-------------------------------------------------------------------------------
--  ClickLegend - Commands.lua
--  Slash commands, events and start-up.
-------------------------------------------------------------------------------
local ADDON_NAME, ns = ...

local ipairs, pairs, tonumber, pcall = ipairs, pairs, tonumber, pcall
local tsort, tconcat = table.sort, table.concat

local db
local layers
local activeSource
ns.Subscribe("db", function(value) db = value end)
ns.Subscribe("layers", function(value) layers = value end)
ns.Subscribe("source", function(value) activeSource = value end)

local CHOICES, InitDB, LongKey, ModsLong, OrderKeys =
    ns.CHOICES, ns.InitDB, ns.LongKey, ns.ModsLong, ns.OrderKeys
local Print, Safe, SanitizeDB, ShortKey, AllBoundKeys =
    ns.Print, ns.Safe, ns.SanitizeDB, ns.ShortKey, ns.AllBoundKeys
local SortedMods, ApplyPosition, CheckAnchor, Refresh =
    ns.SortedMods, ns.ApplyPosition, ns.CheckAnchor, ns.Refresh
local Render, HookTooltip, RefreshUnitTooltip =
    ns.Render, ns.HookTooltip, ns.RefreshUnitTooltip
local ApplyPreset, ExportSettings, ImportSettings =
    ns.ApplyPreset, ns.ExportSettings, ns.ImportSettings
local OpenSettings, PRESETS, PRESET_ORDER =
    ns.OpenSettings, ns.PRESETS, ns.PRESET_ORDER
local RebuildSettingsPages, RegisterSettingsPage =
    ns.RebuildSettingsPages, ns.RegisterSettingsPage
local ResetSettings, ResolveKeyToken =
    ns.ResetSettings, ns.ResolveKeyToken
local SetCharacterProfile, OpenShareTab, RefreshWindow =
    ns.SetCharacterProfile, ns.OpenShareTab, ns.RefreshWindow
local RegisterGameOptions, ToggleWindow =
    ns.RegisterGameOptions, ns.ToggleWindow
local CastCommand, InitCast, UpdateProvider =
    ns.CastCommand, ns.InitCast, ns.UpdateProvider
local OpenGuidedSetup, ShowWelcome, StartLauncher =
    ns.OpenGuidedSetup, ns.ShowWelcome, ns.StartLauncher

-------------------------------------------------------------------------------
--  Slash commands
-------------------------------------------------------------------------------
local function ListBindings()
    if not layers then
        if db.source ~= "auto" then
            Print("no click-cast bindings found in the chosen source (/clg source auto to look everywhere).")
        else
            Print("no click-cast bindings found. ClickLegend reads EllesmereUI HoverCast, Clique, VuhDo, "
                .. "HealBot and the game's Click Casting.")
        end
        return
    end
    Print("current bindings (" .. (activeSource or "?") .. ")")
    for _, mods in ipairs(SortedMods(layers)) do
        local layer = layers[mods]
        for _, key in ipairs(OrderKeys(layer.keys)) do
            local slot = layer.byKey[key]
            local keyName = (mods ~= "" and (ModsLong(mods) .. "+") or "") .. LongKey(key)
            local function Named(entry)
                if not entry then return nil end
                return entry.name .. (entry.missing and " (not available)" or "")
            end
            local ally, enemy = Named(slot.ally), Named(slot.enemy)
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
    print("  /clg setup - guided setup of ClickLegend's own click casting; /clg welcome | news - the welcome window, what is new")
    print("  /clg minimap - show or hide the minimap button")
    print("  /clg config - open the settings in EllesmereUI (or the window without it)")
    print("  /clg lock | unlock - lock in place, or unlock to drag")
    print("  /clg show | hide - toggle the legend")
    print("  /clg visible always | group | combat | hover (now " .. db.visibility .. ")")
    print("  /clg source auto | own | eui | clique | vuhdo | healbot | blizzard (now " .. db.source .. ")")
    print("  /clg cast - ClickLegend's own bindings: status, on | off, sets, set <name>")
    print("  /clg layers held | all - modifier layers shown (now " .. db.layers .. ")")
    print("  /clg anchor screen | party | cursor, /clg side above | below | left | right, /clg gap <0-60>")
    print("  /clg hoverdim | missing - toggle row dimming, greying of broken bindings")
    print("  /clg usable | flash - toggle marking spells you cannot cast, the flash when one is cast")
    print("  /clg off dim | hide - spells that do not apply to the hovered unit (now " .. db.offStyle .. ")")
    print("  /clg profile - separate settings for this character, or shared")
    print("  /clg layout horizontal | vertical | mouse (now " .. db.layout .. ")")
    print("  /clg mouse <96-256> - size of the mouse picture (now " .. db.mouseSize .. ")")
    print("  /clg mousepic a | b | c | d - which mouse is drawn (now " .. db.mousePic .. ")")
    print("  /clg rows both | ally | enemy (now " .. db.rows .. ")")
    print("  /clg flip - enemy spells first, or ally spells first")
    print("  /clg sort mouse | keyboard | alpha | custom (now " .. db.sort .. ")")
    print("  /clg order <keys> - custom order, e.g. /clg order M4 M5 L R")
    print("  /clg reverse - reverse the order")
    print("  /clg wrap <2-24> - buttons per line (now " .. db.perLine .. ")")
    print("  /clg size <16-64> | scale <0.5-2> | alpha <0.1-1>")
    print("  /clg labels | bars | tooltip - toggle labels, color bars, tooltip lines")
    print("  /clg labelstyle text | icon | corner (now " .. db.labelStyle .. ")")
    print("  /clg labelsize <7-14> - label size (now " .. db.labelSize .. ")")
    print("  /clg bg - toggle the background")
    print("  /clg bgcolor | allycolor | enemycolor <RRGGBB> - e.g. /clg bgcolor 101418")
    print("  /clg rangecolor | manacolor | cooldowncolor <RRGGBB> - the tint of a spell you cannot cast now")
    print("  /clg bgalpha <0-1> | pad <0-20> - background opacity and padding")
    print("  /clg preset default | compact | sidebar | full | minimal - apply a layout preset")
    print("  /clg export - settings as text to copy; /clg import <text> - use someone's settings")
    print("  /clg list - print every binding to chat")
    print("  /clg reset - default position and settings")
end

-- Each kind of command is a table from its name to the setting it changes.
local TOGGLES = {
    hoverdim = "hoverDim", missing = "flagMissing", usable = "flagUnusable", flash = "flash", bars = "bars", labels = "labels", minimap = "minimap",
    bg = "background", flip = "enemyFirst", reverse = "reverse",
}
local NUMBERS = {
    size = "iconSize", scale = "scale", alpha = "alpha", wrap = "perLine",
    labelsize = "labelSize", bgalpha = "bgA", pad = "bgPadding", gap = "anchorGap", mouse = "mouseSize",
}
local CHOICE_KEYS = {
    layers = "layers", anchor = "anchor", source = "source", side = "anchorSide", off = "offStyle", mousepic = "mousePic",
    visible = "visibility", labelstyle = "labelStyle", layout = "layout", rows = "rows", sort = "sort",
}
local COLORS = { bgcolor = "bg", allycolor = "ally", enemycolor = "enemy",
                 rangecolor = "far", manacolor = "mana", cooldowncolor = "cool" }

-- Every setter below returns true when a setting changed, so the legend is
-- redrawn once at the end of HandleSlash.
local function SetChoice(key, value)
    if CHOICES[key][value] then db[key] = value; return true end
    local options = {}
    for option in pairs(CHOICES[key]) do options[#options + 1] = option end
    tsort(options)
    Print("use one of: " .. tconcat(options, ", "))
    return false
end

local function SetHexColor(cmd, arg)
    local r, g, b = arg:match("^#?(%x%x)(%x%x)(%x%x)$")
    if not r then Print("use six hex digits, e.g. /clg " .. cmd .. " 101418"); return false end
    local prefix = COLORS[cmd]
    db[prefix .. "R"], db[prefix .. "G"], db[prefix .. "B"] =
        tonumber(r, 16) / 255, tonumber(g, 16) / 255, tonumber(b, 16) / 255
    if prefix == "bg" then db.background = true end
    return true
end

local function SetOrder(arg)
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
        return false
    end
    for _, key in ipairs(bound) do
        if not seen[key] then picked[#picked + 1] = key end
    end
    db.customOrder = picked
    db.sort = "custom"
    RebuildSettingsPages()
    return true
end

-- Commands that do more than set one value: ACTIONS[name](arg, rawArg).
-- rawArg keeps its capitals (settings strings are case sensitive).
local ACTIONS = {
    lock = function() db.locked = true; Print("locked."); return true end,
    unlock = function()
        db.locked = false; db.hidden = false
        Print("unlocked - drag it, then /clg lock.")
        return true
    end,
    show = function() db.hidden = false; return true end,
    hide = function() db.hidden = true; return true end,
    tooltip = function()
        db.tooltip = not db.tooltip
        Print("tooltip bindings " .. (db.tooltip and "on." or "off."))
        return true
    end,
    order = SetOrder,
    cast = function(arg, rawArg) return CastCommand(arg, rawArg) end,
    profile = function()
        local on = not (ClickLegendCharDB.enabled == true)
        SetCharacterProfile(on)
        Print(on and "this character now has its own settings." or "this character now uses the shared settings.")
    end,
    list = function() Refresh(true); ListBindings() end,
    export = function()
        OpenShareTab()
        local window = ns.GetWindow()
        if window and window.share then
            local box = window.share.box
            box:SetText(ExportSettings())
            box:SetFocus()
            box:HighlightText()
            window.share.status:SetText("Copied into the box and selected: press Ctrl+C.")
        end
    end,
    import = function(_, rawArg)
        if rawArg == "" then
            OpenShareTab()
            Print("paste the settings string into the box and press Import, or type /clg import <string>.")
        else
            local _, message = ImportSettings(rawArg)
            Print(message)
        end
    end,
    preset = function(arg)
        if ApplyPreset(arg) then
            Print(PRESETS[arg].name .. " preset applied.")
        else
            Print("presets: " .. tconcat(PRESET_ORDER, ", "))
        end
    end,
    menu = function() ToggleWindow() end,
    setup = function() OpenGuidedSetup() end,
    welcome = function() ShowWelcome(true) end,
    news = function() ns.ShowNews(true) end,              -- Launcher.lua
    -- EllesmereUI's panel when it is there (it does not open in combat), the
    -- addon's own window otherwise.
    config = function()
        if not OpenSettings() then ToggleWindow(true) end
    end,
    reset = function() ResetSettings(); Print("reset.") end,
    help = Help,
    [""] = function() ToggleWindow() end,
}
ACTIONS.options = ACTIONS.config
ACTIONS["?"] = Help

local function HandleSlash(msg)
    local cmd, arg = (msg or ""):lower():match("^%s*(%S*)%s*(.-)%s*$")
    local rawArg = (msg or ""):match("^%s*%S*%s*(.-)%s*$") or ""
    local changed
    if ACTIONS[cmd] then
        changed = ACTIONS[cmd](arg, rawArg)
    elseif TOGGLES[cmd] then
        db[TOGGLES[cmd]] = not db[TOGGLES[cmd]]
        changed = true
    elseif NUMBERS[cmd] and tonumber(arg) then
        db[NUMBERS[cmd]] = tonumber(arg)
        changed = true
    elseif CHOICE_KEYS[cmd] then
        changed = SetChoice(CHOICE_KEYS[cmd], arg)
    elseif COLORS[cmd] then
        changed = SetHexColor(cmd, arg)
    else
        Help()
    end
    if changed then
        SanitizeDB()
        ApplyPosition()
        Refresh(true)
        RefreshWindow()
    end
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
    "UPDATE_SHAPESHIFT_FORM", "UNIT_PET",                 -- change which rule of an own binding fires
    "UNIT_SPELLCAST_SUCCEEDED",                           -- the legend flashes the spell that was cast
}) do
    pcall(events.RegisterEvent, events, event)      -- an event a client lacks must not stop the rest
end

-- No source has a "bindings changed" callback, so poll every POLL_SECONDS.
-- Bindings cannot change in combat, so skip then.
local POLL_SECONDS = 2

local function Poll()
    if not (InCombatLockdown and InCombatLockdown()) then
        Safe(Refresh, false)
        Safe(CheckAnchor)
    end
end

local function StartPolling()
    if C_Timer and C_Timer.NewTicker then
        C_Timer.NewTicker(POLL_SECONDS, Poll)
        return
    end
    local elapsed = 0
    events:SetScript("OnUpdate", function(_, dt)
        elapsed = elapsed + (dt or 0)
        if elapsed >= POLL_SECONDS then elapsed = 0; Poll() end
    end)
end

events:SetScript("OnEvent", function(_, event, arg1, arg2, arg3)
    if event == "ADDON_LOADED" then
        if arg1 == ADDON_NAME then
            Safe(InitDB)
            Safe(InitCast)
            if db then
                Safe(HookTooltip)
                Safe(RegisterSettingsPage)
                Safe(RegisterGameOptions)
            end
        end
        return
    end
    if not db then return end
    -- Both of these fire for every unit in the raid; only the player's count.
    if event == "UNIT_PET" and arg1 ~= "player" then return end
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if arg1 == "player" then Safe(ns.SpellCast, arg3) end        -- Display.lua
        return
    end
    if event == "PLAYER_LOGIN" then
        Safe(ApplyPosition)
        Safe(Refresh, true)
        Safe(UpdateProvider)
        Safe(StartLauncher)
        StartPolling()
        if not db.locked and not db.dragHint then
            db.dragHint = true          -- said once, not at every login
            Print("drag the legend where you want it, then type /clg lock. /clg for settings.")
        end
    elseif event == "MODIFIER_STATE_CHANGED" then
        Render()
        RefreshUnitTooltip()
    elseif event == "PLAYER_REGEN_DISABLED" or event == "PLAYER_REGEN_ENABLED" then
        Safe(Refresh, false)        -- an own binding may have a rule for in or out of combat
        Render()
    elseif event == "GROUP_ROSTER_UPDATE" or event == "PLAYER_ENTERING_WORLD" then
        Safe(Refresh, false)
        Safe(CheckAnchor)
        Render()
    else
        Safe(Refresh, false)
    end
end)
