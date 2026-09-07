# 開発引き継ぎ

SwiftUI / AppKitのmacOS動画圧縮アプリ。リポジトリはmani1261790/NotchCompressor。主な計画はPLAN.md、配布計画はdocs/RELEASE_PLAN.md、実操作の証拠と未確認範囲はdocs/VALIDATION.mdを参照。

## 現在の仕様（過去の履歴より優先）

- 通常はノッチ形状の小さい黒いパネルを表示。ファイルドラッグ時に左=画質、中央=両方、右=音質の3領域へ展開する。中央の表示・ドロップ先はカメラの下に配置する。
- 成功時に全デコード検証後、元動画を同名置き換えする。失敗・キャンセル・外部変更検出時は元動画を保持する。成功後の圧縮前データは残さない。容量増加時も置き換える。
- 一時出力は同じディレクトリ内に作成。直前にsize/mtime/inodeを確認してreplaceItemAt。任意の外部プロセスに対する原子的CASではない。
- キューは既定で自動（最大2件、映像変換は1件まで、省電力/発熱時は1件）。手動で直列/最大2件、待機カードのドラッグ並べ替え/一時停止を操作できる。同じ入力はinode+volumeとパスで排他。復元時の中断ジョブは自動再実行しない。破損履歴は上書きしない。
- macOS 26でLiquid Glass、旧OSは代替の丸いコントロール。アイコンのみは円形、テキスト付きはカプセル。
- FFmpeg 9.0.1を公式ソースからGPL/nonfree無効でビルドし同梱。配布アプリは外部パスや古いツール設定を使わない。開発・テスト時だけNOTCH_FFMPEG_DIRで明示できる。
- Apache 2.0採用。FFmpegは別途LGPL 2.1以降。Developer IDは申請Pendingのためユーザー指示で保留。配布はまずアドホック署名試験版の準備。

## 実行

- `bash scripts/build-app.sh`: Xcode 26以降をコマンド内で選択、FFmpegとアプリをビルド。システムxcode-selectを変更しない。
- `NOTCH_FFMPEG_DIR="$PWD/dist/NotchCompressor.app/Contents/MacOS" NOTCH_MEDIA_TESTS=1 bash scripts/test.sh`: 同梱エンジンの統合テスト。
- `bash scripts/package-release.sh`: ZIP、対応ソース、ビルド情報、チェックサム。
- 設定/履歴は `~/Library/Application Support/com.mani.NotchCompressor/queue.json`。利用者の履歴・既存動画をテストのために変更しない。
- Process終了後、asyncの別スレッドからwaitUntilExitを重ねない（過去にFoundationが待ち続けた）。

## 未完了

提供録画でノッチ展開・3領域の強調は確認済み。Mission Controlへのstationary/nonmovable/早期展開対策後の実ドラッグ完了は未確認（#4）。メニューバーの実操作（#5）、追加画面/ログイン（#6）、代表収録品質（#7）、署名/公証（#8）も完了としない。自動操作の試行、単体テスト、実画面確認は別の証拠。ユーザーは完成後のPublic化とリリースを希望。未確認条件を削って公開済みや完成と報告しない。

最新の指定: 優先度（高/標準/低）と「次に処理」は廃止。待機中カードのドラッグ＆ドロップで並び順を変更し、その順序で空き枠へ割り当てる。旧履歴のpriority値は読み飛ばし、保存済み配列順を使う。

成功したジョブは完了の都度displayedJobsから除外。内部の最大100件の結果と動画本体は保持し、失敗/キャンセル/中断はキューに残す。再起動時も成功カードを表示しない。2026-09-07 21:15の手操作でQueueReorderのdrop committedログを確認（自動操作では到達できなかった実経路）。
