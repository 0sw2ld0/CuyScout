// Replay the exact exported bytes, with external wall-clock control and a hash report.
// Set EVIDENCE_DIR, IOS_UDID, APPIUM_PORT and CUYSCOUT_REPLAY_AUTHORIZED=yes.
// A new simulator with CuyWallet DEMO must already be installed. Never retries a run.
import assert from 'node:assert/strict';
import { readFile, writeFile, mkdtemp } from 'node:fs/promises';
import { resolve, join } from 'node:path';
import { spawn } from 'node:child_process';
import { createHash } from 'node:crypto';
assert.equal(process.env.CUYSCOUT_REPLAY_AUTHORIZED,'yes');
assert.ok(process.env.EVIDENCE_DIR && process.env.IOS_UDID);
const dir=resolve(process.env.EVIDENCE_DIR);
const runtime=resolve('.build/luna-replay');
const original=await readFile(join(dir,'original-export.ts'));
const hash=data=>createHash('sha256').update(data).digest('hex');
const temp=await mkdtemp(join(runtime,'verified-'));
const artifact=join(temp,'original-export.mts');
await writeFile(artifact,original,{flag:'wx'});
assert.equal(hash(await readFile(artifact)),hash(original));
async function command(tool,args,env,timeout) {
    const child=spawn(join(runtime,'node_modules/.bin',tool),args,{env:{...process.env,...env},stdio:['ignore','pipe','pipe']});
    let output='',timedOut=false;
    child.stdout.on('data',data=>{output+=data;process.stdout.write(data);});
    child.stderr.on('data',data=>{output+=data;process.stderr.write(data);});
    const timer=setTimeout(()=>{timedOut=true;child.kill('SIGTERM');},timeout);
    const result=await new Promise((done,fail)=>{child.on('error',fail);child.on('close',(code,signal)=>done({code,signal}));});
    clearTimeout(timer);
    return {...result,timedOut,output};
}
const compile=await command('tsc',['--noEmit','--target','es2022','--module','nodenext','--moduleResolution','nodenext','--skipLibCheck',artifact],{},60000);
await writeFile(join(dir,'typecheck-output.txt'),compile.output,{flag:'wx'});
assert.equal(compile.code,0,'Original export did not compile; no replay performed');
const startedAt=new Date().toISOString();
const replay=await command('tsx',[artifact],{IOS_BUNDLE_ID:'com.cuywallet.app',APPIUM_HOST:'127.0.0.1',
    CUYSCOUT_REPLAY_VALUES:await readFile(join(dir,'parameters.json'),'utf8')},180000);
await writeFile(join(dir,'replay-output.txt'),replay.output,{flag:'wx'});
const report={startedAt,finishedAt:new Date().toISOString(),udid:process.env.IOS_UDID,
    sha256:hash(original),runtimeSha256:hash(await readFile(artifact)),originalUnchanged:hash(await readFile(join(dir,'original-export.ts')))===hash(original),
    compileExitCode:compile.code,replayExitCode:replay.code,timedOut:replay.timedOut,
    status:replay.code===0&&replay.output.includes('replay_completed')?'passed':'failed'};
await writeFile(join(dir,'replay-result.json'),JSON.stringify(report,null,2)+'\n',{flag:'wx'});
console.log(JSON.stringify(report));
assert.equal(report.status,'passed','Replay did not complete; inspect logs and app before any rerun');
