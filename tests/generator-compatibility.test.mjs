// Fingerprints captured from main (c4c8bd9), before release-quality changes.
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {createHash} from 'node:crypto';
const html=readFileSync(new URL('../index.html',import.meta.url),'utf8');
const source=html.slice(html.indexOf('// ---------- seeded RNG'),html.indexOf('// ---------- worker'));
const api=new Function(source+'\nreturn {mulberry32,makePuzzle}')();
const fixtures=[
  [
    5,
    "easy",
    0,
    "b691ccb02e49cd9762c2acb79bdf6cdc13739cb6529447d622766d73ae27c215"
  ],
  [
    5,
    "easy",
    1000,
    "3f5e01b4183e1174fb6b957a97d922e8eaf5361056eab2c2bd5942cfadd7848b"
  ],
  [
    5,
    "easy",
    4294967295,
    "51e75249471b924952da4692575617cc4bda48868b329bf3f68a9fe312e768bc"
  ],
  [
    6,
    "medium",
    0,
    "3ce1da7493c0dfad6d820480931e755e35d317229179de5d7555aeae7f3d969d"
  ],
  [
    6,
    "medium",
    1000,
    "9e566a3c6ec100ae80e529de796d64f37a722ad26de2c9a3871200153df70779"
  ],
  [
    6,
    "medium",
    4294967295,
    "fab32d7a8afac053b369193ab2ba081a47a66508f5fd84e571612c44f38ebe6c"
  ],
  [
    7,
    "hard",
    0,
    "977c690367f395872f43fa8884190dd2ff13d47c9b6ff571932efeae6913c9e0"
  ],
  [
    7,
    "hard",
    1000,
    "f76c7e999db39fe1cc9077655f1cce3ee4a7055b195dafa9c09f711b8f097ae3"
  ],
  [
    7,
    "hard",
    4294967295,
    "75431a41ee3b3ab944802d09cbfcee424062265e6faeacb78ccfefd06ecccec6"
  ],
  [
    8,
    "hard",
    0,
    "f50db12155b391a8ec269517ca07b662aea8713a0582e2297f32bc155c2aea2f"
  ],
  [
    8,
    "hard",
    1000,
    "6116dd3abe9e8e595775e5b5d3c7a5bd9572b2988d561b063197bf92f9f45460"
  ],
  [
    8,
    "hard",
    4294967295,
    "af0a8502f4ade554a6459442cbf74cd43e0dac0754aa086b3bebe6c5d1ab7f10"
  ]
];
for(const [size,difficulty,seed,expected] of fixtures){
 const p=api.makePuzzle(size,size,difficulty,api.mulberry32(seed));
 const data=JSON.stringify({path:p.path,clues:[...p.clues].sort(([a],[b])=>a<b?-1:a>b?1:0)});
 assert.equal(createHash('sha256').update(data).digest('hex'),expected,`seed compatibility: ${size} ${difficulty} ${seed}`);
}
console.log(`ok ${fixtures.length} main seed-compatibility fixtures`);
