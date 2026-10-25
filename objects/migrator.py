#!/usr/bin/env python3

import argparse
import json
import sqlite3
from pathlib import Path


# Fields extracted from the JSON's "object" property.
OBJECT_COLUMNS = {
    "configName": "TEXT",
    "typeName": "TEXT",
    "name": "TEXT",
    "isMembers": "INTEGER",
    "category": "INTEGER",
    "teamID": "INTEGER",
    "cost": "INTEGER",
    "stackType": "INTEGER",
    "isStockmarket": "INTEGER",
    "stockmarketBuyLimit": "INTEGER",
    "isTradeable": "INTEGER",
    "quests": "TEXT",
    "groundOpNames": "TEXT",
    "interfaceOpNames": "TEXT",
    "stackCountAltObjs": "TEXT",
    "params": "TEXT",
}

# Fields extracted from the JSON's top level.
ROOT_COLUMNS = {
    "export": "TEXT",
    "inspector": "TEXT",
}

COLUMNS = ["id", *OBJECT_COLUMNS, *ROOT_COLUMNS, "data"]


def json_text(value):
    return json.dumps(
        value,
        ensure_ascii=False,
        separators=(",", ":"),
        allow_nan=False,
    )


def sql_value(value):
    if isinstance(value, (dict, list)):
        return json_text(value)
    if isinstance(value, bool):
        return int(value)
    return value


def convert_row(source_id, raw_data):
    document = json.loads(raw_data)

    if not isinstance(document, dict):
        raise ValueError("data must contain a JSON object")

    if not isinstance(document.get("object"), dict):
        raise ValueError("data.object must contain a JSON object")

    # Work on the parsed document, removing extracted fields as we go.
    obj = document["object"]
    values = [source_id]

    # The table ID is authoritative. Refuse to silently discard a
    # conflicting ID embedded in the JSON.
    if "id" in obj and obj["id"] != source_id:
        raise ValueError(
            f"JSON object.id {obj['id']!r} differs from "
            f"objects.id {source_id!r}"
        )
    obj.pop("id", None)

    for column in OBJECT_COLUMNS:
        values.append(sql_value(obj.pop(column, None)))

    for column in ROOT_COLUMNS:
        values.append(sql_value(document.pop(column, None)))

    if not obj:
        document.pop("object")

    values.append(json_text(document))
    return values


def migrate(database):
    if not database.is_file():
        raise FileNotFoundError(f"Database does not exist: {database}")

    connection = sqlite3.connect(database)

    try:
        connection.execute("BEGIN IMMEDIATE")

        definitions = [
            '"id" INTEGER PRIMARY KEY',
            *(
                f'"{name}" {column_type}'
                for name, column_type in OBJECT_COLUMNS.items()
            ),
            *(
                f'"{name}" {column_type}'
                for name, column_type in ROOT_COLUMNS.items()
            ),
            '"data" TEXT NOT NULL',
        ]

        # Deliberately fails if items already exists.
        connection.execute(
            f'CREATE TABLE "items" ({", ".join(definitions)})'
        )

        column_names = ", ".join(f'"{name}"' for name in COLUMNS)
        placeholders = ", ".join("?" for _ in COLUMNS)
        insert_sql = (
            f'INSERT INTO "items" ({column_names}) '
            f"VALUES ({placeholders})"
        )

        source = connection.execute('SELECT "id", "data" FROM "objects"')
        count = 0

        for source_id, raw_data in source:
            try:
                values = convert_row(source_id, raw_data)
                connection.execute(insert_sql, values)
            except Exception as exc:
                raise RuntimeError(
                    f"Failed to migrate objects.id={source_id!r}: {exc}"
                ) from exc

            count += 1

        connection.commit()
        return count

    except BaseException:
        connection.rollback()
        raise
    finally:
        connection.close()


def main():
    parser = argparse.ArgumentParser(
        description="Extract objects JSON into a new items table."
    )
    parser.add_argument("database", type=Path, help="SQLite database file")
    args = parser.parse_args()

    count = migrate(args.database)
    print(f"Migrated {count:,} rows into items.")


if __name__ == "__main__":
    main()