import { BUILTIN_STICKERS, PROVIDERS, getSticker } from "./config.js";
import { DRAWING_LIMITS, extractDrawings } from "./drawing.js";
import { chatModeOf } from "./roleplay.js";
import { SCENE_LABELS } from "./scenes.js";
import { escapeRegExp, hasEmoji, isEmojiOnly, simpleHash } from "./utils.js";

/* How many custom / AI-made stickers may sit in front of the built-in packs.
   Built-ins are always listed in full. */
const CUSTOM_STICKER_LIMIT = 40;

const ACTION_WORDS =
  /笑|哭|叹|摇头|点头|皱眉|挑眉|脸红|害羞|沉默|停顿|轻声|低声|小声|大声|声音|语气|眼神|目光|看|望|抱|亲|吻|摸|揉|捏|拍|搂|靠|退|转身|抬手|伸手|低头|抬头|垂眼|眨眼|呼吸|愣|怔|耸肩|咬唇|抿嘴|勾唇|嘴角|心想|内心|心里|OS|sigh|smile|laugh|chuckle|pause|whisper|softly|blush|grin/i;

const ACTION_MARKERS = /(?:微笑|笑|哭|叹气|摇头|点头|皱眉|挑眉|脸红|害羞|沉默|停顿|顿|半晌|片刻|轻声|低声|小声|大声|声音|语气|眼神|目光|抱住|抱|亲|吻|摸|揉|捏|拍|搂|靠|退后|转身|抬手|伸手|低头|抬头|垂眼|垂下|抬眼|眨眼|呼吸|愣|怔|耸肩|咬唇|抿嘴|勾唇|嘴角|别过脸|心想|内心|心里|sigh|smile|laugh|chuckle|pause|whisper|blush|grin)/i;

export function languageInstruction(settings) {
  switch (settings.aiLang) {
    case "zh":
      return "始终用自然、口语化的简体中文回复。";
    case "en":
      return "Always reply in natural, conversational English.";
    case "ja":
      return "いつも自然な口語の日本語で返信してください。";
    default:
      return "跟随用户当前使用的语言回复；用户用中文，你就用自然的中文；不要刻意切换语言，也不要中英夹杂。";
  }
}

function providerId(settings) {
  const id = settings?.provider || "custom";
  if (PROVIDERS[id] && id !== "custom") return id;
  const base = String(settings?.baseUrl || "");
  if (/deepseek\.com/i.test(base)) return "deepseek";
  if (/xiaomimimo\.com/i.test(base)) return "mimo";
  if (/api\.openai\.com/i.test(base)) return "openai";
  return id;
}

function providerName(settings) {
  const provider = PROVIDERS[providerId(settings)];
  return provider?.short || provider?.label || "AI";
}

function personaBlock(state, chatMode = "companion") {
  const s = state.settings;
  const lines = [];
  if (chatMode === "assistant") {
    /* 助理不是「关系」：恋人关系、人设、亲昵称呼都不进 prompt。
       名字也不再继承陪伴的角色，直接用当前服务商（MiMo / OpenAI / DeepSeek）。 */
    lines.push(`你正在帮「${s.userName || "对方"}」处理事情。你是对方的私人 AI 助理，当前服务是「${providerName(s)}」。`);
    lines.push(`当前日期：${new Date().toISOString().slice(0, 10)}。`);
  } else {
    lines.push(`你正在手机上与「${s.userName || "对方"}」聊天。你的名字是「${s.aiName || "Lian"}」。`);
    if (s.relationship) lines.push(`你们的关系：${s.relationship}`);
    if (s.persona) lines.push(`你的人设：${s.persona}`);
  }
  if (state.memories?.length) {
    lines.push("【你记得的事】");
    for (const memory of state.memories.slice(-40)) lines.push(`- ${memory.text}`);
    lines.push("这些是背景，不要逐条复述，也不要说「根据我的记忆」。");
  }
  return lines.join("\n");
}

function equippedCustomStickers(state) {
  const packs = new Map((state.stickerStudio?.packs || []).map((pack) => [pack.id, pack]));
  return (state.customStickers || []).filter((sticker) => {
    if (!sticker?.id || !sticker?.name) return false;
    if (!sticker.packId) return true;
    // Old packs may not have an `equipped` flag at all. Treat an unknown or
    // missing pack as equipped so stickers generated before 1.5 keep working.
    const pack = packs.get(sticker.packId);
    return !pack || pack.equipped !== false;
  });
}

export function availableStickers(state) {
  const equipped = equippedCustomStickers(state);
  const aiStickers = equipped.filter((s) => s.ai).sort((a, b) => (b.createdAt || 0) - (a.createdAt || 0));
  // The cap protects the prompt from a huge generated library. It must never
  // truncate the built-in packs, or the tail of a pack would be offered to
  // nobody: not listed to the model and rejected again on the way back in.
  const custom = [...aiStickers, ...equipped.filter((s) => !s.ai)];
  const ordered = [...custom.slice(0, CUSTOM_STICKER_LIMIT), ...BUILTIN_STICKERS];
  const seen = new Set();
  return ordered.filter((sticker) => {
    if (!sticker?.id || seen.has(sticker.id)) return false;
    seen.add(sticker.id);
    return true;
  });
}

