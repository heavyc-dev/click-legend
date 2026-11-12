-------------------------------------------------------------------------------
--  ClickLegend - Display.lua
--  The legend itself: the panel, its icons and labels, the layout, and
--  where it sits on screen.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, type, tonumber, pcall = ipairs, type, tonumber, pcall
local floor, ceil, max, min = math.floor, math.ceil, math.max, math.min

-- The bindings on screen, and the signatures they were last drawn from.
local layers, lastSig, lastKeySig
local db
local ownSource = false             -- showing ClickLegend's own bindings, which follow the hovered unit
ns.Subscribe("db", function(value) db = value end)
ns.Subscribe("source", function(value) ownSource = value == "ClickLegend" end)

local HeldMods, LongKey, ModsLong, MouseRank, OrderKeys =
    ns.HeldMods, ns.LongKey, ns.ModsLong, ns.MouseRank, ns.OrderKeys
local POINTS, Report, Safe, ShortKey, CollectLayers =
    ns.POINTS, ns.Report, ns.Safe, ns.ShortKey, ns.CollectLayers
local Signatures, SortedMods =
    ns.Signatures, ns.SortedMods

-------------------------------------------------------------------------------
--  Display
-------------------------------------------------------------------------------
local ACCENT = { 0.05, 0.82, 0.62 }           -- the unlocked outline and the settings window's accent
local BAR_W, BAR_GAP, BLOCK_GAP, SECTION_GAP = 3, 3, 8, 10

-- The ally and enemy colors the user picked (bars and tooltip lines).
local function SideColor(side)
    if side == "enemy" then return db.enemyR, db.enemyG, db.enemyB end
    return db.allyR, db.allyG, db.allyB
end

local panel = CreateFrame("Frame", "ClickLegendPanel", UIParent)
panel:SetSize(120, 28)
panel:SetFrameStrata("MEDIUM")
panel:SetClampedToScreen(true)
panel:SetMovable(true)
panel:RegisterForDrag("LeftButton")
panel:Hide()

local bg = panel:CreateTexture(nil, "BACKGROUND", nil, -8)

-- Shown only while unlocked: a thin outline that marks the area to drag. An
-- outline, not a fill, so the background color and opacity read true while
-- the legend is being placed.
local OUTLINE = 2
local moverEdges = {}
for i = 1, 4 do
    local edge = panel:CreateTexture(nil, "OVERLAY")
    edge:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.9)
    edge:Hide()
    moverEdges[i] = edge
end

-- The background and the outline cover the legend plus the chosen padding.
local function ApplyBackground(unlocked)
    local pad = db.bgPadding
    bg:ClearAllPoints()
    bg:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
    bg:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    bg:SetColorTexture(db.bgR, db.bgG, db.bgB, db.bgA)
    bg:SetShown(db.background)

    local top, bottom, left, right = moverEdges[1], moverEdges[2], moverEdges[3], moverEdges[4]
    for _, edge in ipairs(moverEdges) do edge:ClearAllPoints() end
    top:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
    top:SetPoint("TOPRIGHT", panel, "TOPRIGHT", pad, pad)
    top:SetHeight(OUTLINE)
    bottom:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -pad, -pad)
    bottom:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    bottom:SetHeight(OUTLINE)
    left:SetPoint("TOPLEFT", panel, "TOPLEFT", -pad, pad)
    left:SetPoint("BOTTOMLEFT", panel, "BOTTOMLEFT", -pad, -pad)
    left:SetWidth(OUTLINE)
    right:SetPoint("TOPRIGHT", panel, "TOPRIGHT", pad, pad)
    right:SetPoint("BOTTOMRIGHT", panel, "BOTTOMRIGHT", pad, -pad)
    right:SetWidth(OUTLINE)
    for _, edge in ipairs(moverEdges) do edge:SetShown(unlocked) end
end

local layerText = panel:CreateFontString(nil, "OVERLAY")
layerText:SetPoint("RIGHT", panel, "LEFT", -6, 0)

-- Pools of drawn pieces, reused on every render.
local bars, cells, labels, glyphs, captions = {}, {}, {}, {}, {}

