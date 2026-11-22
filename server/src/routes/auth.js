import crypto from 'node:crypto';
import { hashPassword, verifyPassword, createSession } from '../auth.js';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function authRoutes(fastify, options) {
  const { db, defaultQuotaBytes, tokenExpiryDays } = options;

  // Registration
  fastify.post('/auth/register', async (req, reply) => {
    const { email, password, name, avatarTone = 'orange' } = req.body || {};

    if (!email || typeof email !== 'string' || !EMAIL_REGEX.test(email.trim())) {
      return reply.code(400).send({
        error: { code: 'INVALID_EMAIL', message: 'A valid email address is required.' },
      });
    }

    if (!password || typeof password !== 'string' || password.length < 8) {
      return reply.code(400).send({
        error: { code: 'INVALID_PASSWORD', message: 'Password must be at least 8 characters long.' },
      });
    }

    if (!name || typeof name !== 'string' || !name.trim()) {
      return reply.code(400).send({
        error: { code: 'INVALID_NAME', message: 'Name is required.' },
      });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail);
    if (existing) {
      return reply.code(409).send({
        error: { code: 'EMAIL_EXISTS', message: 'An account with this email already exists.' },
      });
    }

    const userId = 'u_' + crypto.randomBytes(8).toString('hex');
    const { hash, salt } = hashPassword(password);
    const now = new Date().toISOString();

    const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
    const isAdmin = userCount === 0 ? 1 : 0;

    const insertStmt = db.prepare(`
      INSERT INTO users (
        id, email, password_hash, password_salt, name, avatar_tone,
        is_admin, storage_quota_bytes, storage_used_bytes, created_at, updated_at
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
    `);

    insertStmt.run(
      userId,
      normalizedEmail,
      hash,
      salt,
      name.trim(),
      avatarTone,
      isAdmin,
      defaultQuotaBytes,
      now,
      now,
    );

    const session = createSession(db, userId, tokenExpiryDays);

    return reply.code(201).send({
      token: session.token,
      expiresAt: session.expiresAt,
      user: {
        id: userId,
        email: normalizedEmail,
        name: name.trim(),
        avatarTone,
        isAdmin: Boolean(isAdmin),
        storageQuotaBytes: defaultQuotaBytes,
        storageUsedBytes: 0,
        createdAt: now,
      },
    });
  });

  // Login
  fastify.post('/auth/login', async (req, reply) => {
    const { email, password } = req.body || {};

    if (!email || !password || typeof email !== 'string' || typeof password !== 'string') {
      return reply.code(400).send({
        error: { code: 'INVALID_CREDENTIALS', message: 'Email and password are required.' },
      });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const user = db.prepare(`
      SELECT id, email, password_hash, password_salt, name, avatar_tone,
             is_admin, storage_quota_bytes, storage_used_bytes, created_at
      FROM users
      WHERE email = ?
    `).get(normalizedEmail);

    if (!user || !verifyPassword(password, user.password_salt, user.password_hash)) {
      return reply.code(401).send({
        error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password.' },
      });
    }

    const session = createSession(db, user.id, tokenExpiryDays);

    return {
      token: session.token,
      expiresAt: session.expiresAt,
      user: {
        id: user.id,
        email: user.email,
        name: user.name,
        avatarTone: user.avatar_tone,
        isAdmin: Boolean(user.is_admin),
        storageQuotaBytes: Number(user.storage_quota_bytes),
        storageUsedBytes: Number(user.storage_used_bytes),
        createdAt: user.created_at,
      },
    };
  });

  // Current user profile
  fastify.get('/auth/me', { preHandler: [fastify.authenticate] }, async (req, reply) => {
    const quotaBytes = req.user.storage_quota_bytes || defaultQuotaBytes;
    const usedBytes = req.user.storage_used_bytes || 0;
    const remainingBytes = Math.max(0, quotaBytes - usedBytes);
    const percentUsed = quotaBytes > 0 ? (usedBytes / quotaBytes) * 100 : 0;

    return {
      user: {
        ...req.user,
        isAdmin: Boolean(req.user.is_admin),
        storage: {
          usedBytes,
          quotaBytes,
          remainingBytes,
          percentUsed: Number(percentUsed.toFixed(2)),
        },
      },
    };
  });

  // Logout
  fastify.post('/auth/logout', { preHandler: [fastify.authenticate] }, async (req, reply) => {
    db.prepare('DELETE FROM sessions WHERE id = ?').run(req.sessionId);
    return { success: true };
  });
}
