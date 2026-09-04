{{- /* KubeFlannelCNIConfig does not exist before Talos v1.14. */ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeFlannelCNIConfig
# cluster.network.cni name: none no longer suppresses this document, so leaving it in
# place starts Flannel alongside Cilium.
$patch: delete
{{- end }}
