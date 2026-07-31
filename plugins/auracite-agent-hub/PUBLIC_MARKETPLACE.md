# AuraCite Agent Hub Public Codex Marketplace Notes

Status: public repo-marketplace release path
Last updated: 2026-07-31

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

## OpenAI Universal Plugins Directory

OpenAI now documents one universal public Plugins Directory shared by ChatGPT and Codex. Public publication uses the OpenAI Platform plugin submission portal and a review-before-publish workflow.

AuraCite submits as `With MCP` plus bundled skills:

- Universal MCP URL: `https://auracite.de/mcp/rpc`
- OAuth-first authentication
- Public skills bundle under `plugins/auracite-agent-hub/skills/`
- Domain verification on `auracite.de`
- Reviewer account supplied only through the OpenAI portal

The repo marketplace remains available while review is pending. Do not claim universal-directory availability until OpenAI approval is published.

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

- OpenAI submission pack includes five positive and three negative review cases.
- Every production MCP tool advertises accurate `readOnlyHint`, `destructiveHint`, and `openWorldHint` values.
- Reviewer credentials work without MFA and are entered only in the OpenAI portal.
- Domain challenge token is served exactly at `/.well-known/openai-apps-challenge` after the portal issues it.

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
