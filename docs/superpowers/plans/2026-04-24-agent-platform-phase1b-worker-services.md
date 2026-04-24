# Agent Orchestration Platform — Phase 1B: BullMQ Worker & Bull Board Services

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Build and deploy the BullMQ worker service and Bull Board dashboard. The worker coordinates agent job lifecycle via HTTP API + Valkey-backed BullMQ queue. Bull Board provides queue visibility.

**Architecture:** TypeScript services running as separate controllers in one bjw-s app-template HelmRelease. Worker exposes HTTP API on port 3000 for n8n integration. Bull Board on port 3001 behind Authentik. Both connect to dedicated agent Valkey (deployed in Phase 1A).

**Tech Stack:** TypeScript, BullMQ v5, ioredis, Zod, prom-client, Node.js 22, Docker, GitHub Actions

**Spec reference:** `docs/superpowers/specs/2026-04-22-agent-orchestration-platform-design.md`

**Prerequisite:** Phase 1A infrastructure must be deployed (namespace, Valkey, CNPs, secrets, Kyverno policies).

______________________________________________________________________

## Tasks

### Task 1: Project Scaffolding — Worker

**Files:**

- Create: `ts/agent-queue-worker/package.json`

- Create: `ts/agent-queue-worker/tsconfig.json`

- Create: `ts/agent-queue-worker/.dockerignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ts/agent-queue-worker/src
```

- [ ] **Step 2: Create package.json**

```json
{
  "name": "agent-queue-worker",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js",
    "dev": "tsx watch src/index.ts",
    "typecheck": "tsc --noEmit",
    "test": "vitest run",
    "test:watch": "vitest"
  },
  "dependencies": {
    "bullmq": "^5.52.0",
    "ioredis": "^5.6.1",
    "prom-client": "^15.1.3",
    "zod": "^3.24.4"
  },
  "devDependencies": {
    "@types/node": "^22.15.3",
    "tsx": "^4.19.4",
    "typescript": "^5.8.3",
    "vitest": "^3.1.3"
  }
}
```

Write to `ts/agent-queue-worker/package.json`.

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "lib": ["ES2022"],
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "resolveJsonModule": true,
    "declaration": true,
    "declarationMap": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

Write to `ts/agent-queue-worker/tsconfig.json`.

- [ ] **Step 4: Create .dockerignore**

```text
node_modules
dist
*.md
.git
```

Write to `ts/agent-queue-worker/.dockerignore`.

- [ ] **Step 5: Install dependencies**

```bash
cd ts/agent-queue-worker && npm install
```

- [ ] **Step 6: Verify TypeScript compiles (empty project)**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

Expected: exits 0

- [ ] **Step 7: Commit scaffolding**

```bash
git add ts/agent-queue-worker/package.json \
       ts/agent-queue-worker/package-lock.json \
       ts/agent-queue-worker/tsconfig.json \
       ts/agent-queue-worker/.dockerignore
git commit -m "feat(agent-worker): scaffold TypeScript project

BullMQ v5 worker with ioredis, Zod validation, prom-client metrics.
Node 22, ESM modules.

Ref #<issue>"
```

______________________________________________________________________

### Task 2: Types Module

**Files:**

- Create: `ts/agent-queue-worker/src/types.ts`

- [ ] **Step 1: Create types.ts**

```typescript
import { z } from 'zod';

export const VALID_ROLES = ['triage', 'fix', 'validate', 'execute'] as const;
export type Role = (typeof VALID_ROLES)[number];

export const ROLE_TIMEOUTS: Record<Role, number> = {
  triage: 600_000,
  fix: 1_800_000,
  validate: 1_800_000,
  execute: 3_600_000,
};

export const ROLE_PRIORITIES: Record<string, number> = {
  critical: 1,
  normal: 10,
  low: 100,
};

export const AgentJobSchema = z.object({
  role: z.enum(VALID_ROLES),
  priority: z.number().int().min(1).optional(),
  repo: z.string().min(1),
  event_type: z.string().min(1),
  pr_number: z.number().int().positive().optional(),
  issue_number: z.number().int().positive().optional(),
  head_sha: z.string().min(1),
  dispatched_at: z.string().optional(),
  dispatch_state: z.enum(['pending', 'dispatched', 'failed']).optional(),
  payload: z.record(z.unknown()),
});

export type AgentJob = z.infer<typeof AgentJobSchema>;

export const DoneRequestSchema = z.object({
  result: z.record(z.unknown()),
  session_token: z.string().uuid(),
  attempt: z.number().int().min(0),
  dispatched_at: z.string().optional(),
});

export type DoneRequest = z.infer<typeof DoneRequestSchema>;

export const FailRequestSchema = z.object({
  reason: z.string().min(1),
});

export type FailRequest = z.infer<typeof FailRequestSchema>;

export interface JobResult {
  status: string;
  [key: string]: unknown;
}

export function buildJobId(data: AgentJob): string {
  const { role, repo, pr_number, issue_number, head_sha } = data;
  if (role === 'validate') return `${repo}:main:validate:${head_sha}`;
  if (role === 'execute') return `${repo}:${issue_number}:execute`;
  if (data.payload?.revert) return `${repo}:${head_sha}:revert:fix`;
  return `${repo}:${pr_number}:${head_sha}:${role}`;
}

export function extractRole(jobId: string): string {
  const parts = jobId.split(':');
  return parts[parts.length - 1] ?? 'unknown';
}
// Note: returns 'fix' for revert-fix jobs ({repo}:{sha}:revert:fix).
// Dedup metrics attribute revert-fix to 'fix' role — acceptable.
```

Write to `ts/agent-queue-worker/src/types.ts`.

- [ ] **Step 2: Verify compiles**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

Expected: exits 0

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/types.ts
git commit -m "feat(agent-worker): add types, Zod schemas, and job ID builder

AgentJob schema with validation. Role timeouts. Deterministic job ID
generation for dedup. DoneRequest/FailRequest schemas for callback
endpoints.

Ref #<issue>"
```

______________________________________________________________________

### Task 3: Config Module

**Files:**

- Create: `ts/agent-queue-worker/src/config.ts`

- [ ] **Step 1: Create config.ts**

```typescript
import { z } from 'zod';

const svcRegex = /^[a-z0-9-]+\.[a-z0-9-]+\.svc(\.cluster\.local)?$/;

const ConfigSchema = z.object({
  VALKEY_HOST: z.string().min(1),
  VALKEY_PORT: z.coerce.number().int().default(6379),
  VALKEY_PASSWORD: z.string().min(1),
  N8N_DISPATCH_WEBHOOK: z.string().url().refine((url) => {
    const hostname = new URL(url).hostname;
    return svcRegex.test(hostname);
  }, 'N8N_DISPATCH_WEBHOOK must be a cluster-internal Service URL'),
  WORKER_TO_N8N_SECRET: z.string().min(1),
  N8N_TO_WORKER_SECRET: z.string().min(1),
  GITHUB_TOKEN: z.string().optional(),
  GITHUB_OWNER: z.string().min(1).default('anthony-spruyt'),
  PORT: z.coerce.number().int().default(3000),
});

export type Config = z.infer<typeof ConfigSchema>;

export function loadConfig(): Config {
  return ConfigSchema.parse(process.env);
}
```

Write to `ts/agent-queue-worker/src/config.ts`.

- [ ] **Step 2: Verify compiles**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/config.ts
git commit -m "feat(agent-worker): add config module with Zod validation

Validates env vars at startup. SSRF prevention: N8N_DISPATCH_WEBHOOK must
match cluster-internal Service URL regex with anchors.

Ref #<issue>"
```

______________________________________________________________________

