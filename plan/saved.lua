-- Keeps the saved data, as ADR 0008 and ADR 0011 describe.
-- It does not use the game API. Tests run it outside the game client.
-- The adapter gives it a store with Get and Set, for example PersistentDB.
local Assumed = require("plan/assumed")
local Made = require("plan/made")
local Plan = require("plan/calculate")

local Saved = {}

-- Problem kinds
Saved.UNKNOWN_VERSION = "UNKNOWN_VERSION"
Saved.NOT_SAVED = "NOT_SAVED"

-- PersistentDB keeps numbers as 32-bit floats, so each count is saved as a decimal string (ADR 0011).
local function countText(count)
    return string.format("%d", count)
end

-- Gives nil when the text is not a decimal integer.
local function countOf(text)
    if type(text) ~= "string" or not text:match("^%-?%d+$") then
        return nil
    end
    return math.tointeger(tonumber(text))
end

local function countTexts(counts)
    local texts = {}
    for item, count in pairs(counts) do
        texts[item] = countText(count)
    end
    return texts
end

-- Gives nil when a count is bad.
local function countsOf(texts)
    if type(texts) ~= "table" then
        return nil
    end
    local counts = {}
    for item, text in pairs(texts) do
        local count = countOf(text)
        if type(item) ~= "string" or not count then
            return nil
        end
        counts[item] = count
    end
    return counts
end

local function tableVersionOf(value)
    return type(value) == "table" and math.tointeger(value.v) or nil
end

-- The Bank snapshot is one string: a version line, then one line `<name>=<count>` for each item.
local bank = { version = 1 }

function bank.versionOf(text)
    return type(text) == "string" and math.tointeger(tonumber(text:match("^v=(%d+)\n"))) or nil
end

