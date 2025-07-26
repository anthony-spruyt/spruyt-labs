#!/bin/bash
set -euo pipefail

# --- Ensure talhelper is installed ---
if ! command -v talhelper &> /dev/null; then
    echo "🔧 talhelper not found. Installing now..."
    curl https://i.jpillora.com/budimanjojo/talhelper! | sudo bash
    if command -v talhelper &> /dev/null; then
        echo "✅ talhelper installed successfully: $(which talhelper)"
    else
        echo "❌ Installation failed. Please check the install script or try manually."
        exit 1
    fi
else
    echo "✅ talhelper is already installed: $(which talhelper)"
fi

talhelper --version

ensure_helm_diff_plugin() {
  # extract only the plugin names (skip header), then look for "diff"
  if helm plugin list | tail -n +2 | awk '{print $1}' | grep -Fxq diff; then
    echo "✅ helm-diff plugin is already installed: $(helm diff version)"
  else
    echo "🔧 helm-diff plugin not found. Installing now..."
    helm plugin install https://github.com/databus23/helm-diff
    echo "→ $(helm diff version)"
  fi
}

ensure_helm_diff_plugin

ensure_helm_schema_gen_plugin() {
  # extract only the plugin names (skip header), then look for "diff"
  if helm plugin list | tail -n +2 | awk '{print $1}' | grep -Fxq schema-gen; then
    echo "✅ helm-schema-gen plugin is already installed"
  else
    echo "🔧 helm-schema-gen plugin not found. Installing now..."
    helm plugin install https://github.com/knechtionscoding/helm-schema-gen
  fi
}

ensure_helm_schema_gen_plugin

# --- Ensure flux is installed ---
if ! command -v flux &> /dev/null; then
    echo "🔧 flux not found. Installing now..."
    curl -s https://fluxcd.io/install.sh | sudo bash
    if command -v flux &> /dev/null; then
        echo "✅ flux installed successfully."
    else
        echo "❌ Installation failed. Please check the install script or try manually."
        exit 1
    fi
else
    echo "✅ flux is already installed: $(which flux)"
fi

flux --version

# --- Ensure taskfile is installed ---
# if task is already installed, skip everything
if command -v task >/dev/null 2>&1; then
  echo "✅ task already installed: $(command -v task)"
else
  echo "🔧 Installing Taskfile (task CLI)…"
  curl -sSfL https://taskfile.dev/install.sh \
    | sudo sh -s -- -b /usr/local/bin
  echo "✅ task installed: $(which task)"
fi

# --- Ensure age and age-keygen is installed (works for Linux and macOS) ---
# Check platform and install prerequisites
if [[ "$OSTYPE" == "linux-gnu"* ]]; then
  if command -v apt &> /dev/null; then
    sudo apt update
    sudo apt install -y age
  elif command -v dnf &> /dev/null; then
    sudo dnf install -y age
  elif command -v pacman &> /dev/null; then
    sudo pacman -Sy --noconfirm age
  else
    echo "No supported package manager found! Install age manually."
  fi
elif [[ "$OSTYPE" == "darwin"* ]]; then
  if ! command -v brew &> /dev/null; then
    echo "Homebrew is required but not found. Please install Homebrew first."
  fi
  brew install age
else
  echo "Unsupported OS. Please install age manually: https://github.com/FiloSottile/age#installation"
fi

age --version
age-keygen --version

echo "🔧 Installing flux capacitor now..."
curl -L "https://github.com/gimlet-io/capacitor/releases/download/capacitor-next/next-$(uname)-$(uname -m)" -o ../capacitor/next
chmod +x ../capacitor/next
