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
      version = "~> 3.0"
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

  git_author_name = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  # Prefer the GitHub noreply address (see `git_email` parameter) so commits
  # verify without leaking the SSO email and without relying on the SSO email
  # being added to the GitHub account. Falls back to the Coder profile email
  # when the parameter is blank (e.g. forks of this template).
  git_author_email = coalesce(data.coder_parameter.git_email.value, data.coder_workspace_owner.me.email)
  repo_url         = data.coder_parameter.repo.value

  devcontainer_builder_image = data.coder_parameter.devcontainer_builder.value

  workspace_folder = "/workspaces/${replace(element(split("/", replace(local.repo_url, ".git", "")), length(split("/", replace(local.repo_url, ".git", ""))) - 1), ".git", "")}"

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
    # Skip kaniko remount of secret volumes during build — mount(2) EPERMs
    # inside Kata+PSA=baseline (no CAP_SYS_ADMIN). Secrets are still
    # accessible at runtime via the k8s volume mounts themselves.
    "ENVBUILDER_IGNORE_PATHS" : "/etc/coder,/var/run",
    "ENVBUILDER_GIT_SSH_PRIVATE_KEY_PATH" : "/etc/coder/ssh-keys/id_ed25519",
    # Expose as shell variable so devcontainer.json lifecycle commands
    # using ${containerWorkspaceFolder} expand correctly under envbuilder.
    "containerWorkspaceFolder" : local.workspace_folder,
  }
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

data "coder_parameter" "git_email" {
  name         = "git_email"
  display_name = "Git commit email"
  description  = "Email used for git author/committer and SSH signature verification. Must be a GitHub-verified email on anthony-spruyt's account. Defaults to the GitHub noreply address so commits verify without leaking personal email."
  type         = "string"
  mutable      = true
  order        = 2
  default      = "99536297+anthony-spruyt@users.noreply.github.com"
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
  order = 2
}

data "coder_parameter" "home_volume_size" {
  name         = "home_volume_size"
  display_name = "Home volume size (GiB)"
  description  = "Size of the /home/vscode persistent volume."
  default      = "5"
  type         = "number"
  icon         = "/emojis/1f4be.png"
  mutable      = false
  validation {
    min = 1
    max = 50
  }
  order = 3
}

data "coder_parameter" "fallback_image" {
  name         = "fallback_image"
  display_name = "Fallback image"
  description  = "Image used if the devcontainer build fails."
  default      = "codercom/enterprise-base:ubuntu"
  mutable      = true
  order        = 4
}

data "coder_parameter" "devcontainer_builder" {
  name         = "devcontainer_builder"
  display_name = "Devcontainer builder"
  description  = "Envbuilder image used to build the devcontainer. Pin to a specific release in production."
  default      = "ghcr.io/coder/envbuilder:latest"
  mutable      = true
  order        = 5
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
  dir  = local.workspace_folder

  startup_script = <<-EOT
    set -e

    # Rootful podman runtime dir (required by podman inside Kata VM).
    sudo mkdir -p /run/user/1000
    sudo chown 1000:1000 /run/user/1000

    # Relax /etc/containers perms so rootless podman (which strips supplementary
    # groups inside its user namespace) can read storage.conf, registries.conf.d/*,
    # and containers.conf.d/*. Image ships these as 0750 root:root which is
    # unreadable from inside the userns. Ref #976.
    sudo chmod a+rx /etc/containers /etc/containers/registries.conf.d 2>/dev/null || true
    [ -d /etc/containers/containers.conf.d ] && sudo chmod a+rx /etc/containers/containers.conf.d

    # Direct-assigned block device for podman storage. First boot: mkfs.
    # Subsequent boots: detect existing ext4 and mount.
    if [ -b /dev/containers-disk ]; then
      if ! sudo blkid /dev/containers-disk >/dev/null 2>&1; then
        sudo mkfs.ext4 -q -L containers /dev/containers-disk
      fi
      sudo mkdir -p /var/lib/containers
      sudo mount -o noatime /dev/containers-disk /var/lib/containers || true
    fi
    export XDG_RUNTIME_DIR=/run/user/1000

    # SA token is mounted read-only as root. Copy to readable location for vscode.
    if [ -f /var/run/secrets/kubernetes.io/serviceaccount/token ]; then
      sudo cp /var/run/secrets/kubernetes.io/serviceaccount/token /tmp/sa-token
      sudo chmod 644 /tmp/sa-token
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
        tokenFile: /tmp/sa-token
    KUBEEOF
    fi

    # Symlink read-only secret mounts into home directory
    ln -sfn /etc/coder/talos /home/vscode/.talos

    # Terraform credentials are root-only on projected volume, copy to readable location
    mkdir -p /home/vscode/.terraform.d
    sudo cp /etc/coder/terraform.d/credentials.tfrc.json /home/vscode/.terraform.d/credentials.tfrc.json
    sudo chown vscode:vscode /home/vscode/.terraform.d/credentials.tfrc.json

    # Configure git commit signing using the read-only SSH key mount.
    # Points directly at the secret volume so key rotation takes effect
    # without a workspace restart (~1 min propagation delay).
    git config --global gpg.format ssh
    git config --global user.signingKey /etc/coder/ssh-keys/id_ed25519
    git config --global commit.gpgSign true
    git config --global tag.gpgSign true
  EOT

  env = {
    GIT_AUTHOR_NAME     = local.git_author_name
    GIT_AUTHOR_EMAIL    = local.git_author_email
    GIT_COMMITTER_NAME  = local.git_author_name
    GIT_COMMITTER_EMAIL = local.git_author_email
    # SSH auth uses the read-only key mount directly — no copy needed.
    # Key rotation propagates automatically via Kubernetes secret volume refresh.
    GIT_SSH_COMMAND = "ssh -i /etc/coder/ssh-keys/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
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
    vscode          = true
    vscode_insiders = false
    web_terminal    = true
    ssh_helper      = true
  }
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
    service_account_name = "coder-workspace-admin"
    restart_policy       = "Never"
    # Kata Containers: each workspace pod runs in its own lightweight VM
    # (QEMU/Cloud Hypervisor + KVM). Hypervisor boundary around arbitrary
    # AI-agent-generated code inside the workspace. Ref #933.
    runtime_class_name = "kata"

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
          weight = 1
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

      # All keys in coder-workspace-env are injected as environment variables
      env_from {
        secret_ref {
          name = "coder-workspace-env"
        }
      }

      # MCP API keys synced from traefik ns via ExternalSecret
      env_from {
        secret_ref {
          name = "coder-workspace-mcp-api-keys"
        }
      }

      resources {
        requests = {
          cpu    = "2000m"
          memory = "4Gi"
        }
        limits = {
          cpu    = "8000m"
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

      # Talosconfig (symlinked to ~/.talos in startup script)
      volume_mount {
        name       = "talosconfig"
        mount_path = "/etc/coder/talos"
        read_only  = true
      }

      # Terraform credentials (symlinked to ~/.terraform.d in startup script)
      volume_mount {
        name       = "terraform-credentials"
        mount_path = "/etc/coder/terraform.d"
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
        secret_name  = "coder-ssh-signing-key"
        default_mode = "0400"
      }
    }

    # Mount only the talosconfig key as "config" file
    volume {
      name = "talosconfig"
      secret {
        secret_name  = "coder-talosconfig"
        default_mode = "0400"
        items {
          key  = "config"
          path = "config"
        }
      }
    }

    # Mount only the terraform credentials key as "credentials.tfrc.json"
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
      name = "registries-conf"
      config_map {
        name         = "coder-workspace-registries-conf"
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
