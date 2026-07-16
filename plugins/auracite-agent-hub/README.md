# AuraCite Agent Hub for Codex

Connect Codex to [AuraCite](https://auracite.de) AI visibility intelligence: brand mentions, citations, share of voice, visibility scores, competitors, Google Search Console signals, Intelligence freshness, opportunity briefs, Action Center handoffs, and project memory.

The normal install path is OAuth-first. Install the plugin, sign in to AuraCite, approve scoped access, and start with read-only tools. No API key needs to be pasted into a repo, README, chat, or screenshot.

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

Start with `mcp:read`. Confirmed writes and provider-spend workflows are not enabled by default.

## What The Plugin Can Do

- Read AI visibility signals for brands, mentions, citations, competitors, share of voice, visibility score, trends, and per-engine breakdowns.
- Read project discovery, user-landscape summaries, recent signups, Google Search Console query/page
  evidence, bounded country/device breakdowns, query trends, and the combined AI-visibility overview.
- Read AuraCite Intelligence context: freshness, refresh candidates, refresh status, opportunity briefs, and evidence summaries.
- Read Action Center handoff state and compact project-memory snapshots.
- Draft context packs, refresh plans, handoffs, and approval notes without changing production state.
- Guide Codex through safe AuraCite operating workflows with bundled skills.

The bundled `ai-visibility` skill helps Codex answer direct GEO and GSC questions from the `auracite`
MCP server. It is read-only and does not trigger scans, provider calls, or credit spend.

## Safety Model

Read and draft tools are the default.

Disabled by default:

- Brand/project mutation
- Bulk prompt creation
- Provider scans and provider-spend tools
- Intelligence `stored_rescore`
- Action Center status writes
- Project-memory append writes
- Admin, billing, demo-user, credit, publishing, and raw Vault file-write tools

Confirmed writes require:

- `mcp:write`
- Exact server-issued confirmation text
- Server-side idempotency/replay checks
- Audit events
- Explicit tenant/project/user scope

Provider-spend tools additionally require:

- `mcp:spend`
- Server-issued quote
- Hard `max_credits`
- Optional `max_usd`
- CostGuard enforcement
- Explicit confirmation

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

## Known Distribution Notes

This package is ready for public repo-marketplace distribution through `getauracite/codex-plugins`.

OpenAI's Codex Plugin Directory has a curated `openai-curated` channel. The public OpenAI docs currently describe repo/personal marketplaces and workspace sharing for third-party distribution; they do not document a self-service submission form for arbitrary third-party plugins. Treat OpenAI-curated listing as a separate partner/submission track, not as the guaranteed install path.

## License

Proprietary - (c) AuraCite.
