# setup-scripts

The one-off setup and model-download scripts used to build the mac mini's AI stack in July
2026. Nothing resident or in daily use refers to them; that has been checked.

- `dl_*`, `pull_*` — downloading models and images
- `finalize_*`, `*_setup.sh`, `setup_*` — the initial build of each service
- `rag_test.py` — a smoke test for the RAG server

The things that actually run live in `configs/macmini/services/` — `ai-stack.sh`, driven by
launchd, plus `rag_server.py`, `ai_panel.py`, `diarize_merge.py`, `sbv2_tts.py` and the rest —
and home-manager links them into `~/.local/share/ai-stack/` (`nix/home/macmini.nix`). The venvs
and models stay imperative, under `~/.local/share/venvs/` and `~/.local/share/models/`.
