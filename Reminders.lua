-- In combat Forever hides the player's own buffs from addons, so Battle Shout
-- is read out of combat and predicted in combat from the last known expiry
-- and our own (readable) casts.

local _, ns = ...

ns.profileDefaults.reminders = {
    battleShout = true,
    warnAt = 15,
    outOfCombat = "instances",
    sound = "chime",
    pos = { x = 0, y = -120 },
    scale = 100,
}

-- Ranks 7 down to 1; the buff carries the same ID as the cast.
local RANKS = { 25289, 11551, 11550, 11549, 6192, 5242, 6673 }
local IS_RANK = {}
for _, id in ipairs(RANKS) do IS_RANK[id] = true end

local DEFAULT_DURATION = 180
-- Aura reads around a loading screen can briefly come back empty.
local LOADING_SETTLE = 2

local OUT_OF_COMBAT = {
    { key = "instances", label = "In instances" },
    { key = "always", label = "Always" },
    { key = "never", label = "Never" },
}

local issecret = ns.issecret

local db
local events = CreateFrame("Frame")
local frame
local expiry, duration = 0, DEFAULT_DURATION
local inCombat, inEncounter = false, false
local settleUntil = 0
local generation = 0
local shown, unlocked, previewing = false, false, false
local previewToken = 0

local function readable(fn, ...)
    local ok, v = pcall(fn, ...)
    if not ok or issecret(v) then return nil end
    return v
end

local function readAura()
    local getAura = C_UnitAuras and C_UnitAuras.GetPlayerAuraBySpellID
    if not getAura then return end
    for _, id in ipairs(RANKS) do
        local ok, aura = pcall(getAura, id)
        if ok and issecret(aura) then return end
        if ok and aura then
            local expires, length = aura.expirationTime, aura.duration
            if issecret(expires) or type(expires) ~= "number" or expires <= 0 then return end
            expiry = expires
            if not issecret(length) and type(length) == "number" and length > 0 then duration = length end
            return
        end
    end
    expiry = 0
end

-- Stored as offsets from the screen centre, so equal values either side mirror.
-- SetPoint offsets are in the frame's own scale, hence the division.
local function applyPosition()
    if not frame then return end
    local scale = db.scale / 100
    frame:SetScale(scale)
    frame:ClearAllPoints()
    frame:SetPoint("CENTER", UIParent, "CENTER", db.pos.x / scale, db.pos.y / scale)
end

local function savePosition()
    local x, y = frame:GetCenter()
    local scale = frame:GetScale()
    local cx, cy = UIParent:GetCenter()
    db.pos.x, db.pos.y = math.floor(x * scale - cx + 0.5), math.floor(y * scale - cy + 0.5)
    applyPosition()
    ns.RefreshOptions()
end

