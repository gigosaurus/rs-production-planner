local UnlockName = require("plan/unlockname")

local DATA = { [62] = { [8] = { name = "Barbarian smithing", guess = true } } }

describe("UnlockName.of", function()
    it("gives the name of an Unlock in the data", function()
        expectEqual(UnlockName.of(DATA, "UNLOCK62:8"), "Barbarian smithing")
    end)

    it("gives nil for a value that is not in the data", function()
        expectEqual(UnlockName.of(DATA, "UNLOCK62:9"), nil)
    end)

    it("gives nil for a type that is not in the data", function()
        expectEqual(UnlockName.of(DATA, "UNLOCK64:8"), nil)
    end)

    it("gives nil for a quest or a blueprint, because the game names them", function()
        expectEqual(UnlockName.of(DATA, "QUEST:8"), nil)
    end)
end)
