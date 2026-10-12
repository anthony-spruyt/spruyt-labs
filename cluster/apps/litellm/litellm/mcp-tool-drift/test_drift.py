import io
import json
import os
import sys
import unittest
import urllib.error
from contextlib import redirect_stdout
from unittest import mock

sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))

import drift  # noqa: E402

try:
    import yaml
except ImportError:
    yaml = None

MASTER_KEY = "sk-master-test-value"
SERVER_ID = "11111111-1111-1111-1111-111111111111"
OTHER_ID = "22222222-2222-2222-2222-222222222222"
TITLE = "chore(litellm): MCP tool drift on alpha"
VALUES_FILE = os.path.join(os.path.dirname(os.path.abspath(__file__)), "..", "app", "values.yaml")


def server(name="alpha", server_id=SERVER_ID, allowed=None, disallowed=None):
    entry = {"server_id": server_id, "alias": name}
    if allowed is not None:
        entry["allowed_tools"] = allowed
    if disallowed is not None:
        entry["disallowed_tools"] = disallowed
    return entry


def config_doc(**servers):
    return {"mcp_servers": servers}


class FakeLiteLLM:
    def __init__(self, catalogs=None, failures=None):
        self.catalogs = catalogs or {}
        self.failures = failures or {}
        self.calls = []

    def list_tools(self, server_id):
        self.calls.append(server_id)
        if server_id in self.failures:
            raise drift.ApiError(self.failures[server_id])
        return set(self.catalogs[server_id])


class FakeGitHub:
    def __init__(self, issues=None, label_exists=True):
        self.issues = issues if issues is not None else []
        self.label_exists = label_exists
        self.calls = []

    def ensure_label(self):
        self.calls.append(("ensure_label",))

    def find_issue(self, title):
        self.calls.append(("find_issue", title))
        for issue in self.issues:
            if issue["title"] == title:
                return issue
        return None

    def create_issue(self, title, body):
        self.calls.append(("create_issue", title, body))

    def update_issue_body(self, number, body):
        self.calls.append(("update_issue_body", number, body))

    def comment_and_close(self, number, comment):
        self.calls.append(("comment_and_close", number, comment))


class ParseServersTest(unittest.TestCase):
    def test_reads_ids_and_lists_with_missing_as_empty(self):
        doc = config_doc(
            alpha=server(allowed=["a", "b"], disallowed=["c"]),
            beta=server("beta", OTHER_ID),
        )
        servers = drift.parse_servers(doc)
        self.assertEqual([s.name for s in servers], ["alpha", "beta"])
        self.assertEqual(servers[0].server_id, SERVER_ID)
        self.assertEqual(servers[0].allowed, frozenset({"a", "b"}))
        self.assertEqual(servers[0].disallowed, frozenset({"c"}))
        self.assertEqual(servers[1].allowed, frozenset())
        self.assertEqual(servers[1].disallowed, frozenset())

    def test_null_list_is_empty(self):
        entry = server()
        entry["allowed_tools"] = None
        servers = drift.parse_servers(config_doc(alpha=entry))
        self.assertEqual(servers[0].allowed, frozenset())

    def test_missing_mcp_servers_is_an_error(self):
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers({"model_list": []})

    def test_empty_mcp_servers_is_an_error(self):
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers({"mcp_servers": {}})

    def test_missing_server_id_is_an_error(self):
        doc = config_doc(alpha={"alias": "alpha"})
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers(doc)

    def test_non_list_tools_is_an_error(self):
        doc = config_doc(alpha=server(allowed="query"))
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers(doc)

    def test_non_string_tool_is_an_error(self):
        doc = config_doc(alpha=server(allowed=["a", 3]))
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers(doc)

    def test_non_mapping_server_is_an_error(self):
        with self.assertRaises(drift.ConfigError):
            drift.parse_servers({"mcp_servers": {"alpha": "x"}})

    @unittest.skipIf(yaml is None, "PyYAML not installed")
    def test_committed_values_cover_every_server_with_an_id(self):
        with open(VALUES_FILE, encoding="utf-8") as handle:
            values = yaml.safe_load(handle)
        config = yaml.safe_load(values["configMaps"]["litellm-config"]["data"]["config.yaml"])
        servers = drift.parse_servers(config)
        self.assertEqual(len(servers), len(config["mcp_servers"]))
        self.assertGreaterEqual(len(servers), 14)
        self.assertEqual(len({s.server_id for s in servers}), len(servers))


