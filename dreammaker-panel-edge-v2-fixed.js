const PANEL_BASE = "/jZMb26oGjigaPhSgj9";

export default {
  async fetch(req) {
    const url = new URL(req.url);

    if (url.pathname === "/__worker_ping") {
      return Response.json({ ok:true, worker:"panel-edge-v2", ts:Date.now() });
    }

    // Probe: test connectivity via multiple paths
    if (url.pathname === "/__probe") {
      const tests = [
        { l:"http-2053-panel-proxy",  u:`http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/` },
        { l:"http-2053-panel-proxy-login", u:`http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/login` },
      ];
      const out = {};
      for (const {l, u} of tests) {
        try {
          const r = await fetch(u, {
            signal: AbortSignal.timeout(6000),
            redirect: "manual",
            headers: { "Host":"direct1.dreammaker-groupsoft.ir:2053" }
          });
          out[l] = `${r.status} | ${(await r.text()).slice(0,80)}`;
        } catch(e) { out[l] = `ERR: ${e.message.slice(0,80)}`; }
      }
      return Response.json(out);
    }

    // Normal transparent proxy to http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy/
    const backendUrl = `http://direct1.dreammaker-groupsoft.ir:2053/panel-proxy${url.pathname}${url.search}`;
    try {
      const fwd = new Headers(req.headers);
      fwd.set("Host","direct1.dreammaker-groupsoft.ir:2053");
      const r = await fetch(backendUrl, {
        method: req.method,
        headers: fwd,
        body: ["GET","HEAD"].includes(req.method) ? undefined : req.body,
        redirect: "manual",
        signal: AbortSignal.timeout(30000)
      });
      return new Response(r.body, { status:r.status, headers:r.headers });
    } catch(e) {
      return new Response(`ERR: ${e.message}`, { status:502 });
    }
  }
};
