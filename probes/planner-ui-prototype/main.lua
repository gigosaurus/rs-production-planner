-- THROWAWAY PROTOTYPE: what should the Planner window look like, built with PrettyUI?
-- Variants of the same fake Plan, cycled with the floating "Prototype" bar
-- (Prev / Next). Nothing is read from the game and nothing is saved.
--   A  Document   - one scrolling page, collapsible sections in Plan order
--   B  Next step  - tabs, with the first unfinished Step front and centre
--   C  Icon board - item grids first, Shortages in a panel you can pop out
--   D  Hybrid     - A's list with icons, next Step pinned on top, pop-out Shortages
--   E  Pass 2     - D reworked against UX.md, plus E2-E4: bank not read, Complete, no Targets
--   F  Less verbose - E with each fact said once and detail moved into tooltips, plus F2-F4 states
--   G  Editing     - G1 inline, G2 item sheet, G3 set-up window
--   H  Editing, combined - F's view, in-place amounts/Assume, Options and Settings dialogs, Undo for all
--   J  Live updates - J1 highlight rows, J2 "just now" line, J3 game chat, J4 = J2 + J1 (chosen);
--                     driven by a Simulate window

local parent = ui.Interfaces:GetComponent(id.Component.TOPLEVEL_V2__PLUGIN_BUILD_LAYER_TOP)

local MUTED = 0xAFA27FFF
local FLAG = 0xE06C4CFF
local GOOD = 0x8FC66AFF
local NEXT = 0xFFCB05FF
local ROWS = { 0x24211EFF, 0x2E2825FF }

-- Fake Plan: 60 Super restore (4) and 40 Prayer potion (4), some stock already owned
local plan = {
    targets = {
        { name = "Super restore (4)", id = 3024, want = 60, have = 12 },
        { name = "Prayer potion (4)", id = 2434, want = 40, have = 0 },
    },
    -- inputs are per action; have is the output already in Stock; feeds is the Step that uses the output
    steps = {
        { verb = "Clean", name = "Grimy snapdragon", id = 3000, times = 24, batch = 28, have = 64, feeds = 2,
          inputs = { { name = "Grimy snapdragon", id = 3051, per = 1, have = 0 } } },
        { verb = "Make", name = "Snapdragon potion (unf)", id = 3004, times = 64, batch = 14, have = 0, feeds = 3,
          inputs = { { name = "Snapdragon", id = 3000, per = 1, have = 64 },
                     { name = "Vial of water", id = 227, per = 1, have = 92 } } },
        { verb = "Mix", name = "Super restore (3)", id = 3026, times = 64, batch = 14, have = 0, feeds = 7,
          flag = "Needs Herblore 63 (you have 61)", short = "Herblore 63",
          inputs = { { name = "Snapdragon potion (unf)", id = 3004, per = 1, have = 0 },
                     { name = "Red spiders' eggs", id = 223, per = 1, have = 12 } } },
        { verb = "Clean", name = "Grimy ranarr", id = 257, times = 54, batch = 28, have = 0, feeds = 5,
          inputs = { { name = "Grimy ranarr", id = 207, per = 1, have = 54 } } },
        { verb = "Make", name = "Ranarr potion (unf)", id = 99, times = 54, batch = 14, have = 0, feeds = 6,
          inputs = { { name = "Ranarr weed", id = 257, per = 1, have = 0 },
                     { name = "Vial of water", id = 227, per = 1, have = 92 } } },
        { verb = "Mix", name = "Prayer potion (3)", id = 139, times = 54, batch = 14, have = 0, feeds = 8,
          inputs = { { name = "Ranarr potion (unf)", id = 99, per = 1, have = 0 },
                     { name = "Snape grass", id = 231, per = 1, have = 40 } } },
        { verb = "Decant", name = "Super restore 64x(3) into 48x(4)", shortName = "Super restore into (4)", id = 3024, times = 1, decant = true, have = 12 },
        { verb = "Decant", name = "Prayer potion 54x(3) into 40x(4)", shortName = "Prayer potion into (4)", id = 2434, times = 1, decant = true, have = 0 },
    },
    firstUnfinished = 2, -- live recompute: step 1's products are already in Stock
    -- Snape grass is fully covered by Assumed stock, Vial of water only partly (issue 03)
    shortages = {
        { name = "Red spiders' eggs", id = 223, count = 52, have = 12, how = "buy" },
        { name = "Vial of water", id = 227, count = 6, have = 92, how = "buy" },
    },
    -- Unfulfilled Assumed stock: what is still counted as owned without being detected
    assumed = {
        { name = "Snape grass", id = 231, remaining = 14, arrived = 36, entered = 50 },
        { name = "Vial of water", id = 227, remaining = 20, arrived = 0, entered = 20 },
    },
    leftovers = {
        { name = "Prayer potion", id = 139, text = "2 doses" },
    },
    assumptions = {
        "Decanting is always possible (empty vials aren't tracked)",
        "Effects counted at zero (conservative)",
        "Bank snapshot from 4 minutes ago",
    },
}

local function obj(itemID)
    local ok, cfg = pcall(config.Obj.FromID, itemID)
    return ok and cfg or nil
end

local function loads(step)
    if step.decant then return "" end
    local n = math.ceil(step.times / step.batch)
    return n == 1 and "1 load" or (n .. " loads")
end

local function stepLine(i, step)
    local line = i .. ". " .. step.verb .. " "
    if not step.decant then line = line .. step.times .. "x " end
    line = line .. step.name
    local l = loads(step)
    if l ~= "" then line = line .. "  -  " .. l end
    return line
end

local function stepColour(i, step)
    if i < plan.firstUnfinished then return GOOD end
    if step.flag then return FLAG end
    return nil
end

local function remaining(t) return math.max(0, t.want - t.have) end