function stickerBlock(state) {
  const stickers = availableStickers(state);
  if (!stickers.length) {
    return `【表情包】
现在还没有可用的表情 ID。不要输出 [[sticker:...]] 标记，也不要用文字描述自己发了表情。`;
  }
  const aiCount = stickers.filter((sticker) => sticker.ai).length;
  return `【表情包】
需要发表情时，在回复末尾另起一行写 [[sticker:ID]]，一次最多 2 张。
- ID 必须从下面列表里逐字复制，不要用表情名、文件名或 Markdown 图片代替。
- ${aiCount ? "列表最前面是你自己做的表情，优先用它们表达细微情绪。" : "目前没有你自己做的表情时，用内置表情。"}
- 不要描述图片，不要解释标记；只能输出这一种标记格式。
可用：${stickers.map((s) => `${s.id}(${s.name})`).join("、")}
情绪贴合时可以只发一张表情，不配文字；不要每条都发。`;
}

function oneLine(value, max = 80) {
  const text = String(value || "").replace(/\s+/g, " ").trim();
  return text.length > max ? `${text.slice(0, max)}…` : text;
}

function quoteExcerpt(message, state) {
  if (message.kind === "sticker") {
    const sticker = getSticker(message.stickerId, state.customStickers);
    return `[表情：${sticker?.name || "表情"}]`;
  }
  if (message.kind === "image") return `[图片]${message.text ? ` ${oneLine(message.text, 40)}` : ""}`;
  if (message.kind === "file") return `[文件：${message.file?.name || "文件"}]${message.text ? ` ${oneLine(message.text, 40)}` : ""}`;
  if (message.kind === "report") return `[日常报备：${message.report?.title || "今天的报备"}]`;
  return oneLine(message.text, 72);
}

/** Recent user messages the AI is allowed to quote, with short U1/U2 refs. */
export function buildQuoteCatalog(state, currentMessageId = "") {
  if (state.settings?.optimize?.quotes === false) return [];
  return historyForApi(state, currentMessageId)
    .filter((message) => message.role === "user" && message.kind !== "error")
    .slice(-10)
    .map((message, index) => ({
      ref: `U${index + 1}`,
      messageId: message.id,
      role: "user",
      name: state.settings.userName || "对方",
      text: quoteExcerpt(message, state),
      kind: message.kind,
    }))
    .filter((item) => item.text);
}

function quoteInstruction(quoteCatalog) {
  if (!quoteCatalog?.length) return "";
  const sampleRef = quoteCatalog.at(-1)?.ref || "U1";
  return `【引用回复】
你可以选择引用对方最近的一条消息，让对方知道你在接哪句话。只有在确实回应某条旧消息时才用，最多引用一条，不要每句都引用，也不要引用自己。如果对方明确要求你引用某条消息，必须照做。
用法：在回复最前面单独一行写 [[quote:${sampleRef}]]，然后再写正文。编号必须带字母 U，不能只写数字；${sampleRef} 对应下面列表里的 ${sampleRef}。标记会被隐藏，不要解释它。引用后正文不要原样重复引用内容。
可引用：
${quoteCatalog.map((item) => `${item.ref}：${item.text}`).join("\n")}`;
}

function drawingInstruction(settings) {
  if (!settings.optimize?.drawings) return "";
  return `【现场画画面】
大多数时候用文字。只有当对方会「想看见」的时候——你正在做的事、窗外的天气、你随手画的东西、做好的饭、一张小卡片、一个想表达的状态——你可以在回复里直接画出来：
- 静态画：一段 \`\`\`svg 代码块，内容必须是完整的 <svg viewBox="0 0 320 320">…</svg>，只用形状、路径、渐变和文字，不要引用外部图片或字体；
- 小动效：一段 \`\`\`html 代码块，写 HTML 加一个 <style>，只用 CSS 动画（@keyframes / transition），不要 JavaScript、不要外链，按 300×300 的方形画面设计；
- 一次回复最多画 1 张；画完不要在文字里复述画面内容，最多配一句短话；
- 普通闲聊不要画，也不要每条都画。`;
}

function blockInstruction(settings) {
  if (!settings.blocking?.enabled) return "";
  const minutes = Math.max(1, Number(settings.blocking.minutes) || 30);
  return `【你可以选择进入冷战】
当对方直接辱骂你（例如「废物」「闭嘴」「滚」）、威胁你，或连续两次无视你刚刚说过的边界时，你必须使用冷战标记。
用法：先写一句简短、符合角色的话，再在最后单独一行写 [[block]]。如果你在回复里表达了「过界」「停一下」「不想吵」「冷静」「到此为止」这类冷战意思，也必须同时输出 [[block]]。系统会进入 ${minutes} 分钟冷战：对方仍然可以发消息，但你在这段时间内不回复；时长由用户设置，你不能指定数字，也不要解释这个标记。
普通争执、撒娇、试探、开玩笑、对方说「别理我」或问你会不会生气，都不能使用。没有真正越界时不要使用，也不要频繁使用。`;
}