-- EllesmereUI's own font and outline when it can be read, the game font
-- otherwise. Looked up once per render (ResolveFont), then reused for every
-- label drawn in it.
local fontPath, fontFlags

local function ResolveFont()
    fontPath, fontFlags = nil, nil
    local E = EllesmereUI
    if type(E) ~= "table" then return end
    if type(E.GetFontPath) == "function" then
        local ok, p = pcall(E.GetFontPath)
        if ok and type(p) == "string" and p ~= "" then fontPath = p end
    end
    if type(E.GetFontOutlineFlag) == "function" then
        local ok, f = pcall(E.GetFontOutlineFlag)
        if ok and type(f) == "string" then fontFlags = f end
    end
end

local function ApplyFont(fs, size)
    local path, flags = fontPath, fontFlags
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

-------------------------------------------------------------------------------
--  What is under the cursor. Drives two things: dimming the row that does not
--  apply to the hovered unit, and the "while hovering a unit frame" visibility.
-------------------------------------------------------------------------------
local hover = { side = nil, onFrame = false, dead = false }

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

-- Returns true when the hovered unit's side or frame state changed.
local function ReadHover()
    local side, onFrame, dead = nil, false, false
    if UnitExists and UnitCanAttack then
        local ok, exists = pcall(UnitExists, "mouseover")
        if ok and not (issecretvalue and issecretvalue(exists)) and exists then
            local ok2, hostile = pcall(UnitCanAttack, "player", "mouseover")
            if ok2 and not (issecretvalue and issecretvalue(hostile)) then
                side = hostile and "enemy" or "ally"
                onFrame = not OverWorld()
                if UnitIsDeadOrGhost then
                    local ok3, gone = pcall(UnitIsDeadOrGhost, "mouseover")
                    dead = ok3 and not (issecretvalue and issecretvalue(gone)) and gone and true or false
                end
            end
        end
    end
    if side == hover.side and onFrame == hover.onFrame and dead == hover.dead then return false end
    hover.side, hover.onFrame, hover.dead = side, onFrame, dead
    return true
end

-- The side of the unit under the cursor ("ally", "enemy" or nil) and whether
-- it is dead. Cast.lua reads this to show what a key would do right now.
function ns.HoverState() return hover.side, hover.dead end

-------------------------------------------------------------------------------
--  Moving the legend
-------------------------------------------------------------------------------
local ApplyPosition                 -- defined after the renderer
local anchoredTo = nil              -- the frame the legend is attached to, when it is

local function DragStart()
    if db and not db.locked and not anchoredTo then panel:StartMoving() end
end

local function DragStop()
    panel:StopMovingOrSizing()
    if not db or anchoredTo then return end
    local point, _, relPoint, x, y = panel:GetPoint(1)
    if POINTS[point] then
        db.point = point
        db.relPoint = POINTS[relPoint] and relPoint or point
        db.x, db.y = tonumber(x) or 0, tonumber(y) or 0
    end
    ApplyPosition()
end

panel:SetScript("OnDragStart", DragStart)
panel:SetScript("OnDragStop", DragStop)

-------------------------------------------------------------------------------
--  Pieces
-------------------------------------------------------------------------------
local function GetBar(i)
    local bar = bars[i]
    if not bar then
        bar = panel:CreateTexture(nil, "ARTWORK")
        bars[i] = bar
    end
    return bar
end

