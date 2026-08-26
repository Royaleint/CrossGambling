-- Raffle: every entrant buys a ticket at the wager price. The host rolls 1-wager and that number
-- picks a ticket holder; everyone else pays the winner one wager.

local RaffleMode = {}
RaffleMode.name        = "Raffle"
RaffleMode.description = "Join to buy a ticket at the wager price - the host can buy one too. Once entries close, the host rolls 1-to-the-wager and that number picks one random ticket-holder as the winner. Every other entrant then pays the winner one wager's worth of gold."
RaffleMode.minPlayers  = 2
RaffleMode.hostRolls   = true

function RaffleMode:OnStartRolls(addon, game)
    addon:Announce(string.format(
        "CrossGambling: Raffle! %s rolls 1-%d to draw the winning ticket!",
        game.hostName or "The host", addon:GetWager()
    ))
end

function RaffleMode:GetRollRange(addon, game)
    return 1, addon:GetWager()
end

function RaffleMode:OnRollReceived(addon, game, playerName, actualRoll, minRoll, maxRoll)
    local wager = addon:GetWager()
    if minRoll ~= 1 or maxRoll ~= wager then return end
    if not game.hostName or playerName ~= game.hostName then return end
    if #game.players == 0 then return end

    local winnerIndex = ((actualRoll - 1) % #game.players) + 1
    local winner      = game.players[winnerIndex]
    addon:RecordRoll(winner.name, "Winner")

    local lines = { string.format("CrossGambling: Winning ticket is %d! %s takes the pot!", actualRoll, winner.name) }

    for i = 1, #game.players do
        local p = game.players[i]
        if p.name ~= winner.name then
            table.insert(lines, addon:SettleDebt(p.name, winner.name, wager, RaffleMode.name))
        end
    end

    addon:FinishGame(lines)
end

CrossGambling:RegisterMode(RaffleMode)
