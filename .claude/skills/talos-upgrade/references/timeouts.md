# Timeout Expectations

| Operation                                | Expected Duration | Timeout    |
| ---------------------------------------- | ----------------- | ---------- |
| Node upgrade command                     | 2-5 minutes       | 10 minutes |
| Node Ready after reboot                  | 1-3 minutes       | 5 minutes  |
| etcd rejoin                              | 30-60 seconds     | 2 minutes  |
| Ceph data recovery (PGs `active+clean`)  | 60-90 seconds     | 10 minutes |
| Ceph `HEALTH_OK` (incl. heartbeat decay) | 90s-12 minutes    | 30 minutes |
| Full cluster upgrade                     | 45-90 minutes     | 3 hours    |

**Measured reference (6-node cluster, v1.13.4 to v1.13.9 — a patch upgrade, so no Phase 2b):** control plane nodes took ~4 minutes each with drain enabled. Workers took ~4 minutes each plus Ceph recovery. Ceph data recovery was consistently 60-90 seconds; on one worker the `OSD_SLOW_PING_TIME_*` average then took a further ~10 minutes to decay below threshold while all PGs were already `active+clean`.
