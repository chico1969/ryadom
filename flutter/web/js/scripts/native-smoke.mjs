import {chromium} from 'playwright';
import {build} from 'esbuild';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const relay=process.argv.includes('--relay');
const identityOnly=process.argv.includes('--identity-only');
const turnFile=process.env.RYADOM_TEST_TURN_FILE||'.tools/turn.local.json';
const turnServers=relay?JSON.parse(await fs.readFile(path.resolve(root,turnFile),'utf8')):undefined;
const peer=(await fs.readFile(path.join(root,'.tools/native-id.txt'),'utf8')).trim();
if(!/^ryadom-[0-9a-f]{32}$/.test(peer))throw new Error('Нет ID Windows-хоста');
const script=(await build({entryPoints:[path.join(here,'native-probe.ts')],bundle:true,write:false,outfile:'native.js',format:'iife',globalName:'NativeProbe',target:'chrome120'})).outputFiles.find(file=>file.path.endsWith('.js')).text;
const server=http.createServer((_,res)=>res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><meta charset="utf-8"><title>Рядом — локальная проверка</title>'));
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
let browser;
const result={date:new Date().toISOString(),peer,status:'pending'};
try{
  browser=await chromium.launch({channel:'msedge',headless:true});
  const page=await browser.newPage();
  let hostRelayCandidateObserved=false;
  page.on('websocket',socket=>socket.on('framereceived',frame=>{
    try{const message=JSON.parse(String(frame.payload));
      if(message.type==='CANDIDATE'&&message.src===peer&&/\btyp relay\b/.test(message.payload?.candidate?.candidate??''))hostRelayCandidateObserved=true;
    }catch{}
  }));
  if(relay)await page.addInitScript(()=>{
    const Original=window.RTCPeerConnection;
    window.RTCPeerConnection=class extends Original {
      constructor(config){super({...config,iceTransportPolicy:'relay'});}
    };
  });
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  await page.addScriptTag({content:script});
  result.outcome=await page.evaluate(({peer,turnServers,identityOnly})=>Promise.race([NativeProbe.run(peer,turnServers,identityOnly),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Ожидание локальной проверки истекло')),120000))]),{peer,turnServers,identityOnly});
  result.hostRelayCandidateObserved=hostRelayCandidateObserved;
  if(relay&&result.outcome?.pair?.relayed!==true)throw new Error('Проверка должна использовать TURN');
  result.status='passed';
}catch(error){result.status='failed';result.error=String(error);process.exitCode=1;}
finally{
  await browser?.close();server.close();
  await fs.writeFile(path.join(root,'ryadom/build-logs/'+(identityOnly?(relay?'native-relay-identity.json':'native-direct-identity.json'):'native-smoke.json')),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}
