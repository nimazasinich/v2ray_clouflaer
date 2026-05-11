// ============================================================================
// DreamMaker Telegram Sales Bot — Cloudflare Worker
// Bot: @Freqbasterd_bot
// Handles: /start /plans /buy — admin approval — subscription delivery
// Storage: HEALTH_KV namespace (reused; keys prefixed "bot:")
// ============================================================================

const BOT_TOKEN  = typeof BOT_TOKEN_ENV !== "undefined" ? BOT_TOKEN_ENV : "";
const ADMIN_ID   = typeof ADMIN_CHAT_ID !== "undefined" ? ADMIN_CHAT_ID : "";
const PANEL_PASS = typeof PANEL_SECRET  !== "undefined" ? PANEL_SECRET  : "";

const API = `https://api.telegram.org/bot${BOT_TOKEN}`;

const PLANS = [
  { id: "starter",   label: "🔵 Starter",  gb: "1 GB",   days: 30,  price: "40,000",  uuid: "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e" },
  { id: "basic",     label: "🟢 Basic",    gb: "2 GB",   days: 30,  price: "70,000",  uuid: "92ebaa01-ec34-4601-a4dc-f6afdf822966" },
  { id: "standard",  label: "⚡ Standard", gb: "5 GB",   days: 30,  price: "130,000", uuid: "3d5e3adf-0912-4c78-9ca9-b87db334ce71" },
  { id: "plus",      label: "🚀 Plus",     gb: "10 GB",  days: 30,  price: "220,000", uuid: "e8eb3d74-8e8c-4903-b878-8feb656ebb0c" },
  { id: "pro",       label: "💫 Pro",      gb: "15 GB",  days: 30,  price: "300,000", uuid: "b3540a54-67dd-452a-b5d8-45d6407b8da5" },
  { id: "elite",     label: "🔥 Elite",    gb: "20 GB",  days: 30,  price: "380,000", uuid: "2680152c-0dc3-4fdb-b366-e936358b121f" },
  { id: "unlimited", label: "💎 Unlimited",gb: "∞",      days: 30,  price: "500,000", uuid: "89c0f294-3f94-4735-96cf-9c1aefdbcbb2" },
];

const SUB_BASE = "https://dreammaker-groupsoft.ir/sub?uuid=";

// ── Telegram helpers ────────────────────────────────────────────────────────
async function tg(method, params) {
  const r = await fetch(`${API}/${method}`, {
    method:  "POST",
    headers: { "Content-Type": "application/json" },
    body:    JSON.stringify(params),
  });
  return r.json();
}

async function reply(chatId, text, extra = {}) {
  return tg("sendMessage", { chat_id: chatId, text, parse_mode: "HTML", ...extra });
}

// ── KV helpers ──────────────────────────────────────────────────────────────
function orderKey(id)   { return `bot:order:${id}`; }
function userKey(uid)   { return `bot:user:${uid}`; }

async function saveOrder(kv, order) {
  await kv.put(orderKey(order.id), JSON.stringify(order), { expirationTtl: 86400 });
}
async function getOrder(kv, id)    { const v = await kv.get(orderKey(id)); return v ? JSON.parse(v) : null; }
async function delOrder(kv, id)    { await kv.delete(orderKey(id)); }

// ── Message handlers ────────────────────────────────────────────────────────
async function handleStart(chatId) {
  const text =
    `👋 <b>خوش آمدید به DreamMaker VPN</b>\n\n` +
    `سرعت بالا، پایداری کامل، سرور آلمان 🇩🇪\n\n` +
    `<b>دستورات:</b>\n` +
    `/plans — مشاهده پلن‌ها و قیمت‌ها\n` +
    `/buy — خرید اشتراک\n` +
    `/support — ارتباط با پشتیبانی\n\n` +
    `🔒 تمام ترافیک رمزنگاری‌شده · XHTTP · بدون لاگ`;
  await reply(chatId, text);
}

async function handlePlans(chatId) {
  let lines = ["<b>📋 پلن‌های DreamMaker</b>\n"];
  for (const p of PLANS) {
    lines.push(`${p.label}  —  ${p.gb}  —  ${p.days} روزه  —  <b>${p.price} تومان</b>`);
  }
  lines.push("\nبرای خرید: /buy");
  await reply(chatId, lines.join("\n"));
}

