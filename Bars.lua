-------------------------------------------------------------------------------
--  ClickLegend - Bars.lua
--  Marks on the action bars: a small mouse picture on (or above) each action
--  button whose spell is also bound to a click with no modifier, with that
--  click's button lit. Off unless the player picks it (setting `barMarks`).
--  Reads the bars only: the marks are plain frames hung on the buttons and
--  nothing about a button is changed.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, pcall, tostring = ipairs, pairs, type, pcall, tostring
local floor, max = math.floor, math.max

local db, layers
local NewGlyph, DrawGlyph, MouseRank, Safe = ns.NewGlyph, ns.DrawGlyph, ns.MouseRank, ns.Safe

-- Action buttons by name: the game's bars, then bar addons that name their
-- buttons by slot.
local BAR_PREFIXES = {
    "ActionButton", "MultiBarBottomLeftButton", "MultiBarBottomRightButton",
    "MultiBarRightButton", "MultiBarLeftButton",
    "MultiBar5Button", "MultiBar6Button", "MultiBar7Button",
}
local SLOT_PREFIXES = { "EABButton", "BT4Button" }      -- EllesmereUI, Bartender: 1 to 180

local marks = {}            -- [button] = { holder, glyphs = {} }
local pending, watcher = false, nil

-- A spell name as both sides write it: no rank, no case.
local function Plain(name)
    if type(name) ~= "string" then return nil end
    name = name:gsub("%s*%(.-%)%s*$", "")
    return name:lower()
end

local function SpellName(id)
    if type(id) ~= "number" then return nil end
    if C_Spell and C_Spell.GetSpellName then
        local ok, name = pcall(C_Spell.GetSpellName, id)
        if ok and type(name) == "string" then return name end
    end
    if GetSpellInfo then
        local ok, name = pcall(GetSpellInfo, id)
        if ok and type(name) == "string" then return name end
    end
end

-- The action slot a button shows now (its page and form included).
local function ButtonSlot(b)
    local slot = rawget(b, "action")
    if type(slot) ~= "number" then slot = rawget(b, "_state_action") end
    if type(slot) ~= "number" and b.GetAttribute then
        local ok, v = pcall(b.GetAttribute, b, "action")
        slot = ok and tonumber(v) or nil
    end
    return type(slot) == "number" and slot > 0 and slot or nil
end

-- The spell on a slot: a spell, or the spell a macro shows.
local function SlotSpell(slot)
    if not GetActionInfo then return nil end
    local ok, kind, id, sub = pcall(GetActionInfo, slot)
    if not ok then return nil end
    if kind == "spell" then return SpellName(id) end
    if kind == "macro" then
        if sub == "spell" then
            local name = SpellName(id)
            if name then return name end
        end
        if GetMacroSpell then
            local ok2, spell = pcall(GetMacroSpell, id)
            if ok2 then return SpellName(spell) end
        end
    end
end

-- Spell name -> the clicks with no modifier that cast it, mouse buttons first.
local function PlainClicks()
    local layer = layers and layers[""]
    if not layer then return nil end
    local found = {}
    for key, sides in pairs(layer.byKey or {}) do
        for _, entry in pairs(sides) do
            local name = type(entry) == "table" and not entry.missing and Plain(entry.name)
            if name then
                local list = found[name] or {}
                found[name] = list
                local seen = false
                for _, k in ipairs(list) do seen = seen or k == key end
                if not seen then list[#list + 1] = key end
            end
        end
    end
    for _, list in pairs(found) do
        table.sort(list, function(a, b)
            local ra, rb = MouseRank(a) or 99, MouseRank(b) or 99
            if ra ~= rb then return ra < rb end
            return a < b
        end)
    end
    return found
end

local function Buttons(each)
    for _, prefix in ipairs(BAR_PREFIXES) do
        for i = 1, 12 do
            local b = _G[prefix .. i]
            if type(b) == "table" then each(b) end
        end
    end
    for _, prefix in ipairs(SLOT_PREFIXES) do
        for i = 1, 180 do
            local b = _G[prefix .. i]
            if type(b) == "table" then each(b) end
        end
    end
end

local function HideMarks(m)
    if m then m.holder:Hide() end
end

local function MarkButton(b, keys, where)
    local m = marks[b]
    if not m then
        local holder = CreateFrame("Frame", nil, b)
        holder:SetAllPoints(b)
        m = { holder = holder, glyphs = {} }
        marks[b] = m
    end
    local holder = m.holder
    if holder.SetFrameLevel and b.GetFrameLevel then
        local ok, level = pcall(b.GetFrameLevel, b)
        if ok and type(level) == "number" then holder:SetFrameLevel(level + 5) end
    end
    local w = b.GetWidth and tonumber((b:GetWidth())) or 36
    if w <= 0 then w = 36 end
    local side = max(10, floor(w * (where == "on" and 0.42 or 0.45) + 0.5))
    local count = #keys
    for n = 1, max(count, #m.glyphs) do
        local g = m.glyphs[n]
        if n <= count then
            if not g then
                g = NewGlyph(holder)
                m.glyphs[n] = g
            end
            DrawGlyph(g, keys[n], side)
            g:ClearAllPoints()
            if where == "on" then
                g:SetPoint("TOPLEFT", holder, "TOPLEFT", 2 + (n - 1) * (side - 2), -2)
            else
                local x = (n - (count + 1) / 2) * side
                g:SetPoint("BOTTOM", holder, "TOP", x, 1)
            end
            g:SetAlpha(1)
            g:Show()
        elseif g then
            g:Hide()
        end
    end
    holder:Show()
end

local function Update()
    pending = false
    if not db then return end
    local where = db.barMarks
    local found = where ~= "off" and PlainClicks() or nil
    local done = {}
    if found and next(found) then
        Buttons(function(b)
            local slot = ButtonSlot(b)
            local name = slot and Plain(SlotSpell(slot))
            local keys = name and found[name]
            if keys then
                MarkButton(b, keys, where)
                done[b] = true
            end
        end)
    end
    for b, m in pairs(marks) do
        if not done[b] then HideMarks(m) end
    end
end

-- Redraws once, a moment later: the bars update on the same events.
local function Schedule()
    if pending then return end
    if not (db and (db.barMarks ~= "off" or next(marks))) then return end
    pending = true
    if C_Timer and C_Timer.After then
        C_Timer.After(0.05, function() Safe(Update) end)
    else
        Safe(Update)
    end
end

local BAR_EVENTS = {
    "ACTIONBAR_SLOT_CHANGED", "ACTIONBAR_PAGE_CHANGED", "UPDATE_BONUS_ACTIONBAR",
    "UPDATE_SHAPESHIFT_FORM", "UPDATE_MACROS", "PLAYER_ENTERING_WORLD", "SPELLS_CHANGED",
}

-- Watches the bars only once marks are wanted.
local function Watch()
    if watcher or not (db and db.barMarks ~= "off") then return end
    watcher = CreateFrame("Frame")
    for _, e in ipairs(BAR_EVENTS) do pcall(watcher.RegisterEvent, watcher, e) end
    watcher:SetScript("OnEvent", Schedule)
end

local function Changed()
    Watch()
    Schedule()
end

ns.Subscribe("db", function(value) db = value end)
ns.Subscribe("layers", function(value) layers = value; Changed() end)

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.UpdateBarMarks = Changed
ns.BarMarkCount   = function()
    local n = 0
    for _, m in pairs(marks) do
        if m.holder:IsShown() then n = n + 1 end
    end
    return n
end
