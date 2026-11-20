-------------------------------------------------------------------------------
--  ClickLegend - Provider.lua
--  Puts ClickLegend's own bindings on unit frames. This is the only file that
--  writes secure attributes or touches a unit frame.
--
--  It does nothing at all until a character switches its own bindings on:
--  no frame is created, no event is heard, no table is hooked. Switched off
--  again, it removes everything it wrote and puts back what was there before.
--
--  The bindings, and their macro text, come from Cast.lua (ClickLegendAPI).
--  Nothing here decides what a click does: each key is a macro the game runs.
--
--  Rules it keeps:
--    * No frame is touched in combat. A change asked for in combat waits for
--      PLAYER_REGEN_ENABLED.
--    * Only attributes it wrote are ever changed back, to the value they had.
--    * Its notes about a frame live in tables of its own, never on the frame.
-------------------------------------------------------------------------------
local API = ClickLegendAPI

local ipairs, pairs, type, tostring, pcall, next = ipairs, pairs, type, tostring, pcall, next
local Print, Safe, ParseKey = API.Print, API.Safe, API.ParseKey

local NIL = {}                              -- stands for "the attribute was not set"
local KEYS_FLAG = "clg-keys"                -- on a frame: entering it binds the keyboard keys
local OWN_FLAG = "clg-own"                  -- on a frame: bound in combat by the header, before it was tracked
local weak = { __mode = "k" }

local tracked = {}                          -- frame -> "blizzard" | "registered"
local written = setmetatable({}, weak)      -- frame -> { attribute = value we wrote }
local original = setmetatable({}, weak)     -- frame -> { attribute = value before us, or NIL }
local clicksSet = setmetatable({}, weak)    -- frame -> "up" | "down": the click registration we gave it
local menuProxy = setmetatable({}, weak)    -- frame -> its menu helper button
local rankProxy = {}                        -- spell id -> helper button name
local dirty = false                         -- a change is waiting for combat to end
local proxyCount = 0

local function InCombat()
    return InCombatLockdown and InCombatLockdown() and true or false
end

-------------------------------------------------------------------------------
--  Helper buttons. The game will not open the unit menu, or cast one exact
--  spell rank, from a unit frame's own attributes; a hidden secure button
--  does it, reached from the macro text with /click.
-------------------------------------------------------------------------------
local function HelperButton(name, parent)
    local b = CreateFrame("Button", name, parent, "SecureActionButtonTemplate")
    b:SetAlpha(0)
    b:EnableMouse(false)                    -- never under the cursor; only /click reaches it
    b:RegisterForClicks("AnyUp")
    b:SetAttribute("useOnKeyDown", false)   -- act on the click /click sends, whatever the key-down setting
    return b
end

-- The menu helper is a child of its frame so that it opens the menu for the
-- unit the frame shows at that moment.
local function MenuProxyName(frame)
    local b = menuProxy[frame]
    if not b then
        -- A short name: it is written into the key's macro text, which has
        -- 255 characters in all, and Cast.lua counts 24 for it.
        -- Named after its frame where that fits, so /fstack reads well; a
        -- longer frame name becomes a number worked out from it.
        local name
        local ok, frameName = pcall(frame.GetName, frame)
        if ok and type(frameName) == "string" and frameName ~= "" then
            name = "ClgMenu_" .. frameName
            if #name > 24 then
                local sum = 0
                for i = 1, #frameName do sum = (sum * 31 + frameName:byte(i)) % 1000000 end
                name = "ClgMenu" .. sum
            end
        end
        while not name or _G[name] do
            proxyCount = proxyCount + 1
            name = "ClgMenu_" .. proxyCount
        end
        b = HelperButton(name, frame)
        b:SetAllPoints(frame)
        b:SetAttribute("type", "togglemenu")
        for i = 1, 5 do b:SetAttribute("type" .. i, "togglemenu") end
        b:SetAttribute("useparent-unit", true)
        menuProxy[frame] = b
    end
    return b:GetName()
end

-- One helper for each spell rank and the unit it is cast on: the helper
-- casts on its own `unit`, whatever the condition in front of the /click
-- looked at. The unit under the cursor unless the rule names another.
local RANK_UNIT = { player = "P", target = "T", focus = "F", targettarget = "TT", pet = "Pet" }
local function RankProxyName(id, unit)
    if not RANK_UNIT[unit] then unit = nil end
    local key = id .. (unit or "")
    local name = rankProxy[key]
    if not name then
        name = "ClgRank" .. id .. (unit and RANK_UNIT[unit] or "")     -- short, as for the menu helper
        local b = HelperButton(name, UIParent)
        b:SetSize(1, 1)
        b:SetAttribute("type", "spell")
        for i = 1, 5 do b:SetAttribute("type" .. i, "spell") end
        b:SetAttribute("spell", id)
        b:SetAttribute("unit", unit or "mouseover")
        rankProxy[key] = name
    end
    return name
