<#
.SYNOPSIS
Runs a secret-safe AuraCite Agent Hub production Intelligence refresh-plan inspection.

.DESCRIPTION
Logs in with the local SecretManagement production test credential, creates a
short-lived mcp:read key, runs inspect-intelligence-refresh-plan.ps1, revokes
the key in a finally block, and verifies that the revoked key fails closed.
It prints refresh source metadata only; it never prints the password, login
token, MCP key, cookies, or raw secret values.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$VaultName = 'AuraCiteLocal',
  [string]$SecretName = 'AuraCiteProdLogin',
  [string]$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [int]$KeyTtlMinutes = 30,
  [int]$Limit = 25,
  [int]$PlanLimit = 10
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($pwsh) {
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
      -BaseUrl $BaseUrl `
      -VaultName $VaultName `
      -SecretName $SecretName `
      -PluginRoot $PluginRoot `
      -KeyTtlMinutes $KeyTtlMinutes `
      -Limit $Limit `
      -PlanLimit $PlanLimit
    exit $LASTEXITCODE
  }
}

Import-Module Microsoft.PowerShell.SecretManagement

function Join-Url {
  param(
    [string]$Root,
    [string]$Path
  )
  return $Root.TrimEnd('/') + '/' + $Path.TrimStart('/')
}

function Invoke-AuraCiteJson {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Url,
    [object]$Body,
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session,
    [hashtable]$Headers
  )

  $jsonBody = $null
  if ($null -ne $Body) {
    $jsonBody = $Body | ConvertTo-Json -Depth 10
  }

  Invoke-RestMethod `
    -Method $Method `
    -Uri $Url `
    -ContentType 'application/json' `
    -Body $jsonBody `
    -WebSession $Session `
    -Headers $Headers `
    -TimeoutSec 45
}

$credential = Get-Secret -Name $SecretName -Vault $VaultName
if (-not $credential -or -not ($credential -is [pscredential])) {
  throw "Secret '$SecretName' was not found as a PSCredential in vault '$VaultName'."
}

$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$plainPassword = $credential.GetNetworkCredential().Password
$createdKey = $null
$temporaryKeyCreated = $false
$temporaryKeyRevoked = $false
$previousToken = $env:AURACITE_MCP_TOKEN
$previousRPCURL = $env:AURACITE_MCP_RPC_URL
$previousMode = $env:AURACITE_MCP_BRIDGE_MODE
$inspectStatus = 'pending'
$inspectSummary = $null

try {
  $login = Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl '/api/v1/auth/login') `
    -Body @{
      email = $credential.UserName
      password = $plainPassword
    } `
    -Session $session

  $tenantID = [string]$login.tenant_id
  $projectID = [string]$login.project_id
  if ([string]::IsNullOrWhiteSpace($tenantID) -or [string]::IsNullOrWhiteSpace($projectID)) {
    throw 'Login response did not include tenant_id/project_id.'
  }

  $createdKey = Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl "/api/tenants/$tenantID/projects/$projectID/api-keys") `
    -Body @{
      name = 'codex-agent-hub-refresh-plan-read-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
      scopes = @('mcp:read')
      rate_limit_rpm = 60
      expires_at = (Get-Date).ToUniversalTime().AddMinutes($KeyTtlMinutes).ToString('o')
    } `
    -Session $session

  if ([string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
    throw 'API key creation did not return a one-time full_key.'
  }
  $temporaryKeyCreated = $true

  $env:AURACITE_MCP_TOKEN = [string]$createdKey.full_key
  $env:AURACITE_MCP_RPC_URL = (Join-Url $BaseUrl '/mcp/rpc')
  $env:AURACITE_MCP_BRIDGE_MODE = 'safe'

  $inspectScript = Join-Path $PluginRoot 'scripts\inspect-intelligence-refresh-plan.ps1'
  $inspectJson = & pwsh -NoProfile -ExecutionPolicy Bypass -File $inspectScript -BaseUrl $BaseUrl -Limit $Limit -PlanLimit $PlanLimit
  if ($LASTEXITCODE -ne 0) {
    throw "inspect-intelligence-refresh-plan.ps1 failed with exit code $LASTEXITCODE."
  }
  $inspectSummary = $inspectJson | ConvertFrom-Json
  $inspectStatus = 'passed'
}
finally {
  $plainPassword = $null

  if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.api_key_id)) {
    try {
      Invoke-AuraCiteJson `
        -Method Delete `
        -Url (Join-Url $BaseUrl "/api/tenants/$tenantID/projects/$projectID/api-keys/$($createdKey.api_key_id)") `
        -Session $session | Out-Null
      $temporaryKeyRevoked = $true
    } catch {
      Write-Warning 'Temporary MCP key revoke failed; revoke it manually from the AuraCite API Keys UI.'
    }
  }

  $env:AURACITE_MCP_TOKEN = $previousToken
  $env:AURACITE_MCP_RPC_URL = $previousRPCURL
  $env:AURACITE_MCP_BRIDGE_MODE = $previousMode
}

$revokedRejected = $false
if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
  try {
    $revokedResponse = Invoke-AuraCiteJson `
      -Method Post `
      -Url (Join-Url $BaseUrl '/mcp/rpc') `
      -Body @{
        jsonrpc = '2.0'
        id = 'revoked-check'
        method = 'tools/list'
        params = @{}
      } `
      -Headers @{ 'X-API-Key' = [string]$createdKey.full_key }

    $revokedRejected = ($null -ne $revokedResponse.error)
  } catch {
    $revokedRejected = $true
  }
}

[pscustomobject]@{
  base_url = $BaseUrl
  tenant_id_present = -not [string]::IsNullOrWhiteSpace($tenantID)
  project_id_present = -not [string]::IsNullOrWhiteSpace($projectID)
  scope = 'mcp:read'
  inspect_status = $inspectStatus
  temporary_key_created = $temporaryKeyCreated
  temporary_key_revoked = $temporaryKeyRevoked
  revoked_key_rejected = $revokedRejected
  printed_secrets_or_tokens = $false
  refresh_plan = $inspectSummary
} | ConvertTo-Json -Depth 10
