/**
 * ============================================================
 * DreamMaker TIER 0: Edge Fabric
 *
 * Lightweight, fast, resilient edge worker for
 * censorship-resistant proxy infrastructure.
 *
 * DESIGN PRINCIPLES:
 *  ✓ Latency is sacred (~8ms target)
 *  ✓ Survival > operational features
 *  ✓ No D1 calls in request path
 *  ✓ XHTTP as primary transport (all devices)
 *  ✓ WebSocket as fallback transport
 *  ✓ Edge-local decision making
 *  ✓ Probabilistic metrics sampling (1%)
 *  ✓ Anti-fingerprinting measures
 *  ✓ Circuit-breaker for failed edges
 *
 * LATENCY BUDGET for /sub endpoint:
 *  - Cloudflare routing:   1ms (fixed)
 *  - Memory cache:         1ms
 *  - KV cache:             3ms
 *  - Business logic:       2ms
 *  - Response generation:  1ms
 *  - TOTAL: 8ms max
 *
 * PATHS — must match Nginx location blocks exactly:
 *  XHTTP: /api/v1/ping  /cdn/init  /app/sync  /api/v2/feed
 *         /static/bundle.js  /media/stream  /v2/content/live
 *  WS:    same paths with "-ws" suffix
 * ============================================================
 */

// ---------------------------------------------------------------------------
// Domain & infrastructure constants
// ---------------------------------------------------------------------------

/** Primary CDN host that Xray clients connect to. */
const CDN_HOST = 'cdn.dreammaker-groupsoft.ir';

/**
 * Tier registry — one entry per Nginx/Xray inbound tier.
 *
 * Paths MUST match the location blocks in your Nginx config exactly.
 * WebSocket paths use a "-ws" suffix and target separate Nginx locations.
 * UUIDs are sourced from the canonical Xray tier registry.
 */
const TIER_REGISTRY = {
  starter: {
    uuid: '7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e',
    xhttpPath: '/api/v1/ping',
    wsPath: '/api/v1/ping-ws',
    label: 'DM-Starter',
  },
  basic: {
    uuid: '92ebaa01-ec34-4601-a4dc-f6afdf822966',
    xhttpPath: '/cdn/init',
    wsPath: '/cdn/init-ws',
    label: 'DM-Basic',
  },
  standard: {
    uuid: '3d5e3adf-0912-4c78-9ca9-b87db334ce71',
    xhttpPath: '/app/sync',
    wsPath: '/app/sync-ws',
    label: 'DM-Standard',
  },
  plus: {
    uuid: 'e8eb3d74-8e8c-4903-b878-8feb656ebb0c',
    xhttpPath: '/api/v2/feed',
    wsPath: '/api/v2/feed-ws',
    label: 'DM-Plus',
  },
  pro: {
    uuid: 'b3540a54-67dd-452a-b5d8-45d6407b8da5',
    xhttpPath: '/static/bundle.js',
    wsPath: '/static/bundle-ws',
    label: 'DM-Pro',
  },
  elite: {
    uuid: '2680152c-0dc3-4fdb-b366-e936358b121f',
    xhttpPath: '/media/stream',
    wsPath: '/media/stream-ws',
    label: 'DM-Elite',
  },
  unlimited: {
    uuid: '89c0f294-3f94-4735-96cf-9c1aefdbcbb2',
    xhttpPath: '/v2/content/live',
    wsPath: '/v2/content/live-ws',
    label: 'DM-Unlimited',
  },
} as const;

type TierKey = keyof typeof TIER_REGISTRY;

// ---------------------------------------------------------------------------
// Type definitions
// ---------------------------------------------------------------------------

interface Env {
  DM_KV: KVNamespace;
  ENVIRONMENT: 'production' | 'staging' | 'development';
}

interface EdgeMetrics {
  edgeId: string;
  latency_ms: number;
  disconnect_rate: number;
  dpi_suspicion: number;
  mobile_stability: number;
  tls_failure_rate: number;
  timestamp: number;
  score?: number;
  /** Circuit-breaker: set by TIER 1 when an edge is unhealthy. */
  circuit_open?: boolean;
}

