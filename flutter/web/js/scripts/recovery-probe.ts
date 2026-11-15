// Browser integration over real ICE/DTLS/SCTP with a native-wire host fixture.
// Host-side grant validation is separately exercised by the Rust tests.
import nacl from 'tweetnacl';
import protobuf from 'protobufjs/light';
import schema from '../src/schema.json';
import {Session} from '../src/session';
import {decode,encode,Wire} from '../src/protocol';
import {deviceId,fingerprint,Framing,hex} from '../src/security';
import {PeerSignal,ICE,directCandidate,proveTransport} from '../src/signaling';

const identityType=protobuf.Root.fromJSON(schema).lookupType('hbb.IdPk');
const wait=async(check:()=>boolean,seconds=15)=>{
  const end=Date.now()+seconds*1000;
  while(!check()){if(Date.now()>end)throw new Error('Recovery fixture timed out');await new Promise(r=>setTimeout(r,30));}
};
type Host={pc:RTCPeerConnection;dc?:RTCDataChannel;framing:Framing;queue:Promise<void>;authorized:boolean;number:number};
export async function run(turnServers:RTCIceServer[]=[]):Promise<unknown>{
  const signing=nacl.sign.keyPair(),box=nacl.box.keyPair(),token=crypto.getRandomValues(new Uint8Array(32));
  const id=await deviceId(signing.publicKey),host=new PeerSignal(id);await host.open();
  const channels=new Map<string,Host>(),session=new Session(id,turnServers);
  const surface=document.createElement('div');document.body.append(surface);session.mount(surface);
  let permitDirect=turnServers.length===0,revoked=false,approvals=0,resumes=0,connected=0,manualEnds=0;
  let logical='',myId='',latest:Host|undefined,failure:unknown,closed='',terminalCommands=0;
  let route='',available=false,makeBeforeBreak=false;const monitors:number[]=[],keys:string[]=[],errors:string[]=[];
  const trace:string[]=[];
  const recording:Blob[][]=[],finished:boolean[]=[],downloadData=Uint8Array.from({length:300000},(_,i)=>i%251),received:number[]=[];
  let fileClosed=false;const offsets:number[]=[];
  const picker=(window as any).showSaveFilePicker,directoryPicker=(window as any).showDirectoryPicker;
  (window as any).showSaveFilePicker=async()=>({createWritable:async()=>({write:async(bytes:Uint8Array)=>received.push(...bytes),close:async()=>{fileClosed=true;},abort:async()=>{throw new Error('Download unexpectedly aborted');}})});
  (window as any).showDirectoryPicker=async()=>({getFileHandle:async()=>{const index=recording.length;recording.push([]);return {createWritable:async()=>({write:async(blob:Blob)=>{recording[index]!.push(blob);},close:async()=>{finished[index]=true;}})};}});
  session.media.canvas.width=64;session.media.canvas.height=64;
  let tick=0;const drawing=setInterval(()=>{const context=session.media.canvas.getContext('2d')!;context.fillStyle=tick++%2?'red':'blue';context.fillRect(0,0,64,64);},40);
  const send=(c:Host,message:Wire)=>{for(const frame of Framing.encode(encode(message)))c.dc!.send(frame);};
  const receive=async(c:Host,message:Wire)=>{
    if(message.publicKey){
      const key=nacl.box.open(message.publicKey.symmetricValue,new Uint8Array(24),message.publicKey.asymmetricValue,box.secretKey);
      if(!key||key.length!==32)throw new Error('Host key exchange failed');
      send(c,{hash:{salt:'fixture',challenge:'challenge',ryadomAuthVersion:1,ryadomPasswordSet:false,ryadomSessionVersion:1}});return;
    }
    if(message.loginRequest){
      const login=message.loginRequest;
      if(login.ryadomResumeToken?.length){
        if(revoked||!nacl.verify(token,login.ryadomResumeToken)||String(login.sessionId)!==logical||login.myId!==myId){send(c,{loginResponse:{error:'RYADOM_RESUME_DENIED: revoked'}});return;}
        resumes++;if(latest?.pc.connectionState==='connected')makeBeforeBreak=true;
      }else{approvals++;logical=String(login.sessionId);myId=login.myId;}
      c.authorized=true;latest=c;
      // Native hosts may publish the floor before the login response.
      send(c,{ryadomControl:{version:1,action:'state',you:c.number,holder:c.number,participants:[{id:c.number,name:'Fixture'}]}});
      send(c,{loginResponse:{ryadomResumeToken:token,peerInfo:{hostname:'Recovery fixture',platform:'Windows',version:'1.5.3',encoding:{vp8:true},currentDisplay:0,displays:[{width:64,height:64,online:true},{width:128,height:64,online:true}]}}});return;
    }
    if(!c.authorized)throw new Error('Application command before authentication');
    if(message.misc?.switchDisplay)monitors.push(message.misc.switchDisplay.display);
    if(message.misc?.closeReason==='Ryadom session ended')manualEnds++;
    if(message.terminalAction?.data)terminalCommands++;
    if(message.keyEvent)keys.push(c.number+':'+(message.keyEvent.down?'down':'up'));
    if(message.fileAction?.send)send(c,{fileResponse:{digest:{id:message.fileAction.send.id,fileNum:0,fileSize:downloadData.length,lastModified:123}}});
    if(message.fileAction?.sendConfirm){
      const confirm=message.fileAction.sendConfirm,offset=confirm.offsetBlk??0;offsets.push(offset);
      if(offset===0)send(c,{fileResponse:{block:{id:confirm.id,fileNum:0,data:downloadData.slice(0,100000),compressed:false}}});
      else{for(let at=offset;at<downloadData.length;at+=100000)send(c,{fileResponse:{block:{id:confirm.id,fileNum:0,data:downloadData.slice(at,at+100000),compressed:false}}});send(c,{fileResponse:{done:{id:confirm.id,fileNum:0}}});}
    }
  };
  const handle=async(message:Wire)=>{
    if(trace.length<40)trace.push('signal:'+message.type);
    const cid=message.payload?.connectionId;
    if(message.type==='OFFER'){
      if(message.payload.metadata?.directOnly&&!permitDirect)return;
      const direct=message.payload.metadata?.directOnly===true;
      const pc=new RTCPeerConnection(direct?{iceServers:[]}:{iceServers:[...(ICE.iceServers??[]),...turnServers],iceTransportPolicy:turnServers.length?'relay':'all'});
      pc.onconnectionstatechange=()=>trace.push('pc:'+pc.connectionState);
      pc.onicecandidateerror=event=>trace.push('ice-error:'+event.errorCode);
      const c:Host={pc,framing:new Framing(),queue:Promise.resolve(),authorized:false,number:channels.size+1};channels.set(cid,c);
      const pending:RTCIceCandidateInit[]=[];let answered=false;
      const candidate=(candidate:RTCIceCandidateInit)=>host.send({type:'CANDIDATE',dst:message.src,payload:{connectionId:cid,type:'data',candidate}});
      pc.onicecandidate=event=>{if(event.candidate){trace.push('candidate:'+event.candidate.type);if(answered)candidate(event.candidate.toJSON());else pending.push(event.candidate.toJSON());}};
      pc.ondatachannel=event=>{
        const dc=c.dc=event.channel;dc.binaryType='arraybuffer';
        trace.push('channel:'+dc.readyState);
        let announced=false;
        const announce=()=>{if(announced)return;announced=true;const signed=identityType.encode(identityType.create({id,pk:box.publicKey,dtlsFingerprint:fingerprint(pc.localDescription!.sdp),kxVersion:0})).finish();send(c,{signedId:{id:nacl.sign(signed,signing.secretKey)}});};
        dc.onopen=announce;if(dc.readyState==='open')announce();
        dc.onmessage=event=>{c.queue=c.queue.then(async()=>{const data=c.framing.accept(new Uint8Array(event.data));if(data)await receive(c,decode(data));}).catch(error=>{failure=error;});};
      };
      await pc.setRemoteDescription(message.payload.sdp);await pc.setLocalDescription(await pc.createAnswer());
      host.send({type:'ANSWER',dst:message.src,payload:{connectionId:cid,type:'data',sdp:pc.localDescription!.toJSON(),metadata:{ryadomVersion:1,publicKey:hex(signing.publicKey)}}});
      answered=true;for(const value of pending)candidate(value);
    }else if(message.type==='CANDIDATE'&&channels.has(cid)){directCandidate(message.payload.candidate,true);await channels.get(cid)!.pc.addIceCandidate(message.payload.candidate);}
  };
  let signals=Promise.resolve();host.addEventListener('signal',event=>{signals=signals.then(()=>handle((event as CustomEvent).detail)).catch(error=>{failure=error;});});
  session.addEventListener('connected',()=>connected++);
  session.addEventListener('closed',event=>closed=(event as CustomEvent).detail);
  session.addEventListener('p2p',event=>available=(event as CustomEvent).detail.available===true);
  session.addEventListener('transport',event=>route=(event as CustomEvent).detail.relayed?'TURN':'P2P');
  session.addEventListener('error',event=>errors.push(String((event as CustomEvent).detail)));
  try{
    const began=performance.now();await session.connect();await wait(()=>session.controls);
    const initial=await proveTransport((session as any).pc,true),initialMs=Math.round(performance.now()-began);
    if(turnServers.length&&!(initial.local==='relay'||initial.remote==='relay'))throw new Error('TURN fixture did not use a relay');
    await session.monitor(1);await wait(()=>monitors.at(-1)===1);
    await session.command({terminalAction:{data:{terminalId:1,data:new TextEncoder().encode('once')}}});
    await wait(()=>terminalCommands===1);
    await session.media.startRecording();await new Promise(r=>setTimeout(r,1100));
    permitDirect=true;
    // A no-credential run exercises handoff from a direct stand-in, never labels it actual TURN.
    if(!turnServers.length)(session as any).routeRelayed=true;
    await session.checkP2P();await wait(()=>available);
    await session.switchToP2P();await wait(()=>connected===2&&session.controls&&route==='P2P');
    if(!makeBeforeBreak||approvals!==1)throw new Error('Replacement was not authorized before the old channel closed');
    const direct=await proveTransport((session as any).pc,false);
    await session.download('C:\\fixture.bin','fixture.bin',downloadData.length);await wait(()=>received.length===100000);
    latest!.pc.close();await wait(()=>connected===3&&session.controls,45);
    await wait(()=>fileClosed);if(received.length!==downloadData.length||received.some((v,i)=>v!==downloadData[i])||offsets.at(-1)!==100000)throw new Error('Download checkpoint was not resumed correctly');
    if(approvals!==1||resumes<2||monitors.at(-1)!==1||terminalCommands!==1)throw new Error('Recovery lost authorization, monitor or replayed a command');
    await new Promise(r=>setTimeout(r,1100));revoked=true;latest!.pc.close();await wait(()=>!!closed,45);
    if(!closed.includes('отозвано')||approvals!==1)throw new Error('Revoked grant requested fresh owner approval');
    if(failure)throw failure;
    if(recording.length!==3||recording.some((chunks,i)=>!finished[i]||new Blob(chunks).size===0))throw new Error('Recording fragments were not finalized and resumed');
    return {initial,initialMs,direct,ownerApprovals:approvals,authenticatedResumes:resumes,makeBeforeBreak,monitorPreserved:true,terminalNotReplayed:true,revokedSecretStopped:true,manualEnds,
      recordingFragments:recording.length,downloadCheckpoint:offsets.at(-1),downloadBytesVerified:received.length,
      actualTurn:turnServers.length>0,scope:'one physical PC; production browser client and real RTC channels with native-wire host fixture; in-memory file sinks; not remote Windows acceptance'};
  }catch(error){throw new Error(String(error)+'; fixture='+String(failure)+'; approvals='+approvals+'; resumes='+resumes+'; connected='+connected+'; errors='+JSON.stringify(errors)+'; trace='+JSON.stringify(trace));}
  finally{await session.close();host.close();for(const c of channels.values())c.pc.close();surface.remove();clearInterval(drawing);(window as any).showSaveFilePicker=picker;(window as any).showDirectoryPicker=directoryPicker;}
}
