{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.serial == "MQ11W14606696"
{{- else }}
machine:
  install:
    diskSelector:
      serial: MQ11W14606696
{{- end }}
