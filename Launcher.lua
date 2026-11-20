-------------------------------------------------------------------------------
--  ClickLegend - Launcher.lua
--  Two ways in for someone who has not typed /clg yet: a minimap button with
--  the addon's logo, and a welcome window shown once after installing or
--  updating to 2.0. Someone who has already seen that window gets the same
--  window once more, saying what is new and offering the guided setup again,
--  when an update brings something worth knowing about.
-------------------------------------------------------------------------------
local _, ns = ...

local type, pcall, tonumber, ipairs = type, pcall, tonumber, ipairs
local cos, sin, rad, deg, atan2, max = math.cos, math.sin, math.rad, math.deg, math.atan2, math.max

local db
ns.Subscribe("db", function(value) db = value end)

local NewButton, NewText, Safe, Skin =
    ns.NewButton, ns.NewText, ns.Safe, ns.Skin
local ACCENT = Skin.ACCENT
local OpenGuidedSetup, ToggleWindow =
    ns.OpenGuidedSetup, ns.ToggleWindow
local AddSet, BuildTemplate, SelectSet, Edit =
    ns.AddSet, ns.BuildTemplate, ns.SelectSet, ns.CastEdit
local SetCastEnabled, SetCastTargetEnemy, SetSettings =
    ns.SetCastEnabled, ns.SetCastTargetEnemy, ns.SetSettings
local ListTemplates, SpecTemplate, ShowMenu, CloseMenu, Print =
    ns.ListTemplates, ns.SpecTemplate, ns.ShowMenu, ns.CloseMenu, ns.Print

local LOGO = "Interface\\AddOns\\ClickLegend\\ClickLegend-Logo.png"
-- The logo is the legend's grid on a dark square; this is the grid alone.
local LOGO_CROP = { 0.09, 0.91, 0.30, 0.70 }

-------------------------------------------------------------------------------
--  Minimap button. Left click: the settings window. Right click: guided
--  setup. Drag: move it round the minimap.
-------------------------------------------------------------------------------
local button

local function PlaceButton()
    if not (button and db and Minimap) then return end
    local angle = rad(db.minimapAngle)
    local radius = max(Minimap:GetWidth() or 140, Minimap:GetHeight() or 140) / 2 + 5
    button:ClearAllPoints()
    button:SetPoint("CENTER", Minimap, "CENTER", cos(angle) * radius, sin(angle) * radius)
end

local function DragButton()
    local mx, my = Minimap:GetCenter()
    local cx, cy = GetCursorPosition()
    local scale = Minimap:GetEffectiveScale() or 1
    if not (mx and my and cx and cy) then return end
    local angle = deg(atan2(cy / scale - my, cx / scale - mx))
    db.minimapAngle = angle < 0 and angle + 360 or angle
    PlaceButton()
end

local function BuildButton()
    local b = CreateFrame("Button", "ClickLegendMinimapButton", Minimap)
    b:SetSize(32, 32)
    b:SetFrameStrata("MEDIUM")
    b:SetFrameLevel(8)
    b:RegisterForClicks("AnyUp")
    b:RegisterForDrag("LeftButton")
    local back = b:CreateTexture(nil, "BACKGROUND")
    back:SetSize(24, 24)
    back:SetPoint("CENTER")
    back:SetTexture("Interface\\Minimap\\UI-Minimap-Background")
    b:SetHighlightTexture("Interface\\Minimap\\UI-Minimap-ZoomButton-Highlight", "ADD")
    local icon = b:CreateTexture(nil, "ARTWORK")
    icon:SetSize(22, 11)                        -- the grid is twice as wide as it is tall
    icon:SetPoint("CENTER")
    icon:SetTexture(LOGO)
    icon:SetTexCoord(LOGO_CROP[1], LOGO_CROP[2], LOGO_CROP[3], LOGO_CROP[4])
    local ring = b:CreateTexture(nil, "OVERLAY")
    ring:SetSize(54, 54)
    ring:SetPoint("TOPLEFT")
    ring:SetTexture("Interface\\Minimap\\MiniMap-TrackingBorder")
    b:SetScript("OnClick", function(_, mouse)
        if mouse == "RightButton" then Safe(OpenGuidedSetup) else Safe(ToggleWindow) end
    end)
    b:SetScript("OnDragStart", function(self) self:SetScript("OnUpdate", function() Safe(DragButton) end) end)
    b:SetScript("OnDragStop", function(self) self:SetScript("OnUpdate", nil) end)
    b:SetScript("OnEnter", function(self)
        if not GameTooltip then return end
        GameTooltip:SetOwner(self, "ANCHOR_LEFT")
        GameTooltip:SetText("ClickLegend", ACCENT[1], ACCENT[2], ACCENT[3])
        GameTooltip:AddLine("Click: settings", 1, 1, 1)
        GameTooltip:AddLine("Right click: guided setup", 1, 1, 1)
        GameTooltip:AddLine("Drag: move this button", 0.6, 0.6, 0.6)
        GameTooltip:Show()
    end)
    b:SetScript("OnLeave", function() if GameTooltip then GameTooltip:Hide() end end)
    return b
