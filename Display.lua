-------------------------------------------------------------------------------
--  ClickLegend - Display.lua
--  The legend itself: the panel, its icons and labels, the layout, and
--  where it sits on screen.
-------------------------------------------------------------------------------
local _, ns = ...

local ipairs, pairs, type, tonumber, tostring, pcall = ipairs, pairs, type, tonumber, tostring, pcall
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
local MOUSE = ns.MOUSE_LAYOUTS                  -- MouseLayout.lua: the pictures and where their buttons are
local SideKeys = ns.SideKeys                    -- Cast.lua: what a block of side buttons sends

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
local mice, lines = {}, {}                      -- the "Mouse picture" layout: the pictures, the lines to the icons

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
    if ownSource then GameTooltip:AddLine("Click to change what this key does.", 0.6, 0.6, 0.6) end
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
        -- Over the icon: the cooldown sweep, the key in a corner (one of the
        -- label styles), the rank of a spell bound to one exact rank, and the
        -- flash when the spell is cast.
        local ok, sweep = pcall(CreateFrame, "Cooldown", nil, cell, "CooldownFrameTemplate")
        if ok and sweep then
            sweep:SetAllPoints(cell.icon)
            if sweep.SetDrawEdge then sweep:SetDrawEdge(false) end
            sweep:Hide()
            cell.sweep = sweep
        end
        cell.over = CreateFrame("Frame", nil, cell)             -- above the sweep
        cell.over:SetAllPoints(cell)
        cell.over:SetFrameLevel((cell:GetFrameLevel() or 1) + 3)
        cell.hotkey = cell.over:CreateFontString(nil, "OVERLAY")
        cell.hotkey:SetPoint("TOPRIGHT", -1, -1)
        cell.rank = cell.over:CreateFontString(nil, "OVERLAY")
        cell.rank:SetPoint("BOTTOMLEFT", 2, 1)
        cell.flash = cell.over:CreateTexture(nil, "ARTWORK")
        cell.flash:SetAllPoints(cell.icon)
        cell.flash:SetColorTexture(1, 1, 1, 1)
        cell.flash:SetAlpha(0)
        -- Mouse is only enabled while unlocked; a drag on an icon moves the legend.
        cell:RegisterForDrag("LeftButton")
        cell:SetScript("OnDragStart", function() cell.dragged = true; DragStart() end)
        cell:SetScript("OnDragStop", DragStop)
        -- A click (not a drag) on one of ClickLegend's own keys opens it in the editor.
        cell:SetScript("OnMouseDown", function() cell.dragged = false end)
        -- With a spell held on the cursor (dragged from the spellbook) the click,
        -- or letting the spell go here, puts it on that key instead.
        local function Dropped(self)
            if not (ownSource and self.key and ns.DropOnKey and GetCursorInfo) then return false end
            local ok, held = pcall(GetCursorInfo)
            if not (ok and held) then return false end
            Safe(ns.DropOnKey, (self.mods or "") .. self.key)
            return true
        end
        cell:SetScript("OnMouseUp", function(self, button)
            if button ~= "LeftButton" or self.dragged or Dropped(self) then return end
            if ownSource and self.key and ns.OpenKey then
                Safe(ns.OpenKey, (self.mods or "") .. self.key)
            end
        end)
        cell:SetScript("OnReceiveDrag", Dropped)
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

-- The key each region of a mouse picture shows. A block of side buttons
-- shows what the player's own buttons send, once the guided setup has
-- learned that; until then they are taken to be mouse buttons 4 and up.
local function MouseKeys(L)
    local learned = L.grid and SideKeys() or nil
    if not (learned and next(learned)) then return L.keys end
    local inBlock, keys = {}, {}
    for _, region in ipairs(L.grid.regions) do inBlock[region] = true end
    for key, region in pairs(L.keys) do
        if not inBlock[region] then keys[key] = region end
    end
    for n, key in pairs(learned) do
        if L.grid.regions[n] then keys[key] = L.grid.regions[n] end
    end
    return keys
end

