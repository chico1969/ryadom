import { Wire } from './protocol';

export class Media {
  readonly canvas = document.createElement('canvas');
  private readonly remoteCursor = document.createElement('div');
  private cursorPosition?: {x:number;y:number};
  private cursorIdle?: ReturnType<typeof setTimeout>;
  private video?: VideoDecoder;
  private audio?: AudioDecoder;
  private audioContext?: AudioContext;
  private nextAudio = 0;
  private recorder?: MediaRecorder;
  private recordingDirectory?:FileSystemDirectoryHandle;
  private recordingRequested=false;
  private sink?: FileSystemWritableFileStream;
  private writes: Promise<void> = Promise.resolve();
  private destination?: MediaStreamAudioDestinationNode;
  private disposed = false;
  frames = 0;
  decoded = 0;
  receivedVideoBytes=0;
  decodeMillis=0;
  private decodeStarts:number[]=[];
  get activeCodec():string {return this.codec.startsWith('vp09')?'vp9':this.codec.startsWith('av01')?'av1':this.codec;}
  private codec = '';
  onError: (error:unknown)=>void = () => {};
  onFrame: ()=>void = () => {};
  constructor() {
    this.canvas.tabIndex = 0; this.canvas.style.cssText='width:100%;height:100%;object-fit:contain;display:block;background:#111827;outline:none;';
    this.remoteCursor.style.cssText='position:absolute;pointer-events:none;display:none;width:22px;height:30px;z-index:2;';
    this.remoteCursor.innerHTML='<svg width="22" height="30" viewBox="0 0 22 30"><path d="M1 1V25L7 20L12 29L16 27L11 18H21Z" fill="#ff8a1c" stroke="white" stroke-width="1.5"/></svg>';
  }
  mount(element: HTMLElement): void { element.style.position='relative';element.style.overflow='hidden';element.replaceChildren(this.canvas,this.remoteCursor); }
  showRemoteCursor(x:number,y:number):void {
    if(this.disposed)return;
    if(this.cursorPosition?.x!==x||this.cursorPosition?.y!==y){
      clearTimeout(this.cursorIdle);
      this.cursorIdle=setTimeout(()=>this.hideRemoteCursor(),5000);
    }
    this.cursorPosition={x,y};this.updateRemoteCursor();
  }
  hideRemoteCursor():void {clearTimeout(this.cursorIdle);this.cursorIdle=undefined;this.cursorPosition=undefined;this.remoteCursor.style.display='none';}
  private updateRemoteCursor():void {
    const pos=this.cursorPosition,rect=this.canvas.getBoundingClientRect();
    if(!pos||!rect.width||!rect.height||!Number.isFinite(pos.x)||!Number.isFinite(pos.y)||pos.x<0||pos.y<0||pos.x>=this.canvas.width||pos.y>=this.canvas.height){this.remoteCursor.style.display='none';return;}
    const scale=Math.min(rect.width/this.canvas.width,rect.height/this.canvas.height);
    this.remoteCursor.style.left=((rect.width-this.canvas.width*scale)/2+pos.x*scale)+'px';
    this.remoteCursor.style.top=((rect.height-this.canvas.height*scale)/2+pos.y*scale)+'px';
    this.remoteCursor.style.display='block';
  }
  videoFrame(video: Wire): void {
    const group = video.vp9s ?? video.vp8s ?? video.av1s;
    if (!group) { this.onError(new Error('Неподдерживаемый видеокодек')); return; }
    const codec = video.vp9s ? 'vp09.00.10.08' : video.vp8s ? 'vp8' : 'av01.0.04M.08';
    if (this.codec !== codec) {
      this.video?.close(); this.codec = codec;this.decodeStarts=[];
      this.video = new VideoDecoder({
        output:frame => {
          try {
            if (this.disposed) return;
            const started=this.decodeStarts.shift();if(started!==undefined)this.decodeMillis+=performance.now()-started;
            if (this.canvas.width !== frame.displayWidth) this.canvas.width = frame.displayWidth;
            if (this.canvas.height !== frame.displayHeight) this.canvas.height = frame.displayHeight;
            this.canvas.getContext('2d',{alpha:false})?.drawImage(frame,0,0); this.decoded++; this.updateRemoteCursor();this.onFrame();
          } finally { frame.close(); }
        }, error:error => this.onError(error)
      });
      this.video.configure({codec,optimizeForLatency:true,hardwareAcceleration:'no-preference'});
    }
    for (const frame of group.frames ?? []) {
      this.frames++;
      this.receivedVideoBytes+=frame.data.byteLength;
      if (!this.video || this.video.state !== 'configured') return;
      // Delta frames cannot be discarded without resetting the decoder at a key frame.
      if (this.video.decodeQueueSize > 60) { this.onError(new Error('Декодер не успевает. Уменьшите качество.')); return; }
      this.decodeStarts.push(performance.now());
      this.video.decode(new EncodedVideoChunk({type:frame.key?'key':'delta',timestamp:Number(frame.pts??0)*1000,data:frame.data}));
    }
  }
  async enableAudio(): Promise<void> {
    this.audioContext ??= new AudioContext(); await this.audioContext.resume();
  }
  audioFormat(format:Wire): void {
    this.audio?.close();
    this.audioContext ??= new AudioContext();
    this.audio = new AudioDecoder({output: data => {
      try {
        if (!this.audioContext || this.audioContext.state !== 'running') return;
        const buffer = this.audioContext.createBuffer(data.numberOfChannels,data.numberOfFrames,data.sampleRate);
        for (let planeIndex=0; planeIndex<data.numberOfChannels; planeIndex++) data.copyTo(buffer.getChannelData(planeIndex),{planeIndex,format:'f32-planar'});
        const node = this.audioContext.createBufferSource(); node.buffer = buffer; node.connect(this.audioContext.destination);
        if (this.destination) node.connect(this.destination);
        this.nextAudio = Math.max(this.audioContext.currentTime+0.02,this.nextAudio);
        if (this.nextAudio > this.audioContext.currentTime+0.5) this.nextAudio = this.audioContext.currentTime+0.02;
        node.start(this.nextAudio); this.nextAudio += buffer.duration;
      } finally { data.close(); }
    },error:error=>this.onError(error)});
    this.audio.configure({codec:'opus',sampleRate:format.sampleRate,numberOfChannels:format.channels});
  }
  audioFrame(frame:Wire): void {
    if (this.audio?.state === 'configured' && this.audio.decodeQueueSize < 60) this.audio.decode(new EncodedAudioChunk({type:'key',timestamp:0,data:frame.data}));
  }
  async startRecording(): Promise<void> {
    if (this.recorder) throw new Error('Запись уже идёт');
    const picker = (window as any).showDirectoryPicker;
    if (!picker) throw new Error('Для потоковой записи нужен актуальный Edge или Chrome');
    this.recordingDirectory=await picker({mode:'readwrite'});this.recordingRequested=true;
    await this.resumeRecording();
  }
  async resumeRecording():Promise<void>{
    if(!this.recordingRequested||!this.recordingDirectory||this.recorder)return;
    const handle=await this.recordingDirectory.getFileHandle(`Рядом-${new Date().toISOString().replace(/[:.]/g,'-')}.webm`,{create:true});
    this.sink = await handle.createWritable();
    const stream = this.canvas.captureStream(30);
    if (this.audioContext) { this.destination = this.audioContext.createMediaStreamDestination(); for (const track of this.destination.stream.getAudioTracks()) stream.addTrack(track); }
    const mimeType = ['video/webm;codecs=vp9,opus','video/webm;codecs=vp8,opus','video/webm'].find(x=>MediaRecorder.isTypeSupported(x));
    if (!mimeType) throw new Error('Запись WebM не поддерживается');
    const recorder = this.recorder = new MediaRecorder(stream,{mimeType});
    recorder.ondataavailable = event => {
      if (event.data.size) this.writes = this.writes.then(async () => { await this.sink?.write(event.data); }).catch(error => { this.onError(error); if (recorder.state !== 'inactive') recorder.stop(); });
    };
    recorder.onerror = event => this.onError(event);
    recorder.start(1000);
  }
  async suspendRecording():Promise<void>{await this.finishRecording();}
  async stopRecording(): Promise<void> {this.recordingRequested=false;this.recordingDirectory=undefined;await this.finishRecording();}
  private async finishRecording(): Promise<void> {
    const recorder = this.recorder; if (!recorder) return;
    if (recorder.state !== 'inactive') await new Promise<void>(resolve=>{ recorder.onstop = () => resolve(); recorder.stop(); });
    try { await this.writes; await this.sink?.close(); }
    finally {
      for (const track of recorder.stream.getTracks()) track.stop();
      this.destination?.disconnect(); this.destination = undefined; this.recorder = undefined; this.sink = undefined;
    }
  }
  async close(): Promise<void> { this.disposed = true;this.hideRemoteCursor();try{await this.stopRecording();}finally{this.video?.close();this.audio?.close();await this.audioContext?.close();} }
}
