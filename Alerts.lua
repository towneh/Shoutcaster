-- Forever closes the combat log to addons. A MISS on the target, or the
-- target's cast being interrupted, in the same frame as our cast is taken as
-- ours; neither event names its source.

local _, ns = ...

local LOCATIONS = {
    { key = "world", label = "Open world" },
    { key = "pvp", label = "Battlegrounds" },
    { key = "dungeon", label = "Dungeons" },
    { key = "raid", label = "Raid instances" },
}

local LOCATION_BY_INSTANCE = {
    none = "world", pvp = "pvp", arena = "pvp", party = "dungeon", scenario = "dungeon", raid = "raid",
}

local COLUMNS = {
    { key = "group", label = "Group", name = "Group chat",
      tooltip = "Raid, instance or party chat, whichever group you're in." },
    { key = "party", label = "Party", name = "Party chat",
      tooltip = "Party chat. In a raid this goes to your subgroup only." },
    { key = "rw", label = "RW", name = "Raid warning",
      tooltip = "Raid warning. Sent only in a raid, when you're leader or assistant." },
    { key = "say", label = "Say", name = "Say",
      tooltip = "/say. Inside instances only, as the game blocks automated /say elsewhere." },
    { key = "yell", label = "Yell", name = "Yell",
      tooltip = "/yell. Inside instances only, as the game blocks automated /yell elsewhere." },
    { key = "me", label = "Me", name = "My chat window",
      tooltip = "Your own chat window. Only you see it." },
    { key = "screen", label = "Screen", name = "On-screen alert",
      tooltip = "Centre-screen alert with the raid warning sound." },
}

local ROWS = {
    { key = "taunt", group = "Taunts", label = "Taunt resisted",
      tooltip = "\"TAUNT RESIST!\" when your Taunt misses." },
    { key = "mockingBlow", group = "Taunts", label = "Mocking Blow failed",
      tooltip = "\"MOCKING BLOW FAILED!\" when it misses or is dodged or parried." },
    { key = "challengingShout", group = "Taunts", label = "Challenging Shout",
      tooltip = "\"AOE TAUNT!\" when you cast it." },
    { key = "shieldWall", group = "Cooldowns", label = "Shield Wall",
      tooltip = "\"SHIELD WALL ACTIVE!\" when you cast it." },
    { key = "lastStand", group = "Cooldowns", label = "Last Stand",
      tooltip = "\"LAST STAND ACTIVE!\" when you cast it." },
    { key = "shieldBashInterrupted", group = "Interrupts", label = "Shield Bash interrupted",
      tooltip = "\"Interrupted <enemy> (Shield Bash)\" when it stops a cast." },
    { key = "shieldBashMissed", group = "Interrupts", label = "Shield Bash missed",
      tooltip = "\"Shield Bash parried by <enemy>\" or similar when it hits a caster without interrupting." },
    { key = "pummelInterrupted", group = "Interrupts", label = "Pummel interrupted",
      tooltip = "\"Interrupted <enemy> (Pummel)\" when it stops a cast." },
    { key = "pummelMissed", group = "Interrupts", label = "Pummel missed",
      tooltip = "\"Pummel parried by <enemy>\" or similar when it hits a caster without interrupting." },
}

local GROUP_DEFAULTS = {
    taunt = "group screen", mockingBlow = "group screen", challengingShout = "group",
    shieldWall = "group", lastStand = "group",
    shieldBashInterrupted = "group", shieldBashMissed = "group screen",
    pummelInterrupted = "group", pummelMissed = "group screen",
}

local DEFAULTS = {
    world = GROUP_DEFAULTS,
    dungeon = GROUP_DEFAULTS,
    pvp = { shieldBashMissed = "screen", pummelMissed = "screen" },
    raid = {
        taunt = "group rw screen", mockingBlow = "group rw screen", challengingShout = "group rw",
        shieldWall = "group rw", lastStand = "group rw",
        shieldBashInterrupted = "party", shieldBashMissed = "party screen",
        pummelInterrupted = "party", pummelMissed = "party screen",
    },
}

ns.profileDefaults.alerts = { enabled = true, locations = {} }
for _, location in ipairs(LOCATIONS) do
    local rows = {}
    for _, row in ipairs(ROWS) do
        local ticked = {}
        for word in (DEFAULTS[location.key][row.key] or ""):gmatch("%S+") do ticked[word] = true end
        rows[row.key] = {}
        for _, column in ipairs(COLUMNS) do rows[row.key][column.key] = ticked[column.key] or false end
    end
    ns.profileDefaults.alerts.locations[location.key] = rows
end

-- The options page stores each row as one number, a bit per column.
local function rowMask(cells)
    local mask = 0
    for i, column in ipairs(COLUMNS) do
        if cells[column.key] then mask = mask + 2 ^ (i - 1) end
    end
    return mask