end

-- "{rank:ID}" and "{rank:ID:unit}" in a key's text become the helper's name.
local function FillRanks(text)
    return (text:gsub("{rank:(%d+):?(%a*)}", function(id, unit) return RankProxyName(tonumber(id), unit) end))
end

-------------------------------------------------------------------------------
--  The plan: what the active set asks for, the same on every frame.
--  plan[i] = { prefix = "shift-", button = 1, text = macro text }     mouse buttons
--  keys[i] = { key = "SHIFT-F", text = macro text }      keyboard keys and the wheel
--  hover[i] = { key = "SHIFT-F", text = macro text, zoom = true or nil, soft = true or nil }
--                                                        keys that work anywhere
--  A key set to work anywhere is bound all the time, not only while the
--  cursor is on a unit frame. A mouse button set so is in `hover` and in
--  `plan`: a unit frame takes its own clicks before any key binding is asked.
-------------------------------------------------------------------------------
local warned = {}
local function WarnOnce(text)
    if warned[text] then return end
    warned[text] = true
    Print(text)
end

-- "ALT-CTRL-" -> "alt-ctrl-", the prefix the game looks attributes up by.
local function AttributePrefix(mods)
    if mods:find("META", 1, true) then return nil end        -- not supported yet
    return mods:lower()
end

local function MacroBody(name)
    if not (GetMacroIndexByName and GetMacroBody) then return nil end
    local ok, index = pcall(GetMacroIndexByName, name)
    if not ok or not index or index == 0 then return nil end
    local ok2, body = pcall(GetMacroBody, index)
    if ok2 and type(body) == "string" and body ~= "" then return body end
    return nil
end

-- Every way of holding Alt, Ctrl and Shift, as the game spells attribute prefixes.
local MOD_PREFIXES = { "alt-", "ctrl-", "shift-", "alt-ctrl-", "alt-shift-", "ctrl-shift-", "alt-ctrl-shift-" }

