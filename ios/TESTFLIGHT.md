# TestFlightに配るまで

## このPRで用意するもの

- SwiftUIアプリとXCTestをmain側でも管理できる構成
- 不透明・1024×1024のAppIcon、起動画面の自動生成設定、Version 1.0 / Build 1
- UserDefaultsをアプリ内保存に使う理由（CA92.1）を記載したPrivacyInfo.xcprivacy
- 現在の実装に合わせた非免除暗号不使用の設定。広告SDK・独自暗号処理はない。任意参加のFirebase Analyticsを使用する
- SimulatorでのXCTestと、実機用の署名なしRelease archiveのCI
- プライバシーポリシーとサポートページ、アプリの「あそびかた」からのリンク

CIのarchiveは署名・配信されない。App Store ConnectへのアップロードやTestFlight招待も自動では行わない。

## 1. 配布用の登録（所有者が一度だけ行う）

1. [Apple Developer Program](https://developer.apple.com/programs/)に登録する。無料のApple IDだけではTestFlight配布はできない。
2. App Store Connectが現在受け付けるSDKを含む、最新の安定版XcodeをMacに用意する。プロジェクトを開く最低条件の「Xcode 16以降」と、ストアが受け付けるSDK要件は別。
3. Xcode → Settings → AccountsでApple IDを追加する。
4. `ios/Hitofude.xcodeproj` → Hitofudeターゲット → Signing & Capabilitiesで自分のTeamを選び、Automatically manage signingを有効にする。
5. `com.example.hitofude` は開発用。自分のアプリ用の一意なBundle Identifierを決め、Debug/Releaseの両方へ設定する。すでに本番用IDで配布している場合は変更しない。Bundle IDが変わると別アプリになり、以前のローカル記録を引き継がない。
6. App Store Connect → マイApp → ＋ → 新規App。iOS、日本語、上記Bundle IDを選ぶ。SKUは自分が管理しやすい一意の値を決める。

Apple IDのパスワード、証明書、秘密鍵をリポジトリやチャットへ貼り付けない。Teamの設定はXcodeの画面で行える。

## 2. 配布前の確認

1. このPRを取り込んだリポジトリをMacへpullし、Xcodeで開く。以前の `codex/hitofude-swiftui-ios` だけをpullしても今回の変更は入らない。マージ後はmainを使う。ローカルで署名設定を変更している場合は、切り替え前にその差分を保存しておく。
2. Simulatorを選び ⌘U。続いて実機を選び ⌘R。
3. [DEVICE_TESTING.md](DEVICE_TESTING.md) の中断・復帰、ヒント、共有、鬼、VoiceOverを確認し、端末名・OS・コミット・結果を記録する。現在の実機欄は未実施。
4. iPhoneとiPadを対象にしている。小さいiPhone、iPad、文字拡大、縦横の表示を確認する。iPadを検証できないまま対応済みとは扱わない。
5. Pagesの公開後、次のURLが開けることと、記載内容が実際の運用に合っていることを確認する。
   - Privacy Policy URL: https://koheisuzuk25252525.github.io/hitofude/privacy.html
   - Support URL: https://koheisuzuk25252525.github.io/hitofude/support.html

これらのページはこのPRがマージされ、Pagesのデプロイが成功してから公開される。現時点の問い合わせ先は公開GitHub Issues。専用メールを使う場合は公開前にページを変更する。

## 3. Archiveとアップロード

1. Schemeは **Hitofude**、実行先は **Any iOS Device (arm64)** などの汎用iOSデバイスを選択する。
2. General → Version / Buildを確認する。最初は1.0 / 1。同じバージョンを再アップロードするときはBuildを2、3…と増やす。
3. Product → Archive。OrganizerでValidate Appを実行し、署名・アイコン・必須メタデータの指摘を解消する。
4. Distribute App → App Store Connect → Upload。認証・署名・配布は所有者のMacで行う。
5. 処理完了後、App Store ConnectのTestFlightタブでビルドを確認する。暗号・コンプライアンスの質問には現在の実装に基づいて回答する。将来SDKを追加した場合は再確認する。

## 4. テスターへ配る

- 内部テストはApp Store Connectの適切な権限を持つメンバー向け。一般の友人を試すためだけに管理権限を付けない。
- 友人5〜10人には外部テストグループを作り、ベータ版の説明、フィードバック先、審査連絡先などを入力する。外部配布にはAppleのBeta App Reviewが必要になる。
- 承認後に招待メールまたは公開リンクで配る。受け取る人はApp StoreからTestFlightをインストールする。XcodeやMacは不要。
- テスター募集・メール送信・公開リンクの有効化は、このPRでは行っていない。

### 「テスト内容」の文案

空き時間に一問遊んでみてください。

1. 途中でホーム画面へ移動し、戻って続きから遊べるか。
2. ヒントの目印が分かりやすく、連打しても余分に減らないか。
3. 指を速く動かしても、思ったマスを通れるか。
4. クリア後に時間を置いて共有しても記録が変わらないか。
5. 友だちの挑戦リンクをアプリに貼り付け、同じ問題で遊べるか。

不具合はTestFlightから、端末・OS・難易度・手順と一緒に送ってください。一問終えたときの感想や、次の空き時間にも開きたいかも教えてもらえるとうれしいです。

## ストア情報のたたき台

- 名前：ヒトフデ
- サブタイトル：数字をたよりに、ひと筆パズル
- 概要：1から指でなぞって、すべてのマスを一本の線につなぐパズル。さくっと一問、毎日の問題、友だちとのタイム対戦を、自分のペースで楽しめます。
- プライバシー申告：任意参加のFirebase Analyticsを追加済み。識別子・製品操作・おおよその地域など、SDKを含めたデータの種類と分析目的を確認して申告する。初期オフでも「データ収集なし」とは申告しない。App Store Connectの各質問には実装とポリシーを確認して回答する。TestFlightや共有先サービスの処理とは区別する。
- 未用意：所有者の審査連絡先、署名情報、実機の確認結果、ストア用の実際のスクリーンショット。これらを架空の内容で埋めない。

Universal Linksは未設定。挑戦リンクのタップで開くのはWeb版で、アプリ参加時は「リンクで対戦」に貼り付ける。端末間同期・Web版からの記録移行・ランキングはない。

計測の有効化と管理画面での確認は [ANALYTICS.md](ANALYTICS.md) を参照してください。
