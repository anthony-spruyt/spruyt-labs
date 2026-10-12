#!/usr/bin/env python3
import json
import os
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass

REPO = "anthony-spruyt/spruyt-labs"
LABEL = "mcp-tool-drift"
LABEL_COLOR = "fbca04"
GITHUB_API = "https://api.github.com"
VALUES_PATH = "cluster/apps/litellm/litellm/app/values.yaml"
PAGE_SIZE = 100
MODES = ("report", "enforce")
DEFAULT_CONFIG_FILE = "/litellm-config/config.yaml"
LITELLM_TIMEOUT = 60
GITHUB_TIMEOUT = 30
DETAIL_LIMIT = 200


class ConfigError(Exception):
    pass


class ApiError(Exception):
    pass


@dataclass(frozen=True)
class Server:
    name: str
    server_id: str
    allowed: frozenset
    disallowed: frozenset


def _tool_set(value, where):
    if value is None:
        return frozenset()
    if not isinstance(value, list) or not all(isinstance(item, str) for item in value):
        raise ConfigError(f"{where} must be a list of strings")
    return frozenset(value)


def parse_servers(doc):
    servers = doc.get("mcp_servers") if isinstance(doc, dict) else None
    if not isinstance(servers, dict) or not servers:
        raise ConfigError("config has no mcp_servers")
    parsed = []
    for name, entry in servers.items():
        if not isinstance(entry, dict):
            raise ConfigError(f"mcp_servers.{name} must be a mapping")
        server_id = entry.get("server_id")
        if not isinstance(server_id, str) or not server_id:
            raise ConfigError(f"mcp_servers.{name} has no server_id")
        parsed.append(
            Server(
                name=str(name),
                server_id=server_id,
                allowed=_tool_set(entry.get("allowed_tools"), f"mcp_servers.{name}.allowed_tools"),
                disallowed=_tool_set(entry.get("disallowed_tools"), f"mcp_servers.{name}.disallowed_tools"),
            )
        )
    return parsed


def diff(upstream, allowed, disallowed):
    listed = allowed | disallowed
    return sorted(set(upstream) - listed), sorted(listed - set(upstream))


def redact(text, secrets):
    for secret in secrets:
        if secret:
            text = text.replace(secret, "***")
    return text


def fetch(request, timeout, allow=(), secrets=()):
    try:
        with urllib.request.urlopen(request, timeout=timeout) as response:
            status, raw = response.status, response.read()
    except urllib.error.HTTPError as error:
        status, raw = error.code, error.read()
        error.close()
        if status not in allow:
            raise ApiError(f"HTTP {status}{_detail(raw, secrets)}") from None
    except urllib.error.URLError as error:
        raise ApiError(redact(f"request failed: {error.reason}", secrets)) from None
    try:
        return status, json.loads(raw) if raw else {}
    except ValueError:
        if status in allow:
            return status, {}
        raise ApiError("response is not valid JSON") from None


def _detail(raw, secrets):
    try:
        message = json.loads(raw).get("message")
    except (ValueError, AttributeError):
        return ""
    if not isinstance(message, str) or not message:
        return ""
    return ": " + redact(message, secrets)[:DETAIL_LIMIT]


class LiteLLM:
    def __init__(self, base_url, master_key):
        self.base_url = base_url.rstrip("/")
        self.master_key = master_key

    def list_tools(self, server_id):
        query = urllib.parse.urlencode(
            {"server_id": server_id, "include_disabled_tools": "true"}, quote_via=urllib.parse.quote
        )
        request = urllib.request.Request(
            f"{self.base_url}/mcp-rest/tools/list?{query}",
            headers={"Authorization": f"Bearer {self.master_key}"},
            method="GET",
        )
        _, payload = fetch(request, LITELLM_TIMEOUT, secrets=(self.master_key,))
        if not isinstance(payload, dict):
            raise ApiError("unexpected response shape")
        if payload.get("error") is not None:
            raise ApiError(redact(f"upstream error: {str(payload['error'])[:DETAIL_LIMIT]}", (self.master_key,)))
        tools = payload.get("tools")
        if not isinstance(tools, list):
            raise ApiError("response has no tools list")
        names = set()
        for tool in tools:
            name = tool.get("name") if isinstance(tool, dict) else None
            if not isinstance(name, str) or not name:
                raise ApiError("response has a tool without a name")
            names.add(name)
        return names


