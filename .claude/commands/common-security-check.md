---
name: security-check
description: Run security checks on staged files or specified paths for secrets and sensitive data
allowed-tools: Read, Glob, Grep, Bash(git:*)
---

# Security Check

Verify files for security issues before commit.

## Target

$ARGUMENTS (defaults to staged files if empty)

## Workflow

### 1. Identify Target Files

```bash
# If no arguments, check staged files
git diff --cached --name-only

# Or check specified paths
# $ARGUMENTS
```

### 2. Secret Pattern Detection

Search for common secret patterns:

**API Keys & Tokens**

- `api[_-]?key`
- `auth[_-]?token`
- `access[_-]?token`
- `bearer\s+[a-zA-Z0-9_-]+`
- `sk-[a-zA-Z0-9]+` (OpenAI)
- `ghp_[a-zA-Z0-9]+` (GitHub PAT)
- `AKIA[A-Z0-9]+` (AWS)

**Passwords & Credentials**

- `password\s*[:=]`
- `passwd\s*[:=]`
- `secret\s*[:=]`
- `credential`

**Private Keys**

- `-----BEGIN.*PRIVATE KEY-----`
- `-----BEGIN RSA PRIVATE KEY-----`
- `-----BEGIN OPENSSH PRIVATE KEY-----`

**Connection Strings**

- `postgres://.*:.*@`
- `mysql://.*:.*@`
- `mongodb://.*:.*@`
- `redis://.*:.*@`

### 3. Sensitive File Detection

Check for files that shouldn't be committed:

- `.env`, `.env.*` (environment files)
- `*.pem`, `*.key`, `*.p12` (certificates/keys)
- `credentials.json`, `secrets.yaml`
- `*.sops.yaml` without `sops:` metadata (unencrypted)
- `id_rsa`, `id_ed25519` (SSH keys)
- `kubeconfig`, `.kube/config`

### 4. Cross-Reference with Settings

Compare against `.claude/settings.json` deny patterns to ensure consistency.

### 5. Report Findings

## Output Format

```
## Security Check Report

### Target
[files checked]

### Findings

#### BLOCK (Must Fix)
- `path/to/file:line` - [description of secret/issue]
  Pattern matched: [pattern]
  Recommendation: [how to fix]

#### WARN (Review Needed)
- `path/to/file` - [potential issue]
  Recommendation: [what to check]

#### OK
- [count] files passed security checks

### Summary
[ ] PASSED - No secrets detected
[ ] BLOCKED - Secrets found, do not commit
[ ] REVIEW - Potential issues need verification
```

## Common Fixes

**Move to environment variables:**

```bash
# Instead of hardcoding
API_KEY="sk-abc123"

# Use environment variable
API_KEY="${API_KEY}"
```

**Use secret management:**

- SOPS for encrypted secrets in repo
- Environment variables for runtime secrets
- Secret managers (Vault, AWS Secrets Manager)

**Add to .gitignore:**

```
.env
*.pem
*.key
credentials.json
```
