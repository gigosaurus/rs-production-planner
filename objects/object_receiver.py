import json
import os
import secrets
import sqlite3
from http.server import BaseHTTPRequestHandler, HTTPServer
from pathlib import Path

HOST = "127.0.0.1"
PORT = 8765
TOKEN = secrets.token_hex(24)
MAX_BODY = 4 * 1024 * 1024

OUTPUT = Path.cwd()
DB = sqlite3.connect(OUTPUT / "objects.sqlite3")
DB.execute("""
    CREATE TABLE IF NOT EXISTS objects (
        id INTEGER PRIMARY KEY,
        data TEXT NOT NULL
    )
""")
# Other config kinds (Param, Struct, Quest, Enum, VarPlayer).
# Obj rows stay in objects, so the migrator still works.
DB.execute("""
    CREATE TABLE IF NOT EXISTS configs (
        kind TEXT NOT NULL,
        id INTEGER NOT NULL,
        data TEXT NOT NULL,
        PRIMARY KEY (kind, id)
    )
""")
DB.commit()


def stored_count():
    objects = DB.execute("SELECT COUNT(*) FROM objects").fetchone()[0]
    configs = DB.execute("SELECT COUNT(*) FROM configs").fetchone()[0]
    return objects + configs


def write_json(destination, query):
    temporary = destination.with_suffix(".json.tmp")

    with temporary.open("w", encoding="utf-8") as file:
        file.write("[")
        first = True

        for (data,) in DB.execute(query):
            if not first:
                file.write(",\n")
            file.write(data)
            first = False

        file.write("]\n")

    os.replace(temporary, destination)


class Receiver(BaseHTTPRequestHandler):
    def reply(self, code, payload):
        body = json.dumps(payload).encode("utf-8")
        self.send_response(code)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def do_GET(self):
        if self.path != "/health":
            return self.reply(404, {"error": "Not found"})

        self.reply(200, {"ok": True, "stored": stored_count()})

    def do_POST(self):
        if self.headers.get("Authorization") != f"Bearer {TOKEN}":
            return self.reply(401, {"error": "Invalid export token"})

        if self.path not in ("/batch", "/finish"):
            return self.reply(404, {"error": "Not found"})

        try:
            length = int(self.headers.get("Content-Length", "0"))
        except ValueError:
            return self.reply(400, {"error": "Invalid Content-Length"})

        if length < 0 or length > MAX_BODY:
            self.close_connection = True
            return self.reply(413, {"error": "Request too large"})

        body = self.rfile.read(length)

        try:
            if self.path == "/batch":
                records = json.loads(body)

                if not isinstance(records, list):
                    raise ValueError("Expected a JSON array")

                objects = []
                configs = []

                for record in records:
                    if not isinstance(record, dict):
                        raise ValueError("Every entry must be an object")

                    # Records from older probe versions have no kind.
                    kind = record.get("kind", "Obj")

                    if not isinstance(kind, str) or not kind.isalpha():
                        raise ValueError("Each entry needs a kind of letters only")

                    obj = record.get("object")

                    if not isinstance(obj, dict):
                        raise ValueError("Each entry needs an object section")

                    obj_id = obj.get("id")

                    if type(obj_id) is not int or obj_id < 0:
                        raise ValueError("Each object needs an integer id")

                    encoded = json.dumps(
                        record,
                        ensure_ascii=False,
                        separators=(",", ":"),
                        allow_nan=False,
                    )

                    if kind == "Obj":
                        objects.append((obj_id, encoded))
                    else:
                        configs.append((kind, obj_id, encoded))

                with DB:
                    DB.executemany(
                        "INSERT OR REPLACE INTO objects(id, data) VALUES (?, ?)",
                        objects,
                    )
                    DB.executemany(
                        "INSERT OR REPLACE INTO configs(kind, id, data) VALUES (?, ?, ?)",
                        configs,
                    )

                return self.reply(
                    200,
                    {
                        "ok": True,
                        "received": len(objects) + len(configs),
                        "stored": stored_count(),
                    },
                )

            objects_file = OUTPUT / "objects.json"
            configs_file = OUTPUT / "configs.json"
            write_json(objects_file, "SELECT data FROM objects ORDER BY id")
            write_json(configs_file, "SELECT data FROM configs ORDER BY kind, id")

            return self.reply(
                200,
                {"ok": True, "files": [str(objects_file), str(configs_file)]},
            )

        except (ValueError, TypeError) as error:
            self.reply(400, {"error": str(error)})
        except Exception as error:
            self.reply(500, {"error": str(error)})


print(f"Receiver: http://{HOST}:{PORT}")
print(f"Export token: {TOKEN}")
print(f"Output directory: {OUTPUT}")
print("Press Ctrl+C to stop.")

try:
    HTTPServer((HOST, PORT), Receiver).serve_forever()
except KeyboardInterrupt:
    pass
finally:
    DB.close()
