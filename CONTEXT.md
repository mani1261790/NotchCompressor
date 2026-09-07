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

## Issue #2 完了

ProcessRunnerとCompressionEngineを追加。非同期進捗・キャンセル・容量事前確認・一時出力・全体デコード・元の変更検知・衝突しない保存を実装。NOTCH_MEDIA_TESTS=1付きswift testで14件成功（実FFmpeg 7.1.1 / VideoToolbox）。3モードのcopy側全パケットSHA256一致、元ファイルSHA256不変、無音声、破損、衝突、キャンセルを確認。

ProcessはisRunningがfalseになるまで待つ。async中にスレッドをまたいでwaitUntilExitを重ねるとFoundationで停止したため、二重待機を除去して回帰確認した。

Codexのタスクが旧作業場所を参照していたため、旧DocumentsパスにはDeveloper実体への互換シンボリックリンクを設置。ソースとビルドの実体はDeveloper配下。

## Issue #3 完了

JobQueueを追加し、直列実行・キャンセル・再試行・受付時設定・JSON永続化・中断復元を実装。破損した履歴は上書きしない。SwiftUIのキュー／設定画面、元と出力のFinder表示、サイズ増減、依存不足の直接導線、SMAppServiceのログイン起動設定、終了確認とプロセス停止待機を接続。

単体テスト14件成功（全18件のうち実メディア4件は明示的に無効）。新規キューテスト4件で順序、最大同時数1、失敗後継続、設定固定、重複、停止、復元、破損履歴保持を確認。ネイティブ操作はIssue #4/#5で行う。
