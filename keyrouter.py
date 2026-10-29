#!/usr/bin/env python3
"""keyrouter — one Anthropic API endpoint in front of several org API keys.

Clients point ANTHROPIC_BASE_URL at this proxy and keep speaking the native
Anthropic API (/v1/messages, streaming, prompt caching, betas). Each request is
forwarded with a real org key chosen here, and moved to the next key when the
current one is out of credits, rate limited, or revoked.

Why not LiteLLM: an org that has spent its credits answers HTTP 400
invalid_request_error ("credit balance is too low"), which LiteLLM treats as a
non-retryable client error — no cooldown, no fallback — so the request fails
instead of moving keys. Its budget routing can work around that, but the spend
counters live in memory or Postgres and don't line up with each plan's billing
date. This proxy reads the error itself and persists key state across restarts.

Routing is consume-first, not shuffle: every request goes to the first usable
key. Prompt caches are per organization, so spreading traffic across orgs
would pay for the same cache write up to N times.

Config (environment):
  KEYROUTER_KEY_1..N            the org API keys, in preference order
  KEYROUTER_TOKEN               token clients must send as x-api-key. When set
                                the proxy listens on all interfaces; when unset
                                it listens on 127.0.0.1 only and accepts anyone
  KEYROUTER_PORT                default 4000
  KEYROUTER_PROBE_HOURS         how long an out-of-credit key rests before the
                                next request tries it again (default 3)
  KEYROUTER_STATE               state file (default ~/.local/share/keyrouter/state.json)
  KEYROUTER_UPSTREAM            default https://api.anthropic.com

Status: GET /keyrouter/status (needs the token when one is set) reports each
key's state and token totals. GET /keyrouter/health is open.

Limitations: Message Batches and Files are org-scoped objects — a batch created
under one key can only be read back with that key — so route those calls to a
single key directly rather than through this proxy. No request content is ever
logged or stored.
"""

import datetime
import hashlib
import hmac
import http.client
import http.server
import json
import os
import sys
import threading
import time
import urllib.parse

HOP_BY_HOP = {
    "connection", "keep-alive", "proxy-authenticate", "proxy-authorization",
    "te", "trailer", "transfer-encoding", "upgrade",
}
# Request headers the proxy owns: credentials are swapped for the chosen key,
# and encoding is forced to identity so error bodies can be classified.
STRIP_REQUEST = HOP_BY_HOP | {"host", "x-api-key", "authorization", "content-length", "accept-encoding"}


def log(msg):
    print(f"[keyrouter] {datetime.datetime.now(datetime.timezone.utc):%Y-%m-%dT%H:%M:%SZ} {msg}",
          file=sys.stderr, flush=True)


class Key:
    def __init__(self, index, secret):
        self.index = index
        self.secret = secret
        self.id = hashlib.sha256(secret.encode()).hexdigest()[:12]
        self.label = f"key{index} …{secret[-4:]}"
        self.available_at = 0.0
        self.reason = ""
        self.requests = 0
        self.failovers = 0
        self.usage = {"input_tokens": 0, "output_tokens": 0,
                      "cache_creation_input_tokens": 0, "cache_read_input_tokens": 0}


class Router:
    def __init__(self, keys, probe_seconds, state_path):
        self.keys = keys
        self.probe_seconds = probe_seconds
        self.state_path = state_path
        self.lock = threading.Lock()
        self._load()

    def _load(self):
        try:
            with open(self.state_path) as f:
                saved = json.load(f)
        except (OSError, ValueError):
            return
        for key in self.keys:
            s = saved.get(key.id)
            if not s:
                continue
            key.available_at = s.get("available_at", 0.0)
            key.reason = s.get("reason", "")
            key.requests = s.get("requests", 0)
            key.failovers = s.get("failovers", 0)
            key.usage.update(s.get("usage", {}))

    def _save(self):
        data = {k.id: {"available_at": k.available_at, "reason": k.reason,
                       "requests": k.requests, "failovers": k.failovers, "usage": k.usage}
                for k in self.keys}
        tmp = self.state_path + ".tmp"
        try:
            os.makedirs(os.path.dirname(self.state_path), exist_ok=True)
            with open(tmp, "w") as f:
                json.dump(data, f)
            os.replace(tmp, self.state_path)
        except OSError as e:
            log(f"could not save state: {e}")

    def candidates(self):
        """Usable keys in the order they should be tried."""
        now = time.time()
        with self.lock:
            return [k for k in self.keys if k.available_at <= now]

    def rest(self, key, seconds, reason):
        with self.lock:
            key.available_at = time.time() + seconds
            key.reason = reason
            key.failovers += 1
            self._save()
        log(f"{key.label} resting {int(seconds)}s: {reason}")

    def record(self, key, usage):
        with self.lock:
            if key.reason:
                log(f"{key.label} back in service")
                key.reason = ""
            key.requests += 1
            for field in key.usage:
                key.usage[field] += usage.get(field) or 0
            self._save()

    def status(self):
        now = time.time()
        with self.lock:
            return {"keys": [{
                "key": k.label,
                "state": "ready" if k.available_at <= now else "resting",
                "resting_for_seconds": max(0, int(k.available_at - now)),
                "reason": k.reason,
                "requests": k.requests,
                "failovers": k.failovers,
                "usage": k.usage,
            } for k in self.keys]}


