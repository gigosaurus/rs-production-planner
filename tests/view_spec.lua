local View = require("plan/view")

local NAMES = {
    GRIMY_RANARR = "Grimy ranarr",
    RANARR = "Ranarr weed",
    RANARR_UNF = "Ranarr potion (unf)",
    VIAL_WATER = "Vial of water",
    SNAPDRAGON_UNF = "Snapdragon potion (unf)",
    SUPER_RESTORE_3 = "Super restore (3)",
    SUPER_RESTORE_4 = "Super restore (4)",
    EGGS = "Red spiders' eggs",
    SNAPE_GRASS = "Snape grass",
    PRAYER_1 = "Prayer potion (1)",
    VIAL = "Vial",
}

local function nameOf(item)
    return NAMES[item]
end

local function unlockName(unlock)
    return unlock == "62:8" and "Barbarian smithing" or nil
end

local function step(item, verb, actions, fields)
    local made = { item = item, verb = verb, actions = actions, flags = {}, inputs = {} }
    for key, value in pairs(fields or {}) do
        made[key] = value
    end
    return made
end

local function target(item, count, have)
    return { id = 1, item = item, count = count, have = have, mode = "have" }
end

-- A Plan with no Steps and no Shortages: each Target is met.
local function plan(fields)
    local made = {
        targets = { target("RANARR_UNF", 28, 0) },
        steps = {},
        shortages = {},
        leftovers = {},
        assumptions = {},
        complete = false,
    }
    for key, value in pairs(fields) do
        made[key] = value
    end
    return made
end

local function build(input)
    input.nameOf = nameOf
    input.unlockName = unlockName
    input.detected = input.detected or {}
    input.assumed = input.assumed or {}
    if input.bankSeen == nil then
        input.bankSeen = true
    end
    return View.build(input)
end

