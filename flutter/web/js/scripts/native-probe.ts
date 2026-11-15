import { Session } from '../src/session';

export async function run(peer:string,turnServers?:RTCIceServer[],identityOnly=false):Promise<unknown> {
  const session=new Session(peer,turnServers);
  const events:unknown[]=[];
  let pair:unknown,peerInfo:any;
  for(const name of ['status','error','password','control','closed'])session.addEventListener(name,event=>{
    events.push({time:new Date().toISOString(),name,value:(event as CustomEvent).detail});
  });
  session.addEventListener('transport',event=>{pair=(event as CustomEvent).detail;});
  session.addEventListener('connected',event=>{peerInfo=(event as CustomEvent).detail;});
  try{
    const identity=identityOnly?new Promise<void>((resolve,reject)=>{
      session.addEventListener('transport',()=>resolve(),{once:true});
      session.addEventListener('error',event=>reject(new Error(String((event as CustomEvent).detail))),{once:true});
    }):undefined;
    const connection=session.connect();
    if(identityOnly){
      void connection.catch(()=>{});
      await identity;
      return {host:'actual Windows Rust host from Ryadom.exe',hostIdentityVerified:true,authorized:false,
        pair,scope:'one physical PC; signed host identity and DTLS verified before desktop permission; no capture, input or files'};
    }
    await connection;
    const started=performance.now();
    while(!session.media.decoded){
      if(!session.active||performance.now()-started>30000)throw new Error('Не получен кадр Windows');
      await new Promise(resolve=>setTimeout(resolve,100));
    }
    return {host:'actual Windows Rust host from Ryadom.exe',authorized:true,controls:session.controls,
      pair,decoded:session.media.decoded,width:session.media.canvas.width,height:session.media.canvas.height,
      platform:peerInfo?.platform,version:peerInfo?.version,events,
      scope:'one physical PC; owner confirmation; no files, input, terminal or recording in this probe'};
  }catch(error){throw new Error(String(error)+'; events='+JSON.stringify(events));}
  finally{await session.close('Локальная проверка завершена');}
}
