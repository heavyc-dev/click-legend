-------------------------------------------------------------------------------
--  ClickLegend - Picker.lua
--  A drop-down list to pick from (with a search box for the long ones), and
--  the lists the binding editor offers: the character's spells, macros and
--  usable items. Plain frames, no templates, like the settings window.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tostring, tonumber, pcall = ipairs, type, tostring, tonumber, pcall
local tsort = table.sort
local max, min = math.max, math.min

local Clamp, Safe, Skin =
    ns.Clamp, ns.Safe, ns.Skin
local ACCENT = Skin.ACCENT
local NewText, SpellName, SpellTexture, ValidIcon =
    ns.NewText, ns.SpellName, ns.SpellTexture, ns.ValidIcon

-------------------------------------------------------------------------------
--  Lists
-------------------------------------------------------------------------------
-- "Rank 3" for a spell that has ranks, else nil.
local function RankText(id)
    if not (id and C_Spell and C_Spell.GetSpellSubtext) then return nil end
    local ok, text = pcall(C_Spell.GetSpellSubtext, id)
    if ok and type(text) == "string" and text ~= "" then return text end
    return nil
end

-- Every castable spell in the character's spellbook, by name; a spell's lower
-- ranks follow its top rank and are marked lowRank.
--   { id, name, icon, rank = "Rank 2" or nil, lowRank = true or nil }
local function ListSpells()
    local spells, seen = {}, {}
    local book = C_SpellBook
    local bank = Enum and Enum.SpellBookSpellBank and Enum.SpellBookSpellBank.Player
    local spellType = Enum and Enum.SpellBookItemType and Enum.SpellBookItemType.Spell
    if not (book and bank and spellType and book.GetNumSpellBookSkillLines
        and book.GetSpellBookSkillLineInfo and book.GetSpellBookItemType) then
        return spells
    end
    local okLines, lines = pcall(book.GetNumSpellBookSkillLines)
    for line = 1, okLines and tonumber(lines) or 0 do
        local ok, info = pcall(book.GetSpellBookSkillLineInfo, line)
        local offSpec = ok and type(info) == "table" and info.offSpecID and info.offSpecID ~= 0
        if ok and type(info) == "table" and not offSpec and not info.shouldHide then
            local first = (info.itemIndexOffset or 0) + 1
            for slot = first, first + (info.numSpellBookItems or 0) - 1 do
                local ok2, kind, actionID, spellID = pcall(book.GetSpellBookItemType, slot, bank)
                local id = ok2 and kind == spellType and (spellID or actionID) or nil
                if type(id) == "number" and not seen[id] then
                    seen[id] = true
                    local passive = false
                    if C_Spell and C_Spell.IsSpellPassive then
                        local ok3, p = pcall(C_Spell.IsSpellPassive, id)
                        passive = ok3 and p and true or false
                    end
                    if not passive then
                        local low = false
                        if book.IsSpellBookItemLowRank then
                            local ok4, l = pcall(book.IsSpellBookItemLowRank, slot, bank)
                            low = ok4 and l and true or false
                        end
                        local rank = RankText(id)
                        spells[#spells + 1] = {
                            id = id, name = SpellName(id), icon = SpellTexture(id), rank = rank,
                            rankNumber = rank and tonumber(rank:match("(%d+)")) or 0, lowRank = low or nil,
                        }
                    end
                end
            end
        end
    end
    tsort(spells, function(a, b)
        if a.name ~= b.name then return a.name < b.name end
        if (a.lowRank or false) ~= (b.lowRank or false) then return not a.lowRank end
        if a.rankNumber ~= b.rankNumber then return a.rankNumber > b.rankNumber end
        return a.id > b.id
    end)
    return spells
end

