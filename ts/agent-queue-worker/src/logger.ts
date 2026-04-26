type Level = "debug" | "info" | "warn" | "error";

const LEVELS: Record<Level, number> = { debug: 0, info: 1, warn: 2, error: 3 };
const minLevel = LEVELS[(process.env.LOG_LEVEL as Level) ?? "info"] ?? 1;

interface LogFields {
  jobId?: string;
  role?: string;
  repo?: string;
  pr?: number;
  sha?: string;
  [key: string]: unknown;
}

function log(level: Level, msg: string, fields?: LogFields): void {
  if (LEVELS[level] < minLevel) return;
  const entry = { ts: new Date().toISOString(), level, msg, ...fields };
  const out = level === "error" ? process.stderr : process.stdout;
  out.write(JSON.stringify(entry) + "\n");
}

export const logger = {
  debug: (msg: string, fields?: LogFields) => log("debug", msg, fields),
  info: (msg: string, fields?: LogFields) => log("info", msg, fields),
  warn: (msg: string, fields?: LogFields) => log("warn", msg, fields),
  error: (msg: string, fields?: LogFields) => log("error", msg, fields),
};
