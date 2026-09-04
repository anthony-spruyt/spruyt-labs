{{- /* KubeProxyConfig is rejected on workers, so the v1.13 form lives in all/. */ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
{{- end }}
