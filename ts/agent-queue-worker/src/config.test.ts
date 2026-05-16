import { beforeEach, describe, expect, it } from "vitest";
import { loadConfig } from "./config.js";

const VALID_ENV = {
  VALKEY_HOST: "valkey.default.svc.cluster.local",
  VALKEY_PASSWORD: "test",
  N8N_DISPATCH_WEBHOOK:
    "http://n8n.n8n-system.svc.cluster.local/webhook/dispatch",
  WORKER_TO_N8N_SECRET: "test",
  N8N_TO_WORKER_SECRET: "test",
  GITHUB_OWNER: "anthony-spruyt",
};

describe("loadConfig", () => {
  beforeEach(() => {
    for (const key of Object.keys(VALID_ENV)) delete process.env[key];
    delete process.env.VALKEY_PORT;
    delete process.env.PORT;
    delete process.env.GITHUB_TOKEN;
    delete process.env.SRE_BATCH_MAX_SIZE;
    delete process.env.SRE_BATCH_WINDOW_MS;
    delete process.env.SRE_COOLDOWN_MS;
    delete process.env.SRE_TRIAGE_SUPPRESS_S;
    delete process.env.WORKER_CONCURRENCY;
    delete process.env.HEALTH_CHECK_TIMEOUT_MS;
    delete process.env.HEALTH_POLL_INTERVAL_MS;
    delete process.env.HEALTH_MAX_PAUSE_MS;
    delete process.env.N8N_HEALTH_URL;
    delete process.env.LITELLM_HEALTH_URL;
  });

  it("parses valid env with defaults", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.VALKEY_HOST).toBe(VALID_ENV.VALKEY_HOST);
    expect(cfg.VALKEY_PORT).toBe(6379);
    expect(cfg.PORT).toBe(3000);
    expect(cfg.GITHUB_TOKEN).toBeUndefined();
  });

  it("coerces string ports to numbers", () => {
    Object.assign(process.env, VALID_ENV, {
      VALKEY_PORT: "6380",
      PORT: "8080",
    });
    const cfg = loadConfig();
    expect(cfg.VALKEY_PORT).toBe(6380);
    expect(cfg.PORT).toBe(8080);
  });

  it("throws when VALKEY_HOST missing", () => {
    Object.assign(process.env, VALID_ENV);
    delete process.env.VALKEY_HOST;
    expect(() => loadConfig()).toThrow();
  });

  it("throws when VALKEY_PASSWORD missing", () => {
    Object.assign(process.env, VALID_ENV);
    delete process.env.VALKEY_PASSWORD;
    expect(() => loadConfig()).toThrow();
  });

  it("throws when N8N_DISPATCH_WEBHOOK is not cluster-internal", () => {
    Object.assign(process.env, VALID_ENV, {
      N8N_DISPATCH_WEBHOOK: "https://external.example.com/webhook",
    });
    expect(() => loadConfig()).toThrow();
  });

  it("accepts webhook with .cluster.local suffix", () => {
    const url = "http://n8n.n8n-system.svc.cluster.local/webhook/dispatch";
    Object.assign(process.env, VALID_ENV, { N8N_DISPATCH_WEBHOOK: url });
    const cfg = loadConfig();
    expect(cfg.N8N_DISPATCH_WEBHOOK).toBe(url);
  });

  it("accepts webhook without .cluster.local suffix", () => {
    const url = "http://n8n.n8n-system.svc/webhook/dispatch";
    Object.assign(process.env, VALID_ENV, { N8N_DISPATCH_WEBHOOK: url });
    const cfg = loadConfig();
    expect(cfg.N8N_DISPATCH_WEBHOOK).toBe(url);
  });

  it("accepts optional GITHUB_TOKEN", () => {
    Object.assign(process.env, VALID_ENV, { GITHUB_TOKEN: "test" });
    const cfg = loadConfig();
    expect(cfg.GITHUB_TOKEN).toBe("test");
  });

  it("defaults SRE_BATCH_MAX_SIZE to 50", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.SRE_BATCH_MAX_SIZE).toBe(50);
  });

  it("coerces SRE_BATCH_MAX_SIZE string to number", () => {
    Object.assign(process.env, VALID_ENV, { SRE_BATCH_MAX_SIZE: "25" });
    const cfg = loadConfig();
    expect(cfg.SRE_BATCH_MAX_SIZE).toBe(25);
  });

  it("throws when SRE_BATCH_MAX_SIZE is 0", () => {
    Object.assign(process.env, VALID_ENV, { SRE_BATCH_MAX_SIZE: "0" });
    expect(() => loadConfig()).toThrow();
  });

  it("defaults SRE_BATCH_WINDOW_MS to 60000", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.SRE_BATCH_WINDOW_MS).toBe(60_000);
  });

  it("allows SRE_BATCH_WINDOW_MS of 0 to disable delay", () => {
    Object.assign(process.env, VALID_ENV, { SRE_BATCH_WINDOW_MS: "0" });
    const cfg = loadConfig();
    expect(cfg.SRE_BATCH_WINDOW_MS).toBe(0);
  });

  it("defaults SRE_COOLDOWN_MS to 300000", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.SRE_COOLDOWN_MS).toBe(300_000);
  });

  it("allows SRE_COOLDOWN_MS of 0 to disable cooldown", () => {
    Object.assign(process.env, VALID_ENV, { SRE_COOLDOWN_MS: "0" });
    const cfg = loadConfig();
    expect(cfg.SRE_COOLDOWN_MS).toBe(0);
  });

  it("defaults SRE_TRIAGE_SUPPRESS_S to 3600", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.SRE_TRIAGE_SUPPRESS_S).toBe(3600);
  });

  it("allows SRE_TRIAGE_SUPPRESS_S of 0 to disable suppression", () => {
    Object.assign(process.env, VALID_ENV, { SRE_TRIAGE_SUPPRESS_S: "0" });
    const cfg = loadConfig();
    expect(cfg.SRE_TRIAGE_SUPPRESS_S).toBe(0);
  });

  it("defaults HEALTH_CHECK_TIMEOUT_MS to 2000", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.HEALTH_CHECK_TIMEOUT_MS).toBe(2000);
  });

  it("coerces HEALTH_CHECK_TIMEOUT_MS string to number", () => {
    Object.assign(process.env, VALID_ENV, { HEALTH_CHECK_TIMEOUT_MS: "3000" });
    const cfg = loadConfig();
    expect(cfg.HEALTH_CHECK_TIMEOUT_MS).toBe(3000);
  });

  it("throws when HEALTH_CHECK_TIMEOUT_MS is below 500", () => {
    Object.assign(process.env, VALID_ENV, { HEALTH_CHECK_TIMEOUT_MS: "100" });
    expect(() => loadConfig()).toThrow();
  });

  it("defaults HEALTH_POLL_INTERVAL_MS to 30000", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.HEALTH_POLL_INTERVAL_MS).toBe(30_000);
  });

  it("throws when HEALTH_POLL_INTERVAL_MS is below 5000", () => {
    Object.assign(process.env, VALID_ENV, { HEALTH_POLL_INTERVAL_MS: "1000" });
    expect(() => loadConfig()).toThrow();
  });

  it("defaults HEALTH_MAX_PAUSE_MS to 600000", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.HEALTH_MAX_PAUSE_MS).toBe(600_000);
  });

  it("throws when HEALTH_MAX_PAUSE_MS is below 60000", () => {
    Object.assign(process.env, VALID_ENV, { HEALTH_MAX_PAUSE_MS: "5000" });
    expect(() => loadConfig()).toThrow();
  });

  it("defaults N8N_HEALTH_URL to cluster-internal endpoint", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.N8N_HEALTH_URL).toBe(
      "http://n8n.n8n-system.svc/healthz/readiness"
    );
  });

  it("defaults LITELLM_HEALTH_URL to cluster-internal endpoint", () => {
    Object.assign(process.env, VALID_ENV);
    const cfg = loadConfig();
    expect(cfg.LITELLM_HEALTH_URL).toBe(
      "http://litellm.litellm.svc:4000/health/readiness"
    );
  });

  it("accepts custom health URLs", () => {
    Object.assign(process.env, VALID_ENV, {
      N8N_HEALTH_URL: "http://n8n.custom.svc:5678/healthz",
      LITELLM_HEALTH_URL: "http://litellm.custom.svc:4000/health",
    });
    const cfg = loadConfig();
    expect(cfg.N8N_HEALTH_URL).toBe("http://n8n.custom.svc:5678/healthz");
    expect(cfg.LITELLM_HEALTH_URL).toBe(
      "http://litellm.custom.svc:4000/health"
    );
  });

  it("throws when N8N_HEALTH_URL is not a valid URL", () => {
    Object.assign(process.env, VALID_ENV, { N8N_HEALTH_URL: "not-a-url" });
    expect(() => loadConfig()).toThrow();
  });

  it("accepts HEALTH_MAX_PAUSE_MS equal to exactly 2x HEALTH_POLL_INTERVAL_MS", () => {
    Object.assign(process.env, VALID_ENV, {
      HEALTH_POLL_INTERVAL_MS: "30000",
      HEALTH_MAX_PAUSE_MS: "60000",
    });
    const cfg = loadConfig();
    expect(cfg.HEALTH_MAX_PAUSE_MS).toBe(60000);
  });

  it("throws when HEALTH_MAX_PAUSE_MS is less than 2x HEALTH_POLL_INTERVAL_MS", () => {
    Object.assign(process.env, VALID_ENV, {
      HEALTH_POLL_INTERVAL_MS: "30000",
      HEALTH_MAX_PAUSE_MS: "59999",
    });
    expect(() => loadConfig()).toThrow(
      "HEALTH_MAX_PAUSE_MS must be at least 2x HEALTH_POLL_INTERVAL_MS"
    );
  });
});
