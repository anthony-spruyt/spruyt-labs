{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.serial == "MQ19B55500378"
{{- else }}
machine:
  install:
    diskSelector:
      serial: MQ19B55500378
{{- end }}
