-- Throwaway probe for #25: how does a bank placeholder slot come from the API?
-- Question: is a placeholder an empty slot (id -1), or a real item with count 0?
-- Steps:
--   1. pon. Open the bank. The probe logs each slot that is not a normal item.
--   2. Withdraw all of one item, with placeholders on. The probe logs the changed slots.
--   3. Close the bank. Open it again. The probe logs the placeholder slots again.

local BANK_ID = config.Inv.BANK.id

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do
        parts[i] = tostring(v)
    end
    log("[placeholder] " .. table.concat(parts, " "))
end

-- Inventory.Find is documented as a list, but gives one Inv in practice.
local function findBank()
    local found = Inventory.Find(BANK_ID)
    if found ~= nil and found.isValid == nil and found[1] ~= nil then
        return found[1]
    end
    return found
end

local function describeSlot(inv, index)
    local slot = inv:GetSlot(index)
    if slot == nil then
        return "slot nil"
    end
    local obj = slot.obj
    if obj == nil then
        return "obj nil, count=" .. tostring(slot.count)
    end
    local total = "?"
    local ok, value = pcall(function()
        return inv:GetTotal(obj.id)
    end)
    if ok then
        total = tostring(value)
    end
    return "id="
        .. tostring(obj.id)
        .. " configName="
        .. tostring(obj.configName)
        .. " name="
        .. tostring(obj.name)
        .. " count="
        .. tostring(slot.count)
        .. " GetTotal="
        .. total
end

-- Log each slot that has a real id and a count below 1. Count the empty slots.
local function scan(label)
    local inv = findBank()
    if inv == nil or not inv.isValid then
        say(label, "bank not valid")
        return
    end
    local empty, normal, odd = 0, 0, 0
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        local id = slot and slot.obj and slot.obj.id
        if id == nil or id == -1 then
            empty = empty + 1
        elseif slot.count < 1 then
            odd = odd + 1
            say(label, "slot", i, describeSlot(inv, i))
        else
            normal = normal + 1
        end
    end
    say(
        label,
        "slots",
        inv.slotCount,
        "used",
        inv.usedSlotCount,
        "free",
        inv.freeSlotCount,
        "| normal",
        normal,
        "empty",
        empty,
        "count<1",
        odd
    )
end

Event.InventoryAdded.Subscribe("bankPlaceholderProbe", function(e)
    if e.inv.id == BANK_ID then
        scan("ADDED")
    end
end)

Event.InventoryUpdated.Subscribe("bankPlaceholderProbe", function(e)
    if e.inv.id ~= BANK_ID then
        return
    end
    local inv = findBank()
    if inv == nil or not inv.isValid then
        say("UPDATED bank not valid")
        return
    end
    for _, index in ipairs(e.slotsUpdated) do
        -- slotsUpdated is possibly 0-based. Log the index as it comes.
        say("UPDATED slot", index, describeSlot(inv, index))
    end
end)

say("Bank placeholder probe running. Bank inv id =", BANK_ID)
scan("LOAD")
