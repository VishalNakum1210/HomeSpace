import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import { authenticate } from './auth.js';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { mediaRoutes } from './routes/media.js';
import { albumsRoutes } from './routes/albums.js';

export async function buildApp({ db, dataDir, config }) {
  const fastify = Fastify({
    logger: false,
    connectionTimeout: 0,
    keepAliveTimeout: 120000,
    requestTimeout: 0,
  });

  // Multipart upload support (up to 500 MB per file)
  await fastify.register(multipart, {
    limits: {
      fileSize: 500 * 1024 * 1024,
    },
  });

  // Rate limiting to protect authentication endpoints from brute force
  await fastify.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
    allowList: (req) => {
      const url = req.url || '';
      return url.startsWith('/api/health') || url.startsWith('/api/media') || url.startsWith('/api/albums');
    },
  });

  // Decorate fastify with auth middleware
  fastify.decorate('authenticate', authenticate(db));

  // Consistent error formatting
  fastify.setErrorHandler((error, req, reply) => {
    const statusCode = error.statusCode || 500;
    const code = error.code || 'INTERNAL_ERROR';
    const message = error.message || 'An unexpected error occurred';

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
    defaultQuotaBytes: config.defaultQuotaBytes,
    tokenExpiryDays: config.tokenExpiryDays,
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

  return fastify;
}
