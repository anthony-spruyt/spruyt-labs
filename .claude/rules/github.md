# GitHub Operations

> **Repository: detect owner/repo from `git remote get-url origin`**

## Tool

Use the **`gh` CLI** for all GitHub operations (issues, PRs, code search, API calls).

## Rules

1. Never output secret values from issues or PRs
2. Never close issues without validated success; if validation isn't possible, get user confirmation first
3. Agent results (validation, QA, reviews) go on the issue as comments, never into the issue body. Validators given the issue number post their own report; don't post it again