### Task 4: Logger Module

**Files:**

- Create: `ts/agent-queue-worker/src/logger.ts`

- [ ] **Step 1: Create logger.ts**

```typescript
type Level = 'debug' | 'info' | 'warn' | 'error';

const LEVELS: Record<Level, number> = { debug: 0, info: 1, warn: 2, error: 3 };
const minLevel = LEVELS[(process.env.LOG_LEVEL as Level) ?? 'info'] ?? 1;

interface LogFields {
  jobId?: string;
  role?: string;
  repo?: string;
  pr?: number;
  sha?: string;
  [key: string]: unknown;
}

function log(level: Level, msg: string, fields?: LogFields): void {
  if (LEVELS[level] < minLevel) return;
  const entry = { ts: new Date().toISOString(), level, msg, ...fields };
  const out = level === 'error' ? process.stderr : process.stdout;
  out.write(JSON.stringify(entry) + '\n');
}

export const logger = {
  debug: (msg: string, fields?: LogFields) => log('debug', msg, fields),
  info: (msg: string, fields?: LogFields) => log('info', msg, fields),
  warn: (msg: string, fields?: LogFields) => log('warn', msg, fields),
  error: (msg: string, fields?: LogFields) => log('error', msg, fields),
};
```

Write to `ts/agent-queue-worker/src/logger.ts`.

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/src/logger.ts
git commit -m "feat(agent-worker): add structured JSON logger

Correlation fields: jobId, role, repo, pr, sha. Level filtering via
LOG_LEVEL env var.

Ref #<issue>"
```

______________________________________________________________________

### Task 5: Metrics Module

**Files:**

- Create: `ts/agent-queue-worker/src/metrics.ts`

- [ ] **Step 1: Create metrics.ts**

```typescript
import { Counter, Histogram, Gauge, Registry } from 'prom-client';

export const registry = new Registry();
registry.setDefaultLabels({ service: 'agent-queue-worker' });

export const queueDepth = new Gauge({
  name: 'agent_queue_depth',
  help: 'Jobs waiting in queue',
  labelNames: ['queue'] as const,
  registers: [registry],
});

export const jobDuration = new Histogram({
  name: 'agent_job_duration_seconds',
  help: 'Job processing time',
  labelNames: ['queue', 'role'] as const,
  buckets: [10, 30, 60, 120, 300, 600, 1200, 1800, 3600],
  registers: [registry],
});

export const jobFailures = new Counter({
  name: 'agent_job_failures_total',
  help: 'Job failures',
  labelNames: ['queue', 'role', 'reason'] as const,
  registers: [registry],
});

export const jobTimeouts = new Counter({
  name: 'agent_job_timeout_total',
  help: 'Job timeouts',
  labelNames: ['queue', 'role'] as const,
  registers: [registry],
});

export const staleDiscards = new Counter({
  name: 'agent_stale_total',
  help: 'Stale job discards',
  labelNames: ['queue', 'role'] as const,
  registers: [registry],
});

export const jobExhausted = new Counter({
  name: 'agent_job_exhausted_total',
  help: 'Jobs that exhausted all retry attempts',
  labelNames: ['queue', 'role', 'repo'] as const,
  registers: [registry],
});

export const workerRestarts = new Counter({
  name: 'agent_worker_restart_total',
  help: 'Graceful shutdown counter',
  registers: [registry],
});

export const dedupCounter = new Counter({
  name: 'agent_dedup_total',
  help: 'Deduplicated job submissions',
  labelNames: ['queue', 'role'] as const,
  registers: [registry],
});
```

Write to `ts/agent-queue-worker/src/metrics.ts`.

- [ ] **Step 2: Commit**

```bash
git add ts/agent-queue-worker/src/metrics.ts
git commit -m "feat(agent-worker): add Prometheus metrics

Queue depth, job duration histogram, failures, timeouts, stale discards,
exhausted jobs, dedup counter, restart counter.

Ref #<issue>"
```

______________________________________________________________________

### Task 6: GitHub Module

**Files:**

- Create: `ts/agent-queue-worker/src/github.ts`

- [ ] **Step 1: Create github.ts**

```typescript
import { logger } from './logger.js';

export async function getCurrentPrHead(
  repo: string,
  prNumber: number,
  token?: string,
): Promise<string> {
  const url = `https://api.github.com/repos/${repo}/pulls/${prNumber}`;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github.v3+json',
    'User-Agent': 'agent-queue-worker',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
  if (!resp.ok) throw new Error(`GitHub API ${resp.status}: ${url}`);

  const data = (await resp.json()) as { head: { sha: string } };
  return data.head.sha;
}

export async function fetchReposWithRevertLabels(
  owner: string,
  token?: string,
): Promise<Map<string, number>> {
  const revertDepths = new Map<string, number>();
  const repos = await fetchPublicRepos(owner, token);

  for (const repo of repos) {
    try {
      const count = await countRevertLabels(repo, token);
      if (count > 0) {
        revertDepths.set(repo, count);
        logger.info('Reconciled revert depth from GitHub', { repo, count });
      }
    } catch (err) {
      logger.warn('Failed to check revert labels', { repo, error: String(err) });
    }
  }

  return revertDepths;
}

async function fetchPublicRepos(owner: string, token?: string): Promise<string[]> {
  const repos: string[] = [];
  let page = 1;

  while (true) {
    const url = `https://api.github.com/users/${owner}/repos?type=public&per_page=100&page=${page}`;
    const headers: Record<string, string> = {
      Accept: 'application/vnd.github.v3+json',
      'User-Agent': 'agent-queue-worker',
    };
    if (token) headers.Authorization = `Bearer ${token}`;

    const resp = await fetch(url, { headers, signal: AbortSignal.timeout(15_000) });
    if (!resp.ok) throw new Error(`GitHub API ${resp.status}: ${url}`);

    const data = (await resp.json()) as { full_name: string }[];
    if (data.length === 0) break;

    repos.push(...data.map((r) => r.full_name));
    if (data.length < 100) break;
    page++;
  }

  return repos;
}

async function countRevertLabels(repo: string, token?: string): Promise<number> {
  const url = `https://api.github.com/repos/${repo}/issues?labels=agent/revert&state=all&per_page=5&sort=created&direction=desc`;
  const headers: Record<string, string> = {
    Accept: 'application/vnd.github.v3+json',
    'User-Agent': 'agent-queue-worker',
  };
  if (token) headers.Authorization = `Bearer ${token}`;

  const resp = await fetch(url, { headers, signal: AbortSignal.timeout(10_000) });
  if (!resp.ok) return 0;

  const data = (await resp.json()) as { created_at: string }[];
  const oneHourAgo = Date.now() - 3_600_000;
  return data.filter((i) => new Date(i.created_at).getTime() > oneHourAgo).length;
}
```

Write to `ts/agent-queue-worker/src/github.ts`.

- [ ] **Step 2: Verify compiles**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/github.ts
git commit -m "feat(agent-worker): add GitHub API client

Stale SHA check for PRs. Startup reconciliation: fetch public repos,
count recent agent/revert labels to seed revert-depth counters.
PAT optional — falls back to unauthenticated (60 req/hr).

Ref #<issue>"
```

______________________________________________________________________

### Task 7: Processor Module

The core job processor with callback management, dispatch, and recovery.

**Files:**

- Create: `ts/agent-queue-worker/src/processor.ts`

- [ ] **Step 1: Create processor.ts**

