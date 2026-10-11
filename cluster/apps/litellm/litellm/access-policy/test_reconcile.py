import io
import os
import sys
import unittest
import urllib.error
from contextlib import redirect_stderr, redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import reconcile  # noqa: E402

try:
    import yaml
except ImportError:
    yaml = None

MASTER_KEY = "sk-master-test-value"
TEAM_ID = "11111111-1111-1111-1111-111111111111"
OTHER_TEAM_ID = "22222222-2222-2222-2222-222222222222"
GROUP_ID = "33333333-3333-3333-3333-333333333333"
SERVER_A = "aaaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa"
SERVER_B = "bbbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb"
KEY_TOKEN = "hashed-token-value"
KEY_ALIAS = "agent-key"
TEAM_ALIAS = "agents"
GROUP_NAME = "dev"
TOOLS = ["query", "alerts"]
EMPTY_PERMISSION = {"object_permission_id": "p1", "mcp_servers": [], "mcp_tool_permissions": {}, "mcp_tool_search_enabled": None, "skills": []}


def policy_doc():
    return {
        "teams": [{"team_id": TEAM_ID, "team_alias": TEAM_ALIAS}],
        "access_groups": [{"name": GROUP_NAME, "mcp_server_ids": [SERVER_A], "team_ids": [TEAM_ID]}],
        "keys": [{"key_alias": KEY_ALIAS, "object_permission": {"mcp_servers": [SERVER_A], "mcp_tool_permissions": {SERVER_A: TOOLS}}}],
    }


class FakeApi:
    def __init__(self):
        self.teams = [{"team_id": TEAM_ID, "team_alias": TEAM_ALIAS, "object_permission": dict(EMPTY_PERMISSION)}]
        self.groups = [
            {
                "access_group_id": GROUP_ID,
                "access_group_name": GROUP_NAME,
                "description": None,
                "access_model_names": [],
                "access_mcp_server_ids": [SERVER_A],
                "access_agent_ids": [],
                "assigned_team_ids": [TEAM_ID],
                "assigned_keys": [],
            }
        ]
        self.keys = [
            {
                "key_alias": KEY_ALIAS,
                "token": KEY_TOKEN,
                "object_permission": {**EMPTY_PERMISSION, "mcp_servers": [SERVER_A], "mcp_tool_permissions": {SERVER_A: list(reversed(TOOLS))}},
            }
        ]
        self.calls = []

    def request(self, method, path, body=None):
        self.calls.append((method, path, body))
        base = path.split("?")[0]
        if method == "GET" and base == "/team/list":
            return [{"team_id": t["team_id"], "team_alias": t["team_alias"], "object_permission": None} for t in self.teams]
        if method == "GET" and base == "/team/info":
            wanted = path.split("team_id=")[1]
            return {"team_info": next(t for t in self.teams if t["team_id"] == wanted)}
        if method == "GET" and base == "/v1/access_group":
            return self.groups
        if method == "GET" and base == "/key/list":
            return {"keys": self.keys, "total_count": len(self.keys), "current_page": 1, "total_pages": 1}
        return {}

    def writes(self):
        return [c for c in self.calls if c[0] != "GET"]


def run_policy(api, doc, mode):
    lines = []
    code = reconcile.run(api, reconcile.parse_policy(doc), mode, out=lines.append)
    return code, lines


class NormalizeTest(unittest.TestCase):
    def test_empty_values_are_dropped_and_lists_sorted(self):
        raw = {**EMPTY_PERMISSION, "mcp_servers": [SERVER_B, SERVER_A, SERVER_A], "mcp_tool_permissions": {SERVER_A: ["b", "a"]}}
        self.assertEqual(
            reconcile.normalize_permission(raw),
            {"mcp_servers": [SERVER_A, SERVER_B], "mcp_tool_permissions": {SERVER_A: ["a", "b"]}},
        )

    def test_none_and_empty_mapping_mean_no_permission(self):
        self.assertEqual(reconcile.normalize_permission(None), {})
        self.assertEqual(reconcile.normalize_permission(dict(EMPTY_PERMISSION)), {})

    def test_unknown_field_is_a_shape_error(self):
        with self.assertRaises(reconcile.ShapeError):
            reconcile.normalize_permission({"surprise": ["x"]})


