import {chromium} from 'playwright';
import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const root=path.resolve(path.dirname(fileURLToPath(import.meta.url)),'../../../..');
const express=process.argv.includes('--express');
const iceServers=JSON.parse(await fs.readFile(path.join(root,express?'.tools/turn.express.local.json':'.tools/turn.local.json'),'utf8'));
if(!iceServers.length)throw new Error('Нет локальной конфигурации TURN');
const server=http.createServer((_,res)=>res.writeHead(200,{'Content-Type':'text/html'}).end('<!doctype html><title>Рядом — проверка TURN</title>'));
await new Promise(resolve=>server.listen(0,'127.0.0.1',resolve));
const result={date:new Date().toISOString(),status:'pending'};
let browser;
try{
  browser=await chromium.launch({channel:'msedge',headless:true});
  const page=await browser.newPage();
  await page.goto(`http://127.0.0.1:${server.address().port}`);
  result.outcome=await page.evaluate(async iceServers=>{
    const a=new RTCPeerConnection({iceServers,iceTransportPolicy:'relay'});
    const b=new RTCPeerConnection({iceServers,iceTransportPolicy:'relay'});
    let timer;
    try{
      const done=new Promise((resolve,reject)=>{
        timer=setTimeout(()=>reject(new Error('TURN не установил канал за 60 секунд')),60000);
        b.ondatachannel=event=>{
          event.channel.binaryType='arraybuffer';
          let received=0;
          event.channel.onmessage=event=>{
            const bytes=new Uint8Array(event.data);
            if(bytes.length!==16384||bytes.some((byte,index)=>byte!==index%251)){
              reject(new Error('Повреждены тестовые данные'));return;
            }
            received+=bytes.length;
            if(received===65536)resolve(received);
          };
        };
      });
      const ac=[],bc=[];
      const pending=[];
      a.onicecandidate=event=>{if(event.candidate){if(b.remoteDescription)pending.push(b.addIceCandidate(event.candidate));else ac.push(event.candidate);}};
      b.onicecandidate=event=>{if(event.candidate){if(a.remoteDescription)pending.push(a.addIceCandidate(event.candidate));else bc.push(event.candidate);}};
      const dc=a.createDataChannel('ryadom-turn-test');
      dc.onopen=()=>{const bytes=Uint8Array.from({length:16384},(_,index)=>index%251);for(let i=0;i<4;i++)dc.send(bytes);};
      await a.setLocalDescription(await a.createOffer());
      await b.setRemoteDescription(a.localDescription);
      for(const candidate of ac)await b.addIceCandidate(candidate);
      await b.setLocalDescription(await b.createAnswer());
      await a.setRemoteDescription(b.localDescription);
      for(const candidate of bc)await a.addIceCandidate(candidate);
      const bytes=await done;
      await Promise.all(pending);
      const stats=await a.getStats();
      let pair;
      stats.forEach(row=>{if(row.type==='transport'&&row.selectedCandidatePairId)pair=stats.get(row.selectedCandidatePairId);});
      const local=stats.get(pair?.localCandidateId)?.candidateType;
      const remote=stats.get(pair?.remoteCandidateId)?.candidateType;
      if(local!=='relay'||remote!=='relay')throw new Error('Выбранная пара не подтверждает TURN');
      return {bytes,pair:{local,remote},integrity:'all test bytes matched',scope:'two browser RTC peers on one Windows PC, actual public TURN; not Windows host or two-PC acceptance'};
    }finally{clearTimeout(timer);a.close();b.close();}
  },iceServers);
  result.status='passed';
}catch(error){result.status='failed';result.error=String(error);process.exitCode=1;}
finally{
  await browser?.close();server.close();
  await fs.writeFile(path.join(root,'ryadom/build-logs/'+(express?'turn-smoke-express.json':'turn-smoke.json')),JSON.stringify(result,null,2));
  console.log(JSON.stringify(result,null,2));
}
