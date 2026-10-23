// No npm dependencies. Requires Chromium (CHROMIUM_PATH overrides its executable).
// Run: node tests/ui.test.mjs
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

const root = fileURLToPath(new URL('../', import.meta.url));
const profile = await mkdtemp(join(tmpdir(), 'hitofude-ui-'));
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const path = resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!path.startsWith(root)) throw Error('outside root');
    const content = await readFile(path);
    const types = { '.html': 'text/html; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png' };
    res.writeHead(200, { 'Content-Type': types[extname(path)] || 'application/octet-stream' });
    res.end(content);
  } catch { res.writeHead(404); res.end(); }
});
await new Promise(r => server.listen(0, '127.0.0.1', r));
const url = `http://127.0.0.1:${server.address().port}/`;
let browser, socket;
let passed = 0;
const errors = [];
try {
  browser = spawn(process.env.CHROMIUM_PATH || 'chromium', [
    '--headless', '--no-sandbox', '--disable-dev-shm-usage', '--no-first-run',
    '--remote-debugging-port=0', `--user-data-dir=${profile}`, 'about:blank',
  ], { env: { ...process.env, XDG_CONFIG_HOME: profile, XDG_CACHE_HOME: profile }, stdio: ['ignore', 'ignore', 'pipe'] });
  const endpoint = await new Promise((resolveEndpoint, reject) => {
    let logs = '';
    const timer = setTimeout(() => reject(Error('Chromium startup timed out')), 15000);
    browser.on('error', e => { clearTimeout(timer); reject(e); });
    browser.on('exit', code => { clearTimeout(timer); reject(Error(`Chromium exited: ${code}\n${logs.slice(-2000)}`)); });
    browser.stderr.on('data', bytes => {
      logs += bytes;
      const found = /DevTools listening on (ws:\/\/[^\s]+)/.exec(logs);
      if (found) { clearTimeout(timer); resolveEndpoint(found[1]); }
    });
  });
  const address = new URL(endpoint);
  const pages = await (await fetch(`http://${address.host}/json`)).json();
  socket = new WebSocket(pages.find(p => p.type === 'page').webSocketDebuggerUrl);
  await new Promise((r, reject) => { socket.onopen = r; socket.onerror = reject; });
  let id = 0;
  const pending = new Map();
  socket.onmessage = e => {
    const message = JSON.parse(e.data);
    if (message.method === 'Runtime.exceptionThrown') errors.push(message.params.exceptionDetails);
    if (message.id) {
      const item = pending.get(message.id);
      if (item) { clearTimeout(item.timer); pending.delete(message.id); message.error ? item.reject(Error(JSON.stringify(message.error))) : item.resolve(message.result); }
    }
  };
  const cdp = (method, params = {}) => new Promise((resolveCall, reject) => {
    const current = ++id;
    const timer = setTimeout(() => { pending.delete(current); reject(Error(`CDP timeout: ${method}`)); }, 30000);
    pending.set(current, { resolve: resolveCall, reject, timer });
    socket.send(JSON.stringify({ id: current, method, params }));
  });
  const evaluate = async expression => {
    const response = await cdp('Runtime.evaluate', { expression, returnByValue: true, awaitPromise: true });
    if (response.exceptionDetails) throw Error(JSON.stringify(response.exceptionDetails));
    return response.result.value;
  };
  const waitFor = async expression => {
    for (let attempt = 0; attempt < 100; attempt++) {
      if (await evaluate(expression)) return;
      await new Promise(r => setTimeout(r, 50));
    }
    throw Error(`Not ready: ${expression}`);
  };
  const check = (name, actual, expected) => { assert.deepEqual(actual, expected, name); passed++; console.log(`ok ${name}`); };
  await cdp('Page.enable');
  await cdp('Runtime.enable');
  await cdp('Network.enable');
  await cdp('Network.setBlockedURLs', { urls: ['*fonts.googleapis.com*', '*fonts.gstatic.com*'] });
  await cdp('Emulation.setDeviceMetricsOverride', { width: 390, height: 844, deviceScaleFactor: 1, mobile: true });
  await cdp('Page.addScriptToEvaluateOnNewDocument', { source: `
    localStorage.setItem('hitofude:sound2','false');localStorage.setItem('hitofude:voice2','false');
    localStorage.setItem('hitofude:best:easy','45000');
  ` });
  await cdp('Page.navigate', { url });
  await waitFor('typeof newGame === "function" && !!puz');
  await evaluate('SFX.init=()=>{};SFX.resume=()=>{};FX.burst=()=>{}');
  check('existing stored preferences and best record preserved', await evaluate("[store.get('best:easy'),store.get('sound2'),store.get('voice2')]"), [45000, false, false]);

  for (const width of [375, 390, 430]) {
    await cdp('Emulation.setDeviceMetricsOverride', { width, height: 844, deviceScaleFactor: 1, mobile: true });
    for (const theme of ['light', 'dark']) {
      await evaluate(`document.documentElement.dataset.theme='${theme}';newGame('easy',1000)`);
      // Exercise the widest stats row and the wrap-to-own-row best label.
      await evaluate("$('timer').textContent='123:45';$('langtag').textContent='🇯🇵';$('best').hidden=false;$('best').textContent='ベスト 123:45';fitBoard()");
      const issues = await evaluate(`(() => {
        const issues=[];
        if(document.documentElement.scrollWidth>innerWidth)issues.push('page overflow');
        for(const e of document.querySelectorAll('.top,.stats,.tabs,.bar,.tab,.iconbtn,.bar .btn,.board')) {
          const r=e.getBoundingClientRect();
          if(r.left<0||r.right>innerWidth+1||e.scrollWidth>e.clientWidth+1)issues.push(e.id||e.className);
        }
        const buttons=[...document.querySelectorAll('.iconbtn,.tab,.bar .btn')];
        if(buttons.some(e=>e.getBoundingClientRect().height<44))issues.push('small touch target');
        return issues;
      })()`);
      check(`${width}px ${theme}: no clipping or horizontal overflow`, issues, []);
      if (process.env.UI_SCREENSHOT_DIR) {
        await mkdir(process.env.UI_SCREENSHOT_DIR, { recursive: true });
        const screenshot = await cdp('Page.captureScreenshot', { format: 'png' });
        await writeFile(join(process.env.UI_SCREENSHOT_DIR, `layout-${width}-${theme}.png`), Buffer.from(screenshot.data, 'base64'));
      }
    }
  }
  await cdp('Emulation.setDeviceMetricsOverride', { width: 375, height: 667, deviceScaleFactor: 1, mobile: true });
  check('compact instructions target only the board instructions', await evaluate(`$('cal').click();fitBoard();[$('instructions').classList.contains('compact'),document.querySelector('#calpanel .hint').classList.contains('compact')]`), [true, false]);
  await evaluate("$('cal').click();newGame('tutorial')");
  const centers = await evaluate(`[...$('cells').children].map(e=>{const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})`);
  const touch = (type, point) => cdp('Input.dispatchTouchEvent', { type, touchPoints: point ? [{ ...point, id: 1 }] : [] });
  const drag = async (a, b) => { await touch('touchStart', centers[a]); await touch('touchMove', centers[b]); await touch('touchEnd'); };
  await drag(0, 3);
  check('fast single move includes all four cells', await evaluate('route'), [[0,0],[0,1],[0,2],[0,3]]);
  await drag(3, 7); await drag(7, 4);
  check('fast reverse row respects numbered clues', await evaluate('route.length'), 8);
  await drag(4, 8); await drag(8, 11); await drag(11, 15); await drag(15, 12);
  check('tutorial can finish through actual touch input', await evaluate('[finished,route.length,store.get("tut")]'), [true,16,1]);
  await evaluate("newGame('tutorial')");
  await drag(0, 5);
  check('interpolation does not invent diagonal moves', await evaluate('route'), [[0,0]]);
  await evaluate("newGame('tutorial')");
  await touch('touchStart', centers[0]);
  await touch('touchMove', { x: centers[0].x, y: centers[0].y - 100 });
  await touch('touchMove', centers[3]); await touch('touchEnd');
  check('leaving board does not bridge a phantom path', await evaluate('route'), [[0,0]]);
  await evaluate("newGame('tutorial')");
  await drag(0,3); await drag(3,1);
  check('fast backwards drag undoes each intermediate step', await evaluate('route'), [[0,0],[0,1]]);

  await evaluate(`newGame('tutorial');globalThis.originalCapture=board.setPointerCapture;board.setPointerCapture=()=>{};
    const center=(r,c)=>{const rect=$('cells').children[r*4+c].getBoundingClientRect();return {clientX:rect.x+rect.width/2,clientY:rect.y+rect.height/2}};
    board.dispatchEvent(new PointerEvent('pointerdown',{...center(0,0),pointerId:99,isPrimary:true,button:0}));
    const event=new PointerEvent('pointermove',{...center(1,3),pointerId:99,isPrimary:true});
    Object.defineProperty(event,'getCoalescedEvents',{value:()=>[center(0,3)]});board.dispatchEvent(event);
    board.dispatchEvent(new PointerEvent('pointercancel',{pointerId:99}));board.setPointerCapture=originalCapture;
  `);
  check('coalesced corner samples retain the actual turn and cancel releases input', await evaluate('[route.length,activePointer,lastPointer]'), [5,null,null]);

  await cdp('Emulation.setDeviceMetricsOverride', { width: 375, height: 450, deviceScaleFactor: 1, mobile: true });
  await evaluate("newGame('tutorial');$('appScroll').scrollTo(0,100)");
  const departure = await evaluate(`(()=>{const r=$('cells').children[0].getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2,scroll:$('appScroll').scrollTop}})()`);
  assert(departure.scroll > 0, 'scroll test needs a nonzero departure offset');
  await touch('touchStart', { x: departure.x, y: departure.y });
  check('touch tracing locks page without moving the board', await evaluate(`(()=>{const r=$('cells').children[0].getBoundingClientRect();return [getComputedStyle(document.body).position,$('appScroll').style.overflowY,Math.abs(r.y+r.height/2-${departure.y})<1]})()`), ['fixed','hidden',true]);
  check('touchmove cancels browser panning', await evaluate(`(()=>{const e=new Event('touchmove',{cancelable:true,bubbles:true});board.dispatchEvent(e);return e.defaultPrevented})()`), true);
  await touch('touchEnd');
  check('touch end restores styles and prior scroll offset', await evaluate("[$('appScroll').style.overflowY,$('appScroll').scrollTop,scrollY,pageScrollLock]"), ['', departure.scroll, 0, null]);
  for (const reason of ['cancel', 'blur', 'new-game']) {
    await touch('touchStart', { x: departure.x, y: departure.y });
    if (reason === 'cancel') await touch('touchCancel');
    else if (reason === 'blur') await evaluate("window.dispatchEvent(new Event('blur'))");
    else await evaluate("newGame('tutorial')");
    check(`${reason} releases scroll lock and input state`, await evaluate("[pageScrollLock,activePointer,drawing,$('appScroll').style.overflowY]"), [null,null,false,'']);
    if (reason !== 'cancel') await touch('touchEnd');
  }
  check('touchmove outside a game gesture is not cancelled', await evaluate(`(()=>{const e=new Event('touchmove',{cancelable:true,bubbles:true});board.dispatchEvent(e);return e.defaultPrevented})()`), false);
  check('document cannot scroll while internal surface remains scrollable', await evaluate(`(()=>{window.scrollTo(0,100);const s=$('appScroll');s.scrollTo(0,50);const result=[scrollY,s.scrollTop>0,getComputedStyle(s).overflowY];s.scrollTo(0,0);return result})()`), [0,true,'auto']);
  await evaluate("$('appScroll').scrollTo(0,0)");
  await cdp('Emulation.setDeviceMetricsOverride', { width: 375, height: 667, deviceScaleFactor: 1, mobile: true });

  check('voice always uses Japanese and respects off setting', await evaluate(`(()=>{
    const originalSpeak=speechSynthesis.speak,originalCancel=speechSynthesis.cancel,wasOn=VOICE.on;
    const spoken=[];speechSynthesis.speak=u=>spoken.push([u.text,u.lang]);speechSynthesis.cancel=()=>{};
    VOICE.on=true;VOICE.say(1);VOICE.say(2);VOICE.say(12);VOICE.on=false;VOICE.say(13);
    VOICE.on=wasOn;speechSynthesis.speak=originalSpeak;speechSynthesis.cancel=originalCancel;
    return [spoken,$('langtag').textContent];
  })()`), [[['1','ja-JP'],['2','ja-JP'],['12','ja-JP']],'']);

  await evaluate(`globalThis.originalNow=Date.now;globalThis.testNow=100000;Date.now=()=>testNow;
    newGame('easy',1000);tryStep(...puz.path[0]);testNow+=12345;
    for(const p of puz.path.slice(1))tryStep(...p);
    globalThis.originalShare=shareText(true);globalThis.originalLink=challengeLink(finalMs);`);
  check('completion persists exact milliseconds', await evaluate("[finalMs,store.get('best:easy'),$('timer').textContent]"), [12345,12345,'0:12']);
  check('four completion buttons form two readable rows on a small phone', await evaluate(`(()=>{
    const bs=[...document.querySelectorAll('#done .row .btn')].filter(b=>!b.hidden);
    const rs=bs.map(b=>b.getBoundingClientRect());
    return [bs.length,Math.abs(rs[0].top-rs[1].top)<1,rs[2].top>rs[0].top,
      Math.abs(rs[2].top-rs[3].top)<1,rs.every(r=>r.width>=105&&r.height>=44&&r.left>=0&&r.right<=innerWidth+1)];
  })()`), [4,true,true,true,true]);
  await evaluate(`testNow+=86400000;finish();
    Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText(text){globalThis.copied=text;return Promise.resolve()}}});
    Object.defineProperty(navigator,'share',{configurable:true,value:data=>{globalThis.shared=data;return Promise.resolve()}});
    $('dare').click()`);
  check('native share receives a frozen-time invitation and challenge URL', await evaluate(
    "[shareText(true)===originalShare,shared.url===originalLink,shared.text.includes('0:12'),shared.title==='ヒトフデで対戦！',finalMs]"
  ), [true,true,true,true,12345]);
  await evaluate(`(async()=>{
    Object.defineProperty(navigator,'share',{configurable:true,value:undefined});
    globalThis.copied=null;
    await shareChallenge();
  })()`);
  check('unsupported share copies only the challenge URL', await evaluate('copied'), await evaluate('originalLink'));
  await evaluate(`(async()=>{
    globalThis.copied=null;
    Object.defineProperty(navigator,'share',{configurable:true,value:()=>Promise.reject(Object.assign(new Error('cancel'),{name:'AbortError'}))});
    await shareChallenge();
  })()`);
  check('cancelled share does not copy anything', await evaluate('copied'), null);
  await evaluate(`(async()=>{
    Object.defineProperty(navigator,'share',{configurable:true,value:()=>Promise.reject(new Error('share unavailable'))});
    await shareChallenge();
  })()`);
  check('failed share gracefully copies the challenge URL', await evaluate('copied'), await evaluate('originalLink'));
  await evaluate("$('copyDare').click()");
  check('explicit copy-link button copies the challenge URL', await evaluate('copied'), await evaluate('originalLink'));
  await evaluate("$('share').click()");
  check('ordinary result copy stays compatible', await evaluate("[copied===shareText(false),copied.includes('⏱ 0:12')]"), [true,true]);

  await evaluate(`rival={seed:1000,ms:9000};
    newGame('easy',1000);tryStep(...puz.path[0]);testNow+=55000;mistakes=8;
    for(const p of puz.path.slice(1))tryStep(...p)`);
  check('challenge finish switches to reply button', await evaluate("[$('share').textContent,$('doneText').textContent.includes('負け')]"), ['対戦結果を返信',true]);
  check('challenge reply is a short match summary without URL or emoji grid', await evaluate(`(()=>{
    const t=challengeResultText();
    return [t.includes('リンクを送った人：0:09'),t.includes('挑戦した人：0:55'),
      t.includes('タイム差：46秒'),t.includes('ミス 8回'),
      t.includes('リンクを送った人の勝ち'),!t.includes('https://'),!t.includes('⬜'),!t.includes('🟧')];
  })()`), [true,true,true,true,true,true,true,true]);
  await evaluate(`(async()=>{
    Object.defineProperty(navigator,'share',{configurable:true,value:data=>{globalThis.shared=data;return Promise.resolve()}});
    await shareResult();
  })()`);
  check('challenge result uses text-only native share', await evaluate("[Object.keys(shared),shared.text===challengeResultText()]"), [['text'],true]);
  await evaluate(`(async()=>{
    Object.defineProperty(navigator,'share',{configurable:true,value:undefined});
    globalThis.copied=null;
    await shareResult();
  })()`);
  check('unsupported challenge reply copies the same readable text', await evaluate('copied===challengeResultText()'), true);
  await evaluate(`(async()=>{
    globalThis.copied=null;
    Object.defineProperty(navigator,'share',{configurable:true,value:()=>Promise.reject(Object.assign(new Error('cancel'),{name:'AbortError'}))});
    await shareResult();
  })()`);
  check('cancelled result share does not copy anything', await evaluate('copied'), null);
  await evaluate(`(async()=>{
    Object.defineProperty(navigator,'share',{configurable:true,value:()=>Promise.reject(new Error('share failure'))});
    await shareResult();
  })()`);
  check('failed result share falls back to clear text', await evaluate('copied===challengeResultText()'), true);
  await evaluate(`testNow+=86400000;
    Object.defineProperty(navigator,'share',{configurable:true,value:data=>{globalThis.shared=data;return Promise.resolve()}});`);
  check('shared match result stays frozen after a day', await evaluate("[challengeResultText().includes('0:55'),challengeResultText().includes('46秒')]"), [true,true]);

  await evaluate("Date.now=originalNow;newGame('daily',20261021);tryStep(...puz.path[0]);for(const p of puz.path.slice(1))tryStep(...p)");
  check('daily date belongs to seed and stored daily record uses frozen result', await evaluate("[shareText().startsWith('ヒトフデ きょうの1問 2026/10/21'),store.get('daily:20261021')===finalMs]"), [true,true]);
  await evaluate(`Object.defineProperty(navigator,'share',{configurable:true,value:undefined});$('share').click()`);
  check('ordinary daily result remains copyable', await evaluate("[!rival,$('share').textContent,copied===shareText(false)]"), [true,'結果をコピー',true]);
  await evaluate("newGame('easy',1001)");
  check('new game resets frozen result', await evaluate('finalMs'), null);

  check('credits are hidden until configured', await evaluate("$('credits').hidden"), true);
  check('configured credits use text and HTTPS links only', await evaluate(`
    Object.assign(SITE_CREDITS,{name:'<制作者>',creatorUrl:'https://example.com/about',worksUrl:'javascript:alert(1)'});
    renderCredits();[!$('credits').hidden,$('credits').textContent.startsWith('制作：<制作者>'),$('credits').querySelectorAll('a').length,$('credits').querySelector('a').href]
  `), [true,true,1,'https://example.com/about']);
  await evaluate('globalThis.RealWorker=Worker');
  for (const failure of ['error', 'messageerror', 'constructor', 'timeout']) {
    await evaluate(`(async()=>{globalThis.terminated=0;globalThis.realTimeout=setTimeout;
      globalThis.setTimeout=(fn,ms,...args)=>realTimeout(fn,ms===GENERATION_TIMEOUT_MS?10:ms,...args);
      globalThis.Worker=class {
        constructor(){if('${failure}'==='constructor')throw Error('unavailable')}
        postMessage(){if('${failure}'==='error')queueMicrotask(()=>this.onerror({preventDefault(){}}));
          if('${failure}'==='messageerror')queueMicrotask(()=>this.onmessageerror())}
        terminate(){terminated++}
      };
      await newGame('oni',1000);globalThis.Worker=RealWorker;globalThis.setTimeout=realTimeout;})()`);
    check(`Worker ${failure}: recoverable UI, no spinner or stale board`, await evaluate("[$('loading').hidden,!$('generationError').hidden,puz===null,$('cells').children.length]"), [true,true,true,0]);
    if (failure !== 'constructor') check(`Worker ${failure}: terminated`, await evaluate('terminated'), 1);
    await evaluate("$('retryGeneration').click()");
    await waitFor('!!puz');
    check(`Worker ${failure}: retry keeps original seed and mode`, await evaluate("[mode,seed,puz.path.length,$('generationError').hidden]"), ['oni',1000,64,true]);
  }
  await evaluate(`(async()=>{globalThis.Worker=class{postMessage(){} terminate(){}};
    const old=newGame('oni',1000);await newGame('easy',1001);await old;globalThis.Worker=RealWorker;})()`);
  check('superseded generation cannot overwrite newer game or expose error', await evaluate("[mode,seed,puz.path.length,$('loading').hidden,$('generationError').hidden]"), ['easy',1001,25,true,true]);
  await cdp('Page.navigate', { url: url + '?legacy-link#c-e-1000-12' });
  await waitFor('typeof puz !== "undefined" && !!puz');
  check('legacy challenge URL loads expected opponent and seed', await evaluate('[mode,seed,rival.ms,puz.path.length]'), ['easy',1000,12000,25]);
  check('legacy daily data and tutorial flag survived reload', await evaluate("[typeof store.get('daily:20261021'),store.get('tut')]"), ['number',1]);
  check('OG image resolves and metadata points to canonical HTTPS PNG', await evaluate(`fetch('assets/og-image.png').then(async r=>[r.ok,(await r.blob()).type,document.querySelector('meta[property="og:image"]').content])`), [true,'image/png','https://koheisuzuk25252525.github.io/hitofude/assets/og-image.png']);
  check('no uncaught browser exceptions', errors, []);
  console.log(`PASS ${passed} browser regression checks (Chromium; iPhone Safari device testing remains required)`);
} finally {
  socket?.close();
  if (browser && browser.exitCode === null) {
    const exited = new Promise(r => browser.once('exit', r)); browser.kill('SIGTERM'); await exited;
  }
  server.closeAllConnections();
  await new Promise(r => server.close(r));
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
