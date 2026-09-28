# chrony - LAN NTP Server

## Overview

Serves NTP (with NTS upstream) to LAN clients on the `${NTP_IP4}` LoadBalancer address. The Talos nodes do **not** use it: they sync directly to the upstream servers in `talos/patches/all/08-configure-ntp.yaml`, so this workload can be down without affecting cluster time.

## Operations

- The image is built from the `chrony` directory of [anthony-spruyt/container-images](https://github.com/anthony-spruyt/container-images), not an upstream chart image.
- `ENABLE_SYSCLK=false` means the pods never discipline the host clock; they only answer queries.
