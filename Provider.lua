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
local weak = { __mode = "k" }

local tracked = {}                          -- frame -> "blizzard" | "registered"
local written = setmetatable({}, weak)      -- frame -> { attribute = value we wrote }
local original = setmetatable({}, weak)     -- frame -> { attribute = value before us, or NIL }
local clicksSet = setmetatable({}, weak)    -- frames whose click registration we changed
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
        -- Named after its frame when the frame has a name, so /fstack reads well.
        local ok, frameName = pcall(frame.GetName, frame)
        if not ok or type(frameName) ~= "string" or frameName == "" or _G["ClickLegendCastMenu_" .. frameName] then
            proxyCount = proxyCount + 1
            frameName = tostring(proxyCount)
        end
        b = HelperButton("ClickLegendCastMenu_" .. frameName, frame)
        b:SetAllPoints(frame)
        b:SetAttribute("type", "togglemenu")
        for i = 1, 5 do b:SetAttribute("type" .. i, "togglemenu") end
        b:SetAttribute("useparent-unit", true)
        menuProxy[frame] = b
    end
    return b:GetName()
end

local function RankProxyName(id)
    local name = rankProxy[id]
    if not name then
        name = "ClickLegendCastRank" .. id
        local b = HelperButton(name, UIParent)
        b:SetSize(1, 1)
        b:SetAttribute("type", "spell")
        for i = 1, 5 do b:SetAttribute("type" .. i, "spell") end
        b:SetAttribute("spell", id)
        b:SetAttribute("unit", "mouseover")
        rankProxy[id] = name
    end
    return name
end

-------------------------------------------------------------------------------
--  The plan: what the active set asks for, the same on every frame.
--  plan[i] = { prefix = "shift-", button = 1, text = macro text }     mouse buttons
--  keys[i] = { key = "SHIFT-F", text = macro text }      keyboard keys and the wheel
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

local function BuildPlan()
    local plan, keys = {}, {}               -- fresh ones each time
    local settings = API.Settings()
    if not (settings and settings.enabled) then return plan, keys end
    local set = API.ActiveSet()
    if not set then return plan, keys end
    for _, binding in ipairs(set.bindings) do
        local mods, key = ParseKey(binding.key)
        local button = tonumber(key:match("^BUTTON(%d+)$"))
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
            if text and button then
                -- A plain mouse button with a rule that asks for an extra modifier
                -- must also answer when that modifier is held: "*" is any modifier.
                -- A key bound with that modifier itself still wins, being exact.
                if prefix == "" and API.UsesExtraModifier(binding) then prefix = "*" end
                plan[#plan + 1] = { prefix = prefix, button = button, text = text }
            elseif text then
                keys[#keys + 1] = { key = mods .. key, text = text }
            end
        end
    end
    return plan, keys
end

-- The attributes one frame should carry for the plan.
local function DesiredFor(frame, plan, hasKeys)
    local want = {}
    if hasKeys then want[KEYS_FLAG] = true end
    for _, p in ipairs(plan) do
        local text = p.text
        if text:find("{", 1, true) then
            text = text:gsub("{menu}", function() return MenuProxyName(frame) end)
            text = text:gsub("{rank:(%d+)}", function(id) return RankProxyName(tonumber(id)) end)
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

-- Brings one frame in line with `want`: writes what is missing or different,
-- and puts back the earlier value of anything written before and no longer
-- wanted.
local function SyncFrame(frame, want)
    if not Usable(frame) then return end
    local mine, before = written[frame], original[frame]
    if not mine then
        if not next(want) then return end
        mine, before = {}, {}
        written[frame], original[frame] = mine, before
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
                before[attribute] = old == nil and NIL or old
            end
            frame:SetAttribute(attribute, value)
            mine[attribute] = value
        end
    end
    -- Extra mouse buttons only reach a frame that listens for every button, so
    -- the frame is set to hear every button on release. The game's "cast on
    -- key down" setting would then drop those clicks (it waits for a press the
    -- frame no longer hears), so the frame is told to act on release. The two
    -- go together and both stay until a reload: the game offers no way to read
    -- what a frame listened for before.
    if next(mine) and tracked[frame] and not clicksSet[frame] and frame.RegisterForClicks then
        frame:RegisterForClicks("AnyUp")
        frame:SetAttribute("useOnKeyDown", false)
        clicksSet[frame] = true
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
local header, keyButton, keyMenu
local wrapped = setmetatable({}, weak)      -- frames that carry the wraps
local snippetEnter, snippetLeave = "", ""

local RUN_ENTER = [[ if self:GetAttribute("clg-keys") then control:RunFor(self, control:GetAttribute("clg_enter")) end ]]
local RUN_LEAVE = [[ control:RunFor(self, control:GetAttribute("clg_leave")) ]]

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
end

local function WrapFrame(frame)
    if wrapped[frame] or not frame.GetScript then return end
    wrapped[frame] = true
    -- One at a time: a frame that refuses one wrap still gets the others.
    for _, wrap in ipairs({ { "OnEnter", RUN_ENTER }, { "OnLeave", RUN_LEAVE },
                            { "OnHide", RUN_LEAVE } }) do      -- OnHide: a frame that vanishes under the cursor
        local ok, err = pcall(header.WrapScript, header, frame, wrap[1], wrap[2])
        if not ok then API.Report(err) end
    end
end

-- Brings the hidden key button and the two snippets in line with `keys`.
local function SyncKeys(keys)
    if #keys == 0 and not header then return end
    EnsureKeyFrames()
    local want, enter, leave, menu = {}, {}, {}, false
    for i, k in ipairs(keys) do
        local suffix = "clg" .. i
        local text = k.text
        if text:find("{", 1, true) then
            if text:find("{menu}", 1, true) then menu = true end
            text = text:gsub("{menu}", "ClickLegendCastKeyMenu")
            text = text:gsub("{rank:(%d+)}", function(id) return RankProxyName(tonumber(id)) end)
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
end

local plan, keyPlan = {}, {}                -- as of the last Apply

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
    plan, keyPlan = BuildPlan()
    local ok, err = pcall(SyncKeys, keyPlan)
    if not ok then API.Report(err); keyPlan = {} end
    for frame in pairs(tracked) do SyncTracked(frame) end
end

-- A frame that turned up after the last Apply gets the same plan.
local function SyncNew(frame)
    if InCombat() then dirty = true else SyncTracked(frame) end
end

-------------------------------------------------------------------------------
--  Finding frames
-------------------------------------------------------------------------------
local function Track(frame, group)
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
    Count = function()
        local frames, bound = 0, 0
        for frame in pairs(tracked) do
            frames = frames + 1
            if written[frame] and next(written[frame]) then bound = bound + 1 end
        end
        return frames, bound
    end,
}
