apiVersion: v1alpha1
kind: VLANConfig
name: enp1s0.20
vlanID: 20
parent: enp1s0
mtu: 9000
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: {{ .Data.gateway }}
    metric: 512
