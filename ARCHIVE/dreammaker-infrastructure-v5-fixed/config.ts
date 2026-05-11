export const DreamMakerConfig = {
  primaryDomain: "dreammaker-groupsoft.ir",
  cdnHost: "cdn.dreammaker-groupsoft.ir",
  transport: {
    primary: "xhttp",
    fallback: "websocket",
  },
  cacheTtlMs: 60_000,
  tiers: {
    starter:   { uuid: "7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e", path: "/api/v1/ping",       label: "DM-Starter" },
    basic:     { uuid: "92ebaa01-ec34-4601-a4dc-f6afdf822966", path: "/cdn/init",           label: "DM-Basic" },
    standard:  { uuid: "3d5e3adf-0912-4c78-9ca9-b87db334ce71", path: "/app/sync",           label: "DM-Standard" },
    plus:      { uuid: "e8eb3d74-8e8c-4903-b878-8feb656ebb0c", path: "/api/v2/feed",        label: "DM-Plus" },
    pro:       { uuid: "b3540a54-67dd-452a-b5d8-45d6407b8da5", path: "/static/bundle.js",    label: "DM-Pro" },
    elite:     { uuid: "2680152c-0dc3-4fdb-b366-e936358b121f", path: "/media/stream",       label: "DM-Elite" },
    unlimited: { uuid: "89c0f294-3f94-4735-96cf-9c1aefdbcbb2", path: "/v2/content/live",     label: "DM-Unlimited" },
  },
} as const;

export type TierKey = keyof typeof DreamMakerConfig.tiers;
