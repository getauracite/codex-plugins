<#
.SYNOPSIS
Runs the customer-facing AuraCite Agent Hub read-only health check.

.DESCRIPTION
Uses AURACITE_MCP_TOKEN from the caller's environment, verifies the hosted
JSON-RPC read path, checks core Agent Hub read/draft tools, and prints a
secret-safe summary. It never prints the token.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [switch]$CallDraftTools
)

$ErrorActionPreference = 'Stop'

if ([string]::IsNullOrWhiteSpace($env:AURACITE_MCP_TOKEN)) {
  throw 'AURACITE_MCP_TOKEN is required. Create a read-only Agent Hub connection in AuraCite Settings and set the token outside the repo.'
}

if ([string]::IsNullOrWhiteSpace($env:AURACITE_MCP_RPC_URL)) {
  $env:AURACITE_MCP_RPC_URL = $BaseUrl.TrimEnd('/') + '/mcp/rpc'
}

if ([string]::IsNullOrWhiteSpace($env:AURACITE_MCP_BRIDGE_MODE)) {
  $env:AURACITE_MCP_BRIDGE_MODE = 'safe'
}

if ($env:AURACITE_MCP_BRIDGE_MODE -ne 'safe') {
  throw 'Customer health check expects AURACITE_MCP_BRIDGE_MODE=safe.'
}

$readSmoke = Join-Path $PluginRoot 'scripts\smoke-jsonrpc-read.ps1'
$smokeArgs = @(
  '-NoProfile',
  '-ExecutionPolicy', 'Bypass',
  '-File', $readSmoke,
  '-BaseUrl', $BaseUrl
)
if ($CallDraftTools) {
  $smokeArgs += '-CallDraftTools'
}

& pwsh @smokeArgs
if ($LASTEXITCODE -ne 0) {
  throw "Agent Hub read-only health check failed with exit code $LASTEXITCODE."
}

[pscustomobject]@{
  agent_hub_health_check = 'passed'
  base_url = $BaseUrl
  rpc_url_present = -not [string]::IsNullOrWhiteSpace($env:AURACITE_MCP_RPC_URL)
  bridge_mode = $env:AURACITE_MCP_BRIDGE_MODE
  token_present = -not [string]::IsNullOrWhiteSpace($env:AURACITE_MCP_TOKEN)
  call_draft_tools = [bool]$CallDraftTools
  printed_secrets_or_tokens = $false
} | ConvertTo-Json -Depth 4
