{{- /*
Talos sets node.kubernetes.io/exclude-from-external-load-balancers by default. These
nodes have never carried it; deleting it keeps the control plane in LoadBalancer
backends. v1.14 moved the label out of .machine.nodeLabels into KubeNodeConfig, and a
delete aimed at the wrong document aborts the render, so the target follows the version.
*/ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  node-role.kubernetes.io/control-plane: ""
  bgp: "65050"
  node.kubernetes.io/exclude-from-external-load-balancers:
    $patch: delete
{{- else }}
machine:
  nodeLabels:
    node-role.kubernetes.io/control-plane: ""
    bgp: "65050"
    node.kubernetes.io/exclude-from-external-load-balancers:
      $patch: delete
{{- end }}
