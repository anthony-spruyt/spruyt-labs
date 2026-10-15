# Orchestration (spruyt-labs)

- Main session: the `renovate-pr` skill returning SAFE is the approval path for Renovate PRs.
- Main session: pass the range `push-reviewed.sh` prints to cluster-validator as well as the CI wait.
- A Coder workspace pod is not this devcontainer: `kubectl exec` into it to read its logs and test there.
- When `validation.md` skips qa-validator, builders run `cd <path> && ./lint.sh`.
