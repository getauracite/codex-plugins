param(
  [string]$PluginRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path,
  [string]$MarketplacePath = (Resolve-Path (Join-Path $PSScriptRoot '..\..\..\.agents\plugins\marketplace.json')).Path
)

$ErrorActionPreference = 'Stop'

function Invoke-NativeChecked {
  param(
    [Parameter(Mandatory = $true)][string]$Command,
    [string[]]$Arguments = @()
  )

  & $Command @Arguments
  if ($LASTEXITCODE -ne 0) {
    throw "Command failed with exit code $LASTEXITCODE`: $Command $($Arguments -join ' ')"
  }
}

$manifestPath = Join-Path $PluginRoot '.codex-plugin\plugin.json'
$mcpPath = Join-Path $PluginRoot '.mcp.json'
$hooksPath = Join-Path $PluginRoot 'hooks\hooks.json'
$iconPath = Join-Path $PluginRoot 'assets\icon.svg'
$logoPath = Join-Path $PluginRoot 'assets\logo.svg'
$customerInstallPath = Join-Path $PluginRoot 'CUSTOMER_INSTALL.md'
$dogfoodProtocolPath = Join-Path $PluginRoot 'DOGFOODING.md'
$workspaceSharingPath = Join-Path $PluginRoot 'WORKSPACE_SHARING.md'
$publicMarketplacePath = Join-Path $PluginRoot 'PUBLIC_MARKETPLACE.md'
$licensePath = Join-Path $PluginRoot 'LICENSE'
$bridgePath = Join-Path $PluginRoot 'bridge\auracite_jsonrpc_bridge.mjs'
$dogfoodGatePath = Join-Path $PluginRoot 'scripts\dogfood-gate.ps1'
$scenarioSessionsPath = Join-Path $PluginRoot 'scripts\dogfood-jsonrpc-sessions.mjs'
$prodReadDogfoodPath = Join-Path $PluginRoot 'scripts\dogfood-prod-read-temp-key.ps1'
$prodOAuthDogfoodPath = Join-Path $PluginRoot 'scripts\dogfood-prod-mcp-oauth-temp-key.ps1'
$prodWriteDenyPath = Join-Path $PluginRoot 'scripts\dogfood-prod-write-deny-temp-key.ps1'
$prodSpendCapPath = Join-Path $PluginRoot 'scripts\dogfood-prod-spend-cap-temp-key.ps1'
$prodRefreshPlanPath = Join-Path $PluginRoot 'scripts\dogfood-prod-refresh-plan-temp-key.ps1'
$refreshInspectPath = Join-Path $PluginRoot 'scripts\inspect-intelligence-refresh-plan.ps1'
$smokePath = Join-Path $PluginRoot 'scripts\smoke-jsonrpc-read.ps1'
$writeDenySmokePath = Join-Path $PluginRoot 'scripts\smoke-jsonrpc-write-deny.ps1'
$outcomeSmokePath = Join-Path $PluginRoot 'scripts\smoke-jsonrpc-outcome-reconciliation.ps1'
$bridgeTestPath = Join-Path $PluginRoot 'scripts\test-jsonrpc-bridge.mjs'
$bridgeLiveSmokePath = Join-Path $PluginRoot 'scripts\smoke-jsonrpc-bridge-live.mjs'

foreach ($path in @($manifestPath, $mcpPath, $hooksPath, $iconPath, $logoPath, $customerInstallPath, $dogfoodProtocolPath, $workspaceSharingPath, $publicMarketplacePath, $licensePath, $MarketplacePath, $bridgePath, $dogfoodGatePath, $scenarioSessionsPath, $prodReadDogfoodPath, $prodOAuthDogfoodPath, $prodWriteDenyPath, $prodSpendCapPath, $prodRefreshPlanPath, $refreshInspectPath, $smokePath, $writeDenySmokePath, $outcomeSmokePath, $bridgeTestPath, $bridgeLiveSmokePath)) {
  if (-not (Test-Path -LiteralPath $path)) {
    throw "Missing required file: $path"
  }
  if ([IO.Path]::GetExtension($path) -eq '.json') {
    Get-Content -Raw -LiteralPath $path | ConvertFrom-Json | Out-Null
  }
}

