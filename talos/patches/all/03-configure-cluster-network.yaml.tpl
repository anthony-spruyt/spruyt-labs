{{- /*
machine.certSANs is not deprecated and stays on v1alpha1 in both branches; only the
cluster network settings move to KubeNetworkConfig. cluster.network.cni has no
replacement field - an external CNI is expressed by deleting KubeFlannelCNIConfig
(see control-plane/17-disable-flannel-cni.yaml.tpl).
*/ -}}
{{- if semverCompare ">=1.14.0-0" (default .TalosVersion .Node.RuntimeData.TalosVersion) }}
---
apiVersion: v1alpha1
kind: KubeNetworkConfig
dnsDomain: {{ .Data.clusterDomain }}
podSubnets:
  - {{ .Data.podCidr }}
serviceSubnets:
  - {{ .Data.svcCidr }}
{{- else }}
cluster:
  network:
    cni:
      name: none # Cilium
    dnsDomain: {{ .Data.clusterDomain }}
    podSubnets:
      - {{ .Data.podCidr }}
    serviceSubnets:
      - {{ .Data.svcCidr }}
{{- end }}
---
machine:
  certSANs:
{{- range .Data.machineCertSans }}
    - {{ . }}
{{- end }}
