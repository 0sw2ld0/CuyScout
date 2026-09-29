#!/usr/bin/env python3
"""Benchmark: generar una prueba con CuyScout decidiendo con LLM solo vs. LLM + Laya.

Modo "llm":  el LLM decide cada acción (escenario + historial + pantalla).
Modo "laya": el LLM descompone el .feature una vez en pasos atómicos; Laya elige la
             acción de cada paso y, si su confianza es baja, se deriva al LLM.
             Las verificaciones se comprueban buscando el texto esperado en pantalla.

Genérico: recibe feature, fixtures, app y UDID; no conoce la app.
"""
import argparse, difflib, json, re, subprocess, sys, time, unicodedata, urllib.request
from pathlib import Path

GATEWAY = "http://127.0.0.1:4723"
LLM_SYSTEM = ("Eres el componente de decisión de un agente que prueba apps iOS con CuyScout. "
              "Responde solo con un objeto JSON válido, sin texto adicional ni bloques de código.")


class HttpLaya:
    """Cliente del servicio Laya compartido (API compatible con Jev: POST /v1/systemone)."""
    def __init__(self, url):
        self.url = url.rstrip("/")

    def predict(self, state, questions, model=None):
        body = json.dumps({"state": state, "questions": questions, **({"model": model} if model else {})}).encode()
        req = urllib.request.Request(self.url + "/v1/systemone", data=body, method="POST", headers={"Content-Type": "application/json"})
        with urllib.request.urlopen(req, timeout=30) as r:
            return json.loads(r.read())


class Meter:
    def __init__(self):
        self.llm_calls = self.llm_in = self.llm_out = 0
        self.llm_cost = self.llm_ms = 0.0
        self.laya_calls = 0
        self.laya_ms = 0.0
        self.fallbacks = 0
        self.device_ms = 0.0
        self.actions = 0
        self.log = []


def http(method, path, body=None, timeout=120):
    data = json.dumps(body).encode() if body is not None else None
    req = urllib.request.Request(GATEWAY + path, data=data, method=method,
                                 headers={"Content-Type": "application/json"})
    try:
        with urllib.request.urlopen(req, timeout=timeout) as r:
            raw = r.read().decode()
    except urllib.error.HTTPError as e:
        raw = e.read().decode()
    try:
        return json.loads(raw)
    except ValueError:
        return raw


LESSONS_TEXT = ""


def llm(meter, prompt, model):
    if LESSONS_TEXT:
        prompt = LESSONS_TEXT + "\n\n" + prompt
    t = time.perf_counter()
    cmd = ["claude", "-p", "--model", model, "--system-prompt", LLM_SYSTEM, "--tools", "",
           "--strict-mcp-config", "--setting-sources", "", "--no-session-persistence", "--output-format", "json", prompt]
    try:
        out = subprocess.run(cmd, capture_output=True, text=True, cwd="/tmp", timeout=180)
    except subprocess.TimeoutExpired:
        meter.log.append({"llm_timeout_reintento": True})
        out = subprocess.run(cmd, capture_output=True, text=True, cwd="/tmp", timeout=180)
    meter.llm_ms += (time.perf_counter() - t) * 1000
    meter.llm_calls += 1
    data = json.loads(out.stdout)
    u = data.get("usage", {})
    meter.llm_in += u.get("input_tokens", 0) + u.get("cache_creation_input_tokens", 0) + u.get("cache_read_input_tokens", 0)
    meter.llm_out += u.get("output_tokens", 0)
    meter.llm_cost += data.get("total_cost_usd") or 0
    text = data.get("result", "")
    m = re.search(r"\{.*\}|\[.*\]", text, re.S)
    return json.loads(m.group(0)) if m else {}


PREFIX = {"btn": "botón", "input": "campo", "tab": "pestaña", "cell": "fila", "switch": "interruptor",
          "link": "enlace", "label": "texto", "row": "fila", "card": "tarjeta", "item": "elemento"}


