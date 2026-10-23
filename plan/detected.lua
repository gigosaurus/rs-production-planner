-- Gives Detected stock from the slots that the adapter reads from the game (issue 42).
-- The adapter removes the empty slots. Tests run this module outside the game client.
local Detected = {}

-- The config name of a Noted item is CERT_<name> (ADR 0007). Detected stock counts it as <name>.
local function itemOf(configName)
    return (configName:gsub("^CERT_", ""))
end

local function addSlots(stock, slots)
    for _, slot in ipairs(slots) do
        local item = itemOf(slot.configName)
        stock[item] = (stock[item] or 0) + slot.count
    end
end

-- backpack and bank are lists of slots. Each slot has a configName and a count.
-- bank is nil when the player did not open the bank yet. Then only the backpack counts.
-- Gives the total count of each item. A Noted item counts as the item.
function Detected.count(backpack, bank)
    local stock = {}
    addSlots(stock, backpack)
    if bank ~= nil then
        addSlots(stock, bank)
    end
    return stock
end

return Detected
