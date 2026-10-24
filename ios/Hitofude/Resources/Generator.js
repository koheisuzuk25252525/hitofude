// Bundled from index.html; keep seeded generator behavior identical.
let nativeDeadline = Infinity;
let nativeChecks = 0;
function checkNativeDeadline() {
  if ((++nativeChecks & 1023) === 0 && Date.now() >= nativeDeadline) throw new Error("Generation timed out");
}
// ---------- seeded RNG ----------
function mulberry32(a){return function(){a|=0;a=a+0x6D2B79F5|0;let t=Math.imul(a^a>>>15,1|a);t=t+Math.imul(t^t>>>7,61|t)^t;return((t^t>>>14)>>>0)/4294967296}}
function shuffle(arr,rnd){for(let i=arr.length-1;i>0;i--){const j=Math.floor(rnd()*(i+1));[arr[i],arr[j]]=[arr[j],arr[i]]}return arr}

// ---------- generator (port of gen/path.py) ----------
function neighbors(r,c,R,C){const o=[];if(r+1<R)o.push([r+1,c]);if(r>0)o.push([r-1,c]);if(c+1<C)o.push([r,c+1]);if(c>0)o.push([r,c-1]);return o}
function randomHamiltonianPath(R,C,rnd){
  let path=[];for(let r=0;r<R;r++){const cols=[];for(let c=0;c<C;c++)cols.push(c);if(r%2)cols.reverse();for(const c of cols)path.push([r,c])}
  const n=path.length,iters=n*n*4;
  for(let it=0;it<iters;it++){
    checkNativeDeadline();
    if(rnd()<0.5)path.reverse();
    const end=path[n-1],prev=path[n-2];
    const cand=neighbors(end[0],end[1],R,C).filter(q=>!(q[0]===prev[0]&&q[1]===prev[1]));
    if(!cand.length)continue;
    const q=cand[Math.floor(rnd()*cand.length)];
    const i=path.findIndex(p=>p[0]===q[0]&&p[1]===q[1]);
    const tail=path.splice(i+1);tail.reverse();path=path.concat(tail);
  }
  if(rnd()<0.5)path.reverse();
  return path;
}
// clues: Map key "r,c" -> k (1-based)
function countSolutions(R,C,clues,limit=2){
  const N=R*C;const posOf=new Map();const grid=new Map();
  for(const [key,k] of clues){posOf.set(k,key.split(',').map(Number));grid.set(key,k)}
  const start=posOf.get(1),end=posOf.get(N);if(!start||!end)return 0;
  const nums=[...posOf.keys()].sort((a,b)=>a-b);
  const nextClue=k=>{let lo=0,hi=nums.length;while(lo<hi){const m=(lo+hi)>>1;if(nums[m]<=k)lo=m+1;else hi=m}return lo<nums.length?nums[lo]:null};
  const vis=Array.from({length:R},()=>new Array(C).fill(false));let found=0;
  function deadEnd(r,c,k){
    for(let rr=0;rr<R;rr++)for(let cc=0;cc<C;cc++){
      if(vis[rr][cc])continue;let deg=0,adj=false;
      for(const [nr,nc] of neighbors(rr,cc,R,C)){if(nr===r&&nc===c)adj=true;else if(!vis[nr][nc])deg++}
      if(deg===0){if(!(adj&&k+1===N&&rr===end[0]&&cc===end[1]))return true}
      else if(deg===1&&!adj&&!(rr===end[0]&&cc===end[1]))return true;
    }return false;
  }
  function dfs(r,c,k){
    checkNativeDeadline();
    if(found>=limit)return;
    if(k===N){found++;return}
    if(N-k>2&&deadEnd(r,c,k))return;
    const nk=nextClue(k);
    if(nk!==null){const [tr,tc]=posOf.get(nk);const d=Math.abs(tr-r)+Math.abs(tc-c),rem=nk-k;if(d>rem||((rem-d)&1))return}
    for(const [nr,nc] of neighbors(r,c,R,C)){
      if(vis[nr][nc])continue;const g=grid.get(nr+','+nc);
      if(g!==undefined&&g!==k+1)continue;
      if(g===undefined&&nk!==null&&k+1===nk)continue;
      vis[nr][nc]=true;dfs(nr,nc,k+1);vis[nr][nc]=false;
    }
  }
  vis[start[0]][start[1]]=true;dfs(start[0],start[1],1);return found;
}
function makePuzzle(R,C,difficulty,rnd){
  const path=randomHamiltonianPath(R,C,rnd),N=path.length;
  const key=p=>p[0]+','+p[1];
  const clues=new Map([[key(path[0]),1],[key(path[N-1]),N]]);
  const pool=shuffle([...Array(N-2).keys()].map(i=>i+1),rnd);
  while(countSolutions(R,C,clues)!==1){if(!pool.length)break;const i=pool.pop();clues.set(key(path[i]),i+1)}
  const removable=shuffle([...clues.keys()].filter(k=>clues.get(k)!==1&&clues.get(k)!==N),rnd);
  for(const k of removable){const v=clues.get(k);clues.delete(k);if(countSolutions(R,C,clues)!==1)clues.set(k,v)}
  const extra={easy:Math.max(2,Math.floor(N/6)),medium:Math.max(1,Math.floor(N/12)),hard:0}[difficulty];
  const cand=shuffle(path.filter(p=>!clues.has(key(p))),rnd);
  for(const p of cand.slice(0,extra))clues.set(key(p),path.findIndex(q=>q[0]===p[0]&&q[1]===p[1])+1);
  return {R,C,path,clues,difficulty};
}


function nativePuzzle(size, difficulty, seed, timeoutMilliseconds = 20000) {
  nativeDeadline = Date.now() + timeoutMilliseconds; nativeChecks = 0;
  try {
  const p = makePuzzle(size, size, difficulty, mulberry32(seed));
  return JSON.stringify({size, path:p.path.map(([row,column])=>({row,column})),
    clues:[...p.clues].map(([key,value])=>{const [row,column]=key.split(',').map(Number);return {row,column,value}})});
  } finally { nativeDeadline = Infinity; }
}
