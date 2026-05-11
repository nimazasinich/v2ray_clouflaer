var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// config.ts
var DreamMakerConfig = {
  primaryDomain: "dreammaker-groupsoft.ir",
  cdnHost: "cdn.dreammaker-groupsoft.ir",
  transport: {
    primary: "xhttp",
    fallback: "websocket"
  },
  cacheTtlMs: 6e4,
  tiers: {
    starter: { uuid: "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e", path: "/api/v1/ping", label: "DM-Starter" },
    basic: { uuid: "92ebaa01-ec34-4601-a4dc-f6afdf822966", path: "/cdn/init", label: "DM-Basic" },
    standard: { uuid: "3d5e3adf-0912-4c78-9ca9-b87db334ce71", path: "/app/sync", label: "DM-Standard" },
    plus: { uuid: "e8eb3d74-8e8c-4903-b878-8feb656ebb0c", path: "/api/v2/feed", label: "DM-Plus" },
    pro: { uuid: "b3540a54-67dd-452a-b5d8-45d6407b8da5", path: "/static/bundle.js", wsPath: "/static/bundle-ws", label: "DM-Pro" },
    elite: { uuid: "2680152c-0dc3-4fdb-b366-e936358b121f", path: "/media/stream", label: "DM-Elite" },
    unlimited: { uuid: "89c0f294-3f94-4735-96cf-9c1aefdbcbb2", path: "/v2/content/live", label: "DM-Unlimited" }
  }
};

// edge-worker-tier0.ts
var MEMORY_CACHE = /* @__PURE__ */ new Map();
function encodeBase64Utf8(input) {
  return btoa(unescape(encodeURIComponent(input)));
}
__name(encodeBase64Utf8, "encodeBase64Utf8");
function buildVlessUri(uuid, path, label, transport) {
  const params = new URLSearchParams({
    encryption: "none",
    type: transport,
    path,
    security: "tls",
    host: DreamMakerConfig.cdnHost,
    sni: DreamMakerConfig.cdnHost,
    fp: "chrome",
    alpn: "h2,http/1.1",
    x_padding_bytes: "100-1000"
  });
  return `vless://${uuid}@${DreamMakerConfig.primaryDomain}:443?${params.toString()}#${label}${transport === "ws" ? "-WS" : ""}`;
}
__name(buildVlessUri, "buildVlessUri");
function buildSubscription(format) {
  const tiers = Object.values(DreamMakerConfig.tiers);
  if (format === "json") {
    return {
      contentType: "application/json; charset=utf-8",
      body: JSON.stringify(
        {
          version: 1,
          generated_at: (/* @__PURE__ */ new Date()).toISOString(),
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
            ws_path: tier.wsPath ?? `${tier.path}-ws`
          }))
        },
        null,
        2
      )
    };
  }
  if (format === "clash") {
    const proxies = tiers.flatMap((tier) => [
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
        "xhttp-opts": { path: tier.path, host: DreamMakerConfig.cdnHost }
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
        "ws-opts": { path: tier.wsPath ?? `${tier.path}-ws`, headers: { Host: DreamMakerConfig.cdnHost } }
      }
    ]);
    return {
      contentType: "text/plain; charset=utf-8",
      body: `proxies:
${proxies.map((p) => `  - ${JSON.stringify(p)}`).join("\n")}`
    };
  }
  const links = [];
  for (const tier of tiers) {
    links.push(buildVlessUri(tier.uuid, tier.path, tier.label, "xhttp"));
    links.push(buildVlessUri(tier.uuid, tier.wsPath ?? `${tier.path}-ws`, tier.label, "ws"));
  }
  return {
    contentType: "text/plain; charset=utf-8",
    body: encodeBase64Utf8(links.join("\n"))
  };
}
__name(buildSubscription, "buildSubscription");
function response(body, contentType, headers = {}, status = 200) {
  return new Response(body, {
    status,
    headers: {
      "Content-Type": contentType,
      "Cache-Control": "public, max-age=60",
      "X-Content-Type-Options": "nosniff",
      ...headers
    }
  });
}
__name(response, "response");
async function handleSub(request, env, ctx) {
  const formatRaw = new URL(request.url).searchParams.get("format")?.toLowerCase() ?? "vless";
  const format = ["vless", "json", "clash"].includes(formatRaw) ? formatRaw : "vless";
  const key = `sub:${format}`;
  const now = Date.now();
  const mem = MEMORY_CACHE.get(key);
  if (mem && mem.expires > now) {
    return response(mem.body, mem.contentType, { "X-Cache": "MEM" });
  }
  if (env.DM_KV) {
    try {
      const kv = await env.DM_KV.get(key, "json");
      if (kv && typeof kv.body === "string" && typeof kv.contentType === "string" && kv.expires > now) {
        MEMORY_CACHE.set(key, kv);
        return response(kv.body, kv.contentType, { "X-Cache": "KV" });
      }
    } catch {
    }
  }
  const built = buildSubscription(format);
  const entry = { ...built, expires: now + DreamMakerConfig.cacheTtlMs };
  MEMORY_CACHE.set(key, entry);
  if (env.DM_KV) {
    ctx.waitUntil(
      env.DM_KV.put(key, JSON.stringify(entry), { expirationTtl: 300 }).catch(() => void 0)
    );
  }
  return response(built.body, built.contentType, { "X-Cache": "GEN" });
}
__name(handleSub, "handleSub");
var edge_worker_tier0_default = {
  async fetch(request, env, ctx) {
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
              clash: "/sub?format=clash"
            }
          },
          null,
          2
        ),
        "application/json; charset=utf-8",
        { "Cache-Control": "public, max-age=30" }
      );
    }
    if (pathname === "/sub") {
      return handleSub(request, env, ctx);
    }
    return response(JSON.stringify({ ok: false, error: "Not found" }), "application/json; charset=utf-8", {}, 404);
  }
};
export {
  edge_worker_tier0_default as default
};
//# sourceMappingURL=edge-worker-tier0.js.map

