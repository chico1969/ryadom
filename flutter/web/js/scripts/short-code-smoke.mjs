import {chromium} from 'playwright';
import {build} from 'esbuild';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url)),root=path.resolve(here,'../../../..');
const code=(await fs.readFile(path.join(root,'.tools/native-code.txt'),'utf8')).trim();
const expected=(await fs.readFile(path.join(root,'.tools/native-id.txt'),'utf8')).trim();
if(!/^[1-9][0-9]{8}$/.test(code))throw new Error('Нужен действующий короткий ID');
const script=(await build({stdin:{contents:"export {resolvePeer} from '../src/short-code'; export {PeerSignal} from '../src/signaling';",resolveDir:here,loader:'ts'},bundle:true,write:false,format:'iife',globalName:'CodeProbe',target:'chrome120'})).outputFiles[0].text;
const server=http.createServer((_,res)=>res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><title>Рядом — проверка короткого ID</title>'));
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const result={date:new Date().toISOString(),status:'pending',scope:'Public PeerServer, actual Windows host, one physical PC; no desktop access'};
let browser;
try{
 browser=await chromium.launch({channel:'msedge',headless:true});
 const page=await browser.newPage();result.trace=[];
 page.on('websocket',socket=>{
  for(const [event,direction] of [['framesent','sent'],['framereceived','received']])socket.on(event,frame=>{
   try{const message=JSON.parse(String(frame.payload));result.trace.push({direction,type:message.type,lookup:message.payload?.metadata?.ryadomLookup});}catch{}
  });
 });
 await page.goto(`http://127.0.0.1:${server.address().port}`);
 await page.evaluate(()=>{
  const Original=WebSocket;window.codeSocketCloses=[];
  window.WebSocket=class extends Original{constructor(...args){super(...args);this.addEventListener('close',event=>window.codeSocketCloses.push({code:event.code,reason:event.reason}));}};
 });
 await page.addScriptTag({content:script});
 try{result.outcome=await page.evaluate(async({code,expected})=>{
  const resolved=await CodeProbe.resolvePeer(code);if(resolved!==expected)throw new Error('Короткий ID указал на другую личность');
  const duplicate=new CodeProbe.PeerSignal('ryadom-code-'+code);let rejected=false;
  duplicate.addEventListener('signal',event=>{if(event.detail.type==='ID-TAKEN')rejected=true;});
  try{await duplicate.open();throw new Error('Повторная регистрация ID разрешена');}catch(error){if(!rejected)throw error;}finally{duplicate.close();}
  if(await CodeProbe.resolvePeer(code)!==expected)throw new Error('Коллизия нарушила исходную регистрацию');
  return {digits:code.length,signedLookupVerified:true,duplicateRegistrationRejected:true,originalRegistrationPreserved:true};
 },{code,expected});}finally{result.socketCloses=await page.evaluate(()=>window.codeSocketCloses);}
 result.status='passed';
}catch(error){result.status='failed';result.error=String(error);process.exitCode=1;}
finally{await browser?.close();server.close();await fs.writeFile(path.join(root,'ryadom/build-logs/short-code-smoke.json'),JSON.stringify(result,null,2));console.log(JSON.stringify(result,null,2));}
