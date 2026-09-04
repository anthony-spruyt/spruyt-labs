{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.serial == "P300ADBB25032802429"
{{- else }}
machine:
  install:
    diskSelector:
      serial: P300ADBB25032802429
{{- end }}
