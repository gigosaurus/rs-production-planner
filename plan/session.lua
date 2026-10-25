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

local function hasMake(session)
    return #makeTargets(session.targets) > 0
end

-- Adds the saved parts of one character.
-- With no Make Target, Made must have no state (made.lua). Saved gives a start state to each character, so Session drops it.
local function addParts(session, name, parts)
    session.made[name] = hasMake(session) and parts.made or nil
    session.assumed[name] = parts.assumed
    session.reserves[name] = parts.reserves
    session.unlocks[name] = parts.unlocks
    session.characters[name] = true
end

-- globals is the result of Saved.loadGlobal. parts maps each name in globals.characters to its Saved.loadCharacter result.
-- Call Session.loadCharacter before the first Make edit.
function Session.new(globals, parts)
    local session = {
        targets = {},
        scope = globals.settings.madeCountScope,
        made = {},
        assumed = {},
        reserves = {},
        unlocks = {},
        characters = {},
        changed = { made = {}, assumed = {} },
    }
    for index, target in ipairs(globals.plan.targets) do
        session.targets[index] = copyOf(target)
    end
    for name, part in pairs(parts) do
        addParts(session, name, part)
    end
    return session
end

-- Gives the saved form of the state of one character, or nil when it has no state.
local function savedForm(module, states, name)
    return states[name] and module.encode(states[name])
end

-- Calls change, then marks the part of the character when its saved form changed.
local function markIfChanged(session, part, module, name, change)
    local before = savedForm(module, session[part], name)
    local result = change()
    if not same(before, savedForm(module, session[part], name)) then
        session.changed[part][name] = true
    end
    return result
end

-- Call this when a character logs in. parts is its Saved.loadCharacter result. offers are all its GE offers now.
-- The parts of a character that Session has already are kept.
-- While a Make Target exists, Made.load makes the next observation the starting point.
function Session.loadCharacter(session, name, parts, offers)
    if not session.characters[name] then
        addParts(session, name, parts)
    end
    session.name = name
    if hasMake(session) then
        markIfChanged(session, "made", Made, name, function()
            Made.load(session.made, name, offers)
        end)
    end
end

-- tick has the facts of one server tick of the logged-in character, as Made.observe takes them.
-- Gives the result of Assumed.observe. A part is changed only when its saved form changes.
function Session.observe(session, tick)
    markIfChanged(session, "made", Made, session.name, function()
        Made.observe(session.made, session.name, tick)
    end)
    return markIfChanged(session, "assumed", Assumed, session.name, function()
        return Assumed.observe(session.assumed, session.name, tick)
    end)
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

local function checkCharacter(session)
    if not session.name then
        error("Load a character before a Make edit.", 4)
    end
end

-- facts has detected, the Detected stock now, and offers, all the GE offers of the character now.
local function start(session, target, facts)
    checkCharacter(session)
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

function Session.setCount(session, id, count)
    session.targets[indexOf(session, id)].count = count
    session.changed.plan = true
end

-- Sets the Made count of a Make Target in the Made count scope. A reset sets it to 0.
function Session.setMade(session, id, count)
    local target = session.targets[indexOf(session, id)]
    if not isMake(target) then
        error("The Target " .. tostring(id) .. " is not a Make Target.", 2)
    end
    Made.set(session.made, session.name, session.scope, target, count)
    markMade(session)
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
    for name in pairs(session.changed.assumed) do
        changes.assumed[name] = session.assumed[name]
    end
    session.changed = { made = {}, assumed = {} }
    return changes
end

return Session
