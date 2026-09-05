{{- /* KubeProxyConfig is rejected on workers, so this lives in control-plane/. */ -}}
---
apiVersion: v1alpha1
kind: KubeProxyConfig
enabled: false
