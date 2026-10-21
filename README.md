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

## iOSアプリ（SwiftUI）

MacのXcode 16以降で `ios/Hitofude.xcodeproj` を開き、HitofudeのSchemeとiPhone Simulatorを選んで実行できます（iOS 17以降）。起動・実機へのインストール・テスト・実装範囲は [iOS版の手順](ios/README.md) を参照してください。

Web版とiOS同梱の問題生成器の一致は `node tests/native-generator.test.mjs` で検証できます。
