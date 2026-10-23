import json
import os
import sys
import unittest
import urllib.parse

sys.path.insert(0, os.path.join(os.path.dirname(__file__), ".."))

import fetch  # noqa: E402


def recipe_row(page, outputs, materials, **extra):
    production = {"outputs": outputs, "materials": materials, "skills": [], "ticks": "2"}
    production.update(extra)
    return {"page_name": page, "production_json": json.dumps(production)}


def item(name, quantity="1"):
    return {"name": name, "quantity": quantity}


class FakeWiki:
    """Gives the rows of each bucket that match the item names or pages in the query."""

    def __init__(self, infobox, recipes):
        self.infobox = infobox
        self.recipes = recipes
        self.urls = []
        self.calls = []

    def get(self, url):
        self.urls.append(url)
        self.calls.append("get")
        query = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)["query"][0]
        if query.startswith('bucket("infobox_item")'):
            rows = [r for r in self.infobox if json.dumps(r["item_name"]) in query]
        else:
            rows = [r for r in self.recipes if json.dumps(r["page_name"]) in query]
        return {"bucketQuery": query, "bucket": rows}

    def sleep(self, seconds):
        self.calls.append(("sleep", seconds))


INFOBOX = [
    {"page_name": "Super restore", "item_name": "Super restore (3)", "item_id": [3026], "version_anchor": "(3)"},
    {"page_name": "Super restore", "item_name": "Super restore (4)", "item_id": [3024], "version_anchor": "(4)"},
    {"page_name": "Snapdragon potion (unfinished)", "item_name": "Snapdragon potion (unfinished)", "item_id": [3004]},
    {"page_name": "Red spiders' eggs", "item_name": "Red spiders' eggs", "item_id": [223]},
]
RECIPES = [
    recipe_row(
        "Super restore",
        [item("Super restore (3)")],
        [item("Snapdragon potion (unfinished)"), item("Red spiders' eggs")],
    ),
    recipe_row("Super restore", [item("Super restore (4)")], [item("Super restore (3)", "4")]),
]


def run(scope):
    wiki = FakeWiki(INFOBOX, RECIPES)
    snapshot = fetch.fetch(scope, wiki.get, wiki.sleep, "2026-10-23")
    return wiki, snapshot


class QueryTest(unittest.TestCase):
    def test_quotes_names_that_contain_an_apostrophe(self):
        query = fetch.query("infobox_item", ["page_name"], "item_name", ["Red spiders' eggs"], 0)

        self.assertIn('"Red spiders\' eggs"', query)

    def test_escapes_a_double_quote_and_a_backslash(self):
        query = fetch.query("infobox_item", ["page_name"], "item_name", ['a"b\\c'], 0)

        self.assertIn('"a\\"b\\\\c"', query)

    def test_asks_for_each_value_with_or(self):
        query = fetch.query("recipe", ["page_name"], "production_output", ["A", "B"], 0)

        self.assertEqual(
            query,
            'bucket("recipe").select("page_name")'
            '.where(bucket.Or({"production_output", "A"}, {"production_output", "B"}))'
            ".limit(5000).offset(0).run()",
        )

    def test_url_uses_the_bucket_action(self):
        url = fetch.url("q")
        params = urllib.parse.parse_qs(urllib.parse.urlparse(url).query)

        self.assertTrue(url.startswith("https://runescape.wiki/api.php?"))
        self.assertEqual(params, {"action": ["bucket"], "format": ["json"], "query": ["q"]})


class FetchTest(unittest.TestCase):
    def test_keeps_only_recipe_rows_whose_first_output_is_in_the_scope(self):
        _, snapshot = run(["Super restore (3)"])

        outputs = [row["production_json"]["outputs"][0]["name"] for row in snapshot["recipe"]]
        self.assertEqual(outputs, ["Super restore (3)"])

    def test_parses_production_json(self):
        _, snapshot = run(["Super restore (3)"])

        self.assertEqual(snapshot["recipe"][0]["production_json"]["ticks"], "2")

    def test_gets_the_infobox_rows_of_each_item_in_the_kept_rows(self):
        _, snapshot = run(["Super restore (3)"])

        names = [row["item_name"] for row in snapshot["infobox_item"]]
        self.assertEqual(names, ["Red spiders' eggs", "Snapdragon potion (unfinished)", "Super restore (3)"])

    def test_header_gives_the_source_date_and_licence(self):
        _, snapshot = run(["Super restore (3)"])

        self.assertEqual(snapshot["source"], "https://runescape.wiki/api.php?action=bucket")
        self.assertEqual(snapshot["date"], "2026-10-23")
        self.assertEqual(snapshot["licence"], "CC BY-NC-SA 3.0")

    def test_waits_one_second_between_requests(self):
        wiki, _ = run(["Super restore (3)"])

        self.assertEqual(wiki.calls[0], "get")
        for before, after in zip(wiki.calls, wiki.calls[1:]):
            self.assertNotEqual(before, after)
        self.assertIn(("sleep", 1), wiki.calls)

    def test_stops_with_an_error_that_names_a_scope_item_with_no_infobox_row(self):
        with self.assertRaisesRegex(fetch.FetchError, "Not an item"):
            run(["Not an item"])

    def test_asks_for_more_rows_when_a_query_gives_the_maximum(self):
        wiki = FakeWiki(INFOBOX, RECIPES)
        full = {"bucket": [INFOBOX[0]] * fetch.MAX_ROWS}
        replies = iter([full, {"bucket": []}])

        rows = fetch.all_rows(lambda u: (wiki.urls.append(u), next(replies))[1], wiki.sleep, "infobox_item", ["page_name"], "item_name", ["x"])

        self.assertEqual(len(rows), fetch.MAX_ROWS)
        self.assertIn(".offset(5000)", urllib.parse.unquote_plus(wiki.urls[1]))

    def test_asks_for_at_most_50_values_in_one_query(self):
        wiki = FakeWiki(INFOBOX, RECIPES)

        fetch.all_rows(wiki.get, wiki.sleep, "infobox_item", ["page_name"], "item_name", [str(n) for n in range(51)])

        counts = [urllib.parse.unquote_plus(u).count('{"item_name"') for u in wiki.urls]
        self.assertEqual(counts, [50, 1])


class WriteTest(unittest.TestCase):
    def test_sorts_keys_and_ends_with_a_newline(self):
        text = fetch.dumps({"b": 1, "a": {"d": 2, "c": 3}})

        self.assertEqual(text, '{\n "a": {\n  "c": 3,\n  "d": 2\n },\n "b": 1\n}\n')

    def test_keeps_non_ascii_text(self):
        self.assertIn("é", fetch.dumps({"a": "é"}))


class UserAgentTest(unittest.TestCase):
    def test_names_the_project_and_its_url(self):
        self.assertEqual(
            fetch.USER_AGENT,
            "rs-production-planner-recipe-tools (https://github.com/gigosaurus/rs-production-planner)",
        )


if __name__ == "__main__":
    unittest.main()
