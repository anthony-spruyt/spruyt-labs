---
name: block-talosctl-machineconfig
enabled: true
event: bash
pattern: talosctl\s+.*get\s+machineconfig.*-o\s+(yaml|json)
action: block
---

**BLOCKED: talosctl get machineconfig output contains decrypted secrets**

Machine config includes plaintext registry passwords, tokens, and other credentials.

**Safe alternatives:**
- Check specific resources: `talosctl get kubeletconfig -o yaml`
- Filter secrets: `talosctl get machineconfig -o yaml | grep -v "password\|token\|secret"`
- Check registry presence: `talosctl get machineconfig -o yaml | grep -B1 -A2 "ghcr\|docker" | grep -v "password\|username"`
