local _, ns = ...

local COLUMN_WIDTH = 40
-- Lines the first column up with Blizzard's own checkbox column.
local FIRST_COLUMN_X = -80
local CHECKBOX_HALF = 15
-- SettingsListElementMixin:Init anchors Text at this x when unindented.
local TEXT_X = 37
-- Matches the title inset of Blizzard's section headers.
local HEADING_X = 7
local DOT_SIZE = 10

local ACTIVE_TOOLTIP = "Announcements use the page for where you are: Open world, Battlegrounds (arenas too), "
    .. "Dungeons or Raid instances. Your group type doesn't change it."

local registered = {}
local offsetOptions = {}

-- UIParent isn't at its final size when options are registered, so the
-- offset ranges are re-measured each time the settings panel opens.
local function updateOffsetRanges()
    local halves = { x = math.floor(UIParent:GetWidth() / 2), y = math.floor(UIParent:GetHeight() / 2) }
    for axis, options in pairs(offsetOptions) do
        options.minValue, options.maxValue, options.steps = -halves[axis], halves[axis], halves[axis] * 2
    end
end

local function columnX(index)
    return FIRST_COLUMN_X + (index - 1) * COLUMN_WIDTH
end

ShoutcasterChannelHeaderMixin = CreateFromMixins(SettingsListElementMixin)

function ShoutcasterChannelHeaderMixin:OnLoad()
    SettingsListElementMixin.OnLoad(self)
    for i, column in ipairs(ns.alerts.COLUMNS) do
        local label = CreateFrame("Frame", nil, self)
        label:SetSize(COLUMN_WIDTH, 20)
        label:SetPoint("CENTER", self, "CENTER", columnX(i) + CHECKBOX_HALF, 0)
        local text = label:CreateFontString(nil, "OVERLAY", "GameFontNormalSmall")
        text:SetPoint("CENTER")
        text:SetText(column.label)
        label:EnableMouse(true)
        label:SetScript("OnEnter", function(frame)
            SettingsTooltip:SetOwner(frame, "ANCHOR_RIGHT")
            Settings.InitTooltip(column.name, column.tooltip)
            SettingsTooltip:Show()
        end)
        label:SetScript("OnLeave", function() SettingsTooltip:Hide() end)
    end

    self.Dot = self:CreateTexture(nil, "OVERLAY")
    self.Dot:SetSize(DOT_SIZE, DOT_SIZE)
    self.Dot:SetPoint("LEFT", self, "LEFT", TEXT_X, 0)
    self.Dot:SetColorTexture(GREEN_FONT_COLOR:GetRGB())
    local mask = self:CreateMaskTexture()
    mask:SetTexture("Interface\\CHARACTERFRAME\\TempPortraitAlphaMask", "CLAMPTOBLACKADDITIVE", "CLAMPTOBLACKADDITIVE")
    mask:SetAllPoints(self.Dot)
    self.Dot:AddMaskTexture(mask)
end

function ShoutcasterChannelHeaderMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self:SetTooltipFunc(function() Settings.InitTooltip("Which page is used", ACTIVE_TOOLTIP) end)
    self:EvaluateState()
end

function ShoutcasterChannelHeaderMixin:EvaluateState()
    SettingsListElementMixin.EvaluateState(self)
    local current = ns.alerts.CurrentLocation()
    local active = current == self.data.location.key
    self.Dot:SetShown(active)
    self.Text:SetPoint("LEFT", self, "LEFT", active and TEXT_X + DOT_SIZE + 4 or TEXT_X, 0)
    if active then
        self.Text:SetText("Now active")
        self.Text:SetTextColor(GREEN_FONT_COLOR:GetRGB())
    else
        self.Text:SetText("Now active: " .. ns.alerts.LocationLabel(current))
        self.Text:SetTextColor(GRAY_FONT_COLOR:GetRGB())
    end
end

ShoutcasterGroupHeaderMixin = CreateFromMixins(SettingsListElementMixin)

function ShoutcasterGroupHeaderMixin:Init(initializer)
    SettingsListElementMixin.Init(self, initializer)
    self.Text:SetFontObject("GameFontHighlight")
    self.Text:SetPoint("LEFT", self, "LEFT", HEADING_X, 0)
    self.Tooltip:Hide()
end

ShoutcasterChannelRowMixin = CreateFromMixins(SettingsControlMixin)

