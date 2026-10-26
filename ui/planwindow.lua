-- Draws the Plan view in a PrettyUI window, and the ribbon layer that opens and closes it (issue 26).
-- It uses the game API and PrettyUI. plan/view.lua and plan/news.lua give all the text.
-- PrettyUI cannot remove the content of a window. Thus each change draws a new window,
-- and the window keeps its position, size, scroll position, open sections and pop-out panels.
local PlanWindow = {}

-- Decisions on issue 26, 2026-10-26.
local WIDTH, HEIGHT = 440, 600
local TITLE = "Production Planner"
local NOT_READY = "Reading the recipes from the game."
local NOT_YET = "Comes with plan editing."

-- Layout F of issue 1. Gold is only for headings, so no text here uses it.
local MUTED = 0xC8BC9AFF
local FLAGGED = 0xFF8A6AFF
local NEXT = 0x7FC8F0FF
local WAITING = 0x8F8676FF
local GOOD = 0x8FC66AFF
-- Issue 5: a changed row is pale yellow for some seconds, and a word tells what changed.
local HIGHLIGHT = 0xFFF0A0FF

-- Text beside an item slot moves down to the centre of the slot.
local BESIDE_SLOT = { inline = true, offsetY = 8 }
local LINE_HEIGHT, PANEL_PADDING = 26, 38

local function obj(item)
    return config.Obj[item]
end

-- The game shows no count of 0 on an item (issue 1).
local function quantity(count)
    return count > 0 and count or nil
end

-- Gives the options of a text beside an item slot.
local function beside(options)
    for key, value in pairs(BESIDE_SLOT) do
        options[key] = value
    end
    return options
end

-- Adds the highlight word to text, and gives the colour. word is nil when the row did not change.
local function marked(text, word, colour)
    if word then
        return text .. "  -  " .. word, HIGHLIGHT
    end
    return text, colour
end

-- getParent gives the component that holds the window. The plugin can load before the game interface exists,
-- so the window asks for it each time it draws.
-- actions has onOpen, onClose and onDismiss. The plugin calls them when the player uses the window or the layer.
-- actions.onProblem gets the text of each problem, for the log.
function PlanWindow.new(getParent, actions)
    return {
        getParent = getParent,
        actions = actions,
        place = { x = 60, y = 80, width = WIDTH, height = HEIGHT, scrollY = 0 },
        -- Issue 26: Production order starts open. Leftovers and the Planning assumptions start collapsed.
        expanded = { order = true, leftovers = false, assumptions = false },
        popouts = {},
        isOpen = false,
    }
end

-- Keeps the state of the window that shows now. The window stays.
local function keep(pw)
    local window = pw.window
    local root = window.root
    pw.place = { x = root.x, y = root.y, width = root.width, height = root.height, scrollY = window.scrollY }
    for key, panel in pairs(pw.panels) do
        local overlay = panel.overlay.root
        pw.popouts[key].x, pw.popouts[key].y = overlay.x, overlay.y
    end
    pw.window, pw.panels = nil, nil
end

-- Keeps the state of the window that shows now, then destroys it.
local function remove(pw)
    local window = pw.window
    if window ~= nil then
        keep(pw)
        window:Destroy()
    end
end

local draw

-- Adds a heading that the player can open and close. Gives true when it is open.
-- All headings use the same title style (issue 1), so a Hide or Show button follows the title on its row.
-- The rows of the section go below the heading.
local function addSection(pw, key, text)
    local expanded = pw.expanded[key]
    pw.window:AddTitle(text)
    pw.window:AddSimpleButton(expanded and "Hide" or "Show", function()
        pw.expanded[key] = not expanded
        draw(pw)
    end, { inline = true })
    return expanded
end

-- Adds a panel that can pop out, so the player can keep it on screen at the GE or the bank (issue 1).
local function addPanel(pw, key, lines, tooltip, popoutY)
    pw.popouts[key] = pw.popouts[key] or { poppedOut = false, x = 520, y = popoutY }
    local state = pw.popouts[key]
    local height = #lines * LINE_HEIGHT + PANEL_PADDING
    local panel = pw.window:AddPanel({
        popout = true,
        poppedOut = state.poppedOut,
        resizable = true,
        height = height,
        popoutX = state.x,
        popoutY = state.y,
        popoutWidth = 260,
        popoutHeight = height,
        popoutBackgroundAlpha = 0.85,
        tooltip = tooltip,
        onPopoutChange = function(_, poppedOut)
            state.poppedOut = poppedOut
        end,
    })
    pw.panels[key] = panel
    for _, line in ipairs(lines) do
        panel:AddText(line)
    end
