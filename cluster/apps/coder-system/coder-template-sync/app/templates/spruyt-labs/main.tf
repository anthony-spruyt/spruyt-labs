terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # <3.x: v3 pod identity tracking trips "Unexpected Identity Change" on refresh, blocking recreate.
      version = "~> 2.38"
    }
    envbuilder = {
      source  = "coder/envbuilder"
      version = "~> 1.0"
    }
  }
}

provider "coder" {}
provider "kubernetes" {
  config_path = null
}
provider "envbuilder" {}

data "coder_provisioner" "me" {}
data "coder_workspace" "me" {}
data "coder_workspace_owner" "me" {}

data "kubernetes_service_v1" "traefik" {
  metadata {
    name      = "traefik"
    namespace = "traefik"
  }
}

locals {
  namespace      = "coder-workspaces"
  workspace_name = "coder-${lower(data.coder_workspace.me.id)}"
  traefik_lb_ip  = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip

  # Same identity as the write-tier Claude agents, so the owner can approve its PRs with their own account.
  git_author_name  = "spruyt-labs-bot"
  git_author_email = "spruyt-labs-bot@users.noreply.github.com"
  repo_url         = data.coder_parameter.repo.value

  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value

  # renovate: datasource=npm depName=happy
  happy_version = "1.2.5"

  workspace_folder = "/workspaces/${one(regex("([^/:]+?)(?:\\.git)?/?$", local.repo_url))}"
  # Keyed on owner/repo, not workspace name, so new workspaces reuse layers from earlier builds.
  cache_key = replace(lower(one(regex("([^/:]+/[^/:]+?)(?:\\.git)?/?$", split("#", local.repo_url)[0]))), "/[^a-z0-9._/-]/", "-")

  envbuilder_env = {
    "CODER_AGENT_TOKEN" : coder_agent.main.token,
    "CODER_AGENT_URL" : data.coder_workspace.me.access_url,
    "ENVBUILDER_GIT_URL" : local.repo_url,
    "ENVBUILDER_INIT_SCRIPT" : coder_agent.main.init_script,
    "ENVBUILDER_FALLBACK_IMAGE" : data.coder_parameter.fallback_image.value,
    # No /repository/ segment: Nexus docker connectors serve OCI v2 at host root.
    "ENVBUILDER_CACHE_REPO" : "nexus.nexus-system.svc.cluster.local:8083/envbuilder-cache/${local.cache_key}",
    "ENVBUILDER_INSECURE" : "true",
    "ENVBUILDER_WORKSPACE_FOLDER" : local.workspace_folder,
    # Read by devcontainer.json build.args to route Ubuntu apt through Nexus. Ref #988.
    "NEXUS_URL" : "http://nexus.nexus-system.svc.cluster.local:8081",
    # Read by devcontainer.json build.args as the FROM registry; envbuilder ignores mirrors. Ref #3229.
    "BASE_REGISTRY" : "nexus.nexus-system.svc.cluster.local:8082",
    # Mount points kaniko must leave alone: remounts EPERM under Kata, and a rebuilt /etc/claude-code comes back root-only 0750.
    "ENVBUILDER_IGNORE_PATHS" : "/etc/coder,/etc/claude-code,/var/run",
    "ENVBUILDER_GIT_SSH_PRIVATE_KEY_PATH" : "/etc/coder/ssh-keys/id_ed25519",
    "containerWorkspaceFolder" : local.workspace_folder,
    "TZ" : "Australia/Melbourne",
    # Set here, not by Kyverno: Kata isolates the workspace from mutating webhooks. Ref #1043.
    "CLAUDE_CODE_ENABLE_TELEMETRY" : "1",
    "CLAUDE_CODE_ENHANCED_TELEMETRY_BETA" : "1",
    "OTEL_LOG_TOOL_DETAILS" : "1",
    "OTEL_LOG_TOOL_CONTENT" : "1",
    "OTEL_LOG_USER_PROMPTS" : "1",
    "OTEL_METRICS_EXPORTER" : "otlp",
    "OTEL_LOGS_EXPORTER" : "otlp",
    "OTEL_TRACES_EXPORTER" : "otlp",
    "OTEL_EXPORTER_OTLP_PROTOCOL" : "http/protobuf",
    "OTEL_EXPORTER_OTLP_METRICS_ENDPOINT" : "http://vmsingle-victoria-metrics-k8s-stack.observability.svc:8428/opentelemetry/v1/metrics",
    "OTEL_EXPORTER_OTLP_LOGS_ENDPOINT" : "http://victoria-logs-single-server.observability.svc:9428/insert/opentelemetry/v1/logs",
    "OTEL_EXPORTER_OTLP_TRACES_ENDPOINT" : "http://victoria-traces-single-vt-single-server.observability.svc:10428/insert/opentelemetry/v1/traces",
    "OTEL_RESOURCE_ATTRIBUTES" : "agent.namespace=coder-workspaces,workspace.name=${data.coder_workspace.me.name},workspace.owner=${data.coder_workspace_owner.me.name}",
    "SAFE_CHAIN_LOGGING" : "silent"
  }
}

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository URL"
  description  = "Git repository to clone and build from its devcontainer.json. SSH URL required so workspace push uses the mounted signing key at /etc/coder/ssh-keys/id_ed25519. HTTPS URLs are rejected."
  type         = "string"
  mutable      = true
  order        = 1
  default      = "git@github.com:anthony-spruyt/spruyt-labs.git"
  validation {
    regex = "^(git@|ssh://)"
    error = "Repository URL must be an SSH URL (git@host:owner/repo.git or ssh://). HTTPS URLs break git push because the SSH signing key is not used for HTTPS auth."
  }
}