// ---------------------------------------------------------------------------
// In-memory L1 cache (per-isolate, resets on deployment)
// ---------------------------------------------------------------------------

const MEMORY_CACHE = new Map<string, { data: string; expires: number }>();

// ---------------------------------------------------------------------------
// Scoring & transport helpers
// ---------------------------------------------------------------------------

/**
 * Composite edge score [0, 100].
 * Higher = better. Weights tuned for censorship-resistant workloads.
 */
function calculateEdgeScore(m: EdgeMetrics): number {
  if (m.circuit_open) return 0; // Never route to tripped edges

  const latencyRatio = Math.min(m.latency_ms / 200, 1); // Normalise at 200 ms
  return (
    (1 - latencyRatio)       * 30 +
    (1 - m.disconnect_rate)  * 25 +
    (1 - m.dpi_suspicion)    * 25 +
    (1 - m.tls_failure_rate) * 10 +
    m.mobile_stability       * 10
  );
}

function detectMobileDevice(request: Request): boolean {
  const ua = request.headers.get('user-agent') ?? '';
  return /Mobile|Android|iPhone|iPad|iPod/i.test(ua);
}

function detectNATConditions(request: Request): boolean {
  const ip = request.headers.get('cf-connecting-ip') ?? '';
  return ip.includes(':'); // IPv6 address → likely behind CGNAT
}

/**
 * Transport selection.
 *
 * XHTTP is always primary (per architecture spec).
 * WebSocket is the fallback for both mobile and desktop.
 *
 * XHTTP does not use the `Upgrade: websocket` header, so it is unaffected
 * by the Nginx block `if ($http_upgrade != "websocket") { return 404; }`.
 * WebSocket links still work because they target separate ws-path locations.
 */
function selectTransport(_request: Request): {
  primary: string;
  mobile: string;
  fallback: string;
} {
  return {
    primary: 'xhttp',
    mobile: 'xhttp',
    fallback: 'websocket',
  };
}

function generateConnectionConfig(isMobile: boolean): {
  idle_timeout: number;
  reconnect_interval: number;
  keepalive: number;
  ipv6_prefer: number;
  cgnat_aware: number;
  packet_fragment: number;
} {
  return {
    idle_timeout: isMobile ? 30_000 : 60_000,
    reconnect_interval: isMobile ? 5_000 : 10_000,
    keepalive: 3_000,
    ipv6_prefer: 1,
    cgnat_aware: 1,
    packet_fragment: isMobile ? 1 : 0,
  };
}

function generateAntiFingerprint(): Record<string, boolean> {
  return {
    userAgentRotation: true,
    headerShuffling: true,
    tlsNoise: true,
    paddingPayload: true,
    randomizePort: false,
  };
}

// ---------------------------------------------------------------------------
// Edge score retrieval (KV → hardcoded fallback)
// ---------------------------------------------------------------------------

const DEFAULT_EDGES: EdgeMetrics[] = [
  {
    edgeId: 'us-west-1',
    latency_ms: 25,
    disconnect_rate: 0.02,
    dpi_suspicion: 0.15,
    mobile_stability: 0.92,
    tls_failure_rate: 0.005,
    timestamp: 0,
  },
  {
    edgeId: 'eu-west-1',
    latency_ms: 18,
    disconnect_rate: 0.01,
    dpi_suspicion: 0.10,
    mobile_stability: 0.95,
    tls_failure_rate: 0.003,
    timestamp: 0,
  },
  {
    edgeId: 'asia-east-1',
    latency_ms: 35,
    disconnect_rate: 0.03,
    dpi_suspicion: 0.25,
    mobile_stability: 0.88,
    tls_failure_rate: 0.008,
    timestamp: 0,
  },
];

