import express, { type Request, type Response } from "express";
import { createBullBoard } from "@bull-board/api";
import { BullMQAdapter } from "@bull-board/api/bullMQAdapter";
import { ExpressAdapter } from "@bull-board/express";
import { Queue } from "bullmq";
import { Redis, RedisOptions } from "ioredis";

class ForceObliterateAdapter extends BullMQAdapter {
  obliterate(): Promise<void> {
    return (this as any).queue.obliterate({ force: true });
  }
}

const required = ["VALKEY_HOST", "VALKEY_PASSWORD", "VALKEY_USER"] as const;
for (const key of required) {
  if (!process.env[key]) {
    console.error(`Missing required env var: ${key}`);
    process.exit(1);
  }
}

const port = parseInt(process.env.BULL_BOARD_PORT ?? "3001", 10);
const readOnly = process.env.READ_ONLY === "true";
const workerUrl = process.env.WORKER_URL ?? "";
const workerSecret = process.env.WORKER_AUTH_SECRET ?? "";

const connection: RedisOptions = {
  host: process.env.VALKEY_HOST!,
  port: parseInt(process.env.VALKEY_PORT ?? "6379", 10),
  password: process.env.VALKEY_PASSWORD!,
  username: process.env.VALKEY_USER!
};

const prefix = process.env.QUEUE_PREFIX ?? "agent:queue";
const queue = new Queue("agent-jobs", { connection, prefix });
const redisClient = new Redis(connection);

const serverAdapter = new ExpressAdapter();
serverAdapter.setBasePath("/");

createBullBoard({
  queues: [new ForceObliterateAdapter(queue, { readOnlyMode: readOnly })],
  serverAdapter,
});

const app = express();

app.get("/healthz", async (_req: Request, res: Response) => {
  try {
    await redisClient.ping();
    res.status(200).json({ status: "ok" });
  } catch {
    res.status(503).json({ status: "error" });
  }
});

app.get("/admin/api/active", async (_req: Request, res: Response) => {
  try {
    const jobs = await queue.getJobs(["active"]);
    const result = jobs.map((j) => ({
      id: j.id,
      name: j.name,
      data: {
        role: j.data.role,
        repo: j.data.repo,
        pr_number: j.data.pr_number,
        issue_number: j.data.issue_number,
      },
      timestamp: j.timestamp,
      processedOn: j.processedOn,
      attemptsMade: j.attemptsMade,
    }));
    res.json(result);
  } catch (err) {
    res.status(500).json({ error: String(err) });
  }
});

app.post(
  "/admin/api/jobs/:jobId/force-fail",
  async (req: Request<{ jobId: string }>, res: Response) => {
    try {
      const jobId = decodeURIComponent(req.params.jobId).replace(
        /[\n\r\t]/g,
        ""
      );
      const job = await queue.getJob(jobId);
      if (!job) return res.status(404).json({ error: "Job not found" });
      if (!(await job.isActive()))
        return res.status(400).json({ error: "Job is not active" });

      // Notify worker to resolve in-memory callback and free concurrency slot
      let workerNotified = false;
      if (workerUrl && workerSecret) {
        try {
          const resp = await fetch(
            `${workerUrl}/jobs/${encodeURIComponent(jobId)}/fail`,
            {
              method: "POST",
              headers: {
                "Content-Type": "application/json",
                Authorization: `Bearer ${workerSecret}`,
              },
              body: JSON.stringify({ reason: "Force failed via admin" }),
              signal: AbortSignal.timeout(5000),
            }
          );
          workerNotified = resp.ok;
        } catch (err) {
          console.warn(`Admin: failed to notify worker for ${jobId}: ${err}`);
        }
      }

      // Redis-side cleanup (moves job to failed, cleans app keys)
      const lockKey = `${prefix}:agent-jobs:${jobId}:lock`;
      const token = `admin-force-fail-${Date.now()}`;
      await redisClient.del(lockKey);
      await redisClient.set(lockKey, token, "PX", 30000);
      job.discard();
      await job.moveToFailed(new Error("Force failed via admin"), token, false);

      const appKeys = [`agent:active:${jobId}`];
      const sessionKeys = await redisClient.keys(`agent:session:${jobId}:*`);
      const resultKeys = await redisClient.keys(`agent:result:${jobId}:*`);
      const allKeys = [...appKeys, ...sessionKeys, ...resultKeys].filter(
        Boolean
      );
      if (allKeys.length > 0) await redisClient.del(...allKeys);

      console.log(
        `Admin: force-failed job ${jobId}, cleaned ${allKeys.length} app keys, worker notified: ${workerNotified}`
      );
      res.json({
        failed: true,
        jobId,
        keysDeleted: allKeys.length,
        workerNotified,
      });
    } catch (err) {
      res.status(500).json({ error: String(err) });
    }
  }
);