class ParsePolicyTest(unittest.TestCase):
    def test_valid_policy_parses(self):
        policy = reconcile.parse_policy(policy_doc())
        self.assertEqual([t.team_id for t in policy.teams], [TEAM_ID])
        self.assertEqual(policy.groups[0].description, "")
        self.assertEqual(policy.keys[0].object_permission["mcp_tool_permissions"][SERVER_A], sorted(TOOLS))

    def test_unknown_section_field_and_duplicates_are_rejected(self):
        bad_docs = [
            {"surprise": []},
            {"teams": [{"team_id": TEAM_ID, "team_alias": TEAM_ALIAS, "surprise": 1}]},
            {"teams": [{"team_id": TEAM_ID, "team_alias": TEAM_ALIAS}, {"team_id": TEAM_ID, "team_alias": "other"}]},
            {"keys": [{"key_alias": KEY_ALIAS}, {"key_alias": KEY_ALIAS}]},
            {"access_groups": [{"description": "no name"}]},
        ]
        for doc in bad_docs:
            with self.subTest(doc=doc), self.assertRaises(reconcile.PolicyError):
                reconcile.parse_policy(doc)


class DiffModeTest(unittest.TestCase):
    def test_matching_state_reports_zero_changes_and_writes_nothing(self):
        api = FakeApi()
        code, lines = run_policy(api, policy_doc(), "diff")
        self.assertEqual(code, 0)
        self.assertEqual(lines[-1], "changes: 0")
        self.assertEqual(api.writes(), [])
        self.assertTrue(all(line.endswith(": ok") or line.startswith("managed:") or line.startswith("changes:") for line in lines))

    def test_differences_are_listed_per_object_and_nothing_is_written(self):
        api = FakeApi()
        api.groups[0]["access_mcp_server_ids"] = [SERVER_B]
        api.keys[0]["object_permission"] = dict(EMPTY_PERMISSION)
        doc = policy_doc()
        doc["teams"].append({"team_id": OTHER_TEAM_ID, "team_alias": "new-team"})
        code, lines = run_policy(api, doc, "diff")
        self.assertEqual(code, 0)
        self.assertEqual(lines[-1], "changes: 3")
        text = "\n".join(lines)
        self.assertIn("team new-team (" + OTHER_TEAM_ID + "): CREATE", text)
        self.assertIn(f"access group {GROUP_NAME}: UPDATE", text)
        self.assertIn(f'mcp_server_ids: live=["{SERVER_B}"] desired=["{SERVER_A}"]', text)
        self.assertIn(f"key {KEY_ALIAS}: UPDATE", text)
        self.assertEqual(api.writes(), [])

    def test_unmanaged_objects_are_ignored(self):
        api = FakeApi()
        api.teams.append({"team_id": OTHER_TEAM_ID, "team_alias": "n8n", "object_permission": {"mcp_servers": [SERVER_B]}})
        api.groups.append({**api.groups[0], "access_group_id": "g2", "access_group_name": "n8n-dev"})
        api.keys.append({"key_alias": "n8n", "token": "other-token", "object_permission": {"mcp_servers": [SERVER_B]}})
        code, lines = run_policy(api, policy_doc(), "diff")
        self.assertEqual((code, lines[-1]), (0, "changes: 0"))

    def test_group_membership_compares_team_ids_and_key_aliases(self):
        api = FakeApi()
        api.groups[0]["assigned_team_ids"] = [TEAM_ID, OTHER_TEAM_ID]
        api.groups[0]["assigned_keys"] = [{"id": KEY_TOKEN, "name": KEY_ALIAS}]
        _, lines = run_policy(api, policy_doc(), "diff")
        text = "\n".join(lines)
        self.assertIn("team_ids: live=", text)
        self.assertIn(f'key_aliases: live=["{KEY_ALIAS}"] desired=[]', text)

    def test_missing_key_alias_fails_after_reporting(self):
        api = FakeApi()
        api.keys = []
        code, lines = run_policy(api, policy_doc(), "diff")
        self.assertEqual(code, 1)
        self.assertIn(f"key {KEY_ALIAS}: key alias missing; keys are never created here", lines)
        self.assertEqual(lines[-1], "changes: 0")

    def test_duplicate_live_key_alias_fails(self):
        api = FakeApi()
        api.keys.append(dict(api.keys[0]))
        code, lines = run_policy(api, policy_doc(), "diff")
        self.assertEqual(code, 1)
        self.assertIn(f"key {KEY_ALIAS}: key alias ambiguous; keys are never created here", lines)

    def test_group_with_alias_less_key_is_a_shape_error(self):
        api = FakeApi()
        api.groups[0]["assigned_keys"] = [{"id": KEY_TOKEN, "name": None}]
        with self.assertRaises(reconcile.ShapeError):
            run_policy(api, policy_doc(), "diff")

    def test_unexpected_team_list_shape_is_an_error(self):
        api = FakeApi()
        api.request = lambda method, path, body=None: {"teams": []} if path.startswith("/team/list") else {}
        with self.assertRaises(reconcile.ShapeError):
            run_policy(api, policy_doc(), "diff")

    def test_keys_are_read_across_pages(self):
        api = FakeApi()
        pages = {1: {"keys": [], "total_pages": 2}, 2: {"keys": api.keys, "total_pages": 2}}
        api.request = lambda method, path, body=None: pages[int(path.split("page=")[1])]
        found = reconcile.fetch_keys(api)
        self.assertEqual(list(found), [KEY_ALIAS])


