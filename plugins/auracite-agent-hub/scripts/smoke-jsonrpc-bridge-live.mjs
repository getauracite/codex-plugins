import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginRoot = path.resolve(__dirname, "..");
const bridgePath = path.join(pluginRoot, "bridge", "auracite_jsonrpc_bridge.mjs");

const rpcURL = process.env.AURACITE_MCP_RPC_URL || "https://auracite.de/mcp/rpc";
const mode = process.env.AURACITE_MCP_BRIDGE_MODE || "safe";

if (!process.env.AURACITE_MCP_TOKEN) {
  throw new Error("AURACITE_MCP_TOKEN is required for the live bridge smoke.");
}

function encodeMessage(message) {
  const json = JSON.stringify(message);
  return `Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`;
}

function createBridgeClient() {
  const child = spawn(process.execPath, [bridgePath], {
    cwd: pluginRoot,
    env: {
      ...process.env,
      AURACITE_MCP_RPC_URL: rpcURL,
      AURACITE_MCP_BRIDGE_MODE: mode
    },
    stdio: ["pipe", "pipe", "pipe"]
  });

  let stdout = Buffer.alloc(0);
  let stderr = "";
  const pending = new Map();

  child.stderr.setEncoding("utf8");
  child.stderr.on("data", (chunk) => {
    stderr += chunk;
  });

  child.stdout.on("data", (chunk) => {
    stdout = Buffer.concat([stdout, chunk]);
    while (stdout.length > 0) {
      let separator = stdout.indexOf("\r\n\r\n");
      let separatorLength = 4;
      if (separator === -1) {
        separator = stdout.indexOf("\n\n");
        separatorLength = 2;
      }
      if (separator === -1) {
        return;
      }

      const header = stdout.subarray(0, separator).toString("utf8");
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      assert.ok(match, `missing Content-Length header in ${header}`);

      const length = Number(match[1]);
      const bodyStart = separator + separatorLength;
      const bodyEnd = bodyStart + length;
      if (stdout.length < bodyEnd) {
        return;
      }

      const payload = JSON.parse(stdout.subarray(bodyStart, bodyEnd).toString("utf8"));
      stdout = stdout.subarray(bodyEnd);

      const waiter = pending.get(payload.id);
      if (waiter) {
        pending.delete(payload.id);
        waiter.resolve(payload);
      }
    }
  });

  child.once("exit", (code, signal) => {
    for (const waiter of pending.values()) {
      waiter.reject(new Error(`bridge exited before response: code=${code} signal=${signal} stderr=${stderr}`));
    }
    pending.clear();
  });

  let nextID = 1;
  return {
    child,
    stderr: () => stderr,
    request(method, params = {}) {
      const id = nextID++;
      const promise = new Promise((resolve, reject) => {
        pending.set(id, { resolve, reject });
      });
      child.stdin.write(encodeMessage({ jsonrpc: "2.0", id, method, params }));
      return promise;
    },
    async close() {
      child.kill();
      await once(child, "exit").catch(() => {});
    }
  };
}

function parseToolContent(response) {
  const text = response?.result?.content?.find((item) => item.type === "text")?.text;
  assert.ok(text, "expected text content from MCP tool result");
  return JSON.parse(text);
}

const client = createBridgeClient();

try {
  const init = await client.request("initialize", {
    protocolVersion: "2024-11-05",
    clientInfo: { name: "auracite-live-bridge-smoke", version: "0.0.0" }
  });
  assert.equal(init.error, undefined);
  assert.equal(init.result.serverInfo.name, "AuraCite Agent Hub JSON-RPC Bridge");

  const listed = await client.request("tools/list");
  assert.equal(listed.error, undefined);
  const toolNames = listed.result.tools.map((tool) => tool.name);
  assert.ok(toolNames.includes("get_project_status"), "get_project_status should be visible");
  assert.ok(toolNames.includes("get_agent_hub_timeline"), "get_agent_hub_timeline should be visible");
  assert.ok(toolNames.includes("get_intelligence_freshness"), "get_intelligence_freshness should be visible");
  assert.ok(toolNames.includes("create_intelligence_refresh_plan_draft"), "create_intelligence_refresh_plan_draft should be visible");
  assert.equal(toolNames.includes("trigger_intelligence_refresh"), false, "trigger_intelligence_refresh must stay hidden in safe mode");
  assert.equal(toolNames.includes("trigger_scan"), false, "trigger_scan must stay locally blocked");

  const status = await client.request("tools/call", {
    name: "get_project_status",
    arguments: {}
  });
  assert.equal(status.error, undefined);
  const statusBody = parseToolContent(status);
  assert.equal(statusBody.mutation_performed, false);
  assert.equal(statusBody.provider_calls_triggered, 0);
  assert.equal(statusBody.credits_charged, 0);

  const timeline = await client.request("tools/call", {
    name: "get_agent_hub_timeline",
    arguments: { limit: 5 }
  });
  assert.equal(timeline.error, undefined);
  const timelineBody = parseToolContent(timeline);
  assert.equal(timelineBody.source, "curated_agent_hub_timeline");
  assert.equal(timelineBody.mutation_performed, false);
  assert.equal(timelineBody.provider_calls_triggered, 0);
  assert.equal(timelineBody.credits_charged, 0);
  assert.ok(Array.isArray(timelineBody.timeline), "timeline must be an array");
  assert.ok(timelineBody.timeline.length > 0, "timeline must not be empty");

  const deniedWrite = await client.request("tools/call", {
    name: "update_action_status",
    arguments: {
      run_id: "00000000-0000-0000-0000-000000000000",
      status: "implemented"
    }
  });
  assert.ok(deniedWrite.error, "safe-mode bridge must deny update_action_status");
  assert.match(deniedWrite.error.message, /disabled by local bridge/i);

  const deniedRefreshTrigger = await client.request("tools/call", {
    name: "trigger_intelligence_refresh",
    arguments: { refresh_type: "stored_rescore", idempotency_key: "safe-mode-deny" }
  });
  assert.ok(deniedRefreshTrigger.error, "safe-mode bridge must deny trigger_intelligence_refresh");
  assert.match(deniedRefreshTrigger.error.message, /disabled by local bridge/i);

  const summary = {
    bridge_name: init.result.serverInfo.name,
    rpc_url: rpcURL,
    mode,
    tool_count: toolNames.length,
    has_get_project_status: toolNames.includes("get_project_status"),
    has_get_agent_hub_timeline: toolNames.includes("get_agent_hub_timeline"),
    has_get_intelligence_freshness: toolNames.includes("get_intelligence_freshness"),
    has_trigger_intelligence_refresh: toolNames.includes("trigger_intelligence_refresh"),
    has_update_action_status: toolNames.includes("update_action_status"),
    has_trigger_scan: toolNames.includes("trigger_scan"),
    denied_update_action_status_locally: true,
    denied_trigger_intelligence_refresh_locally: true,
    project_status_snapshot_version: statusBody.snapshot_version,
    agent_hub_timeline_entries: timelineBody.timeline.length,
    production_state: statusBody.production_state,
    mutation_performed: statusBody.mutation_performed,
    provider_calls_triggered: statusBody.provider_calls_triggered,
    credits_charged: statusBody.credits_charged,
    printed_secrets_or_tokens: false
  };

  console.log(JSON.stringify(summary, null, 2));
} finally {
  await client.close();
}
