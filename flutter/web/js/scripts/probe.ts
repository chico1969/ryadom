import { Framing } from '../src/security';
import { gather, ICE, PeerSignal, proveDirect } from '../src/signaling';
import signalingConfig from '../../../../ryadom/signaling.json';

export async function direct():Promise<unknown> {
  const a=new RTCPeerConnection({iceServers:[]}), b=new RTCPeerConnection({iceServers:[]});
  try {
    const tx=a.createDataChannel('bootstrap',{ordered:true});tx.binaryType='arraybuffer';
    const data=Uint8Array.from({length:150000},(_,i)=>i%251);
    const received=new Promise<Uint8Array>((resolve,reject)=>{
      b.ondatachannel=event=>{const rx=event.channel;rx.binaryType='arraybuffer';const framing=new Framing();
        rx.onmessage=event=>{try{const bytes=framing.accept(new Uint8Array(event.data));if(bytes)resolve(bytes);}catch(error){reject(error);}};
      };
    });
    const opened=new Promise<void>(resolve=>{tx.onopen=()=>resolve();});
    await a.setLocalDescription(await a.createOffer());await b.setRemoteDescription(await gather(a));
    await b.setLocalDescription(await b.createAnswer());await a.setRemoteDescription(await gather(b));
    await opened;for(const frame of Framing.encode(data))tx.send(frame);
    const bytes=await received;if(bytes.length!==data.length||bytes.some((v,i)=>v!==data[i]))throw new Error('Data channel corrupted bytes');
    return {bytes:bytes.length,pair:await proveDirect(a),scope:'two local RTCPeerConnection instances; not two physical PCs'};
  } finally {a.close();b.close();}
}

export async function publicDiscovery():Promise<unknown> {
  const a=new PeerSignal(),b=new PeerSignal('ryadom-'+crypto.randomUUID().replaceAll('-',''));
  const messages:unknown[]=[];
  a.addEventListener('signal',event=>{const message=(event as CustomEvent).detail;messages.push({peer:'a',type:message.type,src:message.src});});
  b.addEventListener('signal',event=>{const message=(event as CustomEvent).detail;messages.push({peer:'b',type:message.type,src:message.src});});
  try {
    await Promise.all([a.open(),b.open()]);
    const received=new Promise<void>((resolve,reject)=>{
      const timer=setTimeout(()=>reject(new Error('Public signaling did not deliver OFFER: '+JSON.stringify(messages))),10000);
      b.addEventListener('signal',event=>{const msg=(event as CustomEvent).detail;if(msg.type==='OFFER'&&msg.src===a.id){clearTimeout(timer);resolve();}});
    });
    // Only negotiation metadata is sent to the signaling service.
    const pc=new RTCPeerConnection(ICE);pc.createDataChannel('bootstrap');await pc.setLocalDescription(await pc.createOffer());
    const offer=pc.localDescription!.toJSON();
    a.send({type:'OFFER',src:a.id,dst:b.id,payload:{type:'data',sdp:offer,label:'bootstrap',reliable:true,serialization:'raw',connectionId:'dc_'+crypto.randomUUID(),metadata:{ryadomVersion:1,probe:true}}});
    try{await received;return {provider:new URL(signalingConfig.url).hostname,userKeyRequired:false,registered:true};}finally{pc.close();}
  } finally {a.close();b.close();}
}