```typescript
import { Job } from 'bullmq';
import { randomUUID } from 'node:crypto';
import type Redis from 'ioredis';
import type { AgentJob, JobResult } from './types.js';
import { ROLE_TIMEOUTS } from './types.js';
import { getCurrentPrHead } from './github.js';
import { logger } from './logger.js';
import * as metrics from './metrics.js';
import type { Config } from './config.js';

// Lua script for atomic session token validation (check -> delete -> accept).
// Eliminates TOCTOU gap. Token consumed on first valid use — replay-proof.
// Uses Redis EVAL command (server-side Lua execution), not JavaScript eval().
const VALIDATE_SESSION_LUA = `
local stored = redis.call('GET', KEYS[1])
if stored == false then
  return 'expired_or_missing'
elseif stored ~= ARGV[1] then
  return 'mismatch'
else
  redis.call('DEL', KEYS[1])
  return 'valid'
end
`;

type CallbackResolver = (result: JobResult) => void;

export class Processor {
  private callbacks = new Map<string, CallbackResolver>();
  private redis: Redis;
  private config: Config;

  constructor(redis: Redis, config: Config) {
    this.redis = redis;
    this.config = config;
  }

  async process(job: Job<AgentJob>): Promise<JobResult> {
    const { role, repo, pr_number, head_sha } = job.data;
    const timeout = ROLE_TIMEOUTS[role] ?? 1_800_000;
    const timeoutSec = Math.ceil(timeout / 1000);
    const fields = { jobId: job.id!, role, repo, pr: pr_number, sha: head_sha };

    const locked = await this.redis.set(`agent:active:${job.id}`, '1', 'NX', 'EX', timeoutSec);
    if (!locked) {
      logger.warn('Duplicate processing detected', fields);
      return { status: 'duplicate' };
    }

    const timer = metrics.jobDuration.startTimer({ queue: 'agent', role });

    try {
      const cached = await this.redis.get(`agent:result:${job.id}:${job.attemptsMade}`);
      if (cached) {
        logger.info('Returning cached result', fields);
        await this.redis.del(`agent:result:${job.id}:${job.attemptsMade}`);
        return JSON.parse(cached) as JobResult;
      }

      if (pr_number) {
        try {
          const currentHead = await getCurrentPrHead(repo, pr_number, this.config.GITHUB_TOKEN);
          if (currentHead !== head_sha) {
            logger.info('Job stale — SHA changed', fields);
            metrics.staleDiscards.inc({ queue: 'agent', role });
            return { status: 'stale' };
          }
        } catch {
          logger.warn('Stale check failed — proceeding optimistically', fields);
        }
      }

      const dispatchState = job.data.dispatch_state ?? 'pending';
      logger.info('Processing job', { ...fields, dispatchState, attempt: job.attemptsMade });

      const result = await Promise.race([
        dispatchState === 'dispatched'
          ? this.awaitCallbackWithCachePoll(job.id!, job.attemptsMade)
          : this.dispatchAndAwaitCallback(job.id!, job.data, job),
        this.rejectAfter(timeout, `Job ${job.id} timed out after ${timeout}ms`),
      ]);

      logger.info('Job completed', { ...fields, status: result.status });
      return result;
    } catch (err) {
      const reason = err instanceof Error && err.message.includes('timed out') ? 'timeout' : 'error';
      if (reason === 'timeout') {
        metrics.jobTimeouts.inc({ queue: 'agent', role });
      } else {
        metrics.jobFailures.inc({ queue: 'agent', role, reason: 'processor_error' });
      }
      logger.error('Job failed', { ...fields, error: String(err) });
      throw err;
    } finally {
      timer();
      const resolver = this.callbacks.get(job.id!);
      if (resolver) resolver({ status: 'cancelled' });
      this.callbacks.delete(job.id!);
      await this.redis.del(`agent:active:${job.id}`);
    }
  }

  async resolveCallback(jobId: string, result: JobResult): Promise<boolean> {
    const resolver = this.callbacks.get(jobId);
    if (resolver) {
      resolver(result);
      this.callbacks.delete(jobId);
      return true;
    }
    return false;
  }

  async cacheResult(jobId: string, attempt: number, result: JobResult): Promise<void> {
    await this.redis.set(
      `agent:result:${jobId}:${attempt}`,
      JSON.stringify(result),
      'EX',
      3600,
    );
  }

  async validateSession(jobId: string, attempt: number, token: string): Promise<string> {
    const key = `agent:session:${jobId}:${attempt}`;
    // Redis EVAL runs Lua server-side for atomic check-delete-accept
    return (await this.redis.eval(VALIDATE_SESSION_LUA, 1, key, token)) as string;
  }

  private async dispatchAndAwaitCallback(
    jobId: string,
    data: AgentJob,
    job: Job<AgentJob>,
  ): Promise<JobResult> {
    const dispatched_at = new Date().toISOString();
    const session_token = randomUUID();
    const timeoutSec = Math.ceil((ROLE_TIMEOUTS[data.role] ?? 1_800_000) / 1000);

    await this.redis.set(`agent:session:${jobId}:${job.attemptsMade}`, session_token, 'EX', timeoutSec);

    const resp = await fetch(this.config.N8N_DISPATCH_WEBHOOK, {
      method: 'POST',
      headers: {
        'Content-Type': 'application/json',
        Authorization: `Bearer ${this.config.WORKER_TO_N8N_SECRET}`,
        'Idempotency-Key': `${jobId}:${job.attemptsMade}`,
      },
      body: JSON.stringify({ ...data, jobId, session_token, attempt: job.attemptsMade, dispatched_at }),
    });

    if (!resp.ok) {
      await job.updateData({ ...data, dispatch_state: 'failed', dispatched_at });
      throw new Error(`Dispatch failed: ${resp.status} ${resp.statusText}`);
    }

    await job.updateData({ ...data, dispatch_state: 'dispatched', dispatched_at });
    logger.info('Dispatched to n8n', { jobId, role: data.role, repo: data.repo });

    return this.awaitCallback(jobId);
  }

  private awaitCallback(jobId: string): Promise<JobResult> {
    return new Promise((resolve) => {
      this.callbacks.set(jobId, resolve);
    });
  }

  private awaitCallbackWithCachePoll(jobId: string, attemptsMade: number): Promise<JobResult> {
    return new Promise((resolve) => {
      let resolved = false;
      let poll: NodeJS.Timeout | undefined;

      const settle = (result: JobResult) => {
        if (resolved) return;
        resolved = true;
        if (poll) clearInterval(poll);
        this.callbacks.delete(jobId);
        resolve(result);
      };

      this.callbacks.set(jobId, settle);

      poll = setInterval(async () => {
        try {
          const cached = await this.redis.get(`agent:result:${jobId}:${attemptsMade}`);
          if (cached) settle(JSON.parse(cached) as JobResult);
        } catch {
          // Valkey blip during poll — retry on next interval
        }
      }, 15_000);
    });
  }

  private rejectAfter(ms: number, message: string): Promise<never> {
    return new Promise((_, reject) => {
      setTimeout(() => reject(new Error(message)), ms);
    });
  }
}
```

Write to `ts/agent-queue-worker/src/processor.ts`.

- [ ] **Step 2: Verify compiles**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/processor.ts
git commit -m "feat(agent-worker): add job processor with callback pattern

Dispatch to n8n, await callback via Promise. Stale SHA check before
dispatch. Three-state dispatch tracking (pending/dispatched/failed).
Session token generation per dispatch attempt. Cached result recovery
after stall. Atomic session validation via Redis Lua script.

