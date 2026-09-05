---
name: block-talosctl-read-s3crets
enabled: true
event: bash
pattern: talosctl\s+.*\bread\b.*(cri\.toml|/system/state/config\.yaml)
action: block
---

**BLOCKED: this node file contains plaintext credentials**

- `/etc/cri/conf.d/cri.toml` holds the registry pull secrets (GHCR, Docker Hub).
- `/system/state/config.yaml` is the full machine config on disk.

`talosctl read` on any other path is fine — only these two are blocked.

**Safe alternatives:**

- List filenames without contents: `talosctl ls /etc/cri/conf.d`
- Read the non-secret CRI fragments: `talosctl read /etc/cri/conf.d/00-base.part`
- Confirm a registry is configured: `talosctl ls /etc/cri/conf.d/hosts`
- Inspect intended CRI config from Git: `talos/patches/all/05-configure-containerd.yaml`
