{{- /* SecurityProfileConfig does not exist before Talos v1.14. */ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.TalosVersion) }}
---
apiVersion: v1alpha1
kind: SecurityProfileConfig
# Under the sandbox a hostPID pod sees the sandbox namespace, not the host, which
# breaks irq-balance and kata-tap-qdisc-fix. Enable once those run clean under sandboxd.
workloadIsolation: false
{{- end }}