function ShoutcasterChannelRowMixin:OnLoad()
    SettingsControlMixin.OnLoad(self)
    self.Checkboxes = {}
    for i in ipairs(ns.alerts.COLUMNS) do
        local checkbox = CreateFrame("CheckButton", nil, self, "SettingsCheckboxTemplate")
        checkbox:SetPoint("LEFT", self, "CENTER", columnX(i), 0)
        self.Checkboxes[i] = checkbox
    end
end

function ShoutcasterChannelRowMixin:Init(initializer)
    SettingsControlMixin.Init(self, initializer)
    local setting = self:GetSetting()
    for i, column in ipairs(ns.alerts.COLUMNS) do
        local checkbox, flag = self.Checkboxes[i], 2 ^ (i - 1)
        checkbox:Init(bit.band(setting:GetValue(), flag) ~= 0, function()
            Settings.InitTooltip(initializer:GetName() .. ": " .. column.name, column.tooltip)
        end)
        self.cbrHandles:RegisterCallback(checkbox, SettingsCheckboxMixin.Event.OnValueChanged, function(_, checked)
            local mask = setting:GetValue()
            local isSet = bit.band(mask, flag) ~= 0
            if checked ~= isSet then setting:SetValue(checked and mask + flag or mask - flag) end
            PlaySound(checked and SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_ON or SOUNDKIT.IG_MAINMENU_OPTION_CHECKBOX_OFF)
        end, self)
    end
    self:EvaluateState()
end

function ShoutcasterChannelRowMixin:OnSettingValueChanged(_, mask)
    for i, checkbox in ipairs(self.Checkboxes) do
        checkbox:SetChecked(bit.band(mask, 2 ^ (i - 1)) ~= 0)
    end
end

function ShoutcasterChannelRowMixin:EvaluateState()
    SettingsListElementMixin.EvaluateState(self)
    local enabled = self:IsEnabled()
    for _, checkbox in ipairs(self.Checkboxes) do checkbox:SetEnabled(enabled) end
    self:DisplayEnabled(enabled)
end

function ShoutcasterChannelRowMixin:Release()
    for _, checkbox in ipairs(self.Checkboxes) do checkbox:Release() end
    SettingsControlMixin.Release(self)
end

local function proxy(category, variable, varType, name, default, get, set)
    local setting = Settings.RegisterProxySetting(category, "SHOUTCASTER_" .. variable, varType, name, default, get, set)
    registered[#registered + 1] = setting
    return setting
end

ns.RefreshSettings = function()
    for _, setting in ipairs(registered) do setting:NotifyUpdate() end
end

local function confirm(text, callback)
    StaticPopup_ShowCustomGenericConfirmation({ text = text, callback = callback })
end

local function menuButton(name, buttonText, tooltip, fill)
    return CreateSettingsButtonInitializer(name, buttonText, function(button)
        MenuUtil.CreateContextMenu(button, function(_, root) fill(root) end)
    end, tooltip, true)
end

local function otherProfiles()
    local names = {}
    for _, name in ipairs(ns.ProfileNames()) do
        if name ~= ns.ProfileName() then names[#names + 1] = name end
    end
    return names
end

local function buildProfiles(category, layout)
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Profiles",
        "Profiles are shared across your characters. Each character remembers which one it uses."))

    local profileSetting = proxy(category, "PROFILE", Settings.VarType.String, "Active profile", ns.DEFAULT_PROFILE,
        ns.ProfileName, ns.SetProfile)
    Settings.CreateDropdown(category, profileSetting, function()
        local container = Settings.CreateControlTextContainer()
        for _, name in ipairs(ns.ProfileNames()) do container:Add(name, name) end
        return container:GetData()
    end, "The profile this character uses.")

    layout:AddInitializer(CreateSettingsButtonInitializer("New profile", "New...", function()
        StaticPopup_ShowCustomGenericInputBox({
            text = "Name for the new profile (starts as a copy of " .. ns.ProfileName() .. "):",
            acceptText = ACCEPT,
            callback = function(name)
                local err = ns.NewProfile(name)
                if err then ns.Print(err) end
            end,
        })
    end, "Create a profile from the current one and switch to it.", true))

    layout:AddInitializer(menuButton("Copy profile", "Copy from...",
        "Replace the current profile's settings with another profile's.", function(root)
            for _, name in ipairs(otherProfiles()) do
                root:CreateButton(name, function()
                    confirm(format("Replace %s with a copy of %s?", ns.ProfileName(), name),
                        function() ns.CopyProfile(name) end)
                end)
            end
        end))

    layout:AddInitializer(menuButton("Delete profile", "Delete...",
        "Delete another profile. Characters using it go back to " .. ns.DEFAULT_PROFILE .. ".", function(root)
            for _, name in ipairs(otherProfiles()) do
                if name ~= ns.DEFAULT_PROFILE then
                    root:CreateButton(name, function()
                        confirm(format("Delete the profile %s?", name), function() ns.DeleteProfile(name) end)
                    end)
                end
            end
        end))

    layout:AddInitializer(CreateSettingsButtonInitializer("Reset profile", "Reset", function()
        confirm(format("Reset %s to the default settings?", ns.ProfileName()), ns.ResetProfile)
    end, "Put every setting in the current profile back to its default.", true))
