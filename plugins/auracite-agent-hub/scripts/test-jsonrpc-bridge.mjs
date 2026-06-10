import assert from "node:assert/strict";
import http from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginRoot = path.resolve(__dirname, "..");
const bridgePath = path.join(pluginRoot, "bridge", "auracite_jsonrpc_bridge.mjs");

const remoteRequests = [];
const remoteTools = [
  "get_project_status",
  "get_agent_hub_timeline",
  "get_intelligence_freshness",
  "list_intelligence_refresh_candidates",
  "create_intelligence_refresh_plan_draft",
  "get_intelligence_refresh_status",
  "list_action_handoffs",
  "list_project_memory_entries",
  "create_context_pack_draft",
  "trigger_intelligence_refresh",
  "update_action_status",
  "record_outcome_measurement",
  "append_project_memory_entry",
  "trigger_scan",
  "generate_ai_prompts",
  "add_credits"
].map((name) => ({
  name,
  description: `${name} from fake AuraCite`,
  inputSchema: { type: "object", properties: {} }
}));

const server = http.createServer(async (req, res) => {
  let raw = "";
  req.setEncoding("utf8");
  req.on("data", (chunk) => {
    raw += chunk;
  });
  await once(req, "end");

  const body = JSON.parse(raw);
  remoteRequests.push({
    method: body.method,
    params: body.params ?? {},
    apiKey: req.headers["x-api-key"]
  });

  const respond = (payload) => {
    res.writeHead(200, { "content-type": "application/json" });
    res.end(JSON.stringify({ jsonrpc: "2.0", id: body.id, ...payload }));
  };

  if (req.headers["x-api-key"] !== "test-token") {
    respond({ error: { code: -32001, message: "Authentication failed" } });
    return;
  }

  if (body.method === "tools/list") {
    respond({ result: { tools: remoteTools } });
    return;
  }

  if (body.method === "tools/call") {
    respond({
      result: {
        content: [
          {
            type: "text",
            text: JSON.stringify({
              proxied_tool: body.params?.name,
              proxied_arguments: body.params?.arguments ?? {}
            })
          }
        ]
      }
    });
    return;
  }

  respond({ result: {} });
});

server.listen(0, "127.0.0.1");
await once(server, "listening");
const port = server.address().port;
const rpcURL = `http://127.0.0.1:${port}/mcp/rpc`;

function encodeMessage(message) {
  const json = JSON.stringify(message);
  return `Content-Length: ${Buffer.byteLength(json, "utf8")}\r\n\r\n${json}`;
}

function createBridgeClient(extraEnv = {}) {
  const child = spawn(process.execPath, [bridgePath], {
    cwd: pluginRoot,
    env: {
      ...process.env,
      AURACITE_MCP_RPC_URL: rpcURL,
      AURACITE_MCP_TOKEN: "test-token",
      AURACITE_MCP_BRIDGE_MODE: "safe",
      ...extraEnv
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
    async request(method, params = {}) {
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

try {
  {
    const client = createBridgeClient();
    const init = await client.request("initialize", {
      protocolVersion: "2024-11-05",
      clientInfo: { name: "bridge-test", version: "0.0.0" }
    });
    assert.equal(init.error, undefined);
    assert.equal(init.result.serverInfo.name, "AuraCite Agent Hub JSON-RPC Bridge");

    const listed = await client.request("tools/list");
    const names = listed.result.tools.map((tool) => tool.name);
    assert.ok(names.includes("get_project_status"));
    assert.ok(names.includes("get_agent_hub_timeline"));
    assert.ok(names.includes("get_intelligence_freshness"));
    assert.ok(names.includes("list_intelligence_refresh_candidates"));
    assert.ok(names.includes("create_intelligence_refresh_plan_draft"));
    assert.ok(names.includes("get_intelligence_refresh_status"));
    assert.ok(names.includes("list_project_memory_entries"));
    assert.equal(names.includes("trigger_intelligence_refresh"), false);
    assert.equal(names.includes("update_action_status"), false);
    assert.equal(names.includes("trigger_scan"), false);

    const read = await client.request("tools/call", {
      name: "get_project_status",
      arguments: { tenant_id: "ignored-by-server" }
    });
    assert.equal(read.error, undefined);
    const readBody = JSON.parse(read.result.content[0].text);
    assert.equal(readBody.proxied_tool, "get_project_status");

    const timeline = await client.request("tools/call", {
      name: "get_agent_hub_timeline",
      arguments: { limit: 4 }
    });
    assert.equal(timeline.error, undefined);
    const timelineBody = JSON.parse(timeline.result.content[0].text);
    assert.equal(timelineBody.proxied_tool, "get_agent_hub_timeline");

    const denied = await client.request("tools/call", {
      name: "update_action_status",
      arguments: { run_id: "run-1" }
    });
    assert.match(denied.error.message, /disabled by local bridge/i);
    await client.close();
  }

  {
    const client = createBridgeClient({ AURACITE_MCP_BRIDGE_MODE: "confirmed-writes" });
    const listed = await client.request("tools/list");
    const names = listed.result.tools.map((tool) => tool.name);
    assert.ok(names.includes("trigger_intelligence_refresh"));
    assert.ok(names.includes("update_action_status"));
    assert.ok(names.includes("append_project_memory_entry"));
    assert.ok(names.includes("trigger_scan"));
    assert.ok(names.includes("generate_ai_prompts"));

    const write = await client.request("tools/call", {
      name: "update_action_status",
      arguments: { run_id: "run-1", status: "implemented" }
    });
    assert.equal(write.error, undefined);
    const writeBody = JSON.parse(write.result.content[0].text);
    assert.equal(writeBody.proxied_tool, "update_action_status");

    const spend = await client.request("tools/call", {
      name: "generate_ai_prompts",
      arguments: { url: "https://example.com", max_credits: 1 }
    });
    assert.equal(spend.error, undefined);
    const spendBody = JSON.parse(spend.result.content[0].text);
    assert.equal(spendBody.proxied_tool, "generate_ai_prompts");
    await client.close();
  }

  assert.ok(
    remoteRequests.some((request) => request.method === "tools/list" && request.apiKey === "test-token"),
    "bridge did not forward X-API-Key to the JSON-RPC endpoint"
  );
} finally {
  server.close();
}

console.log("AuraCite JSON-RPC bridge tests passed.");
