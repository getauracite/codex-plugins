# OpenAI Universal Directory Submission Checklist

Updated: 2026-07-31

## Package

- [x] Public repository and repo marketplace available.
- [x] Strict-semver manifest version `0.11.3`.
- [x] Current plugin validator passes.
- [x] Bundled bridge unit test passes without network or credentials.
- [x] Three manifest starter prompts match supported workflows.
- [ ] Fresh public-repo install in Codex completed after `0.11.3` release.

## Publisher And Portal

- [ ] Submitter logged into `https://platform.openai.com/plugins`.
- [ ] Correct OpenAI organization selected.
- [ ] Publisher has verified AuraCite business identity.
- [ ] Submitter has `Apps Management: Write`.
- [ ] Submission draft created as `With MCP` plus skills.
- [ ] Country/region availability explicitly selected.

## MCP

- [x] Public production URL: `https://auracite.de/mcp/rpc`.
- [x] OAuth discovery and PKCE endpoints are public.
- [x] Tenant/project/user scope is injected server-side.
- [x] Writes and spend require durable approval/idempotency controls.
- [x] Corrected tool annotations deployed and confirmed through production `tools/list`.
- [ ] Portal `Scan Tools` completes without validation errors.
- [ ] Portal domain token served exactly at `https://auracite.de/.well-known/openai-apps-challenge`.
- [ ] Domain verification succeeds.

## Review Access

- [ ] Dedicated reviewer account exists without MFA, SMS, or email-confirmation blockers.
- [ ] Reviewer project contains deterministic non-customer fixture data.
- [ ] Reviewer credentials entered only in the OpenAI portal.
- [ ] Exactly five `mcp:read` cases P1-P5 pass.
- [ ] No `mcp:spend` granted unless OpenAI requests a bounded provider test.

## Listing And Legal

- [x] Website, privacy, terms, repository, and support URLs are public.
- [x] Listing copy avoids OpenAI endorsement claims.
- [x] Release notes describe scopes and safety gates.
- [ ] Public AuraCite landing-page MCP availability copy synchronized with actual launch state.

## Submission

- [x] Exactly five positive and three negative review cases prepared.
- [ ] Final plugin/skills archive uploaded.
- [ ] Policy attestations reviewed against current production behavior.
- [ ] Submission sent for OpenAI review.
- [ ] After approval, publisher explicitly publishes the approved version.
- [ ] Universal-directory listing and fresh-user install smoke pass before public launch claim.
