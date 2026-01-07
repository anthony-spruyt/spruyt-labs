# Conventional Commits and Naming

This repository follows [Conventional Commits](https://www.conventionalcommits.org/) for all commits, issues, and pull requests.

## Format

```text
<type>(<scope>): <description>
```

- **type**: Category of change (required)
- **scope**: Component affected (optional but recommended)
- **description**: Short summary in imperative mood (required)

## Valid Types

| Type       | Description                                |
| ---------- | ------------------------------------------ |
| `feat`     | New feature or functionality               |
| `fix`      | Bug fix                                    |
| `docs`     | Documentation changes                      |
| `style`    | Code style (formatting, whitespace)        |
| `refactor` | Code restructuring without behavior change |
| `test`     | Adding or updating tests                   |
| `chore`    | Maintenance tasks                          |
| `ci`       | CI/CD pipeline changes                     |
| `build`    | Build system or dependencies               |
