export class ApiError extends Error {
  constructor(message, { status = 0, code = "generic", detail = "" } = {}) {
    super(message);
    this.name = "ApiError";
    this.status = status;
    this.code = code;
    this.detail = detail;
  }
}

export function normaliseBaseUrl(baseUrl = "") {
  return String(baseUrl || "").trim().replace(/\/+$/, "");
}

function timeoutSignal(ms, external) {
  const controller = new AbortController();
  const timer = setTimeout(() => controller.abort(new DOMException("timeout", "TimeoutError")), ms);
  if (!external) return { signal: controller.signal, clear: () => clearTimeout(timer) };
  if (external.aborted) controller.abort(external.reason);
  const onAbort = () => controller.abort(external.reason);
  external.addEventListener("abort", onAbort, { once: true });
  return {
    signal: controller.signal,
    clear: () => {
      clearTimeout(timer);
      external.removeEventListener("abort", onAbort);
    },
  };
}

function mapStatus(status) {
  if (status === 401) return "401";
  if (status === 403) return "403";
  if (status === 404) return "404";
  if (status === 429) return "429";
  if (status >= 500) return "5xx";
  return "generic";
}

function providerMessage(payload) {
  if (!payload) return "";
  if (typeof payload === "string") return payload.slice(0, 300);
  const err = payload.error;
  if (typeof err === "string") return err;
  if (err && typeof err === "object") return String(err.message || err.code || "").slice(0, 300);
  return String(payload.message || payload.detail || "").slice(0, 300);
}

async function readJson(response) {
  const text = await response.text();
  if (!text) return null;
  try {
    return JSON.parse(text);
  } catch {
    return text;
  }
}

async function request(settings, path, { method = "GET", body, timeout = 90000, signal } = {}) {
  const base = normaliseBaseUrl(settings.baseUrl);
  if (!settings.apiKey) throw new ApiError("Missing API key", { code: "missing_key" });
  if (!base) throw new ApiError("Missing Base URL", { code: "missing_base" });
  const timed = timeoutSignal(timeout, signal);
  try {
    const response = await fetch(`${base}${path}`, {
      method,
      headers: {
        Authorization: `Bearer ${settings.apiKey}`,
        "Content-Type": "application/json",
        Accept: "application/json",
      },
      body: body ? JSON.stringify(body) : undefined,
      signal: timed.signal,
      mode: "cors",
      cache: "no-store",
    });
    const payload = await readJson(response);
    if (!response.ok) {
      const detail = providerMessage(payload);
      throw new ApiError(detail || `HTTP ${response.status}`, {
        status: response.status,
        code: mapStatus(response.status),
        detail,
      });
    }
    return payload;
  } catch (error) {
    if (error instanceof ApiError) throw error;
    if (error?.name === "TimeoutError" || error?.name === "AbortError") {
      if (signal?.aborted) throw new ApiError("Aborted", { code: "aborted" });
      throw new ApiError("Request timed out", { code: "timeout" });
    }
    throw new ApiError("Network or CORS failure", { code: "network", detail: error?.message || String(error) });
  } finally {
    timed.clear();
  }
}

export async function listModels(settings) {
  const payload = await request(settings, "/models", { timeout: 25000 });
  const data = Array.isArray(payload?.data) ? payload.data : Array.isArray(payload) ? payload : [];
  return data.map((item) => (typeof item === "string" ? item : item?.id)).filter(Boolean);
}

export async function testConnection(settings) {
  const models = await listModels(settings);
  return { ok: true, count: models.length, models };
}

function normaliseUsage(usage) {
  if (!usage) return { prompt: 0, completion: 0, total: 0 };
  const prompt = Number(usage.prompt_tokens ?? usage.input_tokens ?? 0) || 0;
  const completion = Number(usage.completion_tokens ?? usage.output_tokens ?? 0) || 0;
  const total = Number(usage.total_tokens ?? prompt + completion) || prompt + completion;
  return { prompt, completion, total };
}

function extractContent(message) {  const content = message?.content;
  if (typeof content === "string") return content;
  if (Array.isArray(content)) {
    return content
      .map((part) => {
        if (typeof part === "string") return part;
        if (part?.type === "text" || part?.type === "output_text") return part.text || "";
        return "";
      })
      .join("");
  }
  return "";
}

/* 深度思考：MiMo / DeepSeek 都把思考过程放在 reasoning_content；
   有些网关用 reasoning。两者都收。 */
