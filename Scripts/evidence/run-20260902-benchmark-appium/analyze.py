#!/usr/bin/env python3
"""Compara lo que costó el mismo escenario en CuyScout y en Appium.

Lee los registros del proxy medidor y resume tokens leídos/escritos por el agente,
desglosados por endpoint. Los tokens son reales (cl100k_base) sobre el texto que
viajaría en la conversación del agente.
"""
import collections
import json
import sys


def load(path):
    entries = []
    try:
        with open(path) as handle:
            for line in handle:
                line = line.strip()
                if line:
                    entries.append(json.loads(line))
    except FileNotFoundError:
        pass
    return entries


def summarize(entries):
    total_in = sum(e["resp_tokens"] for e in entries)
    total_out = sum(e["req_tokens"] for e in entries)
    by_path = collections.defaultdict(lambda: {"calls": 0, "in": 0, "out": 0, "bytes": 0})
    for e in entries:
        key = f'{e["method"]} {e["path"]}'
        row = by_path[key]
        row["calls"] += 1
        row["in"] += e["resp_tokens"]
        row["out"] += e["req_tokens"]
        row["bytes"] += e["resp_bytes"]
    return {
        "calls": len(entries),
        "tokens_in": total_in,
        "tokens_out": total_out,
        "tokens_total": total_in + total_out,
        "bytes_in": sum(e["resp_bytes"] for e in entries),
        "wall_ms": sum(e["ms"] for e in entries),
        "by_path": by_path,
    }


def table(name, data, limit=12):
    print(f"\n{name}")
    print(f"  llamadas HTTP        {data['calls']}")
    print(f"  tokens leídos        {data['tokens_in']:,}")
    print(f"  tokens escritos      {data['tokens_out']:,}")
    print(f"  TOKENS TOTALES       {data['tokens_total']:,}")
    print(f"  bytes recibidos      {data['bytes_in']:,}")
    print(f"  tiempo en servidor   {data['wall_ms'] / 1000:.1f} s")
    rows = sorted(data["by_path"].items(), key=lambda kv: -kv[1]["in"])[:limit]
    if rows:
        print(f"  {'endpoint':<52} {'n':>4} {'tokens leídos':>14}")
        for key, row in rows:
            print(f"  {key[:52]:<52} {row['calls']:>4} {row['in']:>14,}")


cuyscout = summarize(load(sys.argv[1]))
appium = summarize(load(sys.argv[2]))
table("CUYSCOUT", cuyscout)
table("APPIUM", appium)

print("\nCOMPARACIÓN")
for label, key in (("tokens totales", "tokens_total"), ("tokens leídos", "tokens_in"), ("llamadas HTTP", "calls")):
    c, a = cuyscout[key], appium[key]
    if c and a:
        ratio = a / c
        saved = (1 - c / a) * 100
        print(f"  {label:<18} CuyScout {c:>9,}   Appium {a:>9,}   ×{ratio:.1f}   ahorro {saved:.0f}%")
    else:
        print(f"  {label:<18} CuyScout {c:>9,}   Appium {a:>9,}")
