import crypto from 'node:crypto';

export async function albumsRoutes(fastify, options) {
  const { db } = options;

  const getMembersStmt = db.prepare(`
    SELECT am.user_id, am.role, am.added_by, am.created_at, u.name, u.avatar_tone
    FROM album_members am
    JOIN users u ON am.user_id = u.id
    WHERE am.album_id = ?
    ORDER BY am.created_at ASC
  `);

  const getMediaIdsStmt = db.prepare(
    'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC'
  );

  function toAlbumDto(row, mediaIds = [], members = [], extraMedia = undefined) {
    const dto = {
      id: row.id,
      userId: row.user_id,
      title: row.title,
      description: row.description || '',
      coverMediaId: row.cover_media_id || null,
      isShared: Boolean(row.is_shared),
      mediaCount: mediaIds.length,
      mediaIds,
      memberships: members.map((m) => ({
        userId: m.user_id,
        role: m.role === 'contributor' ? 'contributor' : 'viewer',
        name: m.name,
        avatarTone: m.avatar_tone,
        addedBy: m.added_by || null,
        createdAt: m.created_at,
      })),
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
    if (extraMedia !== undefined) {
      dto.media = extraMedia;
    }
    return dto;
  }

  function loadAlbumMediaItems(albumId) {
    return db.prepare(`
      SELECT m.*
      FROM album_media am
      JOIN media m ON m.id = am.media_id
      WHERE am.album_id = ? AND m.is_trashed = 0
      ORDER BY am.added_at DESC
    `).all(albumId).map((row) => ({
      id: row.id,
      userId: row.user_id,
      filename: row.filename,
      mimeType: row.mime_type,
      size: Number(row.size_bytes),
      takenAt: row.taken_at,
      kind: row.kind,
      isFavorite: Boolean(row.is_favorite),
      isTrashed: Boolean(row.is_trashed),
      trashedAt: row.trashed_at || null,
      isSynced: true,
      thumbUrl: `/api/media/${row.id}/thumb`,
      fileUrl: `/api/media/${row.id}/file`,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    }));
  }

  function canViewAlbum(album, userId, members) {
    if (album.user_id === userId) return true;
    if (members.length > 0) {
      return members.some((m) => m.user_id === userId);
    }
    return Boolean(album.is_shared);
  }

  function canEditAlbumMedia(album, userId, members) {
    if (album.user_id === userId) return true;
    const member = members.find((m) => m.user_id === userId);
    return Boolean(member && member.role === 'contributor');
  }

  function canUserAttachMedia(mediaId, userId, albumId = null) {
    const media = db.prepare('SELECT id, user_id, is_trashed FROM media WHERE id = ?').get(mediaId);
    if (!media || media.is_trashed) return { ok: false, reason: 'NOT_FOUND' };
    if (media.user_id === userId) return { ok: true };
    if (albumId) {
      const inAlbum = db.prepare('SELECT 1 FROM album_media WHERE album_id = ? AND media_id = ?').get(albumId, mediaId);
      if (inAlbum) return { ok: true };
    }
    // Or already accessible to user via another shared album
    const viaShared = db.prepare(`
      SELECT 1
      FROM album_media am
      JOIN albums a ON a.id = am.album_id
      WHERE am.media_id = ?
        AND (
          a.user_id = ?
          OR EXISTS (SELECT 1 FROM album_members mem WHERE mem.album_id = a.id AND mem.user_id = ?)
          OR (a.is_shared = 1 AND NOT EXISTS (SELECT 1 FROM album_members mem2 WHERE mem2.album_id = a.id))
        )
      LIMIT 1
    `).get(mediaId, userId, userId);
    return viaShared ? { ok: true } : { ok: false, reason: 'FORBIDDEN' };
  }

  function normalizeMembershipsInput(rawMemberships, ownerId) {
    if (!Array.isArray(rawMemberships)) return { error: 'memberships must be an array' };
    const dedup = new Map();
    for (const entry of rawMemberships) {
      if (!entry || typeof entry !== 'object') continue;
      const targetUserId = typeof entry.userId === 'string' ? entry.userId.trim() : '';
      if (!targetUserId || targetUserId === ownerId) continue;
      const role = entry.role === 'contributor' ? 'contributor' : 'viewer';
      dedup.set(targetUserId, role);
    }
    const resolved = [];
    for (const [targetUserId, role] of dedup.entries()) {
      const exists = db.prepare('SELECT id FROM users WHERE id = ?').get(targetUserId);
      if (!exists) {
        return { error: `Unknown userId in memberships: ${targetUserId}` };
      }
      resolved.push({ userId: targetUserId, role });
    }
    return { memberships: resolved };
  }

  // 1. GET /albums - List albums accessible to current user
  fastify.get('/albums', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const userId = req.user.id;
    const isSharedOnly = req.query?.shared === 'true' || req.query?.shared === '1';
    const includeMedia = req.query?.includeMedia === 'true' || req.query?.includeMedia === '1';

    let sql = `
      SELECT * FROM albums a
      WHERE (
        a.user_id = ?
        OR EXISTS (SELECT 1 FROM album_members am WHERE am.album_id = a.id AND am.user_id = ?)
        OR (a.is_shared = 1 AND NOT EXISTS (SELECT 1 FROM album_members am2 WHERE am2.album_id = a.id))
      )
    `;
    const params = [userId, userId];

    if (isSharedOnly) {
      sql += ' AND (a.is_shared = 1 OR EXISTS (SELECT 1 FROM album_members am3 WHERE am3.album_id = a.id))';
    }

    sql += ' ORDER BY a.updated_at DESC, a.id DESC';
    const albumRows = db.prepare(sql).all(...params);

    const albums = albumRows.map((row) => {
      const mediaIds = getMediaIdsStmt.all(row.id).map((m) => m.media_id);
      const members = getMembersStmt.all(row.id);
      const extraMedia = includeMedia ? loadAlbumMediaItems(row.id) : undefined;
      return toAlbumDto(row, mediaIds, members, extraMedia);
    });

    return { albums, total: albums.length };
  });

  // 2. GET /albums/:id - Get single album details with media IDs & members
  fastify.get('/albums/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const includeMedia = req.query?.includeMedia === 'true' || req.query?.includeMedia === '1';

    const row = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    const members = getMembersStmt.all(id);
    if (!canViewAlbum(row, userId, members)) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You do not have access to this album' },
      });
    }

    const mediaIds = getMediaIdsStmt.all(id).map((m) => m.media_id);
    const extraMedia = includeMedia ? loadAlbumMediaItems(id) : undefined;

    return { album: toAlbumDto(row, mediaIds, members, extraMedia) };
  });

  // 3. POST /albums - Create new album
  fastify.post('/albums', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const userId = req.user.id;
    const {
      id: customId,
      title,
      description,
      coverMediaId,
      mediaIds = [],
      isShared = false,
      memberships,
    } = req.body || {};

    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      return reply.code(400).send({
        error: { code: 'INVALID_TITLE', message: 'Album title is required' },
      });
    }

    const albumId = (customId && typeof customId === 'string' && customId.trim())
      ? customId.trim().substring(0, 64)
      : `album-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const cleanTitle = title.trim().substring(0, 80);
    const cleanDesc = (description || '').toString().trim().substring(0, 4096);
    const nowIso = new Date().toISOString();

    const insertMediaIds = Array.isArray(mediaIds)
      ? [...new Set(mediaIds.filter((m) => typeof m === 'string' && m.trim()).map((m) => m.trim()))]
      : [];

    for (const mid of insertMediaIds) {
      const check = canUserAttachMedia(mid, userId);
      if (!check.ok) {
        return reply.code(check.reason === 'FORBIDDEN' ? 403 : 400).send({
          error: { code: check.reason, message: `Media ${mid} cannot be added to album` },
        });
      }
    }

    let resolvedCover = typeof coverMediaId === 'string' && coverMediaId.trim() ? coverMediaId.trim() : null;
    if (resolvedCover) {
      const coverCheck = canUserAttachMedia(resolvedCover, userId);
      if (!coverCheck.ok) {
        return reply.code(coverCheck.reason === 'FORBIDDEN' ? 403 : 400).send({
          error: { code: coverCheck.reason, message: `Cover media ${resolvedCover} is not accessible` },
        });
      }
    } else if (insertMediaIds.length > 0) {
      resolvedCover = insertMediaIds[0];
    }

    let normalizedMembers = [];
    if (memberships !== undefined) {
      const res = normalizeMembershipsInput(memberships, userId);
      if (res.error) {
        return reply.code(400).send({ error: { code: 'INVALID_MEMBERSHIPS', message: res.error } });
      }
      normalizedMembers = res.memberships;
    }
    const effectiveShared = Boolean(isShared || normalizedMembers.length > 0);

    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare(`
        INSERT INTO albums (id, user_id, title, description, cover_media_id, is_shared, created_at, updated_at)
        VALUES (?, ?, ?, ?, ?, ?, ?, ?)
      `).run(
        albumId,
        userId,
        cleanTitle,
        cleanDesc,
        resolvedCover || null,
        effectiveShared ? 1 : 0,
        nowIso,
        nowIso
      );

      if (insertMediaIds.length > 0) {
        const insertStmt = db.prepare(
          'INSERT OR IGNORE INTO album_media (album_id, media_id, added_at) VALUES (?, ?, ?)'
        );
        for (const mid of insertMediaIds) {
          insertStmt.run(albumId, mid, nowIso);
        }
      }

      if (normalizedMembers.length > 0) {
        const memberStmt = db.prepare(
          'INSERT OR REPLACE INTO album_members (album_id, user_id, role, added_by, created_at) VALUES (?, ?, ?, ?, ?)'
        );
        for (const m of normalizedMembers) {
          memberStmt.run(albumId, m.userId, m.role, userId, nowIso);
        }
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      if (String(e?.message || '').includes('UNIQUE')) {
        return reply.code(409).send({
          error: { code: 'ALBUM_EXISTS', message: 'An album with this ID already exists' },
        });
      }
      throw e;
    }

    const createdRow = db.prepare('SELECT * FROM albums WHERE id = ?').get(albumId);
    const members = getMembersStmt.all(albumId);
    return reply.code(201).send({
      album: toAlbumDto(createdRow, insertMediaIds, members),
    });
  });

  // 4. POST /albums/:id/media - Add media items to album (Pointer-based, 0 byte duplication)
  fastify.post('/albums/:id/media', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const { mediaIds = [] } = req.body || {};

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    const members = getMembersStmt.all(id);
    if (!canEditAlbumMedia(album, userId, members)) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You cannot add to this album' },
      });
    }

    if (!Array.isArray(mediaIds) || mediaIds.length === 0) {
      return { success: true, count: 0, albumId: id };
    }

    const uniqueIds = [...new Set(mediaIds.filter((m) => typeof m === 'string' && m.trim()).map((m) => m.trim()))];
    for (const mid of uniqueIds) {
      const check = canUserAttachMedia(mid, userId, id);
      if (!check.ok) {
        return reply.code(check.reason === 'FORBIDDEN' ? 403 : 400).send({
          error: { code: check.reason, message: `Media ${mid} cannot be added to album` },
        });
      }
    }

    const nowIso = new Date().toISOString();

    db.exec('BEGIN IMMEDIATE;');
    let addedCount = 0;
    try {
      const insertStmt = db.prepare(
        'INSERT OR IGNORE INTO album_media (album_id, media_id, added_at) VALUES (?, ?, ?)'
      );
      for (const mid of uniqueIds) {
        const info = insertStmt.run(id, mid, nowIso);
        if (info.changes > 0) addedCount++;
      }

      // If album had no cover, set to first added
      if (!album.cover_media_id && uniqueIds.length > 0) {
        db.prepare('UPDATE albums SET cover_media_id = ?, updated_at = ? WHERE id = ?')
          .run(uniqueIds[0], nowIso, id);
      } else {
        db.prepare('UPDATE albums SET updated_at = ? WHERE id = ?').run(nowIso, id);
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    return { success: true, count: addedCount, albumId: id };
  });

  // 5. DELETE /albums/:id/media/:mediaId - Remove single media from album
  fastify.delete('/albums/:id/media/:mediaId', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id, mediaId } = req.params;
    const userId = req.user.id;

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    const members = getMembersStmt.all(id);
    if (!canEditAlbumMedia(album, userId, members)) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You cannot modify this album' },
      });
    }

    const nowIso = new Date().toISOString();
    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare('DELETE FROM album_media WHERE album_id = ? AND media_id = ?').run(id, mediaId);

      if (album.cover_media_id === mediaId) {
        const nextCover = db.prepare(
          'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC LIMIT 1'
        ).get(id);
        db.prepare('UPDATE albums SET cover_media_id = ?, updated_at = ? WHERE id = ?')
          .run(nextCover ? nextCover.media_id : null, nowIso, id);
      } else {
        db.prepare('UPDATE albums SET updated_at = ? WHERE id = ?').run(nowIso, id);
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    return { success: true, removedId: mediaId, albumId: id };
  });

  // 6. POST /albums/:id/media/remove - Bulk remove media from album
  fastify.post('/albums/:id/media/remove', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const { mediaIds = [] } = req.body || {};

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    const members = getMembersStmt.all(id);
    if (!canEditAlbumMedia(album, userId, members)) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You cannot modify this album' },
      });
    }

    if (!Array.isArray(mediaIds) || mediaIds.length === 0) {
      return { success: true, count: 0, albumId: id };
    }

    const nowIso = new Date().toISOString();
    db.exec('BEGIN IMMEDIATE;');
    let removedCount = 0;
    try {
      const deleteStmt = db.prepare('DELETE FROM album_media WHERE album_id = ? AND media_id = ?');
      for (const mid of mediaIds) {
        const info = deleteStmt.run(id, mid);
        if (info.changes > 0) removedCount++;
      }

      if (mediaIds.includes(album.cover_media_id)) {
        const nextCover = db.prepare(
          'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC LIMIT 1'
        ).get(id);
        db.prepare('UPDATE albums SET cover_media_id = ?, updated_at = ? WHERE id = ?')
          .run(nextCover ? nextCover.media_id : null, nowIso, id);
      } else {
        db.prepare('UPDATE albums SET updated_at = ? WHERE id = ?').run(nowIso, id);
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    return { success: true, count: removedCount, albumId: id };
  });

  // 7. PATCH /albums/:id - Update album title, description, cover, sharing, or memberships
  fastify.patch('/albums/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const { title, description, coverMediaId, isShared, memberships } = req.body || {};

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    if (album.user_id !== userId) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Only the album owner can edit settings' },
      });
    }

    if (coverMediaId !== undefined && coverMediaId !== null) {
      const coverCheck = canUserAttachMedia(String(coverMediaId), userId, id);
      if (!coverCheck.ok) {
        return reply.code(coverCheck.reason === 'FORBIDDEN' ? 403 : 400).send({
          error: { code: coverCheck.reason, message: 'Invalid or inaccessible coverMediaId' },
        });
      }
    }

    let normalizedMembers;
    if (memberships !== undefined) {
      const res = normalizeMembershipsInput(memberships, userId);
      if (res.error) {
        return reply.code(400).send({ error: { code: 'INVALID_MEMBERSHIPS', message: res.error } });
      }
      normalizedMembers = res.memberships;
    }

    const updates = [];
    const params = [];
    const nowIso = new Date().toISOString();

    if (typeof title === 'string' && title.trim().length > 0) {
      updates.push('title = ?');
      params.push(title.trim().substring(0, 80));
    }
    if (typeof description === 'string') {
      updates.push('description = ?');
      params.push(description.trim().substring(0, 4096));
    }
    if (coverMediaId !== undefined) {
      updates.push('cover_media_id = ?');
      params.push(coverMediaId);
    }
    if (isShared !== undefined) {
      updates.push('is_shared = ?');
      params.push(isShared ? 1 : 0);
    } else if (normalizedMembers && normalizedMembers.length > 0) {
      updates.push('is_shared = ?');
      params.push(1);
    }

    db.exec('BEGIN IMMEDIATE;');
    try {
      if (updates.length > 0 || normalizedMembers !== undefined) {
        updates.push('updated_at = ?');
        params.push(nowIso);
        params.push(id);
        db.prepare(`UPDATE albums SET ${updates.join(', ')} WHERE id = ?`).run(...params);
      }

      if (normalizedMembers !== undefined) {
        db.prepare('DELETE FROM album_members WHERE album_id = ?').run(id);
        const insertMember = db.prepare(
          'INSERT INTO album_members (album_id, user_id, role, added_by, created_at) VALUES (?, ?, ?, ?, ?)'
        );
        for (const m of normalizedMembers) {
          insertMember.run(id, m.userId, m.role, userId, nowIso);
        }
      }
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    const updated = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    const mediaIds = getMediaIdsStmt.all(id).map((m) => m.media_id);
    const members = getMembersStmt.all(id);

    return { album: toAlbumDto(updated, mediaIds, members) };
  });

  // 7b. PUT /albums/:id/members - Replace shared album member list (Owner only)
  fastify.put('/albums/:id/members', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const { memberships = [] } = req.body || {};

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Album not found' } });
    }
    if (album.user_id !== userId) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Only the album owner can manage members' },
      });
    }

    const res = normalizeMembershipsInput(memberships, userId);
    if (res.error) {
      return reply.code(400).send({ error: { code: 'INVALID_MEMBERSHIPS', message: res.error } });
    }

    const nowIso = new Date().toISOString();
    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare('DELETE FROM album_members WHERE album_id = ?').run(id);
      const insertMember = db.prepare(
        'INSERT INTO album_members (album_id, user_id, role, added_by, created_at) VALUES (?, ?, ?, ?, ?)'
      );
      for (const m of res.memberships) {
        insertMember.run(id, m.userId, m.role, userId, nowIso);
      }
      db.prepare('UPDATE albums SET is_shared = ?, updated_at = ? WHERE id = ?')
        .run(res.memberships.length > 0 ? 1 : album.is_shared, nowIso, id);
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    const updated = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    const mediaIds = getMediaIdsStmt.all(id).map((m) => m.media_id);
    const members = getMembersStmt.all(id);
    return { album: toAlbumDto(updated, mediaIds, members) };
  });

  // 7c. DELETE /albums/:id/members/:memberId - Remove member (Owner or member removing self)
  fastify.delete('/albums/:id/members/:memberId', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id, memberId } = req.params;
    const userId = req.user.id;
    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Album not found' } });
    }
    if (album.user_id !== userId && memberId !== userId) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Only the album owner or the member can remove access' },
      });
    }
    db.prepare('DELETE FROM album_members WHERE album_id = ? AND user_id = ?').run(id, memberId);
    db.prepare('UPDATE albums SET updated_at = ? WHERE id = ?').run(new Date().toISOString(), id);
    return { success: true, albumId: id, removedUserId: memberId };
  });

  // 8. DELETE /albums/:id - Delete album container (Preserves original media 100%)
  fastify.delete('/albums/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;

    const album = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!album) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    if (album.user_id !== userId) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'Only the owner can delete this album' },
      });
    }

    db.prepare('DELETE FROM albums WHERE id = ?').run(id);

    return { success: true, deletedId: id };
  });
}
