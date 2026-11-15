import { parseTurnServers } from './network';
export type Computer = {id:string; name:string; code?:string; lastConnected:number};
const DB = 'ryadom-local-v1';
async function database(): Promise<IDBDatabase> {
  return new Promise((resolve,reject) => {
    const request = indexedDB.open(DB,1);
    request.onupgradeneeded = () => { request.result.createObjectStore('computers',{keyPath:'id'}); request.result.createObjectStore('keys'); request.result.createObjectStore('secrets'); };
    request.onsuccess = () => resolve(request.result); request.onerror = () => reject(request.error);
  });
}
async function operation<T>(store: string, mode:IDBTransactionMode, perform:(store:IDBObjectStore)=>IDBRequest<T>): Promise<T> {
  const db = await database();
  return new Promise((resolve,reject) => {
    const tx = db.transaction(store,mode); const request = perform(tx.objectStore(store));
    tx.oncomplete = () => { db.close(); resolve(request.result); };
    tx.onabort = tx.onerror = () => { db.close(); reject(tx.error); };
  });
}
export class Vault {
  async saveTurnServers(raw:string):Promise<void> {
    const servers=parseTurnServers(raw);
    await this.savePassword('local-turn-settings.v1',JSON.stringify(servers));
  }
  async turnServers():Promise<RTCIceServer[]|undefined> {
    const raw=await this.password('local-turn-settings.v1');
    return raw===undefined?undefined:parseTurnServers(raw);
  }
  async computers(): Promise<Computer[]> { return operation('computers','readonly',s => s.getAll()); }
  async remember(computer:Computer): Promise<void> {
    const previous=await operation<Computer|undefined>('computers','readonly',s=>s.get(computer.id));
    await operation('computers','readwrite',s => s.put({...computer,code:computer.code??previous?.code}));
  }
  async remove(id:string): Promise<void> { await operation('computers','readwrite',s => s.delete(id)); await operation('secrets','readwrite',s => s.delete(id)); }
  private async key(): Promise<CryptoKey> {
    const previous = await operation<CryptoKey | undefined>('keys','readonly',s => s.get('passwords'));
    if (previous) return previous;
    const key = await crypto.subtle.generateKey({name:'AES-GCM',length:256},false,['encrypt','decrypt']);
    // add, rather than put, prevents racing tabs from replacing the key protecting existing entries.
    try { await operation('keys','readwrite',s => s.add(key,'passwords')); return key; }
    catch { const existing = await operation<CryptoKey | undefined>('keys','readonly',s => s.get('passwords')); if (!existing) throw new Error('Не удалось сохранить ключ'); return existing; }
  }
  async savePassword(id:string, password:string): Promise<void> {
    const key = await this.key(); const iv = crypto.getRandomValues(new Uint8Array(12));
    const ciphertext = await crypto.subtle.encrypt({name:'AES-GCM',iv,additionalData:new TextEncoder().encode(id)},key,new TextEncoder().encode(password));
    await operation('secrets','readwrite',s => s.put({iv,ciphertext},id));
  }
  async password(id:string): Promise<string | undefined> {
    const entry = await operation<{iv:Uint8Array;ciphertext:ArrayBuffer} | undefined>('secrets','readonly',s => s.get(id));
    if (!entry) return;
    return new TextDecoder().decode(await crypto.subtle.decrypt({name:'AES-GCM',iv:entry.iv,additionalData:new TextEncoder().encode(id)},await this.key(),entry.ciphertext));
  }
  async forgetPassword(id:string): Promise<void> { await operation('secrets','readwrite',s => s.delete(id)); }
}
