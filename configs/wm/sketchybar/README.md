# SketchyBar Configuration

Enhanced falleco/dotfiles SketchyBar configuration with improved error handling, robustness, and maintainability.

## 🚀 Quick Start

### Basic Usage

```bash
# Start SketchyBar with enhanced startup script
./start_sketchybar.sh

# Or use the direct Lua configuration
CONFIG_DIR=/path/to/config ./sketchybarrc
```

### Management Commands

```bash
# Start SketchyBar
./start_sketchybar.sh start

# Stop SketchyBar  
./start_sketchybar.sh stop

# Restart SketchyBar
./start_sketchybar.sh restart

# Check status
./start_sketchybar.sh status
```

## 🔧 Configuration Validation

Before starting SketchyBar, validate your configuration:

```bash
# Run configuration validation
./validate_config.lua

# Example output:
[INFO] Validator: Starting SketchyBar configuration validation...
[INFO] Validator: Configuration directory: /Users/yuki/dotfiles/configs/wm/sketchybar
[INFO] Validator: Running check: System Dependencies
[INFO] Validator: All system dependencies are satisfied
[INFO] Validator: Check passed: System Dependencies
...
[INFO] Validator: ✅ All validation checks passed!
```

## 📁 File Structure

```
sketchybar/
├── README.md                 # This documentation
├── sketchybarrc             # Main entry point (enhanced with error handling)
├── start_sketchybar.sh      # Robust startup script
├── validate_config.lua      # Configuration validation tool
├── init.lua                 # Main configuration loader
├── bar.lua                  # Bar settings
├── colors.lua               # Color definitions
├── default.lua              # Default item settings
├── icons.lua                # Icon definitions
├── settings.lua             # General settings
├── items/                   # Bar items configuration
│   ├── init.lua
│   ├── aerospace.lua        # Workspace indicators
│   ├── apple.lua           # Apple menu
│   ├── calendar.lua        # Date/time
│   ├── front_app.lua       # Current application
│   ├── media.lua           # Media controls
│   ├── menus.lua           # Context menus
│   ├── spaces.lua          # Workspace management
│   └── widgets/            # System widgets
│       ├── init.lua
│       ├── battery.lua     # Battery indicator
│       ├── cpu.lua         # CPU usage
│       ├── volume.lua      # Volume control
│       └── wifi.lua        # WiFi status
└── helpers/                # Helper binaries and utilities
    ├── makefile            # Enhanced build system
    ├── init.lua            # Helper initialization (enhanced)
    ├── app_icons.lua       # Application icon mapping
    ├── default_font.lua    # Font definitions
    ├── event_providers/    # System monitoring
    │   ├── cpu_load/       # CPU monitoring binary
    │   ├── network_load/   # Network monitoring binary
    │   └── sketchybar.h    # C header definitions
    └── menus/              # Menu utilities
        └── bin/            # Compiled menu binaries
```

## 🛠️ Building Helper Binaries

Helper binaries are automatically built when needed, but you can also build them manually:

```bash
# Build all helpers
cd helpers && make

# Clean and rebuild
cd helpers && make clean && make

# Check build environment
cd helpers && make check
```

## 📋 Dependencies

### System Requirements

- **macOS** (tested on macOS 14+)
- **SketchyBar** - Main bar application
- **Lua** - Configuration language
- **Make** - Build system for helpers
- **C Compiler** (clang/gcc) - For building helper binaries

### Optional Dependencies

- **AeroSpace** - Window manager (workspace integration)
- **Homebrew** - Package manager for additional tools

## 🔍 Troubleshooting

### Common Issues

1. **SketchyBar won't start**
   ```bash
   # Check configuration
   ./validate_config.lua
   
   # Check logs
   tail -f ~/.sketchybar/sketchybar.log
   
   # Force restart
   ./start_sketchybar.sh restart
   ```

2. **Helper binaries missing**
   ```bash
   # Rebuild helpers
   cd helpers && make clean && make
   
   # Check build environment
   cd helpers && make check
   ```

3. **Configuration errors**
   ```bash
   # Validate syntax
   ./validate_config.lua
   
   # Check specific file
   lua -c "dofile('path/to/file.lua')"
   ```

### Log Files

- **Main log**: `~/.sketchybar/sketchybar.log`
- **System log**: Check Console.app for SketchyBar entries
- **Build logs**: Helper build output in terminal

### Debug Mode

Enable verbose logging by setting environment variables:

```bash
export CONFIG_DIR=/path/to/config
export SKETCHYBAR_DEBUG=1
./sketchybarrc
```

## 🔄 Integration with AeroSpace

This configuration is designed to work seamlessly with AeroSpace window manager:

- **Workspace indicators** show current AeroSpace workspace (1-8)
- **Focus changes** trigger SketchyBar updates
- **Workspace switching** updates bar state automatically

### AeroSpace Configuration

Ensure your AeroSpace config includes SketchyBar integration:

```toml
# In aerospace.toml
exec-on-workspace-change = [
  '/bin/bash',
  '-c', 
  'sketchybar --trigger aerospace_workspace_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE'
]

on-focus-changed = [
  'exec-and-forget sketchybar --trigger aerospace_focus_change FOCUSED_WORKSPACE=$AEROSPACE_FOCUSED_WORKSPACE'
]
```

## 🎨 Customization

### Colors

Edit `colors.lua` to customize the color scheme:

```lua
return {
  black = 0xff181825,
  white = 0xffcad3f5,
  red = 0xffed8796,
  -- Add your colors here
}
```

### Icons

Modify `icons.lua` to change icon sets:

```lua
return {
  apple = "󰀵",
  wifi_on = "󰖩",
  wifi_off = "󰖪",
  -- Customize icons here
}
```

### Widgets

Add custom widgets in `items/widgets/`:

1. Create new widget file: `items/widgets/my_widget.lua`
2. Register in `items/widgets/init.lua`
3. Configure appearance and behavior

## 📈 Performance

### Optimization Tips

1. **Reduce update frequency** for expensive operations
2. **Cache expensive calculations** in helper binaries
3. **Use appropriate event triggers** instead of polling
4. **Monitor resource usage** with Activity Monitor

### Monitoring

```bash
# Check SketchyBar resource usage
ps aux | grep sketchybar

# Monitor helper processes
ps aux | grep -E "(cpu_load|network_load)"

# Check memory usage
top -pid $(pgrep sketchybar)
```

## 🤝 Contributing

1. **Validate changes** with `./validate_config.lua`
2. **Test thoroughly** with `./start_sketchybar.sh restart`
3. **Follow Lua best practices** and existing code style
4. **Update documentation** for new features

## 📄 License

Based on falleco/dotfiles SketchyBar configuration.
Enhanced with additional error handling and robustness features.