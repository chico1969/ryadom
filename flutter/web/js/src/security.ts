import nacl from 'tweetnacl';

export const PROTOCOL_VERSION = 1;
export const MAX_MESSAGE = 16 * 1024 * 1024;
export function validId(id: string): boolean { return /^ryadom-[0-9a-f]{32}$/.test(id); }
export async function deviceId(pk: Uint8Array): Promise<string> {
  if (pk.length !== 32) throw new Error('Неверная длина ключа компьютера');
  const hash = new Uint8Array(await crypto.subtle.digest('SHA-256', new Uint8Array(pk)));
  return 'ryadom-' + hex(hash.slice(0,16));
}
export function hex(bytes: Uint8Array): string { return Array.from(bytes, x => x.toString(16).padStart(2,'0')).join(''); }
export function unhex(value: string): Uint8Array {
  if (!/^(?:[0-9a-f]{2})+$/.test(value)) throw new Error('Неверный ключ');
  return Uint8Array.from(value.match(/../g)!, x => parseInt(x,16));
}
export function verifyIdentity(signed: Uint8Array, pk: Uint8Array): Uint8Array {
  const verified = nacl.sign.open(signed, pk);
  if (!verified) throw new Error('Подпись компьютера не прошла проверку');
  return verified;
}
export function exchangeKey(theirPk: Uint8Array): { asymmetricValue: Uint8Array; symmetricValue: Uint8Array } {
  const pair = nacl.box.keyPair();
  const key = nacl.randomBytes(32);
  return {asymmetricValue: pair.publicKey, symmetricValue: nacl.box(key, new Uint8Array(24), theirPk, pair.secretKey)};
}
export async function passwordResponse(password: string, salt: string, challenge: string): Promise<Uint8Array> {
  const enc = new TextEncoder();
  const first = new Uint8Array(await crypto.subtle.digest('SHA-256', enc.encode(password + salt)));
  const data = new Uint8Array(first.length + enc.encode(challenge).length);
  data.set(first); data.set(enc.encode(challenge), first.length);
  return new Uint8Array(await crypto.subtle.digest('SHA-256', data));
}
export function directSdp(sdp: RTCSessionDescriptionInit, allowRelay=false): void {
  if (!sdp.sdp || sdp.sdp.length > 65536 || !['offer','answer'].includes(sdp.type)) throw new Error('Неверное описание соединения');
  if (!allowRelay && sdp.sdp.split(/\r?\n/).some(l => l.startsWith('a=candidate:') && /\btyp relay\b/.test(l))) throw new Error('Ретрансляция запрещена');
}
export function fingerprint(sdp: string): string {
  const match = /^a=fingerprint:sha-256 (.+)\r?$/m.exec(sdp);
  if (!match) throw new Error('Нет отпечатка сертификата DTLS');
  return 'sha-256 ' + match[1]!.trim();
}

export class Framing {
  private parts: Uint8Array[] = [];
  private size = 0;
  accept(frame: Uint8Array,limit=MAX_MESSAGE): Uint8Array | undefined {
    if (!frame.length || frame[0]! > 1 || (frame[0] === 1 && frame.length === 1)) throw new Error('Неверный фрагмент канала');
    this.size += frame.length - 1;
    if (this.size > limit) { this.parts = []; this.size = 0; throw new Error('Превышен размер сообщения'); }
    this.parts.push(frame.slice(1));
    if (frame[0] === 1) return;
    const result = new Uint8Array(this.size); let at = 0;
    for (const part of this.parts) { result.set(part,at); at += part.length; }
    this.parts = []; this.size = 0;
    return result;
  }
  static *encode(message: Uint8Array): Generator<Uint8Array> {
    if (message.length > MAX_MESSAGE) throw new Error('Превышен размер сообщения');
    for (let at = 0; at < message.length || at === 0; at += 16383) {
      const part = message.subarray(at,at+16383); const frame = new Uint8Array(part.length+1);
      frame[0] = at + part.length < message.length ? 1 : 0; frame.set(part,1); yield frame;
    }
  }
}
