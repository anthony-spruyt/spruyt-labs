cluster:
  network:
    cni:
      name: none # Cilium
    dnsDomain: {{ .Data.clusterDomain }}
    podSubnets:
      - {{ .Data.podCidr }}
    serviceSubnets:
      - {{ .Data.svcCidr }}
machine:
  certSANs:
{{- range .Data.machineCertSans }}
    - {{ . }}
{{- end }}
