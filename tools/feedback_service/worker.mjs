// Public game endpoint -> durable per-report receipt -> private GitHub repository.
// No GitHub token, account login or repository access is required from testers.
export const MAX_UPLOAD = 16 * 1024 * 1024;
const ID_PATTERN = /^\d{4}-\d{2}-\d{2}T\d{2}-\d{2}-\d{2}_[a-f0-9]{16}$/;
const encoder = new TextEncoder();

class InputError extends Error {
  constructor(message, status = 400) { super(message); this.status = status; }
}

function response(value, status = 200) {
  return Response.json(value, { status, headers: { "Cache-Control": "no-store" } });
}

async function readBounded(request) {
  const declared = Number(request.headers.get("Content-Length"));
  if (declared > MAX_UPLOAD) throw new InputError("Report is too large", 413);
  const reader = request.body?.getReader();
  if (!reader) throw new InputError("Missing report");
  const chunks = []; let length = 0;
  while (true) {
    const { value, done } = await reader.read();
    if (done) break;
    length += value.length;
    if (length > MAX_UPLOAD) { await reader.cancel(); throw new InputError("Report is too large", 413); }
    chunks.push(value);
  }
  const bytes = new Uint8Array(length); let offset = 0;
  for (const chunk of chunks) { bytes.set(chunk, offset); offset += chunk.length; }
  return bytes;
}

async function parseReport(bytes, contentType) {
  if (!contentType?.startsWith("multipart/form-data;")) throw new InputError("Expected multipart report");
  let form;
  try { form = await new Response(bytes, { headers: { "Content-Type": contentType } }).formData(); }
  catch { throw new InputError("Invalid multipart report"); }
  if (form.getAll("report").length !== 1 || form.getAll("screenshot").length > 1 || [...form.keys()].some(key => !["report", "screenshot"].includes(key))) throw new InputError("Invalid attachments");
  const file = form.get("report");
  if (!(file instanceof Blob) || file.size > 128 * 1024) throw new InputError("Invalid report JSON");
  let report;
  try { report = JSON.parse(await file.text()); } catch { throw new InputError("Invalid report JSON"); }
  if (!report || report.schema_version !== 1 || !ID_PATTERN.test(report.report_id)) throw new InputError("Invalid report identity");
  const text = (key, limit, required = false) => {
    if (typeof report[key] !== "string" || report[key].length > limit || (required && !report[key].trim())) throw new InputError(`Invalid ${key}`);
  };
  text("title", 120, true); text("description", 8000, true); text("steps", 8000);
  if (!["Ошибка", "Идея", "Впечатления"].includes(report.category) || !["Не мешает играть", "Мешает играть", "Блокирует прохождение"].includes(report.severity)) throw new InputError("Invalid category");
  if (!report.context || typeof report.context !== "object" || Array.isArray(report.context)) throw new InputError("Missing game context");
  if (JSON.stringify(report.context).length > 16384) throw new InputError("Game context is too large");
  if (!Number.isFinite(Date.parse(report.saved_at_utc))) throw new InputError("Invalid timestamp");
  const attachment = form.get("screenshot");
  let screenshot = null;
  if (attachment) {
    if (!(attachment instanceof Blob)) throw new InputError("Invalid screenshot");
    screenshot = new Uint8Array(await attachment.arrayBuffer());
    const signature = [137, 80, 78, 71, 13, 10, 26, 10];
    if (screenshot.length < 24 || signature.some((value, i) => screenshot[i] !== value) || new TextDecoder().decode(screenshot.slice(12, 16)) !== "IHDR") throw new InputError("Expected PNG screenshot");
    const view = new DataView(screenshot.buffer, screenshot.byteOffset, screenshot.byteLength);
    if (view.getUint32(16) < 1 || view.getUint32(20) < 1 || view.getUint32(16) > 1920 || view.getUint32(20) > 1920) throw new InputError("Screenshot dimensions exceed limit");
  }
  if (report.attachment !== (screenshot ? "screenshot.png" : "")) throw new InputError("Attachment does not match JSON");
  return { report, json: new Uint8Array(await file.arrayBuffer()), screenshot };
}

function base64(bytes) {
  let binary = "";
  for (let i = 0; i < bytes.length; i += 8192) binary += String.fromCharCode(...bytes.subarray(i, i + 8192));
  return btoa(binary);
}

async function digest(bytes) {
  return [...new Uint8Array(await crypto.subtle.digest("SHA-256", bytes))].map(v => v.toString(16).padStart(2, "0")).join("");
}

function safeText(text) {
  // User descriptions are plain text in a GitHub issue, without pings/HTML injection.
  return text.replaceAll("@", "@\u200b").replaceAll("<", "&lt;").replaceAll(">", "&gt;");
}

function issueBody(report, jsonURL, screenshotURL) {
  const context = JSON.stringify(report.context, null, 2).replaceAll("`", "\\u0060");
  return `Тип: **${report.category}** · Влияние: **${report.severity}**\n\n### Описание\n${safeText(report.description)}\n\n### Как повторить\n${safeText(report.steps || "Не указано")}\n\n### Вложения\n[JSON отчёта](${jsonURL})${screenshotURL ? `\n\n[Открыть скриншот](${screenshotURL})` : ""}\n\n### Контекст игры\n\`\`\`json\n${context}\n\`\`\`\n\n<!-- northernlab-report:${report.report_id} -->`;
}

export class FeedbackReceipt {
  constructor(ctx, env) { this.ctx = ctx; this.env = env; this.pending = null; }