end

local function applyRowMask(cells, mask)
    for i, column in ipairs(COLUMNS) do
        cells[column.key] = bit.band(mask, 2 ^ (i - 1)) ~= 0
    end
end

-- Classic IDs. A spell cast under a different ID on Forever is matched by name.
local SPELLS = {
    [355] = "taunt",
    [694] = "mockingBlow", [7400] = "mockingBlow", [7402] = "mockingBlow", [20559] = "mockingBlow", [20560] = "mockingBlow",
    [1161] = "challengingShout",
    [871] = "shieldWall",
    [12975] = "lastStand",
    [72] = "shieldBash", [1671] = "shieldBash", [1672] = "shieldBash",
    [6552] = "pummel", [6554] = "pummel",
}

local CAST_TEXT = {
    challengingShout = "AOE TAUNT!",
    shieldWall = "SHIELD WALL ACTIVE!",
    lastStand = "LAST STAND ACTIVE!",
}

local RESIST_TEXT = {
    taunt = "TAUNT RESIST!",
    mockingBlow = "MOCKING BLOW FAILED!",
}

local KICKS = { shieldBash = true, pummel = true }

local FAILED_ACTIONS = {
    taunt = { MISS = true, RESIST = true, IMMUNE = true },
    mockingBlow = { MISS = true, DODGE = true, PARRY = true, RESIST = true, IMMUNE = true },
    kick = { MISS = true, DODGE = true, PARRY = true, BLOCK = true, RESIST = true, IMMUNE = true },
}

local ACTION_PHRASES = {
    DODGE = "%s dodged by %s", PARRY = "%s parried by %s", BLOCK = "%s blocked by %s",
    RESIST = "%s resisted by %s", IMMUNE = "%s: %s is immune", MISS = "%s missed %s",
}

local SAME_FRAME = 0.1
local TAUNT_CHECK = 0.5
local KICK_CHECK = 0.3

local issecret = ns.issecret
local sendChat = (C_ChatInfo and C_ChatInfo.SendChatMessage) or SendChatMessage

local db
local byName = {}
local resolved = {}
local pendingTaunt, pendingKick
local outcomes = {}
local lockdownNoted = false

