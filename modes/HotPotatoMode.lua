-- Hot Potato: everyone rolls 1-100 for five rounds; the lowest roller each round holds the potato.
-- Whoever holds it after the last round pays everyone else the wager.
-- Round state lives in game.hotpotato = { round, holder, pending }.

local HotPotatoMode = {}
HotPotatoMode.name        = "HotPotato"
HotPotatoMode.description = "Everyone rolls 1-100 each round; the lowest roller holds the potato. After 5 rounds, whoever's left holding it pays everyone else the wager."
HotPotatoMode.minPlayers  = 3

local MAX_ROUNDS = 5
local ROLL_MAX   = 100

local function everyoneSet(game)
    local set = {}
    for i = 1, #game.players do
        set[game.players[i].name] = true
    end
    return set
end

local function payOut(addon, game)
    local hp    = game.hotpotato
    local wager = addon:GetWager()
    local lines = { string.format("CrossGambling: %s is left holding the potato and pays everyone!", hp.holder) }

    for i = 1, #game.players do
        local p = game.players[i]
        if p.name ~= hp.holder then
            table.insert(lines, addon:SettleDebt(hp.holder, p.name, wager, HotPotatoMode.name))
        end
    end

    addon:FinishGame(lines)
end

local function resolveRound(addon, game)
    local hp = game.hotpotato
    local lowest, lowVal = addon:FindRollExtremes(hp.pending)
    table.sort(lowest)

    -- Defensive: a resolve with no rolls left to compare (e.g. every remaining name in the pending
    -- set left) has no one to hold the potato. Never let hp.holder end up nil.
    if #lowest == 0 then
        addon:FinishGame({ "CrossGambling: Not enough rolls to settle - the game is closed." })
        return
    end

    if #lowest > 1 then
        addon:Announce(string.format(
            "CrossGambling: Tie at %d between %s! Re-roll 1-%d to see who takes the potato.",
            lowVal, table.concat(lowest, ", "), ROLL_MAX
        ))
        hp.pending = {}
        for _, name in ipairs(lowest) do
            hp.pending[name] = true
        end
        addon:ClearRolls(hp.pending)
        return
    end

    hp.holder = lowest[1]
    addon:Announce(string.format(
        "CrossGambling: %s rolled lowest (%d) and holds the potato! Round %d/%d complete.",
        hp.holder, lowVal, hp.round, MAX_ROUNDS
    ))

    if hp.round >= MAX_ROUNDS then
        payOut(addon, game)
        return
    end

    hp.round   = hp.round + 1
    hp.pending = everyoneSet(game)
    addon:ClearRolls()
    addon:Announce(string.format("CrossGambling: Round %d/%d - roll 1-%d!", hp.round, MAX_ROUNDS, ROLL_MAX))
end

function HotPotatoMode:OnStartRolls(addon, game)
    game.hotpotato = { round = 1, holder = nil, pending = everyoneSet(game) }
    addon:Announce(string.format(
        "CrossGambling: Hot Potato! Round 1/%d - everyone rolls 1-%d. Lowest roll holds the potato!",
        MAX_ROUNDS, ROLL_MAX
    ))
end

function HotPotatoMode:GetRollRange(addon, game)
    return 1, ROLL_MAX
end

function HotPotatoMode:OnRollReceived(addon, game, playerName, actualRoll, minRoll, maxRoll)
    local hp = game.hotpotato
    if not hp then return end
    if minRoll ~= 1 or maxRoll ~= ROLL_MAX then return end
    if not hp.pending[playerName] then return end

    local player = addon:getPlayerByName(playerName)
    if not player or player.roll ~= nil then return end

    addon:RecordRoll(playerName, actualRoll)

    if not addon:hasPendingRolls(hp.pending) then
        resolveRound(addon, game)
    end
end

-- A player was removed (banned) mid-round: drop them from the pending set and, if nobody's left
-- to wait on, resolve the round exactly as their last roll would have.
function HotPotatoMode:OnPlayerLeave(addon, game, playerName)
    local hp = game.hotpotato
    if not hp then return end

    if #game.players < 2 then
        addon:FinishGame({ string.format("CrossGambling: %s left. Not enough players remain - the game is closed.", playerName) })
        return
    end

    if not hp.pending then return end

    hp.pending[playerName] = nil

    -- The whole live set for this round just left - there's nothing left to resolve against, not
    -- even a lone straggler's roll. Close instead of resolving on empty.
    if next(hp.pending) == nil then
        addon:FinishGame({ string.format("CrossGambling: %s left. Not enough players remain in this round - the game is closed.", playerName) })
        return
    end

    if not addon:hasPendingRolls(hp.pending) then
        resolveRound(addon, game)
    end
end

function HotPotatoMode:OnEnd(addon, game)
    game.hotpotato = nil
end

CrossGambling:RegisterMode(HotPotatoMode)
