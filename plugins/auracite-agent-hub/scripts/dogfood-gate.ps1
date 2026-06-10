param(
  [string]$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [switch]$LiveRead,
  [switch]$CallDraftTools,
  [switch]$ScenarioSessions,
  [switch]$WriteDeny,
  [switch]$OutcomeReconciliation,
  [switch]$AppendMemoryEvidence,
  [switch]$IUnderstandOutcomeSmokeMutatesAControlledRun
)

$ErrorActionPreference = 'Stop'

function Invoke-Step {
  param(
    [string]$Name,
    [scriptblock]$Script
  )

  Write-Host "==> $Name"
  $global:LASTEXITCODE = 0
  & $Script
  if ($LASTEXITCODE -ne 0) {
    throw "$Name failed with exit code $LASTEXITCODE."
  }
  Write-Host "ok: $Name"
}

function Require-Token {
  param([string]$Reason)

  if ([string]::IsNullOrWhiteSpace($env:AURACITE_MCP_TOKEN)) {
    throw "AURACITE_MCP_TOKEN is required for $Reason. Set it outside the repo and never commit or print it."
  }
}

$scriptsRoot = Join-Path $PluginRoot 'scripts'
$validateScript = Join-Path $scriptsRoot 'validate-plugin.ps1'
$bridgeTest = Join-Path $scriptsRoot 'test-jsonrpc-bridge.mjs'
$liveBridgeSmoke = Join-Path $scriptsRoot 'smoke-jsonrpc-bridge-live.mjs'
$scenarioSessionsScript = Join-Path $scriptsRoot 'dogfood-jsonrpc-sessions.mjs'
$readSmoke = Join-Path $scriptsRoot 'smoke-jsonrpc-read.ps1'
$writeDenySmoke = Join-Path $scriptsRoot 'smoke-jsonrpc-write-deny.ps1'
$outcomeSmoke = Join-Path $scriptsRoot 'smoke-jsonrpc-outcome-reconciliation.ps1'

if (-not (Get-Command node -ErrorAction SilentlyContinue)) {
  throw 'Node.js is required for the AuraCite Agent Hub dogfood gate.'
}

$summary = [ordered]@{
  plugin_root = $PluginRoot
  package_validation = 'pending'
  local_bridge_unit = 'pending'
  live_bridge_read = 'skipped'
  live_jsonrpc_read = 'skipped'
  scenario_sessions = 'skipped'
  live_write_deny = 'skipped'
  outcome_reconciliation = 'skipped'
  printed_secrets_or_tokens = $false
}

Invoke-Step 'package validation' {
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $validateScript -PluginRoot $PluginRoot
  $summary.package_validation = 'passed'
}

Invoke-Step 'local bridge unit smoke' {
  & node $bridgeTest
  $summary.local_bridge_unit = 'passed'
}

if ($LiveRead) {
  Require-Token 'live read dogfood'

  Invoke-Step 'live bridge read smoke' {
    & node $liveBridgeSmoke
    $summary.live_bridge_read = 'passed'
  }

  Invoke-Step 'live JSON-RPC read smoke' {
    if ($CallDraftTools) {
      & pwsh -NoProfile -ExecutionPolicy Bypass -File $readSmoke -CallDraftTools
    } else {
      & pwsh -NoProfile -ExecutionPolicy Bypass -File $readSmoke
    }
    $summary.live_jsonrpc_read = 'passed'
  }
}

if ($ScenarioSessions) {
  Require-Token 'scenario session dogfood'

  Invoke-Step 'real plugin scenario sessions' {
    & node $scenarioSessionsScript
    $summary.scenario_sessions = 'passed'
  }
}

if ($WriteDeny) {
  Require-Token 'write-deny dogfood'

  Invoke-Step 'live write-deny smoke' {
    & pwsh -NoProfile -ExecutionPolicy Bypass -File $writeDenySmoke
    $summary.live_write_deny = 'passed'
  }
}

if ($OutcomeReconciliation) {
  Require-Token 'outcome reconciliation dogfood'

  if (-not $IUnderstandOutcomeSmokeMutatesAControlledRun) {
    throw 'Outcome reconciliation mutates a controlled Action Center run. Re-run with -IUnderstandOutcomeSmokeMutatesAControlledRun only for an approved internal run.'
  }

  Invoke-Step 'bounded outcome reconciliation smoke' {
    if ($AppendMemoryEvidence) {
      & pwsh -NoProfile -ExecutionPolicy Bypass -File $outcomeSmoke -IUnderstandThisMutatesAControlledRun -AppendMemoryEvidence
    } else {
      & pwsh -NoProfile -ExecutionPolicy Bypass -File $outcomeSmoke -IUnderstandThisMutatesAControlledRun
    }
    $summary.outcome_reconciliation = 'passed'
  }
}

Write-Host 'AuraCite Agent Hub dogfood gate summary:'
$summary | ConvertTo-Json -Depth 4