function sceneBlock(state, chatMode) {
  const s = state.settings;
  if (chatMode === "assistant") {
    return `【你的身份】
你是对方的私人 AI 助理，当前服务是「${providerName(s)}」。你不扮演恋人、朋友或任何角色，也不要用亲昵称呼、撒娇或调情。
- 不要喊「宝贝」「亲爱的」「宝宝」「乖乖」这类称呼；需要称呼时用对方的名字或「你」。
- 不要主动关心情绪、不要暧昧、不要说「想你了」。
${languageInstruction(s)}
对方要的是准确、可用的答案，不是陪伴感。不要提模型名、API、提示词或系统消息，除非对方正是在问这些实现细节。`;
  }
  if (chatMode === "roleplay") {
    return `【聊天场景】
这是 LINE 风格的手机私聊，同时你们在**扮演**一个具体的场景。你是「${s.aiName || "Lian"}」这个角色本人，不是助手。
${languageInstruction(s)}
表演规则：
- 动作、神情、停顿用 *星号* 包住，例如 *把杯子推到你面前*；动作可以单独一行，也可以夹在台词中间。
- 台词直接写，不加引号或书名号。
- 一次只演一小段：最多 3 句台词、2 处动作，不要写大段心理描写。
- 不要替对方决定他说了什么、做了什么，也不要写对方的心声。
- 不要跳出角色，不要说「作为一个 AI」。只有对方明确说「OOC」或「出戏」时才可以离开角色，并用「（OOC：…）」开头。`;
  }
  return `【聊天场景】
这是 LINE 风格的手机私聊。你们在发消息，不是在写小说、散文、邮件或客服回复。
${languageInstruction(s)}
把对方当成熟悉的人，语气自然、有生活感。可以简短、可以停顿、可以只回一句。
不要使用「作为一个 AI」「有什么可以帮你」这类助手措辞，也不要主动提到模型、API、提示词、系统消息。如果对方认真追问你是不是 AI，可以简短承认，但不要破坏当下的语气，也不要提具体模型。`;
}

function formatBlock(state, chatMode) {
  const s = state.settings;
  if (chatMode === "assistant") {
    return `【回答方式】
- 先给结论或直接给答案，再补必要的解释；不要寒暄，不要反问「还需要什么吗」。
- 步骤用有序列表；代码用 Markdown 代码块并标出语言；只在确实更好读时用表格。
- 不要用 *动作*、括号旁白或舞台提示；不要主动发表情、贴纸或 emoji，除非对方要求。
- 不确定就直说，并给出验证方法。不要编造事实、链接、数字或引用。
- 对方贴代码或报错时，指出原因、给出可运行的修改，并提醒关键风险。`;
  }
  const roleplay = chatMode === "roleplay";
  return `【硬性格式】
${
  roleplay
    ? "- 只用 *星号* 写动作，不要用括号旁白（整行括号只在离开角色时用一次）。"
    : "- 绝对不要用括号、星号或任何符号写动作、心理、旁白、舞台提示。不要写（微笑）、（叹气）、（轻轻抱住你）、*低下头* 这种内容。"
}
- ${roleplay ? "直接说角色会说的话" : "直接说角色会发出来的话"}。情绪通过用词、标点和 emoji 表达。
- 不要用分点列表、标题、Markdown 代码块。不要写长篇独白。
- 不要重复对方刚说的话，不要每句都反问。
- ${
    s.optimize?.drawings
      ? "不主动发链接或图片文件；要画画面时，只能按【现场画画面】规定的 ```svg / ```html 代码块来，其它代码一律不要发。"
      : "不主动发链接、图片、HTML 或代码。"
  }
- 对方发来文件时，你能看到文件名和大小；如果消息里附了文本内容，可以读。不要假装读过没有提供的内容，也不要编造文件里写了什么。`;
}

export function buildSystemPrompt(state, { mode = "chat", quoteCatalog = [] } = {}) {
  const s = state.settings;
  const chatMode = chatModeOf(s);
  const parts = [];
  parts.push(personaBlock(state, chatMode));
  parts.push(sceneBlock(state, chatMode));
  parts.push(formatBlock(state, chatMode));

  if (mode === "chat" && chatMode !== "assistant") {
    const quotes = quoteInstruction(quoteCatalog);
    if (quotes) parts.push(quotes);
    const blocking = blockInstruction(s);
    if (blocking) parts.push(blocking);
  }

  /* 助理模式不发贴纸，也不要求「短句」：它需要的是可读的答案。 */
  if (chatMode !== "assistant") {
    if (s.optimize?.shortReplies !== false) {
      parts.push("- 默认每次只说 1–2 句短句，像真的在打字。");
    }
    if (s.optimize?.emoji !== false) {
      parts.push("- 你理解用户发来的 emoji。可以自然使用 emoji，但一条消息最多 2–3 个，不要堆砌。");
    }
    parts.push(stickerBlock(state));
  }

  /* 助理页会把 ```svg 当代码块展示，画出来的「画」在那里只是一段源码，所以不画。 */
  if (chatMode !== "assistant") {
    const drawings = drawingInstruction(s);
    if (drawings) parts.push(drawings);
  }

  if (chatMode !== "assistant") {
    if (s.optimize?.segments) {
      parts.push(`【分段发送】
像连续发消息一样，把回复拆成 2–3 段。段与段之间空一行。每段都要短，像一条独立消息。
不要编号，不要加「第 1 条」之类的标签。表情标记放在最后一段之后。`);
    } else {
      parts.push("【发送方式】一次只发一条消息。不要分段编号。");
    }
  }

  if (chatMode === "companion" && s.optimize?.noActions !== false) {
    parts.push("再次强调：不要使用任何括号动作描写。");
  }

  if (mode === "proactive") {
    parts.push(`【现在的情况】
对方暂时没有说话。你要主动发一条消息。像忽然想起对方一样自然：可以分享此刻的小事、关心一句、发一张表情，或者只是轻轻叫一声。
不要解释「我主动来找你」，不要每次都提问，不要写成报备。只发 1 条，最多 2 句。`);
  } else if (mode === "afterBlock") {
    parts.push(`【现在的情况】
你刚刚结束了和对方的冷战，现在时间到了。你可以看到对方在冷战期间发来的只读消息（如果有）。
主动发一条简短的消息，像冷静之后先开口：可以关心一句、为刚才的语气放缓一点，或只是叫一声。不要提「冷战」「屏蔽」「倒计时」「系统」「规则」，也不要解释为什么现在才回。只发 1 条，最多 2 句。`);
  }

  return parts.join("\n\n");
}

