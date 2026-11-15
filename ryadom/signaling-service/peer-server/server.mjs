import {PeerServer} from 'peer';
import {fileURLToPath} from 'node:url';

const port=Number(process.env.PORT || 9000);
const host=process.env.IP || process.env.HOST || '0.0.0.0';
if(!Number.isInteger(port)||port<1||port>65535)throw new Error('Invalid PORT');
const server=PeerServer({
  host,port,path:'/',key:'peerjs',
  proxied:true,allow_discovery:false,concurrent_limit:128,
  alive_timeout:30000,expire_timeout:5000
});
server.get('/health',(_,res)=>res.set('Cache-Control','no-store').json({service:'ryadom-signaling',version:1}));
server.get('/check',(_,res)=>res.sendFile(fileURLToPath(new URL('./public/index.html',import.meta.url)),{headers:{'Cache-Control':'no-store'}}));
server.get('/check.js',(_,res)=>res.sendFile(fileURLToPath(new URL('./public/check.js',import.meta.url)),{headers:{'Cache-Control':'no-store'}}));
console.log(`Ryadom signaling listening on ${port}`);