-- While the legend is unlocked, hovering an icon names the binding.
local function ShowCellTooltip(cell)
    local entry = cell.entry
    if not (entry and GameTooltip and GameTooltip.SetOwner) then return end
    GameTooltip:SetOwner(cell, "ANCHOR_RIGHT")
    local shown = false
    if entry.spellID and GameTooltip.SetSpellByID then
        shown = pcall(GameTooltip.SetSpellByID, GameTooltip, entry.spellID)
    end
    if not shown then GameTooltip:SetText(entry.name, 1, 1, 1) end
    local r, g, b = SideColor(cell.side)
    local keyName = (cell.mods ~= "" and (ModsLong(cell.mods) .. "+") or "") .. LongKey(cell.key)
    GameTooltip:AddLine(" ")
    GameTooltip:AddDoubleLine(keyName, cell.side == "enemy" and "on an enemy" or "on an ally", 1, 1, 1, r, g, b)
    if entry.missing then
        GameTooltip:AddLine("Not available: the spell is not learned or the macro is gone.", 0.9, 0.3, 0.3, true)
    end
    GameTooltip:Show()
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
        -- Mouse is only enabled while unlocked; a drag on an icon moves the legend.
        cell:RegisterForDrag("LeftButton")
        cell:SetScript("OnDragStart", DragStart)
        cell:SetScript("OnDragStop", DragStop)
        cell:SetScript("OnEnter", function(self) Safe(ShowCellTooltip, self) end)
        cell:SetScript("OnLeave", function() if GameTooltip and GameTooltip.Hide then GameTooltip:Hide() end end)
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

local function GetCaption(i)
    local fs = captions[i]
    if not fs then
        fs = panel:CreateFontString(nil, "OVERLAY")
        captions[i] = fs
    end
    return fs
end

-------------------------------------------------------------------------------
--  Label glyphs: the "Icons" label style draws a small mouse with the bound
--  button lit, and a keycap for keyboard keys. Built from plain colored
--  rectangles, no image files.
-------------------------------------------------------------------------------
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

-- The width the label column needs (vertical layout).
local function LabelWidth()
    if not db.labels then return 0 end
    return db.labelSize * 3 + 7
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

local function GlyphText(g, text, size, x, y)
    ApplyFont(g.num, size)
    g.num:ClearAllPoints()
    g.num:SetPoint("CENTER", g, "TOPLEFT", 1 + x, -(1 + y))
    g.num:SetText(text)
    g.num:Show()
end

local function DrawGlyph(g, key)
    local gw, gh, half, bh = GlyphSize()
    g.lit:Hide()
    g.num:Hide()
    g.divider:Hide()
    g.line:Hide()
    for _, t in ipairs(g.tri) do t:Hide() end

    if not MouseRank(key) then
        -- A keyboard key: a keycap wide enough for its name.
        local text = ShortKey(key)
        local size = max(6, db.labelSize - 1)
        ApplyFont(g.num, size)
        g.num:SetText(text)
        local measured = g.num.GetStringWidth and g.num:GetStringWidth() or nil
        local textW = type(measured) == "number" and measured or 0
        if textW <= 0 then textW = #text * size * 0.62 end     -- not laid out yet: estimate
        local w = max(gh, floor(textW + 6.5))
        g:SetSize(w + 2, gh + 2)
        GlyphRect(g, g.body, 0, 0, w, gh)
        GlyphRect(g, g.line, 0, gh - 2, w, 2)               -- the keycap's lower lip
        GlyphText(g, text, size, w / 2, (gh - 2) / 2)
        return
    end

    g:SetSize(gw + 2, gh + 2)
    GlyphRect(g, g.body, 0, 0, gw, gh)
    GlyphRect(g, g.divider, half, 0, 1, bh)
    GlyphRect(g, g.line, 0, bh, gw, 1)
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
        GlyphText(g, n or "", max(6, db.labelSize - 2), gw / 2, bh + (gh - bh) / 2)
    end
end

-- A key's label: a glyph in the icon style, text otherwise. `draw` counts the
-- pieces used so far in this render.
local function PlaceLabel(draw, key, point, x, y, alpha)
    if db.labelStyle == "icon" then
        draw.glyph = draw.glyph + 1
        local g = GetGlyph(draw.glyph)
        DrawGlyph(g, key)
        g:ClearAllPoints()
        g:SetPoint(point, panel, "TOPLEFT", x, y)
        g:SetAlpha(alpha)
        g:Show()
        return
    end
    draw.label = draw.label + 1
    local fs = GetLabel(draw.label)
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

