# irq-balance-ms-01 - IRQ and RSS Tuning for MS-01 Nodes

## Overview

IRQ Balance is a Linux daemon that distributes hardware interrupts across multiple CPUs to improve system performance. This deployment includes both IRQ balancing and RSS (Receive Side Scaling) tuning for MS-01 nodes.

**Components:**

- **irqbalance daemon**: Distributes hardware interrupts across available P-cores
- **RSS tuning (init container)**: Configures network card flow distribution to prevent thermal hotspots

## Prerequisites

- MS-01 nodes with appropriate CPU configuration

## Troubleshooting

1. **RSS tuning not applied**

   - **Symptom**: Network interrupts still concentrated on single CPU
   - **Diagnosis**: Check init container logs: `kubectl logs -n irq-balance <pod> -c tune-rss`
   - **Resolution**: Verify NIC supports RSS, ensure init container has privileged mode
   - **Note**: RSS only affects new network flows; existing connections stay on original queue

## References

- [IRQ Balance Documentation](https://github.com/irqbalance/irqbalance)
- [RSS (Receive Side Scaling)](https://www.kernel.org/doc/html/latest/networking/scaling.html)
- [ethtool RSS Configuration](https://www.kernel.org/doc/Documentation/networking/scaling.txt)
- [Issue #236: CPU thermal throttling](https://github.com/anthony-spruyt/spruyt-labs/issues/236)
