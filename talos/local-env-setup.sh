#!/bin/bash
set -euo pipefail

# --- Ensure helm is installed ---
#if ! command -v helm &> /dev/null; then
#  echo "🔧 helm not found. Installing now..."
#  curl -fsSL https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3 | bash
#  if command -v helm &> /dev/null; then
#        echo "✅ helm installed successfully."
#    else
#        echo "❌ Installation failed. Please check the install script or try manually."
#        exit 1
#    fi
#else
#  echo "✅ helm is already installed: $(which helm)"
#fi
#
#helm version

# --- Ensure kubectl is installed ---
#if ! command -v kubectl &> /dev/null; then
#    echo "🔧 kubectl is not installed. Installing now..."
#
#    OS=$(uname | tr '[:upper:]' '[:lower:]')
#    ARCH=$(uname -m)
#
#    case "$ARCH" in
#        x86_64) ARCH="amd64" ;;
#        arm64|aarch64) ARCH="arm64" ;;
#        *) echo "❌ Unsupported architecture: $ARCH"; exit 1 ;;
#    esac
#
#    VERSION=$(curl -s -L https://dl.k8s.io/release/stable.txt)
#    URL="https://dl.k8s.io/release/${VERSION}/bin/${OS}/${ARCH}/kubectl"
#
#    echo "⬇️ Downloading kubectl ${VERSION} for ${OS}/${ARCH}..."
#    curl -LO "$URL"
#    chmod +x kubectl
#    sudo mv kubectl /usr/local/bin/
#    if command -v kubectl &> /dev/null; then
#        echo "✅ kubectl installed successfully: $(which kubectl)"
#    else
#        echo "❌ Installation failed. Please check the install script or try manually."
#        exit 1
#    fi
#else
#    echo "✅ kubectl is already installed: $(which kubectl)"
#fi
#
#kubectl version --client

# --- Ensure talosctl is installed ---
# Function to fetch the latest non-prerelease Talos version
#get_latest_release() {
#  curl -s https://api.github.com/repos/siderolabs/talos/releases \
#    | jq -r '[.[] | select(.prerelease == false)][0].tag_name' \
#    | sed 's/^v//'
#}

# Install talosctl if missing
#if ! command -v talosctl &> /dev/null; then
#  echo "🔧 talosctl not found. Installing now..."
#
#  VERSION=$(get_latest_release)
#  OS=$(uname | tr '[:upper:]' '[:lower:]')
#  RAW_ARCH=$(uname -m)
#
#  # Map uname arch to Talos download arch
#  case "$RAW_ARCH" in
#    x86_64) ARCH="amd64" ;;
#    aarch64|arm64) ARCH="arm64" ;;
#    *) echo "❌ Unsupported architecture: $RAW_ARCH"; exit 1 ;;
#  esac
#
#  BINARY="talosctl-${OS}-${ARCH}"
#  URL="https://github.com/siderolabs/talos/releases/download/v${VERSION}/${BINARY}"
#
#  echo "⬇️ Downloading talosctl ${VERSION} for ${OS}/${ARCH}..."
#  # -f to fail on HTTP errors
#  if ! curl -fLO "$URL"; then
#    echo "❌ Failed to download $URL"; exit 1
#  fi
#
#  echo "⚙️ Making binary executable"
#  chmod +x "$BINARY"
#
#  echo "🚚 Moving to /usr/local/bin"
#  sudo mv "$BINARY" /usr/local/bin/talosctl
#
#  echo "✅ talosctl installed successfully: $(which talosctl)"
#else
#  echo "✅ talosctl is already installed: $(which talosctl)"
#fi
#
#talosctl version --client --short

# Install sops and age on Ubuntu/WSL, then continue.
#-------------------------------------------------------------------------------
# 1) Determine sudo usage
#-------------------------------------------------------------------------------
#if [[ "$(id -u)" -ne 0 ]]; then
#  SUDO="sudo"
#else
#  SUDO=""
#fi

#-------------------------------------------------------------------------------
# 2) Helper: Get latest non-prerelease tag from GitHub
#-------------------------------------------------------------------------------
#get_latest_release() {
#  curl -s "https://api.github.com/repos/$1/releases" \
#    | jq -r '[.[] | select(.prerelease==false)][0].tag_name' \
#    | sed 's/^v//'
#}

#-------------------------------------------------------------------------------
# 3) Compute OS/ARCH for GitHub asset names
#-------------------------------------------------------------------------------
#OS=$(uname | tr '[:upper:]' '[:lower:]')
#RAW_ARCH=$(uname -m)
#case "$RAW_ARCH" in
#  x86_64) ARCH="amd64" ;;
#  aarch64|arm64) ARCH="arm64" ;;
#  *) echo "❌ Unsupported architecture: $RAW_ARCH" >&2; exit 1 ;;
#esac
#
#BIN_DIR="/usr/local/bin"

