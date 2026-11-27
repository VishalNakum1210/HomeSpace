import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import { authenticate, pruneExpiredSessions } from './auth.js';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { mediaRoutes } from './routes/media.js';
import { albumsRoutes } from './routes/albums.js';
import { adminRoutes } from './routes/admin.js';

export async function buildApp({ db, dataDir, config }) {
  const fastify = Fastify({
    logger: false,
    connectionTimeout: 0,
    keepAliveTimeout: 120000,
    requestTimeout: 0,
  });

  // Periodically prune expired sessions so tokens table does not grow unbounded
  try {
    pruneExpiredSessions(db);
  } catch (_) {}
  const sessionPruneTimer = setInterval(() => {
    try {
      pruneExpiredSessions(db);
    } catch (_) {}
  }, 60 * 60 * 1000);
  sessionPruneTimer.unref?.();
  fastify.addHook('onClose', async () => {
    clearInterval(sessionPruneTimer);
  });

  // Multipart upload support (per-route limits enforce user quota and free disk space)
  await fastify.register(multipart, {
    limits: {
      fileSize: Number.MAX_SAFE_INTEGER,
    },
  });

  // Rate limiting to protect authentication and admin endpoints from brute force
  await fastify.register(rateLimit, {
    max: 60,
    timeWindow: '1 minute',
    allowList: (req) => {
      const url = req.url || '';
      return url.startsWith('/api/health') || url.startsWith('/api/media') || url.startsWith('/api/albums') || url.startsWith('/api/trash');
    },
  });

  // Decorate fastify with auth middleware
  fastify.decorate('authenticate', authenticate(db));

  // Consistent error formatting (sanitize 5xx internal errors)
  fastify.setErrorHandler((error, req, reply) => {
    const statusCode = error.statusCode && error.statusCode >= 400 ? error.statusCode : 500;
    const isServerError = statusCode >= 500;
    if (isServerError) {
      console.error('[HomeSpace Server] Internal error:', error);
    }
    const code = isServerError ? 'INTERNAL_ERROR' : (error.code || 'BAD_REQUEST');
    const message = isServerError
      ? 'An unexpected internal error occurred.'
      : (error.message || 'Request failed.');

    reply.code(statusCode).send({
      error: {
        code,
        message,
      },
    });
  });

  // Register API routes under /api
  await fastify.register(healthRoutes, { prefix: '/api' });
  await fastify.register(authRoutes, {
    prefix: '/api',
    db,
    dataDir,
    defaultQuotaBytes: config.defaultQuotaBytes,
    tokenExpiryDays: config.tokenExpiryDays,
    registrationOpen: config?.registrationOpen ?? true,
  });
  await fastify.register(mediaRoutes, {
    prefix: '/api',
    db,
    dataDir,
  });
  await fastify.register(albumsRoutes, {
    prefix: '/api',
    db,
  });
  await fastify.register(adminRoutes, {
    prefix: '/api',
    db,
    defaultQuotaBytes: config.defaultQuotaBytes,
    dataDir,
  });

  return fastify;
}
