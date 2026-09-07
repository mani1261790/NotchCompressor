# 開発引き継ぎ

作業実体: `/Users/mani/Developer/NotchCompressor`。旧 `/Users/mani/Documents/ChatGPT/NotchCompressor` はCodex互換のシンボリックリンク。GitHubは `mani1261790/NotchCompressor`、非公開、main。

## ユーザーの指示

SwiftUIで実装。念入りな計画をGitHub Issuesへ分割し、IssueごとにCodex Goalを設定して順番に実装する。勝手な元動画の削除や兄のMacへの配備はしない。

## 進捗

- 計画Goalを完了、PLAN.mdとIssue #1〜#5を作成。
- #1 完了: 入力解析、依存検出、圧縮ポリシー。8単体テスト成功。
- #2 完了: ProcessRunner、変換・検証・保存・キャンセル。3モードの実変換、copy側パケットSHA256一致、元データ不変を確認。
- #3 完了: 永続化された直列キュー、設定・結果SwiftUI、依存設定への導線、終了確認。キュー4テスト成功。
- #4 実装済み・実ドラッグ確認待ち: ノッチ上端から展開する形状、ネイティブNSDraggingDestination、3領域、終了・離脱、画面座標テスト。現在のGoal。Finder→ノッチの実経路はまだ合格にしていない。
- #5 検証準備: CI、test.sh、README、VALIDATION.mdを用意。#4の確認待ちの間に独立した回帰作業を進めている。Goalはまだ切り替えていない。

## 最新の確認

`NOTCH_MEDIA_TESTS=1 bash scripts/test.sh` で22テスト成功。実FFmpeg 7.1.1、VideoToolboxを使用。出力名の長いUnicodeと競合も確認。保存確定は同一ボリュームの `renamex_np(..., RENAME_EXCL)`。既存ファイル／リンクを上書きしない。

ネイティブでキュー画面、設定シート、ffmpeg検出表示、完了ボタンを確認。Finderは一時ScreenCaptureKit -3811で状態取得が失敗した。出力をFinder表示する操作で再取得できたが、自動dragで実ドラッグの発生を確認できない。ユーザーへ通常デスクトップのドラッグ結果を非同期質問済み。未回答なら成功を推定しない。

`docs/VALIDATION.md` が確認範囲の記録。テスト成功・画面表示・実ドラッグ・配布署名は別の証拠。

## 実行

- `bash scripts/test.sh`: 単体。既定がCLTのときだけインストール済みXcodeをコマンド内で選ぶ。
- `NOTCH_MEDIA_TESTS=1 bash scripts/test.sh`: 実メディア統合を含む。
- `DEVELOPER_DIR=/Applications/Xcode-beta.app/Contents/Developer bash scripts/build-app.sh`: release .app。
- アプリは `dist/NotchCompressor.app`。ローカルアドホック署名。FFmpegは外部導入。
- 合成した手動確認用動画: `.build/manual-fixtures/Notch-Test.mov`。
- 設定と履歴: `~/Library/Application Support/com.mani.NotchCompressor/queue.json`。

## 注意点

- Processが停止した後にasyncの別スレッドからwaitUntilExitを重ねるとFoundationが待ち続けた。isRunningの終了確認だけにして再テスト済み。
- 異常終了したジョブは中断復元、自動再実行なし。破損した履歴は上書きしない。
- 通常起動／再オープン時はキューを表示。ログイン起動イベントなら表示を抑制する（再ログイン実機検証は未実施）。
- Goal #1/#3は開始できたが、完了更新時にサーバーが「このタスクにGoalがない」と返した。Issueの完了と検証は記録済み。#2のGoal完了はツール成功、#4は開始済み。欠落したGoalを完了したと偽らない。

## ネイティブの追加確認と残作業

ファイル選択→実圧縮→完了→Finder出力表示が成功。合成8秒動画は6.2MB→1.8MB、120秒は93.2MB→26.7MB。1200秒の合成動画で⌘Q→処理を続ける→再度⌘Q→中止して終了を実行し、cancelled、元ファイル存在、一時・完成出力・子プロセスなしを確認。

Issue #6（追加画面/ログイン）、#7（実収録の品質）、#8（配布）を作成。#4の基本実ドラッグと#5のメニューバー経路確認は未完了。#5のCI・README・回帰手順は実装済み。Goalを先へ進めるために#4の未確認条件を削らない。

手動用fixtureは `.build/manual-fixtures/Notch-Test.mov`（6.2MB）。長時間停止検証用のNotch-Cancel.movは生成物約932MBで、再現可能だがまだ保持している。利用者の既存収録ではない。

## 最後の状態

94eb636のCI（run 34106097827）は成功。checkoutのNode 20非推奨警告を受け、公式v7.0.1のNode 24実装をcommit SHAで固定した。

ネイティブの終了検証後、MacがロックされComputer Useが自動解除できないと返した。アプリの最後の再起動はできていない。続行時はユーザーのロック解除後にアプリを起動して#4の実ドラッグを確認する。コードの問題と自動操作環境の制約を混同しない。Goal #4を未達成のままcompleteにしない。


## 2026-09-07 18:50 続行時の状態

Macのロックは解除済み。修正版のreleaseアプリを起動し、履歴とキュー画面を取得できた。ドラッグのpasteboard世代変更時にURLがまだ提供されていないと、その後URLが読めても検出できない状態遷移を修正。同じマウス押下中のみ遅延URLを受け付け、終了後の古いpasteboardでは起動しない。`bash scripts/test.sh --filter NotchTests` は4件成功。releaseビルド成功。

FinderでNotch-Test.movを選択表示するまで成功したが、スクリーンショット取得はScreenCaptureKit -3811で失敗した。この試行ではドラッグ操作に到達していない。ノッチ表示とFinderドロップ→キューは引き続き未確認。修正した状態遷移が実機での表示問題の原因だったとは断定しない。Issue #4 / Goal #4は未完了。


## 2026-09-07 通常時は縮小表示する仕様へ修正

ユーザーの訂正に従い、通常非表示を廃止。常時ノッチと重なる黒い縮小パネルを表示し、ファイル接近時のみ3領域へ展開、終了時は縮小する。NSScreenの左右補助領域からノッチ幅を計算し、ノッチなしでは180×28pt。ウインドウ自体を縮小するため大きな透明領域は残らない。ファイルのnative draggingEntered/Updatedからの展開経路も追加。

NotchTests 5件成功、releaseビルド成功、修正版起動済み。起動後のOSウインドウ一覧で、画面上端X=870,Y=0にWidth=180,Height=28,layer=25のアプリパネルが存在することを確認。これは縮小パネルの配置確認であり、Finderからの実ドラッグ→展開→キューの証拠ではない。後者は未確認のまま。
