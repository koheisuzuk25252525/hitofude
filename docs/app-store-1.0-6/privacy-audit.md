# ヒトフデ 1.0（6）— プライバシー・広告・掲載内容の確認資料

確認日：2026年11月22日（日本時間）

この資料は App Store Connect への回答案を作るためのソース確認結果です。管理画面への入力・送信、アプリの再ビルド、既存ブランチ・PR・審査設定の変更は行っていません。

## 対象と証拠の範囲

| 対象 | 確認したもの | この資料では確認できないもの |
|---|---|---|
| 初回公開のネイティブアプリ | 提出候補 `a04cd41237d4d74b382222aec60ad6c970fda8e2` のコード。Version 1.0 / Build 6 | 所有者が実際にアップロードした Archive の内容、署名、同梱 Firebase 設定、Privacy Report |
| 公開 Web 機能 | GitHub の `main`、`797690efeb9cb375da7f35baf9a58ae5bb595f49` のソース | GitHub Pages 上で同じ内容が配信されているか、ユーザー端末での表示・通信 |
| 次期開発の警告修正 | `5086f9a` は別ブランチ。提供された画像では Xcode Cloud Build 3 成功・問題なし | 広告ヒントの修正後実機動作。この結果を公開ビルド6の実機確認に代用しない |

GitHub Pages、Google・Firebase の資料ページへの直接アクセスは、この実行環境のネットワークで 403 になりました。GitHub API と raw GitHub のソースは取得できています。以下の SDK データ項目は、取得できたアプリ実装・マニフェスト・既存設計資料と、まだ照合が必要な項目を区別しています。

## 実装から確認できたこと

1. **通常のパズルは端末内で動く。** 経路、記録、ヒント、設定は UserDefaults に保存し、アプリ独自のアカウント登録・クラウド同期はありません。UserDefaults の使用理由 `CA92.1` が PrivacyInfo.xcprivacy に記載されています。端末のバックアップは別です。
2. **Firebase Analytics は任意参加・初期オフ。** 正しい Bundle ID の `GoogleService-Info.plist` が Archive に入っていて、利用者が計測を有効にした場合だけ初期化・送信します。オフ時には収集停止とローカル Analytics データのリセットを行います。これは送信済みデータのサーバー削除ではありません。
3. **独自の計測イベントに、手紙本文・氏名・メール・パズルの答え・経路は入っていません。** 難易度、進捗、時間、ヒント数、道案内使用、対戦の有無、一回の挑戦を区別するIDなどは含みます。SDKの標準処理とは分けて考えます。
4. **広告とプレイ計測の同意は別です。** 通常ゲーム画面の表示時に UMP の情報更新が走ります。広告を見る操作の後、同意フォーム処理と `canRequestAds` の確認を経て Google Mobile Ads を開始し、`npa=1` を指定します。広告を選ばなくても UMP の通信まで一切ない、とは説明できません。
5. **本番広告IDと切替処理は既にあります。** Debug／TestFlight／未検証環境はテスト広告。検証済み StoreKit AppTransaction が production の場合だけ本番ユニットを使用します。公開のためだけにテストIDを書き換える必要はありません。
6. **ATT要求の実装はなく、Firebaseの広告利用も抑制しています。** Firebase Analytics の adStorage／adUserData／adPersonalization は拒否、IDFV収集と自動画面報告は Info.plist で無効化されています。ただし、これだけで全 SDK の「データ収集なし」「関連付けなし」「トラッキングなし」を確定することはできません。
7. **広告の報酬は SDK の earned-reward コールバックから一度だけ付与する実装です。** 実際の端末で、報酬取得前の中断や通信失敗がどうなるかは別途確認します。

主な根拠：

