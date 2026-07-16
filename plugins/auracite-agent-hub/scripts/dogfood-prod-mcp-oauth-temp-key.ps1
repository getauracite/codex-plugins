<#
.SYNOPSIS
Runs a secret-safe production MCP OAuth dogfood against AuraCite.

.DESCRIPTION
Logs in with the local SecretManagement production test credential, registers a
public MCP OAuth client, completes the authenticated consent + PKCE authorization
code flow, calls /mcp/rpc with Authorization: Bearer, revokes the OAuth-issued
token, and verifies the revoked bearer fails closed. It never prints the
password, login token, MCP bearer token, cookies, or raw secret values.
#>
[CmdletBinding()]
param(
  [string]$BaseUrl = "https://auracite.de",
  [string]$VaultName = "AuraCiteLocal",
  [string]$SecretName = "AuraCiteProdLogin",
  [string]$RedirectUri = "http://127.0.0.1:3485/callback",
  # When set, omit tenant_id/project_id from /oauth/authorize so the server
  # resolves the actor's default project (exercises the Claude Code one-click path).
  [switch]$UseDefaultProject
)

$ErrorActionPreference = 'Stop'

if ($PSVersionTable.PSEdition -eq 'Desktop') {
  $pwsh = Get-Command pwsh -ErrorAction SilentlyContinue
  if ($pwsh) {
    & $pwsh.Source `
      -NoProfile `
      -ExecutionPolicy Bypass `
      -File $PSCommandPath `
      -BaseUrl $BaseUrl `
      -VaultName $VaultName `
      -SecretName $SecretName `
      -RedirectUri $RedirectUri `
      -UseDefaultProject:$UseDefaultProject
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

function ConvertTo-Base64Url {
  param([byte[]]$Bytes)
  return [Convert]::ToBase64String($Bytes).TrimEnd('=').Replace('+', '-').Replace('/', '_')
}

function New-CodeVerifier {
  $bytes = [byte[]]::new(32)
  [System.Security.Cryptography.RandomNumberGenerator]::Fill($bytes)
  return ConvertTo-Base64Url -Bytes $bytes
}

function Get-PKCES256Challenge {
  param([string]$Verifier)
  $bytes = [System.Text.Encoding]::ASCII.GetBytes($Verifier)
  $hash = [System.Security.Cryptography.SHA256]::HashData($bytes)
  return ConvertTo-Base64Url -Bytes $hash
}

function ConvertTo-FormBody {
  param([hashtable]$Form)
  $pairs = foreach ($key in $Form.Keys) {
    [System.Net.WebUtility]::UrlEncode([string]$key) + '=' + [System.Net.WebUtility]::UrlEncode([string]$Form[$key])
  }
  return ($pairs -join '&')
}

function ConvertTo-QueryString {
  param([hashtable]$Query)
  return ConvertTo-FormBody -Form $Query
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

function Invoke-AuraCiteForm {
  param(
    [Parameter(Mandatory = $true)][string]$Method,
    [Parameter(Mandatory = $true)][string]$Url,
    [Parameter(Mandatory = $true)][hashtable]$Form,
    [Microsoft.PowerShell.Commands.WebRequestSession]$Session
  )

  Invoke-RestMethod `
    -Method $Method `
    -Uri $Url `
    -ContentType 'application/x-www-form-urlencoded' `
    -Body (ConvertTo-FormBody -Form $Form) `
    -WebSession $Session `
    -TimeoutSec 30
}

function Get-HiddenInputValue {
  param(
    [Parameter(Mandatory = $true)][string]$Html,
    [Parameter(Mandatory = $true)][string]$Name
  )
  $escaped = [regex]::Escape($Name)
  $match = [regex]::Match($Html, "name=`"$escaped`"\s+value=`"([^`"]+)`"")
  if (-not $match.Success) {
    throw "Hidden input '$Name' was not found in the consent page."
  }
  return [System.Net.WebUtility]::HtmlDecode($match.Groups[1].Value)
}

function Get-UriQueryValue {
  param(
    [Parameter(Mandatory = $true)][uri]$Uri,
    [Parameter(Mandatory = $true)][string]$Name
  )
  foreach ($pair in $Uri.Query.TrimStart('?').Split('&', [System.StringSplitOptions]::RemoveEmptyEntries)) {
    $parts = $pair.Split('=', 2)
    $key = [System.Net.WebUtility]::UrlDecode($parts[0])
    if ($key -eq $Name) {
      if ($parts.Count -lt 2) {
        return ''
      }
      return [System.Net.WebUtility]::UrlDecode($parts[1])
    }
  }
  return $null
}

$credential = Get-Secret -Name $SecretName -Vault $VaultName
if (-not $credential -or -not ($credential -is [pscredential])) {
  throw "Secret '$SecretName' was not found as a PSCredential in vault '$VaultName'."
}

$session = [Microsoft.PowerShell.Commands.WebRequestSession]::new()
$plainPassword = $credential.GetNetworkCredential().Password
$accessToken = $null
$oauthTokenIssued = $false
$oauthTokenRevoked = $false
$bearerCallPassed = $false
$revokedBearerRejected = $false
$challengeAdvertised = $false
$toolsCount = 0
$toolNames = @()
$oauthReadCallsPassed = $false
$oauthReadToolsCalled = @()
$tenantID = $null
$projectID = $null
$loginAccessToken = $null
$scope = 'mcp:read'

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
  $loginAccessToken = [string]$login.access_token
  if ([string]::IsNullOrWhiteSpace($tenantID) -or [string]::IsNullOrWhiteSpace($projectID)) {
    throw 'Login response did not include tenant_id/project_id.'
  }
  if ([string]::IsNullOrWhiteSpace($loginAccessToken)) {
    throw 'Login response did not include an access token for the OAuth confirm step.'
  }

  $registration = Invoke-AuraCiteJson `
    -Method Post `
    -Url (Join-Url $BaseUrl '/oauth/register') `
    -Body @{
      client_name = 'Codex Agent Hub OAuth Dogfood'
      redirect_uris = @($RedirectUri)
      grant_types = @('authorization_code')
      response_types = @('code')
      token_endpoint_auth_method = 'none'
    }

  $clientID = [string]$registration.client_id
  if ([string]::IsNullOrWhiteSpace($clientID)) {
    throw 'OAuth registration did not return a client_id.'
  }

  $codeVerifier = New-CodeVerifier
  $codeChallenge = Get-PKCES256Challenge -Verifier $codeVerifier
  $resource = (Join-Url $BaseUrl '/mcp/rpc')
  $state = 'oauth-dogfood-' + (Get-Date -Format 'yyyyMMddHHmmss')
  $authorizeQuery = @{
    response_type = 'code'
    client_id = $clientID
    redirect_uri = $RedirectUri
    scope = $scope
    state = $state
    resource = $resource
    code_challenge = $codeChallenge
    code_challenge_method = 'S256'
  }
  if (-not $UseDefaultProject) {
    $authorizeQuery['tenant_id'] = $tenantID
    $authorizeQuery['project_id'] = $projectID
  }
  $authorizeUrl = (Join-Url $BaseUrl '/oauth/authorize') + '?' + (ConvertTo-QueryString -Query $authorizeQuery)

  $authorizeResponse = Invoke-WebRequest `
    -Method Get `
    -Uri $authorizeUrl `
    -WebSession $session `
    -TimeoutSec 30
  if ($authorizeResponse.StatusCode -ne 200) {
    throw "Authorize returned unexpected HTTP $($authorizeResponse.StatusCode)."
  }
  $grantToken = Get-HiddenInputValue -Html $authorizeResponse.Content -Name 'grant_token'

  $httpHandler = [System.Net.Http.HttpClientHandler]::new()
  $httpHandler.AllowAutoRedirect = $false
  $httpClient = [System.Net.Http.HttpClient]::new($httpHandler)
  try {
    $httpClient.Timeout = [TimeSpan]::FromSeconds(30)
    $httpClient.DefaultRequestHeaders.Authorization = [System.Net.Http.Headers.AuthenticationHeaderValue]::new('Bearer', $loginAccessToken)
    $confirmContent = [System.Net.Http.StringContent]::new(
      (ConvertTo-FormBody -Form @{ grant_token = $grantToken; decision = 'allow' }),
      [System.Text.Encoding]::UTF8,
      'application/x-www-form-urlencoded'
    )
    $confirmResponse = $httpClient.PostAsync((Join-Url $BaseUrl '/oauth/authorize/confirm'), $confirmContent).GetAwaiter().GetResult()
  } finally {
    if ($null -ne $confirmContent) {
      $confirmContent.Dispose()
    }
    $httpClient.Dispose()
    $httpHandler.Dispose()
  }
  if ([int]$confirmResponse.StatusCode -ne 302) {
    throw "Confirm returned unexpected HTTP $([int]$confirmResponse.StatusCode)."
  }
  $locationHeader = [string]$confirmResponse.Headers.Location
  $callback = [uri]$locationHeader
  if ($callback.Host -ne ([uri]$RedirectUri).Host -or $callback.AbsolutePath -ne ([uri]$RedirectUri).AbsolutePath) {
    throw 'OAuth confirm redirected to an unexpected callback URI.'
  }
  $code = Get-UriQueryValue -Uri $callback -Name 'code'
  if ([string]::IsNullOrWhiteSpace($code) -or (Get-UriQueryValue -Uri $callback -Name 'state') -ne $state) {
    throw 'OAuth callback did not include the expected code and state.'
  }

  $token = Invoke-AuraCiteForm `
    -Method Post `
    -Url (Join-Url $BaseUrl '/oauth/token') `
    -Form @{
      grant_type = 'authorization_code'
      code = $code
      client_id = $clientID
      redirect_uri = $RedirectUri
      code_verifier = $codeVerifier
      resource = $resource
    }

  $accessToken = [string]$token.access_token
  if ([string]::IsNullOrWhiteSpace($accessToken) -or [string]$token.token_type -ne 'Bearer') {
    throw 'OAuth token response did not include a bearer access token.'
  }
  $oauthTokenIssued = $true

  $toolsResponse = Invoke-AuraCiteJson `
    -Method Post `
    -Url $resource `
    -Body @{
      jsonrpc = '2.0'
      id = 'oauth-tools-list'
      method = 'tools/list'
      params = @{}
    } `
    -Headers @{ Authorization = "Bearer $accessToken" }

  if ($null -ne $toolsResponse.error) {
    throw "MCP tools/list failed through OAuth bearer: $($toolsResponse.error.message)"
  }
  $bearerCallPassed = $true
  $toolNames = @($toolsResponse.result.tools | ForEach-Object { $_.name })
  $toolsCount = $toolNames.Count

  # Exercise bounded, stored-data reads through the OAuth bearer itself. These
  # calls must not trigger provider work, credits, or production mutation.
  $oauthReadChecks = @(
    @{ name = 'get_project_status'; arguments = @{} },
    @{ name = 'get_intelligence_freshness'; arguments = @{} },
    @{ name = 'get_gsc_search_analytics'; arguments = @{ days = 30; limit = 5 } },
    @{ name = 'get_gsc_top_queries'; arguments = @{ days = 30; limit = 5 } },
    @{ name = 'get_gsc_breakdown'; arguments = @{ dimension = 'country'; days = 30; limit = 5 } },
    @{ name = 'get_gsc_top_pages'; arguments = @{ days = 30; limit = 5 } },
    @{ name = 'get_gsc_trend'; arguments = @{ days = 28; limit = 5 } },
    @{ name = 'get_ai_visibility_overview'; arguments = @{ days = 30 } }
  )
  foreach ($check in $oauthReadChecks) {
    if ($toolNames -notcontains $check.name) {
      throw "OAuth tools/list did not expose required read tool '$($check.name)'."
    }
    $readResponse = Invoke-AuraCiteJson `
      -Method Post `
      -Url $resource `
      -Body @{
        jsonrpc = '2.0'
        id = 'oauth-read-' + $check.name
        method = 'tools/call'
        params = @{
          name = $check.name
          arguments = $check.arguments
        }
      } `
      -Headers @{ Authorization = "Bearer $accessToken" }

    if ($null -ne $readResponse.error) {
      throw "OAuth read '$($check.name)' failed: $($readResponse.error.message)"
    }
    $oauthReadToolsCalled += $check.name
  }
  $oauthReadCallsPassed = $true
}
finally {
  $plainPassword = $null
  $credential = $null

  if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
    try {
      Invoke-AuraCiteForm `
        -Method Post `
        -Url (Join-Url $BaseUrl '/oauth/revoke') `
        -Form @{ token = $accessToken } | Out-Null
      $oauthTokenRevoked = $true
    } catch {
      Write-Warning 'OAuth-issued MCP bearer revoke failed; revoke it manually from the AuraCite API Keys UI.'
    }
  }
}

