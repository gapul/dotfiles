# Host roles and data ownership

Each durable dataset has one primary host. Synchronization is for delivery, not a second source
of truth. Generated files may be copied back to the workstation, but source data and bulk assets
stay with the machine that owns the workload.

| Host | Owns | Does not own |
|---|---|---|
| MacBook | GUI editing, Simulator/device testing, interactive debugging, current small working files | Long-running services, bulk asset libraries, unattended batch jobs |
| Mac mini | Personal macOS builds, Nix distributed builds, Blender/ffmpeg batch jobs, AI inference and audio processing | Primary documents, company data, general storage |
| homeserver | Stateful services, databases, backups, CI orchestration, Linux/container jobs and long-term storage | Interactive desktop work, macOS-only builds |
| mvrx-nolang-dev | NoLang/company repositories, VRM source assets and their build/render outputs | Personal data and a workstation-wide mirror |

## Routing rules

- Build on the target platform: macOS release work and Nix derivations go to the Mac mini;
  Linux/container work goes to the homeserver; NoLang builds and renders stay on
  `mvrx-nolang-dev`.
- Keep Simulator, hardware-device deployment, signing prompts and GUI authoring on the MacBook.
- Use Git for source code. Clone on the execution host instead of synchronizing a working tree.
- Use `~/Sync/macmini` only as an ephemeral job inbox/outbox. It must never become the primary
  copy of a project.
- Use Syncthing for intentionally multi-device personal data and rclone mounts for remote-primary
  Drive data.
- Do not automatically mirror `mvrx-nolang-dev`. Access its assets over SSH and copy only the
  small result needed for local review.

## VRM assets

The primary NoLang VRM collection is `mvrx-nolang-dev:~/Sync/MacBook-Mini/vrm-assets`. The old
MacBook mirror at `~/Sync/mvrx-nolang-dev` was retired on 2026-09-10. Before retirement, its ten
conflicting local versions and ignored `fbx_to_vrm` Git metadata were preserved on the server at
`~/vrm-asset-local-archive-20260910`.

Repositories may contain small committed fixtures required by tests. Bulk models, converted
variants, previews and render output do not belong in a workstation clone.
