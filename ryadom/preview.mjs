import http from 'node:http';
import fs from 'node:fs/promises';
import path from 'node:path';
import {fileURLToPath} from 'node:url';
const folder=path.join(path.dirname(fileURLToPath(import.meta.url)),'ui/build/web');
const port=Number(process.env.RYADOM_PREVIEW_PORT||5176);
const types={'.html':'text/html; charset=utf-8','.js':'application/javascript','.css':'text/css','.json':'application/json','.wasm':'application/wasm','.ttf':'font/ttf','.otf':'font/otf','.png':'image/png','.zip':'application/zip','.txt':'text/plain; charset=utf-8'};
await fs.access(path.join(folder,'index.html'));
const server=http.createServer(async(req,res)=>{
  try{
    const url=new URL(req.url,'http://127.0.0.1');
    const relative=decodeURIComponent(url.pathname==='/'?'/index.html':url.pathname);
    const file=path.resolve(folder,'.'+relative);
    if(!file.startsWith(folder+path.sep)){res.writeHead(403).end();return;}
    const data=await fs.readFile(file);
    res.writeHead(200,{'Content-Type':types[path.extname(file)]??'application/octet-stream','Cache-Control':'no-store','X-Content-Type-Options':'nosniff'}).end(data);
  }catch{res.writeHead(404).end();}
});
server.listen(port,'127.0.0.1',()=>console.log(`Рядом: предварительный просмотр http://127.0.0.1:${port}`));
