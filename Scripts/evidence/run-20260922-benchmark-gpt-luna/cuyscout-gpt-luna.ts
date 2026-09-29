import assert from "node:assert/strict";

const BASE = "http://127.0.0.1:4801";
const SESSION = "5A69DA88-D56E-4E87-AC09-4BC4AADCE544";
const SUPPLY = "19891201";
const EXPECTED_AMOUNT = "S/ 120.00";

type Json = Record<string, unknown>;

async function http(path: string, init: RequestInit = {}): Promise<Json> {
  const response = await fetch(`${BASE}${path}`, {
    ...init,
    headers: { "content-type": "application/json", ...(init.headers ?? {}) },
  });
  const body = (await response.json().catch(() => ({}))) as Json;
  assert.equal(response.ok, true, `${init.method ?? "GET"} ${path}: ${JSON.stringify(body)}`);
  return body;
}

function actionsOf(observation: Json): Array<Json> {
  return Array.isArray(observation.actions) ? observation.actions as Array<Json> : [];
}

function textsOf(observation: Json): Record<string, string> {
  const result: Record<string, string> = {};
  if (observation.texts && typeof observation.texts === "object") {
    const entries = Array.isArray(observation.texts)
      ? (observation.texts as Array<Json>).map((value, index) => [String(value.id ?? index), value] as const)
      : Object.entries(observation.texts as Json);
    for (const [key, value] of entries) {
      if (typeof value === "string") result[key] = value;
      else if (value && typeof value === "object" && typeof (value as Json).text === "string") {
        result[key] = (value as Json).text as string;
      }
    }
  }
  return result;
}

function hasSelector(observation: Json, value: string): boolean {
  return actionsOf(observation).some((action) => {
    const selector = action.selector as Json | undefined;
    return selector?.value === value;
  });
}

async function act(type: string, value: string, text?: string): Promise<Json> {
  return http(`/session/${SESSION}/actions`, {
    method: "POST",
    body: JSON.stringify({
      type,
      selector: { strategy: "accessibilityIdentifier", value },
      ...(text === undefined ? {} : { text }),
    }),
  });
}

const initial = await http(`/session/${SESSION}`);
assert.equal(initial.sessionId ?? SESSION, SESSION);
const readiness = await http(`/session/${SESSION}/readiness`);
assert.equal((readiness.interactionReady ?? true), true);

let observation = await http(`/session/${SESSION}/observe?maxActions=20`);
assert.equal(typeof observation.stateId, "string");

if (hasSelector(observation, "input_service_supply")) {
  await act("typeElement", "input_service_supply", SUPPLY);
  await act("typeElement", "input_service_amount", "120");
  observation = await http(`/session/${SESSION}/observe?maxActions=20`);
}

const texts = textsOf(observation);
const flattened = Object.values(texts).join(" | ");
assert.match(flattened, /19891201|Sedapal/i);
assert.match(flattened, /120(?:\.00)?/);

if (hasSelector(observation, "btn_service_continue")) {
  await act("tapElement", "btn_service_continue");
  observation = await http(`/session/${SESSION}/observe?maxActions=20`);
}

const confirmationTexts = textsOf(observation);
const confirmation = Object.values(confirmationTexts).join(" | ");
assert.match(confirmation, /120(?:\.00)?/);
assert.match(confirmation, /19891201/);

if (hasSelector(observation, "btn_service_pay")) {
  await act("tapElement", "btn_service_pay");
  observation = await http(`/session/${SESSION}/observe?maxActions=20`);
}

const receiptTexts = textsOf(observation);
const receipt = Object.values(receiptTexts).join(" | ");
assert.match(receipt, /Pago exitoso|comprobante|operaci[oó]n/i);
assert.match(receipt, /120(?:\.00)?/);
const operation = Object.entries(receiptTexts).find(([key, value]) =>
  /operation|operaci[oó]n/i.test(key) || /N[°º.]?\s*Operaci[oó]n/i.test(value),
);
assert.ok(operation, "No se encontró el número de operación en el comprobante");
assert.match(operation![1], /[A-Z0-9-]{5,}/i);

console.log(JSON.stringify({ session: SESSION, supply: SUPPLY, amount: EXPECTED_AMOUNT, operation: operation![1] }));

try {
  await http(`/session/${SESSION}`, { method: "DELETE" });
} catch (error) {
  console.error("No se pudo cerrar la sesión", error);
  throw error;
}
