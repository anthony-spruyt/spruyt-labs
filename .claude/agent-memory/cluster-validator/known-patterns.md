# Known Patterns

## Operational Patterns

Timing, behavioral, and environmental knowledge learned from validation runs.

| Pattern | Context | Count | Last Seen | Added |
|---------|---------|-------|-----------|-------|
| firemerge dependency chain (firefly-iii → firemerge → traefik-ingress) takes 3-5 min to fully reconcile | Full cluster reconciliation wait | 3 | 2026-02-24 | 2026-02-24 |

## Failure Signatures

Error patterns and their known resolutions.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|

## False Positives

Things that look like failures but aren't — avoid flagging these.

| Signal | Why It's Not a Problem | Count | Last Seen | Added |
|--------|----------------------|-------|-----------|-------|
| Kustomization firemerge not ready during reconciliation wave | Dependency chain, resolves within 5 min — wait for full cluster reconciliation | 3 | 2026-02-24 | 2026-02-24 |
