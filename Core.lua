local addonName, ns = ...

ns.name = addonName
ns.modules = {}
ns.commands = {}
ns.profileDefaults = {}
ns.profileListeners = {}
ns.issecret = issecretvalue or function() return false end

ns.SOUNDS = {
    { key = "none", label = "None" },
    { key = "chime", label = "Chime" },
    { key = "bell", label = "Bell" },
    { key = "pluck", label = "Pluck" },
    { key = "bubble", label = "Bubble" },
    { key = "marimba", label = "Marimba" },
}
local SOUND_FILE = {}
for _, sound in ipairs(ns.SOUNDS) do
    if sound.key ~= "none" then
        SOUND_FILE[sound.key] = "Interface\\AddOns\\" .. addonName .. "\\Sounds\\" .. sound.key .. ".ogg"
    end
end

function ns.IsSound(key)
    return key == "none" or SOUND_FILE[key] ~= nil
end

function ns.PlayAlertSound(key)
    local file = SOUND_FILE[key]
    if file then PlaySoundFile(file, "Master") end
end

local DEFAULT_PROFILE = "Default"
local PREFIX = "|cffc79c6eShoutcaster|r"

function ns.Print(...)
    print(PREFIX, ...)
end

function ns.GroupChannel()
    if LE_PARTY_CATEGORY_INSTANCE and IsInGroup(LE_PARTY_CATEGORY_INSTANCE) then return "INSTANCE_CHAT" end
    if IsInRaid() then return "RAID" end
    if IsInGroup() then return "PARTY" end
end

local function applyDefaults(dst, src)
    for k, v in pairs(src) do
        if type(v) == "table" then
            if type(dst[k]) ~= "table" then dst[k] = {} end
            applyDefaults(dst[k], v)
        elseif dst[k] == nil then
            dst[k] = v
        end
    end
end

local function copyTable(src)
    local dst = {}
    for k, v in pairs(src) do
        dst[k] = type(v) == "table" and copyTable(v) or v
    end
    return dst
end

local db, charDB

function ns.ProfileName()
    return charDB.profile
end

function ns.Profile()
    return db.profiles[charDB.profile]
end

function ns.ProfileNames()
    local names = {}
    for name in pairs(db.profiles) do names[#names + 1] = name end
    table.sort(names)
    return names
end

function ns.RefreshOptions()
    if ns.RefreshSettings then ns.RefreshSettings() end
end

local function activate(name)
    applyDefaults(db.profiles[name], ns.profileDefaults)
    charDB.profile = name
    for _, listener in ipairs(ns.profileListeners) do listener(db.profiles[name]) end
    ns.RefreshOptions()
end

function ns.SetProfile(name)
    if db.profiles[name] and name ~= charDB.profile then activate(name) end
end

-- Returns an error message, or nil on success.
function ns.NewProfile(name)
    name = strtrim(name or "")
    if name == "" then return "enter a name" end
    if db.profiles[name] then return "a profile called " .. name .. " already exists" end
    db.profiles[name] = copyTable(ns.Profile())
    activate(name)
end

function ns.CopyProfile(from)
    if not db.profiles[from] or from == charDB.profile then return end
    db.profiles[charDB.profile] = copyTable(db.profiles[from])
    activate(charDB.profile)
end

function ns.DeleteProfile(name)
    if name == DEFAULT_PROFILE or name == charDB.profile then return end
    db.profiles[name] = nil
    ns.RefreshOptions()
end

function ns.ResetProfile()
    db.profiles[charDB.profile] = {}
    activate(charDB.profile)
end

ns.DEFAULT_PROFILE = DEFAULT_PROFILE

local loader = CreateFrame("Frame")
loader:RegisterEvent("ADDON_LOADED")
loader:SetScript("OnEvent", function(self, _, name)
    if name ~= addonName then return end
    self:UnregisterEvent("ADDON_LOADED")

    ShoutcasterDB = ShoutcasterDB or {}
    ShoutcasterCharDB = ShoutcasterCharDB or {}
    db, charDB = ShoutcasterDB, ShoutcasterCharDB
    db.profiles = db.profiles or {}
    db.profiles[DEFAULT_PROFILE] = db.profiles[DEFAULT_PROFILE] or {}
    if not db.profiles[charDB.profile or ""] then charDB.profile = DEFAULT_PROFILE end
    applyDefaults(ns.Profile(), ns.profileDefaults)
    ns.db = db

    for _, init in ipairs(ns.modules) do
        init(db, ns.Profile())
    end
end)

ns.commands.profile = {
    usage = "[name]  (switch to an existing profile; create one in the options)",
    run = function(args)
        local name = strtrim(args)
        if name ~= "" then
            if db.profiles[name] then
                ns.SetProfile(name)
            else
                ns.Print("no profile called " .. name)
            end
        end
        ns.Print("profile: " .. charDB.profile .. "  (all: " .. table.concat(ns.ProfileNames(), ", ") .. ")")
    end,
}

SLASH_SHOUTCASTER1 = "/shoutcaster"
SLASH_SHOUTCASTER2 = "/scast"
SlashCmdList.SHOUTCASTER = function(msg)
    local cmd, rest = strtrim(msg or ""):match("^(%S*)%s*(.-)$")
    if cmd == "" and ns.settingsCategory then
        Settings.OpenToCategory(ns.settingsCategory:GetID())
        return
    end
    local entry = ns.commands[cmd:lower()]
    if entry then
        entry.run(rest)
        return
    end
    ns.Print("/scast opens the options")
    for name, c in pairs(ns.commands) do
        ns.Print("  /scast " .. name .. " " .. c.usage)
    end
end
