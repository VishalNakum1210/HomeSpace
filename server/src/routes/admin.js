import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { hashPassword } from '../auth.js';

const EMAIL_REGEX = /^[^\s@]+@[^\s@]+\.[^\s@]+$/;

export async function adminRoutes(fastify, options) {
  const { db, defaultQuotaBytes = 15 * 1024 * 1024 * 1024, dataDir = 'data' } = options;

  // Middleware: require authentication and admin privileges
  const requireAdmin = async (req, reply) => {
    await fastify.authenticate(req, reply);
    if (reply.sent) return;

    if (!req.user || !req.user.is_admin) {
      return reply.code(403).send({
        error: {
          code: 'FORBIDDEN',
          message: 'Admin access required for family account management.',
        },
      });
    }
  };

  // 1. List all family users
  fastify.get('/admin/users', { preHandler: [requireAdmin] }, async (req, reply) => {
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
      isAdmin ? 1 : 0,
      storageQuotaBytes,
      now,
      now,
    );

    return reply.code(201).send({
      user: {
        id: userId,
        email: normalizedEmail,
        name: name.trim(),
        avatarTone,
        isAdmin: Boolean(isAdmin),
        storageQuotaBytes: Number(storageQuotaBytes),
        storageUsedBytes: 0,
        createdAt: now,
      },
    });
  });

  // 3. Update family user account
  fastify.patch('/admin/users/:id', { preHandler: [requireAdmin] }, async (req, reply) => {
    const { id } = req.params;
    const { name, avatarTone, storageQuotaBytes, isAdmin } = req.body || {};

    const targetUser = db.prepare('SELECT id, is_admin FROM users WHERE id = ?').get(id);
    if (!targetUser) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found.' },
      });
    }

    // Safety: prevent demoting oneself if the caller is the last admin
    if (id === req.user.id && isAdmin === false) {
      const adminCount = db.prepare('SELECT COUNT(*) as count FROM users WHERE is_admin = 1').get().count;
      if (adminCount <= 1) {
        return reply.code(400).send({
          error: { code: 'CANNOT_DEMOTE_LAST_ADMIN', message: 'Cannot demote the last administrator.' },
        });
      }
    }

    const updates = [];
    const values = [];

    if (name && typeof name === 'string' && name.trim()) {
      updates.push('name = ?');
      values.push(name.trim());
    }
    if (avatarTone && typeof avatarTone === 'string') {
      updates.push('avatar_tone = ?');
      values.push(avatarTone);
    }
    if (storageQuotaBytes !== undefined && typeof storageQuotaBytes === 'number' && storageQuotaBytes > 0) {
      updates.push('storage_quota_bytes = ?');
      values.push(storageQuotaBytes);
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

    const targetUser = db.prepare('SELECT id FROM users WHERE id = ?').get(id);
    if (!targetUser) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found.' },
      });
    }

    // Cascade delete user in DB (FK cascades to sessions, media, albums, album_media)
    db.prepare('DELETE FROM users WHERE id = ?').run(id);

    // Clean up physical directory for user if exists
    try {
      const userDir = path.join(dataDir, 'users', id);
      if (fs.existsSync(userDir)) {
        fs.rmSync(userDir, { recursive: true, force: true });
      }
    } catch (_) {}

    return { success: true };
  });

  // 5. Storage stats breakdown for current user
  fastify.get('/media/storage-breakdown', { preHandler: [fastify.authenticate] }, async (req, reply) => {
    const rows = db.prepare(`
      SELECT kind, COUNT(*) as count, COALESCE(SUM(size_bytes), 0) as total_bytes
      FROM media
      WHERE user_id = ? AND is_trashed = 0
      GROUP BY kind
    `).all(req.user.id);

    let photosBytes = 0;
    let videosBytes = 0;
    for (const r of rows) {
      if (r.kind === 'video') {
        videosBytes = Number(r.total_bytes);
      } else {
        photosBytes += Number(r.total_bytes);
      }
    }

    const totalUsedBytes = Number(req.user.storage_used_bytes || (photosBytes + videosBytes));
    const quotaBytes = Number(req.user.storage_quota_bytes || defaultQuotaBytes);
    const freeBytes = Math.max(0, quotaBytes - totalUsedBytes);

    return {
      photosBytes,
      videosBytes,
      totalUsedBytes,
      quotaBytes,
      freeBytes,
    };
  });
}
