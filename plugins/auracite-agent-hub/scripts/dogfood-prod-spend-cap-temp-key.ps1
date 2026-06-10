<#
.SYNOPSIS
Runs a secret-safe production mcp:spend cap smoke with a temporary API key.

.DESCRIPTION
Logs in with the local SecretManagement production test credential, creates a
short-lived mcp:spend key, verifies hosted MCP exposes spend tools but not
write-only tools, checks missing approval fails closed, verifies max_credits
and max_usd caps block prompt generation before credits/provider calls, revokes
the key, and verifies the revoked key fails closed.

This smoke is intentionally zero-cost: it does not run a successful provider
call. Use a separate explicitly approved live smoke for real provider spend.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = 'https://auracite.de',
  [string]$VaultName = 'AuraCiteLocal',
  [string]$SecretName = 'AuraCiteProdLogin',
  [int]$KeyTtlMinutes = 30,
  [string]$IdempotencyPrefix = ('prod-spend-cap-' + (Get-Date -Format 'yyyyMMdd-HHmmss'))
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
      -IdempotencyPrefix $IdempotencyPrefix
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

function Invoke-MCPRPC {
  param(
    [Parameter(Mandatory = $true)][string]$Endpoint,
    [Parameter(Mandatory = $true)][string]$ApiKey,
    [Parameter(Mandatory = $true)][string]$Method,
    [object]$Params = @{},
    [string]$Id = ([guid]::NewGuid().ToString())
  )

  Invoke-AuraCiteJson `
    -Method Post `
    -Url $Endpoint `
    -Body @{
      jsonrpc = '2.0'
      id = $Id
      method = $Method
      params = $Params
    } `
    -Headers @{ 'X-API-Key' = $ApiKey }
}

function Get-MCPToolText {
  param([object]$Response)

  if ($null -ne $Response.error) {
    return [string]$Response.error.message
  }
  $content = @($Response.result.content)
  if ($content.Count -eq 0) {
    return ''
  }
  $raw = [string]$content[0].text
  try {
    $parsed = $raw | ConvertFrom-Json
    if ($parsed -is [string]) {
      return $parsed
    }
  } catch {
    return $raw
  }
  return $raw
}

