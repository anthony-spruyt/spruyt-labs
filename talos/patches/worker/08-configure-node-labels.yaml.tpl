{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  bgp: "65050"
  kata.spruyt-labs/ready: "true"
{{- else }}
machine:
  nodeLabels:
    bgp: "65050"
    kata.spruyt-labs/ready: "true"
{{- end }}
