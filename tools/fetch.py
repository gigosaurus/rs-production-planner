"""Gets the recipe rows of the covered items from the RuneScape Wiki Bucket API.

Command: python3 tools/fetch.py
It reads tools/scope.json and writes tools/wiki-snapshot.json (ADR 0015).
It sends only GET requests, one at a time, with 1 second between requests.
It has no login, edit or post code. Only a human edits the wiki.
"""

import datetime
import json
import os
import sys
import time
import urllib.parse
import urllib.request

API = "https://runescape.wiki/api.php"
SOURCE = API + "?action=bucket"
LICENCE = "CC BY-NC-SA 3.0"
USER_AGENT = "rs-production-planner-recipe-tools (https://github.com/gigosaurus/rs-production-planner)"
WAIT_SECONDS = 1
# One query gives up to 5000 rows.
MAX_ROWS = 5000
# The number of values in one bucket.Or, so that the URL stays short.
MAX_VALUES = 50

RECIPE_FIELDS = ["page_name", "production_json"]
INFOBOX_FIELDS = ["page_name", "item_name", "item_id", "version_anchor"]

HERE = os.path.dirname(os.path.abspath(__file__))
SCOPE_PATH = os.path.join(HERE, "scope.json")
SNAPSHOT_PATH = os.path.join(HERE, "wiki-snapshot.json")


class FetchError(Exception):
    pass


def lua_string(text):
    return '"' + text.replace("\\", "\\\\").replace('"', '\\"') + '"'


def query(bucket, fields, field, values, offset):
    """Gives a Bucket query for the rows whose field has one of the values."""
    select = ", ".join(lua_string(f) for f in fields)
    conditions = ", ".join("{" + lua_string(field) + ", " + lua_string(v) + "}" for v in values)
    return (
        f"bucket({lua_string(bucket)}).select({select})"
        f".where(bucket.Or({conditions}))"
        f".limit({MAX_ROWS}).offset({offset}).run()"
    )


def url(bucket_query):
    return API + "?" + urllib.parse.urlencode({"action": "bucket", "format": "json", "query": bucket_query})


def http_get(request_url):
    request = urllib.request.Request(request_url, headers={"User-Agent": USER_AGENT})
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.load(response)


class Requests:
    """Sends one request at a time, and waits between two requests."""

    def __init__(self, get, sleep):
        self.get = get
        self.sleep = sleep
        self.sent = False

    def send(self, bucket_query):
        if self.sent:
            self.sleep(WAIT_SECONDS)
        self.sent = True
        reply = self.get(url(bucket_query))
        if "error" in reply or "bucket" not in reply:
            raise FetchError("The wiki did not give rows for the query " + bucket_query + ": " + json.dumps(reply))
        return reply["bucket"]


def rows_of(requests, bucket, fields, field, values):
    rows = []
    for start in range(0, len(values), MAX_VALUES):
        chunk = values[start : start + MAX_VALUES]
        offset = 0
        while True:
            page = requests.send(query(bucket, fields, field, chunk, offset))
            rows.extend(page)
            if len(page) < MAX_ROWS:
                break
            offset += MAX_ROWS
    return rows


def all_rows(get, sleep, bucket, fields, field, values):
    """Gives all rows whose field has one of the values. It asks again with an offset when a query gives the maximum."""
    return rows_of(Requests(get, sleep), bucket, fields, field, values)


def first_output(row):
    outputs = row["production_json"].get("outputs") or [{}]
    return outputs[0].get("name")


def item_names(rows):
    names = set()
    for row in rows:
        production = row["production_json"]
        for entry in production.get("outputs", []) + production.get("materials", []):
            names.add(entry["name"])
    return sorted(names)


def row_key(row):
    return json.dumps(row, sort_keys=True, ensure_ascii=False)


def fetch(scope, get, sleep, date):
    """Gives the snapshot of the recipe rows whose first Output is in the scope, and the infobox rows of their items."""
    requests = Requests(get, sleep)
    wanted = set(scope)

    scope_rows = rows_of(requests, "infobox_item", INFOBOX_FIELDS, "item_name", sorted(wanted))
    found = {row["item_name"] for row in scope_rows}
    missing = sorted(wanted - found)
    if missing:
        raise FetchError("The wiki has no infobox_item row for these scope items: " + ", ".join(missing))

    pages = sorted({row["page_name"] for row in scope_rows})
    recipes = []
    for row in rows_of(requests, "recipe", RECIPE_FIELDS, "production_output", pages):
        row = dict(row, production_json=json.loads(row["production_json"]))
        if first_output(row) in wanted:
            recipes.append(row)

    infobox = rows_of(requests, "infobox_item", INFOBOX_FIELDS, "item_name", item_names(recipes))

    return {
        "source": SOURCE,
        "date": date,
        "licence": LICENCE,
        "recipe": sorted(recipes, key=row_key),
        "infobox_item": sorted(infobox, key=lambda row: (row["item_name"], row_key(row))),
    }


def dumps(snapshot):
    return json.dumps(snapshot, indent=1, sort_keys=True, ensure_ascii=False) + "\n"


def main():
    with open(SCOPE_PATH, encoding="utf-8") as file:
        scope = json.load(file)
    date = datetime.datetime.now(datetime.timezone.utc).date().isoformat()
    try:
        snapshot = fetch(scope, http_get, time.sleep, date)
    except FetchError as error:
        print("Error: " + str(error), file=sys.stderr)
        return 1
    with open(SNAPSHOT_PATH, "w", encoding="utf-8", newline="\n") as file:
        file.write(dumps(snapshot))
    print(f"Wrote {len(snapshot['recipe'])} recipe rows and {len(snapshot['infobox_item'])} infobox rows.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