const adminHtml = `<!DOCTYPE html>
<html><head>
<title>Bull Board Admin</title>
<style>
  body { font-family: system-ui; max-width: 800px; margin: 2rem auto; padding: 0 1rem; background: #1a1a2e; color: #e0e0e0; }
  h1 { color: #fff; }
  table { width: 100%; border-collapse: collapse; margin: 1rem 0; }
  th, td { text-align: left; padding: 0.5rem; border-bottom: 1px solid #333; }
  th { color: #aaa; }
  button { background: #dc3545; color: white; border: none; padding: 0.4rem 0.8rem; border-radius: 4px; cursor: pointer; }
  button:hover { background: #c82333; }
  button:disabled { background: #666; cursor: not-allowed; }
  .refresh { background: #0d6efd; margin-bottom: 1rem; }
  .refresh:hover { background: #0b5ed7; }
  .empty { color: #888; padding: 2rem; text-align: center; }
  .status { margin: 0.5rem 0; padding: 0.5rem; border-radius: 4px; }
  .status.ok { background: #1a3d1a; color: #4caf50; }
  .status.err { background: #3d1a1a; color: #f44336; }
  a { color: #6ea8fe; }
</style>
</head><body>
<h1>Stuck Job Admin</h1>
<p><a href="/">&larr; Back to Bull Board</a></p>
<button class="refresh" onclick="load()">Refresh Active Jobs</button>
<div id="status"></div>
<div id="content"><div class="empty">Click refresh to load active jobs</div></div>
<script>
function esc(s) { const d = document.createElement('div'); d.textContent = s; return d.innerHTML; }
async function load() {
  const res = await fetch('/admin/api/active');
  const jobs = await res.json();
  const el = document.getElementById('content');
  if (!jobs.length) { el.textContent = ''; const d = document.createElement('div'); d.className = 'empty'; d.textContent = 'No active jobs'; el.appendChild(d); return; }
  const tbl = document.createElement('table');
  tbl.innerHTML = '<tr><th>Job ID</th><th>Role</th><th>Repo</th><th>Age</th><th>Attempts</th><th></th></tr>';
  jobs.forEach(j => {
    const tr = document.createElement('tr');
    const age = Math.round((Date.now() - j.processedOn) / 1000);
    const repo = (j.data.repo || '').split('/').pop();
    [j.id || '', j.data.role || '', repo, age + 's', String(j.attemptsMade)].forEach(val => {
      const td = document.createElement('td'); td.textContent = val; tr.appendChild(td);
    });
    const td = document.createElement('td');
    const btn = document.createElement('button');
    btn.textContent = 'Kill';
    btn.addEventListener('click', () => kill(j.id));
    td.appendChild(btn);
    tr.appendChild(td);
    tbl.appendChild(tr);
  });
  el.textContent = '';
  el.appendChild(tbl);
}
async function kill(jobId) {
  if (!confirm('Force-fail this job? It moves to Failed tab and worker picks up next job.')) return;
  const res = await fetch('/admin/api/jobs/' + encodeURIComponent(jobId) + '/force-fail', { method: 'POST' });
  const data = await res.json();
  const el = document.getElementById('status');
  el.textContent = '';
  const div = document.createElement('div');
  if (res.ok) {
    div.className = 'status ok';
    div.textContent = 'Force-failed ' + jobId + ' (' + data.keysDeleted + ' keys cleaned)';
  } else {
    div.className = 'status err';
    div.textContent = 'Error: ' + (data.error || 'unknown');
  }
  el.appendChild(div);
  load();
}
</script>
</body></html>`;

app.get("/admin", (_req: Request, res: Response) => {
  res.setHeader("Content-Type", "text/html");
  res.send(adminHtml);
});

app.use("/", serverAdapter.getRouter());

const server = app.listen(port, () => {
  console.log(`Bull Board running on port ${port} (read-only: ${readOnly})`);
});

process.on("SIGTERM", () => {
  server.close(() => {
    queue
      .close()
      .then(() => redisClient.quit())
      .then(() => process.exit(0))
      .catch((err) => {
        console.error("Shutdown error:", err);
        redisClient.quit().catch(() => {});
        process.exit(1);
      });
  });
});
