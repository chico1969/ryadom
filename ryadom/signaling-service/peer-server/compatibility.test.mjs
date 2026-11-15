import assert from 'node:assert/strict';
import {test} from 'node:test';
import {once} from 'node:events';
const base=process.env.RYADOM_SIGNAL_TEST_URL || 'ws://127.0.0.1:9000/peerjs';
const sockets=[];
async function open(id){
  const ws=new WebSocket(`${base}?key=peerjs&id=${id}&token=${crypto.randomUUID()}&version=1.5.5`);sockets.push(ws);
  const messages=[];ws.addEventListener('message',e=>messages.push(JSON.parse(e.data)));
  await Promise.race([once(ws,'open'),new Promise((_,reject)=>setTimeout(()=>reject(new Error('Open timeout')),10000).unref())]);
  return {ws,messages};
}
async function next(peer){const start=Date.now();while(!peer.messages.length){if(Date.now()-start>10000)throw new Error('Message timeout');await new Promise(r=>setTimeout(r,20));}return peer.messages.shift();}
test('duplicate ID, signed-lookup envelope and real sender remain compatible',async()=>{
  const nonce=crypto.randomUUID().replaceAll('-','');
  const id='ryadom-'+nonce,code=String(100000000+crypto.getRandomValues(new Uint32Array(1))[0]%900000000);
  try{
    const host=await open(id),alias=await open('ryadom-code-'+code),client=await open('ryadom-lookup-'+nonce);
    for(const peer of [host,alias,client])assert.equal((await next(peer)).type,'OPEN');
    const duplicate=await open(id);assert.equal((await next(duplicate)).type,'ID-TAKEN');
    client.ws.send(JSON.stringify({type:'OFFER',src:'forged',dst:'ryadom-code-'+code,payload:{type:'data',connectionId:'lookup_'+nonce,metadata:{ryadomLookup:1,nonce}}}));
    const request=await next(alias);assert.equal(request.src,'ryadom-lookup-'+nonce);assert.equal(request.payload.metadata.nonce,nonce);
    alias.ws.send(JSON.stringify({type:'ANSWER',dst:request.src,payload:{type:'data',connectionId:request.payload.connectionId,metadata:{ryadomLookup:1,id}}}));
    const response=await next(client);assert.equal(response.src,'ryadom-code-'+code);assert.equal(response.payload.metadata.id,id);
    const http=new URL(base);http.protocol=http.protocol==='wss:'?'https:':'http:';http.pathname='/peerjs/peers';http.search='';
    assert.equal((await fetch(http)).status,401);
    http.pathname='/health';
    const health=await fetch(http);assert.equal(health.headers.get('cache-control'),'no-store');
    assert.equal((await health.json()).service,'ryadom-signaling');
    http.pathname='/check';assert.equal((await fetch(http)).status,200);
  }finally{for(const ws of sockets)ws.close();}
});
