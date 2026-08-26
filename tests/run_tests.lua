-- Headless game-logic tests. Run from the repo root with:  lua tests/run_tests.lua
-- Loads the core files in TOC order (no GUI), then plays each mode through the same entry points
-- the game client uses: chat lines for joins/picks and /roll system messages for rolls.

package.path = "./tests/?.lua;" .. package.path
local Stub = require("wow_stub")

local LOAD_ORDER = {
    "CrossGambling.lua",
    "core/Utils.lua", "core/DB.lua", "core/Minimap.lua", "core/Comm.lua", "core/ChatEvents.lua",
    "core/Players.lua", "core/ModeRegistry.lua", "core/Game.lua", "core/Stats.lua", "core/History.lua",
    "modes/ClassicMode.lua", "modes/BigTwoMode.lua", "modes/DeathRollMode.lua", "modes/EliminationMode.lua",
    "modes/HotPotatoMode.lua", "modes/OverUnderMode.lua", "modes/RaffleMode.lua",
    "core/DebugBots.lua",
}

for _, file in ipairs(LOAD_ORDER) do
    assert(loadfile(file))()
end

local CG = CrossGambling
CG:OnInitialize()

-- Helpers ---------------------------------------------------------------------------------------------

local passed, failed = 0, 0
local currentTest

local function check(condition, message)
    if condition then
        passed = passed + 1
    else
        failed = failed + 1
        print(string.format("  FAIL [%s]: %s", currentTest, message))
    end
end

local function eq(actual, expected, message)
    check(actual == expected, string.format("%s (expected %s, got %s)", message, tostring(expected), tostring(actual)))
end

local function test(name, fn)
    currentTest = name
    Stub.reset()
    CG:ResetGameState()
    CG.db.global.stats = {}
    CG.db.global.deathrollStats = {}
    CG.db.global.modeStats = {}
    CG.db.global.auditLog = {}
    CG.db.global.housestats = 0
    CG.db.global.bans = {}
    CG:RebuildBanCache()
    CG.game.sessionStats = {}
    CG.game.house = false
    CG.game.chatframeOption = true
    CG.game.chatMethod = "PARTY"
    local ok, err = pcall(fn)
    if not ok then
        failed = failed + 1
        print(string.format("  ERROR [%s]: %s", name, tostring(err)))
    end
end

local function saidInChat(fragment)
    for _, line in ipairs(Stub.chatLog) do
        if line.text:find(fragment, 1, true) then
            return true
        end
    end
    return false
end

