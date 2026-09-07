# 開発引き継ぎ

作業場所はユーザー指定の `/Users/mani/Developer/NotchCompressor`。旧Documents配下から移動済み。SwiftUIでmacOSアプリを開発する。

## 現在

- Swift Packageの実行可能アプリ。SwiftUIのメニューバーUIとドロップ領域、AppKitのNSPanelを実装。
- 3モードのファイル受け取りを確認するための操作プロトタイプ。
- 圧縮、削除、置き換えは未実装。
- `bash scripts/build-app.sh` でローカル用 `.app` を生成。

## 次の作業

1. Finderの実際のドラッグで表示・非表示と3領域へのドロップを検証する。ビルド成功を操作検証の代用にしない。
2. 添付参考画像に合わせ、ノッチから連続して広がる形状とアニメーションを仕上げる。
3. 動画解析と3種類の圧縮処理を接続する。詳細は `PLAN.md`。

圧縮の数値、対応形式、出力検証の方式は未確定。公開範囲は指定されていないためGitHubは非公開を初期値とする。

## Issue #1 完了

CoreにMediaInfo/InputFile/Toolchain/CompressionPlanを分離。3モード・音声なし・HDR・追加トラック・JSON異常・ツール欠落等の8テスト成功。テストは `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer xcrun swift test`（既定CLTではXCTestを解決できないため、このコマンドだけXcodeを指定）。
