# Known Patterns

## Linting False Positives

MegaLinter or schema check results that are not actual issues.

| Pattern | Tool | Why It's Not a Problem | Count | Last Seen | Added |
|---------|------|----------------------|-------|-----------|-------|
| AVD-KSV-0037 on kube-system resources | Trivy | etcd/control-plane components legitimately run in kube-system | 2 | 2026-02-28 | 2026-02-28 |
| AVD-KSV-0125 on ghcr.io images | Trivy | ghcr.io/siderolabs is the official Talos registry | 2 | 2026-02-28 | 2026-02-28 |

## Schema Quirks

Valid configurations that fail dry-run or schema checks.

| Resource | Quirk | Workaround | Count | Last Seen | Added |
|----------|-------|------------|-------|-----------|-------|
| talos.dev/v1alpha1 ServiceAccount | CRD not available in dev env, dry-run fails | Expected failure -- CRD is built into Talos Linux, not deployed via Flux | 2 | 2026-02-28 | 2026-02-28 |

## Documentation Gaps

Cases where Context7 or upstream docs are missing or misleading.

| Library | Gap Description | Correct Behavior | Count | Last Seen | Added |
|---------|----------------|------------------|-------|-----------|-------|

## Failure Signatures

Common validation failures and their known fixes.

| Error Pattern | Root Cause | Resolution | Count | Last Seen | Added |
|---------------|------------|------------|-------|-----------|-------|
| Talos ServiceAccount (talos.dev/v1alpha1) confused with Kubernetes ServiceAccount | Talos SA creates a Secret, not a k8s SA. serviceAccountName still needs a v1/ServiceAccount | Add separate v1/ServiceAccount resource | 1 | 2026-02-28 | 2026-02-28 |
| gh issue comment blocked by block-individual-linters hook | Hook falsely triggers on gh commands containing lint-related words in body | Write report to /tmp file, use --body-file flag | 2 | 2026-02-28 | 2026-02-28 |
