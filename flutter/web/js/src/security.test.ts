import nacl from 'tweetnacl';
import { webcrypto } from 'node:crypto';
import { deviceId, directSdp, fingerprint, Framing, MAX_MESSAGE, passwordResponse, validId, verifyIdentity, exchangeKey } from './security';
Object.defineProperty(globalThis,'crypto',{value:webcrypto});

test('ID binds the full host public key, rejects foreign IDs',async()=>{
  const a=nacl.sign.keyPair(),b=nacl.sign.keyPair();
  expect(validId(await deviceId(a.publicKey))).toBe(true);
  expect(await deviceId(a.publicKey)).not.toBe(await deviceId(b.publicKey));
  expect(validId('123456789')).toBe(false);
  const payload=new TextEncoder().encode('ryadom identity / certificate');
  const signed=nacl.sign(payload,a.secretKey);
  expect(verifyIdentity(signed,a.publicKey)).toEqual(payload);
  expect(()=>verifyIdentity(signed,b.publicKey)).toThrow();
  signed[70]=signed[70]!^1;expect(()=>verifyIdentity(signed,a.publicKey)).toThrow();
});
test('key exchange is compatible with the core NaCl box handshake',()=>{
  const host=nacl.box.keyPair();const response=exchangeKey(host.publicKey);
  const key=nacl.box.open(response.symmetricValue,new Uint8Array(24),response.asymmetricValue,host.secretKey);
  expect(key).toHaveLength(32);
});
test('password response is salted and bound to a fresh challenge',async()=>{
  expect(await passwordResponse('пароль','salt','1')).not.toEqual(await passwordResponse('пароль','salt','2'));
  expect(await passwordResponse('пароль','salt','1')).not.toEqual(await passwordResponse('другой','salt','1'));
  expect(Buffer.from(await passwordResponse('password','salt','challenge')).toString('hex')).toBe('1ea65d82db76c42e7f674ee7f2c5df1626c8fc80b0d8f18fa61a07b083c16197');
});
test.each([0,1,16383,16384,1000000])('framing interoperates at %i bytes',length=>{
  const bytes=Uint8Array.from({length},(_,i)=>i%251);const reader=new Framing();
  let decoded:Uint8Array|undefined;
  for(const frame of Framing.encode(bytes))decoded=reader.accept(frame);
  expect(Buffer.from(decoded!)).toEqual(Buffer.from(bytes));
});
test('malformed and overlarge frames fail closed',()=>{
  for(const bytes of [new Uint8Array(),new Uint8Array([1]),new Uint8Array([2,42])])expect(()=>new Framing().accept(bytes)).toThrow();
  expect(()=>[...Framing.encode(new Uint8Array(MAX_MESSAGE+1))]).toThrow();
  const reader=new Framing();expect(()=>{for(const frame of Framing.encode(new Uint8Array(70000)))reader.accept(frame,65536);}).toThrow();
});
test('relay candidates in SDP are rejected; DTLS fingerprint includes algorithm',()=>{
  const sdp='v=0\r\na=fingerprint:sha-256 AB:CD\r\na=candidate:1 1 udp 1 10.0.0.1 1234 typ host\r\n';
  expect(()=>directSdp({type:'offer',sdp})).not.toThrow();
  expect(fingerprint(sdp)).toBe('sha-256 AB:CD');
  expect(()=>directSdp({type:'answer',sdp:sdp.replace('typ host','typ relay')})).toThrow();
});