$manifest = Get-Content -Raw -LiteralPath $manifestPath | ConvertFrom-Json
if ($manifest.name -ne 'auracite-agent-hub') {
  throw "Unexpected plugin name: $($manifest.name)"
}
if ($manifest.version -ne '0.11.2') {
  throw "Unexpected plugin version: $($manifest.version)"
}
if (@($manifest.interface.defaultPrompt).Count -ne 3) {
  throw "Expected exactly 3 displayed starter prompts, found $(@($manifest.interface.defaultPrompt).Count)"
}
if ($manifest.repository -ne 'https://github.com/getauracite/codex-plugins') {
  throw "Unexpected plugin repository: $($manifest.repository)"
}
if ($manifest.interface.composerIcon -ne './assets/icon.svg') {
  throw "Plugin composerIcon must point at ./assets/icon.svg."
}
if ($manifest.interface.logo -ne './assets/logo.svg') {
  throw "Plugin logo must point at ./assets/logo.svg."
}

$skills = Get-ChildItem -LiteralPath (Join-Path $PluginRoot 'skills') -Filter 'SKILL.md' -Recurse
if ($skills.Count -lt 3) {
  throw "Expected at least 3 bundled skills, found $($skills.Count)"
}

$mcp = Get-Content -Raw -LiteralPath $mcpPath | ConvertFrom-Json
$mcpServers = $mcp.mcpServers
if ($null -eq $mcpServers) {
  throw '.mcp.json must use top-level mcpServers object.'
}
$enabledTools = @($mcpServers.auracite.enabled_tools)
$expectedProductionReadToolCount = 37
$expectedProductionOperatorToolCount = 48
if ($enabledTools.Count -ne $expectedProductionOperatorToolCount) {
  throw "Hosted enabled_tools must match the verified operator surface ($expectedProductionOperatorToolCount), found $($enabledTools.Count)."
}
# get_crawler_hits was listed here until 0.11.2: the production MCP resource
# registered it but never gave it a tool policy, so /mcp/rpc filtered it out of
# tools/list and rejected the call. Advertising it would have been a false
# promise to a reviewer. AuraCite 6a93e2a9 gave it a read policy and a catalog
# entry, verified live against https://auracite.de, so it moves to
# $requiredTools below. Keep this array for the next tool that regresses.
$staleTools = @()
if (@($staleTools | Where-Object { $enabledTools -contains $_ }).Count -gt 0) {
  throw "Stale production tool advertised in hosted enabled_tools: $($staleTools -join ', ')"
}
$requiredTools = @(
  'list_projects',
  'summarize_user_landscape',
  'list_recent_signups',
  'get_gsc_search_analytics',
  'get_gsc_top_queries',
  'get_gsc_breakdown',
  'get_gsc_top_pages',
  'get_gsc_trend',
  'get_ai_visibility_overview',
  'get_crawler_hits',
  'get_intelligence_overview',
  'get_intelligence_freshness',
  'list_intelligence_refresh_candidates',
  'create_intelligence_refresh_plan_draft',
  'get_intelligence_refresh_status',
  'list_intelligence_opportunity_briefs',
  'get_intelligence_opportunity_brief',
  'list_action_handoffs',
  'get_vault_next_actions',
  'get_project_status',
  'get_recent_changelog',
  'get_agent_hub_timeline',
  'list_project_memory_entries',
  'create_context_pack_draft',
  'create_action_handoff_draft',
  'write_approval_note_draft'
)
$missingTools = @($requiredTools | Where-Object { $enabledTools -notcontains $_ })
if ($missingTools.Count -gt 0) {
  throw "Missing Agent Hub tools from .mcp.json enabled_tools: $($missingTools -join ', ')"
}

$disabledTools = @($mcpServers.auracite.disabled_tools)
$requiredDisabledTools = @(
  'delete_brand',
  'create_demo_user',
  'add_credits'
)
$missingDisabledTools = @($requiredDisabledTools | Where-Object { $disabledTools -notcontains $_ })
if ($missingDisabledTools.Count -gt 0) {
  throw "Missing write/cost/admin tools from .mcp.json disabled_tools: $($missingDisabledTools -join ', ')"
}

$enterpriseBlockedTools = @('delete_brand', 'create_demo_user', 'add_credits')
$unexpectedEnabledTools = @($enterpriseBlockedTools | Where-Object { $enabledTools -contains $_ })
if ($unexpectedEnabledTools.Count -gt 0) {
  throw "Enterprise safety violation: mutation/admin tools must not be enabled by default: $($unexpectedEnabledTools -join ', ')"
}
$missingEnterpriseBlockedTools = @($enterpriseBlockedTools | Where-Object { $disabledTools -notcontains $_ })
if ($missingEnterpriseBlockedTools.Count -gt 0) {
  throw "Enterprise safety violation: mutation/admin tools must be explicitly disabled: $($missingEnterpriseBlockedTools -join ', ')"
}