Ref #<issue>"
```

______________________________________________________________________

### Task 8: Routes Module

HTTP API endpoints.

**Files:**

- Create: `ts/agent-queue-worker/src/routes.ts`

- [ ] **Step 1: Create routes.ts**

```typescript
import { type IncomingMessage, type ServerResponse } from 'node:http';
import { Queue } from 'bullmq';
import type Redis from 'ioredis';
import {
  AgentJobSchema,
  DoneRequestSchema,
  FailRequestSchema,
  buildJobId,
} from './types.js';
import type { Processor } from './processor.js';
import { logger } from './logger.js';
import * as metrics from './metrics.js';
import type { Config } from './config.js';

export class Router {
  private queue: Queue;
  private redis: Redis;
  private processor: Processor;
  private config: Config;
  private isReady: () => boolean;

  constructor(
    queue: Queue,
    redis: Redis,
    processor: Processor,
    config: Config,
    isReady: () => boolean,
  ) {
    this.queue = queue;
    this.redis = redis;
    this.processor = processor;
    this.config = config;
    this.isReady = isReady;
  }

  async handle(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const url = new URL(req.url ?? '/', `http://${req.headers.host}`);
    const path = url.pathname;
    const method = req.method ?? 'GET';

    if (method === 'GET' && path === '/livez') return this.json(res, 200, { status: 'ok' });
    if (method === 'GET' && path === '/readyz') {
      return this.json(res, this.isReady() ? 200 : 503, { ready: this.isReady() });
    }
    if (method === 'GET' && path === '/metrics') {
      res.writeHead(200, { 'Content-Type': metrics.registry.contentType });
      res.end(await metrics.registry.metrics());
      return;
    }

    if (!this.authenticate(req)) return this.json(res, 401, { error: 'Unauthorized' });

    if (method === 'POST' && path === '/jobs') return this.addJob(req, res);

    const jobMatch = path.match(/^\/jobs\/([^/]+)\/(done|fail|retry)$/);
    if (method === 'POST' && jobMatch) {
      const [, jobId, action] = jobMatch;
      if (action === 'done') return this.completeJob(req, res, decodeURIComponent(jobId!));
      if (action === 'fail') return this.failJob(req, res, decodeURIComponent(jobId!));
      if (action === 'retry') return this.retryJob(res, decodeURIComponent(jobId!));
    }

    const circuitMatch = path.match(/^\/circuit\/([^/]+)\/reset$/);
    if (method === 'POST' && circuitMatch) {
      return this.resetCircuit(res, decodeURIComponent(circuitMatch[1]!));
    }

    this.json(res, 404, { error: 'Not found' });
  }

  private async addJob(req: IncomingMessage, res: ServerResponse): Promise<void> {
    const body = await this.readBody(req);
    const parsed = AgentJobSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, { added: false, reason: 'invalid_request', errors: parsed.error.issues });
    }

    const data = parsed.data;

    const recentFailures = await this.redis.zcount(
      `agent:circuit:${data.repo}`,
      Date.now() - 3_600_000,
      '+inf',
    );
    if (recentFailures >= 5) {
      logger.warn('Circuit open', { repo: data.repo, failures: recentFailures });
      return this.json(res, 429, { added: false, reason: 'circuit_open' });
    }

    const rateKey = `agent:rate:${data.repo}`;
    await this.redis.zremrangebyscore(rateKey, '-inf', Date.now() - 3_600_000);
    const rateCount = await this.redis.zcard(rateKey);
    if (rateCount >= 10) {
      logger.warn('Rate limited', { repo: data.repo, count: rateCount });
      return this.json(res, 429, { added: false, reason: 'rate_limited' });
    }

    const jobId = buildJobId(data);

    const completed = await this.redis.exists(`agent:completed:${jobId}`);
    if (completed) {
      return this.json(res, 409, { added: false, reason: 'recently_completed' });
    }

    const active = await this.redis.exists(`agent:active:${jobId}`);
    if (active) {
      return this.json(res, 409, { added: false, reason: 'active' });
    }

    const entity = String(data.pr_number ?? data.issue_number ?? '');
    if (entity && data.role !== 'execute') await this.supersedeOlderJobs(data.repo, entity, data.head_sha, data.role);

    try {
      const job = await this.queue.add(data.role, data, {
        jobId,
        deduplication: { id: jobId },
        attempts: 2,
        backoff: { type: 'exponential', delay: 30_000 },
        removeOnComplete: { age: 3600 },
        removeOnFail: { age: 604_800, count: 500 },
        priority: data.priority,
      });

      if (!job) {
        metrics.dedupCounter.inc({ queue: 'agent', role: data.role });
        return this.json(res, 409, { added: false, reason: 'waiting' });
      }

      await this.redis.zadd(rateKey, Date.now(), jobId);
      await this.redis.expire(rateKey, 3600);

      logger.info('Job added', { jobId, role: data.role, repo: data.repo });
      this.json(res, 201, { added: true, jobId });
    } catch (err) {
      logger.error('Failed to add job', { jobId, error: String(err) });
      this.json(res, 503, { added: false, reason: 'error', message: String(err) });
    }
  }

  private async completeJob(req: IncomingMessage, res: ServerResponse, jobId: string): Promise<void> {
    const body = await this.readBody(req);
    const parsed = DoneRequestSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, { accepted: false, reason: 'invalid_request' });
    }

    const { result, session_token, attempt } = parsed.data;

    const validation = await this.processor.validateSession(jobId, attempt, session_token);
    if (validation === 'expired_or_missing') {
      const job = await this.queue.getJob(jobId);
      if (job && (await job.isCompleted())) {
        return this.json(res, 200, { accepted: true, already_completed: true });
      }
      return this.json(res, 403, { accepted: false, reason: 'invalid_session' });
    }
    if (validation === 'mismatch') {
      return this.json(res, 403, { accepted: false, reason: 'invalid_session' });
    }

    // Execute callback correlation: reject stale dispatch callbacks
    if (parsed.data.dispatched_at) {
      const job = await this.queue.getJob(jobId);
      if (job && job.data.dispatched_at && job.data.dispatched_at !== parsed.data.dispatched_at) {
        await this.processor.cacheResult(jobId, attempt, { status: 'completed', ...result });
        logger.info('Cached stale dispatch result', { jobId, attempt });
        return this.json(res, 200, { accepted: true, stale_dispatch: true });
      }
    }

    const resolved = await this.processor.resolveCallback(jobId, { status: 'completed', ...result });
    if (!resolved) {
      await this.processor.cacheResult(jobId, attempt, { status: 'completed', ...result });
      logger.info('Cached result for re-processing', { jobId, attempt });
    }

    logger.info('Job done callback received', { jobId });
    this.json(res, 200, { accepted: true });
  }

  private async failJob(req: IncomingMessage, res: ServerResponse, jobId: string): Promise<void> {
    const body = await this.readBody(req);
    const parsed = FailRequestSchema.safeParse(body);
    if (!parsed.success) {
      return this.json(res, 400, { accepted: false, reason: 'invalid_request' });
    }

    const resolved = await this.processor.resolveCallback(jobId, {
      status: 'failed',
      reason: parsed.data.reason,
    });
    if (!resolved) {
      logger.warn('No active callback for fail', { jobId });
    }

    logger.info('Job fail callback received', { jobId, reason: parsed.data.reason });
    this.json(res, 200, { accepted: true });
  }

  private async retryJob(res: ServerResponse, jobId: string): Promise<void> {
    const job = await this.queue.getJob(jobId);
    if (!job) return this.json(res, 404, { retried: false, reason: 'not_found' });
    if (!(await job.isFailed())) return this.json(res, 200, { retried: false, reason: 'not_failed' });

    await job.retry();
    logger.info('Job retried manually', { jobId });
    this.json(res, 200, { retried: true });
  }

  private async resetCircuit(res: ServerResponse, repo: string): Promise<void> {
    const deleted = await this.redis.del(`agent:circuit:${repo}`);
    logger.info('Circuit reset', { repo, wasOpen: deleted > 0 });
    this.json(res, 200, { reset: deleted > 0 });
  }

  private async supersedeOlderJobs(
    repo: string,
    entity: string,
    currentSha: string,
    role: string,
  ): Promise<void> {
    const candidates = [
      ...(await this.queue.getJobs(['prioritized'])),
      ...(await this.queue.getJobs(['waiting'])),
    ];
    for (const job of candidates) {
      if (
        job.data.repo === repo &&
        String(job.data.pr_number ?? job.data.issue_number) === entity &&
        job.data.role === role &&
        job.data.head_sha !== currentSha
      ) {
        await job.remove();
        logger.info('Superseded older job', { oldJobId: job.id, newSha: currentSha });
      }
    }
  }

  private authenticate(req: IncomingMessage): boolean {
    const auth = req.headers.authorization;
    return auth === `Bearer ${this.config.N8N_TO_WORKER_SECRET}`;
  }

  private json(res: ServerResponse, status: number, data: unknown): void {
    res.writeHead(status, { 'Content-Type': 'application/json' });
    res.end(JSON.stringify(data));
  }

  private readBody(req: IncomingMessage): Promise<unknown> {
    return new Promise((resolve, reject) => {
      const chunks: Buffer[] = [];
      let size = 0;
      req.on('data', (chunk: Buffer) => {
        size += chunk.length;
        if (size > 1_048_576) { req.destroy(new Error('Body too large')); return; }
        chunks.push(chunk);
      });
      req.on('end', () => {
        try {
          resolve(JSON.parse(Buffer.concat(chunks).toString()));
        } catch {
          resolve(undefined);
        }
      });
      req.on('error', reject);
    });
  }
}
```

Write to `ts/agent-queue-worker/src/routes.ts`.

- [ ] **Step 2: Verify compiles**

```bash
cd ts/agent-queue-worker && npx tsc --noEmit
```

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/routes.ts
git commit -m "feat(agent-worker): add HTTP API routes

Endpoints: POST /jobs (add + supersede + 3-layer dedup), POST /jobs/:id/done
(session validation + callback resolution), POST /jobs/:id/fail, POST
/jobs/:id/retry, POST /circuit/:repo/reset, GET /livez, /readyz, /metrics.
Bearer auth on mutating endpoints. Zod request validation. Per-repo rate
limit (10/hr) and circuit breaker (5 failures/hr).

Ref #<issue>"
```

