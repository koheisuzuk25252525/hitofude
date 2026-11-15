'use strict';
// ---------- letter data (no storage or network) ----------
function validLetter(value) {
  return !!value && value.v === 1 && typeof value.text === 'string' &&
    value.text.trim().length > 0 && [...value.text].length <= 120 &&
    typeof value.from === 'string' && [...value.from].length <= 20 &&
    !/[\u0000-\u0008\u000b\u000c\u000e-\u001f\u007f]/.test(value.text + value.from) &&
    !/[\r\n]/.test(value.from) && Number.isInteger(value.puzzle) && value.puzzle >= 0 && value.puzzle < 4;
}
function encodeLetter(value) {
  if (!validLetter(value)) throw Error('invalid letter');
  const bytes = new TextEncoder().encode(JSON.stringify({v:1,text:value.text,from:value.from,puzzle:value.puzzle}));
  return '#letter=' + btoa(String.fromCharCode(...bytes)).replaceAll('+','-').replaceAll('/','_').replace(/=+$/,'');
}
function decodeLetter(hash) {
  if (hash.length > 3000 || !/^#letter=[A-Za-z0-9_-]+$/.test(hash)) return null;
  try {
    const raw = hash.slice(8).replaceAll('-','+').replaceAll('_','/');
    const value = JSON.parse(new TextDecoder('utf-8',{fatal:true}).decode(Uint8Array.from(atob(raw), c=>c.charCodeAt(0))));
    return validLetter(value) ? {v:1,text:value.text,from:value.from,puzzle:value.puzzle} : null;
  } catch { return null; }
}
function letterBoard(rotation) {
  const transform = index => {
    let r = Math.floor(index / 4), c = index % 4;
    for (let i = 0; i < rotation; i++) [r,c] = [c,3-r];
    return r * 4 + c;
  };
  const path = [0,1,2,3,7,6,5,4,8,9,10,11,15,14,13,12].map(transform);
  const clues = new Map([1,7,11,16].map(n=>[path[n-1],n]));
  return {path,clues};
}
function adjacent(a,b) { return Math.abs(Math.floor(a/4)-Math.floor(b/4))+Math.abs(a%4-b%4)===1; }
// ---------- interface ----------
const $ = id => document.getElementById(id);
let letter = null, board = null, route = [], opened = false, previewing = false;
let pointer = null, previousPoint = null;
const random = new Uint32Array(1); crypto.getRandomValues(random);
const draftPuzzle = random[0] % 4;
const status = text => { $('status').textContent = text; };
function updateForm() {
  const count = [...$('message').value].length;
  $('counter').textContent = `${count} / 120文字`;
  $('message').setCustomValidity(count > 120 ? '120文字以内で書いてください。' : !$('message').value.trim() ? '届けたい言葉を書いてください。' : '');
  $('sender').setCustomValidity([...$('sender').value].length > 20 ? '名前は20文字以内で書いてください。' : '');
  $('shareFallback').hidden = true;
  $('shareURL').value = '';
  status('');
}
function draft() {
  updateForm();
  if (!$('letterForm').reportValidity()) return null;
  const value = {v:1,text:$('message').value.trim(),from:$('sender').value.trim(),puzzle:draftPuzzle};
  if (!validLetter(value)) { status('入力した文字を確認してください。'); return null; }
  return value;
}
function focusTitle(id) { $(id).setAttribute('tabindex','-1'); $(id).focus({preventScroll:true}); }
function showComposer() {
  $('compose').hidden = false; $('receive').hidden = true; $('invalid').hidden = true;
  $('letterBody').textContent = ''; $('signature').textContent = '';
  letter = null; opened = false; pointer = null; previousPoint = null;
  status(''); window.scrollTo(0,0); focusTitle('composeTitle');
}
function showLetter(value, preview = false) {
  letter = value; board = letterBoard(value.puzzle); route = []; opened = false; previewing = preview;
  pointer = null; previousPoint = null;
  $('compose').hidden = true; $('receive').hidden = false; $('invalid').hidden = true;
  $('receiveIntro').hidden = false; $('previewBar').hidden = !preview; $('play').hidden = false; $('opened').hidden = true;
  $('letterBody').textContent = ''; $('signature').textContent = '';
  $('fromLabel').textContent = value.from ? `${value.from}さんから` : '言葉を包んだ、小さな贈りもの';
  $('board').replaceChildren();
  for (let i = 0; i < 16; i++) {
    const cell = document.createElement('button'); cell.type = 'button'; cell.className = 'cell'; cell.dataset.cell = String(i);
    cell.addEventListener('click', event => { if (event.detail === 0) takeStep(i); });
    $('board').appendChild(cell);
  }
  redraw(); status(''); window.scrollTo(0,0); focusTitle('receiveTitle');
}
function redraw(note) {
  for (let i = 0; i < 16; i++) {
    const cell = $('board').children[i], order = route.indexOf(i)+1, clue = board.clues.get(i);
    cell.textContent = clue || (order > 0 ? order : '');
    cell.classList.toggle('visited',order > 0); cell.classList.remove('tip');
    cell.setAttribute('aria-label',`${Math.floor(i/4)+1}行${i%4+1}列、${clue ? clue+'番目に通るマス' : '空白'}${order ? '、通過済み'+order+'番目' : ''}`);
  }
  $('thread').setAttribute('points',route.map(i=>`${i%4*100+50},${Math.floor(i/4)*100+50}`).join(' '));
  $('undo').disabled = !route.length; $('reset').disabled = !route.length;
  const next = [...board.clues.values()].filter(n=>n>route.length).sort((a,b)=>a-b)[0];
  $('guidance').textContent = note || (route.length ? `${route.length} / 16マス。次の「${next}」まで、あと${next-route.length}マス。` : '「1」から、ひと筆。');
}
function takeStep(cell) {
  if (!letter || opened || $('receive').hidden || !Number.isInteger(cell) || cell < 0 || cell > 15) return;
  if (route.at(-1) === cell) return;
  if (route.length > 1 && route.at(-2) === cell) { route.pop(); redraw(); return; }
  if (!route.length && board.clues.get(cell) !== 1) { redraw('「1」のマスからはじめてみて。'); return; }
  if (route.length && (!adjacent(route.at(-1),cell) || route.includes(cell))) return;
  const clue = board.clues.get(cell);
  if (clue && clue !== route.length+1) { redraw(`「${clue}」のマスは、${clue}番目に通ります。`); return; }
  route.push(cell);
  if (route.length === 16) { reveal(false); return; }
  redraw();
}
function reveal(skipped) {
  if (!letter || opened) return;
  opened = true; pointer = null; previousPoint = null;
  $('receiveIntro').hidden = true; $('play').hidden = true; $('opened').hidden = false;
  $('opened').classList.toggle('animated',!skipped);
  $('unsealedThread').hidden = skipped;
  $('openCaption').textContent = skipped ? '手紙を開きました' : 'ひと筆、気持ちがつながりました。';
  $('letterBody').textContent = letter.text;
  $('signature').textContent = letter.from ? `${letter.from}より` : '';
  $('createOwn').textContent = previewing ? '編集に戻って、この一通を送る' : '自分も一通つくる';
  $('opened').scrollIntoView({block:'start',behavior:'auto'}); focusTitle('openTitle');
}
function pointerPoint(event) {
  const rect = $('board').getBoundingClientRect();
  const x = (event.clientX-rect.left)/rect.width, y = (event.clientY-rect.top)/rect.height;
  if (x<0 || y<0 || x>=1 || y>=1) { previousPoint = null; return; }
  const last = previousPoint || {x,y};
  // Interpolate coalesced samples so a fast stroke cannot jump over a square.
  const steps = Math.max(1,Math.ceil(Math.hypot(x-last.x,y-last.y)*32));
  for (let i=0;i<=steps && !opened;i++) {
    const t=i/steps; takeStep(Math.floor((last.y+(y-last.y)*t)*4)*4+Math.floor((last.x+(x-last.x)*t)*4));
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
function loadHash() {
  if (!location.hash) { showComposer(); return; }
  const value=decodeLetter(location.hash);
  if(value)showLetter(value);
  else { $('compose').hidden=true;$('receive').hidden=true;$('invalid').hidden=false;$('letterBody').textContent='';letter=null;status('');focusTitle('invalidTitle'); }
}
window.addEventListener('hashchange',loadHash);
window.addEventListener('pageshow',()=>{pointer=null;previousPoint=null;});
updateForm();loadHash();
