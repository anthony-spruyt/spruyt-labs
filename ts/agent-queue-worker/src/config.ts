import { z } from "zod";

const svcRegex = /^[a-z0-9-]+\.[a-z0-9-]+\.svc(\.cluster\.local)?$/;

const ConfigSchema = z
  .object({
    VALKEY_HOST: z.string().min(1),
    VALKEY_PORT: z.coerce.number().int().default(6379),
    VALKEY_PASSWORD: z.string().min(1),
    VALKEY_USER: z.string().min(1),
    N8N_DISPATCH_WEBHOOK: z
      .string()
      .url()
      .refine((url) => {
        const hostname = new URL(url).hostname;
        return svcRegex.test(hostname);
      }, "N8N_DISPATCH_WEBHOOK must be a cluster-internal Service URL"),
    WORKER_TO_N8N_SECRET: z.string().min(1),
    N8N_TO_WORKER_SECRET: z.string().min(1),
    GITHUB_TOKEN: z.string().optional(),
    GITHUB_OWNER: z.string().min(1),
    PORT: z.coerce.number().int().default(3000),
    SRE_BATCH_MAX_SIZE: z.coerce.number().int().min(1).default(50),
    SRE_BATCH_WINDOW_MS: z.coerce.number().int().min(0).default(60_000),
    SRE_COOLDOWN_MS: z.coerce.number().int().min(0).default(300_000),
    SRE_TRIAGE_SUPPRESS_S: z.coerce.number().int().min(0).default(3600),
    WORKER_CONCURRENCY: z.coerce.number().int().min(1).default(10),
    HEALTH_CHECK_TIMEOUT_MS: z.coerce.number().int().min(500).default(2000),
    HEALTH_POLL_INTERVAL_MS: z.coerce.number().int().min(5000).default(30_000),
    HEALTH_MAX_PAUSE_MS: z.coerce.number().int().min(60_000).default(600_000),
    N8N_HEALTH_URL: z
      .string()
      .url()
      .default("http://n8n.n8n-system.svc/healthz/readiness"),
    LITELLM_HEALTH_URL: z
      .string()
      .url()
      .default("http://litellm.litellm.svc:4000/health/readiness"),
  })
  .refine(
    (c) => c.HEALTH_MAX_PAUSE_MS >= c.HEALTH_POLL_INTERVAL_MS * 2,
    "HEALTH_MAX_PAUSE_MS must be at least 2x HEALTH_POLL_INTERVAL_MS"
  );

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(): Config {
  return ConfigSchema.parse(process.env);
}
