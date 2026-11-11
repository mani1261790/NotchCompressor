# UX改善に向けたライブラリ選定

2026-11-11。現在の実装と公式資料に基づく選定方針。以下は選定時の判断。実施状況は末尾と `VALIDATION.md` を参照。外部サービスへの送信は追加していない。

## 選定

| 候補 | 判断 | 利用者への効果・現在の実装との関係 |
| --- | --- | --- |
| [KeyboardShortcuts](https://github.com/sindresorhus/KeyboardShortcuts) | 次の機能追加に採用 | 任意のアプリから圧縮キューを開く。SwiftUIの記録UI、設定保存、システム／メインメニューとの競合警告を利用できる。初期値は未設定、変更・解除可能。圧縮の直接実行には割り当てない。 |
| [create-dmg](https://github.com/sindresorhus/create-dmg) | 見た目の試作に採用、配布工程への採用は比較後 | 現在のDMGにはアプリとApplicationsリンクがあるが、Finder内の配置・背景を固定していない。アプリ→Applicationsの操作を一目で理解できる配置を試作する。Node.jsはビルド時だけ。既存の署名・公証・マウント検証を維持し、ツール側の署名成功だけで配布可としない。 |
| [swift-format](https://github.com/swiftlang/swift-format) | 開発用に採用 | Xcodeに同梱された版をCIと揃える。設定を固定し、整形は機能変更と別コミットにする。アプリへ追加する依存ではない。 |
| [LaunchAtLogin](https://github.com/sindresorhus/LaunchAtLogin-Modern) | 現時点で追加しない | SMAppServiceで登録・解除・承認待ちの設定画面への導線を実装済み。まずシステム設定で外から状態が変更された際の再同期とログイン起動の実機検証を優先する。 |
| [Defaults](https://github.com/sindresorhus/Defaults) | 現時点で追加しない | 圧縮設定はキューとJSON保存し、ジョブごとに投入時の設定を保持している。単なる保存ライブラリ置換ではUXが改善しない。将来の表示設定は標準AppStorageも検討し、既存ジョブの設定を変更しない。 |
| [DockProgress](https://github.com/sindresorhus/DockProgress) | 現構成では追加しない | Dock非表示の常駐アプリ。進捗はメニューバーで改善する。処理中・一時停止・失敗を区別し、色だけに依存しない表示と読み上げを設計する。 |
| [Sentry](https://docs.sentry.io/platforms/apple/guides/macos/) | 公開後の必要性を見て再評価 | 先に利用者が内容を確認してコピーできる診断情報を設計する。導入時は明示的なオプトインとし、動画・ファイル名・パス・FFmpegの生ログを送らず、許可した項目だけを組み立てる。実際の送信内容を検証する。 |
| [AVFoundation](https://developer.apple.com/documentation/avfoundation/exporting-video-to-alternative-formats) | エンジン移行は見送り | 現行FFmpegもhevc_videotoolboxでハードウェア圧縮している。一時停止／再開、対象外トラックのcopy、全体デコード検証、元ファイル置換を維持する。移行判断には同一素材で速度・容量・品質・消費電力・機能同等性の比較が必要。 |
| [ZIPFoundation](https://github.com/weichsel/ZIPFoundation) | 現用途では追加しない | アプリ内でZIPを扱う要件がない。動画再圧縮の代わりにはならず、配布アーカイブは既存のdittoとSparkleで扱う。 |

## UXとしての実施順

1. グローバルショートカット。設定・解除・競合警告・再起動後の保持を確認。他アプリからキーを押すと既存のキューウィンドウが前面に出ること、動画を勝手に追加／圧縮しないことを実機確認する。他社アプリとの競合を全て検出できるとは案内しない。
2. DMGの配置と短いドラッグ案内。通常のFinder表示でアイコンが隠れず、Applicationsへコピーして起動できることを確認。署名と公証を通してから配布する。
3. メニューバーの状態と完了フィードバック。成功カードをキューに残さず、一時的な完了表示で処理件数・実測の容量差を知らせる。容量増加は増加として表示する。外部通知は任意。ノッチはファイルドラッグ時だけ展開する既存仕様を維持する。
4. 診断情報のコピー。エラーコード・アプリ／OS版などの必要項目を限定し、プレビュー後に利用者が共有できるようにする。

swift-formatの導入は上記の機能実装と分離する。公証用認証の登録はユーザーが後で行う予定のため、既存のリリース工程を妨げずに進める。

## 確認したローカル実装

- `Sources/NotchCompressor/SettingsView.swift`: SMAppServiceによるログイン起動と承認待ち表示。
- `Sources/NotchCompressor/NotchCompressorApp.swift`: accessoryアプリ、メニューバーの件数表示、キューの単一ウィンドウ。
- `Sources/NotchCompressorCore/JobQueue.swift`: JSONによる設定・ジョブ保存と投入時設定。
- `Sources/NotchCompressorCore/CompressionPolicy.swift` / `CompressionControl.swift`: VideoToolbox、stream copy、プロセスの一時停止／再開。
- `scripts/create-dmg.sh`: Applicationsリンク付きDMGの作成とマウント検証。

## 実施時の更新

DMGはcreate-dmg 8.1.0を評価後、dmgbuild 1.6.7を採用。create-dmgのimage-size依存にGHSA-w3rx-r6r6-pgprが残り、古いネイティブ拡張のビルドも必要だったため。dmgbuildと推移依存はバージョン・SHA-256を固定。Finderを操作せず配置を保存し、日本語案内を同梱する。

KeyboardShortcuts、状態／完了表示、診断情報プレビュー、swift-formatを実装した（#22〜#26）。53テスト・DMG配布リハーサル成功。ネイティブ操作検証はCUAタイムアウトで未確認。
