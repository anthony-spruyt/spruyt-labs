# Releases

Every container image in this repository is released by [release-please](https://github.com/googleapis/release-please). There is no manual dispatch, no version input, and no tag to push by hand.

## Services

| Service               | Path                               | Image                                          |
| --------------------- | ---------------------------------- | ---------------------------------------------- |
| shutdown-orchestrator | `cmd/shutdown-orchestrator`        | `ghcr.io/anthony-spruyt/shutdown-orchestrator` |
| kata-tap-qdisc-fix    | `cmd/kata-tap-qdisc-fix`           | `ghcr.io/anthony-spruyt/kata-tap-qdisc-fix`    |
| mcp-header-proxy      | `cmd/mcp-header-proxy`             | `ghcr.io/anthony-spruyt/mcp-header-proxy`      |
| agent-queue-worker    | `ts/agent-queue-worker`            | `ghcr.io/anthony-spruyt/agent-queue-worker`    |
| bull-board            | `ts/agent-queue-worker/bull-board` | `ghcr.io/anthony-spruyt/bull-board`            |

`bull-board` lives inside `ts/agent-queue-worker` but is released independently; its directory is excluded from the worker's paths so a bull-board change does not bump the worker.

## How a release happens

1. A push to `main` touching a service directory updates that service's release pull request. Each service gets its own pull request.
2. The pull request is opened by the `repo-operator-release-bot` app, carries the `autorelease: pending` label, and is merged automatically by Mergify once CI passes.
3. Merging creates the git tag and a **draft** release.
4. In the same run, the build job for that service tests the tag and pushes the image to GHCR with a provenance attestation.
5. The image reference and digest are appended to the release notes and the release is published.

The draft is only published after the image is pushed, so a published release always has an image behind it. If the build fails the release stays a draft and the tag points at code with no image — re-run the workflow rather than cutting a new version.

## Choosing the version

The commit type on `main` decides the bump:

| Commit                                          | Bump  |
| ----------------------------------------------- | ----- |
| `feat:`                                         | minor |
| `feat!:` or a `BREAKING CHANGE:` footer         | major |
| anything else (`fix`, `chore`, `ci`, `docs`, …) | patch |

`kata-tap-qdisc-fix`, `mcp-header-proxy` and `bull-board` are pre-1.0, so a breaking change bumps the minor rather than the major until they reach 1.0.0.

To force a specific version, add a footer to the commit:

```text
Release-As: 2.0.0
```

## Pull request checks

`ci.yaml` runs the same tests and Docker build for any changed service, but never pushes an image or creates a tag. Only `release-please.yaml` publishes.

## Configuration

| File                                    | Purpose                                           |
| --------------------------------------- | ------------------------------------------------- |
| `release-please-config.json`            | Package list, release types, changelog sections   |
| `.release-please-manifest.json`         | Current version of each package — source of truth |
| `.github/workflows/release-please.yaml` | Opens release pull requests, dispatches builds    |
| `.github/workflows/_build-image.yaml`   | Shared test and build workflow                    |

## Troubleshooting

**No release pull request appeared.** The commit did not touch the service's directory, or every commit since the last release maps to a hidden changelog section. All conventional types used here are visible, so the first cause is far more likely.

**The release pull request is not merging.** Mergify requires `summary / Check Results` to pass, the author to be `repo-operator-release-bot[bot]`, the branch to start with `release-please--branches--`, and the diff to touch `.release-please-manifest.json`. Anything else needs a human review.

**A tag exists with no image.** The build failed after the tag was created. The release is still a draft. Re-run the failed run in `release-please.yaml`; do not delete the tag.