def observe(meter):
    # Espera a que la pantalla se estabilice: dos lecturas no vacías seguidas con el mismo
    # stateId. Evita tocar durante una transición o mientras aparece una alerta del sistema
    # (p. ej. «¿Guardar contraseña?»), lo que cuelga el runner XCTest.
    # Tras enviar un formulario con un campo sensible (risk=high) iOS puede mostrar tarde una
    # alerta del sistema; ahí se exigen 3 lecturas iguales espaciadas 1 s.
    global EXTENDED_SETTLE
    need, pause = (3, 1.0) if EXTENDED_SETTLE else (2, 0.8)
    EXTENDED_SETTLE = False
    t = time.perf_counter()
    previous, same = None, 0
    for _ in range(12):
        obs = http("GET", "/session/%s/observe?maxActions=20" % SESSION).get("value") or {}
        empty = not (obs.get("texts") or obs.get("actions"))
        same = same + 1 if (not empty and obs.get("stateId") == previous) else (0 if empty else 1)
        if same >= need:
            break
        previous = None if empty else obs.get("stateId")
        time.sleep(pause)
    meter.device_ms += (time.perf_counter() - t) * 1000
    for a in obs.get("actions", []):
        if a.get("risk") == "high" and a["action"]["type"] == "typeElement":
            SENSITIVE_FIELDS.add(a["action"]["selector"]["value"])
    labels = {}
    for text in obs.get("texts", []):
        m = re.match(r"^([A-Za-z0-9_.-]+): (.+)$", text)
        if m:
            labels[m[1]] = m[2]
    options = {}
    for i, a in enumerate(obs.get("actions", [])):
        x = a["action"]
        ident = x["selector"]["value"]
        parts = ident.split("_")
        head = PREFIX.get(parts[0].lower())
        name = f"{head or 'control'} {' '.join(parts[1:] if head else parts)}"
        verb = "escribir en" if x["type"] == "typeElement" else "tocar"
        extra = f" ({labels[ident]})" if ident in labels else ""
        options[f"a{i}"] = {"label": f"{verb} {name}{extra}", "action": x}
    return obs, options


EXTENDED_SETTLE = False
SENSITIVE_FIELDS = set()
PENDING_SENSITIVE = False


def act(meter, action, text=None):
    global EXTENDED_SETTLE, PENDING_SENSITIVE
    if action["type"] == "typeElement" and action["selector"]["value"] in SENSITIVE_FIELDS:
        PENDING_SENSITIVE = True
    elif action["type"] == "tapElement" and PENDING_SENSITIVE:
        EXTENDED_SETTLE, PENDING_SENSITIVE = True, False
    body = {"type": action["type"], "selector": action["selector"]}
    if action["type"] == "typeElement":
        body["text"] = text or ""
    t = time.perf_counter()
    res = http("POST", "/session/%s/actions?repair=true" % SESSION, body)
    meter.device_ms += (time.perf_counter() - t) * 1000
    meter.actions += 1
    ok = not (isinstance(res, dict) and isinstance(res.get("value"), dict) and res["value"].get("error"))
    if not ok:
        meter.log.append({"accion_fallida": body, "respuesta": str(res)[:300]})
    return ok, res


def norm(s):
    s = unicodedata.normalize("NFKD", s.lower())
    return re.sub(r"\s+", " ", "".join(c for c in s if not unicodedata.combining(c)))


def screen_summary(obs, options):
    return {"textos": obs.get("texts", [])[:40],
            "acciones": {k: v["label"] for k, v in options.items()}}


EXPLICIT_VALUES_RULE = False
VALUE_RULE = ("Cada valor que el escenario nombra (cuenta de origen, destino, monto…) se elige de forma explícita y se "
              "comprueba en el resumen. Un valor preseleccionado por la app no cuenta como elegido. Si lo pedido no coincide "
              "exactamente con ninguna opción, elige la más parecida y dilo; si es ambiguo, detente. Nunca declares terminado "
              "si un valor pedido no se ve en el resumen.")


def run_llm_mode(meter, feature, fixtures, model, budget):
    history = []
    for _ in range(budget):
        obs, options = observe(meter)
        prompt = ("Escenario Gherkin a cumplir:\n" + feature + "\n\nDatos de prueba (fixtures): " + json.dumps(fixtures, ensure_ascii=False) +
                  "\n\nAcciones ya ejecutadas (en orden): " + json.dumps(history[-12:], ensure_ascii=False) +
                  "\n\nPantalla actual: " + json.dumps(screen_summary(obs, options), ensure_ascii=False) +
                  "\n\nDecide la SIGUIENTE acción. Responde JSON: {\"accion\": \"aN\" o null, \"texto\": valor a escribir si la acción es escribir, "
                  "\"estado\": \"continuar\" | \"terminado\" (todos los pasos y verificaciones del escenario cumplidos en pantalla) | \"fallo\", \"motivo\": breve}. "
                  "Antes de confirmar una acción irreversible verifica en los textos que los datos coinciden con el escenario."
                  + (" " + VALUE_RULE if EXPLICIT_VALUES_RULE else ""))
        d = llm(meter, prompt, model)
        estado = d.get("estado")
        if estado in ("terminado", "fallo"):
            return estado == "terminado", d.get("motivo", "")
        key = d.get("accion")
        if key not in options:
            history.append({"error": f"acción inválida {key}"})
            continue
        ok, _ = act(meter, options[key]["action"], d.get("texto"))
        history.append({"accion": options[key]["label"], "texto": d.get("texto"), "ok": ok})
        meter.log.append({"decisor": "llm", "accion": options[key]["label"]})
    return False, "presupuesto agotado"