data "coder_parameter" "workspaces_volume_size" {
  name         = "workspaces_volume_size"
  display_name = "Workspaces volume size (GiB)"
  description  = "Size of the /workspaces persistent volume."
  default      = "20"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 5
    max = 200
  }
  order = 3
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home volume size (GiB)"
  description  = "Size of the /home/vscode persistent volume."
  default      = "20"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 50
  }
  order = 4
}

data "coder_parameter" "fallback_image" {
  name         = "fallback_image"
  display_name = "Fallback image"
  description  = "Image used if the devcontainer build fails."
  default      = "codercom/enterprise-base:ubuntu"
  mutable      = true
  order        = 5
}

data "coder_parameter" "devcontainer_builder" {
  name         = "devcontainer_builder"
  display_name = "Devcontainer builder"
  description  = "Envbuilder image used to build the devcontainer."
  # renovate: datasource=docker depName=ghcr.io/coder/envbuilder
  default = "ghcr.io/coder/envbuilder:1.3.0@sha256:b34ade2fb90a8536df76e7a15c6dd8c6352d0ae835a187b13467fa0c8a71e280"
  mutable = true
  order   = 6
}

resource "kubernetes_persistent_volume_claim_v1" "workspaces" {
  metadata {
    name      = "${local.workspace_name}-workspaces"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "${local.workspace_name}-workspaces"
      "app.kubernetes.io/instance" = "${local.workspace_name}-workspaces"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "rbd-fast-delete"
    resources {
      requests = {
        storage = "${data.coder_parameter.workspaces_volume_size.value}Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "containers" {
  metadata {
    name      = "${local.workspace_name}-containers"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "${local.workspace_name}-containers"
      "app.kubernetes.io/instance" = "${local.workspace_name}-containers"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "rbd-fast-delete"
    volume_mode        = "Block"
    resources {
      requests = {
        storage = "40Gi"
      }
    }
  }
}

resource "kubernetes_persistent_volume_claim_v1" "home" {
  metadata {
    name      = "${local.workspace_name}-home"
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "${local.workspace_name}-home"
      "app.kubernetes.io/instance" = "${local.workspace_name}-home"
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }
  wait_until_bound = false
  spec {
    access_modes       = ["ReadWriteOnce"]
    storage_class_name = "rbd-fast-delete"
    resources {
      requests = {
        storage = "${data.coder_parameter.home_volume_size.value}Gi"
      }
    }
  }
}

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    cd "${local.workspace_folder}"

    if [ -b /dev/containers-disk ]; then
      if ! sudo blkid /dev/containers-disk >/dev/null 2>&1; then
        sudo mkfs.ext4 -q -L containers /dev/containers-disk
      fi
      sudo mkdir -p /var/lib/containers
      sudo mount -o noatime /dev/containers-disk /var/lib/containers || true
    fi

    if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
      mkdir -p /home/vscode/.kube
      cat > /home/vscode/.kube/config <<KUBEEOF
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: /var/run/secrets/kubernetes.io/serviceaccount/ca.crt
        server: https://kubernetes.default.svc
      name: default
    contexts:
    - context:
        cluster: default
        namespace: coder-workspaces
        user: default
      name: default
    current-context: default
    users:
    - name: default
      user:
        tokenFile: /var/run/secrets/kubernetes.io/serviceaccount/token
    KUBEEOF
    fi

    # Symlinks, not copies: rotated Secrets reach the mounts, copies would go stale.
    mkdir -p /home/vscode/.terraform.d /home/vscode/.config/gh
    ln -sfn /etc/coder/terraform.d/credentials.tfrc.json /home/vscode/.terraform.d/credentials.tfrc.json
    ln -sfn /etc/coder/gh/hosts.yml /home/vscode/.config/gh/hosts.yml

    git config --global gpg.format ssh
    git config --global user.signingKey /etc/coder/ssh-keys/id_ed25519
    git config --global commit.gpgSign true
    git config --global tag.gpgSign true

    mkdir -p /home/vscode/.local/bin
    cat > /home/vscode/.local/bin/git-allowed-signers <<'SIGNERSEOF'
    #!/bin/sh
    # Rerun after a key rotation if git verify-commit reports "No principal matched".
    f=/home/vscode/.config/git/allowed_signers
    mkdir -p /home/vscode/.config/git
    {
      echo "${local.git_author_email} $(cut -d' ' -f1,2 /etc/coder/ssh-keys/id_ed25519.pub)"
      curl -fsS --max-time 10 https://api.github.com/users/spruyt-labs-bot/ssh_signing_keys |
        jq -r '.[] | "${local.git_author_email} " + .key'
    } >"$f.tmp" && mv "$f.tmp" "$f"
    git config --global gpg.ssh.allowedSignersFile "$f"
    SIGNERSEOF
    chmod +x /home/vscode/.local/bin/git-allowed-signers
    /home/vscode/.local/bin/git-allowed-signers || true

    # The mounted talosconfig has no nodes and can't be edited. Default -n for read-only
    # commands only: os:operator can reboot and restart services, so never default those to every node.
    cat > /home/vscode/.local/bin/talosctl <<'TALOSEOF'
    #!/bin/sh
    for a in "$@"; do
      case "$a" in
        -n | -n* | --nodes | --nodes=*) exec /usr/local/bin/talosctl "$@" ;;
      esac
    done
    if [ "$1" = service ] || [ "$1" = services ]; then
      for a in "$@"; do
        case "$a" in start | stop | restart) exec /usr/local/bin/talosctl "$@" ;; esac
      done
    fi
    case "$1 $2" in
      "etcd members" | "etcd status") sel=node-role.kubernetes.io/control-plane ;;
      version\ * | get\ * | service\ * | services\ * | logs\ *| dmesg\ * | containers\ * | stats\ * | processes\ * | \
        memory\ * | mounts\ * | disks\ * | time\ * | events\ * | netstat\ * | cgroups\ * | dashboard\ *) sel= ;;
      *) exec /usr/local/bin/talosctl "$@" ;;
    esac
    nodes=$(kubectl get nodes -l "$sel" -o jsonpath='{.items[*].status.addresses[?(@.type=="InternalIP")].address}' | tr ' ' ',')
    [ -n "$nodes" ] || exec /usr/local/bin/talosctl "$@"
    exec /usr/local/bin/talosctl -n "$nodes" "$@"
    TALOSEOF
    chmod +x /home/vscode/.local/bin/talosctl
  EOT

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
    GIT_SSH_COMMAND     = "ssh -i /etc/coder/ssh-keys/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
    TALOSCONFIG         = "/etc/coder/talos/config"
    SOPS_AGE_KEY_FILE   = "/etc/coder/sops/age.key"
  }

  metadata {
    display_name = "CPU Usage"
    key          = "0_cpu_usage"
    script       = "coder stat cpu"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "RAM Usage"
    key          = "1_ram_usage"
    script       = "coder stat mem"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Workspaces Disk"
    key          = "3_workspaces_disk"
    script       = "coder stat disk --path /workspaces"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "Home Disk"
    key          = "4_home_disk"
    script       = "coder stat disk --path /home/vscode"
    interval     = 60
    timeout      = 1
  }

  metadata {
    display_name = "CPU Usage (Host)"
    key          = "5_cpu_usage_host"
    script       = "coder stat cpu --host"
    interval     = 10
    timeout      = 1
  }

  metadata {
    display_name = "Memory Usage (Host)"
    key          = "6_mem_usage_host"
    script       = "coder stat mem --host"
    interval     = 10
    timeout      = 1
  }

  display_apps {
    vscode          = false
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = true
  }
}

