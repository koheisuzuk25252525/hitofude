// No npm dependencies. Requires Chromium (CHROMIUM_PATH overrides its executable).
// Run: node tests/ui.test.mjs
import assert from 'node:assert/strict';
import { spawn } from 'node:child_process';
import { createServer } from 'node:http';
import { mkdtemp, readFile, rm, mkdir, writeFile } from 'node:fs/promises';
import { tmpdir } from 'node:os';
import { join, resolve, extname } from 'node:path';
import { fileURLToPath } from 'node:url';

// Preserve the assertion in CI annotations when hosted logs are unavailable.
process.on('uncaughtExceptionMonitor', error => {
  if (process.env.GITHUB_ACTIONS) {
    const message = String(error.stack || error).slice(0, 3500).replaceAll('%', '%25').replaceAll('\r', '%0D').replaceAll('\n', '%0A');
    console.error(`::error title=Browser regression::${message}`);
  }
});

const root = fileURLToPath(new URL('../', import.meta.url));
const profile = await mkdtemp(join(tmpdir(), 'hitofude-ui-'));
const server = createServer(async (req, res) => {
  try {
    const pathname = decodeURIComponent(new URL(req.url, 'http://localhost').pathname);
    const path = resolve(root, '.' + (pathname === '/' ? '/index.html' : pathname));
    if (!path.startsWith(root)) throw Error('outside root');
    const content = await readFile(path);
    const types = { '.html': 'text/html; charset=utf-8', '.svg': 'image/svg+xml', '.png': 'image/png', '.js':'text/javascript', '.css':'text/css' };
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
  await cdp('Page.navigate', {url:url+'letter.html'});
  await waitFor('typeof encodeLetter === "function"');
  check('Unicode round trip',await evaluate(`(()=>{const v={v:1,text:'ありがとう🌸',from:'こうへい',puzzle:2};return JSON.stringify(decodeLetter(encodeLetter(v)))===JSON.stringify(v)})()`),true);
  check('invalid links rejected',await evaluate(`[decodeLetter('#letter=x'),decodeLetter('#letter='+ 'a'.repeat(3001)),decodeLetter('#bad')]`),[null,null,null]);
  check('message limits enforced',await evaluate(`validLetter({v:1,text:'あ'.repeat(10),from:'',puzzle:0})`),false);
  await evaluate(`$('message').value='あ'.repeat(10);updateForm()`);
  check('ten characters can be sent',await evaluate(`$('message').checkValidity()`),true);
  await evaluate(`$('message').value='今日はありがとう。';$('sender').value='こうへい';$('preview').click()`);
  check('sealed preview has no message in reveal element',await evaluate(`[$('compose').hidden,$('previewBar').hidden,$('letterBody').textContent]`),[true,false,'']);
  await evaluate(`showLetter({v:1,text:'今日はありがとう。',from:'こうへい',puzzle:0},true)`);
  await evaluate(`$('board').children[5].click()`);
  check('endpoints are labelled before solving',await evaluate(`[$('board').children[0].textContent,$('board').children[12].textContent]`),['私','あなた']);
  check('cannot start on wrong cell',await evaluate('route.length'),0);
  const centers=await evaluate(`[...$('board').children].map(e=>{const r=e.getBoundingClientRect();return {x:r.x+r.width/2,y:r.y+r.height/2}})`);
  const touch=(type,point)=>cdp('Input.dispatchTouchEvent',{type,touchPoints:point?[{...point,id:1}]:[]});
  await touch('touchStart',centers[0]);await touch('touchMove',centers[3]);await touch('touchEnd');
  check('fast touch traverses intermediate squares',await evaluate('route'),[0,1,2,3]);
  for(const [a,b] of [[3,7],[7,4],[4,8],[8,11],[11,15],[15,12]]){
    await touch('touchStart',centers[a]);await touch('touchMove',centers[b]);await touch('touchEnd');
  }
  check('complete letter with real touch gestures',await evaluate('opened'),true);
  await evaluate(`showLetter({v:1,text:'今日はありがとう。',from:'こうへい',puzzle:0},true);for(const i of board.path)$('board').children[i].click()`);
  await waitFor(`!$('opened').hidden`);
  check('letters appear on path between endpoints',await evaluate(`route.map(i=>$('board').children[i].textContent).filter(Boolean)`),['私',...'今日はありがとう。','あなた']);
  check('keyboard activation completes and reveals',await evaluate(`[opened,$('letterBody').textContent,document.activeElement.id]`),[true,'今日はありがとう。','openTitle']);
  await evaluate(`$('createOwn').click()`);
  check('preview returns to retained draft',await evaluate(`[$('compose').hidden,$('sender').value,$('message').value.startsWith('今日は')]`),[false,'こうへい',true]);
  await evaluate(`Object.defineProperty(navigator,'share',{configurable:true,value:async data=>{globalThis.shared=data}});$('letterForm').requestSubmit()`);
  await waitFor('!!globalThis.shared');
  check('share payload excludes message from preview text',await evaluate(`[shared.text.includes('今日は'),new URL(shared.url).pathname.endsWith('/letter.html'),decodeLetter(new URL(shared.url).hash).from]`),[false,true,'こうへい']);
  await evaluate(`Object.defineProperty(navigator,'share',{configurable:true,value:async()=>{throw Object.assign(Error(),{name:'AbortError'})}});$('letterForm').requestSubmit()`);
  await waitFor(`$('status').textContent.includes('取りやめ')`);
  check('share cancellation does not expose fallback',await evaluate(`$('shareFallback').hidden`),true);
  await evaluate(`Object.defineProperty(navigator,'share',{configurable:true,value:undefined});$('letterForm').requestSubmit()`);
  check('unsupported share provides a link',await evaluate(`!$('shareFallback').hidden && !!decodeLetter(new URL($('shareURL').value).hash)`),true);
  await evaluate(`Object.defineProperty(navigator,'clipboard',{configurable:true,value:{writeText:async text=>{globalThis.copied=text}}});$('copyLink').click()`);
  await waitFor('!!globalThis.copied');
  check('copy preserves full payload',await evaluate(`copied===$('shareURL').value`),true);
  await evaluate(`Object.defineProperty(navigator,'clipboard',{configurable:true,value:undefined});$('copyLink').click()`);
  await waitFor(`$('status').textContent.includes('自動コピー')`);
  check('clipboard denied selects link for manual copy',await evaluate(`$('shareURL').selectionEnd===$('shareURL').value.length`),true);
  const hash=await evaluate(`encodeLetter({v:1,text:'<img>',from:'友だち',puzzle:1})`);
  await cdp('Page.navigate',{url:url+'letter.html'+hash});
  await waitFor(`typeof letter!=='undefined' && !!letter`);
  check('received message not rendered before opening',await evaluate(`$('letterBody').textContent`),'');
  for(const width of [320,390,430]) {
    await cdp('Emulation.setDeviceMetricsOverride',{width,height:844,deviceScaleFactor:1,mobile:true});
    check(width+'px no overflow',await evaluate('document.documentElement.scrollWidth<=innerWidth'),true);
  }
  await cdp('Emulation.setEmulatedMedia',{features:[{name:'prefers-color-scheme',value:'dark'},{name:'prefers-reduced-motion',value:'reduce'}]});
  check('dark mode uses a dark surface',await evaluate(`getComputedStyle(document.body).backgroundColor`),'rgb(27, 25, 23)');
  await evaluate(`$('skip').click()`);
  check('reduced motion disables animation',await evaluate(`getComputedStyle($('letterBody')).animationName`),'none');
  await cdp('Emulation.setEmulatedMedia',{features:[]});
  check('skip reveals literal text safely',await evaluate(`[$('letterBody').children.length,$('letterBody').textContent.startsWith('<img'),getComputedStyle($('unsealedThread')).display==='none']`),[0,true,true]);
  await evaluate(`$('createOwn').click()`);
  check('recipient starts a fresh letter without old hash',await evaluate(`[$('message').value,location.hash,$('compose').hidden]`),['','',false]);
  await evaluate(`location.hash='#letter=broken'`);
  await waitFor(`!$('invalid').hidden`);
  check('bad link shows recovery instead of an empty puzzle',await evaluate(`[$('compose').hidden,$('receive').hidden]`),[true,true]);
  check('app link retains message payload',await evaluate(`(()=>{const value={v:2,text:'ありがとう。また遊ぼうね',from:'友だち',puzzle:0};updateAppLinks(value);return decodeLetter(new URL($('openApp').href).hash).text})()`),'ありがとう。また遊ぼうね');
  check('no invented store link',await evaluate(`$('installApp').hidden`),true);
  await evaluate(`window.HITOFUDE_INSTALL={appStoreURL:'javascript:alert(1)',testFlightURL:''};updateAppLinks({v:2,text:'ありがとう',from:'',puzzle:0})`);
  check('unsafe install URL hidden',await evaluate(`$('installApp').hidden`),true);
  await evaluate(`history.replaceState(null,'','letter.html?inApp=1');updateAppLinks({v:2,text:'ありがとう',from:'',puzzle:0})`);
  check('in-app page suppresses recursive app opening',await evaluate(`$('appLinks').hidden`),true);
  await evaluate(`history.replaceState(null,'','letter.html')`);
  for(const length of [1,10,30,70]){
    await evaluate(`showLetter({v:2,text:'あ'.repeat(${length}),from:'',puzzle:0});for(const i of board.path)takeStep(i)`);
    await waitFor(`!$('opened').hidden`);
    check(length+' characters all reach recipient',await evaluate(`[$('letterBody').textContent.length,route.map(i=>$('board').children[i].textContent).filter(Boolean).join(''),$('board').children[route.at(-2)].textContent]`),[length,'私'+'あ'.repeat(length)+'あなた','あ']);
    check(length+' character board fits phone width',await evaluate('document.documentElement.scrollWidth<=innerWidth'),true);
  }
  await evaluate(`history.replaceState(null,'','letter.html');showComposer()`);
  if(process.env.UI_SCREENSHOT_DIR){
    await mkdir(process.env.UI_SCREENSHOT_DIR,{recursive:true});
    for(const screen of ['compose','sealed','opened']){
      if(screen==='sealed')await evaluate(`showLetter({v:1,text:'いつもありがとう',from:'こうへい',puzzle:0})`);
      if(screen==='opened'){await evaluate(`for(const i of board.path)takeStep(i)`);await waitFor(`!$('opened').hidden`);}
      await evaluate(`Promise.all(document.getAnimations().map(a=>a.finished.catch(()=>{})))`);
      const shot=await cdp('Page.captureScreenshot',{format:'png',captureBeyondViewport:true});
      await writeFile(join(process.env.UI_SCREENSHOT_DIR,screen+'.png'),Buffer.from(shot.data,'base64'));
    }
  }
  check('no uncaught browser errors',errors,[]);
  console.log(`PASS ${passed} letter checks (Chromium; real iPhone sharing remains to be tested)`);
} finally {
  socket?.close();
  if (browser && browser.exitCode === null) {
    const exited = new Promise(r => browser.once('exit', r)); browser.kill('SIGTERM'); await exited;
  }
  server.closeAllConnections();
  await new Promise(r => server.close(r));
  await rm(profile, { recursive: true, force: true, maxRetries: 5, retryDelay: 100 });
}
