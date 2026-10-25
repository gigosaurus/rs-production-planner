local ObjParams = require("plan/objparams")

-- A fake Obj or Struct config: a params list of ParamTypes and GetParamValue.
local function fakeConfig(values)
    local config = { params = {} }
    for name in pairs(values) do
        config.params[#config.params + 1] = { configName = name }
    end
    function config.GetParamValue(_, param)
        return values[param.configName]
    end
    return config
end

local function fakeObj(configName)
    return { configName = configName }
end

describe("ObjParams.read", function()
    it("gives the recipe params that GameRecipe uses, as plain values", function()
        local params = ObjParams.read(fakeConfig({
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_INGREDIENT_1_SCALE_STACK = false,
            RECIPE_REQUIREMENT_TYPE_1 = 9,
            RECIPE_REQUIREMENT_VALUE_1 = 3,
            RECIPE_XP_TYPE_1 = 9,
            RECIPE_XP_VALUE_1 = 25,
            RECIPE_XP_SCALE_STACK_1 = false,
            RECIPE_MAKE_STACK_SIZE = 1,
            RECIPE_CYCLES = 2,
        }))

        expectEqual(params, {
            RECIPE_INGREDIENT_NUMBER_1 = 1,
            RECIPE_INGREDIENT_1_SCALE_STACK = false,
            RECIPE_REQUIREMENT_TYPE_1 = 9,
            RECIPE_REQUIREMENT_VALUE_1 = 3,
            RECIPE_XP_TYPE_1 = 9,
            RECIPE_XP_VALUE_1 = 25,
            RECIPE_XP_SCALE_STACK_1 = false,
            RECIPE_MAKE_STACK_SIZE = 1,
            RECIPE_CYCLES = 2,
        })
    end)

    -- GetParamValue on some params logs a client error that pcall does not catch (docs/recipe-params.md).
    it("does not read other params", function()
        local read = {}
        local config = fakeConfig({ RECIPE_CYCLES = 2, MAGIC_ALCH_DERIVED_ITEM = 1, RECIPE_TOOL_TYPE_1 = 0 })
        local getParamValue = config.GetParamValue
        function config:GetParamValue(param)
            read[#read + 1] = param.configName
            return getParamValue(self, param)
        end

        expectEqual(ObjParams.read(config), { RECIPE_CYCLES = 2 })
        expectEqual(read, { "RECIPE_CYCLES" })
    end)

    it("gives the config name of an Obj value", function()
        local params = ObjParams.read(fakeConfig({
            RECIPE_INGREDIENT_TYPE_12 = fakeObj("VIAL_WATER"),
            RECIPE_NON_DUMMY_OBJ = fakeObj("ARROW_SHAFT"),
        }))

        expectEqual(params, { RECIPE_INGREDIENT_TYPE_12 = "VIAL_WATER", RECIPE_NON_DUMMY_OBJ = "ARROW_SHAFT" })
    end)

    it("gives the params of a Struct value as a table", function()
        local params = ObjParams.read(fakeConfig({
            RECIPE_INGREDIENT_3_MULTIPLE = fakeConfig({
                RECIPE_INGREDIENT_TYPE_1 = fakeObj("STEEL_BAR"),
                RECIPE_INGREDIENT_NUMBER_1 = 5,
                STRUCT_OTHER = 1,
            }),
        }))

        expectEqual(params, {
            RECIPE_INGREDIENT_3_MULTIPLE = { RECIPE_INGREDIENT_TYPE_1 = "STEEL_BAR", RECIPE_INGREDIENT_NUMBER_1 = 5 },
        })
    end)

    it("gives an empty table for a config with no params", function()
        expectEqual(ObjParams.read({ GetParamValue = function() end }), {})
    end)
end)