class DiffTest(unittest.TestCase):
    def test_new_is_upstream_in_neither_list(self):
        new, stale = drift.diff({"a", "b", "c"}, frozenset({"a"}), frozenset({"b"}))
        self.assertEqual(new, ["c"])
        self.assertEqual(stale, [])

    def test_stale_covers_allowed_and_disallowed(self):
        new, stale = drift.diff({"a"}, frozenset({"a", "gone1"}), frozenset({"gone2"}))
        self.assertEqual(new, [])
        self.assertEqual(stale, ["gone1", "gone2"])

    def test_results_are_sorted(self):
        new, stale = drift.diff({"z", "m", "a"}, frozenset({"y", "b"}), frozenset())
        self.assertEqual(new, ["a", "m", "z"])
        self.assertEqual(stale, ["b", "y"])

    def test_no_drift(self):
        self.assertEqual(drift.diff({"a", "b"}, frozenset({"a"}), frozenset({"b"})), ([], []))

    def test_tool_in_both_lists_and_upstream_is_not_drift(self):
        self.assertEqual(drift.diff({"a"}, frozenset({"a"}), frozenset({"a"})), ([], []))


class LiteLLMClientTest(unittest.TestCase):
    def response(self, payload, status=200):
        handle = mock.MagicMock()
        handle.__enter__.return_value = handle
        handle.status = status
        handle.read.return_value = json.dumps(payload).encode()
        return handle

    def client(self):
        return drift.LiteLLM("http://litellm:4000/", MASTER_KEY)

    def test_requests_raw_catalog_with_bearer_key(self):
        with mock.patch("urllib.request.urlopen", return_value=self.response({"tools": [{"name": "a"}, {"name": "b"}], "error": None, "message": None})) as urlopen:
            names = self.client().list_tools("id with/space")
        self.assertEqual(names, {"a", "b"})
        request = urlopen.call_args.args[0]
        self.assertEqual(
            request.full_url,
            "http://litellm:4000/mcp-rest/tools/list?server_id=id%20with%2Fspace&include_disabled_tools=true",
        )
        self.assertEqual(request.get_header("Authorization"), f"Bearer {MASTER_KEY}")
        self.assertEqual(request.get_method(), "GET")

    def test_error_field_is_a_failure(self):
        payload = {"tools": [], "error": "server_unavailable", "message": "boom"}
        client = self.client()
        with mock.patch("urllib.request.urlopen", return_value=self.response(payload)):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertIn("server_unavailable", str(raised.exception))

    def test_http_error_is_a_failure(self):
        error = urllib.error.HTTPError("http://x", 500, "boom", {}, io.BytesIO(b"{}"))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertIn("500", str(raised.exception))

    def test_connection_error_is_a_failure(self):
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=urllib.error.URLError("refused")):
            with self.assertRaises(drift.ApiError):
                client.list_tools(SERVER_ID)

    def test_malformed_tools_is_a_failure(self):
        client = self.client()
        for payload in ({"tools": "x"}, {"tools": [{"nope": 1}]}, {}, ["a"]):
            with self.subTest(payload=payload):
                with mock.patch("urllib.request.urlopen", return_value=self.response(payload)):
                    with self.assertRaises(drift.ApiError):
                        client.list_tools(SERVER_ID)

    def test_timeout_while_reading_is_a_failure(self):
        handle = self.response({})
        handle.read.side_effect = TimeoutError("timed out")
        client = self.client()
        with mock.patch("urllib.request.urlopen", return_value=handle):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertIn("timed out", str(raised.exception))

    def test_connection_reset_is_a_failure_without_the_key(self):
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=ConnectionResetError(f"reset {MASTER_KEY}")):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertNotIn(MASTER_KEY, str(raised.exception))

    def test_litellm_nested_detail_message_is_reported(self):
        body = json.dumps({"detail": {"error": "server_not_found", "message": "No such server"}}).encode()
        error = urllib.error.HTTPError("http://x", 404, "nf", {}, io.BytesIO(body))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertEqual(str(raised.exception), "HTTP 404: No such server")

    def test_litellm_nested_detail_error_is_the_fallback(self):
        body = json.dumps({"detail": {"error": "server_not_found"}}).encode()
        error = urllib.error.HTTPError("http://x", 404, "nf", {}, io.BytesIO(body))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertEqual(str(raised.exception), "HTTP 404: server_not_found")

    def test_litellm_string_detail_is_reported(self):
        body = json.dumps({"detail": "Not authenticated"}).encode()
        error = urllib.error.HTTPError("http://x", 401, "na", {}, io.BytesIO(body))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertEqual(str(raised.exception), "HTTP 401: Not authenticated")

    def test_detail_is_redacted_and_truncated(self):
        body = json.dumps({"detail": {"message": MASTER_KEY + "y" * 500}}).encode()
        error = urllib.error.HTTPError("http://x", 400, "bad", {}, io.BytesIO(body))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertNotIn(MASTER_KEY, str(raised.exception))
        self.assertLessEqual(len(str(raised.exception)), len("HTTP 400: ") + drift.DETAIL_LIMIT)

    def test_invalid_json_is_a_failure(self):
        handle = self.response({})
        handle.read.return_value = b"<html>"
        client = self.client()
        with mock.patch("urllib.request.urlopen", return_value=handle):
            with self.assertRaises(drift.ApiError):
                client.list_tools(SERVER_ID)

    def test_master_key_never_appears_in_errors(self):
        error = urllib.error.HTTPError("http://x", 401, MASTER_KEY, {}, io.BytesIO(MASTER_KEY.encode()))
        client = self.client()
        with mock.patch("urllib.request.urlopen", side_effect=error):
            with self.assertRaises(drift.ApiError) as raised:
                client.list_tools(SERVER_ID)
        self.assertNotIn(MASTER_KEY, str(raised.exception))


