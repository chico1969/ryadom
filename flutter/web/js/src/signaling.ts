import { directSdp, PROTOCOL_VERSION, validId } from './security';
import { RELAY_ALLOWED, TURN_SERVERS } from './network';
import signalingConfig from '../../../../ryadom/signaling.json';

const STUN_SERVERS:RTCIceServer[]=[{urls:'stun:stun.cloudflare.com:3478'},{urls:'stun:stun.l.google.com:19302'},{urls:'stun:stun.antisip.com:3478'},{urls:'stun:stun.nextcloud.com:443'}];
export const ICE: RTCConfiguration = {iceServers:[...STUN_SERVERS,...TURN_SERVERS],iceTransportPolicy:'all'};
export type Signal = {type:string; src?:string; dst?:string; payload?:any};

export class PeerSignal extends EventTarget {
  private socket?: WebSocket;
  private pulse?: ReturnType<typeof setInterval>;
  constructor(readonly id = 'ryadom-client-' + crypto.randomUUID()) { super(); }
  async open(): Promise<void> {
    return new Promise((resolve,reject) => {
      const socket = this.socket = new WebSocket(signalingConfig.url+'&id='+this.id+'&token='+crypto.randomUUID()+'&version=1.5.5');
      const timeout = setTimeout(() => { socket.close(); reject(new Error('Служба поиска не отвечает')); },15000);
      socket.onmessage = event => {
        try {
          if (typeof event.data !== 'string' || event.data.length > 131072) throw new Error('Неверное служебное сообщение');
          const msg = JSON.parse(event.data) as Signal;
          if (msg.type === 'OPEN') { clearTimeout(timeout); resolve(); }
          if(['ERROR','ID-TAKEN','INVALID-KEY'].includes(msg.type)){clearTimeout(timeout);reject(new Error('Служба поиска отклонила регистрацию'));}
          this.dispatchEvent(new CustomEvent('signal',{detail:msg}));
        } catch(error) { clearTimeout(timeout); reject(error); socket.close(); }
      };
      socket.onopen = () => { this.pulse = setInterval(() => {if(socket.readyState===WebSocket.OPEN)socket.send(JSON.stringify({type:'HEARTBEAT'}));},5000); };
      socket.onerror = () => { clearTimeout(timeout); reject(new Error('Нет связи со службой поиска')); };
      socket.onclose = () => { clearTimeout(timeout); clearInterval(this.pulse); this.dispatchEvent(new Event('offline')); reject(new Error('Служба поиска закрыла соединение')); };
    });
  }
  send(message: Signal): void {
    if (this.socket?.readyState !== WebSocket.OPEN) throw new Error('Служба поиска отключилась');
    this.socket.send(JSON.stringify(message));
  }
  close(): void { clearInterval(this.pulse); this.socket?.close(); }
}

export function directCandidate(candidate:RTCIceCandidateInit,allowRelay=false):void {
  const value=candidate.candidate??'';
  if(!value||value.length>8192||!(/\btyp (host|srflx|prflx)\b/.test(value)||(allowRelay&&/\btyp relay\b/.test(value))))throw new Error('Недопустимый или ретранслируемый ICE-кандидат');
}

export async function gather(pc: RTCPeerConnection): Promise<RTCSessionDescriptionInit> {
  if (pc.iceGatheringState !== 'complete') await new Promise<void>((resolve,reject) => {
    const timeout = setTimeout(() => { cleanup(); reject(new Error('Не удалось получить адреса прямого канала')); },20000);
    const check = () => { if (pc.iceGatheringState === 'complete') { cleanup(); resolve(); } };
    const cleanup = () => { clearTimeout(timeout); pc.removeEventListener('icegatheringstatechange',check); };
    pc.addEventListener('icegatheringstatechange',check); check();
  });
  const sdp = pc.localDescription?.toJSON();
  if (!sdp) throw new Error('Нет локального описания канала');
  directSdp(sdp); return sdp;
}

