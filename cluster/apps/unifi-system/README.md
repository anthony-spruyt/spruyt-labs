# UniFi System - Network Telemetry Collection

## Overview

[UnPoller](https://unpoller.com/) polls the UniFi Network controller and exports its device, client, site and WAN state as Prometheus metrics for the VictoriaMetrics stack. It exists to answer one question that nothing else in the homelab could: **has something that was always on the network stopped being there?**

| Component | Purpose                                        | Namespace    |
| --------- | ---------------------------------------------- | ------------ |
| unpoller  | Polls the UniFi controller, exports `/metrics` | unifi-system |

Related but separate: `cluster/apps/unifi-mcp/` runs an MCP tool server against the same controller. It has write policies enabled and a different credential. UnPoller is read-only and does not share anything with it.

## Prerequisites

- UniFi OS Server reachable at `${UNIFI_IP4}:11443`
- A **local** UniFi account with read-only access to all sites (see [Credential](#credential))
- `victoria-metrics-k8s-stack` deployed in `observability` (provides `vmagent` and the `VMServiceScrape` / `VMRule` CRDs)
- Cluster variables `${UNIFI_IP4}` and `${UNIFI_INFRA_MACS}` present in `cluster/flux/meta/` (see [Cluster variables](#cluster-variables))

## Why this exists

A network audit on 2026-09-12 found a third-party switch on the Management VLAN whose management plane had been unreachable since **2025-10-18 — roughly eleven months**. Nothing alerted. L2 forwarding is hardware and kept working the whole time, so nothing user-facing broke and nobody had a reason to look.

The device is not the point. The failure mode is: **a client stopped appearing and no signal was produced.** Cluster monitoring was thorough; the network layer had no monitoring at all, and absence is invisible to every threshold-based rule.

The same audit also found the gateway sitting at 91.1% memory with no trend data to say whether that was normal, and no history at all for AP retry rates, channel utilisation or per-client signal — a 5 GHz channel change had to be evaluated twice from instantaneous counters because no time series existed.

## Credential

A **new, dedicated, read-only local UniFi account**, separate from the one `unifi-mcp` uses. Stored in `unpoller/app/unpoller-secrets.sops.yaml` as `UNIFI_USER` / `UNIFI_PASS`.

Requirements, learned the hard way in `unifi-mcp`:

- **Local account only.** Cloud SSO (Ubiquiti account) logins fail against the local API.
- **No MFA.** An account with MFA enabled cannot complete a non-interactive login.
- **Read-only, all sites.** UnPoller never writes; anything more is unnecessary exposure.

Separate from `unifi-mcp`'s credential on purpose: the two have different blast radius (one is read-only polling, the other has create/update/delete policies enabled), and rotating or revoking one should never take down the other.

## Cluster variables

| Variable              | Source            | Purpose                                                                     |
| --------------------- | ----------------- | --------------------------------------------------------------------------- |
| `${UNIFI_IP4}`        | `cluster-secrets` | Controller address — used in the URL and the egress CNP                     |
| `${UNIFI_INFRA_MACS}` | `cluster-secrets` | Regex alternation of MACs that must never vanish, e.g. `aa:bb:..\|cc:dd:..` |

`UNIFI_INFRA_MACS` is the allowlist that drives the absence alerts. It belongs in `cluster-secrets` rather than `cluster-settings` because MAC addresses are network details that must not appear in plaintext in Git, issues or PRs.

**Adding a device to the watchlist:** edit `cluster/flux/meta/cluster-secrets.sops.yaml` with `sops`, append `|<mac>` to `UNIFI_INFRA_MACS`, commit. The regex is matched against the `mac` label, which UnPoller emits lowercase and colon-separated.

## Scrape target

| Property        | Value                            |
| --------------- | -------------------------------- |
| Service         | `unpoller.unifi-system.svc:9130` |
| Path            | `/metrics`                       |
| Scrape interval | 60s (`vm-service-scrape.yaml`)   |
| Metric prefix   | `unpoller_`                      |

UnPoller serves `/metrics` from a cache refreshed on its own `UP_PROMETHEUS_INTERVAL` (60s) rather than polling the controller per scrape. That decoupling is what stops a controller 429 backoff from stalling scrapes. Scraping faster than the refresh interval only duplicates samples — keep the two in sync if you change either.

`unpoller_prometheus_cache_age_seconds` reports how stale that cache is, and is on the dashboard. A healthy scrape with a rising cache age means the data is old even though nothing looks broken.

## Alerts

Rules live in `cluster/apps/observability/victoria-metrics-k8s-stack/app/vmrules/unifi.yaml`. Routing is automatic — `alertmanager-config.yaml` routes on `severity`, so there is nothing to wire.

| Alert                           | Severity | Condition                                            |
| ------------------------------- | -------- | ---------------------------------------------------- |
| `UnifiInfraClientAbsent`        | critical | A tracked MAC seen in the last 7d, absent for 1h     |
| `UnifiInfraClientsAllAbsent`    | critical | No tracked MAC reporting at all for 1h               |
| `UnifiWANDown`                  | critical | `unpoller_wan_uptime_percentage < 95` for 15m        |
| `UnifiWANDrops`                 | warning  | Any WAN disconnection in the last hour, sustained 5m |
| `UnpollerDown`                  | warning  | Scrape target down for 5m                            |
| `UnpollerControllerPollFailing` | warning  | `unpoller_controller_up == 0` for 15m                |

### Rationale

**`UnifiInfraClientAbsent`** is the reason this component exists. UnPoller emits no `last_seen` metric and no presence gauge — verified by reading `pkg/promunifi/clients.go` upstream — so a vanished client simply stops producing series. No threshold rule can see that. The expression compares MACs seen over a 7-day window against MACs seen in the last 10 minutes; a device present throughout appears
on both sides and cancels out, leaving only ones that have gone quiet.

A plain `absent()` over a multi-MAC selector will not do this job: it fires only when **every** matching series is gone, so one dead device stays masked by its healthy peers. That is precisely the eleven-month failure mode. `UnifiInfraClientsAllAbsent` is the `absent()` companion, and it covers the different case the per-MAC rule cannot see — all of them vanishing at once, which usually means the
selector broke rather than the network.

**`UnifiWANDown` / `UnifiWANDrops`** exist because the Home Assistant UniFi integration exposes no WAN status entity at all. Confirmed against the integration docs — WAN health is genuinely unmonitored otherwise.

**`UnpollerDown` and `UnpollerControllerPollFailing`** are not optional. Without them this component has exactly the failure mode it was built to catch: it stops reporting and nobody finds out for eleven months. The two are distinct failures — the pod can be up and scrapeable while its controller polls fail on an expired credential, in which case `/metrics` serves a stale cache and every absence
rule silently stops meaning anything.

The `for: 15m` windows ride out a normal AP firmware reboot without paging.

### Deliberately not alerted

The Home Assistant UniFi integration at `ha.${EXTERNAL_DOMAIN}` already covers these **and already notifies on them.** Duplicating them here produces two pages for one event:

| Not alerted here                | Covered by                              |
| ------------------------------- | --------------------------------------- |
| Firmware / upgrade available    | HA `update` entities per device         |
| Device CPU, memory, temperature | HA per-device sensors                   |
| Device offline / unadopted      | HA device tracker                       |
| Client presence                 | HA device tracker (300s away threshold) |

Metrics for all of these are still **collected** — they cost nothing extra and the dashboard needs them for trending, which is the actual gap the audit found. Gateway memory is on the dashboard with no alert rule for this reason: the alerting was already covered, the history was not.

AP retry rate has no alert yet by design. Observed values swung 3.4%-18.4% on one radio within an hour during the audit, so a guessed threshold is an alert storm. The threshold gets set from a week of real p95 data in a follow-up. Home Assistant has no retry-rate data at all, so this one is genuinely new signal once it lands.

## Security

`/metrics` is **unauthenticated** — UnPoller offers no option otherwise — and it exposes every client name, MAC address and IP on the network. The `CiliumNetworkPolicy` in `unpoller/app/network-policies.yaml` is the only boundary:

- **Egress**: `${UNIFI_IP4}/32:11443` only
- **Ingress**: `vmagent` in `observability` on `9130` only

There is deliberately **no IngressRoute and no Cloudflare Tunnel route**. Do not add one.

`UP_UNIFI_DEFAULT_HASH_PII` must stay `false`. With it enabled, client names and MACs are md5-hashed and `UnifiInfraClientAbsent` can no longer match a MAC — the alert would keep evaluating and never fire.

## Known limitation

VLAN 10 (Management) deliberately does not depend on the cluster for DNS, so break-glass access survives a cluster outage. Monitoring the network *from* the cluster inherits the opposite dependency: **a cluster outage blinds network monitoring.**

This is accepted rather than solved. A cluster-down event is already an all-hands situation that gets noticed through other channels, and the failure this component exists to catch is a slow, silent one over months — not a correlated outage. Recorded here so it is a known limitation rather than a surprise during an incident.

## Operations

### Configuration is environment variables only

No config file is mounted. UnPoller's config keys come from the `xml` struct tags in upstream's source (`golift.io/cnfg` uses `xml` as its env tag), prefixed `UP_` and joined with `_`. Two consequences worth knowing before editing `values.yaml`:

- **A misspelled `UP_*` name is silently ignored** — no startup error, no warning. The setting just keeps its default. Verify names against the struct tags, not the docs.
- **Slices are indexed.** `sites` carries the xml tag `site`, so the site list is `UP_UNIFI_DEFAULT_SITE_0`. `UP_UNIFI_DEFAULT_SITES` does nothing at all.

`UP_INFLUXDB_DISABLE=true` is load-bearing: the image ships `/etc/unpoller/up.conf` with the InfluxDB output enabled, and without this the pod retries a nonexistent InfluxDB forever in its logs.

### Verifying the absence alert

The acceptance test that matters. Unplug a device whose MAC is in `UNIFI_INFRA_MACS`, confirm `UnifiInfraClientAbsent` fires within the hour, plug it back, confirm it resolves.

## Troubleshooting

1. **Pod starts but no `unpoller_*` series appear**

   - **Symptom**: Scrape succeeds, `/metrics` returns only Go runtime metrics
   - **Resolution**: Check pod logs for controller login failures. The usual cause is a Cloud SSO or MFA-enabled account — both fail non-interactive login. Use a local read-only account. `unpoller_controller_up` is `0` in this state.

2. **Absence alert never fires for a device that is definitely gone**

   - **Symptom**: Device unplugged, no alert after an hour
   - **Resolution**: Confirm the MAC actually matches. UnPoller emits `mac` lowercase and colon-separated; `UNIFI_INFRA_MACS` is a regex matched against that label. Also confirm `UP_UNIFI_DEFAULT_HASH_PII` is still `false` — with it on, the label holds an md5 hash and nothing matches.

3. **Controller API errors in logs after a controller upgrade**

   - **Symptom**: `400` or `404` on a specific collector (upstream issue #1050 saw this on `collectAlarms` for Network 10.5.67)
   - **Resolution**: Identify the failing collector in the logs and disable its `UP_UNIFI_DEFAULT_SAVE_*` toggle. All `save_*` options default off except `save_sites` and `save_speedtest`, so the surface is small.

4. **Dashboard panels empty while metrics exist**

   - **Symptom**: Series present in VictoriaMetrics, panels blank
   - **Resolution**: Check the dashboard's Site variable — it is populated from `unpoller_site_users` and will be empty if `UP_UNIFI_DEFAULT_SAVE_SITES` was turned off. The Gateway type variable defaults to `ugw|uxg|udm|usg`; adjust if the gateway reports a type outside that set.

## References

- [UnPoller](https://unpoller.com/)
- [UnPoller source](https://github.com/unpoller/unpoller) — metric names live in `pkg/promunifi/`
- [Home Assistant UniFi integration](https://www.home-assistant.io/integrations/unifi/)
- [VictoriaMetrics Operator CRDs](https://docs.victoriametrics.com/operator/api/)
