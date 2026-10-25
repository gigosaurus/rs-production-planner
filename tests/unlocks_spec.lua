local Validate = require("plan/validate")
local unlocks = require("data/unlocks")

-- Gives a list of format problems in the Unlock names. An empty list means no problems.
local function formatProblems(data)
    local problems = {}
    for requirementType, entries in pairs(data) do
        if not Validate.isPositiveInteger(requirementType) then
            problems[#problems + 1] = "requirement type "
                .. tostring(requirementType)
                .. " is not a whole number more than 0"
        end
        if type(entries) ~= "table" then
            problems[#problems + 1] = "requirement type " .. tostring(requirementType) .. " has no table of values"
        else
            for value, entry in pairs(entries) do
                local where = tostring(requirementType) .. ":" .. tostring(value)
                if not Validate.isNonNegativeInteger(value) then
                    problems[#problems + 1] = where .. " value is not a whole number of 0 or more"
                end
                if type(entry) ~= "table" then
                    problems[#problems + 1] = where .. " has no entry table"
                else
                    if type(entry.name) ~= "string" or entry.name == "" then
                        problems[#problems + 1] = where .. " has no name"
                    end
                    if type(entry.guess) ~= "boolean" then
                        problems[#problems + 1] = where .. " guess is not true or false"
                    end
                    if entry.example ~= nil and type(entry.example) ~= "string" then
                        problems[#problems + 1] = where .. " example is not a string"
                    end
                end
            end
        end
    end
    table.sort(problems)
    return problems
end

describe("data/unlocks", function()
    it("has no format problems", function()
        expectEqual(formatProblems(unlocks), {})
    end)

    it("finds a name that is missing", function()
        expectEqual(formatProblems({ [62] = { [5] = { guess = true } } }), { "62:5 has no name" })
    end)

    it("finds a guess that is not true or false", function()
        expectEqual(formatProblems({ [62] = { [5] = { name = "Daemonheim", guess = "yes" } } }), {
            "62:5 guess is not true or false",
        })
    end)

    it("finds a value that is not a whole number", function()
        expectEqual(formatProblems({ [64] = { [1.5] = { name = "Sawmill", guess = true } } }), {
            "64:1.5 value is not a whole number of 0 or more",
        })
    end)

    it("does not include quest requirements, because the plugin finds quests by QUEST_ID", function()
        expectEqual(unlocks[61], nil)
    end)
end)
