// node tests/generator.test.mjs — 生成器が全難易度で一意解を返すか確認する
import { readFileSync } from 'node:fs';
const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const js = html.slice(html.indexOf('// ---------- seeded RNG'), html.indexOf('// ---------- worker'));
const api = new Function(js + '\nreturn {mulberry32, makePuzzle, countSolutions};')();
let fail = 0;
for (const [R, C, d] of [[5,5,'easy'],[6,6,'medium'],[7,7,'hard'],[8,8,'hard']]) {
  for (let k = 0; k < (R === 8 ? 2 : 5); k++) {
    const p = api.makePuzzle(R, C, d, api.mulberry32(1000 + k));
    const n = api.countSolutions(R, C, p.clues);
    if (n !== 1) { fail++; console.error(`NG ${R}x${C} ${d} seed ${1000+k}: ${n} solutions`); }
  }
  console.log(`ok ${R}x${C} ${d}`);
}
// A solver that always returns 1 would let the generated-puzzle checks pass.
// Verify the 0 / 1 / 2 (capped) cases independently, without changing any game data.
const solverCases = [
  ['ambiguous puzzle', 3, 3, [['0,0',1], ['2,2',9]], 2],
  ['impossible puzzle', 3, 3, [['0,0',1], ['0,1',9]], 0],
  ['unique puzzle', 2, 2, [['0,0',1], ['1,0',4]], 1],
  ['missing endpoint', 3, 3, [['0,0',1]], 0],
];
for (const [name, R, C, entries, expected] of solverCases) {
  const clues = new Map(entries);
  const before = JSON.stringify([...clues]);
  const actual = api.countSolutions(R, C, clues);
  if (actual !== expected || JSON.stringify([...clues]) !== before) {
    fail++;
    console.error(`NG ${name}: expected ${expected}, got ${actual} (clues must stay unchanged)`);
  } else {
    console.log(`ok solver: ${name}`);
  }
}
process.exit(fail ? 1 : 0);