______________________________________________________________________

### Task 9: Index Module — Entry Point

**Files:**

- Create: `ts/agent-queue-worker/src/index.ts`

- [ ] **Step 1: Create index.ts**

```typescript
import { createServer, type Server } from 'node:http';
import { Worker, Queue, QueueEvents } from 'bullmq';
import Redis from 'ioredis';
import { loadConfig } from './config.js';
import { Processor } from './processor.js';
import { Router } from './routes.js';
import { logger } from './logger.js';
import * as metrics from './metrics.js';
import { extractRole } from './types.js';
import { fetchReposWithRevertLabels } from './github.js';

const config = loadConfig();

const redis = new Redis({
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
  maxRetriesPerRequest: null,
  retryStrategy: (times) => Math.min(times * 500, 5000),
});

const connection = {
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
};

const queueOpts = { connection, prefix: 'agent:queue' };

const queue = new Queue('agent', queueOpts);
const processor = new Processor(redis, config);

const worker = new Worker(
  'agent',
  async (job) => processor.process(job),
  {
    ...queueOpts,
    concurrency: 1,
    stalledInterval: 60_000,
    lockDuration: 120_000,
    maxStalledCount: 1,
  },
);

const queueEvents = new QueueEvents('agent', queueOpts);

queueEvents.on('deduplicated', ({ deduplicatedJobId }) => {
  metrics.dedupCounter.inc({ queue: 'agent', role: extractRole(deduplicatedJobId) });
});

worker.on('completed', async (job) => {
  if (job) await redis.set(`agent:completed:${job.id}`, '1', 'EX', 3600);
});

worker.on('failed', async (job, err) => {
  if (!job) return;
  const role = job.data.role ?? 'unknown';

  await redis.zadd(`agent:circuit:${job.data.repo}`, Date.now(), `${job.id}:${job.attemptsMade}`);
  await redis.expire(`agent:circuit:${job.data.repo}`, 3600);

  if (job.attemptsMade >= (job.opts.attempts ?? 1)) {
    metrics.jobExhausted.inc({ queue: 'agent', role, repo: job.data.repo });
    logger.error('Job exhausted all attempts', {
      jobId: job.id,
      role,
      repo: job.data.repo,
      error: err.message,
    });
  } else {
    metrics.jobFailures.inc({ queue: 'agent', role, reason: 'job_failed' });
    logger.warn('Job failed, will retry', {
      jobId: job.id,
      role,
      repo: job.data.repo,
      attempt: job.attemptsMade,
      error: err.message,
    });
  }
});

const isReady = () => redis.status === 'ready' && !worker.closing;

const router = new Router(queue, redis, processor, config, isReady);

const server: Server = createServer(async (req, res) => {
  try {
    await router.handle(req, res);
  } catch (err) {
    logger.error('Unhandled route error', { error: String(err) });
    if (!res.headersSent) {
      res.writeHead(500, { 'Content-Type': 'application/json' });
      res.end(JSON.stringify({ error: 'Internal server error' }));
    }
  }
});

async function updateQueueDepth(): Promise<void> {
  try {
    const waiting = await queue.getWaitingCount();
    const prioritized = await queue.getJobCountByTypes('prioritized');
    metrics.queueDepth.set({ queue: 'agent' }, waiting + prioritized);
  } catch {
    // Valkey blip — skip this tick
  }
}

const depthInterval = setInterval(updateQueueDepth, 15_000);

async function startupReconciliation(): Promise<void> {
  try {
    logger.info('Running startup reconciliation');
    const depths = await fetchReposWithRevertLabels(config.GITHUB_OWNER, config.GITHUB_TOKEN);
    for (const [repo, count] of depths) {
      await redis.set(`agent:revert-depth:${repo}`, String(count), 'EX', 3600);
    }
    logger.info('Startup reconciliation complete', { reposWithReverts: depths.size });
  } catch (err) {
    logger.warn('Startup reconciliation failed — proceeding without', { error: String(err) });
  }
}

async function shutdown(): Promise<void> {
  logger.info('Shutting down');
  metrics.workerRestarts.inc();
  // TODO: POST Discord notification ("Worker restarting, active job will resume after re-queue ~2min")
  // Best-effort — don't block shutdown if Discord/n8n is unreachable

  clearInterval(depthInterval);
  server.close();

  await worker.close();
  await queueEvents.close();
  await queue.close();
  await redis.quit();

  logger.info('Shutdown complete');
  process.exit(0);
}

process.on('SIGTERM', shutdown);
process.on('SIGINT', shutdown);

server.listen(config.PORT, async () => {
  logger.info('Worker started', { port: config.PORT });
  await startupReconciliation();
});
```

Write to `ts/agent-queue-worker/src/index.ts`.

- [ ] **Step 2: Verify full build**

```bash
cd ts/agent-queue-worker && npm run build
```

Expected: `dist/` directory created with compiled JS, exits 0

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/src/index.ts
git commit -m "feat(agent-worker): add entry point with startup and shutdown

HTTP server, BullMQ worker/queue/events setup. Startup reconciliation
seeds revert-depth from GitHub labels. Graceful shutdown: stop accepting
requests, close worker, quit Redis. Queue depth metric polling. Circuit
breaker failure tracking on job failures.

