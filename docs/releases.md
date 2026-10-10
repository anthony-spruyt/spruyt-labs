# Releases

Every container image in this repository is released by [release-please](https://github.com/googleapis/release-please). You never choose a version or push a tag by hand.

## Services

| Service               | Path                        | Image                                          |
| --------------------- | --------------------------- | ---------------------------------------------- |
| shutdown-orchestrator | `cmd/shutdown-orchestrator` | `ghcr.io/anthony-spruyt/shutdown-orchestrator` |

[`kata-tap-qdisc-fix`](https://github.com/anthony-spruyt/kata-tap-qdisc-fix) and [`mcp-header-proxy`](https://github.com/anthony-spruyt/mcp-header-proxy) are deployed here but built and released from their own repositories, under the same image names.

## How a release happens

1. A push to `main` touching a service directory updates the single release pull request, `chore: release main` on branch `release-please--branches--main`. Every service with pending changes is bumped in that one pull request.
2. The pull request is opened by the `repo-operator-release-bot` app and carries the `autorelease: pending` label. Mergify merges it once a collaborator approves it and CI passes. Without an approval it waits.
3. Merging creates a git tag and a **draft** release per bumped service.
4. In the same run, the build job for that service tests the tag and pushes the image to GHCR and Docker Hub (`aspruyt/<image>`) with a provenance attestation.
5. The image reference and digest are appended to the release notes and the release is published.

The draft is only published after the image is pushed, so a published release always has an image behind it. If the build fails the release stays a draft and the tag points at code that may have no image — see the troubleshooting section.

## Choosing the version

The commit type on `main` decides the bump:

| Commit                                          | Bump  |
| ----------------------------------------------- | ----- |
| `feat:`                                         | minor |
| `feat!:` or a `BREAKING CHANGE:` footer         | major |
| anything else (`fix`, `chore`, `ci`, `docs`, …) | patch |

To force a specific version, add a footer to the commit:

```text
Release-As: 2.0.0
```

## Pull request checks

The `image` job in `ci.yaml` runs the same tests and Docker build for any changed service through repo-operator's shared `_images.yaml`, but never pushes an image or creates a tag. Only `release-please.yaml` publishes.

## Configuration

| File                                    | Purpose                                                                          |
| --------------------------------------- | -------------------------------------------------------------------------------- |
| `release-please-config.json`            | Package list, release types, changelog sections                                  |
| `.release-please-manifest.json`         | Current version of each package — source of truth                                |
| `.github/workflows/release-please.yaml` | Calls repo-operator's `_release-please.yaml`: release pull requests, then builds |

The workflow is synced from repo-operator; change it there, not here.

## Troubleshooting

**The service is missing from the release pull request.** The commit did not touch the service's directory, or every commit since the last release maps to a hidden changelog section. All conventional types used here are visible, so the first cause is far more likely.

**The release pull request is not merging.** Like any other pull request, it needs a collaborator's approval, `summary / Check Results` to pass, and no `blocked` label. Mergify merges it once all three hold.

**A tag exists with no image.** The build failed after the tag was created, so the release is still a draft. If the cause is outside the commit and outside the pinned shared workflows (a registry outage, a flaky test, a missing or expired secret), fix it and re-run the release run's failed jobs. A re-run uses the same commit and the same pinned `_release-please.yaml`, so it builds what the
original run built.

```bash
gh run rerun <run-id> --failed
```

A re-run cannot recover these cases. Fix the cause on `main` where needed, let release-please cut the next version, then delete the leftover draft:

- **The tagged code is broken, or the cause is in repo-operator's shared workflows:** the fix lands once the caller pin moves.
- **The tag points at a different commit than the run** (for example, after a cancelled run).
- **The run died before relabelling the release PR:** cut the next release, then delete every leftover draft release for that tag.
- **The run is past GitHub's 30-day re-run limit.**

A full re-run does not help: release-please does not report the release as created a second time, so the build is skipped.
