# AuraCite Agent Hub for Codex

Connect Codex to [AuraCite](https://auracite.de) AI visibility intelligence: brand mentions, citations, share of voice, visibility scores, competitors, Google Search Console evidence, Intelligence freshness, opportunity briefs, Action Center handoffs, and project memory.

The normal install path is OAuth-first: install the plugin, sign in to AuraCite, approve scoped access, start with read-only tools. No API key needs to be pasted into a repo, README, chat, or screenshot.

## Install (two commands)

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

Then start a new Codex thread and ask:

```text
Use AuraCite Agent Hub to summarize my current AI visibility state and draft one safe next action.
```

You can also open Codex Plugins, switch to `AuraCite Plugins`, and install `AuraCite Agent Hub` from there.

## Sign in with AuraCite

The hosted MCP entry points to `https://auracite.de/mcp/rpc` (Streamable HTTP, JSON-RPC 2.0). Codex discovers the AuraCite OAuth metadata, opens the browser, and asks you to sign in and approve tenant, project, and scopes. The issued MCP token is scoped, revocable, rate-limited, and bound to the same server-side tenant/project/user controls as AuraCite API keys.

Start with `mcp:read`. Confirmed writes and provider-spend workflows are not enabled by default.

## What the plugin can do

Configured catalog: 47 operator tools, of which 36 are read/draft tools. Availability in an already-connected client depends on refreshing its tool catalog.

Reads (default, `mcp:read`):

- Evidence-grade AI visibility KPIs via `get_visibility_kpis` (`7d`/`30d`/`90d`): visibility, recommendation rate, share of voice, with period, `data_as_of`, denominator and explicit `not_available` reasons. Branded prompts stay separate under `brand_control`.
- Further visibility signals: brands, mentions, citations, competitors, composite score, trends, per-engine breakdowns, brand comparison.
- AI-crawler access: which bots fetch which of your pages.
- Google Search Console: query and per-page evidence, bounded country and device breakdowns, query trends.
- AuraCite Intelligence: freshness, refresh candidates, refresh status, opportunity briefs, evidence summaries.
- Action Center handoff state and compact project-memory snapshots.

Drafts (no production state changes):

- Context packs, intelligence refresh plans, action handoffs, and approval notes, marked as read-only drafts with `human_review_required`.

Writes (only with `mcp:write` and approval):

- Project, brand, prompt, memory, Action Center, and stored-rescore writes. The first call creates a pending approval bound to tenant, project, and API key; the approved retry is one-use and idempotent.

Spend (only with `mcp:spend` and hard caps):

- Provider scans and AI prompt generation, with a server-issued quote, a required max credit cap, an optional USD cap, and CostGuard enforcement.

## Safety model

Read and draft tools are the default. Disabled or blocked in every mode:

- Admin, billing, credit-grant, demo-user, publishing, and raw Vault-file writes.
- Platform-wide observability tools (`summarize_user_landscape`, `list_recent_signups`): blocked since v0.11.3 after the production server reclassified them to admin scope.
- Provider scans and spend tools without `mcp:spend`, quote, and caps.

Confirmed writes require `mcp:write`, an approval in AuraCite (one-use, bound to tenant, project, and API key), server-side idempotency and replay checks, audit events, and explicit tenant/project/user scope. Tenant and project context is injected from the verified credential and overrides caller-supplied IDs.

## Manual fallback (local bridge)

Only for CI, headless environments, or workspaces where MCP OAuth is unavailable. Create a scoped read-only Agent Hub connection in AuraCite, set the token outside the repo:

```powershell
$env:AURACITE_MCP_TOKEN = "gp_..."
$env:AURACITE_MCP_RPC_URL = "https://auracite.de/mcp/rpc"
$env:AURACITE_MCP_BRIDGE_MODE = "safe"
```

Enable the bundled local bridge only in user or workspace Codex config:

```toml
[plugins."auracite-agent-hub".mcp_servers.auracite-jsonrpc-bridge]
enabled = true
default_tools_approval_mode = "prompt"
```

Safe mode exposes read and draft tools only. Never commit tokens or paste them into tickets, screenshots, docs, or vault notes.

## Useful prompts

```text
Use AuraCite Agent Hub to summarize my Intelligence freshness and list the safest next refresh candidates.
```

```text
Use AuraCite Agent Hub to read my current opportunity briefs and draft one Action Center handoff without mutating production.
```

```text
Use AuraCite Agent Hub to prepare a Context Pack for this Codex session from project status, next actions, and visibility evidence.
```

## Validate the package

From a checkout of this repo or the AuraCite monorepo:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/validate-plugin.ps1
node plugins/auracite-agent-hub/scripts/test-jsonrpc-bridge.mjs
```

## Changelog

See [CHANGELOG.md](./CHANGELOG.md). Current version: 0.11.4.

## Support and legal

- Website: https://auracite.de
- Support: hello@auracite.de
- Privacy: https://auracite.de/privacy · Terms: https://auracite.de/terms · Impressum: https://auracite.de/impressum

## License

Proprietary, (c) AuraCite. See [LICENSE](./LICENSE).
