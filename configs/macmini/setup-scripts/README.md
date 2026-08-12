# setup-scripts

macmini AIスタック構築時(2026-07)に使った一回きりのセットアップ/モデルDLスクリプト置き場。
常駐や日常コマンドからは参照されていない(参照確認済み)。

- dl_* / fetch_* / pull_* : モデル・イメージのダウンロード
- finalize_* / *_setup.sh / setup_* : 各サービスの初期構築
- rag_test.py : RAGサーバー動作確認
- popo-remaining-tasks.md : 構築時の残タスクメモ

稼働中の実体はホーム直下に残してある:
ai-stack.sh(launchd),
rag_server.py, ai_panel.py, diarize_merge.py, sbv2_tts.py, llm_ask.py,
各 *-venv / *-models / *-data ディレクトリ(venvは絶対パスのため移動不可)
