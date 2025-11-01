# project_context.md

Spruyt-labs homelab workspace rules

## Guidelines

- This is a Talos Linux kubernetes cluster home lab.
- Talos does NOT support SSH.
- This is a baremetal home lab. No local attaching or network logging.
- Supporting cloud infra is managed by Terraform in the `infra` folder
- Talos config is in the `talos` folder
- This project is in a Visual Studio Code dev container; as such you have a terminal available with preinstalled tools such as `kubectl`, `talosctl`, `talhelper`, `github-cli` IE `gh`, `terraform` and also task files via `task`
- Because you have access to `talosctl` and `kubectl` you can query the cluster to debug and to investigate or plan for new changes. See rule `kubernetes.md` for more details.
- GitHub Actions are in `.github`
- Always consider what MCP servers are available and make sure to use them if they can enhance outcomes.
