import nacl from 'tweetnacl';
import protobuf from 'protobufjs/light';
import schema from '../src/schema.json';
import { Session } from '../src/session';
import { decode, encode, Wire } from '../src/protocol';
import { deviceId, fingerprint, Framing, hex, passwordResponse } from '../src/security';
import { directCandidate, ICE, PeerSignal, proveDirect } from '../src/signaling';

const identityType=protobuf.Root.fromJSON(schema).lookupType('hbb.IdPk');
const wait=(check:()=>boolean,ms=10000)=>new Promise<void>((resolve,reject)=>{
  const start=performance.now();const poll=()=>{if(check())resolve();else if(performance.now()-start>ms)reject(new Error('Interop wait timeout'));else setTimeout(poll,20);};poll();
});

async function attempt(tamper=false,passwordSet=true):Promise<unknown>{
  const pair=nacl.sign.keyPair(),box=nacl.box.keyPair();const id=await deviceId(pair.publicKey);
  const host=new PeerSignal(id);await host.open();
  const session=new Session(id);
  const surface=document.createElement('div');surface.style.cssText='position:relative;width:64px;height:64px';document.body.append(surface);session.mount(surface);
  let pc:RTCPeerConnection|undefined,dc:RTCDataChannel|undefined,connection='',client='',authenticated=false,wrongPasswordSeen=false,chat='';
  let hostFailure:unknown,publicKeySeen=false,loginCount=0;
  let requestedCodec='vp8',streamTimer:ReturnType<typeof setInterval>|undefined,streamEncoder:VideoEncoder|undefined;
  let codecReport:Wire={};session.addEventListener('codecTest',event=>{codecReport=(event as CustomEvent).detail;});
  const inputWire:Wire[]=[];
  const send=(value:Wire)=>{if(!dc||dc.readyState!=='open')throw new Error('Fixture channel closed');for(const frame of Framing.encode(encode(value)))dc.send(frame);};
  const incoming=new Framing();let chain=Promise.resolve();
  const receive=async(message:Wire)=>{
    if(message.publicKey){
      publicKeySeen=true;
      const key=nacl.box.open(message.publicKey.symmetricValue,new Uint8Array(24),message.publicKey.asymmetricValue,box.secretKey);
      if(!key||key.length!==32)throw new Error('NaCl key exchange failed');
      send({hash:{salt:'test-salt',challenge:'fresh-challenge',ryadomAuthVersion:passwordSet?0:1,ryadomPasswordSet:passwordSet}});if(pc)pc.onicecandidate=null;host.close();
    }else if(message.loginRequest){
      if(!publicKeySeen)throw new Error('Login before the key exchange');loginCount++;
      if(message.loginRequest.option?.supportedDecoding?.prefer!==4)throw new Error('Automatic browser codec must prefer VP8');
      const expected=await passwordResponse('тестовый-пароль','test-salt','fresh-challenge');
      const supplied=message.loginRequest.password as Uint8Array;
      if(passwordSet&&(supplied.length!==expected.length||!nacl.verify(expected,supplied))){send({loginResponse:{error:'Неверный пароль'}});return;}
      if(!passwordSet&&supplied.length)throw new Error('Saved password was sent to a host without a configured password');
      authenticated=true;
      send({loginResponse:{peerInfo:{hostname:'Тест протокола',platform:'Windows',version:'1.5.3',platformAdditions:JSON.stringify({ryadom_short_code:'987654321'}),encoding:{vp8:true},displays:[{width:64,height:64,online:true,scale:1}],currentDisplay:0}}});
      send({ryadomControl:{version:1,action:'state',you:7,holder:7,participants:[{id:7,name:'Клиент'},{id:8,name:'Наблюдатель'}]}});
    }else if(message.misc?.chatMessage){if(!authenticated)throw new Error('Application command before authorization');chat=message.misc.chatMessage.text;send({misc:{chatMessage:{text:'Получено: '+chat}}});}
    else if(message.keyEvent||message.clipboard||message.mouseEvent){if(!authenticated)throw new Error('Input before authorization');inputWire.push(message);}
    else if(message.misc?.option?.supportedDecoding){requestedCodec=message.misc.option.supportedDecoding.prefer===4?'vp8':'vp9';}
  };
  const handle=async(message:Wire)=>{
    if(message.type==='OFFER'){
      client=message.src;connection=message.payload.connectionId;
      pc=new RTCPeerConnection(ICE);
      const local:RTCIceCandidateInit[]=[];let answerSent=false;
      const candidate=(candidate:RTCIceCandidateInit)=>{directCandidate(candidate);host.send({type:'CANDIDATE',dst:client,payload:{connectionId:connection,type:'data',candidate}});};
      pc.onicecandidate=event=>{if(event.candidate){if(answerSent)candidate(event.candidate.toJSON());else local.push(event.candidate.toJSON());}};
      pc.ondatachannel=event=>{
        dc=event.channel;dc.binaryType='arraybuffer';
        let announced=false;
        const announce=()=>{
          if(announced)return;announced=true;
          const signed=identityType.encode(identityType.create({id,pk:box.publicKey,dtlsFingerprint:tamper?'sha-256 00:00':fingerprint(pc!.localDescription!.sdp),kxVersion:0})).finish();
          send({signedId:{id:nacl.sign(signed,pair.secretKey)}});
        };
        dc.onopen=announce;if(dc.readyState==='open')announce();
        dc.onmessage=event=>{chain=chain.then(async()=>{const bytes=incoming.accept(new Uint8Array(event.data));if(bytes)await receive(decode(bytes));}).catch(error=>{hostFailure=error;});};
      };
      await pc.setRemoteDescription(message.payload.sdp);await pc.setLocalDescription(await pc.createAnswer());
      host.send({type:'ANSWER',dst:client,payload:{connectionId:connection,type:'data',sdp:pc.localDescription!.toJSON(),metadata:{ryadomVersion:1,publicKey:hex(pair.publicKey)}}});
      answerSent=true;for(const value of local)candidate(value);
    }else if(message.type==='CANDIDATE'&&message.src===client&&message.payload.connectionId===connection){directCandidate(message.payload.candidate);await pc!.addIceCandidate(message.payload.candidate);}
  };
  let signaling=Promise.resolve();
  host.addEventListener('signal',event=>{const message=(event as CustomEvent).detail;signaling=signaling.then(()=>handle(message)).catch(error=>{hostFailure=error;});});
  let echoed='';session.addEventListener('chat',event=>{echoed=(event as CustomEvent).detail;});
  const errors:string[]=[];session.addEventListener('error',event=>errors.push(String((event as CustomEvent).detail)));
  let stage='connect';
  session.addEventListener('password',()=>{wrongPasswordSeen=true;void session.login('тестовый-пароль');});
  try{
    if(tamper){
      let rejected=false;try{await session.connect('тестовый-пароль');}catch{rejected=true;}
      if(!rejected||publicKeySeen||loginCount)throw new Error('Forged DTLS binding reached authentication');
      return {tamperedFingerprintRejected:true,passwordSent:false};
    }
    await session.connect('неверный-пароль');stage='control';await wait(()=>session.controls);
    if(hostFailure)throw hostFailure;
    if(!passwordSet){if(wrongPasswordSeen||loginCount!==1)throw new Error('Unnecessary password prompt');return {noPasswordPrompt:true,stalePasswordNotSent:true,scope:'protocol fixture simulates owner approval; not a real Windows permission dialog'};}
    stage='chat';await session.chat('Кириллица ✓');await wait(()=>!!echoed);
    if(!wrongPasswordSeen||loginCount!==2||chat!=='Кириллица ✓')throw new Error('Password retry or chat interop failed');
    stage='input';
    const input=session.media.canvas;
    input.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',code:'Backspace'}));
    input.dispatchEvent(new KeyboardEvent('keydown',{key:'Backspace',code:'Backspace',repeat:true}));
    input.dispatchEvent(new KeyboardEvent('keyup',{key:'Backspace',code:'Backspace'}));
    input.dispatchEvent(new KeyboardEvent('keydown',{key:'с',code:'KeyC',ctrlKey:true}));
    input.dispatchEvent(new KeyboardEvent('keyup',{key:'с',code:'KeyC',ctrlKey:true}));
    session.clipboardAllowed=true;
    const data=new DataTransfer();data.setData('text/plain','Текст через буфер ✓');
    input.dispatchEvent(new ClipboardEvent('paste',{clipboardData:data}));
    await wait(()=>inputWire.length===8);
    if(!inputWire[0]?.keyEvent?.down||!inputWire[1]?.keyEvent?.down||inputWire[2]?.keyEvent?.down!==false)throw new Error('Key repeat or release lost');
    if(inputWire[3]?.keyEvent?.chr!==99||inputWire[4]?.keyEvent?.chr!==99)throw new Error('Cyrillic Ctrl+C shortcut lost');
    if(new TextDecoder().decode(inputWire[5]?.clipboard?.content)!=='Текст через буфер ✓'||inputWire[6]?.keyEvent?.chr!==118||!inputWire[6]?.keyEvent?.down||inputWire[7]?.keyEvent?.down!==false)throw new Error('Clipboard must precede paste shortcut');
    stage='video';const canvas=document.createElement('canvas');canvas.width=64;canvas.height=64;const ctx=canvas.getContext('2d')!;ctx.fillStyle='#e45f35';ctx.fillRect(0,0,64,64);
    let streamCodec='',tick=0;
    streamTimer=setInterval(()=>{try{
      if(streamCodec!==requestedCodec){streamEncoder?.close();streamCodec=requestedCodec;const codec=streamCodec;
        streamEncoder=new VideoEncoder({output:chunk=>{const data=new Uint8Array(chunk.byteLength);chunk.copyTo(data);send({videoFrame:{[codec==='vp8'?'vp8s':'vp9s']:{frames:[{data,key:chunk.type==='key'}]},display:0}});},error:error=>{hostFailure=error;}});
        streamEncoder.configure({codec:codec==='vp8'?'vp8':'vp09.00.10.08',width:64,height:64,bitrate:100000,framerate:20,latencyMode:'realtime'});
      }
      ctx.fillStyle=`rgb(${tick++%255},95,53)`;ctx.fillRect(0,0,64,64);
      const frame=new VideoFrame(canvas,{timestamp:Math.round(performance.now()*1000)});streamEncoder!.encode(frame);frame.close();
    }catch(error){hostFailure=error;}},50);
    await wait(()=>session.media.decoded>0);
    stage='codec comparison';await wait(()=>String(codecReport.status).startsWith('Авто:'),18000);
    if(hostFailure)throw hostFailure;
    if(codecReport.results?.length!==2||!codecReport.results.every((r:Wire)=>r.fps>=3&&r.delayMs>=0&&r.bytesPerSecond>0))throw new Error('Real codec trials did not measure both VP8 and VP9');
    const measuredCodecs=codecReport.results;
    await session.setCodec('vp8');await wait(()=>session.media.activeCodec==='vp8');
    send({cursorPosition:{x:22,y:18}});
    await wait(()=>surface.querySelector('svg')?.parentElement?.style.display==='block');
    const marker=surface.querySelector('svg')!.parentElement!;
    if(marker.style.left!=='22px'||marker.style.top!=='18px'||surface.querySelector('path')?.getAttribute('fill')!=='#ff8a1c')throw new Error('Remote cursor marker is not orange or incorrectly positioned');
    stage='recording';const originalPicker=(window as any).showDirectoryPicker;const chunks:Blob[]=[];let recordingClosed=false;
    (window as any).showDirectoryPicker=async()=>({getFileHandle:async()=>({createWritable:async()=>({write:async(data:Blob)=>{chunks.push(data);},close:async()=>{recordingClosed=true;}})})});
    let recording:{bytes:number;width:number;height:number};
    try{
      await session.media.startRecording();
      session.media.canvas.getContext('2d')!.fillRect(0,0,1,1);await new Promise(resolve=>setTimeout(resolve,1200));await session.media.stopRecording();
      const file=new Blob(chunks,{type:'video/webm'});const url=URL.createObjectURL(file);const playback=document.createElement('video');playback.muted=true;
      try{const loaded=new Promise<void>((resolve,reject)=>{playback.onloadeddata=()=>resolve();playback.onerror=()=>reject(new Error('Recorded WebM cannot be decoded'));setTimeout(()=>reject(new Error('WebM playback timeout')),5000);});playback.src=url;await loaded;
        recording={bytes:file.size,width:playback.videoWidth,height:playback.videoHeight};if(!recordingClosed||!file.size||playback.videoWidth!==64)throw new Error('Recording was incomplete');
      }finally{playback.removeAttribute('src');playback.load();URL.revokeObjectURL(url);}
    }finally{(window as any).showDirectoryPicker=originalPicker;}
    stage='observer';send({ryadomControl:{version:1,action:'state',you:7,holder:8,participants:[{id:7,name:'Клиент'},{id:8,name:'Другой управляющий'}]}});
    await wait(()=>!session.controls);
    let blocked=false;try{await session.command({terminalAction:{open:{terminalId:1}}});}catch{blocked=true;}
    if(!blocked)throw new Error('Observer could send terminal command');
    const rect=session.media.canvas.getBoundingClientRect();
    session.media.canvas.dispatchEvent(new PointerEvent('pointermove',{clientX:rect.left+12,clientY:rect.top+14}));
    session.media.canvas.dispatchEvent(new PointerEvent('pointerdown',{button:0,clientX:rect.left+12,clientY:rect.top+14}));
    session.media.canvas.dispatchEvent(new PointerEvent('pointerup',{button:0,clientX:rect.left+12,clientY:rect.top+14}));
    await wait(()=>inputWire.length===10);
    if(inputWire[8]?.mouseEvent?.mask!==0||inputWire[9]?.mouseEvent?.mask!==10)throw new Error('Observer pointing must only send movement and a visual click');
    return {passwordRetry:true,chat:echoed,keyboardRepeatAndRelease:true,cyrillicShortcut:true,clipboardBeforePaste:true,remoteCursorOrange:true,observerPointing:true,automaticCodecPreference:'VP8',measuredCodecs,manualCodecPreserved:true,videoFrames:session.media.decoded,recording,observerTerminalBlocked:true,signalingClosedDuringSession:true,pair:await proveDirect(pc!),scope:'native-wire browser fixture with a synthetic 64x64 moving stream, not Windows performance or OS input; recording uses an in-memory file sink'};
  }catch(error){throw new Error(stage+': '+String(error)+'; host='+String(hostFailure)+'; errors='+JSON.stringify(errors)+'; inputMasks='+JSON.stringify(inputWire.map(value=>value.mouseEvent?.mask??'text'))+'; bounds='+JSON.stringify(session.media.canvas.getBoundingClientRect().toJSON()));}
  finally{clearInterval(streamTimer);streamEncoder?.close();await session.close();host.close();pc?.close();surface.remove();}
}
export async function run():Promise<unknown>{return {normal:await attempt(),tamper:await attempt(true),withoutPassword:await attempt(false,false)};}