def classify(status, headers, body, probe_seconds):
    """How long to rest a key after this upstream response, or None to relay it."""
    text = body.decode("utf-8", "replace").lower()
    if "credit balance" in text or "spend limit" in text or "billing" in text:
        return probe_seconds, f"out of credits (HTTP {status})"
    if status == 429:
        try:
            wait = float(headers.get("retry-after") or 20)
        except ValueError:
            wait = 20.0
        return max(wait, 1.0), "rate limited (HTTP 429)"
    if status in (401, 403):
        return 3600.0, f"key rejected (HTTP {status})"
    return None


class UsageScanner:
    """Pulls token counts out of a JSON body or an SSE stream as it passes through."""

    def __init__(self, streaming):
        self.streaming = streaming
        self.buffer = b""
        self.usage = {}

    def feed(self, chunk):
        self.buffer += chunk
        if not self.streaming:
            return
        *lines, self.buffer = self.buffer.split(b"\n")
        for line in lines:
            if line.startswith(b"data:") and b'"usage"' in line:
                self._take(line[5:])

    def finish(self):
        if not self.streaming:
            self._take(self.buffer)
        return self.usage

    def _take(self, raw):
        try:
            event = json.loads(raw)
        except ValueError:
            return
        usage = event.get("usage") or (event.get("message") or {}).get("usage")
        if isinstance(usage, dict):
            # Streams report input in message_start and the running output total
            # in each message_delta, so the latest value of each field wins.
            for field, value in usage.items():
                if isinstance(value, int):
                    self.usage[field] = value


