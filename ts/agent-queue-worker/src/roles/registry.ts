import type { RoleDefinition } from "./types.js";
import { createPrRole } from "./pr-role.js";
import { validateRole } from "./validate-role.js";
import { executeRole } from "./execute-role.js";
import { sreRole } from "./sre-role.js";

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

export function createDefaultRegistry(): RoleRegistry {
  const registry = new RoleRegistry();
  registry.register("triage", createPrRole("triage", 600_000));
  registry.register("fix", createPrRole("fix", 1_800_000));
  registry.register("validate", validateRole);
  registry.register("execute", executeRole);
  registry.register("sre", sreRole);
  return registry;
}
