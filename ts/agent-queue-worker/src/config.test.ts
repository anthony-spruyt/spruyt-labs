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
});
