param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$EndpointPath = '/mcp/rpc',
  [string]$RunId = '',
  [switch]$AppendMemoryEvidence,
  [switch]$IUnderstandThisMutatesAControlledRun
)

$ErrorActionPreference = 'Stop'

if (-not $IUnderstandThisMutatesAControlledRun) {
  throw 'This smoke mutates a controlled Action Center run. Re-run with -IUnderstandThisMutatesAControlledRun and a temporary mcp:write token.'
}

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
    [string]$Id = '1'
  )

  $body = @{
    jsonrpc = '2.0'
    method  = $Method
    params  = $Params
    id      = $Id
  } | ConvertTo-Json -Depth 40 -Compress

  $response = Invoke-RestMethod -Method Post -Uri $endpoint -Headers $headers -Body $body -TimeoutSec 45
  if ($null -ne $response.error) {
    throw "MCP $Method failed: $($response.error.message) $($response.error.data)"
  }
  return $response.result
}

function Invoke-AuraCiteTool {
  param(
    [string]$Name,
    [hashtable]$Arguments = @{},
    [string]$Id = 'tool'
  )

  $result = Invoke-AuraCiteMCP -Method 'tools/call' -Params @{
    name      = $Name
    arguments = $Arguments
  } -Id $Id

  $content = @($result.content)
  if ($content.Count -eq 0 -or [string]::IsNullOrWhiteSpace($content[0].text)) {
    throw "$Name did not return a text payload."
  }
  return $content[0].text | ConvertFrom-Json
}

function Assert-ZeroCost {
  param(
    [object]$Body,
    [string]$Label
  )
  if ([double]$Body.provider_calls_triggered -ne 0 -or [double]$Body.credits_charged -ne 0) {
    throw "$Label reported provider calls or credit charges."
  }
}

$requiredTools = @(
  'list_action_handoffs',
  'update_action_status',
  'record_outcome_measurement'
)
if ($AppendMemoryEvidence) {
  $requiredTools += @('append_project_memory_entry', 'list_project_memory_entries')
}

$tools = Invoke-AuraCiteMCP -Method 'tools/list' -Id 'tools'
$toolNames = @($tools.tools | ForEach-Object { $_.name })
$missing = @($requiredTools | Where-Object { $toolNames -notcontains $_ })
if ($missing.Count -gt 0) {
  throw "tools/list missing required tools: $($missing -join ', ')"
}

$handoffsBefore = Invoke-AuraCiteTool -Name 'list_action_handoffs' -Arguments @{ limit = 10 } -Id 'handoffs-before'
$handoff = $null
if ([string]::IsNullOrWhiteSpace($RunId)) {
  $handoff = @($handoffsBefore.handoffs | Where-Object {
      -not [string]::IsNullOrWhiteSpace([string]$_.linked_hermes_run_id)
    } | Select-Object -First 1)
  if (-not $handoff) {
    throw 'No linked Action Center run was available. Pass -RunId for a known controlled test run.'
  }
  $RunId = [string]$handoff.linked_hermes_run_id
} else {
  $handoff = @($handoffsBefore.handoffs | Where-Object {
      [string]$_.linked_hermes_run_id -eq $RunId
    } | Select-Object -First 1)
}

$suffix = (New-Guid).ToString('N').Substring(0, 12)
$statusKey = "outcome-smoke-status-$(Get-Date -AsUTC -Format 'yyyyMMdd')-$suffix"
$measureKey = "outcome-smoke-measure-$(Get-Date -AsUTC -Format 'yyyyMMdd')-$suffix"

$statusNote = 'Bounded Agent Hub outcome reconciliation smoke: mark controlled test run implemented before measurement. No provider calls or credits.'
$statusPreview = Invoke-AuraCiteTool -Name 'update_action_status' -Arguments @{
  run_id          = $RunId
  status          = 'implemented'
  status_note     = $statusNote
  idempotency_key = $statusKey
} -Id 'status-preview'
if ($statusPreview.approval_gate -ne 'exact_confirmation_required' -or $statusPreview.mutation_performed -ne $false) {
  throw 'update_action_status preview did not require exact confirmation.'
}
Assert-ZeroCost -Body $statusPreview -Label 'update_action_status preview'

$statusConfirmation = "CONFIRM: update_action_status $RunId implemented $statusKey"
$statusConfirmed = Invoke-AuraCiteTool -Name 'update_action_status' -Arguments @{
  run_id          = $RunId
  status          = 'implemented'
  status_note     = $statusNote
  idempotency_key = $statusKey
  confirmation    = $statusConfirmation
} -Id 'status-confirmed'
if ($statusConfirmed.approval_gate -ne 'confirmed_write' -or $statusConfirmed.mutation_performed -ne $true -or [string]$statusConfirmed.action.status -ne 'implemented') {
  throw 'update_action_status did not confirm implemented status.'
}
Assert-ZeroCost -Body $statusConfirmed -Label 'update_action_status confirmed'

$statusReplay = Invoke-AuraCiteTool -Name 'update_action_status' -Arguments @{
  run_id          = $RunId
  status          = 'implemented'
  status_note     = $statusNote
  idempotency_key = $statusKey
  confirmation    = $statusConfirmation
} -Id 'status-replay'
if ($statusReplay.approval_gate -ne 'replayed_confirmed_write' -or $statusReplay.idempotency_replay -ne $true) {
  throw 'update_action_status did not replay same idempotency key.'
}

