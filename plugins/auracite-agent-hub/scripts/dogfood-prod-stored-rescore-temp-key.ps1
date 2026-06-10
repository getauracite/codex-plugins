<#
.SYNOPSIS
Runs a secret-safe production stored-rescore smoke for AuraCite Agent Hub.

.DESCRIPTION
Logs in with the local SecretManagement production test credential, creates a
short-lived mcp:write key, verifies the exact-confirmation preview for
trigger_intelligence_refresh, runs the confirmed stored_rescore, verifies
idempotency replay, revokes the key, and checks that the revoked key fails
closed. It never prints the password, login token, MCP key, cookies, or raw
secret values.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$VaultName = 'AuraCiteLocal',
  [string]$SecretName = 'AuraCiteProdLogin',
  [int]$KeyTtlMinutes = 30,
  [string]$IdempotencyKey = ('prod-stored-rescore-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($pwsh) {
    & $pwsh.Source -NoProfile -ExecutionPolicy Bypass -File $PSCommandPath `
      -BaseUrl $BaseUrl `
      -VaultName $VaultName `
      -SecretName $SecretName `
      -KeyTtlMinutes $KeyTtlMinutes `
      -IdempotencyKey $IdempotencyKey
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
    $jsonBody = $Body | ConvertTo-Json -Depth 20
  }

  Invoke-RestMethod `
    -Method $Method `
    -Uri $Url `
    -ContentType 'application/json' `
    -Body $jsonBody `
    -WebSession $Session `
    -Headers $Headers `
    -TimeoutSec 60
}

function Invoke-MCPTool {
  param(
    [Parameter(Mandatory = $true)][string]$Name,
    [Parameter(Mandatory = $true)][hashtable]$Arguments,
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [int]$Id = 1
  )

  $response = Invoke-AuraCiteJson `
    -Method Post `
    -Url $Endpoint `
    -Body @{
      jsonrpc = '2.0'
      id = $Id
      method = 'tools/call'
      params = @{
        name = $Name
        arguments = $Arguments
      }
    } `
    -Headers @{ 'X-API-Key' = $ApiKey }

  if ($null -ne $response.error) {
    throw "MCP tool '$Name' failed: $($response.error.message)"
  }

  $content = @($response.result.content)
  if ($content.Count -eq 0 -or [string]::IsNullOrWhiteSpace([string]$content[0].text)) {
    throw "MCP tool '$Name' did not return a text payload."
  }

  return ([string]$content[0].text | ConvertFrom-Json)
}

$credential = Get-Secret -Name $SecretName -Vault $VaultName
if (-not $credential -or -not ($credential -is [pscredential])) {
  throw "Secret '$SecretName' was not found as a PSCredential in vault '$VaultName'."
}

$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$plainPassword = $credential.GetNetworkCredential().Password
$createdKey = $null
$tenantID = $null
$projectID = $null
$temporaryKeyCreated = $false
$temporaryKeyRevoked = $false
$previewBody = $null
$confirmedBody = $null
$replayBody = $null

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
      name = 'codex-agent-hub-stored-rescore-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
      scopes = @('mcp:write')
      rate_limit_rpm = 30
      expires_at = (Get-Date).ToUniversalTime().AddMinutes($KeyTtlMinutes).ToString('o')
    } `
    -Session $session

  if ([string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
    throw 'API key creation did not return a one-time full_key.'
  }
  $temporaryKeyCreated = $true

  $endpoint = Join-Url $BaseUrl '/mcp/rpc'
  $apiKey = [string]$createdKey.full_key
  $baseArgs = @{
    refresh_type = 'stored_rescore'
    idempotency_key = $IdempotencyKey
  }

  $previewBody = Invoke-MCPTool `
    -Name 'trigger_intelligence_refresh' `
    -Arguments $baseArgs `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Id 1

  $requiredConfirmation = [string]$previewBody.required_confirmation
  $expectedConfirmation = "CONFIRM: trigger_intelligence_refresh stored_rescore $IdempotencyKey"
  if ($previewBody.approval_gate -ne 'exact_confirmation_required' -or $requiredConfirmation -ne $expectedConfirmation) {
    throw 'Stored-rescore preview did not return the expected exact-confirmation gate.'
  }

  $confirmedArgs = @{
    refresh_type = 'stored_rescore'
    idempotency_key = $IdempotencyKey
    confirmation = $requiredConfirmation
  }
  $confirmedBody = Invoke-MCPTool `
    -Name 'trigger_intelligence_refresh' `
    -Arguments $confirmedArgs `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Id 2

  $replayBody = Invoke-MCPTool `
    -Name 'trigger_intelligence_refresh' `
    -Arguments $confirmedArgs `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Id 3
}
finally {
  $plainPassword = $null

  if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.api_key_id) -and -not [string]::IsNullOrWhiteSpace($tenantID) -and -not [string]::IsNullOrWhiteSpace($projectID)) {
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
}

$revokedRejected = $false
if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
  try {
    $revokedResponse = Invoke-AuraCiteJson `
      -Method Post `
      -Url (Join-Url $BaseUrl '/mcp/rpc') `
      -Body @{
        jsonrpc = '2.0'
        id = 'revoked-stored-rescore-check'
        method = 'tools/list'
        params = @{}
      } `
      -Headers @{ 'X-API-Key' = [string]$createdKey.full_key }

    $revokedRejected = ($null -ne $revokedResponse.error)
  } catch {
    $revokedRejected = $true
  }
}

$refreshResult = $null
if ($confirmedBody -and $confirmedBody.refresh_result) {
  $refreshResult = $confirmedBody.refresh_result
}

[pscustomobject]@{
  base_url = $BaseUrl
  tenant_id_present = -not [string]::IsNullOrWhiteSpace($tenantID)
  project_id_present = -not [string]::IsNullOrWhiteSpace($projectID)
  scope = 'mcp:write'
  idempotency_key_present = -not [string]::IsNullOrWhiteSpace($IdempotencyKey)
  preview_gate = $previewBody.approval_gate
  confirmed_gate = $confirmedBody.approval_gate
  replay_gate = $replayBody.approval_gate
  confirmed_mutation_performed = $confirmedBody.mutation_performed
  confirmed_idempotency_replay = [bool]$confirmedBody.idempotency_replay
  replay_idempotency_replay = [bool]$replayBody.idempotency_replay
  source_data_refreshed = [bool]$confirmedBody.source_data_refreshed
  provider_calls_triggered = [double]$confirmedBody.provider_calls_triggered
  credits_charged = [double]$confirmedBody.credits_charged
  refresh_upserted = if ($refreshResult) { $refreshResult.upserted } else { $null }
  refresh_skipped = if ($refreshResult) { $refreshResult.skipped } else { $null }
  temporary_key_created = $temporaryKeyCreated
  temporary_key_revoked = $temporaryKeyRevoked
  revoked_key_rejected = $revokedRejected
  printed_secrets_or_tokens = $false
} | ConvertTo-Json -Depth 8
