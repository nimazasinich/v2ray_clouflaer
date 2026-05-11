import { DreamMakerConfig, type TierKey } from "./config";

type CacheEntry = { body: string; contentType: string; expires: number };

interface Env {
  DM_KV?: KVNamespace;
}

const MEMORY_CACHE = new Map<string, CacheEntry>();

function encodeBase64Utf8(input: string): string {
  return btoa(unescape(encodeURIComponent(input)));
}

function buildVlessUri(uuid: string, path: string, label: string, transport: "xhttp" | "ws"): string {
  const params = new URLSearchParams({
    encryption: "none",
    type: transport,
    path,
    security: "tls",
    host: DreamMakerConfig.cdnHost,
    sni: DreamMakerConfig.cdnHost,
    fp: "chrome",
    alpn: "h2,http/1.1",
    x_padding_bytes: "100-1000",
  });

  return `vless://${uuid}@${DreamMakerConfig.primaryDomain}:443?${params.toString()}#${label}${transport === "ws" ? "-WS" : ""}`;
}

function buildSubscription(format: "vless" | "json" | "clash"): { body: string; contentType: string } {
  const tiers = Object.values(DreamMakerConfig.tiers);

  if (format === "json") {
    return {
      contentType: "application/json; charset=utf-8",
      body: JSON.stringify(
        {
          version: 1,
          generated_at: new Date().toISOString(),
          primary_domain: DreamMakerConfig.primaryDomain,
          cdn_host: DreamMakerConfig.cdnHost,
          transport: DreamMakerConfig.transport,
          cache_ttl_ms: DreamMakerConfig.cacheTtlMs,
          entries: tiers.map((tier) => ({
            name: tier.label,
            uuid: tier.uuid,
            server: DreamMakerConfig.primaryDomain,
            port: 443,
            host: DreamMakerConfig.cdnHost,
            sni: DreamMakerConfig.cdnHost,
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
        server: DreamMakerConfig.primaryDomain,
        port: 443,
        uuid: tier.uuid,
        tls: true,
        network: "xhttp",
        "client-fingerprint": "chrome",
        servername: DreamMakerConfig.cdnHost,
        "xhttp-opts": { path: tier.path, host: DreamMakerConfig.cdnHost },
      },
      {
        name: `${tier.label}-WS`,
        type: "vless",
        server: DreamMakerConfig.primaryDomain,
        port: 443,
        uuid: tier.uuid,
        tls: true,
        network: "ws",
        "client-fingerprint": "chrome",
        servername: DreamMakerConfig.cdnHost,
        "ws-opts": { path: `${tier.path}-ws`, headers: { Host: DreamMakerConfig.cdnHost } },
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
    body: encodeBase64Utf8(links.join("\n")),
  };
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
  const key = `sub:${format}`;
  const now = Date.now();

  const mem = MEMORY_CACHE.get(key);
  if (mem && mem.expires > now) {
    return response(mem.body, mem.contentType, { "X-Cache": "MEM" });
  }

  if (env.DM_KV) {
    try {
      const kv = await env.DM_KV.get(key, "json") as CacheEntry | null;
      if (kv && typeof kv.body === "string" && typeof kv.contentType === "string" && kv.expires > now) {
        MEMORY_CACHE.set(key, kv);
        return response(kv.body, kv.contentType, { "X-Cache": "KV" });
      }
    } catch {
      // No-op: keep the hot path tiny.
    }
  }

  const built = buildSubscription(format);
  const entry = { ...built, expires: now + DreamMakerConfig.cacheTtlMs };
  MEMORY_CACHE.set(key, entry);

  if (env.DM_KV) {
    ctx.waitUntil(
      env.DM_KV.put(key, JSON.stringify(entry), { expirationTtl: 300 }).catch(() => void 0),
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
            primary_domain: DreamMakerConfig.primaryDomain,
            cdn_host: DreamMakerConfig.cdnHost,
            tier_count: Object.keys(DreamMakerConfig.tiers).length,
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
