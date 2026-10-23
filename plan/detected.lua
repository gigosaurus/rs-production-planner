-- Gives Detected stock from the slots that the adapter reads from the game (issue 42).
-- The adapter removes the empty slots. Tests run this module outside the game client.
local Detected = {}

local function addSlots(stock, slots)
    for _, slot in ipairs(slots) do
        stock[slot.configName] = (stock[slot.configName] or 0) + slot.count
    end
end

-- backpack and bank are lists of slots. Each slot has a configName and a count.
-- Gives the total count of each config name.
function Detected.count(backpack, bank)
    local stock = {}
    addSlots(stock, backpack)
    addSlots(stock, bank)
    return stock
end

return Detected