Ref #<issue>"
```

______________________________________________________________________

### Task 10: Worker Dockerfile

**Files:**

- Create: `ts/agent-queue-worker/Dockerfile`

- [ ] **Step 1: Create Dockerfile**

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src/ src/
RUN npx tsc

FROM node:22-alpine
RUN apk add --no-cache tini
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=builder /app/dist/ dist/
USER 1000:1000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
```

Write to `ts/agent-queue-worker/Dockerfile`.

WORKDIR is `/app` (not `/home/node`) — HelmRelease mounts emptyDir at `/home/node/.npm` which would shadow application code.

- [ ] **Step 2: Verify Docker builds**

```bash
cd ts/agent-queue-worker && docker build -t agent-queue-worker:test .
```

Expected: builds successfully

- [ ] **Step 3: Commit**

```bash
git add ts/agent-queue-worker/Dockerfile
git commit -m "feat(agent-worker): add multi-stage Dockerfile

Node 22 alpine, tini for signal handling. Multi-stage build. WORKDIR /app
to avoid emptyDir shadowing. Runs as UID 1000.

Ref #<issue>"
```

______________________________________________________________________

### Task 11: Bull Board Source

**Files:**

- Create: `ts/agent-queue-worker/bull-board/package.json`

- Create: `ts/agent-queue-worker/bull-board/tsconfig.json`

- Create: `ts/agent-queue-worker/bull-board/src/index.ts`

- Create: `ts/agent-queue-worker/bull-board/Dockerfile`

- Create: `ts/agent-queue-worker/bull-board/.dockerignore`

- [ ] **Step 1: Create directory structure**

```bash
mkdir -p ts/agent-queue-worker/bull-board/src
```

- [ ] **Step 2: Create package.json**

```json
{
  "name": "bull-board",
  "version": "1.0.0",
  "private": true,
  "type": "module",
  "engines": {
    "node": ">=22"
  },
  "scripts": {
    "build": "tsc",
    "start": "node dist/index.js"
  },
  "dependencies": {
    "@bull-board/api": "^6.6.2",
    "@bull-board/express": "^6.6.2",
    "bullmq": "^5.52.0",
    "express": "^4.21.0"
  },
  "devDependencies": {
    "@types/express": "^4.17.21",
    "@types/node": "^22.15.3",
    "typescript": "^5.8.3"
  }
}
```

Write to `ts/agent-queue-worker/bull-board/package.json`.

- [ ] **Step 3: Create tsconfig.json**

```json
{
  "compilerOptions": {
    "target": "ES2022",
    "module": "Node16",
    "moduleResolution": "Node16",
    "lib": ["ES2022"],
    "outDir": "dist",
    "rootDir": "src",
    "strict": true,
    "esModuleInterop": true,
    "skipLibCheck": true,
    "forceConsistentCasingInFileNames": true,
    "sourceMap": true
  },
  "include": ["src"],
  "exclude": ["node_modules", "dist"]
}
```

Write to `ts/agent-queue-worker/bull-board/tsconfig.json`.

- [ ] **Step 4: Create src/index.ts**

```typescript
import express from 'express';
import { createBullBoard } from '@bull-board/api';
import { BullMQAdapter } from '@bull-board/api/bullMQAdapter.js';
import { ExpressAdapter } from '@bull-board/express';
import { Queue } from 'bullmq';

const port = parseInt(process.env.BULL_BOARD_PORT ?? '3001', 10);
const readOnly = process.env.READ_ONLY === 'true';

const connection = {
  host: process.env.VALKEY_HOST!,
  port: parseInt(process.env.VALKEY_PORT ?? '6379', 10),
  password: process.env.VALKEY_PASSWORD!,
};

const prefix = process.env.QUEUE_PREFIX ?? 'agent:queue';
const queue = new Queue('agent', { connection, prefix });

const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath('/');

createBullBoard({
  queues: [new BullMQAdapter(queue, { readOnlyMode: readOnly })],
  serverAdapter,
});

const app = express();
app.use('/', serverAdapter.getRouter());

app.listen(port, () => {
  console.log(`Bull Board running on port ${port} (read-only: ${readOnly})`);
});
```

Write to `ts/agent-queue-worker/bull-board/src/index.ts`.

- [ ] **Step 5: Create .dockerignore**

```text
node_modules
dist
*.md
.git
```

Write to `ts/agent-queue-worker/bull-board/.dockerignore`.

- [ ] **Step 6: Create Dockerfile**

```dockerfile
FROM node:22-alpine AS builder
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --ignore-scripts
COPY tsconfig.json ./
COPY src/ src/
RUN npx tsc

FROM node:22-alpine
RUN apk add --no-cache tini
WORKDIR /app
COPY package.json package-lock.json ./
RUN npm ci --omit=dev --ignore-scripts && npm cache clean --force
COPY --from=builder /app/dist/ dist/
USER 1000:1000
ENTRYPOINT ["/sbin/tini", "--"]
CMD ["node", "dist/index.js"]
```

Write to `ts/agent-queue-worker/bull-board/Dockerfile`.

- [ ] **Step 7: Install deps and verify build**

```bash
cd ts/agent-queue-worker/bull-board && npm install && npm run build
```

- [ ] **Step 8: Commit**

```bash
git add ts/agent-queue-worker/bull-board/
git commit -m "feat(agent-worker): add Bull Board dashboard

Express-based queue UI. Read-only mode default. Separate container image
from worker — crash doesn't affect worker pod.

Ref #<issue>"
```

______________________________________________________________________

### Task 12: GitHub Actions CI Workflows

**Files:**

- Create: `.github/workflows/release-agent-queue-worker.yaml`

- Create: `.github/workflows/release-bull-board.yaml`

- [ ] **Step 1: Create release-agent-queue-worker.yaml**

Adapt from existing `release-shutdown-orchestrator.yaml` pattern. Key changes from Go to Node.js:

- Replace `actions/setup-go` with `actions/setup-node`
- Replace `go test` with `npx tsc --noEmit && npm test`
- Remove `GO_VERSION` and `VERSION`/`COMMIT` build-args from Docker build
- Change `WORKDIR` to `ts/agent-queue-worker`
- Change `IMAGE` to `ghcr.io/anthony-spruyt/agent-queue-worker`
- Change `TAG_PREFIX` to `agent-queue-worker/v`

Use the full workflow from `release-shutdown-orchestrator.yaml` as the template. Replace:

- All `shutdown-orchestrator` references → `agent-queue-worker`
- `cmd/shutdown-orchestrator` → `ts/agent-queue-worker`
- Go setup + test step → Node.js setup + typecheck + test
- Remove `build-args` (Go-specific version/commit injection)
- Remove `go-version` extraction step

Write to `.github/workflows/release-agent-queue-worker.yaml`.

- [ ] **Step 2: Create release-bull-board.yaml**

Same pattern but simpler (no test step — Bull Board is a thin wrapper):

- `IMAGE: ghcr.io/anthony-spruyt/bull-board`
- `WORKDIR: ts/agent-queue-worker/bull-board`
- `TAG_PREFIX: bull-board/v`
- No test job

Write to `.github/workflows/release-bull-board.yaml`.

Note: The complete workflow YAML should be adapted from `.github/workflows/release-shutdown-orchestrator.yaml`. Key changes from Go to Node.js: replace `actions/setup-go` with `actions/setup-node@v4` (node-version: 22), replace `go test` with `npx tsc --noEmit && npm test`, remove Go-specific build-args from Docker build step, change WORKDIR path.

- [ ] **Step 3: Commit**

