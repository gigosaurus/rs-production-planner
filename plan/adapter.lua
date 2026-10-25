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
    return { saved = saved, session = Session.new(globals, parts) }
end

-- Call this on the first ServerLogic tick in which the player is available.
function Adapter.login(adapter, name)
    local parts = Saved.loadCharacter(adapter.saved, name)
    Session.loadCharacter(adapter.session, name, parts, {})
end

-- facts has the Inventory slots of this tick, and the recipes, levels and stackable of Plan.calculate.
-- Gives the Plan.
function Adapter.tick(adapter, facts)
    local detected = Detected.count(facts.inventory)
    local basis = Session.basis(adapter.session, {
        recipes = facts.recipes,
        detected = detected,
        levels = facts.levels,
        stackable = facts.stackable,
    })
    return { plan = Plan.calculate(basis) }
end

return Adapter
