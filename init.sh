#!/bin/bash

# Set strict error handling
set -euo pipefail

# Store original sleep settings
ORIGINAL_SLEEP_SETTINGS=$(pmset -g)
ORIGINAL_DISPLAY_SLEEP=$(echo "$ORIGINAL_SLEEP_SETTINGS" | grep "displaysleep" | awk '{print $2}')
ORIGINAL_DISK_SLEEP=$(echo "$ORIGINAL_SLEEP_SETTINGS" | grep "disksleep" | awk '{print $2}')
ORIGINAL_SYSTEM_SLEEP=$(echo "$ORIGINAL_SLEEP_SETTINGS" | grep "sleep" | awk '{print $2}')

# Prevent sleep during script execution
log_info "Temporarily preventing system sleep..."
sudo pmset -a displaysleep 0 disksleep 0 sleep 0

# Trap to restore original sleep settings on script exit
cleanup() {
    log_info "Restoring original sleep settings..."
    sudo pmset -a displaysleep "$ORIGINAL_DISPLAY_SLEEP" disksleep "$ORIGINAL_DISK_SLEEP" sleep "$ORIGINAL_SYSTEM_SLEEP"
}
trap cleanup EXIT

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

# Generate and configure GitHub SSH key
log_info "Setting up GitHub SSH key..."
if [ ! -f ~/.ssh/id_rsa ]; then
    # Create .ssh directory if it doesn't exist
    mkdir -p ~/.ssh
    chmod 700 ~/.ssh
    
    # Generate SSH key
    ssh-keygen -t rsa -b 4096 -C "$git_email" -f ~/.ssh/id_rsa -N ""
    
    # Start ssh-agent and add the key
    eval "$(ssh-agent -s)"
    ssh-add ~/.ssh/id_rsa
    
    # Copy public key to clipboard
    pbcopy < ~/.ssh/id_rsa.pub
    
    log_info "SSH key has been generated and copied to clipboard"
    log_info "Please add this key to your GitHub account:"
    log_info "1. Go to https://github.com/settings/ssh/new"
    log_info "2. Give your key a title (e.g., 'MacBook Pro')"
    log_info "3. Paste the key from your clipboard"
    log_info "4. Click 'Add SSH key'"
    
    # Wait for user to confirm
    read -p "Press Enter after adding the key to GitHub..."
    
    # Test SSH connection
    log_info "Testing GitHub SSH connection..."
    if ssh -T git@github.com 2>&1 | grep -q "successfully authenticated"; then
        log_info "GitHub SSH connection successful!"
    else
        log_warn "GitHub SSH connection test failed. Please verify your key was added correctly."
    fi
else
    log_warn "SSH key already exists at ~/.ssh/id_rsa"
fi

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
    pip install fastapi uvicorn pydantic[dotenv] requests httpx pytest black isort mypy ruff
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
# Show battery percentage in menu bar
defaults write com.apple.menuextra.battery ShowPercent -bool true

# Restart affected applications
for app in Finder Dock SystemUIServer; do
    killall "$app" >/dev/null 2>&1
done

log_info "Mac setup complete! 🚀"
log_info "Please restart your terminal to apply all changes."