-- sec: the section being drawn ({ mods, alpha = function(side) }).
local function PlaceCell(draw, sec, key, side, x, y, size, entry)
    draw.cell = draw.cell + 1
    local cell = GetCell(draw.cell)
    local alpha = sec.alpha(side)
    cell:ClearAllPoints()
    cell:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    cell:SetSize(size, size)
    cell.entry, cell.key, cell.mods, cell.side = entry, key, sec.mods, side
    cell:EnableMouse((entry ~= nil and not db.locked) and true or false)
    if entry then
        cell.icon:SetTexture(entry.icon)
        -- A binding that cannot fire (spell not learned, macro gone) is greyed.
        local broken = entry.missing and db.flagMissing
        if cell.icon.SetDesaturated then cell.icon:SetDesaturated(broken and true or false) end
        cell.icon:Show()
        cell:SetAlpha(broken and alpha * 0.45 or alpha)
    else
        cell.icon:Hide()                    -- empty slot keeps the grid aligned
        cell:SetAlpha(0.2 * alpha)
    end
    cell:Show()
end

local function PlaceBar(draw, sec, x, y, w, h, side)
    draw.bar = draw.bar + 1
    local bar = GetBar(draw.bar)
    local r, g, b = SideColor(side)
    bar:SetColorTexture(r, g, b, 1)
    bar:ClearAllPoints()
    bar:SetPoint("TOPLEFT", panel, "TOPLEFT", x, y)
    bar:SetSize(w, h)
    bar:SetAlpha(sec.alpha(side))
    bar:Show()
end

