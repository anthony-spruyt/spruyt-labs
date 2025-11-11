# user_context7_libraries.md

Context7 usage workflow for Spruyt-labs contributors working inside the homelab repository.

## Before using Context7 tools

- Review the approved library catalog in [`context7-libraries.json`](../context7-libraries.json:1) to identify an existing entry that covers your topic.
- Confirm the catalog entry contains the documentation or API details you need before invoking any tools.
- Note the library identifier, source description, and any version information that appears in the catalog.

## When the catalog already covers your need

1. Use the information from [`context7-libraries.json`](../context7-libraries.json:1) directly or issue `get-library-docs` for deeper excerpts.
2. Record the library ID, version (if provided), and relevant citation details in your working notes, pull request description, or runbook draft.
3. Mention how the retrieved material informed your change (e.g., field defaults, API semantics, upgrade procedure).

## When the required library is missing or outdated

1. Run `resolve-library-id` with a precise description of the documentation you need.
2. If `resolve-library-id` returns no match, escalate to the documentation governance contact listed in [`project_context.md`](project_context.md:1) and describe the gap.
3. Once a new library is added, update your worklog with the new ID and any prerequisites uncovered during the search.

## Documenting citations and MCP usage

- Capture the tool used (`resolve-library-id`, `get-library-docs`, etc.), timestamp, and output summary in your change notes.
- Include links or excerpts where practical so reviewers can follow the same trail.
- Call out any assumptions you made when interpreting the documentation, especially when deviating from defaults.

## After your change

- Ensure the relevant rule or runbook references the same library ID so future contributors reuse consistent sources.
- If you discovered inaccuracies or stale references, open an issue or submit a follow-up change to update [`context7-libraries.json`](../context7-libraries.json:1) and the associated guidance.