class RenderBodyTest(unittest.TestCase):
    def test_lists_names_only_with_how_to(self):
        body = drift.render_body("alpha", ["n1", "n2"], ["s1"])
        self.assertIn("## New tools", body)
        self.assertIn("- `n1`\n- `n2`", body)
        self.assertIn("## Stale entries", body)
        self.assertIn("- `s1`", body)
        self.assertIn("allowed_tools", body)
        self.assertIn("disallowed_tools", body)
        self.assertIn("cluster/apps/litellm/litellm/app/values.yaml", body)

    def test_omits_empty_sections(self):
        body = drift.render_body("alpha", ["n1"], [])
        self.assertNotIn("Stale entries", body)
        body = drift.render_body("alpha", [], ["s1"])
        self.assertNotIn("New tools", body)

    def test_is_deterministic(self):
        first = drift.render_body("alpha", ["n"], ["s"])
        second = drift.render_body("alpha", ["n"], ["s"])
        self.assertEqual(first, second)

    def test_names_outside_the_safe_charset_are_left_out(self):
        bad = ["a`b", "line\nbreak", "@octocat", "trail\n", "sp ace", "", "x" * 129, "<b>"]
        body = drift.render_body("alpha", ["good_tool-1.x/y"] + bad, ["stale"] + bad)
        self.assertIn("- `good_tool-1.x/y`", body)
        self.assertIn("- `stale`", body)
        for name in bad:
            if name.strip():
                self.assertNotIn(name, body)
        self.assertNotIn("@", body)

    def test_longest_allowed_name_is_kept(self):
        name = "x" * 128
        self.assertIn(f"- `{name}`", drift.render_body("alpha", [name], []))

    def test_only_unsupported_names_gives_a_note_and_no_list(self):
        body = drift.render_body("alpha", ["@octocat"], [])
        self.assertNotIn("@octocat", body)
        self.assertNotIn("- `", body)
        self.assertNotIn("## New tools", body)
        self.assertIn("1 name with unsupported characters is not listed; see the job log.", body)

    def test_note_counts_unsupported_names_across_sections(self):
        body = drift.render_body("alpha", ["ok", "@a"], ["b`c", "d e"])
        self.assertIn("3 names with unsupported characters are not listed; see the job log.", body)

    def test_each_section_is_capped_with_an_and_more_line(self):
        names = [f"tool_{i:04d}" for i in range(250)]
        body = drift.render_body("alpha", names, names[:101])
        self.assertEqual(body.count("- `tool_"), 200)
        self.assertIn("- `tool_0099`", body)
        self.assertNotIn("- `tool_0100`", body)
        self.assertIn("- and 150 more", body)
        self.assertIn("- and 1 more", body)

    def test_a_very_long_list_stays_far_below_the_github_body_limit(self):
        names = [("n%d" % i).ljust(128, "x") for i in range(5000)]
        body = drift.render_body("alpha", names, names)
        self.assertLess(len(body), 30000)

    def test_count_of_unsupported_names(self):
        self.assertEqual(drift.unsupported_count(["ok", "a`b", "@x"], ["bad\n", "fine"]), 3)


