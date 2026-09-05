local ADDON_NAME = ...

-- Foundry-1.0 replaces AceAddon-3.0, AceConsole-3.0, AceEvent-3.0 and AceDB-3.0.
-- The embedded copy under Libs/ loads from Libs.xml; a standalone install wins
-- the bootstrap gate ahead of it via OptionalDeps.
local F = _G.Foundry_1_0
if not F then
    error("CrossGambling requires Foundry-1.0. Please install or enable it.")
end

-- Require the four modules this addon uses, each at the LOWEST API level that
-- carries the behaviour it depends on. A standalone Foundry-1.0 wins the
-- bootstrap gate ahead of the embedded copy, so every level pinned here is a
-- version floor imposed on other people's installs: pinning above what the code
-- needs turns a working older library into a hard load failure.
F:RequireModule("Commands", 1)
F:RequireModule("Events", 1)
F:RequireModule("Lifecycle", 1)
F:RequireModule("DB", 1)

-- The addon object: a plain table, published under the global the rest of the
-- addon already binds at file scope. CrossGambling is also a SavedVariable, so
-- WoW overwrites this global with the save file before ADDON_LOADED;
-- core/DB.lua's ReclaimGlobalFromSavedVariables restores it.
CrossGambling = {}
local CrossGambling = CrossGambling

-- Reproduces AceConsole-3.0's visible output exactly: the addon name in
-- |cff33ff99, a colon, then the stringified arguments joined by single spaces,
-- emitted through DEFAULT_CHAT_FRAME:AddMessage.
local PRINT_PREFIX = "|cff33ff99CrossGambling|r:"

function CrossGambling:Print(...)
    local parts = { PRINT_PREFIX }
    local n = 1
    for i = 1, select("#", ...) do
        n = n + 1
        parts[n] = tostring((select(i, ...)))
    end
    DEFAULT_CHAT_FRAME:AddMessage(table.concat(parts, " ", 1, n))
end

-- One Foundry.Events controller for the whole addon, created at file scope so
-- the shim below is valid from the first call. Events:New creates a hidden
-- frame and registers nothing until :Register (Modules/Events.lua:530-563).
local events = F.Events:New("CrossGambling")

-- AceEvent-3.0 compatibility shim. Two differences from AceEvent are handled
-- here and nowhere else:
--   * Foundry hands the handler (event, ...) with no self, so the wrapper
--     re-supplies the addon object (Modules/Events.lua:553-558).
--   * Foundry REFUSES a duplicate registration where AceEvent silently
--     replaced it (Modules/Events.lua:59-63); RegisterChatEvents can be
--     reached twice without an intervening unregister, so the guard is
--     load-bearing, not defensive padding.
function CrossGambling:RegisterEvent(event, methodName)
    if events:IsRegistered(event) then
        return
    end
    events:Register(event, function(firedEvent, ...)
        local method = CrossGambling[methodName]
        if method then
            method(CrossGambling, firedEvent, ...)
        end
    end)
end

function CrossGambling:UnregisterEvent(event)
    events:Unregister(event)
end

function CrossGambling:IsEventRegistered(event)
    return events:IsRegistered(event)
end

-- Adopt the addon table onto a Lifecycle controller. addon-loaded fires after
-- SavedVariables are restored, which is exactly where AceAddon dispatched
-- OnInitialize. The wrapper (not a direct method reference) is required
-- because OnInitialize is defined further down this file.
local lifecycle = F.Lifecycle:New(CrossGambling, ADDON_NAME)
lifecycle:OnAddonLoaded(function() CrossGambling:OnInitialize() end)

local uiThemes = {
    "Classic",
    "Slick"
}

local commandOrder = {
    "show", "hide", "minimap", "allstats", "stats", "joinstats", "unjoinstats", "listalts",
    "updatestat", "deletestat", "resetstats", "exportstats", "importstats", "ban", "unban",
    "listbans", "audit", "testing", "testbots", "stoptest",
}

function CrossGambling:PrintCommandHelp()
    self:Print("Commands: " .. table.concat(commandOrder, ", "))
    self:Print("Usage: /cg <command> [value]")
end