local function BuildPlan()
    local plan, keys, hover = {}, {}, {}    -- fresh ones each time
    local settings = API.Settings()
    if not (settings and settings.enabled) then return plan, keys, hover end
    local set = API.ActiveSet()
    if not set then return plan, keys, hover end
    for _, binding in ipairs(set.bindings) do
        local mods, key = ParseKey(binding.key)
        local button = tonumber(key:match("^BUTTON(%d+)$"))
        -- Whether a mouse button past the fifth reaches a unit frame as a click
        -- or reaches the game as a key is not known for this client, so it is
        -- bound both ways. Only one of the two can happen for one press.
        local asKey = not button or button > 5
        local prefix = AttributePrefix(mods)
        if prefix then
            local compiled = API.CompileBinding(binding)
            local text
            if compiled.kind == "macro" then
                text = MacroBody(compiled.macro)
            elseif compiled.kind == "macrotext" then
                if compiled.tooLong then
                    WarnOnce("the rules on " .. binding.key .. " are too long to run; that key is not bound.")
                else
                    text = compiled.text
                end
            end
            local anywhere = text and binding.hover and API.HoverAllowed(binding.key)
            if anywhere and not (SetOverrideBindingClick and ClearOverrideBindings) then
                -- Without the game's override bindings the key stays a unit-frame key.
                WarnOnce("this game client cannot bind keys to work anywhere; those keys work on unit frames only.")
                anywhere = false
            end
            if anywhere then
                hover[#hover + 1] = { key = mods .. key, text = text, zoom = compiled.zoom, soft = compiled.soft,
                                      enemy = compiled.softEnemy }
            end
            if text and button then
                plan[#plan + 1] = { prefix = prefix, button = button, text = text,
                    any = (prefix == "" and API.UsesExtraModifier(binding)) or nil }
            end
            if text and asKey and not anywhere then
                keys[#keys + 1] = { key = mods .. key, text = text }
            end
        end
    end
    -- A plain mouse button with a rule that asks for an extra modifier must
    -- also answer when that modifier is held. It is written out for every
    -- combination that has no key of its own. (Not as "*type1", any modifier:
    -- the game's own frames put "*type1" and "*type2" back to targeting and
    -- the menu whenever their unit changes, and leave exact names alone.)
    local has = {}
    for _, p in ipairs(plan) do has[p.prefix .. p.button] = true end
    for i = 1, #plan do
        local p = plan[i]
        if p.any then
            for _, extra in ipairs(MOD_PREFIXES) do
                if not has[extra .. p.button] then
                    has[extra .. p.button] = true
                    plan[#plan + 1] = { prefix = extra, button = p.button, text = p.text }
                end
            end
        end
    end
    return plan, keys, hover
end

-- The attributes one frame should carry for the plan.
local function DesiredFor(frame, plan, hasKeys)
    local want = {}
    if hasKeys then want[KEYS_FLAG] = true end
    for _, p in ipairs(plan) do
        local text = p.text
        if text:find("{", 1, true) then
            text = text:gsub("{menu}", function() return MenuProxyName(frame) end)
            text = FillRanks(text)
        end
        want[p.prefix .. "type" .. p.button] = "macro"
        want[p.prefix .. "macrotext" .. p.button] = text
    end
    return want
end

-------------------------------------------------------------------------------
--  Writing to a frame
-------------------------------------------------------------------------------
local function Usable(frame)
    if type(frame) ~= "table" or not frame.SetAttribute or not frame.GetAttribute then return false end
    if frame.IsForbidden and frame:IsForbidden() then return false end
    return true
end

-- True when clicks on unit frames are to act as the button goes down.
local function ClicksDown()
    local settings = API.Settings()
    return settings and settings.enabled and settings.down and true or false
end

-- Brings one frame in line with `want`: writes what is missing or different,
-- and puts back the earlier value of anything written before and no longer
-- wanted.
local function SyncFrame(frame, want)
    if not Usable(frame) then return end
    local mine, before = written[frame], original[frame]
    local adopted = false
    if not mine then
        if not next(want) then return end
        mine, before = {}, {}
        written[frame], original[frame] = mine, before
        -- A frame the header bound in combat already carries our values: what
        -- it had before them was nothing.
        adopted = frame:GetAttribute(OWN_FLAG) and true or false
    end
    for attribute in pairs(mine) do
        if want[attribute] == nil then
            local old = before[attribute]
            if old == NIL then old = nil end
            frame:SetAttribute(attribute, old)
            mine[attribute], before[attribute] = nil, nil
        end
    end
    for attribute, value in pairs(want) do
        if mine[attribute] ~= value then
            if before[attribute] == nil then
                local old = frame:GetAttribute(attribute)
                before[attribute] = (adopted or old == nil) and NIL or old
            end
            frame:SetAttribute(attribute, value)
            mine[attribute] = value
        end
    end
    -- Extra mouse buttons only reach a frame that listens for every button, so
    -- the frame is set to hear every button: on release, or on the press when
    -- the player asked for that. The game's "cast on key down" setting would
    -- then drop the clicks it is not waiting for, so the frame is told which
    -- of the two to act on. The two go together. A frame we no longer bind
    -- goes back to acting on release, which is what the game's own menu and
    -- targeting expect; the game offers no way to read what it listened for
    -- before us, so that much stays until a reload.
    if tracked[frame] and frame.RegisterForClicks then
        local clicks = (next(mine) and ClicksDown()) and "down" or "up"
        if (next(mine) or clicksSet[frame]) and clicksSet[frame] ~= clicks then
            frame:RegisterForClicks(clicks == "down" and "AnyDown" or "AnyUp")
            frame:SetAttribute("useOnKeyDown", clicks == "down")
            clicksSet[frame] = clicks
        end
    end
end

local function GroupEnabled(group)
    local settings = API.Settings()
    return settings and settings.enabled and settings.frames[group] == true
end

-------------------------------------------------------------------------------
--  Keyboard keys and the mouse wheel. These are not clicks on the frame: a
--  key only means something while the cursor is on a unit frame. So each
--  frame gets a secure OnEnter / OnLeave wrap; entering binds the keys to one
--  hidden button that carries their macro text, leaving releases them. The
--  wraps run in the game's restricted environment, which is what lets them
--  work in combat.
-------------------------------------------------------------------------------
local header, keyButton, keyMenu, hoverMenu
local wrapped = setmetatable({}, weak)      -- frames that carry the wraps
local snippetEnter, snippetLeave = "", ""

-- "clg-in" marks the frame the cursor is on. A frame that hides lets the
-- keys go only when it is that frame: frames hide all the time (a target's
-- target, a pet, a raid member), and one hiding elsewhere must not take the
-- keys from the frame under the cursor.
local RUN_ENTER = [[ if self:GetAttribute("clg-keys") then self:SetAttribute("clg-in", true) control:RunFor(self, control:GetAttribute("clg_enter")) end ]]
local RUN_LEAVE = [[ self:SetAttribute("clg-in", nil) control:RunFor(self, control:GetAttribute("clg_leave")) ]]
local RUN_HIDE = [[ if self:GetAttribute("clg-in") then self:SetAttribute("clg-in", nil) control:RunFor(self, control:GetAttribute("clg_leave")) end ]]

local function EnsureKeyFrames()
    if header then return end
    header = CreateFrame("Frame", "ClickLegendCastHeader", UIParent, "SecureHandlerStateTemplate")
    header:SetAttribute("clg_enter", "")
    header:SetAttribute("clg_leave", "")
    -- Hears the press and the release; the game's "cast on key down" setting
    -- picks which of the two acts.
    keyButton = CreateFrame("Button", "ClickLegendCastKeys", UIParent, "SecureActionButtonTemplate")
    keyButton:SetSize(1, 1)
    keyButton:SetAlpha(0)
    keyButton:EnableMouse(false)
    keyButton:RegisterForClicks("AnyDown", "AnyUp")
    -- The menu for a key press: its unit is copied from the frame on entering.
    keyMenu = HelperButton("ClickLegendCastKeyMenu", UIParent)
    keyMenu:SetSize(1, 1)
    keyMenu:SetAttribute("type", "togglemenu")
    for i = 1, 5 do keyMenu:SetAttribute("type" .. i, "togglemenu") end
    header:SetFrameRef("keyMenu", keyMenu)
    -- The menu for a key that works anywhere: whatever is under the cursor.
    hoverMenu = HelperButton("ClickLegendCastHoverMenu", UIParent)
    hoverMenu:SetSize(1, 1)
    hoverMenu:SetAttribute("type", "togglemenu")
    for i = 1, 5 do hoverMenu:SetAttribute("type" .. i, "togglemenu") end
    hoverMenu:SetAttribute("unit", "mouseover")
end

local function WrapFrame(frame)
    if wrapped[frame] or not frame.GetScript then return end
    wrapped[frame] = true
    -- One at a time: a frame that refuses one wrap still gets the others.
    for _, wrap in ipairs({ { "OnEnter", RUN_ENTER }, { "OnLeave", RUN_LEAVE },
                            { "OnHide", RUN_HIDE } }) do       -- OnHide: a frame that vanishes under the cursor
        local ok, err = pcall(header.WrapScript, header, frame, wrap[1], wrap[2])
        if not ok then API.Report(err) end
    end
end

-- Keys that work anywhere are held by the header as override bindings: the
-- game gives them back to whatever they were when the header lets go.
-- A wheel key among them (`zoom`) is held only while a unit is under the
-- cursor, so that the wheel zooms the camera the rest of the time: a state
-- driver on the header watches for that unit and its snippet takes the key
-- and lets it go, which it may do in combat too. The driver is asked a few
-- times a second, so the first turn of the wheel right after the cursor
-- reaches a unit can still be a zoom.
local hoverBound = ""
local MOUSEOVER_STATE = "[@mouseover,exists] 1; 0"
local driverOn = false

-- A plain left or right click that works in the world (`soft`) must be the
-- game's own click nearly all the time: it turns the camera, selects, loots
-- and talks to a vendor. It is held only while the cursor is on a friendly
-- player's character in the world. Out of combat this file watches for that
-- itself, since only ordinary code can tell a player from an NPC. In combat
-- ordinary code may not bind anything, so a second state driver takes over:
-- it can only ask for a living friendly unit, which lets friendly NPCs in.
-- Its last answer, out of combat, leaves the key alone.
-- A soft key whose enemy spells also target the enemy (`enemy`) is taken
-- over a living enemy as well: there the click still targets, and casts.
local SOFT_STATE = "[combat,@mouseover,help,nodead] 1; [combat,@mouseover,harm,nodead] 3; [combat] 0; 2"
local softDriverOn = false
local softKeys = {}                 -- { key = "BUTTON1", button = "clgh3", enemy = true, "combat" or nil }
local softHeld = false
local softWatch, softElapsed = nil, 0

local function Plain(value) return not (issecretvalue and issecretvalue(value)) end

-- What the cursor is on in the world, as far as a soft key cares: "ally" (a
-- friendly player's character), "enemy" (something alive that can be
-- attacked) or false.
local function SoftWanted()
    if not (UnitExists and UnitIsPlayer and UnitCanAttack) then return false end
    local ok, exists = pcall(UnitExists, "mouseover")
    if not (ok and Plain(exists) and exists) then return false end
    local ok2, isPlayer = pcall(UnitIsPlayer, "mouseover")
    local ok3, hostile = pcall(UnitCanAttack, "player", "mouseover")
    if not (ok2 and ok3 and Plain(isPlayer) and Plain(hostile)) then return false end
    local what = "ally"
    if hostile then
        -- A dead enemy is something to loot: that click stays the game's.
        local ok4, dead = false, nil
        if UnitIsDeadOrGhost then ok4, dead = pcall(UnitIsDeadOrGhost, "mouseover") end
        if not (ok4 and Plain(dead)) or dead then return false end
        what = "enemy"
    elseif not isPlayer then
        return false
    end
    local focus
    if GetMouseFoci then
        local okf, foci = pcall(GetMouseFoci)
        focus = okf and type(foci) == "table" and foci[1] or nil
    elseif GetMouseFocus then
        local okf, f = pcall(GetMouseFocus)
        focus = okf and f or nil
    end
    return (focus == nil or focus == WorldFrame) and what or false
end

local function SoftApply(force)
    if #softKeys == 0 or (InCombatLockdown and InCombatLockdown()) then return end
    local want = SoftWanted()
    if want == softHeld and not force then return end
    softHeld = want
    for _, k in ipairs(softKeys) do
        -- Out of combat only: a key whose enemy spells are for combat only
        -- ("combat") leaves the click on an enemy to the game.
        if want == "ally" or (want == "enemy" and k.enemy == true) then
            SetOverrideBindingClick(header, true, k.key, "ClickLegendCastKeys", k.button)
        else
            SetOverrideBinding(header, true, k.key, nil)
        end
    end
end

-- Watches the cursor while there is a soft key, and not otherwise.
local function SoftWatch(on)
    if not softWatch then
        if not on then return end
        softWatch = CreateFrame("Frame")
        softWatch:SetScript("OnEvent", function(_, event) API.Safe(SoftApply, event == "PLAYER_REGEN_ENABLED") end)
    end
    if on then
        pcall(softWatch.RegisterEvent, softWatch, "UPDATE_MOUSEOVER_UNIT")
        pcall(softWatch.RegisterEvent, softWatch, "PLAYER_REGEN_ENABLED")
        -- No event says the cursor left a unit.
        softWatch:SetScript("OnUpdate", function(_, dt)
            softElapsed = softElapsed + (dt or 0)
            if softElapsed < 0.1 then return end
            softElapsed = 0
            API.Safe(SoftApply, false)
        end)
    else
        softWatch:UnregisterAllEvents()
        softWatch:SetScript("OnUpdate", nil)
    end
end

local function SyncHover(hover)
    local canWatch = RegisterStateDriver ~= nil and header.Execute ~= nil
    local canSoft = canWatch and SetOverrideBinding ~= nil
    local parts = {}
    for i, k in ipairs(hover) do
        parts[i] = k.key .. ((k.soft and (k.enemy and "^!" or "^")) or ((k.zoom and canWatch) and "~") or "")
    end
    local signature = table.concat(parts, " ")
    if signature == hoverBound then return end
    hoverBound = ""
    if not (SetOverrideBindingClick and ClearOverrideBindings) then return end
    ClearOverrideBindings(header)
    softHeld = false
    local take, drop, softTake, softDrop, softEnemy = {}, {}, {}, {}, {}
    softKeys = {}
    for i, k in ipairs(hover) do
        if k.soft then
            -- Without the means to hold it part of the time it stays a unit-frame key.
            if canSoft then
                softKeys[#softKeys + 1] = { key = k.key, button = "clgh" .. i, enemy = k.enemy }
                softTake[#softTake + 1] = ("self:SetBindingClick(true, %q, %q, %q)"):format(k.key, "ClickLegendCastKeys", "clgh" .. i)
                softDrop[#softDrop + 1] = ("self:ClearBinding(%q)"):format(k.key)
                -- Over an enemy: taken when the key is for enemies too, let go when not.
                softEnemy[#softEnemy + 1] = k.enemy and softTake[#softTake] or softDrop[#softDrop]
            end
        elseif k.zoom and canWatch then
            take[#take + 1] = ("self:SetBindingClick(true, %q, %q, %q)"):format(k.key, "ClickLegendCastKeys", "clgh" .. i)
            drop[#drop + 1] = ("self:ClearBinding(%q)"):format(k.key)
        else
            SetOverrideBindingClick(header, true, k.key, "ClickLegendCastKeys", "clgh" .. i)
        end
    end
    if canWatch and (#take > 0 or driverOn) then
        local takeText, dropText = table.concat(take, "\n"), table.concat(drop, "\n")
        header:SetAttribute("_onstate-clgmo", ("if newstate == 1 or newstate == \"1\" then\n%s\nelse\n%s\nend"):format(takeText, dropText))
        if #take > 0 and not driverOn then
            RegisterStateDriver(header, "clgmo", MOUSEOVER_STATE)
            driverOn = true
        end
        -- As things stand now: the driver only speaks when its answer changes.
        local over = SecureCmdOptionParse and SecureCmdOptionParse(MOUSEOVER_STATE)
        if #take > 0 and (over == "1" or over == 1) then header:Execute(takeText) end
    end
    if canSoft and (#softKeys > 0 or softDriverOn) then
        header:SetAttribute("_onstate-clgsoft",
            ("if newstate == 1 or newstate == \"1\" then\n%s\nelseif newstate == 3 or newstate == \"3\" then\n%s\n"
                .. "elseif newstate == 0 or newstate == \"0\" then\n%s\nend")
                :format(table.concat(softTake, "\n"), table.concat(softEnemy, "\n"), table.concat(softDrop, "\n")))
        if #softKeys > 0 and not softDriverOn then
            RegisterStateDriver(header, "clgsoft", SOFT_STATE)
            softDriverOn = true
        end
    end
    SoftWatch(#softKeys > 0)
    SoftApply(true)
    hoverBound = signature
end

-- Brings the hidden key button, the two snippets and the keys that work
-- anywhere in line with `keys` and `hover`.
local function SyncKeys(keys, hover)
    if #keys == 0 and #hover == 0 and not header then return end
    EnsureKeyFrames()
    local want, enter, leave, menu = {}, {}, {}, false
    for i, k in ipairs(hover) do
        local text = k.text
        if text:find("{", 1, true) then
            text = text:gsub("{menu}", "ClickLegendCastHoverMenu")
            text = FillRanks(text)
        end
        want["*type-clgh" .. i] = "macro"
        want["*macrotext-clgh" .. i] = text
    end
    for i, k in ipairs(keys) do
        local suffix = "clg" .. i
        local text = k.text
        if text:find("{", 1, true) then
            if text:find("{menu}", 1, true) then menu = true end
            text = text:gsub("{menu}", "ClickLegendCastKeyMenu")
            text = FillRanks(text)
        end
        -- "*": whatever modifiers are held when the key's click arrives.
        want["*type-" .. suffix] = "macro"
        want["*macrotext-" .. suffix] = text
        enter[#enter + 1] = ("control:SetBindingClick(true, %q, %q, %q)"):format(k.key, "ClickLegendCastKeys", suffix)
        leave[#leave + 1] = ("control:ClearBinding(%q)"):format(k.key)
    end
    if menu then
        table.insert(enter, 1, [[control:GetFrameRef("keyMenu"):SetAttribute("unit", self:GetAttribute("unit"))]])
    end
    SyncFrame(keyButton, want)
    local enterText, leaveText = table.concat(enter, "\n"), table.concat(leave, "\n")
    if enterText ~= snippetEnter then header:SetAttribute("clg_enter", enterText); snippetEnter = enterText end
    if leaveText ~= snippetLeave then
        -- Keys that are no longer bound must not stay held by a hovered frame.
        if snippetLeave ~= "" then header:Execute((snippetLeave:gsub("control:", "self:"))) end
        header:SetAttribute("clg_leave", leaveText)
        snippetLeave = leaveText
    end
    SyncHover(hover)
end

local plan, keyPlan, hoverPlan = {}, {}, {} -- as of the last Apply

-------------------------------------------------------------------------------
--  Frames made during combat. Nothing outside the game's restricted
--  environment may write to a new unit frame then. Group frames from a
--  secure group header can still be reached: the header's own set-up code
--  runs in that environment for each frame it makes, and by a convention
--  that began with Clique it looks for a frame reference "clickcast_header"
--  on the group header and runs that frame's "clickcast_register" snippet
--  with the new frame in "clickcast_button". Our header answers to that, with
--  a snippet that writes the mouse-button bindings. Keyboard keys and the
--  unit menu on such a frame start when combat ends: both need a helper that
--  cannot be made in combat. A key that casts and also opens the menu is
--  written without its menu line until then, so that its spells work at once
--  (the starter sets heal on right click and keep the menu for everyone else).
--  The game's own raid frames have no such hook and are still bound when
--  combat ends.
-------------------------------------------------------------------------------
local Track                                 -- defined below
local offered = setmetatable({}, weak)      -- group headers looked at
local snippetOn, snippetOff = nil, nil

local function SyncRegisterSnippet()
    local on = GroupEnabled("registered")
    if not header then
        if not on then return end
        EnsureKeyFrames()
    end
    -- Called from the snippet: note the frame, so that it is brought fully in
    -- line after combat and put back when the bindings are switched off.
    header.ClgAdopt = function(self)
        local frame = self:GetAttribute("clickcast_button")
        if type(frame) == "table" and not tracked[frame] then
            Track(frame, "registered")
            dirty = true
        end
    end
    -- And the other way: a frame taken back is let go when combat ends.
    header.ClgRelease = function(self)
        local frame = self:GetAttribute("clickcast_button")
        if type(frame) == "table" and tracked[frame] == "registered" then
            tracked[frame] = "released"
            dirty = true
        end
    end
    local head = 'local button = self:GetAttribute("clickcast_button")\nif not button then return end'
    local set, clear = { head }, { head }
    if on then
        for _, p in ipairs(plan) do
            local text = p.text
            if text:find("{menu}", 1, true) then
                local kept = {}
                for line in text:gmatch("[^\n]+") do
                    if not line:find("{menu}", 1, true) then kept[#kept + 1] = line end
                end
                -- What is left ends in the /stopmacro that led to the menu line.
                if kept[#kept] and kept[#kept]:find("^/stopmacro") then kept[#kept] = nil end
                text = table.concat(kept, "\n")
            end
            if text ~= "" then
                text = FillRanks(text)
                local kind, body = p.prefix .. "type" .. p.button, p.prefix .. "macrotext" .. p.button
                set[#set + 1] = ("button:SetAttribute(%q, %q)"):format(kind, "macro")
                set[#set + 1] = ("button:SetAttribute(%q, %q)"):format(body, text)
                clear[#clear + 1] = ("button:SetAttribute(%q, nil)"):format(kind)
                clear[#clear + 1] = ("button:SetAttribute(%q, nil)"):format(body)
            end
        end
        set[#set + 1] = ("button:SetAttribute(%q, true)"):format(OWN_FLAG)
        set[#set + 1] = ("button:SetAttribute(%q, %s)"):format("useOnKeyDown", tostring(ClicksDown()))
        set[#set + 1] = 'self:CallMethod("ClgAdopt")'
        clear[#clear + 1] = ("button:SetAttribute(%q, nil)"):format(OWN_FLAG)
        clear[#clear + 1] = 'self:CallMethod("ClgRelease")'
    end
    local setText, clearText = table.concat(set, "\n"), table.concat(clear, "\n")
    if setText ~= snippetOn then header:SetAttribute("clickcast_register", setText); snippetOn = setText end
    if clearText ~= snippetOff then header:SetAttribute("clickcast_unregister", clearText); snippetOff = clearText end
    -- Frame addons that look for this name when they make a group header.
    if on and ClickCastHeader == nil then ClickCastHeader = header end
end

-- Hands our header to the group header a tracked frame belongs to, unless
-- another click-cast addon's is already there.
local function OfferHeader(frame)
    if not (header and SecureHandlerSetFrameRef and frame.GetParent) then return end
    local ok, parent = pcall(frame.GetParent, frame)
    if not ok or type(parent) ~= "table" or offered[parent] or not parent.GetAttribute then return end
    offered[parent] = true
    if type(parent:GetAttribute("initialConfigFunction")) ~= "string" then return end       -- not a group header
    if parent:GetAttribute("frameref-clickcast_header") ~= nil then return end
    local ok2, err = pcall(SecureHandlerSetFrameRef, parent, "clickcast_header", header)
    if not ok2 then API.Report(err) end
end

local function SyncTracked(frame)
    local group = tracked[frame]
    if not group then return end
    local on = GroupEnabled(group)
    local hasKeys = on and #keyPlan > 0
    local ok, err = pcall(function()
        if hasKeys then WrapFrame(frame) end
        SyncFrame(frame, on and DesiredFor(frame, plan, hasKeys) or {})
    end)
    if not ok then API.Report(err) end
end

local function ApplyNow()
    plan, keyPlan, hoverPlan = BuildPlan()
    local ok, err = pcall(SyncKeys, keyPlan, hoverPlan)
    if not ok then API.Report(err); keyPlan, hoverPlan = {}, {} end
    local ok2, err2 = pcall(SyncRegisterSnippet)
    if not ok2 then API.Report(err2) end
    for frame, group in pairs(tracked) do
        SyncTracked(frame)
        if group == "registered" and GroupEnabled(group) then OfferHeader(frame) end
    end
end

-- A frame that turned up after the last Apply gets the same plan.
local function SyncNew(frame)
    if InCombat() then dirty = true else SyncTracked(frame) end
end

-------------------------------------------------------------------------------
--  Finding frames
-------------------------------------------------------------------------------
Track = function(frame, group)
    if not Usable(frame) or tracked[frame] then return end
    tracked[frame] = group
end

local BLIZZARD_FRAMES = {
    "PlayerFrame", "PetFrame", "TargetFrame", "TargetFrameToT", "FocusFrame", "FocusFrameToT",
    "Boss1TargetFrame", "Boss2TargetFrame", "Boss3TargetFrame", "Boss4TargetFrame", "Boss5TargetFrame",
}

local function TrackNamed(name)
    local frame = _G[name]
    if frame then Track(frame, "blizzard") end
end

local compactHooked = false

local function ScanBlizzardFrames()
    for _, name in ipairs(BLIZZARD_FRAMES) do TrackNamed(name) end
    for i = 1, 5 do
        TrackNamed("CompactPartyFrameMember" .. i)
        TrackNamed("CompactArenaFrameMember" .. i)
    end
    for i = 1, 40 do TrackNamed("CompactRaidFrame" .. i) end
    for g = 1, 8 do
        for i = 1, 5 do TrackNamed("CompactRaidGroup" .. g .. "Member" .. i) end
    end
    local pool = type(PartyFrame) == "table" and PartyFrame.PartyMemberFramePool
    if type(pool) == "table" and pool.EnumerateActive then
        local ok, err = pcall(function()
            for member in pool:EnumerateActive() do
                Track(member, "blizzard")
                if member.PetFrame then Track(member.PetFrame, "blizzard") end
            end
        end)
        if not ok then API.Report(err) end
    end
    -- Raid-style frames are made as people join: hear about each new one.
    if not compactHooked and type(CompactUnitFrame_SetUpFrame) == "function" and hooksecurefunc then
        compactHooked = true
        hooksecurefunc("CompactUnitFrame_SetUpFrame", function(frame)
            if not Usable(frame) or tracked[frame] then return end
            local ok, name = pcall(frame.GetName, frame)
            if not ok or type(name) ~= "string" or name:match("^NamePlate") then return end
            Track(frame, "blizzard")
            SyncNew(frame)
        end)
    end
end

-- Frames other addons offer for click casting: ClickCastFrames[frame] = true,
-- and nil again to take one back. Whoever handles click casting puts a
-- metatable on that table to hear about it. If another addon already has, the
-- frames are theirs and are left alone.
local registeredHooked, registeredTaken = false, false

local function HookRegisteredFrames()
    if registeredHooked or registeredTaken then return end
    local old = ClickCastFrames
    if type(old) == "table" and getmetatable(old) ~= nil then
        registeredTaken = true
        WarnOnce("another click-cast addon is handling other addons' unit frames, so ClickLegend leaves those alone.")
        return
    end
    registeredHooked = true
    ClickCastFrames = setmetatable({}, {
        __newindex = function(_, frame, value)
            if value then
                Track(frame, "registered")
                SyncNew(frame)
            elseif tracked[frame] == "registered" then
                -- Taken back: drop our bindings from it, now or after combat.
                if InCombat() then
                    tracked[frame] = "released"
                    dirty = true
                else
                    tracked[frame] = nil
                    pcall(SyncFrame, frame, {})
                end
            end
        end,
        __index = function(_, frame) return tracked[frame] == "registered" or nil end,
    })
    if type(old) == "table" then
        for frame, value in pairs(old) do
            if value then Track(frame, "registered") end
        end
    end
end

-- Grid2 offers its usual group frames to Clique only, through Clique's own
-- header, and puts just a few special layouts in ClickCastFrames. It does keep
-- a list of every frame it has made (Grid2Frame:WithAllFrames) and makes each
-- one in Grid2Frame:RegisterFrame, so its frames are taken from there. Left
-- alone when Clique is loaded, or when another addon owns ClickCastFrames.
local grid2Hooked = false

local function ScanGrid2Frames()
    local G = Grid2Frame
    if type(G) ~= "table" or type(G.WithAllFrames) ~= "function" then return end
    if registeredTaken or type(Clique) == "table" then return end
    local ok, err = pcall(G.WithAllFrames, G, function(frame) Track(frame, "registered") end)
    if not ok then API.Report(err) end
    if not grid2Hooked and type(G.RegisterFrame) == "function" and hooksecurefunc then
        grid2Hooked = true
        hooksecurefunc(G, "RegisterFrame", function(_, frame)
            if not Usable(frame) or tracked[frame] then return end
            Track(frame, "registered")
            SyncNew(frame)
        end)
    end
end

-------------------------------------------------------------------------------
--  Apply: the one entry point. Safe to call at any time, as often as needed.
-------------------------------------------------------------------------------
local started = false                       -- true once a character has had its bindings on
local Start                                 -- defined below

local function Apply()
    local settings = API.Settings()
    if not started then
        if not (settings and settings.enabled) then return end      -- never switched on: stay out of everything
        Start()
    end
    if InCombat() then dirty = true; return end
    dirty = false
    if settings and settings.enabled then
        if settings.frames.blizzard then ScanBlizzardFrames() end
        if settings.frames.registered then
            HookRegisteredFrames()
            ScanGrid2Frames()
        end
    end
    ApplyNow()
    for frame, group in pairs(tracked) do
        if group == "released" then tracked[frame] = nil end        -- cleaned by ApplyNow
    end
end

-- The first time the bindings are on: start hearing the events that mean the
-- frames or the bindings may have changed.
Start = function()
    started = true
    local events = CreateFrame("Frame")
    for _, event in ipairs({
        "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD", "GROUP_ROSTER_UPDATE", "SPELLS_CHANGED",
        "UPDATE_MACROS", "PLAYER_SPECIALIZATION_CHANGED", "ACTIVE_TALENT_GROUP_CHANGED",
    }) do
        pcall(events.RegisterEvent, events, event)
    end
    events:SetScript("OnEvent", function(_, event)
        if event == "PLAYER_REGEN_ENABLED" and not dirty then return end
        Safe(Apply)
    end)
end

-- For Cast.lua, and for looking at what was done (/dump ClickLegendAPI.provider.Count()).
API.provider = {
    Apply = Apply,
    Started = function() return started end,
    Pending = function() return dirty end,
    Anywhere = function() return #hoverPlan end,
    Count = function()
        local frames, bound = 0, 0
        for frame in pairs(tracked) do
            frames = frames + 1
            if written[frame] and next(written[frame]) then bound = bound + 1 end
        end
        return frames, bound
    end,
}
