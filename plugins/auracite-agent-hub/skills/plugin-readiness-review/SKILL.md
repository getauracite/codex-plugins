---
name: plugin-readiness-review
description: Use when reviewing the AuraCite Codex plugin or marketplace package before local, workspace, repo, or future public distribution.
---

# AuraCite Plugin Readiness Review

## Purpose

Check whether the Codex plugin is safe, installable, and honest about what is live.

## Checklist

- `plugins/auracite-agent-hub/.codex-plugin/plugin.json` is valid JSON and has no TODO placeholders.
- `.agents/plugins/marketplace.json` points to the plugin with `policy.installation` and `policy.authentication`.
- Skills have clear triggers and do not over-promise live tool access.
- MCP config is either working and authenticated, or disabled with a clear explanation.
- Mutating, cost-bearing, external, admin, or bulk tools are approval-gated or disabled.
- Read-only workflows are separated from draft-only workflows and confirmed writes.
- Intelligence refresh controls are honest: safe tools may inspect freshness and draft plans; `trigger_intelligence_refresh` is confirmed-write only and currently limited to `stored_rescore`.
- Intelligence, Action Center, Vault/DB, and Codex plugin responsibilities are documented.
- Action handoffs preserve `human_review_required` until a confirmed write path changes state.
- Tool results, logs, screenshots, and Vault notes do not contain secrets.
- Tenant, user, and project scope are explicit for every agentic workflow.
- Confirmed writes require audit trail, idempotency, and an exact human confirmation contract.
- Privacy/terms URLs are real and public.
- README distinguishes the live repo marketplace from the review-gated universal Plugins Directory.
- OpenAI submission materials include five positive and three negative reviewer cases.
- Production MCP tools expose accurate read-only, destructive, and open-world annotations.
- Reviewer credentials and domain-verification tokens are never committed to the plugin repo.

## Verdict Format

```markdown
## Verdict
Ready / ready for internal dogfood / blocked for public distribution.

## Findings

## Required Before Public

## Agentic BI Phase Verdict
Read-only:
Draft-only:
Confirmed writes:
Governance:
```