local function sentMessage(prefixText)
    for _, m in ipairs(Stub.network) do
        if m.msg == prefixText or m.msg:sub(1, #prefixText + 1) == prefixText .. ":" then
            return true
        end
    end
    return false
end

-- Addon-message echoes are delivered async now (queued on Stub.timers, like the real client) rather
-- than inline inside SendMsg's pcall, so anything that depends on the host hearing its own broadcast
-- (joining/leaving by chat, banning) needs to drain the queue after firing the trigger.
local function chat(name, text)
    CG:FireEvent("CHAT_MSG_PARTY", text, name .. "-Testrealm")
    Stub.runTimers()
end

local function roll(name, value, minRoll, maxRoll)
    CG:FireEvent("CHAT_MSG_SYSTEM", string.format("%s rolls %d (%d-%d)", name, value, minRoll or 1, maxRoll or CG:GetWager()))
end

local function host(mode, wager, players)
    CG.game.mode = mode
    CG.db.global.wager = wager
    CG:HostNewGame()
    for _, name in ipairs(players or {}) do
        chat(name, "1")
    end
end

local function ban(name)
    CG:banPlayer(nil, name)
    Stub.runTimers()
end

local function names()
    local list = {}
    for _, p in ipairs(CG.game.players) do list[#list + 1] = p.name end
    return table.concat(list, ",")
end

local function stat(name) return CG.db.global.stats[name] or 0 end

-- Tests -----------------------------------------------------------------------------------------------

test("all modes registered", function()
    eq(#CG.modeListOrder, 7, "mode count")
    for _, name in ipairs({ "Classic", "BigTwo", "1v1DeathRoll", "Elimination", "HotPotato", "OverUnder", "Raffle" }) do
        check(CG.modeRegistry[name], "mode registered: " .. name)
    end
end)

test("host opens entries, players join and leave by chat", function()
    host("Classic", 1000, { "Alice", "Bob", "Cara" })
    eq(CG.game.state, "REGISTER", "state")
    eq(CG.game.hostName, "Hostplayer", "host name")
    eq(CG.game.wager, 1000, "game wager")
    eq(names(), "Alice,Bob,Cara", "roster after joins")
    chat("Bob", "-1")
    eq(names(), "Alice,Cara", "roster after leave")
    chat("Alice", "1")
    eq(names(), "Alice,Cara", "duplicate join ignored")
    check(sentMessage("New_Game"), "New_Game broadcast")
    check(sentMessage("HOST_NAME"), "HOST_NAME broadcast")
    check(saidInChat("A new game has been started"), "start announced in chat")
    check(saidInChat("Game Mode - Classic - Wager - 1,000g"), "summary line announced")
end)

test("banned players cannot join", function()
    CG.db.global.bans = { "Mallory-Otherrealm" }
    CG:RebuildBanCache()
    host("Classic", 1000, { "Alice", "Mallory" })
    eq(names(), "Alice", "banned player kept out")
    check(saidInChat("Sorry Mallory, you're banned."), "ban announced once")
end)

test("not enough players to start", function()
    host("Classic", 1000, { "Alice" })
    CG:CGRolls()
    eq(CG.game.state, "REGISTER", "still registering")
    check(saidInChat("Not enough Players"), "warned")
end)

test("classic: highest wins the difference from the lowest", function()
    host("Classic", 1000, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    eq(CG.game.state, "ROLL", "rolling")
    check(CG:IsEventRegistered("CHAT_MSG_SYSTEM"), "listening for rolls")
    check(sentMessage("Disable_Join"), "join closed broadcast")
    roll("Alice", 700)
    roll("Bob", 200)
    roll("Bob", 999)            -- second roll from the same player is ignored
    roll("Cara", 950, 1, 500)   -- wrong range is ignored
    eq(CG.game.state, "ROLL", "waiting on Cara")
    CG:CGRolls()
    check(saidInChat("Cara still needs to roll!"), "nag names the right player")
    roll("Cara", 950)
    eq(CG.game.state, "START", "game closed")
    eq(stat("Bob"), -750, "loser stat")
    eq(stat("Cara"), 750, "winner stat")
    eq(stat("Alice"), 0, "middle untouched")
    eq(CG.db.global.modeStats.Classic.Cara, 750, "mode stat")
    eq(#CG.db.global.auditLog, 1, "one audit entry")
    eq(CG.db.global.auditLog[1].amount, 750, "audit amount")
    check(saidInChat("Bob owes Cara 750g!"), "settlement announced")
    check(sentMessage("GAME_OVER"), "GAME_OVER broadcast")
    check(not CG:IsEventRegistered("CHAT_MSG_SYSTEM"), "stopped listening for rolls")
    check(not CG:IsEventRegistered("CHAT_MSG_PARTY"), "stopped listening to chat")
end)

test("classic: high tie then low tie are both re-rolled", function()
    host("Classic", 1000, { "Alice", "Bob", "Cara", "Dan" })
    CG:CGRolls()
    roll("Alice", 900) roll("Bob", 900) roll("Cara", 100) roll("Dan", 100)
    eq(CG.game.state, "ROLL", "still open after double tie")
    check(saidInChat("High tie breaker! Alice and Bob /roll 1000 now!"), "high tie announced")
    roll("Cara", 5)            -- not part of the tie-break, ignored
    roll("Alice", 600) roll("Bob", 400)
    check(saidInChat("Low tie breaker! Cara and Dan /roll 1000 now!"), "low tie announced")
    roll("Cara", 50) roll("Dan", 60)
    eq(CG.game.state, "START", "settled")
    eq(stat("Alice"), 800, "winner gets the original difference")
    eq(stat("Cara"), -800, "loser pays the original difference")
    eq(stat("Bob"), 0, "tied-out player pays nothing")
    eq(stat("Dan"), 0, "tied-out player pays nothing")
end)

test("classic: everyone rolling the same number is a wash", function()
    host("Classic", 1000, { "Alice", "Bob" })
    CG:CGRolls()
    roll("Alice", 500) roll("Bob", 500)
    eq(CG.game.state, "START", "closed")
    eq(stat("Alice"), 0, "no debt")
    check(saidInChat("No winners this round"), "announced")
end)

test("classic: house cut goes to the guild", function()
    CG.game.house = true
    CG.db.global.houseCut = 10
    host("Classic", 1000, { "Alice", "Bob" })
    check(saidInChat("House Cut - 10%"), "summary shows house cut")
    CG:CGRolls()
    roll("Alice", 1000) roll("Bob", 200)
    eq(stat("Alice"), 720, "winner net of cut")
    eq(stat("Bob"), -720, "loser net of cut")
    eq(stat("guild"), 80, "guild stat")
    eq(CG.db.global.housestats, 80, "house total")
    check(saidInChat("Plus 80g to the guild"), "cut announced")
end)

test("bigtwo: coin flip for the wager, saved wager untouched", function()
    host("BigTwo", 5000, { "Alice", "Bob" })
    CG:CGRolls()
    local lo, hi = CG:GetRollRange()
    eq(lo, 1, "range min") eq(hi, 2, "range max")
    roll("Alice", 2, 1, 2) roll("Bob", 1, 1, 2)
    eq(stat("Alice"), 5000, "winner takes the wager")
    eq(stat("Bob"), -5000, "loser pays the wager")
    eq(CG.db.global.wager, 5000, "saved wager not overwritten")
end)

test("deathroll: turns, shrinking range, loser pays the wager", function()
    host("1v1DeathRoll", 1000, { "Alice", "Bob", "Cara" })
    eq(names(), "Alice,Bob", "capped at two players")
    check(saidInChat("This game mode is full"), "third player told")
    CG:CGRolls()
    check(saidInChat("Alice, it's your turn! Type /roll 1000"), "first turn prompt")
    roll("Bob", 500, 1, 1000)
    check(saidInChat("Bob, it's not your turn!"), "out of turn rejected")
    roll("Alice", 400, 1, 1000)
    local _, hi = CG:GetRollRange()
    eq(hi, 400, "range shrinks")
    check(saidInChat("Bob, it's your turn! Type /roll 400"), "next prompt")
    eq(CG:GetCurrentTurn(), "Bob", "turn tracked")
    roll("Bob", 400, 1, 1000)   -- stale range, ignored
    roll("Bob", 1, 1, 400)
    eq(CG.game.state, "START", "closed on a 1")
    eq(stat("Bob"), -1000, "loser pays wager")
    eq(stat("Alice"), 1000, "winner")
    eq(CG.db.global.deathrollStats.Alice, 1000, "deathroll stat kept")
    eq(#CG.db.global.auditLog, 1, "audit entry written")
    check(sentMessage("GAME_OVER"), "clients told")
end)

test("elimination: lowest is out each round, finale is a deathroll", function()
    host("Elimination", 100, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    roll("Alice", 50, 1, 100) roll("Bob", 10, 1, 100) roll("Cara", 80, 1, 100)
    check(saidInChat("Bob rolled lowest (10) and is out!"), "elimination announced")
    check(saidInChat("Final 1v1! Alice vs Cara"), "finale announced")
    eq(CG:GetCurrentTurn(), "Alice", "finale turn")
    roll("Alice", 30, 1, 100)
    local _, hi = CG:GetRollRange()
    eq(hi, 30, "finale range shrinks")
    roll("Cara", 1, 1, 30)
    eq(CG.game.state, "START", "closed")
    eq(stat("Alice"), 200, "winner collects from both")
    eq(stat("Bob"), -100, "first out pays")
    eq(stat("Cara"), -100, "finalist pays")
end)

test("elimination: tie for lowest re-rolls between the tied", function()
    host("Elimination", 100, { "Alice", "Bob", "Cara", "Dan" })
    CG:CGRolls()
    roll("Alice", 5, 1, 100) roll("Bob", 5, 1, 100) roll("Cara", 80, 1, 100) roll("Dan", 90, 1, 100)
    check(saidInChat("Tie at 5 between Alice, Bob!"), "tie announced")
    roll("Cara", 1, 1, 100)   -- not in the tie-break, ignored
    roll("Alice", 20, 1, 100) roll("Bob", 30, 1, 100)
    check(saidInChat("Alice rolled lowest (20) and is out!"), "tie resolved")
    check(saidInChat("Round 2 - 3 players remain"), "next round")
end)

test("hotpotato: five rounds, holder pays everyone", function()
    host("HotPotato", 250, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    for round = 1, 5 do
        roll("Alice", 50, 1, 100) roll("Bob", 60, 1, 100) roll("Cara", 70, 1, 100)
        if round < 5 then
            check(saidInChat(string.format("Round %d/5 - roll 1-100!", round + 1)), "round " .. round + 1 .. " announced")
        end
    end
    eq(CG.game.state, "START", "closed")
    eq(stat("Alice"), -500, "holder pays both")
    eq(stat("Bob"), 250, "paid") eq(stat("Cara"), 250, "paid")
end)

test("overunder: picks by chat, host roll decides", function()
    host("OverUnder", 100, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    check(CG:IsEventRegistered("CHAT_MSG_PARTY"), "still listening for picks")
    chat("Alice", "over") chat("Bob", "under") chat("Cara", "banana") chat("Alice", "under")
    check(saidInChat("Alice picks over!"), "pick announced")
    roll("Alice", 80, 1, 100)          -- only the host's roll counts
    eq(CG.game.state, "ROLL", "player roll ignored")
    roll("Hostplayer", 80, 1, 100)
    eq(CG.game.state, "START", "closed")
    eq(stat("Alice"), 100, "over wins")
    eq(stat("Bob"), -100, "under loses")
    eq(stat("Cara"), 0, "no pick, no bet")
    eq(stat("Hostplayer"), 0, "house even")
end)

test("overunder: exact 50 wins everything for the house", function()
    host("OverUnder", 100, { "Alice", "Bob" })
    CG:CGRolls()
    chat("Alice", "over") chat("Bob", "under")
    roll("Hostplayer", 50, 1, 100)
    eq(stat("Hostplayer"), 200, "house takes both")
end)

test("raffle: the roll picks a ticket, everyone else pays", function()
    host("Raffle", 300, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    roll("Hostplayer", 5, 1, 300)   -- 5 -> index ((5-1) % 3) + 1 = 2 -> Bob
    eq(stat("Bob"), 600, "winner")
    eq(stat("Alice"), -300, "pays") eq(stat("Cara"), -300, "pays")
end)

test("roll parser follows the client's RANDOM_ROLL_RESULT string", function()
    host("Classic", 100, { "Alice", "Bob" })
    CG:CGRolls()
    -- Cross-realm names arrive with a realm suffix and must still match the roster.
    roll("Alice-Otherrealm", 90, 1, 100)
    eq(CG:getPlayerByName("Alice").roll, 90, "realm suffix stripped")
    roll("Bob", 10, 1, 100)
    eq(stat("Alice"), 80, "settled")
end)

test("client: mirrors the host's game from addon messages", function()
    Stub.echoAddonMessages = false
    CG.db.global.wager = 1000
    local function fromHost(msg) CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", msg, "PARTY", "Remotehost-Otherrealm") end
    fromHost("R_NewGame")
    fromHost("New_Game")
    fromHost("SET_WAGER:2500")
    fromHost("GAME_MODE:1v1DeathRoll")
    fromHost("Chat_Method:RAID")
    fromHost("SET_HOUSE:15")
    fromHost("HOST_NAME:Remotehost")
    eq(CG.game.host, false, "not host")
    eq(CG.game.hostName, "Remotehost", "host recorded from the sender")
    eq(CG.game.state, "REGISTER", "registering")
    eq(CG.game.wager, 2500, "wager synced")
    eq(CG.db.global.wager, 1000, "saved wager left alone")
    eq(CG.game.mode, "1v1DeathRoll", "mode synced")
    eq(CG.game.chatMethod, "RAID", "chat method synced")
    eq(CG.game.houseCut, 15, "house cut synced")
    fromHost("ADD_PLAYER:Alice")
    fromHost("ADD_PLAYER:Bob")
    eq(names(), "Alice,Bob", "roster mirrored")
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "ADD_PLAYER:Mallory", "PARTY", "Griefer-Otherrealm")
    eq(names(), "Alice,Bob", "non-host control message ignored")
    fromHost("Remove_Player:Bob")
    eq(names(), "Alice", "removal mirrored")
    fromHost("Disable_Join")
    eq(CG.game.state, "ROLL", "roll phase mirrored")
    check(not CG:IsEventRegistered("CHAT_MSG_SYSTEM"), "clients never parse rolls")
    fromHost("PLAYER_ROLL:Alice:77")
    eq(CG:getPlayerByName("Alice").roll, 77, "remote roll mirrored")
    local _, hi = CG:GetRollRange()
    eq(hi, 77, "deathroll range follows the host")
    CG:rollMe()
    eq(Stub.rolls[1][2], 77, "Roll Me uses the synced range")
    fromHost("GAME_OVER")
    eq(CG.game.state, "START", "reset on game over")
    eq(CG.game.hostName, nil, "host cleared")
    eq(#CG.game.players, 0, "roster cleared")
    Stub.echoAddonMessages = true
end)

test("client: a new host's announcement replaces a stale game", function()
    Stub.echoAddonMessages = false
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "New_Game", "PARTY", "Firsthost")
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "ADD_PLAYER:Alice", "PARTY", "Firsthost")
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "New_Game", "PARTY", "Secondhost")
    eq(CG.game.hostName, "Secondhost", "adopted the new host")
    eq(#CG.game.players, 0, "old roster dropped")
    Stub.echoAddonMessages = true
end)

test("client: chat panel lines are parsed even when the text has colons", function()
    local shown
    CG.CGRightMenu = { TextField = { AddMessage = function(_, text) shown = text end } }
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "CHAT_MSG:Alice:MAGE:hello: world", "PARTY", "Alice")
    check(shown and shown:find("hello: world", 1, true), "text kept intact")
    check(shown and shown:find("ff69ccf0", 1, true), "class colored")
    CG.CGRightMenu = nil
end)

test("announce: host talks to chat, clients only print", function()
    CG.game.host = true
    CG:Announce("hello")
    eq(#Stub.chatLog, 1, "host sent to chat")
    CG.game.host = false
    CG:Announce("hello")
    eq(#Stub.chatLog, 1, "client did not")
    eq(Stub.printLog[#Stub.printLog], "hello", "client printed locally")
end)

test("announce: addon chat panel option routes through addon messages", function()
    CG.game.host = true
    CG.game.chatframeOption = false
    CG:Announce("panel line")
    eq(#Stub.chatLog, 0, "nothing in party chat")
    check(sentMessage("CHAT_MSG"), "sent to the panel")
end)

test("bots: every mode plays to completion", function()
    CG.db.global.testingMode = true
    CG.uiBuilt = true   -- no window in the harness; BuildUI would otherwise open the theme picker
    for _, mode in ipairs(CG.modeListOrder) do
        Stub.reset()
        CG:ResetGameState()
        CG.game.mode = mode
        CG.db.global.wager = 100
        CG:StartBotTest(nil, "4")
        eq(CG.game.state, "ROLL", mode .. ": bots started")
        Stub.runTimers()
        eq(CG.game.state, "START", mode .. ": bot game finished")
        check(CG.botTestSteps < 300, mode .. ": finished within the step limit")
    end
    CG.db.global.testingMode = false
end)

-- Argus Gate 1 fixes -----------------------------------------------------------------------------

test("host ignores a remote R_NewGame echo (does not wipe its own roster)", function()
    host("Classic", 1000, { "Alice", "Bob" })
    local fired = false
    CGCall["R_NewGame"] = function() fired = true end
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "R_NewGame", "PARTY", "Rival-Testrealm")
    CGCall["R_NewGame"] = nil
    eq(CG.game.host, true, "still host")
    eq(#CG.game.players, 2, "roster kept")
    check(not fired, "CGCall R_NewGame did not fire for the host's own game")
end)

test("AnnounceOrPrint keeps working as the single surviving definition", function()
    Stub.inGroup = true
    Stub.inRaid = false
    CG.game.chatMethod = "PARTY"
    CG:AnnounceOrPrint("party line")
    check(saidInChat("party line"), "sent to party chat while grouped")

    Stub.inGroup = false
    CG:AnnounceOrPrint("solo line")
    check(Stub.printLog[#Stub.printLog] == "solo line", "printed locally when not in a group")
    Stub.inGroup = true
end)

test("client does not register chat events for a game it isn't hosting", function()
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "New_Game", "PARTY", "Remotehost-Otherrealm")
    check(not CG:IsEventRegistered("CHAT_MSG_PARTY"), "client did not register party chat for someone else's game")
end)

test("idle: host-only messages from a stray sender are dropped when no game is running", function()
    CG.game.mode = "Classic"
    CG.game.wager = nil
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "SET_WAGER:7", "PARTY", "Rando-Testrealm")
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "GAME_MODE:HotPotato", "PARTY", "Rando-Testrealm")
    CG:OnAddonMessage("CHAT_MSG_ADDON", "CrossGambling", "ADD_PLAYER:Ghost", "PARTY", "Rando-Testrealm")
    eq(CG.game.wager, nil, "wager untouched")
    eq(CG.game.mode, "Classic", "mode untouched")
    eq(#CG.game.players, 0, "roster untouched")
end)

test("elimination: banning a player mid-game doesn't crash and the game still settles", function()
    host("Elimination", 100, { "Alice", "Bob", "Cara", "Dan" })
    CG:CGRolls()
    roll("Alice", 50, 1, 100) roll("Bob", 10, 1, 100) roll("Cara", 80, 1, 100) roll("Dan", 90, 1, 100)
    check(saidInChat("Bob rolled lowest (10) and is out!"), "round 1 elimination happened normally")

    ban("Cara")

    eq(CG.game.state, "ROLL", "still mid-game right after the ban")
    check(saidInChat("Final 1v1! Alice vs Dan"), "ban brought it straight down to the finale")
    eq(CG:GetCurrentTurn(), "Alice", "finale turn set")

    roll("Alice", 30, 1, 100)
    local _, hi = CG:GetRollRange()
    eq(hi, 30, "finale range shrinks")
    roll("Dan", 1, 1, 30)

    eq(CG.game.state, "START", "game settled with no error")
    check(saidInChat("Alice wins the Elimination pot"), "winner settled")
end)

test("deathroll: banning a player mid-roll ends the game by forfeit instead of crashing", function()
    host("1v1DeathRoll", 1000, { "Alice", "Bob" })
    CG:CGRolls()

    ban("Bob")

    eq(CG.game.state, "START", "game closed on the ban instead of hanging")
    eq(stat("Alice"), 0, "no debt recorded")
    eq(stat("Bob"), 0, "no debt recorded")
    check(saidInChat("Bob left"), "forfeit announced")
    check(saidInChat("Alice wins"), "forfeit announced")
end)

test("chat method change re-registers chat events for the new channel", function()
    host("Classic", 1000, {})
    check(CG:IsEventRegistered("CHAT_MSG_PARTY"), "party registered while hosting on PARTY")
    CG:chatMethod()
    eq(CG.game.chatMethod, "RAID", "method switched to RAID")
    check(CG:IsEventRegistered("CHAT_MSG_RAID"), "raid now registered")
    check(not CG:IsEventRegistered("CHAT_MSG_PARTY"), "party no longer registered")
end)

test("CGCall table survives a reload of Comm.lua (doesn't wipe GUI-registered handlers)", function()
    CGCall.__marker = true
    assert(loadfile("core/Comm.lua"))()
    check(CGCall.__marker == true, "CGCall preserved across a reload")
    CGCall.__marker = nil
end)

test("non-host does not re-register chat events after a combat suspend/resume", function()
    -- Mirror a remote host's REGISTER state on this client (not host).
    CG.game.host = false
    CG.game.hostName = "Remotehost"
    CG.game.state = "REGISTER"
    CG.game.chatMethod = "PARTY"

    local realInCombatLockdown, realIsInInstance = InCombatLockdown, IsInInstance
    IsInInstance = function() return true, "arena" end

    InCombatLockdown = function() return true end
    CG:OnCombatStart()

    InCombatLockdown = function() return false end
    CG:OnCombatEnd()

    InCombatLockdown, IsInInstance = realInCombatLockdown, realIsInInstance

    check(not CG:IsEventRegistered("CHAT_MSG_PARTY"), "non-host stayed unregistered across a combat suspend/resume")
end)

test("classic: banning the last un-rolled player resolves the round instead of stalling", function()
    host("Classic", 1000, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    roll("Alice", 700)
    roll("Bob", 200)
    -- Cara never rolls; ban her instead of waiting forever.
    ban("Cara")
    eq(CG.game.state, "START", "settled instead of stalling on Cara")
    eq(stat("Alice"), 500, "winner stat")
    eq(stat("Bob"), -500, "loser stat")
end)

test("classic: banning down to one player closes the game with no debt", function()
    host("Classic", 1000, { "Alice", "Bob" })
    CG:CGRolls()
    roll("Alice", 700)
    ban("Bob")
    eq(CG.game.state, "START", "game closed instead of stalling")
    eq(stat("Alice"), 0, "no debt recorded")
    eq(stat("Bob"), 0, "no debt recorded")
    check(saidInChat("Bob left"), "closure announced")
end)

test("hotpotato: banning the last un-rolled player resolves the round instead of stalling", function()
    host("HotPotato", 250, { "Alice", "Bob", "Cara" })
    CG:CGRolls()
    roll("Alice", 50, 1, 100)
    roll("Bob", 60, 1, 100)
    -- Cara never rolls; ban her instead of waiting forever.
    ban("Cara")
    check(saidInChat("Alice rolled lowest (50) and holds the potato"), "round 1 resolved instead of stalling on Cara")
    check(saidInChat("Round 2/5"), "advanced to round 2")
end)

test("classic: banning both tied players during a tie-break closes the game instead of crashing", function()
    host("Classic", 1000, { "Alice", "Bob", "Cara", "Dan" })
    CG:CGRolls()
    roll("Alice", 900) roll("Bob", 900) roll("Cara", 500) roll("Dan", 100)
    check(saidInChat("High tie breaker! Alice and Bob"), "tie breaker started")

    ban("Alice")
    eq(CG.game.state, "ROLL", "still waiting on Bob after Alice is banned")
    ban("Bob")

    eq(CG.game.state, "START", "game closed instead of crashing on an empty tie-break")
    eq(stat("Alice"), 0, "no stat change") eq(stat("Bob"), 0, "no stat change")
    eq(stat("Cara"), 0, "no stat change") eq(stat("Dan"), 0, "no stat change")
    check(saidInChat("Bob left"), "closure announced")
end)

test("hotpotato: banning both tied-for-lowest players closes the round instead of crashing", function()
    host("HotPotato", 250, { "Alice", "Bob", "Cara", "Dan" })
    CG:CGRolls()
    roll("Alice", 50, 1, 100) roll("Bob", 50, 1, 100) roll("Cara", 90, 1, 100) roll("Dan", 80, 1, 100)
    check(saidInChat("Tie at 50 between Alice, Bob"), "tie detected")

    ban("Alice")
    ban("Bob")

    eq(CG.game.state, "START", "game closed instead of crashing on an empty tie-break")
end)

test("stats: helpers keep working after the refactor", function()
    eq(CG:addCommas(1234567), "1,234,567", "commas")
    eq(CG:addCommas(-1234), "-1,234", "negative commas")
    eq(CG:addCommas(999), "999", "short")
    eq(CG:String({ "A", "B", "C" }), "A, B and C", "name list")
    eq(CG:NormalizePlayerName(" Bob-Realm "), "bob", "normalize")
    eq(CG:ValidateWager("99999999"), 1000000, "wager clamp")
    eq(CG:NormalizeHouseCutValue("150"), 100, "house cut clamp")
    CG:updateStat(nil, "Alice 50")
    eq(stat("Alice"), 50, "manual stat update")
    CG:joinStats(nil, "Alice Alicealt")
    eq(CG.db.global.joinstats["alicealt"], "Alice", "alt joined")
    CG:unjoinStats(nil, "Alicealt")
    eq(CG.db.global.joinstats["alicealt"], nil, "alt unjoined")
end)

print(string.format("\n%d passed, %d failed", passed, failed))
os.exit(failed == 0 and 0 or 1)
