---
name: litellm-middleware
description: Use when adding, moving, or removing a LiteLLM proxy middleware under cluster/apps/litellm/litellm/app/plugins/middleware/, or when the user asks to "add a middleware", "hook into LiteLLM requests/responses", or change what the LiteLLM pipeline runs. Not for LiteLLM model, MCP, or guardrail config in values.yaml.
argument-hint: <middleware-name>
---

# Add a LiteLLM Middleware

The layout rules live in `cluster/apps/litellm/README.md` under "Adding a middleware". Read that section first; this skill is the order of work.

## Paths

| Item           | Path (relative to `cluster/apps/litellm/litellm/app/`) |
| -------------- | ------------------------------------------------------ |
| Middleware dir | `plugins/middleware/<name>/`                           |
| Pipeline hooks | `plugins/middleware/pipeline.py`                       |
| Registry       | `plugins/middleware/registry.py`                       |
| ConfigMap      | `kustomization.yaml` (`litellm-middleware-plugin`)     |
| Pod mounts     | `values.yaml` (init container `mkdir`, `middleware-plugin` mounts) |
| Import test    | `plugins/middleware/tests/test_production_imports.py`  |

`<name>` is snake_case (`secret_masking`); the registry name is kebab-case (`secret-masking`).

## Workflow

1. **Issue.** Find or create the GitHub issue.
2. **Hook check.** Confirm `MiddlewarePipeline` in `pipeline.py` already delegates the LiteLLM hook you need. If not, add it there first, with its own test in `plugins/middleware/tests/test_pipeline.py`. LiteLLM only calls hooks the callback class defines itself, so the pipeline must define the method, not inherit it.
3. **Red.** Create `plugins/middleware/<name>/tests/test_<name>.py`. Copy the `sys.path` and fake-`litellm` setup from `secret_masking/tests/test_secret_masking.py`; import `middleware.<name>.<name>`. Run it and watch it fail.
4. **Green.** Create `<name>/__init__.py` (empty) and `<name>/<name>.py` ending in a module-level instance (`<name> = <Name>Middleware()`). Helpers used only by this middleware go in `<name>/`. No per-middleware `pyproject.toml`; test-only deps go in `plugins/middleware/pyproject.toml` (then `uv lock`).
5. **Register.** Add a `MiddlewareSpec` to `DEFAULT_MIDDLEWARE_SPECS` in `registry.py` pointing at `custom_callbacks.middleware.<name>.<name>`. Order matters: specs run top to bottom. Default to `required=False`. Add a registry test asserting the spec and its `required` value.
6. **Production import.** Add the dotted module to `test_production_dotted_imports_resolve` and add a test that it lands in `pipeline_plugin.pipeline_middleware.middlewares`.
7. **Integration test.** Add a test to `plugins/middleware/integration/test_proxy.py` that sends a real request through the proxy and asserts the middleware's effect. Extend `integration/fake_upstream.py` if the upstream must return something new. Watch it fail before step 8.
8. **Wire into the pod.** For every file in `<name>/` except tests:
   - `kustomization.yaml`: `<file>=plugins/middleware/<name>/<file>` under `litellm-middleware-plugin`. ConfigMap keys are flat, so two files with the same basename collide; rename one. Never add a second plugin ConfigMap.
   - `values.yaml`: add `/app/custom_callbacks/middleware/<name>` to the init container `mkdir`, and add a subPath mount per file plus `/app/custom_callbacks/middleware/<name>/__init__.py` (subPath `__init__.py`).
9. **Test paths.** Add `<name>/tests` to `testpaths` in `plugins/middleware/pyproject.toml`, `middleware/<name>/tests` to `plugins/pytest.ini`, and the full path to `sonar.tests` in `.sonarcloud.properties`.
10. **Verify.**

   ```bash
   task test:litellm-middleware
   task test:litellm-middleware-integration
   cd cluster/apps/litellm/litellm/app/plugins && uv run --project middleware --extra dev pytest -q
   kubectl kustomize cluster/apps/litellm/litellm/app > /dev/null
   ```

11. **Docs.** If anything is non-obvious (an upstream workaround, a removal condition, a failure mode), add a `###` section to `cluster/apps/litellm/README.md`.
12. **Ship.** qa-validator, commit, push, then cluster-validator. After rollout, check the litellm pod logs for `failed to load <name> middleware`.

## Gotchas

| Symptom                                       | Cause                                                                 |
| --------------------------------------------- | --------------------------------------------------------------------- |
| `ModuleNotFoundError` in pod, tests pass      | Missing `mkdir`, `__init__.py` mount, or ConfigMap entry               |
| Hook never fires in pod                       | Pipeline doesn't define that hook, or the spec isn't in the registry   |
| Optional middleware silently absent           | Import failed; `required=False` only logs a warning                    |
| New pod never Ready after rollout             | A `required=True` middleware failed to import (by design)             |
| Tests pass alone, fail together               | Module cache: pop the `middleware.<name>.*` keys from `sys.modules` in the fixture |
| Integration: `LiteLLM container exited during startup` | Import error in the pod layout; the failure message includes the proxy log |
| Unit green, integration red                   | Real LiteLLM calls the hook differently from the stub; trust integration |

## Removing a middleware

Reverse steps 5–9: drop the spec, ConfigMap entries, `mkdir` dir, mounts, test paths and the README section, then delete `<name>/`.