-------------------------------------------------------------------------------
--  Label glyphs: the "Icons" label style draws a small mouse with the bound
--  button lit, and a keycap for keyboard keys. The mouse is the picked
--  picture (MouseLayout.lua): one image holds the whole mouse and each of
--  its buttons on its own, and the button is drawn over the mouse in white.
--  The keycap, and the mouse when there is no picture, are plain coloured
--  rectangles.
-------------------------------------------------------------------------------
-- Shows one cell of a picture's small image in a texture.
local function ShowCell(tex, small, cell)
    local n = small.columns
    local col, row = cell % n, floor(cell / n)
    tex:SetTexture(small.texture)
    tex:SetTexCoord(col / n, (col + 1) / n, row / n, (row + 1) / n)
    tex:Show()
end
-- Width, height, half width and button-zone height of the mouse body.
local function GlyphSize()
    local gh = db.labelSize + 5
    local half = floor(gh * 0.36 + 0.5)
    return half * 2 + 1, gh, half, floor(gh * 0.45 + 0.5)
end

-- The side of the square the mouse picture is drawn in as a label: about three
-- times the label size and at least four fifths of a spell icon, so that it
-- reads beside one, and never larger than an icon, or the labels of
-- neighbouring keys would meet.
local function ArtSide()
    local least = db.labelSize + 11
    local wanted = max(db.labelSize * 3 + 2, floor(db.iconSize * 0.8))
    return max(least, min(wanted, db.iconSize))
end

-- True when the labels are the mouse picture (and not the drawn rectangles).
local function ArtLabels()
    local L = MOUSE and (MOUSE[db.mousePic] or MOUSE.a)
    return db.labelStyle == "icon" and L and L.small and true or false
end

-- The height the label row needs (horizontal layout) for the current style.
local function LabelHeight()
    if not db.labels or db.labelStyle == "corner" then return 0 end
    if ArtLabels() then return ArtSide() + 1 end
    if db.labelStyle == "icon" then return db.labelSize + 12 end
    return db.labelSize + 3
end