export async function proveDirect(pc: RTCPeerConnection): Promise<{local:string; remote:string}> {
  return proveTransport(pc, false);
}

export async function proveTransport(pc: RTCPeerConnection,allowRelay=RELAY_ALLOWED): Promise<{local:string;remote:string;family?:string}> {
  const stats = await pc.getStats();
  let selected: any;
  stats.forEach((row:any) => { if (row.type === 'transport' && row.selectedCandidatePairId) selected = stats.get(row.selectedCandidatePairId); });
  if (!selected) throw new Error('Прямой канал не подтверждён');
  const local = stats.get(selected.localCandidateId) as any;
  const remote = stats.get(selected.remoteCandidateId) as any;
  const allowed = ['host','srflx','prflx',...(allowRelay?['relay']:[])];
  if (!allowed.includes(local?.candidateType) || !allowed.includes(remote?.candidateType)) throw new Error('Ретрансляция запрещена');
  const address=remote.address??remote.ip;
  return {local:local.candidateType,remote:remote.candidateType,...(typeof address==='string'&&!address.endsWith('.local')?{family:address.includes(':')?'IPv6':'IPv4'}:{})};
}

export async function negotiate(peer: string, signal: PeerSignal, onChannel: (pc:RTCPeerConnection,dc:RTCDataChannel,key:string,backlog:ArrayBuffer[])=>Promise<void>,abort?:AbortSignal,turnServers=TURN_SERVERS): Promise<RTCPeerConnection> {
  const controller=new AbortController();let delivered=false;
  const cancel=()=>controller.abort();abort?.addEventListener('abort',cancel,{once:true});
  if(abort?.aborted)controller.abort();
  const deadline=setTimeout(cancel,45000);
  const accept=async(pc:RTCPeerConnection,dc:RTCDataChannel,key:string,backlog:ArrayBuffer[])=>{delivered=true;await onChannel(pc,dc,key,backlog);};
  try{
    try{return await negotiateAttempt(peer,signal,accept,controller.signal,[],true,8000);}
    catch(error){if(controller.signal.aborted||delivered)throw error;}
    return await negotiateAttempt(peer,new PeerSignal(),accept,controller.signal,turnServers,false,25000);
  }finally{clearTimeout(deadline);abort?.removeEventListener('abort',cancel);}
}

export async function negotiateDirect(peer:string,onChannel:(pc:RTCPeerConnection,dc:RTCDataChannel,key:string,backlog:ArrayBuffer[])=>Promise<void>,abort?:AbortSignal):Promise<RTCPeerConnection>{
  return negotiateAttempt(peer,new PeerSignal(),onChannel,abort,[],true,8000);
}

