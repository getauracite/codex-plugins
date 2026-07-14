---
name: agentic-bi-operator
description: Use when operating AuraCite as an Agentic BI OS across Visibility Intelligence, Action Center, Vault/DB memory, and Codex work.
---

# AuraCite Agentic BI Operator

## Purpose

Use Codex as the agentic operator and synchronization layer for AuraCite's Visibility Intelligence, Action Center, and memory/evidence systems.

The goal is not to create another UI. The goal is to move verified context, opportunity signals, handoff drafts, approvals, implementation outcomes, and measurement evidence between product layers without breaking governance.

## Product Map

- Visibility Intelligence: signal and decision layer.
- Action Center: execution layer.
- Vault/DB: memory and evidence layer.
- Codex plugin: agentic operator and synchronization layer. Prefer the local stdio JSON-RPC bridge to the hosted `/mcp/rpc` endpoint until SSE is proven end to end.

## Phase 1 - Read-Only

Use this phase by default.

Read only:

- Intelligence Overview, including Source Health, Opportunity Scoring, Research Readiness, Import Readiness, Evidence, and Provenance.
- Intelligence freshness, refresh candidates, refresh status, and safe refresh-plan drafts.
- Opportunity Briefs and their `research_metadata`.
- Existing Action Center handoffs or recommendations.
- Relevant Vault notes, especially Next Actions, Project Status, Changelog, and user/business context.

Bridge default:

- `AURACITE_MCP_BRIDGE_MODE=safe`
- Read/draft tools only.
- No provider-cost, destructive, admin, bulk, or raw Vault-write tools.

Required output:

- Scope: tenant, project, actor/user when available, and environment.
- Evidence summary with source references.
- Opportunity shortlist with score, confidence, `outcome_status`, `action_handoff_state`, `action_handoff_gate`, and `measurement_state`.
- Stated limits: what was not read, what is stale, and what would require approval.

## Phase 2 - Draft-Only

Use this when the user wants Codex to prepare work, not execute it.

Allowed draft artifacts:

- Context Pack draft.
- Intelligence Refresh Plan draft.
- Action Handoff draft.
- Approval note.
- Implementation proposal.
- Measurement plan.
- Vault memory update draft.

Draft-only means no production mutation, no provider-cost call, no external publishing, no customer-impacting change, and no status transition.

Every Action Handoff draft must carry:

- `approval_gate = human_review_required`
- `source = intelligence`
- `source_view = visibility_intelligence_center`
- `tenant_id`
- `project_id`
- `opportunity_id`
- `recommended_action`
- evidence summaries
- measurement plan
- explicit caveats

## Phase 2.5 - Direct Config Writes (zero-touch)

`create_project`, `add_prompt`, `add_brand`, `bulk_add_prompts` are free, reversible config writes.
AuraCite does **not** gate them with a platform approval quote or an idempotency check (unlike Phase
3 below) — a valid `mcp:write` call executes immediately. `list_projects` is a read, available in
every bridge mode.

Because there is no platform-side confirmation gate, the confirmation checkpoint is this
conversation: only call these after the user has explicitly asked for the specific project/prompt/
brand to be created in this turn. Do not call them speculatively or as a side effect of a read/draft
request. State what was created and its ID after the call.

Bridge requirement: `AURACITE_MCP_BRIDGE_MODE=confirmed-writes` and an API key scoped for `mcp:write`.

## Phase 3 - Confirmed Writes

Use only after the user explicitly approves the specific write and the API/tool contract supports the confirmation gate.

Confirmed writes may include:

- Promote an Intelligence handoff to an Action Center item.
- Update Action status.
- Write outcome measurement back to Intelligence.
- Trigger `stored_rescore` for Intelligence opportunities after exact confirmation. This recomputes from already-stored rollups only; source-data syncs remain source-specific approval/cost/import workflows.
- Update durable Vault/DB memory.

Codex bridge requirement:

- Set `AURACITE_MCP_BRIDGE_MODE=confirmed-writes`.
- Use an API key scoped for `mcp:write`.
- Keep the plugin MCP server approval mode prompting before the call.

Before a confirmed write, verify:

- Human confirmation names the specific mutation.
- Tenant, user, and project scope are explicit.
- The tool/API records an audit event.
- The request has an idempotency key when repeat submission is possible.
- Tool results are secret-redacted.
- Cost-bearing or external effects are separately confirmed.

If any check is missing, stop at a draft or confirmation request.

## Output Shapes

### Context Pack

```markdown
## Scope
Tenant:
Project:
Actor:
Environment:

## Intelligence Signals

## Opportunity Brief

## Evidence And Provenance

## Action Center Context

## Vault Context

## Open Risks

## Draft-Only Next Step
```

### Action Handoff Draft

```markdown
## Handoff Draft
Source: intelligence
Gate: human_review_required
Opportunity:
Recommended action:
Evidence:
Measurement:
Caveats:
Confirmation needed:
```

### Confirmed Write Request

```markdown
## Confirmed Write Check
Mutation:
Tenant:
Project:
Actor:
Idempotency key:
Audit event:
Expected result:
Rollback/recovery:
```

## Guardrails

- Never put secrets, API keys, passwords, OAuth tokens, cookies, private invite links, or raw secret-bearing screenshots in tool results, logs, Vault notes, or plugin files.
- Treat server-side tenant/user/project scope as authoritative; never infer scope from user-visible copy alone.
- Read-only tool results may inform recommendations, but recommendations are not approval.
- For public claims, use conservative wording tied to captured evidence.