#-------------------------------------------------------------------------------
# 4) Install sops if missing
#-------------------------------------------------------------------------------
#if ! command -v sops &>/dev/null; then
#  echo "🔧 Installing sops..."
#  SOPS_VER=$(get_latest_release "getsops/sops")
#  SOPS_ASSET="sops-v${SOPS_VER}.linux.${ARCH}"
#  SOPS_URL="https://github.com/getsops/sops/releases/download/v${SOPS_VER}/${SOPS_ASSET}"
#
#  curl -fL -o "${SOPS_ASSET}" "${SOPS_URL}"
#  chmod +x "${SOPS_ASSET}"
#  $SUDO mv "${SOPS_ASSET}" "${BIN_DIR}/sops"
#  echo "✅ sops v${SOPS_VER} installed"
#else
#  echo "✅ sops already installed: $(which sops)"
#fi

#-------------------------------------------------------------------------------
# 5) Install age & age-keygen if either is missing
#-------------------------------------------------------------------------------
#missing_bins=()
#for cmd in age age-keygen; do
#  if ! command -v $cmd &>/dev/null; then
#    missing_bins+=($cmd)
#  fi
#done
#
#if (( ${#missing_bins[@]} )); then
#  echo "🔧 Installing: ${missing_bins[*]}..."
#
#  AGE_VER=$(get_latest_release "FiloSottile/age")
#  TARFILE="age-v${AGE_VER}-linux-${ARCH}.tar.gz"
#  AGE_URL="https://github.com/FiloSottile/age/releases/download/v${AGE_VER}/${TARFILE}"
#
#  curl -fL -o "${TARFILE}" "${AGE_URL}"
#
#  # Extract all binaries into a temp dir
#  TMPDIR=$(mktemp -d)
#  tar -xzf "${TARFILE}" -C "${TMPDIR}"
#
#  # Move only the missing ones
#  for bin in "${missing_bins[@]}"; do
#    if [[ -f "${TMPDIR}/${bin}" ]]; then
#      chmod +x "${TMPDIR}/${bin}"
#      $SUDO mv "${TMPDIR}/${bin}" "${BIN_DIR}/${bin}"
#      echo "✅ ${bin} v${AGE_VER} installed"
#    else
#      echo "⚠️ ${bin} not found in archive" >&2
#    fi
#  done
#
#  rm -rf "${TMPDIR}" "${TARFILE}"
#else
#  echo "✅ age and age-keygen already installed"
#fi
#
#echo "🎉 All done — sops, age & age-keygen are ready to go!"


#install_helmfile() {
#  # Ensure required tools are present
#  for pkg in curl tar; do
#    if ! command -v "$pkg" &>/dev/null; then
#      echo "Installing missing dependency: $pkg"
#      sudo apt-get update -qq
#      sudo apt-get install -y "$pkg"
#    fi
#  done
#
#  # Fetch latest Helmfile release tag
#  local version
#  version=$(curl -fsSL https://api.github.com/repos/helmfile/helmfile/releases/latest \
#    | grep '"tag_name"' \
#    | head -n1 \
#    | cut -d '"' -f4)
#
#  echo "Latest Helmfile version: $version"
#
#  # Map uname arch → asset
#  local arch os asset url tmpdir ver
#  os=linux
#  ver=${version#v}
#
#  case "$(uname -m)" in
#    x86_64) arch=amd64 ;;
#    aarch64|arm64) arch=arm64 ;;
#    *)
#      echo "Unsupported architecture: $(uname -m)"
#      return 1
#      ;;
#  esac
#
#  asset="helmfile_${ver}_${os}_${arch}.tar.gz"
#  url="https://github.com/helmfile/helmfile/releases/download/${version}/${asset}"
#
#  # Download & install
#  tmpdir=$(mktemp -d)
#  echo "Downloading $url"
#  curl -fsSL "$url" -o "$tmpdir/helmfile.tar.gz"
#  tar -xzf "$tmpdir/helmfile.tar.gz" -C "$tmpdir"
#  chmod +x "$tmpdir/helmfile"
#  sudo mv "$tmpdir/helmfile" /usr/local/bin/helmfile
#  rm -rf "$tmpdir"
#
#  echo "✅ helmfile installed successfully."
#}
#
## --- Ensure helmfile is installed ---
#if command -v helmfile &>/dev/null; then
#  echo "✅ helmfile is already installed: $(which helmfile)"
#else
#  echo "🔧 helmfile not found. Installing now..."
#  install_helmfile
#fi
#
#helmfile --version

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
