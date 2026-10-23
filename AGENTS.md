# AGENTS.md — ヒトフデ

数字の手がかりをたよりに全マスを一筆でなぞるパズル。スマホのブラウザで遊ぶ前提。
Codex・Claude など複数のAIエージェントが同じリポジトリで作業する。この文書が共通ルール。

## 構成
- `index.html` … アプリ本体。HTML・CSS・JS をこの1ファイルに収める（ビルド工程なし、外部ライブラリなし）
- `tests/generator.test.mjs` … 生成器の一意解チェック（`node tests/generator.test.mjs`）
- `.github/workflows/pages.yml` … main への push で GitHub Pages に公開

## 主要な仕組み（index.html 内の区切りコメント順）
- `seeded RNG` / `generator` … `makePuzzle(R,C,difficulty,rnd)`。ランダムなハミルトン路 → 手がかりを最小化 → 難易度で足し戻す。`countSolutions` で一意性を保証
- `worker` … 8×8（鬼）は数秒かかるので Blob Worker で生成
- `audio` … WebAudio で効果音を合成（音源ファイルなし）。1手目 C3 → 最終手 C7 に連続上昇
- `voice` … Web Speech で一歩ごとに日本語で数える
- `game state` / `input` … Pointer Events で指なぞり。`route` が現在の経路
- 対戦は URL ハッシュ `#c-<mode>-<seed>-<秒>` で同じ問題を再現する非同期方式
- 保存は localStorage（キー接頭辞 `hitofude:`）。読み書きは必ず try/catch 経由の `store`

## ルール
- UI文言は日本語。短く、やさしい言葉で
- 生成器を変えたら `node tests/generator.test.mjs` が通ること
- 同じ seed から同じ問題が出ること（きょうの1問・対戦リンクが壊れる）を崩さない
- 色はすべて `:root` の CSS 変数経由。ライト／ダーク両方で確認
- iPhone Safari を最優先で確認（音は touchend/click で解禁、マナーモード対策あり）
- 1つのPRは1つの目的に絞る
