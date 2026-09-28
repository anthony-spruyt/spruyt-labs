terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source = "hashicorp/kubernetes"
      # Pinned below 3.x — the new identity tracking on kubernetes_pod_v1
      # trips "Unexpected Identity Change" on refresh for pods created by
      # previous plan iterations, blocking destroy/recreate. See
      # hashicorp/terraform-provider-kubernetes issues around v3.0.
      version = "~> 2.38"
    }
    envbuilder = {
      source  = "coder/envbuilder"
      version = "~> 1.0"
    }
  }
}

provider "coder" {}
# Coder runs inside the cluster; authenticate via its ServiceAccount.
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
  # Traefik LB IP for hostAliases (avoids Cloudflare hairpin for agent downloads)
  traefik_lb_ip = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip

  # Same identity as the write-tier Claude agents, so the owner can approve its PRs with their own account.
  git_author_name  = "spruyt-labs-bot"
  git_author_email = "spruyt-labs-bot@users.noreply.github.com"
  repo_url         = data.coder_parameter.repo.value

  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value

  workspace_folder = "/workspaces/${one(regex("([^/:]+?)(?:\\.git)?/?$", local.repo_url))}"

  # Environment variables passed into the envbuilder container.
  envbuilder_env = {
    "CODER_AGENT_TOKEN" : coder_agent.main.token,
    "CODER_AGENT_URL" : data.coder_workspace.me.access_url,
    "ENVBUILDER_GIT_URL" : local.repo_url,
    "ENVBUILDER_INIT_SCRIPT" : coder_agent.main.init_script,
    "ENVBUILDER_FALLBACK_IMAGE" : data.coder_parameter.fallback_image.value,
    # Cache pushes hit the envbuilder-cache hosted repo on its own connector (8083).
    # Pulls/mirror go through the docker-group connector (8082).
    # URL has NO /repository/ segment — Nexus docker connectors serve OCI v2 at host-root.
    "ENVBUILDER_CACHE_REPO" : "nexus.nexus-system.svc.cluster.local:8083/envbuilder-cache/${data.coder_workspace.me.name}",
    "KANIKO_REGISTRY_MIRROR" : "nexus.nexus-system.svc.cluster.local:8082",
    "ENVBUILDER_INSECURE" : "true",
    "ENVBUILDER_WORKSPACE_FOLDER" : local.workspace_folder,
    # Substituted into devcontainer.json build.args.NEXUS_URL via
    # envbuilder's SubstituteVars (treats ${localEnv:NEXUS_URL} as an env
    # lookup in the envbuilder process). Routes base-layer Ubuntu archive
    # apt traffic through the in-cluster Nexus apt-ubuntu-proxy. Ref #988.
    "NEXUS_URL" : "http://nexus.nexus-system.svc.cluster.local:8081",
    # Skip kaniko remount of secret volumes during build — mount(2) EPERMs
    # inside Kata+PSA=baseline (no CAP_SYS_ADMIN). Secrets are still
    # accessible at runtime via the k8s volume mounts themselves.
    "ENVBUILDER_IGNORE_PATHS" : "/etc/coder,/var/run",
    "ENVBUILDER_GIT_SSH_PRIVATE_KEY_PATH" : "/etc/coder/ssh-keys/id_ed25519",
    # Expose as shell variable so devcontainer.json lifecycle commands
    # using ${containerWorkspaceFolder} expand correctly under envbuilder.
    "containerWorkspaceFolder" : local.workspace_folder,
    "TZ" : "Australia/Melbourne",
    # Claude Code CLI OpenTelemetry — full audit visibility (#1043).
    # Kata isolates workspace from cluster Kyverno mutating webhooks, so OTel
    # env must be set on the pod template directly. Endpoints resolve to the
    # observability-namespace VictoriaMetrics/Logs/Traces backends.
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

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository URL"
  description  = "Git repository to clone and build from its devcontainer.json. SSH URL required so workspace push uses the mounted signing key at /etc/coder/ssh-keys/id_ed25519. HTTPS URLs are rejected."
  type         = "string"
  mutable      = true
  order        = 2
  default      = "git@github.com:anthony-spruyt/xfg.git"
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

# ---------------------------------------------------------------------------
# Persistent volumes
# ---------------------------------------------------------------------------

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

# ---------------------------------------------------------------------------
# Coder agent
# ---------------------------------------------------------------------------

resource "coder_agent" "main" {
  arch = data.coder_provisioner.me.arch
  os   = "linux"

  startup_script = <<-EOT
    set -e
    cd "${local.workspace_folder}"

    # Direct-assigned block device for podman storage. First boot: mkfs.
    # Subsequent boots: detect existing ext4 and mount.
    if [ -b /dev/containers-disk ]; then
      if ! sudo blkid /dev/containers-disk >/dev/null 2>&1; then
        sudo mkfs.ext4 -q -L containers /dev/containers-disk
      fi
      sudo mkdir -p /var/lib/containers
      sudo mount -o noatime /dev/containers-disk /var/lib/containers || true
    fi

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

    # Symlink, not a copy: the rotated token reaches the mount, a copy would go stale.
    mkdir -p /home/vscode/.config/gh
    ln -sfn /etc/coder/gh/hosts.yml /home/vscode/.config/gh/hosts.yml
  EOT

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
    GIT_SSH_COMMAND     = "ssh -i /etc/coder/ssh-keys/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
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

# ---------------------------------------------------------------------------
# VS Code Desktop (explicit folder bypass for recent-folder cache bug)
# ---------------------------------------------------------------------------

module "vscode" {
  count    = data.coder_workspace.me.start_count
  source   = "registry.coder.com/coder/vscode-desktop/coder"
  version  = "1.3.0"
  agent_id = coder_agent.main.id
  folder   = local.workspace_folder
}

# ---------------------------------------------------------------------------
# code-server (VS Code in browser)
# ---------------------------------------------------------------------------

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
      curl -fsSL https://code-server.dev/install.sh | sh
    fi

    # Install extensions from devcontainer.json for both VS Code Web and Desktop
    dc="${local.workspace_folder}/.devcontainer/devcontainer.json"
    if [ -f "$dc" ] && command -v jq &>/dev/null; then
      mkdir -p ~/.vscode-server/extensions
      for ext in $(jq -r '.customizations.vscode.extensions[]? // empty' "$dc" 2>/dev/null); do
        code-server --install-extension "$ext" &>/dev/null || true
        code-server --extensions-dir ~/.vscode-server/extensions --install-extension "$ext" &>/dev/null || true
      done
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

# ---------------------------------------------------------------------------
# Workspace Pod
# ---------------------------------------------------------------------------

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
    service_account_name            = "coder-workspace"
    automount_service_account_token = false
    restart_policy                  = "Never"
    # Kata Containers: each workspace pod runs in its own lightweight VM
    # (QEMU/Cloud Hypervisor + KVM). Hypervisor boundary around arbitrary
    # AI-agent-generated code inside the workspace. Ref #933.
    runtime_class_name               = "kata"
    termination_grace_period_seconds = 300

    node_selector = {
      "kata.spruyt-labs/ready" = "true"
    }

    # Envbuilder requires root during image build (kaniko). It drops to
    # the devcontainer.json remoteUser (vscode, UID 1000) before exec'ing
    # the init command. PSA=privileged on coder-workspaces permits this.
    # fs_group kept so PVC mounts are group-writable by vscode after drop.
    security_context {
      fs_group = 1000
    }

    # Resolve access URL to Traefik LB internally (avoids Cloudflare hairpin)
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

      # Envbuilder/kaniko need default container caps (CHOWN, FOWNER,
      # DAC_OVERRIDE, SETUID, SETGID, etc) to extract image layers —
      # empirically fails with drop=[ALL] on chown /etc/gshadow.
      # Kata runtime provides the real isolation boundary.
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

      # All keys in coder-workspace-env-common are injected as environment variables
      env_from {
        secret_ref {
          name = "coder-workspace-env-common"
        }
      }

      # All keys in coder-workspace-env-xfg are injected as environment variables
      env_from {
        secret_ref {
          name = "coder-workspace-env-xfg"
        }
      }

      resources {
        requests = {
          cpu    = "500m"
          memory = "2Gi"
        }
        limits = {
          cpu    = "4000m"
          memory = "16Gi"
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

      # SSH key (read-only mount, referenced directly via GIT_SSH_COMMAND)
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

      # Podman registries.conf drop-in: route container pulls through Nexus
      # pull-through proxies (docker.io, ghcr.io, quay.io, mcr.microsoft.com,
      # registry.k8s.io). Ref #976.
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

      # Basic-auth credentials for docker-group (8082) + envbuilder-cache
      # (8083). Nexus 3 rejects anonymous bearer tokens on docker-group
      # (forceBasicAuth=true), so workspaces authenticate as the read-only
      # `workspace-puller` user. Ref #976.
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

      # Direct-assigned block device for podman storage. Kata passes the
      # RBD volume into the guest as virtio-blk so the guest kernel sees
      # real ext4 (formatted in startup) and kernel overlay works without
      # virtiofs xattr limitations.
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

# ---------------------------------------------------------------------------
# Metadata displayed in the Coder dashboard
# ---------------------------------------------------------------------------

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