class EnforceTest(unittest.TestCase):
    def test_enforce_with_matching_state_writes_nothing(self):
        api = FakeApi()
        code, lines = run_policy(api, policy_doc(), "enforce")
        self.assertEqual((code, lines[-1]), (0, "changes: 0"))
        self.assertEqual(api.writes(), [])

    def test_missing_team_is_created_with_its_fixed_id(self):
        api = FakeApi()
        doc = policy_doc()
        doc["teams"].append({"team_id": OTHER_TEAM_ID, "team_alias": "new-team", "object_permission": {"mcp_servers": [SERVER_B]}})
        run_policy(api, doc, "enforce")
        self.assertEqual(
            api.writes(),
            [("POST", "/team/new", {"team_id": OTHER_TEAM_ID, "team_alias": "new-team", "object_permission": {"mcp_servers": [SERVER_B]}})],
        )

    def test_team_update_sends_only_changed_managed_fields_and_clears_emptied_ones(self):
        api = FakeApi()
        api.teams[0]["team_alias"] = "old-alias"
        api.teams[0]["object_permission"] = {**EMPTY_PERMISSION, "mcp_servers": [SERVER_B], "mcp_tool_permissions": {SERVER_B: ["x"]}}
        run_policy(api, policy_doc(), "enforce")
        self.assertEqual(
            api.writes(),
            [
                (
                    "POST",
                    "/team/update",
                    {"team_id": TEAM_ID, "team_alias": TEAM_ALIAS, "object_permission": {"mcp_servers": [], "mcp_tool_permissions": {}}},
                )
            ],
        )

    def test_group_update_sends_only_changed_fields_to_its_id(self):
        api = FakeApi()
        api.groups[0]["access_mcp_server_ids"] = [SERVER_B]
        api.groups[0]["assigned_team_ids"] = [TEAM_ID, OTHER_TEAM_ID]
        run_policy(api, policy_doc(), "enforce")
        self.assertEqual(
            api.writes(),
            [("PUT", f"/v1/access_group/{GROUP_ID}", {"access_mcp_server_ids": [SERVER_A], "assigned_team_ids": [TEAM_ID]})],
        )

    def test_group_create_resolves_key_aliases_to_tokens(self):
        api = FakeApi()
        doc = policy_doc()
        doc["access_groups"].append({"name": "keyed", "description": "d", "mcp_server_ids": [SERVER_B], "key_aliases": [KEY_ALIAS]})
        run_policy(api, doc, "enforce")
        self.assertEqual(
            api.writes(),
            [
                (
                    "POST",
                    "/v1/access_group",
                    {
                        "access_group_name": "keyed",
                        "description": "d",
                        "access_model_names": [],
                        "access_mcp_server_ids": [SERVER_B],
                        "access_agent_ids": [],
                        "assigned_team_ids": [],
                        "assigned_key_ids": [KEY_TOKEN],
                    },
                )
            ],
        )

    def test_key_update_targets_the_alias_and_sends_only_permission(self):
        api = FakeApi()
        api.keys[0]["object_permission"] = {**EMPTY_PERMISSION, "mcp_servers": [SERVER_A]}
        run_policy(api, policy_doc(), "enforce")
        self.assertEqual(
            api.writes(),
            [("POST", "/key/update", {"key_alias": KEY_ALIAS, "object_permission": {"mcp_tool_permissions": {SERVER_A: sorted(TOOLS)}}})],
        )

    def test_writes_apply_teams_then_groups_then_keys(self):
        api = FakeApi()
        api.teams[0]["team_alias"] = "old"
        api.groups[0]["access_mcp_server_ids"] = []
        api.keys[0]["object_permission"] = dict(EMPTY_PERMISSION)
        run_policy(api, policy_doc(), "enforce")
        self.assertEqual([c[1].split("/")[1] for c in api.writes()], ["team", "v1", "key"])

    def test_nothing_is_ever_deleted(self):
        api = FakeApi()
        api.teams.append({"team_id": OTHER_TEAM_ID, "team_alias": "extra", "object_permission": {}})
        api.groups.append({**api.groups[0], "access_group_id": "g2", "access_group_name": "extra"})
        api.keys.append({"key_alias": "extra", "token": "t2", "object_permission": {"mcp_servers": [SERVER_B]}})
        run_policy(api, policy_doc(), "enforce")
        self.assertEqual(api.writes(), [])
        self.assertNotIn("DELETE", {c[0] for c in api.calls})

    def test_missing_key_alias_blocks_every_write(self):
        api = FakeApi()
        api.keys = []
        api.teams[0]["team_alias"] = "old"
        code, _ = run_policy(api, policy_doc(), "enforce")
        self.assertEqual(code, 1)
        self.assertEqual(api.writes(), [])

    def test_output_never_contains_key_tokens(self):
        api = FakeApi()
        doc = policy_doc()
        doc["access_groups"].append({"name": "keyed", "key_aliases": [KEY_ALIAS]})
        _, lines = run_policy(api, doc, "enforce")
        self.assertNotIn(KEY_TOKEN, "\n".join(lines))