function Approve-MCPQuote {
  param(
    [Parameter(Mandatory = $true)][string]$BaseUrl,
    [Parameter(Mandatory = $true)][string]$TenantID,
    [Parameter(Mandatory = $true)][string]$ProjectID,
    [Parameter(Mandatory = $true)][string]$ApiKeyID,
    [Parameter(Mandatory = $true)][string]$ToolName,
    [Parameter(Mandatory = $true)][hashtable]$Arguments,
    [Parameter(Mandatory = $true)][int]$MaxCredits,
    [double]$MaxUsd = 0,
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  $body = @{
    api_key_id = $ApiKeyID
    tool_name = $ToolName
    arguments = $Arguments
    max_credits = $MaxCredits
    ttl_seconds = 600
    confirmation_text = 'APPROVE MCP EXECUTION'
    description = 'Codex production mcp:spend cap smoke'
  }
  if ($MaxUsd -gt 0) {
    $body.max_usd = $MaxUsd
  }

  Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl "/api/tenants/$TenantID/projects/$ProjectID/mcp/execution-quotes/approve") `
    -Body $body `
    -Session $Session
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
$spendToolsVisible = $false
$writeOnlyHidden = $false
$missingApprovalBlocked = $false
$creditCapBlocked = $false
$usdCapBlocked = $false
$revokedRejected = $false

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
      name = 'codex-agent-hub-spend-cap-' + (Get-Date -Format 'yyyyMMdd-HHmmss')
      scopes = @('mcp:spend')
      rate_limit_rpm = 20
      expires_at = (Get-Date).ToUniversalTime().AddMinutes($KeyTtlMinutes).ToString('o')
    } `
    -Session $session

  if ([string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
    throw 'API key creation did not return a one-time full_key.'
  }
  $temporaryKeyCreated = $true

  $endpoint = Join-Url $BaseUrl '/mcp/rpc'
  $apiKey = [string]$createdKey.full_key

  $toolsResponse = Invoke-MCPRPC -Endpoint $endpoint -ApiKey $apiKey -Method 'tools/list' -Id 'spend-tools-list'
  if ($null -ne $toolsResponse.error) {
    throw "tools/list failed: $($toolsResponse.error.message)"
  }
  $toolNames = @($toolsResponse.result.tools | ForEach-Object { [string]$_.name })
  $spendToolsVisible = ($toolNames -contains 'generate_ai_prompts') -and ($toolNames -contains 'trigger_scan')
  $writeOnlyHidden = -not ($toolNames -contains 'add_brand')
  if (-not $spendToolsVisible) {
    throw "mcp:spend tools/list did not expose expected spend tools. Tools: $($toolNames -join ', ')"
  }
  if (-not $writeOnlyHidden) {
    throw 'mcp:spend tools/list exposed write-only add_brand.'
  }

  $baseArgs = @{
    url = 'https://auracite.de'
    brand_name = 'AuraCite'
    count = 1
  }

  $missingApproval = Invoke-MCPRPC `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Method 'tools/call' `
    -Id 'missing-approval' `
    -Params @{
      name = 'generate_ai_prompts'
      arguments = @{
        url = $baseArgs.url
        brand_name = $baseArgs.brand_name
        count = $baseArgs.count
        max_credits = 1
      }
    }
  $missingApprovalBlocked = ($null -ne $missingApproval.error) -and ([string]$missingApproval.error.data -like '*execution approval*')
  if (-not $missingApprovalBlocked) {
    throw 'generate_ai_prompts without quote did not fail closed on execution approval.'
  }

  $scanArgs = @{
    models = 'chatgpt'
  }

  $creditQuote = Approve-MCPQuote `
    -BaseUrl $BaseUrl `
    -TenantID $tenantID `
    -ProjectID $projectID `
    -ApiKeyID ([string]$createdKey.api_key_id) `
    -ToolName 'trigger_scan' `
    -Arguments $scanArgs `
    -MaxCredits 1 `
    -Session $session

  $creditCapResponse = Invoke-MCPRPC `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Method 'tools/call' `
    -Id 'credit-cap' `
    -Params @{
      name = 'trigger_scan'
      arguments = @{
        models = $scanArgs.models
        quote_id = [string]$creditQuote.quote_id
        idempotency_key = "$IdempotencyPrefix-credit"
        max_credits = 1
      }
    }
  $creditCapBlocked = (Get-MCPToolText -Response $creditCapResponse) -like '*exceeding approved max_credits=1*'
  if (-not $creditCapBlocked) {
    throw 'generate_ai_prompts did not stop before spend on max_credits cap.'
  }

  $usdQuote = Approve-MCPQuote `
    -BaseUrl $BaseUrl `
    -TenantID $tenantID `
    -ProjectID $projectID `
    -ApiKeyID ([string]$createdKey.api_key_id) `
    -ToolName 'generate_ai_prompts' `
    -Arguments $baseArgs `
    -MaxCredits 100 `
    -MaxUsd 0.0001 `
    -Session $session

  $usdCapResponse = Invoke-MCPRPC `
    -Endpoint $endpoint `
    -ApiKey $apiKey `
    -Method 'tools/call' `
    -Id 'usd-cap' `
    -Params @{
      name = 'generate_ai_prompts'
      arguments = @{
        url = $baseArgs.url
        brand_name = $baseArgs.brand_name
        count = $baseArgs.count
        quote_id = [string]$usdQuote.quote_id
        idempotency_key = "$IdempotencyPrefix-usd"
        max_credits = 100
        max_usd = 0.0001
      }
    }
  $usdCapBlocked = (Get-MCPToolText -Response $usdCapResponse) -like '*exceeds approved max_usd*'
  if (-not $usdCapBlocked) {
    throw 'generate_ai_prompts did not stop before spend on max_usd cap.'
  }
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
      Write-Warning 'Temporary MCP spend key revoke failed; revoke it manually from the AuraCite API Keys UI.'
    }
  }
}

if ($createdKey -and -not [string]::IsNullOrWhiteSpace([string]$createdKey.full_key)) {
  try {
    $revokedResponse = Invoke-MCPRPC `
      -Endpoint (Join-Url $BaseUrl '/mcp/rpc') `
      -ApiKey ([string]$createdKey.full_key) `
      -Method 'tools/list' `
      -Id 'revoked-spend-check'

    $revokedRejected = ($null -ne $revokedResponse.error)
  } catch {
    $revokedRejected = $true
  }
}

[pscustomobject]@{
  base_url = $BaseUrl
  tenant_id_present = -not [string]::IsNullOrWhiteSpace($tenantID)
  project_id_present = -not [string]::IsNullOrWhiteSpace($projectID)
  scope = 'mcp:spend'
  spend_tools_visible = $spendToolsVisible
  write_only_tools_hidden = $writeOnlyHidden
  missing_approval_blocked = $missingApprovalBlocked
  credit_cap_blocked_before_spend = $creditCapBlocked
  usd_cap_blocked_before_spend = $usdCapBlocked
  successful_provider_call_run = $false
  provider_calls_triggered = 0
  credits_charged = 0
  temporary_key_created = $temporaryKeyCreated
  temporary_key_revoked = $temporaryKeyRevoked
  revoked_key_rejected = $revokedRejected
  printed_secrets_or_tokens = $false
} | ConvertTo-Json -Depth 8