async function handleBuy(chatId, kv) {
  const buttons = PLANS.map(p => ([{
    text:          `${p.label} — ${p.gb} — ${p.price} تومن`,
    callback_data: `select_plan:${p.id}`,
  }]));
  await tg("sendMessage", {
    chat_id:      chatId,
    text:         "🛒 <b>انتخاب پلن:</b>",
    parse_mode:   "HTML",
    reply_markup: { inline_keyboard: buttons },
  });
}

async function handleSelectPlan(chatId, userId, username, planId, kv) {
  const plan = PLANS.find(p => p.id === planId);
  if (!plan) return;

  const orderId = `${userId}-${Date.now()}`;
  const order = { id: orderId, userId, username, planId: plan.id, planLabel: plan.label, price: plan.price, uuid: plan.uuid, status: "pending", ts: Date.now() };
  await saveOrder(kv, order);

  await reply(chatId,
    `✅ انتخاب: <b>${plan.label} — ${plan.gb} — ${plan.price} تومان</b>\n\n` +
    `💳 <b>روش پرداخت:</b>\n` +
    `کارت‌به‌کارت به شماره:\n<code>6037-XXXX-XXXX-XXXX</code>\n` +
    `به نام: حسین ...\n\n` +
    `پس از واریز، <b>رسید را برای پشتیبانی ارسال کنید</b> یا /support\n\n` +
    `کد سفارش: <code>${orderId}</code>`
  );

  const uname = username ? `@${username}` : `id:${userId}`;
  await tg("sendMessage", {
    chat_id:    ADMIN_ID,
    text:
      `🔔 <b>سفارش جدید</b>\n` +
      `کاربر: ${uname}\n` +
      `پلن: ${plan.label} — ${plan.gb}\n` +
      `مبلغ: ${plan.price} تومان\n` +
      `کد: <code>${orderId}</code>`,
    parse_mode: "HTML",
    reply_markup: {
      inline_keyboard: [[
        { text: "✅ تایید — ارسال کانفیگ", callback_data: `approve:${orderId}` },
        { text: "❌ رد",                    callback_data: `reject:${orderId}` },
      ]],
    },
  });
}

async function handleApprove(adminChatId, orderId, kv, msgId) {
  const order = await getOrder(kv, orderId);
  if (!order) { await tg("answerCallbackQuery", { callback_query_id: msgId, text: "سفارش یافت نشد" }); return; }
  if (order.status !== "pending") { await tg("answerCallbackQuery", { callback_query_id: msgId, text: "قبلاً پردازش شده" }); return; }

  order.status = "approved";
  await saveOrder(kv, order);

  const plan    = PLANS.find(p => p.id === order.planId);
  const subUrl  = `${SUB_BASE}${order.uuid}`;
  const configText =
    `🎉 <b>اشتراک فعال شد!</b>\n\n` +
    `پلن: ${plan ? plan.label : order.planLabel}\n\n` +
    `<b>لینک اشتراک (v2rayNG / Nekobox / Hiddify):</b>\n` +
    `<code>${subUrl}</code>\n\n` +
    `این لینک را در بخش <i>اضافه کردن اشتراک</i> کلاینت خود وارد کنید.\n\n` +
    `📱 <b>کانفیگ مستقیم (XHTTP — بهترین):</b>\n` +
    `<code>vless://${order.uuid}@dreammaker-groupsoft.ir:443?encryption=none&type=xhttp&path=%2F${pathForPlan(order.planId)}&security=tls&host=cdn.dreammaker-groupsoft.ir&sni=cdn.dreammaker-groupsoft.ir&fp=chrome&alpn=h2%2Chttp%2F1.1#${encodeURIComponent(plan ? plan.label : "DM")}</code>\n\n` +
    `پشتیبانی: /support`;

  await reply(order.userId, configText);
  await tg("answerCallbackQuery", { callback_query_id: msgId, text: "✅ کانفیگ ارسال شد" });
  await tg("editMessageReplyMarkup", { chat_id: adminChatId, message_id: undefined, reply_markup: { inline_keyboard: [] } });
  await reply(adminChatId, `✅ سفارش <code>${orderId}</code> تایید و کانفیگ ارسال شد.`);
  await delOrder(kv, orderId);
}