async function getEdgeScores(kv: KVNamespace): Promise<EdgeMetrics[]> {
  try {
    const raw = await kv.get('edge:scores', 'json');
    if (Array.isArray(raw) && raw.length > 0) {
      return raw as EdgeMetrics[];
    }
  } catch {
    // KV unavailable — fall through to defaults
  }
  return DEFAULT_EDGES.map((e) => ({ ...e, timestamp: Date.now() }));
}

// ---------------------------------------------------------------------------
// VLESS URI generation
// ---------------------------------------------------------------------------

/**
 * Build a VLESS URI for XHTTP transport over TLS.
 *
 * Format (per Xray spec):
 *   vless://UUID@cdn.host:443?encryption=none&type=xhttp&path=PATH
 *            &security=tls&sni=cdn.host&fp=chrome&host=cdn.host#LABEL
 */
function buildVlessXHTTP(tier: (typeof TIER_REGISTRY)[TierKey]): string {
  const params = new URLSearchParams({
    encryption: 'none',
    type: 'xhttp',
    path: tier.xhttpPath,
    security: 'tls',
    sni: CDN_HOST,
    fp: 'chrome',
    host: CDN_HOST,
  });
  return `vless://${tier.uuid}@${CDN_HOST}:443?${params.toString()}#${tier.label}`;
}

/**
 * Build a VLESS URI for WebSocket transport over TLS (fallback).
 *
 * WebSocket requires the `Upgrade: websocket` header, which Nginx
 * correctly forwards only on the dedicated ws-path locations.
 * This is why XHTTP and WS use separate path namespaces.
 */
function buildVlessWS(tier: (typeof TIER_REGISTRY)[TierKey]): string {
  const params = new URLSearchParams({
    encryption: 'none',
    type: 'ws',
    path: tier.wsPath,
    security: 'tls',
    sni: CDN_HOST,
    fp: 'chrome',
    host: CDN_HOST,
  });
  return `vless://${tier.uuid}@${CDN_HOST}:443?${params.toString()}#${tier.label}-WS`;
}

// ---------------------------------------------------------------------------
// Subscription formatters
// ---------------------------------------------------------------------------

/**
 * VLESS format — base64-encoded, compatible with v2rayN, Happ, Sing-Box, etc.
 *
 * Each tier emits two entries:
 *   1. Primary XHTTP link
 *   2. WebSocket fallback link
 */
function formatVlessSubscription(): string {
  const lines: string[] = [];
  for (const key of Object.keys(TIER_REGISTRY) as TierKey[]) {
    const tier = TIER_REGISTRY[key];
    lines.push(buildVlessXHTTP(tier)); // Primary: XHTTP
    lines.push(buildVlessWS(tier));    // Fallback: WebSocket
  }
  return btoa(lines.join('\n'));
}

function formatClashSubscription(): string {
  const proxies: object[] = [];
  for (const key of Object.keys(TIER_REGISTRY) as TierKey[]) {
    const tier = TIER_REGISTRY[key];

    proxies.push({
      name: tier.label,
      type: 'vless',
      server: CDN_HOST,
      port: 443,
      uuid: tier.uuid,
      tls: true,
      'client-fingerprint': 'chrome',
      'skip-cert-verify': false,
      network: 'xhttp',
      'xhttp-opts': { path: tier.xhttpPath, host: CDN_HOST },
      servername: CDN_HOST,
    });

    proxies.push({
      name: `${tier.label}-WS`,
      type: 'vless',
      server: CDN_HOST,
      port: 443,
      uuid: tier.uuid,
      tls: true,
      'client-fingerprint': 'chrome',
      'skip-cert-verify': false,
      network: 'ws',
      'ws-opts': { path: tier.wsPath, headers: { Host: CDN_HOST } },
      servername: CDN_HOST,
    });
  }

  return `proxies:\n${proxies.map((p) => `  - ${JSON.stringify(p)}`).join('\n')}`;
}

