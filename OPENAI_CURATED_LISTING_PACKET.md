# OpenAI Universal Plugins Directory Submission Packet

Status: preparation in progress; not yet submitted
Updated: 2026-07-31
Plugin version: `0.11.3`
Submission type: `With MCP` plus bundled skills
Public repository: https://github.com/getauracite/codex-plugins

## Listing

- Name: `AuraCite Agent Hub`
- Developer: `AuraCite`
- Category: `Productivity`
- Website: https://auracite.de
- Support: https://github.com/getauracite/codex-plugins/issues
- Privacy: https://auracite.de/privacy
- Terms: https://auracite.de/terms
- Repository: https://github.com/getauracite/codex-plugins

Short description:

> Operate AuraCite from Codex with scoped reads, approved writes, and spend-capped workflows.

Long description:

> AuraCite Agent Hub connects ChatGPT and Codex to AuraCite AI Visibility Intelligence, Google Search Console evidence, project configuration, Action Center, and project memory. OAuth binds access to the selected AuraCite tenant, project, user, and scopes. Read and draft workflows are the safe default. Data-changing actions require a server-issued approval, human approval in AuraCite, one-use consumption, audit, and idempotency. Provider runs additionally require explicit credit and optional USD caps plus CostGuard. Destructive administration, credit grants, demo-user creation, publishing, and raw Vault-file writes are not exposed by the plugin.

## MCP Submission

- URL type: `Universal`
- Production MCP URL: `https://auracite.de/mcp/rpc`
- Authentication: OAuth 2.0 authorization code with PKCE S256
- OAuth resource: `https://auracite.de/mcp/rpc`
- Scopes: `mcp:read`, `mcp:write`, `mcp:spend`
- Challenge base URL: `https://auracite.de`
- Challenge path: `/.well-known/openai-apps-challenge`
- Custom UI: none
- Content security policy: not applicable; plugin has no MCP UI component

The portal-issued domain token must be served as the only response body at the challenge path. Never commit the token to this repository.

## Skills Bundle

Upload the final plugin bundle containing:

- `agent-session-sync`
- `agentic-bi-operator`
- `ai-visibility`
- `plugin-readiness-review`
- `visibility-action-planner`

## Starter Prompts

1. `Compare my AI visibility evidence with Google Search Console performance.`
2. `Review AuraCite Intelligence opportunities and prepare a gated Action Center handoff draft.`
3. `Build an AuraCite Context Pack from Intelligence evidence and project memory.`

## Authentication And Safety

Default reviewer path uses `mcp:read`. Optional mutation review uses `mcp:write` in a dedicated reviewer project.

All remote writes require:

- tenant/project/user binding from authenticated server context
- a fresh idempotency key
- a server-created pending approval quote
- human approval in AuraCite `/approvals`
- one-use quote consumption and replay-safe response
- audit event

Provider calls additionally require `mcp:spend`, `max_credits`, optional `max_usd`, CostGuard, and explicit human approval. Reviewer tests must not perform paid provider calls unless OpenAI specifically requests one and AuraCite separately authorizes a bounded test.

Always unavailable through the public plugin:

- destructive brand deletion
- demo-user creation
- credit grants and other admin/billing actions
- public publishing
- raw Vault-file writes

## Reviewer Account

Provide a dedicated production reviewer account only through the OpenAI submission portal.

Requirements:

- no MFA, SMS, or email-confirmation step during review
- member of one isolated reviewer tenant/project
- deterministic fixture data for all positive read cases
- enough product access for read cases
- `mcp:write` only if the approved-write case is included
- no `mcp:spend` by default
- credentials rotated or revoked after review

Never place credentials, tenant IDs, project IDs, tokens, or private links in Git, release notes, screenshots, or this packet.

## Tool Annotation Contract

- Pure reads and deterministic drafts: `readOnlyHint=true`, `destructiveHint=false`, `openWorldHint=false`.
- Private create/append/status writes: `readOnlyHint=false`, `destructiveHint=false`, `openWorldHint=false`.
- Stored rescore, provider spend, deletion, and irreversible admin value changes: `readOnlyHint=false`, `destructiveHint=true`, `openWorldHint=false`.
- No submitted tool publishes content or changes publicly visible internet state.

Production scan evidence must confirm these values before submission.

## Release Notes

Initial public-directory submission of AuraCite Agent Hub `0.11.3`.

The plugin combines OAuth-authenticated AuraCite MCP tools with five evidence-first operating skills. It exposes scoped AI-visibility, Google Search Console, Intelligence, Action Center, and project-memory reads and drafts by default. Optional private writes use pending server quotes, human approval, audit, one-use consumption, and idempotency. Provider workflows additionally require hard credit/USD caps and CostGuard. Destructive administration, credit grants, demo-user creation, publishing, and raw Vault-file writes remain unavailable.

## Availability

Country/region selection requires final publisher decision in the portal. Select only regions covered by AuraCite support, legal terms, and production operations. Do not infer global availability from repository access.

## Review Cases And Gates

- Review cases: [`OPENAI_SUBMISSION_TEST_CASES.md`](OPENAI_SUBMISSION_TEST_CASES.md)
- Launch gates: [`OPENAI_SUBMISSION_CHECKLIST.md`](OPENAI_SUBMISSION_CHECKLIST.md)

## Public Install While Review Is Pending

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

Repo-marketplace availability is not evidence of OpenAI review or universal-directory publication.