```bash
git add .github/workflows/release-agent-queue-worker.yaml \
       .github/workflows/release-bull-board.yaml
git commit -m "ci: add release workflows for worker and Bull Board

workflow_dispatch with semver bump, same pattern as existing services.
Pushes to ghcr.io. Renovate bumps image tags in HelmRelease.

Ref #<issue>"
```

______________________________________________________________________

### Task 13: Worker HelmRelease + Values

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/release.yaml`

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`

- [ ] **Step 1: Create release.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/helm.toolkit.fluxcd.io/helmrelease_v2.json
apiVersion: helm.toolkit.fluxcd.io/v2
kind: HelmRelease
metadata:
  name: agent-queue-worker
spec:
  chartRef:
    kind: OCIRepository
    name: app-template
    namespace: flux-system
  interval: 4h
  valuesFrom:
    - kind: ConfigMap
      name: agent-queue-worker-values
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/release.yaml`.

- [ ] **Step 2: Create values.yaml**

```yaml
---
defaultPodOptions:
  automountServiceAccountToken: false
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
    runAsGroup: 1000
    fsGroup: 1000
    seccompProfile:
      type: RuntimeDefault
controllers:
  worker:
    replicas: 1
    strategy: RollingUpdate
    rollingUpdate:
      unavailable: 0
    pod:
      terminationGracePeriodSeconds: 30
    containers:
      app:
        image:
          repository: ghcr.io/anthony-spruyt/agent-queue-worker
          tag: v1.0.0
        env:
          VALKEY_HOST: agent-valkey.agent-worker-system.svc
          VALKEY_PORT: "6379"
          N8N_DISPATCH_WEBHOOK: http://n8n-webhook.n8n-system.svc/webhook/agent-dispatch
          GITHUB_OWNER: anthony-spruyt
        envFrom:
          - secretRef:
              name: agent-queue-worker-secrets
        resources:
          requests:
            cpu: 10m
            memory: 64Mi
          limits:
            memory: 128Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /livez
                port: &port 3000
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /readyz
                port: *port
  bull-board:
    replicas: 1
    strategy: RollingUpdate
    containers:
      app:
        image:
          repository: ghcr.io/anthony-spruyt/bull-board
          tag: v1.0.0
        env:
          VALKEY_HOST: agent-valkey.agent-worker-system.svc
          VALKEY_PORT: "6379"
          BULL_BOARD_PORT: "3001"
          QUEUE_PREFIX: agent:queue
          READ_ONLY: "true"
          VALKEY_PASSWORD:
            valueFrom:
              secretKeyRef:
                name: agent-queue-worker-secrets
                key: VALKEY_PASSWORD
        resources:
          requests:
            cpu: 5m
            memory: 32Mi
          limits:
            memory: 128Mi
        securityContext:
          allowPrivilegeEscalation: false
          readOnlyRootFilesystem: true
          capabilities:
            drop:
              - ALL
        probes:
          liveness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: &bbport 3001
          readiness:
            enabled: true
            custom: true
            spec:
              httpGet:
                path: /
                port: *bbport
service:
  worker:
    controller: worker
    ports:
      http:
        port: *port
  bull-board:
    controller: bull-board
    ports:
      http:
        port: *bbport
persistence:
  tmp:
    type: emptyDir
    advancedMounts:
      worker:
        app:
          - path: /tmp
      bull-board:
        app:
          - path: /tmp
  npm-cache:
    type: emptyDir
    advancedMounts:
      worker:
        app:
          - path: /home/node/.npm
      bull-board:
        app:
          - path: /home/node/.npm
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml`.

- [ ] **Step 3: Verify kustomization builds**

```bash
kubectl kustomize cluster/apps/agent-worker-system/agent-queue-worker/app/ > /dev/null
```

- [ ] **Step 4: Commit**

```bash
git add cluster/apps/agent-worker-system/agent-queue-worker/app/release.yaml \
       cluster/apps/agent-worker-system/agent-queue-worker/app/values.yaml
git commit -m "feat(agent-worker): add HelmRelease with worker and Bull Board controllers

bjw-s app-template with two controllers. Worker: port 3000, liveness/
readiness probes, readOnlyRootFilesystem, emptyDir for /tmp and npm cache.
Bull Board: port 3001, read-only mode, Valkey password from secret.
RollingUpdate with unavailable: 0 for zero-downtime deploys.

Ref #<issue>"
```

______________________________________________________________________

### Task 14: Bull Board Ingress

Cluster convention: ALL IngressRoutes live under `cluster/apps/traefik/traefik/ingress/<workload>/`. Each workload directory contains `ingress-routes.yaml`, `certificates.yaml`, a `forward-auth.yaml` (if using Authentik), and a `kustomization.yaml` that patches base middlewares into the target namespace. The workload is added to the existing traefik ingress `kustomization.yaml`. No separate Flux
Kustomization is needed — the traefik ingress Kustomization handles it.

**Files:**

- Create: `cluster/apps/traefik/traefik/ingress/bull-board/kustomization.yaml`

- Create: `cluster/apps/traefik/traefik/ingress/bull-board/ingress-routes.yaml`

- Create: `cluster/apps/traefik/traefik/ingress/bull-board/certificates.yaml`

- Create: `cluster/apps/traefik/traefik/ingress/bull-board/forward-auth.yaml`

- Modify: `cluster/apps/traefik/traefik/ingress/kustomization.yaml`

- [ ] **Step 1: Create ingress-routes.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/ingressroute_v1alpha1.json
# Documentation: https://doc.traefik.io/traefik/reference/routing-configuration/kubernetes/crd/http/ingressroute/
apiVersion: traefik.io/v1alpha1
kind: IngressRoute
metadata:
  name: bull-board-ingress-routes-wan-https
  namespace: agent-worker-system
  annotations:
    cert-manager.io/cluster-issuer: ${CLUSTER_ISSUER}
    external-dns.alpha.kubernetes.io/hostname: bull-board.${EXTERNAL_DOMAIN}
spec:
  entryPoints:
    - websecure
  routes:
    # Authentik outpost path - required for SSO auth flow redirects
    - kind: Rule
      match: Host(`bull-board.${EXTERNAL_DOMAIN}`) && PathPrefix(`/outpost.goauthentik.io/`)
      middlewares:
        - name: compress
      services:
        - name: ak-outpost-bull-board-outpost
          passHostHeader: true
          port: 9000
    # Main Bull Board route with SSO forward-auth
    - kind: Rule
      match: Host(`bull-board.${EXTERNAL_DOMAIN}`)
      middlewares:
        - name: authentik-forward-auth-bull-board
        - name: compress
      services:
        - name: agent-queue-worker-bull-board
          namespace: agent-worker-system
          passHostHeader: true
          port: 3001
  tls:
    secretName: "bull-board-${EXTERNAL_DOMAIN/./-}-tls"
```

Write to `cluster/apps/traefik/traefik/ingress/bull-board/ingress-routes.yaml`.

- [ ] **Step 2: Create certificates.yaml**

```yaml
---
# yaml-language-server: $schema=https://kubernetes-schemas.pages.dev/cert-manager.io/certificate_v1.json
apiVersion: cert-manager.io/v1
kind: Certificate
metadata:
  name: "bull-board-${EXTERNAL_DOMAIN/./-}"
  namespace: agent-worker-system
spec:
  secretName: "bull-board-${EXTERNAL_DOMAIN/./-}-tls"
  issuerRef:
    name: ${CLUSTER_ISSUER}
    kind: ClusterIssuer
  dnsNames:
    - "bull-board.${EXTERNAL_DOMAIN}"
```

Write to `cluster/apps/traefik/traefik/ingress/bull-board/certificates.yaml`.

- [ ] **Step 3: Create forward-auth.yaml**