def run_laya_mode(meter, feature, fixtures, model, budget, router, threshold, laya_model):
    plan_prompt = ("Descompón este escenario Gherkin en pasos atómicos para una app iOS que no conoces.\n" + feature +
                   "\n\nDatos de prueba (fixtures): " + json.dumps(fixtures, ensure_ascii=False) +
                   "\n\nResponde JSON: {\"pasos\": [ {\"tipo\": \"accion\", \"descripcion\": frase corta de UNA interacción (tocar o escribir) en español, "
                   "\"valor\": texto exacto a escribir o null}, {\"tipo\": \"verificar\", \"esperado\": [fragmentos de texto que deben verse en pantalla]} ]}. "
                   "Usa los valores reales de los fixtures y del escenario. No conoces las pantallas: describe la navegación por intención y no inventes "
                   "etiquetas de la interfaz. En \"esperado\" pon SOLO valores literales que el escenario menciona (montos, números, nombres citados), "
                   "nunca textos de interfaz supuestos. Verifica solo donde el escenario lo pide (antes de confirmar y en el resultado).")
    plan = llm(meter, plan_prompt, model).get("pasos", [])
    meter.log.append({"plan": plan})
    i, used, stuck = 0, 0, 0
    while i < len(plan) and used < budget:
        step = plan[i]
        obs, options = observe(meter)
        used += 1
        if step.get("tipo") == "verificar":
            screen = norm(" ".join(obs.get("texts", [])))
            missing = [e for e in step.get("esperado", []) if norm(str(e)) not in screen]
            if not missing:
                meter.log.append({"verificado": step.get("esperado")})
                i, stuck = i + 1, 0
                continue
            stuck += 1
            if stuck < 2:
                time.sleep(1)
                continue
            if stuck >= 5:
                return False, f"no se vio en pantalla: {missing}"
            meter.fallbacks += 1
            prompt = ("Escenario completo:\n" + feature + "\n\nPaso actual: verificar que en pantalla se vea " + json.dumps(missing, ensure_ascii=False) +
                      ". Pasos siguientes: " + json.dumps(plan[i + 1:i + 4], ensure_ascii=False) +
                      "\nPantalla actual: " + json.dumps(screen_summary(obs, options), ensure_ascii=False) +
                      "\n\nLa pantalla no lo muestra. Puede haber una interrupción (diálogo, permiso) o faltar navegación. "
                      "Responde JSON: {\"accion\": \"aN\" o null, \"texto\": valor si hay que escribir, \"imposible\": true si el escenario no puede cumplirse}.")
            d = llm(meter, prompt, model)
            if d.get("imposible"):
                return False, f"verificación imposible: {missing}"
            if d.get("accion") in options:
                act(meter, options[d["accion"]]["action"], d.get("texto"))
                meter.log.append({"decisor": "llm-recuperacion", "paso": f"verificar {missing}", "accion": options[d["accion"]]["label"]})
            continue
        choice, conf = None, 0.0
        if options:
            criteria = {k: v["label"] for k, v in options.items()}
            t = time.perf_counter()
            res = router.predict("Paso a cumplir: " + step.get("descripcion", ""),
                                 {"accion": {"type": "choice", "instructions": "¿Qué acción cumple el paso?", "criteria": criteria}},
                                 model=laya_model)
            meter.laya_ms += (time.perf_counter() - t) * 1000
            meter.laya_calls += 1
            ans = res["answers"]["accion"]
            choice, conf = ans["choice"], max(ans["probabilities"].values())
            needs_text = options[choice]["action"]["type"] == "typeElement"
            if needs_text and not step.get("valor"):
                conf = 0.0
            if not needs_text and step.get("valor"):
                conf = 0.0
        if conf >= threshold:
            ok, _ = act(meter, options[choice]["action"], step.get("valor"))
            meter.log.append({"decisor": "laya", "paso": step.get("descripcion"), "accion": options[choice]["label"], "confianza": round(conf, 2)})
            i, stuck = i + 1, 0
            continue
        meter.fallbacks += 1
        laya_guess = {"accion": options[choice]["label"], "confianza": round(conf, 2)} if choice else None
        prompt = ("Escenario completo:\n" + feature + "\n\nPaso anterior (se asumió cumplido): " + json.dumps(plan[i - 1] if i else None, ensure_ascii=False) +
                  "\nPaso atómico actual: " + json.dumps(step, ensure_ascii=False) +
                  "\nPasos siguientes: " + json.dumps(plan[i + 1:i + 4], ensure_ascii=False) +
                  "\nPantalla actual: " + json.dumps(screen_summary(obs, options), ensure_ascii=False) +
                  "\n\nElige la acción que cumple el paso actual o, si no está disponible en esta pantalla, la que acerca a él. "
                  "Si la pantalla muestra que el paso anterior quedó a medias (por ejemplo una lista abierta), elige la acción que lo termina y responde cumple_paso=false. "
                  "Abrir un selector o una lista no cumple un paso de seleccionar. "
                  "Responde JSON: {\"accion\": \"aN\" o null, \"texto\": valor si hay que escribir, \"cumple_paso\": true si esta acción completa el paso actual, "
                  "\"paso_ya_cumplido\": true si la pantalla muestra que el paso ya estaba hecho}.")
        d = llm(meter, prompt, model)
        if d.get("paso_ya_cumplido"):
            i, stuck = i + 1, 0
            continue
        key = d.get("accion")
        if key not in options:
            stuck += 1
            if stuck >= 3:
                return False, f"sin acción válida para: {step}"
            continue
        ok, _ = act(meter, options[key]["action"], d.get("texto") or step.get("valor"))
        meter.log.append({"decisor": "llm-fallback", "paso": step.get("descripcion"), "accion": options[key]["label"],
                          "laya_habria_elegido": laya_guess, "cumple_paso": bool(d.get("cumple_paso"))})
        if d.get("cumple_paso"):
            i, stuck = i + 1, 0
        else:
            stuck += 1
            if stuck >= 5:
                return False, f"atascado en: {step}"
    return i >= len(plan), ("plan completado" if i >= len(plan) else "presupuesto agotado")


