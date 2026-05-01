import type { JobsOptions } from "bullmq";

export const DEFAULT_JOB_OPTIONS: Omit<JobsOptions, "jobId" | "priority"> = {
  attempts: 2,
  backoff: { type: "exponential", delay: 30_000 },
  removeOnComplete: { age: 3600 },
  removeOnFail: { age: 604_800, count: 500 },
};