function formatJsonSubscription(
  request: Request,
  edgeScores: EdgeMetrics[],
): string {
  const isMobile = detectMobileDevice(request);
  const isNAT = detectNATConditions(request);
  const transports = selectTransport(request);
  const config = generateConnectionConfig(isMobile);

  const scoredEdges = edgeScores
    .map((e) => ({ ...e, score: calculateEdgeScore(e) }))
    .sort((a, b) => b.score - a.score);

  return JSON.stringify(
    {
      version: '2.1.0',
      timestamp: Date.now(),
      domain: CDN_HOST,
      tiers: TIER_REGISTRY,
      transports,
      antiFingerprint: generateAntiFingerprint(),
      config: {
        idle_timeout: config.idle_timeout,
        reconnect_interval: config.reconnect_interval,
        keepalive: config.keepalive,
      },
      edgeMeta: {
        mobile: isMobile,
        nat: isNAT,
        scores: scoredEdges.map((e) => ({
          id: e.edgeId,
          latency: e.latency_ms,
          score: e.score,
          circuit_open: e.circuit_open ?? false,
        })),
      },
    },
    null,
    2,
  );
}

// ---------------------------------------------------------------------------
// Cache key helper
// ---------------------------------------------------------------------------

function buildCacheKey(format: string, request: Request): string {
  if (format === 'json') {
    const isMobile = detectMobileDevice(request);
    return `sub:json:${isMobile ? 'mobile' : 'desktop'}`;
  }
  return `sub:${format}`;
}

// ---------------------------------------------------------------------------
// Response builders
// ---------------------------------------------------------------------------

function buildSubResponse(
  data: string,
  cacheLayer: string,
  duration: number,
): Response {
  return new Response(data, {
    status: 200,
    headers: {
      'Content-Type': 'text/plain; charset=utf-8',
      'Cache-Control': 'public, max-age=300',
      'X-Cache': cacheLayer,
      'X-Response-Time': `${duration.toFixed(1)}ms`,
    },
  });
}

// ---------------------------------------------------------------------------
// Request handlers
// ---------------------------------------------------------------------------

async function handleHealth(): Promise<Response> {
  return new Response(
    JSON.stringify({
      ok: true,
      service: 'DreamMaker TIER 0 Edge Fabric',
      version: '2.1.0',
      timestamp: Date.now(),
      latency_target_ms: 8,
      cdn_host: CDN_HOST,
      tier_count: Object.keys(TIER_REGISTRY).length,
    }),
    {
      status: 200,
      headers: {
        'Content-Type': 'application/json',
        'Cache-Control': 'public, max-age=60',
      },
    },
  );
}

async function handleSubscription(
  request: Request,
  env: Env,
  ctx: ExecutionContext,
): Promise<Response> {
  const startTime = performance.now();
  const url = new URL(request.url);
  const format = (url.searchParams.get('format') ?? 'vless').toLowerCase();
  const cacheKey = buildCacheKey(format, request);

  // L1: Memory cache (<1 ms)
  const memHit = MEMORY_CACHE.get(cacheKey);
  if (memHit && memHit.expires > Date.now()) {
    return buildSubResponse(memHit.data, 'MEMORY', performance.now() - startTime);
  }

  // L2: KV cache (<3 ms)
  try {
    const kvHit = await env.DM_KV.get(cacheKey);
    if (kvHit) {
      MEMORY_CACHE.set(cacheKey, { data: kvHit, expires: Date.now() + 60_000 });
      return buildSubResponse(kvHit, 'KV', performance.now() - startTime);
    }
  } catch {
    console.warn('[TIER0] KV read failed, generating fresh subscription');
  }

  // L3: Generate (<2 ms)
  try {
    const edgeScores = await getEdgeScores(env.DM_KV);
    let subscriptionData: string;

    switch (format) {
      case 'clash':
        subscriptionData = formatClashSubscription();
        break;
      case 'json':
        subscriptionData = formatJsonSubscription(request, edgeScores);
        break;
      case 'vless':
      default:
        subscriptionData = formatVlessSubscription();
        break;
    }

    MEMORY_CACHE.set(cacheKey, {
      data: subscriptionData,
      expires: Date.now() + 60_000,
    });

    ctx.waitUntil(
      env.DM_KV.put(cacheKey, subscriptionData, { expirationTtl: 300 }).catch(
        (e) => console.warn('[TIER0] KV write failed:', e),
      ),
    );

    const duration = performance.now() - startTime;
    recordMetricsAsync(ctx, env.DM_KV, request, duration, 200);
    return buildSubResponse(subscriptionData, 'GENERATED', duration);
  } catch (error) {
    console.error('[TIER0] Subscription generation failed:', error);
    const duration = performance.now() - startTime;
    recordMetricsAsync(ctx, env.DM_KV, request, duration, 500);
    return new Response(
      JSON.stringify({
        ok: false,
        error: 'Subscription generation failed',
        timestamp: Date.now(),
      }),
      {
        status: 500,
        headers: {
          'Content-Type': 'application/json',
          'Cache-Control': 'no-store',
        },
      },
    );
  }
}

