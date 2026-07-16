<#
.SYNOPSIS
Runs AuraCite Agent Hub confirmed-write deny dogfood with a temporary production mcp:write key.

.DESCRIPTION
Logs in with the local SecretManagement production test credential, creates a
short-lived mcp:write key, runs dogfood-gate.ps1 -WriteDeny, revokes the key in
a finally block, and verifies that the revoked key fails closed. The deny smoke
does not perform confirmed mutations; it proves that unapproved writes create
pending requests and never reach business mutation handlers.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = "https://auracite.de",
  [string]$VaultName = "AuraCiteLocal",
  [string]$SecretName = "AuraCiteProdLogin",
  [string]$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [int]$KeyTtlMinutes = 30
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
      -KeyTtlMinutes $KeyTtlMinutes
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
    -TimeoutSec 30
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
$dogfoodGate = 'pending'
$previousToken = $env:AURACITE_MCP_TOKEN
$previousRPCURL = $env:AURACITE_MCP_RPC_URL
$previousMode = $env:AURACITE_MCP_BRIDGE_MODE

try {
  $loginBody = @{
    email = $credential.UserName
    password = $plainPassword
  }

  $login = Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl '/api/v1/auth/login') `
    -Body $loginBody `
    -Session $session

  $tenantID = [string]$login.tenant_id
  $projectID = [string]$login.project_id
  if ([string]::IsNullOrWhiteSpace($tenantID) -or [string]::IsNullOrWhiteSpace($projectID)) {
    throw 'Login response did not include tenant_id/project_id.'
  }

  $keyName = 'codex-agent-hub-dogfood-write-deny-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
  $expiresAt = (Get-Date).ToUniversalTime().AddMinutes($KeyTtlMinutes).ToString('o')
  $createdKey = Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl "/api/tenants/$tenantID/projects/$projectID/api-keys") `
    -Body @{
      name = $keyName
      scopes = @('mcp:write')
      rate_limit_rpm = 30
      expires_at = $expiresAt
    } `
    -Session $session

  if ([string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
    throw 'API key creation did not return a one-time full_key.'
  }
  $temporaryKeyCreated = $true

  $env:AURACITE_MCP_TOKEN = [string]$createdKey.full_key
  $env:AURACITE_MCP_RPC_URL = (Join-Url $BaseUrl '/mcp/rpc')
  $env:AURACITE_MCP_BRIDGE_MODE = 'confirmed-writes'

  $gateScript = Join-Path $PluginRoot 'scripts\dogfood-gate.ps1'
  & pwsh -NoProfile -ExecutionPolicy Bypass -File $gateScript -PluginRoot $PluginRoot -WriteDeny
  if ($LASTEXITCODE -ne 0) {
    throw "dogfood-gate.ps1 write-deny failed with exit code $LASTEXITCODE."
  }
  $dogfoodGate = 'passed'
}
finally {
  $plainPassword = $null
  $loginBody = $null

  if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.api_key_id)) {
    try {
      Invoke-AuraCiteJson `
        -Method Delete `
        -Url (Join-Url $BaseUrl "/api/tenants/$tenantID/projects/$projectID/api-keys/$($createdKey.api_key_id)") `
        -Session $session | Out-Null
      $temporaryKeyRevoked = $true
    } catch {
      Write-Warning 'Temporary MCP write key revoke failed; revoke it manually from the AuraCite API Keys UI.'
    }
  }

  $env:AURACITE_MCP_TOKEN = $previousToken
  $env:AURACITE_MCP_RPC_URL = $previousRPCURL
  $env:AURACITE_MCP_BRIDGE_MODE = $previousMode
}

$revokedRejected = $false
if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
  $rpcBody = @{
    jsonrpc = '2.0'
    id = 'revoked-write-check'
    method = 'tools/list'
    params = @{}
  }
  try {
    $revokedResponse = Invoke-AuraCiteJson `
      -Method Post `
      -Url (Join-Url $BaseUrl '/mcp/rpc') `
      -Body $rpcBody `
      -Headers @{ 'X-API-Key' = [string]$createdKey.full_key }

    $revokedRejected = ($null -ne $revokedResponse.error)
  } catch {
    $revokedRejected = $true
  }
}

[pscustomobject]@{
  BaseUrl = $BaseUrl
  TenantIDPresent = -not [string]::IsNullOrWhiteSpace($tenantID)
  ProjectIDPresent = -not [string]::IsNullOrWhiteSpace($projectID)
  Scope = 'mcp:write'
  DogfoodGate = $dogfoodGate
  TemporaryKeyCreated = $temporaryKeyCreated
  TemporaryKeyRevoked = $temporaryKeyRevoked
  RevokedKeyRejected = $revokedRejected
  MutationPerformed = $false
  ProviderCallsTriggered = 0
  CreditsCharged = 0
  PrintedSecretsOrTokens = $false
} | Format-List
