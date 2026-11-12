import path from 'node:path';

export function loadConfig(env = process.env) {
  const host = env.HOST || '0.0.0.0';
  const port = parseInt(env.PORT || '8888', 10);
  const dataDir = path.resolve(env.DATA_DIR || './data');
  const nodeEnv = env.NODE_ENV || 'development';
  // 10 GB default per-user quota
  const defaultQuotaBytes = parseInt(env.DEFAULT_USER_QUOTA_BYTES || '10737418240', 10);
  const tokenExpiryDays = parseInt(env.TOKEN_EXPIRY_DAYS || '30', 10);

  return {
    host,
    port,
    dataDir,
    nodeEnv,
    defaultQuotaBytes,
    tokenExpiryDays,
  };
}