async function negotiateAttempt(peer: string, signal: PeerSignal, onChannel: (pc:RTCPeerConnection,dc:RTCDataChannel,key:string,backlog:ArrayBuffer[])=>Promise<void>,abort:AbortSignal|undefined,turnServers:RTCIceServer[],directOnly:boolean,budget:number): Promise<RTCPeerConnection> {
  if (!validId(peer)) throw new Error('Введите полный ID компьютера Рядом');
  const allowRelay=RELAY_ALLOWED;
  const pc = new RTCPeerConnection({iceServers:[...STUN_SERVERS,...turnServers],iceTransportPolicy:'all'});
  const dc = pc.createDataChannel('bootstrap',{ordered:true}); dc.binaryType = 'arraybuffer';
  const backlog: ArrayBuffer[] = []; let earlySize = 0;
  dc.onmessage = event => {
    if (!(event.data instanceof ArrayBuffer) || (earlySize += event.data.byteLength) > 131072) { pc.close(); return; }
    backlog.push(event.data);
  };
  const connectionId = 'dc_' + crypto.randomUUID();
  let cancelPending:((error:unknown)=>void)|undefined;
  const cancel=()=>{cancelPending?.(new Error('Подключение отменено'));pc.close();signal.close();};
  abort?.addEventListener('abort',cancel,{once:true});
  try {
    if(abort?.aborted)throw new Error('Подключение отменено');
    await signal.open();
    await new Promise<void>((resolve,reject) => {
      let hostKey='',pending=true,offerSent=false,answerSeen=false,queued=0;
      let processing:Promise<void>=Promise.resolve();
      const local:RTCIceCandidateInit[]=[];
      const timer = setTimeout(() => fail(new Error(allowRelay?'Не удалось подключиться. Проверьте сеть, удалённый ПК и квоту TURN.':'Прямой канал недоступен. Удалённый ПК может быть выключен или сеть требует TURN, который ещё не настроен.')),budget);
      const cleanup = () => { pending=false;clearTimeout(timer);signal.removeEventListener('signal',message);signal.removeEventListener('offline',offline);pc.onicecandidate=null; };
      const fail=(error:unknown)=>{if(!pending)return;cleanup();reject(error);};
      cancelPending=fail;
      const offline=()=>fail(new Error('Служба поиска отключилась до проверки канала'));
      const sendCandidate=(candidate:RTCIceCandidateInit)=>{
        directCandidate(candidate,allowRelay);
        signal.send({type:'CANDIDATE',dst:peer,payload:{type:'data',connectionId,candidate}});
      };
      const message=(event:Event)=>{
        if(!pending)return;
        const msg=(event as CustomEvent<Signal>).detail;
        if(['EXPIRE','ERROR','ID-TAKEN'].includes(msg.type)){fail(new Error('Удалённый ПК не найден или служба поиска недоступна'));return;}
        if(msg.src!==peer||msg.payload?.connectionId!==connectionId)return;
        if(++queued>128){fail(new Error('Слишком много служебных сообщений'));return;}
        processing=processing.then(async()=>{
          if(!pending)return;
          if(msg.type==='ANSWER'){
            if(answerSeen)throw new Error('Повторное описание канала');
            answerSeen=true;directSdp(msg.payload.sdp,allowRelay);hostKey=msg.payload.metadata?.publicKey??'';
            await pc.setRemoteDescription(msg.payload.sdp);
          }else if(msg.type==='CANDIDATE'){
            directCandidate(msg.payload.candidate,allowRelay);
            if(!pc.remoteDescription)throw new Error('ICE-кандидат получен до ответа');
            await pc.addIceCandidate(msg.payload.candidate);
          }
        }).catch(fail).finally(()=>{queued--;});
      };
      signal.addEventListener('signal',message);signal.addEventListener('offline',offline);
      pc.onicecandidate=event=>{
        if(!event.candidate||!pending)return;
        try{const candidate=event.candidate.toJSON();if(offerSent)sendCandidate(candidate);else local.push(candidate);}catch(error){fail(error);}
      };
      dc.onopen=async()=>{
        try{await proveTransport(pc,directOnly?false:allowRelay);await onChannel(pc,dc,hostKey,backlog);if(pending){cleanup();resolve();}}
        catch(error){fail(error);}
      };
      void (async()=>{
        await pc.setLocalDescription(await pc.createOffer());
        const sdp=pc.localDescription?.toJSON();if(!sdp)throw new Error('Нет SDP');
        directSdp(sdp,allowRelay);
        signal.send({type:'OFFER',dst:peer,payload:{sdp,type:'data',connectionId,label:'bootstrap',serialization:'raw',reliable:true,metadata:{ryadomVersion:PROTOCOL_VERSION,networkVersion:1,directOnly}}});
        offerSent=true;for(const candidate of local)sendCandidate(candidate);local.length=0;
      })().catch(fail);
    });
    signal.close();
    return pc;
  } catch(error) { pc.close(); signal.close(); throw error; }
  finally {abort?.removeEventListener('abort',cancel);}
}
