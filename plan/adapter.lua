-- The part of the adapter that does not use the game API (issue 25).
-- main.lua reads the game and gives plain tables to it. Tests run it outside the game client.
local Assumed = require("plan/assumed")
local Detected = require("plan/detected")
local Diff = require("plan/diff")
local Plan = require("plan/calculate")
local Saved = require("plan/saved")
local Session = require("plan/session")
local Validate = require("plan/validate")

local Adapter = {}

-- Adds the problems of a Saved load to the list.
local function addProblems(list, problems)
    for _, problem in ipairs(problems) do
        list[#list + 1] = problem
    end
end

-- Loads the saved parts of one character, and keeps its Bank snapshot.
local function loadCharacter(adapter, name, problems)
    local parts, found = Saved.loadCharacter(adapter.saved, name)
    addProblems(problems, found)
    adapter.banks[name] = parts.bank
    adapter.loaded[name] = true
    return parts
end

-- store has Get and Set, for example PersistentDB.
-- Gives the Adapter, and the problems of Saved.loadGlobal and Saved.loadCharacter.
-- It loads each saved character, because Made needs the state of each character (ADR 0012).
function Adapter.new(store)
    local saved = Saved.new(store)
    local globals, problems = Saved.loadGlobal(saved)
    local adapter = { saved = saved, banks = {}, bankChanged = {}, loaded = {} }
    local parts = {}
    for _, name in ipairs(globals.characters) do
        parts[name] = loadCharacter(adapter, name, problems)
    end
    adapter.session = Session.new(globals, parts)
    return adapter, problems
end

-- Call this on the first ServerLogic tick in which the player is available.
-- Gives the problems of Saved.loadCharacter. A character that Adapter.new loaded gives none.
function Adapter.login(adapter, name)
    local problems = {}
    local parts = not adapter.loaded[name] and loadCharacter(adapter, name, problems) or nil
    -- Make (issue 10) must give the GE offers here. An empty list removes the saved GE slots and GE amounts.
    Session.loadCharacter(adapter.session, name, parts, {})
    adapter.name = name
    -- The first Plan after a login has no diff. A diff from the Plan of another character is not correct.
    adapter.basis, adapter.plan = nil, nil
    return problems
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
    adapter.bankChanged[adapter.name] = true
end

-- Gives true when the plugin has a Bank snapshot of the character.
function Adapter.bankSeen(adapter)
    return adapter.banks[adapter.name] ~= nil
end

-- The Recipes and stackable are large, so the Basis compares them as tables, not by their contents.
local BY_TABLE = { recipes = true, stackable = true }

-- Gives a copy of the Basis with no Recipes and no stackable.
local function withoutLarge(basis)
    local copy = {}
    for key, value in pairs(basis) do
        if not BY_TABLE[key] then
            copy[key] = value
        end
    end
    return copy
end

local function sameBasis(a, b)
    if a == nil then
        return false
    end
    for key in pairs(BY_TABLE) do
        if a[key] ~= b[key] then
            return false
        end
    end
    return Validate.same(withoutLarge(a), withoutLarge(b))
end

-- facts has the Inventory slots of this tick, and the recipes, levels and stackable of Plan.calculate.
-- Give the same recipes and stackable tables until they change.
-- Gives the Plan and the diff from the previous Plan, or nil when the Basis did not change (ADR 0003).
-- The first Plan has no diff. For the view, it also gives the Detected stock and the Assumed lines (issue 26).
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
    return {
        plan = plan,
        diff = diff,
        detected = detected,
        assumed = Assumed.lines(adapter.session.assumed, adapter.name),
    }
end

-- Call this one time in each Logic tick. It gives each changed part to Saved, and gives the problems of Saved.write.
function Adapter.save(adapter)
    local saved = adapter.saved
    local changes = Session.changes(adapter.session)
    if changes.plan then
        Saved.changeGlobal(saved, "plan", changes.plan)
    end
    if changes.settings then
        Saved.changeGlobal(saved, "settings", changes.settings)
    end
    for _, part in ipairs({ "made", "assumed", "reserves", "unlocks" }) do
        for name, value in pairs(changes[part]) do
            Saved.change(saved, name, part, value)
        end
    end
    for name in pairs(adapter.bankChanged) do
        Saved.change(saved, name, "bank", adapter.banks[name])
    end
    adapter.bankChanged = {}
    return Saved.write(saved)
end

return Adapter
