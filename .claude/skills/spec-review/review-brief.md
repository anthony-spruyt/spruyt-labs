# Spec Review Brief

Perform critical architectural and technical review of the provided spec file.

## Review scope

For each architectural area in the spec, identify gaps, risks, incorrect assumptions, and over-engineering. Focus on:

- **Shared infrastructure impact** — how new components affect existing consumers, blast radius, resource contention
- **Coordination correctness** — dedup, race conditions, state machine transitions, failure recovery semantics
- **Security model** — credential separation, RBAC alignment, network policy coverage
- **Integration reliability** — callback patterns, failure modes during restarts, state tracking across components
- **External service assumptions** — free-tier limitations, API behavior under concurrency, dependency chains
- **Safety mechanisms** — loop prevention, circuit breakers, TTL correctness, cascading failure scenarios
- **Kubernetes deployment** — resource sizing, pod lifecycle, namespace/CNP/RBAC alignment with existing cluster config
- **Phase sequencing** — dependency ordering, what's deferred that shouldn't be, what's premature

## Critical requirement: verify against live cluster state

Do NOT assume the spec's claims about existing infrastructure are correct. Actively verify:

- Find and read actual deployed manifests in `cluster/apps/` for any component the spec references
- Check existing namespace config (CNPs, RBAC, Kyverno policies) mentioned in the spec
- Verify current deployment configs and capabilities of referenced services
- Check network policies relevant to inter-component communication

Use Context7 for library/framework docs. Use codebase search to find actual deployed manifests. Never guess what's deployed — read the manifests.

## Before flagging a finding

Specs often address risks in dedicated sections (e.g., "Risks and Mitigations", phase checklists, tradeoff callouts). Before raising a finding:

1. **Search the full spec** for the concern — check the risks table, implementation phases, operational notes, and inline tradeoff discussions
2. **If the spec already identifies and addresses the concern** — do NOT flag it. It's not a finding, it's a design decision the author already made
3. **If the spec identifies the concern but the mitigation is inadequate** — flag the mitigation gap, not the concern itself. Cite where the spec addresses it and explain why the mitigation falls short
4. **Only flag concerns the spec genuinely misses** — no credit for re-discovering what the author already documented

A review that re-raises addressed risks wastes author time and erodes trust in the review process.

## Output format

Structure findings as:
1. **Critical** — blocks implementation or risks data loss/cascading failure
2. **Major** — significant design gap or incorrect assumption about existing infra
3. **Minor** — improvement opportunities, over-engineering, or unclear spec language
4. **Validated** — spec claims verified correct against cluster state

For each finding: state the problem, cite the spec section, show evidence (manifest snippet or doc reference), and suggest a fix.
