# Orchestration (spruyt-labs)

- Main session: the `renovate-pr` skill returning SAFE is the approval path for Renovate PRs.
- Main session: instead of the range `push-reviewed.sh` prints, give cluster-validator as base the last `origin/main` sha a cluster-validator SUCCESS covered (its Deployed Version revision); with none this session, `origin/main` before your first unvalidated push or merge to `main`. After ROLLBACK or ROLL-FORWARD, re-run with the failed run's base. The CI wait gets the pushed sha.
- Main session: a commit that changes only `cluster/` YAML manifests (no scripts or code), pushed straight to `main`, needs no reviewer once qa-validator returns APPROVED; push it with `push-reviewed.sh`.
- A Coder workspace pod is not this devcontainer: `kubectl exec` into it to read its logs and test there.
- When `validation.md` skips qa-validator, builders run `cd <path> && ./lint.sh`, except value-only edits, which get only the `yq` check.