async function handleReject(adminChatId, orderId, kv, msgId) {
  const order = await getOrder(kv, orderId);
  if (!order) { await tg("answerCallbackQuery", { callback_query_id: msgId, text: "سفارش یافت نشد" }); return; }

  order.status = "rejected";
  await saveOrder(kv, order);
  await reply(order.userId, `❌ سفارش شما (کد: <code>${orderId}</code>) رد شد.\nبرای پشتیبانی /support`);
  await tg("answerCallbackQuery", { callback_query_id: msgId, text: "رد شد" });
  await reply(adminChatId, `❌ سفارش <code>${orderId}</code> رد شد.`);
  await delOrder(kv, orderId);
}

async function handleSupport(chatId, userId, username) {
  const uname = username ? `@${username}` : `id:${userId}`;
  await reply(chatId, `📞 پیام شما به پشتیبانی ارسال خواهد شد.\nمشکل خود را بنویسید و /support را در ابتدای پیام قرار دهید.`);
  await reply(ADMIN_ID, `📞 درخواست پشتیبانی از ${uname} (${userId})`);
}

function pathForPlan(planId) {
  const m = { starter:"api/v1/ping", basic:"cdn/init", standard:"app/sync", plus:"api/v2/feed", pro:"static/bundle.js", elite:"media/stream", unlimited:"v2/content/live" };
  return m[planId] ?? "api/v1/ping";
}

// ── Admin commands ───────────────────────────────────────────────────────────
async function handleAdminStats(kv) {
  // Count pending orders
  const list = await kv.list({ prefix: "bot:order:" });
  let pending = 0;
  for (const key of list.keys) {
    const v = await kv.get(key.name);
    if (v) { const o = JSON.parse(v); if (o.status === "pending") pending++; }
  }
  await reply(ADMIN_ID, `📊 <b>Stats</b>\nسفارش‌های در انتظار: ${pending}`);
}

// ── Main dispatch ────────────────────────────────────────────────────────────
async function handleUpdate(update, kv) {
  if (update.callback_query) {
    const cq   = update.callback_query;
    const from = cq.from;
    const data = cq.data ?? "";

    if (data.startsWith("select_plan:")) {
      const planId = data.slice("select_plan:".length);
      await handleSelectPlan(from.id, from.id, from.username, planId, kv);
      await tg("answerCallbackQuery", { callback_query_id: cq.id });
    } else if (data.startsWith("approve:")) {
      await handleApprove(from.id, data.slice("approve:".length), kv, cq.id);
    } else if (data.startsWith("reject:")) {
      await handleReject(from.id, data.slice("reject:".length), kv, cq.id);
    } else {
      await tg("answerCallbackQuery", { callback_query_id: cq.id });
    }
    return;
  }

  if (!update.message) return;
  const msg   = update.message;
  const chat  = msg.chat.id;
  const from  = msg.from;
  const text  = (msg.text ?? "").trim();

  if (text === "/start")        await handleStart(chat);
  else if (text === "/plans")   await handlePlans(chat);
  else if (text === "/buy")     await handleBuy(chat, kv);
  else if (text.startsWith("/support")) await handleSupport(chat, from.id, from.username);
  else if (text === "/stats" && String(from.id) === String(ADMIN_ID)) await handleAdminStats(kv);
  else if (text.startsWith("/")) { /* ignore unknown commands */ }
  else {
    // Forward text messages from known users to admin
    if (String(from.id) !== String(ADMIN_ID)) {
      const uname = from.username ? `@${from.username}` : `id:${from.id}`;
      await reply(ADMIN_ID, `💬 پیام از ${uname}:\n${text}`);
    }
  }
}

// ── Worker entry ─────────────────────────────────────────────────────────────
export default {
  async fetch(request, env) {
    const kv = env.HEALTH_KV;
    const token   = env.BOT_TOKEN_ENV   ?? BOT_TOKEN;
    const adminId = env.ADMIN_CHAT_ID   ?? ADMIN_ID;

    // Patch globals from env bindings
    globalThis.BOT_TOKEN_ENV = token;
    globalThis.ADMIN_CHAT_ID = adminId;

    if (request.method !== "POST") {
      return new Response(JSON.stringify({ ok: true, service: "dm-sales-bot" }), {
        headers: { "Content-Type": "application/json" }
      });
    }

    try {
      const update = await request.json();
      await handleUpdate(update, kv);
    } catch (e) {
      console.error("Bot error:", e);
    }

    return new Response("ok", { status: 200 });
  }
};
