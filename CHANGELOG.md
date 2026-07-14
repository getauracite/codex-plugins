# Changelog

## v0.9.0 - 2026-07-14

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