class Handler(http.server.BaseHTTPRequestHandler):
    protocol_version = "HTTP/1.1"
    router = None
    token = ""
    upstream = None
    timeout_seconds = 600

    def log_message(self, fmt, *args):
        pass  # one line per state change is enough; never log paths or bodies

    def do_GET(self):
        if self.path == "/keyrouter/health":
            return self._reply_json(200, {"ok": True})
        if self.path == "/keyrouter/status":
            if not self._authorized():
                return self._reply_json(401, _error("authentication_error", "invalid keyrouter token"))
            return self._reply_json(200, self.router.status())
        self._forward()

    def _authorized(self):
        if not self.token:
            return True
        sent = self.headers.get("x-api-key") or ""
        auth = self.headers.get("authorization") or ""
        if auth.lower().startswith("bearer "):
            sent = sent or auth[7:]
        return hmac.compare_digest(sent.encode(), self.token.encode())

    def _reply_json(self, status, obj):
        body = json.dumps(obj).encode()
        self.send_response_only(status)
        self.send_header("content-type", "application/json")
        self.send_header("content-length", str(len(body)))
        self.end_headers()
        self.wfile.write(body)

    def _forward(self):
        if not self._authorized():
            return self._reply_json(401, _error("authentication_error", "invalid keyrouter token"))
        length = int(self.headers.get("content-length") or 0)
        if self.headers.get("transfer-encoding"):
            return self._reply_json(411, _error("invalid_request_error", "send a content-length body"))
        body = self.rfile.read(length) if length else b""
        headers = {k: v for k, v in self.headers.items() if k.lower() not in STRIP_REQUEST}
        headers["content-length"] = str(len(body))
        headers["accept-encoding"] = "identity"

        candidates = self.router.candidates()
        if not candidates:
            return self._reply_json(529, _error(
                "overloaded_error", "keyrouter: every API key is resting; see /keyrouter/status"))

        last = None
        for key in candidates:
            headers["x-api-key"] = key.secret
            conn = self.upstream.connect(self.timeout_seconds)
            try:
                conn.request(self.command, self.upstream.prefix + self.path, body, headers)
                resp = conn.getresponse()
            except OSError as e:
                conn.close()
                last = (502, [("content-type", "application/json")],
                        json.dumps(_error("api_error", f"keyrouter: upstream unreachable: {e}")).encode())
                break  # network trouble isn't key-specific; don't burn through keys
            if resp.status < 400:
                return self._relay(key, conn, resp)
            err = resp.read()
            conn.close()
            verdict = classify(resp.status, resp.headers, err, self.router.probe_seconds)
            last = (resp.status, resp.getheaders(), err)
            if verdict is None:
                break  # a real client or server error; another key won't fix it
            self.router.rest(key, *verdict)

        status, resp_headers, err = last
        self.send_response_only(status)
        for name, value in resp_headers:
            if name.lower() not in HOP_BY_HOP | {"content-length"}:
                self.send_header(name, value)
        self.send_header("content-length", str(len(err)))
        self.end_headers()
        self.wfile.write(err)

    do_POST = do_PUT = do_PATCH = do_DELETE = _forward

    def _relay(self, key, conn, resp):
        streaming = "text/event-stream" in (resp.headers.get("content-type") or "")
        scanner = UsageScanner(streaming)
        length = resp.headers.get("content-length")
        chunked = length is None
        try:
            self.send_response_only(resp.status)
            for name, value in resp.getheaders():
                if name.lower() not in HOP_BY_HOP | {"content-length"}:
                    self.send_header(name, value)
            if chunked:
                self.send_header("transfer-encoding", "chunked")
            else:
                self.send_header("content-length", length)
            self.end_headers()
            while True:
                chunk = resp.read1(65536)
                if not chunk:
                    break
                scanner.feed(chunk)
                if chunked:
                    self.wfile.write(b"%x\r\n%s\r\n" % (len(chunk), chunk))
                else:
                    self.wfile.write(chunk)
                self.wfile.flush()
            if chunked:
                self.wfile.write(b"0\r\n\r\n")
        except (BrokenPipeError, ConnectionResetError):
            self.close_connection = True  # client went away mid-stream
        finally:
            conn.close()
            self.router.record(key, scanner.finish())


def _error(kind, message):
    return {"type": "error", "error": {"type": kind, "message": message}}


class Upstream:
    def __init__(self, url):
        parsed = urllib.parse.urlsplit(url)
        self.https = parsed.scheme == "https"
        self.host = parsed.hostname
        self.port = parsed.port or (443 if self.https else 80)
        self.prefix = parsed.path.rstrip("/")

    def connect(self, timeout):
        cls = http.client.HTTPSConnection if self.https else http.client.HTTPConnection
        return cls(self.host, self.port, timeout=timeout)


def load_keys():
    keys = []
    for n in range(1, 100):
        secret = os.environ.get(f"KEYROUTER_KEY_{n}", "").strip()
        if not secret:
            continue
        keys.append(Key(n, secret))
    return keys


def main():
    keys = load_keys()
    if not keys:
        log("no KEYROUTER_KEY_<n> variables set; nothing to route")
        return 1
    token = os.environ.get("KEYROUTER_TOKEN", "")
    port = int(os.environ.get("KEYROUTER_PORT", "4000"))
    host = "0.0.0.0" if token else "127.0.0.1"
    state = os.environ.get("KEYROUTER_STATE") or os.path.expanduser("~/.local/share/keyrouter/state.json")
    probe = float(os.environ.get("KEYROUTER_PROBE_HOURS", "3")) * 3600

    Handler.router = Router(keys, probe, state)
    Handler.token = token
    Handler.upstream = Upstream(os.environ.get("KEYROUTER_UPSTREAM", "https://api.anthropic.com"))
    server = http.server.ThreadingHTTPServer((host, port), Handler)
    server.daemon_threads = True
    log(f"listening on {host}:{port} with {len(keys)} key(s)"
        + ("" if token else " (no token: loopback only)"))
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        pass
    return 0


if __name__ == "__main__":
    sys.exit(main())
