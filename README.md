# ヒトフデ

一筆書きロジックパズル。1 から指でなぞり、すべてのマスを1回ずつ通って、いちばん大きい数字で終わる。

- きょうの1問（毎日同じ問題）・やさしい／ふつう／むずかしい／鬼（8×8）
- ヒント、チュートリアル、ストリークとカレンダー、Wordle風の共有、挑戦リンクでの対戦
- 効果音は端末内で合成、12言語のカウント音声

## 動かす
`index.html` をブラウザで開くだけ。公開は GitHub Pages（Settings → Pages → Source を「GitHub Actions」）。

## テスト
```
node tests/generator.test.mjs
```

## 公開前の確認

`node tests/generator-compatibility.test.mjs` は、変更前のmainで採取した12個の問題（seed 0 / 1000 / UInt32最大値）が同じ経路・手がかりになることを確認します。

Node.js 22以降とChromiumがある環境では、依存パッケージなしでブラウザ回帰テストを実行できます。

```sh
node tests/ui.test.mjs
# Chromeを使う場合
CHROMIUM_PATH=/path/to/google-chrome node tests/ui.test.mjs
# 375 / 390 / 430pxのライト・ダークのスクリーンショットも保存する場合
UI_SCREENSHOT_DIR=/tmp/hitofude-review node tests/ui.test.mjs
```

制作者名・作品一覧リンクの設定、OGP画像の更新、実機確認は [公開チェックリスト](docs/RELEASE_CHECKS.md) を参照してください。
