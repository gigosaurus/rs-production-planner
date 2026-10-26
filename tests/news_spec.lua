local News = require("plan/news")

local NAMES = {
    RANARR = "Ranarr weed",
    RANARR_UNF = "Ranarr potion (unf)",
    SNAPDRAGON_UNF = "Snapdragon potion (unf)",
    SUPER_RESTORE_3 = "Super restore (3)",
    SUPER_RESTORE_4 = "Super restore (4)",
    EGGS = "Red spiders' eggs",
    SNAPE_GRASS = "Snape grass",
}

local function nameOf(item)
    return NAMES[item]
end

local function step(item, verb, fields)
    local made = { item = item, verb = verb, actions = 14, flags = {}, inputs = {} }
    for key, value in pairs(fields or {}) do
        made[key] = value
    end
    return made
end

local CLEAN = step("RANARR", "Clean")
local MAKE = step("RANARR_UNF", "Make")
local SNAPDRAGON = step("SNAPDRAGON_UNF", "Make")
local MIX = step("SUPER_RESTORE_3", "Mix")
local SNAPDRAGON_WAITS = step("SNAPDRAGON_UNF", "Make", { waitsOn = 2 })
local MIX_FLAGGED = step("SUPER_RESTORE_3", "Mix", { flags = { { skill = "HERBLORE", level = 63, current = 61 } } })

-- Gives a state as News takes it: a Plan and the Assumed lines.
local function seen(fields, assumed)
    local plan = {
        targets = { { id = 1, item = "SUPER_RESTORE_4", count = 60, have = 12, mode = "have" } },
        steps = {},
        shortages = {},
        leftovers = {},
        assumptions = {},
        complete = false,
    }
    for key, value in pairs(fields) do
        plan[key] = value
    end
    return { plan = plan, assumed = assumed or {} }
end

local function have(count)
    return { { id = 1, item = "SUPER_RESTORE_4", count = 60, have = count, mode = "have" } }
end

-- Opens a new News on before, then gives it after. Gives the News.
local function change(before, after)
    local news = News.new()
    News.open(news, before, nameOf)
    News.see(news, after, nameOf)
    return news
end

