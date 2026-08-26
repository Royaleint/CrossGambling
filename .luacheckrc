std = "lua51"
max_line_length = false
allow_defined_top = true
unused_args = false
self = false

exclude_files = {
    "Libs/**",
    "tests/**",
}

ignore = {
    "211/_.*",    -- underscore-prefixed locals are deliberately unused
    "311",        -- value assigned to a local is unused (UI setup code reuses names)
    "542",        -- empty if branch
}

globals = {
    -- Addon objects and shared tables
    "CrossGambling", "CrossGamblingDB", "CGCall", "CGChat", "CGTheme", "CGOptions",
    -- Blizzard registries we write into
    "StaticPopupDialogs",
    -- Named frames created by the GUI files
    "CrossGamblingUI", "PlayerListFrame", "PlayerListScrollFrame", "PlayerButtonsFrame",
    "playerButtonsFrame", "playerButtons", "CGPlayers", "playerIndexByName",
}

read_globals = {
    -- Libraries
    "LibStub", "ChatThrottleLib",
    -- WoW string/table helpers
    "strsplit", "strtrim", "strlower", "strupper", "strmatch", "strfind", "format", "tinsert", "tremove", "wipe", "floor", "date", "time",
    -- WoW API
    "CreateFrame", "UIParent", "GameTooltip", "DEFAULT_CHAT_FRAME", "RAID_CLASS_COLORS", "RANDOM_ROLL_RESULT",
    "UnitName", "UnitClass", "UnitRealmRelationship", "GetRealmName", "RandomRoll", "SendChatMessage",
    "IsInGroup", "IsInRaid", "IsInGuild", "IsInInstance", "InCombatLockdown", "IsShiftKeyDown",
    "LE_PARTY_CATEGORY_HOME", "LE_PARTY_CATEGORY_INSTANCE",
    "C_ChatInfo", "C_Timer", "C_AddOns", "GetAddOnMetadata",
    "StaticPopup_Show", "Mixin", "BackdropTemplateMixin", "ChatFontNormal",
    "SlashCmdList", "hooksecurefunc", "PlaySound", "SOUNDKIT", "GetCursorPosition", "GetScreenWidth", "GetScreenHeight",
    "ColorPickerFrame", "OpacitySliderFrame", "ColorPickerOkayButton", "ColorPickerCancelButton", "InterfaceOptionsFrame_OpenToCategory", "Settings",
    "IsControlKeyDown", "IsAltKeyDown", "GetTime", "UISpecialFrames", "GameFontNormal", "GameFontHighlight",
}
