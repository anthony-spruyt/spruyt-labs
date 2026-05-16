import type { Worker, Job } from "bullmq";
import { DelayedError } from "bullmq";
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

export class HealthGate {
  private worker: Worker | undefined;
  private recoveryInProgress = false;
  private recoveryInterval: NodeJS.Timeout | undefined;
  private pollInFlight = false;

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
    if (!job.token) {
      throw new Error(`Job ${job.id} missing token during health gate delay`);
    }
    await job.moveToDelayed(
      Date.now() + this.config.HEALTH_POLL_INTERVAL_MS,
      job.token
    );
    await this.worker.pause();
    metrics.healthPauses.inc({
      reason:
        !status.n8n && !status.litellm
          ? "all"
          : !status.n8n
            ? "n8n"
            : "litellm",
    });

    if (!this.recoveryInProgress) {
      this.recoveryInProgress = true;
      this.startRecoveryPoll();
    }

    throw new DelayedError();
  }

  get paused(): boolean {
    return this.recoveryInProgress;
  }

  clear(): void {
    if (this.recoveryInterval) {
      clearInterval(this.recoveryInterval);
      this.recoveryInterval = undefined;
    }
    this.recoveryInProgress = false;
    this.pollInFlight = false;
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

  private startRecoveryPoll(): void {
    const started = Date.now();

    const interval = setInterval(async () => {
      if (this.pollInFlight) return;
      this.pollInFlight = true;
      try {
        if (!this.recoveryInProgress) return;

        if (Date.now() - started > this.config.HEALTH_MAX_PAUSE_MS) {
          this.clear();
          if (this.worker && !this.worker.closing) {
            this.worker.resume();
          }
          logger.warn("Health pause exceeded max duration, resuming worker");
          return;
        }

        if ((await this.areDepsHealthy()).healthy) {
          this.clear();
          if (this.worker && !this.worker.closing) {
            this.worker.resume();
          }
          logger.info("Dependencies recovered, worker resumed");
        }
      } catch (err) {
        logger.warn("Recovery poll error", { error: String(err) });
      } finally {
        this.pollInFlight = false;
      }
    }, this.config.HEALTH_POLL_INTERVAL_MS);
    interval.unref();
    this.recoveryInterval = interval;
  }
}
