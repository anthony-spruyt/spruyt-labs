{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.serial == "MP46W15115349"
{{- else }}
machine:
  install:
    diskSelector:
      serial: MP46W15115349
{{- end }}
