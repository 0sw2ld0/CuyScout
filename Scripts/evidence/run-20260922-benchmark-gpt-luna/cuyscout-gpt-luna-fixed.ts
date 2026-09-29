// Corrección posterior al benchmark. Continuación de una sesión en el formulario.
import assert from 'node:assert/strict';
import { pathToFileURL } from 'node:url';
type Json = Record<string, any>;

export async function resumeSedapal({ sessionId, baseURL = 'http://127.0.0.1:4801', fetchImpl = fetch }:
  { sessionId: string; baseURL?: string; fetchImpl?: typeof fetch }) {
  assert.ok(sessionId?.trim(), 'CUYSCOUT_SESSION debe indicar una sesión activa');
  const session = `/session/${encodeURIComponent(sessionId)}`;
  let calls = 0;
  async function http(path: string, init: RequestInit = {}) {
    calls++;
    const response = await fetchImpl(`${baseURL.replace(/\/$/, '')}${path}`, {
      ...init, headers: { 'content-type': 'application/json', ...init.headers },
      signal: AbortSignal.timeout(45_000),
    });
    const body = await response.json();
    assert.ok(response.ok, `${init.method ?? 'GET'} ${path}: ${JSON.stringify(body)}`);
    assert.ok(body && Object.hasOwn(body, 'value'), 'Respuesta sin envoltura value');
    assert.ok(!body.value?.error, JSON.stringify(body.value));
    return body.value;
  }
  async function observe() {
    const value = await http(`${session}/observe?maxActions=20`);
    assert.equal(typeof value?.stateId, 'string');
    assert.ok(Array.isArray(value.texts) && value.texts.every((t: unknown) => typeof t === 'string'));
    assert.ok(Array.isArray(value.actions));
    return value as Json;
  }
  function text(observation: Json, id: string) {
    const matches = observation.texts.filter((t: string) => t.startsWith(`${id}: `));
    assert.equal(matches.length, 1, `Texto visible único requerido: ${id}`);
    return matches[0].slice(id.length + 2) as string;
  }
  function receipt(observation: Json) {
    assert.equal(text(observation, 'label_service_result_title'), 'Pago exitoso');
    assert.equal(text(observation, 'label_service_result_name'), 'Servicio: Sedapal');
    assert.equal(text(observation, 'label_service_result_suministro'), 'N° Suministro / Línea: 19891201');
    assert.equal(text(observation, 'label_service_result_amount'), 'Monto pagado: S/ 120.00');
    assert.equal(text(observation, 'label_service_result_account'), 'Desde: Wallet Digital CUY');
    const match = /^N° Operación: (SP\d+)$/.exec(text(observation, 'label_service_result_operation'));
    assert.ok(match, 'Código de operación SP seguido de dígitos requerido');
    return { operation: match[1], amount: 'S/ 120.00', supply: '19891201' };
  }
  let result: ReturnType<typeof receipt> | undefined;
  let failure: unknown;
  let failed = false;
  try {
    assert.equal((await http(session))?.sessionId, sessionId, 'Sesión distinta');
    const ready = await http(`${session}/readiness`);
    assert.equal(ready?.interactionReady, true, `Sesión no preparada: ${JSON.stringify(ready)}`);
    const observation = await observe();
    if (observation.texts.some((t: string) => t.startsWith('label_service_result_operation: '))) {
      result = receipt(observation); // Un comprobante existente no dispara otro pago.
    } else {
      assert.equal(text(observation, 'label_service_summary_name'), 'Servicio: Sedapal');
      assert.equal(text(observation, 'label_service_summary_suministro'), 'N° Suministro: 19891201');
      assert.equal(text(observation, 'label_service_summary_amount'), 'Monto: S/ 120.00');
      assert.equal(text(observation, 'label_service_summary_fee'), 'Comisión: S/ 0.00');
      assert.ok(observation.texts.includes('Wallet Digital CUY'), 'Cuenta Wallet requerida');
      const actions = observation.actions.map((s: Json) => s.action).filter((a: Json) =>
        a?.type === 'tapElement' && a?.selector?.strategy === 'accessibilityIdentifier'
        && a.selector.value === 'btn_service_pay');
      assert.equal(actions.length, 1, 'observe debe ofrecer exactamente una acción Pagar');
      // El número de operación se emite después del pago; antes se valida el resumen.
      // Nunca reintentar este POST automáticamente, ni siquiera tras un timeout.
      await http(`${session}/actions`, { method: 'POST', body: JSON.stringify(actions[0]) });
      result = receipt(await observe());
    }
  } catch (error) { failed = true; failure = error; }
  finally {
    try { await http(session, { method: 'DELETE' }); }
    catch (closeError) {
      if (failed) throw new AggregateError([failure, closeError], 'Falló la prueba y el cierre');
      throw closeError;
    }
  }
  if (failed) throw failure;
  return { ...result!, calls };
}

if (process.argv[1] && import.meta.url === pathToFileURL(process.argv[1]).href) {
  resumeSedapal({ sessionId: process.env.CUYSCOUT_SESSION ?? '', baseURL: process.env.CUYSCOUT_URL })
    .then(result => console.log(JSON.stringify(result)))
    .catch(error => { console.error(error); process.exitCode = 1; });
}