end

-- Shows, hides and places the button to match the settings.
local function UpdateMinimapButton()
    if not (db and Minimap) then return end
    if db.minimap and not button then
        local ok, built = pcall(BuildButton)
        if not ok then ns.Report(built); return end
        button = built
    end
    if button then
        button:SetShown(db.minimap)
        if db.minimap then PlaceButton() end
    end
end

-------------------------------------------------------------------------------
--  Welcome: once per account, the first time a version with its own click
--  casting is run. It offers the two places to begin and never comes back.
-------------------------------------------------------------------------------
local WELCOME_VERSION = 2
local CARD_W = 540
local welcome
local quickPick                     -- the starter set picked on the quickstart page
local QuickPage, QuickApply         -- below: the quickstart page of the same window

local function Seen()
    if type(ClickLegendCastDB) == "table" then ClickLegendCastDB.welcomed = WELCOME_VERSION end
    if welcome then welcome:Hide() end
end

local function BuildWelcome()
    local f = Skin.Panel("ClickLegendWelcome", UIParent, "ClickLegend")
    f:SetSize(CARD_W, 250)
    f:SetPoint("CENTER", 0, 60)
    f:SetFrameStrata("DIALOG")
    f:EnableMouse(true)
    f:Hide()

    local logo = f:CreateTexture(nil, "ARTWORK")
    logo:SetSize(120, 60)
    logo:SetPoint("TOP", 0, -30)
    logo:SetTexture(LOGO)
    logo:SetTexCoord(LOGO_CROP[1], LOGO_CROP[2], LOGO_CROP[3], LOGO_CROP[4])

    -- What it says is set each time it is shown: the welcome, or what is new.
    local title = NewText(f, 16, ACCENT[1], ACCENT[2], ACCENT[3])
    title:SetPoint("TOP", 0, -98)
    local text = NewText(f, 11, 0.85, 0.85, 0.85)
    text:SetPoint("TOP", 0, -124)
    text:SetWidth(CARD_W - 40)
    f.title, f.text = title, text

    local guide = NewButton(f, 120, 26, "Guided setup")
    guide:SetPoint("BOTTOMLEFT", 16, 16)
    Skin.Emph(guide)
    guide:SetScript("OnClick", function() Seen(); Safe(OpenGuidedSetup) end)
    local quick = NewButton(f, 160, 26, "Class Spec Quickstart")
    quick:SetPoint("LEFT", guide, "RIGHT", 8, 0)
    Skin.Emph(quick)
    quick:SetScript("OnClick", function() Safe(QuickPage, true) end)
    local settings = NewButton(f, 110, 26, "Open settings")
    settings:SetScript("OnClick", function() Seen(); Safe(ToggleWindow, true) end)
    local later = NewButton(f, 80, 26, "Not now")
    later:SetPoint("BOTTOMRIGHT", -16, 16)
    later:SetScript("OnClick", Seen)
    f.guide, f.quick, f.settings, f.later = guide, quick, settings, later

    -- The quickstart page: one list of starter sets, then Okay or Back.
    local pickLabel = NewText(f, 12)
    pickLabel:SetText("Starter set")
    local pick = NewButton(f, 260, 24)
    pick:SetPoint("TOPLEFT", text, "BOTTOMLEFT", 100, -14)
    pickLabel:SetPoint("RIGHT", pick, "LEFT", -10, 0)
    Skin.Arrow(pick)
    pick:SetScript("OnClick", function(self)
        local items = {}
        local templates, class = ListTemplates()
        for _, template in ipairs(templates) do
            items[#items + 1] = { text = template.name, value = template,
                note = template.class == class and "your class" or nil }
        end
        ShowMenu(self, items, function(value)
            quickPick = value
            pick.label:SetText(value.name)
            f.ok:SetEnabled(true)
        end, { width = 260 })
    end)
    local ok = NewButton(f, 130, 26, "Okay, set it up")
    ok:SetPoint("BOTTOMLEFT", 16, 16)
    Skin.Emph(ok)
    ok:SetScript("OnClick", function() Safe(QuickApply) end)
    local back = NewButton(f, 80, 26, "Back")
    back:SetPoint("BOTTOMRIGHT", -16, 16)
    back:SetScript("OnClick", function() Safe(QuickPage, false) end)
    f.pick, f.pickLabel, f.ok, f.back = pick, pickLabel, ok, back
    return f
