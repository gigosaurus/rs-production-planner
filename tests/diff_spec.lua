local Plan = require("plan/calculate")
local diff = require("plan/diff")

-- Grimy ranarr becomes Clean ranarr, then Ranarr potion (unf).
local function herbPlan(detected)
    return Plan.calculate({
        targets = { { item = "RANARR_UNF", count = 28 } },
        recipes = {
            RANARR_UNF = {
                { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "CLEAN_RANARR", count = 1 } } },
            },
            CLEAN_RANARR = {
                { verb = "Clean", output = 1, actionLimit = 60, inputs = { { item = "GRIMY_RANARR", count = 1 } } },
            },
        },
        targetMode = Plan.HAVE,
        detected = detected,
    })
end

-- Mix Super restore needs Herblore 63. Make Snapdragon potion (unf) waits on it below that level.
local function restorePlan(herblore)
    return Plan.calculate({
        targets = { { item = "SUPER_RESTORE", count = 14 } },
        recipes = {
            SUPER_RESTORE = {
                {
                    verb = "Mix",
                    output = 1,
                    actionLimit = 60,
                    inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                    skills = { { skill = "HERBLORE", level = 63 } },
                },
            },
            SNAPDRAGON_UNF = {
                { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON", count = 1 } } },
            },
        },
        targetMode = Plan.HAVE,
        detected = { SNAPDRAGON = 14 },
        levels = { HERBLORE = herblore },
    })
end

-- Two Targets that do not depend on each other. In production order, the Steps are
-- Snapdragon potion (unf), Super restore and Clean toadflax.
local function twoChains(herblore, detected)
    return Plan.calculate({
        targets = { { item = "SUPER_RESTORE", count = 14 }, { item = "CLEAN_TOADFLAX", count = 28 } },
        recipes = {
            SUPER_RESTORE = {
                {
                    verb = "Mix",
                    output = 1,
                    actionLimit = 60,
                    inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                    skills = { { skill = "HERBLORE", level = 63 } },
                },
            },
            SNAPDRAGON_UNF = {
                {
                    verb = "Make",
                    output = 1,
                    actionLimit = 60,
                    inputs = { { item = "SNAPDRAGON", count = 1 } },
                },
            },
            CLEAN_TOADFLAX = {
                {
                    verb = "Clean",
                    output = 1,
                    actionLimit = 60,
                    inputs = { { item = "GRIMY_TOADFLAX", count = 1 } },
                },
            },
        },
        targetMode = Plan.HAVE,
        detected = detected,
        levels = { HERBLORE = herblore },
    })
end

describe("Diff.compare", function()
    it("reports a Step that finished", function()
        local before = herbPlan({ GRIMY_RANARR = 28 })
        local after = herbPlan({ CLEAN_RANARR = 28 })

        expectEqual(diff.compare(before, after).finished, { "CLEAN_RANARR" })
    end)

    it("reports a Step that came back", function()
        local before = herbPlan({ CLEAN_RANARR = 28 })
        local after = herbPlan({ GRIMY_RANARR = 28 })

        expectEqual(diff.compare(before, after).back, { "CLEAN_RANARR" })
    end)

    it("reports Steps that stopped being Flagged or Waiting", function()
        local changes = diff.compare(restorePlan(61), restorePlan(63))

        expectEqual(changes.ready, { "SNAPDRAGON_UNF", "SUPER_RESTORE" })
    end)

    it("reports a change of the Next step", function()
        local before = herbPlan({ GRIMY_RANARR = 28 })
        local after = herbPlan({ CLEAN_RANARR = 28 })

        expectEqual(diff.compare(before, after).next, { from = "CLEAN_RANARR", to = "RANARR_UNF", backwards = false })
    end)

    it("does not report the Next step when it does not change", function()
        local before = herbPlan({ GRIMY_RANARR = 28 })
        local after = herbPlan({ GRIMY_RANARR = 30 })

        expectEqual(diff.compare(before, after).next, nil)
    end)

    it("reports when no Step is ready any more", function()
        local before = herbPlan({ GRIMY_RANARR = 28 })
        local after = herbPlan({ GRIMY_RANARR = 27 })

        expectEqual(diff.compare(before, after).next, { from = "CLEAN_RANARR", backwards = false })
    end)

    it("reports when the Next step moves backwards", function()
        local stock = { SNAPDRAGON = 14, GRIMY_TOADFLAX = 28 }

        expectEqual(
            diff.compare(twoChains(61, stock), twoChains(63, stock)).next,
            { from = "CLEAN_TOADFLAX", to = "SNAPDRAGON_UNF", backwards = true }
        )
    end)

    it("does not report a backwards move when the Next step moves forwards", function()
        local before = twoChains(63, { SNAPDRAGON = 14, GRIMY_TOADFLAX = 28 })
        local after = twoChains(63, { GRIMY_TOADFLAX = 28 })

        expectEqual(
            diff.compare(before, after).next,
            { from = "SNAPDRAGON_UNF", to = "CLEAN_TOADFLAX", backwards = false }
        )
    end)

    it("reports Shortages that disappeared", function()
        local before = herbPlan({})
        local after = herbPlan({ GRIMY_RANARR = 28 })

        expectEqual(diff.compare(before, after).covered, { "GRIMY_RANARR" })
    end)

    it("reports that the Plan became Complete", function()
        local before = herbPlan({ CLEAN_RANARR = 28 })
        local after = herbPlan({ RANARR_UNF = 28 })

        expectEqual(diff.compare(before, after).complete, true)
    end)

    it("reports that the Plan stopped being Complete", function()
        local before = herbPlan({ RANARR_UNF = 28 })
        local after = herbPlan({ RANARR_UNF = 20 })

        expectEqual(diff.compare(before, after).complete, false)
    end)

    it("reports a Target whose Counted stock went down", function()
        local before = herbPlan({ RANARR_UNF = 28 })
        local after = herbPlan({ RANARR_UNF = 20 })

        expectEqual(diff.compare(before, after).targets, { { item = "RANARR_UNF", by = -8 } })
    end)

    it("reports a Target whose Counted stock went up", function()
        local before = herbPlan({ RANARR_UNF = 20 })
        local after = herbPlan({ RANARR_UNF = 28 })

        expectEqual(diff.compare(before, after).targets, { { item = "RANARR_UNF", by = 8 } })
    end)

    it("does not report a Target whose Counted stock did not change", function()
        local before = herbPlan({ GRIMY_RANARR = 28 })
        local after = herbPlan({ CLEAN_RANARR = 28 })

        expectEqual(diff.compare(before, after).targets, {})
    end)
end)
