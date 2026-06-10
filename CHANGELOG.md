# Changelog

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

