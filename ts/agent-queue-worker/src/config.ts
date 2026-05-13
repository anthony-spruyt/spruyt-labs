import { z } from "zod";

const svcRegex = /^[a-z0-9-]+\.[a-z0-9-]+\.svc(\.cluster\.local)?$/;

const ConfigSchema = z.object({
  VALKEY_HOST: z.string().min(1),
  VALKEY_PORT: z.coerce.number().int().default(6379),
  VALKEY_PASSWORD: z.string().min(1),
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
});

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(): Config {
  return ConfigSchema.parse(process.env);
}
