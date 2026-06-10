---
name: agent-session-sync
description: Use when finishing or reviewing an AuraCite Codex session and the work should be summarized into AuraCite's action, evidence, and memory layer.
---

# AuraCite Agent Session Sync

## Purpose

Turn agent work into durable AuraCite operating context without leaking secrets or raw logs.

## Workflow

1. Identify the task cluster, scope, outcome, files changed, verification run, blockers, and next decision.
2. Separate facts from recommendations.
3. Do not store secrets, credentials, API keys, private invite links, private customer data, or raw session transcripts.
4. Prefer compact entries in the relevant repo doc or vault note instead of duplicating the entire chat.
5. For production-facing work, include the smoke-test status and whether cost-bearing actions were avoided or explicitly approved.
6. If the session touched Visibility Intelligence or Action Center, capture the handoff and measurement state.

## Output Shape

```markdown
## Agent Session Sync
Date:
Task cluster:
Scope:
Outcome:
Evidence:
Intelligence/Action link:
Handoff state:
Measurement state:
Verification:
Open risks:
Next action:
```

## Guardrails

- Never claim deploy or production verification unless it actually ran.
- Never summarize private credentials or secret-bearing screenshots.
- If the session produced an approval-gated draft, say where the approval gate lives.
- For confirmed writes, include the audit event or write identifier when available.
- For Intelligence handoffs, preserve `human_review_required` unless a later audited workflow changed it.