function extractReasoning(message) {
  const value = message?.reasoning_content ?? message?.reasoning ?? "";
  return typeof value === "string" ? value.trim() : "";
}

/* 联网来源：MiMo 的 web_search 把引用放在 message.annotations（url_citation）。 */
export function extractSources(message) {
  const raw = message?.annotations;
  if (!Array.isArray(raw)) return [];
  const seen = new Set();
  const out = [];
  for (const item of raw) {
    if (!item || item.type !== "url_citation" || !item.url) continue;
    const url = String(item.url);
    if (seen.has(url)) continue;
    seen.add(url);
    out.push({
      url,
      title: String(item.title || "").slice(0, 300),
      siteName: String(item.site_name || "").slice(0, 60),
      summary: String(item.summary || "").slice(0, 500),
      publishTime: String(item.publish_time || ""),
    });
    if (out.length >= 8) break;
  }
  return out;
}

/* Set once a provider proves it cannot stream, so we stop paying for a failed
   SSE attempt on every message. Reset on reload. */
let streamUnavailable = false;

export async function chatCompletion({
  settings,
  messages,
  model,
  maxTokens = 700,
  temperature = 0.9,
  json = false,
  signal,
  retryJson = true,
  onDelta = null,
  extraBody = null,
} = {}) {
  const body = {
    model: model || settings.model,
    messages,
    max_tokens: maxTokens,
    temperature,
    top_p: 0.95,
    stream: false,
  };
  if (json) body.response_format = { type: "json_object" };
  if (extraBody && typeof extraBody === "object") Object.assign(body, extraBody);
  if (typeof onDelta === "function" && !json && !streamUnavailable) {
    const streamed = await streamChatCompletion({
      settings,
      messages,
      model: body.model,
      maxTokens,
      temperature,
      signal,
      onDelta,
      extraBody,
    }).catch((error) => {
      // Any failure before/while streaming falls back to a normal request so a
      // provider without SSE support still works, just without the live text.
      if (error?.code === "aborted") throw error;
      if (error?.code === "nostream" || [400, 404, 422].includes(Number(error?.status))) streamUnavailable = true;
      return null;
    });
    if (streamed) return streamed;
  }
  try {
    const payload = await request(settings, "/chat/completions", {
      method: "POST",
      body,
      timeout: 120000,
      signal,
    });
    const choice = payload?.choices?.[0];
    const content = extractContent(choice?.message).trim();
    if (!content) throw new ApiError("Empty reply", { code: "empty" });
    return {
      content,
      usage: normaliseUsage(payload?.usage),
      finish: choice?.finish_reason || "",
      reasoning: extractReasoning(choice?.message),
      sources: extractSources(choice?.message),
      raw: payload,
    };
  } catch (error) {
    const canRetry = json && retryJson && error instanceof ApiError && [400, 422].includes(error.status);
    if (canRetry) {
      return chatCompletion({ settings, messages, model, maxTokens, temperature, json: false, retryJson: false, signal, extraBody });
    }
    throw error;
  }
}

/** Rough completion-token estimate for SSE responses that omit usage. */
function estimateTokens(text) {
  const length = [...String(text || "")].length;
  return Math.max(1, Math.round(length * 0.7));
}

/**
 * OpenAI-compatible SSE streaming. Calls onDelta(fullText, delta) on every
 * chunk and resolves with the same shape as chatCompletion.
 */
