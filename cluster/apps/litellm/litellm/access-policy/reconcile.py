#!/usr/bin/env python3
import json
import math
import os
import re
import sys
import urllib.error
import urllib.parse
import urllib.request
from dataclasses import dataclass, field, fields

LIST_FIELDS = (
    "mcp_servers",
    "mcp_access_groups",
    "mcp_toolsets",
    "blocked_tools",
    "vector_stores",
    "agents",
    "agent_access_groups",
    "models",
    "search_tools",
    "skills",
)
TOOL_MAP_FIELD = "mcp_tool_permissions"
FLAG_FIELD = "mcp_tool_search_enabled"
PERMISSION_FIELDS = (*LIST_FIELDS, TOOL_MAP_FIELD, FLAG_FIELD)

PERMISSION_KEY = "object_permission"
TEAM_ID = "team_id"
TEAM_ALIAS = "team_alias"
TEAM_MODELS = "models"
TEAM_BUDGET = "max_budget"
TEAM_BUDGET_DURATION = "budget_duration"

SECTIONS = {
    "teams": {TEAM_ID, TEAM_ALIAS, PERMISSION_KEY, TEAM_MODELS, TEAM_BUDGET, TEAM_BUDGET_DURATION},
    "access_groups": {"name", "description", "models", "mcp_server_ids", "agent_ids", "team_ids"},
}
GROUP_API_FIELDS = {
    "description": "description",
    "models": "access_model_names",
    "mcp_server_ids": "access_mcp_server_ids",
    "agent_ids": "access_agent_ids",
    "team_ids": "assigned_team_ids",
}
SECRET_PATTERN = re.compile(r"sk-[A-Za-z0-9_-]+")
APPLY_ACTIONS = ("create", "update")


class PolicyError(Exception):
    pass


class ShapeError(Exception):
    pass


class ApiError(Exception):
    pass


@dataclass(frozen=True)
class Team:
    team_id: str
    team_alias: str | None
    object_permission: dict
    models: list
    max_budget: float | None = None
    budget_duration: str | None = None


@dataclass(frozen=True)
class Group:
    name: str
    description: str
    models: list
    mcp_server_ids: list
    agent_ids: list
    team_ids: list
    group_id: str | None = field(default=None, compare=False)


@dataclass(frozen=True)
class Policy:
    teams: list
    groups: list


@dataclass
class Change:
    label: str
    desired: object
    action: str | None = None
    live: object = None
    diffs: list = field(default_factory=list)


def _require(condition, message, error=ShapeError):
    if not condition:
        raise error(message)


def _is_number(value):
    return isinstance(value, (int, float)) and not isinstance(value, bool)


def _string_list(value, where, error=ShapeError):
    _require(isinstance(value, list) and all(isinstance(v, str) for v in value), f"{where}: expected a list of strings", error)
    return sorted(set(value))


def normalize_permission(raw, error=ShapeError):
    if raw is None:
        return {}
    _require(isinstance(raw, dict), "object_permission: expected a mapping", error)
    unknown = set(raw) - set(PERMISSION_FIELDS) - {"object_permission_id"}
    _require(not unknown, f"object_permission: unknown fields {sorted(unknown)}", error)
    out = {name: _string_list(raw[name], name, error) for name in LIST_FIELDS if raw.get(name)}
    tools = raw.get(TOOL_MAP_FIELD)
    if tools:
        _require(isinstance(tools, dict), f"{TOOL_MAP_FIELD}: expected a mapping", error)
        out[TOOL_MAP_FIELD] = {sid: _string_list(names, f"{TOOL_MAP_FIELD}.{sid}", error) for sid, names in sorted(tools.items())}
    if raw.get(FLAG_FIELD):
        out[FLAG_FIELD] = True
    return out


def _section(doc, name):
    entries = doc.get(name) or []
    _require(isinstance(entries, list), f"{name}: expected a list", PolicyError)
    for entry in entries:
        _require(isinstance(entry, dict), f"{name}: every entry must be a mapping", PolicyError)
        unknown = set(entry) - SECTIONS[name]
        _require(not unknown, f"{name}: unknown fields {sorted(unknown)}", PolicyError)
    return entries


