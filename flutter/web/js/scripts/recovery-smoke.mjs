import {chromium} from 'playwright';
import {build} from 'esbuild';
import {createRequire} from 'node:module';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../..');
const require=createRequire(path.join(root,'ryadom/signaling-service/peer-server/package.json'));
const {PeerServer}=require('peer');
const pageServer=http.createServer((_,res)=>res.setHeader('Content-Type','text/html').end('<!doctype html><html><body></body></html>'));
await new Promise(resolve=>pageServer.listen(0,'127.0.0.1',resolve));
const reserve=http.createServer();await new Promise(resolve=>reserve.listen(0,'127.0.0.1',resolve));
const port=reserve.address().port;await new Promise(resolve=>reserve.close(resolve));
let signalServer,browser,page;
const result={date:new Date().toISOString(),scope:'local native-wire fixture, not physical Windows acceptance'};
let turn=[];
try{
  if(process.env.RYADOM_TEST_TURN_FILE){const parsed=JSON.parse(await fs.readFile(process.env.RYADOM_TEST_TURN_FILE,'utf8'));turn=Array.isArray(parsed)?parsed:parsed.servers;}
  await new Promise(resolve=>PeerServer({host:'127.0.0.1',port,path:'/',key:'peerjs',allow_discovery:false},server=>{signalServer=server;resolve();}));
  const built=await build({entryPoints:[path.join(here,'recovery-probe.ts')],bundle:true,write:false,outfile:'recovery.js',format:'iife',globalName:'RecoveryProbe',target:'chrome120',plugins:[{
    name:'local-signaling-only',setup(build){build.onLoad({filter:/signaling\.json$/},()=>({contents:JSON.stringify({url:`ws://127.0.0.1:${port}/peerjs?key=peerjs`}),loader:'json'}));}
  }]});
  browser=await chromium.launch({channel:'msedge',headless:true,args:['--disable-features=WebRtcHideLocalIpsWithMdns']});result.browser=browser.version();
  page=await browser.newPage();await page.goto(`http://127.0.0.1:${pageServer.address().port}`);
  await page.evaluate(()=>{const Original=RTCPeerConnection;window.__testPeers=[];
    window.RTCPeerConnection=function(...args){const pc=new Original(...args);window.__testPeers.push(pc);return pc;};window.RTCPeerConnection.prototype=Original.prototype;});
  await page.addScriptTag({content:built.outputFiles.find(file=>file.path.endsWith('.js')).text});
  result.test=await page.evaluate(turn=>Promise.race([RecoveryProbe.run(turn),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Recovery test deadline')),120000))]),turn);
  result.status='passed';
}catch(error){
  result.status='failed';let detail=String(error);
  for(const server of turn??[])for(const secret of [server.username,server.credential])if(secret)detail=detail.split(secret).join('[redacted]');
  result.error=detail;process.exitCode=1;
  if(page)result.peers=await page.evaluate(()=>window.__testPeers?.map(pc=>({state:pc.connectionState,ice:pc.iceConnectionState,gather:pc.iceGatheringState,signaling:pc.signalingState,local:!!pc.localDescription,remote:!!pc.remoteDescription})));
}finally{
  await browser?.close();signalServer?.close();pageServer.close();
  const output=path.join(root,'ryadom/build-logs/recovery-smoke.json');await fs.writeFile(output,JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}
// PeerServer owns process-level expiry timers without a public shutdown API.
process.exit(process.exitCode??0);
