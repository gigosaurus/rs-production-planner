-- Throwaway probe: what does stackType look like in practice, and do noted items share a name with the real item?
-- Lists every backpack slot on load and whenever the backpack changes,
-- and summarises stackType across the bank when it's opened.
-- Note: Inv validity flag is `isValid` in-game, not `valid` as the docs list.

local BACKPACK_ID = config.Inv.INV.id
local BANK_ID = config.Inv.BANK.id

-- Docs give ObjStackType as SOMETIMES (0), ALWAYS (1), NEVER (2); print raw value too in case it isn't a plain number
local STACK_NAMES = { [0] = "SOMETIMES", [1] = "ALWAYS", [2] = "NEVER" }

local function stackName(obj)
    local raw = obj.stackType
    return (STACK_NAMES[raw] or "?") .. "(" .. tostring(raw) .. ")"
end

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log(table.concat(parts, " "))
end

local function listBackpack()
    local inv = Inventory.Find(config.Inv.INV)
    if inv == nil or not inv.isValid then
        say("Backpack not available")
        return
    end
    say("--- Backpack (" .. inv.usedSlotCount .. "/" .. inv.slotCount .. " slots) ---")
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        if slot ~= nil and slot.obj ~= nil then
            local o = slot.obj
            say("slot " .. i, "id=" .. o.id, o.configName, '"' .. o.name .. '"', "x" .. slot.count, stackName(o),
                "tradeable=" .. tostring(o.isTradeable))
        end
    end
end

-- Bank summary: how many slots of each stackType, plus a few examples of each
local function summariseBank(inv)
    local counts, examples = {}, {}
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        if slot ~= nil and slot.obj ~= nil then
            local key = stackName(slot.obj)
            counts[key] = (counts[key] or 0) + 1
            examples[key] = examples[key] or {}
            if #examples[key] < 5 then
                table.insert(examples[key], '"' .. slot.obj.name .. '" x' .. slot.count)
            end
        end
    end
    say("--- Bank stackType summary ---")
    for key, n in pairs(counts) do
        say(key, n .. " slots, e.g.", table.concat(examples[key], ", "))
    end
end

Event.InventoryAdded.Subscribe("stackProbe", function(e)
    if e.inv.id == BACKPACK_ID then
        listBackpack()
    elseif e.inv.id == BANK_ID then
        summariseBank(Inventory.Find(config.Inv.BANK))
    end
end)

-- Only list the backpack once per burst of updates, not once per changed slot
local backpackDirty = false
Event.InventoryUpdated.Subscribe("stackProbe", function(e)
    if e.inv.id == BACKPACK_ID then backpackDirty = true end
end)
Event.Logic.Subscribe("stackProbe", function()
    if backpackDirty then
        backpackDirty = false
        listBackpack()
    end
end)

say("Stack probe running")
listBackpack()
