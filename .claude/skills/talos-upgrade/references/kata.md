# Kata Checks

## Step 4.4a: Kata config copy check (first worker only)

`talos/patches/worker/13-tune-kata-memory.yaml` replaces the kata-containers extension's config with a full copy, so a path or option the new extension changed breaks every Kata pod. After the first worker is back:

```bash
diff <(talosctl -n <node-ip> read /usr/local/share/kata-containers/configuration.toml | grep -vE '^\s*(#|$)') \
     <(talosctl -n <node-ip> read /etc/kata-containers/configuration.toml | grep -vE '^\s*(#|$)')
```

**Good:** the only differences are `kernel_params` (our added `page_reporting.page_reporting_order=4 sysctl.vm.compaction_proactiveness=50`), `default_memory` and `reclaim_guest_freed_memory`. Anything else: fix the patch yourself and carry on with the next worker.

1. Replace the patch's `contents` with the new extension file, keeping `page_reporting.page_reporting_order=4 sysctl.vm.compaction_proactiveness=50` appended to `kernel_params`, `default_memory = 1024`, `reclaim_guest_freed_memory = true` and the patch's comments.
2. Do not apply it now (rule 10). The Phase 8 apply ships it; until then Kata pods may fail to start on upgraded workers.
3. Before Phase 8, land it by the landing rule in the skill. The apply ships the working tree, and nodes must not run config that isn't on main: the Phase 8 clean-checkout gate stops the apply until the patch is on main.

## Phase 8: Kata smoke test

Smoke-test Kata on the first worker. Kyverno forces `runAsNonRoot`, so the pod needs a non-root user:

```bash
kubectl run kata-smoke -n default --rm -i --restart=Never --image=busybox:1.37 --pod-running-timeout=3m \
  --overrides='{"spec":{"runtimeClassName":"kata","nodeSelector":{"kubernetes.io/hostname":"<first-worker>"},"securityContext":{"runAsUser":65534,"runAsGroup":65534}}}' \
  -- uname -r
```

**Good:** prints a kernel without the `-talos` suffix (the Kata guest kernel, not the host's). A stuck `ContainerCreating` or sandbox error means the Kata config is broken: run the Step 4.4a diff again, fix the patch and land it, then repeat the Phase 8 clean-checkout gate, diff and apply.
