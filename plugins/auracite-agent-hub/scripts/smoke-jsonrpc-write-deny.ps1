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

function Assert-PendingApproval {
  param(
    [object]$Result,
    [string]$ToolName
  )

  if ($Result.approval_required -ne $true) {
    throw "$ToolName did not return approval_required=true: $($Result | ConvertTo-Json -Depth 8 -Compress)"
  }
  if ([string]::IsNullOrWhiteSpace([string]$Result.quote_id)) {
    throw "$ToolName did not return a pending quote_id."
  }
  if ([string]$Result.approval_url -ne 'https://auracite.de/approvals') {
    throw "$ToolName returned an unexpected approval URL."
  }
  if ($Result.mutation_performed -eq $true -or $Result.provider_calls_triggered -gt 0 -or $Result.credits_charged -gt 0) {
    throw "$ToolName performed a side effect while awaiting approval."
  }
}

$opportunityId = '00000000-0000-0000-0000-00000000b501'
$runId = '00000000-0000-0000-0000-00000000a501'

$checks = @(
  @{
    name = 'create_project'
    arguments = @{
      name = 'Approval-gated smoke project'
      idempotency_key = 'safe-deny-smoke-create-project-20260716'
    }
  },
  @{
    name = 'add_brand'
    arguments = @{
      name = 'Approval-gated smoke brand'
      domain = 'approval-smoke.example'
      idempotency_key = 'safe-deny-smoke-add-brand-20260716'
    }
  },
  @{
    name = 'add_prompt'
    arguments = @{
      text = 'Approval-gated smoke prompt'
      topic = 'smoke'
      idempotency_key = 'safe-deny-smoke-add-prompt-20260716'
    }
  },
  @{
    name = 'bulk_add_prompts'
    arguments = @{
      prompts = '[{"text":"Approval-gated smoke prompt","topic":"smoke"}]'
      idempotency_key = 'safe-deny-smoke-bulk-add-prompts-20260716'
    }
  },
  @{
    name = 'promote_handoff_to_action'
    arguments = @{
      opportunity_id = $opportunityId
      idempotency_key = 'safe-deny-smoke-promote-20260716'
    }
  },
  @{
    name = 'update_action_status'
    arguments = @{
      run_id = $runId
      status = 'implemented'
      idempotency_key = 'safe-deny-smoke-status-20260716'
    }
  },
  @{
    name = 'record_outcome_measurement'
    arguments = @{
      run_id = $runId
      outcome_metrics = @{ safe_denied_smoke = 1 }
      idempotency_key = 'safe-deny-smoke-measure-20260716'
    }
  },
  @{
    name = 'trigger_intelligence_refresh'
    arguments = @{
      refresh_type = 'stored_rescore'
      idempotency_key = 'safe-deny-smoke-refresh-20260716'
    }
  }
)

$requestId = 100
foreach ($check in $checks) {
  $result = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
    name = $check.name
    arguments = $check.arguments
  } -Id $requestId
  $requestId++

  Assert-PendingApproval -Result $result -ToolName $check.name
}

Write-Host 'AuraCite Agent Hub JSON-RPC approval-pending smoke passed: no business mutations, provider calls, or credits charged before approval.'
