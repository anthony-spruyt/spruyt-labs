{{- /*
Talos sets node.kubernetes.io/exclude-from-external-load-balancers by default. These
nodes have never carried it; deleting it keeps the control plane in LoadBalancer
backends.
*/ -}}
---
apiVersion: v1alpha1
kind: KubeNodeConfig
labels:
  node-role.kubernetes.io/control-plane: ""
  bgp: "65050"
  node.kubernetes.io/exclude-from-external-load-balancers:
    $patch: delete