describe("News", function()
    describe("message", function()
        it("is nil before the first change", function()
            local news = News.new()
            News.open(news, seen({}), nameOf)
            expectEqual(news.message, nil)
        end)

        it("names a finished Step by its verb and item", function()
            local news = change(seen({ steps = { CLEAN, MAKE }, next = 1 }), seen({ steps = { MAKE }, next = 1 }))
            expectEqual(news.message, "Clean Ranarr weed is done. Next: Make Ranarr potion (unf).")
        end)

        it("joins two finished Steps", function()
            local news = change(seen({ steps = { CLEAN, MAKE, MIX } }), seen({ steps = { MIX } }))
            expectEqual(news.message, "Clean Ranarr weed and Make Ranarr potion (unf) are done.")
        end)

        it("gives the cause first: a Target used, then the Step that comes back", function()
            local news = change(
                seen({ targets = have(20), steps = { MAKE }, next = 1 }),
                seen({ targets = have(12), steps = { CLEAN, MAKE }, next = 1 })
            )
            expectEqual(
                news.message,
                "You used 8 Super restore (4). Clean Ranarr weed must be done again. "
                    .. "The next step moved back to Clean Ranarr weed."
            )
        end)

        it("gives a Target that goes up", function()
            local news = change(seen({ targets = have(12) }), seen({ targets = have(40) }))
            expectEqual(news.message, "You have 28 more Super restore (4).")
        end)

        it("says when the Plan stops being Complete", function()
            local news = change(
                seen({ targets = have(60), complete = true }),
                seen({ targets = have(52), steps = { MIX }, next = 1 })
            )
            expectEqual(
                news.message,
                "You used 8 Super restore (4). Mix Super restore (3) must be done again. "
                    .. "The plan is not complete now. Next: Mix Super restore (3)."
            )
        end)

        it("gives only the Complete message when the Plan becomes Complete", function()
            local news = change(
                seen({ targets = have(52), steps = { MIX }, next = 1 }),
                seen({ targets = have(60), complete = true })
            )
            expectEqual(news.message, "Plan complete. You have all the items that you wanted to make.")
        end)

        it("gives the Steps that can start now, then the Next step that moved back", function()
            local news = change(
                seen({ steps = { SNAPDRAGON_WAITS, MIX_FLAGGED, CLEAN }, next = 3 }),
                seen({ steps = { SNAPDRAGON, MIX, CLEAN }, next = 1 })
            )
            expectEqual(
                news.message,
                "Make Snapdragon potion (unf) and Mix Super restore (3) can start now. "
                    .. "The next step moved back to Make Snapdragon potion (unf)."
            )
        end)

        it("says nothing about Next when no Step can be the Next step", function()
            local news = change(seen({ steps = { CLEAN, MAKE }, next = 1 }), seen({ steps = { MAKE } }))
            expectEqual(news.message, "Clean Ranarr weed is done.")
        end)

        it("gives a Shortage that is covered", function()
            local news = change(seen({ shortages = { { item = "EGGS", count = 52 } } }), seen({}))
            expectEqual(news.message, "You have enough Red spiders' eggs now.")
        end)

        it("gives Assumed stock that is all arrived", function()
            local news =
                change(seen({}, { { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 } }), seen({}, {}))
            expectEqual(news.message, "All your assumed Snape grass has arrived.")
        end)

        it("gives no message when only some Assumed stock arrives", function()
            local news = change(
                seen({}, { { item = "SNAPE_GRASS", remaining = 50, arrived = 0, entered = 50 } }),
                seen({}, { { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 } })
            )
            expectEqual(news.message, nil)
        end)

        it("keeps the message after a change with no sentence", function()
            local news = change(seen({ steps = { CLEAN, MAKE }, next = 1 }), seen({ steps = { MAKE }, next = 1 }))
            News.see(news, seen({ steps = { step("RANARR_UNF", "Make", { actions = 5 }) }, next = 1 }), nameOf)
            expectEqual(news.message, "Clean Ranarr weed is done. Next: Make Ranarr potion (unf).")
        end)
    end)

    describe("milestone", function()
        it("is true for a finished Step", function()
            local news = change(seen({ steps = { CLEAN, MAKE } }), seen({ steps = { MAKE } }))
            expectEqual(news.milestone, true)
        end)

        it("is false when only a Target changes", function()
            local news = change(seen({ targets = have(12) }), seen({ targets = have(40) }))
            expectEqual(news.milestone, false)
        end)

        it("is false when a Target is only used", function()
            local news = change(seen({ targets = have(40) }), seen({ targets = have(12) }))
            expectEqual(news.milestone, false)
        end)
    end)

    describe("highlights", function()
        it("gives new for the Next step, back and ready now for Steps, and up or down for Targets", function()
            local news = change(
                seen({ targets = have(20), steps = { SNAPDRAGON_WAITS, MIX_FLAGGED } }),
                seen({ targets = have(12), steps = { CLEAN, SNAPDRAGON, MIX }, next = 1 })
            )
            expectEqual(news.highlights, {
                next = "new",
                steps = { RANARR = "back", SNAPDRAGON_UNF = "ready now", SUPER_RESTORE_3 = "ready now" },
                targets = { [1] = "down" },
                assumed = {},
            })
        end)

        it("gives arrived for an Assumed line with less remaining", function()
            local news = change(
                seen({}, { { item = "SNAPE_GRASS", remaining = 50, arrived = 0, entered = 50 } }),
                seen({}, { { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 } })
            )
            expectEqual(news.highlights.assumed, { SNAPE_GRASS = "arrived" })
        end)

        it("gives nothing for an Assumed line that did not change", function()
            local line = { item = "SNAPE_GRASS", remaining = 14, arrived = 36, entered = 50 }
            local news = change(seen({}, { line }), seen({ targets = have(40) }, { line }))
            expectEqual(news.highlights.assumed, {})
        end)

        it("are new for each change", function()
            local news = change(seen({ targets = have(12) }), seen({ targets = have(40) }))
            News.see(news, seen({ targets = have(40), steps = { MAKE }, next = 1 }), nameOf)
            expectEqual(news.highlights.targets, {})
        end)
    end)

    describe("while the window is closed", function()
        it("gives no change", function()
            local news = News.new()
            News.open(news, seen({ steps = { CLEAN, MAKE } }), nameOf)
            News.close(news)
            News.see(news, seen({ steps = { MAKE } }), nameOf)
            expectEqual(news.message, nil)
        end)

        it("gives the changes since the window closed when it opens, with their highlights", function()
            local news = News.new()
            News.open(news, seen({ targets = have(12), steps = { CLEAN, MAKE, MIX } }), nameOf)
            News.close(news)
            News.see(news, seen({ targets = have(12), steps = { MAKE, MIX } }), nameOf)
            News.see(news, seen({ targets = have(20), steps = { MIX }, next = 1 }), nameOf)
            News.open(news, seen({ targets = have(20), steps = { MIX }, next = 1 }), nameOf)
            expectEqual(
                news.message,
                "Since you looked: You have 8 more Super restore (4). "
                    .. "Clean Ranarr weed and Make Ranarr potion (unf) are done. Next: Mix Super restore (3)."
            )
            expectEqual(news.highlights.targets, { [1] = "up" })
        end)

        it("gives no message at the first open", function()
            local news = News.new()
            News.open(news, seen({ steps = { MAKE } }), nameOf)
            expectEqual(news.message, nil)
        end)
    end)

    it("forgets the last Plan and the message at a reset", function()
        local news = change(seen({ steps = { CLEAN, MAKE } }), seen({ steps = { MAKE } }))
        News.reset(news)
        News.see(news, seen({ steps = {} }), nameOf)
        expectEqual(news.message, nil)
    end)
end)