  async github(method, path, data) {
    const result = await fetch(`https://api.github.com/repos/${this.env.GITHUB_REPOSITORY}${path}`, {
      method,
      headers: { "Authorization": `Bearer ${this.env.GITHUB_TOKEN}`, "Accept": "application/vnd.github+json", "X-GitHub-Api-Version": "2026-03-10", "User-Agent": "NorthernLab-Playtest", ...(data ? { "Content-Type": "application/json" } : {}) },
      ...(data ? { body: JSON.stringify(data) } : {}),
      signal: AbortSignal.timeout(15000),
    });
    if (!result.ok) throw new Error(`GitHub ${result.status}`);
    return result.json();
  }

  async uploadFile(id, name, bytes) {
    const branch = this.env.GITHUB_BRANCH || "main";
    const path = `/contents/reports/${id}/${name}`;
    // Retry after a lost response: a matching file is reused, never overwritten.
    let existing;
    try { existing = await this.github("GET", `${path}?ref=${encodeURIComponent(branch)}`); }
    catch (error) { if (error.message !== "GitHub 404") throw error; }
    if (existing) {
      const blob = new Uint8Array(encoder.encode(`blob ${bytes.length}\0`).length + bytes.length);
      const header = encoder.encode(`blob ${bytes.length}\0`);
      blob.set(header); blob.set(bytes, header.length);
      const sha = [...new Uint8Array(await crypto.subtle.digest("SHA-1", blob))].map(v => v.toString(16).padStart(2, "0")).join("");
      if (sha !== existing.sha) throw new InputError("Report identity already used", 409);
      return existing.html_url;
    }
    const created = await this.github("PUT", path, { message: `Playtest report ${id}: ${name}`, content: base64(bytes), branch });
    return created.content.html_url;
  }

  async deliver(payload) {
    const { report, json, screenshot } = payload;
    const fingerprint = await digest(encoder.encode(JSON.stringify({ json: await digest(json), screenshot: screenshot ? await digest(screenshot) : "" })));
    const previous = await this.ctx.storage.get("fingerprint");
    if (previous && previous !== fingerprint) throw new InputError("Report identity already used", 409);
    await this.ctx.storage.put("fingerprint", fingerprint);
    const received = await this.ctx.storage.get("receipt");
    if (received) return received;
    const jsonURL = await this.uploadFile(report.report_id, "report.json", json);
    const screenshotURL = screenshot ? await this.uploadFile(report.report_id, "screenshot.png", screenshot) : "";
    const marker = `<!-- northernlab-report:${report.report_id} -->`;
    // Persisted before creating an issue. After an ambiguous timeout/restart, check
    // issues created since the first attempt rather than duplicating the report.
    const since = await this.ctx.storage.get("issue_attempt_at");
    if (since) {
      for (let page = 1; ; page++) {
        const issues = await this.github("GET", `/issues?state=all&since=${encodeURIComponent(since)}&per_page=100&page=${page}`);
        const existing = issues.find(issue => !issue.pull_request && issue.body?.includes(marker));
        if (existing) {
          const receipt = { ok: true, report_id: report.report_id };
          await this.ctx.storage.put("receipt", receipt);
          return receipt;
        }
        if (issues.length < 100) break;
      }
    }
    await this.ctx.storage.put("issue_attempt_at", since || new Date(Date.now() - 60000).toISOString());
    const created = await this.github("POST", "/issues", { title: `[${report.category}] ${safeText(report.title)}`, body: issueBody(report, jsonURL, screenshotURL) });
    if (!Number.isInteger(created.number) || !created.html_url) throw new Error("Invalid GitHub receipt");
    const receipt = { ok: true, report_id: report.report_id };
    await this.ctx.storage.put("receipt", receipt);
    return receipt;
  }

  async fetch(request) {
    try {
      const payload = await parseReport(await readBounded(request), request.headers.get("Content-Type"));
      // The promise serializes requests to this report while GitHub I/O is pending.
      // A concurrent replay is processed afterwards and receives the stored receipt.
      while (this.pending) { try { await this.pending; } catch {} }
      this.pending = this.deliver(payload);
      try { return response(await this.pending); } finally { this.pending = null; }
    } catch (error) {
      return response({ ok: false, error: error instanceof InputError ? error.message : "Delivery unavailable; retry the same report" }, error instanceof InputError ? error.status : 503);
    }
  }
}

export default {
  async fetch(request, env) {
    const url = new URL(request.url);
    if (url.pathname === "/health" && request.method === "GET") return response({ ok: true });
    if (url.pathname !== "/reports") return response({ ok: false }, 404);
    if (request.method !== "POST") return response({ ok: false }, 405);
    if (!env.GITHUB_TOKEN || !/^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/.test(env.GITHUB_REPOSITORY || "")) return response({ ok: false, error: "Receiver is not configured" }, 503);
    try {
      const limit = await env.REPORT_LIMITER.limit({ key: request.headers.get("CF-Connecting-IP") || "unknown" });
      if (!limit.success) return response({ ok: false, error: "Please retry later" }, 429);
      const bytes = await readBounded(request);
      const type = request.headers.get("Content-Type");
      const { report } = await parseReport(bytes, type);
      const id = env.RECEIPTS.idFromName(report.report_id);
      return env.RECEIPTS.get(id).fetch(new Request("https://internal/reports", { method: "POST", headers: { "Content-Type": type }, body: bytes }));
    } catch (error) {
      return response({ ok: false, error: error instanceof InputError ? error.message : "Receiver unavailable" }, error instanceof InputError ? error.status : 503);
    }
  },
};
