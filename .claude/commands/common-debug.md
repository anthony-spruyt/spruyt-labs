---
description: Systematic debugging workflow using scientific method to isolate and fix issues
allowed-tools: Read, Glob, Grep, Bash(git:*), WebFetch, WebSearch
---

# Debugging Workflow

Debug the issue: $ARGUMENTS

## Process

### 1. Define the Problem

Answer these questions first:

- **What is the expected behavior?**
- **What is the actual behavior?**
- **Is this reproducible?** How consistently?
- **When did it start?** After what change?
- **What is the scope?** One user, all users, specific conditions?

### 2. Gather Evidence

```bash
# Check recent changes
git log --oneline -20
git diff HEAD~5

# Check for related changes
git log --all --oneline --grep="<keyword>"
```

**Collect:**

- Error messages (exact text)
- Stack traces
- Log entries around the time of failure
- Environment details (versions, config)

### 3. Form Hypotheses

Rank possible causes by likelihood:

1. **Most recent changes** - What was modified last?
2. **Related code paths** - What code is involved?
3. **External dependencies** - Did a dependency change?
4. **Environment differences** - Dev vs prod config?
5. **Data issues** - Bad input or state?

### 4. Test Systematically

**Rules:**

- Test ONE hypothesis at a time
- Make minimal changes to isolate variables
- Document each test and result
- Rollback failed attempts before trying next

**For each hypothesis:**

1. Predict what you expect to see
2. Make the smallest change to test it
3. Observe the result
4. Confirm or rule out the hypothesis

### 5. Research If Stuck

Follow research priority:

1. **Context7** - Check library docs

   ```
   resolve-library-id → query-docs
   ```

2. **GitHub Issues** - Search for similar problems

   ```bash
   gh search issues "error message" --repo org/repo
   ```

3. **WebFetch** - Official docs if URL known

4. **WebSearch** - Last resort, explain why others failed

### 6. Implement Fix

Once root cause is identified:

1. Implement the minimal fix
2. Verify the fix resolves the issue
3. Check for regressions
4. Consider adding a test to prevent recurrence

### 7. Document Findings

## Output Format

````markdown
## Debugging Report: [issue description]

### Problem Statement

- Expected: [what should happen]
- Actual: [what happens instead]
- Reproducible: [yes/no, conditions]

### Investigation

| Hypothesis | Test           | Result                |
| ---------- | -------------- | --------------------- |
| [cause 1]  | [what I tried] | Confirmed / Ruled out |
| [cause 2]  | [what I tried] | Confirmed / Ruled out |

### Root Cause

[Identified cause with evidence]

### Fix Applied

```[language]
[code or config change]
```
````

### Verification

- [ ] Fix resolves the original issue
- [ ] No regressions introduced
- [ ] Test added (if applicable)

### Prevention

[How to prevent this issue in the future]

```

## Common Debugging Techniques

**Binary search:**
- Find the commit that introduced the bug
- `git bisect start`, `git bisect bad`, `git bisect good`

**Simplify:**
- Remove components until issue disappears
- Add them back one at a time

**Compare:**
- Working vs broken environment
- Working vs broken input
- Before vs after the change

**Instrument:**
- Add logging at key points
- Use debugger breakpoints
- Monitor resource usage
```
