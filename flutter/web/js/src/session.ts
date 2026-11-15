import { decompress } from 'fzstd';
import { decode, encode, idPk, Wire } from './protocol';
import { deviceId, exchangeKey, fingerprint, Framing, passwordResponse, unhex, verifyIdentity } from './security';
import { negotiate, negotiateDirect, PeerSignal, proveTransport } from './signaling';
import { Media } from './media';
import { Vault } from './vault';
import { keyEvent } from './keyboard';
import { parseTurnServers, RELAY_ALLOWED, TURN_SERVERS } from './network';
import {chooseMeasuredCodec,CodecMeasurement} from './codec-score';
import type { Terminal } from '@xterm/xterm';
import '@xterm/xterm/css/xterm.css';

export class Session extends EventTarget {
  displayCode='';
  readonly media = new Media();
  private pc?: RTCPeerConnection;
  private dc?: RTCDataChannel;
  private phase: 'idle'|'connecting'|'identity'|'authentication'|'active'|'recovering'|'closed' = 'idle';
  private framing = new Framing();
  private resumeToken=new Uint8Array();
  private readonly myId='browser-'+crypto.randomUUID();
  private readonly sessionId=BigInt('0x'+Array.from(crypto.getRandomValues(new Uint8Array(8)),b=>b.toString(16).padStart(2,'0')).join('')).toString();
  private resumeDeadline=0;
  private recovering=false;
  private transportEpoch=0;
  private selectedMonitor=-1;
  private lostTimer?:ReturnType<typeof setTimeout>;
  private directAvailable=false;
  private directChecking=false;
  private probeTimers:ReturnType<typeof setTimeout>[]=[];
  private routeRelayed=false;
  private readonly networkChanged=()=>{if(this.active&&this.routeRelayed)void this.checkP2P();};
  private inputQueue: Promise<void> = Promise.resolve();
  private queuedBytes = 0;
  private outputQueue: Promise<void> = Promise.resolve();
  private challenge?: Wire;
  private password = '';
  private remember = false;
  private authenticatedIdentity = false;
  private readyIdentity?: () => void;
  private rejectIdentity?: (error:unknown)=>void;
  private readyAccess?:()=>void;
  private rejectAccess?:(error:unknown)=>void;
  private readonly vault = new Vault();
  private keys = new Map<string,Wire>();
  private buttons = new Set<number>();
  private floor: Wire = {};
  private controlEpoch = 0;
  private display: Wire = {};
  private nextFileId = 1;
  private terminal?: Terminal;
  private terminalResize?: ResizeObserver;
  private closing = false;
  private abort=new AbortController();
  clipboardAllowed = false;
  private uploads = new Map<number,{file:File;directory:string;resuming:boolean;sent:number;resolve:()=>void;reject:(e:unknown)=>void}>();
  private downloads = new Map<number,{sink:FileSystemWritableFileStream;path:string;received:number;size:number;modified?:string;write:Promise<void>}>();
  private filesPending=false;
  private fileOperations = new Map<number,{resolve:()=>void;reject:(error:unknown)=>void}>();
  private readonly turnServers:RTCIceServer[];
  private peerEncoding:Wire={};
  private codecEpoch=0;
  private codecRunning=false;
  private codecTestStarted=false;
  private codecAutomatic=true;
  private preferredCodec='vp8';
  constructor(readonly peer:string,turnServers=TURN_SERVERS) {
    const configured= parseTurnServers(JSON.stringify(turnServers));
    super(); this.turnServers=configured; this.media.onError = error=>this.emit('error',String(error));
    window.addEventListener('online',this.networkChanged);
    (navigator as any).connection?.addEventListener('change',this.networkChanged);
    this.media.onFrame = () => {
      void this.send({misc:{videoReceived:true}}).catch(error=>this.fail(error));
      if(this.controls&&this.codecAutomatic&&!this.codecTestStarted){this.codecTestStarted=true;void this.testCodecs();}
    };
  }
  private emit(name:string,detail:any): void { this.dispatchEvent(new CustomEvent(name,{detail})); }
  get active(): boolean { return this.phase === 'active'; }
  mount(element:HTMLElement): void { this.media.mount(element); }
  async mountTerminal(element:HTMLElement): Promise<void> {
    if(this.terminal?.element){element.appendChild(this.terminal.element);this.terminalResize?.disconnect();this.terminalResize?.observe(element);return;}
    const [{Terminal},{FitAddon}]=await Promise.all([import('@xterm/xterm'),import('@xterm/addon-fit')]);
    const terminal=this.terminal=new Terminal({cursorBlink:true,fontFamily:'Consolas,monospace',scrollback:2000,theme:{background:'#111827'}});
    const fit=new FitAddon();terminal.loadAddon(fit);terminal.open(element);fit.fit();
    terminal.onData(data=>{if(this.controls)void this.terminalWrite(data).catch(error=>this.emit('error',String(error)));});
    this.terminalResize=new ResizeObserver(()=>{fit.fit();if(this.controls)void this.command({terminalAction:{resize:{terminalId:1,cols:terminal.cols,rows:terminal.rows}}}).catch(error=>this.emit('error',String(error)));});
    this.terminalResize.observe(element);
  }
  get controls(): boolean { return this.active && !!this.floor.you && this.floor.holder === this.floor.you; }
  async connect(password='', remember=false): Promise<void> {
    if (this.phase !== 'idle') throw new Error('Сеанс уже запущен');
    return this.establish(password,remember);
  }
  private async establish(password='',remember=false):Promise<void>{
    ++this.transportEpoch;this.framing=new Framing();this.authenticatedIdentity=false;this.challenge=undefined;
    this.inputQueue=Promise.resolve();this.outputQueue=Promise.resolve();this.queuedBytes=0;
    this.phase='connecting';
    const access=new Promise<void>((resolve,reject)=>{this.readyAccess=resolve;this.rejectAccess=reject;});
    void access.catch(()=>{});
    let stored='';try{stored=await this.vault.password(this.peer)||'';}catch{this.emit('warning','Сохранённый пароль недоступен');}
    this.password = password || stored; this.remember = remember;
    if(this.closing)throw new Error('Подключение отменено');
    this.emit('status','Поиск компьютера и установка прямого канала');
    const signal = new PeerSignal();
    try {
      this.pc = await negotiate(this.peer,signal,async (pc,dc,key,backlog) => {
        if(this.closing)throw new Error('Подключение отменено');
        this.pc = pc; this.dc = dc; this.phase = 'identity';
        const pk = unhex(key); if (await deviceId(pk) !== this.peer) throw new Error('Подмена ключа компьютера');
        if(this.closing)throw new Error('Подключение отменено');
        const identity = new Promise<void>((resolve,reject) => { this.readyIdentity=resolve; this.rejectIdentity=reject; });
        const epoch=this.transportEpoch;
        dc.onmessage = event => {
          if(epoch!==this.transportEpoch)return;
          if (!(event.data instanceof ArrayBuffer)) { this.fail(new Error('Недопустимый формат данных')); return; }
          this.queuedBytes+=event.data.byteLength;
          if(this.queuedBytes>32*1024*1024){this.fail(new Error('Обработка данных не успевает за каналом'));return;}
          this.inputQueue = this.inputQueue.then(async () => {
            if(epoch!==this.transportEpoch)return;
            const bytes = this.framing.accept(new Uint8Array(event.data),this.phase==='identity'?65536:16*1024*1024);
            if (bytes) await this.receive(decode(bytes),pk);
          }).catch(error=>this.fail(error)).finally(()=>{this.queuedBytes-=event.data.byteLength;});
        };
        dc.onclose = () => { if(epoch===this.transportEpoch)void this.transportLost('Соединение закрыто'); };
        for (const data of backlog) dc.dispatchEvent(new MessageEvent('message',{data}));
        backlog.length = 0;
        pc.onconnectionstatechange = () => {
          if(epoch!==this.transportEpoch)return;
          if (['failed','closed'].includes(pc.connectionState)) void this.transportLost('Соединение прервано');
          if (pc.connectionState === 'disconnected') {
            this.emit('status','Интернет временно недоступен');clearTimeout(this.lostTimer);
            this.lostTimer=setTimeout(()=>{if(epoch===this.transportEpoch&&pc.connectionState==='disconnected')void this.transportLost('Связь потеряна');},5000);
          }
          if(pc.connectionState==='connected')clearTimeout(this.lostTimer);
        };
        this.bindInput();
        await identity;
        await this.reportTransport(pc);
        pc.sctp?.transport.iceTransport.addEventListener('selectedcandidatepairchange',()=>{
          void this.reportTransport(pc).catch(()=>this.emit('transport',{relayed:null}));
        });
      },this.abort.signal,this.turnServers);
      await access;
    } catch(error) { if(!this.recovering)await this.close(String(error));throw error; }
  }
  private async reportTransport(pc:RTCPeerConnection):Promise<void> {
    const pair=await proveTransport(pc,RELAY_ALLOWED);
    if(this.phase==='closed')return;
    if(pc!==this.pc)return;
    this.routeRelayed=pair.local==='relay'||pair.remote==='relay';
    this.emit('transport',{...pair,relayed:this.routeRelayed});
    if(pair.local!=='relay'&&pair.remote!=='relay')this.emit('direct',pair);
  }
  private async receive(message:Wire, publicKey:Uint8Array): Promise<void> {
    const receiveEpoch=this.transportEpoch;
    if (this.phase === 'closed') return;
    if (this.phase === 'identity') {
      if (!message.signedId || !this.pc?.remoteDescription) throw new Error('Не получена подписанная личность компьютера');
      const identity = idPk(verifyIdentity(message.signedId.id,publicKey));
      if (identity.id !== this.peer || identity.dtlsFingerprint !== fingerprint(this.pc.remoteDescription.sdp)) throw new Error('Личность компьютера не привязана к каналу');
      await this.send({publicKey:exchangeKey(identity.pk)},true);
      this.authenticatedIdentity = true; this.phase = 'authentication'; this.readyIdentity?.(); return;
    }
    if (message.hash && this.phase === 'authentication') {
      if(this.recovering&&message.hash.ryadomSessionVersion!==1)throw new Error('Удалённый ПК не поддерживает восстановление этого сеанса');
      this.challenge = message.hash;
      if(message.hash.ryadomAuthVersion===1&&!message.hash.ryadomPasswordSet)this.password='';
      await this.login();
      if(message.hash.ryadomAuthVersion===1&&message.hash.ryadomPasswordSet&&!this.password)this.emit('password','Введите постоянный пароль или дождитесь разрешения владельца');
      return;
    }
    if (message.loginResponse) {
      const response = message.loginResponse;
      if (response.error) {
        if(response.error.startsWith('RYADOM_RESUME_DENIED')){this.resumeToken=new Uint8Array();await this.close('Разрешение истекло или отозвано. Подключитесь заново.');return;}
        this.emit('password',response.error); return;
      }
      if (!response.peerInfo || !this.authenticatedIdentity || this.phase !== 'authentication') throw new Error('Неверный порядок авторизации');
      this.phase = 'active'; this.display = response.peerInfo.displays?.[response.peerInfo.currentDisplay ?? 0] ?? {};
      if(response.ryadomResumeToken?.length===32)this.resumeToken=new Uint8Array(response.ryadomResumeToken);
      if(this.selectedMonitor<0)this.selectedMonitor=response.peerInfo.currentDisplay??0;
      else if(this.selectedMonitor!==(response.peerInfo.currentDisplay??0))await this.monitor(this.selectedMonitor);
      this.peerEncoding=response.peerInfo.encoding??{};
      this.preferredCodec=this.peerEncoding.vp8?'vp8':'vp9';
      try {
        let code=this.displayCode;
        try{const additions=JSON.parse(response.peerInfo.platformAdditions||'{}');if(/^[1-9][0-9]{8}$/.test(additions.ryadom_short_code??''))code=additions.ryadom_short_code;}catch{}
        await this.vault.remember({id:this.peer,name:response.peerInfo.hostname || this.peer,code:/^[1-9][0-9]{8}$/.test(code)?code:undefined,lastConnected:Date.now()});
        if (this.remember && this.password) await this.vault.savePassword(this.peer,this.password);
      } catch { this.emit('warning','Соединение работает, но браузер запретил сохранение компьютера или пароля'); }
      if(this.phase!=='active'||receiveEpoch!==this.transportEpoch)return;
      this.resumeDeadline=0;this.password = ''; this.readyAccess?.();this.emit('connected',{...response.peerInfo,currentDisplay:this.selectedMonitor});
      if(this.controls&&this.filesPending)await this.resumeFiles();
      await this.media.resumeRecording().catch(error=>this.emit('warning','Новый фрагмент записи не создан: '+String(error)));
      this.scheduleProbes();return;
    }
    if (message.ryadomControl) { if(this.floor.holder!==message.ryadomControl.holder)this.controlEpoch++;this.floor=message.ryadomControl; if (!this.controls) this.releaseLocalInput(); this.emit('control',this.floor); if(this.controls){await this.command({misc:{option:{enableFileTransfer:2}}});if(this.filesPending)await this.resumeFiles();}return; }
    if (!this.active) return;
    if (message.videoFrame) { this.media.videoFrame(message.videoFrame); return; }
    if (message.audioFrame) { this.media.audioFrame(message.audioFrame); return; }
    if (message.testDelay && !message.testDelay.fromClient) { await this.send({testDelay:message.testDelay}); return; }
    if (message.misc) {
      const misc = message.misc;
      if (misc.chatMessage) this.emit('chat',misc.chatMessage.text);
      if (misc.audioFormat) this.media.audioFormat(misc.audioFormat);
      if (misc.switchDisplay) { this.display = misc.switchDisplay; this.emit('display',misc.switchDisplay); }
      if (misc.closeReason) await this.close(misc.closeReason);
      if (misc.permissionInfo) this.emit('permission',misc.permissionInfo);
    }
    if (message.clipboard && this.clipboardAllowed && (!message.clipboard.format || message.clipboard.format === 0)) {
      const text = new TextDecoder().decode(message.clipboard.compress ? decompress(message.clipboard.content) : message.clipboard.content);
      this.emit('clipboard',text); // Writing the system clipboard requires a user gesture in some browsers.
      if(document.hasFocus()&&navigator.clipboard?.writeText)void navigator.clipboard.writeText(text).catch(()=>this.emit('warning','Браузер не разрешил запись буфера. Используйте кнопку копирования в панели буфера.'));
    }
    if (message.fileResponse) await this.fileResponse(message.fileResponse);
    if(message.cursorPosition)this.media.showRemoteCursor(message.cursorPosition.x-(this.display.x??0),message.cursorPosition.y-(this.display.y??0));
    if(message.misc?.switchDisplay)this.display=message.misc.switchDisplay;
    if (message.fileAction?.sendConfirm) {
      const confirm=message.fileAction.sendConfirm;
      if (this.uploads.has(confirm.id)) {
        if (confirm.skip) { this.uploads.get(confirm.id)?.resolve(); this.uploads.delete(confirm.id); }
        else void this.transmitUpload(confirm.id,confirm.offsetBlk??0).catch(error=>this.emit('error',String(error)));
      }
    }
    if (message.terminalResponse) {
      const response=message.terminalResponse;
      if(response.data){const data=response.data.compressed?decompress(response.data.data):response.data.data;this.terminal?.write(data);this.emit('terminalText',new TextDecoder().decode(data));}
      if(response.error)this.emit('error',response.error.message);
      this.emit('terminal',response);
    }
  }
  async login(password?:string,remember?:boolean): Promise<void> {
    if (password !== undefined) this.password=password;
    if (remember !== undefined) this.remember=remember;
    if (!this.challenge || this.phase !== 'authentication') throw new Error('Компьютер ещё не готов к проверке пароля');
    const response = this.password ? await passwordResponse(this.password,this.challenge.salt,this.challenge.challenge) : new Uint8Array();
    await this.send(this.loginMessage(response,this.challenge.ryadomSessionVersion===1?this.resumeToken:undefined),true);
    this.emit('status',this.password ? 'Проверка пароля' : 'Ожидание разрешения на удалённом ПК');
  }
  private loginMessage(password:Uint8Array,resume?:Uint8Array):Wire {
    return {loginRequest:{username:this.peer,password,myId:this.myId,sessionId:this.sessionId,ryadomSessionVersion:1,ryadomResumeToken:resume,myName:'Браузер • Рядом',myPlatform:'Web',version:'1.5.3',videoAckRequired:true,option:{supportedDecoding:{abilityVp9:1,abilityVp8:1,prefer:4},customFps:30,imageQuality:3,disableAudio:1,enableFileTransfer:2,showRemoteCursor:2}}};
  }
  private clearProbes():void {for(const timer of this.probeTimers)clearTimeout(timer);this.probeTimers=[];this.directAvailable=false;this.emit('p2p',{available:false,checking:false});}
  private scheduleProbes():void {
    this.clearProbes();
    for(const delay of [15000,45000])this.probeTimers.push(setTimeout(()=>{if(this.active&&this.routeRelayed)void this.checkP2P();},delay));
  }
  async checkP2P():Promise<void> {
    if(!this.active||!this.routeRelayed||this.directChecking||this.resumeToken.length!==32)return;
    this.directChecking=true;this.emit('p2p',{available:false,checking:true});
    try{
      const direct=await this.prepareDirect(false);direct.pc.close();
      this.directAvailable=true;this.emit('p2p',{available:true,checking:false,message:'P2P работает: прямой канал со вторым ПК проверен'});
      this.probeTimers.push(setTimeout(()=>{this.directAvailable=false;this.emit('p2p',{available:false,checking:false});},60000));
    }catch{this.directAvailable=false;this.emit('p2p',{available:false,checking:false,message:'Прямой путь недоступен. TURN продолжает работать.'});}
    finally{this.directChecking=false;}
  }
  private async prepareDirect(authorize:boolean):Promise<{pc:RTCPeerConnection;dc:RTCDataChannel;pk:Uint8Array;framing:Framing;messages:Wire[];queue:()=>Promise<void>}> {
    const framing=new Framing(),messages:Wire[]=[];let channel:RTCDataChannel|undefined,pk=new Uint8Array(),queue=Promise.resolve(),state='identity',bytes=0;
    const login=this.loginMessage(new Uint8Array(),new Uint8Array(this.resumeToken));
    const pc=await negotiateDirect(this.peer,async(pc,dc,key,backlog)=>{
      channel=dc;pk=unhex(key);if(await deviceId(pk)!==this.peer)throw new Error('Ключ прямого канала изменён');
      await new Promise<void>((resolve,reject)=>{
        const send=(message:Wire)=>{for(const frame of Framing.encode(encode(message)))dc.send(frame);};
        dc.onclose=()=>reject(new Error('Проверяемый канал закрылся'));
        dc.onmessage=event=>{
          if(!(event.data instanceof ArrayBuffer)){reject(new Error('Неверный формат прямого канала'));return;}
          queue=queue.then(async()=>{
            const payload=framing.accept(new Uint8Array(event.data),1024*1024);if(!payload)return;
            const message=decode(payload);
            if(state==='identity'){
              if(!message.signedId||!pc.remoteDescription)throw new Error('Нет личности прямого канала');
              const id=idPk(verifyIdentity(message.signedId.id,pk));
              if(id.id!==this.peer||id.dtlsFingerprint!==fingerprint(pc.remoteDescription.sdp))throw new Error('Подмена прямого канала');
              send({publicKey:exchangeKey(id.pk)});state='hash';return;
            }
            if(state==='hash'){
              if(message.hash?.ryadomSessionVersion!==1)throw new Error('Обновите Рядом на удалённом ПК');
              if(!authorize){state='ready';resolve();return;}
              if(this.closing||this.resumeToken.length!==32)throw new Error('Сеанс завершён');
              state='login';send(login);return;
            }
            if(!authorize)return;
            if(state==='ready'&&(message.videoFrame||message.audioFrame||message.cursorPosition))return;
            if(message.loginResponse&&!message.loginResponse.peerInfo)throw new Error('Разрешение на прямой канал не подтверждено');
            bytes+=payload.length;if(bytes>1024*1024||messages.length>=32)throw new Error('Слишком много данных до перехода');
            messages.push(message);
            if(message.loginResponse?.peerInfo){state='ready';resolve();}
          }).catch(error=>{reject(error);pc.close();});
        };
        for(const data of backlog)dc.dispatchEvent(new MessageEvent('message',{data}));backlog.length=0;
      });
    },this.abort.signal);
    if(!channel){pc.close();throw new Error('Нет прямого канала');}
    return {pc,dc:channel,pk,framing,messages,queue:()=>queue};
  }
  async switchToP2P():Promise<void> {
    if(!this.active||!this.routeRelayed||this.directChecking||!this.directAvailable)return;
    this.directChecking=true;
    try{
      const candidate=await this.prepareDirect(true);
      await this.media.suspendRecording().catch(error=>this.emit('warning',String(error)));
      if(!this.active||this.closing||candidate.dc.readyState!=='open'){candidate.pc.close();await this.media.resumeRecording();return;}
      // The replacement is authenticated before the working relay is closed.
      const old=this.pc;this.releaseLocalInput();++this.transportEpoch;++this.controlEpoch;this.phase='authentication';
      this.filesPending=true;for(const job of this.uploads.values())job.resuming=true;
      for(const operation of this.fileOperations.values())operation.reject(new Error('Канал заменён; команду нужно повторить явно'));this.fileOperations.clear();
      const epoch=this.transportEpoch;this.floor={};this.phase='authentication';this.authenticatedIdentity=true;
      this.pc=candidate.pc;this.dc=candidate.dc;this.framing=candidate.framing;
      this.outputQueue=Promise.resolve();this.queuedBytes=0;
      this.inputQueue=candidate.queue().then(async()=>{for(const message of candidate.messages)await this.receive(message,candidate.pk);});
      candidate.dc.onmessage=event=>{
        if(epoch!==this.transportEpoch||!(event.data instanceof ArrayBuffer))return;
        this.inputQueue=this.inputQueue.then(async()=>{if(epoch!==this.transportEpoch)return;
          const data=this.framing.accept(new Uint8Array(event.data),16*1024*1024);if(data)await this.receive(decode(data),candidate.pk);
        }).catch(error=>this.fail(error));
      };
      candidate.dc.onclose=()=>{if(epoch===this.transportEpoch)void this.transportLost('Прямой канал прерван');};
      candidate.pc.onconnectionstatechange=()=>{if(epoch===this.transportEpoch&&['failed','closed','disconnected'].includes(candidate.pc.connectionState))void this.transportLost('Прямой канал прерван');};
      old?.close();await this.inputQueue;await this.send({misc:{videoReceived:true}});await this.send({misc:{refreshVideo:true}});await this.reportTransport(candidate.pc);
    }catch(error){this.emit('warning','Не удалось перейти на P2P. '+String(error));}
    finally{this.directChecking=false;}
  }
  private send(message:Wire,handshake=false,privileged=false,epoch=this.controlEpoch): Promise<void> {
    const transportEpoch=this.transportEpoch;
    if (!handshake && !this.active) return Promise.reject(new Error('Сначала требуется разрешить доступ'));
    const task = async () => {
      if(transportEpoch!==this.transportEpoch)throw new Error('Канал был заменён; прежние команды отброшены');
      if(!handshake&&!this.active)throw new Error('Сеанс завершён');
      if(privileged&&(!this.controls||epoch!==this.controlEpoch))throw new Error('Управление было передано другому участнику');
      const dc = this.dc; if (dc?.readyState !== 'open') throw new Error('Канал закрыт');
      for (const frame of Framing.encode(encode(message))) {
        const start=performance.now();
        while(dc.bufferedAmount > 1024*1024) {
          if (dc.readyState !== 'open' || performance.now()-start > 15000) throw new Error('Канал не успевает передавать данные');
          await new Promise(resolve=>setTimeout(resolve,10));
        }
        dc.send(frame);
      }
    };
    const result=this.outputQueue.then(task); this.outputQueue=result.catch(()=>{}); return result;
  }
  async command(message:Wire): Promise<void> { if (!this.controls) throw new Error('Сейчас у вас режим наблюдения'); await this.send(message,false,true); }
  async chat(text:string): Promise<void> { if(text.length>10000) throw new Error('Слишком длинное сообщение'); await this.send({misc:{chatMessage:{text}}}); }
  async control(action:'query'|'claim'|'release'|'transfer',target=0): Promise<void> { await this.send({ryadomControl:{version:1,action,target}}); }
  async monitor(index:number): Promise<void> {this.selectedMonitor=index;await this.send({misc:{switchDisplay:{display:index}}}); }
  async quality(quality:number,fps:number): Promise<void> {
    const interrupted=this.codecRunning;++this.codecEpoch;this.codecRunning=false;
    await this.command({misc:{option:{imageQuality:quality,customFps:Math.min(60,Math.max(5,fps))}}});
    if(interrupted){await this.applyCodec(this.preferredCodec);this.emit('codecTest',{status:'Качество изменилось; повторите проверку кодеков.',results:[]});}
  }
  async setCodec(codec:string):Promise<void> {
    if(codec==='auto'){this.codecAutomatic=true;await this.testCodecs();return;}
    if(!(await this.availableCodecs()).includes(codec))throw new Error('Этот кодек не поддерживается в данном соединении');
    this.codecAutomatic=false;++this.codecEpoch;this.codecRunning=false;this.preferredCodec=codec;
    await this.applyCodec(codec);this.emit('codecTest',{status:'Ручной кодек: '+codec.toUpperCase(),results:[]});
  }
  async availableCodecs():Promise<string[]> {
    const candidates=['vp9',...(this.peerEncoding.vp8?['vp8']:[]),...(this.peerEncoding.av1?['av1']:[])];
    const codecs:Record<string,string>={vp8:'vp8',vp9:'vp09.00.10.08',av1:'av01.0.04M.08'};
    const available=[];
    for(const name of candidates){if((await VideoDecoder.isConfigSupported({codec:codecs[name]!})).supported)available.push(name);}
    return available;
  }
  private async applyCodec(codec:string):Promise<void> {
    const prefer:Record<string,number>={vp8:4,vp9:1,av1:5};
    await this.command({misc:{option:{supportedDecoding:{abilityVp8:1,abilityVp9:1,abilityAv1:codec==='av1'?1:0,prefer:prefer[codec]}}}});
  }
  async testCodecs():Promise<void> {
    if(this.codecRunning||!this.controls)return;
    const epoch=++this.codecEpoch,before=this.preferredCodec,results:CodecMeasurement[]=[];
    const valid=()=>this.active&&this.controls&&epoch===this.codecEpoch;
    this.codecRunning=true;
    let selected=false;
    try{
      const resolution=`${this.media.canvas.width}x${this.media.canvas.height}`;
      const candidates=(await this.availableCodecs()).sort((a,b)=>a==='vp8'?-1:b==='vp8'?1:0);
      for(const codec of candidates){
        if(!valid())return;
        this.emit('codecTest',{status:'Проверка '+codec.toUpperCase()+'… Прокрутите документ или перемещайте окно.',results});
        await this.applyCodec(codec);await new Promise(resolve=>setTimeout(resolve,1500));
        if(!valid())return;
        const samples:CodecMeasurement[]=[];
        for(let i=0;i<3&&valid();i++){
          const frames=this.media.decoded,bytes=this.media.receivedVideoBytes,decode=this.media.decodeMillis,start=performance.now();
          await new Promise(resolve=>setTimeout(resolve,1000));
          if(!valid())return;
          if(resolution!==`${this.media.canvas.width}x${this.media.canvas.height}`)throw new Error('Разрешение изменилось; повторите проверку');
          if(this.media.activeCodec!==codec)continue;
          const seconds=(performance.now()-start)/1000,count=this.media.decoded-frames;
          if(count/seconds<3)continue;
          let rtt=0;const stats=await this.pc!.getStats();
          stats.forEach((row:any)=>{if(row.type==='candidate-pair'&&row.state==='succeeded'&&row.nominated)rtt=Math.max(rtt,Number(row.currentRoundTripTime??0)*1000);});
          samples.push({codec,fps:count/seconds,delayMs:rtt+(this.media.decodeMillis-decode)/count,bytesPerSecond:(this.media.receivedVideoBytes-bytes)/seconds});
        }
        if(samples.length>=2){const mean=(key:'fps'|'delayMs'|'bytesPerSecond')=>samples.reduce((sum,sample)=>sum+sample[key],0)/samples.length;
          results.push({codec,fps:mean('fps'),delayMs:mean('delayMs'),bytesPerSecond:mean('bytesPerSecond')});}
      }
      if(!valid())return;
      const best=chooseMeasuredCodec(results);this.preferredCodec=best?.codec??before;
      await this.applyCodec(this.preferredCodec);selected=true;
      this.emit('codecTest',{status:best?'Авто: '+best.codec.toUpperCase()+' · '+best.fps.toFixed(0)+' кадр/с':'Недостаточно изменений изображения для сравнения. Сохранён прежний кодек.',results});
    }catch(error){if(valid())this.emit('codecTest',{status:'Проверка не завершена: '+String(error),results});}
    finally{if(epoch===this.codecEpoch){if(!selected&&valid())await this.applyCodec(before).catch(error=>this.emit('warning',String(error)));this.codecRunning=false;}}
  }
  async paste(text:string,insert=false): Promise<void> {
    if (!this.clipboardAllowed) throw new Error('Разрешите буфер обмена');
    await this.command({clipboard:{content:new TextEncoder().encode(text),format:0}});
    if(insert){await this.command({keyEvent:{chr:118,down:true,modifiers:[4],mode:0}});await this.command({keyEvent:{chr:118,down:false,modifiers:[],mode:0}});}
  }
  async terminalOpen(): Promise<void> { await this.command({terminalAction:{open:{terminalId:1,rows:30,cols:100}}}); }
  async terminalWrite(text:string): Promise<void> { await this.command({terminalAction:{data:{terminalId:1,data:new TextEncoder().encode(text)}}}); }
  async terminalClose(): Promise<void> { await this.command({terminalAction:{close:{terminalId:1}}}); }
  async reboot(): Promise<void> { await this.command({misc:{restartRemoteDevice:true}}); }
  async directory(path:string): Promise<void> { await this.command({fileAction:{readDir:{path,includeHidden:false}}}); }
  async rename(path:string,newName:string): Promise<void> { await this.fileOperation('rename',{path,newName}); }
  async createDirectory(path:string): Promise<void> { await this.fileOperation('create',{path}); }
  async remove(path:string,directory:boolean): Promise<void> {
    await this.fileOperation(directory?'removeDir':'removeFile',{path,recursive:directory,fileNum:0});
  }
  private async fileOperation(action:string,value:Wire):Promise<void> {
    const id=this.nextFileId++;
    const done=new Promise<void>((resolve,reject)=>this.fileOperations.set(id,{resolve,reject}));
    try {await Promise.all([this.command({fileAction:{[action]:{...value,id}}}),done]);}
    finally{this.fileOperations.delete(id);}
  }
  async upload(file:File,directory:string): Promise<void> {
    if(!directory.trim())throw new Error('Сначала откройте папку назначения');
    const id=this.nextFileId++;
    const done=new Promise<void>((resolve,reject)=>this.uploads.set(id,{file,directory,resuming:false,sent:0,resolve,reject}));
    await this.beginUpload(id);
    return done;
  }
  private async beginUpload(id:number):Promise<void>{
    const job=this.uploads.get(id);if(!job)return;const file=job.file;
    await this.command({fileAction:{receive:{id,path:job.directory,files:[{entryType:4,name:file.name,size:String(file.size),modifiedTime:String(Math.floor(file.lastModified/1000))}],fileNum:0,totalSize:String(file.size)}}});
    await this.command({fileResponse:{digest:{id,fileNum:0,fileSize:String(file.size),lastModified:String(Math.floor(file.lastModified/1000)),isUpload:true,isResume:job.resuming}}});
  }
  private async resumeFiles():Promise<void>{
    this.filesPending=false;
    for(const id of this.uploads.keys())await this.beginUpload(id);
    for(const [id,job] of this.downloads){await job.write;await this.command({fileAction:{send:{id,path:job.path,fileNum:0,includeHidden:false}}});}
  }
  async confirmUpload(id:number,action:'skip'|'replace'|'resume',offset=0): Promise<void> {
    const job=this.uploads.get(id); if(!job) throw new Error('Передача не найдена');
    if(action==='resume'&&(!Number.isInteger(offset)||offset<0||offset>0xffffffff||offset>job.file.size))throw new Error('Продолжение с этого смещения пока недоступно. Выберите замену файла.');
    if (action==='skip') { await this.command({fileAction:{sendConfirm:{id,fileNum:0,skip:true}}}); job.resolve(); this.uploads.delete(id); return; }
    await this.command({fileAction:{sendConfirm:{id,fileNum:0,offsetBlk:action==='resume'?offset:0}}});
    await this.transmitUpload(id,action==='resume'?offset:0);
  }
  private async transmitUpload(id:number,offset:number): Promise<void> {
    const job=this.uploads.get(id);if(!job)throw new Error('Передача не найдена');
    const epoch=this.transportEpoch;
    // RustDesk's current offset_blk is a byte offset despite the historic field name.
    for(let at=offset;at<job.file.size;at+=128*1024) {
      const data=new Uint8Array(await job.file.slice(at,at+128*1024).arrayBuffer());
      if(epoch!==this.transportEpoch||!this.active)return;
      await this.command({fileResponse:{block:{id,fileNum:0,data,compressed:false}}}); job.sent=at+data.length; this.emit('progress',{id,sent:job.sent,size:job.file.size});
    }
    if(epoch===this.transportEpoch)await this.command({fileResponse:{done:{id,fileNum:0}}});
  }
  async download(path:string,name:string,size:number): Promise<void> {
    const picker=(window as any).showSaveFilePicker;if(!picker)throw new Error('Для сохранения больших файлов нужен актуальный Edge или Chrome');
    const handle=await picker({suggestedName:name});const sink=await handle.createWritable();const id=this.nextFileId++;
    this.downloads.set(id,{sink,path,received:0,size,write:Promise.resolve()});
    try { await this.command({fileAction:{send:{id,path,fileNum:0,includeHidden:false}}}); }
    catch(error){this.downloads.delete(id);await sink.abort();throw error;}
  }
  private async fileResponse(response:Wire): Promise<void> {
    if(response.dir) this.emit('directory',response.dir);
    if(response.digest) {
      const digest=response.digest;
      const download=this.downloads.get(digest.id),upload=this.uploads.get(digest.id);
      if(download){
        const modified=String(digest.lastModified??'0');
        if(Number(digest.fileSize)!==download.size||(download.modified!==undefined&&download.modified!==modified)||download.received>0xffffffff)throw new Error('Исходный файл изменился или смещение недоступно. Повторите загрузку.');
        download.modified=modified;await download.write;
        await this.command({fileAction:{sendConfirm:{id:digest.id,fileNum:digest.fileNum??0,offsetBlk:download.received}}});
      }else if(upload?.resuming&&digest.isIdentical&&Number(digest.transferredSize??0)<=upload.file.size&&Number(digest.transferredSize??0)<=0xffffffff){
        upload.resuming=false;void this.confirmUpload(digest.id,'resume',Number(digest.transferredSize??0)).catch(error=>this.emit('error',String(error)));
      }else this.emit('overwrite',digest);
    }
    if(response.error) {
      this.fileOperations.get(response.error.id)?.reject(new Error(response.error.error));this.fileOperations.delete(response.error.id);
      this.uploads.get(response.error.id)?.reject(new Error(response.error.error));this.uploads.delete(response.error.id);
      const job=this.downloads.get(response.error.id);if(job){await job.sink.abort();this.downloads.delete(response.error.id);}
      this.emit('error',response.error.error);
    }
    if(response.done) {
      const operation=this.fileOperations.get(response.done.id);
      if(operation){this.fileOperations.delete(response.done.id);operation.resolve();return;}
      const job=this.downloads.get(response.done.id);
      if(job){if(job.received!==job.size)throw new Error('Получен неполный файл');await job.sink.close();this.downloads.delete(response.done.id);}
      this.uploads.get(response.done.id)?.resolve(); this.uploads.delete(response.done.id); this.emit('fileDone',response.done);
    }
    if(response.block) {
      const block=response.block; const job=this.downloads.get(block.id); if(!job) throw new Error('Неожиданные данные файла');
      const bytes=block.compressed?decompress(block.data):block.data;
      if(job.received+bytes.length>job.size) throw new Error('Превышен размер файла');
      job.write=job.sink.write(bytes).then(()=>{job.received+=bytes.length;});
      await job.write; this.emit('progress',{id:block.id,sent:job.received,size:job.size});
    }
  }
  private bindInput(): void {
    const canvas=this.media.canvas;
    const modifiers=(e:MouseEvent|KeyboardEvent)=>[e.altKey?1:0,e.ctrlKey?4:0,e.metaKey?23:0,e.shiftKey?29:0].filter(Boolean);
    const mouse=(e:MouseEvent,type:number)=>{
      if(!this.active)return; e.preventDefault();
      const rect=canvas.getBoundingClientRect(); const scale=Math.min(rect.width/canvas.width,rect.height/canvas.height);
      const x=Math.round((e.clientX-rect.left-(rect.width-canvas.width*scale)/2)/scale);
      const y=Math.round((e.clientY-rect.top-(rect.height-canvas.height*scale)/2)/scale);
      if(type===0 && (x<0 || y<0 || x>=canvas.width || y>=canvas.height))return;
      const button=({0:1,1:4,2:2} as Record<number,number>)[e.button]??0;
      if(!this.controls){
        if(type===0||(type===2&&button===1))void this.send({mouseEvent:{mask:type===0?0:10,x:x+(this.display.x??0),y:y+(this.display.y??0)}}).catch(error=>this.emit('error',String(error)));
        return;
      }
      this.media.hideRemoteCursor();
      if(type===1)this.buttons.add(button);if(type===2)this.buttons.delete(button);
      void this.command({mouseEvent:{mask:type|(type?button<<3:0),x:x+(this.display.x??0),y:y+(this.display.y??0),modifiers:modifiers(e)}}).catch(error=>this.fail(error));
    };
    canvas.onpointerdown=e=>{canvas.focus();if(this.controls)canvas.setPointerCapture(e.pointerId);mouse(e,1);};canvas.onpointerup=e=>mouse(e,2);canvas.onpointermove=e=>mouse(e,0);
    canvas.oncontextmenu=e=>e.preventDefault();
    canvas.onwheel=e=>{if(this.controls){e.preventDefault();void this.command({mouseEvent:{mask:3,x:0,y:e.deltaY>0?-3:3,modifiers:modifiers(e)}}).catch(error=>this.fail(error));}};
    const key=(e:KeyboardEvent,down:boolean)=>{
      if(!this.controls)return;
      if(down&&this.clipboardAllowed&&e.ctrlKey&&!e.altKey&&e.code==='KeyV')return;
      e.preventDefault();
      if(down){const message=keyEvent(e);if(!message)return;if(!message.press)this.keys.set(e.code,message);void this.command({keyEvent:message}).catch(error=>this.emit('error',String(error)));}
      else {const message=this.keys.get(e.code);if(message)void this.command({keyEvent:{...message,down:false,modifiers:modifiers(e)}}).catch(error=>this.emit('error',String(error)));this.keys.delete(e.code);}
    };
    canvas.onkeydown=e=>key(e,true);canvas.onkeyup=e=>key(e,false);canvas.onblur=()=>this.releaseLocalInput();
    canvas.onpaste=event=>{
      if(!this.controls||!this.clipboardAllowed)return;
      event.preventDefault();
      if(!event.clipboardData?.types.includes('text/plain')){this.emit('warning','Передавайте файлы через файловый менеджер.');return;}
      void this.paste(event.clipboardData.getData('text/plain'),true).catch(error=>this.emit('error',String(error)));
    };
  }
  private releaseLocalInput(): void {
    if(this.controls){for(const message of this.keys.values())void this.command({keyEvent:{...message,down:false,modifiers:[]}}).catch(()=>{});for(const button of this.buttons)void this.command({mouseEvent:{mask:2|(button<<3)}}).catch(()=>{});}
    this.keys.clear();this.buttons.clear();
  }
  private fail(error:unknown): void { this.rejectIdentity?.(error);this.rejectAccess?.(error);this.emit('error',String(error));if(this.dc?.readyState!=='open'&&this.resumeToken.length===32)void this.transportLost(String(error));else void this.close(String(error)); }
  private async transportLost(reason:string):Promise<void>{
    if(this.closing)return;
    this.rejectIdentity?.(new Error(reason));this.rejectAccess?.(new Error(reason));
    if(this.recovering){++this.transportEpoch;this.dc?.close();this.pc?.close();return;}
    if(this.resumeToken.length!==32){await this.close(reason);return;}
    this.recovering=true;this.resumeDeadline ||= Date.now()+300000;
    const expiry=setTimeout(()=>{void this.close('Не удалось восстановить связь за 5 минут. Подключитесь заново.');},Math.max(0,this.resumeDeadline-Date.now()));
    this.phase='recovering';++this.transportEpoch;++this.controlEpoch;++this.codecEpoch;
    this.clearProbes();this.codecRunning=false;this.codecTestStarted=false;
    this.filesPending=true;for(const job of this.uploads.values())job.resuming=true;
    for(const operation of this.fileOperations.values())operation.reject(new Error('Связь прервалась; команду нужно повторить явно'));this.fileOperations.clear();
    this.keys.clear();this.buttons.clear();this.media.hideRemoteCursor();
    this.dc?.close();this.pc?.close();
    await this.media.suspendRecording().catch(()=>{});
    let delay=1000;
    try{
      while(!this.closing&&Date.now()<this.resumeDeadline){
        this.emit('recovering',{remaining:Math.ceil((this.resumeDeadline-Date.now())/1000)});
        this.emit('status','Связь потеряна, восстанавливаем…');
        await new Promise(resolve=>setTimeout(resolve,delay));if(this.closing)return;
        try{await this.establish('',false);return;}catch{++this.transportEpoch;this.dc?.close();this.pc?.close();this.phase='recovering';}
        delay=Math.min(delay*2,15000);
      }
      if(!this.closing)await this.close('Не удалось восстановить связь за 5 минут. Подключитесь заново.');
    }finally{clearTimeout(expiry);this.recovering=false;}
  }
  async close(reason='Сеанс завершён'): Promise<void> {
    ++this.codecEpoch;
    if(this.closing)return;this.closing=true;clearTimeout(this.lostTimer);
    this.clearProbes();window.removeEventListener('online',this.networkChanged);
    (navigator as any).connection?.removeEventListener('change',this.networkChanged);
    if(this.active&&this.dc?.readyState==='open')await this.send({misc:{closeReason:'Ryadom session ended'}}).catch(()=>{});
    this.resumeToken=new Uint8Array();++this.transportEpoch;this.abort.abort();this.releaseLocalInput();this.phase='closed';this.password='';
    this.rejectIdentity?.(new Error(reason));this.rejectAccess?.(new Error(reason));this.dc?.close();this.pc?.close();
    for(const job of this.uploads.values())job.reject(new Error(reason));this.uploads.clear();
    for(const operation of this.fileOperations.values())operation.reject(new Error(reason));this.fileOperations.clear();
    for(const job of this.downloads.values())await job.sink.abort();this.downloads.clear();
    try {await this.media.close();}catch(error){this.emit('error',String(error));}
    finally{this.terminalResize?.disconnect();this.terminal?.dispose();this.emit('closed',reason);}
  }
}
