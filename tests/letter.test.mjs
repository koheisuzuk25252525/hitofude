import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
const source=readFileSync(new URL('../letter.js',import.meta.url),'utf8').split('// ---------- interface ----------')[0];
const {encodeLetter,decodeLetter,letterBoard}=new Function(source+';return {encodeLetter,decodeLetter,letterBoard}')();
const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const {countSolutions}=new Function(html.slice(html.indexOf('// ---------- seeded RNG'),html.indexOf('// ---------- worker'))+';return {countSolutions}')();
for(let rotation=0;rotation<4;rotation++){
  const {path,clues}=letterBoard(rotation);
  assert.equal(new Set(path).size,16);
  assert.equal(countSolutions(4,4,new Map([...clues].map(([i,n])=>[`${Math.floor(i/4)},${i%4}`,n]))),1);
}
const max={v:1,text:'🌸'.repeat(9),from:'名'.repeat(20),puzzle:3};
assert.deepEqual(decodeLetter(encodeLetter(max)),max);
for(const patch of [{v:3},{text:''},{text:' '},{text:'x'.repeat(10)},{from:'x'.repeat(21)},{from:'a\nb'},{text:'\0'},{text:'あ\nい'},{puzzle:4},{puzzle:-1},{puzzle:0.5},{text:123}]){
  const value={...max,...patch};
  assert.throws(()=>encodeLetter(value));
  assert.equal(decodeLetter('#letter='+Buffer.from(JSON.stringify(value)).toString('base64url')),null);
}
for(const hash of ['#letter=%%%','#letter=_w','#letter=e30','#letter='+ 'a'.repeat(3000),'#other=abc'])assert.equal(decodeLetter(hash),null);
console.log('PASS letter Unicode boundaries, untrusted payload validation, and all four uniquely solvable boards');

const family={v:1,text:'👨‍👩‍👧‍👦'.repeat(9),from:'',puzzle:0};
assert.deepEqual(decodeLetter(encodeLetter(family)),family);
assert.deepEqual(decodeLetter(encodeLetter({...family,text:'か\u3099'.repeat(9)})).text,'か\u3099'.repeat(9));

for(const length of [1,5,9,10,20,40,62,100,200])for(let variant=0;variant<4;variant++){
  const value={v:2,text:'あ'.repeat(length),from:'',puzzle:variant};
  assert.deepEqual(decodeLetter(encodeLetter(value)),value);
  const b=letterBoard(variant,length,2);
  assert(b.path.length>=length+2);
  assert.equal(new Set(b.path).size,b.rows*b.cols);
  for(let i=1;i<b.path.length;i++)assert.equal(Math.abs(Math.floor(b.path[i]/b.cols)-Math.floor(b.path[i-1]/b.cols))+Math.abs(b.path[i]%b.cols-b.path[i-1]%b.cols),1);
  if(length<=62)assert.equal(countSolutions(b.rows,b.cols,new Map([...b.clues].map(([i,n])=>[`${Math.floor(i/b.cols)},${i%b.cols}`,n]))),1);
}
console.log('PASS adaptive sizes, path validity, unique solutions, and version 1 compatibility');

const paths=new Set(),density={easy:0,normal:0,hard:0};
for(const difficulty of ['easy','normal','hard'])for(let seed=0;seed<24;seed++){
  const value={v:2,text:'ありがとう',from:'友だち',puzzle:0,difficulty,seed};
  assert.deepEqual(decodeLetter(encodeLetter(value)),value);
  const b=letterBoard(0,6,2,difficulty,seed),again=letterBoard(0,6,2,difficulty,seed);
  assert.deepEqual(b,again,'a shared seed always reproduces the same puzzle');
  assert.equal(new Set(b.path).size,b.rows*b.cols);
  for(let i=1;i<b.path.length;i++)assert.equal(Math.abs(Math.floor(b.path[i]/b.cols)-Math.floor(b.path[i-1]/b.cols))+Math.abs(b.path[i]%b.cols-b.path[i-1]%b.cols),1);
  assert.equal(countSolutions(b.rows,b.cols,new Map([...b.clues].map(([i,n])=>[`${Math.floor(i/b.cols)},${i%b.cols}`,n]))),1,'independent solver confirms unique solution');
  density[difficulty]+=b.clues.size/b.path.length;
  paths.add(b.path.join(','));
}
assert(paths.size>60,'path generation must offer variety, not four mirrors of a snake');
assert(density.easy>density.normal && density.normal>density.hard,'higher levels give less help on average');
for(const difficulty of ['easy','normal','hard'])for(const length of [31,70,1500]){
  const b=letterBoard(0,length,2,difficulty,58);
  assert(b.path.length>=length+2);
  assert.equal(new Set(b.path).size,b.rows*b.cols);
  for(let i=1;i<b.path.length;i++)assert.equal(Math.abs(Math.floor(b.path[i]/b.cols)-Math.floor(b.path[i-1]/b.cols))+Math.abs(b.path[i]%b.cols-b.path[i-1]%b.cols),1);
  if(length<=70)assert.equal(countSolutions(b.rows,b.cols,new Map([...b.clues].map(([i,n])=>[`${Math.floor(i/b.cols)},${i%b.cols}`,n]))),1,'long letters remain unique across panel boundaries');
}
for(const patch of [{difficulty:'invalid',seed:1},{difficulty:'hard'},{difficulty:'hard',seed:-1},{difficulty:'hard',seed:1.5},{difficulty:'hard',seed:4294967296},{seed:1},{v:1,difficulty:'hard',seed:1}]){
  assert.throws(()=>encodeLetter({v:2,text:'あ',from:'',puzzle:0,...patch}));
}
console.log('PASS seeded difficulty variety, independent uniqueness, long-letter boundaries, and invalid difficulty payloads');
