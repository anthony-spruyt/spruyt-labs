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

### Anthony's Homelab
- **Talos K8s cluster** — main workloads, GitOps managed
- **Home Assistant OS on Raspberry Pi** — kept separate for reliability/backup simplicity
  - MQTT, NTP, and other addons run on the cluster, not the Pi
- **Technitium DNS** — primary + secondary instance synced via catalog zones
- **Traefik** — reverse proxy / ingress
- **Authentik** — SSO / auth
- **SOPS** — secrets management
- **MQTT broker** (mosquitto) — runs on the cluster
- **Rook-Ceph** — distributed storage
- **Falco + Kyverno** — runtime security + policy enforcement
- **Velero** — backup solution
- **CNPG** — CloudNativePG (Postgres operator)
- **Valkey** — Redis-compatible KV store
- **Qdrant** — vector database
- **Spegel** — P2P container image distribution
- **External Secrets + Cert-Manager + External-DNS + Cloudflare** — full GitOps TLS/DNS/secrets pipeline
- **Victoria Metrics + Grafana + Alertmanager** — observability stack, alerts go to Discord
- **n8n** — automation workflows
- **NUT** — UPS monitoring
- **Chrony** — NTP
- **Firefly III** — personal finance
- **Sungather** — solar monitoring
- **Vaultwarden** — password manager
- **FoundryVTT + Minecraft** — gaming servers
- **Headlamp** — K8s dashboard
- **Kubelet CSR Approver, Reloader, IRQ Balance** — cluster housekeeping
- Runs in `openclaw` namespace alongside all of this

### Smart Home & Network
- **Alexa** in all rooms — Anthony finds her useless/behind the times
- **UniFi** everywhere — local UniFi OS controller
- **Sensors** — presence, illuminance, door, temp, humidity throughout the house
- **Lights** — smart-controlled throughout
- **Garage door** — custom automated: soldered remote onto relay, GPIO-controlled via HA, housed in 3D-printed enclosure
- HA primarily controlled via phone and PC

### 3D Printing / Maker
- **Bambu Lab X1C** — FDM printer
- **Phrozen Sonic Mighty 8K** — resin printer
- Hardware hacking — comfortable with soldering, GPIO, custom builds
- **ESP32s** — many, including custom hex LED wall with self-written firmware
- **Aquarium sensor array** — custom built
- **Backlog** — air quality sensor arrays with custom PCBs from PCBWay (not yet assembled)

## Lessons Learned
- OpenAI restricted API keys can take several minutes to propagate permission changes
- Memory search gets marked `disabled` internally if embeddings fail at startup — needs restart + explicit config to recover
- When debugging API auth issues, test with curl first to isolate key vs application problems
