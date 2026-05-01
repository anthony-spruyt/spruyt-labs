import { describe, expect, it, vi } from "vitest";
import { type ServerResponse } from "node:http";
import { handleGetJob, type RouteDeps } from "./routes.js";

function mockRes(): ServerResponse & { _status: number; _body: unknown } {
  const res = {
    _status: 0,
    _body: null as unknown,
    writeHead(status: number) {
      res._status = status;
      return res;
    },
    end(data: string) {
      res._body = JSON.parse(data);
    },
  } as unknown as ServerResponse & { _status: number; _body: unknown };
  return res;
}

const jobData = {
  role: "triage" as const,
  repo: "org/repo",
  event_type: "pull_request",
  priority: 5,
  payload: { action: "opened" },
  pr_number: 42,
  dispatch_state: "dispatched" as const,
  dispatched_at: "2026-01-01T00:00:00Z",
};

describe("handleGetJob", () => {
  it("returns job data with session token", async () => {
    const res = mockRes();
    const getJob = vi.fn().mockResolvedValue({
      id: "org/repo--triage-42",
      data: jobData,
      attemptsMade: 1,
      timestamp: 1700000000000,
      processedOn: 1700000001000,
      finishedOn: undefined,
      getState: vi.fn().mockResolvedValue("active"),
    });
    const redisGet = vi
      .fn()
      .mockResolvedValue("00000000-0000-0000-0000-000000000001");
    const deps = {
      queue: { getJob },
      redis: { get: redisGet },
    } as unknown as RouteDeps;

    await handleGetJob(res, "org/repo--triage-42", deps);

    expect(getJob).toHaveBeenCalledWith("org/repo--triage-42");
    expect(redisGet).toHaveBeenCalledWith("agent:session:org/repo--triage-42");
    expect(res._status).toBe(200);
    const body = res._body as Record<string, unknown>;
    expect(body.jobId).toBe("org/repo--triage-42");
    expect(body.state).toBe("active");
    expect(body.repo).toBe("org/repo");
    expect(body.role).toBe("triage");
    expect(body.pr_number).toBe(42);
    expect(body.session_token).toBe("00000000-0000-0000-0000-000000000001");
    expect(body.attempt).toBe(1);
  });

  it("returns null session_token when expired", async () => {
    const res = mockRes();
    const redisGet = vi.fn().mockResolvedValue(null);
    const deps = {
      queue: {
        getJob: vi.fn().mockResolvedValue({
          id: "org/repo--triage-42",
          data: jobData,
          attemptsMade: 0,
          timestamp: 1700000000000,
          processedOn: undefined,
          finishedOn: undefined,
          getState: vi.fn().mockResolvedValue("waiting"),
        }),
      },
      redis: { get: redisGet },
    } as unknown as RouteDeps;

    await handleGetJob(res, "org/repo--triage-42", deps);

    expect(redisGet).toHaveBeenCalledWith("agent:session:org/repo--triage-42");
    expect(res._status).toBe(200);
    expect((res._body as Record<string, unknown>).session_token).toBeNull();
  });

  it("returns 404 for unknown job", async () => {
    const res = mockRes();
    const getJob = vi.fn().mockResolvedValue(null);
    const deps = { queue: { getJob } } as unknown as RouteDeps;

    await handleGetJob(res, "nonexistent", deps);

    expect(getJob).toHaveBeenCalledWith("nonexistent");
    expect(res._status).toBe(404);
    expect((res._body as Record<string, unknown>).error).toBe("not_found");
  });
});
