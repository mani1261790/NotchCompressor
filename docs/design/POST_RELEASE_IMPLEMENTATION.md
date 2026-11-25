# 0.1.0公開後の機能追加

2026-11-25。ユーザーの追加開発指示により開始。公開済み0.1.0の配布物と更新フィードは変更せず、次版として検証する。

1. #36: 非同期の内容判定、混在入力の個別結果、種類と設定の保存。旧履歴は動画として読む。対応エンジンの完成前に画像・音声を受け付けない。
2. #37: PNG可逆最適化、JPEG同形式再圧縮。画像処理は補助プロセスに分離して個別停止・再開を維持。HEIFの複数画像・HDR等は保持を検証するまで非対応。
3. #38: M4A/AAC。音声用のビットレート、時間・チャンネル・タグ・カバーの検証を追加。可逆音声の自動非可逆化はしない。
4. ノッチ: 待機背景を描かず、ドラッグ時に展開。クリックの透過、Reduce Motion、複数画面とカメラ部分の余白を検証。
5. 任意表示: 時計から追加。音楽は公開APIとプレーヤー別の権限・対応を確認し、未対応プレーヤーも含めて万能と案内しない。初期状態はオフ。
6. 各形式の混在投入、原本保持、容量不足、個別停止・除外、スリープ、日英表示を検証してから次版の署名・公証・配布へ進む。

基盤の初回検証: 84テスト、失敗0、実メディア用12件はこの実行ではスキップ。PNG実ファイルの分類、拡張子偽装、混在入力、旧履歴と投入時設定を検査。公開済み0.1.0への反映ではない。

## 画像・音声エンジンの実装と検証

- PNGはIDATのみzlibで再圧縮し、展開後のフィルター付き画素列の完全一致とCRCを検査。その他チャンクはそのまま保存。16bit・透過の試験成功。APNG、破損、上限超過は拒否。
- JPEGはImage I/Oで再圧縮し、対応するAPP/COM情報を元のバイト列で保持。EXIF向き1〜8、GPS、撮影日時、sRGB/Display P3の保持を検査。MPF・ゲインマップ・未知APPブロックは拒否。品質の初期値85は暫定であり、あらゆる写真に最適とは案内しない。
- 画像はNotchImageWorker補助プロセスで実行。原本置換・容量確認・個別停止制御は共用。128 MB・32メガピクセルを上限にする。
- M4Aは単一AAC音声（mono/stereo）と最大1枚のJPEG/PNGカバーが対象。タグ・チャンネル・サンプルレート・時間・カバーのパケットハッシュを検査。ALAC等は自動で非可逆化しない。未対応タグが失われる出力も置換しない。
- 配布FFmpegにシステムzlibを明示してPNGカバーに対応。`use_metadata_tags`指定ではカバーが失われることを試験で検出したため使用しない。
- 2026-11-25: 実FFmpeg/VideoToolboxを含む92テストが成功（スキップなし）。旧履歴・動画圧縮・原本保持・スリープ回復の回帰試験を含む。署名済み配布アプリと実ユーザー操作の検証は別途必要。

