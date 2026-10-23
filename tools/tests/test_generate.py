import copy
import hashlib
import os
import subprocess
import sys
import tempfile
import unittest

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import generate  # noqa: E402

ROOT = os.path.join(os.path.dirname(__file__), "..", "..")


def entry(name, quantity="1", page=None):
    return {"name": name, "quantity": quantity, "page": page or name}


def row(page, outputs, materials, ticks="2", skills=None, facility=None):
    production = {
        "outputs": outputs,
        "materials": materials,
        "ticks": ticks,
        "skills": skills if skills is not None else [{"name": "Herblore", "level": "63", "experience": "142.5"}],
    }
    if facility:
        production["facility"] = facility
    return {"page_name": page, "production_json": production}


def infobox(name, item_id, page=None, anchor="DEFAULT"):
    return {"item_name": name, "item_id": [item_id], "page_name": page or name, "version_anchor": anchor}


def short_hash(*names):
    return hashlib.sha256(",".join(sorted(set(names))).encode()).hexdigest()[:6]


RESTORE_ID = "SUPER_RESTORE_3_x1_" + short_hash("SNAPDRAGON_POTION_UNF", "RED_SPIDERS_EGGS")


def snapshot():
    return {
        "recipe": [
            row(
                "Super restore",
                [entry("Super restore (3)", page="Super restore")],
                [entry("Snapdragon potion (unfinished)"), entry("Red spiders' eggs")],
            )
        ],
        "infobox_item": [
            infobox("Super restore (3)", 3026, page="Super restore", anchor="(3)"),
            infobox("Snapdragon potion (unfinished)", 3004),
            infobox("Red spiders' eggs", 223),
            infobox("Red spiders' eggs", 34395, page="Red spiders' eggs (New Varrock)"),
        ],
    }


def config_names():
    return {
        3026: {"configName": "SUPER_RESTORE_3", "name": "Super restore (3)"},
        3004: {"configName": "SNAPDRAGON_POTION_UNF", "name": "Snapdragon potion (unfinished)"},
        223: {"configName": "RED_SPIDERS_EGGS", "name": "Red spiders' eggs"},
    }


def overrides():
    return {
        "recipes": {
            RESTORE_ID: {
                "actionLimit": {"value": 14, "reason": "The wiki has no Action limit."},
                "verb": {"value": "Mix", "reason": "The row has no facility."},
            }
        }
    }


def run(snap=None, over=None, names=None):
    return generate.generate(
        snap if snap is not None else snapshot(),
        over if over is not None else overrides(),
        names if names is not None else config_names(),
    )


def recipe(data, item="SUPER_RESTORE_3"):
    return data["recipes"][item][0]