-- Shortages as a pop-out panel, so it can sit on screen at the GE or bank
local function addShortagesPanel(host, popoutX)
    local panel = host:AddPanel({
        popout = true, resizable = true, height = 100,
        popoutX = popoutX, popoutY = 80, popoutWidth = 220, popoutHeight = 100,
        popoutBackgroundAlpha = 0.8,
        rowBackgroundColours = ROWS,
    })
    panel:AddText({ text = "Shortages (" .. #plan.shortages .. ")", colour = MUTED })
    local items = {}
    for i, s in ipairs(plan.shortages) do
        local tip = s.how .. " " .. s.count .. "x " .. s.name
        if s.assumed then tip = tip .. " - " .. s.assumed end
        items[i] = { object = obj(s.id), quantity = s.count, tooltip = tip }
    end
    panel:AddItemGrid(items, { columns = #items, rows = 1, tooltip = true })
    return panel
end

---------------------------------------------------------------- Variant A: Document

local function VariantA()
    local w = prettyui.Window.new(parent, {
        title = "Production Planner",
        x = 60, y = 80, width = 400, height = 540,
        resizable = true, scrollable = true,
        rowBackgroundColours = ROWS,
    })

    w:AddTitle("Targets")
    for _, t in ipairs(plan.targets) do
        w:AddItemSlot(obj(t.id), { quantity = t.want, tooltip = t.name })
        w:AddText({ text = t.name .. "   " .. t.have .. " / " .. t.want, inline = true, offsetY = 8 })
    end

    local order = w:AddCollapseButton("Production order (" .. #plan.steps .. " steps)", {
        expanded = true, resizeParent = true,
    })
    for i, step in ipairs(plan.steps) do
        order:AddText({ text = stepLine(i, step), colour = stepColour(i, step) })
        if step.flag and i >= plan.firstUnfinished then
            order:AddText({ text = "     " .. step.flag, colour = FLAG })
        end
    end

    local short = w:AddCollapseButton("Shortages (" .. #plan.shortages .. ")", {
        expanded = true, resizeParent = true,
    })
    for _, s in ipairs(plan.shortages) do
        short:AddText(s.how .. " " .. s.count .. "x " .. s.name)
        if s.assumed then short:AddText({ text = "     " .. s.assumed, colour = MUTED }) end
    end

    local left = w:AddCollapseButton("Leftovers", { expanded = false, resizeParent = true })
    for _, l in ipairs(plan.leftovers) do left:AddText(l.name .. ": " .. l.text) end

    local assume = w:AddCollapseButton("Planning assumptions", { expanded = false, resizeParent = true })
    for _, a in ipairs(plan.assumptions) do assume:AddText({ text = a, colour = MUTED }) end

    w:RefreshRowBackgrounds()
    return w
end

---------------------------------------------------------------- Variant B: Next step

local function VariantB()
    local w = prettyui.Window.new(parent, {
        title = "Production Planner",
        x = 60, y = 80, width = 420, height = 440,
        resizable = true, scrollable = false,
    })

    local tabs = w:AddTabs({
        { text = "Now" }, { text = "Order" }, { text = "Shopping" }, { text = "Targets" },
    }, { height = 360, activeIndex = 1, rowBackgroundColours = ROWS })

    -- Now: the first Step not yet covered by Stock, with everything needed to do it
    local now = tabs:GetPage(1)
    local current = plan.firstUnfinished
    local heading = now:AddTitle("")
    local slot = now:AddItemSlot(nil, {})
    local detail = now:AddText({ text = "", inline = true, offsetY = 8 })
    local warn = now:AddText({ text = "", colour = FLAG })
    local after = now:AddText({ text = "", colour = MUTED })

    local function renderNow()
        local step = plan.steps[current]
        heading.content = "Next: " .. step.verb .. " " .. step.name
        slot:SetObject(obj(step.id), step.times)
        detail.content = step.decant and "Decant step" or
            (step.times .. " actions, " .. step.batch .. " per load, " .. loads(step))
        warn.content = step.flag or ""
        local nxt = plan.steps[current + 1]
        after.content = nxt and ("Then: " .. nxt.verb .. " " .. nxt.name) or "Last step"
    end
    renderNow()

    -- Prototype-only browsing; the real Plan advances from Stock, not from clicks
    now:AddSimpleButton("Prev", function()
        current = math.max(1, current - 1); renderNow()
    end, { marginTop = 16 })
    now:AddSimpleButton("Next", function()
        current = math.min(#plan.steps, current + 1); renderNow()
    end, { inline = true })

    local order = tabs:GetPage(2)
    for i, step in ipairs(plan.steps) do
        order:AddText({ text = stepLine(i, step), colour = stepColour(i, step) })
    end

    local shop = tabs:GetPage(3)
    shop:AddTitle("Buy")
    local items = {}
    for i, s in ipairs(plan.shortages) do
        items[i] = { object = obj(s.id), quantity = s.count, tooltip = s.name .. (s.assumed and (" - " .. s.assumed) or "") }
    end
    shop:AddItemGrid(items, { columns = 4, rows = 1, tooltip = true })
    for _, s in ipairs(plan.shortages) do
        shop:AddText(s.count .. "x " .. s.name)
    end

    local targets = tabs:GetPage(4)
    for _, t in ipairs(plan.targets) do
        targets:AddItemSlot(obj(t.id), { quantity = t.have, tooltip = t.name })
        targets:AddText({ text = t.name .. "  -  " .. remaining(t) .. " to go", inline = true, offsetY = 8 })
    end
    targets:AddTitle("Leftovers")
    for _, l in ipairs(plan.leftovers) do targets:AddText(l.name .. ": " .. l.text) end

    return w
end

---------------------------------------------------------------- Variant C: Icon board

local function VariantC()
    local w = prettyui.Window.new(parent, {
        title = "Planner",
        x = 60, y = 80, width = 300, height = 500,
        resizable = true, scrollable = true,
    })

    -- Targets as a grid, quantity shown is what's still to make
    local targetItems = {}
    for i, t in ipairs(plan.targets) do
        targetItems[i] = { object = obj(t.id), quantity = remaining(t), tooltip = t.name .. ": " .. t.have .. " / " .. t.want }
    end
    w:AddText({ text = "Still to make", colour = MUTED })
    w:AddItemGrid(targetItems, { columns = #targetItems, rows = 1, tooltip = true })

    addShortagesPanel(w, 380)

    -- Steps as icon rows: output icon + count, with a compact caption
    w:AddText({ text = "Steps", colour = MUTED, marginTop = 8 })
    for i, step in ipairs(plan.steps) do
        if i >= plan.firstUnfinished then
            w:AddItemSlot(obj(step.id), {
                quantity = step.decant and nil or step.times,
                tooltip = step.flag or stepLine(i, step),
                disabled = step.flag ~= nil,
            })
            w:AddText({
                text = step.verb .. " " .. step.name .. (step.decant and "" or ("  -  " .. loads(step))),
                colour = step.flag and FLAG or nil,
                inline = true, width = 220, height = 40,
            })
        end
    end

    return w
end

---------------------------------------------------------------- Variant D: Hybrid

-- A's single list as the spine, B's next Step pinned on top, icons on every
-- Step row (C), done Steps folded into one line, and C's pop-out Shortages
local function VariantD()
    local w = prettyui.Window.new(parent, {
        title = "Production Planner",
        x = 60, y = 80, width = 440, height = 580,
        resizable = true, scrollable = true,
        rowBackgroundColours = ROWS,
    })

    -- Next strip
    local nextStep = plan.steps[plan.firstUnfinished]
    local afterStep = plan.steps[plan.firstUnfinished + 1]
    w:AddText({ text = "NEXT", colour = NEXT })
    w:AddItemSlot(obj(nextStep.id), { quantity = nextStep.times, tooltip = nextStep.name })
    w:AddText({ text = nextStep.verb .. " " .. nextStep.times .. "x " .. nextStep.name, inline = true, offsetY = 8 })
    w:AddText({ text = nextStep.batch .. " per load, " .. loads(nextStep), colour = MUTED })
    if afterStep then
        w:AddText({ text = "Then: " .. afterStep.verb .. " " .. afterStep.name, colour = MUTED })
    end

    -- Targets, one compact row each, icon count is what's still to make
    w:AddTitle("Targets")
    for _, t in ipairs(plan.targets) do
        w:AddItemSlot(obj(t.id), { quantity = remaining(t), tooltip = t.name })
        w:AddText({ text = t.name .. "   " .. t.have .. " / " .. t.want, inline = true, offsetY = 8 })
    end

    addShortagesPanel(w, 460)

    -- Production order: finished Steps folded, the rest as icon rows
    w:AddTitle("Production order")
    local done = plan.firstUnfinished - 1
    if done > 0 then
        w:AddText({ text = done == 1 and "1 step done" or (done .. " steps done"), colour = GOOD })
    end
    for i = plan.firstUnfinished, #plan.steps do
        local step = plan.steps[i]
        w:AddItemSlot(obj(step.id), { quantity = (not step.decant) and step.times or nil, tooltip = step.name })
        local caption = i .. ". " .. step.verb .. " " .. step.name
        if not step.decant then caption = caption .. "  -  " .. loads(step) end
        local colour = (i == plan.firstUnfinished and NEXT) or (step.flag and FLAG) or nil
        w:AddText({ text = caption, colour = colour, inline = true, offsetY = 8 })
        if step.flag then w:AddText({ text = step.flag, colour = FLAG, x = 48, marginTop = -8 }) end
    end

    local left = w:AddCollapseButton("Leftovers", { expanded = false, resizeParent = true })
    for _, l in ipairs(plan.leftovers) do left:AddText(l.name .. ": " .. l.text) end

    local assume = w:AddCollapseButton("Planning assumptions", { expanded = false, resizeParent = true })
    for _, a in ipairs(plan.assumptions) do assume:AddText({ text = a, colour = MUTED }) end

    w:RefreshRowBackgrounds()
    return w
end

---------------------------------------------------------------- Variant E: Hybrid, UX pass 2

-- D reworked against UX.md: Next is the first Step you can actually finish and
-- shows what to withdraw, icon numbers always mean "you have", one heading style,
-- Shortages get their own section, counts on collapsed headers, bank age on top.
-- Also renders the empty, bank-not-read and Complete states.
local E_MUTED = 0xC8BC9AFF -- brighter than MUTED for readability
local E_FLAG = 0xFF8A6AFF
local E_NEXT = 0x7FC8F0FF   -- not gold, gold is for headings
local E_HELD = 0x8F8676FF   -- waiting Steps, dimmer than body text

-- The game never shows a count of 0 on an item, so neither do we
local function haveQty(n)
    return (n and n > 0) and n or nil
end

local function inventories(n)
    return n == 1 and "1 inventory" or (n .. " inventories")
end

-- A Step is held when it is Flagged, feeds a Flagged Step, or needs one finished first
local function flaggedDownstream(i)
    local step = plan.steps[i]
    if step.flag then return step end
    return step.feeds and flaggedDownstream(step.feeds) or nil
end

local function flaggedUpstream(i)
    for j, other in ipairs(plan.steps) do
        if other.feeds == i then
            if other.flag then return other end
            local up = flaggedUpstream(j)
            if up then return up end
        end
    end
    return nil
end

local function indexOf(step)
    for i, other in ipairs(plan.steps) do
        if other == step then return i end
    end
end

local function heldBy(i)
    return flaggedDownstream(i) or flaggedUpstream(i)
end

local function firstDoable()
    for i = plan.firstUnfinished, #plan.steps do
        if not heldBy(i) then return i end
    end
    return nil
end

local E_HEIGHTS = { empty = 200, complete = 400 }

local function VariantE(state)
    local w = prettyui.Window.new(parent, {
        title = "Production Planner",
        x = 60, y = 80, width = 440, height = E_HEIGHTS[state] or 600,
        resizable = true, scrollable = true,
    })

    -- The bank only matters if it has never been seen; players open theirs often
    -- enough that an old snapshot is never treated as stale
    if state == "nobank" then
        w:AddText({ text = "Bank not read yet. Open your bank once so stored items count.", colour = E_FLAG })
        w:AddText({ text = "Until then, Shortages only count your backpack and may be too high.", colour = E_MUTED })
    end

    if state == "empty" then
        w:AddTitle("No targets yet")
        w:AddText("Add the items you want to end up with and the planner works out what to make, buy and gather.")
        w:AddSimpleButton("Add target", function() log("[prototype] Add target (editing pass)") end, { marginTop = 8 })
        return w
    end

    if state == "complete" then
        w:AddTitle("Plan complete")
        w:AddText({ text = "You have everything you set out to make.", colour = E_MUTED })
        w:AddTitle("Targets")
        for _, t in ipairs(plan.targets) do
            w:AddItemSlot(obj(t.id), { quantity = t.want, tooltip = t.name })
            w:AddText({ text = t.name .. "   have " .. t.want .. " of " .. t.want, inline = true, offsetY = 8 })
        end
        w:AddText({ text = "Leftovers: Prayer potion, 2 doses", colour = E_MUTED, marginTop = 8 })
        w:AddSimpleButton("Clear targets", function()
            prettyui.Confirm.new(parent, {
                title = "Clear targets",
                body = "Remove all " .. #plan.targets .. " targets? The plan will be empty until you add new ones.",
                confirmLabel = "Clear",
                confirmVariant = "negative",
                onConfirm = function() log("[prototype] Targets cleared") end,
            })
        end, { marginTop = 8 })
        w:AddSimpleButton("Keep tracking", function() log("[prototype] Keep tracking targets") end, {
            inline = true,
            tooltip = "Keeps your targets, so the plan comes back if you use some of what you made",
        })
        return w
    end

    -- Do next: the Step, what to withdraw per inventory, and why anything was skipped
    local nextIndex = firstDoable()
    w:AddTitle("Do next")
    if nextIndex then
        local step = plan.steps[nextIndex]
        w:AddText({ text = step.verb .. " " .. step.times .. "x " .. step.name ..
            "  -  " .. inventories(math.ceil(step.times / step.batch)), colour = E_NEXT })
        w:AddText({ text = "Withdraw each inventory:", colour = E_MUTED })
        for k, input in ipairs(step.inputs) do
            local per = input.per * step.batch
            w:AddItemSlot(obj(input.id), { quantity = haveQty(input.have), tooltip = input.name .. ": you have " .. input.have, inline = k > 1 })
            w:AddText({ text = per .. " " .. input.name, inline = true, offsetY = 8, columnGap = 16 })
        end
        if nextIndex > plan.firstUnfinished then
            local blocker = heldBy(plan.firstUnfinished)
            w:AddText({
                text = "Skipped steps " .. plan.firstUnfinished .. "-" .. (nextIndex - 1) ..
                    ": they lead to " .. blocker.verb .. " " .. blocker.name .. ", which needs " .. blocker.short .. ".",
                colour = E_MUTED,
            })
        end
    else
        w:AddText({ text = "Nothing you can do yet. Every remaining step is held by a requirement below.", colour = E_FLAG })
    end

    -- Targets: icon shows what you have, text says have/of
    w:AddTitle("Targets")
    for _, t in ipairs(plan.targets) do
        w:AddItemSlot(obj(t.id), { quantity = haveQty(t.have), tooltip = t.name })
        w:AddText({ text = t.name .. "   have " .. t.have .. " of " .. t.want, inline = true, offsetY = 8 })
    end

    -- Shortages: own heading, readable list, buy/gather spelled out; the panel pops out
    w:AddTitle("Shortages (" .. #plan.shortages .. ")")
    local lines = #plan.shortages
    for _, s in ipairs(plan.shortages) do
        if s.assumed then lines = lines + 1 end
    end
    local panelHeight = lines * 26 + 44
    local panel = w:AddPanel({
        popout = true, resizable = true, height = panelHeight,
        popoutX = 520, popoutY = 80, popoutWidth = 280, popoutHeight = panelHeight,
        popoutBackgroundAlpha = 0.85,
        tooltip = "Pop out to keep on screen at the GE. Press again to put it back.",
    })
    for _, s in ipairs(plan.shortages) do
        panel:AddText({ text = (s.how == "buy" and "Buy " or "Gather ") .. s.count .. " " .. s.name ..
            "   (have " .. s.have .. ")" })
        if s.assumed then panel:AddText({ text = "   " .. s.assumed, colour = E_MUTED }) end
    end

    -- Production order: one line for done, NEXT marked in words, held Steps explain why
    w:AddTitle("Production order")
    local done = plan.firstUnfinished - 1
    if done > 0 then
        w:AddText({ text = done == 1 and "1 step done" or (done .. " steps done"), colour = GOOD })
    end
    for i = plan.firstUnfinished, #plan.steps do
        local step = plan.steps[i]
        w:AddItemSlot(obj(step.id), { quantity = haveQty(step.have), tooltip = step.name .. ": you have " .. step.have })
        local caption = i .. ". " .. step.verb .. " "
        if not step.decant then caption = caption .. step.times .. "x " end
        caption = caption .. step.name
        local colour
        if i == nextIndex then
            caption = "NEXT  " .. caption
            colour = E_NEXT
        elseif step.flag then
            colour = E_FLAG
        elseif heldBy(i) then
            colour = E_HELD
        end
        w:AddText({ text = caption, colour = colour, inline = true, offsetY = 8 })
        if step.flag then
            w:AddText({ text = step.flag, colour = E_FLAG, x = 62, marginTop = -14 })
        elseif heldBy(i) then
            local blocker = heldBy(i)
            w:AddText({ text = "Waiting: step " .. indexOf(blocker) .. " needs " .. blocker.short,
                colour = E_MUTED, x = 62, marginTop = -14 })
        end
    end

    local left = w:AddCollapseButton("Leftovers (" .. #plan.leftovers .. ")", { expanded = false, resizeParent = true })
    for _, l in ipairs(plan.leftovers) do left:AddText(l.name .. ": " .. l.text) end

    local notes = w:AddCollapseButton("How this was worked out (" .. (#plan.assumptions - 1) .. ")", {
        expanded = false, resizeParent = true,
    })
    -- The last assumption is the bank age, which E shows at the top instead
    for k = 1, #plan.assumptions - 1 do notes:AddText({ text = plan.assumptions[k], colour = E_MUTED }) end

    return w
end

---------------------------------------------------------------- Variant F: E, less verbose

-- Same information as E with each fact said once: no skip line, Waiting steps
-- point at their Flagged step on the same row, headings carry the repeated
-- words, and detail moves into tooltips. Also renders the other states.
local F_HEIGHTS = { empty = 200, complete = 380 }

local function addTargetsF(w, haveOf)
    w:AddTitle("Targets")
    for _, t in ipairs(plan.targets) do
        local have = haveOf(t)
        w:AddItemSlot(obj(t.id), { quantity = haveQty(have), tooltip = t.name })
        w:AddText({ text = t.name .. "   " .. have .. " of " .. t.want, inline = true, offsetY = 8 })
    end
end

local function VariantF(state)
    local w = prettyui.Window.new(parent, {
        title = "Production Planner",
        x = 60, y = 80, width = 440, height = F_HEIGHTS[state] or 600,
        resizable = true, scrollable = true,
    })

    if state == "empty" then
        w:AddTitle("No targets yet")
        w:AddText("Add the items you want to end up with and the planner works out what to make, buy and gather.")
        w:AddSimpleButton("Add target", function() log("[prototype] Add target (editing pass)") end, { marginTop = 8 })
        return w
    end

    if state == "complete" then
        w:AddTitle("Plan complete")
        addTargetsF(w, function(t) return t.want end)
        w:AddText({ text = "Left over: 2 doses of Prayer potion", colour = E_MUTED, marginTop = 8 })
        w:AddSimpleButton("Clear targets", function()
            prettyui.Confirm.new(parent, {
                title = "Clear targets",
                body = "Remove all " .. #plan.targets .. " targets? The plan will be empty until you add new ones.",
                confirmLabel = "Clear",
                confirmVariant = "negative",
                onConfirm = function() log("[prototype] Targets cleared") end,
            })
        end, { marginTop = 8 })
        w:AddSimpleButton("Keep tracking", function() log("[prototype] Keep tracking targets") end, {
            inline = true,
            tooltip = "Keeps your targets, so the plan comes back if you use some of what you made",
        })
        return w
    end

    if state == "nobank" then
        w:AddText({ text = "Bank not read yet. Open it once so stored items count.", colour = E_FLAG })
        w:AddText({ text = "Until then, amounts to buy may be too high.", colour = E_MUTED })
    end

    local nextIndex = firstDoable()
    w:AddTitle("Do next")
    if nextIndex then
        local step = plan.steps[nextIndex]
        w:AddText({ text = step.verb .. " " .. step.times .. "x " .. step.name ..
            " (" .. inventories(math.ceil(step.times / step.batch)) .. ")", colour = E_NEXT })
        for k, input in ipairs(step.inputs) do
            w:AddItemSlot(obj(input.id), { quantity = haveQty(input.have), tooltip = input.name .. ": you have " .. input.have })
            local line = (input.per * step.batch) .. " " .. input.name
            if k == #step.inputs then line = line .. " per inventory" end
            w:AddText({ text = line, inline = true, offsetY = 8 })
        end
    else
        w:AddText({ text = "Nothing you can do yet", colour = E_FLAG })
    end

    addTargetsF(w, function(t) return t.have end)

    -- One heading per kind of Shortage, so the verb isn't repeated on each line
    for _, how in ipairs({ "buy", "gather" }) do
        local group = {}
        for _, sh in ipairs(plan.shortages) do
            if sh.how == how then group[#group + 1] = sh end
        end
        if #group > 0 then
            w:AddTitle((how == "buy" and "Buy" or "Gather") .. " (" .. #group .. ")")
            local panelHeight = #group * 26 + 38
            local panel = w:AddPanel({
                popout = true, resizable = true, height = panelHeight,
                popoutX = 520, popoutY = 80, popoutWidth = 260, popoutHeight = panelHeight,
                popoutBackgroundAlpha = 0.85,
                tooltip = "Pop out to keep on screen at the GE. Press again to put it back.",
            })
            for _, sh in ipairs(group) do
                panel:AddText({ text = sh.count .. " " .. sh.name, tooltip = "You have " .. sh.have })
            end
        end
    end

    -- Assumed stock gets its own section and is never repeated on a Buy line (issue 03)
    if #plan.assumed > 0 then
        w:AddTitle("Assumed (" .. #plan.assumed .. ")")
        local panelHeight = #plan.assumed * 26 + 38
        local panel = w:AddPanel({
            popout = true, resizable = true, height = panelHeight,
            popoutX = 520, popoutY = 240, popoutWidth = 260, popoutHeight = panelHeight,
            popoutBackgroundAlpha = 0.85,
            tooltip = "Counted as owned until it shows up in your backpack or bank.",
        })
        for _, a in ipairs(plan.assumed) do
            local line = a.remaining .. " " .. a.name
            if a.arrived > 0 then line = line .. "   (" .. a.arrived .. " of " .. a.entered .. " arrived)" end
            panel:AddText({ text = line, colour = E_MUTED })
        end
    end

    -- One row per Step; action counts live in the tooltip and Do next
    w:AddTitle("Production order")
    local done = plan.firstUnfinished - 1
    if done > 0 then
        w:AddText({ text = done == 1 and "1 step done" or (done .. " steps done"), colour = GOOD })
    end
    for i = plan.firstUnfinished, #plan.steps do
        local step = plan.steps[i]
        local full = stepLine(i, step)
        w:AddItemSlot(obj(step.id), { quantity = haveQty(step.have), tooltip = full })
        local caption = i .. ". " .. step.verb .. " " .. (step.shortName or step.name)
        local blocker = heldBy(i)
        if i == nextIndex then
            w:AddText({ text = "NEXT  " .. caption, colour = E_NEXT, inline = true, offsetY = 8, tooltip = full })
        elseif step.flag then
            w:AddText({ text = caption .. "  -  needs " .. step.short, colour = E_FLAG,
                inline = true, offsetY = 8, tooltip = step.flag })
        elseif blocker then
            -- Dim caption, but the reason stays readable
            w:AddText({ text = caption, colour = E_HELD, inline = true, offsetY = 8, columnGap = 6, tooltip = full })
            w:AddText({ text = "-  waits on " .. indexOf(blocker), colour = E_MUTED, inline = true, offsetY = 8,
                tooltip = "Step " .. indexOf(blocker) .. " needs " .. blocker.short })
        else
            w:AddText({ text = caption, inline = true, offsetY = 8, tooltip = full })
        end
    end

    local left = w:AddCollapseButton("Leftovers (" .. #plan.leftovers .. ")", { expanded = false, resizeParent = true })
    for _, l in ipairs(plan.leftovers) do left:AddText(l.name .. ": " .. l.text) end

    local notes = w:AddCollapseButton("How this was worked out (" .. (#plan.assumptions - 1) .. ")", {
        expanded = false, resizeParent = true,
    })
    for k = 1, #plan.assumptions - 1 do notes:AddText({ text = plan.assumptions[k], colour = E_MUTED }) end

    return w
end

---------------------------------------------------------------- Variants G1-G3: editing

-- THROWAWAY PROTOTYPE: where should editing the Plan live?
-- Three structurally different answers, all on top of F's Plan view:
--   G1  Inline      - edit in place: quantity fields, search, recipe dropdowns,
--                     "Assume" on Buy lines, settings at the bottom; applies at once, with Undo
--   G2  Item sheet  - read-only view, "Edit" on every item opens one dialog with
--                     everything about that item; Cancel or Save
--   G3  Set-up window - read-only view plus a separate tabbed window of forms;
--                     applies at once
-- Edits change the fake Plan's Targets, Assumed stock and settings, but the Plan
-- itself is NOT recalculated: Steps and Shortages stay as they were.

local function makeEditing(ctx)
    local parent, plan, obj, haveQty = ctx.parent, ctx.plan, ctx.obj, ctx.haveQty
    local C = ctx.colours

    ------------------------------------------------------------ editable state

    -- Items you can search for when adding a Target, Assumed stock or a Reserve
    local catalogue = {
        { name = "Super restore (4)", id = 3024 }, { name = "Prayer potion (4)", id = 2434 },
        { name = "Super attack (4)", id = 2436 }, { name = "Super strength (4)", id = 2440 },
        { name = "Super defence (4)", id = 2442 }, { name = "Super energy (4)", id = 3016 },
        { name = "Saradomin brew (4)", id = 6685 }, { name = "Antifire (4)", id = 2452 },
        { name = "Ranarr potion (unf)", id = 99 }, { name = "Snapdragon potion (unf)", id = 3004 },
        { name = "Vial of water", id = 227 }, { name = "Snape grass", id = 231 },
        { name = "Red spiders' eggs", id = 223 },
    }

    -- Items with more than one Recipe (made-up alternatives, for the shape of the UI)
    local recipes = {
        [3026] = { name = "Super restore (3)", options = {
            { id = 1, label = "Mix it (needs Herblore 63)" },
            { id = 2, label = "Buy Super restore (4) instead" },
        } },
        [139] = { name = "Prayer potion (3)", options = {
            { id = 1, label = "Mix it" },
            { id = 2, label = "Mix at a Botanist's workbench (needs unlock)", unlock = "Botanist's workbench" },
        } },
    }

    local edit = {
        recipe = {},          -- item id -> chosen option id (absent = Default recipe)
        unlocks = { ["Botanist's workbench"] = false },
        reserves = { { id = 3024, name = "Super restore (4)", keep = 10 } },
        mode = "conservative",
        itemMode = {},        -- item id -> "conservative" | "expected" (absent = same as everything else)
        account = "regular",
        status = nil,         -- last change, shown so every action has visible feedback
        undo = nil,
    }

    local function nameOf(itemID)
        for _, c in ipairs(catalogue) do if c.id == itemID then return c.name end end
        for _, t in ipairs(plan.targets) do if t.id == itemID then return t.name end end
        if recipes[itemID] then return recipes[itemID].name end
        for _, step in ipairs(plan.steps) do if step.id == itemID then return step.name end end
        return "Item " .. itemID
    end

    local function findTarget(itemID)
        for i, t in ipairs(plan.targets) do if t.id == itemID then return t, i end end
    end

    local function findAssumed(itemID)
        for i, a in ipairs(plan.assumed) do if a.id == itemID then return a, i end end
    end

    local function findReserve(itemID)
        for i, r in ipairs(edit.reserves) do if r.id == itemID then return r, i end end
    end

    local function quantity(field, text)
        local q = field and field.root and field.root.contentQuantity
        return q or tonumber(text)
    end

    local function search(text, exclude)
        local results = {}
        local needle = string.lower(text or "")
        if needle == "" then return results end
        for _, c in ipairs(catalogue) do
            if string.find(string.lower(c.name), needle, 1, true) and not (exclude and exclude(c.id)) then
                results[#results + 1] = { label = c.name, id = c.id }
            end
        end
        return results
    end

    local function logState()
        local parts = {}
        for _, t in ipairs(plan.targets) do parts[#parts + 1] = t.name .. "=" .. t.want end
        local assumed = {}
        for _, a in ipairs(plan.assumed) do assumed[#assumed + 1] = a.name .. "=" .. a.remaining end
        local reserves = {}
        for _, r in ipairs(edit.reserves) do reserves[#reserves + 1] = r.name .. "=" .. r.keep end
        log("[planner-ui-prototype] targets{" .. table.concat(parts, ", ") .. "} assumed{" ..
            table.concat(assumed, ", ") .. "} reserves{" .. table.concat(reserves, ", ") ..
            "} mode=" .. edit.mode .. " account=" .. edit.account)
    end

    ------------------------------------------------------------ rebuilding

    -- Windows are rebuilt on the next frame, never from inside their own callbacks.
    -- Each part remembers where it was dragged to.
    local active

    local function newController(parts)
        local ctrl = { parts = parts, pending = {} }
        function ctrl.refresh(name)
            if name then ctrl.pending[name] = true
            else for key in pairs(ctrl.parts) do ctrl.pending[key] = true end end
        end
        function ctrl.rebuild(name)
            local part = ctrl.parts[name]
            local pos
            if part.win and part.win.root then pos = { x = part.win.root.x, y = part.win.root.y } end
            if part.win then part.win:Destroy() end
            part.win = part.build(pos or part.pos)
        end
        function ctrl:Destroy()
            prettyui.Dialog.dismissAll(parent)
            for _, part in pairs(ctrl.parts) do
                if part.win then part.win:Destroy(); part.win = nil end
            end
            if active == ctrl then active = nil end
        end
        for name in pairs(parts) do ctrl.rebuild(name) end
        active = ctrl
        return ctrl
    end

    Event.Draw.Subscribe("planner-ui-prototype-rebuild", function()
        if not active then return end
        for name in pairs(active.pending) do
            active.pending[name] = nil
            active.rebuild(name)
        end
    end)

    local function changed(ctrl, message, undo, which)
        edit.typingKey = nil
        edit.status = message
        edit.undo = undo
        logState()
        ctrl.refresh(which)
    end

    ------------------------------------------------------------ Plan view (F) with hooks

    -- F's layout. Each hook replaces or extends one kind of row; without hooks it's F, read-only.
    local function renderPlan(w, hooks)
        hooks = hooks or {}
        if hooks.top then hooks.top(w) end

        local nextIndex = ctx.firstDoable()
        w:AddTitle("Do next")
        if nextIndex then
            local step = plan.steps[nextIndex]
            w:AddText({ text = step.verb .. " " .. step.times .. "x " .. step.name ..
                " (" .. ctx.inventories(math.ceil(step.times / step.batch)) .. ")", colour = C.NEXT })
            for k, input in ipairs(step.inputs) do
                w:AddItemSlot(obj(input.id), { quantity = haveQty(input.have), tooltip = input.name .. ": you have " .. input.have })
                local line = (input.per * step.batch) .. " " .. input.name
                if k == #step.inputs then line = line .. " per inventory" end
                w:AddText({ text = line, inline = true, offsetY = 8 })
            end
        end

        w:AddTitle("Targets")
        if hooks.targetsTop then hooks.targetsTop(w) end
        for _, t in ipairs(plan.targets) do
            w:AddItemSlot(obj(t.id), { quantity = haveQty(t.have), tooltip = t.name })
            if hooks.targetRow then hooks.targetRow(w, t)
            else w:AddText({ text = t.name .. "   " .. t.have .. " of " .. t.want, inline = true, offsetY = 8 }) end
        end

        if #plan.shortages > 0 then
            w:AddTitle((edit.account == "ironman" and "Gather" or "Buy") .. " (" .. #plan.shortages .. ")")
            local panel = w:AddPanel({
                popout = true, resizable = true, height = #plan.shortages * (hooks.buyRow and 36 or 26) + 38,
                popoutX = 560, popoutY = 80, popoutWidth = 300, popoutHeight = #plan.shortages * 34 + 38,
                popoutBackgroundAlpha = 0.85,
            })
            for _, sh in ipairs(plan.shortages) do
                if hooks.buyRow then hooks.buyRow(panel, sh)
                else panel:AddText({ text = sh.count .. " " .. sh.name, tooltip = "You have " .. sh.have }) end
            end
        end

        if #plan.assumed > 0 then
            w:AddTitle("Assumed (" .. #plan.assumed .. ")")
            local panel = w:AddPanel({
                popout = true, resizable = true, height = #plan.assumed * (hooks.assumedRow and 36 or 26) + 38,
                popoutX = 560, popoutY = 260, popoutWidth = 300, popoutHeight = #plan.assumed * 34 + 38,
                popoutBackgroundAlpha = 0.85,
                tooltip = "Counted as owned until it shows up in your backpack or bank.",
            })
            for _, a in ipairs(plan.assumed) do
                if hooks.assumedRow then hooks.assumedRow(panel, a)
                else
                    local line = a.remaining .. " " .. a.name
                    if a.arrived > 0 then line = line .. "   (" .. a.arrived .. " of " .. a.entered .. " arrived)" end
                    panel:AddText({ text = line, colour = C.MUTED })
                end
            end
        end

        w:AddTitle("Production order")
        local done = plan.firstUnfinished - 1
        if done > 0 then
            w:AddText({ text = done == 1 and "1 step done" or (done .. " steps done"), colour = C.GOOD })
        end
        for i = plan.firstUnfinished, #plan.steps do
            local step = plan.steps[i]
            local full = ctx.stepLine(i, step)
            w:AddItemSlot(obj(step.id), { quantity = haveQty(step.have), tooltip = full })
            local caption = i .. ". " .. step.verb .. " " .. (step.shortName or step.name)
            if edit.recipe[step.id] and edit.recipe[step.id] ~= 1 then caption = caption .. "  (your recipe)" end
            local blocker = ctx.heldBy(i)
            if i == nextIndex then
                w:AddText({ text = "NEXT  " .. caption, colour = C.NEXT, inline = true, offsetY = 8, tooltip = full })
            elseif step.flag then
                w:AddText({ text = caption .. "  -  needs " .. step.short, colour = C.FLAG,
                    inline = true, offsetY = 8, tooltip = step.flag })
            elseif blocker then
                w:AddText({ text = caption, colour = C.HELD, inline = true, offsetY = 8, columnGap = 6, tooltip = full })
                w:AddText({ text = "-  waits on " .. ctx.indexOf(blocker), colour = C.MUTED, inline = true, offsetY = 8,
                    tooltip = "Step " .. ctx.indexOf(blocker) .. " needs " .. blocker.short })
            else
                w:AddText({ text = caption, inline = true, offsetY = 8, tooltip = full })
            end
            if hooks.stepRow then hooks.stepRow(w, i, step) end
        end

        if hooks.bottom then hooks.bottom(w) end
    end

    local function planWindow(pos, title, width)
        return prettyui.Window.new(parent, {
            title = title or "Production Planner",
            x = pos and pos.x or 60, y = pos and pos.y or 80,
            width = width or 440, height = 640,
            resizable = true, scrollable = true,
        })
    end

    -- Prototype-only line saying what just changed, with Undo when it can be undone.
    -- Kept as references so typing can update them without a rebuild (which would steal focus).
    local statusText, undoButton

    local function addStatus(w)
        w:AddText({ text = "Prototype: the plan isn't recalculated after edits.", colour = C.MUTED })
        statusText = w:AddText({
            text = edit.status and ("Changed: " .. edit.status) or "No changes yet",
            colour = C.GOOD, width = 300,
        })
        undoButton = w:AddSimpleButton("Undo", function()
            local undo = edit.undo
            if not undo then return end
            edit.undo = nil
            undo()
            -- The first build runs before the controller exists, so use whichever is active now
            changed(active, "undone")
        end, { inline = true, disabled = edit.undo == nil })
    end

    -- A change made by typing. One Undo covers the whole run of typing in a field,
    -- going back to the value from before the first keystroke.
    local function typed(key, message, undo)
        edit.status = message
        if edit.typingKey ~= key then
            edit.typingKey = key
            edit.undo = undo
        end
        if statusText then statusText.content = "Changed: " .. message end
        if undoButton then undoButton:SetDisabled(false) end
        logState()
    end

    local function addSearch(host, placeholder, exclude, onPick)
        local list
        host:AddTextField({
            placeholder = placeholder,
            onChange = function(_, _, text)
                if list then list:SetEntries(search(text, exclude)) end
            end,
        })
        list = host:AddList({
            height = 84,
            entries = {},
            onChange = function(_, itemID, selected)
                if selected then onPick(itemID) end
            end,
        })
        return list
    end

    local function addSettings(host, onChange)
        host:AddText({ text = "Planning", colour = C.MUTED })
        host:AddRadioButton({
            { text = "Conservative", value = "conservative",
              tooltip = "Count chances to save Inputs or make extra at zero, so you never come up short" },
            { text = "Expected", value = "expected",
              tooltip = "Count those chances at their average, so you buy less but may come up short" },
        }, {
            inline = true, selectedValue = edit.mode,
            onChange = function(_, value) onChange("planning set to " .. value, function() edit.mode = value end) end,
        })
        host:AddText({ text = "Account", colour = C.MUTED })
        host:AddRadioButton({
            { text = "Regular", value = "regular" },
            { text = "Ironman", value = "ironman", tooltip = "Shortages are listed as things to gather, not buy" },
        }, {
            inline = true, selectedValue = edit.account,
            onChange = function(_, value) onChange("account set to " .. value, function() edit.account = value end) end,
        })
        host:AddText({ text = "Unlocks you have", colour = C.MUTED })
        host:AddCheckboxButton({
            { text = "Botanist's workbench", value = "Botanist's workbench", selected = edit.unlocks["Botanist's workbench"] },
        }, {
            onChange = function(_, _, value, selected)
                onChange((selected and "have " or "don't have ") .. value, function() edit.unlocks[value] = selected end)
            end,
        })
    end

    ------------------------------------------------------------ G1: Inline

    local function G1()
        local ctrl
        local function apply(message, fn, undo)
            fn()
            changed(ctrl, message, undo)
        end

        local function build(pos)
            local w = planWindow(pos, nil, 460)
            renderPlan(w, {
                top = function(host) addStatus(host) end,

                targetsTop = function(host)
                    addSearch(host, "Add a target: type an item name", function(itemID) return findTarget(itemID) end,
                        function(itemID)
                            local t = { name = nameOf(itemID), id = itemID, want = 1, have = 0 }
                            apply("added target " .. t.name, function() table.insert(plan.targets, t) end,
                                function() local _, i = findTarget(itemID); if i then table.remove(plan.targets, i) end end)
                        end)
                end,

                targetRow = function(host, t)
                    host:AddText({ text = t.name .. "   " .. t.have .. " of", inline = true, offsetY = 8, width = 200 })
                    local before = t.want
                    host:AddTextField({
                        text = tostring(t.want), filterMode = ui.InputFieldFilterMode.QUANTITY,
                        inline = true, width = 70, tooltip = "How many you want. Accepts 1k and 1m.",
                        -- Applies as you type; no rebuild so the field keeps focus
                        onChange = function(field, _, text)
                            local q = quantity(field, text)
                            if q and q > 0 then
                                t.want = q
                                typed("target" .. t.id, t.name .. " target " .. q, function() t.want = before end)
                            end
                        end,
                    })
                    host:AddSimpleButton("Remove", function()
                        local _, i = findTarget(t.id)
                        apply("removed target " .. t.name, function() table.remove(plan.targets, i) end,
                            function() table.insert(plan.targets, i, t) end)
                    end, { inline = true })
                end,

                buyRow = function(panel, sh)
                    panel:AddText({ text = sh.count .. " " .. sh.name, tooltip = "You have " .. sh.have })
                    panel:AddSimpleButton("Assume", function()
                        local a = { name = sh.name, id = sh.id, remaining = sh.count, arrived = 0, entered = sh.count }
                        local i
                        for k, other in ipairs(plan.shortages) do if other == sh then i = k end end
                        apply("assuming " .. sh.count .. " " .. sh.name, function()
                            table.remove(plan.shortages, i); table.insert(plan.assumed, a)
                        end, function()
                            local _, j = findAssumed(a.id); table.remove(plan.assumed, j); table.insert(plan.shortages, i, sh)
                        end)
                    end, { inline = true, tooltip = "Count these as owned, for example because you're about to buy them" })
                end,

                assumedRow = function(panel, a)
                    local line = a.remaining .. " " .. a.name
                    if a.arrived > 0 then line = line .. "   (" .. a.arrived .. " of " .. a.entered .. " arrived)" end
                    panel:AddText({ text = line, colour = C.MUTED })
                    panel:AddSimpleButton("Remove", function()
                        local _, i = findAssumed(a.id)
                        apply("stopped assuming " .. a.name, function() table.remove(plan.assumed, i) end,
                            function() table.insert(plan.assumed, i, a) end)
                    end, { inline = true })
                end,

                -- A Recipe dropdown under any Step that has alternatives; it's also the answer to a flag
                stepRow = function(host, _, step)
                    local r = recipes[step.id]
                    if not r then return end
                    local before = edit.recipe[step.id]
                    host:AddComboBox({
                        entries = r.options, selectedID = before or 1, x = 62, width = 340,
                        tooltip = "How this item is made",
                        onChange = function(_, optionID, label)
                            apply("recipe for " .. r.name .. ": " .. label,
                                function() edit.recipe[step.id] = optionID end,
                                function() edit.recipe[step.id] = before end)
                        end,
                    })
                end,

                bottom = function(host)
                    host:AddTitle("Keep back")
                    for _, res in ipairs(edit.reserves) do
                        host:AddText({ text = res.name, offsetY = 8, width = 248 })
                        local before = res.keep
                        host:AddTextField({
                            text = tostring(res.keep), filterMode = ui.InputFieldFilterMode.QUANTITY,
                            inline = true, width = 70, tooltip = "Never used by the plan",
                            onChange = function(field, _, text)
                                local q = quantity(field, text)
                                if q then
                                    res.keep = q
                                    typed("reserve" .. res.id, "keeping back " .. q .. " " .. res.name, function() res.keep = before end)
                                end
                            end,
                        })
                        host:AddSimpleButton("Remove", function()
                            local _, i = findReserve(res.id)
                            apply("no longer keeping back " .. res.name, function() table.remove(edit.reserves, i) end,
                                function() table.insert(edit.reserves, i, res) end)
                        end, { inline = true })
                    end
                    addSearch(host, "Keep back another item", function(itemID) return findReserve(itemID) end,
                        function(itemID)
                            local res = { id = itemID, name = nameOf(itemID), keep = 1 }
                            apply("keeping back " .. res.name, function() table.insert(edit.reserves, res) end,
                                function() local _, i = findReserve(itemID); table.remove(edit.reserves, i) end)
                        end)

                    host:AddTitle("Settings")
                    addSettings(host, function(message, fn)
                        local snapshot = { mode = edit.mode, account = edit.account, workbench = edit.unlocks["Botanist's workbench"] }
                        apply(message, fn, function()
                            edit.mode, edit.account = snapshot.mode, snapshot.account
                            edit.unlocks["Botanist's workbench"] = snapshot.workbench
                        end)
                    end)
                end,
            })
            return w
        end

        ctrl = newController({ plan = { build = build } })
        return ctrl
    end

    ------------------------------------------------------------ G2: Item sheet

    local function G2()
        local ctrl

        -- One dialog with everything about one item. Nothing changes until Save.
        local function openSheet(itemID, opts)
            opts = opts or {}
            local name = nameOf(itemID)
            local target = findTarget(itemID)
            local assumed = findAssumed(itemID)
            local reserve = findReserve(itemID)
            local r = recipes[itemID] and { id = itemID, rec = recipes[itemID] }
            local draft = {
                want = target and target.want or (opts.newTarget and 1 or nil),
                assume = assumed and assumed.remaining or nil,
                keep = reserve and reserve.keep or nil,
                recipe = r and (edit.recipe[r.id] or 1) or nil,
                mode = edit.itemMode[itemID] or "default",
            }
            -- An emptied field means 0, which removes that setting on Save
            local function qtyField(win, label, key, placeholder, hint)
                win:AddText({ text = label, colour = C.MUTED })
                win:AddTextField({
                    text = draft[key] and tostring(draft[key]) or "", placeholder = placeholder,
                    filterMode = ui.InputFieldFilterMode.QUANTITY, width = 120,
                    tooltip = hint,
                    onChange = function(field, _, text) draft[key] = quantity(field, text) or 0 end,
                })
            end
            prettyui.Dialog.new(parent, {
                title = name, width = 380, height = 470,
                content = function(win)
                    qtyField(win, "Target", "want", "Not a target", "How many you want to end up with")
                    if r then
                        win:AddText({ text = "Recipe", colour = C.MUTED })
                        win:AddComboBox({
                            entries = r.rec.options, selectedID = draft.recipe,
                            onChange = function(_, optionID) draft.recipe = optionID end,
                        })
                    end
                    qtyField(win, "Assume I have", "assume", "0", "Counted as owned until it shows up in your backpack or bank")
                    qtyField(win, "Keep back", "keep", "0", "Never used by the plan")
                    win:AddText({ text = "Planning for this item", colour = C.MUTED })
                    win:AddRadioButton({
                        { text = "Same as everything else", value = "default" },
                        { text = "Conservative", value = "conservative" },
                        { text = "Expected", value = "expected" },
                    }, {
                        selectedValue = draft.mode,
                        onChange = function(_, value) draft.mode = value end,
                    })
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Save", variant = "positive", onClick = function()
                        local want, assume, keep = draft.want, draft.assume, draft.keep
                        local t, ti = findTarget(itemID)
                        if want and want > 0 then
                            if t then t.want = want else table.insert(plan.targets, { name = name, id = itemID, want = want, have = 0 }) end
                        elseif t then table.remove(plan.targets, ti) end
                        local a, ai = findAssumed(itemID)
                        if assume and assume > 0 then
                            if a then a.remaining = assume else table.insert(plan.assumed, { name = name, id = itemID, remaining = assume, arrived = 0, entered = assume }) end
                        elseif a then table.remove(plan.assumed, ai) end
                        local res, ri = findReserve(itemID)
                        if keep and keep > 0 then
                            if res then res.keep = keep else table.insert(edit.reserves, { id = itemID, name = name, keep = keep }) end
                        elseif res then table.remove(edit.reserves, ri) end
                        if r then edit.recipe[r.id] = draft.recipe end
                        edit.itemMode[itemID] = draft.mode ~= "default" and draft.mode or nil
                        changed(ctrl, "saved " .. name)
                        return true
                    end },
                },
            })
        end

        local function openAddTarget()
            local dialog
            dialog = prettyui.Dialog.new(parent, {
                title = "Add target", width = 360, height = 260,
                content = function(win)
                    addSearch(win, "Type an item name", function(itemID) return findTarget(itemID) end, function(itemID)
                        dialog:Destroy()
                        openSheet(itemID, { newTarget = true })
                    end)
                end,
                actions = { { label = "Cancel", variant = "neutral" } },
            })
        end

        local function openSettings()
            local draft = { mode = edit.mode, account = edit.account, workbench = edit.unlocks["Botanist's workbench"] }
            prettyui.Dialog.new(parent, {
                title = "Planner settings", width = 380, height = 330,
                content = function(win)
                    addSettings(win, function(_, fn)
                        -- Apply to a copy, so Cancel leaves the real settings alone
                        local saved = { mode = edit.mode, account = edit.account, workbench = edit.unlocks["Botanist's workbench"] }
                        edit.mode, edit.account, edit.unlocks["Botanist's workbench"] = draft.mode, draft.account, draft.workbench
                        fn()
                        draft.mode, draft.account, draft.workbench = edit.mode, edit.account, edit.unlocks["Botanist's workbench"]
                        edit.mode, edit.account, edit.unlocks["Botanist's workbench"] = saved.mode, saved.account, saved.workbench
                    end)
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Save", variant = "positive", onClick = function()
                        edit.mode, edit.account, edit.unlocks["Botanist's workbench"] = draft.mode, draft.account, draft.workbench
                        changed(ctrl, "settings saved")
                        return true
                    end },
                },
            })
        end

        local function editButton(host, itemID)
            host:AddSimpleButton("Edit", function() openSheet(itemID) end, { inline = true, tooltip = "Change anything about this item" })
        end

        local function build(pos)
            local w = planWindow(pos, nil, 480)
            renderPlan(w, {
                top = function(host)
                    addStatus(host)
                    host:AddSimpleButton("Add target", openAddTarget)
                    host:AddSimpleButton("Settings", openSettings, { inline = true })
                end,
                targetRow = function(host, t)
                    host:AddText({ text = t.name .. "   " .. t.have .. " of " .. t.want, inline = true, offsetY = 8 })
                    editButton(host, t.id)
                end,
                buyRow = function(panel, sh)
                    panel:AddText({ text = sh.count .. " " .. sh.name, tooltip = "You have " .. sh.have })
                    editButton(panel, sh.id)
                end,
                assumedRow = function(panel, a)
                    local line = a.remaining .. " " .. a.name
                    if a.arrived > 0 then line = line .. "   (" .. a.arrived .. " of " .. a.entered .. " arrived)" end
                    panel:AddText({ text = line, colour = C.MUTED })
                    editButton(panel, a.id)
                end,
                stepRow = function(host, _, step)
                    if recipes[step.id] then editButton(host, step.id) end
                end,
            })
            return w
        end

        ctrl = newController({ plan = { build = build } })
        return ctrl
    end

    ------------------------------------------------------------ G3: Set-up window

    local function G3()
        local ctrl
        local activeTab = 1

        local function apply(message, fn, which)
            fn()
            changed(ctrl, message, nil, which)
        end

        local function buildPlan(pos)
            local w = planWindow(pos)
            renderPlan(w, {
                top = function(host)
                    addStatus(host)
                    host:AddSimpleButton("Set up plan", function()
                        local setup = ctrl.parts.setup
                        if not setup.win then return end
                        if setup.win and setup.win.root and setup.win.root.hidden ~= true then setup.win:Close() else setup.win:Show() end
                    end, { tooltip = "Targets, recipes, stock and settings" })
                end,
            })
            return w
        end

        local function qtyRow(page, name, value, onValue, onRemove, hint)
            page:AddText({ text = name, offsetY = 8, width = 200 })
            page:AddTextField({
                text = tostring(value), filterMode = ui.InputFieldFilterMode.QUANTITY,
                inline = true, width = 80, tooltip = hint,
                onChange = function(field, _, text)
                    local q = quantity(field, text)
                    if q then onValue(q) end
                end,
            })
            page:AddSimpleButton("Remove", onRemove, { inline = true })
        end

        local function buildSetup(pos)
            local w = prettyui.Window.new(parent, {
                title = "Set up plan",
                x = pos and pos.x or 520, y = pos and pos.y or 80,
                width = 420, height = 520, resizable = true, scrollable = false,
            })
            local tabs = w:AddTabs({ { text = "Targets" }, { text = "Recipes" }, { text = "Stock" }, { text = "Settings" } }, {
                height = 460, activeIndex = activeTab,
                onChange = function(_, index) activeTab = index end,
            })

            local targets = tabs:GetPage(1)
            targets:AddText({ text = "What you want to end up with.", colour = C.MUTED })
            for _, t in ipairs(plan.targets) do
                local before = t.want
                qtyRow(targets, t.name, t.want,
                    function(q)
                        t.want = q
                        typed("target" .. t.id, t.name .. " target " .. q, function() t.want = before end)
                        ctrl.refresh("plan")
                    end,
                    function()
                        local _, i = findTarget(t.id)
                        apply("removed target " .. t.name, function() table.remove(plan.targets, i) end)
                    end, "How many you want. Accepts 1k and 1m.")
            end
            addSearch(targets, "Add a target: type an item name", function(itemID) return findTarget(itemID) end, function(itemID)
                apply("added target " .. nameOf(itemID), function()
                    table.insert(plan.targets, { name = nameOf(itemID), id = itemID, want = 1, have = 0 })
                end)
            end)

            local recipePage = tabs:GetPage(2)
            recipePage:AddText({ text = "Only items with more than one recipe are listed.", colour = C.MUTED })
            for stepItem, rec in pairs(recipes) do
                recipePage:AddText(rec.name)
                recipePage:AddComboBox({
                    entries = rec.options, selectedID = edit.recipe[stepItem] or 1,
                    onChange = function(_, optionID, label)
                        apply("recipe for " .. rec.name .. ": " .. label, function() edit.recipe[stepItem] = optionID end, "plan")
                    end,
                })
            end

            local stock = tabs:GetPage(3)
            stock:AddTitle("Assumed")
            stock:AddText({ text = "Counted as owned until it shows up in your backpack or bank.", colour = C.MUTED })
            for _, a in ipairs(plan.assumed) do
                local before = a.remaining
                qtyRow(stock, a.name, a.remaining,
                    function(q)
                        a.remaining = q
                        typed("assumed" .. a.id, "assuming " .. q .. " " .. a.name, function() a.remaining = before end)
                        ctrl.refresh("plan")
                    end,
                    function()
                        local _, i = findAssumed(a.id)
                        apply("stopped assuming " .. a.name, function() table.remove(plan.assumed, i) end)
                    end)
            end
            addSearch(stock, "Assume another item", function(itemID) return findAssumed(itemID) end, function(itemID)
                apply("assuming 1 " .. nameOf(itemID), function()
                    table.insert(plan.assumed, { name = nameOf(itemID), id = itemID, remaining = 1, arrived = 0, entered = 1 })
                end)
            end)
            stock:AddTitle("Keep back")
            stock:AddText({ text = "Never used by the plan.", colour = C.MUTED })
            for _, res in ipairs(edit.reserves) do
                local before = res.keep
                qtyRow(stock, res.name, res.keep,
                    function(q)
                        res.keep = q
                        typed("reserve" .. res.id, "keeping back " .. q .. " " .. res.name, function() res.keep = before end)
                        ctrl.refresh("plan")
                    end,
                    function()
                        local _, i = findReserve(res.id)
                        apply("no longer keeping back " .. res.name, function() table.remove(edit.reserves, i) end)
                    end)
            end
            addSearch(stock, "Keep back another item", function(itemID) return findReserve(itemID) end, function(itemID)
                apply("keeping back " .. nameOf(itemID), function()
                    table.insert(edit.reserves, { id = itemID, name = nameOf(itemID), keep = 1 })
                end)
            end)

            local settings = tabs:GetPage(4)
            addSettings(settings, function(message, fn) apply(message, fn, "plan") end)
            return w
        end

        ctrl = newController({ plan = { build = buildPlan }, setup = { build = buildSetup } })
        return ctrl
    end

    ------------------------------------------------------------ H: best of G1-G3

    -- F's clean Plan view with the frequent edits in place (target amounts, Assume,
    -- Remove assumed), rarer per-item settings in an Options dialog, a Settings dialog
    -- for global choices and every Recipe, and Undo for everything via snapshots.
    local function H()
        local ctrl

        local function copy(value)
            if type(value) ~= "table" then return value end
            local out = {}
            for k, v in pairs(value) do out[k] = copy(v) end
            return out
        end

        -- Everything an edit can touch, so any change (including a dialog Save) can be undone
        local function snapshot()
            local saved = {
                targets = copy(plan.targets), assumed = copy(plan.assumed), shortages = copy(plan.shortages),
                recipe = copy(edit.recipe), unlocks = copy(edit.unlocks), reserves = copy(edit.reserves),
                mode = edit.mode, itemMode = copy(edit.itemMode), account = edit.account,
            }
            return function()
                local function refill(list, from)
                    for k = #list, 1, -1 do list[k] = nil end
                    for k, v in ipairs(from) do list[k] = copy(v) end
                end
                refill(plan.targets, saved.targets)
                refill(plan.assumed, saved.assumed)
                refill(plan.shortages, saved.shortages)
                refill(edit.reserves, saved.reserves)
                edit.recipe, edit.unlocks, edit.itemMode = copy(saved.recipe), copy(saved.unlocks), copy(saved.itemMode)
                edit.mode, edit.account = saved.mode, saved.account
            end
        end

        local function apply(message, fn)
            local undo = snapshot()
            fn()
            changed(ctrl, message, undo)
        end

        -- "keeping back 10 X", or "keeping back 10 X and 2 more"; nil when nothing changed
        local function describe(changes)
            if #changes == 0 then return nil end
            if #changes == 1 then return changes[1] end
            return changes[1] .. " and " .. (#changes - 1) .. " more"
        end

        local MODE_NAMES = { conservative = "Conservative", expected = "Expected" }

        -- Search list that starts with every item, so it is never an empty box
        local function addItemPicker(win, exclude, onPick)
            local function entries(text)
                local out = {}
                local needle = string.lower(text or "")
                for _, c in ipairs(catalogue) do
                    if not exclude(c.id) and (needle == "" or string.find(string.lower(c.name), needle, 1, true)) then
                        out[#out + 1] = { label = c.name, id = c.id }
                    end
                end
                return out
            end
            local list
            win:AddTextField({
                placeholder = "Type to narrow the list",
                onChange = function(_, _, text) if list then list:SetEntries(entries(text)) end end,
            })
            list = win:AddList({
                height = 5 * 24 + 4, entryHeight = 24, entries = entries(""), maxSelected = 1,
                onChange = function(_, itemID, selected) if selected then onPick(itemID) end end,
            })
        end

        local function dropdown(win, label, entries, selectedID, onChange)
            win:AddText({ text = label, colour = C.MUTED })
            win:AddComboBox({ entries = entries, selectedID = selectedID, onChange = function(_, id) onChange(id) end })
        end

        local function flaggedStep(itemID)
            for _, step in ipairs(plan.steps) do
                if step.id == itemID and step.flag then return step end
            end
        end

        -- Opened from a Flagged step: just the reason and the Recipe choice
        local function openRecipeFix(itemID)
            local name, rec, step = nameOf(itemID), recipes[itemID], flaggedStep(itemID)
            local chosen = edit.recipe[itemID] or 1
            prettyui.Dialog.new(parent, {
                title = name, width = 400, height = 230,
                content = function(win)
                    if step then win:AddText({ text = step.flag, colour = C.FLAG }) end
                    win:AddText({ text = "Choose another way to get it, or train and come back.", colour = C.MUTED })
                    dropdown(win, "How it's made", rec.options, chosen, function(id) chosen = id end)
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Save", variant = "positive", onClick = function()
                        if chosen ~= (edit.recipe[itemID] or 1) then
                            apply(name .. ": " .. rec.options[chosen].label, function() edit.recipe[itemID] = chosen end)
                        end
                        return true
                    end },
                },
            })
        end

        -- Per-item settings. Nothing changes until Save, and Save can be undone.
        local function openOptions(itemID)
            local name = nameOf(itemID)
            local target = findTarget(itemID)
            local assumed = findAssumed(itemID)
            local reserve = findReserve(itemID)
            local rec = recipes[itemID]
            local before = {
                assume = assumed and assumed.remaining or 0,
                keep = reserve and reserve.keep or 0,
                recipe = rec and (edit.recipe[itemID] or 1) or nil,
                mode = edit.itemMode[itemID] or "default",
            }
            local draft = copy(before)
            draft.removeTarget = false
            local function qtyField(win, label, key, hint)
                win:AddText({ text = label, colour = C.MUTED })
                win:AddTextField({
                    text = draft[key] > 0 and tostring(draft[key]) or "", placeholder = "none",
                    filterMode = ui.InputFieldFilterMode.QUANTITY, width = 120, tooltip = hint,
                    onChange = function(field, _, text) draft[key] = quantity(field, text) or 0 end,
                })
            end
            prettyui.Dialog.new(parent, {
                title = name, width = 400, height = rec and 430 or 360,
                content = function(win)
                    qtyField(win, "Assume I have", "assume", "Counted as owned until it shows up in your backpack or bank")
                    qtyField(win, "Keep back", "keep", "Never used by the plan")
                    dropdown(win, "Planning for this item", {
                        { label = "Same as everything else (" .. MODE_NAMES[edit.mode] .. ")", id = 1 },
                        { label = "Conservative: count bonus chances as zero", id = 2 },
                        { label = "Expected: count bonus chances at their average", id = 3 },
                    }, ({ default = 1, conservative = 2, expected = 3 })[draft.mode], function(id)
                        draft.mode = ({ "default", "conservative", "expected" })[id]
                    end)
                    if rec then
                        dropdown(win, "How it's made", rec.options, draft.recipe, function(id) draft.recipe = id end)
                    end
                    if target then
                        win:AddCheckboxButton({ { text = "Remove from targets", value = "remove" } }, {
                            onChange = function(_, _, _, selected) draft.removeTarget = selected end,
                        })
                    end
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Save", variant = "positive", onClick = function()
                        local changes = {}
                        if draft.removeTarget then changes[#changes + 1] = "removed " .. name .. " from targets" end
                        if draft.assume ~= before.assume then
                            changes[#changes + 1] = draft.assume > 0 and ("assuming " .. draft.assume .. " " .. name) or ("stopped assuming " .. name)
                        end
                        if draft.keep ~= before.keep then
                            changes[#changes + 1] = draft.keep > 0 and ("keeping back " .. draft.keep .. " " .. name) or ("no longer keeping back " .. name)
                        end
                        if draft.mode ~= before.mode then
                            changes[#changes + 1] = "planning for " .. name .. ": " .. (MODE_NAMES[draft.mode] or "same as everything else")
                        end
                        if rec and draft.recipe ~= before.recipe then
                            changes[#changes + 1] = name .. ": " .. rec.options[draft.recipe].label
                        end
                        local message = describe(changes)
                        if not message then return true end
                        apply(message, function()
                            local a, ai = findAssumed(itemID)
                            if draft.assume > 0 then
                                if a then a.remaining = draft.assume
                                else table.insert(plan.assumed, { name = name, id = itemID, remaining = draft.assume, arrived = 0, entered = draft.assume }) end
                            elseif a then table.remove(plan.assumed, ai) end
                            local res, ri = findReserve(itemID)
                            if draft.keep > 0 then
                                if res then res.keep = draft.keep
                                else table.insert(edit.reserves, { id = itemID, name = name, keep = draft.keep }) end
                            elseif res then table.remove(edit.reserves, ri) end
                            if rec then edit.recipe[itemID] = draft.recipe end
                            edit.itemMode[itemID] = draft.mode ~= "default" and draft.mode or nil
                            if draft.removeTarget then
                                local _, ti = findTarget(itemID)
                                if ti then table.remove(plan.targets, ti) end
                            end
                        end)
                        return true
                    end },
                },
            })
        end

        -- One dialog: pick from a list that starts full, say how many, Add
        local function openAddTarget()
            local picked, want = nil, 1
            local label, dialog
            local function add()
                if not picked then
                    if label then label.content = "Pick an item first" end
                    return false
                end
                apply("added " .. want .. " " .. nameOf(picked) .. " as a target", function()
                    table.insert(plan.targets, { name = nameOf(picked), id = picked, want = want, have = 0 })
                end)
                return true
            end
            dialog = prettyui.Dialog.new(parent, {
                title = "Add target", width = 380, height = 360,
                content = function(win)
                    addItemPicker(win, function(itemID) return findTarget(itemID) end, function(itemID)
                        picked = itemID
                        if label then label.content = "Add: " .. nameOf(itemID) end
                    end)
                    label = win:AddText({ text = "Pick an item above", colour = C.MUTED })
                    win:AddText({ text = "How many", colour = C.MUTED })
                    win:AddTextField({
                        text = "1", filterMode = ui.InputFieldFilterMode.QUANTITY, width = 120,
                        tooltip = "Accepts 1k and 1m. Press Enter to add.",
                        onChange = function(field, _, text) want = quantity(field, text) or want end,
                        onSubmit = function() if add() and dialog then dialog:Destroy() end end,
                    })
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Add", variant = "positive", onClick = add },
                },
            })
        end

        -- Global choices plus every item with more than one Recipe. Dropdowns, not
        -- square radio buttons, so each reads as a single choice.
        local function openSettings()
            local draft = {
                mode = edit.mode, account = edit.account, workbench = edit.unlocks["Botanist's workbench"],
                recipe = copy(edit.recipe), reserves = copy(edit.reserves),
            }
            prettyui.Dialog.new(parent, {
                title = "Planner settings", width = 420, height = 600,
                content = function(win)
                    dropdown(win, "Planning", {
                        { label = "Conservative: count bonus chances as zero", id = 1 },
                        { label = "Expected: count bonus chances at their average", id = 2 },
                    }, draft.mode == "expected" and 2 or 1, function(id) draft.mode = id == 2 and "expected" or "conservative" end)
                    dropdown(win, "Account", {
                        { label = "Regular: shortages are things to buy", id = 1 },
                        { label = "Ironman: shortages are things to gather", id = 2 },
                    }, draft.account == "ironman" and 2 or 1, function(id) draft.account = id == 2 and "ironman" or "regular" end)
                    win:AddText({ text = "Unlocks you have", colour = C.MUTED })
                    win:AddCheckboxButton({
                        { text = "Botanist's workbench", value = "workbench", selected = draft.workbench },
                    }, { onChange = function(_, _, _, selected) draft.workbench = selected end })
                    win:AddTitle("Recipes")
                    win:AddText({ text = "Only items with more than one way to make them.", colour = C.MUTED })
                    for itemID, rec in pairs(recipes) do
                        dropdown(win, rec.name, rec.options, draft.recipe[itemID] or 1, function(id) draft.recipe[itemID] = id end)
                    end
                    -- Everything kept back in one place; amounts are set from each item's Options
                    win:AddTitle("Kept back")
                    if #draft.reserves == 0 then
                        win:AddText({ text = "Nothing. Use an item's Options to keep some back.", colour = C.MUTED })
                    end
                    for _, res in ipairs(draft.reserves) do
                        win:AddText({ text = res.keep .. " " .. res.name, width = 250, offsetY = 4 })
                        win:AddSimpleButton("Remove", function(_, active) res.removed = active end, {
                            inline = true, toggleable = true, tooltip = "Removed when you press Save",
                        })
                    end
                end,
                actions = {
                    { label = "Cancel", variant = "neutral" },
                    { label = "Save", variant = "positive", onClick = function()
                        local changes = {}
                        if draft.mode ~= edit.mode then changes[#changes + 1] = "planning: " .. MODE_NAMES[draft.mode] end
                        if draft.account ~= edit.account then changes[#changes + 1] = "account: " .. draft.account end
                        if draft.workbench ~= edit.unlocks["Botanist's workbench"] then
                            changes[#changes + 1] = (draft.workbench and "have " or "don't have ") .. "Botanist's workbench"
                        end
                        for itemID, rec in pairs(recipes) do
                            if (draft.recipe[itemID] or 1) ~= (edit.recipe[itemID] or 1) then
                                changes[#changes + 1] = rec.name .. ": " .. rec.options[draft.recipe[itemID]].label
                            end
                        end
                        local kept = {}
                        for _, res in ipairs(draft.reserves) do
                            if res.removed then changes[#changes + 1] = "no longer keeping back " .. res.name
                            else kept[#kept + 1] = { id = res.id, name = res.name, keep = res.keep } end
                        end
                        local message = describe(changes)
                        if not message then return true end
                        apply(message, function()
                            edit.mode, edit.account = draft.mode, draft.account
                            edit.unlocks["Botanist's workbench"] = draft.workbench
                            edit.recipe = draft.recipe
                            for k = #edit.reserves, 1, -1 do edit.reserves[k] = nil end
                            for k, res in ipairs(kept) do edit.reserves[k] = res end
                        end)
                        return true
                    end },
                },
            })
        end

        local function build(pos)
            local w = planWindow(pos, nil, 460)
            renderPlan(w, {
                top = function(host)
                    addStatus(host)
                    host:AddSimpleButton("Add target", openAddTarget)
                    host:AddSimpleButton("Settings", openSettings, { inline = true })
                end,

                targetRow = function(host, t)
                    host:AddText({ text = t.name .. "   " .. t.have .. " of", inline = true, offsetY = 8, width = 200 })
                    local undo = snapshot()
                    host:AddTextField({
                        text = tostring(t.want), filterMode = ui.InputFieldFilterMode.QUANTITY,
                        inline = true, width = 70, tooltip = "How many you want. Accepts 1k and 1m.",
                        onChange = function(field, _, text)
                            local q = quantity(field, text)
                            if q and q > 0 then
                                t.want = q
                                typed("target" .. t.id, t.name .. " target " .. q, undo)
                            end
                        end,
                    })
                    host:AddSimpleButton("Options", function() openOptions(t.id) end, {
                        inline = true, tooltip = "Recipe, assumed stock, keep back, planning, remove",
                    })
                end,

                buyRow = function(panel, sh)
                    panel:AddText({ text = sh.count .. " " .. sh.name, tooltip = "You have " .. sh.have, width = 250 })
                    panel:AddSimpleButton("Assume", function()
                        apply("assuming " .. sh.count .. " more " .. sh.name, function()
                            for k, other in ipairs(plan.shortages) do
                                if other.id == sh.id then table.remove(plan.shortages, k) break end
                            end
                            -- One line per item: add to an existing assumption rather than starting another
                            local a = findAssumed(sh.id)
                            if a then
                                a.remaining, a.entered = a.remaining + sh.count, a.entered + sh.count
                            else
                                table.insert(plan.assumed, { name = sh.name, id = sh.id, remaining = sh.count, arrived = 0, entered = sh.count })
                            end
                        end)
                    end, { inline = true, tooltip = "Count these as owned, for example because you're about to buy them" })
                end,

                assumedRow = function(panel, a)
                    local line = a.remaining .. " " .. a.name
                    if a.arrived > 0 then line = line .. "  (" .. a.arrived .. "/" .. a.entered .. " arrived)" end
                    panel:AddText({ text = line, colour = C.MUTED, width = 250 })
                    panel:AddSimpleButton("Remove", function()
                        apply("stopped assuming " .. a.name, function()
                            local _, i = findAssumed(a.id)
                            if i then table.remove(plan.assumed, i) end
                        end)
                    end, { inline = true })
                end,

                -- Only Flagged steps get an action, and it goes straight to the fix
                stepRow = function(host, _, step)
                    if step.flag and recipes[step.id] then
                        host:AddSimpleButton("Change recipe", function() openRecipeFix(step.id) end, {
                            x = 62, tooltip = "Choose another way to make this, such as buying it instead",
                        })
                    end
                end,
            })
            return w
        end

        ctrl = newController({ plan = { build = build } })
        return ctrl
    end

    return {
        G1 = G1, G2 = G2, G3 = G3, H = H,
        Shutdown = function()
            if active then active:Destroy() end
            Event.Draw.Unsubscribe("planner-ui-prototype-rebuild")
        end,
    }
end

local Editing = makeEditing({
    parent = parent, plan = plan, obj = obj, haveQty = haveQty,
    firstDoable = firstDoable, heldBy = heldBy, indexOf = indexOf,
    inventories = inventories, stepLine = stepLine,
    colours = { NEXT = E_NEXT, FLAG = E_FLAG, HELD = E_HELD, MUTED = E_MUTED, GOOD = GOOD },
})

---------------------------------------------------------------- Variants J1-J3: live updates

-- THROWAWAY PROTOTYPE: how does the player notice what a live recalculation changed?
-- A "Simulate" window fakes Stock changes on its own copy of the Plan; the three
-- variants differ only in how they tell the player what happened:
--   J1  Highlight - changed rows light up for a few seconds, with a word saying why
--   J2  Just now  - one sentence at the top saying what the last change did
--   J3  Chat      - milestones go to the game chat (optional chatAccess); window stays quiet
-- The simulation is hand-written, not a real Plan calculation.
local function makeLive(ctx)
    local parent, obj, haveQty, inventories, C = ctx.parent, ctx.obj, ctx.haveQty, ctx.inventories, ctx.colours
    local HIGHLIGHT = 0xFFF0A0FF
    local HIGHLIGHT_SECONDS = 4

    local function copy(value)
        if type(value) ~= "table" then return value end
        local out = {}
        for k, v in pairs(value) do out[k] = copy(v) end
        return out
    end

    local S -- simulated Plan

    local function reset()
        S = {
            targets = {
                { name = "Super restore (4)", id = 3024, want = 60, have = 12 },
                { name = "Prayer potion (4)", id = 2434, want = 40, have = 0 },
            },
            steps = copy(ctx.plan.steps),
            shortages = {
                { name = "Red spiders' eggs", id = 223, count = 52, have = 12 },
                { name = "Vial of water", id = 227, count = 6, have = 92 },
            },
            assumed = {
                { name = "Snape grass", id = 231, remaining = 14, arrived = 36, entered = 50 },
            },
        }
        for i, step in ipairs(S.steps) do
            step.done = i == 1
            step.progress = 0
        end
    end
    reset()

    ------------------------------------------------------------ Plan rules (same as F, over S)

    local function indexOf(step)
        for i, other in ipairs(S.steps) do if other == step then return i end end
    end

    local function flaggedDownstream(i)
        local step = S.steps[i]
        if step.flag and not step.done then return step end
        return step.feeds and flaggedDownstream(step.feeds) or nil
    end

    local function flaggedUpstream(i)
        for j, other in ipairs(S.steps) do
            if other.feeds == i and not other.done then
                if other.flag then return other end
                local up = flaggedUpstream(j)
                if up then return up end
            end
        end
    end

    local function heldBy(i) return flaggedDownstream(i) or flaggedUpstream(i) end

    local function firstDoable()
        for i, step in ipairs(S.steps) do
            if not step.done and not step.flag and not heldBy(i) then return i end
        end
    end

    local function left(step) return step.times - step.progress end

    local function complete()
        for _, t in ipairs(S.targets) do if t.have < t.want then return false end end
        return true
    end

    ------------------------------------------------------------ describing a change

    -- A picture of everything the player might notice changing
    local function summary()
        local sum = { next = firstDoable(), done = {}, waiting = {}, flagged = {}, assumed = {}, shortages = {}, targets = {}, complete = complete() }
        for i, step in ipairs(S.steps) do
            if step.done then sum.done[i] = true
            elseif step.flag then sum.flagged[i] = true
            elseif heldBy(i) then sum.waiting[i] = true end
        end
        for _, a in ipairs(S.assumed) do sum.assumed[a.id] = { remaining = a.remaining, name = a.name } end
        for _, sh in ipairs(S.shortages) do sum.shortages[sh.id] = sh.name end
        for _, t in ipairs(S.targets) do sum.targets[t.id] = t.have end
        return sum
    end

    local function listSteps(indices)
        table.sort(indices)
        if #indices == 1 then return "Step " .. indices[1] end
        local last = table.remove(indices)
        return "Steps " .. table.concat(indices, ", ") .. " and " .. last
    end

    -- Sentences for the player, plus which rows to highlight and the word to show on each.
    -- Milestones are the sentences worth interrupting for (J3 sends only those to chat).
    local function describe(before, after)
        local sentences, keys = {}, {}
        local function say(text, milestone) sentences[#sentences + 1] = { text = text, milestone = milestone } end

        if after.complete and not before.complete then say("Plan complete: you have everything you set out to make.", true) end

        -- Using up a Target is one sentence that also says what it undid
        local used = {}
        for _, t in ipairs(S.targets) do
            local was = before.targets[t.id]
            if t.have < was then used[#used + 1] = (was - t.have) .. " " .. t.name end
        end

        local newlyDone, back, ready = {}, {}, {}
        for i in pairs(after.done) do if not before.done[i] then newlyDone[#newlyDone + 1] = i end end
        for i in pairs(before.done) do if not after.done[i] then back[#back + 1] = i; keys["step:" .. i] = "back" end end
        for i in pairs(before.waiting) do if not after.waiting[i] and not after.done[i] then ready[#ready + 1] = i; keys["step:" .. i] = "ready now" end end
        for i in pairs(before.flagged) do if not after.flagged[i] and not after.done[i] then ready[#ready + 1] = i; keys["step:" .. i] = "ready now" end end
        if #newlyDone > 0 then
            say(listSteps(newlyDone) .. " done.", true)
            keys["done"] = "+" .. #newlyDone
        end
        if #used > 0 then
            local consequence
            if #back > 0 then consequence = ", so " .. string.lower(listSteps(back)) .. (#back == 1 and " is" or " are") .. " back"
            elseif before.complete and not after.complete then consequence = ", so the plan isn't complete any more" end
            say("You used " .. table.concat(used, " and ") .. (consequence or "") .. ".", consequence ~= nil)
        elseif #back > 0 then
            say(listSteps(back) .. (#back == 1 and " is" or " are") .. " back.", true)
        end
        if #ready > 0 then say(listSteps(ready) .. " can go ahead now.", true) end

        if after.next ~= before.next then
            if after.next then
                local step = S.steps[after.next]
                local jumped = before.next and after.next < before.next
                say((jumped and "Next moved back to " or "Next: ") .. after.next .. ". " .. step.verb .. " " .. (step.shortName or step.name) .. ".", true)
                keys["next"] = "new"
            elseif not after.complete then
                say("Nothing you can do yet.", true)
            end
        end

        for id, was in pairs(before.assumed) do
            local now = after.assumed[id]
            if not now then say("All your assumed " .. was.name .. " has arrived.", true)
            elseif now.remaining < was.remaining then
                say((was.remaining - now.remaining) .. " assumed " .. was.name .. " arrived.", false)
                keys["assumed:" .. id] = "arrived"
            end
        end
        for id, name in pairs(before.shortages) do
            if not after.shortages[id] then say("You have enough " .. name .. " now.", true) end
        end
        for _, t in ipairs(S.targets) do
            local was = before.targets[t.id]
            if t.have ~= was then
                keys["target:" .. t.id] = t.have > was and "up" or "down"
            end
        end
        -- Completing the Plan is the whole story; the details would only be noise
        if after.complete and not before.complete then sentences = { sentences[1] } end
        return sentences, keys
    end

    ------------------------------------------------------------ the variants

    local active

    local function chatAllowed()
        local ok, allowed = pcall(function() return Plugin.HasPermission(PluginPermissions.chatAccess) end)
        return ok and allowed
    end

    local function newLive(mode)
        local ctrl = { mode = mode, sentences = nil, keys = {}, timer = 0, pending = false }

        local function rowColour(key, normal)
            if ctrl.keys[key] then return HIGHLIGHT end
            return normal
        end

        local function tag(key)
            local word = ctrl.keys[key]
            return word and ("  -  " .. word) or ""
        end

        local function addSentences(w, prefix)
            local parts = {}
            for _, s in ipairs(ctrl.sentences) do parts[#parts + 1] = s.text end
            w:AddText({ text = prefix .. table.concat(parts, " "), colour = C.GOOD })
        end

        local function buildPlan(pos)
            local w = prettyui.Window.new(parent, {
                title = "Production Planner",
                x = pos and pos.x or 60, y = pos and pos.y or 80,
                width = 440, height = 640, resizable = true, scrollable = true,
            })

            if (mode == "line" or mode == "both") and ctrl.sentences then
                addSentences(w, "Just now: ")
                w:AddSimpleButton("Dismiss", function() ctrl.sentences = nil; ctrl.pending = true end)
            elseif mode == "chat" and ctrl.sentences and not chatAllowed() then
                w:AddText({ text = "Chat permission is off, so updates show here instead.", colour = C.MUTED })
                addSentences(w, "")
            end

            if complete() then
                w:AddTitle("Plan complete")
                for _, t in ipairs(S.targets) do
                    w:AddItemSlot(obj(t.id), { quantity = haveQty(t.have), tooltip = t.name })
                    w:AddText({ text = t.name .. "   " .. t.have .. " of " .. t.want .. tag("target:" .. t.id),
                        colour = rowColour("target:" .. t.id), inline = true, offsetY = 8 })
                end
                return w
            end

            local nextIndex = firstDoable()
            w:AddTitle("Do next")
            if nextIndex and S.steps[nextIndex].decant then
                -- Decant steps have no inventories or Inputs to withdraw
                local step = S.steps[nextIndex]
                w:AddText({ text = "Decant " .. step.name .. tag("next"), colour = rowColour("next", C.NEXT) })
            elseif nextIndex then
                local step = S.steps[nextIndex]
                local invsLeft = math.ceil(left(step) / step.batch)
                w:AddText({ text = step.verb .. " " .. step.times .. "x " .. step.name .. tag("next"),
                    colour = rowColour("next", C.NEXT) })
                if step.progress > 0 then
                    -- Only what's left: no stored progress (ADR 0003)
                    w:AddText({ text = left(step) .. " left, " .. inventories(invsLeft), colour = C.MUTED })
                else
                    w:AddText({ text = inventories(invsLeft), colour = C.MUTED })
                end
                for k, input in ipairs(step.inputs) do
                    w:AddItemSlot(obj(input.id), { quantity = haveQty(input.have), tooltip = input.name .. ": you have " .. input.have })
                    local line = (input.per * step.batch) .. " " .. input.name
                    if k == #step.inputs then line = line .. " per inventory" end
                    w:AddText({ text = line, inline = true, offsetY = 8 })
                end
            else
                w:AddText({ text = "Nothing you can do yet", colour = C.FLAG })
            end

            w:AddTitle("Targets")
            for _, t in ipairs(S.targets) do
                w:AddItemSlot(obj(t.id), { quantity = haveQty(t.have), tooltip = t.name })
                w:AddText({ text = t.name .. "   " .. t.have .. " of " .. t.want .. tag("target:" .. t.id),
                    colour = rowColour("target:" .. t.id), inline = true, offsetY = 8 })
            end

            if #S.shortages > 0 then
                w:AddTitle("Buy (" .. #S.shortages .. ")")
                local panel = w:AddPanel({ popout = true, height = #S.shortages * 26 + 38, popoutWidth = 260, popoutHeight = #S.shortages * 26 + 38 })
                for _, sh in ipairs(S.shortages) do panel:AddText(sh.count .. " " .. sh.name) end
            end
            if #S.assumed > 0 then
                w:AddTitle("Assumed (" .. #S.assumed .. ")")
                local panel = w:AddPanel({ popout = true, height = #S.assumed * 26 + 38, popoutWidth = 260, popoutHeight = #S.assumed * 26 + 38 })
                for _, a in ipairs(S.assumed) do
                    local key = "assumed:" .. a.id
                    panel:AddText({ text = a.remaining .. " " .. a.name .. "  (" .. a.arrived .. "/" .. a.entered .. " arrived)" .. tag(key),
                        colour = rowColour(key, C.MUTED) })
                end
            end

            w:AddTitle("Production order")
            local done = 0
            for _, step in ipairs(S.steps) do if step.done then done = done + 1 end end
            if done > 0 then
                w:AddText({ text = (done == 1 and "1 step done" or (done .. " steps done")) .. tag("done"), colour = rowColour("done", C.GOOD) })
            end
            for i, step in ipairs(S.steps) do
                if not step.done then
                    local key = "step:" .. i
                    w:AddItemSlot(obj(step.id), { quantity = haveQty(step.have), tooltip = step.name })
                    local caption = i .. ". " .. step.verb .. " " .. (step.shortName or step.name)
                    if step.progress > 0 then caption = caption .. "  (" .. left(step) .. " left)" end
                    local blocker = heldBy(i)
                    if i == nextIndex then
                        w:AddText({ text = "NEXT  " .. caption .. tag(key), colour = rowColour(key, C.NEXT), inline = true, offsetY = 8 })
                    elseif step.flag then
                        w:AddText({ text = caption .. "  -  needs " .. step.short, colour = C.FLAG, inline = true, offsetY = 8 })
                    elseif blocker then
                        w:AddText({ text = caption, colour = C.HELD, inline = true, offsetY = 8, columnGap = 6 })
                        w:AddText({ text = "-  waits on " .. indexOf(blocker), colour = C.MUTED, inline = true, offsetY = 8 })
                    else
                        w:AddText({ text = caption .. tag(key), colour = rowColour(key), inline = true, offsetY = 8 })
                    end
                end
            end
            return w
        end

        -- Run a simulated Stock change, then tell the player in this variant's way
        local function happen(fn, progressText)
            local before = summary()
            fn()
            local sentences, keys = describe(before, summary())
            if progressText then table.insert(sentences, 1, { text = progressText, milestone = false }) end
            ctrl.sentences = #sentences > 0 and sentences or nil
            ctrl.keys = (mode == "highlight" or mode == "both") and keys or {}
            ctrl.timer = HIGHLIGHT_SECONDS
            if mode == "chat" and chatAllowed() then
                for _, s in ipairs(sentences) do
                    if s.milestone then Chat.AddMessage("[Planner] " .. s.text) end
                end
            end
            local log_ = {}
            for _, s in ipairs(sentences) do log_[#log_ + 1] = s.text end
            log("[planner-ui-prototype] live: " .. table.concat(log_, " | "))
            ctrl.pending = true
        end

        local function nextStep() local i = firstDoable(); return i and S.steps[i] end

        local function doInventory(step, n)
            step.progress = step.progress + n
            for _, input in ipairs(step.inputs or {}) do input.have = math.max(0, input.have - input.per * n) end
            step.have = (step.have or 0) + n
            if left(step) <= 0 then step.done = true end
        end

        local function finishDecant(step)
            step.done = true
            for _, t in ipairs(S.targets) do if t.id == step.id then t.have = t.want end end
        end

        local function buildSim(pos)
            local w = prettyui.Window.new(parent, {
                title = "Simulate (prototype)",
                x = pos and pos.x or 520, y = pos and pos.y or 80,
                width = 300, height = 420, scrollable = true,
            })
            w:AddText({ text = "Fake game events. The plan view reacts.", colour = C.MUTED })
            w:AddSimpleButton("Do 1 inventory of Next", function()
                local step = nextStep(); if not step then return end
                local n = math.min(step.batch or step.times, left(step))
                happen(function()
                    if step.decant then finishDecant(step) else doInventory(step, n) end
                end, not step.decant and (n .. " " .. step.name .. " " .. (step.verb == "Clean" and "cleaned" or "made") .. ".") or nil)
            end)
            w:AddSimpleButton("Finish Next step", function()
                local step = nextStep(); if not step then return end
                happen(function()
                    if step.decant then finishDecant(step) else doInventory(step, left(step)) end
                end)
            end)
            w:AddSimpleButton("Herblore reaches 63", function()
                happen(function()
                    for _, step in ipairs(S.steps) do step.flag, step.short = nil, nil end
                end)
            end)
            w:AddSimpleButton("Assumed Snape grass arrives", function()
                happen(function()
                    for k, a in ipairs(S.assumed) do
                        if a.id == 231 then table.remove(S.assumed, k) break end
                    end
                end)
            end)
            w:AddSimpleButton("Buy the Red spiders' eggs", function()
                happen(function()
                    for k, sh in ipairs(S.shortages) do
                        if sh.id == 223 then table.remove(S.shortages, k) break end
                    end
                end)
            end)
            w:AddSimpleButton("Drink 8 Super restore (4)", function()
                happen(function()
                    for _, t in ipairs(S.targets) do if t.id == 3024 then t.have = math.max(0, t.have - 8) end end
                    for _, step in ipairs(S.steps) do
                        if step.id == 3024 and step.decant and step.done then step.done = false end
                    end
                end)
            end)
            w:AddSimpleButton("Finish everything", function()
                happen(function()
                    for _, step in ipairs(S.steps) do step.done = true; step.flag = nil end
                    for _, t in ipairs(S.targets) do t.have = t.want end
                    S.shortages, S.assumed = {}, {}
                end)
            end)
            w:AddSimpleButton("Reset", function()
                reset()
                ctrl.sentences, ctrl.keys = nil, {}
                ctrl.pending = true
            end, { marginTop = 12 })
            return w
        end

        ctrl.planWin = buildPlan()
        ctrl.simWin = buildSim()

        function ctrl.rebuild()
            local pos
            if ctrl.planWin and ctrl.planWin.root then pos = { x = ctrl.planWin.root.x, y = ctrl.planWin.root.y } end
            if ctrl.planWin then ctrl.planWin:Destroy() end
            ctrl.planWin = buildPlan(pos)
        end

        function ctrl:Destroy()
            if ctrl.planWin then ctrl.planWin:Destroy(); ctrl.planWin = nil end
            if ctrl.simWin then ctrl.simWin:Destroy(); ctrl.simWin = nil end
            if active == ctrl then active = nil end
        end

        active = ctrl
        return ctrl
    end

    -- Rebuild on the next frame, and fade highlights after a few seconds
    Event.Draw.Subscribe("planner-ui-prototype-live", function(e)
        local ctrl = active
        if not ctrl then return end
        if ctrl.timer > 0 then
            ctrl.timer = ctrl.timer - (e and e.timeDeltaSecs or 0)
            if ctrl.timer <= 0 and next(ctrl.keys) then
                ctrl.keys = {}
                ctrl.pending = true
            end
        end
        if ctrl.pending then
            ctrl.pending = false
            ctrl.rebuild()
        end
    end)

    return {
        J1 = function() reset(); return newLive("highlight") end,
        J2 = function() reset(); return newLive("line") end,
        J3 = function() reset(); return newLive("chat") end,
        J4 = function() reset(); return newLive("both") end,
        Shutdown = function()
            if active then active:Destroy() end
            Event.Draw.Unsubscribe("planner-ui-prototype-live")
        end,
    }
end

local Live = makeLive({
    parent = parent, plan = plan, obj = obj, haveQty = haveQty, inventories = inventories,
    colours = { NEXT = E_NEXT, FLAG = E_FLAG, HELD = E_HELD, MUTED = E_MUTED, GOOD = GOOD },
})

---------------------------------------------------------------- Switcher

local variants = {
    { key = "A", name = "Document", build = VariantA },
    { key = "B", name = "Next step", build = VariantB },
    { key = "C", name = "Icon board", build = VariantC },
    { key = "D", name = "Hybrid", build = VariantD },
    { key = "E", name = "Pass 2", build = function() return VariantE("plan") end },
    { key = "E2", name = "Bank not read", build = function() return VariantE("nobank") end },
    { key = "E3", name = "Complete", build = function() return VariantE("complete") end },
    { key = "E4", name = "No targets", build = function() return VariantE("empty") end },
    { key = "F", name = "Less verbose", build = function() return VariantF("plan") end },
    { key = "F2", name = "Bank not read", build = function() return VariantF("nobank") end },
    { key = "F3", name = "Complete", build = function() return VariantF("complete") end },
    { key = "F4", name = "No targets", build = function() return VariantF("empty") end },
    { key = "G1", name = "Edit inline", build = Editing.G1 },
    { key = "G2", name = "Edit item sheet", build = Editing.G2 },
    { key = "G3", name = "Edit set-up window", build = Editing.G3 },
    { key = "H", name = "Editing, combined", build = Editing.H },
    { key = "J1", name = "Live: highlight", build = Live.J1 },
    { key = "J2", name = "Live: just now", build = Live.J2 },
    { key = "J3", name = "Live: chat", build = Live.J3 },
    { key = "J4", name = "Live: just now + highlight", build = Live.J4 },
}
local index = 20
local window, label

local function show(i)
    index = ((i - 1) % #variants) + 1
    if window then window:Destroy() end
    local v = variants[index]
    window = v.build()
    label.content = v.key .. " (" .. v.name .. ")"
    log("[planner-ui-prototype] showing variant " .. v.key .. " (" .. v.name .. ")")
end

local bar = prettyui.Window.new(parent, {
    title = "Prototype",
    x = -190, y = -150, xAnchor = 0.5, yAnchor = 1,
    width = 380, height = 100, minWidth = 200, minHeight = 80,
    scrollable = false,
})
bar:AddSimpleButton("Prev", function() show(index - 1) end)
label = bar:AddText({ text = "", inline = true, width = 230, alignHorizontal = ui.AlignMode.CENTRE, offsetY = 4 })
bar:AddSimpleButton("Next", function() show(index + 1) end, { inline = true })

show(index)

function PluginShutdown()
    if window then window:Destroy() end
    prettyui.Dialog.dismissAll(parent)
    Editing.Shutdown()
    Live.Shutdown()
    bar:Destroy()
end