def _policy_team(entry):
    _require(entry.get(TEAM_ID) and entry.get(TEAM_ALIAS), "teams: team_id and team_alias are required", PolicyError)
    where = f"teams.{entry[TEAM_ALIAS]}"
    _require(TEAM_MODELS in entry, f"{where}.{TEAM_MODELS}: required", PolicyError)
    models = _string_list(entry[TEAM_MODELS], f"{where}.{TEAM_MODELS}", PolicyError)
    _require(models, f"{where}.{TEAM_MODELS}: must not be empty, an empty list allows every model", PolicyError)
    budget, duration = entry.get(TEAM_BUDGET), entry.get(TEAM_BUDGET_DURATION)
    _require((budget is None) == (duration is None), f"{where}: {TEAM_BUDGET} and {TEAM_BUDGET_DURATION} are set together or not at all", PolicyError)
    if budget is not None:
        _require(_is_number(budget) and math.isfinite(budget) and budget > 0, f"{where}.{TEAM_BUDGET}: expected a number above 0", PolicyError)
        _require(isinstance(duration, str) and duration, f"{where}.{TEAM_BUDGET_DURATION}: expected a string such as 30d", PolicyError)
    return Team(entry[TEAM_ID], entry[TEAM_ALIAS], normalize_permission(entry.get(PERMISSION_KEY), PolicyError), models, budget, duration)


def _policy_group(entry):
    _require(entry.get("name"), "access_groups: name is required", PolicyError)
    lists = {name: _string_list(entry.get(name) or [], f"access_groups.{entry['name']}.{name}", PolicyError) for name in SECTIONS["access_groups"] - {"name", "description"}}
    return Group(name=entry["name"], description=entry.get("description") or "", **lists)


def _unique(values, name):
    _require(len(values) == len(set(values)), f"{name}: duplicate entries", PolicyError)


def parse_policy(doc):
    _require(isinstance(doc, dict), "policy: expected a mapping", PolicyError)
    unknown = set(doc) - set(SECTIONS)
    _require(not unknown, f"policy: unknown sections {sorted(unknown)}", PolicyError)
    policy = Policy(
        teams=[_policy_team(e) for e in _section(doc, "teams")],
        groups=[_policy_group(e) for e in _section(doc, "access_groups")],
    )
    _unique([t.team_id for t in policy.teams], "teams.team_id")
    _unique([t.team_alias for t in policy.teams], "teams.team_alias")
    _unique([g.name for g in policy.groups], "access_groups.name")
    return policy


def redact(text, secret):
    text = SECRET_PATTERN.sub("[redacted]", text)
    return text.replace(secret, "[redacted]") if secret else text


class Api:
    def __init__(self, base_url, token, timeout=30):
        self.base_url = base_url.rstrip("/")
        self.token = token
        self.timeout = timeout

    def request(self, method, path, body=None):
        data = None if body is None else json.dumps(body).encode()
        headers = {"Authorization": f"Bearer {self.token}", "Content-Type": "application/json"}
        req = urllib.request.Request(self.base_url + path, data=data, method=method, headers=headers)
        where = f"{method} {path.split('?')[0]}"
        try:
            with urllib.request.urlopen(req, timeout=self.timeout) as resp:
                raw = resp.read()
        except urllib.error.HTTPError as exc:
            detail = redact(exc.read().decode(errors="replace")[:300], self.token)
            raise ApiError(f"{where} -> {exc.code}: {detail}") from None
        except urllib.error.URLError as exc:
            raise ApiError(f"{where} failed: {redact(str(exc.reason), self.token)}") from None
        return json.loads(raw) if raw else None


def live_team(team_id, info):
    _require(isinstance(info, dict) and isinstance(info.get("team_info"), dict), "team/info: unexpected shape")
    team = info["team_info"]
    models = _string_list(team.get(TEAM_MODELS) or [], f"team/info {team_id}.{TEAM_MODELS}")
    budget, duration = team.get(TEAM_BUDGET), team.get(TEAM_BUDGET_DURATION)
    _require(budget is None or _is_number(budget), f"team/info {team_id}.{TEAM_BUDGET}: expected a number")
    _require(duration is None or isinstance(duration, str), f"team/info {team_id}.{TEAM_BUDGET_DURATION}: expected a string")
    return Team(team_id, team.get(TEAM_ALIAS), normalize_permission(team.get(PERMISSION_KEY)), models, budget, duration)


def live_group(raw):
    _require(isinstance(raw, dict) and raw.get("access_group_id") and raw.get("access_group_name"), "access_group: unexpected shape")
    name = raw["access_group_name"]
    lists = {attr: _string_list(raw.get(api_name) or [], f"access_group {name}.{api_name}") for attr, api_name in GROUP_API_FIELDS.items() if attr != "description"}
    return Group(name=name, description=raw.get("description") or "", group_id=raw["access_group_id"], **lists)


def fetch_teams(api, wanted_ids):
    teams = api.request("GET", "/team/list")
    _require(isinstance(teams, list) and all(isinstance(t, dict) for t in teams), "team/list: expected a list")
    present = {t.get(TEAM_ID) for t in teams}
    return {tid: live_team(tid, api.request("GET", f"/team/info?{urllib.parse.urlencode({'team_id': tid})}")) for tid in sorted(wanted_ids & present)}


