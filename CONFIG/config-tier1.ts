import * as dotenv from 'dotenv';

// Load environment variables
dotenv.config();

/**
 * Infrastructure Configuration
 * DreamMaker — dreammaker-groupsoft.ir
 *
 * Source of truth for all shared constants.
 * All secrets come from environment variables; no hardcoded credentials.
 */

export const config = {
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Cloudflare Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  cloudflare: {
    // Primary full-access token (Workers + KV + DNS + Routes)
    // Use CF_API_TOKEN for all new operations.
    apiToken: process.env.CF_API_TOKEN || '',
    zoneId:   process.env.CF_ZONE_ID    || '7521f025c7660ad0f5ab6c57d787fa6f',
    accountId: process.env.CF_ACCOUNT_ID || 'd902b91f0f1076e0601ffd6e7b4382c0',
    kvNamespaceId: process.env.CF_KV_NAMESPACE_ID || 'ef1a164f23424e9a9b23721fb0d16133',

    // Legacy token slots — kept for backward compatibility only.
    // Prefer apiToken (CF_TOKEN5 / CF_API_TOKEN) for all operations.
    tokens: {
      token1: process.env.CF_TOKEN1 || '', // Zone DNS + SSL (legacy)
      token2: process.env.CF_TOKEN2 || '', // Workers API (legacy)
      token3: process.env.CF_TOKEN3 || '', // Deprecated
      token4: process.env.CF_TOKEN4 || '', // Deprecated
      token5: process.env.CF_TOKEN5 || '', // Full-access (same as CF_API_TOKEN)
    },
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Domain Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  domain: {
    primary: process.env.DOMAIN     || 'dreammaker-groupsoft.ir',
    cdn:     process.env.CDN_DOMAIN || 'cdn.dreammaker-groupsoft.ir',
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // VPS Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  vps: {
    germany: {
      ip:          process.env.VPS_DE_IP    || '82.115.26.105',
      user:        process.env.VPS_DE_USER  || 'root',
      port:        parseInt(process.env.VPS_DE_PORT || '22'),
      password:    process.env.VPS_DE_PASS  || '',
      // SOCKS5 proxy required when connecting from outside network
      proxy:       process.env.VPS_DE_PROXY || '127.0.0.1:10808',
      description: 'Primary Production Server (ARM64 Ubuntu LTS)',
    },
    iran: {
      ip:          process.env.VPS_IR_IP    || '87.107.108.53',
      user:        process.env.VPS_IR_USER  || 'root',
      port:        parseInt(process.env.VPS_IR_PORT || '2222'),
      password:    process.env.VPS_IR_PASS  || '',
      proxy:       process.env.VPS_IR_PROXY || '',
      description: 'Relay / Secondary Server (direct SSH on 2222)',
    },
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Telegram Bot Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  telegram: {
    botToken:    process.env.TELEGRAM_BOT_TOKEN    || '',
    botUsername: process.env.TELEGRAM_BOT_USERNAME || '@Freqbasterd_bot',
    ownerId:     process.env.TELEGRAM_OWNER_ID     || '7437859619',
    chatId:      process.env.TELEGRAM_CHAT_ID      || '7437859619',
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Infrastructure Tiers (Canonical UUID Registry)
  //
  // Port mapping (127.0.0.1 only — never public):
  //   Starter   → XHTTP :11001 / WS :11101  → Nginx /api/v1/ping  + /api/v1/ping-ws
  //   Basic     → XHTTP :11002 / WS :11102  → Nginx /cdn/init      + /cdn/init-ws
  //   Standard  → XHTTP :11003 / WS :11103  → Nginx /app/sync      + /app/sync-ws
  //   Plus      → XHTTP :11004 / WS :11104  → Nginx /api/v2/feed   + /api/v2/feed-ws
  //   Pro       → XHTTP :11005 / WS :11105  → Nginx /static/bundle.js + /static/bundle-ws
  //   Elite     → XHTTP :11006 / WS :11106  → Nginx /media/stream  + /media/stream-ws
  //   Unlimited → XHTTP :11007 / WS :11107  → Nginx /v2/content/live + /v2/content/live-ws
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  tiers: {
    Starter: {
      uuid:       process.env.TIER_STARTER_UUID  || '7dd47c02-8dce-4b12-9dbc-7cdb95a9e10e',
      xhttpPath:  '/api/v1/ping',
      wsPath:     '/api/v1/ping-ws',
      xhttpPort:  11001,
      wsPort:     11101,
    },
    Basic: {
      uuid:       process.env.TIER_BASIC_UUID    || '92ebaa01-ec34-4601-a4dc-f6afdf822966',
      xhttpPath:  '/cdn/init',
      wsPath:     '/cdn/init-ws',
      xhttpPort:  11002,
      wsPort:     11102,
    },
    Standard: {
      uuid:       process.env.TIER_STANDARD_UUID || '3d5e3adf-0912-4c78-9ca9-b87db334ce71',
      xhttpPath:  '/app/sync',
      wsPath:     '/app/sync-ws',
      xhttpPort:  11003,
      wsPort:     11103,
    },
    Plus: {
      uuid:       process.env.TIER_PLUS_UUID     || 'e8eb3d74-8e8c-4903-b878-8feb656ebb0c',
      xhttpPath:  '/api/v2/feed',
      wsPath:     '/api/v2/feed-ws',
      xhttpPort:  11004,
      wsPort:     11104,
    },
    Pro: {
      uuid:       process.env.TIER_PRO_UUID      || 'b3540a54-67dd-452a-b5d8-45d6407b8da5',
      xhttpPath:  '/static/bundle.js',
      wsPath:     '/static/bundle-ws',
      xhttpPort:  11005,
      wsPort:     11105,
    },
    Elite: {
      uuid:       process.env.TIER_ELITE_UUID    || '2680152c-0dc3-4fdb-b366-e936358b121f',
      xhttpPath:  '/media/stream',
      wsPath:     '/media/stream-ws',
      xhttpPort:  11006,
      wsPort:     11106,
    },
    Unlimited: {
      uuid:       process.env.TIER_UNLIMITED_UUID || '89c0f294-3f94-4735-96cf-9c1aefdbcbb2',
      xhttpPath:  '/v2/content/live',
      wsPath:     '/v2/content/live-ws',
      xhttpPort:  11007,
      wsPort:     11107,
    },
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Legacy UUIDs (RETIRED — for cleanup reference)
  // Action: delete these from all Xray inbounds
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  legacyUUIDs: {
    'Customer-1': {
      uuid: '6b529aac-012a-4363-88e7-51b26e6072e8',
      oldPorts: [80],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
    'Customer-2': {
      uuid: '9fd77a9a-08a2-4a8c-88ba-0e0a4a30da66',
      oldPorts: [8080, 8000, 2082],
      status: 'ACTIVE (broken — provider drops ports)',
      action: 'MIGRATE to tier or DELETE',
    },
    'Customer-3': {
      uuid: '75c604fc-8f65-4201-9902-8de1d407edb5',
      oldPorts: [8080],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
    'Customer-4': {
      uuid: '85526724-f667-4243-a58d-7cd3cb8b8997',
      oldPorts: [2092],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
    'Customer-5': {
      uuid: 'e2a5e62c-4a0b-4d2d-a10a-b4a13d06a0a9',
      oldPorts: [8880],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
    'Customer-6': {
      uuid: '045319fd-9f1d-4d05-b5ad-46949a8b6ea5',
      oldPorts: [2086],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
    'Customer-7': {
      uuid: 'c4ba6ae4-94be-4752-ae77-76f36154e737',
      oldPorts: [2086],
      status: 'RETIRED',
      action: 'DELETE from Xray inbounds',
    },
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Transport Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  transport: {
    primary:  process.env.TRANSPORT_PRIMARY  || 'xhttp',
    fallback: process.env.TRANSPORT_FALLBACK || 'websocket',
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // SSL Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  ssl: {
    // Let's Encrypt certs managed by Certbot
    certPath: process.env.SSL_CERT_PATH || '/etc/letsencrypt/live/dreammaker-groupsoft.ir/fullchain.pem',
    keyPath:  process.env.SSL_KEY_PATH  || '/etc/letsencrypt/live/dreammaker-groupsoft.ir/privkey.pem',
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Application Configuration
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  app: {
    nodeEnv:  process.env.NODE_ENV   || 'production',
    debug:    process.env.DEBUG === 'true',
    logLevel: process.env.LOG_LEVEL  || 'info',
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Rate Limiting & Security
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  security: {
    rateLimitRequests: parseInt(process.env.RATE_LIMIT_REQUESTS || '100'),
    rateLimitWindow:   process.env.RATE_LIMIT_WINDOW   || '60s',
    rateLimitByIp:     parseInt(process.env.RATE_LIMIT_BY_IP || '10'),
  },

  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━
  // Monitoring
  // ━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━

  monitoring: {
    healthCheckInterval:      process.env.HEALTH_CHECK_INTERVAL || '30s',
    upstreamHealthCheck:      process.env.UPSTREAM_HEALTH_CHECK_ENABLED !== 'false',
    logRetentionNginxDays:    parseInt(process.env.LOG_RETENTION_NGINX || '14'),
    logRetentionXrayDays:     parseInt(process.env.LOG_RETENTION_XRAY  || '7'),
    enableIpAnonymization:    process.env.ENABLE_IP_ANONYMIZATION !== 'false',
  },
};

/**
 * Validate critical configuration values.
 * Call this at startup to catch missing secrets early.
 */
export function validateConfig(): { valid: boolean; errors: string[] } {
  const errors: string[] = [];

  if (!config.cloudflare.apiToken) {
    errors.push('CF_API_TOKEN is not set (required for Cloudflare operations)');
  }
  if (!config.cloudflare.zoneId) {
    errors.push('CF_ZONE_ID is not set');
  }
  if (!config.cloudflare.accountId) {
    errors.push('CF_ACCOUNT_ID is not set');
  }
  if (!config.domain.primary) {
    errors.push('DOMAIN is not set');
  }
  if (!config.vps.germany.password) {
    errors.push('VPS_DE_PASS is not set');
  }
  if (!config.vps.iran.password) {
    errors.push('VPS_IR_PASS is not set');
  }
  if (!config.telegram.botToken) {
    errors.push('TELEGRAM_BOT_TOKEN is not set');
  }

  return {
    valid: errors.length === 0,
    errors,
  };
}

export default config;
