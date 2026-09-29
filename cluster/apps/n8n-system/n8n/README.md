# n8n - Workflow Automation

## Overview

Workflow engine and the control plane for the agent platform: it receives GitHub and Alertmanager webhooks, queues jobs through [agent-queue-worker](../../agent-worker-system/agent-queue-worker/README.md), and spawns Claude Code agent pods in the `claude-agents-*` namespaces ([claude-agents-shared](../../claude-agents-shared/README.md)). Runs in queue mode with separate main, worker and webhook
deployments.

## Operations

### SSO via forward-auth and an external hook

n8n Community Edition has no OAuth login, so SSO is Authentik proxy-provider forward-auth ([pattern](../../authentik-system/authentik/README.md#adding-sso-via-proxy-provider-forward-auth)) plus a custom external hook, `app/hooks-configmap.yaml`:

1. Traefik forward-auth to the Authentik outpost injects `X-authentik-email`.
2. The hook, spliced into the Express stack right after `cookieParser`, looks the email up in n8n's user table and issues an n8n session cookie.
3. Unknown users get a 401. **Users must be invited in n8n (Settings > Users) with their Authentik email before SSO works for them.**

The hook reaches into n8n internals (`dist/server.js`, `auth/jwt.js` `issueCookie`, the Express router stack). An n8n upgrade that moves any of these disables SSO silently: n8n still boots, and the hook logs `[forward-auth] SSO disabled - ...`. Check for that log line after every n8n bump. If SSO is disabled, n8n's own password login still works.

Paths that must work without a browser session are excluded in the blueprint's `skip_path_regex` (`authentik-system/authentik/app/blueprints/n8n-sso.yaml`): webhooks, MCP endpoints, OAuth credential callbacks and static assets. Add new machine-facing paths there, not in Traefik.

For users with MFA enabled in n8n, disable it (`n8n mfa:disable --email=<email>` in the main pod) and rely on Authentik MFA instead.

### Agent platform wiring

- **Prompts**: `app/prompts/*.md` become the `n8n-prompts` ConfigMap, mounted as a directory so edits reach running pods without a restart (the Dispatcher workflow reads them at run time).
- **Agent MCP endpoint**: a `mcp-header-proxy` sidecar is added to the webhook deployment by a postRenderer in `app/release.yaml` and exposed as port 8080 on the `n8n-webhook` Service. Agent pods call `n8n-webhook.n8n-system.svc:8080/mcp/agent-platform`.
- **Workflows** (Dispatcher, callbacks, MCP Server, SRE schedule) live only in the n8n database; they are not in Git, so they are backed up only as part of the n8n database.
- **Credentials** for the Claude Code node (one K8s credential per agent namespace, including the Claude subscription login) also live only in n8n.

### Task drain on shutdown

Since 2.38, n8n caps in-flight task timers at `N8N_GRACEFUL_SHUTDOWN_TIMEOUT * 0.8` once shutdown starts (`SHUTDOWN_TASK_BUDGET_RATIO` in `task-broker-ws-server.ts`). The env var is set to `75` so the cap lands on the configured `N8N_RUNNERS_TASK_TIMEOUT` of 60, and `terminationGracePeriodSeconds` is `90` on all three deployments so the kubelet does not SIGKILL mid-drain.

This holds for pod-level rollouts only. On a **node** shutdown the kubelet gives regular pods `shutdownGracePeriod - shutdownGracePeriodCriticalPods`, which is 60s - 30s = 30s (`talos/patches/all/06-configure-kubelet.yaml.tpl`), truncating the drain regardless of the value in the manifest.

This is deliberate and should stay that way. A priority class would not help: the kubelet only counts `system-cluster-critical` and `system-node-critical` as critical, and that tier gets the same 30s anyway. Widening `shutdownGracePeriod` would delay every node shutdown, including an emergency one on UPS failure — not worth it to drain a workflow run.

The tradeoff is real, so know what it costs. `maxStalledCount` is hardcoded to `0` in n8n's `scaling.service.ts`, so a job whose worker is SIGKILLed does not retry — it fails as `MaxStalledCountError` and needs a manual re-run. Only affects executions still running past the 30s mark when a node goes down.

### Database credentials

The `n8n` Postgres login is ESO-generated (`sl_` prefix) into `n8n-cnpg-owner` by `app/cnpg-roles-eso.yaml`; nothing is in SOPS and superuser access is off. `bootstrap.initdb.secret` points CNPG at it, so CNPG no longer generates `n8n-cnpg-cluster-app`. n8n connects through the `-pooler-rw` PgBouncer, which looks passwords up in Postgres (`auth_query`), so the pooler needs no change on rotation.

The database is deliberately not a db-mcp source: it holds plaintext n8n API keys and full execution payloads. Use the n8n MCP server, or `kubectl cnpg psql n8n-cnpg-cluster -n n8n-system -- -d n8n`.

To rotate, delete both the Secret and the ExternalSecret (`kubectl -n n8n-system delete secret,externalsecret n8n-cnpg-owner`). Flux recreates the ExternalSecret with a new password and CNPG applies it. Then `kubectl -n n8n-system rollout restart deploy -l app.kubernetes.io/name=n8n` - Reloader ignores a recreated Secret.

### Task runner token

`N8N_RUNNERS_AUTH_TOKEN` is ESO-generated into `n8n-runner-auth` by `app/runner-auth-eso.yaml`. Only the n8n pods and their runner sidecars use it. To rotate, `kubectl -n n8n-system delete secret,externalsecret n8n-runner-auth`, then `kubectl -n n8n-system rollout restart deploy -l app.kubernetes.io/name=n8n`.

## Troubleshooting

1. **SSO login returns "User not found. Please have an admin invite this user first."**

   - **Cause**: No n8n user with that Authentik email.
   - **Fix**: Invite the user in n8n with the exact email Authentik sends.

2. **SSO stopped working after an n8n upgrade, n8n otherwise fine**

   - **Cause**: The external hook could not find an n8n internal it depends on.
   - **Fix**: Look for `[forward-auth]` errors in the main pod log and update `hooks-configmap.yaml` for the new internals.

3. **A webhook or MCP call from outside is redirected to the Authentik login page**

   - **Cause**: The path is not in the blueprint's `skip_path_regex`.
   - **Fix**: Add it there and let the blueprint re-apply.

## References

- [n8n Documentation](https://docs.n8n.io/)
- [n8n external hooks](https://docs.n8n.io/hosting/configuration/environment-variables/external-hooks/)
