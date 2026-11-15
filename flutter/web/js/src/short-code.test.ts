import nacl from 'tweetnacl';
import { webcrypto } from 'node:crypto';
import { deviceId, hex } from './security';
import { verifyCodeReply } from './short-code';
Object.defineProperty(globalThis,'crypto',{value:webcrypto,configurable:true});

test('short ID resolution preserves the cryptographic address and rejects changed context',async()=>{
  const pair=nacl.sign.keyPair(),id=await deviceId(pair.publicKey);
  const code='123456789',nonce='0'.repeat(32),client='ryadom-client-test';
  const text=`RyadomCodeV1|${code}|${nonce}|${client}|${id}`;
  const reply={ryadomLookup:1,code,nonce,id,publicKey:hex(pair.publicKey),signature:hex(nacl.sign.detached(new TextEncoder().encode(text),pair.secretKey))};
  await expect(verifyCodeReply(reply,code,nonce,client)).resolves.toBe(id);
  await expect(verifyCodeReply(reply,'123456788',nonce,client)).rejects.toThrow();
  await expect(verifyCodeReply(reply,code,'1'.repeat(32),client)).rejects.toThrow();
  await expect(verifyCodeReply(reply,code,nonce,'another-client')).rejects.toThrow();
});
