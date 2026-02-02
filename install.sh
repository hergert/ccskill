#!/bin/bash
# Install ccskill - Claude Code skill manager
# curl -sSL https://raw.githubusercontent.com/hergert/ccskill/main/install.sh | bash

set -e

REPO="https://github.com/hergert/ccskill.git"
INSTALL_DIR="${SKILL_REGISTRY:-$HOME/.skills}"

echo "Installing ccskill..."

# Check for git
if ! command -v git &>/dev/null; then
    echo "Error: git is required"
    exit 1
fi

# Check for gum
if ! command -v gum &>/dev/null; then
    echo "Note: gum is required for interactive features"
    echo "  Install: brew install gum"
fi

# Clone or update
if [[ -d "$INSTALL_DIR/.git" ]]; then
    echo "Updating existing installation..."
    git -C "$INSTALL_DIR" pull --rebase
else
    if [[ -d "$INSTALL_DIR" ]]; then
        echo "Error: $INSTALL_DIR exists but is not a git repo"
        echo "  Remove it first: rm -rf $INSTALL_DIR"
        exit 1
    fi
    echo "Cloning to $INSTALL_DIR..."
    git clone "$REPO" "$INSTALL_DIR"
fi

# Make executable
chmod +x "$INSTALL_DIR/ccskill"

echo ""
echo "✓ Installed to $INSTALL_DIR"
echo ""

# Detect shell and show PATH instructions
SHELL_NAME=$(basename "$SHELL")
case "$SHELL_NAME" in
    fish)
        echo "Add to PATH (run once):"
        echo "  fish_add_path $INSTALL_DIR"
        ;;
    zsh)
        echo "Add to ~/.zshrc:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        ;;
    bash)
        echo "Add to ~/.bashrc:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        ;;
    *)
        echo "Add to your shell config:"
        echo "  export PATH=\"$INSTALL_DIR:\$PATH\""
        ;;
esac

echo ""
echo "Then run: ccskill list"
