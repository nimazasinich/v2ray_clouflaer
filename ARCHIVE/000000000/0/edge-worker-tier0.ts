/**
 * DreamMaker Tier 0 — Lean Edge Subscription Worker
 *
 * Design goals:
 * - Keep the hot path tiny
 * - No D1 calls in request path
 * - No external fetches
 * - Only memory cache + optional KV cache
 * - XHTTP primary, WebSocket fallback
 * - Paths must match nginx location blocks and Xray config
 */

const PRIMARY_DOMAIN = "dreammaker-groupsoft.ir";
const CDN_HOST = "cdn.dreammaker-groupsoft.ir";
const CACHE_TTL_MS = 60_000;

const TIER_REGISTRY = {
  starter:   { uuid: "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e", path: "/api/v1/ping",       label: "DM-Starter" },
  basic:     { uuid: "92ebaa01-ec34-4601-a4dc-f6afdf822966", path: "/cdn/init",           label: "DM-Basic" },
  standard:  { uuid: "3d5e3adf-0912-4c78-9ca9-b87db334ce71", path: "/app/sync",           label: "DM-Standard" },
  plus:      { uuid: "e8eb3d74-8e8c-4903-b878-8feb656ebb0c", path: "/api/v2/feed",        label: "DM-Plus" },
  pro:       { uuid: "b3540a54-67dd-452a-b5d8-45d6407b8da5", path: "/static/bundle.js",    label: "DM-Pro" },
  elite:     { uuid: "2680152c-0dc3-4fdb-b366-e936358b121f", path: "/media/stream",       label: "DM-Elite" },
  unlimited: { uuid: "89c0f294-3f94-4735-96cf-9c1aefdbcbb2", path: "/v2/content/live",     label: "DM-Unlimited" },
} as const;

type TierKey = keyof typeof TIER_REGISTRY;

interface Env {
  DM_KV?: KVNamespace;
}

const MEMORY_CACHE = new Map<string, { body: string; expires: number; contentType: string }>();

function b64(str: string): string {
  return btoa(unescape(encodeURIComponent(str)));
}

function buildVlessUri(uuid: string, path: string, label: string, transport: "xhttp" | "ws"): string {
  const params = new URLSearchParams({
    encryption: "none",
    type: transport,
    path,
    security: "tls",
    host: CDN_HOST,
    sni: CDN_HOST,
    fp: "chrome",
    alpn: "h2,http/1.1",
    x_padding_bytes: "100-1000",
  });

  return `vless://${uuid}@${PRIMARY_DOMAIN}:443?${params.toString()}#${label}${transport === "ws" ? "-WS" : ""}`;
}

function buildSubscription(format: "vless" | "json" | "clash"): { body: string; contentType: string } {
  const tiers = Object.values(TIER_REGISTRY);

  if (format === "json") {
    return {
      contentType: "application/json; charset=utf-8",
      body: JSON.stringify(
        {
          version: 1,
          generated_at: new Date().toISOString(),
          primary_domain: PRIMARY_DOMAIN,
          cdn_host: CDN_HOST,
          transport: { primary: "xhttp", fallback: "ws" },
          entries: tiers.map((tier) => ({
            name: tier.label,
            uuid: tier.uuid,
            server: PRIMARY_DOMAIN,
            port: 443,
            host: CDN_HOST,
            sni: CDN_HOST,
            xhttp_path: tier.path,
            ws_path: `${tier.path}-ws`,
          })),
        },
        null,
        2,
      ),
    };
  }

  if (format === "clash") {
    const proxies = tiers.flatMap((tier) => ([
      {
        name: tier.label,
        type: "vless",
        server: PRIMARY_DOMAIN,
        port: 443,
        uuid: tier.uuid,
        tls: true,
        network: "xhttp",
        "client-fingerprint": "chrome",
        servername: CDN_HOST,
        "xhttp-opts": { path: tier.path, host: CDN_HOST },
      },
      {
        name: `${tier.label}-WS`,
        type: "vless",
        server: PRIMARY_DOMAIN,
        port: 443,
        uuid: tier.uuid,
        tls: true,
        network: "ws",
        "client-fingerprint": "chrome",
        servername: CDN_HOST,
        "ws-opts": { path: `${tier.path}-ws`, headers: { Host: CDN_HOST } },
      },
    ]));

    return {
      contentType: "text/plain; charset=utf-8",
      body: `proxies:\n${proxies.map((p) => `  - ${JSON.stringify(p)}`).join("\n")}`,
    };
  }

  const links: string[] = [];
  for (const tier of tiers) {
    links.push(buildVlessUri(tier.uuid, tier.path, tier.label, "xhttp"));
    links.push(buildVlessUri(tier.uuid, `${tier.path}-ws`, tier.label, "ws"));
  }

  return {
    contentType: "text/plain; charset=utf-8",
    body: b64(links.join("\n")),
  };
}

function cacheKey(format: string) {
  return `sub:${format}`;
}

function response(body: string, contentType: string, headers: Record<string, string> = {}, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=60",
      "X-Content-Type-Options": "nosniff",
      ...headers,
    },
  });
}

async function handleSub(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
  const formatRaw = new URL(request.url).searchParams.get("format")?.toLowerCase() ?? "vless";
  const format = (["vless", "json", "clash"].includes(formatRaw) ? formatRaw : "vless") as "vless" | "json" | "clash";
  const key = cacheKey(format);
  const now = Date.now();

  const mem = MEMORY_CACHE.get(key);
  if (mem && mem.expires > now) {
    return response(mem.body, mem.contentType, { "X-Cache": "MEM" });
  }

  if (env.DM_KV) {
    try {
      const kv = await env.DM_KV.get(key, "json") as { body: string; contentType: string; expires: number } | null;
      if (kv && typeof kv.body === "string" && typeof kv.contentType === "string" && (kv.expires ?? 0) > now) {
        MEMORY_CACHE.set(key, { body: kv.body, contentType: kv.contentType, expires: kv.expires });
        return response(kv.body, kv.contentType, { "X-Cache": "KV" });
      }
    } catch {
      // ignore and generate fresh
    }
  }

  const built = buildSubscription(format);
  MEMORY_CACHE.set(key, { ...built, expires: now + CACHE_TTL_MS });

  if (env.DM_KV) {
    ctx.waitUntil(
      env.DM_KV.put(key, JSON.stringify({ ...built, expires: now + CACHE_TTL_MS }), { expirationTtl: 300 })
        .catch(() => void 0),
    );
  }

  return response(built.body, built.contentType, { "X-Cache": "GEN" });
}

export default {
  async fetch(request: Request, env: Env, ctx: ExecutionContext): Promise<Response> {
    const { pathname } = new URL(request.url);

    if (pathname === "/" || pathname === "/health" || pathname === "/ping") {
      return response(
        JSON.stringify(
          {
            ok: true,
            service: "DreamMaker Tier 0",
            mode: "lean",
            primary_domain: PRIMARY_DOMAIN,
            cdn_host: CDN_HOST,
            tier_count: Object.keys(TIER_REGISTRY).length,
            endpoints: {
              health: "/health",
              subscription: "/sub?format=vless",
              json: "/sub?format=json",
              clash: "/sub?format=clash",
            },
          },
          null,
          2,
        ),
        "application/json; charset=utf-8",
        { "Cache-Control": "public, max-age=30" },
      );
    }

    if (pathname === "/sub") {
      return handleSub(request, env, ctx);
    }

    return response(JSON.stringify({ ok: false, error: "Not found" }), "application/json; charset=utf-8", {}, 404);
  },
};
