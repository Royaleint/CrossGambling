-- Classic: everyone rolls, highest roll wins the difference from the lowest roll.
--
-- The tie handling here is shared with BigTwo through CrossGambling:NewHighLowMode. Round state
-- lives in game.highlow:
--   stage      "main" (everyone rolls) | "high" (top-tied re-roll) | "low" (bottom-tied re-roll)
--   pending    set of names expected to roll this stage
--   winners    names currently tied for the win
--   losers     names currently tied for the loss
--   amountOwed the difference from the first full round; tie-breakers only decide who pays it

local function SetFromList(list)
    local set = {}
    for i = 1, #list do
        set[list[i]] = true
    end
    return set
end

-- options: fixedMax (roll ceiling instead of the wager), stakeIsWager (loser pays the wager instead
-- of the roll difference), allowHouseCut (honor the House Cut toggle)
function CrossGambling:NewHighLowMode(name, description, options)
    options = options or {}

    local Mode = {}
    Mode.name        = name
    Mode.description = description

    local function RollCeiling(addon)
        return options.fixedMax or addon:GetWager()
    end

    local function StartTieBreaker(addon, game, tieType, names)
        local hl = game.highlow
        hl.stage   = (tieType == "High") and "high" or "low"
        hl.pending = SetFromList(names)
        addon:ClearRolls(hl.pending)
        addon:Announce(tieType .. " tie breaker! " .. addon:String(names) .. " /roll " .. RollCeiling(addon) .. " now!")
    end

    local function Settle(addon, game)
        local hl = game.highlow

        -- Defensive: a resolve with no rolls left to compare (e.g. every remaining name in the
        -- pending set left) has no one to settle between. Never call SettleDebt with a nil name.
        if not hl.winners[1] or not hl.losers[1] then
            addon:FinishGame({ "CrossGambling: Not enough rolls to settle - the game is closed." })
            return
        end

        local amount, houseAmount = hl.amountOwed, 0
        if options.allowHouseCut then
            amount, houseAmount = addon:ApplyHouseCut(amount)
        end

        local line = addon:SettleDebt(hl.losers[1], hl.winners[1], amount, Mode.name)
        if houseAmount > 0 then
            line = line .. " Plus " .. addon:addCommas(houseAmount) .. "g to the guild."
        end
        addon:FinishGame({ line })
    end

    local function Resolve(addon, game)
        local hl = game.highlow
        local lowest, lowValue, highest, highValue = addon:FindRollExtremes(hl.pending)

        if hl.stage == "main" then
            if highValue == lowValue then
                addon:Announce("Everyone rolled " .. highValue .. "! No winners this round.")
                addon:CloseGame()
                return
            end
            hl.winners    = highest
            hl.losers     = lowest
            hl.amountOwed = options.stakeIsWager and addon:GetWager() or (highValue - lowValue)
        elseif hl.stage == "high" then
            hl.winners = highest
        else
            hl.losers = lowest
        end

        if #hl.winners > 1 then
            StartTieBreaker(addon, game, "High", hl.winners)
        elseif #hl.losers > 1 then
            StartTieBreaker(addon, game, "Low", hl.losers)
        else
            Settle(addon, game)
        end
    end

    function Mode:OnStartRolls(addon, game)
        local pending = {}
        for i = 1, #game.players do
            pending[game.players[i].name] = true
        end
        game.highlow = { stage = "main", pending = pending }
    end

    function Mode:GetRollRange(addon, game)
        return 1, RollCeiling(addon)
    end

    function Mode:OnRollReceived(addon, game, playerName, actualRoll, minRoll, maxRoll)
        local hl = game.highlow
        if not hl then return end
        if minRoll ~= 1 or maxRoll ~= RollCeiling(addon) then return end
        if not hl.pending[playerName] then return end

        local player = addon:getPlayerByName(playerName)
        if not player or player.roll ~= nil then return end

        addon:RecordRoll(playerName, actualRoll)

        if not addon:hasPendingRolls(hl.pending) then
            Resolve(addon, game)
        end
    end

    -- A player was removed (banned) mid-round or mid-tie-break: drop them from whichever pending
    -- set is live and, if nobody's left to wait on, resolve exactly as their last roll would have.
    function Mode:OnPlayerLeave(addon, game, playerName)
        local hl = game.highlow
        if not hl then return end

        if #game.players < 2 then
            addon:FinishGame({ string.format("CrossGambling: %s left. Not enough players remain - the game is closed.", playerName) })
            return
        end

        if not hl.pending then return end

        hl.pending[playerName] = nil

        -- The whole live set for this stage (round or tie-break) just left - there's nothing left
        -- to resolve against, not even a lone straggler's roll. Close instead of resolving on empty.
        if next(hl.pending) == nil then
            addon:FinishGame({ string.format("CrossGambling: %s left. Not enough players remain in this round - the game is closed.", playerName) })
            return
        end

        if not addon:hasPendingRolls(hl.pending) then
            Resolve(addon, game)
        end
    end

    function Mode:OnEnd(addon, game)
        game.highlow = nil
    end

    return Mode
end

CrossGambling:RegisterMode(CrossGambling:NewHighLowMode(
    "Classic",
    "Everyone rolls 1-wager. Highest roll wins the difference from the lowest roll. Ties at the top or bottom are settled with a re-roll between the tied players.",
    { allowHouseCut = true }
))