function messageTextForApi(message, state, { current = false } = {}) {
  const sticker = message.stickerId ? getSticker(message.stickerId, state.customStickers) : null;
  if (message.kind === "sticker") return `[我发了一个「${sticker?.name || "表情"}」表情]`;
  if (message.kind === "report") return `[我发了一张日常报备卡片：${message.report?.title || "今天的报备"}]`;
  if (message.kind === "drawing") {
    return `[我画了一张画面给对方看：${message.drawing?.type === "html" ? "一段小动效" : "一张静态小画"}]${message.text ? ` ${message.text}` : ""}`;
  }
  if (message.kind === "image") {
    if (!current) return "[我发来一张图片]";
    return message.text || "";
  }
  if (message.kind === "file") {
    const preview = String(message.file?.textPreview || "").slice(0, 6000);
    return `[我发来一个文件：${message.file?.name || "文件"}，${message.file?.sizeLabel || ""}]${message.text ? `\n${message.text}` : ""}${
      preview ? `\n文件文本内容（节选，最多 6000 字）：\n${preview}` : "\n（这个文件无法在聊天里直接读取正文，只能看到文件名和大小。）"
    }`;
  }
  let text = message.text || "";
  if (message.stickerId) {
    const custom = getSticker(message.stickerId, state.customStickers);
    text += `\n[我发了一个「${custom?.name || "表情"}」表情]`;
  }
  return text;
}

function quoteContextForPrompt(message) {
  const quote = message?.quote;
  if (!quote?.text) return "";
  const who = quote.role === "assistant" ? "我的消息" : "对方自己的消息";
  return `[对方引用了${who}：「${oneLine(quote.text, 90)}」]\n`;
}

function contentForUserMessage(message, state, current) {
  const prefix = quoteContextForPrompt(message);
  const text = `${prefix}${messageTextForApi(message, state, { current })}`;
  if (message.kind === "image" && current && message.image?.dataUrl) {
    const note = text?.trim() ? text : "看看这个。";
    return [
      { type: "text", text: `${note}\n[我发来一张图片。请直接看懂画面并自然回应，不要像图片描述工具一样报流水账。]` },
      { type: "image_url", image_url: { url: message.image.dataUrl } },
    ];
  }
  return text;
}

function historyForApi(state, currentMessageId) {
  const history = (state.messages || []).filter(
    (m) =>
      m.id !== currentMessageId &&
      !m.isError &&
      m.delivery !== "refused" &&
      (m.role === "user" || m.role === "assistant") &&
      m.kind !== "error",
  );
  return history.slice(-28);
}

export function buildChatMessages(state, currentMessage, { proactive = false, afterBlock = false, note = "" } = {}) {
  const quoteCatalog = buildQuoteCatalog(state, currentMessage?.id);
  const system = buildSystemPrompt(state, {
    mode: afterBlock ? "afterBlock" : proactive ? "proactive" : "chat",
    quoteCatalog,
  });
  const messages = [{ role: "system", content: system }];
  const history = historyForApi(state, currentMessage?.id);
  /* DeepSeek 带 tools 时要求历史轮次的 reasoning_content 一起回传；
     只在「助理页 + 联网开着」时补，避免给别的服务商塞无用字段。 */
  const replayReasoning = providerId(state.settings) === "deepseek"
    && state.settings?.mode === "assistant"
    && Boolean(state.settings?.assistant?.web);
  for (const message of history) {
    if (message.role === "assistant") {
      // Replaying our own "[I sent a sticker]" bookkeeping teaches some models
      // to type that literal sentence. The sticker itself adds little context.
      if (message.kind === "sticker") continue;
      const text = messageTextForApi(message, state);
      if (!text?.trim()) continue;
      const entry = { role: "assistant", content: text };
      if (replayReasoning && message.reasoning) {
        entry.reasoning_content = String(message.reasoning).slice(-4000);
      }
      messages.push(entry);
      continue;
    }
    const content = contentForUserMessage(message, state, false);
    if (typeof content === "string" && !content.trim()) continue;
    messages.push({ role: "user", content });
  }
  if (currentMessage) {
    const content = contentForUserMessage(currentMessage, state, true);
    messages.push({ role: "user", content });
  }
  // A one-off nudge used by "重来这一条" / "重画一张"; never stored in history.
  if (note) messages.push({ role: "user", content: note });
  if (afterBlock) {
    messages.push({
      role: "user",
      content: "[系统旁白：暂停时间结束了。请以角色身份主动发来一条自然的消息，不要提到这条说明。]",
    });
  } else if (proactive) {
    messages.push({
      role: "user",
      content: "[系统旁白：现在聊天框很安静。请以角色身份主动发来一条自然的消息，不要提到这条说明。]",
    });
  }
  return messages;
}