-- The width the label column needs (vertical layout).
local function LabelWidth()
    if not db.labels or db.labelStyle == "corner" then return 0 end
    if ArtLabels() then return max(db.labelSize * 3 + 7, ArtSide() + 5) end
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
        g.art = g:CreateTexture(nil, "BORDER")              -- the mouse picture, and the lit button over it
        g.art:SetAllPoints()
        g.artLit = g:CreateTexture(nil, "ARTWORK")
        g.artLit:SetAllPoints()
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
    g.art:Hide()
    g.artLit:Hide()
    g.outline:Show()
    g.body:Show()

    -- The picture of the mouse, with this key's button lit. A key the mouse
    -- has no button for falls through to the drawn ones below: a keycap for
    -- a keyboard key, the mouse with a number for an extra mouse button.
    local L = MOUSE and (MOUSE[db.mousePic] or MOUSE.a)
    local small = L and L.small
    local region = small and MouseKeys(L)[key]
    local cell = region and small.cells[region]
    if cell or (small and MouseRank(key)) then
        local side = ArtSide()                              -- square: the picture carries its own margins
        g:SetSize(side, side)
        g.outline:Hide()
        g.body:Hide()
        ShowCell(g.art, small, 0)
        if g.art.SetVertexColor then g.art:SetVertexColor(0.55, 0.57, 0.62) end
        if cell then
            ShowCell(g.artLit, small, cell)
            if key == "MOUSEWHEELUP" or key == "MOUSEWHEELDOWN" then
                -- The wheel alone would read as a middle click: an arrow in the
                -- palm says which way it turns.
                local top = floor(side * 0.62)
                local u = max(1, floor(side / 14))          -- the arrow grows with the picture
                for row = 1, 3 do
                    local w = ((key == "MOUSEWHEELUP") and (row * 2 - 1) or (7 - row * 2)) * u
                    GlyphRect(g, g.tri[row], (side - 2) / 2 - w / 2, top + (row - 1) * u, w, u)
                end
            end
        else
            local n = key:match("^BUTTON(%d+)$")                    -- a button the picture does not have
            GlyphText(g, n or "", max(6, db.labelSize), (side - 2) / 2, side * 0.68)
        end
        return
    end

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
        local applies = not (db.hoverDim and db.offStyle == "hide" and hover.side and side ~= hover.side)
        if has[side] and applies and (db.rows == "both" or db.rows == side) then sides[#sides + 1] = side end
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

-- Why the entry's spell cannot be cast at this moment, or false when it can:
--   "range"     the unit under the cursor is of this row's side and out of range
--               (for a rule about a unit of its own: that unit is out of range)
--   "mana"      not enough mana, rage or energy
--   "cooldown"  on cooldown, longer than the global one (start and length follow)
--   "other"     the game says it is not usable, for some other reason
-- Anything the game will not tell (it hides some of this in combat) counts as
-- castable.
local function Known(v)
    return v ~= nil and not (issecretvalue and issecretvalue(v))
end

local function CannotCast(entry, side)
    local id = entry.spellID
    if not (id and C_Spell) or entry.missing then return false end
    if (entry.unit or hover.side == side) and C_Spell.IsSpellInRange then
        local ok, inRange = pcall(C_Spell.IsSpellInRange, id, entry.unit or "mouseover")
        if ok and Known(inRange) and inRange == false then return "range" end
    end
    if C_Spell.GetSpellCooldown then
        local ok, info = pcall(C_Spell.GetSpellCooldown, id)
        if ok and type(info) == "table" and not (issecretvalue and issecretvalue(info)) then
            local start, length = info.startTime, info.duration
            if Known(start) and Known(length) and type(start) == "number" and type(length) == "number"
                and start > 0 and length > 1.5 then
                return "cooldown", start, length
            end
        end
    end
    if C_Spell.IsSpellUsable then
        local ok, usable, noPower = pcall(C_Spell.IsSpellUsable, id)
        if ok and Known(usable) and usable == false then
            return (Known(noPower) and noPower == true) and "mana" or "other"
        end
    end
    return false
end

-- One character per spell on the legend: whether it can be cast now. The
-- legend is redrawn when this changes.
local function CastableSignature()
    if not layers then return "" end
    local parts = {}
    for _, layer in pairs(layers) do
        for _, slot in pairs(layer.byKey) do
            if slot.ally and slot.ally.spellID then parts[#parts + 1] = (CannotCast(slot.ally, "ally") or "-"):sub(1, 1) end
            if slot.enemy and slot.enemy.spellID then parts[#parts + 1] = (CannotCast(slot.enemy, "enemy") or "-"):sub(1, 1) end
        end
    end
    return table.concat(parts)
end

-- How an icon looks for each reason its spell cannot be cast: the setting
-- that holds its tint (by default orange out of range, blue without the
-- mana, grey on cooldown under the sweep) and how far it is faded. Not red
-- for range: red is what the enemy side is drawn in by default.
local REASON_LOOK = {
    range = { "far", 0.85 }, mana = { "mana", 0.85 },
    cooldown = { "cool", 0.8 }, other = { nil, 0.45 },
}

-- sec: the section being drawn ({ mods, alpha = function(side) }). `keyed`:
-- this is the cell that carries the key's name in the "On the icon" style.
local function PlaceCell(draw, sec, key, side, x, y, size, entry, keyed)
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
        local reason, start, length = false, nil, nil
        if not broken and db.flagUnusable then reason, start, length = CannotCast(entry, side) end
        if reason == "range" and db.offStyle == "hide" then
            entry = nil                     -- shown as an empty place: it will not work on this unit
        else
            local look = reason and REASON_LOOK[reason]
            if cell.icon.SetVertexColor then
                local tint = look and look[1]
                cell.icon:SetVertexColor(tint and db[tint .. "R"] or 1, tint and db[tint .. "G"] or 1, tint and db[tint .. "B"] or 1)
            end
            cell:SetAlpha(broken and alpha * 0.45 or (look and alpha * look[2]) or alpha)
            if cell.sweep then
                if reason == "cooldown" then
                    cell.sweep:SetCooldown(start, length)
                    cell.sweep:Show()
                else
                    cell.sweep:Hide()
                end
            end
        end
    end
    if entry then
        local showKey = keyed and db.labels and db.labelStyle == "corner"
        cell.hotkey:SetShown(showKey and true or false)
        if showKey then
            ApplyFont(cell.hotkey, max(6, min(db.labelSize, floor(size * 0.45))))
            cell.hotkey:SetText(ShortKey(key))
        end
        cell.rank:SetShown(entry.rank ~= nil)
        if entry.rank then
            ApplyFont(cell.rank, max(6, min(db.labelSize, floor(size * 0.4))))
            cell.rank:SetText(tostring(entry.rank))
            cell.rank:SetTextColor(1, 0.82, 0)
        end
    else
        cell.icon:Hide()                    -- empty slot keeps the grid aligned
        cell.hotkey:Hide()
        cell.rank:Hide()
        if cell.sweep then cell.sweep:Hide() end
        cell:SetAlpha(0.2 * alpha)
    end
    cell:Show()
end

-- The side whose cell carries the key's name in the "On the icon" style: the
-- first one drawn that has something bound.
local function KeyedSide(slot, sides)
    for _, side in ipairs(sides) do
        if slot[side] then return side end
    end
    return nil
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
        local keyed = KeyedSide(slot, sides)
        for r, side in ipairs(sides) do
            local y = y0 - labelH - (r - 1) * (size + gap)
            if col == 0 and db.bars then PlaceBar(draw, sec, ox, y, BAR_W, size, side) end
            PlaceCell(draw, sec, key, side, x, y, size, slot[side], side == keyed)
        end
        if db.labels and db.labelStyle ~= "corner" then
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
        local keyed = KeyedSide(slot, sides)
        for c, side in ipairs(sides) do
            local x = x0 + labelW + (c - 1) * (size + gap)
            if row == 0 and db.bars then PlaceBar(draw, sec, x, oy, size, BAR_W, side) end
            PlaceCell(draw, sec, key, side, x, y, size, slot[side], side == keyed)
        end
        if db.labels and db.labelStyle ~= "corner" then
            if db.labelStyle == "icon" then                 -- a picture sits in the middle of its column
                PlaceLabel(draw, key, "CENTER", x0 + (labelW - 4) / 2, y - size / 2, sec.labelAlpha)
            else
                PlaceLabel(draw, key, "RIGHT", x0 + labelW - 4, y - size / 2, sec.labelAlpha)
            end
        end
    end
    return blocks * blockW + (blocks - 1) * BLOCK_GAP, top + min(#keys, per) * (size + gap) - gap
end

-------------------------------------------------------------------------------
--  Mouse picture: a mouse seen from above, with the spells of each button
--  beside it and a line from the button to them. Every position comes from
--  the points in MouseLayout.lua and the size the picture is drawn at, so it
--  can be drawn at any size.
--    left of the picture   the left button and the side buttons (or, on a
--                          mouse with a block of side buttons, that block)
--    right of it           the wheel's three keys stacked, then the right button
--    under it              every key with no place on a mouse
-------------------------------------------------------------------------------
local function GetMouse(i)
    local tex = mice[i]
    if not tex then
        tex = panel:CreateTexture(nil, "ARTWORK")
        mice[i] = tex
    end
    return tex
end

-- One straight piece of a line, level or upright, `t` thick. Points are
-- measured from the panel's top left, y downward.
local function Segment(draw, x1, y1, x2, y2, t, alpha)
    draw.line = draw.line + 1
    local tex = lines[draw.line]
    if not tex then
        tex = panel:CreateTexture(nil, "BORDER")
        lines[draw.line] = tex
    end
    local x, y = min(x1, x2), min(y1, y2)
    local w, h = max(x1, x2) - x, max(y1, y2) - y
    tex:SetColorTexture(ACCENT[1], ACCENT[2], ACCENT[3], 0.8)
    tex:ClearAllPoints()
    if h < w then                               -- level
        tex:SetPoint("TOPLEFT", panel, "TOPLEFT", x, -(y - t / 2))
        tex:SetSize(w, t)
    else                                        -- upright; the ends cover the corners
        tex:SetPoint("TOPLEFT", panel, "TOPLEFT", x - t / 2, -(y - t / 2))
        tex:SetSize(t, h + t)
    end
    tex:SetAlpha(alpha)
    tex:Show()
end

-- Tops for the entries of one column, each as near its own height as the
-- others allow: none overlapping, and none below `bottom` unless the column
-- is simply too tall. Returns the top of the first.
local function StackColumn(col, vgap, bottom)
    table.sort(col, function(a, b) return a.order < b.order end)
    local floorY = nil
    for _, e in ipairs(col) do                  -- push down past the one above
        e.top = e.want - e.h / 2
        if floorY and e.top < floorY then e.top = floorY end
        floorY = e.top + e.h + vgap
    end
    local ceilY = bottom
    for i = #col, 1, -1 do                      -- pull up past the bottom, and past the one below
        local e = col[i]
        if e.top + e.h > ceilY then e.top = ceilY - e.h end
        ceilY = e.top - vgap
    end
    return col[1] and col[1].top or 0
end

local function LayoutMouse(draw, sec, ox, oy)
    local L = MOUSE[db.mousePic] or MOUSE.a
    local keyRegion = MouseKeys(L)
    local layer, sides = sec.layer, sec.sides
    local size, gap = db.iconSize, db.spacing
    local S = db.mouseSize
    local k = S / L.size                                    -- picture units to pixels
    local lead = max(4, floor(16 * k + 0.5))                -- the shortest a line may be
    local thick = max(1, floor(5 * k + 0.5))
    local barH = db.bars and 2 or 0                         -- a line in the side's colour under each icon
    local vgap = max(2, gap) + barH
    local groupW = #sides * (size + gap) - gap              -- the icons of one key, side by side
    local corner = db.labels and db.labelStyle == "corner"
    local labelW = (db.labels and not corner) and (LabelWidth() - 4) or 0

    local bound = {}
    for _, key in ipairs(sec.keys) do bound[key] = true end
    local regionKeys = {}                                   -- region -> its bound keys, in the layer's order
    for _, key in ipairs(sec.keys) do
        local region = keyRegion[key]
        if region then
            regionKeys[region] = regionKeys[region] or {}
            table.insert(regionKeys[region], key)
            bound[key] = nil
        end
    end
    local rest = {}                                         -- keys with no place on the picture
    for _, key in ipairs(sec.keys) do
        if bound[key] then rest[#rest + 1] = key end
    end

    -- The columns. Where the icons stand is fixed by the picture alone (the
    -- outermost line start on that side, and a lead), so that binding or
    -- unbinding a button moves nothing else.
    local left, right = {}, {}
    local leftEdge, rightEdge = L.size, 0
    for _, region in ipairs(L.left) do leftEdge = min(leftEdge, L.regions[region].calloutX) end
    for _, region in ipairs(L.right) do rightEdge = max(rightEdge, L.regions[region].calloutX) end
    local gridCols, gridRows, gridX, gridY = 0, 0, L.size, 0
    local gridKey = {}                                      -- region of the block -> the key it stands for
    if L.grid then
        for key, region in pairs(keyRegion) do gridKey[region] = key end
        gridCols = L.grid.columns
        gridRows = ceil(#L.grid.regions / gridCols)
        for _, region in ipairs(L.grid.regions) do
            local r = L.regions[region]
            gridX, gridY = min(gridX, r.calloutX), gridY + r.cy / #L.grid.regions
        end
        leftEdge = min(leftEdge, gridX)
    end
    -- Never inside the drawing: on some mice a button's edge is within the body.
    leftEdge, rightEdge = min(leftEdge, L.bounds[1]) * k - lead, max(rightEdge, L.bounds[3]) * k + lead

    for i, region in ipairs(L.left) do
        local keys = regionKeys[region]
        if keys then
            local r = L.regions[region]
            left[#left + 1] = { order = i, keys = keys, x = r.calloutX * k, y = r.calloutY * k, want = r.calloutY * k,
                                w = groupW, h = #keys * (size + vgap) - vgap }
        end
    end
    local gridEntry
    if L.grid then
        local any = false
        for _, region in ipairs(L.grid.regions) do any = any or regionKeys[region] ~= nil end
        if any then
            gridEntry = { order = 100, grid = true, x = gridX * k, y = gridY * k, want = gridY * k,
                          w = gridCols * (groupW + 2 * gap) - 2 * gap, h = gridRows * (size + vgap) - vgap }
            left[#left + 1] = gridEntry
        end
    end
    -- The wheel's line goes up out of the picture and then across, so its keys
    -- start level with that turn, above the right button's.
    local wheelKeys, wheel = {}, L.regions[L.wheel]
    for _, key in ipairs(L.wheelKeys) do
        for _, has in ipairs(regionKeys[L.wheel] or {}) do
            if has == key then wheelKeys[#wheelKeys + 1] = key end
        end
    end
    local turnY = L.bounds[2] * k * 0.5                     -- half way up the clear strip above the mouse
    if #wheelKeys > 0 then
        local h = #wheelKeys * (size + vgap) - vgap
        right[#right + 1] = { order = 0, wheel = true, keys = wheelKeys, x = wheel.calloutX * k, y = wheel.calloutY * k,
                              want = turnY + h / 2, w = groupW + labelW, h = h }
    end
    for i, region in ipairs(L.right) do
        local keys = regionKeys[region]
        if keys then
            local r = L.regions[region]
            right[#right + 1] = { order = i, keys = keys, x = r.calloutX * k, y = r.calloutY * k, want = r.calloutY * k,
                                  w = groupW, h = #keys * (size + vgap) - vgap }
        end
    end

    -- Room: the picture moves right when the icons on its left need more
    -- than its own clear margin, and down when a column starts above it.
    local leftW, rightW = 0, 0
    for _, e in ipairs(left) do leftW = max(leftW, e.w) end
    for _, e in ipairs(right) do rightW = max(rightW, e.w) end
    local topL, topR = StackColumn(left, vgap, S), StackColumn(right, vgap, S)
    local px = #left > 0 and max(0, ceil(leftW - leftEdge)) or 0
    local py = max(0, ceil(-min(topL, topR)))
    local bottom = S
    for _, col in ipairs({ left, right }) do
        local last = col[#col]
        if last then bottom = max(bottom, last.top + last.h + (db.bars and barH + 1 or 0)) end
    end

    -- The picture, tinted like the rest of the addon.
    draw.mouse = draw.mouse + 1
    local tex = GetMouse(draw.mouse)
    tex:SetTexture(L.texture)
    if tex.SetVertexColor then tex:SetVertexColor(ACCENT[1], ACCENT[2], ACCENT[3]) end
    tex:ClearAllPoints()
    tex:SetPoint("TOPLEFT", panel, "TOPLEFT", ox + px, oy - py)
    tex:SetSize(S, S)
    tex:SetAlpha(sec.labelAlpha)
    tex:Show()

    -- Everything below is measured from the section's top left, y downward.
    local function Line(x1, y1, x2, y2)
        Segment(draw, ox + x1, -oy + y1, ox + x2, -oy + y2, thick, sec.labelAlpha)
    end
    -- From a button's edge to the icons: straight across when they are level
    -- with it, else across, up or down, and across again.
    local function Leader(fromX, fromY, toX, toY)
        if toY > fromY - 1 and toY < fromY + 1 then
            Line(fromX, fromY, toX, fromY)
        else
            local midX = toX + (fromX > toX and 1 or -1) * lead / 2
            Line(fromX, fromY, midX, fromY)
            Line(midX, fromY, midX, toY)
            Line(midX, toY, toX, toY)
        end
    end
    local function Group(key, x, y, keyed)
        local slot = layer.byKey[key] or {}                 -- nothing bound: empty places
        local named = KeyedSide(slot, sides)
        for s, side in ipairs(sides) do
            local cx = x + (s - 1) * (size + gap)
            PlaceCell(draw, sec, key, side, ox + cx, oy - y, size, slot[side], keyed and side == named)
            if db.bars then PlaceBar(draw, sec, ox + cx, oy - y - size - 1, size, barH, side) end
        end
    end

    for _, e in ipairs(left) do
        local edge = px + leftEdge                          -- the icons' right-hand side
        local top = py + e.top
        if e.grid then
            -- Every place of the block is drawn, bound or not, so that a
            -- spell's place in it says which button it is on.
            for n, region in ipairs(L.grid.regions) do
                local col, row = (n - 1) % gridCols, floor((n - 1) / gridCols)
                Group(regionKeys[region] and regionKeys[region][1] or gridKey[region] or region,
                    edge - e.w + col * (groupW + 2 * gap), top + row * (size + vgap), false)
            end
        else
            for i, key in ipairs(e.keys) do
                Group(key, edge - groupW, top + (i - 1) * (size + vgap), false)
            end
        end
        Leader(px + e.x, py + e.y, edge, top + e.h / 2)
    end
    for _, e in ipairs(right) do
        local edge = px + rightEdge                         -- the icons' left-hand side
        local top = py + e.top
        for i, key in ipairs(e.keys) do
            local y = top + (i - 1) * (size + vgap)
            Group(key, edge, y, e.wheel and corner)
            if e.wheel then
                -- Three keys share the wheel: each is named, and each gets a
                -- short line off the upright one.
                if db.labels and not corner then
                    PlaceLabel(draw, key, "LEFT", ox + edge + groupW + 4, oy - (y + size / 2), sec.labelAlpha)
                end
                Line(edge - lead / 2, y + size / 2, edge, y + size / 2)
            end
        end
        if e.wheel then
            local busX, firstY, lastY = edge - lead / 2, top + size / 2, top + e.h - size / 2
            Line(px + e.x, py + e.y, px + e.x, py + turnY)              -- up out of the picture
            Line(px + e.x, py + turnY, busX, py + turnY)                -- across to the icons
            Line(busX, min(py + turnY, firstY), busX, max(py + turnY, lastY))
        else
            Leader(px + e.x, py + e.y, edge, top + e.h / 2)
        end
    end

    local w = px + max(S, #right > 0 and (rightEdge + rightW) or 0)
    local h = py + bottom
    if #rest > 0 then
        local under = { layer = layer, sides = sides, keys = rest, mods = sec.mods, alpha = sec.alpha, labelAlpha = sec.labelAlpha }
        local w2, h2 = LayoutHorizontal(draw, under, ox, oy - h - BLOCK_GAP)
        w, h = max(w, w2), h + BLOCK_GAP + h2
    end
    return w, h
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

local fadeIn = nil                  -- 0 to 1 while the legend fades in, nil when it is steady
local FADE_SECONDS = 0.15

local function RenderNow()
    ResolveFont()
    for _, c in ipairs(cells) do c:Hide() end
    for _, l in ipairs(labels) do l:Hide() end
    for _, g in ipairs(glyphs) do g:Hide() end
    for _, b in ipairs(bars) do b:Hide() end
    for _, c in ipairs(captions) do c:Hide() end
    for _, m in ipairs(mice) do m:Hide() end
    for _, l in ipairs(lines) do l:Hide() end

    local unlocked = not db.locked
    ApplyBackground(unlocked)
    panel:EnableMouse(unlocked)

    local held = HeldMods()
    local sections = BuildSections(held)
    local empty = #sections == 0

    -- While unlocked the legend stays up whatever the visibility rule says,
    -- so there is always something to drag. With nothing to draw (nothing
    -- bound, or nothing on the layer in view: the plain clicks hidden and the
    -- rest behind a modifier) that is an empty box, which is only worth
    -- showing while the settings are open.
    local window = empty and ns.GetWindow and ns.GetWindow()
    local idle = empty and not (window and window:IsShown())
    if db.hidden or idle or ((empty or not VisibleNow()) and not unlocked) then
        panel:Hide()
        return
    end
    if not panel:IsShown() then fadeIn = 0 end             -- coming back: fade in
    panel:Show()
    panel:SetScale(db.scale)
    panel:SetAlpha(db.alpha * (fadeIn or 1))
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
    local draw = { cell = 0, bar = 0, label = 0, glyph = 0, mouse = 0, line = 0 }
    local vertical = db.layout == "vertical"
    local Layout = vertical and LayoutVertical or LayoutHorizontal
    if db.layout == "mouse" and MOUSE then Layout = LayoutMouse end     -- sections stack downward, as in horizontal
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

-- Puts the legend beside the cursor, on the chosen side.
local function FollowCursor()
    if not GetCursorPosition then return false end
    local ok, cx, cy = pcall(GetCursorPosition)
    local scale = panel.GetEffectiveScale and panel:GetEffectiveScale() or 1
    if not ok or type(cx) ~= "number" or type(cy) ~= "number" or type(scale) ~= "number" or scale <= 0 then return false end
    local a = ANCHOR_POINTS[db.anchorSide] or ANCHOR_POINTS.below
    local gap = db.anchorGap + db.bgPadding + 14            -- clear of the pointer itself
    panel:ClearAllPoints()
    return pcall(panel.SetPoint, panel, a[1], UIParent, "BOTTOMLEFT", cx / scale + a[3] * gap, cy / scale + a[4] * gap)
end

local function AnchorTarget()
    if db.anchor == "cursor" then return GetCursorPosition and "cursor" or nil end
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
    if target == "cursor" then
        if FollowCursor() then
            anchoredTo = target
            return
        end
        panel:ClearAllPoints()
        target = nil
    end
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
local castableSig = ""
local flashing = {}                 -- cells that are flashing now

-- The spell that was just cast flashes on the legend. Matched by id, or by
-- name: a spell bound by name casts whichever rank is the highest.
local function SpellCast(spellID)
    if not (db and db.flash and panel:IsShown()) or spellID == nil then return end
    if issecretvalue and issecretvalue(spellID) then return end
    local name
    if C_Spell and C_Spell.GetSpellName then
        local ok, n = pcall(C_Spell.GetSpellName, spellID)
        name = ok and type(n) == "string" and n or nil
    end
    for _, cell in ipairs(cells) do
        local entry = cell.entry
        if type(entry) == "table" and cell:IsShown() and (entry.spellID == spellID or (name and entry.name == name)) then
            cell.flashLeft = 0.3
            cell.flash:SetAlpha(0.6)
            flashing[cell] = true
        end
    end
end

hoverDriver:SetScript("OnUpdate", function(_, dt)
    dt = dt or 0
    if anchoredTo == "cursor" and panel:IsShown() then FollowCursor() end
    if fadeIn and db then
        fadeIn = fadeIn + dt / FADE_SECONDS
        if fadeIn >= 1 then fadeIn = nil end
        panel:SetAlpha(db.alpha * (fadeIn or 1))
    end
    for cell in pairs(flashing) do
        cell.flashLeft = cell.flashLeft - dt
        if cell.flashLeft <= 0 then
            cell.flash:SetAlpha(0)
            flashing[cell] = nil
        else
            cell.flash:SetAlpha(0.6 * cell.flashLeft / 0.3)
        end
    end
    hoverElapsed = hoverElapsed + dt
    if hoverElapsed < 0.1 then return end
    hoverElapsed = 0
    if not db or db.hidden or not (db.hoverDim or db.visibility == "hover" or ownSource or db.flagUnusable) then
        if hover.side or hover.onFrame then hover.side, hover.onFrame, hover.dead = nil, false, false end
        return
    end
    local redraw = ReadHover()
    if redraw and ownSource then Safe(ns.Refresh, false) end        -- a dead unit can change what a key does
    if db.flagUnusable then
        local ok, sig = pcall(CastableSignature)
        if not ok then Report(sig) elseif sig ~= castableSig then castableSig = sig; redraw = true end
    end
    if redraw then Render() end
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
ns.SpellCast     = SpellCast
-- For looking at a drawing.
ns.LegendPieces   = function() return { mice = mice, lines = lines, cells = cells, bars = bars, labels = labels, glyphs = glyphs } end
ns.SideColor     = SideColor
