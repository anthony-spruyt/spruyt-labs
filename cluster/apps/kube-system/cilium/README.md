# Cilium - Networking and Security

## Overview

Cilium provides networking, security, and observability for Kubernetes using eBPF technology. It serves as the CNI (Container Network Interface) for the spruyt-labs cluster, providing network connectivity, load balancing, network policies, and security features.

## Prerequisites

- BGP-capable network infrastructure

## Troubleshooting

1. **eBPF loading failures**

   - **Symptom**: Cilium pods failing to start
   - **Diagnosis**: Check kernel compatibility and eBPF support
   - **Resolution**: Verify node kernel version and eBPF requirements

## References

- [Cilium Documentation](https://docs.cilium.io/)
- [eBPF Documentation](https://ebpf.io/)
- [BGP Configuration Guide](https://docs.cilium.io/en/stable/network/bgp/)
