import { describe, expect, it, beforeEach } from "vitest";
import { loadConfig } from "./config.js";

const VALID_ENV = {
  VALKEY_HOST: "valkey.default.svc.cluster.local",
  VALKEY_PASSWORD: "secret",
  N8N_DISPATCH_WEBHOOK:
    "http://n8n.n8n-system.svc.cluster.local/webhook/dispatch",
  WORKER_TO_N8N_SECRET: "w2n-secret",
  N8N_TO_WORKER_SECRET: "n2w-secret",
  GITHUB_OWNER: "anthony-spruyt",
};

describe("loadConfig", () => {
  beforeEach(() => {
    for (const key of Object.keys(VALID_ENV)) delete process.env[key];
    delete process.env.VALKEY_PORT;
    delete process.env.PORT;
    delete process.env.GITHUB_TOKEN;
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
    Object.assign(process.env, VALID_ENV, {
      N8N_DISPATCH_WEBHOOK:
        "http://n8n.n8n-system.svc.cluster.local/webhook/dispatch",
    });
    const cfg = loadConfig();
    expect(cfg.N8N_DISPATCH_WEBHOOK).toContain("cluster.local");
  });

  it("accepts webhook without .cluster.local suffix", () => {
    Object.assign(process.env, VALID_ENV, {
      N8N_DISPATCH_WEBHOOK: "http://n8n.n8n-system.svc/webhook/dispatch",
    });
    const cfg = loadConfig();
    expect(cfg.N8N_DISPATCH_WEBHOOK).toContain(".svc");
  });

  it("accepts optional GITHUB_TOKEN", () => {
    Object.assign(process.env, VALID_ENV, { GITHUB_TOKEN: "ghp_test" });
    const cfg = loadConfig();
    expect(cfg.GITHUB_TOKEN).toBe("ghp_test");
  });
});