次の表示改善: [#40 ノッチ](https://github.com/mani1261790/NotchCompressor/issues/40)、[#41 時計・音楽](https://github.com/mani1261790/NotchCompressor/issues/41)。

## ノッチと任意情報の実装

待機時に時計・音楽がオフならNSPanelをorderOutし、クリック領域を残さない。接近検知時にウインドウ枠は即時確保し、SwiftUIのマスクだけを展開する。収納中もクリックを透過し、Reduce Motion時は描画アニメーションを止める。時計と日付、Apple Musicの曲名はノッチ左右の独立した領域へ表示する。初期値は両方オフ。

Apple Musicは公開Apple Eventsで既に起動しているPIDから現在曲だけを取得する。オフ時はアクセスせず、定期取得は許可を要求しない。利用者が設定の接続ボタンを押したときだけ許可要求が可能。拒否・曲なし・未起動・タイムアウトの説明を日英で用意した。Spotifyやブラウザ等の全プレーヤー対応ではない。曲情報の実取得と権限ダイアログは未確認。

2026-11-25: 実メディア込み93テスト成功。追加の画像補助プロセス停止・再開テストも成功。アドホック署名付きアプリのビルドと署名検査、パッケージ内の画像補助プロセス実行が成功。画像・音声を含むUI文言をファイル単位へ更新。署名・公証済み次版を公開したという意味ではない。

CUAはMacのロックを検出し実画面を取得できなかったため、解除を依頼した。NotchBoxの表示、展開の見た目、実Finderドロップ、音楽権限は合格としない。既存0.1.0のキューとアプリは変更せず、別bundle IDの検証用コピーでUIを確認する。

## MacのDynamic Island

[AppleのWidgetKit戦略](https://developer.apple.com/documentation/widgetkit/developing-a-widgetkit-strategy/)はmacOS 27.3以降のネイティブLive Activitiesを案内している。一方、実機のOS27.3に対しインストール済みSDKは27.2で、ActivityKit.ActivityとWidgetKit.DynamicIslandはmacOS unavailable。既存SDKでavailabilityを回避しない。[#42](https://github.com/mani1261790/NotchCompressor/issues/42)で対応SDKと機種の検証を追跡する。自前の受け取りパネルとシステムLive Activityは別に扱う。

追加検証: 94テスト（実メディア込み）が成功。配布アプリ内の画像補助プロセスでPNGを圧縮し、展開後の画素列が元と一致した。検証コピーは `.local-work/next/media-preview-build12/NotchCompressor Preview.app`（bundle ID `com.mani.NotchCompressor.preview`）。履歴保存先をbundle ID単位に分離し、検証コピーではSparkleを開始しない。インストール済み正式版は0.1.0/build11を維持。CIも補助プロセスをビルド・指定するtest.sh経由へ統一する。

## CIと公証済み候補の確認（2026-11-25）

コミット `965990ce2dfde31524f6864cc7745d680f4bc300` の [CI 45610117573](https://github.com/mani1261790/NotchCompressor/actions/runs/45610117573) が成功。整形・日英カタログ・単体テスト・配布リハーサルを含む。CIの単体テストとローカルの実メディア込み94件は別の実行結果。

同コミットのアプリ本体はDeveloper IDで署名し、公証 `20167add-9ee7-4929-8aaf-c402efea2896` がAccepted。公証済みアプリ内の画像補助プロセスを実行し、試験PNGが355,226から235,893バイトになり、展開後の画素列および入力原本のバイトが変わらないことを確認した。これはFinderドロップやノッチ表示の確認ではない。

残りの実操作は [実機確認表](../releases/0.2.0-acceptance.md) に列挙した。CUAは引き続きMacのロックを報告しており、表示・権限・操作は未確認のまま。正式版0.1.0のアプリ・キュー・公開更新フィードは変更していない。

日本語・英語DMGも公証Accepted。アプリと両DMGのstapler検証・Gatekeeper評価、配布物チェックサム検証が成功。ローカル候補は `dist/0.2.0-alpha.1-build12`。Sparkle署名済みappcastも同ディレクトリ内に作成したが、公開フィードには反映していない。

## 実画面での初回確認

Macが操作可能になったためPreviewを起動した。アドホック署名のPreviewはSparkleのライブラリ検証により起動失敗したが、同じコピーをDeveloper IDで全体署名すると起動した。公証済み配布候補のバイナリ変更は行っていない。

英語UIでJPEGを追加し、完了表示と行の自動削除を確認。次に追加ダイアログでPNG・M4A・MOVの3行を選択したことを確認して投入し、全件完了・キューが空になることを確認した。完了サマリーは8.8 MBから3 MB、5.8 MB削減。Finderからノッチへのドラッグではなく追加ダイアログの確認である。選択直後のCommand-Aだけでは全選択にならず、選択状態を確認したShiftクリックで実施した。非対応txtはダイアログの選択対象外であり、混在ドロップの拒否理由検証はまだ必要。

時計・音楽の初期値オフ、設定のオン・オフを確認。Music表示オンだけでは権限要求が出ず、接続ボタンと権限説明が表示された。接続ボタンは未操作で、許可ダイアログ・実曲名・ノッチ上の描画は未確認。時計・音楽は確認後オフへ戻した。動画は停止操作前に完了したため、今回の実機操作では停止・再開を確認済みとしない。

実機停止試験: 224.8 MBの長い生成動画をPreviewの追加ダイアログから投入。23%で個別停止し、行の残留、停止中の除外ボタン、実行中に除外ボタンがないことを確認。同じFFmpeg PID 36182が停止状態Tから実行状態Rへ戻り、進捗23%から再開した。97%で再停止して除外するとキューから消え、子プロセスが終了し、一時出力ディレクトリが除去された。除外前後の原本SHA-256は一致。試験結果は `.local-work/next/pause-ui-process.json` と `pause-removal-before.sha256`。

時計・Musicの実表示: Previewの時計を有効にしてキューを閉じた後、画面上部の独立したパネルで時刻と日付を確認。9:24から9:25への更新も確認した。Musicの操作権限についてユーザーから許可を得た後、接続操作を実施し「No current track」を確認。Musicで試験再生を開始すると、パネルの右側に曲名が表示され、アクセシビリティに曲名とアーティストが反映された。一時停止後はポーリングでmusic.noteからpause.fillへ変化した。曲名・アーティスト等の利用者の個別再生情報はこの公開記録へ転記しない。試験再生は停止済み。

今回の接続操作でOSの権限ダイアログは出ず、取得は成功した。従って新規権限ダイアログ・拒否からの回復は未確認。時計・Music表示はPreviewのみ有効になっている。Finderの画面取得が一時的に失敗したため、ノッチへの実ドロップは未実施。正式版とPreviewが同時起動しているので、今後のドロップ試験では受け取り先の識別も確認する。

## ホバー中心の情報表示への変更

2026-11-25のユーザー指定により、時計・Musicの主な入口を常時表示からホバー展開に変更。画面上端中央に180 ms留まると情報パネルを開き、パネルの中への移動中は維持し、外へ離れて250 msで閉じる。ファイルドラッグが優先。カメラの下に時計・日付・曲名・アーティストと設定ボタンを配置し、既存の展開マスクとReduce Motion設定を共用する。

「閉じている間も常時表示」は独立した設定で初期値オフ。オンのときだけ従来の小さな情報表示を残す。新規設定の時計はオン、Musicはオフ。既存利用者の時計・Music選択は保持する。時計の更新は毎分に揃える。

ビルド成功、NotchTests 9件成功（ホバーの滞在時間・退出猶予・内容領域への移動・リセットを含む）、日英303キー整合性確認。Developer ID署名のPreviewを差し替え、実設定画面の新しいスイッチと常時表示オン時のパネルを確認し、オフへ戻した。操作ツールのポインター移動ではホバー展開を再現できていないため、実ポインターでの展開・収納の見た目は未確認。

以前作成した公証済みbuild12候補にはこの変更を含まない。次回配布候補は新しいビルド番号で再生成・公証する。自動ドラッグ試験のためのグローバルイベント監視追加は効果を確認できなかったため採用せず、現在のソースとPreviewには含めていない。

ホバー追加後の回帰検証: `NOTCH_MEDIA_TESTS=1 bash scripts/test.sh` が95件・失敗0・スキップ0で成功。実FFmpeg/VideoToolbox、JPEG/PNG/M4A、原本保護、停止・再開と既存動画処理を含む。これは実カーソルによるホバー／Finderドロップの確認には代用しない。ログは `.local-work/next/hover-full-regression.log`。

## アニメーションの作り込み（build 14）

時計に秒表示とnumericTextによる数字の切り替えを追加。再生中は20 fpsを上限とする小さな4本のバーが動き、一時停止時は停止アイコンへ切り替える。音量解析ではなく再生状態のインジケーターで、音声取得は行わない。曲名切り替えはフェード。Reduce Motionでは秒の移動・バーの連続運動・ドロップのバネ移動を抑える。

ドロップ面のコンテナを常時表示・展開で共用し、開閉のマスクと内容のフェード／位置変化を組み合わせる。対象ゾーンは青い背景が移動し、アイコンを少し拡大する。ファイルを受け取った直後に550 msの受領表示を出して閉じる。受領は圧縮成功の表示ではない。連続投入時は古い受領表示の終了タスクをキャンセルする。

アプリビルドとノッチ関連9件の回帰テスト成功。日英306キーを検査。Developer ID署名の `dist/Preview/NotchCompressor Preview.app` を起動し、build14の確認用コピーを準備。新しいアニメーションの実ポインター・実ドロップでの最終評価は未完了。build14は未公証・未公開であり、以前の公証済みbuild13と区別する。

### 2026-11-25: media-specific drop targets and Music controls (build 15)

- Expanded and compact panels now meet the top screen edge with square upper corners; external-screen compact placement no longer has an 8 pt gap.
- File URL extensions provide presentation hints before entry: videos retain video/both/audio targets; JPEG/PNG, M4A and mixed/unknown batches have one appropriately labelled target. Hit testing uses the same model as the visible target. InputBatch remains authoritative for content validation.
- Music artwork uses the running Music process's scripting dictionary (cArt/pRaw), with per-track caching and a 10 MB retained-data cap. Missing artwork uses a music-note placeholder.
- Explicit play/pause uses Music's hook/PlPs command, never launches Music, and never prompts for automation permission during polling or playback. Command failures are visible next to playback controls.
- Checked: 10 NotchTests pass, 315 JA/EN localization keys, universal release build and Developer ID preview signing. Music command/artwork rendering and physical hover/drop acceptance still require real UI verification; compilation does not establish those outcomes.
- Preview remains separate from the public 0.1.0 application and Sparkle feed.

### 2026-11-25: settings navigation and Liquid Glass (build 16)

- Replaced the three-tab modal settings sheet with an independent, resizable settings window. The compression queue remains available while settings are open.
- Native NavigationSplitView/sidebar separates General, Notch, Video, Image, Audio, Saving, and Updates. Each destination has a short purpose statement. Existing setting bindings and persistence are retained.
- Uses native macOS 26 navigation and Liquid Glass action controls; primary capsule actions now use glassProminent. Grouped Form content remains readable rather than applying glass to every row. Older macOS retains native fallback controls.
- Corrected help text to reference dedicated image/audio settings and media-specific drop targets.
- Build and localization checks passed. First visual review exposed truncated sidebar labels and cramped sheet presentation; shortened navigation names and moved to a separate window.
- Final native UI verification: independent window opens; General, Video, Image, and Notch destinations switch correctly; full window renders without the sheet clipping; close returns to queue and reopen retains the selected destination. No preference values changed. Visual inspection was English/dark mode; Japanese/light mode and older-macOS rendering remain unverified.

### 2026-11-25: first-hover animation origin (build 17)

- User observed the first hover expanding from the upper-left, with later openings correctly centered.
- Found the panel was initialized with a zero-size content rect and hidden without establishing its expanded canvas; initial size and visible state could be committed together.
- Initialize the panel with a screen-top-centered canvas. Keep hidden layout prepared, and commit destination geometry/closed-mask layout with animations disabled before setting visible. Actual window movement remains unanimated to preserve native drag tracking.
- Validation: 10 existing notch geometry/hover tests pass, universal release build and signed preview. These checks do not verify animation frames; first-hover visual acceptance still needs physical pointer input.

### 2026-11-25: single playback affordance and immediate feedback (build 18)

- Removed the dashboard's paused-state activity glyph beside the play button. Only the single play/pause control remains when paused; activity bars appear only during playback. Compact paused status uses a neutral music note.
- Playback commands no longer wait for or disable themselves during metadata polling. The circular native button immediately shows pending progress and rejects duplicate clicks until the command completes.
- Read back only player state after the command, updating the button without waiting for artwork/title retrieval. A revision counter discards metadata polls begun before the command so they cannot restore stale playback state.
- Failure preserves the last known playback state and displays the existing error indicator. No optimistic playback success is shown.
- Universal build and localization checks passed. Actual Music response latency and physical notch-button acceptance have not been measured.

### 2026-11-25: image drag target refresh (build 19)

- User reported video targets while dragging an image. Live inspection found both the installed public app and Preview running; the public app still offers only video targets. It has one paused and two waiting jobs, so termination requires the user's decision about losing partial progress.
- Removed the presentation cache keyed only by pasteboard changeCount. Re-read actual URL entries during active drag and update only when the classified kind changes; unavailable URLs now reset to the neutral automatic target.
- Native dragging callbacks own their pasteboard classification while the native session holds the panel. Global polling no longer overwrites it, and drop delivery rechecks before selecting a compression mode.
- Existing 10 notch tests pass. Physical image-hover/drop and removing the old app's overlapping panel remain acceptance steps.

### 2026-11-25: permission guidance, defaults and focused settings (build 20)

- Notifications now distinguish not-requested/denied/authorized from the app's notification preference. Request action is offered before authorization; denied state names the actual bundle display name and opens the macOS Notifications pane. Returning refreshes authorization. Notification preference defaults on without claiming OS permission or auto-prompting.
- SUEnableAutomaticChecks defaults true in the packaged plist; explicit Sparkle preferences remain authoritative. Fresh production installs (no saved queue or app preference domain) attempt login registration once; existing installations and Preview are not auto-registered. Clock remains default-on; Music and persistent background remain opt-in.
- Video explanation is progressively disclosed. JPEG gains 70/85/95 quality shortcuts; PNG has a separate lossless explanation. Audio gains 96/160/256 kbps shortcuts and a stereo MB/min estimate, with mono/source-bitrate/artwork caveats. These reuse existing validated engines; resize, new codecs and metadata-removal options were not introduced.
- Persistent compact rendering no longer mounts the hidden 148-point dashboard under the compact content. Clock-only side regions are 90 pt; music uses 120 pt. Expanded clock/music-only content is centered with settings overlaid at the edge. Black idle background is independently selectable and suppressed when no widgets have content.
- Validation: universal build, Developer ID preview signing, 339 JA/EN keys and 11 notch tests. Native English/dark UI checked for Video/Image/Audio/Updates and notification-denied instructions. Open-settings action reached the actual Notifications pane and Preview's permission control; OS permission was not changed. Widget toggle dependencies checked and original values restored.
- Remaining: first-install login registration, fresh permission prompt, JA/light visual review, physical compact/hover animations and single-widget rendering. Public distribution unchanged.

### 2026-11-25: explicit Music connection state (build 21)

- Replace ambiguous Connect action with explicit permission-needed, blocked, Music-closed, connected/no-track, playing and paused states.
- Connected states explain that track updates are automatic; no repeat connection is necessary. Music-closed/no-track offers Open Music; denied offers Automation settings and actual app name; unrequested permission offers Allow Music access. Recheck leaves a completion timestamp.
- Explicit recheck waits for in-flight polling/control instead of silently returning. Polling still cannot prompt or launch Music. Opening Music is an explicit user action.
- The installed Preview's prior noTrack result already implied successful permission and player-state read; the original UI obscured that distinction.
- Validation: 12 NotchTests including connection-state classification, 354 localization keys, universal build and signed Preview. Fresh authorization prompts/denied UI paths are not end-to-end verified.
- Native UI acceptance: displayed Connected · No track playing and automatic-update explanation. Clicking Check status again completed and displayed Checked at 11:48:29 PM; screenshot visually reviewed. Existing Music permission was reused; no new permission granted and no playback changed.