def fetch_groups(api):
    groups = api.request("GET", "/v1/access_group")
    _require(isinstance(groups, list), "access_group: expected a list")
    return {g.name: g for g in (live_group(raw) for raw in groups)}


def differing(live, desired):
    pairs = ((f.name, getattr(live, f.name), getattr(desired, f.name)) for f in fields(desired) if f.compare)
    return [(name, was, want) for name, was, want in pairs if was != want]


def empty_like(name):
    if name == TOOL_MAP_FIELD:
        return {}
    return False if name == FLAG_FIELD else []


def permission_payload(live_permission, desired_permission):
    return {name: desired_permission.get(name, empty_like(name)) for name in PERMISSION_FIELDS if live_permission.get(name) != desired_permission.get(name)}


def _compare(label, live, desired):
    if live is None:
        return Change(label, desired, "create")
    diffs = differing(live, desired)
    return Change(label, desired, "update" if diffs else None, live, diffs)


def plan_teams(policy, live):
    return [_compare(f"team {t.team_alias} ({t.team_id})", live.get(t.team_id), t) for t in policy.teams]


def plan_groups(policy, live):
    return [_compare(f"access group {g.name}", live.get(g.name), g) for g in policy.groups]


def team_request(change):
    desired = change.desired
    if change.action == "create":
        body = {TEAM_ID: desired.team_id, TEAM_ALIAS: desired.team_alias}
        if desired.object_permission:
            body[PERMISSION_KEY] = desired.object_permission
        body[TEAM_MODELS] = desired.models
        for name in (TEAM_BUDGET, TEAM_BUDGET_DURATION):
            if getattr(desired, name) is not None:
                body[name] = getattr(desired, name)
        return "POST", "/team/new", body
    changed = {name for name, _, _ in change.diffs}
    body = {TEAM_ID: desired.team_id}
    if TEAM_ALIAS in changed:
        body[TEAM_ALIAS] = desired.team_alias
    if PERMISSION_KEY in changed:
        body[PERMISSION_KEY] = permission_payload(change.live.object_permission, desired.object_permission)
    if TEAM_MODELS in changed:
        body[TEAM_MODELS] = desired.models
    for name in (TEAM_BUDGET, TEAM_BUDGET_DURATION):
        if name in changed:
            body[name] = getattr(desired, name)
    return "POST", "/team/update", body


def group_request(change):
    desired = change.desired
    creating = change.action == "create"
    names = [f.name for f in fields(desired) if f.compare] if creating else [name for name, _, _ in change.diffs]
    body = {"access_group_name": desired.name} if creating else {}
    for name in names:
        if name != "name":
            body[GROUP_API_FIELDS[name]] = getattr(desired, name)
    if creating:
        return "POST", "/v1/access_group", body
    return "PUT", f"/v1/access_group/{urllib.parse.quote(change.live.group_id, safe='')}", body


def report(changes, out):
    for change in changes:
        out(f"{change.label}: {'ok' if change.action is None else change.action.upper()}")
        for name, was, want in change.diffs:
            out(f"  {name}: live={json.dumps(was, sort_keys=True)} desired={json.dumps(want, sort_keys=True)}")


def apply_changes(api, changes, build_request, out):
    for change in changes:
        if change.action in APPLY_ACTIONS:
            method, path, body = build_request(change)
            api.request(method, path, body)
            out(f"applied {change.label}: {change.action}")


def run(api, policy, mode, out=print):
    teams = plan_teams(policy, fetch_teams(api, {t.team_id for t in policy.teams}))
    groups = plan_groups(policy, fetch_groups(api))
    everything = [*teams, *groups]
    report(everything, out)
    if mode == "enforce":
        apply_changes(api, teams, team_request, out)
        apply_changes(api, groups, group_request, out)
    out(f"managed: teams={len(teams)} access_groups={len(groups)}")
    out(f"changes: {sum(1 for c in everything if c.action in APPLY_ACTIONS)}")
    return 0


def main(environ=None):
    env = os.environ if environ is None else environ
    mode = env.get("MODE", "diff")
    if mode not in ("diff", "enforce"):
        print(f"MODE must be diff or enforce, got {mode!r}", file=sys.stderr)
        return 2
    import yaml  # PyYAML ships in the Job image

    master_key = env.get("LITELLM_MASTER_KEY", "")
    try:
        with open(env.get("POLICY_FILE", "/policy/access-policy.yml"), encoding="utf-8") as handle:
            policy = parse_policy(yaml.safe_load(handle))
        print(f"mode: {mode}")
        return run(Api(env["LITELLM_URL"], master_key), policy, mode)
    except (PolicyError, ShapeError, ApiError, KeyError) as exc:
        print(f"error: {redact(str(exc), master_key)}", file=sys.stderr)
        return 1


if __name__ == "__main__":
    sys.exit(main())
