-- Chat channel listening: join/leave words while entries are open, mode chat picks while rolling,
-- /roll system messages, and the combat suspension that keeps the addon quiet during fights.

local chatMethods = { "PARTY", "RAID", "GUILD" }

local chatEventsByMethod = {
    PARTY = { "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    RAID  = { "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER", "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER" },
    GUILD = { "CHAT_MSG_GUILD" },
}

local allChatEvents = {
    "CHAT_MSG_PARTY", "CHAT_MSG_PARTY_LEADER",
    "CHAT_MSG_RAID", "CHAT_MSG_RAID_LEADER",
    "CHAT_MSG_INSTANCE_CHAT", "CHAT_MSG_INSTANCE_CHAT_LEADER",
    "CHAT_MSG_GUILD",
}

-- Build the /roll parser from the client's own RANDOM_ROLL_RESULT string ("%s rolls %d (%d-%d)")
-- so it works in every locale, with the English pattern as a fallback.
local rollResultPattern
local function GetRollResultPattern()
    if rollResultPattern then
        return rollResultPattern
    end

    local template = RANDOM_ROLL_RESULT
    if type(template) == "string" and template:find("%s", 1, true) then
        local pattern = template:gsub("%%(%d)%$", "%%")               -- "%1$s" -> "%s"
        pattern = pattern:gsub("[%(%)%.%+%-%*%?%[%]%^%$]", "%%%0")   -- escape magic characters
        pattern = pattern:gsub("%%s", "(%%S+)"):gsub("%%d", "(%%d+)")
        rollResultPattern = "^" .. pattern .. "%.?$"
    else
        rollResultPattern = "^(%S+) rolls (%d+) %((%d+)%-(%d+)%)%.?$"
    end

    return rollResultPattern
end

-- Registration --------------------------------------------------------------------------------------

function CrossGambling:RegisterChatEvents()
    -- Only the host runs the game (handleChatMsg is a no-op for everyone else); every caller of this
    -- function funnels through here, so this is the one place that needs the guard.
    if not self.game.host then
        return
    end

    if self:ShouldSuspendChatEventsInCombat() then
        self:SuspendRegistrationChatEvents()
        return
    end

    self.chatEventsSuspendedForCombat = false

    local events = chatEventsByMethod[self.game.chatMethod] or chatEventsByMethod.PARTY
    for _, eventName in ipairs(events) do
        self:RegisterEvent(eventName, "handleChatMsg")
    end
end

function CrossGambling:UnRegisterChatEvents()
    for _, eventName in ipairs(allChatEvents) do
        self:UnregisterEvent(eventName)
    end
end

function CrossGambling:chatMethod()
    local current = self.game.chatMethod
    local currentEvents = chatEventsByMethod[current] or chatEventsByMethod.PARTY
    local wasRegistered = currentEvents[1] ~= nil and self:IsEventRegistered(currentEvents[1])

    local newMethod = chatMethods[1]
    for i = 1, #chatMethods do
        if current == chatMethods[i] then
            newMethod = chatMethods[(i % #chatMethods) + 1]
            break
        end
    end
    self.game.chatMethod = newMethod

    -- Entries were already open on the old channel: swap the registered events over so the new
    -- channel actually gets heard, instead of silently listening on the channel we just left.
    if wasRegistered then
        self:UnRegisterChatEvents()
        self:RegisterChatEvents()
    end
end

-- Combat suspension ---------------------------------------------------------------------------------

function CrossGambling:IsHighImpactCombatContext()
    if self.bossEncounterActive then
        return true
    end

    local _, instanceType = IsInInstance()
    return instanceType == "arena" or instanceType == "pvp"
end

function CrossGambling:ShouldSuspendChatEventsInCombat()
    return self.db
        and self.db.global
        and self.db.global.suspendChatEventsInCombat ~= false
        and InCombatLockdown()
        and self:IsHighImpactCombatContext()
end

function CrossGambling:SuspendRegistrationChatEvents()
    if self.game.state == "START" then
        return
    end

    self.chatEventsSuspendedForCombat = true
    self:UnRegisterChatEvents()
end

function CrossGambling:ResumeRegistrationChatEvents()
    if not self.chatEventsSuspendedForCombat then
        return
    end

    local mode = self:GetCurrentMode()
    local pickPhaseActive = self.game.state == "ROLL" and mode and mode.usesChatPick

    if self.game.state == "REGISTER" or pickPhaseActive then
        self:RegisterChatEvents()
    end
end

function CrossGambling:OnCombatStart()
    if self:ShouldSuspendChatEventsInCombat() then
        self:SuspendRegistrationChatEvents()
    end
end

function CrossGambling:OnCombatEnd()
    self:ResumeRegistrationChatEvents()
end

function CrossGambling:OnEncounterStart()
    self.bossEncounterActive = true

    if self:ShouldSuspendChatEventsInCombat() then
        self:SuspendRegistrationChatEvents()
    end
end

function CrossGambling:OnEncounterEnd()
    self.bossEncounterActive = false

    if not self:ShouldSuspendChatEventsInCombat() then
        self:ResumeRegistrationChatEvents()
    end
end

-- Handlers -------------------------------------------------------------------------------------------

function CrossGambling:handleChatMsg(_, text, playerName)
    if self:ShouldSuspendChatEventsInCombat() then
        self:SuspendRegistrationChatEvents()
        return
    end

    -- Only the host runs the game; other clients get the roster over addon messages.
    if not self.game.host then
        return
    end

    playerName = self:ShortPlayerName(playerName)

    if self.game.state == "REGISTER" then
        self:RegisterGame(text, playerName)
    elseif self.game.state == "ROLL" then
        self:DispatchModeHook("OnChatText", playerName, text)
    end
end

function CrossGambling:handleSystemMessage(_, text)
    if self.game.state ~= "ROLL" or not self.game.host then
        return
    end

    local playerName, actualRoll, minRoll, maxRoll = strmatch(text, GetRollResultPattern())
    if not playerName or not actualRoll or not minRoll or not maxRoll then
        return
    end

    self:DispatchModeHook("OnRollReceived", self:ShortPlayerName(playerName), tonumber(actualRoll), tonumber(minRoll), tonumber(maxRoll))
end
