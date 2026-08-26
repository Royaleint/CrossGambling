-- The roster of the running game: self.game.players (ordered list) plus a name -> index lookup.
-- Each entry is { name = "Player", roll = nil | number | marker string }.

local function GetIndexByName(game)
    local indexByName = game.playerIndexByName
    if not indexByName then
        indexByName = {}
        for i = 1, #game.players do
            indexByName[game.players[i].name] = i
        end
        game.playerIndexByName = indexByName
    end
    return indexByName
end

function CrossGambling:ResetPlayers()
    self.game.players = {}
    self.game.playerIndexByName = nil
end

function CrossGambling:getPlayerByName(name)
    local playerIndex = name and GetIndexByName(self.game)[name]
    return playerIndex and self.game.players[playerIndex] or nil
end

-- Returns true when the player was added, false when they were already in.
function CrossGambling:registerPlayer(playerName, playerRoll)
    local players = self.game.players
    local indexByName = GetIndexByName(self.game)

    if indexByName[playerName] then
        return false
    end

    local newIndex = #players + 1
    players[newIndex] = { name = playerName, roll = playerRoll }
    indexByName[playerName] = newIndex
    return true
end

function CrossGambling:unregisterPlayer(playerName)
    local players = self.game.players
    local indexByName = GetIndexByName(self.game)
    local playerIndex = indexByName[playerName]
    if not playerIndex then
        return false
    end

    tremove(players, playerIndex)
    indexByName[playerName] = nil

    for i = playerIndex, #players do
        indexByName[players[i].name] = i
    end

    -- Only the current mode's round state cares about a mid-roll departure; joins/leaves during
    -- REGISTER are just roster bookkeeping and need no hook.
    if self.game.state == "ROLL" then
        self:DispatchModeHook("OnPlayerLeave", playerName)
    end

    return true
end

-- Names of players who still have no roll. Pass a set ({ name = true }) to only look at those.
function CrossGambling:CheckRolls(onlyThese)
    local pending = {}
    for i = 1, #self.game.players do
        local player = self.game.players[i]
        if player.roll == nil and (not onlyThese or onlyThese[player.name]) then
            table.insert(pending, player.name)
        end
    end
    return pending
end

function CrossGambling:hasPendingRolls(onlyThese)
    return #self:CheckRolls(onlyThese) > 0
end

-- Clear rolls for the next round. Pass a set to only clear some players.
function CrossGambling:ClearRolls(onlyThese)
    for i = 1, #self.game.players do
        local player = self.game.players[i]
        if not onlyThese or onlyThese[player.name] then
            player.roll = nil
        end
    end
end

-- Store a roll (or a marker like "Loser") for a player, refresh the player list, and tell the other
-- clients. Returns the player entry, or nil if the name is not in the game.
function CrossGambling:RecordRoll(playerName, value)
    local player = self:getPlayerByName(playerName)
    if not player then
        return nil
    end

    player.roll = value

    if CGCall["PLAYER_ROLL"] then
        CGCall["PLAYER_ROLL"](playerName, tostring(value))
    end

    if self.game.host then
        self:SendMsg("PLAYER_ROLL", playerName .. ":" .. tostring(value))
    end

    return player
end

-- Lowest and highest numeric rolls among the given names (or everyone). Returns two lists of
-- player names plus the two values, so ties are visible to the caller.
function CrossGambling:FindRollExtremes(onlyThese)
    local lowest, highest = {}, {}
    local lowValue, highValue

    for i = 1, #self.game.players do
        local player = self.game.players[i]
        local roll = tonumber(player.roll)
        if roll and (not onlyThese or onlyThese[player.name]) then
            if lowValue == nil or roll < lowValue then
                lowValue = roll
                lowest = { player.name }
            elseif roll == lowValue then
                table.insert(lowest, player.name)
            end

            if highValue == nil or roll > highValue then
                highValue = roll
                highest = { player.name }
            elseif roll == highValue then
                table.insert(highest, player.name)
            end
        end
    end

    return lowest, lowValue, highest, highValue
end

-- Named-player mirrors used by the GUI files. The GUI redefines these when it builds the window;
-- these fallbacks keep the core working (bot tests, slash commands) before a window exists.
function CrossGambling:AddPlayer(playerName)
end

function CrossGambling:RemovePlayer(playerName)
end
