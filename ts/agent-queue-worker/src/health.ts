import type { Job, Worker } from "bullmq";
import type { Config } from "./config.js";
import type { AgentJob } from "./job/schema.js";
import { logger } from "./logger.js";
import * as metrics from "./metrics.js";

async function isEndpointHealthy(
  url: string,
  timeoutMs: number
): Promise<boolean> {
  try {
    const resp = await fetch(url, {
      signal: AbortSignal.timeout(timeoutMs),
    });
    return resp.ok;
  } catch {
    return false;
  }
}

interface DepStatus {
  healthy: boolean;
  n8n: boolean;
  litellm: boolean;
}

function sleep(ms: number): Promise<void> {
  return new Promise((resolve) => setTimeout(resolve, ms));
}

export class HealthGate {
  private worker: Worker | undefined;
  private _paused = false;
  private pauseCount = 0;

  constructor(private config: Config) {}

  setWorker(worker: Worker): void {
    this.worker = worker;
  }

  async check(job: Job<AgentJob>): Promise<void> {
    if (!this.worker) {
      throw new Error("HealthGate.setWorker() must be called before check()");
    }
    const status = await this.areDepsHealthy();
    if (status.healthy) return;

    logger.warn("Dependencies unhealthy, pausing worker", {
      jobId: job.id,
      n8n: status.n8n,
      litellm: status.litellm,
    });
    this.pauseCount++;
    await this.worker.pause();
    this._paused = true;
    metrics.healthPauses.inc({
      reason:
        !status.n8n && !status.litellm
          ? "all"
          : !status.n8n
            ? "n8n"
            : "litellm",
    });

    // Wait in-process for deps to recover. Lock extension in processor.ts
    // keeps the BullMQ lock alive during the wait, so the job won't stall.
    while (true) {
      await sleep(this.config.HEALTH_POLL_INTERVAL_MS);
      if ((await this.areDepsHealthy()).healthy) {
        logger.info("Dependencies recovered, resuming worker");
        this.resumeWorker();
        return;
      }
    }
  }

  get paused(): boolean {
    return this._paused;
  }

  clear(): void {
    this._paused = false;
    this.pauseCount = 0;
  }

  private resumeWorker(): void {
    this.pauseCount--;
    if (this.pauseCount > 0) return; // other check() calls still waiting
    this._paused = false;
    try {
      if (this.worker && !this.worker.closing) {
        this.worker.resume();
      }
    } catch (err) {
      logger.error("Failed to resume worker", { error: String(err) });
    }
  }

  private async areDepsHealthy(): Promise<DepStatus> {
    const [n8n, litellm] = await Promise.all([
      isEndpointHealthy(
        this.config.N8N_HEALTH_URL,
        this.config.HEALTH_CHECK_TIMEOUT_MS
      ),
      isEndpointHealthy(
        this.config.LITELLM_HEALTH_URL,
        this.config.HEALTH_CHECK_TIMEOUT_MS
      ),
    ]);
    return { healthy: n8n && litellm, n8n, litellm };
  }
}
