import type { JobsOptions } from "bullmq";

export const DEFAULT_JOB_OPTIONS: Omit<JobsOptions, "jobId" | "priority"> = {
  attempts: 1,
  removeOnComplete: { age: 3600 },
  removeOnFail: { age: 604_800, count: 500 },
};
