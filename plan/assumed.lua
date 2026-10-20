-- Tracks Assumed stock, as ADR 0004 describes.
-- It does not use the game API. Tests run it outside the game client.
-- The state is a plain table, so the plugin can save it with PersistentDB.
local Assumed = {}

function Assumed.new()
    return { entries = {} }
end

-- detected is the Detected stock when the player adds the Assumed stock.
-- An item that is already assumed keeps its line and its baseline.
-- The view must check the amount that the player types. A bad amount here is a fault in the code.
function Assumed.add(state, item, amount, detected)
    if amount <= 0 then
        error("The Assumed amount of " .. item .. " must be more than 0.", 2)
    end
    for _, entry in ipairs(state.entries) do
        if entry.item == item then
            entry.entered = entry.entered + amount
            entry.remaining = entry.remaining + amount
            return
        end
    end
    state.entries[#state.entries + 1] = {
        item = item,
        entered = amount,
        remaining = amount,
        baseline = detected[item] or 0,
    }
end

function Assumed.remove(state, item)
    for index, entry in ipairs(state.entries) do
        if entry.item == item then
            table.remove(state.entries, index)
            return
        end
    end
end

-- detected is the Detected stock now: the backpack and the bank together.
-- A rise since the last call uses up Assumed stock of that item.
function Assumed.observe(state, detected)
    local arrived, fulfilled, kept = {}, {}, {}
    for _, entry in ipairs(state.entries) do
        local now = detected[entry.item] or 0
        local used = math.min(now - entry.baseline, entry.remaining)
        if used > 0 then
            entry.remaining = entry.remaining - used
            arrived[#arrived + 1] = { item = entry.item, count = used }
        end
        entry.baseline = now
        if entry.remaining == 0 then
            fulfilled[#fulfilled + 1] = entry.item
        else
            kept[#kept + 1] = entry
        end
    end
    state.entries = kept
    return { arrived = arrived, fulfilled = fulfilled }
end

-- Call this when the plugin sees the bank for the first time.
-- Detected stock then rises by all the contents of the bank. This rise is not an arrival.
function Assumed.rebase(state, detected)
    for _, entry in ipairs(state.entries) do
        entry.baseline = detected[entry.item] or 0
    end
end

-- Gives the assumed field of the Basis of Plan.calculate.
function Assumed.remaining(state)
    local remaining = {}
    for _, entry in ipairs(state.entries) do
        remaining[entry.item] = entry.remaining
    end
    return remaining
end

function Assumed.lines(state)
    local lines = {}
    for _, entry in ipairs(state.entries) do
        lines[#lines + 1] = {
            item = entry.item,
            remaining = entry.remaining,
            arrived = entry.entered - entry.remaining,
            entered = entry.entered,
        }
    end
    return lines
end

return Assumed
