"""Anthropic stand-in that runs inside the LiteLLM container and records what LiteLLM forwards."""

import json
import os
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer

RATELIMIT_HEADERS = {
    "anthropic-ratelimit-unified-status": "allowed",
    "anthropic-ratelimit-unified-5h-utilization": "0.42",
}
CHUNK = 5
received = []


def _last_user_text(body):
    content = body["messages"][-1]["content"]
    if isinstance(content, str):
        return content
    return "".join(block.get("text", "") for block in content)


def _message(model, text):
    return {
        "id": "msg_it",
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": [{"type": "text", "text": text}],
        "stop_reason": "end_turn",
        "stop_sequence": None,
        "usage": {"input_tokens": 10, "output_tokens": 10},
    }


def _events(model, text):
    start = _message(model, "")
    start["content"] = []
    yield "message_start", {"type": "message_start", "message": start}
    yield "content_block_start", {"type": "content_block_start", "index": 0,
                                  "content_block": {"type": "text", "text": ""}}
    # Small chunks so a fake straddles chunk boundaries.
    for i in range(0, len(text), CHUNK):
        yield "content_block_delta", {"type": "content_block_delta", "index": 0,
                                      "delta": {"type": "text_delta", "text": text[i:i + CHUNK]}}
    yield "content_block_stop", {"type": "content_block_stop", "index": 0}
    yield "message_delta", {"type": "message_delta", "delta": {"stop_reason": "end_turn", "stop_sequence": None},
                            "usage": {"output_tokens": 10}}
    yield "message_stop", {"type": "message_stop"}


class Handler(BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"

    def log_message(self, *_):
        pass

    def do_GET(self):
        if self.path != "/_received":
            self._json(404, {})
            return
        self._json(200, received)

    def do_POST(self):
        body = json.loads(self.rfile.read(int(self.headers.get("content-length", 0))) or b"{}")
        received.append({"path": self.path, "body": body})
        if self.path.startswith("/v1/messages/count_tokens"):
            self._json(200, {"input_tokens": 10})
        elif self.path.startswith("/v1/messages"):
            text = "echo: " + _last_user_text(body)
            if body.get("stream"):
                self._stream(body["model"], text)
            else:
                self._json(200, _message(body["model"], text), RATELIMIT_HEADERS)
        else:
            self._json(404, {})

    def _json(self, status, payload, headers=None):
        data = json.dumps(payload).encode()
        self.send_response(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(data)))
        for key, value in (headers or {}).items():
            self.send_header(key, value)
        self.end_headers()
        self.wfile.write(data)

    def _stream(self, model, text):
        self.send_response(200)
        self.send_header("content-type", "text/event-stream")
        self.send_header("transfer-encoding", "chunked")
        for key, value in RATELIMIT_HEADERS.items():
            self.send_header(key, value)
        self.end_headers()
        for event, payload in _events(model, text):
            frame = f"event: {event}\ndata: {json.dumps(payload)}\n\n".encode()
            self.wfile.write(f"{len(frame):x}\r\n".encode() + frame + b"\r\n")
            self.wfile.flush()
        self.wfile.write(b"0\r\n\r\n")


if __name__ == "__main__":
    ThreadingHTTPServer(("127.0.0.1", int(os.environ.get("FAKE_UPSTREAM_PORT", "8099"))), Handler).serve_forever()
