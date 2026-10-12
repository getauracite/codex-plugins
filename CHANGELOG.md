# Changelog

## v0.11.5 - 2026-10-12

### Changed

- `get_project_status`, `get_vault_next_actions`, `get_recent_changelog` and `get_agent_hub_timeline` are removed from hosted `enabled_tools` and the safe bridge allowlist. They read a snapshot of AuraCite's own development state, the same for every caller, and AuraCite PR #198 made them operator-only (`mcp:admin`). A customer key now gets a refusal instead of AuraCite's dev changelog.
- Project context comes from `list_project_memory_entries` (tenant-scoped). OpenAI test case P4, the workspace guide and the smoke/dogfood scripts use it.
- `validate-plugin.ps1` lists the four tools as stale. Tool counts are 43/32.

### Release notes

- Ship together with AuraCite PR #198. Reconnect the ChatGPT connector or start a new session to refresh a pinned tool catalog.

## v0.11.4 - 2026-10-10

### Added

- Read-only `get_visibility_kpis` in both OAuth-hosted enabled tools and local safe JSON-RPC bridge allowlist.
- Evidence-first skill guidance for `7d`, `30d`, `90d`, `measured`/`not_available`, denominators, `data_as_of`, and `buyer_discovery` vs `brand_control`.
- Fake-RPC regression tests for tool discovery, allowed periods, and server rejection of `1y`; optional read-only live smoke checks.

### Release notes

- Synced from the AuraCite monorepo (merge f2a8ea7e). A new ChatGPT connector session or reconnection is still needed to refresh a pinned tool catalog.

## v0.11.3 - 2026-08-14

### Removed

- `summarize_user_landscape` and `list_recent_signups` are no longer advertised to customers. Both
  read platform-wide user data with no tenant filter, so the production server reclassified them to
  admin scope and stopped listing them in the hosted `/mcp/rpc` catalog. They stayed in the
  package's safe allowlist regardless — the wrong place for a tool no customer key may call. They
  are now explicitly disabled and blocked by the local bridge in every mode.

### Fixed

- The live bridge smoke asserted that both tools *should* be visible in safe mode, which stopped
  being true when the server reclassified them. It now asserts the opposite. The unit test keeps
  them in the fake upstream's tool list so the filter is proven to drop them.

### Changed

- Verified operator surface is now 46 tools (was 48); safe read surface is 35.

### Safety

- No customer-visible capability is lost: these tools already failed at the server for every
  non-admin key. This removes a misleading local allowlist entry, not a working feature.

## v0.11.2 - 2026-08-14

### Added

- Restored `get_crawler_hits` to the hosted package and the local bridge allowlist. AI-crawler
  access is the input side of AI visibility: which bots fetch which pages, and which pages are
  crawled heavily but rarely cited.

### Changed

- Verified operator surface is now 48 tools (was 47).

### Why it was removed in v0.11.0

- The tool was registered on the production MCP server but had no entry in its tool policy, so
  `/mcp/rpc` filtered it out of `tools/list` and rejected any call. Removing it was correct at the
  time. AuraCite `6a93e2a9` closed that gap; the tool was verified live against
  `https://auracite.de` before this release — listed with read-only annotations, and returning real
  per-crawler data.

### Safety

- Read-only, no provider call, no credit spend, tenant/project scoped server-side. Write, cost, and
  admin tools remain unchanged and blocked by default.

## v0.11.1 - 2026-07-31

Universal Plugins Directory submission-readiness release.

### Changed

- Updated distribution guidance for OpenAI's public submission portal and universal directory shared by ChatGPT and Codex.
- Reduced manifest starter prompts to the three workflows Codex displays.
- Added reviewer-ready listing data, release notes, five positive cases, three negative cases, and explicit launch gates.
- Added continuous package validation for pull requests and pushes.

### Safety

- No credentials, domain challenge tokens, tenant identifiers, or customer evidence are stored in this repository.
- The repo marketplace remains the only claimed live distribution path until OpenAI review is approved and the approved version is published.

## v0.10.0 - 2026-07-16

Enterprise read-surface and governance release.

### Added

