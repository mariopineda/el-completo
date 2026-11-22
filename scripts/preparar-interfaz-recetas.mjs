import fs from 'node:fs';
import path from 'node:path';
const base='content', root=path.join(base,'01 - Recetas');
const read=p=>fs.readFileSync(p,'utf8');
const write=(p,s)=>fs.writeFileSync(p,s,'utf8');
const cats=fs.readdirSync(root,{withFileTypes:true}).filter(x=>x.isDirectory()).map(x=>x.name);
const counts={};
for(const cat of cats){
 const dir=path.join(root,cat);
 counts[cat]=fs.readdirSync(dir).filter(f=>f.endsWith('.md')&&f.toLowerCase()!=='index.md')
 .filter(f=>!/^[ \t]*draft:[ \t]*true[ \t]*$/m.test(read(path.join(dir,f)))).length;
}
const total=Object.values(counts).reduce((a,b)=>a+b,0);
function collectionCount(file){
 const s=read(path.join(base,file));
 return new Set([...s.matchAll(/\[\[([^\]|]+)(?:\|[^\]]*)?\]\]/g)].map(m=>m[1])).size;
}
const favorites=collectionCount('Favoritas.md');
const toTry=collectionCount('Por probar.md');
let home=read(path.join(base,'index.md'));
home=home.replace(/(\[\[01 - Recetas\/index\|🍲 Recetas)(?:\s*\(\d+\))?(\]\])/g,(_m,a,b)=>a+' ('+total+')'+b)
 .replace(/(\[\[Favoritas\|❤️ Favoritas)(?:\s*\(\d+\))?(\]\])/g,(_m,a,b)=>a+' ('+favorites+')'+b)
 .replace(/(\[\[Por probar\|🍽️ Por probar)(?:\s*\(\d+\))?(\]\])/g,(_m,a,b)=>a+' ('+toTry+')'+b);
write(path.join(base,'index.md'),home);
let portal=read(path.join(root,'index.md'));
for(const [cat,n] of Object.entries(counts)){
 const prefix='[[01 - Recetas/'+cat+'/index|';
 portal=portal.split('\n').map(line=>line.includes(prefix)?line.replace(/(?:\s*\(\d+\))?(\]\])/,(_m,end)=>' ('+n+')'+end):line).join('\n');
}
write(path.join(root,'index.md'),portal);
let removed=0;
for(const cat of cats){
 const dir=path.join(root,cat);
 for(const filename of fs.readdirSync(dir).filter(f=>f.endsWith('.md')&&f.toLowerCase()!=='index.md')){
  const p=path.join(dir,filename), original=read(p);
  // Remove the AI disclosure *caption*, not the image or provenance metadata.
  const updated=original.replace(/^> \[!note\] Imagen de referencia\r?\n(?:>[^\r\n]*(?:\r?\n|$))+/gmi,()=>{removed++;return '';});
  // Remove italic AI-image captions such as those under the chili photograph.
  const withoutItalicAiCaption = updated.replace(/^\s*\*Ilustraci[oÃ³]n generada con IA[^\r\n]*\*\s*$/gmi, '');
  if(withoutItalicAiCaption!==original)write(p,withoutItalicAiCaption);
 }
}
console.log('El Completo — recipe counts:',JSON.stringify({total,favorites,toTry,categories:counts,AI_captions_removed:removed},null,2));
