-- Keeps the saved data, as ADR 0008 and ADR 0011 describe.
-- It does not use the game API. Tests run it outside the game client.
-- The adapter gives it a store with Get and Set, for example PersistentDB.
local Assumed = require("plan/assumed")

local Saved = {}

-- Problem kinds
Saved.UNKNOWN_VERSION = "UNKNOWN_VERSION"
Saved.NOT_SAVED = "NOT_SAVED"

-- PersistentDB keeps numbers as 32-bit floats, so each count is saved as a decimal string (ADR 0011).
local function countText(count)
    return string.format("%d", count)
end

local function countOf(text)
    return math.tointeger(tonumber(text))
end

local function tableVersionOf(value)
    return type(value) == "table" and math.tointeger(value.v) or nil
end

-- The Bank snapshot is one string: a version line, then one line `<name>=<count>` for each item.
local bank = { version = 1 }

function bank.versionOf(text)
    return math.tointeger(tonumber(text:match("^v=(%d+)\n")))
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
    local snapshot = {}
    for name, count in text:gsub("^[^\n]*\n", "", 1):gmatch("([^\n]*)=(%d+)\n") do
        snapshot[name] = countOf(count)
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
    local state = Assumed.new()
    for index, entry in ipairs(value.entries) do
        state.entries[index] = {
            item = entry.item,
            entered = countOf(entry.entered),
            remaining = countOf(entry.remaining),
            baseline = countOf(entry.baseline),
        }
    end
    return state
end

local CODECS = { bank = bank, assumed = assumed }

local function key(name, part)
    return "char:" .. name .. ":" .. part
end

function Saved.new(store)
    return { store = store, changed = {}, blocked = {} }
end

-- Gives the saved parts of one character, and a list of problems.
-- The plugin does not read or write a key with no version or a newer version (ADR 0011).
function Saved.loadCharacter(saved, name)
    local parts, problems = {}, {}
    for part, codec in pairs(CODECS) do
        local partKey = key(name, part)
        local value = saved.store:Get(partKey)
        if value == nil then
            parts[part] = codec.start()
        else
            local version = codec.versionOf(value)
            if version == codec.version then
                parts[part] = codec.decode(value)
            else
                saved.blocked[partKey] = true
                problems[#problems + 1] = { key = partKey, kind = Saved.UNKNOWN_VERSION }
            end
        end
    end
    return parts, problems
end

-- Marks a part as changed. Saved.write writes it.
function Saved.change(saved, name, part, value)
    saved.changed[key(name, part)] = CODECS[part].encode(value)
end

-- Call this one time in each Logic tick. It writes each changed part one time, and gives a list of problems.
-- A part that the store does not save is not marked again. Its next change tries again (ADR 0011).
function Saved.write(saved)
    local problems = {}
    for changedKey, value in pairs(saved.changed) do
        if not saved.blocked[changedKey] and not saved.store:Set(changedKey, value) then
            problems[#problems + 1] = { key = changedKey, kind = Saved.NOT_SAVED }
        end
    end
    saved.changed = {}
    return problems
end

return Saved
