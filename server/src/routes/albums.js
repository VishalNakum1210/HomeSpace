import crypto from 'node:crypto';

export async function albumRoutes(fastify, options) {
  const { db } = options;

  // Authenticate all album routes
  fastify.addHook('preHandler', fastify.authenticate);

  // Helper: check user permission on album (owner, contributor, or viewer)
  function getAlbumMembership(albumId, userId) {
    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(albumId);
    if (!album) return null;

    if (album.owner_id === userId) {
      return { album, role: 'owner', isOwner: true, canEdit: true };
    }

    const membership = db.prepare('SELECT role FROM album_members WHERE album_id = ? AND user_id = ?').get(albumId, userId);
    if (!membership) return null;

    return {
      album,
      role: membership.role,
      isOwner: false,
      canEdit: membership.role === 'contributor',
    };
  }

  // 1. List user's albums (owned + shared)
  fastify.get('/albums', async (req, reply) => {
    const stmt = db.prepare(`
      SELECT 
        a.id, a.owner_id, a.title, a.description, a.cover_media_id,
        a.created_at, a.updated_at,
        CASE WHEN a.owner_id = ? THEN 'owner' ELSE m.role END as user_role,
        (SELECT COUNT(*) FROM album_media am WHERE am.album_id = a.id) as media_count
      FROM albums a
      LEFT JOIN album_members m ON a.id = m.album_id AND m.user_id = ?
      WHERE a.owner_id = ? OR m.user_id = ?
      ORDER BY a.created_at DESC
    `);

    const rows = stmt.all(req.user.id, req.user.id, req.user.id, req.user.id);

    return {
      albums: rows.map(r => ({
        id: r.id,
        ownerId: r.owner_id,
        title: r.title,
        description: r.description,
        coverMediaId: r.cover_media_id,
        createdAt: r.created_at,
        updatedAt: r.updated_at,
        userRole: r.user_role,
        mediaCount: Number(r.media_count),
      })),
    };
  });

  // 2. Create album
  fastify.post('/albums', async (req, reply) => {
    const { title, description = '', coverMediaId, mediaIds = [] } = req.body || {};

    if (!title || typeof title !== 'string' || !title.trim()) {
      return reply.code(400).send({
        error: { code: 'INVALID_TITLE', message: 'Album title is required' },
      });
    }

    const albumId = 'alb_' + crypto.randomBytes(8).toString('hex');
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO albums (id, owner_id, title, description, cover_media_id, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?)
    `).run(albumId, req.user.id, title.trim(), description.trim(), coverMediaId || null, now, now);

    // Add initial media items if provided
    if (Array.isArray(mediaIds) && mediaIds.length > 0) {
      const addStmt = db.prepare('INSERT OR IGNORE INTO album_media (album_id, media_id, added_at) VALUES (?, ?, ?)');
      for (const mId of mediaIds) {
        addStmt.run(albumId, mId, now);
      }
    }

    return reply.code(201).send({
      id: albumId,
      ownerId: req.user.id,
      title: title.trim(),
      description: description.trim(),
      coverMediaId: coverMediaId || null,
      createdAt: now,
      updatedAt: now,
      userRole: 'owner',
      mediaCount: mediaIds.length,
    });
  });

  // 3. Get album details with items & members
  fastify.get('/albums/:id', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found or access denied' },
      });
    }

    const { album, role } = access;

    // Photos in this album
    const mediaRows = db.prepare(`
      SELECT m.*, am.added_at
      FROM album_media am
      JOIN media m ON am.media_id = m.id
      WHERE am.album_id = ? AND m.is_trashed = 0
      ORDER BY am.added_at DESC
    `).all(album.id);

    // Members of this album
    const members = db.prepare(`
      SELECT u.id, u.name, u.email, u.avatar_tone, mem.role, mem.invited_at
      FROM album_members mem
      JOIN users u ON mem.user_id = u.id
      WHERE mem.album_id = ?
    `).all(album.id);

    // Include album owner in members list
    const owner = db.prepare('SELECT id, name, email, avatar_tone FROM users WHERE id = ?').get(album.owner_id);

    return {
      album: {
        id: album.id,
        ownerId: album.owner_id,
        title: album.title,
        description: album.description,
        coverMediaId: album.cover_media_id,
        createdAt: album.created_at,
        updatedAt: album.updated_at,
        userRole: role,
      },
      media: mediaRows.map(r => ({
        id: r.id,
        userId: r.user_id,
        fileName: r.file_name,
        mimeType: r.mime_type,
        byteSize: Number(r.byte_size),
        width: r.width,
        height: r.height,
        takenAt: r.taken_at,
        createdAt: r.created_at,
        isFavorite: Boolean(r.is_favorite),
      })),
      members: [
        {
          id: owner.id,
          name: owner.name,
          email: owner.email,
          avatarTone: owner.avatar_tone,
          role: 'owner',
        },
        ...members.map(m => ({
          id: m.id,
          name: m.name,
          email: m.email,
          avatarTone: m.avatar_tone,
          role: m.role,
        })),
      ],
    };
  });

  // 4. Update album (owner or contributor)
  fastify.patch('/albums/:id', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access || !access.canEdit) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You do not have permission to edit this album' },
      });
    }

    const { title, description, coverMediaId } = req.body || {};
    const now = new Date().toISOString();

    const updates = [];
    const params = [];

    if (title !== undefined) {
      if (!title || !title.trim()) {
        return reply.code(400).send({ error: { code: 'INVALID_TITLE', message: 'Title cannot be empty' } });
      }
      updates.push('title = ?');
      params.push(title.trim());
    }

    if (description !== undefined) {
      updates.push('description = ?');
      params.push(description.trim());
    }

    if (coverMediaId !== undefined) {
      updates.push('cover_media_id = ?');
      params.push(coverMediaId);
    }

    if (updates.length > 0) {
      updates.push('updated_at = ?');
      params.push(now);
      params.push(req.params.id);
      db.prepare(`UPDATE albums SET ${updates.join(', ')} WHERE id = ?`).run(...params);
    }

    const updated = db.prepare('SELECT * FROM albums WHERE id = ?').get(req.params.id);

    return {
      id: updated.id,
      title: updated.title,
      description: updated.description,
      coverMediaId: updated.cover_media_id,
      updatedAt: updated.updated_at,
    };
  });

  // 5. Delete album (owner only)
  fastify.delete('/albums/:id', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Album not found' } });
    }

    if (!access.isOwner) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Only the album owner can delete it' } });
    }

    // Cascade deletes album_media and album_members, keeps media items in library!
    db.prepare('DELETE FROM albums WHERE id = ?').run(req.params.id);

    return { deleted: true, id: req.params.id };
  });

  // 6. Add media to album (owner or contributor)
  fastify.post('/albums/:id/media', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access || !access.canEdit) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Cannot add media to this album' } });
    }

    const mediaIds = Array.isArray(req.body?.mediaIds) ? req.body.mediaIds : [];
    if (!mediaIds.length) return { addedCount: 0 };

    const now = new Date().toISOString();
    let count = 0;
    const stmt = db.prepare('INSERT OR IGNORE INTO album_media (album_id, media_id, added_at) VALUES (?, ?, ?)');

    for (const mId of mediaIds) {
      const res = stmt.run(req.params.id, mId, now);
      if (res.changes > 0) count++;
    }

    return { addedCount: count };
  });

  // 7. Remove media from album
  fastify.delete('/albums/:id/media/:mediaId', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access || !access.canEdit) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Cannot modify this album' } });
    }

    db.prepare('DELETE FROM album_media WHERE album_id = ? AND media_id = ?').run(req.params.id, req.params.mediaId);

    return { removed: true, mediaId: req.params.mediaId };
  });

  // 8. Add/Invite member by email
  fastify.post('/albums/:id/members', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access || !access.isOwner) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Only album owner can manage members' } });
    }

    const { email, role = 'viewer' } = req.body || {};
    if (!email || typeof email !== 'string') {
      return reply.code(400).send({ error: { code: 'INVALID_EMAIL', message: 'User email is required' } });
    }

    const user = db.prepare('SELECT id, name, email, avatar_tone FROM users WHERE email = ?').get(email.trim().toLowerCase());
    if (!user) {
      return reply.code(404).send({ error: { code: 'USER_NOT_FOUND', message: 'No registered user found with that email' } });
    }

    if (user.id === req.user.id) {
      return reply.code(400).send({ error: { code: 'INVALID_MEMBER', message: 'Owner is already a member' } });
    }

    const cleanRole = role === 'contributor' ? 'contributor' : 'viewer';
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO album_members (album_id, user_id, role, invited_at)
      VALUES (?, ?, ?, ?)
      ON CONFLICT(album_id, user_id) DO UPDATE SET role = ?
    `).run(req.params.id, user.id, cleanRole, now, cleanRole);

    return {
      member: {
        id: user.id,
        name: user.name,
        email: user.email,
        avatarTone: user.avatar_tone,
        role: cleanRole,
      },
    };
  });

  // 9. Update member role (owner only)
  fastify.patch('/albums/:id/members/:userId', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access || !access.isOwner) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Only album owner can manage member roles' } });
    }

    const { role } = req.body || {};
    const cleanRole = role === 'contributor' ? 'contributor' : 'viewer';

    db.prepare('UPDATE album_members SET role = ? WHERE album_id = ? AND user_id = ?')
      .run(cleanRole, req.params.id, req.params.userId);

    return { userId: req.params.userId, role: cleanRole };
  });

  // 10. Remove member (owner or member removing self)
  fastify.delete('/albums/:id/members/:userId', async (req, reply) => {
    const access = getAlbumMembership(req.params.id, req.user.id);
    if (!access) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Album not found' } });
    }

    const targetUserId = req.params.userId;
    if (!access.isOwner && req.user.id !== targetUserId) {
      return reply.code(403).send({ error: { code: 'FORBIDDEN', message: 'Cannot remove another member' } });
    }

    db.prepare('DELETE FROM album_members WHERE album_id = ? AND user_id = ?').run(req.params.id, targetUserId);

    return { removed: true, userId: targetUserId };
  });
}
