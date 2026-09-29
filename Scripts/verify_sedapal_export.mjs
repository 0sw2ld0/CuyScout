// Product integration regression, NOT an independent model benchmark.
// Uses only local CuyScout HTTP and previously observed semantic selectors.
// CUYSCOUT_DEMO_AUTHORIZED=yes IOS_UDID=... CUYWALLET_IPA=... EVIDENCE_DIR=... node this-file
import assert from 'node:assert/strict';
import { mkdir, writeFile, appendFile } from 'node:fs/promises';
import { resolve } from 'node:path';
import { createHash } from 'node:crypto';

assert.equal(process.env.CUYSCOUT_DEMO_AUTHORIZED, 'yes', 'Explicit local DEMO authorization required');
const udid = process.env.IOS_UDID;
const ipa = process.env.CUYWALLET_IPA;
assert.ok(udid && ipa && process.env.EVIDENCE_DIR);
const out = resolve(process.env.EVIDENCE_DIR);
await mkdir(out); // refuse to mix attempts
const base = 'http://127.0.0.1:' + (process.env.CUYSCOUT_PORT || '4725');
const start = Date.now();
let calls = 0, sid, operation;
const inputs = {input_email:'demo@cuywallet.com',input_password:'Cuywallet2024',input_service_suministro:'19891201',input_service_amount:'25.00'};
const summary = {label_service_summary_name:'Servicio: Sedapal',label_service_summary_suministro:'N° Suministro: 19891201',label_service_summary_amount:'Monto: S/ 25.00'};
const receipt = {label_service_result_title:'Pago exitoso',label_service_result_name:'Servicio: Sedapal',label_service_result_suministro:'N° Suministro / Línea: 19891201',label_service_result_amount:'Monto pagado: S/ 25.00'};
async function call(method, path, body) {
    if (method !== 'DELETE') assert.ok(++calls <= 80 && Date.now()-start < 480000, 'External call/time limit');
    await appendFile(out+'/http.jsonl', JSON.stringify({at:new Date().toISOString(),event:'request',method,path,body})+'\n');
    const response = await fetch(base+path, {method,headers:{'Content-Type':'application/json'},body:body ? JSON.stringify(body):undefined,signal:AbortSignal.timeout(90000)});
    const text = await response.text();
    const value = response.headers.get('content-type')?.includes('json') ? JSON.parse(text) : text;
    await appendFile(out+'/http.jsonl', JSON.stringify({at:new Date().toISOString(),event:'response',status:response.status,path,value})+'\n');
    assert.ok(response.ok, JSON.stringify(value));
    return value;
}
const selector = value => ({strategy:'accessibilityIdentifier',value});
const act = action => call('POST',`/session/${sid}/actions`,action);
const observe = async () => (await call('GET',`/session/${sid}/observe`)).value;
function offers(observation, id) {assert.ok(observation.actions.some(x=>x.action.selector?.value===id), 'Missing observed control: '+id);}
async function checks(expected) {
    const observation = await observe();
    for (const [id,text] of Object.entries(expected)) {
        assert.ok(observation.texts.includes(id+': '+text), 'Missing expected observed summary/receipt: '+id);
        await act({type:'assertText',selector:selector(id),expected:text});
    }
    return observation;
}
try {
    await call('GET','/agent-help');
    const created = await call('POST','/session',{capabilities:{alwaysMatch:{'appium:app':ipa,'appium:automationName':'XCUITest','appium:udid':udid}}});
    sid=created.value.sessionId;
    assert.equal(created.value.capabilities['appium:bundleId'],'com.cuywallet.app');
    await call('POST',`/session/${sid}/timeouts`,{implicit:8000});
    for (let n=0;n<30;n++) {
        if ((await call('GET',`/session/${sid}/readiness`)).value.interactionReady===true) break;
        assert.ok(n<29,'Runner not ready'); await new Promise(r=>setTimeout(r,2000));
    }
    let observation=await observe();
    for (const id of ['input_email','input_password']) {offers(observation,id);await act({type:'typeElement',selector:selector(id),text:inputs[id]});}
    offers(observation,'btn_login'); await act({type:'tapElement',selector:selector('btn_login')});
    for (const id of ['btn_quick_pay','service_sedapal']) {
        observation=await observe(); offers(observation,id); await act({type:'tapElement',selector:selector(id)});
    }
    observation=await observe();
    for (const id of ['input_service_suministro','input_service_amount']) {offers(observation,id);await act({type:'typeElement',selector:selector(id),text:inputs[id]});}
    observation=await checks(summary);
    offers(observation,'btn_service_pay');
    // Only this call confirms payment. No catch/retry, even on ambiguous timeout.
    await act({type:'tapElement',selector:selector('btn_service_pay')});
    await act({type:'waitFor',selector:selector('label_service_result_title'),timeout:15});
    observation=await checks(receipt);
    operation=observation.texts.find(x=>x.startsWith('label_service_result_operation:'));
    assert.match(operation || '', /N° Operación: .+/);
    await act({type:'assertVisible',selector:{strategy:'predicate',value:"identifier == 'label_service_result_operation' AND label MATCHES 'N° Operación: .+'"}});
    const recording=await call('GET',`/session/${sid}/recording`);
    const source=await call('GET',`/session/${sid}/recording/appium/typescript`);
    assert.equal(source,recording.generatedAppiumTypeScript);
    const parameters={};
    for (const [index,step] of recording.steps.entries()) {
        assert.equal(step.success,true);
        const action=step.action;
        if (action.type==='typeElement') parameters[index+'.text']=inputs[action.selector.value];
        if (action.type==='assertText') parameters[index+'.expected']=summary[action.selector.value] || receipt[action.selector.value];
    }
    await writeFile(out+'/original-export.ts',source,{flag:'wx'});
    await writeFile(out+'/parameters.json',JSON.stringify(parameters,null,2)+'\n',{flag:'wx'});
    await writeFile(out+'/recording.json',JSON.stringify(recording,null,2)+'\n',{flag:'wx'});
    await writeFile(out+'/result.json',JSON.stringify({status:'recorded_and_exported_NOT_replay_verified',udid,sid,operation,calls,sha256:createHash('sha256').update(source).digest('hex')},null,2)+'\n',{flag:'wx'});
    console.log(JSON.stringify({out,operation,calls,exported:true}));
} finally {if(sid) await call('DELETE',`/session/${sid}`);}
