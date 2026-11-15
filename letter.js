'use strict';
// ---------- letter data (no storage or network) ----------
const letterSegmenter = typeof Intl.Segmenter === 'function' ? new Intl.Segmenter('ja', {granularity:'grapheme'}) : null;
function letterCharacters(text) { return letterSegmenter ? [...letterSegmenter.segment(text)].map(part=>part.segment) : [...text]; }
function validLetter(value) {
  return !!value && (value.v === 1 || value.v === 2) && typeof value.text === 'string' &&
    value.text.trim().length > 0 && value.text.length <= 6000 && (value.v === 2 || letterCharacters(value.text).length <= 9) && !/[\r\n]/.test(value.text) &&
    typeof value.from === 'string' && [...value.from].length <= 20 &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value.text + value.from) &&
    !/[\r\n]/.test(value.from) && Number.isInteger(value.puzzle) && value.puzzle >= 0 && value.puzzle < 4 &&
    (value.difficulty === undefined ? value.seed === undefined : value.v === 2 && ['easy','normal','hard'].includes(value.difficulty) && Number.isInteger(value.seed) && value.seed >= 0 && value.seed <= 4294967295);
}
function letterPayload(value) {
  return {v:value.v,text:value.text,from:value.from,puzzle:value.puzzle,...(value.difficulty===undefined?{}:{difficulty:value.difficulty,seed:value.seed})};
}
function encodeLetter(value) {
  if (!validLetter(value)) throw Error('invalid letter');
  const bytes = new TextEncoder().encode(JSON.stringify(letterPayload(value)));
  const hash = '#letter=' + btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
  if(hash.length>8192)throw Error('letter too long');
  return hash;
}
function decodeLetter(hash) {
  if (hash.length > 8192 || !/^#letter=[A-Za-z0-9_-]+$/.test(hash)) return null;
  try {
    const raw = hash.slice(8).replaceAll('-','+').replaceAll('_','/');
    const value = JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(raw), c=>c.charCodeAt(0))));
    return validLetter(value) ? letterPayload(value) : null;
  } catch { return null; }
}
function letterBoard(rotation, count = 9, version = 1, difficulty, seed) {
  if(version===2 && difficulty!==undefined)return difficultyBoard(count,difficulty,seed);
  if(version === 2)return adaptiveBoard(rotation,count);
  const transform = index => {
    let r = Math.floor(index / 4), c = index % 4;
    for (let i = 0; i < rotation; i++) [r,c] = [c,3-r];
    return r * 4 + c;
  };
  const path = [0,1,2,3,7,6,5,4,8,9,10,11,15,14,13,12].map(transform);
  const clues = new Map([1,7,11,16].map(n=>[path[n-1],n]));
  return {path,clues,rows:4,cols:4};
}
function adjacent(a,b,cols=4) { return Math.abs(Math.floor(a/cols)-Math.floor(b/cols))+Math.abs(a%cols-b%cols)===1; }
function adaptiveBoard(variant,count) {
  const cols=Math.min(4,Math.max(2,Math.ceil(Math.sqrt(count+2)))), rows=Math.ceil((count+2)/cols);
  const path=[];
  for(let r=0;r<rows;r++)for(let j=0;j<cols;j++){
    let c=r%2?cols-1-j:j, rr=r;
    if(variant&1)c=cols-1-c;
    if(variant&2)rr=rows-1-r;
    path.push(rr*cols+c);
  }
  const clues=new Map([[path[0],1],[path.at(-1),path.length]]);
  for(let n=cols;n<path.length;n+=cols)clues.set(path[n-1],n);
  // Start with uniquely forced row segments; only remove clues after proving uniqueness.
  if(path.length<=64)for(const [cell,n] of [...clues]){
    if(n===1 || n===path.length)continue;
    clues.delete(cell);
    if(letterSolutionCount(rows,cols,clues)!==1)clues.set(cell,n);
  }
  return {rows,cols,path,clues};
}
function letterSolutionCount(rows,cols,clues) {
  const total=rows*cols, byStep=new Map([...clues].map(([cell,n])=>[n,cell]));
  const visited=new Uint8Array(total);let nodes=0,solutions=0;
  function walk(cell,n){
    if(++nodes>10000){solutions=2;return;}
    if(clues.has(cell) && clues.get(cell)!==n)return;
    if(n===total){solutions++;return;}
    const next=[...byStep.keys()].filter(k=>k>n).sort((a,b)=>a-b)[0],target=byStep.get(next);
    const distance=Math.abs(Math.floor(cell/cols)-Math.floor(target/cols))+Math.abs(cell%cols-target%cols);
    if(distance>next-n || (next-n-distance)%2)return;
    visited[cell]=1;
    for(const neighbor of [cell-1,cell+1,cell-cols,cell+cols]){
      if(solutions>=2)break;
      if(neighbor>=0 && neighbor<total && !visited[neighbor] && adjacent(cell,neighbor,cols))walk(neighbor,n+1);
    }
    visited[cell]=0;
  }
  walk(byStep.get(1),1);return solutions;
}
// Difficulty letters carry a seed; legacy v1/v2 letters retain their original boards.
function letterRandom(seed) {
  return () => { seed|=0;seed=seed+0x6D2B79F5|0;let t=Math.imul(seed^seed>>>15,1|seed);t=t+Math.imul(t^t>>>7,61|t)^t;return ((t^t>>>14)>>>0)/4294967296; };
}
function letterShuffle(items,rnd) {
  for(let i=items.length-1;i>0;i--){const j=Math.floor(rnd()*(i+1));[items[i],items[j]]=[items[j],items[i]];}
  return items;
}
function letterNeighbors(cell,rows,cols) {
  return [cell-cols,cell+1,cell+cols,cell-1].filter(n=>n>=0 && n<rows*cols && adjacent(cell,n,cols));
}
function wovenPath(rows,cols,rnd,fixedEndpoints=false) {
  if(!fixedEndpoints){
    let path=Array.from({length:rows*cols},(_,i)=>{const r=Math.floor(i/cols),c=i%cols;return r*cols+(r%2?cols-1-c:c);});
    for(let turn=0;turn<path.length*path.length*4;turn++){
      if(rnd()<0.5)path.reverse();
      const candidates=letterNeighbors(path.at(-1),rows,cols).filter(cell=>cell!==path.at(-2));
      const cell=candidates[Math.floor(rnd()*candidates.length)],index=path.indexOf(cell);
      if(index>=0)path=path.slice(0,index+1).concat(path.slice(index+1).reverse());
    }
    return path;
  }
  const total=rows*cols, end=(rows-1)*cols, visited=new Uint8Array(total),path=[0];
  const neighbors=Array.from({length:total},(_,i)=>letterNeighbors(i,rows,cols));
  let budget=40000;visited[0]=1;
  function walk(cell){
    if(--budget<0)return false;
    if(path.length===total)return cell===end;
    const candidates=letterShuffle(neighbors[cell].filter(n=>!visited[n] && (n!==end || path.length===total-1)),rnd);
    // Prefer constrained cells; random ties produce winding, reproducible paths.
    candidates.sort((a,b)=>neighbors[a].filter(n=>!visited[n]).length-neighbors[b].filter(n=>!visited[n]).length);
    for(const n of candidates){
      visited[n]=1;path.push(n);
      if(walk(n))return true;
      path.pop();visited[n]=0;
      if(budget<0)break;
    }
    return false;
  }
  if(walk(0))return path;
  // Bounded deterministic fallback, subsequently checked by the same clue solver.
  return Array.from({length:total},(_,i)=>{const r=Math.floor(i/cols),c=i%cols;return r*cols+(r%2?cols-1-c:c);});
}
function wovenSolutionCount(rows,cols,clues,budget=12000) {
  const total=rows*cols, neighbors=Array.from({length:total},(_,i)=>letterNeighbors(i,rows,cols));
  const byStep=new Map([...clues].map(([cell,n])=>[n,cell])),steps=[...byStep.keys()].sort((a,b)=>a-b);
  const visited=new Uint8Array(total),end=byStep.get(total);let found=0;
  function walk(cell,n){
    if(--budget<0){found=2;return;}
    if(n===total){found++;return;}
    const next=steps.find(k=>k>n),target=byStep.get(next);
    const d=Math.abs(Math.floor(cell/cols)-Math.floor(target/cols))+Math.abs(cell%cols-target%cols);
    if(d>next-n || (next-n-d)%2)return;
    for(let i=0;i<total;i++)if(!visited[i]){
      const degree=neighbors[i].filter(j=>!visited[j] || j===cell).length;
      if(degree===0 || (degree===1 && i!==end))return;
    }
    for(const neighbor of neighbors[cell]){
      if(found>=2)break;
      if(visited[neighbor] || (clues.has(neighbor) && clues.get(neighbor)!==n+1))continue;
      visited[neighbor]=1;walk(neighbor,n+1);visited[neighbor]=0;
    }
  }
  visited[byStep.get(1)]=1;walk(byStep.get(1),1);return found;
}
function difficultyBoard(count,difficulty,seed) {
  const cols=difficulty==='easy'?4:5, panelRows={easy:4,normal:6,hard:8}[difficulty];
  const capacity=cols*panelRows, panels=Math.ceil((count+2)/capacity),rnd=letterRandom(seed);
  const path=[],clues=new Map();
  for(let panel=0;panel<panels;panel++){
    const local=wovenPath(panelRows,cols,rnd,panels>1), localClues=new Map(local.map((cell,i)=>[cell,i+1]));
    // Numbered boundary rows separate long letters into independently unique sections.
    const protectedCell=cell=>cell===local[0] || cell===local.at(-1) || (panels>1 && (cell<cols || cell>=capacity-cols));
    for(const cell of letterShuffle(local.filter(cell=>!protectedCell(cell)),rnd)){
      const n=localClues.get(cell);localClues.delete(cell);
      if(wovenSolutionCount(panelRows,cols,localClues)!==1)localClues.set(cell,n);
    }
    const extra={easy:Math.ceil(capacity/4),normal:Math.ceil(capacity/12),hard:0}[difficulty];
    for(const cell of letterShuffle(local.filter(cell=>!localClues.has(cell)),rnd).slice(0,extra))localClues.set(cell,local.indexOf(cell)+1);
    const offset=panel*capacity;
    path.push(...local.map(cell=>cell+offset));
    for(const [cell,n] of localClues)clues.set(cell+offset,n+offset);
  }
  return {rows:panelRows*panels,cols,path,clues};
}

