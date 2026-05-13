import type { Histogram } from "prom-client";
import type { Config } from "../config.js";
import { executeIssueRole } from "./execute-issue-role.js";
import { createRenovateRole } from "./renovate-role.js";
import { revertRole } from "./revert-role.js";
import { createSreAlertRole } from "./sre-alert-role.js";
import { sreHealthCheckRole } from "./sre-health-check-role.js";
import type { RoleDefinition } from "./types.js";
import { validateRole } from "./validate-role.js";

export class RoleRegistry {
  private roles = new Map<string, RoleDefinition>();

  register(name: string, definition: RoleDefinition): void {
    this.roles.set(name, definition);
  }

  get(name: string): RoleDefinition {
    const def = this.roles.get(name);
    if (!def) throw new Error(`Unknown role: ${name}`);
    return def;
  }

  has(name: string): boolean {
    return this.roles.has(name);
  }

  names(): string[] {
    return [...this.roles.keys()];
  }
}

export function createDefaultRegistry(
  config: Config,
  batchSizeHistogram: Histogram
): RoleRegistry {
  const registry = new RoleRegistry();
  registry.register(
    "renovate-triage",
    createRenovateRole("renovate-triage", 1_800_000)
  );
  registry.register(
    "renovate-fix",
    createRenovateRole("renovate-fix", 5_400_000)
  );
  registry.register("revert", revertRole);
  registry.register("validate", validateRole);
  registry.register("execute-issue", executeIssueRole);
  registry.register(
    "sre-alert",
    createSreAlertRole(config, batchSizeHistogram)
  );
  registry.register("sre-health-check", sreHealthCheckRole);
  return registry;
}
