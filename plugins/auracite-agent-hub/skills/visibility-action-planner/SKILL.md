---
name: visibility-action-planner
description: Use when turning AuraCite Visibility Intelligence, Opportunity Briefs, GSC, LLM Mentions, Answer Quality, or Action Center evidence into a safe next action or handoff draft.
---

# AuraCite Visibility Action Planner

## Purpose

Convert evidence into one useful next action for AI visibility/GEO work, or into a gated Action Center handoff draft.

## Inputs

Prefer direct AuraCite evidence over generic advice:

- LLM Mentions / source opportunities
- GSC index and query signals
- Answer Quality truth-source gaps
- Intelligence Center overview, Source Health, Research Readiness, and Opportunity Briefs
- Opportunity metadata: `outcome_status`, `action_handoff_state`, `action_handoff_gate`, `measurement_state`
- Evidence/provenance attached to the opportunity
- Action Center / Recommended Actions
- Public proof hub and customer-facing claims
- Recent content, social, and platform-leverage status

## Plan Shape

```markdown
## Goal
## Evidence
## Recommended Action
## Handoff Draft
## Non-Goals
## Approval Gate
## Verification
```

## Decision Rules

- Pick one next action that can ship or be validated.
- Treat Visibility Intelligence as the decision layer and Action Center as the execution layer.
- If preparing an Action Center handoff, keep it draft-only unless the user explicitly confirms the mutation and the tool/API supports audit-gated writes.
- Preserve `approval_gate = human_review_required` for Intelligence handoffs.
- Include the expected measurement loop, especially primary metric and outcome windows.
- Do not trigger provider-cost, GSC, publishing, social, paid-ad, or customer-impacting actions without approval.
- Prefer stored data and screenshots before live cost-bearing provider calls.
- For public content, keep claims conservative and evidence-backed.
