-- Gives Detected stock from the slots that the adapter reads from the game (issue 42).
-- The adapter removes the empty slots. Tests run this module outside the game client.
local Validate = require("plan/validate")

local Detected = {}

-- The config name of a Noted item is CERT_<name> (ADR 0007). Detected stock counts it as <name>.
local function itemOf(configName)
    return (configName:gsub("^CERT_", ""))
end

-- A bad slot is a bug in the adapter. Level 4 is the caller of Detected.count.
local function checkSlot(slot, listName)
    if type(slot.configName) ~= "string" then
        error(
            "The adapter gave a "
                .. listName
                .. " slot with a bad config name. The config name must be a string. The value is "
                .. tostring(slot.configName)
                .. ".",
            4
        )
    end
    if not Validate.isPositiveInteger(slot.count) then
        error(
            "The adapter gave a "
                .. listName
                .. " slot with a bad count. The count must be a whole number more than 0. The value is "
                .. tostring(slot.count)
                .. ".",
            4
        )
    end
end

local function addSlots(stock, slots, listName)
    for _, slot in ipairs(slots) do
        checkSlot(slot, listName)
        local item = itemOf(slot.configName)
        stock[item] = (stock[item] or 0) + slot.count
    end
end

-- backpack and bank are lists of slots. Each slot has a configName and a count.
-- bank is nil when the player did not open the bank yet. Then only the backpack counts.
-- Gives the total count of each item. A Noted item counts as the item.
function Detected.count(backpack, bank)
    if type(backpack) ~= "table" then
        error(
            "The adapter gave a bad backpack. The backpack must be a table. The value is " .. tostring(backpack) .. ".",
            2
        )
    end
    if bank ~= nil and type(bank) ~= "table" then
        error("The adapter gave a bad bank. The bank must be a table or nil. The value is " .. tostring(bank) .. ".", 2)
    end
    local stock = {}
    addSlots(stock, backpack, "backpack")
    if bank ~= nil then
        addSlots(stock, bank, "bank")
    end
    return stock
end

return Detected
