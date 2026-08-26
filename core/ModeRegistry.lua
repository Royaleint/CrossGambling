-- Game modes register themselves here. A mode is a plain table:
--
--   name          (required) shown on the mode button and used as the stats key
--   description   rules text for the tooltip and "Shift+Click to post rules"
--   minPlayers    default 2
--   maxPlayers    default nil (no cap)
--   usesChatPick  true when players answer in chat during the roll phase (OnChatText)
--   hostRolls     true when only the host rolls (raffle draws, over/under)
--
-- Hooks (all optional, all called as mode:Hook(addon, game, ...)):
--   OnStart(addon, game)                          host opened entries; announce the game
--   OnPlayerJoin(addon, game, name) -> bool       return false to refuse the entry
--   OnStartRolls(addon, game)                     entries closed; set up round state
--   OnRollReceived(addon, game, name, roll, min, max)
--   OnChatText(addon, game, name, text)           chat during the roll phase (usesChatPick)
--   OnRemoteRoll(addon, game, name, value)        client side: a roll relayed by the host
--   OnPlayerLeave(addon, game, name)              a player was removed mid-roll (game.state == "ROLL");
--                                                  name is already gone from game.players by the time this fires
--   GetRollRange(addon, game) -> min, max         what "Roll Me" and the bots should roll
--   GetCurrentTurn(addon, game) -> name           whose turn it is, for turn-based modes
--   OnEnd(addon, game)                            game closed; clear round state
--
-- Shared helpers a mode can lean on: addon:RecordRoll, addon:CheckRolls, addon:hasPendingRolls,
-- addon:ClearRolls, addon:FindRollExtremes, addon:SettleDebt, addon:Announce, addon:FinishGame,
-- addon:GetWager, addon:getPlayerByName.

CrossGambling.modeRegistry  = CrossGambling.modeRegistry  or {}
CrossGambling.modeListOrder = CrossGambling.modeListOrder or {}

function CrossGambling:RegisterMode(modeObj)
    assert(type(modeObj) == "table", "RegisterMode: mode must be a table")
    assert(type(modeObj.name) == "string" and modeObj.name ~= "", "RegisterMode: mode must have a non-empty .name")
    assert(not self.modeRegistry[modeObj.name], "RegisterMode: a mode named '" .. modeObj.name .. "' is already registered")

    modeObj.description  = modeObj.description or ""
    modeObj.minPlayers   = modeObj.minPlayers or 2
    modeObj.maxPlayers   = modeObj.maxPlayers or nil
    modeObj.usesChatPick = modeObj.usesChatPick or false
    modeObj.hostRolls    = modeObj.hostRolls or false

    self.modeRegistry[modeObj.name] = modeObj
    table.insert(self.modeListOrder, modeObj.name)
end

function CrossGambling:GetCurrentMode()
    return self.modeRegistry[self.game.mode]
end

function CrossGambling:changeGameMode()
    local list = self.modeListOrder
    if #list == 0 then return end

    local current = self.game.mode
    for i = 1, #list do
        if list[i] == current then
            self.game.mode = list[(i % #list) + 1]
            return
        end
    end
    self.game.mode = list[1]
end

-- Calls the hook on the current mode. Returns true when the mode had one, plus the hook's results.
function CrossGambling:DispatchModeHook(hookName, ...)
    local mode = self:GetCurrentMode()
    if mode and type(mode[hookName]) == "function" then
        return true, mode[hookName](mode, self, self.game, ...)
    end
    return false
end

function CrossGambling:GetModeRulesText(mode)
    if not mode then
        return "No Mode Selected", "Pick a game mode first."
    end

    local rules = (mode.description and mode.description ~= "") and mode.description or "No rules description available for this mode."
    return mode.name, rules
end

function CrossGambling:PostModeRules()
    local title, rules = self:GetModeRulesText(self:GetCurrentMode())
    self:SendChat(string.format("CrossGambling: %s Rules - %s", title, rules))
end

function CrossGambling:ShowGameModeTooltip(button)
    local title, rules = self:GetModeRulesText(self:GetCurrentMode())
    GameTooltip:SetOwner(button, "ANCHOR_RIGHT")
    GameTooltip:SetText(title, 1, 1, 1)
    GameTooltip:AddLine(rules, 0.9, 0.9, 0.9, true)
    GameTooltip:AddLine(" ")
    GameTooltip:AddLine("Shift+Click to post these rules in chat.", 0.6, 0.8, 1)
    GameTooltip:Show()
end

function CrossGambling:RefreshGameModeTooltip(button)
    if GameTooltip:IsShown() and GameTooltip:GetOwner() == button then
        self:ShowGameModeTooltip(button)
    end
end

function CrossGambling:AttachGameModeTooltip(button)
    button:HookScript("OnEnter", function(btn)
        self:ShowGameModeTooltip(btn)
    end)

    button:HookScript("OnLeave", function()
        GameTooltip:Hide()
    end)
end
