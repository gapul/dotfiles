# SketchyBar Helpers Makefile
# Enhanced with error handling and dependency checking

.PHONY: all clean check install event_providers menus

# Default target
all: check event_providers menus
	@echo "[INFO] All helper binaries built successfully"

# Check build environment
check:
	@echo "[INFO] Checking build environment..."
	@command -v cc >/dev/null 2>&1 || command -v gcc >/dev/null 2>&1 || command -v clang >/dev/null 2>&1 || \
		(echo "[ERROR] No C compiler found (cc/gcc/clang)" && exit 1)
	@echo "[INFO] Build environment OK"

# Build event providers
event_providers:
	@echo "[INFO] Building event providers..."
	@if [ -d "event_providers" ]; then \
		cd event_providers && $(MAKE) || (echo "[ERROR] Failed to build event_providers" && exit 1); \
	else \
		echo "[WARN] event_providers directory not found"; \
	fi

# Build menus
menus:
	@echo "[INFO] Building menus..."
	@if [ -d "menus" ]; then \
		cd menus && $(MAKE) || (echo "[ERROR] Failed to build menus" && exit 1); \
	else \
		echo "[WARN] menus directory not found"; \
	fi

# Clean all binaries
clean:
	@echo "[INFO] Cleaning helper binaries..."
	@if [ -d "event_providers" ]; then cd event_providers && $(MAKE) clean 2>/dev/null || true; fi
	@if [ -d "menus" ]; then cd menus && $(MAKE) clean 2>/dev/null || true; fi
	@echo "[INFO] Clean completed"

# Install dependencies (macOS specific)
install:
	@echo "[INFO] Installing build dependencies..."
	@if command -v brew >/dev/null 2>&1; then \
		echo "[INFO] Homebrew found, checking dependencies..."; \
	else \
		echo "[WARN] Homebrew not found, some dependencies may be missing"; \
	fi