PLAN_V2 = (
    "Descompón este escenario Gherkin en pasos atómicos para una app iOS que no conoces.\n{feature}\n\n"
    "Datos de prueba (fixtures): {fixtures}\n\n"
    "Responde JSON: {{\"pasos\": [ {{\"intencion\": \"escribir\" | \"tocar\" | \"seleccionar\" | \"confirmar\" | \"verificar\", "
    "\"descripcion\": frase corta de UNA interacción, \"valor\": texto exacto a escribir (solo escribir), "
    "\"opcion\": lista de formas de nombrar la opción a elegir (solo seleccionar; incluye variantes y posibles typos corregidos), "
    "\"post\": lista de fragmentos que deben APARECER en pantalla tras completar el paso, o [] si no se pueden saber, "
    "\"irreversible\": true si confirma una operación que no se puede deshacer}} ]}}.\n"
    "La app arranca en su pantalla inicial sin nada hecho: incluye también los pasos para cumplir cada Given/Background "
    "(por ejemplo iniciar sesión con los datos de los fixtures). "
    "Reglas: no conoces las pantallas; no inventes textos de interfaz. Los fragmentos de \"post\" y de verificar deben salir de "
    "valores del escenario o fixtures (montos, nombres de cuentas, conceptos que el escenario dice que se verán). "
    "Seleccionar implica abrir y elegir: descríbelo como UN paso con su \"opcion\". Para confirmar, \"post\" debe pedir las señales "
    "del resultado que el escenario menciona (por ejemplo \"operación\"), no datos que ya se veían antes de confirmar. "
    "Incluye un paso verificar antes de confirmar y otro al final.")


def is_interruption(obs, options):
    """Alerta del sistema: pocas acciones, todas por label, y un texto que pregunta."""
    acts = [v["action"] for v in options.values()]
    return (0 < len(acts) <= 3 and all(a["selector"]["strategy"] == "label" for a in acts)
            and any(t.strip().endswith("?") for t in obs.get("texts", [])))


