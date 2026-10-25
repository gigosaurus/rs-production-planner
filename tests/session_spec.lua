local Assumed = require("plan/assumed")
local Made = require("plan/made")
local Plan = require("plan/calculate")
local Saved = require("plan/saved")
local Session = require("plan/session")

-- Gives the globals of Saved.loadGlobal with no saved data, and the given Targets.
local function globals(targets)
    return { characters = {}, plan = { targets = targets or {} }, settings = { madeCountScope = Made.CHARACTER } }
end

-- Gives the parts of Saved.loadCharacter for a character with no saved data.
local function startParts()
    return { made = Made.new(), assumed = Assumed.new(), reserves = {}, unlocks = {} }
end

-- Gives a Session with Alice logged in. parts maps each name to its saved parts, as Session.new takes them.
local function loaded(saved, parts)
    local session = Session.new(saved, parts)
    Session.loadCharacter(session, "Alice", parts.Alice or startParts(), {})
    return session
end

local function newSession(targets)
    return loaded(globals(targets), {})
end

-- Calls fn from this file. Gives the error message without its position, or nil when the error is not at this file.
local function errorOf(fn, ...)
    local args = table.pack(...)
    local ok, message = pcall(function()
        fn(table.unpack(args, 1, args.n))
    end)
    return not ok and tostring(message):match("session_spec%.lua:%d+: (.*)$") or nil
end

local SHARK = { id = 1, item = "SHARK", count = 10, mode = Plan.MAKE }
local ROCKTAIL = { id = 2, item = "ROCKTAIL", count = 10, mode = Plan.MAKE }
local FACTS = { recipes = {}, detected = {} }
local NO_FACTS = { detected = {}, offers = {} }

-- Gives the parts of Saved.loadCharacter, with a Made state that has the given item counts and start values.
local function stateOf(counts, starts)
    local parts = startParts()
    parts.made.counts, parts.made.starts = counts, starts
    return parts
end

-- Gives the parts of a character that saw made SHARK.
local function madeParts(made, starts)
    return stateOf({ SHARK = made }, starts)
end

local function madeOf(session, index)
    return Session.basis(session, FACTS).targets[index].made
end