class GitHub:
    def __init__(self, repo, token, label=LABEL):
        self.repo = repo
        self.token = token
        self.label = label

    def request(self, method, path, body=None, allow=()):
        request = urllib.request.Request(
            GITHUB_API + path,
            data=json.dumps(body).encode() if body is not None else None,
            headers={
                "Authorization": f"Bearer {self.token}",
                "Accept": "application/vnd.github+json",
                "Content-Type": "application/json",
                "X-GitHub-Api-Version": "2022-11-28",
                "User-Agent": "litellm-mcp-tool-drift",
            },
            method=method,
        )
        return fetch(request, GITHUB_TIMEOUT, allow=allow, secrets=(self.token,))

    def ensure_label(self):
        status, _ = self.request(
            "GET", f"/repos/{self.repo}/labels/{urllib.parse.quote(self.label)}", allow=(404,)
        )
        if status == 404:
            self.request(
                "POST",
                f"/repos/{self.repo}/labels",
                {"name": self.label, "color": LABEL_COLOR, "description": "LiteLLM MCP tool list drift"},
            )

    def find_issue(self, title):
        page = 1
        while True:
            query = urllib.parse.urlencode(
                {"labels": self.label, "state": "open", "per_page": PAGE_SIZE, "page": page}
            )
            _, issues = self.request("GET", f"/repos/{self.repo}/issues?{query}")
            if not isinstance(issues, list):
                raise ApiError("unexpected issues response")
            for issue in issues:
                if "pull_request" not in issue and issue.get("title") == title:
                    return issue
            if len(issues) < PAGE_SIZE:
                return None
            page += 1

    def create_issue(self, title, body):
        self.request("POST", f"/repos/{self.repo}/issues", {"title": title, "body": body, "labels": [self.label]})

    def update_issue_body(self, number, body):
        self.request("PATCH", f"/repos/{self.repo}/issues/{number}", {"body": body})

    def comment_and_close(self, number, comment):
        self.request("POST", f"/repos/{self.repo}/issues/{number}/comments", {"body": comment})
        self.request("PATCH", f"/repos/{self.repo}/issues/{number}", {"state": "closed", "state_reason": "completed"})


def issue_title(server):
    return f"chore(litellm): MCP tool drift on {server}"


def _bullets(names):
    return "\n".join(f"- `{name}`" for name in names)


def render_body(server, new, stale):
    sections = []
    if new:
        sections.append(
            "## New tools\n\nOffered upstream, but in neither `allowed_tools` nor `disallowed_tools`:\n\n" + _bullets(new)
        )
    if stale:
        sections.append(
            "## Stale entries\n\nListed in `allowed_tools` or `disallowed_tools`, but no longer offered upstream:\n\n"
            + _bullets(stale)
        )
    sections.append(
        "Add a new tool to `allowed_tools` to enable it or to `disallowed_tools` to hide it on purpose, and delete "
        f"stale entries; both lists are under `mcp_servers.{server}` in `{VALUES_PATH}`."
    )
    return "\n\n".join(sections) + "\n"


def _normalized(text):
    return (text or "").replace("\r\n", "\n").strip()


def sync_issue(github, server, new, stale):
    title = issue_title(server)
    issue = github.find_issue(title)
    if new or stale:
        body = render_body(server, new, stale)
        if issue is None:
            github.create_issue(title, body)
            return "create"
        if _normalized(issue.get("body")) == _normalized(body):
            return "noop"
        github.update_issue_body(issue["number"], body)
        return "edit"
    if issue is None:
        return "noop"
    github.comment_and_close(
        issue["number"],
        f"No drift remains: every tool offered by `{server}` is in `allowed_tools` or `disallowed_tools`, "
        "and no entries are stale.",
    )
    return "close"


def run(servers, litellm, mode, github=None, out=print):
    failures = 0
    if mode == "enforce":
        github.ensure_label()
    for server in servers:
        try:
            upstream = litellm.list_tools(server.server_id)
        except ApiError as error:
            out(f"{server.name}: FAILED {error}")
            failures += 1
            continue
        new, stale = diff(upstream, server.allowed, server.disallowed)
        out(
            f"{server.name}: upstream={len(upstream)} allowed={len(server.allowed)} "
            f"disallowed={len(server.disallowed)} new={json.dumps(new)} stale={json.dumps(stale)}"
        )
        if mode != "enforce":
            continue
        try:
            out(f"{server.name}: issue {sync_issue(github, server.name, new, stale)}")
        except ApiError as error:
            out(f"{server.name}: FAILED {error}")
            failures += 1
    return 1 if failures else 0


def mode_from(environ):
    mode = environ.get("MODE") or "report"
    if mode not in MODES:
        raise ConfigError(f"MODE must be one of {', '.join(MODES)}")
    return mode


def load_servers(path):
    import yaml  # PyYAML ships in the Job image

    try:
        with open(path, encoding="utf-8") as handle:
            return parse_servers(yaml.safe_load(handle))
    except (OSError, yaml.YAMLError) as error:
        raise ConfigError(f"cannot read {path}: {error}") from None


def main(environ=None):
    environ = os.environ if environ is None else environ
    try:
        mode = mode_from(environ)
        master_key = environ.get("LITELLM_MASTER_KEY")
        base_url = environ.get("LITELLM_URL")
        if not master_key or not base_url:
            raise ConfigError("LITELLM_URL and LITELLM_MASTER_KEY are required")
        github = None
        if mode == "enforce":
            token = environ.get("GITHUB_TOKEN")
            if not token:
                raise ConfigError("GITHUB_TOKEN is required in enforce mode")
            github = GitHub(REPO, token)
        servers = load_servers(environ.get("CONFIG_FILE") or DEFAULT_CONFIG_FILE)
    except ConfigError as error:
        print(f"config error: {error}")
        return 2
    try:
        return run(servers, LiteLLM(base_url, master_key), mode, github)
    except ApiError as error:
        print(f"FAILED {error}")
        return 1


if __name__ == "__main__":
    sys.exit(main())
