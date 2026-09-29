# Laya como servicio local compartido

[Laya](https://github.com/NandhaKishorM/laya) es un modelo de decisión rápida (Apache 2.0,
compatible con la API de Jev): elige entre opciones que tú defines y devuelve probabilidades,
en decenas de milisegundos y sin tokens. Se instala **una vez** por máquina y cualquier programa
lo usa por HTTP; nadie carga su propia copia (2–3 GB de RAM).

## Instalar y arrancar

```bash
Scripts/laya/install_laya.sh                                   # idempotente
"$HOME/Library/Application Support/Laya/laya-service.sh" start # start | stop | status | restart
```

Todo queda en `~/Library/Application Support/Laya/`, fuera de cualquier proyecto:

| Ruta | Contenido |
|---|---|
| `venv/` | Python con `laya[serve]` |
| `models/` | caché de Hugging Face solo para Laya (`HF_HOME`) |
| `laya.env` | puerto, modelos a precargar, dispositivo, clave opcional |
| `logs/laya.log` | salida del servicio |

Por defecto escucha **solo en esta Mac** (`127.0.0.1:8791`) y precarga el checkpoint `english`;
`multilingual` y `typed-decisions` se cargan al primer uso. Si los modelos ya están descargados,
`HF_HUB_OFFLINE=1` en `laya.env` evita consultar la red al arrancar. Para exigir clave, define
`LAYA_API_KEY` y envía `Authorization: Bearer <clave>`.

## Usarlo desde cualquier programa

```bash
curl -s -X POST http://127.0.0.1:8791/v1/systemone -H 'Content-Type: application/json' -d '{
  "model": "english",
  "state": "Paso a cumplir: Tocar el botón para iniciar sesión",
  "questions": {"accion": {"type": "choice", "instructions": "¿Qué acción cumple el paso?",
    "criteria": {"a0": "tocar botón login", "a1": "escribir en campo email"}}}}'
# -> {"answers": {"accion": {"choice": "a0", "probabilities": {...}, "confidence": ...}}, ...}
```

Tipos de pregunta: `choice` (una opción de una lista), `noul` (sí/no con probabilidad) y `score`.
`GET /health` devuelve `{"status":"ok","loaded":[...]}`. Cualquier cliente de Jev funciona
apuntando a esta URL.

Buenas prácticas medidas en `Scripts/evidence/run-20260926-laya-benchmark/`:
- Estado corto y atómico («Paso a cumplir: …») funciona mejor que pasarle toda la pantalla.
- Acota las opciones antes de preguntar (tipo de acción, sin navegación global, sin repetidos).
- Usa `choice` para elegir; no para decidir si un paso ya se cumplió (eso se verifica en pantalla).
- Con confianza baja, deriva a un LLM; en acciones irreversibles exige más confianza.

## CuyScout

CuyScout no necesita Laya para funcionar, y está **desactivado por defecto**. Para activarlo:

- CuyScout.app: botón **Laya** de la barra superior, con interruptor, URL y estado.
- Configuración: `decision.layaEnabled: true` (y opcionalmente `decision.layaURL`) en
  `.cuyscout.yaml`, o `CUYSCOUT_LAYA_ENABLED=true` / `CUYSCOUT_LAYA_URL=…`.
- En caliente: `POST /decision/laya {"enabled": true, "url": "http://127.0.0.1:8791"}` (permiso
  `admin`). `GET /decision/laya` devuelve el estado y si el servicio responde.

Activo, `GET /doctor` lo verifica (sin afectar `ready`), `agent-state` lo anuncia en `decision`
y `POST /session/:id/decide` (herramienta MCP `cuyscout_decide`) elige el control de cada paso.
Está documentado en AGENT-GUIDE.md §3. Desactivado, `decide` responde `laya_disabled`.
