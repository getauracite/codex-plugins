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
7. For a GEO/SEO decision, preserve knowledge card IDs/versions and `corpus_hash`, applicability,
   source freshness and the existing action/measurement references. Store customer-specific evidence
   only in its existing project scope. Propose generalized learnings through the canonical
   `docs/GEO_KNOWLEDGE_BASE.md` lifecycle; never promote an observation or copy a corpus on sync alone.

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
Knowledge references (IDs/versions/corpus_hash):
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

## Direct learning capture across sessions

On an explicit request to remember or update a GEO learning, use `search_geo_learnings` first to find an existing entry. This live owner-only inbox complements the curated corpus; it is not a replacement for reviewed cards or a task/CRM ledger. No credentials or private customer data belong here.

Use `save_geo_learning` with a stable UUID, `expected_revision` (0 for creation), title, body, source/session reference, status `unreviewed`, and a fresh request_key. Updates reuse the ID and latest revision; retries reuse the identical request and key. A revision conflict requires a fresh read and reconciliation, never a blind overwrite. Saving cannot mark evidence validated. Archive with status `archived`; history is retained.

Read the ID back with `search_geo_learnings` before claiming success. Report ID and revision. New sessions search this inbox alongside `search_geo_knowledge`/the canonical CLI. Unreviewed observations stay unreviewed; archived entries are not active advice. Changes are immediately visible without deployment. A read-only connection cannot save: report the missing write scope, never substitute a local note and claim shared persistence.
