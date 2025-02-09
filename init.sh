#!/bin/bash

# Set strict error handling
set -euo pipefail

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Helper functions
log_info() {
    echo -e "${GREEN}[INFO]${NC} $1"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $1"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Check if running with sudo
if [ "$EUID" -eq 0 ]; then
    log_error "Please don't run this script with sudo"
    exit 1
fi

# Create necessary directories
mkdir -p ~/Development ~/Documents/Screenshots

# Install Xcode Command Line Tools
log_info "Installing Xcode Command Line Tools..."
if ! xcode-select -p &> /dev/null; then
    xcode-select --install
else
    log_warn "Xcode Command Line Tools already installed"
fi

# Install Homebrew
log_info "Installing Homebrew..."
if ! command -v brew &> /dev/null; then
    # Get latest Homebrew version
    BREW_VERSION=$(curl -s https://api.github.com/repos/Homebrew/brew/releases/latest | grep -o '"tag_name": ".*"' | cut -d'"' -f4)
    
    if [ -z "$BREW_VERSION" ]; then
        log_error "Failed to get Homebrew version"
        exit 1
    fi
    
    # Construct download URL
    BREW_URL="https://github.com/Homebrew/brew/releases/download/${BREW_VERSION}/Homebrew-${BREW_VERSION}.pkg"
    
    log_info "Downloading Homebrew ${BREW_VERSION}..."
    if ! curl -L -o /tmp/homebrew.pkg "$BREW_URL"; then
        log_error "Failed to download Homebrew"
        exit 1
    fi
    
    log_info "Installing Homebrew..."
    if ! sudo installer -pkg /tmp/homebrew.pkg -target /; then
        log_error "Failed to install Homebrew"
        rm /tmp/homebrew.pkg
        exit 1
    fi
    rm /tmp/homebrew.pkg

    # Initialize Homebrew environment
    if [[ $(uname -m) == 'arm64' ]]; then
        echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/opt/homebrew/bin/brew shellenv)"
    else
        echo 'eval "$(/usr/local/bin/brew shellenv)"' >> ~/.zprofile
        eval "$(/usr/local/bin/brew shellenv)"
    fi
else
    log_warn "Homebrew already installed"
fi

# Update & upgrade brew packages
log_info "Updating Homebrew..."
brew update && brew upgrade

# Install essential CLI tools
log_info "Installing CLI tools..."
BREW_PACKAGES=(
    git
    wget
    tmux
    htop
    fzf
    zsh
    zsh-autosuggestions
    zsh-syntax-highlighting
    ripgrep
    jq
    tree
)

# Install GUI applications
log_info "Installing GUI applications..."
CASK_PACKAGES=(
    iterm2
    google-chrome
    android-studio
    spotify
)

for package in "${BREW_PACKAGES[@]}"; do
    if ! brew list "$package" &> /dev/null; then
        brew install "$package"
    else
        log_warn "$package already installed"
    fi
done

# Install GUI applications via Homebrew Cask
for cask in "${CASK_PACKAGES[@]}"; do
    if ! brew list --cask "$cask" &> /dev/null; then
        brew install --cask "$cask"
    else
        log_warn "$cask already installed"
    fi
done

# Install Python & Conda
log_info "Installing Python & Conda..."
brew install python miniforge

# Set up Conda
if [ ! -f ~/.zshrc ]; then
    touch ~/.zshrc
fi

if ! grep -q "miniforge3/bin" ~/.zshrc; then
    echo 'export PATH="$HOME/miniforge3/bin:$PATH"' >> ~/.zshrc
fi

source ~/.zshrc
conda init zsh

# Create Python environment for API development
if ! conda env list | grep -q "^api "; then
    conda create -n api python=3.11 -y
    conda activate api
    pip install fastapi uvicorn pydantic[dotenv] requests httpx pytest black isort mypy
else
    log_warn "Python 'api' environment already exists"
fi

# Install Node.js & frontend tools
log_info "Installing Node.js & npm..."
brew install node
npm install -g yarn pnpm

# Install Docker
log_info "Installing Docker..."
if ! brew list --cask docker &> /dev/null; then
    brew install --cask docker
else
    log_warn "Docker already installed"
fi

# Install VS Code
log_info "Installing VS Code..."
if ! brew list --cask visual-studio-code &> /dev/null; then
    brew install --cask visual-studio-code
else
    log_warn "VS Code already installed"
fi

# Install databases
log_info "Installing databases..."
brew install postgresql mongodb-community

# Configure PostgreSQL
log_info "Setting up PostgreSQL..."
brew services start postgresql
createuser -s postgres 2>/dev/null || log_warn "User 'postgres' already exists"
createdb postgres 2>/dev/null || log_warn "Database 'postgres' already exists"

# Configure MongoDB
log_info "Setting up MongoDB..."
brew services start mongodb-community

# Install networking tools
log_info "Installing networking tools..."
brew install nmap tcpdump wireshark

# Set up Git configuration
log_info "Setting up Git configuration..."
if [ ! -f ~/.gitconfig ]; then
    read -p "Enter your Git name: " git_name
    read -p "Enter your Git email: " git_email
    git config --global user.name "$git_name"
    git config --global user.email "$git_email"
    git config --global init.defaultBranch main
    git config --global core.editor "code --wait"
fi

# Set zsh as default shell
log_info "Setting zsh as the default shell..."
if [[ $SHELL != "/bin/zsh" ]]; then
    chsh -s /bin/zsh
fi

# Install Oh My Zsh
if [ ! -d ~/.oh-my-zsh ]; then
    log_info "Installing Oh My Zsh..."
    sh -c "$(curl -fsSL https://raw.githubusercontent.com/ohmyzsh/ohmyzsh/master/tools/install.sh)"
fi

# Set up macOS preferences
log_info "Configuring macOS preferences..."
# Show hidden files in Finder
defaults write com.apple.finder AppleShowAllFiles YES
# Show path bar in Finder
defaults write com.apple.finder ShowPathbar -bool true
# Show status bar in Finder
defaults write com.apple.finder ShowStatusBar -bool true
# Save screenshots to ~/Documents/Screenshots
defaults write com.apple.screencapture location ~/Documents/Screenshots

# Restart affected applications
for app in Finder Dock SystemUIServer; do
    killall "$app" >/dev/null 2>&1
done

log_info "Mac setup complete! 🚀"
log_info "Please restart your terminal to apply all changes."
