import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { Transform } from 'node:stream';
import { execFile } from 'node:child_process';
import sharp from 'sharp';

function tryExtractVideoThumbnail(videoPath, thumbPath) {
  return new Promise((resolve) => {
    // scale=480:-2 ensures height is an even number, avoiding ffmpeg scale filter error
    execFile(
      'ffmpeg',
      ['-y', '-ss', '00:00:00.500', '-i', videoPath, '-vframes', '1', '-vf', 'scale=480:-2', thumbPath],
      (err) => {
        if (err) {
          execFile(
            'ffmpeg',
            ['-y', '-i', videoPath, '-vframes', '1', '-vf', 'scale=480:-2', thumbPath],
            (err2) => {
              if (err2) {
                resolve(false);
              } else {
                resolve(fs.existsSync(thumbPath) && fs.statSync(thumbPath).size > 0);
              }
            }
          );
        } else {
          resolve(fs.existsSync(thumbPath) && fs.statSync(thumbPath).size > 0);
        }
      }
    );
  });
}

export async function mediaRoutes(fastify, options) {
  const { db, dataDir } = options;

  function toMediaItem(row) {
    return {
      id: row.id,
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
    };
  }

  // 1. Upload media (single multipart file)
  fastify.post('/media/upload', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const userId = req.user.id;

    // Fast quota pre-check
    const userRow = db.prepare('SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?').get(userId);
    if (!userRow) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }

    const quotaBytes = Number(userRow.storage_quota_bytes);
    const usedBytes = Number(userRow.storage_used_bytes);

    if (usedBytes >= quotaBytes) {
      return reply.code(413).send({
        error: {
          code: 'QUOTA_EXCEEDED',
          message: `Storage quota exceeded (${Math.round(usedBytes / 1e6)}MB of ${Math.round(quotaBytes / 1e6)}MB used)`,
        },
      });
    }

    let part;
    try {
      part = await req.file({ limits: { fileSize: 500 * 1024 * 1024 } });
    } catch (err) {
      return reply.code(400).send({
        error: { code: 'UPLOAD_FAILED', message: err.message },
      });
    }

    if (!part) {
      return reply.code(400).send({
        error: { code: 'NO_FILE_UPLOADED', message: 'No file part found in request body' },
      });
    }

    const originalFilename = part.filename || 'upload.jpg';
    const mimeType = part.mimetype || 'application/octet-stream';

    // Parse takenAt from query parameter, header, or multipart field
    let takenAtStr = req.query?.takenAt || req.headers['x-taken-at'] || part.fields?.takenAt?.value;
    let takenAtDate = takenAtStr ? new Date(takenAtStr) : null;
    if (!takenAtDate || isNaN(takenAtDate.getTime())) {
      takenAtDate = new Date();
    }
    const takenAt = takenAtDate.toISOString();

    const isVideo = mimeType.startsWith('video/') ||
      ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'].some(ext => originalFilename.toLowerCase().endsWith(ext));
    const kind = isVideo ? 'video' : 'photo';

    // File destinations
    const mediaId = 'm_' + crypto.randomBytes(16).toString('hex');
    const ext = path.extname(originalFilename).toLowerCase() || (isVideo ? '.mp4' : '.jpg');

    const userOriginalsDir = path.join(dataDir, 'users', userId, 'originals');
    const userThumbsDir = path.join(dataDir, 'users', userId, 'thumbnails');
    fs.mkdirSync(userOriginalsDir, { recursive: true, mode: 0o700 });
    fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });

    const targetOriginalPath = path.join(userOriginalsDir, `${mediaId}${ext}`);
    const targetThumbPath = path.join(userThumbsDir, `${mediaId}.webp`);

    let bytesWritten = 0;
    const writeStream = fs.createWriteStream(targetOriginalPath);

    // Byte counter transform stream
    const counterStream = new Transform({
      transform(chunk, encoding, callback) {
        bytesWritten += chunk.length;
        if (usedBytes + bytesWritten > quotaBytes) {
          callback(new Error('QUOTA_LIMIT_EXCEEDED'));
        } else {
          callback(null, chunk);
        }
      },
    });

    try {
      await pipeline(part.file, counterStream, writeStream);
    } catch (streamErr) {
      try { writeStream.destroy(); } catch (_) {}
      try { fs.unlinkSync(targetOriginalPath); } catch (_) {}

      if (streamErr.message === 'QUOTA_LIMIT_EXCEEDED' || streamErr.code === 'FST_REQ_FILE_TOO_LARGE') {
        return reply.code(413).send({
          error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while uploading file' },
        });
      }
      return reply.code(500).send({
        error: { code: 'UPLOAD_FAILED', message: streamErr.message },
      });
    }

    // Thumbnail generation
    let thumbnailRelPath = null;
    if (kind === 'photo') {
      try {
        await sharp(targetOriginalPath)
          .rotate() // auto-orient via EXIF
          .resize(480, 480, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 80 })
          .toFile(targetThumbPath);
        thumbnailRelPath = path.posix.join('users', userId, 'thumbnails', `${mediaId}.webp`);
      } catch (sharpErr) {
        // Fallback: original will be served directly if thumb is absent
        thumbnailRelPath = null;
      }
    } else if (kind === 'video') {
      try {
        const hasThumb = await tryExtractVideoThumbnail(targetOriginalPath, targetThumbPath);
        if (hasThumb) {
          thumbnailRelPath = path.posix.join('users', userId, 'thumbnails', `${mediaId}.webp`);
        }
      } catch (_) {
        thumbnailRelPath = null;
      }
    }

    const originalRelPath = path.posix.join('users', userId, 'originals', `${mediaId}${ext}`);
    const nowIso = new Date().toISOString();

    // Database record and storage tally
    db.exec('BEGIN IMMEDIATE;');
    try {
      db.prepare(`
        INSERT INTO media (
          id, user_id, filename, mime_type, size_bytes, taken_at, kind,
          original_path, thumbnail_path, is_favorite, is_trashed, created_at, updated_at
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0, ?, ?)
      `).run(
        mediaId,
        userId,
        originalFilename,
        mimeType,
        bytesWritten,
        takenAt,
        kind,
        originalRelPath,
        thumbnailRelPath,
        nowIso,
        nowIso
      );

      db.prepare(`
        UPDATE users
        SET storage_used_bytes = storage_used_bytes + ?, updated_at = ?
        WHERE id = ?
      `).run(bytesWritten, nowIso, userId);

      db.exec('COMMIT;');
    } catch (dbErr) {
      db.exec('ROLLBACK;');
      try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
      try { if (thumbnailRelPath) fs.unlinkSync(targetThumbPath); } catch (_) {}
      throw dbErr;
    }

    const inserted = db.prepare('SELECT * FROM media WHERE id = ?').get(mediaId);
    return reply.code(201).send({
      media: toMediaItem(inserted),
    });
  });

  // 2. Query timeline media items
  fastify.get('/media', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const userId = req.user.id;
    const limit = Math.min(Math.max(parseInt(req.query?.limit || '100', 10), 1), 500);
    const offset = Math.max(parseInt(req.query?.offset || '0', 10), 0);
    const isFavoriteOnly = req.query?.favorite === 'true' || req.query?.favorite === '1';
    const kindFilter = req.query?.kind; // 'photo' or 'video'
    const isTrashed = req.query?.trashed === 'true' || req.query?.trashed === '1' ? 1 : 0;

    let sql = 'SELECT * FROM media WHERE user_id = ? AND is_trashed = ?';
    const params = [userId, isTrashed];

    if (isFavoriteOnly) {
      sql += ' AND is_favorite = 1';
    }
    if (kindFilter === 'photo' || kindFilter === 'video') {
      sql += ' AND kind = ?';
      params.push(kindFilter);
    }

    sql += ' ORDER BY taken_at DESC, id DESC LIMIT ? OFFSET ?';
    params.push(limit, offset);

    const rows = db.prepare(sql).all(...params);

    const totalCountRow = db.prepare(`
      SELECT COUNT(*) as total FROM media
      WHERE user_id = ? AND is_trashed = ?
      ${isFavoriteOnly ? ' AND is_favorite = 1' : ''}
      ${kindFilter ? ' AND kind = ?' : ''}
    `).get(...[userId, isTrashed, ...(kindFilter ? [kindFilter] : [])]);

    return {
      items: rows.map(toMediaItem),
      total: Number(totalCountRow?.total || 0),
      limit,
      offset,
    };
  });

  // 3. Get single media metadata
  fastify.get('/media/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }
    return { media: toMediaItem(row) };
  });

  // 4. Stream thumbnail
  fastify.get('/media/:id/thumb', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = db.prepare('SELECT id, original_path, thumbnail_path, mime_type, kind FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    if (row.thumbnail_path) {
      const fullThumbPath = path.join(dataDir, row.thumbnail_path);
      if (fs.existsSync(fullThumbPath)) {
        const isJpeg = fullThumbPath.endsWith('.jpg') || fullThumbPath.endsWith('.jpeg');
        reply.header('Content-Type', isJpeg ? 'image/jpeg' : 'image/webp');
        reply.header('Cache-Control', 'public, max-age=31536000, immutable');
        return reply.send(fs.createReadStream(fullThumbPath));
      }
    }

    // Fallback: if photo, stream original as thumb
    if (row.kind === 'photo' && row.original_path) {
      const fullOrigPath = path.join(dataDir, row.original_path);
      if (fs.existsSync(fullOrigPath)) {
        reply.header('Content-Type', row.mime_type || 'image/jpeg');
        reply.header('Cache-Control', 'public, max-age=86400');
        return reply.send(fs.createReadStream(fullOrigPath));
      }
    }

    return reply.code(404).send({
      error: { code: 'THUMBNAIL_NOT_AVAILABLE', message: 'Thumbnail not available' },
    });
  });

  // 4b. Upload / update thumbnail for a media item
  fastify.post('/media/:id/thumb', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const row = db.prepare('SELECT id FROM media WHERE id = ? AND user_id = ?').get(id, userId);
    if (!row) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Media not found' } });
    }

    const part = await req.file();
    if (!part) {
      return reply.code(400).send({ error: { code: 'NO_FILE', message: 'No thumbnail file uploaded' } });
    }

    const userThumbsDir = path.join(dataDir, 'users', userId, 'thumbnails');
    fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });
    const targetThumbPath = path.join(userThumbsDir, `${id}.webp`);
    const writeStream = fs.createWriteStream(targetThumbPath);
    await pipeline(part.file, writeStream);

    const relPath = path.posix.join('users', userId, 'thumbnails', `${id}.webp`);
    db.prepare('UPDATE media SET thumbnail_path = ?, updated_at = ? WHERE id = ?').run(
      relPath,
      new Date().toISOString(),
      id
    );

    return { success: true, thumbUrl: `/api/media/${id}/thumb` };
  });

  // 5. Full file streaming & video Range requests
  async function streamFullFile(req, reply) {
    const { id } = req.params;
    const row = db.prepare('SELECT id, original_path, mime_type, size_bytes FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!row || !row.original_path) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media file not found' },
      });
    }

    const fullPath = path.join(dataDir, row.original_path);
    if (!fs.existsSync(fullPath)) {
      return reply.code(404).send({
        error: { code: 'FILE_NOT_FOUND', message: 'Media file missing on disk' },
      });
    }

    const stat = fs.statSync(fullPath);
    const fileSize = stat.size;
    const range = req.headers.range;

    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : fileSize - 1;

      if (isNaN(start) || isNaN(end) || start > end || start >= fileSize) {
        reply.code(416);
        reply.header('Content-Range', `bytes */${fileSize}`);
        return reply.send();
      }

      const chunkSize = (end - start) + 1;
      reply.code(206);
      reply.header('Content-Range', `bytes ${start}-${end}/${fileSize}`);
      reply.header('Accept-Ranges', 'bytes');
      reply.header('Content-Length', chunkSize);
      reply.header('Content-Type', row.mime_type || 'application/octet-stream');
      return reply.send(fs.createReadStream(fullPath, { start, end }));
    }

    reply.code(200);
    reply.header('Content-Length', fileSize);
    reply.header('Accept-Ranges', 'bytes');
    reply.header('Content-Type', row.mime_type || 'application/octet-stream');
    return reply.send(fs.createReadStream(fullPath));
  }

  fastify.get('/media/:id/file', { preHandler: [fastify.authenticate] }, streamFullFile);
  fastify.get('/media/:id/preview', { preHandler: [fastify.authenticate] }, streamFullFile);

  // 6. Toggle favorite
  fastify.patch('/media/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const { isFavorite } = req.body || {};
    const nowIso = new Date().toISOString();

    const row = db.prepare('SELECT id FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }

    db.prepare('UPDATE media SET is_favorite = ?, updated_at = ? WHERE id = ?').run(
      isFavorite ? 1 : 0,
      nowIso,
      id
    );

    const updated = db.prepare('SELECT * FROM media WHERE id = ?').get(id);
    return { media: toMediaItem(updated) };
  });

  // 7. Bulk toggle favorites
  fastify.post('/media/favorite', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids, isFavorite } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) {
      return { success: true, count: 0 };
    }

    const nowIso = new Date().toISOString();
    const favVal = isFavorite ? 1 : 0;
    const stmt = db.prepare('UPDATE media SET is_favorite = ?, updated_at = ? WHERE id = ? AND user_id = ?');

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const id of ids) {
        stmt.run(favVal, nowIso, id, req.user.id);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }

    return { success: true, count: ids.length, isFavorite: Boolean(favVal) };
  });

  // 8. Trash / Restore single item
  fastify.post('/media/:id/trash', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const nowIso = new Date().toISOString();
    const info = db.prepare('UPDATE media SET is_trashed = 1, trashed_at = ?, updated_at = ? WHERE id = ? AND user_id = ?').run(
      nowIso, nowIso, id, req.user.id
    );
    if (info.changes === 0) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }
    return { success: true, id, isTrashed: true };
  });

  fastify.post('/media/:id/restore', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const nowIso = new Date().toISOString();
    const info = db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL, updated_at = ? WHERE id = ? AND user_id = ?').run(
      nowIso, id, req.user.id
    );
    if (info.changes === 0) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }
    return { success: true, id, isTrashed: false };
  });

  // 9. Bulk trash / restore
  fastify.post('/media/trash', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) {
      return { success: true, count: 0 };
    }
    const nowIso = new Date().toISOString();
    const stmt = db.prepare('UPDATE media SET is_trashed = 1, trashed_at = ?, updated_at = ? WHERE id = ? AND user_id = ?');

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const id of ids) {
        stmt.run(nowIso, nowIso, id, req.user.id);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: ids.length, isTrashed: true };
  });

  fastify.post('/media/restore', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) {
      return { success: true, count: 0 };
    }
    const nowIso = new Date().toISOString();
    const stmt = db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL, updated_at = ? WHERE id = ? AND user_id = ?');

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const id of ids) {
        stmt.run(nowIso, id, req.user.id);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: ids.length, isTrashed: false };
  });

  // 10. Permanent delete (single and bulk)
  function deleteMediaRecordAndFiles(mediaRow) {
    if (mediaRow.original_path) {
      try { fs.unlinkSync(path.join(dataDir, mediaRow.original_path)); } catch (_) {}
    }
    if (mediaRow.thumbnail_path) {
      try { fs.unlinkSync(path.join(dataDir, mediaRow.thumbnail_path)); } catch (_) {}
    }
    const bytesToFree = Number(mediaRow.size_bytes);
    db.prepare('DELETE FROM media WHERE id = ?').run(mediaRow.id);
    db.prepare(`
      UPDATE users
      SET storage_used_bytes = MAX(0, storage_used_bytes - ?), updated_at = ?
      WHERE id = ?
    `).run(bytesToFree, new Date().toISOString(), mediaRow.user_id);
  }

  fastify.delete('/media/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = db.prepare('SELECT id, user_id, original_path, thumbnail_path, size_bytes FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }

    db.exec('BEGIN IMMEDIATE;');
    try {
      deleteMediaRecordAndFiles(row);
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }

    return { success: true, deletedId: id };
  });

  fastify.post('/media/delete', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) {
      return { success: true, count: 0 };
    }

    const rows = db.prepare(`SELECT id, user_id, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND id IN (${ids.map(() => '?').join(',')})`).all(req.user.id, ...ids);

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const row of rows) {
        deleteMediaRecordAndFiles(row);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }

    return { success: true, count: rows.length };
  });

  // 11. Empty trash and 30-day auto purge
  function purgeExpiredTrash() {
    const expiredRows = db.prepare(`
      SELECT id, user_id, original_path, thumbnail_path, size_bytes
      FROM media
      WHERE is_trashed = 1 AND trashed_at IS NOT NULL AND trashed_at < datetime('now', '-30 days')
    `).all();

    if (expiredRows.length === 0) return { count: 0, freedBytes: 0 };

    let totalFreed = 0;
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const row of expiredRows) {
        totalFreed += Number(row.size_bytes || 0);
        deleteMediaRecordAndFiles(row);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { count: expiredRows.length, freedBytes: totalFreed };
  }

  fastify.post('/media/trash/empty', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const rows = db.prepare('SELECT id, user_id, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND is_trashed = 1').all(req.user.id);
    let totalFreed = 0;
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const row of rows) {
        totalFreed += Number(row.size_bytes || 0);
        deleteMediaRecordAndFiles(row);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: rows.length, freedBytes: totalFreed };
  });

  // Trash REST Aliases
  fastify.get('/trash', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    try { purgeExpiredTrash(); } catch (_) {}
    const rows = db.prepare('SELECT * FROM media WHERE user_id = ? AND is_trashed = 1 ORDER BY trashed_at DESC, id DESC').all(req.user.id);
    return {
      items: rows.map(toMediaItem),
      total: rows.length,
    };
  });

  fastify.post('/trash/empty', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const rows = db.prepare('SELECT id, user_id, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND is_trashed = 1').all(req.user.id);
    let totalFreed = 0;
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const row of rows) {
        totalFreed += Number(row.size_bytes || 0);
        deleteMediaRecordAndFiles(row);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: rows.length, freedBytes: totalFreed };
  });

  fastify.post('/trash/restore', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) return { success: true, count: 0 };
    const nowIso = new Date().toISOString();
    const stmt = db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL, updated_at = ? WHERE id = ? AND user_id = ?');
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const id of ids) {
        stmt.run(nowIso, id, req.user.id);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: ids.length, isTrashed: false };
  });

  fastify.post('/trash/delete', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const { ids } = req.body || {};
    if (!Array.isArray(ids) || ids.length === 0) return { success: true, count: 0 };
    const rows = db.prepare(`SELECT id, user_id, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND id IN (${ids.map(() => '?').join(',')})`).all(req.user.id, ...ids);
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const row of rows) {
        deleteMediaRecordAndFiles(row);
      }
      db.exec('COMMIT;');
    } catch (e) {
      db.exec('ROLLBACK;');
      throw e;
    }
    return { success: true, count: rows.length };
  });

  fastify.post('/trash/purge', {
    preHandler: [fastify.authenticate],
  }, async () => {
    const result = purgeExpiredTrash();
    return { success: true, ...result };
  });
}
