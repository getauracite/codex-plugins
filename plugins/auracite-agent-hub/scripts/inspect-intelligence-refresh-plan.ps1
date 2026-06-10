param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$EndpointPath = '/mcp/rpc',
  [int]$Limit = 25,
  [int]$PlanLimit = 10
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

  $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -TimeoutSec 45
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

function Assert-NoSideEffects {
  param(
    [object]$Body,
    [string]$ToolName
  )

  if ($Body.mutation_performed -ne $false) {
    throw "$ToolName must report mutation_performed=false."
  }
  if ([double]$Body.provider_calls_triggered -ne 0) {
    throw "$ToolName must report provider_calls_triggered=0."
  }
  if ([double]$Body.credits_charged -ne 0) {
    throw "$ToolName must report credits_charged=0."
  }
}

$candidateResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'list_intelligence_refresh_candidates'
  arguments = @{ limit = $Limit }
} -Id 1
$candidateBody = Get-ToolTextBody -Result $candidateResult
Assert-NoSideEffects -Body $candidateBody -ToolName 'list_intelligence_refresh_candidates'

$statusResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'get_intelligence_refresh_status'
  arguments = @{ limit = $PlanLimit }
} -Id 2
$statusBody = Get-ToolTextBody -Result $statusResult
Assert-NoSideEffects -Body $statusBody -ToolName 'get_intelligence_refresh_status'

$planResult = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
  name      = 'create_intelligence_refresh_plan_draft'
  arguments = @{ limit = $PlanLimit }
} -Id 3
$planBody = Get-ToolTextBody -Result $planResult
Assert-NoSideEffects -Body $planBody -ToolName 'create_intelligence_refresh_plan_draft'

if ($planBody.approval_gate -ne 'human_review_required') {
  throw 'create_intelligence_refresh_plan_draft must preserve human_review_required approval gate.'
}

$candidates = @($candidateBody.candidates | ForEach-Object {
  [pscustomobject]@{
    source_key                         = $_.source_key
    display_name                       = $_.display_name
    category                           = $_.category
    freshness_state                    = $_.freshness_state
    freshness_days                     = $_.freshness_days
    sync_status                        = $_.sync_status
    signal_count                       = $_.signal_count
    evidence_count                     = $_.evidence_count
    data_state                         = $_.data_state
    quality_state                      = $_.quality_state
    provenance                         = $_.provenance
    cost_model                         = $_.cost_model
    next_step_code                     = $_.next_step_code
    execution_mode                     = $_.execution_mode
    approval_gate                      = $_.approval_gate
    credits_required                   = $_.credits_required
    provider_calls_require_confirmation = $_.provider_calls_require_confirmation
    source_data_refresh_via_plugin     = $_.source_data_refresh_via_plugin
  }
})

$executionModes = @{}
foreach ($group in ($candidates | Group-Object -Property execution_mode)) {
  $executionModes[$group.Name] = $group.Count
}

$demoReadiness = 'ready_with_partial_data_framing'
if ($candidateBody.freshness_state -eq 'fresh' -and [int]$candidateBody.total -eq 0) {
  $demoReadiness = 'ready_as_current_data_demo'
}

$summary = [pscustomobject]@{
  base_url = $BaseUrl
  freshness_state = $candidateBody.freshness_state
  refresh_status = $statusBody.status
  total_candidates = $candidateBody.total
  returned_candidates = $candidates.Count
  recommended_next_step = $statusBody.recommended_next_step
  plan_gate = $planBody.approval_gate
  stored_rescore_available = $planBody.stored_rescore_available
  execution_modes = $executionModes
  demo_readiness = $demoReadiness
  demo_framing = 'Do not claim all source data is current unless freshness_state=fresh and total_candidates=0. Partial/stale data is acceptable for a controlled walkthrough if labeled as such.'
  mutation_performed = $false
  provider_calls_triggered = 0
  credits_charged = 0
  source_data_refreshed = $false
  printed_secrets_or_tokens = $false
  candidates = $candidates
}

$summary | ConvertTo-Json -Depth 8