end

local function buildLocationPage(category, layout, location, enabledInit, alertsOn)
    local alerts = ns.alerts
    local defaults = ns.profileDefaults.alerts.locations[location.key]

    local header = Settings.CreateElementInitializer("ShoutcasterChannelHeaderTemplate", { name = "", location = location })
    header:AddEvaluateStateFrameEvent("ZONE_CHANGED_NEW_AREA")
    header:AddEvaluateStateFrameEvent("PLAYER_ENTERING_WORLD")
    layout:AddInitializer(header)

    local group
    for _, row in ipairs(alerts.ROWS) do
        if row.group ~= group then
            group = row.group
            layout:AddInitializer(Settings.CreateElementInitializer("ShoutcasterGroupHeaderTemplate", { name = group }))
        end
        local setting = proxy(category, (location.key .. "_" .. row.key):upper(), Settings.VarType.Number,
            row.label, alerts.RowMask(defaults[row.key]),
            function() return alerts.RowMask(alerts.Cells(location.key, row.key)) end,
            function(mask) alerts.ApplyRowMask(alerts.Cells(location.key, row.key), mask) end)
        local init = Settings.CreateSettingInitializer("ShoutcasterChannelRowTemplate",
            Settings.CreateSettingInitializerData(setting, nil, row.tooltip))
        init:AddSearchTags(row.label)
        init:SetParentInitializer(enabledInit, alertsOn)
        layout:AddInitializer(init)
    end

    layout:AddInitializer(menuButton("Copy settings", "Copy from...",
        "Replace this page's ticks with another location's.", function(root)
            for _, source in ipairs(alerts.LOCATIONS) do
                if source ~= location then
                    root:CreateButton(source.label, function() alerts.Copy(source.key, location.key) end)
                end
            end
        end))
end