# folder set explicitly to bypass the VS Code recent-folder cache bug.
module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = local.workspace_folder
}

resource "coder_script" "code_server" {
  agent_id           = coder_agent.main.id
  display_name       = "code-server"
  icon               = "/icon/code.svg"
  run_on_start       = true
  start_blocks_login = false
  log_path           = "/tmp/code-server.log"
  script             = <<-EOT
    #!/bin/bash
    set -e
    if ! command -v code-server &>/dev/null; then
      curl -fsSL https://code-server.dev/install.sh | flock /tmp/coder-dpkg.lock sh
    fi

    dc="${local.workspace_folder}/.devcontainer/devcontainer.json"
    if [ -f "$dc" ] && command -v jq &>/dev/null; then
      mkdir -p ~/.vscode-server/extensions
      vsix_dir=$(mktemp -d)
      for ext in $(jq -r '.customizations.vscode.extensions[]? // empty' "$dc" 2>/dev/null); do
        src="$ext"
        # code-server resolves IDs against Open VSX; Marketplace-only extensions need the VSIX.
        if ! code-server --install-extension "$ext" &>/dev/null; then
          src="$vsix_dir/$ext.vsix"
          curl -fsSL --compressed --max-time 60 -o "$src" \
            "https://marketplace.visualstudio.com/_apis/public/gallery/publishers/$${ext%%.*}/vsextensions/$${ext#*.}/latest/vspackage" &&
            code-server --install-extension "$src" &>/dev/null || true
        fi
        code-server --extensions-dir ~/.vscode-server/extensions --install-extension "$src" &>/dev/null || true
      done
      rm -rf "$vsix_dir"
    fi

    exec code-server --auth none --port 13337 --host 127.0.0.1 "${local.workspace_folder}"
  EOT
}

