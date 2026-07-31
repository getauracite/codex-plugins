# AuraCite Agent Hub for Codex

Connect Codex to [AuraCite](https://auracite.de) as a scoped operator: AI visibility intelligence, Google Search Console signals, project/brand/prompt configuration, Intelligence, Action Center, project memory, and spend-capped provider workflows.

The normal install path is OAuth-first. Install the plugin, sign in to AuraCite, approve scoped access, and start with read/draft tools. When you grant `mcp:write` or `mcp:spend`, Codex can request useful mutations and provider runs; AuraCite still requires a human approval quote before execution. No API key needs to be pasted into a repo, README, chat, or screenshot.

## Install From The Public Marketplace Repo

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

Then start a new Codex thread and ask:

```text
Use AuraCite Agent Hub to summarize my current AI visibility state and draft one safe next action.
```

You can also open Codex Plugins, switch to `AuraCite Plugins`, and install `AuraCite Agent Hub`.

## Sign In With AuraCite

The hosted MCP entry points to:

```text
https://auracite.de/mcp/rpc
```

Codex discovers AuraCite OAuth metadata, opens the browser, and asks you to sign in and approve the tenant, project, and scopes. The issued MCP token is scoped, revocable, rate-limited, and bound to the same server-side tenant/project/user controls as AuraCite API keys.

Start with `mcp:read`. Add `mcp:write` for project, brand, prompt, memory, Action Center, and stored-rescore operations. Add `mcp:spend` only when provider scans or AI prompt generation are needed.

## What The Plugin Can Do

- Read AI visibility signals for brands, mentions, citations, competitors, share of voice, visibility score, trends, and per-engine breakdowns.
- Read project discovery, user-landscape summaries, recent signups, Google Search Console query/page
  evidence, bounded country/device breakdowns, query trends, and the combined AI-visibility overview.
- Read AuraCite Intelligence context: freshness, refresh candidates, refresh status, opportunity briefs, and evidence summaries.
- Read Action Center handoff state and compact project-memory snapshots.
- Draft context packs, refresh plans, handoffs, and approval notes without changing production state.
- Request approval-gated project, brand, prompt, bulk-prompt, memory, Action Center, and stored-rescore writes. The server creates a pending request first; after approval the retry is quote-bound and idempotent.
- Request provider scans and AI prompt generation with explicit credit caps, optional USD caps, and server-side CostGuard enforcement.
- Guide Codex through safe AuraCite operating workflows with bundled skills.

The bundled `ai-visibility` skill helps Codex answer direct GEO and GSC questions from the `auracite`
MCP server. It is read-only and does not trigger scans, provider calls, or credit spend.

## Safety Model

Read and draft tools are the default. The local bridge uses `safe` mode by default; set `AURACITE_MCP_BRIDGE_MODE=confirmed-writes` only when the OAuth/API-key scope and human approval flow are intended.

Always blocked:

- Destructive brand deletion
- Demo-user creation
- Credit grants and other admin/billing actions
- Publishing and raw Vault file writes

Approval-gated writes require:

- `mcp:write`
- A first call with an idempotency key creates a pending server-side approval
- Tenant/project/API-key-bound quote approval
- One-use quote consumption and server-side idempotency/replay checks
- Audit events and explicit tenant/project/user scope

Provider-spend tools additionally require:

- `mcp:spend`
- Server-issued quote
- Hard `max_credits`
- Optional `max_usd`
- CostGuard enforcement
- Explicit approval before any provider call

## Manual Fallback

Use this only for CI, headless environments, or a Codex workspace where MCP OAuth is unavailable.

Create a scoped read-only Agent Hub connection in AuraCite, then set the token outside the repo:

```powershell
$env:AURACITE_MCP_TOKEN = "gp_..."
$env:AURACITE_MCP_RPC_URL = "https://auracite.de/mcp/rpc"
$env:AURACITE_MCP_BRIDGE_MODE = "safe"
```

Enable the bundled local bridge only in user/workspace Codex config:

```toml
[plugins."auracite-agent-hub".mcp_servers.auracite-jsonrpc-bridge]
enabled = true
default_tools_approval_mode = "prompt"
```

Never commit tokens or paste them into support tickets, screenshots, docs, or vault notes.

## Useful Prompts

```text
Use AuraCite Agent Hub to summarize my Intelligence freshness and list the safest next refresh candidates.
```

```text
Use AuraCite Agent Hub to read my current opportunity briefs and draft one Action Center handoff without mutating production.
```

```text
Use AuraCite Agent Hub to prepare a Context Pack for this Codex session from project status, next actions, and visibility evidence.
```

## Validate The Package

From a checkout of the marketplace repo or AuraCite monorepo:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/validate-plugin.ps1
node plugins/auracite-agent-hub/scripts/test-jsonrpc-bridge.mjs
```

Internal AuraCite operators can run production dogfood helpers in `scripts/` with temporary keys. Those helpers create, use, revoke, and verify scoped connections without printing secrets.

## Distribution

This package is ready for public repo-marketplace distribution through `getauracite/codex-plugins`.

OpenAI now provides a submission portal for the universal Plugins Directory shared by ChatGPT and Codex. AuraCite is preparing the reviewed `With MCP` plus skills submission there. The public repo marketplace remains the working install path until OpenAI approves the submission and AuraCite publishes the approved version.

## License

Proprietary - (c) AuraCite.
