param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$EndpointPath = '/mcp/rpc',
  [string]$OpportunityId = '',
  [switch]$CallDraftTools
)

$ErrorActionPreference = 'Stop'

$token = $env:AURACITE_MCP_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
  throw 'AURACITE_MCP_TOKEN is required. The token is read from env and never printed.'
}

$endpoint = $BaseUrl.TrimEnd('/') + $EndpointPath
$headers = @{
  'X-API-Key'    = $token
  'Content-Type' = 'application/json'
}

function Invoke-AuraCiteMCP {
  param(
    [string]$Method,
    [hashtable]$Params = @{},
    [int]$Id = 1
  )

  $body = @{
    jsonrpc = '2.0'
    method  = $Method
    params  = $Params
    id      = $Id
  } | ConvertTo-Json -Depth 30 -Compress

  $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body
  if ($null -ne $response.error) {
    throw "MCP $Method failed: $($response.error.message) $($response.error.data)"
  }
  return $response.result
}

function Get-ToolTextBody {
  param([object]$Result)

  $content = @($Result.content)
  if ($content.Count -eq 0 -or [string]::IsNullOrWhiteSpace($content[0].text)) {
    throw 'MCP tool result did not contain a text payload.'
  }
  return $content[0].text | ConvertFrom-Json
}

$requiredTools = @(
  'get_intelligence_overview',
  'get_intelligence_freshness',
  'list_intelligence_refresh_candidates',
  'create_intelligence_refresh_plan_draft',
  'get_intelligence_refresh_status',
  'list_intelligence_opportunity_briefs',
  'get_intelligence_opportunity_brief',
  'list_action_handoffs',
  'get_vault_next_actions',
  'get_project_status',
  'get_recent_changelog',
  'get_agent_hub_timeline',
  'create_context_pack_draft',
  'create_action_handoff_draft',
  'write_approval_note_draft'
)

$toolsResult = Invoke-AuraCiteMCP -Method 'tools/list' -Id 1
$toolNames = @($toolsResult.tools | ForEach-Object { $_.name })
$missing = @($requiredTools | Where-Object { $toolNames -notcontains $_ })
if ($missing.Count -gt 0) {
  throw "tools/list missing required tools: $($missing -join ', ')"
}

Write-Host "tools/list OK: $($toolNames.Count) tools visible; Agent Hub BI tools present."

$overviewResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'get_intelligence_overview'
  arguments = @{}
} -Id 2
$overview = Get-ToolTextBody -Result $overviewResult
$opportunityCount = @($overview.opportunities).Count

Write-Host "get_intelligence_overview OK: freshness=$($overview.freshness_state), opportunities=$opportunityCount."

$freshnessResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'get_intelligence_freshness'
  arguments = @{ limit = 5 }
} -Id 3
$freshness = Get-ToolTextBody -Result $freshnessResult
if ($freshness.mutation_performed -ne $false -or $freshness.provider_calls_triggered -ne 0 -or $freshness.credits_charged -ne 0) {
  throw 'get_intelligence_freshness must be read-only with zero provider/credit side effects.'
}

$refreshPlanResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'create_intelligence_refresh_plan_draft'
  arguments = @{ limit = 5 }
} -Id 4
$refreshPlan = Get-ToolTextBody -Result $refreshPlanResult
if ($refreshPlan.mutation_performed -ne $false -or $refreshPlan.approval_gate -ne 'human_review_required') {
  throw 'create_intelligence_refresh_plan_draft must remain a human-reviewed, side-effect-free draft.'
}
Write-Host "Intelligence refresh controls OK: candidates=$($freshness.refresh_candidate_count), planGate=$($refreshPlan.approval_gate)."

$memoryChecks = @(
  @{ name = 'get_project_status'; arguments = @{} },
  @{ name = 'get_vault_next_actions'; arguments = @{ limit = 3 } },
  @{ name = 'get_recent_changelog'; arguments = @{ limit = 3 } },
  @{ name = 'get_agent_hub_timeline'; arguments = @{ limit = 5 } }
)
$memoryRequestId = 5
foreach ($check in $memoryChecks) {
  $memoryResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
    name      = $check.name
    arguments = $check.arguments
  } -Id $memoryRequestId
  $memoryRequestId++
  $memory = Get-ToolTextBody -Result $memoryResult

  if ($memory.mutation_performed -ne $false) {
    throw "$($check.name) did not report mutation_performed=false."
  }
  if ($memory.redaction_state -ne 'secret_safe_snapshot') {
    throw "$($check.name) did not report secret_safe_snapshot redaction state."
  }
}

Write-Host 'Project memory tools OK: status, next actions, changelog, and Agent Hub timeline are secret-safe read-only snapshots.'

if ([string]::IsNullOrWhiteSpace($OpportunityId) -and $opportunityCount -gt 0) {
  $OpportunityId = @($overview.opportunities)[0].id
}

if ($CallDraftTools) {
  if ([string]::IsNullOrWhiteSpace($OpportunityId)) {
    throw 'CallDraftTools was requested, but no OpportunityId was provided and the overview has no opportunities.'
  }

  foreach ($tool in @('create_context_pack_draft', 'create_action_handoff_draft', 'write_approval_note_draft')) {
    $draftResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
      name      = $tool
      arguments = @{ opportunity_id = $OpportunityId }
    } -Id 10
    $draft = Get-ToolTextBody -Result $draftResult

    if ($draft.mutation_performed -ne $false) {
      throw "$tool did not report mutation_performed=false."
    }
    if ($draft.approval_gate -ne 'human_review_required') {
      throw "$tool did not preserve human_review_required approval gate."
    }
  }

  Write-Host "Draft tools OK for opportunity $OpportunityId; all reported no mutation and human review gate."
}

Write-Host 'AuraCite Agent Hub JSON-RPC smoke passed.'