local function buildReminders(category, layout)
    local reminders, defaults = ns.reminders, ns.profileDefaults.reminders
    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Reminders",
        "Tell you what your warrior is missing."))

    local function bind(key, varType, name)
        return proxy(category, "REMIND_" .. key:upper(), varType, name, defaults[key],
            function() return reminders.Get(key) end, function(value) reminders.Set(key, value) end)
    end

    local shout = bind("battleShout", Settings.VarType.Boolean, "Battle Shout")
    local shoutInit = Settings.CreateCheckbox(category, shout,
        "Show the Battle Shout icon when it's missing or about to run out. In combat the game hides your buffs "
        .. "from addons, so the time left is counted from your last shout. Warriors only.")
    shoutInit:AddModifyPredicate(reminders.IsWarrior)
    local function shoutOn() return reminders.IsWarrior() and shout:GetValue() end

    local sliderOptions = Settings.CreateSliderOptions(0, 60, 5)
    sliderOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format("%ds", value)
    end)
    Settings.CreateSlider(category, bind("warnAt", Settings.VarType.Number, "Warn when under"), sliderOptions,
        "Seconds left when the icon appears. At 0 it only shows once Battle Shout has run out.")
        :SetParentInitializer(shoutInit, shoutOn)

    Settings.CreateDropdown(category, bind("outOfCombat", Settings.VarType.String, "Out of combat"), function()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(reminders.OUT_OF_COMBAT) do container:Add(option.key, option.label) end
        return container:GetData()
    end, "When to show it outside combat. It never shows while you're resting in a city or inn.")
        :SetParentInitializer(shoutInit, shoutOn)

    Settings.CreateDropdown(category, bind("sound", Settings.VarType.String, "Sound"), function()
        local container = Settings.CreateControlTextContainer()
        for _, sound in ipairs(ns.SOUNDS) do container:Add(sound.key, sound.label) end
        return container:GetData()
    end, "Played when the icon appears.")
        :SetParentInitializer(shoutInit, shoutOn)

    local unlock = proxy(category, "REMIND_UNLOCKED", Settings.VarType.Boolean, "Unlock to move", false,
        reminders.IsUnlocked, reminders.SetUnlocked)
    Settings.CreateCheckbox(category, unlock, "Show the icon so you can drag it into place. Untick to lock it.")
        :SetParentInitializer(shoutInit, shoutOn)

    local sizeOptions = Settings.CreateSliderOptions(50, 200, 5)
    sizeOptions:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
        return format("%d%%", value)
    end)
    Settings.CreateSlider(category, proxy(category, "REMIND_SCALE", Settings.VarType.Number, "Icon size",
        defaults.scale, reminders.GetScale, reminders.SetScale), sizeOptions,
        "Size of the Battle Shout icon. It stays centred on the same spot as it grows or shrinks.")
        :SetParentInitializer(shoutInit, shoutOn)

    local function offsetSlider(axis, name, tooltip)
        local setting = proxy(category, "REMIND_" .. axis:upper(), Settings.VarType.Number, name, defaults.pos[axis],
            function() return reminders.GetOffset(axis) end, function(value) reminders.SetOffset(axis, value) end)
        local options = Settings.CreateSliderOptions(-1, 1, 1)
        options:SetLabelFormatter(MinimalSliderWithSteppersMixin.Label.Right, function(value)
            return format("%d", value)
        end)
        offsetOptions[axis] = options
        Settings.CreateSlider(category, setting, options, tooltip):SetParentInitializer(shoutInit, shoutOn)
    end
    offsetSlider("x", "Horizontal offset",
        "Distance from the centre of the screen: negative is left, positive is right, 0 is centred.")
    offsetSlider("y", "Vertical offset",
        "Distance from the centre of the screen: negative is down, positive is up, 0 is centred.")
    updateOffsetRanges()
    SettingsPanel:HookScript("OnShow", updateOffsetRanges)

    local preview = CreateSettingsButtonInitializer("Preview", "Show", function() reminders.Preview(true) end,
        "Show the icon for five seconds, with its sound.", true)
    preview:SetParentInitializer(shoutInit, shoutOn)
    layout:AddInitializer(preview)
end

table.insert(ns.modules, function()
    if not (Settings and Settings.RegisterVerticalLayoutCategory) then return end

    local category, layout = Settings.RegisterVerticalLayoutCategory("Shoutcaster")

    layout:AddInitializer(CreateSettingsListSectionHeaderInitializer("Announcements",
        "Tell your group what your warrior just did. Where each one goes is set on the location pages below."))
    local enabled = proxy(category, "ALERTS_ENABLED", Settings.VarType.Boolean, "Enable announcements", true,
        ns.alerts.IsEnabled, ns.alerts.SetEnabled)
    local enabledInit = Settings.CreateCheckbox(category, enabled, "Turn all tank and interrupt announcements on or off.")
    local function alertsOn() return enabled:GetValue() end
    local sound = proxy(category, "ALERTS_SOUND", Settings.VarType.String, "On-screen alert sound",
        ns.profileDefaults.alerts.sound, ns.alerts.GetSound, ns.alerts.SetSound)
    Settings.CreateDropdown(category, sound, function()
        local container = Settings.CreateControlTextContainer()
        for _, option in ipairs(ns.SOUNDS) do container:Add(option.key, option.label) end
        return container:GetData()
    end, "Played with announcements ticked under Screen.")
        :SetParentInitializer(enabledInit, alertsOn)
    layout:AddInitializer(CreateSettingsButtonInitializer("Test alert", "Show",
        ns.alerts.Test, "Show a sample alert on your screen. Nothing is sent to chat.", true))

    buildReminders(category, layout)
    buildProfiles(category, layout)

    for _, location in ipairs(ns.alerts.LOCATIONS) do
        local page, pageLayout = Settings.RegisterVerticalLayoutSubcategory(category, location.label)
        buildLocationPage(page, pageLayout, location, enabledInit, alertsOn)
    end

    Settings.RegisterAddOnCategory(category)
    ns.settingsCategory = category
end)
