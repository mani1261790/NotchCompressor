

## 2026-09-07 保存仕様の変更（旧記録より優先）

ユーザーが成功時の上書きを明示指定。従来の別名保存を廃止し、元と同じ名前・場所に置き換える。一時ファイルで変換・再解析・全デコード検証を完了し、元のサイズ/mtime/inodeを直前確認してFileManager.replaceItemAtを実行。既存ファイル権限を維持。MOVはMOV、MP4/M4VはMP4コンテナで書き出す。失敗・キャンセル・外部変更検出なら元データを維持。成功後の圧縮前データは残さない。サイズ増加時も置き換え、実測増加を表示する。

実FFmpegを含む26テスト、失敗0/スキップ0。3モードで同名出力・変更側codec・保持側packet hash一致、MP4/M4Vのftyp、Unicode名と権限、外部変更拒否、置き換え失敗時保持、キャンセル時元バイト列一致を確認。合成した一時ファイルだけを使用し、既存のユーザー動画には実行していない。旧履歴に残る別名出力は移動/削除しない。ノッチ実ドラッグ検証はこの変更の成功証拠ではない。

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


## 2026-09-07 19:15 ドロップ受付の安定化

NativeDropSessionを追加。AppKitからドラッグ進入を受けた間は、全体ポーリングによる縮小を抑止し、マウスアップからドロップ通知まで対象領域を維持する。終了・離脱通知で解除し、通知が来ない場合はボタンを離して350msで縮小へ戻す。開始・リリース・終了・キャンセルの単体テスト追加。状態変化のみをOSLogへ記録し、ファイル名は記録しない。

実FFmpegを含む25テスト成功（スキップ0）、releaseビルド成功、修正版起動済み。Computer Useのアプリスクリーンショットで黒い180×28の縮小表示を実際に確認。19:11:51のOSLogに実ファイルドラッグのpasteboard変更（leftDown=true,files=true）が記録された。ただしFinderからのドロップ→キュー成功はまだ確認できていない。自動dragはユーザーによるFinderウインドウ変更を検出して実行前に止まった。Finderを再取得するとDesktopが選ばれる。確認できていない操作を合格としない。


## 2026-09-07 キューと設定のUI刷新

AppleのLiquid Glass導入ガイドとSwiftUIのglass/glassEffect APIに合わせ、macOS 26以降では標準Glassボタンを採用。macOS 14/15では標準の丸いボタンとMaterialにフォールバックする。追加・設定・元ファイル・再試行・キャンセル・履歴消去は説明付きアイコンにし、結果表示・フォルダ選択はピル型。キューは静かな背景のカード、設定はgrouped Form、標準segmented pickerとswitch。ガラスは操作部品に限定する。

releaseビルド成功。起動したキューのスクリーンショットで追加ボタンの過剰な横幅を見つけて修正し、丸い追加・設定とピル型結果ボタンを再確認。設定シートの全セクション、ツール検出、設定を閉じる操作を実画面で確認。追加アイコンから3モードのメニューが開くことも確認。ログイン設定の変更や新たな変換は実行していない。ノッチ実ドロップ検証は別途未完了。

参照: https://developer.apple.com/documentation/technologyoverviews/adopting-liquid-glass
参照: https://developer.apple.com/documentation/swiftui/applying-liquid-glass-to-custom-views


## 2026-09-07 円形操作と動画サムネイル

ユーザー訂正: アイコンのみは円、文字付き横長ボタンはピル。IconControlを標準glass + circleに変更し、追加メニューも44ptの円へ統一。macOS 14/15はCircle + Material。大きな圧縮モード記号を廃止し、Quick Lookで各動画のサムネイルを非同期取得。完了時は出力を優先し、なければ元動画。未ダウンロードのiCloudファイルはサムネイル生成をスキップ。失敗時は形式付きプレースホルダー、画面から消えたリクエストはキャンセル。圧縮モードはファイル名下の補足ラベル。

releaseビルド成功。起動した実画面で円形ボタン、ピル型の結果ボタン、個別動画サムネイルを確認。追加ボタンだけ小さくなる問題を再調整し、最終スクリーンショットで設定ボタンと揃う円を確認。検証動画は同じカラーバー素材なのでサムネイルが似ているが、各URLをQuick Lookに渡している。大元のFinder→ノッチドロップ検証はこのUI変更の検証に含めない。


## 2026-09-07 ビルド環境の修正

サムネイルUI追加後のCI 34111319040は失敗。macos-15の既定Xcode 16.4にはLiquid Glass SDKがなく、#availableだけでは未定義APIをコンパイルできないことが原因。GitHub公式runner-imagesのインストール済み一覧を確認し、CIにXcode 26.3を明示。修正後run 34111533113は単体テストまで成功、releaseを実行中。

build-app.sh/test.sh共通のselect-xcode.shを追加。明示したDEVELOPER_DIRを尊重し、それが無い場合のみインストール済みのSDK26以上かつフルXcodeを選ぶ。システム設定は変えない。対応SDKが無い・明示パスが不正なら必要バージョンと指定方法を出して停止。通常のbash scripts/build-app.shでビルド成功、不正な明示パスが案内付きexit1となることを確認。

基本Finderドラッグは引き続き未確認。このターンでもドラッグ呼び出しはFinder状態変更エラーで止まり、観察用pasteboardはcount117/filesfalseのまま。新しいキュー追加・展開を示す証拠なし。


## 2026-09-07 Mission Control干渉への対策

ユーザー提供の10.2秒録画を確認。ファイルドラッグでノッチ展開と3領域の強調は実際に動き、その後Mission Controlが開いている。19:56:21.440にexpanded、19:56:21.806にnative destinationが記録された。従来の「展開すら未確認」はこの録画で更新。ただし今回録画はドロップ完了の証拠ではない。

パネルをstationary/ignoresCycle/canJoinAllApplicationsとしてMission Controlの整列から除外し、isMovableと背景移動を禁止。ドラッグ中に受付矩形が移動するNSWindowのフレームアニメーションを停止。接近判定を上端から120pt（ノッチ高32ptでも120pt）まで広げる。screenIndexとtrigger判定に外側境界を含め、CGRectのmaxY境界で判定を失わないよう修正。通常のマウス移動では展開しない条件は維持。OSのMission Control設定は変更していない。

NotchTests 7件成功、releaseビルドと修正版起動成功。Mission Controlが同じ操作で再発しないことは未検証で、完了を断言しない。提供動画自体は読み取りのみ。展開の証拠と干渉解消の証拠を区別する。

参照: https://developer.apple.com/documentation/appkit/nswindow/collectionbehavior-swift.struct


## 公開方針
ユーザーは全体完成後のGitHub Public化・リリースを希望。docs/RELEASE_PLAN.mdに残作業と公開条件を整理。現在Private、Releaseなし、Developer ID Application identityは0件。FFmpeg同梱は未実装。公開条件を満たす前にPublicへ変更しない。
