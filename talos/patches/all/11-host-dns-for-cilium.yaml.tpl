{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: ResolverConfig
hostDNS:
  enabled: true
  # Incompatible with Cilium bpf masquerade. https://github.com/siderolabs/talos/issues/8836
  forwardKubeDNSToHost: false
  resolveMemberNames: true
{{- else }}
machine:
  features:
    hostDNS:
      enabled: true
      # Incompatible with Cilium bpf masquerade. https://github.com/siderolabs/talos/issues/8836
      forwardKubeDNSToHost: false
      resolveMemberNames: true
{{- end }}