class ApiTest(unittest.TestCase):
    def test_non_2xx_raises_with_redacted_detail(self):
        error = urllib.error.HTTPError("http://x", 401, "no", {}, io.BytesIO(f"bad {MASTER_KEY} and sk-other-1234".encode()))
        self.addCleanup(error.close)
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(reconcile.ApiError) as ctx:
                reconcile.Api("http://litellm.example", MASTER_KEY).request("GET", "/team/list?x=1")
        message = str(ctx.exception)
        self.assertIn("GET /team/list -> 401", message)
        self.assertNotIn(MASTER_KEY, message)
        self.assertNotIn("sk-other-1234", message)

    def test_connection_failure_raises(self):
        with mock.patch("urllib.request.urlopen", side_effect=urllib.error.URLError("refused")):
            with self.assertRaises(reconcile.ApiError):
                reconcile.Api("http://litellm.example", MASTER_KEY).request("GET", "/team/list")

    def test_request_sends_bearer_json_body(self):
        response = mock.MagicMock()
        response.__enter__.return_value.read.return_value = b'{"ok": true}'
        with mock.patch("urllib.request.urlopen", return_value=response) as opened:
            result = reconcile.Api("http://litellm.example/", MASTER_KEY).request("POST", "/team/new", {"team_id": TEAM_ID})
        req = opened.call_args.args[0]
        self.assertEqual(result, {"ok": True})
        self.assertEqual(req.full_url, "http://litellm.example/team/new")
        self.assertEqual(req.get_header("Authorization"), f"Bearer {MASTER_KEY}")
        self.assertEqual(req.data, b'{"team_id": "' + TEAM_ID.encode() + b'"}')


@unittest.skipUnless(yaml, "PyYAML not installed")
class MainTest(unittest.TestCase):
    def run_main(self, env, doc=None):
        out, err = io.StringIO(), io.StringIO()
        policy_path = os.path.join(os.environ.get("TMPDIR", "/tmp"), "reconcile-test-policy.yml")
        with open(policy_path, "w", encoding="utf-8") as handle:
            yaml.safe_dump(doc or policy_doc(), handle)
        full_env = {"LITELLM_URL": "http://litellm.example", "LITELLM_MASTER_KEY": MASTER_KEY, "POLICY_FILE": policy_path, **env}
        with redirect_stdout(out), redirect_stderr(err):
            code = reconcile.main(full_env)
        return code, out.getvalue(), err.getvalue()

    def test_default_mode_is_diff_and_exit_zero(self):
        api = FakeApi()
        with mock.patch.object(reconcile, "Api", return_value=api):
            code, out, _ = self.run_main({})
        self.assertEqual(code, 0)
        self.assertIn("mode: diff", out)
        self.assertIn("changes: 0", out)
        self.assertEqual(api.writes(), [])

    def test_unknown_mode_is_rejected(self):
        code, _, err = self.run_main({"MODE": "prune"})
        self.assertEqual(code, 2)
        self.assertIn("MODE must be diff or enforce", err)

    def test_api_error_exits_non_zero_without_leaking_the_key(self):
        error = urllib.error.HTTPError("http://x", 500, "boom", {}, io.BytesIO(MASTER_KEY.encode()))
        self.addCleanup(error.close)
        with mock.patch("urllib.request.urlopen", side_effect=error):
            code, out, err = self.run_main({})
        self.assertEqual(code, 1)
        self.assertNotIn(MASTER_KEY, out + err)

    def test_invalid_policy_exits_non_zero(self):
        code, _, err = self.run_main({}, doc={"surprise": []})
        self.assertEqual(code, 1)
        self.assertIn("unknown sections", err)


@unittest.skipUnless(yaml, "PyYAML not installed")
class CommittedPolicyTest(unittest.TestCase):
    def test_committed_policy_file_parses(self):
        path = os.path.join(os.path.dirname(os.path.abspath(__file__)), "access-policy.yml")
        with open(path, encoding="utf-8") as handle:
            policy = reconcile.parse_policy(yaml.safe_load(handle))
        self.assertTrue(policy.teams and policy.groups and policy.keys)


if __name__ == "__main__":
    unittest.main()
