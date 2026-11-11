# Developer ID配布: alpha.2
2026-11-11時点。対象はGitHubから直接配布するApple Silicon版。Developer Programへの加入と配布用証明書の発行は別の手続き。現在配布しているalpha.1はアドホック署名・未公証のまま変更しない。

1. **配布工程（#18）**: 同梱エンジンとアプリ本体を内側から署名し、リハーサル用と配布用の出力を分ける。
2. **実署名・公証（#8 / #19）**: このMacで秘密鍵が使えるDeveloper ID Application証明書と、同じチームの公証プロファイルを用意。チケット付きアプリを含むZIPとDMGを作る。
3. **配布経路の確認（#19）**: ブラウザで取得したZIPでGatekeeperと主要操作を確認する。全条件が通ったら新規タグで公開する。
4. **次の判断**: 実機・代表収録の課題（#4〜#7）を整理して安定版を判断する。DMGとSparkle更新を今回の配布工程に含める。ストア配布を選ぶ場合はサンドボックス下のFinderドロップ・同名置換・同梱ヘルパーの動作を別途設計する。

## 一度だけ行うアカウント設定

- Xcode → Settings → Accounts（Apple Accounts）で該当チームを選び、Manage Certificates → ＋ → **Developer ID Application**。既に別のMacで発行済みなら、秘密鍵付きの既存証明書を安全に移行する方法もある。Apple DevelopmentやDeveloper ID Installerでは代用できない。
- ターミナルで次を実行。Apple Account・Team ID・アプリ用パスワード等は手元の対話プロンプトに入力し、チャットやリポジトリには記載しない。既存プロファイルを使う場合は登録不要。

```sh
xcrun notarytool store-credentials NotchCompressor
bash scripts/distribute.sh check
```

別名のプロファイルは `NOTCH_NOTARY_PROFILE`、複数の配布証明書があるときは `NOTCH_SIGNING_SHA1` に対象のフィンガープリントを指定する。checkは証明書の種類・有効性とAppleの公証サービスへの認証を確認し、アップロードは行わない。秘密鍵のバックアップと失効管理はチーム所有者が行う。

## ビルドと検証

```sh
bash scripts/distribute.sh rehearse
# 配布用認証の用意後、リリース元コミットのクリーンなcheckoutで:
bash scripts/distribute.sh notarize
```

rehearseはローカルのアドホック署名で、build 2・Hardened Runtime付きのアプリと同梱ffmpeg/ffprobeを検証する。出力は隠し作業ディレクトリのREHEARSAL名で、公開禁止。notarizeは証明書・認証の不足時に失敗し、アドホック署名へ切り替えない。署名 → secure timestamp → ZIP提出 → Accepted確認 → appにstaple → 再梱包 → 展開したappをcodesign/stapler/spctlで検査する。公証ログ・提出IDは出力された作業パスで確認する。通信中断時は同じIDをnotarytool info/logで確認してから再提出を判断する。

配布用資産は成功時だけ `dist/0.1.0-alpha.2/` に揃う。公開はスクリプトに含めない。ソースと同梱ライセンス・ビルド情報・SHA256SUMSは従来どおり添付する。

## 公開の判定

- AppleのAccepted、公証ログ（警告も確認）、全実行ファイルの署名、展開済みアプリのticketとGatekeeper判定が成功。
- 該当コミットでGitHubの新規Release下書きを作成し、検証済みの配布資産を添付。別のMacまたはクリーンなユーザーで、ブラウザから取得した正規DMGを開き、アプリをApplicationsへドラッグして起動。**隔離属性を削除しない**。通常の初回起動確認と「開発元を確認できません」を区別する。
- 許可されたテスト動画のコピーでノッチ3領域、キュー、同名置換・失敗時保持、メニューバー、ログイン起動を確認。未確認項目は記録する。
- 署名した同じDMG・ZIPを公開し、匿名ダウンロード後のSHA-256を照合。READMEはその時点で新しい手順へ変更し、alpha.1向けの隔離属性の説明を混在させない。公開済みのタグ・添付物は変更しない。

Apple: [Developer ID](https://developer.apple.com/developer-id/) / [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)


## DMGとSparkle更新

`distribute.sh rehearse` はアプリとApplicationsへのリンクを含む読み取り専用DMGを作り、マウントして署名とリンクを検証する。`notarize` はアプリに加えてDMGも署名・公証・stapleし、Gatekeeperの検査を行う。DMGは初回インストール用、ZIPはSparkle更新用で、両方に同じアプリを格納する。

Sparkle 2.10.1を固定し、メニューバーと設定に更新確認を追加した。自動チェックは初期状態ではオフ。設定から有効にできるが、インストールにはユーザーの操作を必要とする。処理待ち・実行中・一時停止中の動画がある間は更新チェックを開始せず、ダウンロード中に動画が追加された場合もキューが空になるまで再起動を待つ。一時停止中の動画は再開または除外が必要。

更新ZIPとフィードをEdDSA署名し、アプリ側で検証する。秘密鍵はこのMacのログインキーチェーン（アカウント `com.mani.NotchCompressor`）に保存し、リポジトリには公開鍵だけを含める。鍵を失うと既存インストールへの更新配布が困難になるため、所有者が安全な場所へバックアップする。秘密鍵をIssueやチャットへ貼らない。ツールは `bash scripts/sparkle-tools.sh` で取得でき、固定SHA-256を検証してから使用する。

### 公開する順序

1. 未使用のリリース番号と、既存版より大きい `CFBundleVersion` を設定する。現在の候補はalpha.2 / build 2。
2. クリーンなコミットから `bash scripts/distribute.sh notarize` を実行する。生成された `dist/0.1.0-alpha.2/appcast.xml` はまだ公開されない。
3. GitHub ReleaseにDMG・更新ZIP・対応ソース・ビルド情報・SHA256SUMS・appcastを添付し、上の配布経路確認を行って公開する。
4. 公開した更新ZIPのURLとSHA-256を確認してから、生成されたappcastを**バイトを変えず** `updates/appcast.xml` にコピーしてコミット・pushする。更新フィードの公開を先行させない。
5. 既存のSparkle対応版でチェック→ダウンロード→インストール→再起動まで確認する。キュー実行中・一時停止中に再起動されないことも実機で確認する。

初期の `updates/appcast.xml` は署名済みの空フィードで、未検証の版を案内しない。alpha.1にはSparkleがないため、最初の対応版はDMGから手動インストールする。次版からアプリ内で更新できる。GitHub Actionsの検証にはApple認証やSparkle秘密鍵を置かず、公証と更新署名は鍵を持つMacで行う。

Sparkle: [配布ガイド](https://sparkle-project.org/documentation/publishing/) / [カスタマイズ](https://sparkle-project.org/documentation/customization/)