```yaml
---
# yaml-language-server: $schema=https://datreeio.github.io/CRDs-catalog/traefik.io/middleware_v1alpha1.json
# Bull Board forward-auth middleware - points to bull-board outpost
apiVersion: traefik.io/v1alpha1
kind: Middleware
metadata:
  name: authentik-forward-auth-bull-board
  namespace: agent-worker-system
spec:
  forwardAuth:
    address: http://ak-outpost-bull-board-outpost.agent-worker-system.svc.cluster.local:9000/outpost.goauthentik.io/auth/traefik
    trustForwardHeader: true
    authResponseHeaders:
      - X-authentik-username
      - X-authentik-groups
      - X-authentik-entitlements
      - X-authentik-email
      - X-authentik-name
      - X-authentik-uid
      - X-authentik-jwt
      - X-authentik-meta-jwks
      - X-authentik-meta-outpost
      - X-authentik-meta-provider
      - X-authentik-meta-app
      - X-authentik-meta-version
```

Write to `cluster/apps/traefik/traefik/ingress/bull-board/forward-auth.yaml`.

Note: Requires an Authentik Application + Provider + Outpost for `bull-board` to be created in Authentik before this works. The outpost must be deployed to the `agent-worker-system` namespace.

- [ ] **Step 4: Create kustomization.yaml**

```yaml
---
# yaml-language-server: $schema=https://json.schemastore.org/kustomization
apiVersion: kustomize.config.k8s.io/v1beta1
kind: Kustomization
resources:
  - ../base/compress.yaml
  - ./certificates.yaml
  - ./forward-auth.yaml
  - ./ingress-routes.yaml
patches:
  - target:
      kind: Middleware
      name: compress
    patch: |
      - op: replace
        path: /metadata/namespace
        value: agent-worker-system
```

Write to `cluster/apps/traefik/traefik/ingress/bull-board/kustomization.yaml`.

- [ ] **Step 5: Add to traefik ingress kustomization**

Add `- ./bull-board` to the resources list in `cluster/apps/traefik/traefik/ingress/kustomization.yaml`.

- [ ] **Step 6: Commit**

```bash
git add cluster/apps/traefik/traefik/ingress/bull-board/ \
       cluster/apps/traefik/traefik/ingress/kustomization.yaml
git commit -m "feat(agent-worker): add Bull Board ingress with Authentik auth

IngressRoute via Traefik at bull-board.\${EXTERNAL_DOMAIN}. Authentik
forward-auth middleware for admin access. Certificate via ClusterIssuer.
Follows cluster ingress convention under traefik/ingress/.

Ref #<issue>"
```

______________________________________________________________________

### Task 15: ServiceMonitor + VPA + Final Assembly

**Files:**

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/servicemonitor.yaml`

- Create: `cluster/apps/agent-worker-system/agent-queue-worker/app/vpa.yaml`

- Finalize: `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomization.yaml`

- [ ] **Step 1: Create servicemonitor.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/monitoring.coreos.com/servicemonitor_v1.json
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: agent-queue-worker
spec:
  selector:
    matchLabels:
      app.kubernetes.io/instance: agent-queue-worker
      app.kubernetes.io/name: agent-queue-worker
  namespaceSelector:
    matchNames:
      - agent-worker-system
  endpoints:
    - port: http
      path: /metrics
      interval: 30s
      scrapeTimeout: 10s
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/servicemonitor.yaml`.

- [ ] **Step 2: Create vpa.yaml**

```yaml
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: agent-queue-worker-worker
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-queue-worker-worker
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 128Mi
---
# yaml-language-server: $schema=https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/autoscaling.k8s.io/verticalpodautoscaler_v1.json
apiVersion: autoscaling.k8s.io/v1
kind: VerticalPodAutoscaler
metadata:
  name: agent-queue-worker-bull-board
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: agent-queue-worker-bull-board
  updatePolicy:
    updateMode: "Off"
  resourcePolicy:
    containerPolicies:
      - containerName: app
        minAllowed:
          cpu: 1m
          memory: 1Mi
        maxAllowed:
          memory: 128Mi
```

Write to `cluster/apps/agent-worker-system/agent-queue-worker/app/vpa.yaml`.

- [ ] **Step 3: Update kustomization.yaml**

Add `./servicemonitor.yaml` to the resources list in the existing `cluster/apps/agent-worker-system/agent-queue-worker/app/kustomization.yaml` (created in Phase 1A Task 18). The final resources list should be:

```yaml
resources:
  - ./release.yaml
  - ./network-policies.yaml
  - ./prometheusrule.yaml
  - ./vpa.yaml
  - ./secret-reader-rbac.yaml
  - ./servicemonitor.yaml
  - ./agent-queue-worker-secrets.sops.yaml
```

Note: `agent-queue-worker-secrets.sops.yaml` is added after user creates the SOPS secret (Phase 1A Task 20).

- [ ] **Step 4: Verify full build chain**

```bash
kubectl kustomize cluster/apps/agent-worker-system/ > /dev/null
```

- [ ] **Step 5: Commit**

```bash
git add cluster/apps/agent-worker-system/agent-queue-worker/app/servicemonitor.yaml \
       cluster/apps/agent-worker-system/agent-queue-worker/app/vpa.yaml \
       cluster/apps/agent-worker-system/agent-queue-worker/app/kustomization.yaml
git commit -m "feat(agent-worker): add ServiceMonitor, VPA, and finalize kustomization

ServiceMonitor scrapes /metrics every 30s. Two VPAs (worker + bull-board),
mode Off, recommendations only.

Ref #<issue>"
```

______________________________________________________________________

### Task 16: Verification Checklist (Post-Deploy)

After CI runs, images pushed, SOPS secrets created, and Flux reconciles:

- [ ] **Step 1: Verify container images exist**

```bash
gh api user/packages/container/agent-queue-worker/versions --jq '.[0].metadata.container.tags'
gh api user/packages/container/bull-board/versions --jq '.[0].metadata.container.tags'
```

Expected: tags include `1.0.0`

- [ ] **Step 2: Verify pods running**

```bash
kubectl get pods -n agent-worker-system -l app.kubernetes.io/instance=agent-queue-worker
```

Expected: two pods (worker + bull-board), both Running

- [ ] **Step 3: Verify worker health endpoints**

```bash
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- http://localhost:3000/livez
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- http://localhost:3000/readyz
```

Expected: `{"status":"ok"}` and `{"ready":true}`

- [ ] **Step 4: Verify metrics**

```bash
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- http://localhost:3000/metrics | head -5
```

Expected: Prometheus-format metrics output

- [ ] **Step 5: Verify Bull Board UI**

Navigate to `https://bull-board.${EXTERNAL_DOMAIN}` — Authentik login, then Bull Board with `agent` queue visible.

- [ ] **Step 6: Verify bidirectional CNP connectivity**

```bash
# Worker -> n8n (dispatch direction)
kubectl exec -n agent-worker-system deploy/agent-queue-worker-worker -- wget -qO- --timeout=5 http://n8n-webhook.n8n-system.svc:5678/healthz 2>&1 || true

# n8n -> worker (callback direction) — test from n8n worker pod
kubectl exec -n n8n-system deploy/n8n-worker -- wget -qO- --timeout=5 http://agent-queue-worker-worker.agent-worker-system.svc:3000/readyz 2>&1
```

Expected: connections succeed (HTTP response received, content may vary)

- [ ] **Step 7: Verify observability resources**

```bash
kubectl get vpa,servicemonitor,prometheusrule -n agent-worker-system
```

Expected: 2 VPAs, 1 ServiceMonitor, 1 PrometheusRule
