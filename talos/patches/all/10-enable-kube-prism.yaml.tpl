{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubePrismConfig
port: 7445
{{- else }}
machine:
  features:
    kubePrism:
      enabled: true
      port: 7445
{{- end }}
