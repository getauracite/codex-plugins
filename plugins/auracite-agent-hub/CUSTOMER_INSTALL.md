# AuraCite Agent Hub Customer Install Guide

Status: public repo-marketplace and trusted-pilot guide
Last updated: 2026-06-10

## Purpose

AuraCite Agent Hub lets Codex read and operate AuraCite AI Visibility Intelligence, opportunity briefs, Action Center handoffs, project configuration, project-memory entries, and the compact Agent Hub timeline. It can prepare drafts and request useful writes or provider runs while production-changing actions stay behind explicit server-side approval and scoped authorization.

## Prerequisites

- Codex with plugin installation enabled.
- An AuraCite account with access to the intended tenant and project.
- Browser access for the OAuth consent flow.
- PowerShell and Node.js only if you want to run local validation helpers.

Never paste API keys, OAuth tokens, cookies, or screenshots containing secrets into the repo, vault, chat logs, support tickets, or public docs.

## Public Codex Marketplace Repo Install

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

Then start a new Codex thread and ask:

```text
Use AuraCite Agent Hub to summarize my current AI visibility state and draft one safe next action.
```

In the Codex app, you can also open Plugins, switch to `AuraCite Plugins`, and install `AuraCite Agent Hub`.

## OAuth-First Connection

The default plugin entry uses:

```text
https://auracite.de/mcp/rpc
```

Codex discovers AuraCite OAuth metadata, opens AuraCite in the browser, and asks the user to sign in and approve the tenant, project, and scopes. The token is scoped, revocable, rate-limited, and backed by AuraCite's MCP key store.

Start pilots with `mcp:read`.

Use `mcp:write` for project, brand, prompt, memory, Action Center, and stored-rescore operations. The first call creates a pending approval; after a project member approves it, Codex retries with the one-use quote and idempotency key.

Use `mcp:spend` only for a scheduled cost-bearing run with a server quote, required `max_credits`, optional `max_usd`, CostGuard, and explicit confirmation.

`mcp:admin` is not issued through OAuth.

## First Safe Test

Ask Codex:

```text
Use AuraCite Agent Hub to read my project timeline, Intelligence freshness, and current opportunity briefs. Do not mutate production.
```

Expected behavior:

- Read-only tools work after OAuth.
- Draft tools can create context packs, refresh-plan drafts, handoff drafts, and approval-note drafts.
- Safe mode keeps all mutations and provider-spend tools unavailable. Confirmed-writes mode exposes the useful write and spend tools, while AuraCite still blocks execution until the server-side approval quote is approved.

## Manual Fallback

Use this only for CI, headless machines, or a Codex workspace where MCP OAuth is unavailable.

Create a read-only Agent Hub connection in AuraCite and set the token outside the repo:

```powershell
$env:AURACITE_MCP_TOKEN = "gp_..."
$env:AURACITE_MCP_RPC_URL = "https://auracite.de/mcp/rpc"
$env:AURACITE_MCP_BRIDGE_MODE = "safe"
```

Enable the local bridge only in user/workspace Codex config:

```toml
[plugins."auracite-agent-hub".mcp_servers.auracite-jsonrpc-bridge]
enabled = true
default_tools_approval_mode = "prompt"
```

Safe mode exposes read and draft-only tools. Confirmed-writes mode (`AURACITE_MCP_BRIDGE_MODE=confirmed-writes`) exposes useful writes and spend tools, but a `mcp:write`/`mcp:spend` scope or bridge mode is never approval by itself: the server creates a tenant/project/API-key-bound pending quote, requires approval, consumes it once, and enforces idempotency. Destructive/admin tools (`delete_brand`, `create_demo_user`, `add_credits`) stay disabled through the bridge in every mode. Cost-bearing runs (`trigger_scan`, `generate_ai_prompts`) additionally require `mcp:spend`, a server-created execution quote approved once in AuraCite, a max credit cap, optional USD cap, and CostGuard.

Run the fallback health check:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/agent-hub-health-check.ps1
```

Revoke temporary keys after the session.

## Package Validation

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/validate-plugin.ps1
node plugins/auracite-agent-hub/scripts/test-jsonrpc-bridge.mjs
```

Internal AuraCite operators can use the production dogfood helpers in `scripts/`; they create temporary scoped keys, run bounded checks, revoke the keys, and verify failed access after revocation without printing secrets.

## Pilot Exit Criteria

- The plugin installs from `getauracite/codex-plugins`.
- OAuth succeeds without asking the user to paste a token.
- Read-only Intelligence, project status, and timeline tools return useful context.
- Draft tools produce useful handoff material without mutating production.
- Admin/destructive tools remain unavailable in every mode; safe mode hides all writes and spend tools by default.
- The user can revoke the connection and the plugin fails closed afterward.
- Feedback is captured as concrete backlog items.

## Support Notes

For issues, capture only redacted diagnostics:

- Codex app/CLI/IDE surface.
- Plugin version.
- Install path.
- OAuth vs. manual fallback.
- Tool name.
- Redacted error text.
- Whether mutation or provider spend was expected.
- Whether the connection was revoked after the session.
