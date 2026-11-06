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
    // Parity alone would miss a malformed route shared by both implementations.
    assert.equal(actual.path.length, size * size, `path length ${size} seed ${seed}`);
    for (const [index, cell] of actual.path.entries()) {
      assert.ok(Number.isInteger(cell.row) && Number.isInteger(cell.column)
        && cell.row >= 0 && cell.row < size && cell.column >= 0 && cell.column < size,
      `path cell in bounds: ${size} seed ${seed} step ${index + 1}`);
      if (index > 0) {
        const prev = actual.path[index - 1];
        assert.equal(Math.abs(cell.row - prev.row) + Math.abs(cell.column - prev.column), 1,
          `orthogonal step: ${size} seed ${seed} step ${index + 1}`);
      }
    }
    assert.equal(new Set(actual.path.map(cell => `${cell.row},${cell.column}`)).size, size * size);
    const clueNumbers = new Set();
    for (const clue of actual.clues) {
      assert.ok(Number.isInteger(clue.value) && clue.value >= 1 && clue.value <= size * size,
        `clue number in range: ${size} seed ${seed}`);
      assert.ok(!clueNumbers.has(clue.value), `duplicate clue number: ${size} seed ${seed}`);
      clueNumbers.add(clue.value);
      assert.deepEqual({row:clue.row, column:clue.column}, actual.path[clue.value - 1],
        `clue matches route position: ${size} seed ${seed} clue ${clue.value}`);
    }
    assert.ok(clueNumbers.has(1) && clueNumbers.has(size * size),
      `start and finish clues: ${size} seed ${seed}`);
    const clues = JSON.stringify(actual.clues.map(({row, column, value}) => [`${row},${column}`, value]));
    assert.equal(vm.runInContext(`countSolutions(${size},${size},new Map(${clues}))`, native), 1);
    checked++;
  }
}
console.log(`ok ${checked} iOS generator cases: Web parity, valid paths, unique solutions`);

assert.throws(() => vm.runInContext("nativePuzzle(8,'hard',1000,0)", native), /timed out/);
assert.doesNotThrow(() => JSON.parse(vm.runInContext("nativePuzzle(5,'easy',1000)", native)));
console.log('ok generation deadline and recovery');
