{{- /* v1.14 replaces this with KubeProxyConfig, which is control-plane only. */ -}}
{{- if not (semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion)) }}
cluster:
  proxy:
    disabled: true
{{- end }}
