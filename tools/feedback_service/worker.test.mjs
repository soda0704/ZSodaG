import { test } from "node:test";
import assert from "node:assert/strict";
import { createHash } from "node:crypto";
import worker, { FeedbackReceipt, MAX_UPLOAD } from "./worker.mjs";

const encoder = new TextEncoder();
const id = "2026-10-13T15-25-00_1234567890abcdef";
function report(overrides = {}) {
  return { schema_version: 1, report_id: id, saved_at_utc: "2026-10-13T15:25:00Z", title: "Дверь", description: "Дверь не открылась. @everyone <script>", steps: "Нажать E", category: "Ошибка", severity: "Мешает играть", context: { base: { day: 2 } }, attachment: "", ...overrides };
}
function request(value = report(), screenshot = null) {
  const form = new FormData();
  form.append("report", new Blob([JSON.stringify(value)], { type: "application/json" }), "report.json");
  if (screenshot) form.append("screenshot", new Blob([screenshot], { type: "image/png" }), "screenshot.png");
  return new Request("https://feedback.example/reports", { method: "POST", body: form });
}
function png() {
  // Real 1x1 PNG, suitable for binary-preserving transport checks.
  return Buffer.from("iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAQAAAC1HAwCAAAAC0lEQVR42mP8/x8AAwMCAO+a2ioAAAAASUVORK5CYII=", "base64");
}
function fixture() {
  const storage = new Map(); const files = new Map(); const issues = [];
  let calls = 0, loseIssueResponse = false;
  const env = { GITHUB_REPOSITORY: "team/feedback", GITHUB_BRANCH: "main", GITHUB_TOKEN: "fake-server-token", REPORT_LIMITER: { limit: async () => ({ success: true }) } };
  const ctx = { storage: { get: async key => storage.get(key), put: async (key, value) => storage.set(key, value) } };
  let receipt = new FeedbackReceipt(ctx, env);
  env.RECEIPTS = { idFromName: name => name, get: () => ({ fetch: req => receipt.fetch(req) }) };
  const original = globalThis.fetch;
  globalThis.fetch = async (url, options) => {
    calls++;
    assert.ok(String(url).startsWith("https://api.github.com/repos/team/feedback/"));
    assert.equal(options.headers.Authorization, "Bearer fake-server-token");
    const path = new URL(url).pathname.replace("/repos/team/feedback", "");
    if (path.startsWith("/contents/")) {
      if (options.method === "GET") return files.has(path) ? Response.json(files.get(path)) : Response.json({}, { status: 404 });
      const input = JSON.parse(options.body);
      assert.equal(options.method, "PUT");
      assert.equal(input.branch, "main");
      assert.equal(files.has(path), false);
      const bytes = Buffer.from(input.content, "base64");
      const sha = createHash("sha1").update(`blob ${bytes.length}\0`).update(bytes).digest("hex");
      const content = { sha, html_url: "https://github.com/team/feedback/blob/main" + path, bytes };
      files.set(path, content);
      return Response.json({ content }, { status: 201 });
    }
    if (path === "/issues" && options.method === "GET") return Response.json(issues);
    if (path === "/issues" && options.method === "POST") {
      const issue = { ...JSON.parse(options.body), number: issues.length + 1, html_url: "https://github.com/team/feedback/issues/1" };
      issues.push(issue);
      if (loseIssueResponse) { loseIssueResponse = false; throw new Error("Lost HTTP response"); }
      return Response.json(issue, { status: 201 });
    }
    throw new Error("Unexpected API call");
  };
  return { env, files, issues, storage, calls: () => calls, restore: () => { globalThis.fetch = original; }, restart: () => { receipt = new FeedbackReceipt(ctx, env); }, loseIssueResponse: () => { loseIssueResponse = true; } };
}

test("JSON + PNG become private repository files and an issue; retry does not duplicate", async () => {
  const f = fixture();
  try {
    const value = report({ attachment: "screenshot.png" });
    const first = await worker.fetch(request(value, png()), f.env);
    assert.equal(first.status, 200);
    assert.deepEqual(await first.json(), { ok: true, report_id: id });
    assert.equal(f.files.size, 2); assert.equal(f.issues.length, 1);
    assert.deepEqual(f.files.get(`/contents/reports/${id}/screenshot.png`).bytes, png());
    assert.ok(f.issues[0].body.includes("Открыть скриншот"));
    assert.ok(!f.issues[0].body.includes("@everyone"));
    assert.ok(f.issues[0].body.includes("&lt;script&gt;"));
    const calls = f.calls(); f.restart();
    assert.equal((await worker.fetch(request(value, png()), f.env)).status, 200);
    assert.equal(f.calls(), calls); assert.equal(f.issues.length, 1);
    assert.equal((await worker.fetch(request(report({ description: "Changed" })), f.env)).status, 409);
  } finally { f.restore(); }
});

test("concurrent retries produce one issue", async () => {
  const f = fixture();
  try {
    const responses = await Promise.all([worker.fetch(request(), f.env), worker.fetch(request(), f.env)]);
    assert.ok(responses.every(value => value.status === 200)); assert.equal(f.issues.length, 1);
  } finally { f.restore(); }
});

test("lost issue response is recovered after receiver restart", async () => {
  const f = fixture();
  try {
    f.loseIssueResponse();
    assert.equal((await worker.fetch(request(), f.env)).status, 503);
    assert.equal(f.issues.length, 1); f.restart();
    assert.equal((await worker.fetch(request(), f.env)).status, 200);
    assert.equal(f.issues.length, 1); assert.equal(f.files.size, 1);
  } finally { f.restore(); }
});

test("invalid descriptions, paths, JSON, screenshot mismatch and overlarge bodies are rejected", async () => {
  const f = fixture();
  try {
    for (const bad of [report({ title: " " }), report({ report_id: "../../attack" }), report({ category: "unknown" }), report({ description: "x".repeat(8001) }), report({ attachment: "screenshot.png" })]) {
      assert.equal((await worker.fetch(request(bad), f.env)).status, 400);
    }
    assert.equal((await worker.fetch(request(report({ attachment: "screenshot.png" }), encoder.encode("bad")), f.env)).status, 400);
    const oversized = request(); oversized.headers.set("Content-Length", String(MAX_UPLOAD + 1));
    assert.equal((await worker.fetch(oversized, f.env)).status, 413);
    assert.equal(f.calls(), 0);
  } finally { f.restore(); }
});

test("rate limit, configuration error and health never expose GitHub credentials", async () => {
  const f = fixture();
  try {
    f.env.REPORT_LIMITER.limit = async () => ({ success: false });
    assert.equal((await worker.fetch(request(), f.env)).status, 429);
    delete f.env.GITHUB_TOKEN;
    const unavailable = await worker.fetch(request(), f.env);
    assert.equal(unavailable.status, 503); assert.ok(!(await unavailable.text()).includes("fake-server-token"));
    assert.equal((await worker.fetch(new Request("https://feedback.example/health"), f.env)).status, 200);
    assert.equal(f.calls(), 0);
  } finally { f.restore(); }
});