resource "coder_app" "code_server" {
  agent_id     = coder_agent.main.id
  slug         = "code-server"
  display_name = "VS Code Web"
  icon         = "/icon/code.svg"
  url          = "http://localhost:13337?folder=${local.workspace_folder}"
  share        = "owner"
  subdomain    = false
  open_in      = "slim-window"

  healthcheck {
    url       = "http://localhost:13337/healthz"
    interval  = 5
    threshold = 6
  }
}

resource "coder_script" "tmux" {
  agent_id           = coder_agent.main.id
  display_name       = "tmux"
  icon               = "/icon/terminal.svg"
  run_on_start       = true
  start_blocks_login = false
  log_path           = "/tmp/tmux-setup.log"
  script             = <<-EOT
    #!/bin/bash
    set -e
    if ! command -v tmux &>/dev/null; then
      # Shared with the code-server script: a second concurrent dpkg run fails on its lock.
      (
        flock 9
        sudo apt-get update -qq
        sudo DEBIAN_FRONTEND=noninteractive apt-get install -y -qq tmux
      ) 9>/tmp/coder-dpkg.lock
    fi
    printf 'set -g mouse on\nset -g history-limit 50000\n' | sudo tee /etc/tmux.conf >/dev/null
    # The happy script waits on this, so its tmux server starts with the config above.
    touch /tmp/coder-tmux-ready

    # Reattach an orphaned session first, so terminals left behind by a closed VS Code come back.
    mkdir -p /home/vscode/.local/bin
    cat > /home/vscode/.local/bin/tmux-term <<'TMUXEOF'
    #!/bin/sh
    command -v tmux >/dev/null 2>&1 || exec bash -l
    s=$(tmux list-sessions -F '#{session_attached} #{session_name}' 2>/dev/null | awk '$1 == 0 { print $2; exit }')
    [ -n "$s" ] && exec tmux attach-session -t "$s"
    exec tmux new-session
    TMUXEOF
    chmod +x /home/vscode/.local/bin/tmux-term

    command -v jq >/dev/null || { echo "jq not found, skipping tmux terminal profile"; exit 0; }
    for f in /home/vscode/.vscode-server/data/Machine/settings.json /home/vscode/.local/share/code-server/Machine/settings.json; do
      mkdir -p "$(dirname "$f")"
      [ -s "$f" ] || echo '{}' >"$f"
      jq '."terminal.integrated.profiles.linux".tmux = {"path": "/home/vscode/.local/bin/tmux-term"} | ."terminal.integrated.defaultProfile.linux" = "tmux"' "$f" >"$f.tmp"
      mv "$f.tmp" "$f"
    done
  EOT
}

