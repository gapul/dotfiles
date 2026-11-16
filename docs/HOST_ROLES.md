# Host roles and data ownership

Each durable dataset has one primary host. Synchronization is for delivery, not a second source
of truth. Generated files may be copied back to the workstation, but source data and bulk assets
stay with the machine that owns the workload.

| Host | Owns | Does not own |
|---|---|---|
| MacBook | GUI editing, Simulator/device testing, interactive debugging, current small working files | Long-running services, bulk asset libraries, unattended batch jobs |
| Mac mini | Personal macOS builds, Nix distributed builds, Blender/ffmpeg batch jobs, AI inference and audio processing | Primary documents, general storage |
| homeserver | Stateful services, databases, backups, CI orchestration, Linux/container jobs and long-term storage | Interactive desktop work, macOS-only builds |

## Routing rules

- Build on the target platform: macOS release work and Nix derivations go to the Mac mini;
  Linux/container work goes to the homeserver.
- Keep Simulator, hardware-device deployment, signing prompts and GUI authoring on the MacBook.
- Use Git for source code. Clone on the execution host instead of synchronizing a working tree.
- Use `~/Sync/macmini` only as an ephemeral job inbox/outbox. It must never become the primary
  copy of a project.
- Use Syncthing for intentionally multi-device personal data and rclone mounts for remote-primary
  Drive data.

## Remote build and render

- `macmini-build -- COMMAND ...` builds the current clean, pushed Git commit in a disposable
  Mac mini checkout. A repository flake is used automatically; Ladybird and Servo use the
  dedicated toolchain shells. `--get RELATIVE_PATH` copies a selected artifact back.
- Native Rust/CMake, Node, Flutter/Dart, Android API 36, full Xcode (via xcodes), CocoaPods and
  WebAssembly toolchains live on the Mac mini. Android emulators and Apple export remain on the
  MacBook. iOS apps can be built, signed with the development identity on this machine and
  installed over USB to an iPhone attached to it.
- `macmini-render ffmpeg INPUT OUTPUT -- OPTIONS...` transcodes on the Mac mini and returns the
  output file. `macmini-render blender PACKED_SCENE.blend OUTPUT_DIR [FRAME]` renders a packed
  Blender scene and returns the rendered files. `macmini-render after-effects COLLECTED_DIR
  PROJECT.aep OUTPUT COMP` uploads an After Effects Collect Files directory, renders one
  composition with `aerender`, returns the output and deletes the remote copy.
- Build checkouts and render uploads are execution caches, not primary data. Render uploads are
  deleted after each job; inactive build checkouts are deleted by the weekly storage cleanup
  after 30 days.
- Simulator tests and GUI editing remain on the MacBook.

## VRM assets

The retained asset snapshot is on the Mac mini under `~/Documents/Archives/`.
Its `source-manifest.json` records file hashes and `verification.json` records the completed
SHA-256 comparison. Keep these records with the snapshot. The Mac mini's scheduled backup
does not currently include this directory; saving the snapshot there is not an off-site backup.

Repositories may contain small committed fixtures required by tests. Bulk models, converted
variants, previews and render output do not belong in a workstation clone.
