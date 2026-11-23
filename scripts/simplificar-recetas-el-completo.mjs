/**
 * El Completo — presentation-only recipe layout for Quartz.
 * Never run against the Obsidian vault. This script only transforms Quartz's
 * website content/ during the GitHub Pages build (or a local validation).
 */
import fs from 'node:fs';
import path from 'node:path';

const root = path.join('content', '01 - Recetas');
const checkOnly = process.argv.includes('--check');
const normal = s => s.replace(/\r\n?/g, '\n');
const titleOf = heading => heading.replace(/^##\s+/, '').trim().toLocaleLowerCase('es');
const has = (key, phrase) => key === phrase || key.startsWith(phrase + ' ');

function sectionize(body){
  const lineStart = /^##\s+[^\n]+$/gm;
  const headings = [...body.matchAll(lineStart)];
  if(!headings.length) return {lead:body,sections:[]};
  const sections = headings.map((match,index)=>({
    heading:match[0],
    key:titleOf(match[0]),
    body:body.slice(match.index + match[0].length, index+1 < headings.length ? headings[index+1].index : body.length).trim(),
  }));
  return {lead:body.slice(0,headings[0].index).trim(),sections};
}
function cleanIngredientIntro(body){
  // Remove only the introductory callout, not the ingredient checklist itself.
  return body.replace(/^>\s*\[!tip\][^\n]*(?:\n>[^\n]*)*\n*/i, '').trim();
}
function photoOnly(body){
  // Support both Obsidian embeds and ordinary Markdown images, preserving
  // the native image dimensions/aspect ratios (no enforced square crop).
  const lines=body.split('\n');
  const imageLine=lines.find(line=>/^\s*(?:!\[\[[^\]]+\]\]|!\[[^\]]*\]\([^)]*\))\s*$/.test(line));
  return imageLine?.trim() ?? '';
}
function collapseReview(body){
  // Native Quartz/Obsidian folded callout: the rest is preserved in the
  // source text and exposed only when expanded by a reader.
  const rows=body.trim().split('\n');
  if(!rows.length || !body.trim())return '';
  return ['> [!warning]- Revisión pendiente',...rows.map(row=>row ? '> '+row : '>')].join('\n');
}
function simplifyMarkdown(source, file){
  const original=normal(source);
  const yaml=original.match(/^\uFEFF?(---\n[\s\S]*?\n---\n)/);
  if(!yaml)throw new Error(`${file}: missing YAML frontmatter; refusing to transform`);
  const header=yaml[1];
  const {lead,sections}=sectionize(original.slice(yaml[0].length));
  const ingredients=sections.find(s=>has(s.key,'ingredientes'));
  const preparation=sections.find(s=>has(s.key,'preparación') || has(s.key,'preparacion') || has(s.key,'instrucciones') || has(s.key,'elaboración'));
  if(!ingredients||!preparation)throw new Error(`${file}: missing Ingredientes or Preparación; refusing to transform`);
  const imageSection=sections.find(s=>has(s.key,'fotografía') || has(s.key,'fotografia'));
  const nutrition=sections.find(s=>has(s.key,'información nutricional') || has(s.key,'informacion nutricional'));
  const next=sections.find(s=>has(s.key,'pendiente para la próxima preparación') || has(s.key,'pendiente para la proxima preparacion'));
  const review=sections.find(s=>has(s.key,'revisión pendiente') || has(s.key,'revision pendiente'));
  const used=new Set([ingredients,preparation,imageSection,nutrition,next,review].filter(Boolean));
  const keepExtra=sections.filter(s=>!used.has(s) && ![
    'observaciones y mejoras','historial de preparaciones','antes de empezar'
  ].some(k=>has(s.key,k)));
  const mainTitle=lead.match(/^#\s+[^\n]+/m);
  if(!mainTitle)throw new Error(`${file}: missing H1 title; refusing to transform`);
  const intro=lead.replace(mainTitle[0], '').replace(/^>\s*\[!info\]\s*Antes de empezar[^\n]*(?:\n>[^\n]*)*\n*/gmi, '').trim();
  const blocks=[mainTitle[0]];
  if(imageSection){const image=photoOnly(imageSection.body);if(image)blocks.push(image);}
  blocks.push(ingredients.heading+'\n\n'+cleanIngredientIntro(ingredients.body));
  blocks.push(preparation.heading+'\n\n'+preparation.body);
  if(intro)blocks.push('## Notas de la receta\n\n'+intro);
  for(const section of keepExtra) blocks.push(section.heading+'\n\n'+section.body);
  if(nutrition)blocks.push(nutrition.heading+'\n\n'+nutrition.body);
  if(next)blocks.push(next.heading+'\n\n'+next.body);
  if(review)blocks.push(collapseReview(review.body));
  return header+'\n'+blocks.filter(Boolean).join('\n\n').trim()+'\n';
}

if(!fs.existsSync(root))throw new Error(`Recipe directory missing: ${root}`);
let changed=0, total=0;
for(const folder of fs.readdirSync(root,{withFileTypes:true}).filter(d=>d.isDirectory())){
  const dir=path.join(root,folder.name);
  for(const filename of fs.readdirSync(dir).filter(f=>f.toLowerCase().endsWith('.md') && f.toLowerCase()!=='index.md')){
    const file=path.join(dir,filename);
    const before=fs.readFileSync(file,'utf8');
    // Render only recipe files, not category indexes, portals or collections.
    if(!/^tipo:\s*receta\s*$/m.test(before))continue;
    total++;
    const after=simplifyMarkdown(before,file);
    if(normal(before)!==after){changed++;if(!checkOnly)fs.writeFileSync(file,after,'utf8');}
  }
}
if(total===0)throw new Error('No recipe pages found; refusing to report success');
console.log(`El Completo recipe layout: checked=${total}, ${checkOnly?'would_transform':'transformed'}=${changed}`);