class SyncIssueTest(unittest.TestCase):
    def issue(self, body, number=7):
        return {"number": number, "title": TITLE, "body": body}

    def test_drift_without_issue_creates_it(self):
        github = FakeGitHub()
        action = drift.sync_issue(github, "alpha", ["n"], [])
        self.assertEqual(action, "create")
        self.assertEqual(github.calls[-1], ("create_issue", TITLE, drift.render_body("alpha", ["n"], [])))

    def test_drift_with_changed_body_edits_it(self):
        github = FakeGitHub([self.issue("old body")])
        action = drift.sync_issue(github, "alpha", ["n"], ["s"])
        self.assertEqual(action, "edit")
        self.assertEqual(github.calls[-1], ("update_issue_body", 7, drift.render_body("alpha", ["n"], ["s"])))

    def test_drift_with_same_body_is_a_noop(self):
        body = drift.render_body("alpha", ["n"], [])
        github = FakeGitHub([self.issue(body)])
        self.assertEqual(drift.sync_issue(github, "alpha", ["n"], []), "noop")
        self.assertEqual([c[0] for c in github.calls], ["find_issue"])

    def test_same_body_with_crlf_and_trailing_space_is_a_noop(self):
        body = drift.render_body("alpha", ["n"], []).replace("\n", "\r\n") + "\r\n"
        github = FakeGitHub([self.issue(body)])
        self.assertEqual(drift.sync_issue(github, "alpha", ["n"], []), "noop")

    def test_issue_with_null_body_is_edited(self):
        github = FakeGitHub([self.issue(None)])
        self.assertEqual(drift.sync_issue(github, "alpha", ["n"], []), "edit")

    def test_no_drift_with_open_issue_comments_and_closes(self):
        github = FakeGitHub([self.issue("old")])
        action = drift.sync_issue(github, "alpha", [], [])
        self.assertEqual(action, "close")
        self.assertEqual([c[0] for c in github.calls], ["find_issue", "comment_and_close"])
        self.assertEqual(github.calls[-1][1], 7)

    def test_no_drift_without_issue_does_nothing(self):
        github = FakeGitHub()
        self.assertEqual(drift.sync_issue(github, "alpha", [], []), "noop")
        self.assertEqual([c[0] for c in github.calls], ["find_issue"])

    def test_only_the_exact_title_matches(self):
        other = {"number": 9, "title": TITLE + " extra", "body": "x"}
        github = FakeGitHub([other])
        self.assertEqual(drift.sync_issue(github, "alpha", ["n"], []), "create")


