# NotchCompressor 0.2.0 配布記録

2026-11-26（日本時間）、0.2.0 / build 28を正式公開。

- ソース: `6bb43bdf01d19e3f1ab5dae1f33b1065f0cd202f`。タグ `v0.2.0`。PR #43をmainへマージ。
- ローカル: `NOTCH_MEDIA_TESTS=1 bash scripts/test.sh`、103件成功、失敗・スキップなし。実動画・音声エンジン、画像補助プロセスを含む。
- CI: https://github.com/mani1261790/NotchCompressor/actions/runs/45647548248 — 整形、翻訳、テスト、配布リハーサル成功。
- Developer ID署名、アプリと日英DMGの公証、staple、Gatekeeper検査成功。
- 公証ID: アプリ `fbe984ff-86ee-405d-98ca-76ef9fc604ec`、日本語DMG `11624ee7-d3e7-44cb-ab58-d91d75542521`、英語DMG `d7c3fc7e-7cdf-4ab3-a713-51a5e6a94e38`。
- 署名済み配布アプリの画像ワーカーで生成済み試験JPEGを圧縮し、1600×1000の出力を確認。
- 日英DMGは同一アプリ。インストーラーの配置、Applicationsリンク、収録アプリの署名をスクリプトで検査。
- GitHub Releaseの7添付物を下書きから再取得しローカル原本と照合。正式公開後、全7添付物を認証なしで再取得してバイト一致を確認。
- Sparkleフィードは署名済み候補をバイト変更せずコピー。公開ZIP確認後に昇格。

## 確認範囲

Previewの実操作記録は `docs/design/POST_RELEASE_IMPLEMENTATION.md` を参照。ユーザーによるノッチ表示の確認後に公開を承認された。今回、既存インストールのキューや設定を置き換える更新インストール、ログアウト・再ログイン、実スリープは実施していない。各ディスプレイやすべての入力構成を実機確認したという意味ではない。旧チェックリストの未確認項目を自動テストや公証で完了扱いにしない。

## 公開先

- https://github.com/mani1261790/NotchCompressor/releases/tag/v0.2.0
- https://mani1261790.github.io/NotchCompressor/
- https://raw.githubusercontent.com/mani1261790/NotchCompressor/main/updates/appcast.xml
