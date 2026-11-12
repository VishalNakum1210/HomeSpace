import Fastify from 'fastify';
import rateLimit from '@fastify/rate-limit';
import multipart from '@fastify/multipart';
import { authenticate } from './auth.js';
import { healthRoutes } from './routes/health.js';
import { authRoutes } from './routes/auth.js';
import { mediaRoutes } from './routes/media.js';
import { albumRoutes } from './routes/albums.js';
import { trashRoutes } from './routes/trash.js';

export async function buildApp({ db, dataDir, config }) {
  const fastify = Fastify({
    logger: false,
    bodyLimit: 10 * 1024 * 1024, // 10MB default json limit
  });

  // Rate limiting to protect authentication endpoints from brute force
  await fastify.register(rateLimit, {
    max: 100,
    timeWindow: '1 minute',
    allowList: (req) => {
      const url = req.url || '';
      return url.startsWith('/api/media') || url.startsWith('/api/health');
    },
  });

  // Multipart file upload support for media uploads (1GB max for high-res videos & photos)
  await fastify.register(multipart, {
    limits: {
      fileSize: 1024 * 1024 * 1024, // 1GB max per photo/video
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
    dataDir,
    defaultQuotaBytes: config.defaultQuotaBytes,
    tokenExpiryDays: config.tokenExpiryDays,
  });
  await fastify.register(mediaRoutes, {
    prefix: '/api',
    db,
    dataDir,
  });
  await fastify.register(albumRoutes, {
    prefix: '/api',
    db,
    dataDir,
  });
  await fastify.register(trashRoutes, {
    prefix: '/api',
    db,
    dataDir,
  });

  return fastify;
}
