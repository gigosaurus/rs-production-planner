-- Changes counts to decimal strings and back, for the saved data.
-- PersistentDB keeps numbers as 32-bit floats, so each count is saved as a decimal string (ADR 0011).
-- It does not use the game API. Tests run it outside the game client.
local CountText = {}

function CountText.text(count)
    return string.format("%d", count)
end

-- Gives nil when the text is not a decimal integer.
function CountText.count(text)
    if type(text) ~= "string" or not text:match("^%-?%d+$") then
        return nil
    end
    return math.tointeger(tonumber(text))
end

-- Gives one text for each key of counts.
function CountText.texts(counts)
    local texts = {}
    for key, count in pairs(counts) do
        texts[key] = CountText.text(count)
    end
    return texts
end

-- Gives one count for each key of texts. Gives nil when a key is not a string or a count is bad.
function CountText.counts(texts)
    if type(texts) ~= "table" then
        return nil
    end
    local counts = {}
    for key, text in pairs(texts) do
        local count = CountText.count(text)
        if type(key) ~= "string" or not count then
            return nil
        end
        counts[key] = count
    end
    return counts
end

return CountText
