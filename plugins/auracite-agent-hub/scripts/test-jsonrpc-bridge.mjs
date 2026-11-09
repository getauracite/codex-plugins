import assert from "node:assert/strict";
import http from "node:http";
import { once } from "node:events";
import { spawn } from "node:child_process";
import { fileURLToPath } from "node:url";
import { readFile } from "node:fs/promises";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginRoot = path.resolve(__dirname, "..");
const bridgePath = path.join(pluginRoot, "bridge", "auracite_jsonrpc_bridge.mjs");
// Synthetic remote schema: verify transparent forwarding without shipping a
// second corpus or depending on the private monorepo in this public package.
const canonicalFilterEnums = {
  provider: ["google", "openai"],
  surface: ["chatgpt_search", "google_ai_overviews"],
  industry: ["ecommerce", "local_services"],
  page_type: ["product", "service"]
};

const remoteRequests = [];
const knowledgeTools = new Set(["search_geo_knowledge", "get_geo_knowledge"]);
const remoteTools = [
  "list_projects",
  "get_visibility_kpis",
  "render_visibility_overview",
  "get_customer_guidance",
  "summarize_user_landscape",
  "list_recent_signups",
  "get_gsc_search_analytics",
  "get_gsc_top_queries",
  "get_gsc_breakdown",
  "get_gsc_top_pages",
  "get_gsc_trend",
  "get_ai_visibility_overview",
  "get_project_status",
  "search_geo_knowledge",
  "get_geo_knowledge",
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
  "create_project",
  "add_prompt",
  "add_brand",
  "bulk_add_prompts",
  "delete_brand",
  "create_demo_user",
  "add_credits"
].map((name) => ({
  name,
  description: `${name} from fake AuraCite`,
  inputSchema: {
    type: "object",
    properties: name === "search_geo_knowledge"
      ? Object.fromEntries(Object.entries(canonicalFilterEnums).map(([field, values]) => [field, { type: "string", enum: values }]))
      : {}
  }
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

  // The fake owner and customer tokens model the server-side discovery and
  // call gates. A bridge allowlist must never synthesize a hidden owner tool.
  const isOwner = req.headers["x-api-key"] === "test-token";
  if (!isOwner && req.headers["x-api-key"] !== "customer-token") {
    respond({ error: { code: -32001, message: "Authentication failed" } });
    return;
  }

  if (body.method === "tools/list") {
    respond({ result: { tools: remoteTools.filter((tool) => isOwner || !knowledgeTools.has(tool.name)) } });
    return;
  }

  if (body.method === "tools/call") {
    if (knowledgeTools.has(body.params?.name) && !isOwner) {
      respond({ error: { code: -32003, message: "Knowledge tool requires scope mcp:agentops:read and the owner gate" } });
      return;
    }
    if (body.params?.name === "get_visibility_kpis" && body.params?.arguments?.period === "1y") {
      respond({
        result: {
          isError: true,
          content: [{ type: "text", text: 'invalid period "1y": use 7d, 30d or 90d' }]
        }
      });
      return;
    }
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
  const manifest = JSON.parse(await readFile(path.join(pluginRoot, ".mcp.json"), "utf8"));
  for (const [transport, config] of Object.entries(manifest.mcpServers)) {
    for (const tool of knowledgeTools) {
      assert.equal(config.enabled_tools.filter((name) => name === tool).length, 1, `${transport} must declare ${tool} exactly once`);
      assert.equal(config.disabled_tools.includes(tool), false, `${transport} must not contradict the knowledge allowlist`);
    }
  }

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
    for (const name of knowledgeTools) {
      assert.ok(names.includes(name), `${name} must pass through safe mode when the server authorizes it`);
    }
    const knowledgeSchema = listed.result.tools.find((tool) => tool.name === "search_geo_knowledge").inputSchema;
    for (const [field, values] of Object.entries(canonicalFilterEnums)) {
      assert.deepEqual(knowledgeSchema.properties[field].enum, values, `the bridge must preserve the synthetic remote ${field} taxonomy for discovery`);
    }
    assert.ok(names.includes("get_visibility_kpis"), "read-only headline KPIs must be visible in safe mode");
    for (const name of ["render_visibility_overview", "get_customer_guidance"]) {
      assert.ok(names.includes(name), `${name} must be visible in safe mode`);
      const response = await client.request("tools/call", { name, arguments: { query: "OAI-SearchBot", surface: "chatgpt_search" } });
      assert.equal(response.error, undefined);
      assert.equal(JSON.parse(response.result.content[0].text).proxied_tool, name);
    }
    assert.ok(names.includes("get_intelligence_freshness"));
    assert.ok(names.includes("list_intelligence_refresh_candidates"));
    assert.ok(names.includes("create_intelligence_refresh_plan_draft"));
    assert.ok(names.includes("get_intelligence_refresh_status"));
    assert.ok(names.includes("list_project_memory_entries"));
    for (const toolName of [
      "list_projects",
      "get_gsc_search_analytics",
      "get_gsc_top_queries",
      "get_gsc_breakdown",
      "get_gsc_top_pages",
      "get_gsc_trend",
      "get_ai_visibility_overview"
    ]) {
      assert.ok(names.includes(toolName), `${toolName} should be visible in safe mode`);
    }
    // Platform-wide operator reads: no tenant filter server-side, admin scope
    // only, and absent from the hosted catalog. They must not survive the
    // bridge filter either, in any mode.
    assert.equal(names.includes("summarize_user_landscape"), false);
    assert.equal(names.includes("list_recent_signups"), false);
    // Project-memory snapshot tools describe AuraCite's own dev state and are
    // operator-only server-side (AuraCite PR #198); the safe bridge drops them.
    assert.equal(names.includes("get_project_status"), false);
    assert.equal(names.includes("get_agent_hub_timeline"), false);
    assert.equal(names.includes("trigger_intelligence_refresh"), false);
    assert.equal(names.includes("update_action_status"), false);
    assert.equal(names.includes("trigger_scan"), false);
    assert.equal(names.includes("create_project"), false);

    const read = await client.request("tools/call", {
      name: "list_project_memory_entries",
      arguments: { tenant_id: "ignored-by-server" }
    });
    assert.equal(read.error, undefined);
    const readBody = JSON.parse(read.result.content[0].text);
    assert.equal(readBody.proxied_tool, "list_project_memory_entries");

    const searchArgs = {
      query: "OAI-SearchBot", provider: "openai", surface: "chatgpt_search",
      industry: "ecommerce", page_type: "product", locale: "de-DE", mode: "research", limit: 3
    };
    for (const [field, values] of Object.entries(canonicalFilterEnums)) {
      assert.ok(values.includes(searchArgs[field]), `bridge search fixture ${field} must be accepted by the synthetic remote taxonomy`);
    }
    const getArgs = { id: "K013", mode: "research", expected_corpus_hash: `sha256:${"a".repeat(64)}` };
    for (const [name, args] of [["search_geo_knowledge", searchArgs], ["get_geo_knowledge", getArgs]]) {
      const response = await client.request("tools/call", { name, arguments: args });
      assert.equal(response.error, undefined);
      const body = JSON.parse(response.result.content[0].text);
      assert.equal(body.proxied_tool, name);
      assert.deepEqual(body.proxied_arguments, args, "knowledge context and revision pins must survive the stdio bridge unchanged");
    }

    for (const period of ["7d", "30d", "90d"]) {
      const kpis = await client.request("tools/call", {
        name: "get_visibility_kpis",
        arguments: { project_id: "project-1", period }
      });
      assert.equal(kpis.error, undefined);
      const body = JSON.parse(kpis.result.content[0].text);
      assert.equal(body.proxied_tool, "get_visibility_kpis");
      assert.equal(body.proxied_arguments.project_id, "project-1");
      assert.equal(body.proxied_arguments.period, period);
    }

    // The bridge must transparently return an MCP tool error from the server;
    // period validation itself is implemented and tested in the Go backend.
    const invalidPeriod = await client.request("tools/call", {
      name: "get_visibility_kpis",
      arguments: { project_id: "project-1", period: "1y" }
    });
    assert.equal(invalidPeriod.error, undefined);
    assert.equal(invalidPeriod.result.isError, true);
    assert.match(invalidPeriod.result.content[0].text, /invalid period/);

    const timeline = await client.request("tools/call", {
      name: "get_agent_hub_timeline",
      arguments: { limit: 4 }
    });
    assert.match(timeline.error.message, /disabled by local bridge/i);

    const denied = await client.request("tools/call", {
      name: "update_action_status",
      arguments: { run_id: "run-1" }
    });
    assert.match(denied.error.message, /disabled by local bridge/i);
    await client.close();
  }

  {
    const client = createBridgeClient({ AURACITE_MCP_TOKEN: "customer-token" });
    const listed = await client.request("tools/list");
    const names = listed.result.tools.map((tool) => tool.name);
    for (const name of knowledgeTools) {
      assert.equal(names.includes(name), false, "a local allowlist must not expose a server-hidden internal tool");
      const denied = await client.request("tools/call", { name, arguments: { id: "K013" } });
      assert.match(denied.error.message, /mcp:agentops:read/);
      assert.equal(denied.result, undefined, "server denial must never become a corpus answer");
    }
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
    for (const toolName of ["create_project", "add_prompt", "add_brand", "bulk_add_prompts"]) {
      assert.ok(names.includes(toolName), `${toolName} should be visible in confirmed-writes mode`);
    }
    for (const toolName of ["delete_brand", "create_demo_user", "add_credits"]) {
      assert.equal(names.includes(toolName), false, `${toolName} must remain permanently blocked`);
    }

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

    const configWrite = await client.request("tools/call", {
      name: "add_brand",
      arguments: { project_id: "project-1", name: "approved-brand", idempotency_key: "idem-1" }
    });
    assert.equal(configWrite.error, undefined);
    const configBody = JSON.parse(configWrite.result.content[0].text);
    assert.equal(configBody.proxied_tool, "add_brand");
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
