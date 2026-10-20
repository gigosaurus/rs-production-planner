local Plan = require("plan/calculate")
local diff = require("plan/diff")

-- Grimy ranarr becomes Clean ranarr, then Ranarr potion (unf).
local function herbPlan(detected)
    return Plan.calculate({
        targets = { { item = "RANARR_UNF", count = 28 } },
        recipes = {
            RANARR_UNF = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "CLEAN_RANARR", count = 1 } } } },
            CLEAN_RANARR = { { verb = "Clean", output = 1, actionLimit = 60, inputs = { { item = "GRIMY_RANARR", count = 1 } } } },
        },
        detected = detected,
    })
end

-- Mix Super restore needs Herblore 63. Make Snapdragon potion (unf) waits on it below that level.
local function restorePlan(herblore)
    return Plan.calculate({
        targets = { { item = "SUPER_RESTORE", count = 14 } },
        recipes = {
            SUPER_RESTORE = { {
                verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                skills = { { skill = "HERBLORE", level = 63 } },
            } },
            SNAPDRAGON_UNF = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON", count = 1 } } } },
        },
        detected = { SNAPDRAGON = 14 },
        levels = { HERBLORE = herblore },
    })
end

describe("Plan.diff", function()
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

    it("reports when the Next step moves backwards", function()
        local function twoChains(herblore)
            return Plan.calculate({
                targets = { { item = "SUPER_RESTORE", count = 14 }, { item = "CLEAN_TOADFLAX", count = 28 } },
                recipes = {
                    SUPER_RESTORE = { {
                        verb = "Mix", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON_UNF", count = 1 } },
                        skills = { { skill = "HERBLORE", level = 63 } },
                    } },
                    SNAPDRAGON_UNF = { { verb = "Make", output = 1, actionLimit = 60, inputs = { { item = "SNAPDRAGON", count = 1 } } } },
                    CLEAN_TOADFLAX = { { verb = "Clean", output = 1, actionLimit = 60, inputs = { { item = "GRIMY_TOADFLAX", count = 1 } } } },
                },
                detected = { SNAPDRAGON = 14, GRIMY_TOADFLAX = 28 },
                levels = { HERBLORE = herblore },
            })
        end

        expectEqual(diff.compare(twoChains(61), twoChains(63)).next,
            { from = "CLEAN_TOADFLAX", to = "SNAPDRAGON_UNF", backwards = true })
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

    it("reports Targets whose Counted stock went up or down", function()
        local before = herbPlan({ RANARR_UNF = 28 })
        local after = herbPlan({ RANARR_UNF = 20 })

        expectEqual(diff.compare(before, after).targets, { { item = "RANARR_UNF", by = -8 } })
    end)
end)
