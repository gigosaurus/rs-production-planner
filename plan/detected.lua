-- Gives Detected stock from the slots that the adapter reads from the game (issue 42).
-- The adapter removes the empty slots. Tests run this module outside the game client.
local Validate = require("plan/validate")

local Detected = {}

-- The config name of a Noted item is CERT_<name> (ADR 0007). Detected stock counts it as <name>.
local function itemOf(configName)
    return (configName:gsub("^CERT_", ""))
end

-- Gives "an Inventory" or "a bank".
local function withArticle(listName)
    return (listName:find("^[AEIOU]") and "an " or "a ") .. listName
end

-- A bad slot is a bug in the adapter. Level 5 is the caller of Detected.count.
local function badSlot(listName, field, rule, value)
    error(
        "The adapter gave "
            .. withArticle(listName)
            .. " slot with a bad "
            .. field
            .. ". The "
            .. field
            .. " must be "
            .. rule
            .. ". The value is "
            .. tostring(value)
            .. ".",
        5
    )
end

-- Level 4 is the caller of Detected.count.
local function checkSlot(slot, listName)
    if type(slot) ~= "table" then
        error(
            "The adapter gave a bad "
                .. listName
                .. " slot. The slot must be a table. The value is "
                .. tostring(slot)
                .. ".",
            4
        )
    end
    if type(slot.configName) ~= "string" then
        badSlot(listName, "config name", "a string", slot.configName)
    end
    if not Validate.isPositiveInteger(slot.count) then
        badSlot(listName, "count", "a whole number more than 0", slot.count)
    end
end

-- A list has the keys 1 to n and no other keys. Level 4 is the caller of Detected.count.
local function checkList(slots, listName)
    local n = 0
    for _ in pairs(slots) do
        n = n + 1
    end
    for i = 1, n do
        if slots[i] == nil then
            error(
                "The adapter gave "
                    .. withArticle(listName)
                    .. " with a gap or a key that is not a slot number. The "
                    .. listName
                    .. " must be a list.",
                4
            )
        end
    end
end

local function addSlots(stock, slots, listName)
    checkList(slots, listName)
    for _, slot in ipairs(slots) do
        checkSlot(slot, listName)
        local item = itemOf(slot.configName)
        stock[item] = (stock[item] or 0) + slot.count
    end
end

-- inventory and bank are lists of slots. Each slot has a configName and a count.
-- bank is nil when the player did not open the bank yet. Then only the Inventory counts.
-- Gives the total count of each item. A Noted item counts as the item.
function Detected.count(inventory, bank)
    if type(inventory) ~= "table" then
        error(
            "The adapter gave a bad Inventory. The Inventory must be a table. The value is "
                .. tostring(inventory)
                .. ".",
            2
        )
    end
    if bank ~= nil and type(bank) ~= "table" then
        error("The adapter gave a bad bank. The bank must be a table or nil. The value is " .. tostring(bank) .. ".", 2)
    end
    local stock = {}
    addSlots(stock, inventory, "Inventory")
    if bank ~= nil then
        addSlots(stock, bank, "bank")
    end
    return stock
end

return Detected