describe("Session", function()
    describe("Basis", function()
        it("gives the game facts and no Targets when the plan has no Targets", function()
            local session = newSession()

            local basis = Session.basis(session, { recipes = {}, detected = { SHARK = 3 } })

            expectEqual(basis, {
                recipes = {},
                detected = { SHARK = 3 },
                targets = {},
                assumed = {},
                reserves = {},
                unlocks = {},
            })
        end)

        it("does not change the facts of the caller", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.HAVE)
            local facts = { recipes = {}, detected = {} }

            Session.basis(session, facts)

            expectEqual(facts, { recipes = {}, detected = {} })
        end)

        it("gives copies of the Targets, so a change to the Basis does not change the Session", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.HAVE)

            Session.basis(session, { recipes = {}, detected = {} }).targets[1].count = 99

            expectEqual(Session.basis(session, { recipes = {}, detected = {} }).targets[1].count, 10)
        end)

        it("gives a Plan that Plan.calculate accepts", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.HAVE)

            local result = Plan.calculate(Session.basis(session, { recipes = {}, detected = { SHARK = 4 } }))

            expectEqual(result.shortages, { { item = "SHARK", count = 6 } })
        end)
    end)

    describe("addTarget", function()
        it("adds a Have Target with no Made count", function()
            local session = newSession()

            local id = Session.addTarget(session, "SHARK", 10, Plan.HAVE)

            expectEqual(id, 1)
            expectEqual(
                Session.basis(session, { recipes = {}, detected = {} }).targets,
                { { id = 1, item = "SHARK", count = 10, mode = Plan.HAVE } }
            )
        end)

        it("gives the largest id plus 1", function()
            local session = newSession({ { id = 5, item = "SHARK", count = 10, mode = Plan.HAVE } })

            expectEqual(Session.addTarget(session, "ROCKTAIL", 2, Plan.HAVE), 6)
        end)
    end)

    describe("Make Targets", function()
        it("gives each Make Target its Made count from the saved Made states", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            expectEqual(madeOf(session, 1), 3)
        end)

        it("gives the Made counts of all characters in the Made count scope All characters", function()
            local saved = globals({ SHARK })
            saved.settings.madeCountScope = Made.ALL
            local parts = { Alice = madeParts(5, { [1] = 2 }), Bob = madeParts(4, { [1] = 0 }) }

            expectEqual(madeOf(loaded(saved, parts), 1), 7)
        end)

        it("starts a new Make Target with a Made count of 0", function()
            local session = newSession()

            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 4 }, offers = {} })

            expectEqual(madeOf(session, 1), 0)
        end)

        it(
            "drops the saved Made states when no Make Target exists, so the first Make Target reads the GE offers",
            function()
                local session = loaded(globals(), { Alice = madeParts(5, {}) })
                local offer =
                    { slot = 0, item = "SHARK", type = Made.BUY, stage = Made.ADDED, soldCount = 3, itemCount = 9 }

                Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = {}, offers = { offer } })

                local made = Session.changes(session).made
                expectEqual(made.Alice.counts, { SHARK = 0 })
                expectEqual(made.Alice.slots[0].soldCount, 3)
            end
        )

        it("gives the Made state of each character after a Make Target starts", function()
            local parts = { Alice = madeParts(5, { [1] = 2 }), Bob = madeParts(4, { [1] = 0 }) }
            local session = loaded(globals({ SHARK }), parts)

            Session.addTarget(session, "SHARK", 20, Plan.MAKE, { detected = {}, offers = {} })

            local changes = Session.changes(session)
            expectEqual(changes.made.Alice.starts, { [1] = 2, [2] = 5 })
            expectEqual(changes.made.Bob.starts, { [1] = 0, [2] = 4 })
        end)

        it("starts a Target that changes to Make", function()
            local session = newSession({ { id = 1, item = "SHARK", count = 10, mode = Plan.HAVE } })

            Session.setMode(session, 1, Plan.MAKE, { detected = {}, offers = {} })

            expectEqual(madeOf(session, 1), 0)
            expectEqual(Session.changes(session).plan.targets[1].mode, Plan.MAKE)
        end)

        it("stops a Target that changes to Have, and gives an empty Made state to save", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.setMode(session, 1, Plan.HAVE)

            expectEqual(madeOf(session, 1), nil)
            local changes = Session.changes(session)
            expectEqual(changes.plan.targets[1].mode, Plan.HAVE)
            expectEqual(changes.made, { Alice = Made.new() })
        end)

        it("changes nothing when the mode is the same", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.setMode(session, 1, Plan.MAKE, { detected = {}, offers = {} })

            expectEqual(madeOf(session, 1), 3)
            expectEqual(Session.changes(session), { made = {}, assumed = {}, reserves = {}, unlocks = {} })
        end)

        it("keeps the Made count of the other Make Target of the item when one is removed", function()
            local other = { id = 2, item = "SHARK", count = 50, mode = Plan.MAKE }
            local parts = { Alice = madeParts(5, { [1] = 2, [2] = 1 }) }
            local session = loaded(globals({ SHARK, other }), parts)

            Session.removeTarget(session, 1)

            expectEqual(
                Session.basis(session, FACTS).targets,
                { { id = 2, item = "SHARK", count = 50, mode = Plan.MAKE, made = 4 } }
            )
            expectEqual(Session.changes(session).made.Alice.starts, { [2] = 1 })
        end)

        it("does not change the Made states when a Have Target is removed", function()
            local have = { id = 2, item = "ROCKTAIL", count = 5, mode = Plan.HAVE }
            local session = loaded(globals({ SHARK, have }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.removeTarget(session, 2)

            local changes = Session.changes(session)
            expectEqual(changes.plan.targets, { SHARK })
            expectEqual(changes.made, {})
        end)

        it("gives an error for a Target id that does not exist", function()
            expectEqual(errorOf(Session.removeTarget, newSession(), 7), "The Target 7 does not exist.")
        end)
    end)

    describe("loadCharacter", function()
        it("counts no rise between sessions", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.observe(session, { detected = { SHARK = 50 } })
            Session.observe(session, { detected = { SHARK = 52 } })

            expectEqual(madeOf(session, 1), 5)
        end)

        it("counts no rise while the character was logged out, also in the same session", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            Session.observe(session, { detected = { SHARK = 12 } })
            Session.loadCharacter(session, "Bob", startParts(), {})

            Session.loadCharacter(session, "Alice", startParts(), {})
            Session.observe(session, { detected = { SHARK = 30 } })

            expectEqual(madeOf(session, 1), 2)
        end)

        it("keeps the parts that it has of a character that logs in again", function()
            local parts = startParts()
            parts.reserves = { SHARK = 2 }
            local session = loaded(globals(), { Alice = parts })
            Session.loadCharacter(session, "Bob", startParts(), {})

            Session.loadCharacter(session, "Alice", startParts(), {})

            expectEqual(Session.basis(session, FACTS).reserves, { SHARK = 2 })
        end)

        it(
            "gives a Made count of 0 to a character with no saved data, and counts from its first observation",
            function()
                local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

                Session.loadCharacter(session, "Bob", startParts(), {})
                Session.observe(session, { detected = { SHARK = 4 } })
                Session.observe(session, { detected = { SHARK = 9 } })

                expectEqual(madeOf(session, 1), 5)
            end
        )

        it("gives the Basis the Reserves, Unlocks and Assumed stock of the logged-in character", function()
            local session = newSession()
            local parts = startParts()
            parts.reserves, parts.unlocks = { SHARK = 2 }, { LUNAR_SPELLBOOK = true }
            parts.assumed.entries = { { item = "ROCKTAIL", entered = 5, remaining = 5, baseline = 0 } }

            Session.loadCharacter(session, "Bob", parts, {})

            local basis = Session.basis(session, FACTS)
            expectEqual(basis.reserves, { SHARK = 2 })
            expectEqual(basis.unlocks, { LUNAR_SPELLBOOK = true })
            expectEqual(basis.assumed, { ROCKTAIL = 5 })
        end)

        it("makes no Made state with no Make Target, so the first Make Target reads the GE offers", function()
            local session = newSession()
            Session.loadCharacter(session, "Bob", startParts(), {})
            local offer =
                { slot = 0, item = "SHARK", type = Made.BUY, stage = Made.ADDED, soldCount = 3, itemCount = 9 }

            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = {}, offers = { offer } })

            local made = Session.changes(session).made
            expectEqual(made.Alice, nil)
            expectEqual(made.Bob.slots[0].soldCount, 3)
        end)

        it("gives an error at the caller for a Make edit before a character is loaded", function()
            local ok, message = pcall(function()
                Session.addTarget(Session.new(globals(), {}), "SHARK", 10, Plan.MAKE, NO_FACTS)
            end)

            expectEqual(ok, false)
            expectEqual(message:find("session_spec.lua:%d+: Load a character before this edit.") ~= nil, true)
        end)
    end)

    describe("observe", function()
        it("adds a rise in Detected stock to the Made count", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })

            Session.observe(session, { detected = { SHARK = 13 } })

            expectEqual(madeOf(session, 1), 3)
        end)

        it("saves counts only for the items of the Make Targets", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            Session.observe(session, { detected = { SHARK = 10, VIAL_OF_WATER = 5 } })
            Session.observe(session, { detected = { SHARK = 13, VIAL_OF_WATER = 9 } })

            expectEqual(Session.changes(session).made.Alice.counts, { SHARK = 3 })
        end)

        it("saves no GE amount for an item that is in Detected stock but is not a Make Target", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            local offer =
                { slot = 1, item = "ROCKTAIL", type = Made.BUY, stage = Made.ADDED, soldCount = 30, itemCount = 100 }

            Session.observe(session, { detected = { SHARK = 10, ROCKTAIL = 0 }, ge = { offer } })

            expectEqual(Session.changes(session).made.Alice.ge, {})
        end)

        it("gives the Assumed stock that arrived and the lines that are Fulfilled", function()
            local parts = startParts()
            parts.assumed.entries = { { item = "ROCKTAIL", entered = 5, remaining = 5, baseline = 0 } }
            local session = loaded(globals(), { Alice = parts })

            local result = Session.observe(session, { detected = { ROCKTAIL = 5 } })

            expectEqual(result, { arrived = { { item = "ROCKTAIL", count = 5 } }, fulfilled = { "ROCKTAIL" } })
            expectEqual(Session.basis(session, FACTS).assumed, {})
        end)

        it("gives no Made state to save when its saved form does not change", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            Session.changes(session)

            Session.observe(session, { detected = { SHARK = 10 } })
            expectEqual(Session.changes(session).made, {})

            Session.observe(session, { detected = { SHARK = 12 } })
            expectEqual(Session.changes(session).made.Alice.counts, { SHARK = 2 })
        end)

        it("gives the Assumed state to save only when its saved form changes", function()
            local parts = startParts()
            parts.assumed.entries = { { item = "ROCKTAIL", entered = 5, remaining = 5, baseline = 0 } }
            local session = loaded(globals(), { Alice = parts })

            Session.observe(session, { detected = { ROCKTAIL = 0 } })
            expectEqual(Session.changes(session).assumed, {})

            Session.observe(session, { detected = { ROCKTAIL = 2 } })
            expectEqual(Session.changes(session).assumed.Alice.entries[1].remaining, 3)
        end)

        it("deletes the saved counts of an item that no Make Target is for, on each character", function()
            local starts = { [1] = 0, [2] = 0 }
            local parts = { Alice = stateOf({ SHARK = 2, ROCKTAIL = 3 }, starts), Bob = stateOf({ SHARK = 4 }, starts) }
            local session = loaded(globals({ SHARK, ROCKTAIL }), parts)

            Session.removeTarget(session, 1)

            local made = Session.changes(session).made
            expectEqual(made.Alice.counts, { ROCKTAIL = 3 })
            expectEqual(made.Bob.counts, {})
        end)
    end)

    describe("Target edits", function()
        it("sets the Made count of a Make Target", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.setMade(session, 1, 9)

            expectEqual(madeOf(session, 1), 9)
            expectEqual(Session.changes(session).made.Alice.starts, { [1] = -4 })
        end)

        it("gives an error for a Made count edit of a Have Target", function()
            local session = newSession({ { id = 1, item = "SHARK", count = 10, mode = Plan.HAVE } })

            expectEqual(errorOf(Session.setMade, session, 1, 3), "The Target 1 is not a Make Target.")
        end)

        it("sets the count of a Target", function()
            local session = loaded(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) })

            Session.setCount(session, 1, 40)

            local changes = Session.changes(session)
            expectEqual(changes.plan.targets[1].count, 40)
            expectEqual(changes.made, {})
            expectEqual(madeOf(session, 1), 3)
        end)
    end)

    describe("saved data", function()
        -- Acts as PersistentDB for the parts that Session gives.
        local function store()
            local values = {}
            return {
                Get = function(_, key)
                    return values[key]
                end,
                Set = function(_, key, value)
                    values[key] = value
                    return true
                end,
            }
        end

        -- Loads a Session from the store, as the adapter does.
        local function load(db, name)
            local saved = Saved.new(db)
            local savedGlobals = Saved.loadGlobal(saved)
            local parts = {}
            for _, known in ipairs(savedGlobals.characters) do
                parts[known] = Saved.loadCharacter(saved, known)
            end
            local session = Session.new(savedGlobals, parts)
            Session.loadCharacter(session, name, parts[name] or Saved.loadCharacter(saved, name), {})
            return session, saved
        end

        -- Saves the changed parts, as the adapter does.
        local function save(session, saved)
            local changes = Session.changes(session)
            for _, part in ipairs({ "plan", "settings" }) do
                if changes[part] then
                    Saved.changeGlobal(saved, part, changes[part])
                end
            end
            for part, byName in pairs(changes) do
                if part ~= "plan" and part ~= "settings" then
                    for name, value in pairs(byName) do
                        Saved.change(saved, name, part, value)
                    end
                end
            end
            Saved.write(saved)
        end

        it("gives the same Plan after an edit of the Made count, a save and a load", function()
            local db = store()
            local session, saved = load(db, "Alice")
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            Session.observe(session, { detected = { SHARK = 15 } })
            Session.setMade(session, 1, 2)
            save(session, saved)

            local again = load(db, "Alice")

            expectEqual(Session.basis(again, FACTS).targets, Session.basis(session, FACTS).targets)
            expectEqual(Plan.calculate(Session.basis(again, FACTS)), Plan.calculate(Session.basis(session, FACTS)))
        end)

        it("gives the same Basis after edits of each part, a save and a load", function()
            local db = store()
            local session, saved = load(db, "Alice")
            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 10 }, offers = {} })
            Session.observe(session, { detected = { SHARK = 15 } })
            Session.setScope(session, Made.ALL)
            Session.setReserve(session, "ROCKTAIL", 4)
            Session.setUnlock(session, "LUNAR_SPELLBOOK", true)
            Session.addAssumed(session, "RAW_SHARK", 6, { RAW_SHARK = 1 })
            save(session, saved)

            local again = load(db, "Alice")

            expectEqual(Session.basis(again, FACTS), Session.basis(session, FACTS))
        end)
    end)

    describe("character edits", function()
        it("sets a Reserve of the logged-in character", function()
            local session = newSession()

            Session.setReserve(session, "SHARK", 3)

            expectEqual(Session.basis(session, FACTS).reserves, { SHARK = 3 })
            expectEqual(Session.changes(session).reserves, { Alice = { SHARK = 3 } })
        end)

        it("deletes a Reserve that is set to 0", function()
            local session = newSession()
            Session.setReserve(session, "SHARK", 3)

            Session.setReserve(session, "SHARK", 0)

            expectEqual(Session.basis(session, FACTS).reserves, {})
        end)

        it("gives an error for a Reserve that is not a whole number of 0 or more", function()
            expectEqual(
                errorOf(Session.setReserve, newSession(), "SHARK", 1.5),
                "The Reserve of SHARK must be a whole number of 0 or more."
            )
        end)

        it("sets and clears an Unlock of the logged-in character", function()
            local session = newSession()

            Session.setUnlock(session, "LUNAR_SPELLBOOK", true)
            Session.setUnlock(session, "ANCIENT_CURSES", true)
            Session.setUnlock(session, "ANCIENT_CURSES", false)

            expectEqual(Session.basis(session, FACTS).unlocks, { LUNAR_SPELLBOOK = true })
            expectEqual(Session.changes(session).unlocks, { Alice = { LUNAR_SPELLBOOK = true } })
        end)

        it("adds and removes Assumed stock of the logged-in character", function()
            local session = newSession()

            Session.addAssumed(session, "SHARK", 5, { SHARK = 2 })
            Session.addAssumed(session, "ROCKTAIL", 3, {})
            Session.removeAssumed(session, "ROCKTAIL")

            expectEqual(Session.basis(session, FACTS).assumed, { SHARK = 5 })
            expectEqual(Session.changes(session).assumed.Alice.entries, {
                { item = "SHARK", entered = 5, remaining = 5, baseline = 2 },
            })
        end)

        it("gives an error at the caller for each character edit before a character is loaded", function()
            local edits = {
                function(session)
                    Session.setMade(session, 1, 2)
                end,
                function(session)
                    Session.setReserve(session, "SHARK", 3)
                end,
                function(session)
                    Session.setUnlock(session, "LUNAR_SPELLBOOK", true)
                end,
                function(session)
                    Session.addAssumed(session, "SHARK", 5, {})
                end,
                function(session)
                    Session.removeAssumed(session, "SHARK")
                end,
            }
            for _, edit in ipairs(edits) do
                local ok, message = pcall(edit, Session.new(globals({ SHARK }), {}))

                expectEqual(ok, false)
                expectEqual(message:find("session_spec.lua:%d+: Load a character before this edit.") ~= nil, true)
            end
        end)
    end)

    describe("setScope", function()
        it("gives the Made counts of the new Made count scope, and the settings to save", function()
            local parts = { Alice = madeParts(5, { [1] = 2 }), Bob = madeParts(4, { [1] = 0 }) }
            local session = loaded(globals({ SHARK }), parts)

            Session.setScope(session, Made.ALL)

            expectEqual(madeOf(session, 1), 7)
            expectEqual(Session.changes(session).settings, { madeCountScope = Made.ALL })
        end)

        it("gives an error for an unknown Made count scope", function()
            expectEqual(
                errorOf(Session.setScope, newSession(), "EVERYONE"),
                "The Made count scope EVERYONE is unknown."
            )
        end)
    end)

    describe("changes", function()
        it("gives no parts when nothing changed", function()
            expectEqual(Session.changes(newSession()), { made = {}, assumed = {}, reserves = {}, unlocks = {} })
        end)

        it("gives the Targets after a Target edit, then clears the mark", function()
            local session = newSession()
            Session.addTarget(session, "SHARK", 10, Plan.HAVE)

            local changes = Session.changes(session)

            expectEqual(changes.plan, { targets = { { id = 1, item = "SHARK", count = 10, mode = Plan.HAVE } } })
            expectEqual(Session.changes(session).plan, nil)
        end)
    end)
end)
