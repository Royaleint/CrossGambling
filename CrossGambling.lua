CrossGambling = LibStub("AceAddon-3.0"):NewAddon("CrossGambling", "AceConsole-3.0", "AceEvent-3.0")
local CrossGambling = LibStub("AceAddon-3.0"):GetAddon("CrossGambling")

local uiThemes = {
    "Classic",
    "Slick"
}

local options = {
    name = "CrossGambling",
    handler = CrossGambling,
    type = 'group',
    args = {
        show = {
            name = "Show",
            desc = "Show Game",
            type = "execute",
            func = function()
                CrossGambling:ToggleGUI(nil, true)
            end
        },
        hide = {
            name = "Hide",
            desc = "Hide Game",
            type = "execute",
            func = function()
                CrossGambling:ToggleGUI(nil, false)
            end
        },
        minimap = {
            name = "Minimap",
            desc = "Show/Hide Minimap Icon",
            type = "execute",
            func = "ToggleMinimap"
        },
        allstats = {
            name = "All Stats",
            desc = "Shows all Stats(Out of Order in Guild)",
            type = "execute",
            func = function()
                CrossGambling:reportStats(true)
            end
        },
        stats = {
            name = "Fame/Shame",
            desc = "Shows Top 3 Winners/Losers(Out of Order in Guild)",
            type = "execute",
            func = "reportStats"
        },
        joinstats = {
            name = "Join Stats",
            desc = "[main] [alt] - Join the two character's win/loss amounts on stat tracker",
            type = "input",
            set = "joinStats"
        },
        unjoinstats = {
            name = "Unjoin Stats",
            desc = "[alt] - Unjoins the Alt from whomever it's attached to",
            type = "input",
            set = "unjoinStats"
        },
        listalts = {
            name = "List Alts",
            desc = "See everyone whos used joinstats",
            type = "execute",
            func = "listAlts"
        },
        updatestat = {
            name = "Update Stat",
            desc = "[player] [amount] - Add [amount] to [player]'s stats (use negative numbers to subtract)",
            type = "input",
            set = "updateStat"
        },
        deletestat = {
            name = "Delete Stat",
            desc = "[player] - Permanently delete stats",
            type = "input",
            set = "deleteStat"
        },
        resetstats = {
            name = "Reset Stats",
            desc = "Deletes All Stats",
            type = "execute",
            func = "resetStats"
        },
        exportstats = {
            name = "Export Stats",
            desc = "Open the stats export window",
            type = "execute",
            func = function()
                CrossGambling:ShowStatsTransferFrame("export")
            end
        },
        importstats = {
            name = "Import Stats",
            desc = "Open the stats import window",
            type = "execute",
            func = function()
                CrossGambling:ShowStatsTransferFrame("import")
            end
        },
        ban = {
            name = "Ban Player",
            desc = "[player] -  Ban players from joining",
            type = "input",
            set = "banPlayer"
        },
        unban = {
            name = "Unban Player",
            desc = "[player] - Unbans a previously banned player",
            type = "input",
            set = "unbanPlayer"
        },
        listbans = {
            name = "List Bans",
            desc = "See banned players",
            type = "execute",
            func = "listBans"
        },
        audit = {
            name = "List Merges",
            desc = "See all merged players or changes",
            type = "execute",
            func = "auditMerges"
        },
        testing = {
            name = "Testing Mode",
            desc = "[on|off] - Enable to unlock /cg testbots and debug chat echoes. Off by default.",
            type = "input",
            set = "SetTestingMode"
        },
        testbots = {
            name = "Test Bots",
            desc = "[count] - Start a local bot-only test game in the current mode. Requires /cg testing on first.",
            type = "input",
            set = "StartBotTest"
        },
        stoptest = {
            name = "Stop Bot Test",
            desc = "Stops/resets an in-progress bot test game",
            type = "execute",
            func = "StopBotTest"
        },
    }
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

function CrossGambling:HandleSlashCommand(input)
    local trimmed = self:TrimInput(input)
    if trimmed == "" then
        self:PrintCommandHelp()
        return
    end

    local command, remainder = trimmed:match("^(%S+)%s*(.-)$")
    command = command and command:lower() or ""
    remainder = self:TrimInput(remainder)

    local option = options.args[command]
    if not option then
        self:Print(("Unknown command: %s"):format(command))
        self:PrintCommandHelp()
        return
    end

    if option.type == "execute" then
        if type(option.func) == "string" then
            local method = self[option.func]
            if type(method) == "function" then
                method(self)
                return
            end
        elseif type(option.func) == "function" then
            option.func()
            return
        end
    elseif option.type == "input" then
        if remainder == "" then
            self:Print(("Usage: /cg %s %s"):format(command, option.desc or "<value>"))
            return
        end

        if type(option.set) == "string" then
            local method = self[option.set]
            if type(method) == "function" then
                method(self, nil, remainder)
                return
            end
        elseif type(option.set) == "function" then
            option.set(nil, remainder)
            return
        end
    end

    self:Print(("Command '%s' is not available right now."):format(command))
end

function CrossGambling:OnInitialize()
    self:InitDB()
    self:InitMinimap()
    self:RegisterEvent("CHAT_MSG_ADDON", "OnAddonMessage")
    self:RegisterEvent("PLAYER_REGEN_DISABLED", "OnCombatStart")
    self:RegisterEvent("PLAYER_REGEN_ENABLED", "OnCombatEnd")
    self:RegisterEvent("ENCOUNTER_START", "OnEncounterStart")
    self:RegisterEvent("ENCOUNTER_END", "OnEncounterEnd")
    self:RegisterChatCommand("CrossGambling", "HandleSlashCommand")
    self:RegisterChatCommand("cg", "HandleSlashCommand")
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
