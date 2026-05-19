import { Queue, Worker } from "bullmq";
import { Redis } from "ioredis";
import { loadConfig } from "./config.js";
import { HealthGate } from "./health.js";
import { createHttpServer } from "./http/server.js";
import * as metrics from "./metrics.js";
import { Processor } from "./processor.js";
import { CircuitBreaker, RateLimiter } from "./queue/guard.js";
import { setupLifecycle } from "./queue/lifecycle.js";
import { createDefaultRegistry } from "./roles/registry.js";

const config = loadConfig();

const redis = new Redis({
  host: config.VALKEY_HOST,
  port: config.VALKEY_PORT,
  password: config.VALKEY_PASSWORD,
  maxRetriesPerRequest: null,
  retryStrategy: (times: number) => Math.min(times * 500, 5000),
});

const queueOpts = { connection: redis, prefix: "agent:queue" };

const queue = new Queue("agent-jobs", queueOpts);
const registry = createDefaultRegistry(config, metrics.sreBatchSize);
const healthGate = new HealthGate(config);
const processor = new Processor(redis, config, registry, healthGate);
const circuitBreaker = new CircuitBreaker(redis);
const rateLimiter = new RateLimiter(redis);

const worker = new Worker("agent-jobs", async (job) => processor.process(job), {
  ...queueOpts,
  concurrency: config.WORKER_CONCURRENCY,
  stalledInterval: 120_000,
  lockDuration: 120_000,
  maxStalledCount: 2,
});

// Worker constructor needs processor callback, processor needs healthGate,
// healthGate needs worker reference — break the cycle with late-bind.
healthGate.setWorker(worker);

const isReady = () => redis.status === "ready" && !worker.closing;

const server = createHttpServer({
  queue,
  redis,
  processor,
  config,
  registry,
  circuitBreaker,
  rateLimiter,
  isReady,
});

setupLifecycle({
  worker,
  queue,
  redis,
  processor,
  registry,
  circuitBreaker,
  healthGate,
  server,
  config,
});