def fuzzy_in(token, text, ratio=0.8):
    """¿Aparece token en text, tolerando un typo (p. ej. «waller» ≈ «wallet»)?"""
    if token in text:
        return True
    n = len(token)
    return n >= 4 and any(difflib.SequenceMatcher(None, token, text[i:i + n]).ratio() >= ratio
                          for i in range(len(text) - n + 1))


def fragment_present(fragment, screen):
    """El fragmento está en pantalla literalmente o por la mayoría de sus palabras relevantes."""
    f = norm(fragment)
    if f in screen:
        return True
    tokens = re.findall(r"[a-z0-9]{4,}", f)
    return bool(tokens) and sum(1 for t in tokens if fuzzy_in(t, screen)) / len(tokens) >= 0.5


def match_option(candidates, wanted):
    """Elige la opción cuyas palabras aparecen más en alguna forma de nombrar lo pedido."""
    best, best_score, tie = None, 0.0, False
    for k, v in candidates.items():
        tokens = [t for t in re.findall(r"[a-z0-9]{3,}", norm(v["label"])) if t not in ("tocar", "control", "boton")]
        if not tokens:
            continue
        score = max(sum(1 for t in tokens if fuzzy_in(t, w.replace(" ", ""))) / len(tokens) for w in wanted)
        if score > best_score:
            best, best_score, tie = k, score, False
        elif score == best_score and score > 0:
            tie = True
    return best if best_score >= 0.5 and not tie else None


def is_global_nav(action):
    value = action["selector"]["value"]
    return "." in value or norm(value) in ("barra de pestanas", "tab bar")


