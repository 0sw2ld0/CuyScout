import test from 'node:test';
import assert from 'node:assert/strict';
import { resumeSedapal } from '../../Scripts/evidence/run-20260922-benchmark-gpt-luna/cuyscout-gpt-luna-fixed.ts';

const form = {
  stateId: 'form',
  texts: ['label_service_summary_name: Servicio: Sedapal',
    'label_service_summary_suministro: N° Suministro: 19891201',
    'label_service_summary_amount: Monto: S/ 120.00',
    'label_service_summary_fee: Comisión: S/ 0.00', 'Wallet Digital CUY'],
  actions: [{ risk: 'low', action: { type: 'tapElement',
    selector: { strategy: 'accessibilityIdentifier', value: 'btn_service_pay' } } }],
};
const receipt = { stateId: 'receipt', actions: [], texts: [
  'label_service_result_title: Pago exitoso', 'label_service_result_name: Servicio: Sedapal',
  'label_service_result_suministro: N° Suministro / Línea: 19891201',
  'label_service_result_amount: Monto pagado: S/ 120.00',
  'label_service_result_account: Desde: Wallet Digital CUY',
  'label_service_result_operation: N° Operación: SP289050',
] };
function fixture({ first = form, last = receipt, ready = { interactionReady: true },
  postError, deleteError, responseStatus = 200, sessionId = 'test-session' } = {}) {
  const requests = [];
  let reads = 0;
  const fetchImpl = async (url, init) => {
    const path = new URL(url).pathname;
    const method = init.method ?? 'GET';
    requests.push({ method, path, body: init.body });
    let value = null;
    if (method === 'DELETE' && deleteError) throw deleteError;
    if (method === 'POST' && postError) throw postError;
    if (path.endsWith('/observe')) value = reads++ ? last : first;
    else if (path.endsWith('/readiness')) value = ready;
    else if (method === 'GET') value = { sessionId };
    return Response.json({ value }, { status: method === 'DELETE' ? 200 : responseStatus });
  };
  return { requests, run: () => resumeSedapal({ sessionId: 'test-session', fetchImpl }) };
}

test('unwraps value, parses string texts, executes the nested observed action and closes', async () => {
  const f = fixture();
  assert.deepEqual(await f.run(), { operation: 'SP289050', amount: 'S/ 120.00', supply: '19891201', calls: 6 });
  assert.deepEqual(JSON.parse(f.requests.find(r => r.method === 'POST').body), form.actions[0].action);
  assert.equal(f.requests.at(-1).method, 'DELETE');
});
test('verifies an existing receipt without paying again', async () => {
  const f = fixture({ first: receipt });
  await f.run();
  assert.equal(f.requests.filter(r => r.method === 'POST').length, 0);
});
for (const [name, options] of [
  ['incorrect amount', { first: { ...form, texts: form.texts.map(t => t.replace('120.00', '1120.00')) } }],
  ['incorrect supply', { first: { ...form, texts: form.texts.map(t => t.replace('19891201', '198912010')) } }],
  ['missing readiness', { ready: {} }],
  ['blocked readiness', { ready: { interactionReady: false, blockers: ['xctest_runner_starting'] } }],
  ['missing action', { first: { ...form, actions: [] } }],
  ['wrong session', { sessionId: 'other' }],
  ['HTTP failure', { responseStatus: 404 }],
]) {
  test(`${name} fails before payment and still closes`, async () => {
    const f = fixture(options);
    await assert.rejects(f.run);
    assert.equal(f.requests.filter(r => r.method === 'POST').length, 0);
    assert.equal(f.requests.at(-1).method, 'DELETE');
  });
}
test('rejects a receipt without a real operation code and closes', async () => {
  const f = fixture({ last: { ...receipt, texts: receipt.texts.map(t => t.replace('SP289050', 'Operación')) } });
  await assert.rejects(f.run, /Código de operación/);
  assert.equal(f.requests.at(-1).method, 'DELETE');
});
test('a payment timeout is never retried', async () => {
  const f = fixture({ postError: new Error('timeout') });
  await assert.rejects(f.run, /timeout/);
  assert.equal(f.requests.filter(r => r.method === 'POST').length, 1);
  assert.equal(f.requests.at(-1).method, 'DELETE');
});
test('preserves the primary error if cleanup also fails', async () => {
  const f = fixture({ ready: {}, deleteError: new Error('close failed') });
  await assert.rejects(f.run, error => error instanceof AggregateError && error.errors.length === 2);
});
test('requires an explicit active session before making any request', async () => {
  await assert.rejects(() => resumeSedapal({ sessionId: '', fetchImpl: () => assert.fail('Unexpected request') }), /CUYSCOUT_SESSION/);
});