end

local WELCOME_TEXT = "Click casting: click a unit frame to cast on that player, without targeting. "
    .. "Mouseover (hover) casting: press a key to cast on whoever is under your cursor.\n\n"
    .. "One key can do several things (dead ally: resurrect, ally: heal, enemy: damage), "
    .. "and a legend on screen shows what every key does.\n\n"
    .. "The guided setup takes about a minute; the Class Spec Quickstart sets you up "
    .. "from your class and spec in one click. /clg opens the settings later."

-- What is new, for someone who already uses the addon. Shown once per
-- account for each NEWS_VERSION; raise it, and rewrite NEWS_TEXT, only when
-- a release has something worth stopping a player for.
local NEWS_VERSION = 6              -- 1: 2.1.0 (a line in chat), 2: 2.1.1 (this window), 3: 2.2.0, 4: 2.3.0, 5: 3.0.0, 6: 3.1.0
local NEWS_TEXT = "New in this version:\n\n"
    .. "- Class Spec Quickstart: a starter set for your class and spec, set up in one click (/clg welcome)\n"
    .. "- Starter sets for every spec: in combat, left click casts your main damage spell on an enemy and "
    .. "targets it (casters: right click a second one); out of combat it only targets\n"
    .. "- Sets made from a starter set before are not changed: New... in the Bindings tab makes a fresh one\n\n"
    .. "Thanks everyone for using this addon during development. This release is likely the \"final\" one "
    .. "for now. I don't want to scope creep this project and did a long pass on the quick start sets for "
    .. "each spec. That being said, I'm still taking requests for improvements, features, and QoL. Drop a "
    .. "message on the Curse Forge page and check out my other add ons if interested.\n\n"
    .. "- Heavy C"

-- Which buttons the window shows: the welcome's, what is new's (no
-- quickstart there: it would change the look of someone who has set theirs),
-- or the quickstart page's.
local function ShowButtons(mode)
    local f = welcome
    local card = mode ~= "quick"
    f.guide:SetShown(card)
    f.quick:SetShown(mode == "welcome")
    f.settings:SetShown(card)
    f.later:SetShown(card)
    f.pick:SetShown(not card)
    f.pickLabel:SetShown(not card)
    f.ok:SetShown(not card)
    f.back:SetShown(not card)
    f.settings:ClearAllPoints()
    f.settings:SetPoint("LEFT", mode == "welcome" and f.quick or f.guide, "RIGHT", 8, 0)
    CloseMenu()
end

-- The window, made on first use, saying one thing or the other.
local function ShowCard(height, title, text, justify, guideLabel, mode)
    if not welcome then
        local ok, built = pcall(BuildWelcome)
        if not ok then ns.Report(built); return false end
        welcome = built
    end
    welcome:SetHeight(height + 14)                  -- the panel's title bar
    welcome.title:SetText(title)
    welcome.text:SetText(text)
    welcome.text:SetJustifyH(justify)
    welcome.guide.label:SetText(guideLabel)
    ShowButtons(mode or "news")
    welcome:Show()
    return true
