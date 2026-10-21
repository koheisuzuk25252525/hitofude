// Run from any directory: node tests/native-generator.test.mjs
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import vm from 'node:vm';

const html = readFileSync(new URL('../index.html', import.meta.url), 'utf8');
const source = html.slice(html.indexOf('// ---------- seeded RNG'), html.indexOf('// ---------- worker'));
const bundled = readFileSync(new URL('../ios/Hitofude/Resources/Generator.js', import.meta.url), 'utf8');
const web = vm.createContext({});
const native = vm.createContext({});
vm.runInContext(source, web);
vm.runInContext(bundled, native);
let checked = 0;
for (const [size, difficulty] of [[5, 'easy'], [6, 'medium'], [7, 'hard'], [8, 'hard']]) {
  for (let seed = 1000; seed < 1000 + (size === 8 ? 2 : 5); seed++) {
    const expected = JSON.parse(vm.runInContext(`(() => {
      const p = makePuzzle(${size},${size},'${difficulty}',mulberry32(${seed}));
      return JSON.stringify({size:${size}, path:p.path.map(([row,column])=>({row,column})),
        clues:[...p.clues].map(([key,value])=>{const [row,column]=key.split(',').map(Number);return {row,column,value}})});
    })()`, web));
    const actual = JSON.parse(vm.runInContext(`nativePuzzle(${size},'${difficulty}',${seed})`, native));
    assert.deepEqual(actual, expected, `Web/native parity ${size} seed ${seed}`);
    assert.equal(new Set(actual.path.map(cell => `${cell.row},${cell.column}`)).size, size * size);
    const clues = JSON.stringify(actual.clues.map(({row, column, value}) => [`${row},${column}`, value]));
    assert.equal(vm.runInContext(`countSolutions(${size},${size},new Map(${clues}))`, native), 1);
    checked++;
  }
}
console.log(`ok ${checked} iOS generator cases: Web parity, valid paths, unique solutions`);