function CrossGambling:OnInitialize()
    self:InitDB()
    self:InitMinimap()
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")

    -- Foundry.Commands replaces AceConsole-3.0's RegisterChatCommand. The
    -- printer routes every controller line through the same coloured prefix
    -- AceConsole used, so help and error text look unchanged.
    local commands = F.Commands:New({
        name = "CrossGambling",
        slashes = { "/cg", "/crossgambling" },
        printer = function(line) CrossGambling:Print(line) end,
        defaultHandler = function() CrossGambling:PrintCommandHelp() end,
        unknownMessage = function(input)
            -- Reproduce the pre-Foundry two-part response: the offending token
            -- only (not the whole input), then the command list. Returning ""
            -- suppresses the controller's own line (Modules/Commands.lua:282).
            local token = input:match("^(%S+)") or input
            CrossGambling:Print(("Unknown command: %s"):format(token:lower()))
            CrossGambling:PrintCommandHelp()
            return ""
        end,
    })
    self.commands = commands

    commands:Register({ name = "show", help = "Show Game",
        handler = function() CrossGambling:ToggleGUI(nil, true) end })
    commands:Register({ name = "hide", help = "Hide Game",
        handler = function() CrossGambling:ToggleGUI(nil, false) end })
    commands:Register({ name = "minimap", help = "Show/Hide Minimap Icon",
        handler = function() CrossGambling:ToggleMinimap() end })
    commands:Register({ name = "allstats", help = "Shows all Stats(Out of Order in Guild)",
        handler = function() CrossGambling:reportStats(true) end })
    commands:Register({ name = "stats", help = "Shows Top 3 Winners/Losers(Out of Order in Guild)",
        handler = function() CrossGambling:reportStats() end })
    commands:Register({ name = "joinstats", args = "[main] [alt]",
        help = "[main] [alt] - Join the two character's win/loss amounts on stat tracker",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg joinstats [main] [alt] - Join the two character's win/loss amounts on stat tracker")
                return
            end
            CrossGambling:joinStats(nil, rest)
        end })
    commands:Register({ name = "unjoinstats", args = "[alt]",
        help = "[alt] - Unjoins the Alt from whomever it's attached to",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg unjoinstats [alt] - Unjoins the Alt from whomever it's attached to")
                return
            end
            CrossGambling:unjoinStats(nil, rest)
        end })
    commands:Register({ name = "listalts", help = "See everyone whos used joinstats",
        handler = function() CrossGambling:listAlts() end })
    commands:Register({ name = "updatestat", args = "[player] [amount]",
        help = "[player] [amount] - Add [amount] to [player]'s stats (use negative numbers to subtract)",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg updatestat [player] [amount] - Add [amount] to [player]'s stats (use negative numbers to subtract)")
                return
            end
            CrossGambling:updateStat(nil, rest)
        end })
    commands:Register({ name = "deletestat", args = "[player]",
        help = "[player] - Permanently delete stats",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg deletestat [player] - Permanently delete stats")
                return
            end
            CrossGambling:deleteStat(nil, rest)
        end })
    commands:Register({ name = "resetstats", help = "Deletes All Stats",
        handler = function() CrossGambling:resetStats() end })
    commands:Register({ name = "exportstats", help = "Open the stats export window",
        handler = function() CrossGambling:ShowStatsTransferFrame("export") end })
    commands:Register({ name = "importstats", help = "Open the stats import window",
        handler = function() CrossGambling:ShowStatsTransferFrame("import") end })
    commands:Register({ name = "ban", args = "[player]",
        help = "[player] -  Ban players from joining",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg ban [player] -  Ban players from joining")
                return
            end
            CrossGambling:banPlayer(nil, rest)
        end })
    commands:Register({ name = "unban", args = "[player]",
        help = "[player] - Unbans a previously banned player",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg unban [player] - Unbans a previously banned player")
                return
            end
            CrossGambling:unbanPlayer(nil, rest)
        end })
    commands:Register({ name = "listbans", help = "See banned players",
        handler = function() CrossGambling:listBans() end })
    commands:Register({ name = "audit", help = "See all merged players or changes",
        handler = function() CrossGambling:auditMerges() end })
    commands:Register({ name = "testing", args = "[on|off]",
        help = "[on|off] - Enable to unlock /cg testbots and debug chat echoes. Off by default.",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg testing [on|off] - Enable to unlock /cg testbots and debug chat echoes. Off by default.")
                return
            end
            CrossGambling:SetTestingMode(nil, rest)
        end })
    commands:Register({ name = "testbots", args = "[count]",
        help = "[count] - Start a local bot-only test game in the current mode. Requires /cg testing on first.",
        handler = function(rest)
            if rest == "" then
                CrossGambling:Print("Usage: /cg testbots [count] - Start a local bot-only test game in the current mode. Requires /cg testing on first.")
                return
            end
            CrossGambling:StartBotTest(nil, rest)
        end })
    commands:Register({ name = "stoptest", help = "Stops/resets an in-progress bot test game",
        handler = function() CrossGambling:StopBotTest() end })

    self.uiBuilt = false
end

function CrossGambling:BuildUI()
    if self.uiBuilt then return end
    if self.db.global.themechoice == 1 then
        self:ShowThemePicker()
        return
    end
    self.uiBuilt = true
    if self.db.global.theme == uiThemes[2] then
        self:DrawMainEvents()
    elseif self.db.global.theme == uiThemes[1] then
        self:DrawMainEvents2()
    end
