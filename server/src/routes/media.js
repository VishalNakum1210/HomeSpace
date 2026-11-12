import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import sharp from 'sharp';
import { getMediaPaths, deleteMediaFiles, checkQuota, updateStorageUsage, sanitizeMediaId } from '../storage.js';

const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/avif',
]);

const EXTENSION_MAP = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/avif': 'avif',
};

// Check if user has permission to access a media item (owner OR shared album member)
export function canAccessMedia(db, userId, mediaId) {
  // 1. Direct owner
  const media = db.prepare('SELECT * FROM media WHERE id = ?').get(mediaId);
  if (!media) return null;
  if (media.user_id === userId) return media;

  // 2. Shared album member
  const shared = db.prepare(`
    SELECT am.album_id
    FROM album_media am
    JOIN album_members mem ON am.album_id = mem.album_id
    WHERE am.media_id = ? AND mem.user_id = ?
  `).get(mediaId, userId);

  if (shared) return media;
  return null;
}

export async function mediaRoutes(fastify, options) {
  const { db, dataDir } = options;

  // Authenticate all media routes
  fastify.addHook('preHandler', fastify.authenticate);

  // 1. Upload media item
  fastify.post('/media/upload', async (req, reply) => {
    const data = await req.file();
    if (!data) {
      return reply.code(400).send({
        error: { code: 'NO_FILE', message: 'No file uploaded' },
      });
    }

    let mimeType = data.mimetype;
    if ((!mimeType || mimeType === 'application/octet-stream') && data.filename) {
      const fileExt = path.extname(data.filename).toLowerCase().replace('.', '');
      const reverseMap = {
        jpg: 'image/jpeg',
        jpeg: 'image/jpeg',
        png: 'image/png',
        webp: 'image/webp',
        gif: 'image/gif',
        heic: 'image/heic',
        avif: 'image/avif',
      };
      if (reverseMap[fileExt]) mimeType = reverseMap[fileExt];
    }
    if (!ALLOWED_MIME_TYPES.has(mimeType)) {
      return reply.code(415).send({
        error: {
          code: 'UNSUPPORTED_MEDIA_TYPE',
          message: `Unsupported media format: ${mimeType}. Supported: JPEG, PNG, WebP, GIF, HEIC, AVIF`,
        },
      });
    }

    const fileBuffer = await data.toBuffer();
    const byteSize = fileBuffer.length;

    // Estimate total size with thumbnail (~80KB thumbnail estimate)
    const estimatedTotalBytes = byteSize + 80 * 1024;
    const quotaCheck = checkQuota(db, req.user.id, estimatedTotalBytes);
    if (!quotaCheck.allowed) {
      return reply.code(413).send({
        error: {
          code: 'QUOTA_EXCEEDED',
          message: `Storage quota exceeded. Free space: ${(quotaCheck.remainingBytes / (1024 * 1024)).toFixed(1)} MB, Upload requires: ${(byteSize / (1024 * 1024)).toFixed(1)} MB`,
        },
      });
    }

    const mediaId = 'm_' + crypto.randomBytes(8).toString('hex');
    const ext = EXTENSION_MAP[mimeType] || 'jpg';
    const paths = getMediaPaths(dataDir, req.user.id, mediaId, ext);

    // Save original image to user's isolated folder
    fs.writeFileSync(paths.original, fileBuffer);

    let width = 0;
    let height = 0;
    let thumbSize = 0;

    try {
      // Process with Sharp for metadata & thumbnail
      const image = sharp(fileBuffer);
      const metadata = await image.metadata();
      width = metadata.width || 0;
      height = metadata.height || 0;

      // Generate compressed mobile thumbnail (400px width/height bounding box, webp format)
      await image
        .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
        .webp({ quality: 80 })
        .toFile(paths.thumbnail);

      const thumbStat = fs.statSync(paths.thumbnail);
      thumbSize = thumbStat.size;
    } catch (err) {
      // Cleanup on failure
      if (fs.existsSync(paths.original)) fs.unlinkSync(paths.original);
      if (fs.existsSync(paths.thumbnail)) fs.unlinkSync(paths.thumbnail);
      throw err;
    }

    const actualTotalBytes = byteSize + thumbSize;
    const now = new Date().toISOString();
    const originalFileName = data.filename || `photo_${Date.now()}.${ext}`;

    // Record in media table
    const insertStmt = db.prepare(`
      INSERT INTO media (
        id, user_id, file_name, mime_type, byte_size, width, height,
        taken_at, created_at, is_favorite, is_trashed
      ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, 0, 0)
    `);

    insertStmt.run(
      mediaId,
      req.user.id,
      originalFileName,
      mimeType,
      actualTotalBytes,
      width,
      height,
      now,
      now,
    );

    // Update user storage
    updateStorageUsage(db, req.user.id, actualTotalBytes);

    return reply.code(201).send({
      id: mediaId,
      userId: req.user.id,
      fileName: originalFileName,
      mimeType,
      byteSize: actualTotalBytes,
      width,
      height,
      takenAt: now,
      createdAt: now,
      isFavorite: false,
      isTrashed: false,
    });
  });

  // 2. List media items for current user
  fastify.get('/media', async (req, reply) => {
    const trashed = req.query.trashed === '1' ? 1 : 0;
    const favorite = req.query.favorite === '1' ? 1 : null;

    let query = 'SELECT * FROM media WHERE user_id = ? AND is_trashed = ?';
    const params = [req.user.id, trashed];

    if (favorite !== null) {
      query += ' AND is_favorite = ?';
      params.push(favorite);
    }

    query += ' ORDER BY taken_at DESC';

    const rows = db.prepare(query).all(...params);

    return {
      items: rows.map(r => ({
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
        isTrashed: Boolean(r.is_trashed),
        trashedAt: r.trashed_at,
      })),
    };
  });

  // 3. Get media details
  fastify.get('/media/:id', async (req, reply) => {
    const media = canAccessMedia(db, req.user.id, req.params.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found or access denied' },
      });
    }

    return {
      id: media.id,
      userId: media.user_id,
      fileName: media.file_name,
      mimeType: media.mime_type,
      byteSize: Number(media.byte_size),
      width: media.width,
      height: media.height,
      takenAt: media.taken_at,
      createdAt: media.created_at,
      isFavorite: Boolean(media.is_favorite),
      isTrashed: Boolean(media.is_trashed),
      trashedAt: media.trashed_at,
    };
  });

  // 4. Stream thumbnail
  fastify.get('/media/:id/thumb', async (req, reply) => {
    const media = canAccessMedia(db, req.user.id, req.params.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found or access denied' },
      });
    }

    const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
    const paths = getMediaPaths(dataDir, media.user_id, media.id, ext);

    if (!fs.existsSync(paths.thumbnail)) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Thumbnail file missing' },
      });
    }

    reply.header('Content-Type', 'image/webp');
    reply.header('Cache-Control', 'private, max-age=86400');
    return reply.send(fs.createReadStream(paths.thumbnail));
  });

  // 5. Stream full original file
  fastify.get('/media/:id/file', async (req, reply) => {
    const media = canAccessMedia(db, req.user.id, req.params.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found or access denied' },
      });
    }

    const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
    const paths = getMediaPaths(dataDir, media.user_id, media.id, ext);

    if (!fs.existsSync(paths.original)) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Original file missing' },
      });
    }

    const stat = fs.statSync(paths.original);
    const range = req.headers.range;

    reply.header('Content-Type', media.mime_type);
    reply.header('Accept-Ranges', 'bytes');

    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      const end = parts[1] ? parseInt(parts[1], 10) : stat.size - 1;
      const chunksize = end - start + 1;

      reply.code(206);
      reply.header('Content-Range', `bytes ${start}-${end}/${stat.size}`);
      reply.header('Content-Length', chunksize);
      return reply.send(fs.createReadStream(paths.original, { start, end }));
    }

    reply.header('Content-Length', stat.size);
    return reply.send(fs.createReadStream(paths.original));
  });

  // 6. Toggle Favorite
  fastify.patch('/media/:id', async (req, reply) => {
    const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    const isFavorite = req.body?.favorite !== undefined ? (req.body.favorite ? 1 : 0) : (media.is_favorite ? 0 : 1);
    db.prepare('UPDATE media SET is_favorite = ? WHERE id = ?').run(isFavorite, media.id);

    return {
      id: media.id,
      isFavorite: Boolean(isFavorite),
    };
  });

  // 7. Move to Trash (Soft delete)
  fastify.post('/media/:id/trash', async (req, reply) => {
    const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    const now = new Date().toISOString();
    db.prepare('UPDATE media SET is_trashed = 1, trashed_at = ? WHERE id = ?').run(now, media.id);

    return { id: media.id, isTrashed: true, trashedAt: now };
  });

  // 8. Restore from Trash
  fastify.post('/media/:id/restore', async (req, reply) => {
    const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL WHERE id = ?').run(media.id);

    return { id: media.id, isTrashed: false };
  });

  // 9. Permanent Delete (Owner only - frees disk and recovers quota)
  fastify.delete('/media/:id', async (req, reply) => {
    const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(req.params.id, req.user.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media not found' },
      });
    }

    const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
    deleteMediaFiles(dataDir, req.user.id, media.id, ext);

    db.prepare('DELETE FROM media WHERE id = ?').run(media.id);
    const updatedQuota = updateStorageUsage(db, req.user.id, -Number(media.byte_size));

    return {
      deleted: true,
      id: media.id,
      recoveredBytes: Number(media.byte_size),
      storageUsedBytes: updatedQuota.usedBytes,
    };
  });

  // 10. Batch Operations
  fastify.post('/media/batch/trash', async (req, reply) => {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
    if (!ids.length) return { trashedCount: 0 };

    const now = new Date().toISOString();
    let count = 0;
    const stmt = db.prepare('UPDATE media SET is_trashed = 1, trashed_at = ? WHERE id = ? AND user_id = ?');

    for (const id of ids) {
      const res = stmt.run(now, id, req.user.id);
      if (res.changes > 0) count++;
    }

    return { trashedCount: count };
  });

  fastify.post('/media/batch/restore', async (req, reply) => {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
    if (!ids.length) return { restoredCount: 0 };

    let count = 0;
    const stmt = db.prepare('UPDATE media SET is_trashed = 0, trashed_at = NULL WHERE id = ? AND user_id = ?');

    for (const id of ids) {
      const res = stmt.run(id, req.user.id);
      if (res.changes > 0) count++;
    }

    return { restoredCount: count };
  });

  fastify.post('/media/batch/favorite', async (req, reply) => {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
    const favorite = req.body?.favorite ? 1 : 0;
    if (!ids.length) return { updatedCount: 0 };

    let count = 0;
    const stmt = db.prepare('UPDATE media SET is_favorite = ? WHERE id = ? AND user_id = ?');

    for (const id of ids) {
      const res = stmt.run(favorite, id, req.user.id);
      if (res.changes > 0) count++;
    }

    return { updatedCount: count };
  });

  fastify.post('/media/batch/delete', async (req, reply) => {
    const ids = Array.isArray(req.body?.ids) ? req.body.ids : [];
    if (!ids.length) return { deletedCount: 0, recoveredBytes: 0 };

    let deletedCount = 0;
    let totalBytesRecovered = 0;

    for (const id of ids) {
      const media = db.prepare('SELECT * FROM media WHERE id = ? AND user_id = ?').get(id, req.user.id);
      if (media) {
        const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
        deleteMediaFiles(dataDir, req.user.id, media.id, ext);
        db.prepare('DELETE FROM media WHERE id = ?').run(media.id);
        totalBytesRecovered += Number(media.byte_size);
        deletedCount++;
      }
    }

    if (totalBytesRecovered > 0) {
      updateStorageUsage(db, req.user.id, -totalBytesRecovered);
    }

    return { deletedCount, recoveredBytes: totalBytesRecovered };
  });
}
