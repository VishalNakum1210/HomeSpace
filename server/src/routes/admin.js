import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { hashPassword } from '../auth.js';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;
const AVATAR_TONE_REGEX = /^[a-zA-Z0-9_-]{1,24}$/;

export async function adminRoutes(fastify, options) {
  const { db, defaultQuotaBytes = 15 * 1024 * 1024 * 1024, dataDir = 'data' } = options;

  // Middleware: require authentication and admin privileges
  const requireAdmin = async (req, reply) => {
    await fastify.authenticate(req, reply);
    if (reply.sent) return;

    if (!req.user || (!req.user.isAdmin && !req.user.is_admin)) {
      return reply.code(403).send({
        error: {
          code: 'FORBIDDEN',
          message: 'Admin access required for family account management.',
        },
      });
    }
  };

  // 1. List all family users
  fastify.get('/admin/users', { preHandler: [requireAdmin] }, async () => {
    const users = db.prepare(`
      SELECT id, email, name, avatar_tone, is_admin,
             storage_quota_bytes, storage_used_bytes, created_at
      FROM users
      ORDER BY created_at ASC
    `).all();

    return {
      users: users.map((u) => ({
        id: u.id,
        email: u.email,
        name: u.name,
        avatarTone: u.avatar_tone,
        isAdmin: Boolean(u.is_admin),
        storageQuotaBytes: Number(u.storage_quota_bytes),
        storageUsedBytes: Number(u.storage_used_bytes),
        createdAt: u.created_at,
      })),
    };
  });

  // 2. Create a new family user account
  fastify.post('/admin/users', { preHandler: [requireAdmin] }, async (req, reply) => {
    const {
      email,
      password,
      name,
      avatarTone = 'orange',
      storageQuotaBytes = defaultQuotaBytes,
      isAdmin = false,
    } = req.body || {};

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

    const numericQuota = Number(storageQuotaBytes);
    if (!Number.isFinite(numericQuota) || numericQuota <= 0) {
      return reply.code(400).send({
        error: { code: 'INVALID_QUOTA', message: 'storageQuotaBytes must be a positive number.' },
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

    db.exec('BEGIN IMMEDIATE;');
    try {
      const existing = db.prepare('SELECT id FROM users WHERE email = ?').get(normalizedEmail);
      if (existing) {
        db.exec('ROLLBACK;');
        return reply.code(409).send({
          error: { code: 'EMAIL_EXISTS', message: 'An account with this email already exists.' },
        });
      }

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
        isAdmin ? 1 : 0,
        Math.floor(numericQuota),
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

    const userRoot = path.join(dataDir, 'users', userId);
    fs.mkdirSync(path.join(userRoot, 'originals'), { recursive: true, mode: 0o700 });
    fs.mkdirSync(path.join(userRoot, 'thumbnails'), { recursive: true, mode: 0o700 });

    return reply.code(201).send({
      user: {
        id: userId,
        email: normalizedEmail,
        name: cleanName,
        avatarTone: cleanTone,
        isAdmin: Boolean(isAdmin),
        storageQuotaBytes: Math.floor(numericQuota),
        storageUsedBytes: 0,
        createdAt: now,
      },
    });
  });

  // 3. Update family user account
  fastify.patch('/admin/users/:id', { preHandler: [requireAdmin] }, async (req, reply) => {
    const { id } = req.params;
    const { name, avatarTone, storageQuotaBytes, isAdmin } = req.body || {};

    db.exec('BEGIN IMMEDIATE;');
    try {
      const targetUser = db.prepare('SELECT id, is_admin FROM users WHERE id = ?').get(id);
      if (!targetUser) {
        db.exec('ROLLBACK;');
        return reply.code(404).send({
          error: { code: 'USER_NOT_FOUND', message: 'User not found.' },
        });
      }

      // Safety: prevent demoting oneself if the caller is the last admin
      if (id === req.user.id && isAdmin === false) {
        const adminCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_admin = 1').get().count;
        if (adminCount <= 1) {
          db.exec('ROLLBACK;');
          return reply.code(400).send({
            error: { code: 'CANNOT_DEMOTE_LAST_ADMIN', message: 'Cannot demote the last administrator.' },
          });
        }
      }

      const updates = [];
      const values = [];

      if (name && typeof name === 'string' && name.trim()) {
        updates.push('name = ?');
        values.push(name.trim().substring(0, 80));
      }
      if (avatarTone && typeof avatarTone === 'string' && AVATAR_TONE_REGEX.test(avatarTone.trim())) {
        updates.push('avatar_tone = ?');
        values.push(avatarTone.trim().toLowerCase());
      }
      if (storageQuotaBytes !== undefined && typeof storageQuotaBytes === 'number' && Number.isFinite(storageQuotaBytes) && storageQuotaBytes > 0) {
        updates.push('storage_quota_bytes = ?');
        values.push(Math.floor(storageQuotaBytes));
      }
      if (isAdmin !== undefined && typeof isAdmin === 'boolean') {
        updates.push('is_admin = ?');
        values.push(isAdmin ? 1 : 0);
      }

      if (updates.length > 0) {
        updates.push('updated_at = ?');
        values.push(new Date().toISOString());
        values.push(id);
        db.prepare(`UPDATE users SET ${updates.join(', ')} WHERE id = ?`).run(...values);
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    const updated = db.prepare(`
      SELECT id, email, name, avatar_tone, is_admin,
             storage_quota_bytes, storage_used_bytes, created_at
      FROM users WHERE id = ?
    `).get(id);

    return {
      user: {
        id: updated.id,
        email: updated.email,
        name: updated.name,
        avatarTone: updated.avatar_tone,
        isAdmin: Boolean(updated.is_admin),
        storageQuotaBytes: Number(updated.storage_quota_bytes),
        storageUsedBytes: Number(updated.storage_used_bytes),
        createdAt: updated.created_at,
      },
    };
  });

  // 4. Delete family user account
  fastify.delete('/admin/users/:id', { preHandler: [requireAdmin] }, async (req, reply) => {
    const { id } = req.params;

    if (id === req.user.id) {
      return reply.code(400).send({
        error: { code: 'CANNOT_DELETE_SELF', message: 'You cannot delete your own admin account.' },
      });
    }

    db.exec('BEGIN IMMEDIATE;');
    try {
      const targetUser = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
      if (!targetUser) {
        db.exec('ROLLBACK;');
        return reply.code(404).send({
          error: { code: 'USER_NOT_FOUND', message: 'User not found.' },
        });
      }

      // Cascade delete user in DB (FK cascades to sessions, media, albums, album_media, album_members)
      db.prepare('DELETE FROM users WHERE id = ?').run(id);
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    // Clean up physical directory for user after DB commit
    try {
      const userDir = path.join(dataDir, 'users', id);
      if (fs.existsSync(userDir)) {
        fs.rmSync(userDir, { recursive: true, force: true });
      }
    } catch (_) {}

    return { success: true };
  });

  // 5. Storage stats breakdown for current user
  fastify.get('/media/storage-breakdown', { preHandler: [fastify.authenticate] }, async (req) => {
    const rows = db.prepare(`
      SELECT kind, is_trashed, COUNT(*) as count, COALESCE(SUM(size_bytes), 0) as total_bytes
      FROM media
      WHERE user_id = ?
      GROUP BY kind, is_trashed
    `).all(req.user.id);

    let photosBytes = 0;
    let videosBytes = 0;
    let trashedBytes = 0;
    for (const r of rows) {
      const bytes = Number(r.total_bytes || 0);
      if (r.is_trashed) {
        trashedBytes += bytes;
      } else if (r.kind === 'video') {
        videosBytes += bytes;
      } else {
        photosBytes += bytes;
      }
    }

    const totalUsedBytes = Number(req.user.storageUsedBytes ?? (photosBytes + videosBytes + trashedBytes));
    const quotaBytes = Number(req.user.storageQuotaBytes ?? defaultQuotaBytes);
    const freeBytes = Math.max(0, quotaBytes - totalUsedBytes);

    return {
      photosBytes,
      videosBytes,
      trashedBytes,
      totalUsedBytes,
      quotaBytes,
      freeBytes,
    };
  });
}
