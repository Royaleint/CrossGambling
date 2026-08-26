-- Minimal WoW + Ace3 environment so the game logic can run under plain Lua 5.1.
-- Only what the core files touch is stubbed; the GUI files are never loaded here.

local Stub = {}

-- Everything the addon says or sends, for assertions.
Stub.chatLog = {}       -- SendChatMessage lines
Stub.printLog = {}      -- addon:Print lines
Stub.network = {}       -- addon messages sent (delivered back to ourselves immediately, like WoW does)
Stub.timers = {}        -- C_Timer.After queue
Stub.rolls = {}         -- RandomRoll calls

Stub.playerName = "Hostplayer"
Stub.inGroup = true
Stub.inRaid = false
Stub.inGuild = true
Stub.echoAddonMessages = true

function Stub.reset()
    Stub.chatLog, Stub.printLog, Stub.network, Stub.timers, Stub.rolls = {}, {}, {}, {}, {}
end

-- WoW string helpers -------------------------------------------------------------------------------

function strsplit(delim, text, limit)
    local parts = {}
    local remaining = text
    while true do
        if limit and #parts == limit - 1 then
            parts[#parts + 1] = remaining
            break
        end
        local i = remaining:find(delim, 1, true)
        if not i then
            parts[#parts + 1] = remaining
            break
        end
        parts[#parts + 1] = remaining:sub(1, i - 1)
        remaining = remaining:sub(i + #delim)
    end
    return unpack(parts)
end

function strtrim(s) return (s:gsub("^%s+", ""):gsub("%s+$", "")) end
strlower = string.lower
strupper = string.upper
strmatch = string.match
strfind  = string.find
format   = string.format
tinsert  = table.insert
tremove  = table.remove
floor    = math.floor
function wipe(t) for k in pairs(t) do t[k] = nil end return t end
time = os.time
date = os.date

-- WoW API --------------------------------------------------------------------------------------------

RANDOM_ROLL_RESULT = "%s rolls %d (%d-%d)"
LE_PARTY_CATEGORY_HOME = 1
LE_PARTY_CATEGORY_INSTANCE = 2
RAID_CLASS_COLORS = { WARRIOR = { colorStr = "ffc79c6e" }, MAGE = { colorStr = "ff69ccf0" } }
UIParent = {}
ChatFontNormal = {}
BackdropTemplateMixin = {}
StaticPopupDialogs = {}
function StaticPopup_Show() end
function Mixin(t) return t end

function UnitName() return Stub.playerName end
function UnitClass() return "Warrior", "WARRIOR" end
function GetRealmName() return "Testrealm" end
function UnitRealmRelationship() return 1 end
function IsInGroup(category) if category == LE_PARTY_CATEGORY_INSTANCE then return false end return Stub.inGroup end
function IsInRaid() return Stub.inRaid end
function IsInGuild() return Stub.inGuild end
function IsInInstance() return false, "none" end
function InCombatLockdown() return false end
function IsShiftKeyDown() return false end
function RandomRoll(minRoll, maxRoll) table.insert(Stub.rolls, { minRoll, maxRoll }) end
function SendChatMessage(msg, method) table.insert(Stub.chatLog, { text = msg, method = method }) end

DEFAULT_CHAT_FRAME = { AddMessage = function(_, msg) table.insert(Stub.printLog, msg) end }
GameTooltip = { SetOwner = function() end, SetText = function() end, AddLine = function() end, Show = function() end, Hide = function() end, IsShown = function() return false end, GetOwner = function() end }

C_ChatInfo = { RegisterAddonMessagePrefix = function() end }
C_Timer = { After = function(delay, fn) table.insert(Stub.timers, fn) end }

-- Runs queued timers until none are left (each may queue more). Returns the number run.
function Stub.runTimers(maxSteps)
    maxSteps = maxSteps or 10000
    local ran = 0
    while #Stub.timers > 0 and ran < maxSteps do
        local fn = table.remove(Stub.timers, 1)
        fn()
        ran = ran + 1
    end
    return ran
end

ChatThrottleLib = {
    -- The real library delivers addon messages on a later frame, never inline inside the send call.
    -- Queuing the echo (instead of calling OnAddonMessage here, synchronously, inside SendMsg's pcall)
    -- means an error thrown while handling our own echo surfaces like it would for a real client,
    -- instead of being swallowed by that pcall. Drained by Stub.runTimers(), same as C_Timer.After.
    SendAddonMessage = function(_, priority, prefix, msg, channel)
        table.insert(Stub.network, { prefix = prefix, msg = msg, channel = channel })
        if Stub.echoAddonMessages then
            local sender = Stub.playerName .. "-Testrealm"
            table.insert(Stub.timers, function()
                if CrossGambling and CrossGambling.OnAddonMessage then
                    CrossGambling:OnAddonMessage("CHAT_MSG_ADDON", prefix, msg, channel, sender)
                end
            end)
        end
    end,
}

function CreateFrame()
    local frame = { scripts = {} }
    function frame:SetScript(name, fn) self.scripts[name] = fn end
    function frame:RegisterEvent() end
    function frame:UnregisterEvent() end
    function frame:Show() end
    function frame:Hide() end
    function frame:SetSize() end
    function frame:SetPoint() end
    return frame
end

-- Ace3 -----------------------------------------------------------------------------------------------

local function deepcopy(t)
    if type(t) ~= "table" then return t end
    local copy = {}
    for k, v in pairs(t) do copy[k] = deepcopy(v) end
    return copy
end

local libs = {}
LibStub = setmetatable({}, { __call = function(_, name) return libs[name] end })
function LibStub:GetLibrary(name) return libs[name] end

libs["AceAddon-3.0"] = {
    NewAddon = function(_, name)
        local addon = { name = name, registeredEvents = {} }
        function addon:Print(msg) table.insert(Stub.printLog, tostring(msg)) end
        function addon:RegisterEvent(event, handler) self.registeredEvents[event] = handler or event end
        function addon:UnregisterEvent(event) self.registeredEvents[event] = nil end
        function addon:IsEventRegistered(event) return self.registeredEvents[event] ~= nil end
        function addon:RegisterChatCommand() end
        -- Fire an event the way AceEvent would, if the addon is listening for it.
        function addon:FireEvent(event, ...)
            local handler = self.registeredEvents[event]
            if not handler then return false end
            if type(handler) == "string" then
                self[handler](self, event, ...)
            else
                handler(event, ...)
            end
            return true
        end
        libs["AceAddon-3.0"]._addon = addon
        return addon
    end,
    GetAddon = function(self) return self._addon end,
}

libs["AceDB-3.0"] = {
    New = function(_, _, defaults)
        return { global = deepcopy(defaults.global) }
    end,
}

libs["LibDBIcon-1.0"] = { Register = function() end, Show = function() end, Hide = function() end }
libs["LibDataBroker-1.1"] = { NewDataObject = function() return {} end }

CGTheme = { ClearRegistry = function() end }

return Stub
