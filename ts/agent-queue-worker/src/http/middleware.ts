import { type IncomingMessage, type ServerResponse } from "node:http";

export function json(res: ServerResponse, status: number, data: unknown): void {
  res.writeHead(status, { "Content-Type": "application/json" });
  res.end(JSON.stringify(data));
}

export function authenticate(req: IncomingMessage, secret: string): boolean {
  return req.headers.authorization === `Bearer ${secret}`;
}

export function readBody(req: IncomingMessage): Promise<unknown> {
  return new Promise((resolve, reject) => {
    const chunks: Buffer[] = [];
    let size = 0;
    req.on("data", (chunk: Buffer) => {
      size += chunk.length;
      if (size > 1_048_576) {
        req.destroy(new Error("Body too large"));
        return;
      }
      chunks.push(chunk);
    });
    req.on("end", () => {
      try {
        resolve(JSON.parse(Buffer.concat(chunks).toString()));
      } catch {
        reject(new SyntaxError("Malformed JSON body"));
      }
    });
    req.on("error", reject);
  });
}

interface SafeParseResult<T> {
  success: boolean;
  data?: T;
  error?: { issues: unknown[] };
}

interface ZodLike<T> {
  safeParse(data: unknown): SafeParseResult<T>;
}

export type ParseResult<T> = { ok: true; data: T } | { ok: false };

export async function parseAndValidate<T>(
  req: IncomingMessage,
  res: ServerResponse,
  schema: ZodLike<T>,
  responseBase: Record<string, unknown>
): Promise<ParseResult<T>> {
  let body: unknown;
  try {
    body = await readBody(req);
  } catch (err) {
    if (err instanceof SyntaxError) {
      json(res, 400, { ...responseBase, reason: "malformed_json" });
      return { ok: false };
    }
    throw err;
  }
  const parsed = schema.safeParse(body);
  if (!parsed.success) {
    json(res, 400, {
      ...responseBase,
      reason: "invalid_request",
      errors: parsed.error?.issues,
    });
    return { ok: false };
  }
  return { ok: true, data: parsed.data! };
}