describe("View.build", function()
    describe("state", function()
        it("is noTargets when the Plan has no Targets", function()
            expectEqual(build({ plan = plan({ targets = {} }) }).state, "noTargets")
        end)

        it("is complete when the Plan is Complete", function()
            expectEqual(build({ plan = plan({ complete = true }) }).state, "complete")
        end)

        it("is plan otherwise", function()
            expectEqual(build({ plan = plan({}) }).state, "plan")
        end)
    end)

    describe("bank warning", function()
        it("shows when the bank was never seen", function()
            expectEqual(build({ plan = plan({}), bankSeen = false }).bankWarning, true)
        end)

        it("does not show when the bank was seen", function()
            expectEqual(build({ plan = plan({}), bankSeen = true }).bankWarning, false)
        end)
    end)

    describe("Do next", function()
        it("gives the verb, the action count and the item of the Next step", function()
            local view = build({
                plan = plan({ steps = { step("RANARR", "Clean", 54, { batchHint = 28 }) }, next = 1 }),
                detected = { RANARR = 3 },
            })
            expectEqual(view.doNext.text, "Clean 54x Ranarr weed")
        end)

        it("gives each Input per inventory, with 'per inventory' after the last", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("RANARR_UNF", "Make", 54, {
                            batchHint = 14,
                            inputs = {
                                { item = "RANARR", perInventory = 14, detected = 54 },
                                { item = "VIAL_WATER", perInventory = 14, detected = 0 },
                            },
                        }),
                    },
                    next = 1,
                }),
            })
            expectEqual(view.doNext.inputs, {
                { item = "RANARR", have = 54, text = "14 Ranarr weed" },
                { item = "VIAL_WATER", have = 0, text = "14 Vial of water per inventory" },
            })
        end)

        it("gives only the name of an Input with no Batch hint", function()
            local view = build({
                plan = plan({
                    steps = { step("RANARR", "Clean", 54, { inputs = { { item = "GRIMY_RANARR", detected = 2 } } }) },
                    next = 1,
                }),
            })
            expectEqual(
                view.doNext.inputs,
                { { item = "GRIMY_RANARR", have = 2, text = "Grimy ranarr per inventory" } }
            )
        end)

        it("gives one line and no Inputs for a Decant step", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("SUPER_RESTORE_4", "Decant", 48, {
                            decant = true,
                            inputs = { { item = "SUPER_RESTORE_3", count = 64 } },
                        }),
                    },
                    next = 1,
                }),
            })
            expectEqual(view.doNext, { text = "Decant 64 Super restore (3) into 48 Super restore (4)", inputs = {} })
        end)

        it("says no step is ready when each Step is Flagged or Waiting", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("SNAPDRAGON_UNF", "Make", 14, { waitsOn = 2 }),
                        step(
                            "SUPER_RESTORE_3",
                            "Mix",
                            14,
                            { flags = { { skill = "HERBLORE", level = 63, current = 61 } } }
                        ),
                    },
                }),
            })
            expectEqual(view.doNext, { text = "No step is ready yet.", inputs = {} })
        end)

        it("points to Buy or gather when a Step is not ready because of Shortages", function()
            local view = build({ plan = plan({ steps = { step("RANARR", "Clean", 54) } }) })
            expectEqual(view.doNext, { text = "Get the items under Buy or gather first.", inputs = {} })
        end)

        it("points to Buy or gather when the Plan has no Steps", function()
            local view = build({ plan = plan({}) })
            expectEqual(view.doNext, { text = "Get the items under Buy or gather first.", inputs = {} })
        end)
    end)

    describe("Targets", function()
        it("gives the item, Counted stock and the count, with Detected stock for the icon", function()
            local view = build({ plan = plan({}), detected = { RANARR_UNF = 9 } })
            expectEqual(view.targets, { { item = "RANARR_UNF", have = 9, text = "Ranarr potion (unf)   0 of 28" } })
        end)

        it("gives the count as the Counted stock in the Complete state", function()
            local view = build({ plan = plan({ complete = true, targets = { target("RANARR_UNF", 28, 30) } }) })
            expectEqual(view.targets[1].text, "Ranarr potion (unf)   28 of 28")
        end)
    end)

    describe("Buy or gather", function()
        it("gives one line for each Shortage, with Detected stock in the tooltip", function()
            local view = build({
                plan = plan({ shortages = { { item = "EGGS", count = 52 } } }),
                detected = { EGGS = 12 },
            })
            expectEqual(view.shortages, { { item = "EGGS", text = "52 Red spiders' eggs", tooltip = "You have 12." } })
        end)
    end)

    describe("Assumed", function()
        it("gives the remaining amount, and the arrived amount when some arrived", function()
            local view = build({
                plan = plan({}),
                assumed = {
                    { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 },
                    { item = "VIAL_WATER", remaining = 20, arrived = 0, entered = 20 },
                },
            })
            expectEqual(view.assumed, {
                { item = "SNAPE_GRASS", text = "14 Snape grass   (36 of 50 arrived)" },
                { item = "VIAL_WATER", text = "20 Vial of water" },
            })
        end)
    end)

    describe("Production order", function()
        it("gives a numbered caption with no action count, and the detail in the tooltip", function()
            local view = build({
                plan = plan({ steps = { step("RANARR", "Clean", 54, { batchHint = 28 }) } }),
                detected = { RANARR = 3 },
            })
            expectEqual(view.steps, {
                {
                    item = "RANARR",
                    have = 3,
                    caption = "1. Clean Ranarr weed",
                    tooltip = "Clean 54x Ranarr weed (2 inventories)",
                },
            })
        end)

        it("says 1 inventory in the singular", function()
            local view = build({ plan = plan({ steps = { step("RANARR", "Clean", 20, { batchHint = 28 }) } }) })
            expectEqual(view.steps[1].tooltip, "Clean 20x Ranarr weed (1 inventory)")
        end)

        it("puts NEXT before the Next step", function()
            local view = build({ plan = plan({ steps = { step("RANARR", "Clean", 54) }, next = 1 }) })
            expectEqual(view.steps[1].kind, "next")
            expectEqual(view.steps[1].caption, "NEXT  1. Clean Ranarr weed")
        end)

        it("gives a short caption for a Decant step and the counts in the tooltip", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("SUPER_RESTORE_4", "Decant", 48, {
                            decant = true,
                            inputs = { { item = "SUPER_RESTORE_3", count = 64 } },
                        }),
                    },
                }),
            })
            expectEqual(view.steps[1].caption, "1. Decant Super restore into (4)")
            expectEqual(view.steps[1].tooltip, "Decant 64 Super restore (3) into 48 Super restore (4)")
        end)

        it("gives the reason of a Flagged step, and the current level in the tooltip", function()
            local view = build({
                plan = plan({
                    steps = {
                        step(
                            "SUPER_RESTORE_3",
                            "Mix",
                            14,
                            { flags = { { skill = "HERBLORE", level = 63, current = 61 } } }
                        ),
                    },
                }),
            })
            expectEqual(view.steps[1].kind, "flagged")
            expectEqual(view.steps[1].reason, "needs Herblore 63")
            expectEqual(view.steps[1].tooltip, "Needs Herblore 63 (you have 61).")
        end)

        it("gives the first Flag and a count, and all the Flags in the tooltip", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("SUPER_RESTORE_3", "Mix", 14, {
                            flags = { { skill = "HERBLORE", level = 63, current = 61 }, { unlock = "62:8" } },
                        }),
                    },
                }),
            })
            expectEqual(view.steps[1].reason, "needs Herblore 63 and 1 more")
            expectEqual(view.steps[1].tooltip, "Needs Herblore 63 (you have 61) and Barbarian smithing.")
        end)

        it("gives the Unlock key when the Unlock has no name", function()
            local view = build({
                plan = plan({ steps = { step("SUPER_RESTORE_3", "Mix", 14, { flags = { { unlock = "QUEST:9" } } }) } }),
            })
            expectEqual(view.steps[1].reason, "needs QUEST:9")
        end)

        it("names the item of the Flagged step that a Waiting step waits on", function()
            local view = build({
                plan = plan({
                    steps = {
                        step("SNAPDRAGON_UNF", "Make", 14, { waitsOn = 2 }),
                        step(
                            "SUPER_RESTORE_3",
                            "Mix",
                            14,
                            { flags = { { skill = "HERBLORE", level = 63, current = 61 } } }
                        ),
                    },
                }),
            })
            expectEqual(view.steps[1].kind, "waiting")
            expectEqual(view.steps[1].caption, "1. Make Snapdragon potion (unf)")
            expectEqual(view.steps[1].reason, "waits on Super restore (3)")
            expectEqual(view.steps[1].tooltip, "Mix Super restore (3) needs Herblore 63.")
        end)
    end)

    describe("Leftovers", function()
        it("gives one line for each Leftover", function()
            local view = build({ plan = plan({ leftovers = { { item = "PRAYER_1", count = 2 } } }) })
            expectEqual(view.leftovers, { "2 Prayer potion (1)" })
        end)

        it("gives one line of all Leftovers for the Complete state", function()
            local view = build({
                plan = plan({
                    complete = true,
                    leftovers = { { item = "PRAYER_1", count = 2 }, { item = "VIAL", count = 5 } },
                }),
            })
            expectEqual(view.leftOver, "Left over: 2 Prayer potion (1), 5 Vial")
        end)

        it("gives no Complete line with no Leftovers", function()
            expectEqual(build({ plan = plan({ complete = true }) }).leftOver, nil)
        end)
    end)

    it("gives the Planning assumptions", function()
        local view =
            build({ plan = plan({ assumptions = { "The Plan assumes that you have the empty vials to decant." } }) })
        expectEqual(view.assumptions, { "The Plan assumes that you have the empty vials to decant." })
    end)
end)