end

function CrossGambling:ShowThemePicker()
    if self.themePickerFrame then
        self.themePickerFrame:Show()
        return
    end

    local picker = CreateFrame("Frame", "CrossGamblingThemePicker", UIParent, "BasicFrameTemplateWithInset")
    picker:SetSize(1000, 320)
    picker:SetPoint("CENTER", UIParent, "CENTER", 0, 0)
    picker:SetMovable(true)
    picker:EnableMouse(true)
    picker:SetUserPlaced(true)
    picker:SetClampedToScreen(true)
    picker:RegisterForDrag("LeftButton")
    picker:SetScript("OnDragStart", picker.StartMoving)
    picker:SetScript("OnDragStop", picker.StopMovingOrSizing)
    self.themePickerFrame = picker

    local header = picker:CreateFontString(nil, "ARTWORK", "GameFontNormal")
    header:SetPoint("TOP", picker, "TOP", 0, -2)
    header:SetText("CrossGambling")

    local subtext = picker:CreateFontString(nil, "OVERLAY", "GameFontNormal")
    subtext:SetPoint("TOP", picker, "TOP", 0, -50)
    subtext:SetText("Choose between Classic or Slick style. Click Confirm to switch instantly.\nClosing this window will default to Slick.")

    local pickerSelected = "Slick"

    local classicThumb = picker:CreateTexture(nil, "ARTWORK")
    classicThumb:SetPoint("BOTTOMLEFT", picker, "BOTTOMLEFT", 0, 10)
    classicThumb:SetTexture("Interface\\AddOns\\CrossGambling\\media\\ClassicTheme.tga")

    local slickThumb = picker:CreateTexture(nil, "ARTWORK")
    slickThumb:SetPoint("BOTTOMRIGHT", picker, "BOTTOMRIGHT", 0, 10)
    slickThumb:SetTexture("Interface\\AddOns\\CrossGambling\\media\\NewTheme.tga")
    slickThumb:SetSize(608, 280)

    local function makeRadioBtn(parent, label, x, y)
        local btn = CreateFrame("CheckButton", nil, parent)
        btn:SetSize(26, 26)
        btn:SetPoint("BOTTOMLEFT", parent, "BOTTOMLEFT", x, y)
        btn:SetNormalTexture("Interface\\Buttons\\UI-CheckBox-Up")
        btn:SetPushedTexture("Interface\\Buttons\\UI-CheckBox-Down")
        btn:SetHighlightTexture("Interface\\Buttons\\UI-CheckBox-Highlight")
        btn:SetCheckedTexture("Interface\\Buttons\\UI-CheckBox-Check")
        local lbl = parent:CreateFontString(nil, "OVERLAY", "GameFontNormal")
        lbl:SetPoint("LEFT", btn, "RIGHT", 4, 0)
        lbl:SetText(label)
        return btn
    end

    local oldThemeBtn = makeRadioBtn(picker, "Old Theme", 220, 10)
    local newThemeBtn = makeRadioBtn(picker, "New Theme", 620, 10)
    newThemeBtn:SetChecked(true)

    oldThemeBtn:SetScript("OnClick", function()
        pickerSelected = "Classic"
        oldThemeBtn:SetChecked(true)
        newThemeBtn:SetChecked(false)
    end)

    newThemeBtn:SetScript("OnClick", function()
        pickerSelected = "Slick"
        newThemeBtn:SetChecked(true)
        oldThemeBtn:SetChecked(false)
    end)

    local function confirmChoice(theme)
        self.db.global.themechoice = 0
        self.db.global.theme = theme
        picker:Hide()
        self.uiBuilt = true
        CGTheme:ClearRegistry()
        if theme == uiThemes[2] then
            self:DrawMainEvents()
        else
            self:DrawMainEvents2()
        end
    end

    local confirmBtn = CreateFrame("Button", nil, picker, "UIPanelButtonTemplate")
    confirmBtn:SetSize(100, 26)
    confirmBtn:SetPoint("BOTTOM", picker, "BOTTOM", 0, 10)
    confirmBtn:SetText("Confirm")
    confirmBtn:SetScript("OnClick", function()
        confirmChoice(pickerSelected)
    end)

    picker.CloseButton:SetScript("OnClick", function()
        confirmChoice("Slick")
    end)

    picker:Show()
end

function CrossGambling:ToggleGUI(info, isShowing)
    self:BuildUI()
    local method = isShowing and "Show" or "Hide"
    local theme = self.db.global.theme

    if theme == uiThemes[1] then
        CrossGambling[method .. "Classic"](CrossGambling)
    elseif theme == uiThemes[2] then
        CrossGambling[method .. "Slick"](CrossGambling)
    end
end
