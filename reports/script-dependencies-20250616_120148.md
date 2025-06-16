# Script Dependencies Analysis Report
Generated: #午後

## Shell Scripts Analysis

### setup.sh
**External Commands:**
- None detected

**File References:**
- exec "$(dirname "$0")/scripts/setup.sh" "$@"
- ✅ Executable

### install.sh
**External Commands:**
- None detected

**File References:**
- exec "$(dirname "$0")/scripts/install.sh" "$@"
- ✅ Executable

### scripts/setup.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- ✅ Executable

### scripts/nix-maintenance.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
-     if ! command -v nix &> /dev/null; then
- ✅ Executable

### scripts/utils.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
-     if [[ "${DEBUG:-false}" == "true" ]]; then
- ✅ Executable

### scripts/check-ci.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
-     if ! gh auth status &>/dev/null; then
- ✅ Executable

### scripts/phase3-migration.sh
**External Commands:**
-     yabai --version > "$BACKUP_DIR/yabai-version.txt"
-     skhd --version > "$BACKUP_DIR/skhd-version.txt"
-     sketchybar --version > "$BACKUP_DIR/sketchybar-version.txt"

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- readonly NIX_DARWIN_DIR="$HOME/.config/nix-darwin"
- ✅ Executable

### scripts/nix-shortcuts.sh
**External Commands:**
- None detected

**File References:**
- alias nrs="sudo darwin-rebuild switch --flake ~/.config/nix-darwin"
- alias nrb="sudo darwin-rebuild build --flake ~/.config/nix-darwin"
- alias nrc="nix flake check ~/.config/nix-darwin"
- alias nru="cd ~/.config/nix-darwin && nix flake update && cd -"
- alias hms="home-manager switch --flake ~/.config/nix-darwin"
- ✅ Executable

### scripts/install.sh
**External Commands:**
- None detected

**File References:**
- SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- source "$SCRIPT_DIR/utils.sh"
- DEBUG=${DEBUG:-false}
-     if [[ -d "$BACKUP_DIR" ]]; then
-         latest_backup=$(find "$BACKUP_DIR" -maxdepth 1 -type d ! -path "$BACKUP_DIR" -exec stat -f "%m %N" {} \; 2>/dev/null | sort -nr | head -1 | cut -d' ' -f2- | xargs basename 2>/dev/null || echo "")
- ✅ Executable

### scripts/software.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1" >&2
-     if [[ -d "$HOME/.oh-my-zsh" ]]; then
- ✅ Executable

### scripts/restore.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- ✅ Executable

### scripts/check-dependencies.sh
**External Commands:**
- None detected

**File References:**
- SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- source "$SCRIPT_DIR/utils.sh"
- DEPENDENCY_MAP="$(get_dotfiles_dir)/.dependency-map.yml"
-             local target_script="scripts/$wrapper"
-             if ! grep -q "scripts/$wrapper" "$wrapper"; then
- ✅ Executable

### scripts/backup.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- ✅ Executable

### scripts/nix-channel-setup.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
-     if command -v nix &> /dev/null; then
- ✅ Executable

### scripts/enhanced-dependency-check.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
- ✅ Executable

### scripts/nix-package-optimizer.sh
**External Commands:**
- None detected

**File References:**
-     echo -e "${BLUE}[INFO]${NC} $1"
-     echo -e "${GREEN}[SUCCESS]${NC} $1"
-     echo -e "${YELLOW}[WARNING]${NC} $1"
-     echo -e "${RED}[ERROR]${NC} $1"
- readonly DOTFILES_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
- ✅ Executable