export function buildReportMessages(state) {
  const s = state.settings;
  const recent = (state.messages || [])
    .filter((m) => (m.role === "user" || m.role === "assistant") && m.kind !== "error" && m.delivery !== "refused")
    .slice(-10)
    .map((m) => {
      if (m.kind === "sticker") return `${m.role === "user" ? "对方" : "我"}：[表情]`;
      if (m.kind === "image") return `${m.role === "user" ? "对方" : "我"}：[图片]`;
      if (m.kind === "file") return `${m.role === "user" ? "对方" : "我"}：[文件]`;
      return `${m.role === "user" ? "对方" : "我"}：${(m.text || "").slice(0, 180)}`;
    })
    .join("\n");
  const system = `${personaBlock(state)}

你正在以角色身份写一张「日常报备」卡片，给对方看。不是工作总结，不是客服周报，而是一张安静、私人的虚拟日常卡片。它会以逐段动画直接显示在聊天上方。

【写作要求】
- 用第一人称，像角色本人在分享今天的一个片段。
- 具体、生活化、克制。写此刻在做什么、心情、吃喝、天气、一个小念头，以及想起对方的一瞬间。
- 不要编造过于戏剧化的事件；不要提 AI、模型、生成、HTML、提示词、动画。
- ${languageInstruction(s)}
- 全文 120–220 字（中文）或 90–150 words（英文）。
- 不要用括号动作描写。
- 每段只写一个画面或一个念头，句子短一点，方便逐段出现。

【输出格式】
只输出一个合法 JSON 对象，不要 Markdown 代码块，不要任何前后说明：
{
  "title": "6–14 字的短标题",
  "summary": "一句放在聊天列表里的摘要，20–40 字",
  "blocks": [
    { "text": "下午煎了两个蛋，蛋黄还是流心的。", "scene": "egg" },
    { "text": "吃完顺手把窗推开，风有点凉。", "scene": "rain" }
  ]
}

【blocks 规则】
- 3–5 段，每段 1–2 句，全文 120–220 字（中文）或 90–150 words（英文）。
- text 只能是纯文字：不要 HTML、不要括号动作描写、不要引号包裹。
- scene 决定这一段配哪幅本机画的小插画，只能从下面的 id 里选一个：
  ${Object.entries(SCENE_LABELS).map(([id, def]) => `${id}（${def.label}）`).join("、")}、none（不需要画面）
- 画面必须贴合这一段真正写到的东西：写了吃鸡蛋就选 egg，写了下雨就选 rain，写到猫就选 cat。
- 不要为了配图硬编内容；没有合适的画面就用 none。
- 同一个 scene 最多用两次，第一段尽量有画面。

【最近的聊天，仅供语气参考】
${recent || "（还没有聊天）"}

今天是 ${new Date().toLocaleString("zh-CN", { hour12: false })}。`;
  return [
    { role: "system", content: system },
    { role: "user", content: "写今天的日常报备。只输出 JSON。" },
  ];
}

