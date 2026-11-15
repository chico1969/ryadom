import assert from 'node:assert/strict';
import {test} from 'node:test';
import {once} from 'node:events';

const base=process.env.RYADOM_SIGNAL_TEST_URL || 'ws://127.0.0.1:8787/peerjs';
const sockets=[];
async function connect(id, endpoint=base) {
  const ws=new WebSocket(`${endpoint}?key=peerjs&id=${id}&token=${crypto.randomUUID()}&version=1.5.5`);
  sockets.push(ws);
  const messages=[];ws.addEventListener('message',e=>messages.push(JSON.parse(e.data)));
  await Promise.race([once(ws,'open'),new Promise((_,reject)=>setTimeout(()=>reject(new Error('WebSocket open timeout')),10000).unref())]);
  return {ws,messages};
}
async function next(peer) {
  const start=Date.now();while(!peer.messages.length){if(Date.now()-start>10000)throw new Error('Message timeout');await new Promise(r=>setTimeout(r,20));}
  return peer.messages.shift();
}
test('registry rejects duplicates and routes only from the real sender',async()=>{
  const suffix=crypto.randomUUID().replaceAll('-','');
  try {
    const a=await connect('ryadom-'+suffix), b=await connect('ryadom-client-'+suffix);
    assert.equal((await next(a)).type,'OPEN');assert.equal((await next(b)).type,'OPEN');
    const duplicate=await connect('ryadom-'+suffix);assert.equal((await next(duplicate)).type,'ID-TAKEN');
    b.ws.send(JSON.stringify({type:'OFFER',src:'forged',dst:'ryadom-'+suffix,payload:{connectionId:'test',sdp:{type:'offer',sdp:'test'}}}));
    const offer=await next(a);assert.equal(offer.src,'ryadom-client-'+suffix);assert.equal(offer.type,'OFFER');
    b.ws.send(JSON.stringify({type:'OFFER',dst:'ryadom-'+'f'.repeat(32),payload:{connectionId:'missing'}}));
    assert.equal((await next(b)).type,'EXPIRE');
    a.ws.send('{"type":"HEARTBEAT"}');assert.equal((await next(a)).type,'HEARTBEAT');
    const code=String(100000000+crypto.getRandomValues(new Uint32Array(1))[0]%900000000);
    const alias=await connect('ryadom-code-'+code), lookup=await connect('ryadom-lookup-'+suffix);
    assert.equal((await next(alias)).type,'OPEN');assert.equal((await next(lookup)).type,'OPEN');
    lookup.ws.send(JSON.stringify({type:'OFFER',dst:'ryadom-code-'+code,payload:{connectionId:'lookup_test',metadata:{ryadomLookup:1,nonce:suffix}}}));
    assert.equal((await next(alias)).src,'ryadom-lookup-'+suffix);
    alias.ws.send(JSON.stringify({type:'ANSWER',dst:'ryadom-lookup-'+suffix,payload:{connectionId:'lookup_test',metadata:{ryadomLookup:1}}}));
    assert.equal((await next(lookup)).src,'ryadom-code-'+code);
  } finally {for(const ws of sockets.splice(0))ws.close();}
});
test('service refuses application data and retains no public directory',async()=>{
  try{
    const a=await connect('ryadom-client-'+crypto.randomUUID());assert.equal((await next(a)).type,'OPEN');
    const closed=once(a.ws,'close');a.ws.send(JSON.stringify({type:'SCREEN',dst:'ryadom-'+'a'.repeat(32),payload:{bytes:'not allowed'}}));
    const [event]=await closed;assert.equal(event.code,1008);
    const url=new URL(base);url.protocol=url.protocol==='wss:'?'https:':'http:';url.pathname='/';
    assert.equal((await fetch(url)).status,404);
  }finally{for(const ws of sockets.splice(0))ws.close();}
});
test('alternate hostname uses the same live ID registry', {skip:!process.env.RYADOM_SIGNAL_SECONDARY_TEST_URL}, async()=>{
  const alternate=process.env.RYADOM_SIGNAL_SECONDARY_TEST_URL;
  const suffix=crypto.randomUUID().replaceAll('-','');
  try {
    const host=await connect('ryadom-'+suffix);
    const client=await connect('ryadom-client-'+suffix, alternate);
    assert.equal((await next(host)).type,'OPEN');
    assert.equal((await next(client)).type,'OPEN');
    const duplicate=await connect('ryadom-'+suffix, alternate);
    assert.equal((await next(duplicate)).type,'ID-TAKEN');
    client.ws.send(JSON.stringify({type:'OFFER',dst:'ryadom-'+suffix,payload:{connectionId:'alternate-host'}}));
    assert.equal((await next(host)).src,'ryadom-client-'+suffix);
    host.ws.send(JSON.stringify({type:'ANSWER',dst:'ryadom-client-'+suffix,payload:{connectionId:'alternate-host'}}));
    assert.equal((await next(client)).src,'ryadom-'+suffix);
  }finally{for(const ws of sockets.splice(0))ws.close();}
});
