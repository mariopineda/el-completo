/* El Completo: portion scaling for cooking quantities, and no changes to original recipe files. */
(() => {
  const numberPattern = String.raw`(?:\d+(?:[.,]\d+)?|[¼½¾⅓⅔⅛⅜⅝⅞])`;
  const frac = {'¼':.25,'½':.5,'¾':.75,'⅓':1/3,'⅔':2/3,'⅛':.125,'⅜':.375,'⅝':.625,'⅞':.875};
  const units = String.raw`(?:kg|kilos?|kilogramos?|g|gramos?|mg|ml|mL|l|litros?|tazas?|cucharadas?|cucharaditas?|cdas?\.?|cdtas?\.?|dientes?|hojas?|ramitas?|ramas?|granos?|latas?|tarros?|paquetes?|unidades?|piezas?|trozos?|tortillas?|huevos?|papas?|patatas?|puerros?|cebollas?|tomates?|pimentones?|limones?|limas?|zanahorias?|paltas?|aguacates?|platos?|porciones?|burritos?|rebanadas?|rodajas?|manojos?|puñados?|pizcas?)`;
  const measured = new RegExp('(^|[^\\p{L}\\p{N}])('+numberPattern+')(?:\\s*[-–]\\s*('+numberPattern+'))?(\\s+)('+units+')\\b','giu');
  const numeric = new RegExp('(^|[^\\p{L}\\p{N}])('+numberPattern+')(?:\\s*[-–]\\s*('+numberPattern+'))?(?=\\s|$)','giu');
  const convert=s=>frac[s]??Number(s.replace(',','.'));
  function format(v){
    if(!Number.isFinite(v))return '';
    if(Math.abs(v-Math.round(v))<.0001)return String(Math.round(v));
    for(const [sign,f] of Object.entries(frac))if(Math.abs(v-f)<.0001)return sign;
    const whole=Math.floor(v), remainder=v-whole;
    for(const [sign,f] of Object.entries(frac))if(whole>0&&Math.abs(remainder-f)<.0001)return whole+' '+sign;
    return String(Number(v.toFixed(2))).replace('.',',');
  }
  function rewrite(s,mult,ingredient){
    if(ingredient){
      // Only the ingredient list: quantities are recipe quantities, including bare counts.
      return s.replace(numeric,(match,prefix,n1,n2)=>{
        const v=convert(n1); if(!Number.isFinite(v))return match;
        const x=format(v*mult), y=n2?format(convert(n2)*mult):null;
        return prefix+x+(y!==null?(match.includes('–')?'–':'-')+y:'');
      });
    }
    // Preparation: touch only ingredient quantities followed by an ingredient/unit noun.
    // Do NOT scale temperatures, elapsed time, knife cut dimensions or step numbers.
    return s.replace(measured,(match,prefix,n1,n2,space,unit)=>{
      const a=convert(n1),b=n2?convert(n2):null;
      return prefix+format(a*mult)+(b!==null?(match.includes('–')?'–':'-')+format(b*mult):'')+space+unit;
    });
  }
  function init(){
    document.querySelectorAll('.el-completo-escalador').forEach(e=>e.remove());
    const article=document.querySelector('.center > article') || document.querySelector('article');
    if(!article)return;
    const slug=document.body.dataset.slug||'';
    if(!slug.includes('01 - Recetas/')||slug.endsWith('/index'))return;
    const headings=[...article.querySelectorAll('h2')];
    const ingredients=headings.find(h=>/^ingredientes\b/i.test(h.textContent.trim()));
    if(!ingredients)return;
    const instructions=headings.find(h=>/^preparaci[oó]n\b|^instrucciones\b|^elaboraci[oó]n\b/i.test(h.textContent.trim()));
    const eligible=[];
    function collect(start,isIngredient){
      for(let e=start.nextElementSibling;e&&!/^H2$/i.test(e.tagName);e=e.nextElementSibling){
        // Exclude notes and callouts: quantities therein often refer to fixed per-serving comparisons.
        if(e.matches('.callout,blockquote,table,details'))continue;
        const walk=document.createTreeWalker(e,NodeFilter.SHOW_TEXT);
        let node;
        while((node=walk.nextNode())){
          if(!node.nodeValue.trim()||node.parentElement.closest('a,code,pre,button,select,.el-completo-escalador'))continue;
          // Ingredient quantities: actual list items only (or first paragraph in section).
          if(isIngredient&&!node.parentElement.closest('li')&&!e.matches('p'))continue;
          eligible.push({node,original:node.nodeValue,ingredient:isIngredient});
        }
      }
    }
    collect(ingredients,true);
    if(instructions)collect(instructions,false);
    if(!eligible.length)return;
    const wrapper=document.createElement('div'); wrapper.className='el-completo-escalador';
    const id='el-completo-factor';
    const label=document.createElement('label');label.htmlFor=id;label.textContent='🍽️ Tamaño de la receta';
    const select=document.createElement('select');select.id=id;select.setAttribute('aria-label','Multiplicar cantidades de la receta');
    [1,2,3,4].forEach(n=>{const o=document.createElement('option');o.value=n;o.textContent=n+'×';select.append(o)});
    const note=document.createElement('small');note.textContent='Se ajustan las cantidades de ingredientes. Los tiempos, temperaturas y valores nutricionales por porción no cambian automáticamente.';
    wrapper.append(label,select,note);
    ingredients.before(wrapper);
    select.addEventListener('change',()=>{
      const factor=Number(select.value);
      for(const x of eligible)x.node.nodeValue=factor===1?x.original:rewrite(x.original,factor,x.ingredient);
    });
  }
  if(document.readyState==='loading')document.addEventListener('DOMContentLoaded',init);else init();
  document.addEventListener('nav',init); // Quartz SPA navigation
})();