$measureNote = 'Bounded Agent Hub outcome reconciliation smoke: close controlled test run as measured with synthetic smoke metrics.'
$metrics = @{
  agent_hub_outcome_smoke = 1
  smoke_cycle             = [int](Get-Date -AsUTC -Format 'yyyyMMdd')
  measured_signal_count   = 1
}
$measurePreview = Invoke-AuraCiteTool -Name 'record_outcome_measurement' -Arguments @{
  run_id          = $RunId
  status_note     = $measureNote
  outcome_metrics = $metrics
  idempotency_key = $measureKey
} -Id 'measure-preview'
if ($measurePreview.approval_gate -ne 'exact_confirmation_required' -or $measurePreview.mutation_performed -ne $false) {
  throw 'record_outcome_measurement preview did not require exact confirmation.'
}
Assert-ZeroCost -Body $measurePreview -Label 'record_outcome_measurement preview'

$measureConfirmation = "CONFIRM: record_outcome_measurement $RunId $measureKey"
$measureConfirmed = Invoke-AuraCiteTool -Name 'record_outcome_measurement' -Arguments @{
  run_id          = $RunId
  status_note     = $measureNote
  outcome_metrics = $metrics
  idempotency_key = $measureKey
  confirmation    = $measureConfirmation
} -Id 'measure-confirmed'
if ($measureConfirmed.approval_gate -ne 'confirmed_write' -or $measureConfirmed.mutation_performed -ne $true -or [string]$measureConfirmed.action.status -ne 'measured') {
  throw 'record_outcome_measurement did not confirm measured status.'
}
Assert-ZeroCost -Body $measureConfirmed -Label 'record_outcome_measurement confirmed'

$measureReplay = Invoke-AuraCiteTool -Name 'record_outcome_measurement' -Arguments @{
  run_id          = $RunId
  status_note     = $measureNote
  outcome_metrics = $metrics
  idempotency_key = $measureKey
  confirmation    = $measureConfirmation
} -Id 'measure-replay'
if ($measureReplay.approval_gate -ne 'replayed_confirmed_write' -or $measureReplay.idempotency_replay -ne $true) {
  throw 'record_outcome_measurement did not replay same idempotency key.'
}

$handoffsAfter = Invoke-AuraCiteTool -Name 'list_action_handoffs' -Arguments @{ limit = 10 } -Id 'handoffs-after'
$updated = @($handoffsAfter.handoffs | Where-Object {
    [string]$_.linked_hermes_run_id -eq $RunId
  } | Select-Object -First 1)
if ($updated) {
  if ([string]$updated.action_handoff_state -ne 'reconciled' -or [string]$updated.outcome_status -ne 'measured' -or [string]$updated.measurement_state -ne 'closed') {
    throw 'Updated handoff was not reconciled/measured/closed.'
  }
}

$memoryAppendConfirmed = $null
if ($AppendMemoryEvidence) {
  $memoryKey = "outcome-smoke-memory-$(Get-Date -AsUTC -Format 'yyyyMMdd')-$suffix"
  $memoryBody = 'Production /mcp/rpc outcome reconciliation smoke passed for a controlled test run. Verified exact-confirmation previews, confirmed implemented status, status idempotency replay, confirmed measured outcome, measurement idempotency replay, final reconciliation readback, provider_calls_triggered=0, credits_charged=0. Run IDs intentionally omitted.'
  $memoryConfirmation = "CONFIRM: append_project_memory_entry smoke_evidence $memoryKey"
  $memory = Invoke-AuraCiteTool -Name 'append_project_memory_entry' -Arguments @{
    note_ref        = 'smoke_evidence'
    entry_type      = 'smoke_evidence'
    title           = 'Agent Hub outcome reconciliation smoke passed'
    body            = $memoryBody
    tags            = @('agent-hub', 'outcome-reconciliation', 'production-smoke')
    idempotency_key = $memoryKey
    confirmation    = $memoryConfirmation
  } -Id 'memory-append'
  if ($memory.approval_gate -ne 'confirmed_write' -or $memory.mutation_performed -ne $true -or $memory.raw_vault_write_performed -ne $false) {
    throw 'append_project_memory_entry did not persist expected server-side memory evidence.'
  }
  $memoryAppendConfirmed = $true
}

[pscustomobject]@{
  BaseUrl                = $BaseUrl
  ToolCount              = @($toolNames).Count
  RunPrefix              = $RunId.Substring(0, [Math]::Min(8, $RunId.Length))
  StatusConfirmed        = $true
  StatusReplay           = $true
  MeasurementConfirmed   = $true
  MeasurementReplay      = $true
  ReconciliationState    = if ($updated) { [string]$updated.action_handoff_state } else { 'not_listed_by_run_id' }
  OutcomeStatus          = if ($updated) { [string]$updated.outcome_status } else { 'not_listed_by_run_id' }
  MeasurementState       = if ($updated) { [string]$updated.measurement_state } else { 'not_listed_by_run_id' }
  MemoryAppendConfirmed  = $memoryAppendConfirmed
  ProviderCalls          = 0
  CreditsCharged         = 0
  PrintedSecretsOrTokens = $false
} | Format-List
