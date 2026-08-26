-- Small helpers shared by every other file. Nothing here touches game state.

function CrossGambling:TrimInput(text)
    if not text then
        return ""
    end

    return (tostring(text):gsub("^%s+", ""):gsub("%s+$", ""))
end

-- "Name-Realm" -> "Name"
function CrossGambling:ShortPlayerName(name)
    if not name then
        return nil
    end

    return (strsplit("-", tostring(name), 2))
end

-- Lower-cased, trimmed comparison key. The realm is stripped unless preserveRealm is true.
function CrossGambling:NormalizePlayerName(name, preserveRealm)
    if not name then
        return nil
    end

    name = strtrim(tostring(name))
    if name == "" then
        return nil
    end

    if not preserveRealm then
        name = strsplit("-", name, 2)
        if not name or name == "" then
            return nil
        end
    end

    return strlower(name)
end

-- Whole number clamped to [low, high], or nil when the input is not a number.
function CrossGambling:ClampInteger(value, low, high)
    local numericValue = tonumber(value)
    if not numericValue then
        return nil
    end

    numericValue = math.floor(numericValue)
    if numericValue < low then
        numericValue = low
    elseif numericValue > high then
        numericValue = high
    end

    return numericValue
end

-- 1234567 -> "1,234,567"
function CrossGambling:addCommas(value)
    local text = tostring(value)
    local sign, digits = text:match("^(-?)(%d+)$")
    if not digits or #digits <= 3 then
        return text
    end

    local formatted = digits:reverse():gsub("(%d%d%d)", "%1,"):reverse()
    formatted = formatted:gsub("^,", "")
    return sign .. formatted
end

-- {player, player, player} -> "A, B and C" (entries may be player tables or plain strings)
function CrossGambling:String(players)
    local names = {}
    for i = 1, #players do
        local entry = players[i]
        names[i] = type(entry) == "table" and entry.name or tostring(entry)
    end

    if #names == 0 then
        return ""
    elseif #names == 1 then
        return names[1]
    end

    return table.concat(names, ", ", 1, #names - 1) .. " and " .. names[#names]
end

function CrossGambling:CountKeys(tbl)
    local count = 0
    for _ in pairs(tbl or {}) do
        count = count + 1
    end
    return count
end
