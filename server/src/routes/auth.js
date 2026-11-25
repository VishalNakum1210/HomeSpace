import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { hashPassword, verifyPassword, createSession } from '../auth.js';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const AVATAR_TONE_REGEX = /^[a-zA-Z0-9_-]{1,24}$/;

function ensureUserStorageDirs(dataDir, userId) {
  if (!dataDir) return;
  const userRoot = path.join(dataDir, 'users', userId);
  fs.mkdirSync(path.join(userRoot, 'originals'), { recursive: true, mode: 0o700 });
  fs.mkdirSync(path.join(userRoot, 'thumbnails'), { recursive: true, mode: 0o700 });
}

export async function authRoutes(fastify, options) {
  const { db, dataDir, defaultQuotaBytes, tokenExpiryDays, registrationOpen = true } = options;

  // Registration
  fastify.post('/auth/register', async (req, reply) => {
    if (!registrationOpen) {
      return reply.code(403).send({
        error: {
          code: 'REGISTRATION_DISABLED',
          message: 'Public registration is disabled on this server. Ask an administrator to create an account.',
        },
      });
    }

    const { email, password, name, avatarTone = 'orange' } = req.body || {};

    if (!email || typeof email !== 'string' || email.trim().length > 254 || !EMAIL_REGEX.test(email.trim())) {
      return reply.code(400).send({
        error: { code: 'INVALID_EMAIL', message: 'A valid email address is required.' },
      });
    }

    if (!password || typeof password !== 'string' || password.length < 8 || password.length > 256) {
      return reply.code(400).send({
        error: { code: 'INVALID_PASSWORD', message: 'Password must be between 8 and 256 characters long.' },
      });
    }

    if (!name || typeof name !== 'string' || !name.trim() || name.trim().length > 80) {
      return reply.code(400).send({
        error: { code: 'INVALID_NAME', message: 'Name is required (max 80 characters).' },
      });
    }

    const cleanTone = (typeof avatarTone === 'string' && AVATAR_TONE_REGEX.test(avatarTone.trim()))
      ? avatarTone.trim().toLowerCase()
      : 'orange';
    const normalizedEmail = email.trim().toLowerCase();
    const cleanName = name.trim();

    const userId = 'u_' + crypto.randomBytes(8).toString('hex');
    const { hash, salt } = await hashPassword(password);
    const now = new Date().toISOString();

    let isAdmin = 0;
    db.exec('BEGIN IMMEDIATE;');
    try {
      const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail);
      if (existing) {
        db.exec('ROLLBACK;');
        return reply.code(409).send({
          error: { code: 'EMAIL_EXISTS', message: 'An account with this email already exists.' },
        });
      }

      const userCount = db.prepare('SELECT COUNT(*) as count FROM users').get().count;
      isAdmin = userCount === 0 ? 1 : 0;

      db.prepare(`
        INSERT INTO users (
          id, email, password_hash, password_salt, name, avatar_tone,
          is_admin, storage_quota_bytes, storage_used_bytes, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, 0, ?, ?)
      `).run(
        userId,
        normalizedEmail,
        hash,
        salt,
        cleanName,
        cleanTone,
        isAdmin,
        defaultQuotaBytes,
        now,
        now,
      );
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      if (String(e?.message || '').includes('UNIQUE')) {
        return reply.code(409).send({
          error: { code: 'EMAIL_EXISTS', message: 'An account with this email already exists.' },
        });
      }
      throw e;
    }

    ensureUserStorageDirs(dataDir, userId);

    const session = createSession(db, userId, tokenExpiryDays);

    return reply.code(201).send({
      token: session.token,
      expiresAt: session.expiresAt,
      user: {
        id: userId,
        email: normalizedEmail,
        name: cleanName,
        avatarTone: cleanTone,
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

    if (email.length > 254 || password.length > 256) {
      return reply.code(401).send({
        error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password.' },
      });
    }

    const normalizedEmail = email.trim().toLowerCase();
    const user = db.prepare(`
      SELECT id, email, password_hash, password_salt, name, avatar_tone,
             is_admin, storage_quota_bytes, storage_used_bytes, created_at
      FROM users
      WHERE email = ?
    `).get(normalizedEmail);

    if (!user || !(await verifyPassword(password, user.password_salt, user.password_hash))) {
      return reply.code(401).send({
        error: { code: 'INVALID_CREDENTIALS', message: 'Incorrect email or password.' },
      });
    }

    ensureUserStorageDirs(dataDir, user.id);
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
  fastify.get('/auth/me', { preHandler: [fastify.authenticate] }, async (req) => {
    const quotaBytes = Number(req.user.storageQuotaBytes ?? defaultQuotaBytes);
    const usedBytes = Number(req.user.storageUsedBytes ?? 0);
    const remainingBytes = Math.max(0, quotaBytes - usedBytes);
    const percentUsed = quotaBytes > 0 ? (usedBytes / quotaBytes) * 100 : 0;
    const { is_admin: _ignoredIsAdmin, ...safeUser } = req.user;

    return {
      user: {
        ...safeUser,
        isAdmin: Boolean(req.user.isAdmin ?? req.user.is_admin),
        storage: {
          usedBytes,
          quotaBytes,
          remainingBytes,
          percentUsed: Number(percentUsed.toFixed(2)),
        },
      },
    };
  });

  // Family member directory for shared albums (non-sensitive fields only)
  fastify.get('/family/members', { preHandler: [fastify.authenticate] }, async () => {
    const rows = db.prepare(`
      SELECT id, name, avatar_tone, is_admin
      FROM users
      ORDER BY created_at ASC
    `).all();
    return {
      members: rows.map((u) => ({
        id: u.id,
        name: u.name,
        avatarTone: u.avatar_tone,
        isAdmin: Boolean(u.is_admin),
      })),
    };
  });

  // Logout
  fastify.post('/auth/logout', { preHandler: [fastify.authenticate] }, async (req) => {
    db.prepare('DELETE FROM sessions WHERE id = ?').run(req.sessionId);
    return { success: true };
  });
}
