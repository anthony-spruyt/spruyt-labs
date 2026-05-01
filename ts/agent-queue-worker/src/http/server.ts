import { createServer, type Server } from "node:http";
import type { Config } from "../config.js";
import { json, authenticate } from "./middleware.js";
import {
  handleAddJob,
  handleGetJob,
  handleCompleteJob,
  handleFailJob,
  handleRetryJob,
  handleResetCircuit,
} from "./routes.js";
import type { RouteDeps } from "./routes.js";
import { logger } from "../logger.js";
import * as metrics from "../metrics.js";

export interface ServerDeps extends RouteDeps {
  config: Config;
  isReady: () => boolean;
}

export function createHttpServer(deps: ServerDeps): Server {
  return createServer(async (req, res) => {
    try {
      const url = new URL(req.url ?? "/", `http://${req.headers.host}`);
      const path = url.pathname;
      const method = req.method ?? "GET";

      if (method === "GET" && path === "/livez")
        return json(res, 200, { status: "ok" });
      if (method === "GET" && path === "/readyz") {
        return json(res, deps.isReady() ? 200 : 503, {
          ready: deps.isReady(),
        });
      }
      if (method === "GET" && path === "/metrics") {
        res.writeHead(200, { "Content-Type": metrics.registry.contentType });
        res.end(await metrics.registry.metrics());
        return;
      }

      if (!authenticate(req, deps.config.N8N_TO_WORKER_SECRET))
        return json(res, 401, { error: "Unauthorized" });

      if (method === "POST" && path === "/jobs")
        return handleAddJob(req, res, deps);

      const jobIdMatch = path.match(/^\/jobs\/([^/]+)$/);
      if (method === "GET" && jobIdMatch) {
        return handleGetJob(res, decodeURIComponent(jobIdMatch[1]!), deps);
      }

      const jobMatch = path.match(/^\/jobs\/([^/]+)\/(done|fail|retry)$/);
      if (method === "POST" && jobMatch) {
        const [, jobId, action] = jobMatch;
        const decoded = decodeURIComponent(jobId!);
        if (action === "done")
          return handleCompleteJob(req, res, decoded, deps);
        if (action === "fail") return handleFailJob(req, res, decoded, deps);
        if (action === "retry") return handleRetryJob(res, decoded, deps);
      }

      const circuitMatch = path.match(/^\/circuit\/([^/]+)\/reset$/);
      if (method === "POST" && circuitMatch) {
        return handleResetCircuit(
          res,
          decodeURIComponent(circuitMatch[1]!),
          deps
        );
      }

      json(res, 404, { error: "Not found" });
    } catch (err) {
      logger.error("Unhandled route error", { error: String(err) });
      if (!res.headersSent) {
        res.writeHead(500, { "Content-Type": "application/json" });
        res.end(JSON.stringify({ error: "Internal server error" }));
      }
    }
  });
}
