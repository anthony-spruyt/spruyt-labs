{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: UnattendedInstallConfig
provisioning:
  diskSelector:
    match: disk.serial == "50026B76874DDE95" # Kinston
    # match: disk.serial == "P300ADBB25032802523" # Patriot
{{- else }}
machine:
  install:
    diskSelector:
      serial: 50026B76874DDE95 # Kinston
      # serial: P300ADBB25032802523 # Patriot
{{- end }}
