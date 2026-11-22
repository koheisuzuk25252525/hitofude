# Web公開準備の検証結果

実施日：2026年11月22日（日本時間）

## 対象と結果

- 対象は公開Web版のソース `797690efeb9cb375da7f35baf9a58ae5bb595f49`。
- GitHubのコミットアーカイブを `/workspace/release-preparation/web-source` に展開し、既存の作業ブランチ・main・PRを変更せずに検証した。
- 既存の **6テストスイートがすべて成功**。内訳は通常Web UI **62項目**、手紙UI **59項目**（合計121項目）、手紙データ・生成ロジック、Web/iOS生成器の互換性、固定シード互換性、通常問題生成器。
- HTML内の相対リンク・参照先 **13件** をソース上で確認し、存在しない参照先は **0件**。
- 実行環境：Node.js `v24.19.0`、Linux Chromium。テスト用のローカルサーバーとブラウザは各スイートの終了処理で停止済み。
- この結果は **Web機能と生成ロジックの検証**。TestFlight 1.0（6）の実機操作、iPhone Safari、iOS広告SDK、ストア審査の成功を意味しない。

## 実行したコマンド

作業ディレクトリ：`/workspace/release-preparation/web-source`

```sh
node tests/letter.test.mjs
CHROMIUM_PATH=/usr/bin/chromium node tests/letter-ui.test.mjs
CHROMIUM_PATH=/usr/bin/chromium node tests/ui.test.mjs
node tests/native-generator.test.mjs
node tests/generator-compatibility.test.mjs
node tests/generator.test.mjs
```

| 検証 | 結果 | 証拠 |
|---|---|---|
| 手紙データ・盤面生成 | 成功。Unicode・不正リンク拒否・旧v1互換・文字数対応・難易度別の生成と独立ソルバーによる一意解を確認。難易度別24シード×3段階の72盤面を含む。 | [letter-tests.log](evidence/letter-tests.log) |
| 手紙UI | 59項目成功。タッチ操作による完成、本文の表示、共有キャンセル・コピー失敗時の復帰、長文、難易度、320/390/430px幅、ダーク表示・視差効果軽減の検証を含む。 | [letter-ui-tests.log](evidence/letter-ui-tests.log) |
| 通常Web UI | 62項目成功。各難易度の表示、ライト・ダーク、共有、固定された結果、対戦リンク互換、生成失敗からの復帰など。 | [web-ui-tests.log](evidence/web-ui-tests.log) |
| Web/iOS生成ロジック | 17ケース成功。経路の妥当性・一意解・Webとの一致、および生成期限と復帰処理。iOSネイティブ画面や広告の試験ではない。 | [native-generator-tests.log](evidence/native-generator-tests.log) |
| 固定シード互換 | 12ケース成功。既存リンクの問題再現を確認。 | [generator-compatibility-tests.log](evidence/generator-compatibility-tests.log) |
| 通常問題生成器 | 5×5、6×6、7×7、8×8と、曖昧・不可能・一意・終点不足のソルバー例が成功。 | [generator-tests.log](evidence/generator-tests.log) |
| HTML相対リンク | 13件、参照先欠落0件。 | [local-link-audit.json](evidence/local-link-audit.json) |

## 公開ソースとデプロイ状況

GitHub APIを読み取りで確認した結果：

1. ヒトフデ本体のPages実行 [43738172368](https://github.com/koheisuzuk25252525/hitofude/actions/runs/43738172368) は対象コミット `797690ef...` で `test` / `deploy` ともに成功。
2. ドメイン直下用リポジトリ `koheisuzuk25252525.github.io` のmainは `7185255a4b0517abc93e2f2ade4a17e124261b8f`。Pagesの最新ビルドは同コミットで `built`、エラーなし。
3. ドメイン直下用ソースの `app-ads.txt` は次の正しい広告販売者情報を含む。

```text
google.com, pub-2673589317149443, DIRECT, f08c47fec0942fa0
```

4. `.well-known/apple-app-site-association` のソースに、アプリID `93749WHY5S.com.koheisuzuk25252525.hitofude` と `/hitofude/letter.html` があり、`inApp=1` は除外されている。
5. 公開Web版の `privacy.html` は2026年11月15日更新で、任意の計測、広告・同意、一筆の手紙のURL共有・非暗号化・削除制限を記載している。
6. `support.html` に、GitHub Issuesと **minnano.idea.game@gmail.com** の連絡先がある。今回メールの送信や受信確認はしていない。
7. `letter-links.js` の `appStoreURL` / `testFlightURL` は空。公開前の状態として不正なリンクを出さない設計。実際のApp Storeページが開ける段階でURLを設定する作業は未実施。架空のURLは追加していない。

## 公開URLで残る確認

この環境から `koheisuzuk25252525.github.io` へのHTTPアクセスはネットワーク制限により `Tunnel connection failed: 403 Forbidden` となった。**サイトが403を返していると判定したものではない**。制限を迂回せず、GitHub側の公開ソースとデプロイ完了まで確認した。

以下は利用者のブラウザまたは実機での到達性・挙動確認が残る。

- https://koheisuzuk25252525.github.io/hitofude/privacy.html
- https://koheisuzuk25252525.github.io/hitofude/support.html
- https://koheisuzuk25252525.github.io/hitofude/letter.html
- https://koheisuzuk25252525.github.io/app-ads.txt
- https://koheisuzuk25252525.github.io/.well-known/apple-app-site-association

HTTP試行結果：[public-http-check.json](evidence/public-http-check.json)

AASAの配信ヘッダー・Apple CDN反映、AdMob管理画面のapp-ads.txt認識、インストール済みiPhoneでのアプリ起動、未インストール端末でのSafari表示とOS共有シートは今回の自動テストでは確認できない。

## 提出への扱い

今回の範囲で、Web側のコード修正を要する失敗は見つからなかった。ソース変更や再デプロイは実施していない。App Store公開候補は既存TestFlight **1.0（6）** のまま維持する。実機の広告ヒント確認は、このWeb検証と分けて記録する。