local function readable(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return nil end
    return v
end

local function currentLocation()
    local ok, _, instanceType = pcall(IsInInstance)
    if not ok or instanceType == nil or issecret(instanceType) then return "world" end
    return LOCATION_BY_INSTANCE[instanceType] or "world"
end

-- Enemy cast info is secret while casting and nil otherwise.
local function targetIsCasting(fn)
    local ok, v = pcall(fn, "target")
    if not ok then return nil end
    return issecret(v) or v ~= nil
end

local function targetName()
    return readable(UnitName, "target")
end

local function resolveSpell(spellID)
    local key = resolved[spellID]
    if key == nil then
        key = SPELLS[spellID]
        if not key then
            local name = readable(C_Spell.GetSpellName, spellID)
            key = name and byName[name] or false
        end
        resolved[spellID] = key
    end
    return key
end

local function showOnScreen(text, withSound)
    if RaidNotice_AddMessage and RaidWarningFrame then
        RaidNotice_AddMessage(RaidWarningFrame, text, ChatTypeInfo.RAID_WARNING)
    else
        UIErrorsFrame:AddMessage(text, 1, 0.3, 0.3)
    end
    if withSound then
        PlaySound(SOUNDKIT and SOUNDKIT.RAID_WARNING or 8959, "Master")
    end
end

local function chatLocked()
    local locked = C_ChatInfo.InChatMessagingLockdown and C_ChatInfo.InChatMessagingLockdown()
    if not (issecret(locked) or locked) then return false end
    if not lockdownNoted then
        lockdownNoted = true
        ns.Print("addon chat is locked here, showing announcements on screen instead")
    end
    return true
end

local function channelsFor(cfg)
    local channels = {}
    if cfg.group then channels[#channels + 1] = ns.GroupChannel() end
    if cfg.party and IsInGroup(LE_PARTY_CATEGORY_HOME) then channels[#channels + 1] = "PARTY" end
    if cfg.rw and IsInRaid() and (UnitIsGroupLeader("player") or UnitIsGroupAssistant("player")) then
        channels[#channels + 1] = "RAID_WARNING"
    end
    -- Addons may only /say or /yell inside instances; elsewhere it needs a keypress.
    if readable(IsInInstance) == true then
        if cfg.say then channels[#channels + 1] = "SAY" end
        if cfg.yell then channels[#channels + 1] = "YELL" end
    end
    return channels
end

local function announce(rowKey, text)
    local cfg = db.locations[currentLocation()][rowKey]
    local channels = channelsFor(cfg)
    local blocked = false
    if #channels > 0 then
        if chatLocked() then
            blocked = true
        else
            local sent = {}
            for _, channel in ipairs(channels) do
                if not sent[channel] then
                    sent[channel] = true
                    if not pcall(sendChat, text, channel) then blocked = true end
                end
            end
        end
    end
    if cfg.me then ns.Print(text) end
    if cfg.screen then
        showOnScreen(text, true)
    elseif blocked then
        showOnScreen(text, false)
    end
end

local listener = CreateFrame("Frame")
local listening = false
local listenUntil = 0

local function setListening(on)
    if on == listening then return end
    listening = on
    if on then
        listener:RegisterUnitEvent("UNIT_COMBAT", "target")
        listener:RegisterUnitEvent("UNIT_SPELLCAST_INTERRUPTED", "target")
        listener:RegisterUnitEvent("UNIT_SPELLCAST_CHANNEL_STOP", "target")
        listener:RegisterEvent("PLAYER_TARGET_CHANGED")
    else
        listener:UnregisterAllEvents()
    end
end

local function listen(seconds)
    local untilTime = GetTime() + seconds
    if untilTime > listenUntil then listenUntil = untilTime end
    setListening(true)
    C_Timer.After(seconds + 0.05, function()
        if GetTime() >= listenUntil then setListening(false) end
    end)
end

local function sameFrameAction(at, allowed)
    for i = #outcomes, 1, -1 do
        local o = outcomes[i]
        if math.abs(o.t - at) <= SAME_FRAME and allowed[o.action] then return o.action end
    end
end

listener:SetScript("OnEvent", function(_, event, _, action)
    local now = GetTime()
    if event == "UNIT_COMBAT" then
        if issecret(action) then return end
        while outcomes[1] and now - outcomes[1].t > 2 do table.remove(outcomes, 1) end
        outcomes[#outcomes + 1] = { t = now, action = action }
    elseif event == "PLAYER_TARGET_CHANGED" then
        if pendingTaunt then pendingTaunt.retargeted = true end
        if pendingKick then pendingKick.retargeted = true end
    elseif pendingKick then
        if event == "UNIT_SPELLCAST_INTERRUPTED" or pendingKick.channeling then
            pendingKick.interruptedAt = now
        end
    end
end)

-- In instances UnitIsUnit on targettarget is secret; threat status isn't.
local function tauntTookHold(p)
    if p.onMeBefore == false and readable(UnitIsUnit, "targettarget", "player") == true then return true end
    local threat = readable(UnitThreatSituation, "player", "target")
    return threat ~= nil and threat >= 2 and (p.threatBefore or 0) < 2
end

local function resolveTaunt(p)
    pendingTaunt = nil
    if p.retargeted or not sameFrameAction(p.at, FAILED_ACTIONS[p.key]) then return end
    -- A same-frame miss on a taunt that took hold anyway was someone else's miss.
    if tauntTookHold(p) then return end
    local name = p.target and (" (" .. p.target .. ")") or ""
    announce(p.key, RESIST_TEXT[p.key] .. name)
end

local function resolveKick(p)
    pendingKick = nil
    if p.retargeted or not p.at then return end
    local who = p.target or "the target"
    if p.interruptedAt and math.abs(p.interruptedAt - p.at) <= SAME_FRAME + 0.05 then
        announce(p.key .. "Interrupted", format("Interrupted %s (%s)", who, p.spell))
    elseif p.casting or p.channeling then
        local action = sameFrameAction(p.at, FAILED_ACTIONS.kick)
        local phrase = ACTION_PHRASES[action] or "%s failed on %s"
        announce(p.key .. "Missed", format(phrase, p.spell, who))
    end
end

local function onSent(spellID)
    local key = resolveSpell(spellID)
    if KICKS[key] then
        pendingKick = {
            key = key,
            casting = targetIsCasting(UnitCastingInfo),
            channeling = targetIsCasting(UnitChannelInfo),
            target = targetName(),
        }
        listen(1.5)
        local p = pendingKick
        C_Timer.After(1.5, function()
            if pendingKick == p and not p.at then pendingKick = nil end
        end)
    elseif RESIST_TEXT[key] then
        listen(1.5)
    end
end

local function onSucceeded(spellID)
    local key = resolveSpell(spellID)
    if not key then return end
    local now = GetTime()
    if CAST_TEXT[key] then
        announce(key, CAST_TEXT[key])
    elseif RESIST_TEXT[key] then
        local p = {
            key = key, at = now, target = targetName(),
            onMeBefore = readable(UnitIsUnit, "targettarget", "player"),
            threatBefore = readable(UnitThreatSituation, "player", "target"),
        }
        pendingTaunt = p
        listen(TAUNT_CHECK + 0.1)
        C_Timer.After(TAUNT_CHECK, function()
            if pendingTaunt == p then resolveTaunt(p) end
        end)
    elseif KICKS[key] then
        local p = (pendingKick and pendingKick.key == key) and pendingKick or { key = key, target = targetName() }
        p.at = now
        p.spell = readable(C_Spell.GetSpellName, spellID) or "Interrupt"
        pendingKick = p
        listen(KICK_CHECK + 0.1)
        C_Timer.After(KICK_CHECK, function()
            if pendingKick == p then resolveKick(p) end
        end)
    end
end

local driver = CreateFrame("Frame")
driver:SetScript("OnEvent", function(_, event, _, a2, a3, a4)
    local spellID
    if event == "UNIT_SPELLCAST_SENT" then spellID = a4 else spellID = a3 end
    if spellID == nil or issecret(spellID) then return end
    if event == "UNIT_SPELLCAST_SENT" then onSent(spellID) else onSucceeded(spellID) end
end)

local function setEnabled(on)
    db.enabled = on
    if on then
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SENT", "player")
        driver:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
    else
        driver:UnregisterAllEvents()
        setListening(false)
        pendingTaunt, pendingKick = nil, nil
    end
end

local function lookup(list, word)
    word = word:lower()
    for _, item in ipairs(list) do
        if item.key:lower() == word then return item end
    end
end

local function setCell(location, row, column, value)
    db.locations[location][row][column] = value
    ns.RefreshOptions()
end

local function copyLocation(from, to)
    for _, row in ipairs(ROWS) do
        for _, column in ipairs(COLUMNS) do
            db.locations[to][row.key][column.key] = db.locations[from][row.key][column.key]
        end
    end
    ns.RefreshOptions()
end

ns.alerts = {
    LOCATIONS = LOCATIONS,
    COLUMNS = COLUMNS,
    ROWS = ROWS,
    RowMask = rowMask,
    ApplyRowMask = applyRowMask,
    IsEnabled = function() return db.enabled end,
    SetEnabled = function(on) setEnabled(on) end,
    Cells = function(location, row) return db.locations[location][row] end,
    Test = function() showOnScreen("TAUNT RESIST! (Test Dummy)", true) end,
    Copy = copyLocation,
    CurrentLocation = currentLocation,
    LocationLabel = function(key) return lookup(LOCATIONS, key).label end,
}

table.insert(ns.profileListeners, function(profile)
    db = profile.alerts
    setEnabled(db.enabled)
end)

table.insert(ns.modules, function(_, profile)
    db = profile.alerts
    for id in pairs(SPELLS) do
        local name = readable(C_Spell.GetSpellName, id)
        if name then byName[name] = SPELLS[id] end
    end
    if db.enabled then setEnabled(true) end
end)

local function status(location)
    ns.Print(format("%s (announcements %s, you're in: %s)", location.label, db.enabled and "on" or "off",
        lookup(LOCATIONS, currentLocation()).label))
    for _, row in ipairs(ROWS) do
        local ticked = {}
        for _, column in ipairs(COLUMNS) do
            if db.locations[location.key][row.key][column.key] then ticked[#ticked + 1] = column.name end
        end
        ns.Print(format("  %s (%s): %s", row.label, row.key, #ticked > 0 and table.concat(ticked, ", ") or "off"))
    end
end

ns.commands.announce = {
    usage = "on | off | test | <location> | <location> <row> <column> on|off | copy <from> <to>"
        .. "  (locations: world, pvp, dungeon, raid)",
    run = function(args)
        local words = {}
        for word in args:gmatch("%S+") do words[#words + 1] = word end
        local first = (words[1] or ""):lower()
        local location = words[1] and lookup(LOCATIONS, words[1])
        if first == "on" or first == "off" then
            setEnabled(first == "on")
            ns.Print("announcements " .. first)
        elseif first == "test" then
            ns.alerts.Test()
            ns.Print("test alert shown on screen; nothing was sent to chat")
        elseif first == "copy" then
            local from, to = lookup(LOCATIONS, words[2] or ""), lookup(LOCATIONS, words[3] or "")
            if from and to and from ~= to then
                copyLocation(from.key, to.key)
                ns.Print(format("copied %s settings to %s", from.label, to.label))
            else
                ns.Print("usage: /scast announce copy <from> <to>  (world, pvp, dungeon, raid)")
            end
        elseif location and words[2] then
            local row, column = lookup(ROWS, words[2]), lookup(COLUMNS, words[3] or "")
            local value = (words[4] or ""):lower()
            if row and column and (value == "on" or value == "off") then
                setCell(location.key, row.key, column.key, value == "on")
                status(location)
            else
                ns.Print("usage: /scast announce <location> <row> <column> on|off")
            end
        else
            status(location or lookup(LOCATIONS, currentLocation()))
        end
    end,
}
