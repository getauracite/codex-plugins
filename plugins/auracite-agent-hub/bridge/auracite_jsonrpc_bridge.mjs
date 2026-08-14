#!/usr/bin/env node

const PROTOCOL_VERSION = "2024-11-05";
const DEFAULT_RPC_URL = "https://auracite.de/mcp/rpc";
const SERVER_NAME = "AuraCite Agent Hub JSON-RPC Bridge";
const SERVER_VERSION = "0.1.0";

const SAFE_TOOL_NAMES = new Set([
  "list_brands",
  "list_projects",
  "get_dashboard_stats",
  "get_mentions",
  "get_citations",
  "list_prompts",
  "list_competitors",
  "get_visibility_score",
  "get_share_of_voice",
  "get_trend_data",
  "get_ai_engine_breakdown",
  "compare_brands",
  "summarize_user_landscape",
  "list_recent_signups",
  "get_gsc_search_analytics",
  "get_gsc_top_queries",
  "get_gsc_breakdown",
  "get_gsc_top_pages",
  "get_gsc_trend",
  "get_crawler_hits",
  "get_ai_visibility_overview",
  "get_intelligence_overview",
  "get_intelligence_freshness",
  "list_intelligence_refresh_candidates",
  "create_intelligence_refresh_plan_draft",
  "get_intelligence_refresh_status",
  "list_intelligence_opportunity_briefs",
  "get_intelligence_opportunity_brief",
  "list_action_handoffs",
  "get_vault_next_actions",
  "get_project_status",
  "get_recent_changelog",
  "get_agent_hub_timeline",
  "list_project_memory_entries",
  "create_context_pack_draft",
  "create_action_handoff_draft",
  "write_approval_note_draft"
]);

const CONFIRMED_WRITE_TOOL_NAMES = new Set([
  "create_project",
  "add_prompt",
  "add_brand",
  "bulk_add_prompts",
  "trigger_intelligence_refresh",
  "promote_handoff_to_action",
  "update_action_status",
  "record_outcome_measurement",
  "append_project_memory_entry"
]);

const COST_TOOL_NAMES = new Set([
  "trigger_scan",
  "generate_ai_prompts"
]);

// Destructive and admin tools remain blocked locally even for a broad operator
// token. User-visible writes and provider-spend tools are exposed only in
// confirmed-writes mode and remain server-gated by quote, scope, audit,
// idempotency, and (for spend) credit/USD caps.
const ALWAYS_BLOCKED_TOOL_NAMES = new Set([
  "delete_brand",
  "create_demo_user",
  "add_credits"
]);

class BridgeError extends Error {
  constructor(code, message, data = undefined) {
    super(message);
    this.code = code;
    this.data = data;
  }
}

function bridgeMode() {
  const raw = (process.env.AURACITE_MCP_BRIDGE_MODE || "safe").trim().toLowerCase();
  if (raw === "confirmed-writes" || raw === "safe") {
    return raw;
  }
  return "safe";
}

function rpcURL() {
  return (process.env.AURACITE_MCP_RPC_URL || DEFAULT_RPC_URL).trim();
}

function apiToken() {
  return (process.env.AURACITE_MCP_TOKEN || "").trim();
}

function isAllowedTool(name, mode = bridgeMode()) {
  if (ALWAYS_BLOCKED_TOOL_NAMES.has(name)) {
    return false;
  }
  if (SAFE_TOOL_NAMES.has(name)) {
    return true;
  }
  if (
    mode === "confirmed-writes" &&
    (CONFIRMED_WRITE_TOOL_NAMES.has(name) || COST_TOOL_NAMES.has(name))
  ) {
    return true;
  }
  return false;
}

function filterTools(tools, mode = bridgeMode()) {
  if (!Array.isArray(tools)) {
    return [];
  }
  return tools.filter((tool) => typeof tool?.name === "string" && isAllowedTool(tool.name, mode));
}

async function callAuraCiteRPC(method, params, id) {
  const token = apiToken();
  if (!token) {
    throw new BridgeError(
      -32001,
      "AURACITE_MCP_TOKEN is required for the AuraCite JSON-RPC bridge.",
      { redaction_state: "secret_not_printed" }
    );
  }

  const response = await fetch(rpcURL(), {
    method: "POST",
    headers: {
      "content-type": "application/json",
      "x-api-key": token
    },
    body: JSON.stringify({
      jsonrpc: "2.0",
      id,
      method,
      params: params || {}
    })
  });

  if (!response.ok) {
    throw new BridgeError(-32002, `AuraCite JSON-RPC endpoint returned HTTP ${response.status}.`);
  }

  const payload = await response.json();
  if (payload.error) {
    throw new BridgeError(
      payload.error.code || -32003,
      payload.error.message || "AuraCite JSON-RPC endpoint returned an error.",
      payload.error.data
    );
  }
  return payload.result;
}