class RecipeTest(unittest.TestCase):
    def test_makes_a_recipe_in_the_format_of_plan_calculate(self):
        data, warnings = run()

        self.assertEqual(
            data["recipes"],
            {
                "SUPER_RESTORE_3": [
                    {
                        "id": RESTORE_ID,
                        "wiki": "Super restore",
                        "verb": "Mix",
                        "output": 1,
                        "otherOutputs": [],
                        "inputs": [
                            {"item": "SNAPDRAGON_POTION_UNF", "count": 1},
                            {"item": "RED_SPIDERS_EGGS", "count": 1},
                        ],
                        "skills": [{"skill": "HERBLORE", "level": 63}],
                        "unlocks": [],
                        "actionLimit": 14,
                        "actionTime": 2,
                    }
                ]
            },
        )
        self.assertEqual(warnings, [])

    def test_gives_other_outputs_after_the_first(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["outputs"].append(entry("Red spiders' eggs", "3"))

        self.assertEqual(recipe(run(snap)[0])["otherOutputs"], [{"item": "RED_SPIDERS_EGGS", "count": 3}])

    def test_uses_the_facility_as_the_verb(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["facility"] = "Botanist's Workbench"
        over = overrides()
        del over["recipes"][RESTORE_ID]["verb"]

        self.assertEqual(recipe(run(snap, over)[0])["verb"], "Botanist's Workbench")

    def test_sorts_the_recipes_of_an_item_by_id(self):
        second_id = "SUPER_RESTORE_3_x1_" + short_hash("RED_SPIDERS_EGGS")
        over = overrides()
        over["recipes"][second_id] = copy.deepcopy(over["recipes"][RESTORE_ID])
        for first in (True, False):
            snap = snapshot()
            second = copy.deepcopy(snap["recipe"][0])
            second["production_json"]["materials"] = [entry("Red spiders' eggs")]
            snap["recipe"].insert(0 if first else 1, second)

            ids = [r["id"] for r in run(snap, over)[0]["recipes"]["SUPER_RESTORE_3"]]

            self.assertEqual(ids, sorted([RESTORE_ID, second_id]))


class IdTest(unittest.TestCase):
    def test_id_does_not_change_with_amounts_or_input_order(self):
        snap = snapshot()
        materials = snap["recipe"][0]["production_json"]["materials"]
        materials.reverse()
        materials[0]["quantity"] = "4"

        self.assertEqual(recipe(run(snap)[0])["id"], RESTORE_ID)

    def test_id_has_no_hash_when_the_recipe_has_no_inputs(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["materials"] = []
        over = {"recipes": {"SUPER_RESTORE_3_x1": overrides()["recipes"][RESTORE_ID]}}

        self.assertEqual(recipe(run(snap, over)[0])["id"], "SUPER_RESTORE_3_x1")

    def test_stops_with_an_error_when_two_recipes_have_the_same_id(self):
        snap = snapshot()
        snap["recipe"].append(copy.deepcopy(snap["recipe"][0]))

        with self.assertRaisesRegex(generate.GenerateError, "Two Recipes have the id " + RESTORE_ID):
            run(snap)


class ItemTest(unittest.TestCase):
    def test_matches_an_item_by_page_and_name(self):
        data, _ = run()

        self.assertIn({"item": "RED_SPIDERS_EGGS", "count": 1}, recipe(data)["inputs"])

    def test_stops_with_an_error_that_names_an_item_id_that_is_not_in_config_names(self):
        names = config_names()
        del names[223]

        with self.assertRaisesRegex(generate.GenerateError, r"Red spiders' eggs .*223.* tools/config-names.lua"):
            run(names=names)

    def test_stops_with_an_error_that_names_a_thing_with_no_item_id(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["materials"].append(entry("Produce points", "5500"))

        with self.assertRaisesRegex(generate.GenerateError, "Produce points"):
            run(snap)

    def test_stops_with_an_error_that_names_the_ids_of_an_item_with_two_rows(self):
        snap = snapshot()
        snap["infobox_item"].append(infobox("Red spiders' eggs", 54830, anchor="1B"))

        with self.assertRaisesRegex(generate.GenerateError, "Red spiders' eggs.*223, 54830"):
            run(snap)

    def test_an_item_override_chooses_the_item_id(self):
        snap = snapshot()
        snap["infobox_item"].append(infobox("Red spiders' eggs", 54830, anchor="1B"))
        over = overrides()
        over["items"] = {"Red spiders' eggs": {"id": {"value": 223, "reason": "54830 is a different version."}}}

        self.assertIn({"item": "RED_SPIDERS_EGGS", "count": 1}, recipe(run(snap, over)[0])["inputs"])


class OverrideTest(unittest.TestCase):
    def test_stops_with_an_error_when_a_recipe_has_no_action_limit(self):
        over = overrides()
        del over["recipes"][RESTORE_ID]["actionLimit"]

        with self.assertRaisesRegex(generate.GenerateError, "The Recipe " + RESTORE_ID + " has no Action limit."):
            run(over=over)

    def test_stops_with_an_error_when_a_recipe_has_no_verb(self):
        over = overrides()
        del over["recipes"][RESTORE_ID]["verb"]

        with self.assertRaisesRegex(generate.GenerateError, "The Recipe " + RESTORE_ID + " has no verb."):
            run(over=over)

    def test_gives_all_errors_together(self):
        over = overrides()
        del over["recipes"][RESTORE_ID]

        with self.assertRaises(generate.GenerateError) as caught:
            run(over=over)

        self.assertIn("no Action limit", str(caught.exception))
        self.assertIn("no verb", str(caught.exception))

    def test_skip_removes_a_recipe(self):
        over = {"recipes": {RESTORE_ID: {"skip": {"reason": "Not a player action."}}}}

        self.assertEqual(run(over=over)[0]["recipes"], {})

    def test_stops_with_an_error_when_an_override_has_no_reason(self):
        over = overrides()
        del over["recipes"][RESTORE_ID]["actionLimit"]["reason"]

        with self.assertRaisesRegex(generate.GenerateError, "actionLimit .* has no reason"):
            run(over=over)

    def test_stops_with_an_error_when_a_tested_value_has_no_date_or_method(self):
        over = overrides()
        over["recipes"][RESTORE_ID]["actionLimit"]["tested"] = {"method": "probe"}

        with self.assertRaisesRegex(generate.GenerateError, "actionLimit .* has no date"):
            run(over=over)

    def test_stops_with_an_error_when_a_tested_method_is_unknown(self):
        over = overrides()
        over["recipes"][RESTORE_ID]["actionLimit"]["tested"] = {"date": "2026-10-23", "method": "guess"}

        with self.assertRaisesRegex(generate.GenerateError, "method guess"):
            run(over=over)


class NotANumberTest(unittest.TestCase):
    def check_skipped(self, change):
        snap = snapshot()
        change(snap["recipe"][0]["production_json"])

        data, warnings = run(snap, over={})

        self.assertEqual(data["recipes"], {})
        self.assertEqual(len(warnings), 1)
        self.assertIn("Super restore", warnings[0])

    def test_skips_a_row_whose_ticks_are_not_a_number_with_a_warning(self):
        self.check_skipped(lambda p: p.update(ticks="varies"))

    def test_skips_a_row_whose_level_is_not_a_number_with_a_warning(self):
        self.check_skipped(lambda p: p["skills"][0].update(level="?"))

    def test_skips_a_row_whose_quantity_is_not_a_number_with_a_warning(self):
        self.check_skipped(lambda p: p["materials"][0].update(quantity="1-3"))


def restore_pool_snapshot(sizes=(1, 2, 3, 4)):
    snap = snapshot()
    snap["recipe"][0]["production_json"]["outputs"][0].update(variant="(3)", portion=3)
    snap["infobox_item"] = [r for r in snap["infobox_item"] if r["page_name"] != "Super restore"]
    for size in sizes:
        snap["infobox_item"].append(infobox(f"Super restore ({size})", 3030 - 2 * size, "Super restore", f"({size})"))
    return snap


def restore_pool_names():
    names = config_names()
    for size in (1, 2, 3, 4):
        names[3030 - 2 * size] = {"configName": f"SUPER_RESTORE_{size}", "name": f"Super restore ({size})"}
    return names


class ItemNameTest(unittest.TestCase):
    def test_gives_the_wiki_name_of_each_item(self):
        data, _ = run()

        self.assertEqual(
            data["items"],
            {
                "SUPER_RESTORE_3": {"name": "Super restore (3)"},
                "SNAPDRAGON_POTION_UNF": {"name": "Snapdragon potion (unfinished)"},
                "RED_SPIDERS_EGGS": {"name": "Red spiders' eggs"},
            },
        )

    def test_warns_when_the_wiki_name_is_different_from_the_game_name(self):
        names = config_names()
        names[3004]["name"] = "Snapdragon potion (unf)"

        _, warnings = run(names=names)

        self.assertEqual(len(warnings), 1)
        self.assertIn("Snapdragon potion (unfinished)", warnings[0])
        self.assertIn("Snapdragon potion (unf)", warnings[0])

    def test_warns_once_about_an_item_in_two_recipes(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["outputs"].append(entry("Red spiders' eggs"))
        names = config_names()
        names[223]["name"] = "Red spider eggs"

        self.assertEqual(len(run(snap, names=names)[1]), 1)

    def test_a_game_name_override_stops_the_warning(self):
        names = config_names()
        names[3004]["name"] = "Snapdragon potion (unf)"
        over = overrides()
        over["items"] = {
            "Snapdragon potion (unfinished)": {"gameName": {"value": "Snapdragon potion (unf)", "reason": "Short."}}
        }

        self.assertEqual(run(over=over, names=names)[1], [])

    def test_warns_again_when_the_game_name_is_not_the_override(self):
        names = config_names()
        names[3004]["name"] = "Snapdragon potion (u)"
        over = overrides()
        over["items"] = {
            "Snapdragon potion (unfinished)": {"gameName": {"value": "Snapdragon potion (unf)", "reason": "Short."}}
        }

        warnings = run(over=over, names=names)[1]

        self.assertEqual(len(warnings), 1)
        self.assertIn("Snapdragon potion (u)", warnings[0])


class PoolTest(unittest.TestCase):
    def test_makes_a_dose_pool_from_all_versions_of_the_page(self):
        data, warnings = run(restore_pool_snapshot(), names=restore_pool_names())

        self.assertEqual(
            data["pools"],
            {"SUPER_RESTORE": ["SUPER_RESTORE_1", "SUPER_RESTORE_2", "SUPER_RESTORE_3", "SUPER_RESTORE_4"]},
        )
        self.assertEqual(data["items"]["SUPER_RESTORE_1"], {"name": "Super restore (1)"})
        self.assertEqual(warnings, [])

    def test_stops_with_an_error_when_a_dose_pool_has_a_gap(self):
        with self.assertRaisesRegex(generate.GenerateError, "Super restore.*1, 3, 4"):
            run(restore_pool_snapshot((1, 3, 4)), names=restore_pool_names())

    def test_warns_about_a_version_that_is_not_a_dose_size(self):
        snap = restore_pool_snapshot()
        snap["infobox_item"].append(infobox("Super restore (flask)", 9999, "Super restore", "Flask"))

        warnings = run(snap, names=restore_pool_names())[1]

        self.assertEqual(len(warnings), 1)
        self.assertIn("Flask", warnings[0])

    def test_has_no_pools_when_no_item_has_a_dose_size(self):
        self.assertEqual(run()[0]["pools"], {})


class UnlockTest(unittest.TestCase):
    def unlock_overrides(self):
        over = overrides()
        over["unlocks"] = {"DRUIDIC_RITUAL": {"text": "Druidic Ritual", "reason": "Herblore needs the quest."}}
        over["recipes"][RESTORE_ID]["unlocks"] = {"value": ["DRUIDIC_RITUAL"], "reason": "Herblore needs it."}
        return over

    def test_gives_the_unlocks_of_a_recipe_and_their_text(self):
        data, warnings = run(over=self.unlock_overrides())

        self.assertEqual(recipe(data)["unlocks"], ["DRUIDIC_RITUAL"])
        self.assertEqual(data["unlocks"], {"DRUIDIC_RITUAL": "Druidic Ritual"})
        self.assertEqual(warnings, [])

    def test_stops_with_an_error_when_a_recipe_names_an_unknown_unlock(self):
        over = self.unlock_overrides()
        del over["unlocks"]

        with self.assertRaisesRegex(generate.GenerateError, "unknown Unlock DRUIDIC_RITUAL"):
            run(over=over)

    def test_stops_with_an_error_when_an_unlock_has_no_text(self):
        over = self.unlock_overrides()
        del over["unlocks"]["DRUIDIC_RITUAL"]["text"]

        with self.assertRaisesRegex(generate.GenerateError, "DRUIDIC_RITUAL has no text"):
            run(over=over)

    def test_warns_when_the_wiki_gives_a_quest_and_the_recipe_has_no_unlocks(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["quest"] = "Druidic Ritual"

        warnings = run(snap)[1]

        self.assertEqual(len(warnings), 1)
        self.assertIn("Druidic Ritual", warnings[0])

    def test_does_not_warn_about_a_quest_when_the_recipe_has_unlocks(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["quest"] = "Druidic Ritual"

        self.assertEqual(run(snap, self.unlock_overrides())[1], [])


class NotNecessaryTest(unittest.TestCase):
    def check_warning(self, text, snap=None, over=None, names=None):
        warnings = run(snap, over, names)[1]

        self.assertEqual(len(warnings), 1, warnings)
        self.assertIn("not necessary", warnings[0])
        self.assertIn(text, warnings[0])

    def test_warns_about_a_verb_override_when_the_row_has_a_facility(self):
        snap = snapshot()
        snap["recipe"][0]["production_json"]["facility"] = "Botanist's Workbench"

        self.check_warning(RESTORE_ID, snap=snap)

    def test_warns_about_an_item_id_override_when_the_wiki_gives_only_that_id(self):
        over = overrides()
        over["items"] = {"Red spiders' eggs": {"id": {"value": 223, "reason": "One version."}}}

        self.check_warning("Red spiders' eggs", over=over)

    def test_warns_about_a_game_name_override_when_the_names_are_equal(self):
        over = overrides()
        over["items"] = {"Red spiders' eggs": {"gameName": {"value": "Red spiders' eggs", "reason": "Same."}}}

        self.check_warning("Red spiders' eggs", over=over)

    def test_warns_about_an_override_for_an_unknown_recipe_id(self):
        over = overrides()
        over["recipes"]["OLD_x1_abcdef"] = {"actionLimit": {"value": 1, "reason": "Old."}}

        self.check_warning("OLD_x1_abcdef", over=over)

    def test_warns_about_an_unlock_that_no_recipe_names(self):
        over = overrides()
        over["unlocks"] = {"DRUIDIC_RITUAL": {"text": "Druidic Ritual", "reason": "Herblore needs the quest."}}

        self.check_warning("DRUIDIC_RITUAL", over=over)

    def test_does_not_warn_about_an_override_of_a_skipped_recipe(self):
        over = {"recipes": {RESTORE_ID: {"skip": {"reason": "Not a player action."}}}}

        self.assertEqual(run(over=over)[1], [])


class LuaTest(unittest.TestCase):
    def write(self, text):
        handle, path = tempfile.mkstemp(suffix=".lua")
        with os.fdopen(handle, "w") as file:
            file.write(text)
        self.addCleanup(os.remove, path)
        return path

    def test_reads_a_lua_table(self):
        path = self.write('return { [257] = { configName = "RANARR", name = "Clean ranarr" }, list = { 1, 2 } }')

        self.assertEqual(generate.load_lua(path), {"257": {"configName": "RANARR", "name": "Clean ranarr"}, "list": [1, 2]})

    def test_stops_with_an_error_that_names_a_lua_file_that_does_not_load(self):
        path = self.write("return {")

        with self.assertRaisesRegex(generate.GenerateError, os.path.basename(path)):
            generate.load_lua(path)

    def test_written_data_loads_as_the_same_table(self):
        data, _ = run()

        data["unlocks"] = {"DRUIDIC_RITUAL": "Druidic Ritual"}
        data["pools"] = {"SUPER_RESTORE": ["SUPER_RESTORE_1", "SUPER_RESTORE_2"]}

        path = self.write(generate.render(data))

        self.assertEqual(generate.load_lua(path), data)

    def test_written_data_passes_stylua_and_luacheck(self):
        data, _ = run()
        path = self.write(generate.render(data))

        stylua = subprocess.run(
            ["stylua", "--config-path", os.path.join(ROOT, "stylua.toml"), "--check", path], capture_output=True
        )
        luacheck = subprocess.run(
            ["luacheck", "--config", os.path.join(ROOT, ".luacheckrc"), path], capture_output=True
        )

        self.assertEqual(stylua.returncode, 0, stylua.stdout)
        self.assertEqual(luacheck.returncode, 0, luacheck.stdout)

    def test_formats_with_stylua(self):
        self.assertEqual(generate.stylua("return {a=1}\n"), "return { a = 1 }\n")

    def test_says_that_the_file_is_generated_and_gives_the_source(self):
        text = generate.render(run()[0])

        self.assertIn("tools/generate.py", text.splitlines()[0])
        self.assertIn("CC BY-NC-SA 3.0", text)


if __name__ == "__main__":
    unittest.main()
