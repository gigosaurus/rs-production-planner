-- Keeps the Targets, the Made states, the Assumed states, the Reserves, the Unlocks and the Made count scope (issue 79).
-- It gives the Basis of Plan.calculate and the parts to save. The adapter calls Saved with these parts.
-- It does not use the game API. Tests run it outside the game client.
local Assumed = require("plan/assumed")
local Made = require("plan/made")
local Plan = require("plan/calculate")

local Session = {}

local function copyOf(source)
    local copy = {}
    for key, value in pairs(source) do
        copy[key] = value
    end
    return copy
end

local function isMake(target)
    return target.mode == Plan.MAKE
end

local function makeTargets(targets)
    local make = {}
    for _, target in ipairs(targets) do
        if isMake(target) then
            make[#make + 1] = target
        end
    end
    return make
end

-- globals is the result of Saved.loadGlobal. parts maps each name in globals.characters to its Saved.loadCharacter result.
-- name is the logged-in character.
-- With no Make Target, Made must have no state (made.lua). Saved gives a start state to each character, so Session drops them.
function Session.new(globals, parts, name)
    local session = {
        name = name,
        targets = {},
        scope = globals.settings.madeCountScope,
        made = {},
        assumed = {},
        reserves = {},
        unlocks = {},
        changed = { made = {} },
    }
    for index, target in ipairs(globals.plan.targets) do
        session.targets[index] = copyOf(target)
    end
    local hasMake = #makeTargets(session.targets) > 0
    for partName, part in pairs(parts) do
        session.made[partName] = hasMake and part.made or nil
        session.assumed[partName] = part.assumed
        session.reserves[partName] = part.reserves
        session.unlocks[partName] = part.unlocks
    end
    return session
end

-- Gives the Basis of Plan.calculate. facts has the game facts: recipes, detected, levels, stackable and pools.
-- Each Make Target gets the Made count of the Made count scope. A Have Target has no Made count.
-- The table of the caller does not change.
function Session.basis(session, facts)
    local basis = copyOf(facts)
    local counts = Made.counts(session.made, session.name, session.scope, makeTargets(session.targets))
    basis.targets = {}
    for index, target in ipairs(session.targets) do
        basis.targets[index] = copyOf(target)
        basis.targets[index].made = counts[target.id]
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

local function indexOf(session, id)
    for index, target in ipairs(session.targets) do
        if target.id == id then
            return index
        end
    end
    error("The Target " .. tostring(id) .. " does not exist.", 3)
end

-- Marks the Made state of each character as changed.
local function markMade(session)
    for name in pairs(session.made) do
        session.changed.made[name] = true
    end
end

-- facts has detected, the Detected stock now, and offers, all the GE offers of the character now.
local function start(session, target, facts)
    Made.startTarget(session.made, session.name, target, facts.detected, facts.offers)
    markMade(session)
end

-- Call this after the Target changed to Have or left the Targets.
-- With no Make Target, Made deletes all states. Each character that had a state then saves an empty state.
local function stop(session, target)
    markMade(session)
    Made.stopTarget(session.made, target, makeTargets(session.targets))
end

-- Adds a Target and gives its id. A Make Target needs facts, as start describes.
function Session.addTarget(session, item, count, mode, facts)
    local target = { id = nextId(session.targets), item = item, count = count, mode = mode }
    session.targets[#session.targets + 1] = target
    if isMake(target) then
        start(session, target, facts)
    end
    session.changed.plan = true
    return target.id
end

function Session.removeTarget(session, id)
    local target = table.remove(session.targets, indexOf(session, id))
    if isMake(target) then
        stop(session, target)
    end
    session.changed.plan = true
end

-- A change to Make needs facts, as start describes. The same mode changes nothing.
function Session.setMode(session, id, mode, facts)
    local target = session.targets[indexOf(session, id)]
    if target.mode == mode then
        return
    end
    target.mode = mode
    if isMake(target) then
        start(session, target, facts)
    else
        stop(session, target)
    end
    session.changed.plan = true
end

-- Gives the parts that changed since the last call, and clears the marks.
-- plan is the global Targets, or nil. made, assumed, reserves and unlocks map each changed character to its part.
function Session.changes(session)
    local changes = { made = {}, assumed = {}, reserves = {}, unlocks = {} }
    if session.changed.plan then
        changes.plan = { targets = session.targets }
    end
    for name in pairs(session.changed.made) do
        changes.made[name] = session.made[name] or Made.new()
    end
    session.changed = { made = {} }
    return changes
end

return Session
