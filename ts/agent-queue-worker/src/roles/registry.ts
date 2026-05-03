import type { Histogram } from "prom-client";
import type { Config } from "../config.js";
import { executeRole } from "./execute-role.js";
import { createPrRole } from "./pr-role.js";
import { createSreRole } from "./sre-role.js";
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
  registry.register("triage", createPrRole("triage", 600_000));
  registry.register("fix", createPrRole("fix", 1_800_000));
  registry.register("validate", validateRole);
  registry.register("execute", executeRole);
  registry.register("sre", createSreRole(config, batchSizeHistogram));
  return registry;
}
