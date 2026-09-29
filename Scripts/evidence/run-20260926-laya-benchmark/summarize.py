#!/usr/bin/env python3
"""Agrega results/<tag>-*.json en tablas Markdown por modo.

--expect: fragmentos que deben aparecer en la pantalla final (verificación independiente).
"""
import argparse, glob, json, statistics as st
from pathlib import Path

NO_LLM = ("laya", "coincidencia", "unica-opcion", "interrupcion")

p = argparse.ArgumentParser()
p.add_argument("--dir", default=str(Path(__file__).parent / "results"))
p.add_argument("--tag", default="serie")
p.add_argument("--expect", action="append", default=[])
a = p.parse_args()

rows = []
for f in sorted(glob.glob(f"{a.dir}/{a.tag}-*.json")):
    d = json.loads(Path(f).read_text())
    final = " ".join(d.get("final_screen_texts", [])).lower()
    d["verified"] = bool(final) and all(e.lower() in final for e in a.expect)
    d["xctest_timeout"] = any("Timeout esperando respuesta de XCTest" in json.dumps(e) for e in d.get("log", []))
    d["no_llm"] = sum(1 for e in d.get("log", []) if e.get("decisor") in NO_LLM)
    d["file"] = Path(f).stem
    rows.append(d)

print("| Corrida | Declaró éxito | Correcta en pantalla | Escenario (s) | Decisión (s) | Acciones | Llamadas LLM | Tokens LLM | Decisiones sin LLM | Cuelgue XCTest |")
print("|---|---|---|---|---|---|---|---|---|---|")
for d in rows:
    print(f"| {d['file']} | {'sí' if d['success'] else 'no'} | {'✅' if d['verified'] else '❌'} | {d['scenario_seconds']} | "
          f"{d['decision_seconds']} | {d['actions']} | {d['llm_calls']} | {d['llm_total_tokens']} | {d['no_llm']} | "
          f"{'sí' if d['xctest_timeout'] else 'no'} |")

print("\n| Modo | Corridas | Correctas | Falsos éxitos | Escenario (s) prom. | Decisión (s) prom. | Llamadas LLM prom. | Tokens LLM prom. |")
print("|---|---|---|---|---|---|---|---|")
for mode in sorted({d["mode"] for d in rows}):
    rs = [d for d in rows if d["mode"] == mode]
    ok = [d for d in rs if d["verified"]]
    false_ok = sum(1 for d in rs if d["success"] and not d["verified"])
    src = ok or rs
    m = lambda k: round(st.mean(d[k] for d in src), 1)
    print(f"| {mode} | {len(rs)} | {len(ok)} | {false_ok} | {m('scenario_seconds')} | {m('decision_seconds')} | "
          f"{m('llm_calls')} | {round(st.mean(d['llm_total_tokens'] for d in src))} |")
print("\nPromedios calculados sobre las corridas correctas de cada modo (si no hay, sobre todas).")