class GitHubClientTest(unittest.TestCase):
    def client(self):
        return drift.GitHub("owner/repo", "ghs_token", label="mcp-tool-drift")

    def test_find_issue_filters_label_state_and_skips_pull_requests(self):
        bot = {"type": "Bot"}
        pages = [
            [{"number": 1, "title": "other", "user": bot}, {"number": 2, "title": TITLE, "pull_request": {}, "user": bot}],
            [{"number": 3, "title": TITLE, "body": "b", "user": bot}],
        ]
        client = self.client()
        with mock.patch.object(client, "request", side_effect=[(200, p) for p in pages]) as request:
            with mock.patch.object(drift, "PAGE_SIZE", 2):
                issue = client.find_issue(TITLE)
        self.assertEqual(issue["number"], 3)
        first = request.call_args_list[0].args
        self.assertEqual(first[0], "GET")
        self.assertIn("labels=mcp-tool-drift", first[1])
        self.assertIn("state=open", first[1])
        self.assertIn("page=1", first[1])
        self.assertIn("page=2", request.call_args_list[1].args[1])

    def test_find_issue_ignores_issues_not_authored_by_a_bot(self):
        issues = [
            {"number": 1, "title": TITLE, "user": {"type": "User"}},
            {"number": 2, "title": TITLE, "user": None},
            {"number": 3, "title": TITLE},
            {"number": 4, "title": TITLE, "user": {"type": "Bot"}},
        ]
        client = self.client()
        with mock.patch.object(client, "request", return_value=(200, issues)):
            self.assertEqual(client.find_issue(TITLE)["number"], 4)
        with mock.patch.object(client, "request", return_value=(200, issues[:3])):
            self.assertIsNone(client.find_issue(TITLE))

    def test_ensure_label_creates_when_missing(self):
        client = self.client()
        with mock.patch.object(client, "request", side_effect=[(404, {}), (201, {})]) as request:
            client.ensure_label()
        self.assertEqual(request.call_args_list[1].args[0], "POST")
        self.assertEqual(request.call_args_list[1].args[1], "/repos/owner/repo/labels")
        self.assertEqual(request.call_args_list[1].args[2]["name"], "mcp-tool-drift")

    def test_ensure_label_skips_when_present(self):
        client = self.client()
        with mock.patch.object(client, "request", return_value=(200, {})) as request:
            client.ensure_label()
        self.assertEqual(request.call_count, 1)

    def test_create_issue_sends_title_body_and_label(self):
        client = self.client()
        with mock.patch.object(client, "request", return_value=(201, {})) as request:
            client.create_issue(TITLE, "body")
        self.assertEqual(
            request.call_args.args,
            ("POST", "/repos/owner/repo/issues", {"title": TITLE, "body": "body", "labels": ["mcp-tool-drift", "chore"]}),
        )

    def test_comment_and_close_closes_first_then_comments(self):
        client = self.client()
        with mock.patch.object(client, "request", return_value=(200, {})) as request:
            client.comment_and_close(7, "done")
        self.assertEqual(
            request.call_args_list[0].args,
            ("PATCH", "/repos/owner/repo/issues/7", {"state": "closed", "state_reason": "completed"}),
        )
        self.assertEqual(request.call_args_list[1].args, ("POST", "/repos/owner/repo/issues/7/comments", {"body": "done"}))

    def test_failed_close_posts_no_comment(self):
        client = self.client()
        with mock.patch.object(client, "request", side_effect=drift.ApiError("HTTP 500")) as request:
            with self.assertRaises(drift.ApiError):
                client.comment_and_close(7, "done")
        self.assertEqual(request.call_count, 1)

    def test_request_sends_token_and_raises_on_unexpected_status(self):
        client = self.client()
        error = urllib.error.HTTPError("http://x", 403, "forbidden", {}, io.BytesIO(b'{"message":"nope"}'))
        with mock.patch("urllib.request.urlopen", side_effect=error) as urlopen:
            with self.assertRaises(drift.ApiError) as raised:
                client.request("GET", "/repos/owner/repo/issues")
        self.assertEqual(urlopen.call_args.args[0].get_header("Authorization"), "Bearer ghs_token")
        self.assertNotIn("ghs_token", str(raised.exception))
        self.assertIn("403", str(raised.exception))