// ---------- interface ----------
const $ = id => document.getElementById(id);
let letter = null, board = null, route = [], opened = false, previewing = false;
let pointer = null, previousPoint = null, revealTimer = null;
const random = new Uint32Array(1); crypto.getRandomValues(random);
const draftPuzzle = random[0] % 4;
let draftSeed = random[0];
const difficultyNames={easy:"やさしい",normal:"ふつう",hard:"むずかしい"};
function draftValue(){return {v:2,text:$("message").value.trim(),from:$("sender").value.trim(),puzzle:draftPuzzle,difficulty:$("difficulty").value,seed:draftSeed};}
const status = text => { $('status').textContent = text; };
function updateForm() {
  const count = letterCharacters($('message').value).length;
  $('counter').textContent = `${count}文字`;
  $('message').setCustomValidity(!$('message').value.trim() ? '届けたい言葉を書いてください。' : '');
  if($('message').value.trim()){try{encodeLetter(draftValue());}catch{$('message').setCustomValidity('共有リンクに収まるよう、言葉を少し短くしてください。');}}
  $('sender').setCustomValidity([...$('sender').value].length > 20 ? '名前は20文字以内で書いてください。' : '');
  $('shareFallback').hidden = true;
  $('shareURL').value = '';
  status('');
}
function draft() {
  updateForm();
  if (!$('letterForm').reportValidity()) return null;
  const value = draftValue();
  if (!validLetter(value)) { status('入力した文字を確認してください。'); return null; }
  return value;
}
function focusTitle(id) { $(id).setAttribute('tabindex','-1'); $(id).focus({preventScroll:true}); }
function showComposer() {
  clearTimeout(revealTimer);
  $('compose').hidden = false; $('receive').hidden = true; $('invalid').hidden = true;
  $('letterBody').textContent = ''; $('signature').textContent = '';
  $('appLinks').hidden=true;
  letter = null; opened = false; pointer = null; previousPoint = null;
  status(''); window.scrollTo(0,0); focusTitle('composeTitle');
}
function showLetter(value, preview = false) {
  clearTimeout(revealTimer); $('play').classList.remove('delivered');
  letter = value; board = letterBoard(value.puzzle,letterCharacters(value.text).length,value.v,value.difficulty,value.seed); route = []; opened = false; previewing = preview;
  pointer = null; previousPoint = null;
  $('compose').hidden = true; $('receive').hidden = false; $('invalid').hidden = true;
  $('receiveIntro').hidden = false; $('previewBar').hidden = !preview; $('play').hidden = false; $('opened').hidden = true;
  $('letterBody').textContent = ''; $('signature').textContent = '';
  $('difficultyLabel').textContent=value.difficulty?`難易度：${difficultyNames[value.difficulty]}`:'';
  $('fromLabel').textContent = value.from ? `${value.from}さんから` : '言葉を包んだ、小さな贈りもの';
  $('board').replaceChildren();
  $('board').style.gridTemplateColumns=`repeat(${board.cols},1fr)`;
  $('board').style.gridTemplateRows=`repeat(${board.rows},1fr)`;
  $('board').style.aspectRatio=`${board.cols} / ${board.rows}`;
  $('board').setAttribute('aria-label',`${board.rows}かける${board.cols}の一筆パズル`);
  document.querySelector('svg.route').setAttribute('viewBox',`0 0 ${board.cols*100} ${board.rows*100}`);
  for (let i = 0; i < board.path.length; i++) {
    const cell = document.createElement('button'); cell.type = 'button'; cell.className = 'cell'; cell.dataset.cell = String(i);
    cell.addEventListener('click', event => { if (event.detail === 0) takeStep(i); });
    $('board').appendChild(cell);
  }
  redraw(); status(''); window.scrollTo(0,0); focusTitle('receiveTitle');
}
function redraw(note) {
  const positions=new Map(route.map((cell,index)=>[cell,index+1]));
  for (let i = 0; i < board.path.length; i++) {
    const cell = $('board').children[i], order = positions.get(i) || 0, clue = board.clues.get(i);
    const endpoint = clue === 1 ? '送り手' : clue === board.path.length ? '受け手' : '';
    cell.textContent = endpoint || clue || (order > 0 ? order : '');
    cell.classList.toggle('endpoint',!!endpoint);
    cell.classList.toggle('visited',order > 0); cell.classList.remove('tip');
    cell.setAttribute('aria-label',`${Math.floor(i/board.cols)+1}行${i%board.cols+1}列、${endpoint ? endpoint+'、'+clue+'番目に通るマス' : clue ? clue+'番目に通るマス' : '空白'}${order ? '、通過済み'+order+'番目' : ''}`);
  }
  $('thread').setAttribute('points',route.map(i=>`${i%board.cols*100+50},${Math.floor(i/board.cols)*100+50}`).join(' '));
  $('undo').disabled = !route.length; $('reset').disabled = !route.length;
  const next = [...board.clues.values()].filter(n=>n>route.length).sort((a,b)=>a-b)[0];
  $('guidance').textContent = note || (route.length ? `${route.length} / ${board.path.length}マス。次の「${next===board.path.length?'受け手':next}」まで、あと${next-route.length}マス。` : '「送り手」から「受け手」へ、ひと筆。');
}
function takeStep(cell) {
  if (!letter || opened || $('receive').hidden || !Number.isInteger(cell) || cell < 0 || cell >= board.path.length) return;
  if (route.at(-1) === cell) return;
  if (route.length > 1 && route.at(-2) === cell) { route.pop(); redraw(); return; }
  if (!route.length && board.clues.get(cell) !== 1) { redraw('「送り手」のマスからはじめてみて。'); return; }
  if (route.length && (!adjacent(route.at(-1),cell,board.cols) || route.includes(cell))) return;
  const clue = board.clues.get(cell);
  if (clue && clue !== route.length+1) { redraw(`「${clue}」のマスは、${clue}番目に通ります。`); return; }
  route.push(cell);
  if (route.length === board.path.length) { reveal(false); return; }
  redraw();
}
function reveal(skipped) {
  if (!letter || opened) return;
  opened = true; pointer = null; previousPoint = null;
  $('receiveIntro').hidden = true;
  $('play').hidden = skipped;
  $('opened').hidden = true;
  $('opened').classList.toggle('animated',!skipped);
  $('unsealedThread').setAttribute('hidden','');
  $('openCaption').textContent = skipped ? '手紙を開きました' : '送り手から、受け手へ。';
  $('letterBody').textContent = letter.text;
  $('signature').textContent = letter.from ? `${letter.from}より` : '';
  $('createOwn').textContent = previewing ? '編集に戻って、この一通を送る' : '自分も一通つくる';
  const characters = letterCharacters(letter.text);
  if (!skipped) {
    redraw(); $('play').classList.add('delivered');
    $('guidance').textContent = 'ひと筆、気持ちがつながりました。';
    for (let step=0;step<route.length;step++) {
      const cell=$('board').children[route[step]];
      cell.disabled=true;cell.replaceChildren();
      const text=step===0?'送り手':step===route.length-1?'受け手':characters[step-(route.length-1-characters.length)] || '';
      cell.setAttribute('aria-label',text || '線でつながるマス');
      const span=document.createElement('span'); span.textContent=text;
      if(step>=route.length-1-characters.length && step<route.length-1) {
        span.className='revealedCharacter';span.style.animationDelay=`${(step-(route.length-1-characters.length))*Math.min(180,2400/characters.length)}ms`;
      }
      cell.appendChild(span);
    }
  }
  const finish=()=>{
    $('opened').hidden=false;focusTitle('openTitle');
    if(skipped)$('opened').scrollIntoView({block:'start',behavior:'auto'});
  };
  if(skipped || matchMedia('(prefers-reduced-motion: reduce)').matches)finish();
  else revealTimer=setTimeout(finish,(characters.length-1)*Math.min(180,2400/characters.length)+400);
}
function pointerPoint(event) {
  const rect = $('board').getBoundingClientRect();
  const x = (event.clientX-rect.left)/rect.width, y = (event.clientY-rect.top)/rect.height;
  if (x<0 || y<0 || x>=1 || y>=1) { previousPoint = null; return; }
  const last = previousPoint || {x,y};
  // Interpolate coalesced samples so a fast stroke cannot jump over a square.
  const steps = Math.max(1,Math.ceil(Math.hypot((x-last.x)*board.cols,(y-last.y)*board.rows)*8));
  for (let i=0;i<=steps && !opened;i++) {
    const t=i/steps; takeStep(Math.floor((last.y+(y-last.y)*t)*board.rows)*board.cols+Math.floor((last.x+(x-last.x)*t)*board.cols));
  }
  previousPoint = {x,y};
}
$('board').addEventListener('pointerdown',event=>{
  if (pointer !== null || opened || (event.pointerType==='mouse' && event.button!==0)) return;
  event.preventDefault(); pointer=event.pointerId; previousPoint=null;
  $('board').setPointerCapture(event.pointerId); pointerPoint(event);
});
$('board').addEventListener('pointermove',event=>{
  if (pointer!==event.pointerId) return;
  event.preventDefault();
  for (const sample of event.getCoalescedEvents?.() || []) pointerPoint(sample);
  pointerPoint(event);
});
for (const name of ['pointerup','pointercancel','lostpointercapture']) $('board').addEventListener(name,event=>{
  if(pointer===event.pointerId) { pointer=null; previousPoint=null; }
});
$('undo').onclick=()=>{route.pop();redraw();};
$('reset').onclick=()=>{route=[];redraw();};
$('hint').onclick=()=>{
  let correct=0; while(correct<route.length && route[correct]===board.path[correct]) correct++;
  const corrected=correct<route.length; route=route.slice(0,correct);
  redraw((corrected?'つながる分岐点まで戻しました。':'')+'枠のマスへ進んでみて。');
  $('board').children[board.path[correct]].classList.add('tip');
};
$('skip').onclick=()=>reveal(true);
$('backToEdit').onclick=showComposer;
$('createOwn').onclick=()=>{
  if (!previewing) { history.replaceState(null,'',location.pathname+location.search); $('message').value=''; $('sender').value=''; updateForm(); }
  showComposer();
};
$('message').addEventListener('input',updateForm); $('sender').addEventListener('input',updateForm);
for (const button of document.querySelectorAll('[data-example]')) button.onclick=()=>{
  if ($('message').value.trim() && !confirm('今の言葉を、この例文に置き換えますか？')) return;
  $('message').value=button.dataset.example.replaceAll('\\n','\n'); updateForm(); $('message').focus();
};
$('difficulty').addEventListener('change',updateForm);
$('newPuzzle').onclick=()=>{const seed=new Uint32Array(1);crypto.getRandomValues(seed);draftSeed=seed[0];const value=draft();if(value)showLetter(value,true);};
$('preview').onclick=()=>{const value=draft();if(value)showLetter(value,true);};
$('letterForm').onsubmit=async event=>{
  event.preventDefault(); const value=draft(); if(!value)return;
  const link=new URL('letter.html',location.href); link.search='';link.hash=encodeLetter(value);
  const data={title:'あなたへ、一筆の手紙。',text:'ひと筆、つないで開けてみて。解かずに読むこともできます。',url:link.href};
  if (typeof navigator.share==='function') {
    try { await navigator.share(data);status('共有の操作が完了しました。');return; }
    catch(error){if(error?.name==='AbortError'){status('共有を取りやめました。手紙は編集できます。');return;}}
  }
  $('shareURL').value=link.href; $('shareFallback').hidden=false;
  $('shareFallback').scrollIntoView({block:'nearest'});status('リンクをコピーして、いつものメッセージで送れます。');
};
$('copyLink').onclick=async()=>{
  try { await navigator.clipboard.writeText($('shareURL').value);status('リンクをコピーしました。'); }
  catch { $('shareURL').focus();$('shareURL').select();status('自動コピーができませんでした。リンクを選択してコピーしてください。'); }
};
function updateAppLinks(value) {
  const inApp=new URLSearchParams(location.search).get('inApp')==='1';
  $('appLinks').hidden=!value || inApp;
  if(!value)return;
  $('openApp').href='hitofude://letter'+encodeLetter(value);
  const config=window.HITOFUDE_INSTALL || {};
  const store=/^https:\/\/apps\.apple\.com\/(?:[a-z]{2}\/)?app\/[^?#]*id[0-9]+(?:[?#].*)?$/.test(config.appStoreURL || '') ? config.appStoreURL : null;
  const beta=/^https:\/\/testflight\.apple\.com\/join\/[A-Za-z0-9]+$/.test(config.testFlightURL || '') ? config.testFlightURL : null;
  $('installApp').hidden=!(store || beta);
  if(store || beta){
    $('installApp').href=store || beta;
    $('installApp').textContent=store?'App Storeで入手':'TestFlightで試す';
    $('installHelp').textContent='インストール後は、この手紙のリンクをもう一度開いてください。';
  }
}
function loadHash() {
  clearTimeout(revealTimer);
  updateAppLinks(decodeLetter(location.hash));
  if (!location.hash) { showComposer(); return; }
  const value=decodeLetter(location.hash);
  if(value)showLetter(value);
  else { $('compose').hidden=true;$('receive').hidden=true;$('invalid').hidden=false;$('letterBody').textContent='';letter=null;status('');focusTitle('invalidTitle'); }
}
window.addEventListener('hashchange',loadHash);
window.addEventListener('pageshow',()=>{pointer=null;previousPoint=null;});
updateForm();loadHash();
