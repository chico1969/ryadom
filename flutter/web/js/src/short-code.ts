import nacl from 'tweetnacl';
import { deviceId, unhex, validId } from './security';
import { PeerSignal, Signal } from './signaling';

export async function verifyCodeReply(reply:any,code:string,nonce:string,client:string):Promise<string> {
  if(reply?.ryadomLookup!==1||reply.code!==code||reply.nonce!==nonce||!validId(reply.id))throw new Error('Ответ не соответствует короткому ID');
  const pk=unhex(reply.publicKey??''),signature=unhex(reply.signature??'');
  if(await deviceId(pk)!==reply.id||!nacl.sign.detached.verify(new TextEncoder().encode(`RyadomCodeV1|${code}|${nonce}|${client}|${reply.id}`),signature,pk))throw new Error('Подпись короткого ID не прошла проверку');
  return reply.id;
}
export async function resolvePeer(input:string):Promise<string> {
  const code=input.replace(/\s/g,'').toLowerCase();
  if(validId(code))return code;
  if(!/^[1-9][0-9]{8}$/.test(code))throw new Error('Введите 9 цифр ID компьютера');
  const signal=new PeerSignal();
  const nonce=crypto.randomUUID().replaceAll('-',''),connectionId='lookup_'+nonce;
  try {
    await signal.open();
    return await new Promise<string>((resolve,reject)=>{
      let checking=false;
      const cleanup=()=>{clearTimeout(timer);signal.removeEventListener('signal',message);signal.removeEventListener('offline',offline);};
      const fail=(error:unknown)=>{cleanup();reject(error);};
      const offline=()=>fail(new Error('Служба поиска отключилась'));
      const timer=setTimeout(()=>fail(new Error('Компьютер с этим ID не найден или не запущен')),15000);
      const message=(event:Event)=>{
        const msg=(event as CustomEvent<Signal>).detail;
        if(['ERROR','EXPIRE','ID-TAKEN'].includes(msg.type)){fail(new Error('Компьютер с этим ID недоступен'));return;}
        if(checking||msg.type!=='ANSWER'||msg.src!=='ryadom-code-'+code||msg.payload?.connectionId!==connectionId)return;
        checking=true;
        void verifyCodeReply(msg.payload.metadata,code,nonce,signal.id).then(id=>{cleanup();resolve(id);}).catch(fail);
      };
      signal.addEventListener('signal',message);signal.addEventListener('offline',offline);
      signal.send({type:'OFFER',dst:'ryadom-code-'+code,payload:{type:'data',connectionId,label:'bootstrap',serialization:'raw',reliable:true,sdp:{type:'offer',sdp:'v=0\r\n'},metadata:{ryadomLookup:1,nonce}}});
    });
  } finally {signal.close();}
}
