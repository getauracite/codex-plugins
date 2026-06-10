# AuraCite Agent Hub Workspace Sharing Runbook

Status: public repo-marketplace and trusted-pilot runbook
Last updated: 2026-06-10

## Goal

Share AuraCite Agent Hub through the public Codex repo marketplace, workspace sharing, or trusted customer pilots while preserving OAuth-first setup and safe default tool exposure.

## Share Preconditions

- `scripts/dogfood-gate.ps1` passes locally with no token.
- The public repo-marketplace package validates.
- A live read dogfood session passed with OAuth or a temporary `mcp:read` key.
- The customer or pilot workspace has plugin installation or sharing enabled.
- The pilot owner can install Agent Hub from Codex, approve AuraCite OAuth, and revoke the resulting Agent Hub connection from AuraCite.
- Confirmed writes remain disabled by default.
- No screenshots, logs, or docs contain keys, cookies, private customer data, or private links.

## Share Package

Send or mirror only:

- `.agents/plugins/marketplace.json`
- `plugins/auracite-agent-hub/`
- The customer install guide.
- The dogfood protocol.
- Public privacy and terms URLs.
- `PUBLIC_MARKETPLACE.md`

Do not send:

- `.env` files.
- Local Codex config with tokens.
- Browser profiles.
- SecretManagement exports.
- Vault notes containing private operational context unrelated to the pilot.

## Pilot Flow

1. Confirm the target workspace can install repo marketplace plugins.
2. Add the public marketplace:

   ```powershell
   codex plugin marketplace add getauracite/codex-plugins
   codex plugin add auracite-agent-hub@auracite-marketplace
   ```

3. Confirm `AuraCite Agent Hub` appears as installed and enabled.
4. Complete the AuraCite OAuth consent flow for the intended tenant/project.
5. Run the no-token dogfood gate when local validation is needed.
6. Use the manual fallback only if the Codex workspace cannot complete MCP OAuth.
7. Run `agent-hub-health-check.ps1` only for fallback/local-bridge pilots.
8. Ask Codex to use the plugin for one real read-only scenario.
9. Capture sanitized findings in the evidence log format from `DOGFOODING.md`.
10. Revoke the connection.
11. Confirm revoked-token/key failure if the pilot requires proof.

## Current Trusted Pilot Anchor

The current first UX pilot anchor is Hamid. The goal is to test the intended Marketplace-style flow after the manual key friction has been moved behind AuraCite Settings. ANTOM/Andreas remains a later customer feedback candidate, but should not be the first install-friction test.

First-session goal:

1. Install from the intended repo-marketplace path.
2. Approve AuraCite OAuth for read-only `mcp:read`.
3. Run `get_agent_hub_timeline`, `get_project_status`, `get_intelligence_freshness`, and one draft tool.
4. Revoke the connection.
5. Verify failed access after revocation.
6. Capture sanitized findings only.

## Write Pilot Flow

Use this only for internal AuraCite dogfood or a customer pilot with explicit written approval.

1. Create a temporary `mcp:write` key.
2. Confirm the run/opportunity is controlled and reversible.
3. Run denied-write proof first.
4. Run the bounded outcome reconciliation smoke only if the mutation is intended.
5. Check replay behavior and final readback.
6. Revoke the key immediately.
7. Record sanitized evidence.

## Public Listing Readiness

For broad public repo-marketplace distribution:

- Use `getauracite/codex-plugins` as the install repo.
- Keep README and `CUSTOMER_INSTALL.md` OAuth-first.
- List known limitations: OpenAI-curated directory is a separate track, hosted SSE is not the default, generic external source refresh is not exposed, and confirmed writes are disabled by default.
- Add screenshots or demo capture only when they use non-sensitive data.