class RunTest(unittest.TestCase):
    def run_drift(self, servers, litellm, github=None, mode="report"):
        out = io.StringIO()
        with redirect_stdout(out):
            code = drift.run(servers, litellm, mode, github)
        return code, out.getvalue()

    def servers(self):
        return drift.parse_servers(
            config_doc(
                alpha=server("alpha", SERVER_ID, allowed=["a", "gone"], disallowed=["d"]),
                beta=server("beta", OTHER_ID, allowed=["x"]),
            )
        )

    def test_report_logs_counts_and_sorted_names_without_github(self):
        litellm = FakeLiteLLM({SERVER_ID: ["a", "d", "z", "m"], OTHER_ID: ["x"]})
        github = FakeGitHub()
        code, output = self.run_drift(self.servers(), litellm, github)
        self.assertEqual(code, 0)
        self.assertIn('alpha: upstream=4 allowed=2 disallowed=1 new=["m", "z"] stale=["gone"]', output)
        self.assertIn("beta: upstream=1 allowed=1 disallowed=0 new=[] stale=[]", output)
        self.assertEqual(github.calls, [])

    def test_report_works_with_no_github_client(self):
        litellm = FakeLiteLLM({SERVER_ID: ["a"], OTHER_ID: ["x"]})
        code, _ = self.run_drift(self.servers(), litellm, None)
        self.assertEqual(code, 0)

    def test_failed_server_is_logged_others_continue_and_exit_is_nonzero(self):
        litellm = FakeLiteLLM({OTHER_ID: ["x", "n"]}, failures={SERVER_ID: "HTTP 500"})
        code, output = self.run_drift(self.servers(), litellm)
        self.assertEqual(code, 1)
        self.assertIn("alpha: FAILED HTTP 500", output)
        self.assertIn('beta: upstream=2 allowed=1 disallowed=0 new=["n"] stale=[]', output)

    def test_enforce_leaves_failed_server_issue_untouched_and_processes_others(self):
        beta_title = "chore(litellm): MCP tool drift on beta"
        github = FakeGitHub([{"number": 5, "title": TITLE, "body": "keep"}])
        litellm = FakeLiteLLM({OTHER_ID: ["x", "n"]}, failures={SERVER_ID: "HTTP 500"})
        code, _ = self.run_drift(self.servers(), litellm, github, mode="enforce")
        self.assertEqual(code, 1)
        titles = [c[1] for c in github.calls if c[0] == "find_issue"]
        self.assertEqual(titles, [beta_title])
        self.assertEqual(github.calls[-1][0], "create_issue")

    def test_enforce_creates_edits_noops_and_closes_per_server(self):
        servers = drift.parse_servers(
            config_doc(
                alpha=server("alpha", SERVER_ID, allowed=["a"]),
                beta=server("beta", OTHER_ID, allowed=["x"]),
                gamma=server("gamma", "33333333-3333-3333-3333-333333333333", allowed=["g"]),
            )
        )
        litellm = FakeLiteLLM({SERVER_ID: ["a", "new"], OTHER_ID: ["x"], "33333333-3333-3333-3333-333333333333": ["g", "h"]})
        gamma_body = drift.render_body("gamma", ["h"], [])
        github = FakeGitHub(
            [
                {"number": 2, "title": "chore(litellm): MCP tool drift on beta", "body": "stale text"},
                {"number": 3, "title": "chore(litellm): MCP tool drift on gamma", "body": gamma_body},
            ]
        )
        code, output = self.run_drift(servers, litellm, github, mode="enforce")
        self.assertEqual(code, 0)
        kinds = [c[0] for c in github.calls if c[0] != "find_issue"]
        self.assertEqual(kinds, ["ensure_label", "create_issue", "comment_and_close"])
        self.assertIn("alpha: issue create", output)
        self.assertIn("beta: issue close", output)
        self.assertIn("gamma: issue noop", output)

    def test_enforce_ensures_label_once_before_any_issue_call(self):
        litellm = FakeLiteLLM({SERVER_ID: ["a"], OTHER_ID: ["x"]})
        github = FakeGitHub()
        self.run_drift(self.servers(), litellm, github, mode="enforce")
        self.assertEqual(github.calls[0], ("ensure_label",))
        self.assertEqual(sum(1 for c in github.calls if c[0] == "ensure_label"), 1)

    def test_one_server_timing_out_does_not_stop_the_others(self):
        class Flaky(FakeLiteLLM):
            def list_tools(self, server_id):
                if server_id == SERVER_ID:
                    return drift.LiteLLM.list_tools(drift.LiteLLM("http://x", MASTER_KEY), server_id)
                return super().list_tools(server_id)

        handle = mock.MagicMock()
        handle.__enter__.return_value = handle
        handle.read.side_effect = TimeoutError("timed out")
        with mock.patch("urllib.request.urlopen", return_value=handle):
            code, output = self.run_drift(self.servers(), Flaky({OTHER_ID: ["x"]}))
        self.assertEqual(code, 1)
        self.assertIn("alpha: FAILED request failed: timed out", output)
        self.assertIn("beta: upstream=1", output)

    def test_unsupported_names_are_logged_as_a_count_only(self):
        litellm = FakeLiteLLM({SERVER_ID: ["a", "bad`name", "@mention"], OTHER_ID: ["x"]})
        github = FakeGitHub()
        code, output = self.run_drift(self.servers(), litellm, github, mode="enforce")
        self.assertIn("alpha: 2 names with unsupported characters left out of the issue", output)
        self.assertNotIn("beta: 0", output)
        create = [c for c in github.calls if c[0] == "create_issue"][0]
        self.assertNotIn("bad`name", create[2])
        self.assertNotIn("@mention", create[2])

    def test_single_unsupported_name_is_logged_in_the_singular(self):
        litellm = FakeLiteLLM({SERVER_ID: ["a", "@mention"], OTHER_ID: ["x"]})
        _, output = self.run_drift(self.servers(), litellm)
        self.assertIn("alpha: 1 name with unsupported characters left out of the issue", output)

    def test_github_failure_fails_that_server_only(self):
        github = FakeGitHub()
        original = github.find_issue

        def flaky(title):
            if title.endswith("alpha"):
                raise drift.ApiError("GitHub 502")
            return original(title)

        github.find_issue = flaky
        litellm = FakeLiteLLM({SERVER_ID: ["a"], OTHER_ID: ["x", "n"]})
        code, output = self.run_drift(self.servers(), litellm, github, mode="enforce")
        self.assertEqual(code, 1)
        self.assertIn("alpha: FAILED GitHub 502", output)
        self.assertEqual(github.calls[-1][0], "create_issue")