if ($mcpServers.auracite.url -ne 'https://auracite.de/mcp/rpc') {
  throw "AuraCite hosted MCP entry must point at the OAuth-capable JSON-RPC endpoint, got: $($mcpServers.auracite.url)"
}
if ($mcpServers.auracite.enabled -ne $true) {
  throw 'AuraCite hosted MCP OAuth entry must be enabled by default for one-click install.'
}
if (@($mcpServers.auracite.PSObject.Properties.Name) -contains 'bearer_token_env_var') {
  throw 'AuraCite hosted MCP OAuth entry must not require a manual bearer token env var.'
}

$bridge = $mcpServers.'auracite-jsonrpc-bridge'
if ($null -eq $bridge) {
  throw 'Missing auracite-jsonrpc-bridge MCP server entry.'
}
if ($bridge.command -ne 'node') {
  throw "Unexpected bridge command: $($bridge.command)"
}
if (@($bridge.args) -notcontains './bridge/auracite_jsonrpc_bridge.mjs') {
  throw 'Bridge MCP server must point at ./bridge/auracite_jsonrpc_bridge.mjs.'
}
if ($bridge.enabled -ne $false) {
  throw 'AuraCite JSON-RPC bridge must remain disabled by default; enable per user/workspace config with a token.'
}
if ($bridge.env.AURACITE_MCP_BRIDGE_MODE -ne 'safe') {
  throw 'AuraCite JSON-RPC bridge must default to safe mode.'
}

$bridgeEnabledTools = @($bridge.enabled_tools)
if ($bridgeEnabledTools.Count -ne $expectedProductionOperatorToolCount) {
  throw "Bridge enabled_tools must match the verified operator surface ($expectedProductionOperatorToolCount), found $($bridgeEnabledTools.Count)."
}
$bridgeStaleTools = @($staleTools | Where-Object { $bridgeEnabledTools -contains $_ })
if ($bridgeStaleTools.Count -gt 0) {
  throw "Stale production tool advertised in bridge enabled_tools: $($bridgeStaleTools -join ', ')"
}
$bridgeMissingTools = @($requiredTools | Where-Object { $bridgeEnabledTools -notcontains $_ })
if ($bridgeMissingTools.Count -gt 0) {
  throw "Missing Agent Hub tools from auracite-jsonrpc-bridge enabled_tools: $($bridgeMissingTools -join ', ')"
}
$bridgeDisabledTools = @($bridge.disabled_tools)
$bridgeMissingDisabledTools = @($requiredDisabledTools | Where-Object { $bridgeDisabledTools -notcontains $_ })
if ($bridgeMissingDisabledTools.Count -gt 0) {
  throw "Missing write/cost/admin tools from auracite-jsonrpc-bridge disabled_tools: $($bridgeMissingDisabledTools -join ', ')"
}
$bridgeUnexpectedEnabledTools = @($enterpriseBlockedTools | Where-Object { $bridgeEnabledTools -contains $_ })
if ($bridgeUnexpectedEnabledTools.Count -gt 0) {
  throw "Enterprise safety violation: bridge mutation/admin tools must not be enabled by default: $($bridgeUnexpectedEnabledTools -join ', ')"
}
$bridgeMissingEnterpriseBlockedTools = @($enterpriseBlockedTools | Where-Object { $bridgeDisabledTools -notcontains $_ })
if ($bridgeMissingEnterpriseBlockedTools.Count -gt 0) {
  throw "Enterprise safety violation: bridge mutation/admin tools must be explicitly disabled: $($bridgeMissingEnterpriseBlockedTools -join ', ')"
}

$node = Get-Command node -ErrorAction SilentlyContinue
if (-not $node) {
  throw 'Node.js is required to validate the AuraCite JSON-RPC bridge.'
}

foreach ($scriptPath in @($dogfoodGatePath, $prodReadDogfoodPath, $prodOAuthDogfoodPath, $prodWriteDenyPath, $prodSpendCapPath, $prodRefreshPlanPath, $refreshInspectPath, $smokePath, $writeDenySmokePath, $outcomeSmokePath)) {
  $parseErrors = $null
  [System.Management.Automation.Language.Parser]::ParseFile($scriptPath, [ref]$null, [ref]$parseErrors) | Out-Null
  if ($parseErrors.Count -gt 0) {
    throw "PowerShell parse errors in $scriptPath`: $($parseErrors.Message -join '; ')"
  }
}

Invoke-NativeChecked -Command $node.Source -Arguments @('--check', $bridgePath)
Invoke-NativeChecked -Command $node.Source -Arguments @('--check', $bridgeLiveSmokePath)
Invoke-NativeChecked -Command $node.Source -Arguments @('--check', $scenarioSessionsPath)
Invoke-NativeChecked -Command $node.Source -Arguments @($bridgeTestPath)

Write-Host "AuraCite Agent Hub plugin validation passed."
