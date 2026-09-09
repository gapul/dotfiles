# setup-scripts

The one-off setup and model-download scripts used to build the mac mini's AI stack in July
2026. Nothing resident or in daily use refers to them; that has been checked.

- `dl_*`, `fetch_*`, `pull_*` — downloading models and images
- `finalize_*`, `*_setup.sh`, `setup_*` — the initial build of each service
- `rag_test.py` — a smoke test for the RAG server
- `popo-remaining-tasks.md` — notes on what was left over during the build

The things that actually run stayed in the home directory: `ai-stack.sh`, driven by launchd;
`rag_server.py`, `ai_panel.py`, `diarize_merge.py`, `sbv2_tts.py` and `llm_ask.py`; and the
`*-venv`, `*-models` and `*-data` directories, which cannot be moved because the venvs hold
absolute paths.
