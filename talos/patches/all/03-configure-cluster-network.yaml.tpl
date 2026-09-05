{{- /*
machine.certSANs is not deprecated and stays on v1alpha1. An external CNI has no field
here - it is expressed by deleting KubeFlannelCNIConfig (see
control-plane/17-disable-flannel-cni.yaml.tpl).
*/ -}}
---
apiVersion: v1alpha1
kind: KubeNetworkConfig
dnsDomain: {{ .Data.clusterDomain }}
podSubnets:
  - {{ .Data.podCidr }}
serviceSubnets:
  - {{ .Data.svcCidr }}
---
machine:
  certSANs:
{{- range .Data.machineCertSans }}
    - {{ . }}
{{- end }}
