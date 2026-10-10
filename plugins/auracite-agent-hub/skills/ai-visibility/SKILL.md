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

1. Identify the intended brand/project with `list_brands` and `list_projects`.
2. Start with `get_visibility_kpis` (period `7d`, `30d`, or `90d`). Preserve each metric's `status`, numerator/denominator, period, and `data_as_of`. A `not_available` metric is not zero. Keep `brand_control` separate from non-brand `buyer_discovery` rates. Use `get_dashboard_stats` for additional legacy dashboard context.
3. Drill into mentions, citations, engine breakdown, competitors, GSC queries/pages, or trends.
4. Separate observed evidence from interpretation and state the time window.
5. If the user asks what to do next, hand the evidence to `visibility-action-planner` and keep any
   Action Center handoff at `human_review_required`.

## Safety and scope

- This skill is read-only. It must not trigger scans, ingestion, provider calls, publishing, or credit
  spend speculatively.
- OAuth or API-key scope binds tenant/project/user server-side; never infer scope from user-visible
  labels or accept caller-supplied scope as authoritative.
- GSC and the combined overview read stored data. If data is stale or missing, report that limitation
  and draft a refresh plan instead of triggering a refresh.
