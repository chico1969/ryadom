import { build } from 'esbuild';
import fs from 'node:fs/promises';
import path from 'node:path';
const result=await build({entryPoints:['src/index.ts'],bundle:true,outfile:'../ryadom.js',format:'iife',globalName:'RyadomEngine',target:'chrome120',sourcemap:true,legalComments:'eof',metafile:true});
const packages=new Set();
for(const input of Object.keys(result.metafile.inputs)){
  const match=input.replaceAll('\\','/').match(/^node_modules\/(\@[^/]+\/[^/]+|[^/]+)/);
  if(match)packages.add(match[1]);
}
let notices='Рядом browser engine — AGPL-3.0-only. Based on RustDesk 1.5.3.\n\n';
for(const name of [...packages].sort()){
  const folder=path.join('node_modules',name);const info=JSON.parse(await fs.readFile(path.join(folder,'package.json'),'utf8'));
  notices+=`\n${name} ${info.version} (${info.license??'see package notice'})\n`;
  const files=await fs.readdir(folder);
  for(const file of files.filter(x=>/^(licen[cs]e|copying|unlicen[cs]e)(\.|$)/i.test(x))){
    notices+=await fs.readFile(path.join(folder,file),'utf8')+'\n';
  }
}
await fs.writeFile('../THIRD_PARTY_NOTICES.txt',notices);
