var __defProp = Object.defineProperty;
var __name = (target, value) => __defProp(target, "name", { value, configurable: true });

// helper-ecosystem-tier1.ts
var DEFAULT_HELPERS = [
  {
    // Primary CDN path — the main traffic route
    edgeId: "cdn-primary",
    url: "https://cdn.dreammaker-groupsoft.ir/health",
    method: "GET",
    timeout: 5e3
  },
  {
    // Clean subdomain — alternate DPI-evasion route
    edgeId: "cdn-clean",
    url: "https://clean.dreammaker-groupsoft.ir/health",
    method: "GET",
    timeout: 5e3
  },
  {
    // Root domain — final fallback
    edgeId: "cdn-main",
    url: "https://dreammaker-groupsoft.ir/health",
    method: "GET",
    timeout: 5e3
  },
  {
    // Tier connectivity probe: Starter path (XHTTP check)
    // A 404 here means Nginx location block is missing — critical alert
    edgeId: "tier-starter",
    url: "https://cdn.dreammaker-groupsoft.ir/api/v1/ping",
    method: "GET",
    timeout: 5e3
  },
  {
    // Tier connectivity probe: Basic path
    edgeId: "tier-basic",
    url: "https://cdn.dreammaker-groupsoft.ir/cdn/init",
    method: "GET",
    timeout: 5e3
  }
];
function detectDPIInterference(latency, statusCode, headers) {
  let confidence = 0;
  if (latency > 5e3)
    confidence += 0.35;
  if (statusCode && [403, 451, 500, 502, 503].includes(statusCode)) {
    confidence += 0.4;
  }
  if (!statusCode)
    confidence += 0.2;
  if (headers) {
    const suspiciousAbsence = ["server", "date"].some((h) => !headers[h]);
    if (suspiciousAbsence)
      confidence += 0.15;
  }
  if (latency > 1500 && latency < 3e3)
    confidence += 0.1;
  return {
    suspected: confidence > 0.5,
    confidence: Math.min(confidence, 1)
  };
}
__name(detectDPIInterference, "detectDPIInterference");
function detectTLSFailure(error) {
  if (!error)
    return false;
  const str = String(error).toLowerCase();
  return ["certificate", "tls", "ssl", "handshake", "verify", "untrusted", "expired"].some(
    (kw) => str.includes(kw)
  );
}
__name(detectTLSFailure, "detectTLSFailure");
async function probeHelper(config) {
  const t0 = Date.now();
  let statusCode;
  let responseHeaders = {};
  let tlsFailure = false;
  let success = false;
  try {
    const controller = new AbortController();
    const timer = setTimeout(() => controller.abort(), config.timeout);
    const response = await fetch(config.url, {
      method: config.method,
      signal: controller.signal,
      headers: {
        "User-Agent": "DreamMaker-Monitor/2.1",
        "Accept": "*/*"
      }
    });
    clearTimeout(timer);
    statusCode = response.status;
    response.headers.forEach((v, k) => {
      responseHeaders[k.toLowerCase()] = v;
    });
    success = response.status >= 200 && response.status < 500;
  } catch (err) {
    tlsFailure = detectTLSFailure(err);
    success = false;
  }
  const latency = Date.now() - t0;
  const { suspected: dpiSuspected } = detectDPIInterference(latency, statusCode, responseHeaders);
  return {
    edgeId: config.edgeId,
    latency_ms: latency,
    success,
    statusCode,
    dpiSuspected,
    tlsFailure,
    timestamp: Date.now()
  };
}
__name(probeHelper, "probeHelper");
async function calculateDisconnectRate(kv, edgeId) {
  try {
    const history = await kv.get(`probe-history:${edgeId}`, "json");
    if (!Array.isArray(history) || history.length === 0)
      return 0.02;
    const recent = history.slice(-20);
    return recent.filter((p) => !p.success).length / recent.length;
  } catch {
    return 0.02;
  }
}
__name(calculateDisconnectRate, "calculateDisconnectRate");
async function calculateTLSFailureRate(kv, edgeId) {
  try {
    const history = await kv.get(`probe-history:${edgeId}`, "json");
    if (!Array.isArray(history) || history.length === 0)
      return 5e-3;
    const recent = history.slice(-20);
    return recent.filter((p) => p.tlsFailure).length / recent.length;
  } catch {
    return 5e-3;
  }
}
__name(calculateTLSFailureRate, "calculateTLSFailureRate");
async function calculateMobileStability(kv, edgeId, latency, dpiSuspected) {
  let score = 0.95;
  if (latency > 100)
    score -= 0.05;
  if (latency > 200)
    score -= 0.1;
  if (dpiSuspected)
    score -= 0.1;
  const disconnectRate = await calculateDisconnectRate(kv, edgeId);
  score -= disconnectRate * 0.15;
  return Math.max(score, 0.6);
}
__name(calculateMobileStability, "calculateMobileStability");
async function updateEdgeMetrics(kv, config) {
  const probe = await probeHelper(config);
  const histKey = `probe-history:${config.edgeId}`;
  try {
    const raw = await kv.get(histKey, "json");
    const history = Array.isArray(raw) ? raw : [];
    const updated = [...history, probe].slice(-100);
    await kv.put(histKey, JSON.stringify(updated), { expirationTtl: 3600 });
  } catch (e) {
    console.warn(`probe history write failed for ${config.edgeId}:`, e);
  }
  const disconnectRate = await calculateDisconnectRate(kv, config.edgeId);
  const tlsFailureRate = await calculateTLSFailureRate(kv, config.edgeId);
  const mobileStability = await calculateMobileStability(
    kv,
    config.edgeId,
    probe.latency_ms,
    probe.dpiSuspected
  );
  return {
    edgeId: config.edgeId,
    latency_ms: probe.latency_ms,
    disconnect_rate: disconnectRate,
    dpi_suspicion: probe.dpiSuspected ? 0.6 : 0.1,
    mobile_stability: mobileStability,
    tls_failure_rate: tlsFailureRate,
    timestamp: Date.now()
  };
}
__name(updateEdgeMetrics, "updateEdgeMetrics");
async function loadHelperConfigs(db) {
  if (!db)
    return DEFAULT_HELPERS;
  try {
    const result = await db.prepare("SELECT * FROM helpers WHERE enabled = 1").all();
    if (!result.success || !result.results?.length)
      return DEFAULT_HELPERS;
    return result.results.map((row) => ({
      edgeId: row.edge_id,
      url: row.url,
      method: row.method || "GET",
      timeout: row.timeout || 5e3,
      expectedPattern: row.expected_pattern
    }));
  } catch (e) {
    console.warn("D1 helper load failed, using defaults:", e);
    return DEFAULT_HELPERS;
  }
}
__name(loadHelperConfigs, "loadHelperConfigs");
async function storeMetricsAudit(db, metrics) {
  if (!db)
    return;
  for (const m of metrics) {
    try {
      await db.prepare(
        `INSERT INTO edge_metrics
           (edge_id, latency_ms, disconnect_rate, dpi_suspicion, mobile_stability, tls_failure_rate, timestamp)
           VALUES (?, ?, ?, ?, ?, ?, ?)`
      ).bind(m.edgeId, m.latency_ms, m.disconnect_rate, m.dpi_suspicion, m.mobile_stability, m.tls_failure_rate, m.timestamp).run();
    } catch (e) {
      console.warn(`D1 metrics write failed for ${m.edgeId}:`, e);
    }
  }
}
__name(storeMetricsAudit, "storeMetricsAudit");
function detectAnomalies(metrics) {
  const anomalies = [];
  for (const m of metrics) {
    if (!m.latency_ms || m.disconnect_rate >= 1) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "critical",
        message: `\u{1F6A8} DEAD: ${m.edgeId} \u2014 no connectivity`
      });
    }
    if (m.dpi_suspicion > 0.6) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "critical",
        message: `\u{1F6D1} DPI DETECTED: ${m.edgeId} (${(m.dpi_suspicion * 100).toFixed(0)}% confidence)`
      });
    }
    if (m.disconnect_rate > 0.15) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "warning",
        message: `\u26A0\uFE0F UNSTABLE: ${m.edgeId} (${(m.disconnect_rate * 100).toFixed(1)}% disconnect)`
      });
    }
    if (m.tls_failure_rate > 0.05) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "critical",
        message: `\u{1F512} TLS FAILING: ${m.edgeId} (${(m.tls_failure_rate * 100).toFixed(1)}% failure)`
      });
    }
    if (m.mobile_stability < 0.8) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "warning",
        message: `\u{1F4F1} MOBILE POOR: ${m.edgeId} (${(m.mobile_stability * 100).toFixed(0)}% stable)`
      });
    }
    if (m.latency_ms > 3e3) {
      anomalies.push({
        edgeId: m.edgeId,
        severity: "warning",
        message: `\u{1F422} HIGH LATENCY: ${m.edgeId} (${m.latency_ms}ms)`
      });
    }
  }
  return anomalies;
}
__name(detectAnomalies, "detectAnomalies");
async function sendTelegramAlert(env, anomalies) {
  if (!env.TG_BOT_TOKEN || !env.TG_CHAT_ID)
    return;
  if (anomalies.length === 0)
    return;
  const critical = anomalies.filter((a) => a.severity === "critical");
  const warnings = anomalies.filter((a) => a.severity === "warning");
  const lines = [
    `*DreamMaker Infrastructure Alert*`,
    `\u{1F550} ${(/* @__PURE__ */ new Date()).toISOString()}`,
    `\u{1F30D} Environment: ${env.ENVIRONMENT}`,
    ""
  ];
  if (critical.length > 0) {
    lines.push("*\u{1F6A8} CRITICAL:*");
    critical.forEach((a) => lines.push(`  ${a.message}`));
    lines.push("");
  }
  if (warnings.length > 0) {
    lines.push("*\u26A0\uFE0F WARNINGS:*");
    warnings.forEach((a) => lines.push(`  ${a.message}`));
  }
  const text = lines.join("\n");
  try {
    await fetch(`https://api.telegram.org/bot${env.TG_BOT_TOKEN}/sendMessage`, {
      method: "POST",
      headers: { "Content-Type": "application/json" },
      body: JSON.stringify({
        chat_id: env.TG_CHAT_ID,
        text,
        parse_mode: "Markdown",
        disable_web_page_preview: true
      })
    });
  } catch (e) {
    console.error("Telegram alert failed:", e);
  }
}
__name(sendTelegramAlert, "sendTelegramAlert");
async function runHelperEcosystem(env, ctx) {
  const t0 = Date.now();
  console.log("[TIER1] Starting helper ecosystem check...");
  try {
    const helpers = await loadHelperConfigs(env.DM_DB);
    console.log(`[TIER1] Probing ${helpers.length} helpers...`);
    const metrics = await Promise.all(helpers.map((h) => updateEdgeMetrics(env.DM_KV, h)));
    await env.DM_KV.put("edge:scores", JSON.stringify(metrics), { expirationTtl: 600 });
    const anomalies = detectAnomalies(metrics);
    if (anomalies.length > 0) {
      console.warn("[TIER1] Anomalies:", anomalies.map((a) => a.message));
      await env.DM_KV.put(
        "alerts:latest",
        JSON.stringify({ timestamp: Date.now(), anomalies }),
        { expirationTtl: 600 }
      );
      const criticals = anomalies.filter((a) => a.severity === "critical");
      if (criticals.length > 0) {
        await sendTelegramAlert(env, anomalies);
      }
    } else {
      console.log("[TIER1] All endpoints healthy \u2705");
    }
    ctx.waitUntil(storeMetricsAudit(env.DM_DB, metrics));
    console.log(`[TIER1] Done in ${Date.now() - t0}ms`, {
      edges: metrics.map((m) => ({
        id: m.edgeId,
        latency: m.latency_ms,
        dpi: m.dpi_suspicion.toFixed(2),
        mobile: m.mobile_stability.toFixed(2)
      }))
    });
  } catch (err) {
    console.error("[TIER1] Fatal error:", err);
    await sendTelegramAlert(env, [
      {
        edgeId: "tier1-worker",
        severity: "critical",
        message: `\u{1F6A8} TIER 1 WORKER CRASHED: ${String(err)}`
      }
    ]);
  }
}
__name(runHelperEcosystem, "runHelperEcosystem");
var helper_ecosystem_tier1_default = {
  async scheduled(event, env, ctx) {
    await runHelperEcosystem(env, ctx);
  }
};
export {
  helper_ecosystem_tier1_default as default,
  runHelperEcosystem
};
//# sourceMappingURL=helper-ecosystem-tier1.js.map

--85682d7578a9d640b1f08cf7f04d42a5d3c74f768ca033e81be46b858fc4--

