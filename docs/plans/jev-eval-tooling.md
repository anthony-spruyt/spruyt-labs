# Plan: Jev replay/eval tooling and golden set ([#3467](https://github.com/anthony-spruyt/spruyt-labs/issues/3467) step 8)

## Status

- **Design:** owner-reviewed 2026-10-19 after two spec reviews and a spike that passed (cost $0.83). The xfg reviewers feature (§10 step 2) stays marked "needs owner OK" until the owner confirms it.
- **Open:** how an eval run gets its model id now that the prod pin is worker config in spruyt-labs, not agent-platform code: which id a `pull_request` run uses, and how a model-upgrade run compares the old id with the new one (§7, §9).
- **Prereq:** [agent-platform#117](https://github.com/anthony-spruyt/agent-platform/pull/117), the release-notes detector (`ReleaseNotesDetector`, "the code detector" below). It is in a final fix round for changelog-format coverage. §10 step 7 starts after it merges.
- **Next steps (§10 step numbers):**
  - Steps 3, 4 and 6 can start now. Step 6 adds the `eval` `reviewers` and `preventSelfReview` only once step 2's xfg release is in repo-operator; until then the owner sets them by hand (step 5.3).
  - Step 2 starts only after the owner OKs the new xfg feature.
  - Step 5 is the owner's.
  - Step 7, the agent-platform build, waits for [agent-platform#117](https://github.com/anthony-spruyt/agent-platform/pull/117) to merge.

Items marked "my call" are designer choices; the rest are owner decisions or verified facts.

The spike's scratch outputs were local and are not in the repo: the gate set's PR bodies and file lists ("the gate bodies"), the code detector's answers on them, and the per-run Jev and labeller outputs. The gate set is the 600 recorded Renovate PRs that [agent-platform#117](https://github.com/anthony-spruyt/agent-platform/pull/117) ran its detector on; 124 of them have recorded Jev answers. The
key numbers are inline below. The draft rubric is [jev-eval-rubric-draft.md](jev-eval-rubric-draft.md).

## 1. Goal (owner)

Test Jev prompts against historic Renovate PRs, so a new prompt's performance is measured before it ships. The first use is to rewrite and calibrate the `changelog` question in `JevQuestions.json`.

## 2. Current setup (verified)

- `JevClient.cs`: path and model are options, `LiteLlm:JevPath` (default `v1/systemone`, relative to `LiteLlm:BaseUrl`) and `LiteLlm:JevModel` (default `jev-1.14.0`), both validated at startup ([agent-platform#157](https://github.com/anthony-spruyt/agent-platform/pull/157)). It caps the body and diff at 32 KB each (:21-23) and loads the questions from embedded resources through a static Lazy (:27-31), so they can't be injected. It sends `{state:{pr_body, pr_diff, current_date}, model, questions}` with state first (:33-69), POSTs to `JevPath` on LiteLLM (:71), and ignores the `model` field in the
  response (:141-160).
- The prod pin is worker config: `LiteLlm__JevPath: v1/systemone` and `LiteLlm__JevModel: jev-1.14.0` in `cluster/apps/agent-platform/worker/app/values.yaml` ([#3886](https://github.com/anthony-spruyt/spruyt-labs/issues/3886)).
- The triage worker and the llm-tool-guard scanner use LiteLLM's native `/v1/systemone` route, not the `/typesafe` pass-through. The route resolves `model` against `model_list`, so each Jev version used needs a deployment (`jev-1.14.0` -> `typesafe/jev-1.14.0`, `cluster/apps/litellm/litellm/app/values.yaml:1356-1358`). The caller's key and team model lists are expected to gate it too (§10 step 4 checks this). Other TypeSafe callers are jev-router, the jev-compaction guardrail and n8n.
- `jev-latest` is an alias that moves; it has resolved to `jev-1.14.0` since about Oct 22 (spend logs). The worker sends the pinned id; jev-router still sends the alias (`cluster/apps/litellm/litellm/app/values.yaml:1375`). The TypeSafe docs describe no prompt caching. Price is $0.042/MTok input and output is free. The rate limit is per organization, shared with prod; its exact figure is unverified.
- `changelog` is a single bare line. `breaking` and `bump_type` have full rubrics. `JevCiQuestions.json` has `ci_failure`.
- `TriageRules.cs:42-43` sets the cut-offs at breaking 0.66 and changelog 0.7. In `DecidePatchOrMinor`, a changelog score >= 0.7 means Approve "changelog-present". §8 allows zero false positives on `changelog` for a question change, and no new false positives for other trigger PRs.
- `run_steps` holds 126 `jev`, 1 `jev-changelog` and 11 `ci-classify` steps (live). `input`, `prompt_hash` and `model` are NULL on all of them; only the scores and decision are kept. The 127 answers cover 125 PRs in 9 repos. Scores are bimodal: 100 at or above 0.7, 27 below.
- Against the code detector's answers on the gate bodies, Jev on the 124 PRs in the gate set is 99 yes/yes, 25 no/no, 2 Jev-no/detector-yes and 0 Jev-yes/detector-no. The current history has almost no hard negatives.
- Tests: `tests/AgentPlatform.Tests/Replay/` is Temporal history replay, which checks determinism and is not an eval. No eval code exists.
- agent-platform CI (`ci-repo.yaml`): jobs `dotnet` and `integration` run on ubuntu-latest behind repo-operator's shared harden-runner action, whose egress mode is the owner's one switch. The only environment is `release`, and no CI job calls LiteLLM today.
- The only CI-to-LiteLLM pattern is xfg's: environments `integration` (required reviewers, set by hand: xfg's environment schema allows only `deploymentBranchPolicy` and `secrets`, `config-schema.json:2002,2036`) and `integration-main` (main only), each with `LITELLM_HOST`, `LITELLM_API_KEY`, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`, synced by repo-operator (`src/repos.yaml`).
  harden-runner allows `LITELLM_HOST:443`. The Cloudflare path list (`rulesets.tf:26-31`, used by `tunnel.tf:41`) allows only `/v1/messages`, `/v1/messages/count_tokens`, `/v1/chat/completions` and `/health/liveliness`.
- PR population (GitHub search): 2,851 merged and 584 closed-unmerged Renovate PRs. The gate bodies already hold 600 bodies and file lists, including all 124 gate-set Jev PRs.

## 3. Target layout (agent-platform)

| Path                                | Content                                                                                                                                                             |
| ----------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------- |
| `eval/renovate-triage/cases.jsonl`  | One PR per line: repo, number, url, state, created_at, merged_at, head_sha, title, head_ref, body, files `[{filename, patch, status}]`, manager, strata tags, split |
| `eval/renovate-triage/labels.jsonl` | Per case: `changelog`, `breaking` (bool, each with a short reason), labeller model, rubric hash, Opus label, owner override                                         |
| `eval/renovate-triage/rubric.md`    | The byte-identical labelling prefix (hashed into each label)                                                                                                        |
| `eval/renovate-triage/sample.json`  | Seed, strata and counts, so the sample can be rebuilt                                                                                                               |
| `tools/AgentPlatform.EvalData/`     | Console app: fetch, sample and label. An agent runs it once, locally                                                                                                |
| `tests/AgentPlatform.Eval/`         | Console eval runner that calls live Jev. Not an xunit project, so `dotnet test` never calls Jev                                                                     |
| `tests/AgentPlatform.Tests/Eval/`   | Offline test: every case parses, and `PrDiff.Build` and `BumpAnalyzer.Analyze` run on it                                                                            |

- my call: store the raw file list, not a built diff. The runner calls `PrDiff.Build(files, 32 KB)` and `BumpAnalyzer.Analyze(files)` as `JudgeAsync` does, so a change to either is measured too.
- my call: plain JSONL, about 5 MB for 800 cases (the 600 gate-set cases hold 2.9 MB of bodies and 1.0 MB of file JSON). All of the data comes from public PRs.

## 4. Dataset build and rate limits (fetch once)

The eval (local and CI) reads only the dataset and makes no GitHub calls.

1. Metadata pass, GraphQL. For each repo, page through `repository.pullRequests(first:50, states:[MERGED,CLOSED], orderBy:CREATED_AT)`, halving the page size on a timeout or error, and keep PRs whose author is the Renovate bot (databaseId 29139614, not the login). Each page returns body, title, headRefName, createdAt, mergedAt, state, labels, `headRefOid` and `files(first:100){path changeType}`.
   Paging per repo avoids search's 1,000-result cap: about 40-60 pages at 1-2 points each.
2. Sample (§5) from that metadata. Manager comes from the file paths, since the body doesn't name it (my call).
3. Diff pass, REST: `pulls/{n}/files?per_page=100` (paginated) for sampled PRs only, about 800 calls against a 5,000/h core quota. Null patches on large files stay null (`GitHubApiClient.cs:37`).
4. Notes pass: for each sampled PR, run the `ChangelogFetcher` logic once and store the fetched sections in the case, so the runner replays triage step 2 with no GitHub calls. Triage step 2 is the second Jev pass: when the first pass finds no changelog, Jev runs again on the body joined with the fetched changelog sections (§7). It is not §10 step 2.
5. Rate limits:
   - Every GraphQL query asks for `rateLimit{cost remaining resetAt}`; every REST call reads `x-ratelimit-remaining` and `x-ratelimit-reset`. Below 100 remaining, the fetch sleeps until reset.
   - On a secondary limit (403 or 429) it waits for `retry-after` if present, else 60 s doubling up to 15 min. Requests run one at a time.
   - Each page and case is written to disk as it arrives, so a rerun resumes (my call).
6. The gate bodies (my call): the spike uses them as-is. The real build re-fetches, because those files lack `status` and `headRefOid` and bodies may have been edited since.

## 5. Sampling (my call, about 800 cases, fixed seed)

- Every PR with a recorded Jev answer (125 today). The recorded scores are a reference, not labels: their input wasn't stored, and the body may have changed since.
- Base strata: about 450 PRs, in proportion by repo x manager, at least 10 per repo and per manager (or all if fewer).
- Oversampled hard cases, about 250, tagged in `strata` so metrics can be split by them:
  - link-only bodies and bodies with no "Release Notes" section (the negatives)
  - notes for a different package or version than the bump
  - grouped or multi-package PRs
  - all bodies over 32 KB (16 of the 600 in the gate set)
  - digest, calver and major bumps
  - about 100 closed-unmerged PRs
  - breaking positives: every PR that carried `blocked` or `agent/needs-human-review`, plus all major bumps
  - every case where the detector and Jev disagree
- Split: 70% `dev` for prompt tuning, 30% `test` for the gate, stratified, so the rewrite isn't judged on the cases it was tuned on.

## 6. Labelling flow (owner flow, details my call)

1. Haiku 5.5 labels every case for `changelog` and `breaking`, each with a reason of one sentence or less and a confidence.
   - `changelog` rubric (semantic, my call): true only if, for every updated package, the body says what changed in its new version, in any format. Links, the Renovate table, compare links, "Full Changelog" lines, contributor-only lines and "Configuration" boilerplate don't count. A one-line note such as "Bug fixes and reliability improvements" counts (the owner judged
     [container-images#2389](https://github.com/anthony-spruyt/container-images/pull/2389) as having a changelog). Version ranges, tag suffixes and `v` prefixes are matched by meaning.
   - The label is not a copy of the `ReleaseNotesDetector` rule, so the detector is measured too. Each case stores the detector's answer, and §8 reports its FPs and FNs on their own.
   - `breaking` rubric: a removal or a behaviour change that existing config must react to, even when announced under "Features" ([spruyt-labs#3531](https://github.com/anthony-spruyt/spruyt-labs/pull/3531)). Lock-file maintenance and transitive bumps are not breaking unless the notes say so.
   - The prefix's worked examples cover a one-line placeholder note, a range bump, a link-only body, a grouped PR missing one package's notes, a removal under "Features", and lock-file maintenance. The build starts from the spike's [draft rubric](jev-eval-rubric-draft.md).
   - The labeller sees the body capped at 32 KB, as Jev does. Cases over the cap are tagged `over-cap`. Bump type is not labelled: `BumpAnalyzer` gives it (owner).
2. Opus 5.5 labels 50 cases, half of them likely negatives, so negative-class agreement is measured (my call). The measure is Cohen's kappa per question. Below 0.8 is low (my call), and then Opus labels every disputed case for that question: Haiku vs detector, Haiku vs recorded Jev, and Haiku confidence below 0.7.
3. Opus also labels every case the gate would count as a false positive: labelled false and scored at or above the cut-off by the current prompt (my call), so the zero-FP rule never rests on one Haiku label.
4. The tool writes a Haiku-vs-Opus disagreement list with the PR URL, both reasons and the body excerpt. The owner reviews only that list, and the owner's override wins.
5. The labels are committed with the model ids, the rubric hash and the date. This is a one-off agent run, not CI (owner).

Prompt cache layout (owner rule, layout my call):

- Call LiteLLM `/v1/messages` with the official Anthropic C# SDK. `system` is one block (instructions, rubric, about 8 worked examples) ending in `cache_control: {type: "ephemeral"}`, at least 2K tokens, well over the 512-token minimum.
- Nothing variable goes in the prefix: no date, repo or ids. `messages[0]` (user) holds the case facts (repo, manager, BumpAnalyzer versions), the PR body, then the `PrDiff.Build` diff. The reply uses structured outputs against a JSON schema.
- Thinking: Opus 5.5 rejects `thinking: disabled`, so both models run adaptive thinking with `output_config.effort` set on every call and stored with the label. Haiku 5.5 also allows `disabled` at effort `high` or below; adaptive is its default, so one setting covers both.
- Caches are per model: each model gets a warm-up call, then its cases fan out at concurrency 4 within the 5-minute TTL. The run aborts if `usage.cache_read_input_tokens` is 0 after a warm-up.
- Billing is API credit through LiteLLM `anthropic-api/*` (my call): headless `claude -p` isn't logged in here, and caching needs `/v1/messages`.
- Cost, from the spike: Haiku about $0.0005 per case (about $0.40 for 800), Opus about $0.016 per case. The 5.8K-token prefix was read from cache on 49 of 49 calls per model.
- Jev: TypeSafe documents no caching, so no layout. If it adds caching, move `questions` and `model` ahead of `state` (my call).

## 7. Eval runner and metrics

- Prod change, test-first: a `JevClient` overload that takes the questions JSON, model id, time, base URL and auth headers (CI uses `x-litellm-api-key` plus the Access headers; prod sends Bearer, `JevClient.cs:75`). It returns the answers plus `response.model`. The static Lazy stays the default. Model and path are options (`LiteLlm:JevModel`, `LiteLlm:JevPath`, §2); the overload still takes the model id as an argument, so the runner sets it per run.
- Prod does not follow new Jev versions on its own. The pin is `LiteLlm__JevModel` in the worker values (§2), so a model upgrade is a config change there, not a code PR.
- The runner takes the model id as input. Before changing the worker's `LiteLlm__JevModel`, run the eval with the new id. A new id needs a `model_list` deployment and a `jev-eval` team model entry (§10 step 4), rolled out together. `current_date` is frozen to the run time for recorded cases and to `created_at` for the rest (my call). The run fails if `response.model` doesn't match the id it sent.
- The TypeSafe limit is shared with prod triage, the llm-tool-guard scanner, jev-router (`cluster/apps/litellm/litellm/app/values.yaml:1363-1378`), the jev-compaction guardrail (`:606-614`) and n8n. The runner uses concurrency 4, paces itself to 10 req/s, honours `retry-after` on 429/529 with capped backoff (up to 5 tries), and counts Jev unreachable only after the retries run out. LiteLLM's budget-exceeded error is its own failure, "eval budget exhausted".
- Each case goes through the prod path: the head-ref term gate first (`RenovateTriageActivities.cs:109-111`; cases it stops skip Jev), then `ReleaseNotesDetector` and `TriageRules.DecideFromJev`, and on `no-changelog`, triage step 2: Jev on the body joined with the stored notes (`"\n\n---\n\n"`, as `JevBody` does) and the detector on those notes. So end verdicts are measured as well as raw scores.
- Report, to `$GITHUB_STEP_SUMMARY` and a JSON artifact, after the §8 header:
  - `changelog` and `breaking`: TP, FP, FN and TN at the cut-off; precision, recall and F1; old, new and delta; by `dev`/`test` and by stratum.
  - Precision and recall at cut-offs 0.5 to 0.9, for calibration.
  - `bump_type`: accuracy against BumpAnalyzer and a 6x6 confusion table, excluding unpaired versions.
  - An FP list per question (PR URL, every run's score, label, label reason), and verdict flips between old and new.
- `ci_failure` has no dataset: CI logs were never stored and the 11 `ci-classify` inputs are NULL. A change to `JevCiQuestions.json` alone passes with the note "ci_failure not measured (no dataset)" until §12 data exists.

## 8. Old vs new comparison

- my call: the job builds the runner twice, from a worktree at the base sha ("old") and from head ("new"), and runs both on head's dataset. This covers a change to the questions JSON, cut-offs, detector or diff code without parsing C# constants.
- Old's metrics come from base's runner and scoring code, and the comparison and bar logic come from base too, so a PR never grades itself. When base has no runner (the bootstrap PR) or can't read head's `schema_version`, old is head's runner built in the base worktree; the report says so, and the PR needs the owner's review, as a label change does.
- Repeats: each case runs N=3 times per side. A case is an FP if any of its runs scores at or above the cut-off, since prod makes one call. The per-case mean is used only for F1 and calibration. (Spike: median spread 0.01, and 1 of 50 cases near 0.7 crossed between runs.)
- Delta: a paired bootstrap over `test` cases on per-case mean scores (10,000 resamples, fixed seed) gives a 95% CI for each question's F1 delta. The report lists every CI.
  - "Beats": the CI lower bound for the changed question is above 0.
  - "Not worse": the CI lower bound is above -0.02.
- FPs are counted on the full set: Jev's `changelog` score (body and triage step 2), plus "changelog-present" end verdicts where the detector said no. Detector FPs and FNs are reported on their own and must be no worse than old; a prompt can't fix them, so they don't fail a prompt change.
- Bars:
  - A PR that changes a `JevQuestions.json` question: zero FP on the full set (owner), the changed question beats old, and the others are not worse.
  - Every other trigger PR, including the bootstrap PR: no FP that old didn't have, and every question not worse. The bootstrap PR's report also records the current prompt's FP list.
- The report starts with "labels changed vs base": counts per question and the changed case ids. A label change needs the owner's review of the PR (§10 step 6).

## 8a. Fail fast (owner)

The run stops as soon as the result is decided, and cancels calls in flight (one CancellationToken).

1. Canary: one Jev call first checks auth, the model id and the budget. Any failure stops the run before the fan-out.
2. Old is reused: every run uploads its scores as an artifact `eval-scores-<key>`, where the key hashes the Jev files, the model, the runner/scoring version and the dataset. Old first looks for an artifact with base's key from a run whose head commit is in main's history (for example, the merged PR's own "new" scores), and calls Jev only if there is none (90-day retention). Fix pushes on the same
   PR therefore pay only for new.
3. Likeliest-FP cases first: new runs the labelled negatives first, ordered by FP likelihood (old score near or above the cut-off, then the hard-negative strata). For a question change, the first FP fails the run at once and reports that case.
4. Adaptive repeats: each case runs once. Only cases within 0.15 of a cut-off run 2 more times (the spike's max spread was 0.11), so far-off cases cost 1 call, not 3.
5. Early stop on the bar: after each batch of 50, the runner computes the best F1 delta new could still reach if every remaining case were right. If that can't clear the "beats" bar, it stops and fails with "cannot reach the bar".
6. Infrastructure stops: budget exhausted, 401/403, or a model mismatch stops at once, with no retries beyond the 429/529 backoff.

## 9. CI job (agent-platform, live Jev in GitHub CI)

- Workflows (my call on layout):
  - New repo-owned `.github/workflows/eval.yaml` with `workflow_dispatch` (input `base`, default `main`) and `workflow_call`, which declares the four secrets `LITELLM_HOST`, `LITELLM_API_KEY`, `CF_ACCESS_CLIENT_ID` and `CF_ACCESS_CLIENT_SECRET`. xfg syncs `ci.yaml` only; `ci-repo.yaml` is repo-owned (repo-operator `src/groups.yaml:198-206`).
  - `ci-repo.yaml` job `eval` calls it and passes the four secrets by name, as xfg's `ci-repo.yaml:176-185` does; no `secrets: inherit`. The `eval` environment supplies the values. It runs only on `pull_request` events from branches of this repo (`head.repo.full_name == github.repository`), and not on pushes to main.
  - `ci.yaml` caps the `repo` job at `contents: read` (`ci.yaml:26-27`). That is enough: the repo is public, so the environments API needs no extra scope (checked).
  - New `eval-drift.yaml`: a weekly run of the `guard` check that opens or updates an issue when it fails. It is separate because a called workflow can't ask for `issues: write` above its caller.
- Jobs in `eval.yaml`:
  1. `changes` diffs base..head. The eval runs only if one of these changes (a dispatch always runs):
     - `JevQuestions.json`, `JevCiQuestions.json`, `TriageRules.cs`, `ReleaseNotesDetector*.cs` (owner)
     - `JevClient.cs`, `PrDiff.cs`, `BumpAnalyzer.cs`, `eval/renovate-triage/**`, `tests/AgentPlatform.Eval/**`, `tools/AgentPlatform.EvalData/**`, `.github/workflows/eval.yaml`, `.github/workflows/ci-repo.yaml` (my call)
  2. `guard` reads `environments/eval` and passes only if its `required_reviewers` rule lists exactly the owner's user and `prevent_self_review` is true. The script is shared with `eval-drift.yaml`.
  3. `build` keeps the usual nuget/dotnet allowlist. It publishes the old runner and comparison step (base worktree) and the new runner (head) self-contained, and uploads them with the dataset as one artifact.
  4. `eval` declares `environment: eval` and does no checkout or SDK install. It downloads the artifact, runs old, then new, then base's comparison. A direct harden-runner step (not the shared action), with `egress-policy: block` and `disable-telemetry: true` like xfg's AI lane, allows `${{ secrets.LITELLM_HOST }}:443` plus the two GitHub artifact endpoints agent-platform's `ci-repo.yaml:31,38` already lists, and nothing else.
- Approval (end state):
  - `build` has no environment and no secrets. Only the `eval` job gets secrets, and only after the owner approves.
  - Only the owner's approval starts the `eval` job. Every run waits for it, after the owner reads the diff. The paths filter only decides whether a run is needed.
  - The `eval` environment uses required reviewers only, with no custom deployment protection rules. Its only required reviewer is the owner's user account, with `prevent_self_review: true`. The `guard` job (job 2) checks the reviewer list and `prevent_self_review`. Agents act as a GitHub App installation and are not reviewers, so only the owner approves eval runs.
  - With `prevent_self_review`, the owner can't approve a run they started, so an agent starts dispatches and re-runs.
  - Only the eval token passes Access on `/v1/systemone`, and the eval key can call only that route (§10 steps 3 and 4).
- Fail rule: the job fails below the bar, and also when Jev is unreachable, the model id doesn't match or the eval budget is exhausted, because an unmeasured prompt must not pass. A failure fails `repo`, which blocks `image` (`ci.yaml:34`) and the required `summary / Check Results`.
- Approvals per PR:
  - A new push cancels the previous run, a waiting approval included (`ci.yaml:13-15`), so only the last push needs one. Status checks aren't strict (repo-operator `src/groups.yaml:778`, the agent-platform block), so a moving main doesn't re-run it.
  - A typical Jev PR costs 1 approval once the PR is final, plus 1 per round that fixes a failed eval. A dispatch costs 1. Renovate PRs that touch a trigger path (action pins in the two workflows, EvalData packages) cost 1; other Renovate and xfg PRs cost none.
- Dispatch runs use their own concurrency group, `eval-<ref>`, with cancel-in-progress.
- Budget and time:
  - The eval team's budget is $20 per 30 days. The spike measured $0.025 for 150 Jev calls; a run at N=3 is about 4,800 calls (800 cases x 2 sides x 3, plus triage step 2), about $0.81, so the budget covers about 24 runs.
  - §10 step 8's prompt tuning runs locally on `dev` with the devcontainer key, not in CI.
  - At 10 req/s the calls take about 8 min. With two builds (about 3 min), the workflow runs about 12-14 min plus the wait for approval.

## 10. Changes per repo, in order

1. Spike, done by a helper with no commits (§11).
2. xfg (needs owner OK: new xfg feature): environment `reviewers` (`[{type: User|Team, id}]`, numeric ids as in rulesets' `bypassActors`) and `preventSelfReview`.
   - Add them to `rootEnvironmentConfig` and `environmentConfig` (`config-schema.json:2002,2036`), the config types and the normaliser.
   - `list` reads `protection_rules` (`github-environments-strategy.ts:48-65`) and `diffEnvironment` compares reviewers (`diff.ts:96-147`).
   - An absent `reviewers` (or `preventSelfReview`) is unmanaged, unlike an absent `deploymentBranchPolicy`, which `diff.ts:96-147` manages. The sync leaves the existing value, and the PUT (`:67-77`) echoes the reviewers and `prevent_self_review` that `list` read, so a policy change keeps them.
   - Tests, including one that proves xfg `integration`'s hand-set reviewers survive a sync, and docs, then a release. repo-operator picks it up through Renovate.
3. spruyt-labs `infra/terraform/cloudflare/`:
   - `access.tf`: service token `agent_platform_eval`, a `non_identity` policy for it, and Access app `litellm_eval` on `${litellm_host}/v1/systemone` with only that policy and `service_auth_401_redirect = true`, as on the host app (`:34`). In Access the more specific path wins and inherits nothing from the host app (Cloudflare app-path docs), so only the eval token passes on that path.
     The `litellm` app keeps only `litellm_ci`.
   - `tunnel.tf`: a second litellm route for `^/v1/systemone$` whose `aud_tag` is the eval app alone, ahead of the CI route. `tunnel_hostnames` (`:74-76`) is keyed by subdomain, so it is built from the distinct subdomains. `depends_on` (`:108-112`) adds the eval app.
   - `rulesets.tf`: a new `litellm_eval_paths`, joined to the CI paths in the block rule (`:95-97`).
   - The eval key's `rpm_limit` caps its request rate (§10 step 4).
   - `outputs.tf`: `agent_platform_eval_access_client_id` and `agent_platform_eval_access_client_secret` (sensitive), like `:11-20`. Update README `:41-44`.
   - The workspace has no auto-apply, so the run is confirmed once the plan shows only these changes.
4. spruyt-labs `cluster/apps/litellm/litellm/access-policy/`:
   - `access-policy.yml` gets team `jev-eval`: a new UUID, `models: [jev-1.14.0]`, `max_budget: 20`, `budget_duration: 30d`. CI needs only the Jev models; labelling and tuning run locally on the devcontainer key.
     - Model lists: measured on `/typesafe`, the pass-through checks the body's `model` against the key's and the team's lists. It passes on `all-proxy-models`, `*`, an empty list, `jev-*` or the exact name, but not `typesafe/*` (spike). `/v1/systemone` resolves `model` against `model_list`, so each id also needs its deployment. Re-check the list matching on `/v1/systemone` in this step. A new Jev id adds its `model_list` deployment and its entry here in the same rollout.
     - Budget: measured on `/typesafe`, pass-through spend is checked against the team's `max_budget` before each call and recorded after it at the `typesafe/<model>` price (spike). The team budget is meant to cap the eval's spend; re-check in this step that `/v1/systemone` records spend at the deployment's price.
   - It also gets a `keys` section matched by `key_alias`, because route limits exist per key only (spike). The Job sets `team_id`, `allowed_routes`, `rpm_limit`, the budget and "no MCP servers". It never creates, reads or prints a key value. It skips an alias that doesn't exist yet with a warning and never fails on it. After an update it reads `/key/info` for the alias and logs the team, routes,
     `rpm_limit` and budget.
     - `agent-platform-eval`: team `jev-eval`, `allowed_routes: ["/v1/systemone"]`, `rpm_limit: 900`. The spike peaked at 17 req/s; the runner paces itself to 10 req/s (600 a minute).
     - `github-ci`: `allowed_routes: ["/v1/chat/completions"]`. No key except the eval key lists `/v1/systemone`, and every key lists exact routes, not route groups such as `llm_api_routes`.
     - Re-check in this step that `allowed_routes` is enforced on `/v1/systemone`: a key that lists it passes and a key that doesn't is refused.
   - LiteLLM matches routes exactly or by `/` prefix for every role (`route_checks.py:94-210,587-610`), and only a proxy admin may set them (`key_mgmt.py:919-960`), so the Job makes these calls as admin.
   - `reconcile.py` and `test_reconcile.py` plan and apply keys through `/key/list?key_alias=` and `/key/update`, test-first. The litellm Terraform provider has a key resource, but TFC can't reach the in-cluster admin API, and the Job already owns teams.
   - Update `cluster/apps/litellm/README.md:22,82-90,121`. Run qa-validator before the commit and cluster-validator after the push.
5. Owner steps, after 3 and 4. Each handles a secret value, which no agent may read or set:
   1. Create key `agent-platform-eval` in the LiteLLM UI with team `jev-eval` (the Job sets the rest). Once the Job's `/key/info` log line shows team `jev-eval`, the one route and the budget, store it as `LITELLM_EVAL_API_KEY` in repo-operator's `production` environment. LiteLLM shows the value once, to whoever creates the key.
   2. Read the two new TFC outputs and store them there as `CF_ACCESS_EVAL_CLIENT_ID` and `CF_ACCESS_EVAL_CLIENT_SECRET`, the path xfg's token takes.
   3. OK the xfg feature (§10 step 2). Without it, the owner sets the `eval` reviewer and `prevent_self_review` by hand once, as on xfg `integration` today, and `guard` and `eval-drift.yaml` hold them.
6. repo-operator:
   - `.github/workflows/ci.yaml` (repo-owned, `createOnly`): "Apply Secrets Sync" (`:285-300`) passes the three new secrets.
   - `.github/scripts/check-xfg-config.sh` runs before every xfg step. It fails any secret source env outside its lists (`:9-10`, `:58-64`) and passes the gateway names only under xfg's `integration`/`integration-main` (`gateway_secret_site`, `:40-43`). It gets the three new names, `LITELLM_EVAL_API_KEY`, `CF_ACCESS_EVAL_CLIENT_ID` and `CF_ACCESS_EVAL_CLIENT_SECRET`, and `gateway_secret_site` gets
     one more site: the agent-platform repo's `eval` environment. At that site only `LITELLM_HOST` and the three eval names pass, and the eval names pass nowhere else. Tests in `test/check-xfg-config.bats` mirror the xfg cases (`:210-298`); update `CLAUDE.md:52`.
   - In `src/repos.yaml`, the agent-platform entry (`:4-21`) gets:
     - `environments` with `deleteOrphaned: false` and `eval`: `reviewers: [{type: User, id: 99536297}]`, `preventSelfReview: true` (these two once step 2's xfg release is in repo-operator), no branch policy. Its secrets (`deleteOrphaned: false`) map `LITELLM_HOST` from `LITELLM_HOST`, `LITELLM_API_KEY` from `LITELLM_EVAL_API_KEY`, and `CF_ACCESS_CLIENT_ID`/`CF_ACCESS_CLIENT_SECRET` from the
       `CF_ACCESS_EVAL_*` names, like xfg (`:551-585`).
     - `.mergify.yml` var `gateFilesExtra: 'eval/renovate-triage/labels\.jsonl$|'`, as repo-operator sets for itself (`:232-234`), so a label change needs the owner's approval.
   - Update `docs/ci.md:154-161`.
7. agent-platform, after `ReleaseNotesDetector` lands:
   1. the `JevClient` overload. Path and model are already options ([agent-platform#157](https://github.com/anthony-spruyt/agent-platform/pull/157)); the prod pin is worker config (§7).
   2. golden set recording (§12), early so live data builds up
   3. `tools/AgentPlatform.EvalData` and the committed dataset and labels
   4. the eval runner and the offline test. The runner's first call checks that the eval credentials are accepted only on `/v1/systemone`: `/v1/chat/completions` answers 401 or 403 with no `x-litellm-*` header.
   5. `eval.yaml`, `eval-drift.yaml` and the `ci-repo.yaml` job, then one dispatch run as the end-to-end check. Re-check the Jev variance (§11) from that run's `eval-scores` artifact: per-case spread and cut-off crossings on `jev-1.14.0` and `/v1/systemone`.
8. agent-platform: rewrite and calibrate the `changelog` question locally on `dev`, then pass the gate on `test` in CI.
9. spruyt-labs issue [#3467](https://github.com/anthony-spruyt/spruyt-labs/issues/3467): fix the line that says CI can't reach LiteLLM/Jev (about line 289), and tick off step 8.

## 11. The spike

The spike checks that the labels, the negatives in particular, are accurate enough, and Jev's scores stable enough, for a zero-FP bar and an old-vs-new delta to mean something. One wrong negative label, or one Jev score that flips across 0.7 between runs, decides the bar.

The spike used the gate bodies only, needed no fetch and was budgeted under $5 (it cost $0.83):

1. Jev variance: the current questions 3 times on 50 cases with `jev-1.13.0` on `/typesafe` and frozen dates. The 50 hold all 19 recorded scores between 0.70 and 0.79, and the rest are likely negatives. Measure the per-case spread, cut-off crossings and the request rate at concurrency 4.
2. Agreement: Haiku and Opus label the same 50 with the draft rubric. Measure kappa per question, and confirm `cache_read_input_tokens` > 0.
3. Route: the `/typesafe` route works, and model lists, route limits and team budget behave as §10 step 4 states.

Go: kappa >= 0.8 on `changelog`, cut-off crossings at or under 2 of 50, and a working route. Otherwise, revise the rubric or the repeat count before building.

Results: the spike passed.

- Agreement: `changelog` kappa, Haiku vs Opus, was 1.000 (the go criterion, at least 0.8). `breaking` kappa was 0.79, below 0.8, so the §6 step 2 dispute path applies to `breaking` too: Opus labels every disputed `breaking` case, and every Haiku/Opus disagreement goes on the owner's list.
- Caching: prompt caching hit on 49 of 49 calls per model.
- Variance: median spread 0.01; 1 of 50 cases crossed 0.7 between runs (the go criterion, at most 2). The request rate peaked at 17 req/s. Measured on `jev-1.13.0` and `/typesafe`; re-check on `jev-1.14.0` and `/v1/systemone` in step 7.5.
- Route: measured on `/typesafe`, model lists apply, `allowed_routes` is per key, and pass-through spend counts against the team budget (§10 step 4). Re-check on `/v1/systemone` in step 4.
- Cost: $0.83.
- Calibration input: the 3 breaking positives scored 0.25 at most on `breaking` ([spruyt-labs#3531](https://github.com/anthony-spruyt/spruyt-labs/pull/3531) at 0.14), against the 0.66 cut-off. The `breaking` question is a likely second rewrite target after `changelog`.

## 12. Golden set growth (my call, ambitious extension)

From now on, every prod Jev call is stored with its exact input, so it can become an eval case.

- `JevClient` serializes the state once to text and builds the request from that text, the model and the questions text, so the request can be rebuilt byte for byte. It returns `JevCall(RequestSha256, StateSha256, QuestionsSha256, ResponseModel)`, which `JudgeResult` (`RenovateTriageModels.cs:63`) and `ClassifyCiResult` (`RenovateTriageCodeActivities.cs:24`) carry as an optional field, so old
  histories replay with null. The replay tests cover this.
- Before it returns, the activity writes the state to a content-addressed table and the questions to `prompts` (insert if missing). A failed write is logged and the triage carries on, as in `RunRecorder`.
  - The table is `jev_inputs(hash varchar(64) pk, kind text, state text, created_at timestamptz)`, added by an EF migration. It uses `text`, not `jsonb`, to keep the exact bytes the hash covers.
  - Size: the state is capped at 64 KB (body and diff) or 24,000 log chars. 138 calls in 7 days is about 20 a day, so about 1.3 MB a day even at the cap; the DB is 11 MB today.
  - CI logs are stored because GitHub expires them.
- The `jev` and `jev-changelog` steps (`RenovateTriageWorkflow.cs:266,452`) and `ci-classify` (`:384`) then record:
  - `prompt_hash`: the questions sha256, set only when the write succeeded, because `RecordStepAsync` rejects an unknown hash (`RunDataStore.cs:118-121`). The column is `varchar(64)` with an FK to `prompts.hash` (`PromptHashing.cs`).
  - `model` (`text`): `response.model`.
  - `input` (`jsonb`, NULL on all 138 steps today): `state_sha256`, `request_sha256`, repo, PR, head sha, `current_date`, and the body and diff sizes and truncation; `jev-changelog` adds the notes section count, `ci-classify` the run ids, job ids and log length.
- Refresh: `tools/AgentPlatform.EvalData refresh --export <file>`.
  - The export is one read-only query of the new steps joined to `jev_inputs`, run by the agent with the `postgres-execute_sql_agent_platform` tool, through the read-only `agent_platform` source in db-mcp (`cluster/apps/agent-platform/README.md:90`, `cluster/apps/db-mcp/db-mcp/app/values.yaml:166-183`), so no password is handled. Results are paged by `started_at` to stay within the tool's row
    limit.
  - It keeps public repos only, dedupes on repo, PR and head sha against `cases.jsonl`, and fetches files through the §4 diff pass.
  - It assigns the split by a hash of repo and PR, tags the cases `live`, and queues them for the §6 labelling flow.
  - Each live case keeps its recorded score, questions hash and model. When the rebuilt state hashes to `state_sha256`, rerunning the same questions and model measures Jev drift directly.
  - `ci-classify` rows go to `eval/renovate-triage/ci-cases.jsonl` with the log text. `ci_failure` is labelled and measured once there are enough cases of each kind.
  - Before commit, `cases.jsonl` and `ci-cases.jsonl` are scrubbed of masked or secret-looking values, and gitleaks/betterleaks passes on both.
  - A refresh lands as a PR, which runs the eval, since `eval/renovate-triage/**` is a trigger path.
