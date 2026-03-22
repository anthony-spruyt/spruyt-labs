# Shutdown Orchestrator Go Rewrite — Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development
> (recommended) or superpowers:executing-plans to implement this plan task-by-task.
> Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace the bash shutdown/recovery scripts with a Go binary that has proper
error handling, timeouts, automatic recovery, preflight validation, and a test mode
that exercises real shutdown against the live cluster.

**Architecture:** Single Go binary with three modes (monitor, test, preflight). Uses
client-go for Kubernetes API, Talos gRPC client for node shutdown, and a minimal NUT
protocol client for UPS monitoring. Interfaces for all external dependencies enable
unit testing with mocks.

**Tech Stack:** Go 1.24+, client-go v0.35.x, Talos machinery client, distroless
container image, GitHub Actions CI.

**Spec:** `docs/superpowers/specs/2026-03-22-shutdown-orchestrator-go-rewrite-design.md`

**Issue:** [#719](https://github.com/anthony-spruyt/spruyt-labs/issues/719)

---

## File Structure

All Go code lives in `cmd/shutdown-orchestrator/` within the repo root.

```text
cmd/shutdown-orchestrator/
├── main.go                  # CLI entrypoint, mode selection
├── config.go                # Config struct, env var parsing
├── config_test.go           # Config parsing tests
├── orchestrator.go          # Shutdown + recovery sequence logic
├── orchestrator_test.go     # Sequence ordering, error handling, timeout tests
├── monitor.go               # UPS polling loop + health endpoint
├── monitor_test.go          # Polling loop, power-restored cancellation tests
├── preflight.go             # Prerequisite validation
├── preflight_test.go        # Preflight check tests
├── phases/
│   ├── cnpg.go              # Hibernate / wake CNPG clusters
│   ├── cnpg_test.go         # CNPG phase tests
│   ├── ceph.go              # Noout flag, scale down / up
│   ├── ceph_test.go         # Ceph phase tests
│   └── nodes.go             # Shutdown via Talos gRPC
│   └── nodes_test.go        # Node shutdown tests (parallel, self-skip)
├── clients/
│   ├── interfaces.go        # KubeClient, TalosClient, UPSClient interfaces + types
│   ├── kube.go              # client-go implementation of KubeClient
│   ├── talos.go             # Talos gRPC implementation of TalosClient
│   └── ups.go               # NUT protocol implementation of UPSClient
│   └── ups_test.go          # NUT protocol parsing tests
├── Dockerfile               # Multi-stage build
├── go.mod                   # Go module definition
└── go.sum                   # Dependency checksums
```

Kubernetes manifests modified:

```text
cluster/apps/nut-system/shutdown-orchestrator/app/
├── values.yaml              # Replace container image, env vars, probes, remove init container
├── kustomization.yaml       # Remove shutdown-script-configmap, recovery-script-configmap
├── release.yaml             # No changes needed
├── rbac.yaml                # No changes needed
├── vpa.yaml                 # Update container name if needed
├── shutdown-script-configmap.yaml   # DELETE
├── recovery-script-configmap.yaml   # DELETE
├── recovery-job.yaml                # DELETE (keep for reference, already excluded from kustomization)
```

CI:

```text
.github/workflows/
└── shutdown-orchestrator.yaml   # Build, test, push to GHCR
```

---

## Task 0: Project Scaffolding

**Files:**

- Create: `cmd/shutdown-orchestrator/go.mod`
- Create: `cmd/shutdown-orchestrator/main.go`
- Create: `cmd/shutdown-orchestrator/config.go`
- Create: `cmd/shutdown-orchestrator/config_test.go`


- [ ] **Step 1: Install Go toolchain**

Dev container may not have Go. Install it:

```bash
# Check if go is available
go version || true
# If not, install (adjust version as needed)
curl -sL https://go.dev/dl/go1.24.4.linux-amd64.tar.gz | sudo tar -C /usr/local -xz
export PATH=$PATH:/usr/local/go/bin
go version
```

- [ ] **Step 2: Initialize Go module**

```bash
mkdir -p cmd/shutdown-orchestrator
cd cmd/shutdown-orchestrator
go mod init github.com/anthony-spruyt/spruyt-labs/cmd/shutdown-orchestrator
```

- [ ] **Step 3: Write config test**

Create `cmd/shutdown-orchestrator/config_test.go`:

```go
package main

import (
  "os"
  "testing"
)

func TestLoadConfigDefaults(t *testing.T) {
  // Clear any env vars that might interfere
  for _, key := range []string{"MODE", "NUT_SERVER", "NUT_PORT", "UPS_NAME",
    "SHUTDOWN_DELAY", "POLL_INTERVAL", "UPS_RUNTIME_BUDGET", "HEALTH_PORT"} {
    os.Unsetenv(key)
  }

  cfg := LoadConfig()

  if cfg.Mode != "monitor" {
    t.Errorf("Mode = %q, want %q", cfg.Mode, "monitor")
  }
  if cfg.NUTServer != "nut-server-nut.nut-system.svc.cluster.local" {
    t.Errorf("NUTServer = %q, want default", cfg.NUTServer)
  }
  if cfg.NUTPort != 3493 {
    t.Errorf("NUTPort = %d, want 3493", cfg.NUTPort)
  }
  if cfg.UPSName != "cp1500" {
    t.Errorf("UPSName = %q, want %q", cfg.UPSName, "cp1500")
  }
  if cfg.ShutdownDelay != 30 {
    t.Errorf("ShutdownDelay = %d, want 30", cfg.ShutdownDelay)
  }
  if cfg.PollInterval != 5 {
    t.Errorf("PollInterval = %d, want 5", cfg.PollInterval)
  }
  if cfg.UPSRuntimeBudget != 600 {
    t.Errorf("UPSRuntimeBudget = %d, want 600", cfg.UPSRuntimeBudget)
  }
  if cfg.HealthPort != 8080 {
    t.Errorf("HealthPort = %d, want 8080", cfg.HealthPort)
  }
}

func TestLoadConfigFromEnv(t *testing.T) {
  os.Setenv("MODE", "test")
  os.Setenv("SHUTDOWN_DELAY", "60")
  os.Setenv("UPS_RUNTIME_BUDGET", "900")
  defer func() {
    os.Unsetenv("MODE")
    os.Unsetenv("SHUTDOWN_DELAY")
    os.Unsetenv("UPS_RUNTIME_BUDGET")
  }()

  cfg := LoadConfig()

  if cfg.Mode != "test" {
    t.Errorf("Mode = %q, want %q", cfg.Mode, "test")
  }
  if cfg.ShutdownDelay != 60 {
    t.Errorf("ShutdownDelay = %d, want 60", cfg.ShutdownDelay)
  }
  if cfg.UPSRuntimeBudget != 900 {
    t.Errorf("UPSRuntimeBudget = %d, want 900", cfg.UPSRuntimeBudget)
  }
}

func TestLoadConfigNodeIPs(t *testing.T) {
  os.Setenv("MS_01_1_IP4", "10.0.0.1")
  os.Setenv("MS_01_2_IP4", "10.0.0.2")
  os.Setenv("MS_01_3_IP4", "10.0.0.3")
  os.Setenv("E2_1_IP4", "10.0.1.1")
  os.Setenv("E2_2_IP4", "10.0.1.2")
  os.Setenv("E2_3_IP4", "10.0.1.3")
  defer func() {
    for _, k := range []string{"MS_01_1_IP4", "MS_01_2_IP4", "MS_01_3_IP4",
      "E2_1_IP4", "E2_2_IP4", "E2_3_IP4"} {
      os.Unsetenv(k)
    }
  }()

  cfg := LoadConfig()

  if len(cfg.WorkerIPs) != 3 {
    t.Fatalf("WorkerIPs len = %d, want 3", len(cfg.WorkerIPs))
  }
  if len(cfg.ControlPlaneIPs) != 3 {
    t.Fatalf("ControlPlaneIPs len = %d, want 3", len(cfg.ControlPlaneIPs))
  }
  if cfg.WorkerIPs[0] != "10.0.0.1" {
    t.Errorf("WorkerIPs[0] = %q, want %q", cfg.WorkerIPs[0], "10.0.0.1")
  }
}

func TestLoadConfigInvalidMode(t *testing.T) {
  os.Setenv("MODE", "invalid")
  defer os.Unsetenv("MODE")

  cfg := LoadConfig()
  if err := cfg.Validate(); err == nil {
    t.Error("Validate() = nil, want error for invalid mode")
  }
}
```

- [ ] **Step 4: Run test, verify it fails**

```bash
cd cmd/shutdown-orchestrator && go test -run TestLoadConfig -v
```

Expected: FAIL — `LoadConfig` and `Config` not defined.

- [ ] **Step 5: Write config implementation**

Create `cmd/shutdown-orchestrator/config.go`:

```go
package main

import (
  "fmt"
  "os"
  "strconv"
  "time"
)

type Config struct {
  Mode             string
  NUTServer        string
  NUTPort          int
  UPSName          string
  ShutdownDelay    int
  PollInterval     int
  UPSRuntimeBudget int
  HealthPort       int
  NodeName         string

  // Phase timeouts
  CNPGPhaseTimeout         time.Duration
  CephFlagPhaseTimeout     time.Duration
  CephScalePhaseTimeout    time.Duration
  NodeShutdownPhaseTimeout time.Duration

  // Node IPs
  WorkerIPs       []string
  ControlPlaneIPs []string

  // Talos config path
  TalosConfigPath string
}

func LoadConfig() Config {
  cfg := Config{
    Mode:                     envOrDefault("MODE", "monitor"),
    NUTServer:                envOrDefault("NUT_SERVER", "nut-server-nut.nut-system.svc.cluster.local"),
    NUTPort:                  envIntOrDefault("NUT_PORT", 3493),
    UPSName:                  envOrDefault("UPS_NAME", "cp1500"),
    ShutdownDelay:            envIntOrDefault("SHUTDOWN_DELAY", 30),
    PollInterval:             envIntOrDefault("POLL_INTERVAL", 5),
    UPSRuntimeBudget:         envIntOrDefault("UPS_RUNTIME_BUDGET", 600),
    HealthPort:               envIntOrDefault("HEALTH_PORT", 8080),
    NodeName:                 os.Getenv("NODE_NAME"),
    CNPGPhaseTimeout:         time.Duration(envIntOrDefault("CNPG_PHASE_TIMEOUT", 60)) * time.Second,
    CephFlagPhaseTimeout:     time.Duration(envIntOrDefault("CEPH_FLAG_PHASE_TIMEOUT", 15)) * time.Second,
    CephScalePhaseTimeout:    time.Duration(envIntOrDefault("CEPH_SCALE_PHASE_TIMEOUT", 60)) * time.Second,
    NodeShutdownPhaseTimeout: time.Duration(envIntOrDefault("NODE_SHUTDOWN_PHASE_TIMEOUT", 120)) * time.Second,
    TalosConfigPath:          envOrDefault("TALOSCONFIG", "/talos/talosconfig"),
  }

  // Collect non-empty node IPs
  for _, key := range []string{"MS_01_1_IP4", "MS_01_2_IP4", "MS_01_3_IP4"} {
    if ip := os.Getenv(key); ip != "" {
      cfg.WorkerIPs = append(cfg.WorkerIPs, ip)
    }
  }
  for _, key := range []string{"E2_1_IP4", "E2_2_IP4", "E2_3_IP4"} {
    if ip := os.Getenv(key); ip != "" {
      cfg.ControlPlaneIPs = append(cfg.ControlPlaneIPs, ip)
    }
  }

  return cfg
}

func (c Config) Validate() error {
  switch c.Mode {
  case "monitor", "test", "preflight":
    // valid
  default:
    return fmt.Errorf("invalid mode %q: must be monitor, test, or preflight", c.Mode)
  }
  return nil
}

func envOrDefault(key, def string) string {
  if v := os.Getenv(key); v != "" {
    return v
  }
  return def
}

func envIntOrDefault(key string, def int) int {
  if v := os.Getenv(key); v != "" {
    if n, err := strconv.Atoi(v); err == nil {
      return n
    }
  }
  return def
}
```

- [ ] **Step 6: Write minimal main.go**

Create `cmd/shutdown-orchestrator/main.go`:

```go
package main

import (
  "fmt"
  "log"
  "os"
)

func main() {
  cfg := LoadConfig()
  if err := cfg.Validate(); err != nil {
    log.Fatalf("invalid configuration: %v", err)
  }

  switch cfg.Mode {
  case "monitor":
    fmt.Println("monitor mode not yet implemented")
    os.Exit(1)
  case "test":
    fmt.Println("test mode not yet implemented")
    os.Exit(1)
  case "preflight":
    fmt.Println("preflight mode not yet implemented")
    os.Exit(1)
  }
}
```

- [ ] **Step 7: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v ./...
```

Expected: All config tests PASS.

- [ ] **Step 8: Commit**

```bash
git add cmd/shutdown-orchestrator/go.mod cmd/shutdown-orchestrator/go.sum \
  cmd/shutdown-orchestrator/main.go cmd/shutdown-orchestrator/config.go \
  cmd/shutdown-orchestrator/config_test.go
git commit -m "feat(nut-system): scaffold shutdown-orchestrator Go project

Initialize Go module, config parsing with env vars, mode validation.

Ref #719"
```

---

## Task 1: Client Interfaces and Types

**Files:**

- Create: `cmd/shutdown-orchestrator/clients/interfaces.go`


- [ ] **Step 1: Create interfaces file**

Create `cmd/shutdown-orchestrator/clients/interfaces.go`:

```go
package clients

import "context"

// CNPGCluster represents a CNPG cluster with its hibernation state.
type CNPGCluster struct {
  Namespace  string
  Name       string
  Hibernated bool
}

// Node represents a Kubernetes node.
type Node struct {
  Name  string
  Ready bool
}

// KubeClient abstracts Kubernetes API operations.
type KubeClient interface {
  // CNPG operations
  GetCNPGClusters(ctx context.Context) ([]CNPGCluster, error)
  SetCNPGHibernation(ctx context.Context, ns, name string, hibernate bool) error

  // Ceph operations
  DeploymentExists(ctx context.Context, ns, name string) (bool, error)
  ExecInDeployment(ctx context.Context, ns, deploy string, cmd []string) (string, error)
  ScaleDeployment(ctx context.Context, ns, name string, replicas int32) error
  ListDeploymentNames(ctx context.Context, ns, labelSelector string) ([]string, error)

  // Node operations
  GetNodes(ctx context.Context) ([]Node, error)

  // Recovery detection
  IsCephNooutSet(ctx context.Context) (bool, error)
}

// TalosClient abstracts Talos node operations.
type TalosClient interface {
  Shutdown(ctx context.Context, nodeIP string, force bool) error
}

// UPSClient abstracts UPS status queries.
type UPSClient interface {
  GetStatus(ctx context.Context) (string, error)
}
```

- [ ] **Step 2: Verify it compiles**

```bash
cd cmd/shutdown-orchestrator && go build ./clients/
```

Expected: No errors.

- [ ] **Step 3: Commit**

```bash
git add cmd/shutdown-orchestrator/clients/interfaces.go
git commit -m "feat(nut-system): add client interfaces for kube, talos, and UPS

Ref #719"
```

---

## Task 2: UPS Client (NUT Protocol)

**Files:**

- Create: `cmd/shutdown-orchestrator/clients/ups.go`
- Create: `cmd/shutdown-orchestrator/clients/ups_test.go`


- [ ] **Step 1: Write NUT protocol parsing test**

Create `cmd/shutdown-orchestrator/clients/ups_test.go`:

```go
package clients

import (
  "bufio"
  "context"
  "fmt"
  "net"
  "strings"
  "testing"
  "time"
)

// fakeNUTServer creates a TCP server that responds to NUT protocol commands.
func fakeNUTServer(t *testing.T, responses map[string]string) (string, func()) {
  t.Helper()
  ln, err := net.Listen("tcp", "127.0.0.1:0")
  if err != nil {
    t.Fatalf("listen: %v", err)
  }
  go func() {
    for {
      conn, err := ln.Accept()
      if err != nil {
        return
      }
      go func(c net.Conn) {
        defer c.Close()
        scanner := bufio.NewScanner(c)
        for scanner.Scan() {
          line := scanner.Text()
          if resp, ok := responses[line]; ok {
            fmt.Fprintln(c, resp)
          } else {
            fmt.Fprintln(c, "ERR UNKNOWN")
          }
        }
      }(conn)
    }
  }()
  return ln.Addr().String(), func() { ln.Close() }
}

func TestNUTClientGetStatus(t *testing.T) {
  addr, cleanup := fakeNUTServer(t, map[string]string{
    "GET VAR testups ups.status": "VAR testups ups.status \"OL\"",
  })
  defer cleanup()

  parts := strings.SplitN(addr, ":", 2)
  host := parts[0]
  port := 0
  fmt.Sscanf(parts[1], "%d", &port)

  client := NewNUTClient(host, port, "testups")
  ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
  defer cancel()

  status, err := client.GetStatus(ctx)
  if err != nil {
    t.Fatalf("GetStatus() error: %v", err)
  }
  if status != "OL" {
    t.Errorf("GetStatus() = %q, want %q", status, "OL")
  }
}

func TestNUTClientGetStatusOnBattery(t *testing.T) {
  addr, cleanup := fakeNUTServer(t, map[string]string{
    "GET VAR testups ups.status": "VAR testups ups.status \"OB DISCHRG\"",
  })
  defer cleanup()

  parts := strings.SplitN(addr, ":", 2)
  host := parts[0]
  port := 0
  fmt.Sscanf(parts[1], "%d", &port)

  client := NewNUTClient(host, port, "testups")
  ctx, cancel := context.WithTimeout(context.Background(), 2*time.Second)
  defer cancel()

  status, err := client.GetStatus(ctx)
  if err != nil {
    t.Fatalf("GetStatus() error: %v", err)
  }
  if !strings.Contains(status, "OB") {
    t.Errorf("GetStatus() = %q, want to contain %q", status, "OB")
  }
}

func TestNUTClientConnectionRefused(t *testing.T) {
  client := NewNUTClient("127.0.0.1", 1, "testups") // port 1 = refused
  ctx, cancel := context.WithTimeout(context.Background(), 1*time.Second)
  defer cancel()

  _, err := client.GetStatus(ctx)
  if err == nil {
    t.Error("GetStatus() = nil error, want connection error")
  }
}
```

- [ ] **Step 2: Run test, verify it fails**

```bash
cd cmd/shutdown-orchestrator && go test -v ./clients/ -run TestNUT
```

Expected: FAIL — `NewNUTClient` not defined.

- [ ] **Step 3: Implement NUT client**

Create `cmd/shutdown-orchestrator/clients/ups.go`:

```go
package clients

import (
  "bufio"
  "context"
  "fmt"
  "net"
  "strings"
)

// NUTClient implements UPSClient using the NUT protocol over TCP.
type NUTClient struct {
  host    string
  port    int
  upsName string
}

func NewNUTClient(host string, port int, upsName string) *NUTClient {
  return &NUTClient{host: host, port: port, upsName: upsName}
}

func (c *NUTClient) GetStatus(ctx context.Context) (string, error) {
  addr := fmt.Sprintf("%s:%d", c.host, c.port)

  var d net.Dialer
  conn, err := d.DialContext(ctx, "tcp", addr)
  if err != nil {
    return "", fmt.Errorf("connecting to NUT server %s: %w", addr, err)
  }
  defer conn.Close()

  // Set deadline from context
  if deadline, ok := ctx.Deadline(); ok {
    conn.SetDeadline(deadline)
  }

  cmd := fmt.Sprintf("GET VAR %s ups.status\n", c.upsName)
  if _, err := conn.Write([]byte(cmd)); err != nil {
    return "", fmt.Errorf("sending command: %w", err)
  }

  scanner := bufio.NewScanner(conn)
  if !scanner.Scan() {
    if err := scanner.Err(); err != nil {
      return "", fmt.Errorf("reading response: %w", err)
    }
    return "", fmt.Errorf("no response from NUT server")
  }

  line := scanner.Text()
  return parseNUTVar(line, c.upsName, "ups.status")
}

// parseNUTVar extracts the value from a NUT response line.
// Format: VAR <upsname> <varname> "<value>"
func parseNUTVar(line, upsName, varName string) (string, error) {
  prefix := fmt.Sprintf("VAR %s %s ", upsName, varName)
  if !strings.HasPrefix(line, prefix) {
    return "", fmt.Errorf("unexpected response: %s", line)
  }
  value := strings.TrimPrefix(line, prefix)
  value = strings.Trim(value, "\"")
  return value, nil
}
```

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v ./clients/ -run TestNUT
```

Expected: All 3 tests PASS.

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/clients/ups.go \
  cmd/shutdown-orchestrator/clients/ups_test.go
git commit -m "feat(nut-system): implement NUT protocol client for UPS status

Ref #719"
```

---

## Task 3: CNPG Phase

**Files:**

- Create: `cmd/shutdown-orchestrator/phases/cnpg.go`
- Create: `cmd/shutdown-orchestrator/phases/cnpg_test.go`


- [ ] **Step 1: Write CNPG phase tests**

Create `cmd/shutdown-orchestrator/phases/cnpg_test.go`. Tests should cover:

- Hibernate all clusters: mock returns 2 clusters, verify both get annotated
- No clusters found: mock returns empty list, verify no error (info log)
- CRD not installed: mock GetCNPGClusters returns "not found" error, verify no error
  (info level skip)
- Annotation failure: mock SetCNPGHibernation fails for one cluster, verify continues
  to next (error level, not fatal)
- Wake all hibernated clusters: mock returns 2 hibernated clusters, verify both get
  annotation removed
- Context timeout: mock that blocks forever, verify context cancellation is respected

Use a mock KubeClient struct that records calls in order.

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestCNPG
```

- [ ] **Step 3: Implement CNPG phase**

Create `cmd/shutdown-orchestrator/phases/cnpg.go` with:

- `type CNPGPhase struct { kube clients.KubeClient; logger *slog.Logger }`
- `func (p *CNPGPhase) Hibernate(ctx context.Context) error`
- `func (p *CNPGPhase) Wake(ctx context.Context) error`

Hibernate: list clusters, annotate each with per-cluster timeout from context.
Wake: list clusters, remove annotation from hibernated ones.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestCNPG
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/phases/cnpg.go \
  cmd/shutdown-orchestrator/phases/cnpg_test.go
git commit -m "feat(nut-system): implement CNPG hibernate/wake phase

Ref #719"
```

---

## Task 4: Ceph Phase

**Files:**

- Create: `cmd/shutdown-orchestrator/phases/ceph.go`
- Create: `cmd/shutdown-orchestrator/phases/ceph_test.go`


- [ ] **Step 1: Write Ceph phase tests**

Create `cmd/shutdown-orchestrator/phases/ceph_test.go`. Tests should cover:

- SetNoout: mock exec succeeds, verify correct command (`ceph osd set noout`)
- SetNoout tools pod missing: mock DeploymentExists returns false, verify warning
  (not error)
- UnsetNoout: verify correct command (`ceph osd unset noout`)
- ScaleDown: verify correct order (operator → OSDs → monitors → managers), verify
  each scale call gets replicas=0
- ScaleDown with multiple OSDs: mock ListDeploymentNames returns 3 OSD deploys,
  verify all scaled
- ScaleDown operator fails: mock ScaleDeployment fails for operator, verify
  continues to OSDs/mons/mgrs (warning level, not fatal — per error handling table)
- ScaleDown OSD fails: mock ScaleDeployment fails for one OSD deploy, verify
  continues to remaining OSDs and mons/mgrs (warning level)
- ScaleUp: verify correct order (monitors → managers → OSDs → operator), verify
  each scale call gets replicas=1
- WaitForToolsPod: mock DeploymentExists returns false 3 times then true, verify
  exponential backoff (1s, 2s, 4s). Mock never returns true, verify timeout after
  10 minutes and continues with error.
- IsCephNooutSet: mock exec returns dump with noout, verify true. Mock returns dump
  without noout, verify false.
- Context timeout during scale-down: verify cancellation respected

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestCeph
```

- [ ] **Step 3: Implement Ceph phase**

Create `cmd/shutdown-orchestrator/phases/ceph.go` with:

- `type CephPhase struct { kube clients.KubeClient; logger *slog.Logger }`
- `func (p *CephPhase) SetNoout(ctx context.Context) error`
- `func (p *CephPhase) UnsetNoout(ctx context.Context) error`
- `func (p *CephPhase) ScaleDown(ctx context.Context) error`
- `func (p *CephPhase) ScaleUp(ctx context.Context) error`
- `func (p *CephPhase) WaitForToolsPod(ctx context.Context) error` — retry with
  exponential backoff (1s, 2s, 4s, ..., max 30s interval) up to 10 minutes. Returns
  error if tools pod never becomes available.
- `func (p *CephPhase) NeedsRecovery(ctx context.Context) (bool, error)`

ScaleDown order: operator (`rook-ceph-operator`) → OSDs (`app=rook-ceph-osd`) →
monitors (`app=rook-ceph-mon`) → managers (`app=rook-ceph-mgr`).

ScaleUp order: reverse — monitors → managers → OSDs → operator.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestCeph
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/phases/ceph.go \
  cmd/shutdown-orchestrator/phases/ceph_test.go
git commit -m "feat(nut-system): implement Ceph noout flag and scale phases

Ref #719"
```

---

## Task 5: Node Shutdown Phase

**Files:**

- Create: `cmd/shutdown-orchestrator/phases/nodes.go`
- Create: `cmd/shutdown-orchestrator/phases/nodes_test.go`


- [ ] **Step 1: Write node phase tests**

Create `cmd/shutdown-orchestrator/phases/nodes_test.go`. Tests should cover:

- ShutdownAll: verify workers called before control plane
- Workers concurrent: mock with artificial delay, verify all workers are called
  (WaitGroup completes)
- Control plane sequential: verify called in order
- Self-skip in test mode: set nodeName matching a CP entry, verify that entry is
  excluded from shutdown
- Self-last in real mode: set nodeName matching a CP entry, verify it is called last
- NodeName not found: set nodeName to unknown value, verify warning logged and all
  nodes still shut down (fail-open)
- Single node timeout: mock one node blocks forever, verify others still get called
- Auth failure: mock returns auth error, verify phase aborts (fatal)
- All force: verify every Shutdown call has force=true

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestNode
```

- [ ] **Step 3: Implement node phase**

Create `cmd/shutdown-orchestrator/phases/nodes.go` with:

- `type NodePhase struct { talos clients.TalosClient; logger *slog.Logger }`
- `func (p *NodePhase) ShutdownAll(ctx context.Context, cfg NodeConfig) error`
- `type NodeEntry struct { Name string; IP string }` — pairs node name with IP
- `type NodeConfig struct { Workers, ControlPlane []NodeEntry; NodeName string; TestMode bool; PerNodeTimeout time.Duration }`

Config construction (in `config.go`): `NODE_NAME` is a Kubernetes node name (e.g.,
`e2-1`). To map it to an IP, the orchestrator queries `KubeClient.GetNodes()` at
startup and matches node names to the configured IPs via node `status.addresses`.
This mapping is stored in `NodeEntry` pairs used by `NodeConfig`.

ShutdownAll: workers concurrently with WaitGroup, then CP sequentially. In test
mode, skip the entry matching `NodeName`. In real mode, move the entry matching
`NodeName` to last position in CP list. Every call uses `force=true`.

If `NodeName` doesn't match any known node, log a warning and proceed without
self-skip/self-last (fail-open — shutting down is more important than self-protection).

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v ./phases/ -run TestNode
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/phases/nodes.go \
  cmd/shutdown-orchestrator/phases/nodes_test.go
git commit -m "feat(nut-system): implement node shutdown phase with self-skip

Ref #719"
```

---

## Task 6: Orchestrator (Shutdown + Recovery Sequences)

**Files:**

- Create: `cmd/shutdown-orchestrator/orchestrator.go`
- Create: `cmd/shutdown-orchestrator/orchestrator_test.go`


- [ ] **Step 1: Write orchestrator tests**

Create `cmd/shutdown-orchestrator/orchestrator_test.go`. Tests should cover:

- Shutdown sequence ordering: verify phases called in order (CNPG → Ceph flag →
  Ceph scale → nodes)
- Recovery sequence ordering: verify phases called in order (wait for tools pod →
  Ceph scale-up → Ceph unset flag → CNPG wake → health verify)
- Phase timeout: mock CNPG phase blocks beyond timeout, verify Ceph phase still runs
- Overall deadline: mock all phases slow, verify node shutdown is reached before
  budget expires
- Recovery detection: mock IsCephNooutSet returns true, verify recovery runs
- Recovery detection: mock IsCephNooutSet returns false but CNPG clusters are
  hibernated, verify recovery still runs (partial recovery scenario)
- Recovery detection: mock IsCephNooutSet returns false and no hibernated clusters,
  verify recovery is skipped
- Recovery health verification: mock GetNodes returns all ready + Ceph healthy +
  CNPG running, verify health check passes. Mock partial health (Ceph degraded),
  verify warning logged but recovery completes.
- Test mode: verify shutdown runs, then waits for nodes (mock GetNodes to return
  not-ready then ready after delay), then recovery runs

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestOrchestrator
```

- [ ] **Step 3: Implement orchestrator**

Create `cmd/shutdown-orchestrator/orchestrator.go` with:

- `type Orchestrator struct { cnpg *phases.CNPGPhase; ceph *phases.CephPhase; nodes *phases.NodePhase; cfg Config; logger *slog.Logger }`
- `func (o *Orchestrator) Shutdown(ctx context.Context) error` — runs phases in
  order, each with its own timeout context. If overall deadline approaches, skips to
  nodes.
- `func (o *Orchestrator) Recover(ctx context.Context) error` — wait for Ceph tools
  pod (via `CephPhase.WaitForToolsPod`) → Ceph scale-up → unset noout → wake CNPG →
  verify health.
- `func (o *Orchestrator) NeedsRecovery(ctx context.Context) (bool, error)` — checks
  BOTH Ceph noout flag (via `CephPhase.NeedsRecovery`) AND CNPG hibernation state
  (via `CNPGPhase` — any cluster with hibernation annotation). Returns true if either
  condition is met.
- `func (o *Orchestrator) RunTest(ctx context.Context) error` — calls Shutdown (test
  mode), then polls `KubeClient.GetNodes()` every 10s waiting for all shutdown nodes
  to return to Ready state (no timeout — user physically powers on nodes, logs
  progress periodically), then calls Recover.
- `func (o *Orchestrator) verifyHealth(ctx context.Context) error` — checks:
  all nodes Ready (`KubeClient.GetNodes`), Ceph healthy (`ExecInDeployment` →
  `ceph status` → parse for `HEALTH_OK`), CNPG clusters not hibernated
  (`GetCNPGClusters` → check none hibernated). Logs warnings for degraded state
  but does not fail.

Each phase is wrapped in `runPhase(ctx, name, timeout, fn)` which logs start/end,
applies timeout, and handles errors per the severity table.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestOrchestrator
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/orchestrator.go \
  cmd/shutdown-orchestrator/orchestrator_test.go
git commit -m "feat(nut-system): implement shutdown/recovery orchestrator

Ref #719"
```

---

## Task 7: Preflight Checks

**Files:**

- Create: `cmd/shutdown-orchestrator/preflight.go`
- Create: `cmd/shutdown-orchestrator/preflight_test.go`


- [ ] **Step 1: Write preflight tests**

Create `cmd/shutdown-orchestrator/preflight_test.go`. Tests for each check
independently:

- Kubernetes API unreachable: mock KubeClient.GetNodes returns connection error,
  verify check fails with descriptive message
- CNPG CRD missing: mock GetCNPGClusters returns "not found" / CRD not registered
  error, verify check fails
- CNPG clusters not listable: mock GetCNPGClusters returns RBAC forbidden, verify
  check fails
- Ceph tools pod missing: mock DeploymentExists returns false, verify check fails
- Ceph tools exec fails: mock ExecInDeployment returns error, verify check fails
- Ceph deployments not listable: mock ListDeploymentNames returns error, verify
  check fails
- Talos API unreachable for one node: mock TalosClient connection fails for one IP,
  verify that specific node is reported and other nodes still checked
- Node IPs missing: config with empty WorkerIPs/ControlPlaneIPs, verify check fails
- UPS unreachable: mock UPSClient.GetStatus returns connection error, verify check
  fails
- All checks pass: all mocks succeed, verify all results Passed, exit code 0
- Multiple checks fail: mock 3 checks fail, verify all 3 failures reported (not
  just the first one)

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestPreflight
```

- [ ] **Step 3: Implement preflight**

Create `cmd/shutdown-orchestrator/preflight.go` with:

- `type PreflightChecker struct { kube clients.KubeClient; talos clients.TalosClient; ups clients.UPSClient; cfg Config; logger *slog.Logger }`
- `func (p *PreflightChecker) RunAll(ctx context.Context) []PreflightResult`
- `type PreflightResult struct { Check string; Passed bool; Error string }`

Run all checks, collect results, return all (don't stop on first failure).

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestPreflight
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/preflight.go \
  cmd/shutdown-orchestrator/preflight_test.go
git commit -m "feat(nut-system): implement preflight checks replacing DRY_RUN

Ref #719"
```

---

## Task 8: Monitor (UPS Polling Loop + Health Endpoint)

**Files:**

- Create: `cmd/shutdown-orchestrator/monitor.go`
- Create: `cmd/shutdown-orchestrator/monitor_test.go`


- [ ] **Step 1: Write monitor tests**

Tests should cover:

- UPS online: mock returns "OL" status, verify no shutdown triggered after N polls
- Power loss detection: mock returns "OB", verify countdown starts
- Power restored during countdown: mock returns "OB" then "OL", verify countdown
  resets
- Countdown expires: mock returns "OB" for >shutdownDelay, verify shutdown is
  triggered (via callback/channel)
- Health endpoint: start monitor, verify /healthz returns 200. During shutdown,
  verify /healthz returns 503.

- [ ] **Step 2: Run tests, verify they fail**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestMonitor
```

- [ ] **Step 3: Implement monitor**

Create `cmd/shutdown-orchestrator/monitor.go` with:

- `type Monitor struct { ups clients.UPSClient; orchestrator *Orchestrator; cfg Config; logger *slog.Logger; shuttingDown atomic.Bool }`
- `func (m *Monitor) Run(ctx context.Context) error` — start health server, run
  preflight, detect recovery, poll UPS in loop, trigger shutdown when countdown
  expires.
- `func (m *Monitor) healthHandler(w http.ResponseWriter, r *http.Request)` —
  returns 200 or 503 based on `shuttingDown`.

Poll loop: check UPS status every `PollInterval` seconds. If status contains "OB",
start countdown. If power restores, reset countdown. If countdown reaches
`ShutdownDelay`, call `orchestrator.Shutdown()`.

- [ ] **Step 4: Run tests, verify they pass**

```bash
cd cmd/shutdown-orchestrator && go test -v -run TestMonitor
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/monitor.go \
  cmd/shutdown-orchestrator/monitor_test.go
git commit -m "feat(nut-system): implement UPS monitor with health endpoint

Ref #719"
```

---

## Task 9: Real Client Implementations

**Files:**

- Create: `cmd/shutdown-orchestrator/clients/kube.go`
- Create: `cmd/shutdown-orchestrator/clients/talos.go`


- [ ] **Step 1: Implement KubeClient with client-go**

Create `cmd/shutdown-orchestrator/clients/kube.go`. This uses:

- `k8s.io/client-go` for Kubernetes API
- `k8s.io/client-go/rest` with `InClusterConfig()` for auth
- Dynamic client for CNPG CRD operations (unstructured)
- `k8s.io/client-go/kubernetes` typed client for deployments, pods, exec

Key methods:

- `GetCNPGClusters`: dynamic client list `clusters.postgresql.cnpg.io` across all
  namespaces
- `SetCNPGHibernation`: dynamic client patch annotation
- `DeploymentExists`: apps/v1 get deployment
- `ExecInDeployment`: list pods by label, pick first ready, use remotecommand for
  exec
- `ScaleDeployment`: apps/v1 update scale subresource
- `ListDeploymentNames`: apps/v1 list with label selector
- `GetNodes`: core/v1 list nodes
- `IsCephNooutSet`: ExecInDeployment + parse `ceph osd dump` output for `noout`

- [ ] **Step 2: Implement TalosClient with gRPC**

Create `cmd/shutdown-orchestrator/clients/talos.go`. This uses:

- `github.com/siderolabs/talos/pkg/machinery/client` for Talos API
- `github.com/siderolabs/talos/pkg/machinery/client/config` to parse talosconfig
- Import path: `github.com/siderolabs/talos/pkg/machinery`

Key method:

- `Shutdown`: create client from talosconfig, set target node, call
  `client.Shutdown(ctx, client.WithShutdownForce(force))`

- [ ] **Step 3: Fetch dependencies**

```bash
cd cmd/shutdown-orchestrator
go get k8s.io/client-go@v0.35.3
go get k8s.io/apimachinery@v0.35.3
go get github.com/siderolabs/talos/pkg/machinery@latest
go mod tidy
```

- [ ] **Step 4: Verify it compiles**

```bash
cd cmd/shutdown-orchestrator && go build -o /dev/null .
```

- [ ] **Step 5: Commit**

```bash
git add cmd/shutdown-orchestrator/clients/kube.go \
  cmd/shutdown-orchestrator/clients/talos.go \
  cmd/shutdown-orchestrator/go.mod cmd/shutdown-orchestrator/go.sum
git commit -m "feat(nut-system): implement real kube and talos clients

Ref #719"
```

---

## Task 10: Wire Up main.go

**Files:**

- Modify: `cmd/shutdown-orchestrator/main.go`


- [ ] **Step 1: Implement main.go mode dispatch**

Update `cmd/shutdown-orchestrator/main.go` to:

- Create real client implementations (KubeClient with client-go, TalosClient with
  Talos gRPC, UPSClient with NUT)
- Resolve NODE_NAME to IP: call `KubeClient.GetNodes()`, match node names to
  configured IPs via `status.addresses`, build `NodeEntry` pairs
- Construct phases and orchestrator
- Dispatch based on mode:
  - `monitor`: create Monitor, call Run
  - `test`: create Orchestrator, call RunTest
  - `preflight`: create PreflightChecker, call RunAll, print results, exit

Use `slog.New(slog.NewJSONHandler(os.Stdout, nil))` for structured logging.

- [ ] **Step 2: Verify it compiles**

```bash
cd cmd/shutdown-orchestrator && go build -o /dev/null .
```

- [ ] **Step 3: Commit**

```bash
git add cmd/shutdown-orchestrator/main.go cmd/shutdown-orchestrator/go.mod \
  cmd/shutdown-orchestrator/go.sum
git commit -m "feat(nut-system): wire up main.go with client construction

Ref #719"
```

---

## Task 11: Dockerfile and CI

**Files:**

- Create: `cmd/shutdown-orchestrator/Dockerfile`
- Create: `.github/workflows/shutdown-orchestrator.yaml`


- [ ] **Step 1: Create Dockerfile**

Create `cmd/shutdown-orchestrator/Dockerfile`:

```dockerfile
FROM golang:1.24-alpine AS builder

WORKDIR /build
COPY go.mod go.sum ./
RUN go mod download
COPY . .
RUN CGO_ENABLED=0 GOOS=linux GOARCH=amd64 go build -ldflags="-s -w" -o /shutdown-orchestrator .

FROM gcr.io/distroless/static:nonroot
COPY --from=builder /shutdown-orchestrator /shutdown-orchestrator
USER 65534:65534
ENTRYPOINT ["/shutdown-orchestrator"]
```

- [ ] **Step 2: Create GitHub Actions workflow**

Create `.github/workflows/shutdown-orchestrator.yaml` that:

- Triggers on push to main when `cmd/shutdown-orchestrator/**` changes
- Triggers on PR for the same paths (test only, no push)
- Runs `go test ./...` in the module directory
- Builds Docker image
- On main push: tags with git SHA and `latest`, pushes to
  `ghcr.io/anthony-spruyt/shutdown-orchestrator`

Check existing workflows in `.github/workflows/` for patterns to follow.

- [ ] **Step 3: Verify Dockerfile builds locally**

```bash
cd cmd/shutdown-orchestrator && docker build -t shutdown-orchestrator:test .
```

- [ ] **Step 4: Commit**

```bash
git add cmd/shutdown-orchestrator/Dockerfile \
  .github/workflows/shutdown-orchestrator.yaml
git commit -m "feat(nut-system): add Dockerfile and CI workflow

Ref #719"
```

---

## Task 12: Update Kubernetes Manifests

**Files:**

- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml`
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml`
- Modify: `cluster/apps/nut-system/shutdown-orchestrator/app/vpa.yaml`
- Delete: `cluster/apps/nut-system/shutdown-orchestrator/app/shutdown-script-configmap.yaml`
- Delete: `cluster/apps/nut-system/shutdown-orchestrator/app/recovery-script-configmap.yaml`


- [ ] **Step 1: Read current manifests**

Read `values.yaml`, `kustomization.yaml`, `vpa.yaml` to understand current structure.

- [ ] **Step 2: Rewrite values.yaml**

Replace the entire values.yaml with the new container image, remove init container,
update env vars (replace `DRY_RUN` with `MODE`, add `NODE_NAME` downward API, add
timeout vars, add `HEALTH_PORT`), update probes to use HTTP `/healthz`, set
non-root security context, remove tools volume mount, remove scripts volume mount,
keep talos secret mount.

- [ ] **Step 3: Update kustomization.yaml**

Remove references to `shutdown-script-configmap.yaml` and
`recovery-script-configmap.yaml`. Remove `configMapGenerator` entry for
shutdown-orchestrator-values if it references the old config maps. Keep the
`kustomizeconfig.yaml` reference.

- [ ] **Step 4: Update vpa.yaml**

Update container name to match the new deployment (likely `app` stays the same).
Adjust resource boundaries based on the lighter Go binary (lower memory).

- [ ] **Step 5: Delete old configmaps**

```bash
git rm cluster/apps/nut-system/shutdown-orchestrator/app/shutdown-script-configmap.yaml
git rm cluster/apps/nut-system/shutdown-orchestrator/app/recovery-script-configmap.yaml
```

Note: `recovery-job.yaml` is already excluded from kustomization — leave it for
reference but it can be deleted too.

- [ ] **Step 6: Run qa-validator**

Validate the manifest changes before committing.

- [ ] **Step 7: Commit**

```bash
git add cluster/apps/nut-system/shutdown-orchestrator/app/values.yaml \
  cluster/apps/nut-system/shutdown-orchestrator/app/kustomization.yaml \
  cluster/apps/nut-system/shutdown-orchestrator/app/vpa.yaml
git commit -m "feat(nut-system): update manifests for Go shutdown-orchestrator

Remove bash script configmaps, update to custom container image,
add health probes, non-root security context, timeout configuration.

Ref #719"
```

---

## Task 13: Final Integration and Documentation

**Files:**

- Modify: `cluster/apps/nut-system/README.md`
- Modify: `cmd/shutdown-orchestrator/main.go` (if needed for final wiring)


- [ ] **Step 1: Run all Go tests**

```bash
cd cmd/shutdown-orchestrator && go test -v -count=1 ./...
```

All tests must pass.

- [ ] **Step 2: Build Docker image**

```bash
cd cmd/shutdown-orchestrator && docker build -t shutdown-orchestrator:test .
```

Must succeed.

- [ ] **Step 3: Update README**

Update `cluster/apps/nut-system/README.md`:

- Update Components table: orchestrator status from "Disabled" to "Active"
- Remove references to bash scripts
- Update configuration table to match new env vars
- Verify shutdown/recovery sections are accurate (already updated in earlier commit)

- [ ] **Step 4: Run qa-validator on all changes**

- [ ] **Step 5: Final commit**

```bash
git add cluster/apps/nut-system/README.md
git commit -m "docs(nut-system): update README for Go shutdown-orchestrator

Ref #719"
```

- [ ] **Step 6: Create PR**

```bash
gh pr create --title "feat(nut-system): rewrite shutdown-orchestrator in Go" \
  --body "$(cat <<'EOF'
## Summary

Rewrites the shutdown-orchestrator from bash scripts to a Go binary with:
- Proper error handling (not `|| true`)
- Per-phase and per-command timeouts with context cancellation
- Automatic recovery on pod startup (no manual recovery job)
- Test mode that exercises real shutdown against live cluster
- Preflight validation replacing useless DRY_RUN

## Linked Issue

Closes #719

## Changes

- New Go binary in `cmd/shutdown-orchestrator/`
- Custom container image (distroless, non-root, read-only rootfs)
- Removed bash script configmaps and manual recovery job
- Updated Kubernetes manifests for new image
- GitHub Actions CI for build + test + push to GHCR
- Comprehensive unit tests with mocked clients

## Testing

- [ ] All unit tests pass (`go test ./...`)
- [ ] Docker image builds successfully
- [ ] Preflight mode validates against live cluster
- [ ] Test mode exercises shutdown/recovery (with physical node power-on)
- [ ] Monitor mode detects UPS status changes

EOF
)"
```
