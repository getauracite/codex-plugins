param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$EndpointPath = '/mcp/rpc'
)

$ErrorActionPreference = 'Stop'

$token = $env:AURACITE_MCP_TOKEN
if ([string]::IsNullOrWhiteSpace($token)) {
  throw 'AURACITE_MCP_TOKEN is required. Use a temporary mcp:write token. The token is never printed.'
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

$idempotencyKey = 'safe-deny-smoke-2026-05-22'
$opportunityId = '00000000-0000-0000-0000-00000000b501'
$runId = '00000000-0000-0000-0000-00000000a501'

$checks = @(
  @{
    name = 'promote_handoff_to_action'
    arguments = @{
      opportunity_id = $opportunityId
      idempotency_key = $idempotencyKey
    }
    expected = "CONFIRM: promote_handoff_to_action $opportunityId $idempotencyKey"
  },
  @{
    name = 'update_action_status'
    arguments = @{
      run_id = $runId
      status = 'implemented'
      idempotency_key = $idempotencyKey
    }
    expected = "CONFIRM: update_action_status $runId implemented $idempotencyKey"
  },
  @{
    name = 'record_outcome_measurement'
    arguments = @{
      run_id = $runId
      outcome_metrics = @{ safe_denied_smoke = 1 }
      idempotency_key = $idempotencyKey
    }
    expected = "CONFIRM: record_outcome_measurement $runId $idempotencyKey"
  },
  @{
    name = 'trigger_intelligence_refresh'
    arguments = @{
      refresh_type = 'stored_rescore'
      idempotency_key = $idempotencyKey
    }
    expected = "CONFIRM: trigger_intelligence_refresh stored_rescore $idempotencyKey"
  }
)

$requestId = 100
foreach ($check in $checks) {
  $result = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
    name = $check.name
    arguments = $check.arguments
  } -Id $requestId
  $requestId++

  $body = Get-ToolTextBody -Result $result
  if ($body.mutation_performed -ne $false) {
    throw "$($check.name) unexpectedly reported mutation_performed=true."
  }
  if ($body.approval_gate -ne 'exact_confirmation_required') {
    throw "$($check.name) did not require exact confirmation. approval_gate=$($body.approval_gate)"
  }
  if ($body.required_confirmation -ne $check.expected) {
    throw "$($check.name) returned an unexpected confirmation string."
  }
  if ($body.provider_calls_triggered -ne 0 -or $body.credits_charged -ne 0) {
    throw "$($check.name) reported provider calls or credit charges on denied preview."
  }
}

Write-Host 'AuraCite Agent Hub JSON-RPC confirmed-write deny smoke passed: no mutations, no provider calls, no credits charged.'
