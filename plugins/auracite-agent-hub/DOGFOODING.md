# AuraCite Agent Hub Dogfood Protocol

Status: active before public release
Last updated: 2026-05-27

## Decision

AuraCite Agent Hub must be used and optimized in our own work before broad public release. Public listing is a product milestone after repeated internal dogfood, trusted pilot feedback, and release-gate evidence.

## Dogfood Loop

1. Install the plugin from the repo marketplace in a real Codex workspace.
2. Run the safe package gate with no token.
3. Run live read dogfood with a temporary `mcp:read` token, preferably through `scripts/dogfood-prod-read-temp-key.ps1` for internal AuraCite production dogfood.
4. Run the OAuth install-path dogfood through `scripts/dogfood-prod-mcp-oauth-temp-key.ps1` before any customer handoff that expects marketplace-style OAuth.
5. Use the plugin in real AuraCite work: status review, opportunity triage, action handoff planning, and session sync.
6. Record what was useful, confusing, missing, or risky.
7. Convert findings into small plugin/backend/docs changes.
8. Re-run the dogfood gate.
9. Only schedule confirmed-write dogfood on controlled internal runs.
10. Run `mcp:spend` cap dogfood before any real provider-spend run.
11. Revoke temporary tokens and record sanitized evidence.

## Weekly Practical Scenarios

- Start-of-session context: ask Codex to summarize Agent Hub timeline, project status, and next actions.
- Visibility triage: inspect opportunity briefs and produce one Action Center handoff draft.
- Intelligence refresh control: inspect freshness/candidates, draft a refresh plan, and only run confirmed `stored_rescore` on controlled internal data.
- Implementation handoff: turn a real Intelligence opportunity into a Context Pack draft.
- Session closeout: prepare safe project-memory entry text and confirm whether it belongs in server memory or curated Vault snapshot.
- Reconciliation: on a controlled internal run, update status and record one outcome measurement with replay proof.

Automated internal scenario suite:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-read-temp-key.ps1 -ScenarioSessions
```

Confirmed-write deny gate without mutation:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-write-deny-temp-key.ps1
```

OAuth install-path gate without printing the issued bearer:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-mcp-oauth-temp-key.ps1
```

Spend cap gate without provider calls or credit charges:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-spend-cap-temp-key.ps1
```

Refresh-plan inspection before public screenshots:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-refresh-plan-temp-key.ps1
```

Confirmed stored-rescore smoke after source data refresh:

```powershell
pwsh -NoProfile -ExecutionPolicy Bypass -File plugins/auracite-agent-hub/scripts/dogfood-prod-stored-rescore-temp-key.ps1
```

## Release Gates

- Three internal sessions use the plugin without manual debugging.
- At least one trusted pilot installs from the intended distribution path.
- OAuth install path passes production dogfood: metadata, registration, PKCE consent, bearer MCP read, revoke, and revoked-bearer rejection.
- Safe mode is useful without write scope.
- Confirmed writes stay disabled by default and fail closed without exact confirmation.
- `mcp:spend` tools require a short-lived quote, hard `max_credits`, CostGuard, provider-cost event recording, and cap-smoke evidence before any live provider-spend pilot.
- No secret appears in repo, vault, logs, screenshots, or tool results.
- Screenshots or a short demo are captured from non-sensitive data.
- Customer install and key revocation instructions are clear enough for a non-developer operator.
- Known issues are either fixed or explicitly listed in the public release notes.

## Evidence Log Format

Use this format in release notes or vault updates:

```text
date:
operator:
workspace:
plugin_version:
scenario:
tools_used:
mode:
result:
mutation_performed:
provider_calls_triggered:
credits_charged:
token_revoked:
follow_up:
```

Keep evidence concise and secret-free.

## Optimization Backlog Seeds

- Reduce setup friction for the local JSON-RPC bridge.
- Keep the temporary-key production dogfood helper working so internal operators do not manually handle keys more than needed.
- Improve first-run prompts so Codex naturally starts with read-only context.
- Use the V0.8 refresh-control tools to resolve or clearly frame stale Intelligence data before public demo screenshots.
- After source-specific data refreshes, run the stored-rescore helper and record whether candidates changed.
- Add a customer-safe demo dataset or screenshots.
- Promote useful server-side memory entries into curated Vault snapshots only after operator review.
- Keep hosted SSE disabled until it is proven through production edge behavior.
