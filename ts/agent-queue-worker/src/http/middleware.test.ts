import { EventEmitter } from "node:events";
import type { IncomingMessage, ServerResponse } from "node:http";
import { describe, expect, it } from "vitest";
import { z } from "zod";
import {
  authenticate,
  json,
  parseAndValidate,
  readBody,
} from "./middleware.js";

// ---------------------------------------------------------------------------
// Helpers
// ---------------------------------------------------------------------------

function mockRes(): ServerResponse & {
  _status: number;
  _headers: Record<string, string>;
  _body: string;
} {
  const res = {
    _status: 0,
    _headers: {} as Record<string, string>,
    _body: "",
    writeHead(status: number, headers?: Record<string, string>) {
      res._status = status;
      if (headers) Object.assign(res._headers, headers);
      return res;
    },
    end(data: string) {
      res._body = data;
    },
  } as unknown as ServerResponse & {
    _status: number;
    _headers: Record<string, string>;
    _body: string;
  };
  return res;
}

function makeReq(
  body: Buffer | string | null,
  opts: { errorAfterData?: boolean } = {}
): IncomingMessage {
  const emitter = new EventEmitter();
  process.nextTick(() => {
    if (body !== null) {
      emitter.emit("data", typeof body === "string" ? Buffer.from(body) : body);
    }
    if (opts.errorAfterData) {
      emitter.emit("error", new Error("socket reset"));
    } else {
      emitter.emit("end");
    }
  });
  return emitter as unknown as IncomingMessage;
}

// ---------------------------------------------------------------------------
// json()
// ---------------------------------------------------------------------------

describe("json()", () => {
  it("sets Content-Type header and serialises body", () => {
    const res = mockRes();
    json(res, 201, { created: true, id: 42 });
    expect(res._status).toBe(201);
    expect(res._headers["Content-Type"]).toBe("application/json");
    expect(JSON.parse(res._body)).toEqual({ created: true, id: 42 });
  });

  it("handles nested objects and arrays", () => {
    const res = mockRes();
    json(res, 200, { items: [1, 2, 3], nested: { a: "b" } });
    expect(JSON.parse(res._body)).toEqual({
      items: [1, 2, 3],
      nested: { a: "b" },
    });
  });

  it("handles 4xx status codes", () => {
    const res = mockRes();
    json(res, 400, { error: "bad request" });
    expect(res._status).toBe(400);
  });
});

// ---------------------------------------------------------------------------
// authenticate()
// ---------------------------------------------------------------------------

describe("authenticate()", () => {
  it("returns true when Authorization header matches Bearer token", () => {
    const req = {
      headers: { authorization: "Bearer my-secret-token" },
    } as unknown as IncomingMessage;
    expect(authenticate(req, "my-secret-token")).toBe(true);
  });

  it("returns false when token is wrong", () => {
    const req = {
      headers: { authorization: "Bearer wrong-token" },
    } as unknown as IncomingMessage;
    expect(authenticate(req, "my-secret-token")).toBe(false);
  });

  it("returns false when Authorization header is missing", () => {
    const req = { headers: {} } as unknown as IncomingMessage;
    expect(authenticate(req, "my-secret-token")).toBe(false);
  });

  it("returns false when scheme is not Bearer", () => {
    const req = {
      headers: { authorization: "Basic my-secret-token" },
    } as unknown as IncomingMessage;
    expect(authenticate(req, "my-secret-token")).toBe(false);
  });

  it("returns false when Authorization is the bare token without Bearer prefix", () => {
    const req = {
      headers: { authorization: "my-secret-token" },
    } as unknown as IncomingMessage;
    expect(authenticate(req, "my-secret-token")).toBe(false);
  });
});

// ---------------------------------------------------------------------------
// readBody()
// ---------------------------------------------------------------------------

