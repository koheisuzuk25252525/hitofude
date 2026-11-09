// Refresh the offline bank with the unchanged seeded generator.
// Slow seeds are skipped, never simplified. Runtime failures use another real seed.
import {readFileSync, writeFileSync} from 'node:fs';
import vm from 'node:vm';
const file = new URL('../ios/Hitofude/Resources/Generator.js', import.meta.url);
const marker = '// ---------- prepared puzzles (generated; do not edit) ----------';
const source = readFileSync(file, 'utf8').split(marker)[0];
const context = vm.createContext({});
vm.runInContext(source, context);
const bank = {};
for (const [size, difficulty] of [[5,'easy'],[6,'medium'],[7,'hard'],[8,'hard']]) {
  const entries = [];
  for (let seed = 1000; entries.length < 16 && seed < 1200; seed++) {
    try {
      const puzzle = JSON.parse(vm.runInContext(`nativePuzzle(${size},'${difficulty}',${seed})`, context, {timeout: 2500}));
      entries.push({seed, puzzle});
    } catch { /* Keep the generator and difficulty unchanged; try the next seed. */ }
  }
  if (entries.length !== 16) throw new Error(`Not enough ${size}x${size} puzzles`);
  bank[`${size}-${difficulty}`] = entries;
  console.log(`${size}x${size}: ${entries.length} prepared puzzles`);
}
writeFileSync(file, source + marker + '\nconst preparedPuzzles = ' + JSON.stringify(bank) + ';\n');
