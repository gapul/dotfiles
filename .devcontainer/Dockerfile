# GitHub Packages用のDevelopment Container Image
FROM mcr.microsoft.com/vscode/devcontainers/base:ubuntu-22.04

LABEL org.opencontainers.image.title="Dotfiles Development Environment"
LABEL org.opencontainers.image.description="Complete development environment for dotfiles management with Nix, home-manager, and GitHub integration"
LABEL org.opencontainers.image.vendor="gapul"
LABEL org.opencontainers.image.source="https://github.com/gapul/dotfiles"
LABEL org.opencontainers.image.licenses="MIT"

# Install system dependencies
RUN apt-get update && apt-get install -y \
    curl \
    wget \
    git \
    zsh \
    build-essential \
    sudo \
    software-properties-common \
    ca-certificates \
    gnupg \
    lsb-release \
    && rm -rf /var/lib/apt/lists/*

# Install Nix package manager using Determinate Systems installer
RUN curl --proto '=https' --tlsv1.2 -sSf -L https://install.determinate.systems/nix | sh -s -- install linux --init none --no-confirm
ENV PATH="/nix/var/nix/profiles/default/bin:$PATH"

# Setup Nix configuration
RUN mkdir -p /etc/nix && \
    echo "experimental-features = nix-command flakes" >> /etc/nix/nix.conf && \
    echo "trusted-users = vscode root" >> /etc/nix/nix.conf && \
    echo "max-jobs = auto" >> /etc/nix/nix.conf && \
    echo "cores = 0" >> /etc/nix/nix.conf

# Install Node.js for Claude CLI and development tools
RUN curl -fsSL https://deb.nodesource.com/setup_20.x | bash - && \
    apt-get install -y nodejs

# Create workspace directory
WORKDIR /workspaces/dotfiles

# Copy dotfiles configuration
COPY . /workspaces/dotfiles/
RUN chown -R vscode:vscode /workspaces/dotfiles

# Switch to vscode user
USER vscode

# Setup Nix environment for vscode user
RUN . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && \
    nix-channel --add https://github.com/nix-community/home-manager/archive/master.tar.gz home-manager && \
    nix-channel --update

# Install base development tools through Nix with error handling
RUN . /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh && \
    nix-env -iA nixpkgs.gh \
                nixpkgs.starship \
                nixpkgs.bat \
                nixpkgs.eza \
                nixpkgs.fd \
                nixpkgs.ripgrep \
                nixpkgs.jq \
                nixpkgs.yq-go \
                nixpkgs.just \
                nixpkgs.direnv \
                nixpkgs.neovim || \
    echo "Some Nix packages failed to install, continuing..."

# Install Claude CLI globally
RUN npm install -g @anthropic-ai/claude-code

# Setup shell configuration
RUN mkdir -p ~/.config/zsh && \
    echo 'export PATH="/nix/var/nix/profiles/default/bin:$PATH"' >> ~/.zshrc && \
    echo 'if [ -e /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh ]; then' >> ~/.zshrc && \
    echo '  source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh' >> ~/.zshrc && \
    echo 'fi' >> ~/.zshrc && \
    echo 'command -v starship >/dev/null && eval "$(starship init zsh)"' >> ~/.zshrc && \
    echo 'command -v direnv >/dev/null && eval "$(direnv hook zsh)"' >> ~/.zshrc

# Setup Git configuration for container
RUN git config --global user.name "GitHub Codespaces" && \
    git config --global user.email "codespaces@github.com" && \
    git config --global init.defaultBranch main && \
    git config --global push.autoSetupRemote true

# Create helpful aliases
RUN echo 'alias ls="eza --color=auto --group-directories-first"' >> ~/.zshrc && \
    echo 'alias ll="eza -la --color=auto --group-directories-first"' >> ~/.zshrc && \
    echo 'alias cat="bat --style=auto"' >> ~/.zshrc && \
    echo 'alias grep="rg"' >> ~/.zshrc && \
    echo 'alias find="fd"' >> ~/.zshrc

# Create welcome message
RUN echo 'echo "🚀 Welcome to gapul/dotfiles development environment!"' >> ~/.zshrc && \
    echo 'echo "💡 Available commands: claude, gh, just, nix"' >> ~/.zshrc && \
    echo 'echo "📚 Try: just --list, gh --help, claude --help"' >> ~/.zshrc

# Set default shell to zsh
RUN sudo chsh -s $(which zsh) vscode

# Expose common development ports
EXPOSE 3000 8080 9090

# Set working directory
WORKDIR /workspaces/dotfiles

# Health check with fallbacks
HEALTHCHECK --interval=30s --timeout=10s --start-period=30s --retries=3 \
    CMD (command -v nix >/dev/null || exit 1) && \
        (command -v gh >/dev/null || exit 1) && \
        (command -v claude >/dev/null || echo "Claude CLI not available")

# Default command
CMD ["/bin/zsh"]