function bank.encode(snapshot)
    local names = {}
    for name in pairs(snapshot) do
        names[#names + 1] = name
    end
    table.sort(names)
    local lines = { "v=1\n" }
    for _, name in ipairs(names) do
        lines[#lines + 1] = name .. "=" .. countText(snapshot[name]) .. "\n"
    end
    return table.concat(lines)
end

function bank.decode(text)
    local lines = text:gsub("^[^\n]*\n", "", 1)
    if lines ~= "" and lines:sub(-1) ~= "\n" then
        return nil
    end
    local snapshot = {}
    for line in lines:gmatch("([^\n]*)\n") do
        local name, digits = line:match("^(.*)=([^=]*)$")
        local count = countOf(digits)
        if not count then
            return nil
        end
        snapshot[name] = count
    end
    return snapshot
end

-- A character that the plugin has not seen has no Bank snapshot.
function bank.start()
    return nil
end

local assumed = { version = 1, versionOf = tableVersionOf, start = Assumed.new }

function assumed.encode(state)
    local entries = {}
    for index, entry in ipairs(state.entries) do
        entries[index] = {
            item = entry.item,
            entered = countText(entry.entered),
            remaining = countText(entry.remaining),
            baseline = countText(entry.baseline),
        }
    end
    return { v = assumed.version, entries = entries }
end

function assumed.decode(value)
    if type(value.entries) ~= "table" then
        return nil
    end
    local state = Assumed.new()
    for index, entry in ipairs(value.entries) do
        if type(entry) ~= "table" or type(entry.item) ~= "string" then
            return nil
        end
        local entered, remaining, baseline = countOf(entry.entered), countOf(entry.remaining), countOf(entry.baseline)
        if not entered or not remaining or not baseline then
            return nil
        end
        state.entries[index] = { item = entry.item, entered = entered, remaining = remaining, baseline = baseline }
    end
    return state
end

local function empty()
    return {}
end

local reserves = { version = 1, versionOf = tableVersionOf, start = empty }

function reserves.encode(counts)
    return { v = reserves.version, reserves = countTexts(counts) }
end

function reserves.decode(value)
    return countsOf(value.reserves)
end

local unlocks = { version = 1, versionOf = tableVersionOf, start = empty }

function unlocks.encode(set)
    local copy = {}
    for unlock in pairs(set) do
        copy[unlock] = true
    end
    return { v = unlocks.version, unlocks = copy }
end

function unlocks.decode(value)
    if type(value.unlocks) ~= "table" then
        return nil
    end
    local set = {}
    for unlock in pairs(value.unlocks) do
        set[unlock] = true
    end
    return set
end

-- Made.load clears the GE amounts and the last Detected counts, so the plugin does not save them.
local made = { version = 1, versionOf = tableVersionOf, start = Made.new }

function made.encode(state)
    local slots = {}
    for slot, data in pairs(state.slots) do
        slots[slot] = { item = data.item, type = data.type, stage = data.stage, soldCount = countText(data.soldCount) }
    end
    return { v = made.version, counts = countTexts(state.counts), slots = slots }
end

function made.decode(value)
    local state = Made.new()
    state.counts = countsOf(value.counts)
    if not state.counts or type(value.slots) ~= "table" then
        return nil
    end
    for slot, data in pairs(value.slots) do
        if type(data) ~= "table" or not countOf(data.soldCount) then
            return nil
        end
        state.slots[slot] =
            { item = data.item, type = data.type, stage = data.stage, soldCount = countOf(data.soldCount) }
    end
    return state
end

local plan = { version = 1, versionOf = tableVersionOf }

function plan.start()
    return { targets = {} }
end

function plan.encode(value)
    local targets = {}
    for index, target in ipairs(value.targets) do
        targets[index] = { item = target.item, count = countText(target.count) }
    end
    return { v = plan.version, targets = targets }
end

function plan.decode(value)
    if type(value.targets) ~= "table" then
        return nil
    end
    local targets = {}
    for index, target in ipairs(value.targets) do
        if type(target) ~= "table" or type(target.item) ~= "string" or not countOf(target.count) then
            return nil
        end
        targets[index] = { item = target.item, count = countOf(target.count) }
    end
    return { targets = targets }
end

-- Gives a codec for a table of settings. Each setting that the saved data does not have gets its start value.
-- Then a new setting needs no new version.
local function settingsCodec(startValues)
    local codec = { version = 1, versionOf = tableVersionOf }
    function codec.start()
        local settings = {}
        for name, value in pairs(startValues) do
            settings[name] = value
        end
        return settings
    end
    function codec.encode(settings)
        local value = { v = codec.version }
        for name in pairs(startValues) do
            value[name] = settings[name]
        end
        return value
    end
    function codec.decode(value)
        local settings = codec.start()
        for name, startValue in pairs(startValues) do
            if value[name] ~= nil and type(value[name]) ~= type(startValue) then
                return nil
            end
            if value[name] ~= nil then
                settings[name] = value[name]
            end
        end
        return settings
    end
    return codec
end

local CODECS = {
    bank = bank,
    assumed = assumed,
    reserves = reserves,
    unlocks = unlocks,
    made = made,
    settings = settingsCodec({ ironman = false }),
}

local GLOBAL_CODECS = {
    plan = plan,
    settings = settingsCodec({ targetMode = Plan.HAVE, madeCountScope = Made.CHARACTER }),
}

local function globalKey(part)
    return "global:" .. part
end

-- The display names of all characters that have saved data, in the order that the plugin added them.
local CHARACTERS_KEY = "global:characters"
local characters = { version = 1, versionOf = tableVersionOf, start = empty }

function characters.encode(names)
    return { v = characters.version, characters = table.move(names, 1, #names, 1, {}) }
end

function characters.decode(value)
    if type(value.characters) ~= "table" then
        return nil
    end
    for _, name in ipairs(value.characters) do
        if type(name) ~= "string" then
            return nil
        end
    end
    return table.move(value.characters, 1, #value.characters, 1, {})
end

local function key(name, part)
    return "char:" .. name .. ":" .. part
end

function Saved.new(store)
    return { store = store, changed = {}, blocked = {}, loaded = {}, characters = nil, charactersUnsaved = false }
end

-- Gives the value of one key, decoded, or the start value.
-- A key with an unknown version or bad data is blocked. Decode gives nil for bad data.
local function load(saved, codec, loadKey, problems)
    local value = saved.store:Get(loadKey)
    if value == nil then
        return codec.start()
    end
    local decoded = codec.versionOf(value) == codec.version and codec.decode(value) or nil
    if decoded ~= nil then
        return decoded
    end
    saved.blocked[loadKey] = true
    problems[#problems + 1] = { key = loadKey, kind = Saved.UNKNOWN_VERSION }
    return codec.start()
end

-- Gives the global data, and a list of problems. Call this one time at start, before a change.
function Saved.loadGlobal(saved)
    local problems = {}
    saved.characters = load(saved, characters, CHARACTERS_KEY, problems)
    local globals = { characters = table.move(saved.characters, 1, #saved.characters, 1, {}) }
    for part, codec in pairs(GLOBAL_CODECS) do
        globals[part] = load(saved, codec, globalKey(part), problems)
    end
    return globals, problems
end

-- Gives the saved parts of one character, and a list of problems.
-- The plugin does not read or write a key with no version or a newer version (ADR 0011).
-- Such a part gets its start value.
function Saved.loadCharacter(saved, name)
    local parts, problems = {}, {}
    for part, codec in pairs(CODECS) do
        parts[part] = load(saved, codec, key(name, part), problems)
    end
    saved.loaded[name] = true
    return parts, problems
end

local function isKnown(names, name)
    for _, known in ipairs(names) do
        if known == name then
            return true
        end
    end
    return false
end

-- Marks a part as changed. Saved.write writes it.
-- The first change for a character adds its name to the saved characters.
-- Until the store saves the characters, each change marks them again.
-- Load the character first, so that a key with an unknown version is not written.
function Saved.change(saved, name, part, value)
    if not saved.characters then
        error("Load the global data before a change.", 2)
    end
    if not saved.loaded[name] then
        error("Load the character " .. name .. " before a change.", 2)
    end
    saved.changed[key(name, part)] = CODECS[part].encode(value)
    if not isKnown(saved.characters, name) then
        saved.characters[#saved.characters + 1] = name
        saved.charactersUnsaved = true
    end
    if saved.charactersUnsaved then
        saved.changed[CHARACTERS_KEY] = characters.encode(saved.characters)
    end
end

-- Marks a global part as changed. Saved.write writes it.
function Saved.changeGlobal(saved, part, value)
    if not saved.characters then
        error("Load the global data before a change.", 2)
    end
    saved.changed[globalKey(part)] = GLOBAL_CODECS[part].encode(value)
end

-- Call this one time in each Logic tick. It writes each changed part one time, and gives a list of problems.
-- A part that the store does not save is not marked again. Its next change tries again (ADR 0011).
function Saved.write(saved)
    local problems = {}
    for changedKey, value in pairs(saved.changed) do
        if not saved.blocked[changedKey] then
            if not saved.store:Set(changedKey, value) then
                problems[#problems + 1] = { key = changedKey, kind = Saved.NOT_SAVED }
            elseif changedKey == CHARACTERS_KEY then
                saved.charactersUnsaved = false
            end
        end
    end
    saved.changed = {}
    return problems
end

return Saved
