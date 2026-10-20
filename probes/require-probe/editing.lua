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

return function(ctx)
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