async function handleRequest(message) {
  const method = message.method;
  const params = message.params || {};
  const mode = bridgeMode();

  switch (method) {
    case "initialize":
      return {
        protocolVersion: params.protocolVersion || PROTOCOL_VERSION,
        capabilities: {
          tools: {},
          resources: {}
        },
        serverInfo: {
          name: SERVER_NAME,
          version: SERVER_VERSION
        },
        instructions:
          "AuraCite Agent Hub bridge. Safe mode exposes read and draft tools. Set AURACITE_MCP_BRIDGE_MODE=confirmed-writes only for server-confirmed project/brand/prompt, memory, Action Center, and stored-rescore writes (mcp:write + pending approval + one-use quote + idempotency) and cost tools (mcp:spend + one-tap execution approval + max_credits/max_usd caps). Destructive, admin, credit-grant, demo-user, publishing, and raw Vault-file writes remain blocked."
      };

    case "ping":
    case "notifications/initialized":
      return {};

    case "tools/list": {
      const result = await callAuraCiteRPC("tools/list", params, message.id);
      return {
        ...result,
        tools: filterTools(result?.tools, mode)
      };
    }

    case "tools/call": {
      const toolName = params.name;
      if (typeof toolName !== "string" || !toolName.trim()) {
        throw new BridgeError(-32602, "tools/call requires params.name.");
      }
      if (!isAllowedTool(toolName, mode)) {
        throw new BridgeError(
          -32010,
          `Tool ${toolName} is disabled by local bridge mode '${mode}'.`,
          {
            bridge_mode: mode,
            enable_confirmed_writes: "Set AURACITE_MCP_BRIDGE_MODE=confirmed-writes for approval-gated writes or cost-capped tools.",
            provider_calls_triggered: 0,
            credits_charged: 0
          }
        );
      }
      return callAuraCiteRPC("tools/call", params, message.id);
    }

    case "resources/list":
    case "resources/read":
      return callAuraCiteRPC(method, params, message.id);

    default:
      throw new BridgeError(-32601, `Method not found: ${method}`);
  }
}

function writeMessage(message) {
  const body = JSON.stringify(message);
  process.stdout.write(`Content-Length: ${Buffer.byteLength(body, "utf8")}\r\n\r\n${body}`);
}

function writeResponse(id, result) {
  writeMessage({
    jsonrpc: "2.0",
    id,
    result
  });
}

function writeError(id, error) {
  writeMessage({
    jsonrpc: "2.0",
    id,
    error: {
      code: error.code || -32603,
      message: error.message || "Internal bridge error",
      ...(error.data === undefined ? {} : { data: error.data })
    }
  });
}

let inputBuffer = Buffer.alloc(0);

function tryReadMessages() {
  while (inputBuffer.length > 0) {
    let separator = inputBuffer.indexOf("\r\n\r\n");
    let separatorLength = 4;
    if (separator === -1) {
      separator = inputBuffer.indexOf("\n\n");
      separatorLength = 2;
    }
    if (separator === -1) {
      return;
    }

    const header = inputBuffer.subarray(0, separator).toString("utf8");
    const match = /Content-Length:\s*(\d+)/i.exec(header);
    if (!match) {
      throw new BridgeError(-32700, "Missing Content-Length header.");
    }

    const length = Number(match[1]);
    const bodyStart = separator + separatorLength;
    const bodyEnd = bodyStart + length;
    if (inputBuffer.length < bodyEnd) {
      return;
    }

    const raw = inputBuffer.subarray(bodyStart, bodyEnd).toString("utf8");
    inputBuffer = inputBuffer.subarray(bodyEnd);
    void dispatchRawMessage(raw);
  }
}

async function dispatchRawMessage(raw) {
  let message;
  try {
    message = JSON.parse(raw);
  } catch {
    writeError(null, new BridgeError(-32700, "Invalid JSON-RPC message."));
    return;
  }

  if (message.id === undefined || message.id === null) {
    if (message.method === "notifications/initialized") {
      return;
    }
    return;
  }

  try {
    const result = await handleRequest(message);
    writeResponse(message.id, result);
  } catch (error) {
    writeError(message.id, error);
  }
}

process.stdin.on("data", (chunk) => {
  inputBuffer = Buffer.concat([inputBuffer, chunk]);
  try {
    tryReadMessages();
  } catch (error) {
    writeError(null, error);
  }
});

process.stdin.resume();
