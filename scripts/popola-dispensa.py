"""Popola le liste Dispensa e Dispensa Stagionale da lista-spesa.md.

Il nome del task è il prodotto, la descrizione è la categoria.
Ordine: per categoria come nel file, alfabetico all'interno.
I prodotti marcati [x] vengono segnati come completati.
"""
import json, pathlib, re, subprocess, time, unicodedata

SP = pathlib.Path(__file__).parent
TOKEN = (SP / "ha_token").read_text().strip()
BASE = "http://192.168.1.37/api/services/todo"
SRC = pathlib.Path.home() / "0Projects/lista-spesa/lista-spesa.md"

STAGIONALE = "Stagionale o Specifico"


def parse(path):
    """Restituisce {categoria: [(prodotto, spuntato), ...]} nell'ordine del file."""
    cats, cur = {}, None
    for line in path.read_text().splitlines():
        line = line.rstrip()
        if line.startswith("## "):
            cur = line[3:].strip()
            cats[cur] = []
        elif cur and (m := re.match(r"- \[([ xX])\] (.+)", line)):
            cats[cur].append((m.group(2).strip(), m.group(1).lower() == "x"))
    return cats


def sortkey(s):
    """Alfabetico ignorando accenti e maiuscole."""
    return unicodedata.normalize("NFKD", s.lower()).encode("ascii", "ignore")


def call(service, payload):
    r = subprocess.run(
        ["curl", "-s", "-o", "/dev/null", "-w", "%{http_code}", "-X", "POST",
         "-H", f"Authorization: Bearer {TOKEN}",
         "-H", "Content-Type: application/json",
         "-d", json.dumps(payload), f"{BASE}/{service}"],
        capture_output=True, text=True,
    )
    return r.stdout.strip()


def fill(entity, categories):
    added, done, failed = 0, 0, []
    for cat, items in categories.items():
        for name, checked in sorted(items, key=lambda t: sortkey(t[0])):
            code = call("add_item", {
                "entity_id": entity, "item": name, "description": cat,
            })
            if code != "200":
                failed.append((name, code))
                continue
            added += 1
            time.sleep(0.2)
            if checked:
                c2 = call("update_item", {
                    "entity_id": entity, "item": name, "status": "completed",
                })
                if c2 == "200":
                    done += 1
                else:
                    failed.append((f"{name} (completamento)", c2))
                time.sleep(0.2)
    return added, done, failed


cats = parse(SRC)
principali = {k: v for k, v in cats.items() if k != STAGIONALE}
stagionale = {k: v for k, v in cats.items() if k == STAGIONALE}

for entity, data in (("todo.dispensa", principali),
                     ("todo.dispensa_stagionale", stagionale)):
    a, d, f = fill(entity, data)
    tot = sum(len(v) for v in data.values())
    print(f"{entity}: {a}/{tot} inseriti, {d} segnati come presenti")
    for name, code in f:
        print(f"   FALLITO ({code}): {name}")