-- The player's macros, account-wide ones first.  { name, icon, shared = true or nil }
local function ListMacros()
    local macros = {}
    if not (GetNumMacros and GetMacroInfo) then return macros end
    local ok, shared, own = pcall(GetNumMacros)
    if not ok then return macros end
    local function Add(from, count, isShared)
        for i = from, from + (tonumber(count) or 0) - 1 do
            local ok2, name, icon = pcall(GetMacroInfo, i)
            if ok2 and type(name) == "string" and name ~= "" then
                macros[#macros + 1] = { name = name, icon = ValidIcon(icon), shared = isShared or nil }
            end
        end
    end
    Add(1, shared, true)
    Add((tonumber(MAX_ACCOUNT_MACROS) or 120) + 1, own, false)
    return macros
end

-- Worn items that can be used.  { id, name, icon }
local function ListItems()
    local items, seen = {}, {}
    if not (GetInventoryItemID and C_Item and C_Item.GetItemSpell) then return items end
    for slot = 1, 19 do
        local ok, id = pcall(GetInventoryItemID, "player", slot)
        if ok and type(id) == "number" and not seen[id] then
            seen[id] = true
            local ok2, use = pcall(C_Item.GetItemSpell, id)
            if ok2 and use then
                local name, icon
                if C_Item.GetItemNameByID then
                    local ok3, n = pcall(C_Item.GetItemNameByID, id)
                    name = ok3 and type(n) == "string" and n ~= "" and n or nil
                end
                if GetInventoryItemTexture then
                    local ok4, tex = pcall(GetInventoryItemTexture, "player", slot)
                    icon = ok4 and ValidIcon(tex) or nil
                end
                if name then items[#items + 1] = { id = id, name = name, icon = icon } end
            end
        end
    end
    return items
end

-- The character's stances or forms, in order.  { index, name, icon }
local function ListForms()
    local forms = {}
    if not (GetNumShapeshiftForms and GetShapeshiftFormInfo) then return forms end
    local ok, count = pcall(GetNumShapeshiftForms)
    for i = 1, ok and tonumber(count) or 0 do
        local ok2, icon, _, _, spellID = pcall(GetShapeshiftFormInfo, i)
        if ok2 then
            forms[#forms + 1] = { index = i, icon = ValidIcon(icon),
                name = type(spellID) == "number" and SpellName(spellID) or ("Form " .. i) }
        end
    end
    return forms
end

-------------------------------------------------------------------------------
--  The drop-down. One at a time; picking, pressing Escape or clicking
--  anywhere else closes it.
--    ShowMenu(anchor, items, onPick, options)
--    items[i] = { text, value, icon = texture, note = right-hand text }
--    options  = { width, search = true, typed = function(text) -> item or nil }
--  `typed` lets the search text itself be offered as a choice, for a name
--  that is not in the list.
-------------------------------------------------------------------------------
local ROW_H, MAX_ROWS = 20, 12
local EDGE = 5                      -- the list's border
local function Top(search) return search and (EDGE + 25) or EDGE end
local menu, blocker
local state = { all = {}, shown = {}, onPick = nil, options = nil, offset = 0 }

local function CloseMenu()
    if menu then menu:Hide() end
    if blocker then blocker:Hide() end
end

local function Pick(index)
    local item = state.shown[index]
    local onPick = state.onPick
    if not (item and onPick) then return end
    CloseMenu()
    Safe(onPick, item.value, item)
end

local function Render()
    local shown, rows = state.shown, menu.rows
    local visible = min(#shown, MAX_ROWS)
    state.offset = Clamp(state.offset, 0, max(0, #shown - MAX_ROWS))
    for i = 1, MAX_ROWS do
        local row, item = rows[i], shown[i + state.offset]
        if item and i <= visible then
            row.index = i + state.offset
            row.text:SetText(item.text)
            row.note:SetText(item.note or "")
            if item.icon then
                row.icon:SetTexture(item.icon)
                row.icon:Show()
                row.text:SetPoint("LEFT", 24, 0)
            else
                row.icon:Hide()
                row.text:SetPoint("LEFT", 6, 0)
            end
            if item.current then
                row.text:SetTextColor(ACCENT[1], ACCENT[2], ACCENT[3])
            else
                row.text:SetTextColor(1, 1, 1)
            end
            row:Show()
        else
            row:Hide()
        end
    end
    local top = Top(state.options.search)
    menu.none:SetShown(#shown == 0)
    menu.more:SetShown(#shown > MAX_ROWS)
    menu.more:SetText((state.offset + 1) .. "-" .. (state.offset + visible) .. " of " .. #shown .. "  (scroll)")
    menu:SetHeight(top + max(1, visible) * ROW_H + (#shown > MAX_ROWS and 18 or EDGE))
end

-- Narrows the list to the items whose text contains what was typed.
local function Filter(text)
    local shown = {}
    local typed = type(text) == "string" and text:match("^%s*(.-)%s*$") or ""
    text = typed:lower()
    for _, item in ipairs(state.all) do
        if text == "" or tostring(item.text):lower():find(text, 1, true) then shown[#shown + 1] = item end
    end
    if text ~= "" and state.options.typed then
        local extra = state.options.typed(typed)             -- as typed, capitals kept
        if extra then shown[#shown + 1] = extra end
    end
    state.shown, state.offset = shown, 0
    Render()
end

local function BuildMenu()
    blocker = CreateFrame("Button", nil, UIParent)
    blocker:SetAllPoints(UIParent)
    blocker:SetFrameStrata("FULLSCREEN_DIALOG")
    blocker:RegisterForClicks("AnyUp")
    blocker:SetScript("OnClick", CloseMenu)
    blocker:Hide()

    menu = Skin.Popup("ClickLegendMenu", UIParent)
    menu:SetFrameStrata("TOOLTIP")
    menu:SetClampedToScreen(true)
    menu:EnableMouse(true)
    menu:EnableMouseWheel(true)
    menu:Hide()
    if type(UISpecialFrames) == "table" then UISpecialFrames[#UISpecialFrames + 1] = "ClickLegendMenu" end
    menu:SetScript("OnHide", function() if blocker then blocker:Hide() end end)
    menu:SetScript("OnMouseWheel", function(_, delta)
        state.offset = state.offset - delta * 3
        Render()
    end)

    local search = Skin.EditBox(menu, 10, 20)
    search:SetPoint("TOPLEFT", EDGE + 6, -EDGE - 1)
    search:SetPoint("TOPRIGHT", -EDGE - 3, -EDGE - 1)
    search:SetMaxLetters(60)
    search:SetScript("OnTextChanged", function(self) Safe(Filter, self:GetText()) end)
    search:SetScript("OnEscapePressed", CloseMenu)
    search:SetScript("OnEnterPressed", function() Pick(1) end)        -- Enter takes the first match
    menu.search = search

    menu.rows = {}
    for i = 1, MAX_ROWS do
        local row = CreateFrame("Button", nil, menu)
        row:SetHeight(ROW_H)
        row.hl = row:CreateTexture(nil, "BACKGROUND")
        row.hl:SetAllPoints()
        Skin.Bar(row.hl, false)
        row.hl:Hide()
        row.icon = row:CreateTexture(nil, "ARTWORK")
        row.icon:SetSize(16, 16)
        row.icon:SetPoint("LEFT", 4, 0)
        row.icon:SetTexCoord(0.08, 0.92, 0.08, 0.92)
        row.text = NewText(row, 11)
        row.text:SetPoint("LEFT", 24, 0)
        row.note = NewText(row, 10, 0.6, 0.6, 0.6)
        row.note:SetPoint("RIGHT", -6, 0)
        row:SetScript("OnEnter", function(self) self.hl:Show() end)
        row:SetScript("OnLeave", function(self) self.hl:Hide() end)
        row:SetScript("OnClick", function(self) Pick(self.index) end)
        menu.rows[i] = row
    end
    menu.none = NewText(menu, 11, 0.6, 0.6, 0.6)
    menu.none:SetText("Nothing matches.")
    menu.more = NewText(menu, 9, 0.6, 0.6, 0.6)
    menu.more:SetPoint("BOTTOM", 0, EDGE)
end

local function ShowMenu(anchor, items, onPick, options)
    if not menu then BuildMenu() end
    options = options or {}
    state.all, state.onPick, state.options = items, onPick, options
    local width = options.width or 180
    local top = Top(options.search)
    menu:SetWidth(width)
    menu.search:SetShown(options.search and true or false)
    for i, row in ipairs(menu.rows) do
        row:ClearAllPoints()
        row:SetPoint("TOPLEFT", EDGE, -(top + (i - 1) * ROW_H))
        row:SetWidth(width - EDGE * 2)
    end
    menu.none:ClearAllPoints()
    menu.none:SetPoint("TOPLEFT", EDGE + 6, -(top + 3))
    menu:ClearAllPoints()
    menu:SetPoint("TOPLEFT", anchor, "BOTTOMLEFT", 0, -2)
    blocker:Show()
    menu:Show()
    if options.search then
        menu.search:SetText("")
        menu.search:SetFocus()
    end
    Filter("")
end

-- What the open list offers, as text; and picking by position. The mock
-- tests drive the editor through these.
local function MenuTexts()
    local out = {}
    if menu and menu:IsShown() then
        for i, item in ipairs(state.shown) do
            out[i] = tostring(item.text) .. (item.note and (" (" .. item.note .. ")") or "") .. (item.current and " *" or "")
        end
    end
    return out
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.CloseMenu  = CloseMenu
ns.FilterMenu = Filter
ns.ListForms  = ListForms
ns.ListItems  = ListItems
ns.ListMacros = ListMacros
ns.ListSpells = ListSpells
ns.MenuTexts  = MenuTexts
ns.PickMenu   = Pick
ns.RankText   = RankText
ns.ShowMenu   = ShowMenu
