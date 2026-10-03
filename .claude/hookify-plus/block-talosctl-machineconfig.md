---
name: block-talosctl-machineconfig
enabled: true
event: bash
action: block
mask_data: true
conditions:
  - field: command
    operator: command_match
    pattern: '^talosctl\b(?=.*\sget\s)(?=.*\s(?:machineconfigs?|mc)(?:\.[\w.]+)?(?=\s|$))(?=.*[\s''](?:-o\s*=?\s*|--output[=\s]\s*)''?(?:yaml|json|jsonpath))'
    fallback: 'talosctl\s+.*get\s+(?:machineconfigs?|mc)\b.*(?:-o\s*=?\s*|--output[=\s]\s*)(yaml|json|jsonpath)'
---

**BLOCKED: talosctl get machineconfig output contains decrypted secrets**

Machine config includes plaintext registry passwords, tokens, and other credentials.

**Safe alternatives:**

- Check specific resources: `talosctl get kubeletconfig -o yaml`
- List machine config versions without contents: `talosctl get machineconfig`
- Inspect intended config from Git: `talos/patches/`
