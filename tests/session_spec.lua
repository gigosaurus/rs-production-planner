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
