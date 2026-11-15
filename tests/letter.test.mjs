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
const max={v:1,text:'🌸'.repeat(120),from:'名'.repeat(20),puzzle:3};
assert.deepEqual(decodeLetter(encodeLetter(max)),max);
for(const patch of [{v:2},{text:''},{text:' '},{text:'x'.repeat(121)},{from:'x'.repeat(21)},{from:'a\nb'},{text:'\0'},{puzzle:4},{puzzle:-1},{puzzle:0.5},{text:123}]){
  const value={...max,...patch};
  assert.throws(()=>encodeLetter(value));
  assert.equal(decodeLetter('#letter='+Buffer.from(JSON.stringify(value)).toString('base64url')),null);
}
for(const hash of ['#letter=%%%','#letter=_w','#letter=e30','#letter='+ 'a'.repeat(3000),'#other=abc'])assert.equal(decodeLetter(hash),null);
console.log('PASS letter Unicode boundaries, untrusted payload validation, and all four uniquely solvable boards');
