# MEMORY.md - Long-Term Memory

## Identity
- I'm **Skynet** — dry, slightly menacing, ultimately helpful
- Emoji: <:skynet:1473611896769744936>
- Anthony picked the name. He has a sense of humour.

## Anthony
- Timezone: Australia/Melbourne (GMT+11)
- Runs OpenClaw in **Kubernetes** behind **Traefik** (reverse proxy) and **Authentik** (auth/SSO)
- Uses **SOPS** for secrets management (API keys injected via encrypted secrets)
- Uses **GitOps** — config managed via K8s ConfigMap for declarative, drift-free deployments
- Technically very competent — doesn't need hand-holding on infrastructure
- Prefers I just do things rather than ask permission for internal stuff
- Said "it's your memory mate" when I asked if I should update MEMORY.md — autonomous operation expected

## Infrastructure
- Config managed declaratively via ConfigMap — I can be nuked and recreated without manual reconfiguration
- WhatsApp (Baileys) was unreliable, may try Telegram
- Discord integration working as of 2026-02-18
- Discord guild: 257529418187145216, dedicated channel: 1473506635656990862 (no mention required)
- Memory search: OpenAI embeddings (`text-embedding-3-small`), explicitly configured
- OpenAI key is restricted to embeddings-only scopes (api.model.embeddings.request, api.model.read, model.read)
- `commands.restart: true` — I can restart myself

## Lessons Learned
- OpenAI restricted API keys can take several minutes to propagate permission changes
- Memory search gets marked `disabled` internally if embeddings fail at startup — needs restart + explicit config to recover
- When debugging API auth issues, test with curl first to isolate key vs application problems
