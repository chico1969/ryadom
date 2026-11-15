import { chromium } from 'playwright';
import { build } from 'esbuild';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
const here=path.dirname(fileURLToPath(import.meta.url));
const root=path.resolve(here,'../../../../ryadom/ui/build/web');
const output=path.resolve(here,'../../../../ryadom/build-logs');await fs.mkdir(output,{recursive:true});
const probe=(await build({entryPoints:[path.join(here,'probe.ts')],bundle:true,write:false,format:'iife',globalName:'Probe',target:'chrome120'})).outputFiles[0].text;
const types={'.html':'text/html','.js':'application/javascript','.css':'text/css','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.png':'image/png'};
const server=http.createServer(async(req,res)=>{
  try {const url=new URL(req.url,'http://127.0.0.1');const relative=decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname);const file=path.resolve(root,'.'+relative);
    if(!file.startsWith(root+path.sep)){res.writeHead(403).end();return;}
    const bytes=await fs.readFile(file);res.writeHead(200,{'Content-Type':types[path.extname(file)]??'application/octet-stream','Cache-Control':'no-store'}).end(bytes);
  } catch{res.writeHead(404).end();}
});
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const url=`http://127.0.0.1:${server.address().port}`;
let browser;
const results={date:new Date().toISOString(),ui:{},direct:null,discovery:null,errors:[]};
try {
  browser=await chromium.launch({channel:'msedge',headless:true,args:['--disable-features=WebRtcHideLocalIpsWithMdns']});
  results.browser={channel:'msedge',version:browser.version(),fixtureAddresses:'numeric LAN, matching the native host'};
  const context=await browser.newContext({viewport:{width:1280,height:900}});
  const page=await context.newPage();
  page.on('pageerror',error=>results.errors.push(String(error)));
  await page.goto(url);await page.locator('flutter-view').waitFor({timeout:60000});
  await page.waitForFunction(()=>document.querySelector('flutter-view')?.getBoundingClientRect().height>100);
  await page.waitForTimeout(1500);
  await page.screenshot({path:path.join(output,'web-desktop.png')});
  results.ui.desktop={width:1280,height:900};
  const placeholder=page.locator('flt-semantics-placeholder');
  if(await placeholder.count()){await placeholder.evaluate(element=>element.click());await page.getByRole('button',{name:'Подключиться',exact:true}).first().waitFor();}
  results.ui.storage=await page.evaluate(async()=>({available:Array.isArray(await new RyadomEngine.Vault().computers())}));
  results.ui.credentials=await page.evaluate(async()=>{
    const id='ryadom-'+'0'.repeat(32);const vault=new RyadomEngine.Vault();
    await vault.savePassword(id,'test-only-vault-value');
    if(await new RyadomEngine.Vault().password(id)!=='test-only-vault-value')throw new Error('Saved password cannot be recovered');
    await vault.forgetPassword(id);if(await vault.password(id)!==undefined)throw new Error('Password was not removed');
    await vault.remember({id,name:'History fixture',lastConnected:1,code:'123456789'});
    await vault.remember({id,name:'Renamed fixture',lastConnected:2});
    if((await vault.computers()).find(peer=>peer.id===id)?.code!=='123456789')throw new Error('History lost the numeric ID');
    await vault.remove(id);
    const servers=[{urls:['turn:relay.example.com:3478'],username:'local-test',credential:'test-only'}];
    await vault.saveTurnServers(JSON.stringify(servers));
    if(JSON.stringify(await new RyadomEngine.Vault().turnServers())!==JSON.stringify(servers))throw new Error('Local TURN settings were not recovered');
    await vault.saveTurnServers('[]');
    if((await vault.turnServers()).length!==0)throw new Error('Local TURN settings were not cleared');
    return {roundTrip:true,removed:true,localTurnRoundTrip:true,localTurnCleared:true};
  });
  await page.setViewportSize({width:390,height:844});await page.waitForTimeout(500);await page.screenshot({path:path.join(output,'web-mobile.png')});results.ui.mobile={width:390,height:844};
  const testPage=await context.newPage();
  const socketTrace=[];
  testPage.on('websocket',socket=>{
    const record=(direction,frame)=>{try{const message=JSON.parse(String(frame.payload));socketTrace.push({direction,type:message.type,hasDestination:!!message.dst,hasSource:!!message.src});}catch{}};
    socket.on('framesent',frame=>record('sent',frame));socket.on('framereceived',frame=>record('received',frame));
  });
  await testPage.goto(url+'/index.html');await testPage.addScriptTag({content:probe});
  results.direct=await testPage.evaluate(()=>Promise.race([Probe.direct(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('ICE test timeout')),45000))]));
  try{results.discovery=await testPage.evaluate(()=>Probe.publicDiscovery());}catch(error){results.discovery={error:String(error),trace:socketTrace};}
  if(!results.discovery.error){
    const built=await build({entryPoints:[path.join(here,'interop-probe.ts')],bundle:true,write:false,outfile:path.join(output,'interop.js'),format:'iife',globalName:'InteropProbe',target:'chrome120'});
    const script=built.outputFiles.find(file=>file.path.endsWith('.js')).text;
    await testPage.addScriptTag({content:script});results.interop=await testPage.evaluate(()=>Promise.race([InteropProbe.run(),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Interop timeout')),60000))]));
  }
  if(results.discovery.error){
    const reference=path.resolve(here,'../../../../.tools/downloads/peerjs-reference.min.js');
    try{
      await testPage.addScriptTag({path:reference});
      results.reference=await testPage.evaluate(async()=>{
        const config={iceServers:[{urls:'stun:stun.l.google.com:19302'}]};
        const a=new Peer(undefined,{config}),b=new Peer(undefined,{config});let timer;
        try{
          const timeout=new Promise((_,reject)=>{timer=setTimeout(()=>reject(new Error('Official PeerJS timeout')),20000);});
          const connection=(async()=>{
            await Promise.all([new Promise((resolve,reject)=>{a.on('open',resolve);a.on('error',reject);}),new Promise((resolve,reject)=>{b.on('open',resolve);b.on('error',reject);})]);
            const accepted=new Promise(resolve=>b.on('connection',c=>c.on('open',resolve)));
            const c=a.connect(b.id,{serialization:'raw',reliable:true});
            await Promise.all([accepted,new Promise((resolve,reject)=>{c.on('open',resolve);c.on('error',reject);})]);return {connected:true};
          })();
          return await Promise.race([connection,timeout]);
        }finally{clearTimeout(timer);a.destroy();b.destroy();}
      });
    }catch(error){results.reference={error:String(error)};}
  }
  if(results.discovery.error)throw new Error(results.discovery.error);
  if(results.errors.length)throw new Error(results.errors.join('\n'));
} finally {await browser?.close();server.close();await fs.writeFile(path.join(output,'browser-smoke.json'),JSON.stringify(results,null,2));console.log(JSON.stringify(results,null,2));}