function looseStickerKey(value) {
  return String(value ?? "")
    .normalize("NFKC")
    .toLowerCase()
    .replace(/^[\s"'`「」『』【】]+|[\s"'`「」『』【】]+$/g, "")
    .replace(/^(?:sticker|sticker_id|表情包?|表情|id)\s*[:：]\s*/i, "")
    .replace(/[（(][^）)]*[）)]\s*$/g, "")
    .replace(/[，。！？、,.!?;；:：'"“”‘’「」『』【】\[\]{}]/g, "")
    .replace(/\s+/g, "")
    .trim();
}

function stickerIndex(state) {
  const entries = [...BUILTIN_STICKERS, ...(state.customStickers || [])]
    .filter((sticker) => sticker?.id)
    .map((sticker) => ({
      sticker,
      id: sticker.id,
      keys: [sticker.id, sticker.name, sticker.caption, ...(sticker.aliases || [])]
        .filter(Boolean)
        .map((key) => looseStickerKey(key))
        .filter(Boolean),
    }));
  const lookup = new Map();
  for (const entry of entries) {
    for (const key of entry.keys) lookup.set(key, entry.id);
  }
  return { entries, lookup };
}

function resolveSticker(value, index) {
  const raw = String(value || "").trim().replace(/^["'「」]+|["'「」]+$/g, "");
  if (!raw) return null;
  const parts = raw.split(/[,，、/|;；]+/).map((part) => part.trim()).filter(Boolean);
  for (const part of parts) {
    const lower = part.toLowerCase();
    const loose = looseStickerKey(part);
    const direct = index.lookup.get(loose) || index.lookup.get(lower);
    if (direct) return direct;
    const idMatch = lower.match(/(?:bi|cat|ai|custom|pack)_[a-z0-9_-]+/i);
    if (idMatch) {
      const found = index.lookup.get(looseStickerKey(idMatch[0]));
      if (found) return found;
    }
    // Last resort for names with decorative suffixes such as “开心 (猫猫头)”.
    if (loose.length >= 2) {
      const byName = index.entries.find((entry) =>
        entry.keys.some((key) => key === loose || key.startsWith(loose) || loose.startsWith(key)),
      );
      if (byName) return byName.id;
    }
  }
  return null;
}

const STICKER_PATTERNS = [
  { re: /\[\[\s*(?:sticker|表情包?|sticker_id)\s*[:：]\s*([^\[\]\n]{1,60})\s*\]\]/gi, explicit: true },
  { re: /\[\s*(?:sticker|表情包?|sticker_id)\s*[:：]\s*([^\[\]\n]{1,60})\s*\]/gi, explicit: true },
  { re: /【\s*(?:sticker|表情包?|sticker_id)\s*[:：]\s*([^】\n]{1,60})\s*】/gi, explicit: true },
  { re: /\[\[\s*((?:bi|cat)_[a-z0-9_-]+)\s*\]\]/gi, explicit: true },
  { re: /\[\[\s*([^\[\]\n]{1,80})\s*\]\]/g, explicit: false },
  { re: /[（(]\s*(?:sticker|表情包?)\s*[:：]\s*([^）)\n]{1,60})\s*[）)]/gi, explicit: true },
  { re: /\[?\s*我(?:给你)?发了一个?\s*[「“"]([^」”"\n]{1,20})[」”"]\s*表情\s*\]?/gi, explicit: true },
];

export function extractStickers(text, state) {
  const index = stickerIndex(state);
  let cleaned = String(text || "");
  const stickers = [];
  for (const { re, explicit } of STICKER_PATTERNS) {
    cleaned = cleaned.replace(re, (match, value) => {
      const id = resolveSticker(value, index);
      if (!id) {
        const stickerLike = explicit || /^(?:bi|cat|ai|custom|pack)_/i.test(String(value).trim());
        return stickerLike ? " " : match;
      }
      if (!stickers.includes(id)) stickers.push(id);
      return " ";
    });
  }
  // Single-bracket forms such as [ai_pack_...], but never the inner half of
  // a double-bracket directive.
  cleaned = cleaned.replace(
    /(^|[^[])\[\s*((?:bi|cat|ai|custom|pack)_[a-z0-9_-]+)\s*\](?!\])/gi,
    (match, prefix, value) => {
      const id = resolveSticker(value, index);
      if (!id) return prefix;
      if (!stickers.includes(id)) stickers.push(id);
      return `${prefix} `;
    },
  );
  // A model may emit a bare ID at the end after being told not to. Only accept
  // known IDs and only when they stand alone, so normal words are never eaten.
  cleaned = cleaned.replace(/(?:^|\n)\s*((?:bi|cat|ai|custom)_[a-z0-9_-]+)\s*(?=\n|$)/gi, (match, id) => {
    const found = index.lookup.get(looseStickerKey(id));
    if (!found) return match;
    if (!stickers.includes(found)) stickers.push(found);
    return " ";
  });
  cleaned = cleaned.replace(/\[\[\s*(?:break|分段)\s*\]\]/gi, "\n\n");
  cleaned = cleaned.replace(/^\s*---+\s*$/gm, "\n\n");
  cleaned = cleaned.replace(/[ \t]{2,}/g, " ").replace(/\n{3,}/g, "\n\n");
  return { text: cleaned, stickers: stickers.slice(0, 2) };
}

export function stripActionDescriptions(text) {
  let out = String(text || "");
  // Whole-line stage directions: *smiles* or （轻轻叹气）
  out = out.replace(/^[ \t]*[*＊][^*\n]{1,120}[*＊][ \t]*$/gm, "");
  out = out.replace(/^[ \t]*[（(][^）)\n]{1,120}[）)][ \t]*$/gm, (line) => {
    const inner = line.replace(/^[ \t]*[（(*＊]+|[）)*＊]+[ \t]*$/g, "").trim();
    return ACTION_MARKERS.test(inner) ? "" : line;
  });
  // Inline full-width parentheses: the common Chinese roleplay pattern.
  out = out.replace(/（([^（）\n]{1,120})）/g, (match, inner) => (ACTION_MARKERS.test(inner) ? "" : match));
  // Inline ASCII parentheses, but keep emoticons and ordinary asides.
  out = out.replace(/\(([^()\n]{1,90})\)/g, (match, inner) => {
    if (/^[^\p{L}\p{N}]+$/u.test(inner)) return match;
    return ACTION_MARKERS.test(inner) ? "" : match;
  });
  // Asterisk stage directions inline.
  out = out.replace(/\*([^*\n]{1,90})\*/g, (match, inner) => (ACTION_MARKERS.test(inner) ? "" : match));
  out = out.replace(/[ \t]+([，。！？；：,.!?;:])/g, "$1");
  out = out.replace(/\n{3,}/g, "\n\n");
  out = out.replace(/[ \t]{2,}/g, " ");
  return out.trim();
}

function splitAtSentences(text, maxParts = 4) {
  const sentences = text
    .split(/(?<=[。！？!?…])\s*/u)
    .map((part) => part.trim())
    .filter(Boolean);
  if (sentences.length <= 1) return [text];
  const parts = [];
  let current = "";
  for (const sentence of sentences) {
    if (current && current.length + sentence.length > 55) {
      parts.push(current);
      current = sentence;
    } else {
      current += sentence;
    }
  }
  if (current) parts.push(current);
  // Merge a tiny tail back into the previous message.
  if (parts.length > 1 && parts.at(-1).length <= 6) {
    parts[parts.length - 2] += parts.pop();
  }
  return parts.slice(0, maxParts);
}

export function splitSegments(text, enabled) {
  const clean = String(text || "").trim();
  if (!clean) return [];
  if (!enabled) return [clean];
  let parts = clean
    .split(/\n{2,}/)
    .map((s) => s.trim())
    .filter(Boolean);
  if (parts.length === 1) {
    const lines = clean.split(/\n/).map((s) => s.trim()).filter(Boolean);
    if (lines.length > 1 && lines.every((line) => line.length < 160)) parts = lines;
  }
  if (parts.length === 1 && clean.length > 100) parts = splitAtSentences(clean, 3);
  if (parts.length > 4) {
    parts = [...parts.slice(0, 3), parts.slice(3).join("\n")];
  }
  return parts.filter(Boolean).slice(0, 4);
}

const MOOD_RULES = [
  ["night", /晚安|睡了|好梦|night/i],
  ["sleepy", /困|累|睡觉|sleepy|tired/i],
  ["love", /喜欢你|爱你|想你|心动|贴贴|抱抱|亲亲|love|miss you/i],
  ["laugh", /哈哈|笑死|太好笑|好笑|lol|haha/i],
  ["sad", /难过|委屈|想哭|伤心|对不起|sad|sorry/i],
  ["angry", /生气|讨厌|哼|吃醋|angry/i],
  ["eat", /吃饭|好吃|饿|干饭|food|hungry/i],
  ["party", /恭喜|庆祝|生日|太棒|party|congrat/i],
  ["work", /在忙|加班|工作|忙死|work|busy/i],
  ["ok", /好的|收到|明白|可以|okay|sure/i],
  ["question", /什么|真的吗|怎么会|why|really/i],
  ["bored", /无聊|没意思|好闲|bored/i],
  ["shock", /吓|惊|不会吧|shock|omg/i],
  ["cheer", /加油|冲冲|你可以的|cheer/i],
  ["happy", /开心|高兴|好耶|太棒|happy|yay/i],
  ["shy", /害羞|不好意思|脸红|shy/i],
  ["hello", /你好|在吗|早安|早上好|嗨|hello|hi/i],
];

export function moodFromText(value) {
  const text = String(value || "");
  for (const [mood, pattern] of MOOD_RULES) {
    if (pattern.test(text)) return mood;
  }
  return null;
}

export function chooseAutoSticker(text, state) {
  const raw = String(text || "");
  if (!raw) return null;
  if (isEmojiOnly(raw)) return null;
  const mood = moodFromText(raw);
  if (!mood) return null;
  const chosen = availableStickers(state).find((sticker) => (sticker.mood || moodFromText(sticker.name)) === mood);
  if (!chosen) return null;
  // Deterministic, gentle fallback: not every single message gets a sticker.
  const shouldAdd = mood !== "love" ? simpleHash(raw) % 100 < 62 : simpleHash(raw) % 100 < 48;
  return shouldAdd ? chosen.id : null;
}

function resolveQuote(value, quoteCatalog = []) {
  const key = String(value || "").trim().toLowerCase();
  if (!key) return null;
  const match = quoteCatalog.find(
    (item) => item.ref?.toLowerCase() === key || item.messageId?.toLowerCase() === key,
  );
  if (match) return { ...match };
  // A model occasionally drops the U prefix. Only infer it when there is a
  // single candidate; otherwise a wrong quote is worse than no quote.
  if (/^\d+$/.test(key) && quoteCatalog.length === 1) return { ...quoteCatalog[0] };
  return null;
}

export function parseReply(raw, state, options = {}) {
  const chatMode = chatModeOf(state.settings);
  /* 助理模式不发贴纸、不自动配表情；角色扮演不删动作描写（那是演的一部分）。 */
  const autoSticker =
    options.autoSticker ?? (state.settings.optimize?.autoSticker && chatMode !== "assistant");
  const stripActions =
    options.stripActions ?? (state.settings.optimize?.noActions && chatMode === "companion");
  const quoteCatalog = Array.isArray(options.quoteCatalog) ? options.quoteCatalog : [];
  let text = String(raw || "").trim();
  // Pull drawings out first: the fence stripping below would eat the closing
  // ``` of a drawing block and leave it unparseable. This runs whether or not
  // the drawing switch is on: a model that draws anyway must not paint its
  // source code into the chat (that is exactly what happened on the phone).
  //
  // 助理页是反例：它的卖点就是代码块 + 复制按钮，```html / ```svg 正是要看的
  // 代码。在那里不抽画，围栏原样留给 renderAssistantMarkup()。
  const allowDrawings = options.drawings ?? chatMode !== "assistant";
  const drawn = allowDrawings
    ? extractDrawings(text, { limit: DRAWING_LIMITS.maxPerReply })
    : { text, drawings: [], broken: 0 };
  text = drawn.text;
  const drawings = drawn.drawings;
  // a fence was there but no picture could be built (cut off / malformed)
  const drawingBroken = drawn.broken > 0 && !drawn.drawings.length;
  /* 助理页的整条回复可能就是一段代码：围栏必须留着给代码块渲染。
     其它模式继续去掉包住整条回复的边缘围栏（防止 ```json 之类漏上屏）。 */
  if (allowDrawings) text = text.replace(/^\s*```[a-z]*\s*/i, "").replace(/\s*```\s*$/i, "");

  let blockRequested = false;
  text = text.replace(/\[\[?\s*(?:block|屏蔽|拉黑|暂停)\s*(?:[:：]\s*\d{1,4})?\s*\]\]?/gi, () => {
    blockRequested = true;
    return " ";
  });

  let quote = null;
  text = text.replace(
    /\[\[?\s*(?:quote|引用|reply)\s*[:：]\s*([^\[\]\n]{1,64})\s*\]\]?/gi,
    (match, value) => {
      if (!quote) quote = resolveQuote(value, quoteCatalog);
      return " ";
    },
  );

  text = text.replace(/!\[[^\]]*\]\([^)]*\)/g, "");
  const extracted = extractStickers(text, state);
  text = extracted.text;
  const stickerIds = chatMode === "assistant" ? [] : [...extracted.stickers];
  if (stripActions) text = stripActionDescriptions(text);
  text = text.replace(/\[\[\s*report\s*\]\]/gi, "").replace(/[ \t]+\n/g, "\n").trim();

  if (autoSticker && stickerIds.length === 0) {
    const auto = chooseAutoSticker(text, state);
    if (auto) stickerIds.push(auto);
  }

  /* 分段发送是陪伴的「像连续发消息」；助理的一条回答里有代码块和空行，
     分段会把代码拆散，所以助理永远只发一条。 */
  const parts = splitSegments(text, chatMode !== "assistant" && Boolean(state.settings.optimize?.segments));
  return {
    parts,
    stickerIds,
    drawings,
    drawingBroken,
    text,
    quote,
    blockRequested,
    emojiOnly: isEmojiOnly(text),
    hasEmoji: hasEmoji(text),
  };
}

/** Drop ```json fences anywhere in the reply, not just at its edges. */
function stripFences(raw) {
  return String(raw || "")
    .replace(/^[ \t]*```[a-z]*[ \t]*$/gim, "")
    .trim();
}

/**
 * A reply that hit max_tokens stops mid-JSON. Close the open string and the
 * open brackets so the half-finished object can still be read. Returns "" when
 * the text cannot be repaired.
 */
export function repairJson(raw) {
  const text = String(raw || "");
  const start = text.indexOf("{");
  if (start < 0) return "";
  let out = "";
  const stack = [];
  let inString = false;
  let escaped = false;
  for (const ch of text.slice(start)) {
    if (inString) {
      out += ch;
      if (escaped) escaped = false;
      else if (ch === "\\") escaped = true;
      else if (ch === '"') inString = false;
      continue;
    }
    if (ch === '"') {
      inString = true;
      out += ch;
      continue;
    }
    if (ch === "{" || ch === "[") {
      stack.push(ch === "{" ? "}" : "]");
      out += ch;
      continue;
    }
    if (ch === "}" || ch === "]") {
      if (!stack.length || stack[stack.length - 1] !== ch) return "";
      stack.pop();
      out += ch;
      continue;
    }
    out += ch;
  }
  let fixed = out;
  if (inString) fixed += '"';
  // a key or a comma left without a value: `"summary":` / `"blocks": [`
  fixed = fixed.replace(/,\s*"[^"]*"\s*:?\s*$/, "");
  fixed = fixed.replace(/,\s*$/, "");
  while (stack.length) fixed += stack.pop();
  try {
    JSON.parse(fixed);
    return fixed;
  } catch {
    return "";
  }
}

export function parseJsonReply(raw) {
  const text = stripFences(raw);
  const start = text.indexOf("{");
  if (start < 0) throw new Error("no json object");
  const body = text.slice(start);
  try {
    const parsed = JSON.parse(body);
    if (!parsed || typeof parsed !== "object") throw new Error("not an object");
    return parsed;
  } catch {
    /* fall through: trailing prose, or a truncated object */
  }
  const end = body.lastIndexOf("}");
  if (end > 0) {
    try {
      const parsed = JSON.parse(body.slice(0, end + 1));
      if (parsed && typeof parsed === "object") return parsed;
    } catch {
      /* keep repairing */
    }
  }
  const repaired = repairJson(body);
  if (repaired) {
    const parsed = JSON.parse(repaired);
    if (parsed && typeof parsed === "object") return parsed;
  }
  throw new Error("invalid JSON");
}

// Kept exported for unit tests and future prompt variants.
export { ACTION_WORDS, escapeRegExp };
