import type { Redis } from "ioredis";
import { logger } from "../logger.js";

export class CircuitBreaker {
  constructor(private redis: Redis) {}

  async check(repo: string): Promise<{ open: boolean; failures?: number }> {
    const key = `agent:circuit:${repo}`;
    await this.redis.zremrangebyscore(key, "-inf", Date.now() - 3_600_000);
    const count = await this.redis.zcount(key, Date.now() - 3_600_000, "+inf");
    if (count >= 5) {
      logger.warn("Circuit open", { repo, failures: count });
      return { open: true, failures: count };
    }
    return { open: false };
  }

  async trip(repo: string, jobId: string, attempt: number): Promise<void> {
    const key = `agent:circuit:${repo}`;
    await this.redis.zadd(key, Date.now(), `${jobId}:${attempt}`);
    await this.redis.expire(key, 3600);
  }

  async reset(repo: string): Promise<boolean> {
    const deleted = await this.redis.del(`agent:circuit:${repo}`);
    logger.info("Circuit reset", { repo, wasOpen: deleted > 0 });
    return deleted > 0;
  }
}

export class RateLimiter {
  constructor(private redis: Redis) {}

  async check(repo: string): Promise<{ limited: boolean; count?: number }> {
    const key = `agent:rate:${repo}`;
    await this.redis.zremrangebyscore(key, "-inf", Date.now() - 3_600_000);
    const count = await this.redis.zcard(key);
    if (count >= 120) {
      logger.warn("Rate limited", { repo, count });
      return { limited: true, count };
    }
    return { limited: false };
  }

  async record(repo: string, jobId: string): Promise<void> {
    const key = `agent:rate:${repo}`;
    await this.redis.zadd(key, Date.now(), jobId);
    await this.redis.expire(key, 3600);
  }
}
