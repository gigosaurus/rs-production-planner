-- Throwaway probe: how does the bank inventory reach the client?
-- Answers: is the bank readable before it's opened, does it arrive whole or in chunks,
-- and is it removed when the bank interface closes?

local BANK_ID = config.Inv.BANK.id
local tick = 0

local function say(...)
    local parts = {}
    for i, v in ipairs({ ... }) do parts[i] = tostring(v) end
    log("[t" .. tick .. "] " .. table.concat(parts, " "))
end

-- Summarise an inventory: slot usage plus the total item count across all slots
local function describe(inv)
    if inv == nil then return "nil" end
    -- Docs disagree on the flag name (property table says `valid`, warning says `isValid`), so report both raw
    local flags = "valid=" .. tostring(inv.valid) .. " isValid=" .. tostring(inv.isValid)
    -- Read contents regardless of either flag, guarded in case access throws
    local ok, result = pcall(function()
        local total = 0
        for i = 1, inv.slotCount do
            local slot = inv:GetSlot(i)
            if slot ~= nil and slot.obj ~= nil then total = total + slot.count end
        end
        return "slots " .. inv.usedSlotCount .. "/" .. inv.slotCount .. ", total items " .. total
    end)
    return flags .. " | " .. (ok and result or ("read failed: " .. tostring(result)))
end

local function sampleSlots(inv, n)
    if inv == nil then return end
    local shown = 0
    for i = 1, inv.slotCount do
        local slot = inv:GetSlot(i)
        if slot ~= nil and slot.obj ~= nil then
            say("  slot", i, slot.obj.name, "x" .. slot.count)
            shown = shown + 1
            if shown >= n then return end
        end
    end
end

-- Deferred checks: { atTick = n, label = s } run from the Logic event
local pending = {}

local function checkLookups(label, proxy)
    say(label, "Find(proxy):", describe(Inventory.Find(proxy)))
    say(label, "Find(proxy.id):", describe(Inventory.Find(proxy.id)))
    say(label, "Find(config.Inv.BANK):", describe(Inventory.Find(config.Inv.BANK)))
end

Event.Logic.Subscribe("bankProbeTick", function(e)
    tick = e.logicTick
    for i = #pending, 1, -1 do
        local p = pending[i]
        if tick >= p.atTick then
            table.remove(pending, i)
            checkLookups(p.label, config.Inv.BANK)
        end
    end
end)

-- 1. Is the bank available before it has ever been opened this session?
local bankAtLoad = Inventory.Find(config.Inv.BANK)
say("At load, bank:", describe(bankAtLoad))
say("At load, backpack:", describe(Inventory.Find(config.Inv.INV)))

-- 2. Does it arrive whole (one Added with everything) or in chunks (Added then many Updated)?
Event.InventoryAdded.Subscribe("bankProbe", function(e)
    if e.inv.id == BANK_ID then
        say("BANK ADDED. proxy size =", e.inv.size)
        checkLookups("  now", e.inv)
        sampleSlots(Inventory.Find(e.inv.id), 5)
        -- 50 logic ticks = 1 second
        table.insert(pending, { atTick = tick + 1, label = "  +1 tick" })
        table.insert(pending, { atTick = tick + 50, label = "  +1s" })
        table.insert(pending, { atTick = tick + 250, label = "  +5s" })
    else
        say("other inv added:", e.inv.configName, "(id " .. e.inv.id .. ")")
    end
end)

Event.InventoryUpdated.Subscribe("bankProbe", function(e)
    if e.inv.id == BANK_ID then
        say("BANK UPDATED:", #e.slotsUpdated, "slots changed ->", describe(Inventory.Find(e.inv.id)))
    end
end)

-- 3. Is it removed when the bank closes, and does a held Inv go invalid?
Event.InventoryRemoved.Subscribe("bankProbe", function(e)
    if e.inv.id == BANK_ID then
        say("BANK REMOVED. Held-at-load Inv now:", describe(bankAtLoad))
    else
        say("other inv removed:", e.inv.configName)
    end
end)

say("Bank probe running. Bank inv id =", BANK_ID)
