-- The part of the adapter that does not use the game API (issue 25).
-- main.lua reads the game and gives plain tables to it. Tests run it outside the game client.
local Detected = require("plan/detected")
local Plan = require("plan/calculate")
local Saved = require("plan/saved")
local Session = require("plan/session")

local Adapter = {}

-- store has Get and Set, for example PersistentDB.
function Adapter.new(store)
    local saved = Saved.new(store)
    local globals = Saved.loadGlobal(saved)
    local parts = {}
    for _, name in ipairs(globals.characters) do
        parts[name] = Saved.loadCharacter(saved, name)
    end
    local banks = {}
    for name, part in pairs(parts) do
        banks[name] = part.bank
    end
    return { saved = saved, session = Session.new(globals, parts), banks = banks }
end

-- Call this on the first ServerLogic tick in which the player is available.
function Adapter.login(adapter, name)
    local parts = Saved.loadCharacter(adapter.saved, name)
    Session.loadCharacter(adapter.session, name, parts, {})
    adapter.name = name
    if adapter.banks[name] == nil then
        adapter.banks[name] = parts.bank
    end
end

-- Gives the slots that hold an item. An empty slot has the id -1 (ADR 0007).
-- A bank placeholder has the real item and the count 0 (docs/client-behaviour.md).
local function itemSlots(slots)
    local kept = {}
    for _, slot in ipairs(slots) do
        if slot.id ~= -1 and slot.count ~= 0 then
            kept[#kept + 1] = slot
        end
    end
    return kept
end

-- Gives the total count of each config name. The Bank snapshot keeps the config names, so a Noted item stays CERT_<name>.
local function snapshotOf(slots)
    local snapshot = {}
    for _, slot in ipairs(itemSlots(slots)) do
        snapshot[slot.configName] = (snapshot[slot.configName] or 0) + slot.count
    end
    return snapshot
end

-- Gives the Bank snapshot as slots for Detected.count, or nil when the bank of the character was never seen.
local function bankSlots(adapter)
    local snapshot = adapter.banks[adapter.name]
    if snapshot == nil then
        return nil
    end
    local slots = {}
    for configName, count in pairs(snapshot) do
        slots[#slots + 1] = { configName = configName, count = count }
    end
    return slots
end

-- slots are all the slots of the bank, from InventoryAdded or InventoryUpdated.
-- The Bank snapshot never becomes stale (issue 1).
function Adapter.bank(adapter, slots)
    adapter.banks[adapter.name] = snapshotOf(slots)
end

-- Gives true when the plugin has a Bank snapshot of the character.
function Adapter.bankSeen(adapter)
    return adapter.banks[adapter.name] ~= nil
end

-- facts has the Inventory slots of this tick, and the recipes, levels and stackable of Plan.calculate.
-- Gives the Plan.
function Adapter.tick(adapter, facts)
    local detected = Detected.count(itemSlots(facts.inventory), bankSlots(adapter))
    local basis = Session.basis(adapter.session, {
        recipes = facts.recipes,
        detected = detected,
        levels = facts.levels,
        stackable = facts.stackable,
    })
    return { plan = Plan.calculate(basis) }
end

return Adapter
