# Orchestration (spruyt-labs)

- Main session: the `renovate-pr` skill returning SAFE is the approval path for Renovate PRs.
- Main session: instead of the range `push-reviewed.sh` prints, give cluster-validator as base the last `origin/main` sha a cluster-validator SUCCESS covered (its Deployed Version revision); with none this session, `origin/main` before the first unvalidated change this run must cover: your first push or merge to `main`, the push or merge the owner reported, or the Talos pin's squash commit. After ROLLBACK or ROLL-FORWARD, re-run with the failed run's base. The CI wait gets the pushed sha.
- Main session: qa-validator counts as the reviewer for a commit that changes only `cluster/` YAML manifests (no scripts or code), on `main` or a PR branch: its APPROVED is the READY review unless the change is high risk. Push it with `push-reviewed.sh`.
- High risk here (every check, per the `orchestration` skill) includes Talos and Kubernetes upgrades, Cilium, CoreDNS, Rook Ceph, CNPG, Velero, changes to PVs, PVCs or storage classes, the Flux system, CRDs, etcd, Kyverno policies, cert-manager, external-secrets, the NUT shutdown orchestrator, and deleting anything that holds data. Security YAML (network policies, RBAC, Authentik, ingress) is high risk and gets an attacker-minded reviewer.
- A Coder workspace pod is not this devcontainer: `kubectl exec` into it to read its logs and test there.
- When `validation.md` skips qa-validator, builders run `cd <path> && ./lint.sh`, except value-only edits, which get only the `yq` check.
