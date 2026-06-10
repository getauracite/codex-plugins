# OpenAI Curated Listing Packet - AuraCite Agent Hub

Status: ready for partner/submission contact  
Prepared: 2026-06-10  
Plugin version: `0.8.1`  
Public repository: https://github.com/getauracite/codex-plugins

## Listing

Name: AuraCite Agent Hub

Developer: AuraCite

Category: Productivity

Short description:

> Read AuraCite AI visibility data and prepare safe action handoffs from Codex.

Long description:

AuraCite Agent Hub connects Codex to AuraCite's AI Visibility Intelligence, Action Center handoffs, project memory, and evidence-backed operating rules. It uses the hosted OAuth-capable MCP JSON-RPC endpoint at `https://auracite.de/mcp/rpc` by default, so users sign in to AuraCite and approve scoped access instead of pasting API keys. Safe read and draft tools are exposed for brand visibility, mentions, citations, share of voice, Intelligence freshness, opportunity briefs, Action Center handoffs, compact project timelines, context-pack drafts, refresh-plan drafts, and approval-note drafts. Mutating, cost-bearing, admin, bulk, publishing, and raw Vault-write tools stay disabled by default.

## Public Install Path

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

Marketplace source: `auracite-marketplace`  
Plugin ID: `auracite-agent-hub@auracite-marketplace`

## URLs

- Website: https://auracite.de
- Public repo: https://github.com/getauracite/codex-plugins
- Privacy policy: https://auracite.de/privacy
- Terms: https://auracite.de/terms
- Hosted MCP endpoint: https://auracite.de/mcp/rpc

## User Value

AuraCite helps teams understand and improve how AI engines mention, cite, rank, and describe their brand. The Codex plugin lets a user bring that visibility context into an agentic coding or operating session and turn evidence into safe next actions without switching tools or copying API keys into prompts.

Primary use cases:

- Summarize brand AI visibility, share of voice, mentions, citations, and competitor context.
- Inspect Intelligence freshness and draft a safe refresh plan.
- Review opportunity briefs and draft an Action Center handoff.
- Build a compact AuraCite Context Pack for a Codex session.
- Review a Codex session and record follow-up recommendations through guarded workflows.

## Auth And Safety Model

Normal install is OAuth-first. Users sign in to AuraCite and approve scoped access.

Defaults:

- `mcp:read` for read-only intelligence and draft workflows.
- No provider-spend workflows by default.
- No raw Obsidian Vault file writes.
- No admin, billing, demo-user, credit, publishing, or bulk mutation tools by default.

Confirmed writes require:

- `mcp:write`
- Exact server-issued confirmation text
- Server-side idempotency and replay checks
- Audit events
- Explicit tenant/project/user scope

Provider-spend tools additionally require:

- `mcp:spend`
- Server-issued quote
- Hard `max_credits`
- Optional `max_usd`
- CostGuard enforcement
- Explicit confirmation

## Verification Evidence

Public repo-marketplace install:

- GitHub repo is public: `getauracite/codex-plugins`
- Default branch: `main`
- Public install commands tested from a clean Codex home.
- Installed plugin version: `0.8.1`

Package checks:

- `plugins/auracite-agent-hub/scripts/validate-plugin.ps1`
- `plugins/auracite-agent-hub/scripts/test-jsonrpc-bridge.mjs`

Production app checks:

- AuraCite `/agent-hub` production install flow shows both public Codex CLI commands.
- Desktop and mobile authenticated smoke passed.
- Runtime console and failed-request checks passed.
- Old slash-command install copy was absent.
- No fallback API-key create/revoke action was triggered during the install-copy smoke.
- No provider-cost, DataForSEO, LLM, or GSC action was triggered.

## OpenAI Documentation Alignment

The public OpenAI Codex docs describe:

- Plugins bundle skills, app integrations, and MCP servers for Codex.
- Plugins can be shared through marketplace sources such as repo marketplaces.
- A Codex marketplace file lives at `$REPO_ROOT/.agents/plugins/marketplace.json` for repo-scoped catalogs.
- `codex plugin marketplace add owner/repo` installs and tracks a marketplace source.
- The Codex app also has a curated OpenAI plugin directory.

As of 2026-06-10, the public docs do not document a self-service submission form for arbitrary third-party plugins to the OpenAI-curated directory. This packet is therefore prepared for the partner/submission-contact path, while the public repo marketplace remains the live install path.

Relevant official docs:

- https://developers.openai.com/codex/plugins
- https://developers.openai.com/codex/plugins/build

## Submission Notes

Recommended partner-contact message:

```text
Hello OpenAI Codex team,

AuraCite would like to submit AuraCite Agent Hub for review for the OpenAI-curated Codex Plugin Directory.

The plugin is already available through a public Codex repo marketplace:
https://github.com/getauracite/codex-plugins

Install:
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace

AuraCite Agent Hub connects Codex to AuraCite AI Visibility Intelligence and Action Center workflows through an OAuth-first hosted MCP endpoint. Default workflows are read/draft-only. Confirmed writes and spend tools are gated by explicit scopes, server-issued confirmations, idempotency, audit events, CostGuard, and credit/USD caps.

We can provide a short demo video, screenshots, security notes, and production smoke evidence on request.
```

Recommended attachments for a private submission thread:

- One short install/use demo video.
- One redacted screenshot of the Codex plugin listing.
- One redacted screenshot of the AuraCite OAuth/install flow.
- This packet.

