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
process.exit(fail ? 1 : 0);