// ---------------------------------------------------------------------------
// Metrics (1% probabilistic sampling)
// ---------------------------------------------------------------------------

async function recordMetricsAsync(
  ctx: ExecutionContext,
  kv: KVNamespace,
  request: Request,
  duration: number,
  status: number,
): Promise<void> {
  if (Math.random() > 0.01) return; // Skip 99% of requests

  ctx.waitUntil(
    (async () => {
      try {
        const now = Date.now();
        await kv.put(
          `sampled-metrics:${now}`,
          JSON.stringify({
            timestamp: now,
            path: new URL(request.url).pathname,
            status,
            duration,
            method: request.method,
          }),
          { expirationTtl: 86_400 },
        );
      } catch (e) {
        console.error('[TIER0] Metrics recording failed:', e);
      }
    })(),
  );
}

// ---------------------------------------------------------------------------
// Security headers
// ---------------------------------------------------------------------------

function addSecurityHeaders(response: Response): Response {
  const headers = new Headers(response.headers);
  headers.set('Strict-Transport-Security', 'max-age=31536000; includeSubDomains');
  headers.set('Content-Security-Policy', "default-src 'self'; script-src 'none'");
  headers.set('X-Frame-Options', 'DENY');
  headers.set('X-Content-Type-Options', 'nosniff');
  headers.set('Referrer-Policy', 'strict-origin-when-cross-origin');
  return new Response(response.body, {
    status: response.status,
    statusText: response.statusText,
    headers,
  });
}

// ---------------------------------------------------------------------------
// Main fetch handler
// ---------------------------------------------------------------------------

export default {
  async fetch(
    request: Request,
    env: Env,
    ctx: ExecutionContext,
  ): Promise<Response> {
    const { pathname } = new URL(request.url);
    let response: Response;

    try {
      if (pathname === '/health' || pathname === '/ping') {
        response = await handleHealth();
      } else if (pathname === '/sub') {
        response = await handleSubscription(request, env, ctx);
      } else if (pathname === '/') {
        response = new Response(
          JSON.stringify({
            ok: true,
            name: 'DreamMaker TIER 0 Edge Fabric',
            version: '2.1.0',
            endpoints: {
              health: '/health',
              subscription_vless: '/sub?format=vless',
              subscription_clash: '/sub?format=clash',
              subscription_json: '/sub?format=json',
            },
          }),
          { status: 200, headers: { 'Content-Type': 'application/json' } },
        );
      } else {
        response = new Response(
          JSON.stringify({ ok: false, error: 'Not found' }),
          { status: 404, headers: { 'Content-Type': 'application/json' } },
        );
      }
    } catch (error) {
      console.error('[TIER0] Request handler error:', error);
      response = new Response(
        JSON.stringify({ ok: false, error: 'Internal server error' }),
        { status: 500, headers: { 'Content-Type': 'application/json' } },
      );
    }

    return addSecurityHeaders(response);
  },
};