def run_laya2_mode(meter, feature, fixtures, model, budget, router, threshold, laya_model):
    plan = llm(meter, PLAN_V2.format(feature=feature, fixtures=json.dumps(fixtures, ensure_ascii=False)), model).get("pasos", [])
    state = {"pasos": [dict(p, estado="pendiente") for p in plan], "elegidos": {}, "usados": set()}
    meter.log.append({"plan": plan})
    decisions = 0
    seen = set()

    def laya_choice(text, candidates):
        t = time.perf_counter()
        res = router.predict(text, {"accion": {"type": "choice", "instructions": "¿Qué acción cumple el paso?",
                                               "criteria": {k: v["label"] for k, v in candidates.items()}}}, model=laya_model)
        meter.laya_ms += (time.perf_counter() - t) * 1000
        meter.laya_calls += 1
        ans = res["answers"]["accion"]
        return ans["choice"], max(ans["probabilities"].values())

    for step in state["pasos"]:
        step["estado"] = "en_curso"
        tried = set()
        intent = step.get("intencion")
        post = [str(x) for x in (step.get("post") or [])]
        if not post and (intent == "confirmar" or step.get("irreversible")):
            # Sin postcondición propia, un paso irreversible toma la de la verificación siguiente.
            nxt = state["pasos"][state["pasos"].index(step) + 1:]
            verify = next((p for p in nxt if p.get("intencion") == "verificar"), None)
            if verify:
                post = [str(x) for x in (verify.get("post") or []) + (verify.get("esperado") or [])]
        for attempt in range(6):
            if decisions >= budget:
                return False, "presupuesto agotado"
            obs, options = observe(meter)
            seen.update(norm(t) for t in obs.get("texts", []))
            if intent == "verificar":
                screen = norm(" ".join(obs.get("texts", [])))
                missing = [e for e in post + [str(x) for x in step.get("esperado", [])] if not fragment_present(e, screen)]
                if not missing:
                    break
                if attempt >= 2:
                    return False, f"no se vio en pantalla: {missing}"
                time.sleep(1)
                continue
            if is_interruption(obs, options):
                key, conf = laya_choice("Descartar el aviso del sistema sin aceptar nada", options)
                if conf < 0.5:
                    meter.fallbacks += 1
                    key = llm(meter, "Aviso del sistema en pantalla: " + json.dumps(screen_summary(obs, options), ensure_ascii=False) +
                              "\nElige la opción que lo descarta sin aceptar nada. Responde JSON {\"accion\": \"aN\"}.", model).get("accion")
                if key in options:
                    act(meter, options[key]["action"])
                    meter.log.append({"decisor": "interrupcion", "accion": options[key]["label"]})
                decisions += 1
                continue
            before_texts, before_state = set(obs.get("texts", [])), obs.get("stateId")
            want = "typeElement" if intent == "escribir" else "tapElement"
            candidates = {k: v for k, v in options.items() if v["action"]["type"] == want and not is_global_nav(v["action"])
                          and v["action"]["selector"]["value"] not in state["usados"] | tried}
            chosen, decisor, conf, typed = None, None, None, None
            wanted = [norm(o) for o in (step.get("opcion") or []) if o]
            if intent == "seleccionar" and wanted:
                key = match_option(candidates, wanted)
                if key:
                    chosen, decisor = key, "coincidencia"
            if not chosen and len(candidates) == 1:
                chosen, decisor = next(iter(candidates)), "unica-opcion"
            # Si el paso nombra qué elegir y no hubo coincidencia clara, no se deja adivinar a Laya.
            named_pick = intent == "seleccionar" and wanted and all(v["action"]["selector"]["strategy"] == "label" for v in candidates.values())
            if not chosen and candidates and not named_pick:
                context = "; ".join(f"{k}: {v}" for k, v in state["elegidos"].items())
                key, conf = laya_choice("Paso a cumplir: " + step.get("descripcion", "") + (f" (ya elegido: {context})" if context else ""), candidates)
                limit = max(threshold, 0.6) if step.get("irreversible") else threshold
                if conf >= limit:
                    chosen, decisor = key, "laya"
            if not chosen:
                meter.fallbacks += 1
                d = llm(meter, "Escenario:\n" + feature + "\n\nEstado de la petición: " + json.dumps(
                    [{k: p.get(k) for k in ("descripcion", "estado")} for p in state["pasos"]], ensure_ascii=False) +
                    "\nElegidos: " + json.dumps(state["elegidos"], ensure_ascii=False) +
                    "\nPaso actual: " + json.dumps(step, ensure_ascii=False) +
                    "\nPantalla actual: " + json.dumps(screen_summary(obs, options), ensure_ascii=False) +
                    "\n\nElige la acción que avanza el paso actual (si no está en pantalla, la que acerca a él). "
                    "Responde JSON {\"accion\": \"aN\" o null, \"texto\": valor si hay que escribir, \"paso_ya_cumplido\": true|false}.", model)
                if d.get("paso_ya_cumplido"):
                    break
                chosen, decisor = d.get("accion"), "llm-fallback"
                if chosen not in options:
                    continue
                typed = d.get("texto")
            decisions += 1
            action = options[chosen]["action"]
            seen_before = " ".join(seen)
            ok, _ = act(meter, action, step.get("valor") or typed)
            meter.log.append({"decisor": decisor, "paso": step.get("descripcion"), "accion": options[chosen]["label"],
                              "confianza": round(conf, 2) if conf is not None else None})
            tried.add(action["selector"]["value"])
            if intent == "escribir":
                if ok:
                    break
                continue
            obs2, _ = observe(meter)
            new_texts = norm(" ".join(t for t in obs2.get("texts", []) if t not in before_texts))
            # Una postcondición solo cuenta como evidencia nueva: se ignoran fragmentos ya vistos.
            fresh = [f for f in post if norm(f) not in seen_before]
            seen.update(norm(t) for t in obs2.get("texts", []))
            if fresh:
                done = any(fragment_present(f, new_texts) for f in fresh)
            elif intent == "seleccionar":
                if action["selector"]["strategy"] == "label":
                    done = norm(action["selector"]["value"]) in new_texts
                else:
                    # Un "seleccionar" que navega: pantalla nueva con contenido (no una lista abierta).
                    done = obs2.get("stateId") != before_state and bool(obs2.get("texts"))
            else:
                done = obs2.get("stateId") != before_state and bool(obs2.get("texts"))
            if done:
                break
        else:
            return False, f"no se cumplió: {step.get('descripcion')}"
        step["estado"] = "cumplido"
        if intent in ("seleccionar", "tocar", "confirmar") and tried:
            state["usados"] |= tried
        if intent == "seleccionar" and tried:
            state["elegidos"][step.get("descripcion", "")] = meter.log[-1].get("accion")
        meter.log.append({"cumplido": step.get("descripcion")})
    return True, "plan completado"


