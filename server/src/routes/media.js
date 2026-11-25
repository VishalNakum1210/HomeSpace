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
  const resolvedDataDir = path.resolve(dataDir);

  function toMediaItem(row) {
    return {
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
    };
  }

  function resolveSafeMediaPath(relPath) {
    if (!relPath || typeof relPath !== 'string') return null;
    const resolved = path.resolve(resolvedDataDir, relPath);
    if (!resolved.startsWith(resolvedDataDir + path.sep)) {
      return null;
    }
    return resolved;
  }

  function findReadableMediaRow(id, userId) {
    return db.prepare(`
      SELECT m.*
      FROM media m
      WHERE m.id = ?
        AND (
          m.user_id = ?
          OR (
            m.is_trashed = 0
            AND EXISTS (
              SELECT 1
              FROM album_media am
              JOIN albums a ON a.id = am.album_id
              WHERE am.media_id = m.id
                AND (
                  a.user_id = ?
                  OR EXISTS (SELECT 1 FROM album_members mem WHERE mem.album_id = a.id AND mem.user_id = ?)
                  OR (a.is_shared = 1 AND NOT EXISTS (SELECT 1 FROM album_members mem2 WHERE mem2.album_id = a.id))
                )
            )
          )
        )
    `).get(id, userId, userId, userId);
  }

  function sanitizeUploadFilename(raw) {
    const base = path.basename(String(raw || 'upload.jpg')).replace(/[\r\n\0]/g, '_').trim();
    return base || 'upload.jpg';
  }

  function findMatchingOwnedMediaRows({ userId, ids, filenames, onlyTrashed = false, selectColumns = 'id' }) {
    const rows = [];
    const seen = new Set();
    const trashedClause = onlyTrashed ? ' AND is_trashed = 1' : '';

    if (Array.isArray(ids) && ids.length > 0) {
      const cleanIds = ids.map((id) => String(id).trim()).filter(Boolean);
      if (cleanIds.length > 0) {
        const byId = db.prepare(
          `SELECT ${selectColumns} FROM media WHERE user_id = ?${trashedClause} AND id IN (${cleanIds.map(() => '?').join(',')})`
        ).all(userId, ...cleanIds);
        for (const r of byId) {
          if (!seen.has(r.id)) {
            seen.add(r.id);
            rows.push(r);
          }
        }
      }
    }

    if (Array.isArray(filenames) && filenames.length > 0) {
      const cleanNames = filenames.map((f) => String(f).toLowerCase().trim()).filter(Boolean);
      if (cleanNames.length > 0) {
        const byName = db.prepare(
          `SELECT ${selectColumns} FROM media WHERE user_id = ?${trashedClause} AND LOWER(filename) IN (${cleanNames.map(() => '?').join(',')})`
        ).all(userId, ...cleanNames);
        for (const r of byName) {
          if (!seen.has(r.id)) {
            seen.add(r.id);
            rows.push(r);
          }
        }
      }
    }

    return rows;
  }

  function unlinkMediaFiles(rows) {
    for (const row of rows) {
      if (row.original_path) {
        const origFullPath = resolveSafeMediaPath(row.original_path);
        if (origFullPath) {
          try {
            if (fs.existsSync(origFullPath)) fs.unlinkSync(origFullPath);
          } catch (err) {
            console.error(`[DELETE] Error unlinking original file ${origFullPath}:`, err.message);
          }
        }
      }
      if (row.thumbnail_path) {
        const thumbFullPath = resolveSafeMediaPath(row.thumbnail_path);
        if (thumbFullPath) {
          try {
            if (fs.existsSync(thumbFullPath)) fs.unlinkSync(thumbFullPath);
          } catch (err) {
            console.error(`[DELETE] Error unlinking thumbnail file ${thumbFullPath}:`, err.message);
          }
        }
      }
    }
  }

  function purgeMediaRowsTransactional(rows) {
    if (!rows || rows.length === 0) return 0;
    const nowIso = new Date().toISOString();
    let totalFreed = 0;

    db.exec('BEGIN IMMEDIATE;');
    try {
      const delAlbumMediaStmt = db.prepare('DELETE FROM album_media WHERE media_id = ?');
      const affectedAlbumsStmt = db.prepare('SELECT id FROM albums WHERE cover_media_id = ?');
      const nextCoverStmt = db.prepare(
        'SELECT media_id FROM album_media WHERE album_id = ? ORDER BY added_at DESC LIMIT 1'
      );
      const updateCoverStmt = db.prepare('UPDATE albums SET cover_media_id = ?, updated_at = ? WHERE id = ?');
      const delMediaStmt = db.prepare('DELETE FROM media WHERE id = ?');
      const refundQuotaStmt = db.prepare(
        'UPDATE users SET storage_used_bytes = MAX(0, storage_used_bytes - ?), updated_at = ? WHERE id = ?'
      );

      for (const row of rows) {
        const bytesToFree = Number(row.size_bytes || 0);
        totalFreed += bytesToFree;

        delAlbumMediaStmt.run(row.id);

        const albumsUsingCover = affectedAlbumsStmt.all(row.id);
        for (const alb of albumsUsingCover) {
          const nextCover = nextCoverStmt.get(alb.id);
          updateCoverStmt.run(nextCover ? nextCover.media_id : null, nowIso, alb.id);
        }

        delMediaStmt.run(row.id);
        refundQuotaStmt.run(bytesToFree, nowIso, row.user_id);
      }

      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    // Only unlink physical files strictly after DB commit succeeds
    unlinkMediaFiles(rows);
    return totalFreed;
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

    const originalFilename = sanitizeUploadFilename(part.filename);
    const mimeType = part.mimetype || 'application/octet-stream';

    const isVideo = mimeType.startsWith('video/') ||
      ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'].some(ext => originalFilename.toLowerCase().endsWith(ext));
    const kind = isVideo ? 'video' : 'photo';

    // File destinations
    const mediaId = 'm_' + crypto.randomBytes(16).toString('hex');
    const rawExt = path.extname(originalFilename).toLowerCase();
    const ext = /^\.[a-z0-9]{1,10}$/.test(rawExt) ? rawExt : (isVideo ? '.mp4' : '.jpg');

    const userOriginalsDir = path.join(resolvedDataDir, 'users', userId, 'originals');
    const userThumbsDir = path.join(resolvedDataDir, 'users', userId, 'thumbnails');
    fs.mkdirSync(userOriginalsDir, { recursive: true, mode: 0o700 });
    fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });

    const targetOriginalPath = path.join(userOriginalsDir, `${mediaId}${ext}`);
    const targetThumbPath = path.join(userThumbsDir, `${mediaId}.webp`);

    let bytesWritten = 0;
    const writeStream = fs.createWriteStream(targetOriginalPath);

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
        error: { code: 'UPLOAD_FAILED', message: 'Failed to store uploaded media file' },
      });
    }

    // Parse takenAt from query parameter, header, or multipart fields (now fully drained)
    const takenAtStr = req.query?.takenAt || req.headers['x-taken-at'] || part.fields?.takenAt?.value;
    let takenAtDate = takenAtStr ? new Date(String(takenAtStr)) : null;
    if (!takenAtDate || isNaN(takenAtDate.getTime())) {
      takenAtDate = new Date();
    }
    const takenAt = takenAtDate.toISOString();

    // Thumbnail generation
    let thumbnailRelPath = null;
    if (kind === 'photo') {
      try {
        await sharp(targetOriginalPath)
          .rotate()
          .resize(480, 480, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 80 })
          .toFile(targetThumbPath);
        thumbnailRelPath = path.posix.join('users', userId, 'thumbnails', `${mediaId}.webp`);
      } catch (_) {
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

    // Atomic quota verification & DB commit
    db.exec('BEGIN IMMEDIATE;');
    try {
      const freshUser = db.prepare(
        'SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?'
      ).get(userId);
      if (!freshUser) {
        db.exec('ROLLBACK;');
        try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
        try { if (thumbnailRelPath) fs.unlinkSync(targetThumbPath); } catch (_) {}
        return reply.code(404).send({
          error: { code: 'USER_NOT_FOUND', message: 'User not found' },
        });
      }

      const currentUsed = Number(freshUser.storage_used_bytes);
      const currentQuota = Number(freshUser.storage_quota_bytes);
      if (currentUsed + bytesWritten > currentQuota) {
        db.exec('ROLLBACK;');
        try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
        try { if (thumbnailRelPath) fs.unlinkSync(targetThumbPath); } catch (_) {}
        return reply.code(413).send({
          error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while finalizing upload' },
        });
      }

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
      try { db.exec('ROLLBACK;'); } catch (_) {}
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
    const rawLimit = Number.parseInt(req.query?.limit ?? '100', 10);
    const limit = Number.isFinite(rawLimit) ? Math.min(Math.max(rawLimit, 1), 500) : 100;
    const rawOffset = Number.parseInt(req.query?.offset ?? '0', 10);
    const offset = Number.isFinite(rawOffset) ? Math.max(rawOffset, 0) : 0;

    const isFavoriteOnly = req.query?.favorite === 'true' || req.query?.favorite === '1';
    const kindFilter = (req.query?.kind === 'photo' || req.query?.kind === 'video') ? req.query.kind : null;
    const isTrashed = req.query?.trashed === 'true' || req.query?.trashed === '1' ? 1 : 0;

    let whereSql = 'WHERE user_id = ? AND is_trashed = ?';
    const whereParams = [userId, isTrashed];

    if (isFavoriteOnly) {
      whereSql += ' AND is_favorite = 1';
    }
    if (kindFilter) {
      whereSql += ' AND kind = ?';
      whereParams.push(kindFilter);
    }

    const rows = db.prepare(
      `SELECT * FROM media ${whereSql} ORDER BY taken_at DESC, id DESC LIMIT ? OFFSET ?`
    ).all(...whereParams, limit, offset);

    const totalCountRow = db.prepare(
      `SELECT COUNT(*) as total FROM media ${whereSql}`
    ).get(...whereParams);

    return {
      items: rows.map(toMediaItem),
      total: Number(totalCountRow?.total || 0),
      limit,
      offset,
    };
  });

  // 3. Get single media metadata (owner or shared-album viewer)
  fastify.get('/media/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = findReadableMediaRow(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }
    return { media: toMediaItem(row) };
  });

  // 4. Stream thumbnail (owner or shared-album viewer)
  fastify.get('/media/:id/thumb', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = findReadableMediaRow(id, req.user.id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    reply.header('Vary', 'Authorization');

    if (row.thumbnail_path) {
      const fullThumbPath = resolveSafeMediaPath(row.thumbnail_path);
      if (fullThumbPath && fs.existsSync(fullThumbPath)) {
        const isJpeg = fullThumbPath.endsWith('.jpg') || fullThumbPath.endsWith('.jpeg');
        reply.header('Content-Type', isJpeg ? 'image/jpeg' : 'image/webp');
        reply.header('Cache-Control', 'private, max-age=31536000, immutable');
        return reply.send(fs.createReadStream(fullThumbPath));
      }
    }

    // Fallback: if photo, stream original as thumb
    if (row.kind === 'photo' && row.original_path) {
      const fullOrigPath = resolveSafeMediaPath(row.original_path);
      if (fullOrigPath && fs.existsSync(fullOrigPath)) {
        reply.header('Content-Type', row.mime_type || 'image/jpeg');
        reply.header('Cache-Control', 'private, max-age=86400');
        return reply.send(fs.createReadStream(fullOrigPath));
      }
    }

    return reply.code(404).send({
      error: { code: 'THUMBNAIL_NOT_AVAILABLE', message: 'Thumbnail not available' },
    });
  });

  // 4b. Upload / update thumbnail for a media item (owner only)
  fastify.post('/media/:id/thumb', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const userId = req.user.id;
    const row = db.prepare('SELECT id FROM media WHERE id = ? AND user_id = ?').get(id, userId);
    if (!row) {
      return reply.code(404).send({ error: { code: 'NOT_FOUND', message: 'Media not found' } });
    }

    let part;
    try {
      part = await req.file({ limits: { fileSize: 10 * 1024 * 1024 } });
    } catch (err) {
      return reply.code(400).send({ error: { code: 'UPLOAD_FAILED', message: err.message } });
    }
    if (!part) {
      return reply.code(400).send({ error: { code: 'NO_FILE', message: 'No thumbnail file uploaded' } });
    }

    const userThumbsDir = path.join(resolvedDataDir, 'users', userId, 'thumbnails');
    fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });
    const targetThumbPath = path.join(userThumbsDir, `${id}.webp`);
    const tempThumbPath = `${targetThumbPath}.tmp`;
    const writeStream = fs.createWriteStream(tempThumbPath);

    try {
      await pipeline(part.file, writeStream);
      fs.renameSync(tempThumbPath, targetThumbPath);
    } catch (err) {
      try { writeStream.destroy(); } catch (_) {}
      try { fs.unlinkSync(tempThumbPath); } catch (_) {}
      const status = err.code === 'FST_REQ_FILE_TOO_LARGE' ? 413 : 500;
      return reply.code(status).send({ error: { code: 'THUMB_UPLOAD_FAILED', message: 'Failed to store thumbnail' } });
    }

    const relPath = path.posix.join('users', userId, 'thumbnails', `${id}.webp`);
    db.prepare('UPDATE media SET thumbnail_path = ?, updated_at = ? WHERE id = ?').run(
      relPath,
      new Date().toISOString(),
      id
    );

    return { success: true, thumbUrl: `/api/media/${id}/thumb` };
  });

  // 5. Full file streaming & RFC 9110 Range requests (owner or shared-album viewer)
  async function streamFullFile(req, reply) {
    const { id } = req.params;
    const row = findReadableMediaRow(id, req.user.id);
    if (!row || !row.original_path) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media file not found' },
      });
    }

    const fullPath = resolveSafeMediaPath(row.original_path);
    if (!fullPath || !fs.existsSync(fullPath)) {
      return reply.code(404).send({
        error: { code: 'FILE_NOT_FOUND', message: 'Media file missing on disk' },
      });
    }

    const stat = fs.statSync(fullPath);
    const fileSize = stat.size;
    const rangeHeader = req.headers.range;

    reply.header('Cache-Control', 'private, max-age=3600');
    reply.header('Vary', 'Authorization');

    if (rangeHeader) {
      const match = /^bytes=(\d*)-(\d*)$/.exec(String(rangeHeader).trim());
      if (!match || fileSize === 0) {
        reply.code(416);
        reply.header('Content-Range', `bytes */${fileSize}`);
        return reply.send();
      }

      const [, startStr, endStr] = match;
      let start;
      let end;

      if (!startStr && !endStr) {
        reply.code(416);
        reply.header('Content-Range', `bytes */${fileSize}`);
        return reply.send();
      } else if (!startStr) {
        // Suffix range: bytes=-N
        const suffixLen = Number.parseInt(endStr, 10);
        if (!Number.isFinite(suffixLen) || suffixLen <= 0) {
          reply.code(416);
          reply.header('Content-Range', `bytes */${fileSize}`);
          return reply.send();
        }
        start = Math.max(0, fileSize - suffixLen);
        end = fileSize - 1;
      } else {
        start = Number.parseInt(startStr, 10);
        end = endStr ? Math.min(Number.parseInt(endStr, 10), fileSize - 1) : fileSize - 1;
      }

      if (!Number.isFinite(start) || !Number.isFinite(end) || start < 0 || start >= fileSize || end < start) {
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

    let updatedCount = 0;
    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const id of ids) {
        const info = stmt.run(favVal, nowIso, id, req.user.id);
        if (info.changes > 0) updatedCount++;
      }
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }

    return { success: true, count: updatedCount, isFavorite: Boolean(favVal) };
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

  // 9. Bulk trash / restore handlers
  function handleBulkTrash(userId, body) {
    const { ids, filenames } = body || {};
    const targetRows = findMatchingOwnedMediaRows({ userId, ids, filenames, selectColumns: 'id' });
    if (targetRows.length === 0) {
      return { success: true, count: 0, isTrashed: true };
    }

    const nowIso = new Date().toISOString();
    const stmt = db.prepare('UPDATE media SET is_trashed = 1, trashed_at = ?, updated_at = ? WHERE id = ? AND user_id = ?');

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const r of targetRows) {
        stmt.run(nowIso, nowIso, r.id, userId);
      }
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }
    return { success: true, count: targetRows.length, isTrashed: true };
  }

  function handleBulkRestore(userId, body) {
    const { ids, filenames } = body || {};
    const targetRows = findMatchingOwnedMediaRows({ userId, ids, filenames, selectColumns: 'id' });
    if (targetRows.length === 0) {
      return { success: true, count: 0, isTrashed: false };
    }

    const nowIso = new Date().toISOString();
    const stmt = db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL, updated_at = ? WHERE id = ? AND user_id = ?');

    db.exec('BEGIN IMMEDIATE;');
    try {
      for (const r of targetRows) {
        stmt.run(nowIso, r.id, userId);
      }
      db.exec('COMMIT;');
    } catch (e) {
      try { db.exec('ROLLBACK;'); } catch (_) {}
      throw e;
    }
    return { success: true, count: targetRows.length, isTrashed: false };
  }

  fastify.post('/media/trash', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleBulkTrash(req.user.id, req.body));

  fastify.post('/media/restore', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleBulkRestore(req.user.id, req.body));

  // 10. Permanent delete (single and bulk)
  fastify.delete('/media/:id', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const { id } = req.params;
    const row = db.prepare(
      'SELECT id, user_id, filename, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND id = ?'
    ).get(req.user.id, id);
    if (!row) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found' },
      });
    }

    purgeMediaRowsTransactional([row]);
    return { success: true, deletedId: row.id };
  });

  function handleBulkDelete(userId, body) {
    const { ids, filenames } = body || {};
    const rows = findMatchingOwnedMediaRows({
      userId,
      ids,
      filenames,
      selectColumns: 'id, user_id, filename, original_path, thumbnail_path, size_bytes',
    });
    if (rows.length === 0) {
      return { success: true, count: 0 };
    }
    purgeMediaRowsTransactional(rows);
    return { success: true, count: rows.length };
  }

  fastify.post('/media/delete', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleBulkDelete(req.user.id, req.body));

  // 11. Empty trash and 30-day auto purge
  function purgeExpiredTrash(userId) {
    const expiredRows = db.prepare(`
      SELECT id, user_id, filename, original_path, thumbnail_path, size_bytes
      FROM media
      WHERE user_id = ? AND is_trashed = 1 AND trashed_at IS NOT NULL AND trashed_at < datetime('now', '-30 days')
    `).all(userId);

    if (expiredRows.length === 0) return { count: 0, freedBytes: 0 };
    const freedBytes = purgeMediaRowsTransactional(expiredRows);
    return { count: expiredRows.length, freedBytes };
  }

  function handleEmptyTrash(userId, body) {
    const { ids, filenames } = body || {};
    const hasFilter = (Array.isArray(ids) && ids.length > 0) || (Array.isArray(filenames) && filenames.length > 0);

    const rows = hasFilter
      ? findMatchingOwnedMediaRows({
          userId,
          ids,
          filenames,
          onlyTrashed: true,
          selectColumns: 'id, user_id, filename, original_path, thumbnail_path, size_bytes',
        })
      : db.prepare(
          'SELECT id, user_id, filename, original_path, thumbnail_path, size_bytes FROM media WHERE user_id = ? AND is_trashed = 1'
        ).all(userId);

    const totalFreed = purgeMediaRowsTransactional(rows);
    return { success: true, count: rows.length, freedBytes: totalFreed };
  }

  fastify.post('/media/trash/empty', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleEmptyTrash(req.user.id, req.body));

  // Trash REST Aliases
  fastify.get('/trash', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    try { purgeExpiredTrash(req.user.id); } catch (_) {}
    const rows = db.prepare('SELECT * FROM media WHERE user_id = ? AND is_trashed = 1 ORDER BY trashed_at DESC, id DESC').all(req.user.id);
    return {
      items: rows.map(toMediaItem),
      total: rows.length,
    };
  });

  fastify.post('/trash/empty', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleEmptyTrash(req.user.id, req.body));

  fastify.post('/trash/restore', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleBulkRestore(req.user.id, req.body));

  fastify.post('/trash/delete', {
    preHandler: [fastify.authenticate],
  }, async (req) => handleBulkDelete(req.user.id, req.body));

  fastify.post('/trash/purge', {
    preHandler: [fastify.authenticate],
  }, async (req) => {
    const result = purgeExpiredTrash(req.user.id);
    return { success: true, ...result };
  });
}
