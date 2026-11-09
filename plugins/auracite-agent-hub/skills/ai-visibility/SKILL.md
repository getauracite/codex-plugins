---
name: ai-visibility
description: Use when the user asks how a brand is mentioned, ranked, cited, or recommended by AI engines, wants GEO visibility or share of voice, asks for competitor/trend evidence, or wants to connect AI visibility with Google Search Console performance.
---

# AuraCite AI Visibility

Use the `auracite` MCP server to answer AI-visibility/GEO questions from AuraCite evidence. Keep the
answer tied to returned data; do not invent engine, query, citation, or competitor numbers.

## Read-only tools

| Tool | Use it for |
| --- | --- |
| `list_brands` / `list_projects` | Find the tracked brand and project |
| `get_dashboard_stats` | Headline mentions, citations, and sentiment for `7d`, `30d`, or `90d` |
| `get_mentions` / `get_citations` | Inspect AI-answer mentions and earned source links |
| `get_visibility_kpis` | Buyer-discovery headline rates (visibility, recommendations, share of voice) with measured/not_available status, base, scope, and data date for 7d/30d/90d |
| `get_visibility_score` / `get_share_of_voice` | Legacy composite GEO score and share of voice; do not mix brand_control into the headline |
| `get_ai_engine_breakdown` / `get_trend_data` | Engine-level comparison and time-series context |
| `list_competitors` / `compare_brands` | Identify and compare tracked competitors |
| `get_gsc_top_queries` / `get_gsc_top_pages` | Search demand and landing-page performance |
| `get_gsc_search_analytics` | Query+page rows over a bounded day window |
| `get_gsc_breakdown` | Country or device performance |
| `get_gsc_trend` | Current-vs-previous query movement; negative position delta is improvement |
| `get_ai_visibility_overview` | One stored cross-source snapshot combining GSC, crawler, mentions, and citations |

## Working pattern

### Customer overview and guidance

For a customer's visibility overview, call `render_visibility_overview` with the
verified project and requested `7d`/`30d`/`90d` period (default `30d`). It reads the
stored metrics itself and returns an optional dashboard plus identical structured
data for text-only clients. Do not rebuild or invent the metrics in HTML. Explain
the most relevant returned limitation and one next step; do not repeat the whole
dashboard in prose. Short follow-up questions do not need another render.

Before a substantive GEO suggestion, call `get_customer_guidance` with a concrete
question and the actually known surface, industry and page type. Do not infer
`chatgpt_search` from a generic provider name. Preserve sources, conditions,
caveats, card ID/revision and corpus hash. Reuse `expected_corpus_hash` within one
analysis; on a mismatch retrieve and reassess, never combine revisions silently.
Use the same query/context when rendering the supporting knowledge in the overview.

The customer tools expose only editorially approved, currently actionable cards.
Do not request owner scopes, private repository access, owner knowledge tools or
owner learnings to fill a customer's knowledge gap. `knowledge_gap` or
`insufficient_context` requires an honest limitation or a targeted question, never
a fabricated AuraCite recommendation. A documentation rule is not a measured
customer defect or a promise of uplift. Missing data is not zero.

For an investigation, inspect stored answers and source evidence before alleging
a website problem. Keep measured facts, knowledge, interpretation and test ideas
separate. No scan, publishing, account change or credit spend follows from opening
the dashboard. If the client cannot display UI, summarize the same returned
metrics, their bases, date, limitation and next step in readable text.

### Existing detailed analysis

1. Identify the intended brand/project with `list_brands` and `list_projects`.
2. Start with `get_visibility_kpis` (period `7d`, `30d`, or `90d`). Preserve each metric's `status`, numerator/denominator, period, and `data_as_of`. A `not_available` metric is not zero. Keep `brand_control` separate from non-brand `buyer_discovery` rates. Use `get_dashboard_stats` for additional legacy dashboard context.
3. Drill into mentions, citations, engine breakdown, competitors, GSC queries/pages, or trends.
4. Separate observed evidence from interpretation and state the time window.
5. If the user asks what to do next, hand the evidence to `visibility-action-planner` and keep any
   Action Center handoff at `human_review_required`.

## Shared optimization knowledge for owner workflows

Read the [canonical entry](https://github.com/G5317/AuraCite/blob/master/docs/GEO_KNOWLEDGE_BASE.md)
through an authorized repository connection. Select and record the actual repository commit; if
working from an unreleased PR, say so. Retrieve its canonical corpus unchanged and use the shared
CLI with `--corpus <file>` in the available cloud workspace or local checkout. Railway, AgentOps,
a local coding worker and a backend deployment are not prerequisites. Working files are disposable
read copies, never a second editable knowledge source. Raw JSON inspection alone is not a passed
retrieval/validation run.

Pass the actual provider/surface and known industry, page type and locale. Pin the returned
`corpus_hash` with `expected_corpus_hash` on subsequent reads. Retain card ID/version, sources,
review date, applicability and limitations. Only actionable results support recommendations;
research results remain hypotheses or blocked knowledge. Documentation is not a measured customer
effect. A missing result is a knowledge gap.

The owner tools `search_geo_knowledge` and `get_geo_knowledge` are optional additional access paths.
They require `mcp:agentops:read` plus the live owner gate and must match the selected corpus hash.
If the backend is unavailable or serves another hash, use the direct CLI path. Do not broaden
permissions, require a backend deployment or substitute archived strategies as a workaround.
Customer-only workflows may use their stored measurements and explicitly sourced public guidance.

Keep customer observations and outcomes in their existing project scope. Link decisions to card
IDs/version/hash and existing action/measurement references; do not copy private customer data into
the global corpus or copy the corpus into project memory.

## Safety and scope

- Analysis is read-only. The explicit owner-requested learning capture below is the only write
  exception. Never trigger scans, ingestion, provider calls, publishing, or credit spend speculatively.
- OAuth or API-key scope binds tenant/project/user server-side; never infer scope from user-visible
  labels or accept caller-supplied scope as authoritative.
- GSC and the combined overview read stored data. If data is stale or missing, report that limitation
  and draft a refresh plan instead of triggering a refresh.

## Direct learning capture across sessions

On an explicit request to remember or update a GEO learning, use `search_geo_learnings` first to find an existing entry. This live owner-only inbox complements the curated corpus; it is not a replacement for reviewed cards or a task/CRM ledger. No credentials or private customer data belong here.

Use `save_geo_learning` with a stable UUID, `expected_revision` (0 for creation), title, body, source/session reference, status `unreviewed`, and a fresh request_key. Updates reuse the ID and latest revision; retries reuse the identical request and key. A revision conflict requires a fresh read and reconciliation, never a blind overwrite. Saving cannot mark evidence validated. Archive with status `archived`; history is retained.

Read the ID back with `search_geo_learnings` before claiming success. Report ID and revision. New sessions search this inbox alongside `search_geo_knowledge`/the canonical CLI. Unreviewed observations stay unreviewed; archived entries are not active advice. Changes are immediately visible without deployment. A read-only connection cannot save: report the missing write scope, never substitute a local note and claim shared persistence.