def main():
    global SESSION
    p = argparse.ArgumentParser()
    p.add_argument("--mode", choices=["llm", "laya", "laya2"], required=True)
    p.add_argument("--feature", required=True)
    p.add_argument("--fixtures", required=True)
    p.add_argument("--app", required=True)
    p.add_argument("--udid", required=True)
    p.add_argument("--model", default="sonnet")
    p.add_argument("--laya-model", default="english")
    p.add_argument("--threshold", type=float, default=0.6)
    p.add_argument("--budget", type=int, default=40)
    p.add_argument("--out", required=True)
    p.add_argument("--regla-valores", action="store_true", help="incluye la regla de valores explícitos en el modo llm")
    p.add_argument("--laya-url", default=__import__("os").environ.get("CUYSCOUT_LAYA_URL"), help="servicio Laya compartido; si falta, carga Laya en el proceso")
    p.add_argument("--lessons", action="store_true", help="lee las lecciones de CuyScout para esta app y las da al LLM")
    p.add_argument("--learn", action="store_true", help="si el intento falla (según --oracle), registra una lección candidata")
    p.add_argument("--oracle", action="append", default=[], help="requisito 'fragmento=>mensaje de negocio' evaluado en la pantalla final")
    a = p.parse_args()
    global EXPLICIT_VALUES_RULE
    EXPLICIT_VALUES_RULE = a.regla_valores
    feature, fixtures = Path(a.feature).read_text(), json.loads(Path(a.fixtures).read_text())
    meter, router, laya_load = Meter(), None, 0.0
    if a.mode in ("laya", "laya2") and a.laya_url:
        t = time.perf_counter()
        router = HttpLaya(a.laya_url)
        router.predict("warmup", {"x": {"type": "choice", "instructions": "?", "criteria": {"a": "a", "b": "b"}}}, model=a.laya_model)
        laya_load = time.perf_counter() - t
    elif a.mode in ("laya", "laya2"):
        from laya import Router, DEFAULT_MODELS
        t = time.perf_counter()
        router = Router(models={a.laya_model: DEFAULT_MODELS[a.laya_model]}, default=a.laya_model, preload=True)
        router.predict("warmup", {"x": {"type": "choice", "instructions": "?", "criteria": {"a": "a", "b": "b"}}}, model=a.laya_model)
        laya_load = time.perf_counter() - t
    t0 = time.perf_counter()
    created = http("POST", "/session", {"capabilities": {"alwaysMatch": {"appium:app": a.app, "appium:automationName": "XCUITest", "appium:udid": a.udid}}})
    SESSION = created["value"]["sessionId"]
    http("POST", f"/session/{SESSION}/timeouts", {"implicit": 8000})
    while not http("GET", f"/session/{SESSION}/readiness")["value"].get("interactionReady"):
        time.sleep(1)
    session_s = time.perf_counter() - t0
    global LESSONS_TEXT
    used_lessons = []
    if a.lessons:
        got = http("GET", f"/session/{SESSION}/lessons?limit=10")
        used_lessons = got if isinstance(got, list) else (got.get("value") or got.get("lessons") or []) if isinstance(got, dict) else []
        if used_lessons:
            LESSONS_TEXT = ("Lecciones aprendidas en intentos anteriores con esta app (aplícalas):\n" +
                            "\n".join(f"- {l.get('title')}: {l.get('recommendation')}" for l in used_lessons))
    t1 = time.perf_counter()
    try:
        if a.mode == "llm":
            ok, reason = run_llm_mode(meter, feature, fixtures, a.model, a.budget)
        elif a.mode == "laya":
            ok, reason = run_laya_mode(meter, feature, fixtures, a.model, a.budget, router, a.threshold, a.laya_model)
        else:
            ok, reason = run_laya2_mode(meter, feature, fixtures, a.model, a.budget, router, a.threshold, a.laya_model)
    except Exception as exc:
        ok, reason = False, f"excepción: {exc}"
    scenario_s = time.perf_counter() - t1
    final_texts = (http("GET", f"/session/{SESSION}/observe?maxActions=5").get("value") or {}).get("texts", [])
    validation = http("GET", f"/session/{SESSION}/recording/plan/validate")
    export = http("GET", f"/session/{SESSION}/recording/appium/typescript")
    # Evaluación del intento y aprendizaje, antes de cerrar la sesión (la lección se ancla a la app).
    screen = " ".join(final_texts).lower()
    oracle = [o.split("=>", 1) for o in a.oracle]
    unmet = [msg for frag, msg in oracle if frag.lower() not in screen]
    oracle_ok = bool(oracle) and not unmet
    infra = reason.startswith("excepción") or any("Timeout esperando respuesta de XCTest" in json.dumps(e) for e in meter.log)
    learned, reinforced, learning_tokens = None, [], 0
    if a.learn and oracle and not oracle_ok and not infra:
        before = meter.llm_in + meter.llm_out
        d = llm(meter, "Un intento de generar esta prueba automatizada falló.\nEscenario:\n" + feature +
                "\n\nRequisitos del escenario que NO se cumplieron: " + json.dumps(unmet, ensure_ascii=False) +
                "\nMotivo reportado por el agente: " + reason[:300] +
                "\nPantalla final: " + json.dumps(final_texts[:30], ensure_ascii=False) +
                "\nLecciones que se aplicaron en este intento y NO bastaron: " + json.dumps([l.get("title") for l in used_lessons], ensure_ascii=False) + "\nDecisiones tomadas (en orden): " + json.dumps([e for e in meter.log if e.get("accion") or e.get("cumplido")][-25:], ensure_ascii=False) +
                "\n\nPropón UNA lección accionable para que el próximo intento no repita el error: qué hacer distinto en esta app, "
                "no un relato de esta corrida. No culpes a un camino de la app sin evidencia de que no lleva al objetivo: si el agente se atascó decidiendo cuándo un paso estaba cumplido o repitió controles, la lección es sobre esa decisión. No repitas ni contradigas una lección que no bastó; propón otra causa. Si la causa es de infraestructura (cuelgue, timeout), responde {\"infra\": true, \"motivo\": ...}. "
                "Si no, responde JSON {\"titulo\": ..., \"observacion\": ..., \"recomendacion\": ..., \"tags\": [...]}.", a.model)
        learning_tokens = meter.llm_in + meter.llm_out - before
        if d.get("titulo") and not d.get("infra"):
            learned = http("POST", "/lessons", {"scope": "project", "sessionId": SESSION, "title": d["titulo"],
                           "observation": d.get("observacion", ""), "recommendation": d.get("recomendacion", ""),
                           "evidence": "intento fallido; no cumplido: " + "; ".join(unmet), "tags": (d.get("tags") or []) + ["candidata"],
                           "confidence": 0.5})
        else:
            learned = {"infra": True, "motivo": d.get("motivo")}
    if used_lessons and oracle and not infra:
        outcome = "helped" if oracle_ok else "failed"
        for l in used_lessons:
            fb = http("POST", f"/lessons/{l.get('id')}/feedback", {"outcome": outcome})
            reinforced.append({"leccion": l.get("title"), "resultado": outcome,
                               "confianza": fb.get("confidence") if isinstance(fb, dict) else None})
    http("DELETE", f"/session/{SESSION}")
    result = {"mode": a.mode, "model": a.model, "laya_model": a.laya_model if a.mode != "llm" else None, "laya_url": a.laya_url if a.mode != "llm" else None,
              "threshold": a.threshold if a.mode != "llm" else None, "regla_valores": a.regla_valores, "session": SESSION, "success": ok, "reason": reason,
              "scenario_seconds": round(scenario_s, 1), "session_open_seconds": round(session_s, 1),
              "laya_load_seconds": round(laya_load, 1), "decision_seconds": round((meter.llm_ms + meter.laya_ms) / 1000, 1),
              "device_seconds": round(meter.device_ms / 1000, 1), "actions": meter.actions,
              "llm_calls": meter.llm_calls, "llm_input_tokens": meter.llm_in, "llm_output_tokens": meter.llm_out,
              "llm_total_tokens": meter.llm_in + meter.llm_out, "llm_cost_usd": round(meter.llm_cost, 4),
              "llm_seconds": round(meter.llm_ms / 1000, 1), "laya_calls": meter.laya_calls,
              "laya_seconds": round(meter.laya_ms / 1000, 2), "fallbacks": meter.fallbacks,
              "final_screen_texts": final_texts, "oracle_ok": oracle_ok, "unmet": unmet, "infra": infra, "lessons_used": [l.get("title") for l in used_lessons], "lesson_learned": learned, "lessons_reinforced": reinforced, "learning_tokens": learning_tokens, "plan_validation": validation, "log": meter.log}
    out = Path(a.out)
    out.parent.mkdir(parents=True, exist_ok=True)
    out.write_text(json.dumps(result, ensure_ascii=False, indent=1))
    if isinstance(export, str):
        out.with_suffix(".ts").write_text(export)
    print(json.dumps({k: v for k, v in result.items() if k not in ("log", "plan_validation")}, ensure_ascii=False))


if __name__ == "__main__":
    main()
