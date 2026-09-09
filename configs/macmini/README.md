# The local AI stack on the mac mini

Everything AI-related on the headless M4 Mac mini with 24 GB, reachable from a phone through
gapul.net.

## What is declared in nix and what is not

| Layer | Managed by | Where |
|---|---|---|
| brew: ffmpeg, uv, aria2, socat, container, tailscale | Declared in nix | `homebrew.brews` in `nix/hosts/macmini.nix` |
| Wrapper CLIs: transcribe, tts, describe and the rest | This repository | `configs/macmini/bin/` linked into `~/.local/bin/` |
| Services and scripts, such as ai-stack.sh | This repository | `configs/macmini/services/` linked into `~/` |
| The launchd supervisor | This repository | `configs/macmini/launchd/` linked into `~/Library/LaunchAgents/` |
| Python venvs for ML | Imperative | Rebuilt by `bootstrap.sh` with uv; torch, mlx and pyannote are hard to express in nix |
| The models, which are large | Imperative | The `models.txt` manifest plus `bootstrap.sh`, downloading from hf-mirror and GitHub |

## Reproducing it from a clean mac mini

1. `darwin-rebuild switch`, which brings in the brew packages and the SSH and sleep settings.
2. `bash configs/macmini/bootstrap.sh`, which rebuilds the venvs, fetches the models, places the
   scripts, starts the containers and registers the launchd agents.
3. Add the tools block to Caddy, which runs on a different host; see `docs/`.

## The services, all on 192.168.116.91

- The embedding and reranking server, Ruri, on :8900, and the AI tools web panel on :8901.
- Containers: Minecraft on :25565, through apple container, published to the host with socat.

Open WebUI and AnythingLLM moved to homeserver on 2026-08-12 and were retired on 2026-08-20,
because they overlapped with the AI panel on :8901.

Ollama, on :11434, and the `ask` command were removed on 2026-08-28. It was holding 47 GB in its
own blob store while the actual inference had moved to the MLX stack and claude-bridge.

## Things that catch you out

The details are in the comments in each script.

**Download models directly on the mac mini**, not through the Mac. HF Xet gets throttled, down
to a few kilobytes per second, so prefer hf-mirror.com, which manages about 8 MB/s, or GitHub,
for things like TRvlvr's releases. aria2 is used with self-healing plus zip verification.

**Quantisation interacts badly with Japanese.** Four-bit VLMs can break Japanese generation;
this is a peer-reviewed result from EMNLP 2024. Ruri holds up well in Japanese.

**apple container** needs `container system start` and
`container system kernel set --recommended` the first time. DNS breaks, so pass
`--dns 1.1.1.1`. Publishing a host port with `-p` breaks over HTTP, so socat forwards from the
host to the container's address instead.

**SSH to the mac mini** is often refused by the Bitwarden agent, so `ControlMaster` multiplexing
is effectively required.