- [PlayAnalytics.swift（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/PlayAnalytics.swift#L15)：設定ファイル条件、同意、送信制御。
- [GameModel.swift（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/GameModel.swift#L431)：独自イベントのパラメータ。
- [RewardedHints.swift（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/RewardedHints.swift#L6)：広告切替、UMP、広告要求、報酬処理。
- [GameView.swift（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/GameView.swift#L259)：起動後の広告同意情報更新。
- [Info.plist（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/Info.plist)、[PrivacyInfo.xcprivacy（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/Hitofude/Resources/PrivacyInfo.xcprivacy)。
- [copy-firebase-config.sh（提出候補）](https://github.com/koheisuzuk25252525/hitofude/blob/a04cd41237d4d74b382222aec60ad6c970fda8e2/ios/copy-firebase-config.sh)：所有者の任意設定ファイルをビルド時に同梱する条件。

## App Store「Appのプライバシー」の回答下書き

**この表をそのまま確定回答として送信しないでください。** 「SDKを使っているから全項目をオン」「非パーソナライズ広告だから全部オフ」のどちらでもなく、アップロード済み Archive のレポートと実際の管理設定を照合して確定します。任意参加の収集も確認対象です。

| データ項目の候補 | 分かっている用途・処理 | ソース上の関連付け／トラッキング | 確定前に確認すること |
|---|---|---|---|
| 使用状況データ → 製品の操作 | 計測オン時に開始・ヒント・クリア・中断などを Analytics へ送信。目的は分析 | アプリのマニフェストは「関連付けあり・トラッキングなし」と宣言 | ビルド6の Firebase 設定同梱の有無、Analytics 管理設定。独自イベント以外の SDK 標準処理も確認 |
| 識別子 → デバイスID | Firebase のインストール識別子などが確認対象。独自の挑戦IDはアカウントIDではない | アプリのマニフェストは分析目的・関連付けあり・トラッキングなし | 広告 SDK が扱う識別子を含めた実際の種類・用途。IDFAを要求しないことと、他の識別子も収集しないことを混同しない |
| 位置情報 → おおよその位置情報 | Firebase による IP に基づく地域の処理をポリシーが説明。広告・UMP 側の IP 処理も照合対象 | アプリのマニフェストは分析目的・関連付けあり・トラッキングなし | SDK／プロパティ設定ごとの保持・利用。GPS の許可を要求しないことだけで「位置情報なし」としない |
| 使用状況データ → 広告データ | 任意リワード広告の表示・操作に関するデータを公開ポリシーが説明。第三者広告の目的が確認対象 | アプリ独自マニフェストにはこの項目なし。SDK のマニフェスト・資料との照合が必要 | Google Mobile Ads 12.14.0 のデータ開示、Archive の集約レポート、AdMob 側の配信設定で種類・関連付け・目的を確認 |
| 診断 → クラッシュ／パフォーマンス／その他診断データ | 公開ポリシーは広告 SDK の診断情報を説明 | アプリ独自マニフェストだけでは分類や関連付けを確定できない | SDK が実際に扱う診断の種類と目的を確認。Crashlytics がないという理由で他 SDK の診断処理もないとしない |
| その他のデータ等に該当する同意情報 | UMP に地域・同意の更新要求を送る。広告表示を選ぶ前の更新もある | アプリコードだけでは App Store の分類を特定できない | UMP 3.1.0 のデータ処理を資料と Archive のレポートで照合。存在しない「同意情報」専用項目を作らない |
| ユーザーコンテンツ → カスタマーサポート等 | 利用者が報告文を共有したり GitHub に投稿する。公開サポートページには問い合わせメールもある | 自動の Analytics 送信はない。公開投稿やメールで運営者が受け取る情報とは別 | 実際の問い合わせ運用、Apple の任意開示例外の条件への適合を確認。任意だから必ず申告不要、とは扱わない |
| ユーザーコンテンツ → 手紙本文、名前 | 下記の Web 機能。本文・任意の名前は URL フラグメントに入り、共有先へ渡る | 確認した Web コードに運営側の本文データベースや計測送信はない | 自社で本文を収集するサービスだと誤記しない。ホスティングのアクセス処理、外部共有先での保存と区別する |
| 端末内のパズル経路・記録・設定 | アプリ内保存・復元に使用 | 自動の外部送信は確認していない（上記の集計イベントは別） | 端末内処理を、独自のクラウド収集・同期と表記しない |

現在のアプリ独自マニフェストは **DeviceID／ProductInteraction／CoarseLocation の3種類を、分析目的・関連付けあり・トラッキングなしで宣言**しています。Google Mobile Ads 等の全処理をこの3種類だけで網羅したと結論付けることはできません。SDK のマニフェストを集約した Archive の Privacy Report と併せて扱います。

Firebase は 12.4.0 の FirebaseAnalyticsCore と FirebaseCore、Google Mobile Ads は 12.14.0、UMP は 3.1.0 を指定しています。所有者の Firebase 設定ファイルは Git 管理対象外のため、リポジトリのファイル一覧からアップロード済みアプリの同梱有無を判定できません。ビルド6で「プレイ状況の計測」のスイッチが利用可能かを見ると運用確認の手掛かりになりますが、Archive の確認も必要です。

照合先：

- [Apple：App privacy details](https://developer.apple.com/app-store/app-privacy-details/)
- [Google Mobile Ads：App Store data disclosure](https://developers.google.com/admob/ios/privacy/data-disclosure)
- [Firebase：App Store data collection details](https://firebase.google.com/docs/ios/app-store-data-collection)
- [Google Mobile Ads：Privacy](https://developers.google.com/admob/ios/privacy)

これらは最終照合先のリンクです。今回の環境から最新版の本文を取得できていないため、閲覧済みの根拠として引用していません。

## 手紙機能・公開ポリシー・サポートの照合

ネイティブ1.0（6）は「…」→「一筆の手紙」で SFSafariViewController に公開 Web を表示します。アプリに埋め込まれた古いページで動く方式ではないため、公開 Web の実際の内容と切り分けます。

- GitHub の Web `main` の `letter.js` は本文と任意の送り手名を JSON → Base64URL にし、共有リンクの `#letter=` 以降へ入れます。これは暗号化ではありません。通常のページ取得時にフラグメント自体は HTTP リクエストへ送られませんが、共有先にはリンク全体が渡ります。
- 確認した手紙コードに、本文を送信する `fetch`、運営の手紙サーバー、アカウント、広告・Analytics、独自の永続下書き保存はありません。受信表示には `textContent` を使用しています。ブラウザ履歴・復元機能や送信先での保存まで否定するものではありません。
- リンクを知っている人は本文を読めます。「解かずに手紙を読む」もあります。閲覧者を本人確認する仕組み、送信後のリンク無効化・取消・相手側削除はありません。作成画面の注意書きと公開ポリシーの手紙項目にこれらの説明があります。
- Web `main` のプライバシーポリシーは更新日 2026年11月15日で、上記の手紙項目を含みます。一方、提出コミット内の古い `privacy.html` は11月13日です。**古いファイルだけを見て、現行ポリシーに手紙の説明がないと判断しない**でください。ネイティブアプリのリンク先はホストされたページです。
- Web `main` のサポートページには GitHub Issues に加え `minnano.idea.game@gmail.com` のメール窓口が記載済みです。新しい連絡先を推測して作る必要はありません。受信できるか、誰が確認するかは所有者の運用確認です。
- `letter-links.js` の `appStoreURL` と `testFlightURL` は現在空です。入手ボタンは実URLを設定したときだけ表示する実装です。公開 App Store ページを確認できたらそのURLを設定するのが適切です。ビルド6の再 Archive は必要ありません。インストール後は元の手紙リンクをもう一度開く方式で、自動引継ぎはありません。

根拠：Web コミット `797690efeb9cb375da7f35baf9a58ae5bb595f49` の [privacy.html](https://github.com/koheisuzuk25252525/hitofude/blob/797690efeb9cb375da7f35baf9a58ae5bb595f49/privacy.html)、[support.html](https://github.com/koheisuzuk25252525/hitofude/blob/797690efeb9cb375da7f35baf9a58ae5bb595f49/support.html)、[letter.html](https://github.com/koheisuzuk25252525/hitofude/blob/797690efeb9cb375da7f35baf9a58ae5bb595f49/letter.html)、[letter.js](https://github.com/koheisuzuk25252525/hitofude/blob/797690efeb9cb375da7f35baf9a58ae5bb595f49/letter.js)、[letter-links.js](https://github.com/koheisuzuk25252525/hitofude/blob/797690efeb9cb375da7f35baf9a58ae5bb595f49/letter-links.js)。

## 年齢区分・掲載文・審査メモの下書き

- **広告を含む：はい、任意のリワード広告あり。** 「広告なし」「完全オフライン」とは掲載しません。通常のパズルはオフラインで遊べ、広告と手紙は通信が必要、と分けて説明します。
- **課金：現時点のゲーム機能にアプリ内課金はありません。** StoreKit は広告の本番環境判定に使っています。StoreKit の import だけを見て購入機能があると扱いません。
- **ユーザーが入力する内容：手紙の本文・送り手名、任意の不具合報告があります。** 年齢区分のユーザー生成コンテンツ・共有／メッセージ関連の質問は、この仕様に沿って回答します。SNSの公開投稿一覧、匿名マッチング、アプリ内受信箱、運営による手紙配信があると説明しません。一方、自由入力があるのに「誰かが入力した文章は一切表示しない」ともしません。
- **年齢区分の数値は未確定。** 通常パズルの内容だけで4歳以上などと決めず、実際の App Store Connect の質問と広告設定を確認します。必要な広告コンテンツ制限も AdMob 側と整合させます。
- **手紙機能を理由に、直ちにSNS相当の新機能一式が必須と断定しません。** 仕様を審査メモに説明し、実際の質問・指摘に合わせて対応します。新規の通報サーバー・アカウント・受信箱の開発を初回公開の前提にしません。
- **対応機種：iPhone／iPad。** 提出候補の `TARGETED_DEVICE_FAMILY` は `1,2` です。スクリーンショットと操作確認はこの対応範囲と合わせます。
- **掲載できる説明：** 「数字をたよりに、すべてのマスをひと筆でつなぐパズル」「難易度を選んで一問」「友だちと同じ問題でタイムを比べる」「言葉をパズルに包んで送る」。グローバルランキング、リアルタイム対戦、アカウント同期、暗号化された秘密の手紙は実装済み機能として掲載しません。

審査メモ用の文章案：

> アカウント登録・ログインは不要です。初回の2段階チュートリアルを終えると通常のパズルを遊べます。通常ヒントは1問につき3回です。使い切った後に「道案内」を選ぶと、任意のリワード広告を経て次の数字まで最大6マスを案内します。広告を見ずに通常プレイを続けることもできます。右上の「…」から広告のプライバシー設定、任意のプレイ状況の計測、問い合わせへ移れます。「一筆の手紙」は同メニューから開くWeb機能です。利用者が入力した言葉を共有リンクに含め、本人が選んだメッセージアプリ等で送ります。運営が手紙を蓄積するデータベースや、アプリ内の公開投稿一覧・受信箱はありません。手紙の作成・受け取りには通信が必要です。

審査担当者の連絡先や実際の管理画面の回答は、この資料では登録していません。

## 残る確認（実施済みと混同しない）

1. アップロード済み1.0（6）の Archive の Privacy Report、GoogleService-Info.plist 同梱有無を確認し、SDK開示資料・AdMob／Firebase設定と表を照合する。
2. App Store Connect に入力済みのプライバシー回答、年齢区分、価格・配信地域、掲載内容、審査連絡先と選択ビルドを照合する。ここでは現状を未確認とする。
3. 実際の公開URLでプライバシー・サポート・手紙ページが開くことを確認する。raw GitHub の取得成功だけでは配信成功と断定しない。
4. 公開候補1.0（6）の実機で、計測オフ／オン／オフ、広告の完了・報酬取得前の中断・通信失敗、対象地域の同意設定、手紙の送受信を確認する。既に確認した操作は結果を記録し、すべてを無条件に繰り返す必要はない。
5. 公開ページが利用可能になったら、Web手紙ページのインストール先と AdMob のストア情報を実URLで設定する。初回公開の準備のためだけに自動 TestFlight 配信を有効にしない。

広告ID、SDK、収集設定、ネイティブ挙動に変更が必要だと判明した場合は、1.0（6）をそのまま維持したまま変更できると装いません。その場合だけ、修正内容と新ビルドの要否を別途判断します。