- Production-aligned safe reads for project discovery, user-landscape summaries, recent signups,
  all six bounded GSC reads, and the combined AI-visibility overview.
- Bundled `ai-visibility` skill for evidence-first GEO/GSC answers.
- OAuth dogfood now exercises bounded read calls through the PKCE bearer, not only `tools/list`.

### Changed

- Project/brand/prompt mutations remain blocked by the hosted package and local bridge until the
  production server enforces exact confirmation, audit, tenant/project scope, and idempotency for
  each call. `mcp:write` scope alone is not treated as approval.
- Removed the stale `get_crawler_hits` package entry because it is not exposed by the production
  MCP resource used by the plugin.

### Verification

- OAuth/PKCE default-project flow passed against `https://auracite.de`: 36 safe tools visible, eight
  bounded read calls passed, OAuth bearer revoked, revoked bearer rejected, and OAuth challenge
  advertised. No provider calls, credits, or business mutations.
- Local validator, bridge unit smoke, and enterprise blocked-tool assertions pass.

## v0.9.0 - 2026-07-14

Superseded by v0.10.0: the zero-touch config-write exposure described below is no longer part of
the enterprise package or bridge contract.

Adds free config-write tools to the bridge's `confirmed-writes` mode.

### Added

- `create_project`, `add_prompt`, `add_brand`, `bulk_add_prompts` are now reachable through the local
  JSON-RPC bridge (`auracite-jsonrpc-bridge`) in `confirmed-writes` mode. Previously the bridge
  permanently blocked these regardless of token scope or bridge mode.
- `list_projects` added as a safe-mode read.

### Changed

- These four tools are zero-touch on the AuraCite server (`mcp:write` scope only — no approval quote,
  no idempotency key), unlike the existing confirmed-write tools (memory/action-status updates,
  intelligence refresh) which still require exact confirmation and idempotency, and the cost tools
  (`trigger_scan`, `generate_ai_prompts`) which still require `mcp:spend` and a one-tap execution
  approval in AuraCite.

### Unchanged

- Destructive/admin tools (`delete_brand`, `create_demo_user`, `add_credits`) remain permanently
  blocked through the bridge, in every mode, regardless of token scope.
- The bridge still defaults to `safe` mode (read/draft tools only); `confirmed-writes` must be set
  explicitly.
- Hosted OAuth connections at `https://auracite.de/mcp/rpc` are unaffected — their tool visibility
  was always governed by the token's own scope, not the bridge.

### Verification

- `pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/validate-plugin.ps1` passed.
- Bounded subprocess smoke against the bridge (no network/token/cost): the 4 tools pass the gate in
  `confirmed-writes` mode, are blocked in `safe` mode; `delete_brand`/`add_credits` stay blocked in
  every mode. 8/8 assertions passed.
- Server-side change was already live and tested on `origin/master` before this release
  (`go test ./internal/adapters/mcp/... ./internal/adapters/http/api/... ./internal/application/mcpapproval/...`, all pass).

## v0.8.1 - 2026-06-10

Public repo-marketplace release for AuraCite Agent Hub.

### Install

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

### Added

- Public Codex marketplace repo at `getauracite/codex-plugins`.
- OAuth-first install copy for AuraCite Agent Hub.
- Hosted MCP JSON-RPC endpoint configuration for `https://auracite.de/mcp/rpc`.
- Public install guide and workspace sharing guide.
- Safe bundled skills for AuraCite AI Visibility Intelligence, Action Center handoffs, project memory context, and plugin readiness review.

### Safety

- Read and draft workflows remain the default.
- Mutating, provider-spend, admin, bulk, publishing, and raw Vault-write workflows stay disabled by default.
- Confirmed writes require scoped `mcp:write`, exact confirmation text, audit events, and idempotency checks.
- Provider-spend workflows additionally require `mcp:spend`, a server quote, hard credit caps, optional USD caps, CostGuard, and explicit confirmation.

### Verification

- Plugin manifest validation passed.
- JSON-RPC bridge test passed.
- Clean Codex install from the public marketplace repo passed.
- AuraCite production `/agent-hub` install flow was browser-smoked on desktop and mobile with the public two-command install path.

