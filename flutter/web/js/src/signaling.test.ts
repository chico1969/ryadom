import { ICE, directCandidate, proveDirect, proveTransport } from './signaling';
import { parseTurnServers } from './network';
function peer(local:string,remote:string,selected=true):RTCPeerConnection {
  const rows=new Map<string,any>([
    ['transport',{type:'transport',selectedCandidatePairId:selected?'pair':undefined}],
    ['pair',{type:'candidate-pair',localCandidateId:'local',remoteCandidateId:'remote'}],
    ['local',{type:'local-candidate',candidateType:local}],['remote',{type:'remote-candidate',candidateType:remote}]
  ]);
  return {getStats:async()=>rows} as unknown as RTCPeerConnection;
}
test('configured ICE servers contain STUN only',()=>{
  for(const server of ICE.iceServers??[])for(const url of typeof server.urls==='string'?[server.urls]:server.urls)expect(url).toMatch(/^stun:/);
});
test('proves the actual selected transport pair',async()=>{
  await expect(proveDirect(peer('host','srflx'))).resolves.toEqual({local:'host',remote:'srflx'});
  await expect(proveDirect(peer('relay','srflx'))).rejects.toThrow();
  await expect(proveDirect(peer('host','relay'))).rejects.toThrow();
  await expect(proveDirect(peer('host','host',false))).rejects.toThrow();
  await expect(proveDirect(peer('unknown','host'))).rejects.toThrow();
  await expect(proveTransport(peer('relay','srflx'),true)).resolves.toEqual({local:'relay',remote:'srflx'});
  await expect(proveTransport(peer('unknown','host'),true)).rejects.toThrow();
  expect(()=>directCandidate({candidate:'candidate:1 1 udp 1 10.0.0.1 5000 typ relay'},true)).not.toThrow();
});

test('TURN configuration accepts connection credentials and rejects API keys',()=>{
  const config=[{urls:['turn:relay.example.com:80?transport=tcp','turns:relay.example.com:443?transport=tcp'],username:'test',credential:'test'}];
  expect(parseTurnServers(JSON.stringify(config))).toEqual(config);
  expect(()=>parseTurnServers(JSON.stringify([{...config[0],apiKey:'secret'}]))).toThrow();
  expect(()=>parseTurnServers(JSON.stringify([{...config[0],urls:['https://example.com']}]))).toThrow();
  expect(parseTurnServers('')).toEqual([]);
});
