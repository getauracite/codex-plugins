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

- In customer workflows, retrieve `get_customer_guidance` before any substantive
  GEO suggestion. Use only the actual question/surface/page context. Owner-only
  knowledge and unreviewed learnings are not a customer fallback.
- Tie each proposed action to a concrete customer evidence reference plus the
  applicable knowledge card ID/revision and corpus hash. State conditions not yet
  checked. If either side is missing, propose a diagnostic step and label the gap;
  do not claim the customer has a defect or that an intervention will work.
- `render_visibility_overview` renders stored metrics and a diagnostic next step.
  It deliberately does not accept arbitrary model-written recommendations or
  numerical inputs. Its knowledge panel is supporting context, not a confirmed
  customer diagnosis. Explain customized proposals in the chat with their sources.

- Pick one next action that can ship or be validated.
- Treat Visibility Intelligence as the decision layer and Action Center as the execution layer.
- If preparing an Action Center handoff, keep it draft-only unless the user explicitly confirms the mutation and the tool/API supports audit-gated writes.
- Preserve `approval_gate = human_review_required` for Intelligence handoffs.
- Include the expected measurement loop, especially primary metric and outcome windows.
- Do not trigger provider-cost, GSC, publishing, social, paid-ad, or customer-impacting actions without approval.
- Prefer stored data and screenshots before live cost-bearing provider calls.
- For public content, keep claims conservative and evidence-backed.
