import crypto from 'node:crypto';

export async function albumsRoutes(fastify, options) {
  const { db } = options;

  function toAlbumDto(row, mediaIds = []) {
    return {
      id: row.id,
      userId: row.user_id,
      title: row.title,
      description: row.description || '',
      coverMediaId: row.cover_media_id || null,
      isShared: Boolean(row.is_shared),
      mediaCount: mediaIds.length,
      mediaIds: mediaIds,
      createdAt: row.created_at,
      updatedAt: row.updated_at,
    };
  }

  // 1. GET /albums - List albums for current user (or shared albums)
  fastify.get('/albums', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const userId = req.user.id;
    const isSharedOnly = req.query?.shared === 'true' || req.query?.shared === '1';

    let sql = 'SELECT * FROM albums WHERE (user_id = ? OR is_shared = 1)';
    const params = [userId];

    if (isSharedOnly) {
      sql = 'SELECT * FROM albums WHERE is_shared = 1';
      params.length = 0;
    }

    sql += ' ORDER BY updated_at DESC, id DESC';
    const albumRows = db.prepare(sql).all(...params);

    const getMediaIdsStmt = db.prepare(
      'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC'
    );

    const albums = albumRows.map((row) => {
      const mediaRows = getMediaIdsStmt.all(row.id);
      const mediaIds = mediaRows.map((m) => m.media_id);
      return toAlbumDto(row, mediaIds);
    });

    return { albums, total: albums.length };
  });

  // 2. GET /albums/:id - Get single album details with media IDs
  fastify.get('/albums/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;

    const row = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Album not found' },
      });
    }

    if (row.user_id !== userId && !row.is_shared) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You do not have access to this album' },
      });
    }

    const mediaRows = db.prepare(
      'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC'
    ).all(id);
    const mediaIds = mediaRows.map((m) => m.media_id);

    return { album: toAlbumDto(row, mediaIds) };
  });

  // 3. POST /albums - Create new album
  fastify.post('/albums', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const userId = req.user.id;
    const { id: customId, title, description, coverMediaId, mediaIds = [], isShared = false } = req.body || {};

    if (!title || typeof title !== 'string' || title.trim().length === 0) {
      return reply.code(400).send({
        error: { code: 'INVALID_TITLE', message: 'Album title is required' },
      });
    }

    const albumId = (customId && typeof customId === 'string' && customId.trim())
      ? customId.trim()
      : `album-${Date.now()}-${crypto.randomBytes(4).toString('hex')}`;
    const cleanTitle = title.trim().substring(0, 80);
    const cleanDesc = (description || '').toString().trim().substring(0, 4096);
    const nowIso = new Date().toISOString();

    const insertMediaIds = Array.isArray(mediaIds) ? [...new Set(mediaIds)] : [];
    let resolvedCover = coverMediaId;
    if (!resolvedCover && insertMediaIds.length > 0) {
      resolvedCover = insertMediaIds[0];
    }

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
        isShared ? 1 : 0,
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

      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }

    const createdRow = db.prepare('SELECT * FROM albums WHERE id = ?').get(albumId);
    return reply.code(201).send({
      album: toAlbumDto(createdRow, insertMediaIds),
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

    if (album.user_id !== userId && !album.is_shared) {
      return reply.code(403).send({
        error: { code: 'FORBIDDEN', message: 'You cannot add to this album' },
      });
    }

    if (!Array.isArray(mediaIds) || mediaIds.length === 0) {
      return { success: true, count: 0, albumId: id };
    }

    const uniqueIds = [...new Set(mediaIds)];
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
      db.exec('ROLLBACK;');
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

    if (album.user_id !== userId && !album.is_shared) {
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
      db.exec('ROLLBACK;');
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

    if (album.user_id !== userId && !album.is_shared) {
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
      db.exec('ROLLBACK;');
      throw e;
    }

    return { success: true, count: removedCount, albumId: id };
  });

  // 7. PATCH /albums/:id - Update album title, description, cover, or sharing
  fastify.patch('/albums/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const { title, description, coverMediaId, isShared } = req.body || {};

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
    }

    if (updates.length > 0) {
      updates.push('updated_at = ?');
      params.push(nowIso);
      params.push(id);
      db.prepare(`UPDATE albums SET ${updates.join(', ')} WHERE id = ?`).run(...params);
    }

    const updated = db.prepare('SELECT * FROM albums WHERE id = ?').get(id);
    const mediaRows = db.prepare(
      'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC'
    ).all(id);
    const mediaIds = mediaRows.map((m) => m.media_id);

    return { album: toAlbumDto(updated, mediaIds) };
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