class MainTest(unittest.TestCase):
    def environ(self, **extra):
        env = {"LITELLM_URL": "http://litellm:4000", "LITELLM_MASTER_KEY": MASTER_KEY}
        env.update(extra)
        return env

    def test_unknown_mode_exits_2(self):
        out = io.StringIO()
        with redirect_stdout(out):
            self.assertEqual(drift.main(self.environ(MODE="nope")), 2)

    def test_missing_master_key_exits_2(self):
        env = self.environ(MODE="report")
        del env["LITELLM_MASTER_KEY"]
        with redirect_stdout(io.StringIO()):
            self.assertEqual(drift.main(env), 2)

    def test_enforce_without_token_exits_2(self):
        with redirect_stdout(io.StringIO()):
            self.assertEqual(drift.main(self.environ(MODE="enforce")), 2)

    def test_label_failure_aborts_enforce_before_any_issue_call(self):
        github = FakeGitHub()
        github.ensure_label = mock.Mock(side_effect=drift.ApiError("HTTP 403"))
        servers = drift.parse_servers(config_doc(alpha=server()))
        litellm = FakeLiteLLM({SERVER_ID: ["a"]})
        with redirect_stdout(io.StringIO()):
            with self.assertRaises(drift.ApiError):
                drift.run(servers, litellm, "enforce", github)
        self.assertEqual(github.calls, [])

    def test_default_mode_is_report(self):
        self.assertEqual(drift.mode_from(self.environ()), "report")

    @unittest.skipIf(yaml is None, "PyYAML not installed")
    def test_unreadable_config_exits_2(self):
        env = self.environ(MODE="report", CONFIG_FILE="/nonexistent/config.yaml")
        with redirect_stdout(io.StringIO()):
            self.assertEqual(drift.main(env), 2)


if __name__ == "__main__":
    unittest.main()