describe("readBody()", () => {
  it("parses valid JSON body", async () => {
    const req = makeReq(JSON.stringify({ hello: "world" }));
    const result = await readBody(req);
    expect(result).toEqual({ hello: "world" });
  });

  it("parses JSON array body", async () => {
    const req = makeReq(JSON.stringify([1, 2, 3]));
    const result = await readBody(req);
    expect(result).toEqual([1, 2, 3]);
  });

  it("rejects with SyntaxError on malformed JSON", async () => {
    const req = makeReq("{ not valid json ]]]");
    await expect(readBody(req)).rejects.toThrow(SyntaxError);
    await expect(readBody(makeReq("{ not valid json ]]]"))).rejects.toThrow(
      "Malformed JSON body"
    );
  });

  it("rejects when body exceeds 1MB", async () => {
    // Build a payload just over 1MB
    const oversized = Buffer.alloc(1_048_577, "x");
    const emitter = new EventEmitter() as unknown as IncomingMessage;
    const destroyed: boolean[] = [];
    (emitter as unknown as { destroy: () => void }).destroy = () => {
      destroyed.push(true);
    };

    process.nextTick(() => {
      // Two chunks so the size check triggers mid-stream
      emitter.emit("data", oversized);
      emitter.emit("end");
    });

    await expect(readBody(emitter)).rejects.toThrow("Body too large");
  });

  it("rejects on socket error event", async () => {
    const req = makeReq(null, { errorAfterData: true });
    await expect(readBody(req)).rejects.toThrow("socket reset");
  });
});

// ---------------------------------------------------------------------------
// parseAndValidate()
// ---------------------------------------------------------------------------

const SimpleSchema = z.object({
  name: z.string().min(1),
  count: z.number().int().positive(),
});

describe("parseAndValidate()", () => {
  it("returns ok:true with parsed data for valid request", async () => {
    const req = makeReq(JSON.stringify({ name: "test", count: 5 }));
    const res = mockRes();
    const result = await parseAndValidate(req, res, SimpleSchema, {
      accepted: false,
    });
    expect(result.ok).toBe(true);
    if (result.ok) {
      expect(result.data).toEqual({ name: "test", count: 5 });
    }
    // Response should NOT have been written
    expect(res._status).toBe(0);
  });

  it("returns ok:false and 400 for malformed JSON", async () => {
    const req = makeReq("not-json!!!");
    const res = mockRes();
    const result = await parseAndValidate(req, res, SimpleSchema, {
      accepted: false,
    });
    expect(result.ok).toBe(false);
    expect(res._status).toBe(400);
    const body = JSON.parse(res._body);
    expect(body.reason).toBe("malformed_json");
    // responseBase fields are spread into the error response
    expect(body.accepted).toBe(false);
  });

  it("returns ok:false and 400 for schema validation failure", async () => {
    const req = makeReq(JSON.stringify({ name: "", count: -1 }));
    const res = mockRes();
    const result = await parseAndValidate(req, res, SimpleSchema, {
      accepted: false,
    });
    expect(result.ok).toBe(false);
    expect(res._status).toBe(400);
    const body = JSON.parse(res._body);
    expect(body.reason).toBe("invalid_request");
    expect(Array.isArray(body.errors)).toBe(true);
    // Should include errors for both name (too short) and count (negative)
    expect(body.errors.length).toBeGreaterThan(0);
    const fields = body.errors.map((e: { field: string }) => e.field);
    expect(fields).toContain("name");
  });

  it("returns ok:false and 400 when required field is missing", async () => {
    const req = makeReq(JSON.stringify({ name: "test" })); // missing count
    const res = mockRes();
    const result = await parseAndValidate(req, res, SimpleSchema, {
      accepted: false,
    });
    expect(result.ok).toBe(false);
    expect(res._status).toBe(400);
    const body = JSON.parse(res._body);
    expect(body.reason).toBe("invalid_request");
    const fields = body.errors.map((e: { field: string }) => e.field);
    expect(fields).toContain("count");
  });

  it("spreads responseBase into validation error response", async () => {
    const req = makeReq(JSON.stringify({}));
    const res = mockRes();
    await parseAndValidate(req, res, SimpleSchema, { myFlag: true, code: 42 });
    const body = JSON.parse(res._body);
    expect(body.myFlag).toBe(true);
    expect(body.code).toBe(42);
    expect(body.reason).toBe("invalid_request");
  });

  it("propagates non-SyntaxError from readBody (e.g. socket error)", async () => {
    const req = makeReq(null, { errorAfterData: true });
    const res = mockRes();
    await expect(parseAndValidate(req, res, SimpleSchema, {})).rejects.toThrow(
      "socket reset"
    );
  });
});
