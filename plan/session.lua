-- Keeps the Targets, the Made states, the Assumed states, the Reserves, the Unlocks and the Made count scope (issue 79).
-- It gives the Basis of Plan.calculate and the parts to save. The adapter calls Saved with these parts.
-- It does not use the game API. Tests run it outside the game client.
local Assumed = require("plan/assumed")

local Session = {}

-- globals is the result of Saved.loadGlobal. parts maps each name in globals.characters to its Saved.loadCharacter result.
-- name is the logged-in character.
function Session.new(globals, parts, name)
    local session = {
        name = name,
        targets = globals.plan.targets,
        scope = globals.settings.madeCountScope,
        made = {},
        assumed = {},
        reserves = {},
        unlocks = {},
        changed = {},
    }
    for partName, part in pairs(parts) do
        session.made[partName] = part.made
        session.assumed[partName] = part.assumed
        session.reserves[partName] = part.reserves
        session.unlocks[partName] = part.unlocks
    end
    return session
end

local function copyOf(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

-- Gives the Basis of Plan.calculate. facts has the game facts: recipes, detected, levels, stackable and pools.
-- The table of the caller does not change.
function Session.basis(session, facts)
    local basis = copyOf(facts)
    basis.targets = {}
    for index, target in ipairs(session.targets) do
        basis.targets[index] = copyOf(target)
    end
    basis.assumed = Assumed.remaining(session.assumed, session.name)
    basis.reserves = copyOf(session.reserves[session.name] or {})
    basis.unlocks = copyOf(session.unlocks[session.name] or {})
    return basis
end

-- Gives the id of the new Target: the largest id now, plus 1.
local function nextId(targets)
    local largest = 0
    for _, target in ipairs(targets) do
        largest = math.max(largest, target.id)
    end
    return largest + 1
end

-- Adds a Target and gives its id.
function Session.addTarget(session, item, count, mode)
    local id = nextId(session.targets)
    session.targets[#session.targets + 1] = { id = id, item = item, count = count, mode = mode }
    session.changed.plan = true
    return id
end

-- Gives the parts that changed since the last call, and clears the marks.
-- plan is the global Targets, or nil. made, assumed, reserves and unlocks map each changed character to its part.
function Session.changes(session)
    local changes = { made = {}, assumed = {}, reserves = {}, unlocks = {} }
    if session.changed.plan then
        changes.plan = { targets = session.targets }
    end
    session.changed = {}
    return changes
end

return Session