-- Horizontal: keys run left to right, one row per side, the key label above.
-- Past perLine keys the section wraps into another block underneath.
-- Draws at (ox, oy) from the panel's top left; returns the width and height used.
local function LayoutHorizontal(draw, sec, ox, oy)
    local layer, keys, sides = sec.layer, sec.keys, sec.sides
    local size, gap, per = db.iconSize, db.spacing, db.perLine
    local labelH = LabelHeight()
    local left = db.bars and (BAR_W + BAR_GAP) or 0
    local blocks = ceil(#keys / per)
    local blockH = labelH + #sides * (size + gap) - gap

    for i, key in ipairs(keys) do
        local block, col = floor((i - 1) / per), (i - 1) % per
        local x, y0 = ox + left + col * (size + gap), oy - block * (blockH + BLOCK_GAP)
        local slot = layer.byKey[key]
        for r, side in ipairs(sides) do
            local y = y0 - labelH - (r - 1) * (size + gap)
            if col == 0 and db.bars then PlaceBar(draw, sec, ox, y, BAR_W, size, side) end
            PlaceCell(draw, sec, key, side, x, y, size, slot[side])
        end
        if db.labels then
            PlaceLabel(draw, key, "BOTTOM", x + size / 2, y0 - labelH + 1, sec.labelAlpha)
        end
    end
    return left + min(#keys, per) * (size + gap) - gap, blocks * blockH + (blocks - 1) * BLOCK_GAP
end

-- Vertical: keys run top to bottom, one column per side, the key label to the
-- left. Past perLine keys the section wraps into another block to the right.
local function LayoutVertical(draw, sec, ox, oy)
    local layer, keys, sides = sec.layer, sec.keys, sec.sides
    local size, gap, per = db.iconSize, db.spacing, db.perLine
    local labelW = LabelWidth()
    local top = db.bars and (BAR_W + BAR_GAP) or 0
    local blocks = ceil(#keys / per)
    local blockW = labelW + #sides * (size + gap) - gap

    for i, key in ipairs(keys) do
        local block, row = floor((i - 1) / per), (i - 1) % per
        local x0, y = ox + block * (blockW + BLOCK_GAP), oy - (top + row * (size + gap))
        local slot = layer.byKey[key]
        for c, side in ipairs(sides) do
            local x = x0 + labelW + (c - 1) * (size + gap)
            if row == 0 and db.bars then PlaceBar(draw, sec, x, oy, size, BAR_W, side) end
            PlaceCell(draw, sec, key, side, x, y, size, slot[side])
        end
        if db.labels then
            PlaceLabel(draw, key, "RIGHT", x0 + labelW - 4, y - size / 2, sec.labelAlpha)
        end
    end
    return blocks * blockW + (blocks - 1) * BLOCK_GAP, top + min(#keys, per) * (size + gap) - gap
end

-- The "Visible" setting: always, in a group, in combat, or while a unit frame
-- is under the cursor.
local function VisibleNow()
    if db.visibility == "group" then
        return (IsInGroup and IsInGroup()) and true or false
    elseif db.visibility == "combat" then
        return ((InCombatLockdown and InCombatLockdown())
            or (UnitAffectingCombat and UnitAffectingCombat("player"))) and true or false
    elseif db.visibility == "hover" then
        return hover.onFrame
    end
    return true
end

-- One section per layer to draw. "Held" mode draws the layer for the
-- modifiers held right now (a modifier with nothing bound keeps the unmodified
-- layer up, dimmed). "All" mode draws every layer, and a held modifier dims
-- the layers it does not select.
local function BuildSections(held)
    local sections = {}
    if not layers then return sections end
    local function Add(mods, dim, caption)
        local layer = layers[mods]
        if not layer then return end
        local sides = SidesFor(layer)
        local keys = VisibleKeys(layer, sides)
        if #keys == 0 then return end
        local base = dim and 0.3 or 1
        sections[#sections + 1] = {
            layer = layer, sides = sides, keys = keys, mods = mods, caption = caption,
            labelAlpha = dim and 0.4 or 1,
            alpha = function(side)
                -- The row that does not apply to the hovered unit steps back.
                if db.hoverDim and hover.side and side ~= hover.side then return base * 0.3 end
                return base
            end,
        }
    end
    if db.layers == "all" then
        for _, mods in ipairs(SortedMods(layers)) do      -- "" (no modifier) sorts first
            Add(mods, held ~= "" and mods ~= held, mods ~= "" and ModsLong(mods) or nil)
        end
    elseif layers[held] then
        Add(held, false)
    elseif held ~= "" then
        Add("", true)
    end
    return sections
end

local function RenderNow()
    ResolveFont()
    for _, c in ipairs(cells) do c:Hide() end
    for _, l in ipairs(labels) do l:Hide() end
    for _, g in ipairs(glyphs) do g:Hide() end
    for _, b in ipairs(bars) do b:Hide() end
    for _, c in ipairs(captions) do c:Hide() end

    local unlocked = not db.locked
    ApplyBackground(unlocked)
    panel:EnableMouse(unlocked)

    local held = HeldMods()
    local sections = BuildSections(held)
    local empty = #sections == 0

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

    -- Sections stack downward in the horizontal layout and sit side by side in
    -- the vertical one. A captioned section gets its modifier name on top.
    local draw = { cell = 0, bar = 0, label = 0, glyph = 0 }
    local vertical = db.layout == "vertical"
    local Layout = vertical and LayoutVertical or LayoutHorizontal
    local anyCaption = false
    for _, sec in ipairs(sections) do
        if sec.caption then anyCaption = true end
    end
    local capH = 13
    local x, y, totalW, totalH = 0, 0, 0, 0
    for i, sec in ipairs(sections) do
        local top = y
        if sec.caption or (vertical and anyCaption) then
            if sec.caption then
                local fs = GetCaption(i)
                ApplyFont(fs, 10)
                fs:ClearAllPoints()
                fs:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -y)
                fs:SetText(sec.caption)
                fs:SetAlpha(sec.labelAlpha)
                fs:Show()
            end
            top = y + capH
        end
        local w, h = Layout(draw, sec, x, -top)
        if vertical then
            x = x + w + SECTION_GAP
            totalW, totalH = x - SECTION_GAP, max(totalH, top + h)
        else
            y = top + h + SECTION_GAP
            totalW, totalH = max(totalW, w), y - SECTION_GAP
        end
    end
    panel:SetSize(max(1, totalW), max(1, totalH))

    -- "Held" mode names the modifier layer being shown ("Shift", or
    -- "Shift: none" when the held modifier has nothing bound).
    if db.layers ~= "all" and held ~= "" then
        local dim = sections[1].mods ~= held
        layerText:SetText(dim and (ModsLong(held) .. ": none") or ModsLong(held))
        layerText:Show()
    else
        layerText:Hide()
    end
end

local function Render()
    if db then Safe(RenderNow) end
end

-- Makes the next Refresh redraw even when the bindings have not changed.
function ns.Invalidate() lastSig = nil end

local function RebuildSettingsPages() ns.RebuildSettingsPages() end      -- Options.lua
local function UpdateMinimapButton() if ns.UpdateMinimapButton then ns.UpdateMinimapButton() end end     -- Launcher.lua

local function Refresh(force)
    if not db then return end
    local fresh = CollectLayers()
    local ok, sig, keySig = pcall(Signatures, fresh)
    if not ok then Report(sig); return end
    if force or sig ~= lastSig then
        layers, lastSig = fresh, sig
        ns.Publish("layers", layers)
        Render()
    end
    if force then UpdateMinimapButton() end         -- a setting may have changed
    if keySig ~= lastKeySig then
        local first = lastKeySig == nil
        lastKeySig = keySig
        if not first then RebuildSettingsPages() end
    end
end

-------------------------------------------------------------------------------
--  Position: free on the screen, or attached to the party frames
-------------------------------------------------------------------------------
-- Party frame containers, in order of preference. The first one on screen is
-- used; with none on screen (solo, frames hidden) the saved screen position is.
local ANCHOR_FRAMES = {
    "ERFPartyHeader", "EllesmereUIRaidFrameContainer",
    "CompactPartyFrame", "PartyFrame", "CompactRaidFrameContainer",
}
local ANCHOR_POINTS = {
    above = { "BOTTOM", "TOP", 0, 1 }, below = { "TOP", "BOTTOM", 0, -1 },
    left = { "RIGHT", "LEFT", -1, 0 }, right = { "LEFT", "RIGHT", 1, 0 },
}

local function AnchorTarget()
    if db.anchor ~= "party" then return nil end
    for _, name in ipairs(ANCHOR_FRAMES) do
        local f = _G[name]
        if type(f) == "table" and f.IsVisible then
            local ok, visible = pcall(f.IsVisible, f)
            if ok and visible and not (issecretvalue and issecretvalue(visible)) then return f end
        end
    end
    return nil
end

ApplyPosition = function()
    panel:ClearAllPoints()
    local target = AnchorTarget()
    if target then
        local a = ANCHOR_POINTS[db.anchorSide] or ANCHOR_POINTS.below
        local gap = db.anchorGap + db.bgPadding
        if pcall(panel.SetPoint, panel, a[1], target, a[2], a[3] * gap, a[4] * gap) then
            anchoredTo = target
            return
        end
        panel:ClearAllPoints()
    end
    anchoredTo = nil
    if not pcall(panel.SetPoint, panel, db.point, UIParent, db.relPoint, db.x, db.y) then
        panel:ClearAllPoints()
        panel:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    end
end

-- The party frames come and go (joining a group, leaving it): re-attach when
-- the frame to anchor to has changed. Not in combat, where frames are locked.
local function CheckAnchor()
    if not db or (InCombatLockdown and InCombatLockdown()) then return end
    if AnchorTarget() ~= anchoredTo then ApplyPosition() end
end

-- Ten times a second, look at what is under the cursor. Only when a setting
-- needs it, and only the cheap read: a render happens when the answer changed.
local hoverDriver = CreateFrame("Frame")
local hoverElapsed = 0
hoverDriver:SetScript("OnUpdate", function(_, dt)
    hoverElapsed = hoverElapsed + (dt or 0)
    if hoverElapsed < 0.1 then return end
    hoverElapsed = 0
    if not db or db.hidden or not (db.hoverDim or db.visibility == "hover" or ownSource) then
        if hover.side or hover.onFrame then hover.side, hover.onFrame, hover.dead = nil, false, false end
        return
    end
    if ReadHover() then
        if ownSource then Safe(ns.Refresh, false) end        -- a dead unit can change what a key does
        Render()
    end
end)

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.ACCENT        = ACCENT
ns.ApplyFont     = ApplyFont
ns.ApplyPosition = ApplyPosition
ns.CheckAnchor   = CheckAnchor
ns.OverWorld     = OverWorld
ns.Refresh       = Refresh
ns.Render        = Render
ns.ResolveFont   = ResolveFont
ns.SideColor     = SideColor
