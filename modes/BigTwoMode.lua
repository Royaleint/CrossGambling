-- BigTwo: a coin flip. Everyone rolls 1-2; whoever rolls the 2 wins the wager from whoever rolls
-- the 1. Ties re-roll like Classic. Uses the shared high/low rules from ClassicMode.lua.

CrossGambling:RegisterMode(CrossGambling:NewHighLowMode(
    "BigTwo",
    "Everyone rolls 1-2. High roll wins the full wager from the low roll. Ties at the top or bottom re-roll.",
    { fixedMax = 2, stakeIsWager = true }
))
