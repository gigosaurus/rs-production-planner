-- The part of the adapter that does not use the game API (issue 25).
-- main.lua reads the game and gives plain tables to it. Tests run it outside the game client.
local Detected = require("plan/detected")
local Diff = require("plan/diff")
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
    -- The first Plan after a login has no diff. A diff from the Plan of another character is not correct.
    adapter.basis, adapter.plan = nil, nil
end

-- Call this when the game state is not GAME. The adapter keeps the state of the character.
-- Until the next login, a tick gives nothing.
function Adapter.leave(adapter)
    adapter.name, adapter.firstBank = nil, nil
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
-- The first Bank snapshot of a character makes the next tick record a first Bank tick (ADR 0004).
function Adapter.bank(adapter, slots)
    if adapter.name == nil then
        return
    end
    if adapter.banks[adapter.name] == nil then
        adapter.firstBank = true
    end
    adapter.banks[adapter.name] = snapshotOf(slots)
end

-- Gives true when the plugin has a Bank snapshot of the character.
function Adapter.bankSeen(adapter)
    return adapter.banks[adapter.name] ~= nil
end

-- Gives true when the two values are the same, also for tables.
local function same(a, b)
    if type(a) ~= "table" or type(b) ~= "table" then
        return a == b
    end
    for key, value in pairs(a) do
        if not same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- The Recipes and stackable are large, so the Basis compares them as tables, not by their contents.
local BY_TABLE = { recipes = true, stackable = true }

local function sameBasis(a, b)
    if a == nil then
        return false
    end
    for key in pairs(BY_TABLE) do
        if a[key] ~= b[key] then
            return false
        end
    end
    for key, value in pairs(a) do
        if not BY_TABLE[key] and not same(value, b[key]) then
            return false
        end
    end
    for key in pairs(b) do
        if a[key] == nil then
            return false
        end
    end
    return true
end

-- facts has the Inventory slots of this tick, and the recipes, levels and stackable of Plan.calculate.
-- Give the same recipes and stackable tables until they change.
-- Gives the Plan and the diff from the previous Plan, or nil when the Basis did not change (ADR 0003).
-- The first Plan has no diff.
function Adapter.tick(adapter, facts)
    if adapter.name == nil then
        return nil
    end
    local detected = Detected.count(itemSlots(facts.inventory), bankSlots(adapter))
    -- tick.detected holds all items. Made.observe counts only the items of the Make Targets.
    Session.observe(adapter.session, { detected = detected, firstBank = adapter.firstBank })
    adapter.firstBank = nil
    local basis = Session.basis(adapter.session, {
        recipes = facts.recipes,
        detected = detected,
        levels = facts.levels,
        stackable = facts.stackable,
    })
    if sameBasis(adapter.basis, basis) then
        return nil
    end
    local plan = Plan.calculate(basis)
    local diff = adapter.plan and Diff.compare(adapter.plan, plan)
    adapter.basis, adapter.plan = basis, plan
    return { plan = plan, diff = diff }
end

return Adapter
