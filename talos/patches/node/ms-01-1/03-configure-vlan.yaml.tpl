apiVersion: v1alpha1
kind: VLANConfig
name: enp89s0.20
vlanID: 20
parent: enp89s0
mtu: 9000
addresses:
  - address: {{ .Node.IP }}/24
routes:
  - gateway: {{ .Data.gateway }}
    metric: 512
  # Fallback path for the Thunderbolt ring peers. Metric must stay above the 2048
  # used by the direct links in 02-configure-thunderbolt-links.yaml, so these only
  # take over once a link drops and takes its own route with it.
  # source is load-bearing: Ceph leaves outgoing connections unbound because
  # ms_bind_before_connect defaults to false, so without an explicit prefsrc the
  # detour would be sourced from this node's VLAN address and arrive at the peer
  # from outside the configured cluster network.
  - destination: 169.254.255.102/32
    gateway: {{ .Data.ms012Ip4 }}
    source: 169.254.255.101
    metric: 4096
  - destination: 169.254.255.103/32
    gateway: {{ .Data.ms013Ip4 }}
    source: 169.254.255.101
    metric: 4096
