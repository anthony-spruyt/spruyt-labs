---
name: block-talosctl-read-s3crets
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '^talosctl\b.*\s(?:read|cat|copy|cp)\s(?:.*\s)?\S*(?:cri\.toml|/system/state/config\.yaml)'
    fallback: 'talosctl\s+.*\b(?:read|cat|copy|cp)\b.*(cri\.toml|/system/state/config\.yaml)'
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