local function buildFrame()
    frame = CreateFrame("Frame", nil, UIParent)
    frame:SetSize(48, 48)
    frame:SetFrameStrata("HIGH")
    frame:SetClampedToScreen(true)
    frame:SetMovable(true)
    frame:RegisterForDrag("LeftButton")
    frame:SetScript("OnDragStart", function(self) if unlocked then self:StartMoving() end end)
    frame:SetScript("OnDragStop", function(self)
        self:StopMovingOrSizing()
        savePosition()
    end)

    local icon = frame:CreateTexture(nil, "ARTWORK")
    icon:SetAllPoints()
    icon:SetTexture(C_Spell.GetSpellTexture(RANKS[#RANKS]))

    frame.cooldown = CreateFrame("Cooldown", nil, frame, "CooldownFrameTemplate")
    frame.cooldown:SetAllPoints()
    frame.cooldown:SetHideCountdownNumbers(false)

    frame.label = frame:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
    frame.label:SetPoint("TOP", frame, "BOTTOM", 0, -2)

    frame.pulse = frame:CreateAnimationGroup()
    frame.pulse:SetLooping("BOUNCE")
    local fade = frame.pulse:CreateAnimation("Alpha")
    fade:SetFromAlpha(1)
    fade:SetToAlpha(0.35)
    fade:SetDuration(0.6)

    frame:Hide()
    applyPosition()
end

local function playSound()
    ns.PlayAlertSound(db.sound)
end

-- v0.1.0 saved the sound as on or off.
local function migrate()
    if db.sound == false then
        db.sound = "none"
    elseif not ns.IsSound(db.sound) then
        db.sound = ns.profileDefaults.reminders.sound
    end
end

-- Only the highest rank may count as known, so check them all.
local function knowsShout()
    for _, id in ipairs(RANKS) do
        if IsPlayerSpell(id) then return true end
    end
    return false
end

local function shoutState()
    local left = expiry - GetTime()
    if left <= 0 then return "missing" end
    if left <= db.warnAt then return "expiring" end
    return "ok"
end

local function wanted(state)
    if state == "ok" or not db.battleShout then return false end
    if not knowsShout() or readable(UnitIsDeadOrGhost, "player") then return false end
    if inCombat then return true end
    if db.outOfCombat == "never" or readable(IsResting) then return false end
    return db.outOfCombat == "always" or readable(IsInInstance) == true
end

local function render(state, label)
    if not frame then buildFrame() end
    if state == "missing" then
        frame.cooldown:Clear()
        frame.label:SetText(label or "Battle Shout missing")
        frame.label:SetTextColor(RED_FONT_COLOR:GetRGB())
        if not frame.pulse:IsPlaying() then frame.pulse:Play() end
    elseif state == "edit" then
        frame.cooldown:Clear()
        frame.label:SetText("Drag to move")
        frame.label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        frame.pulse:Stop()
    else
        frame.cooldown:SetCooldown(expiry - duration, duration)
        frame.label:SetText(label or "Battle Shout")
        frame.label:SetTextColor(NORMAL_FONT_COLOR:GetRGB())
        frame.pulse:Stop()
    end
    frame:Show()
end

local function refresh()
    if previewing then return end
    if unlocked then
        render("edit")
        frame:EnableMouse(true)
        return
    end
    local state = shoutState()
    local show = wanted(state)
    if show then
        render(state)
        frame:EnableMouse(false)
        if not shown and GetTime() >= settleUntil then playSound() end
    elseif frame then
        frame.pulse:Stop()
        frame:Hide()
    end
    shown = show
end

-- One timer for the warning threshold and one for expiry; a newer schedule
-- makes older timers no-ops.
local function schedule()
    generation = generation + 1
    local gen, now = generation, GetTime()
    for _, at in ipairs({ expiry - db.warnAt, expiry }) do
        if at > now then
            C_Timer.After(at - now + 0.05, function() if gen == generation then refresh() end end)
        end
    end
    refresh()
end

local function resync()
    if inCombat or inEncounter or GetTime() < settleUntil then return end
    readAura()
    schedule()
end

events:SetScript("OnEvent", function(_, event, _, _, spellID)
    if event == "UNIT_SPELLCAST_SUCCEEDED" then
        if spellID ~= nil and not issecret(spellID) and IS_RANK[spellID] then
            expiry = GetTime() + duration
            schedule()
        end
    elseif event == "PLAYER_REGEN_DISABLED" then
        inCombat = true
        refresh()
    elseif event == "PLAYER_REGEN_ENABLED" then
        inCombat = false
        resync()
    elseif event == "ENCOUNTER_START" then
        -- Boss pulls hide the aura a moment before combat begins.
        inEncounter = true
    elseif event == "ENCOUNTER_END" then
        inEncounter = false
        resync()
    elseif event == "PLAYER_ENTERING_WORLD" then
        inEncounter = false
        settleUntil = GetTime() + LOADING_SETTLE
        C_Timer.After(LOADING_SETTLE + 0.05, resync)
        refresh()
    elseif event == "UNIT_AURA" then
        resync()
    else
        refresh()
    end
end)

local function setEnabled(on)
    if on then
        events:RegisterUnitEvent("UNIT_AURA", "player")
        events:RegisterUnitEvent("UNIT_SPELLCAST_SUCCEEDED", "player")
        for _, e in ipairs({ "PLAYER_REGEN_DISABLED", "PLAYER_REGEN_ENABLED", "PLAYER_ENTERING_WORLD",
            "ENCOUNTER_START", "ENCOUNTER_END", "ZONE_CHANGED_NEW_AREA", "PLAYER_UPDATE_RESTING",
            "PLAYER_DEAD", "PLAYER_ALIVE", "PLAYER_UNGHOST" }) do
            events:RegisterEvent(e)
        end
        inCombat = InCombatLockdown()
        resync()
        refresh()
    else
        events:UnregisterAllEvents()
        inEncounter = false
        generation = generation + 1
        if frame then
            frame.pulse:Stop()
            frame:Hide()
        end
        shown = false
    end
end

local isWarrior = false

ns.reminders = {
    OUT_OF_COMBAT = OUT_OF_COMBAT,
    IsWarrior = function() return isWarrior end,
    Get = function(key) return db[key] end,
    Set = function(key, value)
        db[key] = value
        if key == "battleShout" then
            setEnabled(value and isWarrior)
        elseif key == "sound" then
            playSound()
        else
            schedule()
        end
    end,
    IsUnlocked = function() return unlocked end,
    SetUnlocked = function(on)
        unlocked = on
        if not on and frame then frame:EnableMouse(false) end
        refresh()
    end,
    Preview = function(withSound)
        if withSound then playSound() end
        previewing = true
        previewToken = previewToken + 1
        local token, saved = previewToken, expiry
        expiry = GetTime() + math.max(db.warnAt, 5)
        render("expiring")
        expiry = saved
        C_Timer.After(5, function()
            if token ~= previewToken then return end
            previewing = false
            refresh()
        end)
    end,
    GetOffset = function(axis) return db.pos[axis] end,
    GetScale = function() return db.scale end,
    SetScale = function(percent)
        db.scale = math.floor(percent + 0.5)
        applyPosition()
        if not unlocked then ns.reminders.Preview() end
    end,
    SetOffset = function(axis, value)
        db.pos[axis] = math.floor(value + 0.5)
        applyPosition()
        if not unlocked then ns.reminders.Preview() end
    end,
}

table.insert(ns.profileListeners, function(profile)
    db = profile.reminders
    migrate()
    applyPosition()
    setEnabled(db.battleShout and isWarrior)
end)

table.insert(ns.modules, function(_, profile)
    db = profile.reminders
    migrate()
    isWarrior = select(2, UnitClass("player")) == "WARRIOR"
    if isWarrior and db.battleShout then setEnabled(true) end
end)

ns.commands.remind = {
    usage = "on | off | move | test | offset <x> <y> | scale <percent>",
    run = function(args)
        local word, x, y = strtrim(args):lower():match("^(%S*)%s*(%S*)%s*(%S*)$")
        if word == "scale" and tonumber(x) then
            ns.reminders.SetScale(math.max(50, math.min(200, tonumber(x))))
            ns.RefreshOptions()
        elseif word == "offset" and tonumber(x) and tonumber(y) then
            ns.reminders.SetOffset("x", tonumber(x))
            ns.reminders.SetOffset("y", tonumber(y))
            ns.RefreshOptions()
        elseif word == "on" or word == "off" then
            ns.reminders.Set("battleShout", word == "on")
            ns.RefreshOptions()
        elseif word == "move" then
            ns.reminders.SetUnlocked(not unlocked)
            ns.RefreshOptions()
        elseif word == "test" then
            ns.reminders.Preview(true)
        end
        ns.Print(format("Battle Shout reminder %s, warn under %ds, out of combat: %s, offset %d, %d, size %d%%%s",
            db.battleShout and "on" or "off", db.warnAt, db.outOfCombat, db.pos.x, db.pos.y, db.scale,
            unlocked and ", unlocked" or ""))
    end,
}
