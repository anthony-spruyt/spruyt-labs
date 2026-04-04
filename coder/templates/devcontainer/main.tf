terraform {
  required_version = ">= 1.0"
  required_providers {
    coder = {
      source  = "coder/coder"
      version = "~> 2.0"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
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
  namespace      = "coder-system"
  workspace_name = "coder-${lower(data.coder_workspace.me.id)}"
  # Traefik LB IP for hostAliases (avoids Cloudflare hairpin for agent downloads)
  traefik_lb_ip = data.kubernetes_service_v1.traefik.status[0].load_balancer[0].ingress[0].ip

  git_author_name  = coalesce(data.coder_workspace_owner.me.full_name, data.coder_workspace_owner.me.name)
  git_author_email = data.coder_workspace_owner.me.email
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
    "ENVBUILDER_CACHE_REPO" : "ghcr.io/anthony-spruyt/envbuilder-cache/${data.coder_workspace.me.name}",
    "ENVBUILDER_WORKSPACE_FOLDER" : local.workspace_folder,
    # Expose as shell variable so devcontainer.json lifecycle commands
    # using ${containerWorkspaceFolder} expand correctly under envbuilder.
    "containerWorkspaceFolder" : local.workspace_folder,
  }
}

# ---------------------------------------------------------------------------
# Parameters
# ---------------------------------------------------------------------------

data "coder_parameter" "repo" {
  name         = "repo"
  display_name = "Repository URL"
  description  = "Git repository to clone and build from its devcontainer.json."
  type         = "string"
  mutable      = true
  order        = 1
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

    # Start Docker daemon (envbuilder doesn't run DinD feature entrypoint)
    if command -v dockerd &>/dev/null && ! docker info &>/dev/null 2>&1; then
      echo "Starting Docker daemon..."
      sudo dockerd --iptables=false &>/tmp/dockerd.log &
      # Wait for Docker to be ready
      for i in $(seq 1 30); do
        docker info &>/dev/null 2>&1 && break
        sleep 1
      done
    fi

    # Configure git commit signing using the read-only SSH key mount.
    # Points directly at the secret volume so key rotation takes effect
    # without a workspace restart (~1 min propagation delay).
    git config --global gpg.format ssh
    git config --global user.signingKey /home/vscode/.ssh-keys/id_ed25519
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
    GIT_SSH_COMMAND = "ssh -i /home/vscode/.ssh-keys/id_ed25519 -o IdentitiesOnly=yes -o StrictHostKeyChecking=accept-new"
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
  start_blocks_login = true
  script             = <<-EOT
    #!/bin/bash
    set -e
    if ! command -v code-server &>/dev/null; then
      curl -fsSL https://code-server.dev/install.sh | sh
    fi
    code-server --auth none --port 13337 --host 127.0.0.1 "${local.workspace_folder}" &
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
    service_account_name = "coder-workspace"
    restart_policy       = "Never"

    # Root required for Docker-in-Docker; remoteUser in devcontainer.json
    # switches the agent shell to vscode.
    security_context {
      run_as_user = 0
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

      security_context {
        privileged = true
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
        mount_path = "/home/vscode/.ssh-keys"
        read_only  = true
      }

      # Talosconfig -> ~/.talos/config
      volume_mount {
        name       = "talosconfig"
        mount_path = "/home/vscode/.talos"
        read_only  = true
      }

      # Terraform credentials -> ~/.terraform.d/credentials.tfrc.json
      volume_mount {
        name       = "terraform-credentials"
        mount_path = "/home/vscode/.terraform.d"
        read_only  = true
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
