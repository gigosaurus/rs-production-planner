-- Tracks Assumed stock, as ADR 0004 describes.
-- It does not use the game API. Tests run it outside the game client.
-- states maps each displayName to the state of that character (ADR 0008).
-- Each state is a plain table, so the plugin can save it with PersistentDB.
local Validate = require("plan/validate")

local Assumed = {}

-- Gives the state of one character.
function Assumed.new()
    return { entries = {} }
end

local function character(states, name)
    local state = states[name]
    if not state then
        state = Assumed.new()
        states[name] = state
    end
    return state
end

-- A character that has no state has no Assumed stock.
local function entries(states, name)
    return states[name] and states[name].entries or {}
end

-- detected is the Detected stock when the player adds the Assumed stock.
-- An item that is already assumed keeps its line and its baseline.
-- The view must check the amount that the player types. A bad amount here is a fault in the code.
function Assumed.add(states, name, item, amount, detected)
    if not Validate.isPositiveInteger(amount) then
        error("The Assumed amount of " .. tostring(item) .. " must be a whole number more than 0.", 2)
    end
    local state = character(states, name)
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

function Assumed.remove(states, name, item)
    local list = entries(states, name)
    for index, entry in ipairs(list) do
        if entry.item == item then
            table.remove(list, index)
            return
        end
    end
end

-- tick has the facts of one server tick for one character, as Made.observe takes them.
-- tick.detected is the Detected stock now: the Inventory and the bank together.
-- A rise since the last call uses up Assumed stock of that item. Pickups, shops and the GE count too.
-- On the first Bank snapshot, Detected stock rises by all the contents of the bank. This rise is not an arrival.
function Assumed.observe(states, name, tick)
    local state = character(states, name)
    local arrived, fulfilled, kept = {}, {}, {}
    for _, entry in ipairs(state.entries) do
        local now = tick.detected[entry.item] or 0
        local used = tick.firstBank and 0 or math.min(now - entry.baseline, entry.remaining)
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

-- Gives the assumed field of the Basis of Plan.calculate.
function Assumed.remaining(states, name)
    local remaining = {}
    for _, entry in ipairs(entries(states, name)) do
        remaining[entry.item] = entry.remaining
    end
    return remaining
end

function Assumed.lines(states, name)
    local lines = {}
    for _, entry in ipairs(entries(states, name)) do
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