if (-not [string]::IsNullOrWhiteSpace($accessToken)) {
  $revokedResponse = Invoke-WebRequest `
    -Method Post `
    -Uri (Join-Url $BaseUrl '/mcp/rpc') `
    -ContentType 'application/json' `
    -Body (@{
      jsonrpc = '2.0'
      id = 'oauth-revoked-check'
      method = 'tools/list'
      params = @{}
    } | ConvertTo-Json -Depth 10) `
    -Headers @{ Authorization = "Bearer $accessToken" } `
    -SkipHttpErrorCheck `
    -TimeoutSec 30

  $revokedBearerRejected = ($revokedResponse.StatusCode -eq 401 -or $revokedResponse.Content -like '*invalid*token*')
  $challenge = [string]$revokedResponse.Headers.'WWW-Authenticate'
  $challengeAdvertised = ($challenge -like '*oauth-protected-resource*' -and $challenge -like '*mcp:read*')
}

[pscustomobject]@{
  BaseUrl = $BaseUrl
  DefaultProjectMode = [bool]$UseDefaultProject
  TenantIDPresent = -not [string]::IsNullOrWhiteSpace($tenantID)
  ProjectIDPresent = -not [string]::IsNullOrWhiteSpace($projectID)
  OAuthClientRegistered = $true
  Scope = $scope
  OAuthTokenIssued = $oauthTokenIssued
  BearerToolsListPassed = $bearerCallPassed
  ToolsListCount = $toolsCount
  VisibleToolNames = ($toolNames -join ',')
  OAuthReadCallsPassed = $oauthReadCallsPassed
  OAuthReadToolsCalled = ($oauthReadToolsCalled -join ',')
  OAuthTokenRevoked = $oauthTokenRevoked
  RevokedBearerRejected = $revokedBearerRejected
  OAuthChallengeAdvertised = $challengeAdvertised
  PrintedSecretsOrTokens = $false
} | Format-List
