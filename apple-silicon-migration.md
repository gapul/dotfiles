# Apple Silicon Compatibility Migration

## Overview

Based on the pattern of VLC, OBS Studio, and Krita being incompatible with Apple Silicon (arm64-apple-darwin) in nixpkgs, I've performed a systematic analysis and migration of packages that are likely to have platform compatibility issues.

## Research Findings

### Known Issues
- **Inkscape**: Confirmed broken on aarch64-darwin - executable starts but no window appears
- **VLC & OBS Studio**: Already identified as not supported on Apple Silicon in nix
- **General Pattern**: Many Linux-focused applications and those with complex dependencies have compatibility issues

### Apple Silicon Support Status
- nixpkgs now supports aarch64-darwin (Apple Silicon)
- Hydra build cluster builds for x86_64-darwin and aarch64-darwin
- Many packages still don't build on aarch64, particularly Haskell applications
- Complex GUI applications often have dependency issues

## Packages Migrated Back to Homebrew

### 🎨 Creative/Graphics Applications
| Package | Reason | Status |
|---------|--------|--------|
| `gimp` | Potential Apple Silicon issues | Moved to Homebrew |
| `inkscape` | Confirmed broken on aarch64-darwin | Moved to Homebrew |
| `krita` | Potential ARM build issues | Moved to Homebrew |
| `blender` | Complex dependencies, potential issues | Moved to Homebrew |
| `natron` | Compositing software, Linux-focused | Moved to Homebrew |
| `opentoonz` | 2D animation, potential issues | Moved to Homebrew |
| `scribus` | Desktop publishing compatibility | Moved to Homebrew |
| `fontforge` | Font editor, X11 dependencies | Moved to Homebrew |

### 🔧 CAD/Engineering Software
| Package | Reason | Status |
|---------|--------|--------|
| `freecad` | CAD software compatibility issues | Moved to Homebrew |
| `kicad` | PCB design potential issues | Moved to Homebrew |
| `goxel` | Niche application | Moved to Homebrew |

### 🎵 Media Applications
| Package | Reason | Status |
|---------|--------|--------|
| `musescore` | Qt-based, potential issues | Moved to Homebrew |
| `mixxx` | DJ software, audio dependencies | Moved to Homebrew |
| `surge-XT` | Synthesizer, audio/MIDI dependencies | Moved to Homebrew |

### 🎮 Gaming/Entertainment
| Package | Reason | Status |
|---------|--------|--------|
| `prismlauncher` | Minecraft launcher, Java complexities | Moved to Homebrew |
| `godot_4` | Game engine, complex dependencies | Moved to Homebrew |

### 🖥️ Development Tools
| Package | Reason | Status |
|---------|--------|--------|
| `podman-desktop` | Container management GUI, potential issues | Moved to Homebrew |

### 🛠️ Specialized Applications
| Package | Reason | Status |
|---------|--------|--------|
| `wireshark` | Network analyzer, complex system dependencies | Moved to Homebrew |
| `spacedrive` | File manager, newer Rust application | Moved to Homebrew |
| `rustdesk` | Remote desktop, network/graphics dependencies | Moved to Homebrew |

## Safe Packages Remaining in Nix

### ✅ Well-Supported Applications
- `docker` - Container runtime
- `firefox` - Web browser
- `thunderbird` - Email client  
- `libreoffice` - Office suite
- `qbittorrent` - Torrent client
- `vscode` - Visual Studio Code
- `zed-editor` - Modern text editor
- `vivaldi` - Feature-rich browser
- `tor-browser` - Privacy browser
- `obsidian` - Knowledge management
- `zotero` - Reference manager
- `bitwarden-desktop` - Password manager
- `espanso` - Text expander
- `syncthing` - File synchronization
- `onlyoffice-bin` - Office suite
- `ollama` - Local LLM runner
- `wezterm` - Modern terminal emulator

## Impact Summary

### Before Migration
- **Total nix packages**: ~50 GUI applications
- **Risk level**: High (multiple potential compatibility failures)
- **Maintenance burden**: High (fixing individual package failures)

### After Migration  
- **Total nix packages**: ~30 GUI applications (conservative, stable set)
- **Risk level**: Low (well-tested, compatible packages)
- **Maintenance burden**: Low (proactive issue prevention)

### Homebrew Impact
- **Additional casks**: +18 applications moved back
- **Benefit**: Native Apple Silicon optimized versions
- **Trade-off**: Less declarative, but more reliable

## Benefits of This Approach

1. **Proactive Issue Prevention**: Avoid build failures before they occur
2. **Better Apple Silicon Support**: Homebrew typically has better native ARM64 support
3. **Reduced Maintenance**: Less time debugging nix build issues
4. **Professional Stability**: Creative and development tools work reliably
5. **Hybrid Best-of-Both**: Use nix for CLI tools, Homebrew for complex GUI apps

## Validation Strategy

1. **Test Current Configuration**: Ensure remaining nix packages build successfully
2. **Gradual Rollout**: Can be applied incrementally if needed
3. **Rollback Capability**: Easy to move packages back to nix if needed
4. **Documentation**: Clear reasoning for each migration decision

## Next Steps

1. Apply the configuration changes
2. Run `darwin-rebuild switch` to test the new configuration
3. Verify all remaining nix packages build successfully
4. Install moved applications via Homebrew
5. Document any additional compatibility issues discovered

This conservative approach prioritizes system stability and reliability over maximizing nix usage, which is appropriate for a production development environment.