resource "coder_script" "happy" {
  agent_id           = coder_agent.main.id
  display_name       = "Happy"
  icon               = "/emojis/1f4f1.png"
  run_on_start       = true
  start_blocks_login = false
  log_path           = "/tmp/happy-setup.log"
  script             = <<-EOT
    #!/bin/bash
    set -e
    command -v npm >/dev/null || { echo "npm not found, skipping Happy"; exit 0; }
    # Scripts skip ~/.bashrc, which is what puts the safe-chain npm shim on PATH.
    npm=/home/vscode/.safe-chain/shims/npm
    [ -x "$npm" ] || npm=npm
    "$npm" ls -g --depth=0 "happy@${local.happy_version}" &>/dev/null ||
      "$npm" install -g --no-fund --no-audit "happy@${local.happy_version}"

    # Happy reads only ~/.claude/settings.json (not project settings) and defaults to adding its co-author ad to commits.
    settings=/home/vscode/.claude/settings.json
    if command -v jq >/dev/null; then
      mkdir -p "$(dirname "$settings")"
      [ -s "$settings" ] || echo '{}' >"$settings"
      jq '.includeCoAuthoredBy = false' "$settings" >"$settings.tmp" && mv "$settings.tmp" "$settings" ||
        { rm -f "$settings.tmp"; echo "WARNING: could not set includeCoAuthoredBy in $settings"; }
      # Auth comes from env, so Claude's first-run, login and folder-trust screens would only block the session.
      state=/home/vscode/.claude.json
      [ -s "$state" ] || (umask 077; echo '{}' >"$state")
      jq --arg d "${local.workspace_folder}" '.hasCompletedOnboarding = true | .projects[$d].hasTrustDialogAccepted = true' "$state" >"$state.tmp" && chmod 600 "$state.tmp" && mv "$state.tmp" "$state" ||
        { rm -f "$state.tmp"; echo "WARNING: could not mark Claude onboarding done in $state"; }
    else
      echo "jq not found, Happy will add its co-author trailer and Claude will show first-run screens"
    fi

    # A regular file is a pairing made in this workspace, so it wins over the template key.
    key=/home/vscode/.happy/access.key
    if [ -f /etc/coder/happy/access.key ] && { [ -L "$key" ] || [ ! -e "$key" ]; }; then
      mkdir -p -m 700 /home/vscode/.happy
      ln -sfn /etc/coder/happy/access.key "$key"
    elif [ -L "$key" ] && [ ! -e "$key" ]; then
      # Dangling once the template secret is gone; Happy would write a new pairing through it into the read-only mount.
      rm -f "$key"
    fi
    # Unpaired, the daemon would block on an interactive QR login; the first `happy` run pairs it.
    [ -f "$key" ] || exit 0
    happy daemon start

    for _ in $(seq 180); do [ -f /tmp/coder-tmux-ready ] && break; sleep 5; done
    [ -f /tmp/coder-tmux-ready ] || { echo "tmux not ready after 15 minutes, not starting a Happy session"; exit 0; }
    # Own socket: a default server started here would hand this script's env to every VS Code terminal.
    if ! tmux -L happy has-session -t happy 2>/dev/null; then
      tmux -L happy new-session -d -s happy -c "${local.workspace_folder}"
      tmux -L happy send-keys -t happy happy Enter
    fi
  EOT
}

