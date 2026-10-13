// Real Godot HTTPRequest -> real local HTTP -> production Worker -> mocked GitHub.
// No reports, tokens or messages are sent to an external account.
import { createServer } from "node:http";
import { spawn } from "node:child_process";
import { resolve } from "node:path";
import { createHash } from "node:crypto";
import assert from "node:assert/strict";
import worker, { FeedbackReceipt } from "../feedback_service/worker.mjs";

const files = new Map(), issues = [], receipts = new Map();
let loseResponse = true;
const env = { GITHUB_REPOSITORY: "test/feedback", GITHUB_BRANCH: "main", GITHUB_TOKEN: "only-in-local-mock", REPORT_LIMITER: { limit: async () => ({ success: true }) } };
env.RECEIPTS = {
  idFromName: name => name,
  get: name => {
    if (!receipts.has(name)) {
      const storage = new Map();
      receipts.set(name, new FeedbackReceipt({ storage: { get: async key => storage.get(key), put: async (key, value) => storage.set(key, value) } }, env));
    }
    return receipts.get(name);
  },
};
globalThis.fetch = async (url, options) => {
  assert.ok(String(url).startsWith("https://api.github.com/repos/test/feedback/"));
  const path = new URL(url).pathname;
  if (path.includes("/contents/")) {
    if (options.method === "GET") return files.has(path) ? Response.json(files.get(path)) : Response.json({}, { status: 404 });
    const bytes = Buffer.from(JSON.parse(options.body).content, "base64");
    const sha = createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
    const content = { sha, html_url: "https://github.com/test/feedback/blob/main" + path, bytes };
    files.set(path, content); return Response.json({ content }, { status: 201 });
  }
  if (options.method === "GET") return Response.json(issues);
  const issue = { ...JSON.parse(options.body), number: issues.length + 1, html_url: "https://github.com/test/feedback/issues/1" };
  issues.push(issue);
  if (loseResponse) { loseResponse = false; throw new Error("Simulated lost receipt"); }
  return Response.json(issue, { status: 201 });
};

const server = createServer(async (incoming, outgoing) => {
  try {
    const chunks = []; for await (const chunk of incoming) chunks.push(chunk);
    let result;
    if (incoming.url === "/wrong-receipt") result = Response.json({ ok: true, report_id: "incorrect" });
    else if (incoming.url === "/broken-json") result = new Response("not JSON", { status: 200 });
    else if (incoming.url === "/slow") { await new Promise(resolve => setTimeout(resolve, 1200)); result = Response.json({ ok: false }); }
    else result = await worker.fetch(new Request("https://feedback.example" + incoming.url, { method: incoming.method, headers: incoming.headers, body: Buffer.concat(chunks) }), env);
    outgoing.writeHead(result.status, Object.fromEntries(result.headers));
    outgoing.end(Buffer.from(await result.arrayBuffer()));
  } catch (error) { outgoing.writeHead(500); outgoing.end("Local receiver error"); console.error(error); }
});
await new Promise(resolve => server.listen(0, "127.0.0.1", resolve));
const executable = process.argv[2] || resolve("tools/.local/godotsteam-editor/godot.exe");
const child = spawn(executable, ["--headless", "--path", ".", "--script", "res://tools/tests/tester_feedback_delivery_regression.gd"], { env: { ...process.env, NORTHERNLAB_FEEDBACK_TEST_URL: `http://127.0.0.1:${server.address().port}` }, stdio: "inherit" });
const timer = setTimeout(() => child.kill(), 60000);
try {
  const code = await new Promise((resolve, reject) => { child.once("exit", resolve); child.once("error", reject); });
  assert.equal(code, 0);
  assert.equal(issues.length, 1, "retry/reload must not duplicate issue");
  assert.equal(files.size, 2, "JSON and PNG uploaded once");
  const png = [...files.values()].find(value => value.bytes[0] === 137);
  assert.ok(png, "actual Godot PNG reaches Worker/GitHub adapter");
  const report = JSON.parse([...files.values()].find(value => value.bytes[0] !== 137).bytes.toString("utf8"));
  assert.equal(report.context.session.role, "client");
  console.log("END-TO-END DELIVERY PASS: 1 issue, 1 JSON, 1 PNG; client has no GitHub account");
} finally { clearTimeout(timer); server.close(); server.closeAllConnections(); }
