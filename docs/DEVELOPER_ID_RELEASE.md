# Developer ID配布: alpha.2
2026-11-07時点。対象はGitHubから直接配布するApple Silicon版。Developer Programへの加入と配布用証明書の発行は別の手続き。現在配布しているalpha.1はアドホック署名・未公証のまま変更しない。

1. **配布工程（#18）**: 同梱エンジンとアプリ本体を内側から署名し、リハーサル用と配布用の出力を分ける。
2. **実署名・公証（#8 / #19）**: このMacで秘密鍵が使えるDeveloper ID Application証明書と、同じチームの公証プロファイルを用意。チケット付きアプリを含むZIPを作る。
3. **配布経路の確認（#19）**: ブラウザで取得したZIPでGatekeeperと主要操作を確認する。全条件が通ったら新規タグで公開する。
4. **次の判断**: 実機・代表収録の課題（#4〜#7）を整理して安定版を判断する。自動更新やMac App Store配布は署名版の前提にしない。ストア配布を選ぶ場合はサンドボックス下のFinderドロップ・同名置換・同梱ヘルパーの動作を別途設計する。

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
- 該当コミットでGitHubの新規Release下書きを作成し、検証済みの4資産を添付。別のMacまたはクリーンなユーザーで、ブラウザから取得した正規ZIPを展開して起動。**隔離属性を削除しない**。通常の初回起動確認と「開発元を確認できません」を区別する。
- 許可されたテスト動画のコピーでノッチ3領域、キュー、同名置換・失敗時保持、メニューバー、ログイン起動を確認。未確認項目は記録する。
- 署名した同じZIPを公開し、匿名ダウンロード後のSHA-256を照合。READMEはその時点で新しい手順へ変更し、alpha.1向けの隔離属性の説明を混在させない。公開済みのタグ・添付物は変更しない。

Apple: [Developer ID](https://developer.apple.com/developer-id/) / [Notarizing macOS software before distribution](https://developer.apple.com/documentation/security/notarizing-macos-software-before-distribution)