resource "kubernetes_pod_v1" "main" {
  count = data.coder_workspace.me.start_count

  depends_on = [
    kubernetes_persistent_volume_claim_v1.workspaces,
    kubernetes_persistent_volume_claim_v1.home,
    kubernetes_persistent_volume_claim_v1.containers,
  ]

  metadata {
    name      = local.workspace_name
    namespace = local.namespace
    labels = {
      "app.kubernetes.io/name"     = "coder-workspace"
      "app.kubernetes.io/instance" = local.workspace_name
      "app.kubernetes.io/part-of"  = "coder"
      "com.coder.resource"         = "true"
      "com.coder.workspace.id"     = data.coder_workspace.me.id
      "com.coder.workspace.name"   = data.coder_workspace.me.name
      "com.coder.user.id"          = data.coder_workspace_owner.me.id
      "com.coder.user.username"    = data.coder_workspace_owner.me.name
    }
    annotations = {
      "com.coder.user.email" = data.coder_workspace_owner.me.email
    }
  }

  spec {
    service_account_name = "coder-workspace-ops"
    restart_policy       = "Never"
    # VM boundary around AI-agent-generated code. Ref #933.
    runtime_class_name               = "kata"
    termination_grace_period_seconds = 300

    node_selector = {
      "kata.spruyt-labs/ready" = "true"
    }

    # Envbuilder builds as root then drops to remoteUser; fs_group keeps PVCs writable after the drop.
    security_context {
      fs_group = 1000
    }

    # Avoids the Cloudflare hairpin for agent downloads.
    host_aliases {
      ip        = local.traefik_lb_ip
      hostnames = [replace(replace(data.coder_workspace.me.access_url, "https://", ""), "http://", "")]
    }

    affinity {
      pod_anti_affinity {
        preferred_during_scheduling_ignored_during_execution {
          weight = 100
          pod_affinity_term {
            topology_key = "kubernetes.io/hostname"
            label_selector {
              match_expressions {
                key      = "app.kubernetes.io/name"
                operator = "In"
                values   = ["coder-workspace"]
              }
            }
          }
        }
      }
    }

    container {
      name              = "dev"
      image             = local.devcontainer_builder_image
      image_pull_policy = "Always"

      # kaniko fails with drop=[ALL] (chown /etc/gshadow); Kata is the isolation boundary.
      security_context {
        privileged                 = true
        allow_privilege_escalation = true
        read_only_root_filesystem  = false
      }

      dynamic "env" {
        for_each = nonsensitive(local.envbuilder_env)
        content {
          name  = env.key
          value = env.value
        }
      }

      # Explicit env beats env_from, so this wins over any stale key in coder-workspace-env-common
      env {
        name = "ENVBUILDER_DOCKER_CONFIG_BASE64"
        value_from {
          secret_key_ref {
            name = "coder-workspace-nexus-clients"
            key  = "ENVBUILDER_DOCKER_CONFIG_BASE64"
          }
        }
      }

      env_from {
        secret_ref {
          name = "coder-workspace-env-common"
        }
      }

      env_from {
        secret_ref {
          name = "coder-workspace-env-spruyt-labs"
        }
      }

      resources {
        requests = {
          cpu    = "500m"
          memory = "8Gi"
        }
        limits = {
          cpu    = "4000m"
          memory = "8Gi"
        }
      }

      volume_mount {
        name       = "workspaces"
        mount_path = "/workspaces"
      }

      volume_mount {
        name       = "home"
        mount_path = "/home/vscode"
      }

      volume_mount {
        name       = "ssh-signing-key"
        mount_path = "/etc/coder/ssh-keys"
        read_only  = true
      }

      volume_mount {
        name       = "gh-hosts"
        mount_path = "/etc/coder/gh"
        read_only  = true
      }

      volume_mount {
        name       = "happy-key"
        mount_path = "/etc/coder/happy"
        read_only  = true
      }

      volume_mount {
        name       = "talosconfig"
        mount_path = "/etc/coder/talos"
        read_only  = true
      }

      volume_mount {
        name       = "terraform-credentials"
        mount_path = "/etc/coder/terraform.d"
        read_only  = true
      }

      volume_mount {
        name       = "sops-age-key"
        mount_path = "/etc/coder/sops"
        read_only  = true
      }

      volume_mount {
        name       = "registries-conf"
        mount_path = "/etc/containers/registries.conf.d/99-nexus-mirror.conf"
        sub_path   = "99-nexus-mirror.conf"
        read_only  = true
      }

      volume_mount {
        name       = "claude-managed-settings"
        mount_path = "/etc/claude-code/managed-settings.json"
        sub_path   = "managed-settings.json"
        read_only  = true
      }

      # Nexus docker-group forces basic auth (rejects anonymous bearer). Ref #976.
      volume_mount {
        name       = "nexus-auth"
        mount_path = "/etc/containers/auth.json"
        sub_path   = "auth.json"
        read_only  = true
      }

      # Root podman's default authfile when XDG_RUNTIME_DIR is unset; /etc/containers/auth.json is never read. Ref #3163.
      volume_mount {
        name       = "nexus-auth"
        mount_path = "/run/containers/0/auth.json"
        sub_path   = "auth.json"
        read_only  = true
      }

      # virtio-blk so podman overlay runs on real ext4, avoiding virtiofs xattr limits.
      volume_device {
        name        = "containers"
        device_path = "/dev/containers-disk"
      }

    }

    volume {
      name = "workspaces"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.workspaces.metadata[0].name
      }
    }

    volume {
      name = "home"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.home.metadata[0].name
      }
    }

    volume {
      name = "containers"
      persistent_volume_claim {
        claim_name = kubernetes_persistent_volume_claim_v1.containers.metadata[0].name
      }
    }

    volume {
      name = "ssh-signing-key"
      secret {
        secret_name  = "github-bot-ssh-key"
        default_mode = "0400"
      }
    }

    volume {
      name = "gh-hosts"
      secret {
        secret_name  = "github-bot-credentials"
        default_mode = "0400"
        items {
          key  = "hosts.yml"
          path = "hosts.yml"
        }
      }
    }

    volume {
      name = "happy-key"
      secret {
        secret_name  = "coder-happy-spruyt-labs"
        default_mode = "0400"
        optional     = true
      }
    }

    volume {
      name = "talosconfig"
      secret {
        secret_name  = "coder-workspace-talos"
        default_mode = "0400"
        items {
          key  = "config"
          path = "config"
        }
      }
    }

    volume {
      name = "terraform-credentials"
      secret {
        secret_name  = "coder-terraform-credentials"
        default_mode = "0400"
        items {
          key  = "credentials.tfrc.json"
          path = "credentials.tfrc.json"
        }
      }
    }

    volume {
      name = "sops-age-key"
      secret {
        secret_name  = "coder-age-key"
        default_mode = "0400"
        items {
          key  = "age.key"
          path = "age.key"
        }
      }
    }

    volume {
      name = "registries-conf"
      config_map {
        name         = "coder-workspace-registries-conf"
        default_mode = "0444"
      }
    }

    volume {
      name = "claude-managed-settings"
      config_map {
        name         = "coder-workspace-claude-managed-settings"
        default_mode = "0444"
      }
    }

    volume {
      name = "nexus-auth"
      secret {
        secret_name  = "coder-workspace-nexus-clients"
        default_mode = "0444"
      }
    }

  }
}

resource "coder_metadata" "container_info" {
  count       = data.coder_workspace.me.start_count
  resource_id = coder_agent.main.id

  item {
    key   = "image"
    value = local.devcontainer_builder_image
  }

  item {
    key   = "repo"
    value = local.repo_url
  }

  item {
    key   = "namespace"
    value = local.namespace
  }
}
