# ヒトフデ — SwiftUI版

iOS 17以降、iPhone / iPad向けのネイティブアプリです。画面はSwiftUI、問題生成はApple標準のJavaScriptCoreを使い、通信せず端末内で動きます。WebViewや外部パッケージは使用していません。

## Xcodeで遊ぶ

1. MacのXcode 16以降で `ios/Hitofude.xcodeproj` を開く。
2. Schemeで **Hitofude**、実行先でインストール済みの **iPhone Simulator** を選ぶ。
3. **⌘R** で起動。最初は4×4の練習問題が表示されます。
4. 1から上下左右になぞるか、マスを順番にタップします。すべてのマスを通り、16で終わるとクリアです。

実機で試す場合は、アプリターゲットの **Signing & Capabilities → Team** で自分のApple IDのチームを選び、Bundle Identifierの `com.example.hitofude` を自分用の一意な値に変更します。接続したiPhoneを実行先に選び、必要に応じて端末のDeveloper Modeを有効にして実行してください。Simulatorではチーム設定は不要です。

## 実装内容

- 練習、きょうの1問、やさしい、ふつう、むずかしい、鬼
- 指なぞり・タップ・ひとつ前のマスへの後戻り
- 数字と通過順序のチェック、ヒント3回、取り消し、やり直し
- タイマー、難易度ごとのベスト記録、練習完了と今日の結果の端末内保存
- クリア表示、結果テキストの共有、触覚フィードバック
- ライト／ダーク、VoiceOver用のマスの説明、画面サイズに合わせた盤面
- バックグラウンドでの問題生成とエラー時の再試行

日付seedは端末のローカル日付を使い、Web版と同じYYYYMMDDです。同じseed・難易度ではWeb版と同じ問題になります。Web版の音声読み上げ、効果音、カレンダー表示、対戦リンクの読み込み、途中経路の保存はこの初版には含めていません。Web版のlocalStorageは引き継ぎません。アプリアイコンやApp Store配信用の設定は配布前に追加してください。

## テスト

Xcodeで **⌘U**。XCTestは生成器17ケースの一意解・再現性、練習問題の不正操作・クリア・保存、ヒントと取り消し、日付seedを検証します。

コマンドラインではMac上で、まず利用可能なSimulatorを確認します。

```sh
xcodebuild -project ios/Hitofude.xcodeproj -scheme Hitofude -showdestinations
xcodebuild -project ios/Hitofude.xcodeproj -scheme Hitofude \
  -destination 'platform=iOS Simulator,id=<表示されたSimulatorのID>' test
```

Linuxでも生成器のWeb/iOS一致を確認できます。

```sh
node tests/generator.test.mjs
node tests/native-generator.test.mjs
```

このクラウド環境にはXcode・Swiftがないため、iOSビルド、XCTest、Simulator、iPhone実機での操作・VoiceOver確認は未実施です。Nodeでの検証をiOS実行成功として扱わないでください。

## 生成器を更新するとき

`Resources/Generator.js` は `index.html` のseeded RNG / generator部分を同じ動作のまま同梱し、末尾の `nativePuzzle` でSwiftにJSONを返します。生成器を変更する場合は両方を同期し、上記NodeテストとXCTestを実行してください。生成器はJavaScriptCoreのローカルコンテキスト内で完結し、インターネット接続は不要です。
