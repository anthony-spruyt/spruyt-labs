import type { Worker, Job } from "bullmq";
import { DelayedError } from "bullmq";
import type { Config } from "./config.js";
import type { AgentJob } from "./job/schema.js";
import { logger } from "./logger.js";

let recoveryInProgress = false;
let recoveryInterval: NodeJS.Timeout | undefined;

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

async function areDepsHealthy(config: Config): Promise<DepStatus> {
  const [n8n, litellm] = await Promise.all([
    isEndpointHealthy(config.N8N_HEALTH_URL, config.HEALTH_CHECK_TIMEOUT_MS),
    isEndpointHealthy(
      config.LITELLM_HEALTH_URL,
      config.HEALTH_CHECK_TIMEOUT_MS
    ),
  ]);
  return { healthy: n8n && litellm, n8n, litellm };
}

function startRecoveryPoll(config: Config, worker: Worker): void {
  recoveryInProgress = true;
  const started = Date.now();

  recoveryInterval = setInterval(async () => {
    try {
      if (Date.now() - started > config.HEALTH_MAX_PAUSE_MS) {
        clearInterval(recoveryInterval);
        recoveryInterval = undefined;
        recoveryInProgress = false;
        worker.resume();
        logger.warn("Health pause exceeded max duration, resuming worker");
        return;
      }

      if ((await areDepsHealthy(config)).healthy) {
        clearInterval(recoveryInterval);
        recoveryInterval = undefined;
        recoveryInProgress = false;
        worker.resume();
        logger.info("Dependencies recovered, worker resumed");
      }
    } catch (err) {
      logger.error("Recovery poll error", { error: String(err) });
    }
  }, config.HEALTH_POLL_INTERVAL_MS);
}

export function clearRecoveryPoll(): void {
  if (recoveryInterval) {
    clearInterval(recoveryInterval);
    recoveryInterval = undefined;
  }
  recoveryInProgress = false;
}

export async function checkDependencies(
  config: Config,
  worker: Worker,
  job: Job<AgentJob>
): Promise<void> {
  const status = await areDepsHealthy(config);
  if (status.healthy) return;

  logger.warn("Dependencies unhealthy, pausing worker", {
    jobId: job.id,
    n8n: status.n8n,
    litellm: status.litellm,
  });
  await job.moveToDelayed(
    Date.now() + config.HEALTH_POLL_INTERVAL_MS,
    job.token!
  );
  await worker.pause();

  if (!recoveryInProgress) {
    startRecoveryPoll(config, worker);
  }

  throw new DelayedError();
}
