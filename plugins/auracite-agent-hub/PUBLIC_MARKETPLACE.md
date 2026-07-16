# AuraCite Agent Hub Public Codex Marketplace Notes

Status: public repo-marketplace release path
Last updated: 2026-06-10

## Public Install Path

The public Codex marketplace repo is:

```text
https://github.com/getauracite/codex-plugins
```

Customer install command:

```powershell
codex plugin marketplace add getauracite/codex-plugins
codex plugin add auracite-agent-hub@auracite-marketplace
```

The repo root must contain:

```text
.agents/plugins/marketplace.json
plugins/auracite-agent-hub/
```

`marketplace.json` keeps the marketplace name `auracite-marketplace` so local and public installs use the same plugin id:

```text
auracite-agent-hub@auracite-marketplace
```

## OpenAI Curated Directory

OpenAI's Codex Plugin Directory includes an `openai-curated` marketplace. Current public OpenAI docs describe:

- Local and repo marketplaces.
- Personal marketplaces.
- Workspace sharing from the Codex app.
- Curated plugins in the OpenAI directory.

They do not document a self-service submission form for arbitrary third-party plugins. Treat OpenAI-curated listing as a separate partner/submission track after the repo-marketplace package is public, tested, and accompanied by screenshots or a short demo.

## Release Checklist

- `plugins/auracite-agent-hub/.codex-plugin/plugin.json` has a public version and public repository URL.
- `.agents/plugins/marketplace.json` points to `./plugins/auracite-agent-hub`.
- README and customer install guide are OAuth-first.
- Hosted MCP uses `https://auracite.de/mcp/rpc`.
- Manual bridge stays disabled by default and safe-mode only unless explicitly enabled.
- Safe mode hides mutating and provider-spend tools by default. Confirmed-writes mode exposes useful writes and spend workflows behind AuraCite's server-side quote, scope, audit, idempotency, and cost gates; destructive/admin, publishing, and raw Vault-write tools remain blocked.
- Validation passes:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/validate-plugin.ps1
node plugins/auracite-agent-hub/scripts/test-jsonrpc-bridge.mjs
codex plugin list --marketplace auracite-marketplace --json --available
```

## Public Repo Sync

Mirror only the plugin marketplace package into the public repo:

```text
.agents/plugins/marketplace.json
plugins/auracite-agent-hub/
README.md
LICENSE
```

Do not mirror:

- `.env` files.
- Local Codex config.
- Browser profiles.
- SecretManagement exports.
- Internal vault notes.
- Customer/private evidence.