end

local function hasNext(view)
    for _, row in ipairs(view.steps) do
        if row.kind == "next" then
            return true
        end
    end
    return false
end

local function addDoNext(pw, view, highlights)
    local window = pw.window
    window:AddTitle("Do next")
    local ready = hasNext(view)
    local text, colour = marked(view.doNext.text, ready and highlights.next, ready and NEXT or MUTED)
    window:AddText({ text = text, colour = colour })
    for _, input in ipairs(view.doNext.inputs) do
        window:AddItemSlot(
            obj(input.item),
            { quantity = quantity(input.have), tooltip = "You have " .. input.have .. "." }
        )
        window:AddText(beside({ text = input.text }))
    end
end

local function addTargets(pw, view, highlights)
    local window = pw.window
    window:AddTitle("Targets")
    for _, target in ipairs(view.targets) do
        local text, colour = marked(target.text, highlights.targets[target.id])
        window:AddItemSlot(obj(target.item), { quantity = quantity(target.have) })
        window:AddText(beside({ text = text, colour = colour }))
    end
end

local function addShortages(pw, view)
    if #view.shortages == 0 then
        return
    end
    pw.window:AddTitle("Buy or gather (" .. #view.shortages .. ")")
    local lines = {}
    for index, shortage in ipairs(view.shortages) do
        lines[index] = { text = shortage.text, tooltip = shortage.tooltip }
    end
    addPanel(pw, "shortages", lines, "Pop out to keep it on screen. Press again to put it back.", 80)
end

local function addAssumed(pw, view, highlights)
    if #view.assumed == 0 then
        return
    end
    pw.window:AddTitle("Assumed (" .. #view.assumed .. ")")
    local lines = {}
    for index, line in ipairs(view.assumed) do
        local text, colour = marked(line.text, highlights.assumed[line.item], MUTED)
        lines[index] = { text = text, colour = colour }
    end
    addPanel(pw, "assumed", lines, "The plan counts these items until they come to your backpack or bank.", 240)
end

local STEP_COLOURS = { next = NEXT, flagged = FLAGGED, waiting = WAITING }

local function addSteps(pw, view, highlights)
    local window = pw.window
    if #view.steps == 0 or not addSection(pw, "order", "Production order (" .. #view.steps .. ")") then
        return
    end
    for _, row in ipairs(view.steps) do
        local word = row.kind == "next" and highlights.next or highlights.steps[row.item]
        window:AddItemSlot(obj(row.item), { quantity = quantity(row.have), tooltip = row.tooltip })
        -- A Flagged row gives its reason on the same row (issue 1). The highlight word comes last.
        local caption = row.kind == "flagged" and row.caption .. "  -  " .. row.reason or row.caption
        local colour
        caption, colour = marked(caption, word, STEP_COLOURS[row.kind])
        window:AddText(beside({ text = caption, colour = colour, tooltip = row.tooltip, columnGap = 6 }))
        -- A Waiting row has a dim caption and a reason that the player can read (issue 1).
        if row.kind == "waiting" then
            window:AddText(beside({ text = "-  " .. row.reason, colour = MUTED, tooltip = row.tooltip }))
        end
    end
end

local function addLines(pw, key, title, lines, colour)
    if #lines > 0 and addSection(pw, key, title .. " (" .. #lines .. ")") then
        for _, line in ipairs(lines) do
            pw.window:AddText({ text = line, colour = colour })
        end
    end
end

local function addMessage(pw, message)
    if message then
        pw.window:AddText({ text = message, colour = GOOD })
        pw.window:AddSimpleButton("Dismiss", pw.actions.onDismiss)
    end
end

-- The buttons need editing (issue 27). Until then, they show but are disabled.
local function addLaterButton(window, text, options)
    options.disabled = true
    options.tooltip = NOT_YET
    window:AddSimpleButton(text, function() end, options)
end

local function addNoTargets(pw)
    local window = pw.window
    window:AddTitle("No targets yet")
    window:AddText("Add the items that you want. The plan then tells you what to make, buy and gather.")
    addLaterButton(window, "Add target", { marginTop = 8 })
end

local function addComplete(pw, view, highlights)
    local window = pw.window
    window:AddTitle("Plan complete")
    addTargets(pw, view, highlights)
    if view.leftOver then
        window:AddText({ text = view.leftOver, colour = MUTED, marginTop = 8 })
    end
    addLaterButton(window, "Clear targets", { marginTop = 8 })
    addLaterButton(window, "Keep tracking", { inline = true })
end

local function addPlan(pw, view, highlights)
    local window = pw.window
    if view.bankWarning then
        window:AddText({
            text = "The plugin has not seen your bank. Open your bank one time to count its items.",
            colour = FLAGGED,
        })
        window:AddText({ text = "Until you do, the amounts to buy can be too high.", colour = MUTED })
    end
    addDoNext(pw, view, highlights)
    addTargets(pw, view, highlights)
    addShortages(pw, view)
    addAssumed(pw, view, highlights)
    addSteps(pw, view, highlights)
    addLines(pw, "leftovers", "Leftovers", view.leftovers)
    addLines(pw, "assumptions", "What this plan assumes", view.assumptions, MUTED)
end

local NO_HIGHLIGHTS = { steps = {}, targets = {}, assumed = {} }

local drawLayer

function draw(pw)
    remove(pw)
    if not pw.isOpen then
        return
    end
    local parent = pw.getParent()
    if parent == nil then
        pw.actions.onProblem("The window has no parent component.")
        return
    end
    local place = pw.place
    pw.panels = {}
    pw.window = prettyui.Window.new(parent, {
        title = TITLE,
        x = place.x,
        y = place.y,
        width = place.width,
        height = place.height,
        resizable = true,
        scrollable = true,
        destroyOnClose = true,
        -- The player closed the window. Window.Close destroys it after this call.
        onClose = function()
            pw.isOpen = false
            keep(pw)
            drawLayer(pw)
            pw.actions.onClose()
        end,
    })
    local view, highlights = pw.view, pw.highlights or NO_HIGHLIGHTS
    if view == nil then
        pw.window:AddText({ text = NOT_READY, colour = MUTED })
        return
    end
    addMessage(pw, pw.message)
    if view.state == "noTargets" then
        addNoTargets(pw)
    elseif view.state == "complete" then
        addComplete(pw, view, highlights)
    else
        addPlan(pw, view, highlights)
    end
    pw.window:SetScrollPosition(place.scrollY or 0)
end

-- The size of the content layer is not known (issue 26). These sizes are for a layer with no size.
local LAYER_WIDTH, LAYER_HEIGHT = 300, 120

-- Draws the ribbon layer again: one button and the status.
function drawLayer(pw)
    local layer = pw.layer
    if layer == nil then
        return
    end
    if pw.layerView then
        pcall(pw.layerView.Destroy, pw.layerView)
    end
    local ok, view = pcall(prettyui.SimpleView.new, layer, {
        width = layer.width > 0 and layer.width or LAYER_WIDTH,
        height = layer.height > 0 and layer.height or LAYER_HEIGHT,
    })
    if not ok then
        -- Possibly the client removed the layer.
        pw.actions.onProblem("The ribbon layer did not draw: " .. tostring(view))
        pw.layer, pw.layerView = nil, nil
        return
    end
    pw.layerView = view
    view:AddSimpleButton(pw.isOpen and "Close Plan" or "Open Plan", function()
        if pw.isOpen then
            PlanWindow.close(pw)
            pw.actions.onClose()
        else
            PlanWindow.open(pw)
            pw.actions.onOpen()
        end
    end)
    view:AddText({ text = pw.view and pw.view.status or NOT_READY, colour = MUTED })
end

-- view is the result of View.build, or nil before the first Plan. message is the "Just now" message, or nil.
-- highlights are the highlights that show now, or nil.
function PlanWindow.show(pw, view, message, highlights)
    pw.view, pw.message, pw.highlights = view, message, highlights
    if pw.isOpen then
        draw(pw)
    end
    drawLayer(pw)
end

function PlanWindow.open(pw)
    pw.isOpen = true
    draw(pw)
    drawLayer(pw)
end

function PlanWindow.close(pw)
    pw.isOpen = false
    remove(pw)
    drawLayer(pw)
end

-- Call this on each ContentLayerReady event. The client clears the layer before the event.
function PlanWindow.mountLayer(pw, component)
    pw.layer, pw.layerView = component, nil
    drawLayer(pw)
end

function PlanWindow.destroy(pw)
    pw.isOpen = false
    remove(pw)
    if pw.layerView then
        pcall(pw.layerView.Destroy, pw.layerView)
    end
    pw.layer, pw.layerView = nil, nil
end

return PlanWindow
