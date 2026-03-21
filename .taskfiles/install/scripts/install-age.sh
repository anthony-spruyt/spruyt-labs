#!/bin/bash
set -euo pipefail

echo "🔍 Checking OS and package manager..."

if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if command -v apt &>/dev/null; then
    echo "📦 Using apt (Debian/Ubuntu)"
    sudo apt update
    if dpkg -s age &>/dev/null; then
      echo "🔄 Updating age..."
      sudo apt install --only-upgrade -y age
    else
      echo "🆕 Installing age..."
      sudo apt install -y age
    fi

  elif command -v dnf &>/dev/null; then
    echo "📦 Using dnf (Fedora/RHEL)"
    sudo dnf check-update || true
    sudo dnf install -y age # dnf handles upgrades automatically

  elif command -v pacman &>/dev/null; then
    echo "📦 Using pacman (Arch)"
    sudo pacman -Sy --noconfirm age # pacman also upgrades if installed

  else
    echo "❌ No supported package manager found! Install age manually."
    exit 1
  fi

elif [[ "$OSTYPE" == "darwin"* ]]; then
  echo "🍎 macOS detected"
  if ! command -v brew &>/dev/null; then
    echo "❌ Homebrew is required but not found. Please install Homebrew first."
    exit 1
  fi
  if brew list age &>/dev/null; then
    echo "🔄 Upgrading age..."
    brew upgrade age || echo "✅ Already up to date."
  else
    echo "🆕 Installing age..."
    brew install age
  fi

else
  echo "❌ Unsupported OS. Please install age manually:"
  echo "👉 https://github.com/FiloSottile/age#installation"
  exit 1
fi

echo "✅ Installed versions:"
age --version
age-keygen --version