end

-------------------------------------------------------------------------------
--  Class Spec Quickstart: the starter set for this class and spec, mouseover
--  casting on, enemy spells also target, click casting on, and the legend's
--  default look. One click to confirm, and done.
-------------------------------------------------------------------------------
-- The legend's look it gives. These are the defaults too; they are set again
-- here in case they were changed before the welcome was answered.
local QUICK_LOOK = {
    layout = "vertical", labels = true, labelStyle = "icon",
    background = true, bgR = 0.1, bgG = 0.1, bgB = 0.1, bgA = 0.75, border = "tooltip",
}

local QUICK_TEXT = "Click casting from the starter set below, picked for your class and spec:\n\n"
    .. "- Click casting on, with that set\n"
    .. "- Mouseover (hover) casting on: the set's keys also work on units in the world\n"
    .. "- Enemy spells also target the enemy\n"
    .. "- The legend in a column, a small mouse picture for each button, "
    .. "a thin border on a dark grey background\n\n"
    .. "All of it can be changed later: /clg opens the settings."

QuickPage = function(on)
    if not on then
        ShowCard(280, "Welcome to ClickLegend", WELCOME_TEXT, "CENTER", "Guided setup", "welcome")
        return
    end
    quickPick = SpecTemplate()
    local text = QUICK_TEXT
    local blocked = ns.CastBlocked()
    if blocked then
        text = text .. "\n\n|cffff8040Clique is loaded: click casting stays off until Clique is switched off.|r"
    end
    ShowCard(blocked and 330 or 300, "Class Spec Quickstart", text, "LEFT", "Guided setup", "quick")
    welcome.pick.label:SetText(quickPick and quickPick.name or "Pick a starter set")
    welcome.ok:SetEnabled(quickPick ~= nil)
end

QuickApply = function()
    local template = quickPick
    if not template then return end
    local name = AddSet(template.name, BuildTemplate(template))
    if not (name and SelectSet(name)) then
        Print("The starter set could not be made.")
        return
    end
    Edit.SetHoverKeys(true, false)
    SetCastTargetEnemy(true)
    SetCastEnabled(true)
    SetSettings(QUICK_LOOK)
    Seen()
    Print("Set up from \"" .. template.name .. "\". /clg opens the settings; its Bindings tab shows every key.")
end

-- Shows the welcome window; `again` shows it even when it has been seen.
local function ShowWelcome(again)
    if type(ClickLegendCastDB) ~= "table" then return false end
    if not again and (ClickLegendCastDB.welcomed or 0) >= WELCOME_VERSION then return false end
    return ShowCard(280, "Welcome to ClickLegend", WELCOME_TEXT, "CENTER", "Guided setup", "welcome")
end

-- Shows what is new, once; `again` shows it whether or not it has been seen.
-- Someone being shown the welcome window (`welcoming`) is not shown this as
-- well: the welcome says it all, and what is new is new to nobody then.
local function ShowNews(again, welcoming)
    local store = ClickLegendCastDB
    if type(store) ~= "table" then return false end
    local seen = (tonumber(store.news) or 0) >= NEWS_VERSION
    store.news = NEWS_VERSION
    if welcoming or (seen and not again) then return false end
    return ShowCard(380, "What is new in ClickLegend", NEWS_TEXT, "LEFT", "Guided setup")
end

-- At login: the button at once, the welcome a moment later, when the rest
-- of the interface has settled.
local function StartLauncher()
    UpdateMinimapButton()
    local function Greet()
        local welcoming = false
        Safe(function() welcoming = ShowWelcome() end)
        Safe(ShowNews, false, welcoming)
    end
    if C_Timer and C_Timer.After then
        C_Timer.After(3, Greet)
    else
        Greet()
    end
end

-------------------------------------------------------------------------------
--  Used by the other files
-------------------------------------------------------------------------------
ns.GetWelcome          = function() return welcome end
ns.ShowNews            = ShowNews
ns.ShowWelcome         = ShowWelcome
ns.StartLauncher       = StartLauncher
ns.UpdateMinimapButton = UpdateMinimapButton
