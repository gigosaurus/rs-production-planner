local Made = require("plan/made")
local Plan = require("plan/calculate")
local Session = require("plan/session")

-- Gives the globals of Saved.loadGlobal with no saved data, and the given Targets.
local function globals(targets)
    return { characters = {}, plan = { targets = targets or {} }, settings = { madeCountScope = Made.CHARACTER } }
end

local function newSession(targets)
    return Session.new(globals(targets), {}, "Alice")
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
        local SHARK = { id = 1, item = "SHARK", count = 10, mode = Plan.MAKE }
        local FACTS = { recipes = {}, detected = {} }

        -- Gives the parts of Saved.loadCharacter, with a Made state that saw made SHARK and the given start values.
        local function madeParts(made, starts)
            local state = Made.new()
            state.counts, state.starts = { SHARK = made }, starts
            return { made = state, assumed = { entries = {} }, reserves = {}, unlocks = {} }
        end

        local function madeOf(session, index)
            return Session.basis(session, FACTS).targets[index].made
        end

        it("gives each Make Target its Made count from the saved Made states", function()
            local session = Session.new(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) }, "Alice")

            expectEqual(madeOf(session, 1), 3)
        end)

        it("gives the Made counts of all characters in the Made count scope All characters", function()
            local saved = globals({ SHARK })
            saved.settings.madeCountScope = Made.ALL
            local parts = { Alice = madeParts(5, { [1] = 2 }), Bob = madeParts(4, { [1] = 0 }) }

            expectEqual(madeOf(Session.new(saved, parts, "Alice"), 1), 7)
        end)

        it("starts a new Make Target with a Made count of 0", function()
            local session = newSession()

            Session.addTarget(session, "SHARK", 10, Plan.MAKE, { detected = { SHARK = 4 }, offers = {} })

            expectEqual(madeOf(session, 1), 0)
        end)

        it(
            "drops the saved Made states when no Make Target exists, so the first Make Target reads the GE offers",
            function()
                local session = Session.new(globals(), { Alice = madeParts(5, {}) }, "Alice")
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
            local session = Session.new(globals({ SHARK }), parts, "Alice")

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
            local session = Session.new(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) }, "Alice")

            Session.setMode(session, 1, Plan.HAVE)

            expectEqual(madeOf(session, 1), nil)
            local changes = Session.changes(session)
            expectEqual(changes.plan.targets[1].mode, Plan.HAVE)
            expectEqual(changes.made, { Alice = Made.new() })
        end)

        it("changes nothing when the mode is the same", function()
            local session = Session.new(globals({ SHARK }), { Alice = madeParts(5, { [1] = 2 }) }, "Alice")

            Session.setMode(session, 1, Plan.MAKE, { detected = {}, offers = {} })

            expectEqual(madeOf(session, 1), 3)
            expectEqual(Session.changes(session), { made = {}, assumed = {}, reserves = {}, unlocks = {} })
        end)

        it("keeps the Made count of the other Make Target of the item when one is removed", function()
            local other = { id = 2, item = "SHARK", count = 50, mode = Plan.MAKE }
            local parts = { Alice = madeParts(5, { [1] = 2, [2] = 1 }) }
            local session = Session.new(globals({ SHARK, other }), parts, "Alice")

            Session.removeTarget(session, 1)

            expectEqual(
                Session.basis(session, FACTS).targets,
                { { id = 2, item = "SHARK", count = 50, mode = Plan.MAKE, made = 4 } }
            )
            expectEqual(Session.changes(session).made.Alice.starts, { [2] = 1 })
        end)

        it("does not change the Made states when a Have Target is removed", function()
            local have = { id = 2, item = "ROCKTAIL", count = 5, mode = Plan.HAVE }
            local session = Session.new(globals({ SHARK, have }), { Alice = madeParts(5, { [1] = 2 }) }, "Alice")

            Session.removeTarget(session, 2)

            local changes = Session.changes(session)
            expectEqual(changes.plan.targets, { SHARK })
            expectEqual(changes.made, {})
        end)

        it("gives an error for a Target id that does not exist", function()
            local ok, message = pcall(Session.removeTarget, newSession(), 7)

            expectEqual(ok, false)
            expectEqual(message:find("The Target 7 does not exist.", 1, true) ~= nil, true)
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