async function streamChatCompletion({ settings, messages, model, maxTokens, temperature, signal, onDelta, extraBody = null }) {
  const base = normaliseBaseUrl(settings.baseUrl);
  if (!settings.apiKey) throw new ApiError("Missing API key", { code: "missing_key" });
  if (!base) throw new ApiError("Missing Base URL", { code: "missing_base" });
  const body = {
    model: model || settings.model,
    messages,
    max_tokens: maxTokens,
    temperature,
    top_p: 0.95,
    stream: true,
    stream_options: { include_usage: true },
  };
  if (extraBody && typeof extraBody === "object") Object.assign(body, extraBody);
  const timed = timeoutSignal(150000, signal);
  let content = "";
  let reasoning = "";
  const sourceMap = new Map();
  const collectSources = (node) => {
    for (const source of extractSources(node)) {
      if (!sourceMap.has(source.url)) sourceMap.set(source.url, source);
    }
  };
  try {
    const response = await fetch(`${base}/chat/completions`, {
      method: "POST",
      headers: {
        Authorization: `Bearer ${settings.apiKey}`,
        "Content-Type": "application/json",
        Accept: "text/event-stream",
      },
      body: JSON.stringify(body),
      signal: timed.signal,
      mode: "cors",
      cache: "no-store",
    });
    if (!response.ok) {
      const payload = await readJson(response);
      const detail = providerMessage(payload);
      throw new ApiError(detail || `HTTP ${response.status}`, {
        status: response.status,
        code: mapStatus(response.status),
        detail,
      });
    }
    if (!response.body || typeof response.body.getReader !== "function") {
      throw new ApiError("Streaming unsupported", { code: "nostream" });
    }
    const reader = response.body.getReader();
    const decoder = new TextDecoder();
    let buffer = "";
    let finish = "";
    let usage = null;
    for (;;) {
      const { value, done } = await reader.read();
      if (done) break;
      buffer += decoder.decode(value, { stream: true });
      const lines = buffer.split("\n");
      buffer = lines.pop() || "";
      for (const line of lines) {
        const trimmed = line.trim();
        if (!trimmed || trimmed.startsWith(":") || !trimmed.startsWith("data:")) continue;
        const data = trimmed.slice(5).trim();
        if (!data || data === "[DONE]") continue;
        let payload;
        try {
          payload = JSON.parse(data);
        } catch {
          continue;
        }
        if (payload?.usage) usage = payload.usage;
        const choice = payload?.choices?.[0];
        const delta = choice?.delta?.content ?? choice?.delta?.text;
        if (typeof delta === "string" && delta) {
          content += delta;
          onDelta(content, delta);
        }
        const think = choice?.delta?.reasoning_content ?? choice?.delta?.reasoning;
        if (typeof think === "string" && think) reasoning += think;
        collectSources(payload);
        collectSources(choice?.delta);
        collectSources(choice?.message);
        if (choice?.finish_reason) finish = choice.finish_reason;
      }
    }
    const text = content.trim();
    if (!text) throw new ApiError("Empty reply", { code: "empty" });
    const normalised = normaliseUsage(usage);
    return {
      content: text,
      usage: normalised.total ? normalised : { prompt: 0, completion: estimateTokens(text), total: estimateTokens(text), estimated: true },
      finish,
      streamed: true,
      reasoning: reasoning.trim(),
      sources: [...sourceMap.values()],
    };
  } catch (error) {
    if (error instanceof ApiError) {
      // A partial reply is better than throwing it away.
      if (content.trim() && error.code !== "aborted") {
        const text = content.trim();
        return {
          content: text,
          usage: { prompt: 0, completion: estimateTokens(text), total: estimateTokens(text), estimated: true },
          finish: "partial",
          streamed: true,
          reasoning: reasoning.trim(),
          sources: [...sourceMap.values()],
        };
      }
      throw error;
    }
    if (error?.name === "TimeoutError" || error?.name === "AbortError") {
      if (signal?.aborted) throw new ApiError("Aborted", { code: "aborted" });
      if (!content.trim()) throw new ApiError("Request timed out", { code: "timeout" });
      const text = content.trim();
      return {
        content: text,
        usage: { prompt: 0, completion: estimateTokens(text), total: estimateTokens(text), estimated: true },
        finish: "partial",
        streamed: true,
        reasoning: reasoning.trim(),
        sources: [...sourceMap.values()],
      };
    }
    if (!content.trim()) throw new ApiError("Network or CORS failure", { code: "network", detail: error?.message || String(error) });
    const text = content.trim();
    return {
      content: text,
      usage: { prompt: 0, completion: estimateTokens(text), total: estimateTokens(text), estimated: true },
      finish: "partial",
      streamed: true,
      reasoning: reasoning.trim(),
      sources: [...sourceMap.values()],
    };
  } finally {
    timed.clear();
  }
}

export function errorText(error, t) {
  if (error instanceof ApiError) {
    if (error.code === "missing_key") return t("setup.fillKey");
    if (error.code === "timeout") return t("error.timeout");
    if (error.code === "network") return t("error.cors");
    if (error.code === "empty") return t("error.empty");
    const key = error.code && ["401", "403", "404", "429", "5xx"].includes(error.code) ? `error.${error.code}` : "";
    const localised = key ? t(key) : "";
    if (error.detail && error.detail !== localised) {
      return localised ? `${localised} · ${error.detail}` : error.detail;
    }
    return localised || error.message || t("error.generic");
  }
  return error?.message || t("error.generic");
}
