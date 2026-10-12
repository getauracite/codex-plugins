import assert from "node:assert/strict";
import { spawn } from "node:child_process";
import { once } from "node:events";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import path from "node:path";

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
const pluginRoot = path.resolve(__dirname, "..");
const bridgePath = path.join(pluginRoot, "bridge", "auracite_jsonrpc_bridge.mjs");
const manifest = JSON.parse(readFileSync(path.join(pluginRoot, ".codex-plugin", "plugin.json"), "utf8"));

const rpcURL = process.env.AURACITE_MCP_RPC_URL || "https://auracite.de/mcp/rpc";
const mode = process.env.AURACITE_MCP_BRIDGE_MODE || "safe";

if (!process.env.AURACITE_MCP_TOKEN) {
  throw new Error("AURACITE_MCP_TOKEN is required for the session dogfood suite.");
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
      if (separator === -1) return;

      const header = stdout.subarray(0, separator).toString("utf8");
      const match = /Content-Length:\s*(\d+)/i.exec(header);
      assert.ok(match, `missing Content-Length header in ${header}`);

      const length = Number(match[1]);
      const bodyStart = separator + separatorLength;
      const bodyEnd = bodyStart + length;
      if (stdout.length < bodyEnd) return;

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

function firstArrayLength(body, keys) {
  for (const key of keys) {
    if (Array.isArray(body?.[key])) return body[key].length;
  }
  return 0;
}

function extractOpportunityID(...bodies) {
  const candidateLists = [];
  for (const body of bodies) {
    candidateLists.push(body?.opportunities, body?.briefs, body?.items, body?.data);
  }
  for (const list of candidateLists) {
    if (!Array.isArray(list)) continue;
    const found = list.find((item) => typeof item?.id === "string" || typeof item?.opportunity_id === "string");
    if (found) return found.id || found.opportunity_id;
  }
  return "";
}

function assertNoKnownSideEffects(body, toolName) {
  if (Object.prototype.hasOwnProperty.call(body, "mutation_performed")) {
    assert.equal(body.mutation_performed, false, `${toolName} must not mutate in safe dogfood`);
  }
  if (Object.prototype.hasOwnProperty.call(body, "provider_calls_triggered")) {
    assert.equal(body.provider_calls_triggered, 0, `${toolName} must not trigger providers`);
  }
  if (Object.prototype.hasOwnProperty.call(body, "credits_charged")) {
    assert.equal(body.credits_charged, 0, `${toolName} must not charge credits`);
  }
}

async function callTool(client, session, name, args = {}) {
  const started = Date.now();
  const response = await client.request("tools/call", { name, arguments: args });
  assert.equal(response.error, undefined, `${name} returned bridge error: ${response.error?.message || ""}`);
  const body = parseToolContent(response);
  assertNoKnownSideEffects(body, name);
  session.tools_used.push(name);
  session.tool_latencies_ms[name] = Date.now() - started;
  return body;
}

function passedSession(name) {
  return {
    name,
    result: "passed",
    tools_used: [],
    tool_latencies_ms: {},
    observations: {},
    findings: []
  };
}

const client = createBridgeClient();
const sessions = [];
const findings = [];

try {
  const init = await client.request("initialize", {
    protocolVersion: "2024-11-05",
    clientInfo: { name: "auracite-agent-hub-dogfood-sessions", version: "0.0.0" }
  });
  assert.equal(init.error, undefined);
  assert.equal(init.result.serverInfo.name, "AuraCite Agent Hub JSON-RPC Bridge");

  const listed = await client.request("tools/list");
  assert.equal(listed.error, undefined);
  const toolNames = listed.result.tools.map((tool) => tool.name);
  const requiredSafeTools = [
    "get_intelligence_overview",
    "get_intelligence_freshness",
    "list_intelligence_refresh_candidates",
    "create_intelligence_refresh_plan_draft",
    "get_intelligence_refresh_status",
    "list_intelligence_opportunity_briefs",
    "get_intelligence_opportunity_brief",
    "list_action_handoffs",
    "list_project_memory_entries",
    "create_context_pack_draft",
    "create_action_handoff_draft",
    "write_approval_note_draft"
  ];
  const missing = requiredSafeTools.filter((name) => !toolNames.includes(name));
  assert.deepEqual(missing, [], `safe bridge missing tools: ${missing.join(", ")}`);
  assert.equal(toolNames.includes("update_action_status"), false, "safe mode must hide update_action_status");
  assert.equal(toolNames.includes("trigger_scan"), false, "safe mode must hide trigger_scan");

  const startup = passedSession("startup_context");
  // Startup context comes from the tenant memory store; the AuraCite-internal
  // snapshot tools are operator-only since AuraCite PR #198.
  const startupMemory = await callTool(client, startup, "list_project_memory_entries", { limit: 8 });
  startup.observations = {
    memory_entries: firstArrayLength(startupMemory, ["entries", "items"]),
    redaction_state: startupMemory.redaction_state || ""
  };
  if (startup.observations.memory_entries < 3) {
    startup.findings.push("Project memory has fewer than 3 entries; first-run context may feel thin.");
  }
  sessions.push(startup);

  const triage = passedSession("visibility_triage");
  const overview = await callTool(client, triage, "get_intelligence_overview", { limit: 8 });
  const freshness = await callTool(client, triage, "get_intelligence_freshness", { limit: 8 });
  const refreshCandidates = await callTool(client, triage, "list_intelligence_refresh_candidates", { limit: 8 });
  const refreshPlan = await callTool(client, triage, "create_intelligence_refresh_plan_draft", { limit: 5 });
  const refreshStatus = await callTool(client, triage, "get_intelligence_refresh_status", { limit: 5 });
  const briefs = await callTool(client, triage, "list_intelligence_opportunity_briefs", { limit: 8 });
  const opportunityID = extractOpportunityID(overview, briefs);
  let brief = null;
  if (opportunityID) {
    brief = await callTool(client, triage, "get_intelligence_opportunity_brief", { opportunity_id: opportunityID });
  } else {
    triage.findings.push("No opportunity ID was available for a detailed brief call.");
  }
  triage.observations = {
    freshness_state: overview.freshness_state || "",
    refresh_status: refreshStatus.status || "",
    refresh_candidate_count: refreshCandidates.total ?? freshness.refresh_candidate_count ?? 0,
    refresh_plan_gate: refreshPlan.approval_gate || "",
    opportunity_count: firstArrayLength(overview, ["opportunities", "briefs", "items"]),
    brief_count: firstArrayLength(briefs, ["briefs", "opportunities", "items"]),
    detailed_brief_called: Boolean(brief),
    evidence_count: firstArrayLength(overview, ["evidence", "evidence_items"]),
    selected_opportunity_present: Boolean(opportunityID)
  };
  if (overview.freshness_state && overview.freshness_state !== "fresh") {
    triage.findings.push(`Intelligence overview freshness is '${overview.freshness_state}'; refresh or demo-context framing is needed before public screenshots.`);
  }
  if (refreshPlan.mutation_performed !== false || refreshPlan.provider_calls_triggered !== 0 || refreshPlan.credits_charged !== 0) {
    throw new Error("create_intelligence_refresh_plan_draft must be side-effect free");
  }
  sessions.push(triage);

  const draft = passedSession("handoff_draft");
  if (opportunityID) {
    const contextPack = await callTool(client, draft, "create_context_pack_draft", { opportunity_id: opportunityID });
    const handoff = await callTool(client, draft, "create_action_handoff_draft", { opportunity_id: opportunityID });
    const approval = await callTool(client, draft, "write_approval_note_draft", {
      opportunity_id: opportunityID,
      audience: "internal_dogfood"
    });
    for (const [toolName, body] of [
      ["create_context_pack_draft", contextPack],
      ["create_action_handoff_draft", handoff],
      ["write_approval_note_draft", approval]
    ]) {
      assert.equal(body.approval_gate, "human_review_required", `${toolName} must preserve human_review_required`);
    }
    draft.observations = {
      context_pack_gate: contextPack.approval_gate || "",
      handoff_gate: handoff.approval_gate || "",
      approval_note_gate: approval.approval_gate || "",
      draft_only: true
    };
  } else {
    draft.result = "skipped";
    draft.findings.push("Skipped because no opportunity ID was available.");
  }
  sessions.push(draft);

  const closeout = passedSession("closeout_memory");
  const handoffs = await callTool(client, closeout, "list_action_handoffs", { limit: 10 });
  const memoryEntries = await callTool(client, closeout, "list_project_memory_entries", { limit: 5 });
  const denied = await client.request("tools/call", {
    name: "update_action_status",
    arguments: {
      run_id: "00000000-0000-0000-0000-000000000000",
      status: "implemented",
      idempotency_key: "dogfood-safe-mode-deny"
    }
  });
  assert.ok(denied.error, "safe-mode bridge must deny update_action_status");
  assert.match(denied.error.message, /disabled by local bridge/i);
  closeout.tools_used.push("update_action_status_denied_by_safe_bridge");
  closeout.observations = {
    handoff_count: firstArrayLength(handoffs, ["handoffs", "items", "runs"]),
    memory_entry_count: firstArrayLength(memoryEntries, ["entries", "items"]),
    safe_write_denial: true
  };
  if (closeout.observations.memory_entry_count === 0) {
    closeout.findings.push("No recent server-side memory entries returned; pilot docs should explain when entries appear.");
  }
  sessions.push(closeout);

  for (const session of sessions) {
    findings.push(...session.findings.map((finding) => `${session.name}: ${finding}`));
  }

  const summary = {
    run_at: new Date().toISOString(),
    plugin_name: manifest.name,
    plugin_version: manifest.version,
    bridge_name: init.result.serverInfo.name,
    rpc_url: rpcURL,
    mode,
    safe_tool_count: toolNames.length,
    sessions_run: sessions.length,
    sessions_passed: sessions.filter((session) => session.result === "passed").length,
    sessions_skipped: sessions.filter((session) => session.result === "skipped").length,
    has_get_agent_hub_timeline: toolNames.includes("get_agent_hub_timeline"),
    safe_mode_hides_confirmed_writes: !toolNames.includes("update_action_status"),
    safe_mode_hides_cost_tools: !toolNames.includes("trigger_scan"),
    mutation_performed: false,
    provider_calls_triggered: 0,
    credits_charged: 0,
    printed_secrets_or_tokens: false,
    sessions,
    findings,
    recommended_optimizations: [
      "Keep scenario dogfood in the release gate before public listing.",
      ...(findings.length > 0 ? findings : ["No blocking findings from the scripted real-session suite."]),
      "Capture a non-sensitive screenshot/demo from the same session flow before broad listing."
    ]
  };

  console.log(JSON.stringify(summary, null, 2));
} finally {
  await client.close();
}
