import fs from 'node:fs';
import path from 'node:path';
import crypto from 'node:crypto';
import { pipeline } from 'node:stream/promises';
import { Transform } from 'node:stream';
import { execFile } from 'node:child_process';
import sharp from 'sharp';

const DEFAULT_UPLOAD_SESSION_TTL_MS = 24 * 60 * 60 * 1000;
const DEFAULT_CHUNK_SIZE_BYTES = 10 * 1024 * 1024;
const MAX_CHUNK_BYTES = 50 * 1024 * 1024;
const FFMPEG_THUMB_TIMEOUT_MS = 60 * 1000;

function tryExtractVideoThumbnail(videoPath, thumbPath) {
  return new Promise((resolve) => {
    // scale=480:-2 ensures height is an even number, avoiding ffmpeg scale filter error
    execFile(
      'ffmpeg',
      ['-y', '-ss', '00:00:00.500', '-i', videoPath, '-vframes', '1', '-vf', 'scale=480:-2', thumbPath],
      { timeout: FFMPEG_THUMB_TIMEOUT_MS },
      (err) => {
        if (err) {
          execFile(
            'ffmpeg',
            ['-y', '-i', videoPath, '-vframes', '1', '-vf', 'scale=480:-2', thumbPath],
            { timeout: FFMPEG_THUMB_TIMEOUT_MS },
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

function getAvailableDiskBytes(dirPath) {
  try {
    fs.mkdirSync(dirPath, { recursive: true });
    const stats = fs.statfsSync(dirPath);
    return Number(stats.bavail) * Number(stats.bsize);
  } catch (_) {
    return Number.MAX_SAFE_INTEGER;
  }
}

function moveFileSync(srcPath, destPath) {
  try {
    fs.renameSync(srcPath, destPath);
  } catch (err) {
    if (err.code === 'EXDEV') {
      fs.copyFileSync(srcPath, destPath);
      fs.unlinkSync(srcPath);
    } else {
      throw err;
    }
  }
}

export function cleanupExpiredTempUploads(tmpRoot, ttlMs = DEFAULT_UPLOAD_SESSION_TTL_MS) {
  if (!fs.existsSync(tmpRoot)) return 0;
  let removed = 0;
  const now = Date.now();
  let entries = [];
  try {
    entries = fs.readdirSync(tmpRoot, { withFileTypes: true });
  } catch (_) {
    return 0;
  }
  for (const entry of entries) {
    if (!entry.isDirectory()) continue;
    const sessionDir = path.join(tmpRoot, entry.name);
    const metaPath = path.join(sessionDir, 'meta.json');
    let lastActiveMs = 0;
    try {
      if (fs.existsSync(metaPath)) {
        const meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
        const parsed = Date.parse(meta.updatedAt || meta.createdAt || '');
        if (Number.isFinite(parsed)) {
          lastActiveMs = parsed;
        }
      }
      if (!lastActiveMs) {
        lastActiveMs = fs.statSync(sessionDir).mtimeMs;
      }
      if (now - lastActiveMs > ttlMs) {
        fs.rmSync(sessionDir, { recursive: true, force: true });
        removed++;
      }
    } catch (_) {}
  }
  return removed;
}

export async function mediaRoutes(fastify, options) {
  const {
    db,
    dataDir,
    uploadSessionTtlMs = DEFAULT_UPLOAD_SESSION_TTL_MS,
  } = options;
  const resolvedDataDir = path.resolve(dataDir);
  const tmpUploadsRoot = path.join(resolvedDataDir, 'tmp_uploads');
  const activeChunkLocks = new Set();

  // Accept raw binary chunk payloads without Fastify JSON parsing overhead
  fastify.addContentTypeParser('application/octet-stream', (req, payload, done) => {
    done(null, payload);
  });

  // Clean up any abandoned chunked uploads on startup and every hour
  cleanupExpiredTempUploads(tmpUploadsRoot, uploadSessionTtlMs);
  const uploadCleanupTimer = setInterval(() => {
    try {
      cleanupExpiredTempUploads(tmpUploadsRoot, uploadSessionTtlMs);
    } catch (_) {}
  }, 60 * 60 * 1000);
  uploadCleanupTimer.unref?.();
  fastify.addHook('onClose', async () => {
    clearInterval(uploadCleanupTimer);
  });

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

  async function finalizeUploadedMedia({
    userId,
    mediaId,
    originalFilename,
    mimeType,
    kind,
    ext,
    takenAt,
    bytesWritten,
    targetOriginalPath,
    targetThumbPath,
    userThumbsDir,
  }) {
    let thumbnailRelPath = null;
    if (kind === 'photo') {
      try {
        fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });
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
        fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });
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

    db.exec('BEGIN IMMEDIATE;');
    try {
      const freshUser = db.prepare(
        'SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?'
      ).get(userId);
      if (!freshUser) {
        db.exec('ROLLBACK;');
        try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
        try { if (thumbnailRelPath) fs.unlinkSync(targetThumbPath); } catch (_) {}
        return {
          statusCode: 404,
          body: { error: { code: 'USER_NOT_FOUND', message: 'User not found' } },
        };
      }

      const currentUsed = Number(freshUser.storage_used_bytes);
      const currentQuota = Number(freshUser.storage_quota_bytes);
      if (currentUsed + bytesWritten > currentQuota) {
        db.exec('ROLLBACK;');
        try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
        try { if (thumbnailRelPath) fs.unlinkSync(targetThumbPath); } catch (_) {}
        return {
          statusCode: 413,
          body: { error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while finalizing upload' } },
        };
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
    return {
      statusCode: 201,
      body: { media: toMediaItem(inserted) },
    };
  }

  function validateUploadSessionAccess(uploadId, userId) {
    if (!/^[a-zA-Z0-9_-]{8,64}$/.test(String(uploadId || ''))) {
      return { error: { statusCode: 400, code: 'INVALID_UPLOAD_ID', message: 'Invalid upload session ID' } };
    }
    const sessionDir = path.join(tmpUploadsRoot, uploadId);
    const resolvedSessionDir = path.resolve(sessionDir);
    if (!resolvedSessionDir.startsWith(path.resolve(tmpUploadsRoot) + path.sep)) {
      return { error: { statusCode: 400, code: 'INVALID_UPLOAD_ID', message: 'Invalid upload session ID' } };
    }
    const metaPath = path.join(resolvedSessionDir, 'meta.json');
    const partPath = path.join(resolvedSessionDir, 'upload.part');
    if (!fs.existsSync(metaPath) || !fs.existsSync(partPath)) {
      return { error: { statusCode: 404, code: 'UPLOAD_SESSION_NOT_FOUND', message: 'Upload session not found or expired' } };
    }
    let meta;
    try {
      meta = JSON.parse(fs.readFileSync(metaPath, 'utf8'));
    } catch (_) {
      return { error: { statusCode: 500, code: 'CORRUPT_UPLOAD_SESSION', message: 'Upload session metadata unreadable' } };
    }
    if (meta.userId !== userId) {
      return { error: { statusCode: 404, code: 'UPLOAD_SESSION_NOT_FOUND', message: 'Upload session not found or expired' } };
    }
    return { sessionDir: resolvedSessionDir, metaPath, partPath, meta };
  }

  function writeSessionMetaAtomic(metaPath, meta) {
    const tmpMetaPath = `${metaPath}.tmp`;
    fs.writeFileSync(tmpMetaPath, JSON.stringify(meta));
    fs.renameSync(tmpMetaPath, metaPath);
  }

  // 1. Upload media (single multipart file — allowed up to user's available quota & free disk space)
  fastify.post('/media/upload', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const userId = req.user.id;

    // Fast quota & disk pre-check
    const userRow = db.prepare('SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?').get(userId);
    if (!userRow) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }

    const quotaBytes = Number(userRow.storage_quota_bytes);
    const usedBytes = Number(userRow.storage_used_bytes);
    const availableQuota = Math.max(0, quotaBytes - usedBytes);

    if (availableQuota <= 0) {
      return reply.code(413).send({
        error: {
          code: 'QUOTA_EXCEEDED',
          message: `Storage quota exceeded (${Math.round(usedBytes / 1e6)}MB of ${Math.round(quotaBytes / 1e6)}MB used)`,
        },
      });
    }

    const availableDisk = getAvailableDiskBytes(resolvedDataDir);
    if (availableDisk <= 0) {
      return reply.code(507).send({
        error: {
          code: 'INSUFFICIENT_SERVER_DISK',
          message: 'Not enough free disk space on the home server.',
        },
      });
    }

    const maxAllowedBytes = Math.min(availableQuota, availableDisk);

    let part;
    try {
      part = await req.file({ limits: { fileSize: maxAllowedBytes } });
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

      if (streamErr.message === 'QUOTA_LIMIT_EXCEEDED' ||
          (streamErr.code === 'FST_REQ_FILE_TOO_LARGE' && availableQuota <= availableDisk)) {
        return reply.code(413).send({
          error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while uploading file' },
        });
      }
      if (streamErr.code === 'FST_REQ_FILE_TOO_LARGE' || streamErr.code === 'ENOSPC') {
        return reply.code(507).send({
          error: { code: 'INSUFFICIENT_SERVER_DISK', message: 'Not enough free disk space on the home server' },
        });
      }
      return reply.code(500).send({
        error: { code: 'UPLOAD_FAILED', message: 'Failed to store uploaded media file' },
      });
    }

    // Busboy truncates part.file silently when limits.fileSize is reached
    if (part.file.truncated) {
      try { fs.unlinkSync(targetOriginalPath); } catch (_) {}
      if (availableDisk < availableQuota) {
        return reply.code(507).send({
          error: { code: 'INSUFFICIENT_SERVER_DISK', message: 'Not enough free disk space on the home server' },
        });
      }
      return reply.code(413).send({
        error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while uploading file' },
      });
    }

    // Parse takenAt from query parameter, header, or multipart fields (now fully drained)
    const takenAtStr = req.query?.takenAt || req.headers['x-taken-at'] || part.fields?.takenAt?.value;
    let takenAtDate = takenAtStr ? new Date(String(takenAtStr)) : null;
    if (!takenAtDate || isNaN(takenAtDate.getTime())) {
      takenAtDate = new Date();
    }
    const takenAt = takenAtDate.toISOString();

    const result = await finalizeUploadedMedia({
      userId,
      mediaId,
      originalFilename,
      mimeType,
      kind,
      ext,
      takenAt,
      bytesWritten,
      targetOriginalPath,
      targetThumbPath,
      userThumbsDir,
    });

    return reply.code(result.statusCode).send(result.body);
  });

  // 1b. Chunked upload — initialize resumable upload session
  fastify.post('/media/upload/init', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const userId = req.user.id;
    const { filename, mimeType, totalBytes, takenAt } = req.body || {};

    const parsedTotal = Number(totalBytes);
    if (!Number.isInteger(parsedTotal) || parsedTotal <= 0) {
      return reply.code(400).send({
        error: { code: 'INVALID_SIZE', message: 'totalBytes must be a positive integer' },
      });
    }

    const userRow = db.prepare('SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?').get(userId);
    if (!userRow) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }

    const quotaBytes = Number(userRow.storage_quota_bytes);
    const usedBytes = Number(userRow.storage_used_bytes);
    const availableQuota = Math.max(0, quotaBytes - usedBytes);
    if (parsedTotal > availableQuota) {
      return reply.code(413).send({
        error: {
          code: 'QUOTA_EXCEEDED',
          message: `Insufficient account storage (${Math.round(availableQuota / 1e6)}MB available, file needs ${Math.round(parsedTotal / 1e6)}MB)`,
        },
      });
    }

    const availableDisk = getAvailableDiskBytes(resolvedDataDir);
    if (parsedTotal > availableDisk) {
      return reply.code(507).send({
        error: {
          code: 'INSUFFICIENT_SERVER_DISK',
          message: 'Not enough free disk space on the home server for this file',
        },
      });
    }

    const uploadId = 'up_' + crypto.randomBytes(16).toString('hex');
    const sessionDir = path.join(tmpUploadsRoot, uploadId);
    fs.mkdirSync(sessionDir, { recursive: true, mode: 0o700 });

    const cleanName = sanitizeUploadFilename(filename);
    const cleanMime = typeof mimeType === 'string' && mimeType.trim()
      ? mimeType.trim()
      : 'application/octet-stream';

    let takenAtDate = takenAt ? new Date(String(takenAt)) : null;
    if (!takenAtDate || isNaN(takenAtDate.getTime())) {
      takenAtDate = new Date();
    }

    const nowIso = new Date().toISOString();
    const meta = {
      uploadId,
      userId,
      filename: cleanName,
      mimeType: cleanMime,
      totalBytes: parsedTotal,
      bytesReceived: 0,
      takenAt: takenAtDate.toISOString(),
      createdAt: nowIso,
      updatedAt: nowIso,
    };

    fs.writeFileSync(path.join(sessionDir, 'upload.part'), Buffer.alloc(0));
    writeSessionMetaAtomic(path.join(sessionDir, 'meta.json'), meta);

    return reply.code(201).send({
      uploadId,
      bytesReceived: 0,
      totalBytes: parsedTotal,
      chunkSize: DEFAULT_CHUNK_SIZE_BYTES,
    });
  });

  // 1c. Chunked upload — query current offset for resume
  fastify.get('/media/upload/:uploadId', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const access = validateUploadSessionAccess(req.params.uploadId, req.user.id);
    if (access.error) {
      return reply.code(access.error.statusCode).send({
        error: { code: access.error.code, message: access.error.message },
      });
    }

    const { partPath, metaPath, meta } = access;
    const actualSize = fs.statSync(partPath).size;
    if (actualSize !== meta.bytesReceived) {
      meta.bytesReceived = actualSize;
      meta.updatedAt = new Date().toISOString();
      writeSessionMetaAtomic(metaPath, meta);
    }

    return {
      uploadId: meta.uploadId,
      bytesReceived: meta.bytesReceived,
      totalBytes: meta.totalBytes,
      chunkSize: DEFAULT_CHUNK_SIZE_BYTES,
    };
  });

  // 1d. Chunked upload — append raw binary chunk at expected byte offset
  fastify.put('/media/upload/:uploadId/chunk', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const uploadId = req.params.uploadId;
    const access = validateUploadSessionAccess(uploadId, req.user.id);
    if (access.error) {
      return reply.code(access.error.statusCode).send({
        error: { code: access.error.code, message: access.error.message },
      });
    }

    if (activeChunkLocks.has(uploadId)) {
      return reply.code(409).send({
        error: { code: 'UPLOAD_IN_PROGRESS', message: 'Another chunk write is currently in progress' },
      });
    }

    const { metaPath, partPath, meta } = access;
    const rawOffset = req.query?.offset ?? req.headers['x-upload-offset'];
    const offset = Number(rawOffset);
    if (!Number.isInteger(offset) || offset < 0) {
      return reply.code(400).send({
        error: { code: 'INVALID_OFFSET', message: 'Valid non-negative integer offset is required' },
      });
    }

    const currentDiskSize = fs.statSync(partPath).size;
    if (currentDiskSize !== meta.bytesReceived) {
      meta.bytesReceived = currentDiskSize;
      writeSessionMetaAtomic(metaPath, meta);
    }

    if (offset !== meta.bytesReceived) {
      return reply.code(409).send({
        error: {
          code: 'OFFSET_MISMATCH',
          message: `Expected offset ${meta.bytesReceived}, got ${offset}`,
          bytesReceived: meta.bytesReceived,
        },
      });
    }

    if (!req.body || typeof req.body.pipe !== 'function') {
      return reply.code(400).send({
        error: { code: 'INVALID_CHUNK_BODY', message: 'Chunk request must use application/octet-stream body' },
      });
    }

    const userRow = db.prepare('SELECT storage_quota_bytes, storage_used_bytes FROM users WHERE id = ?').get(req.user.id);
    if (!userRow) {
      return reply.code(404).send({
        error: { code: 'USER_NOT_FOUND', message: 'User not found' },
      });
    }
    const quotaBytes = Number(userRow.storage_quota_bytes);
    const usedBytes = Number(userRow.storage_used_bytes);

    activeChunkLocks.add(uploadId);
    let chunkBytes = 0;
    const writeStream = fs.createWriteStream(partPath, { flags: 'a' });

    const guardStream = new Transform({
      transform(chunk, encoding, callback) {
        chunkBytes += chunk.length;
        if (chunkBytes > MAX_CHUNK_BYTES) {
          callback(new Error('CHUNK_TOO_LARGE'));
        } else if (offset + chunkBytes > meta.totalBytes) {
          callback(new Error('EXCEEDS_DECLARED_SIZE'));
        } else if (usedBytes + offset + chunkBytes > quotaBytes) {
          callback(new Error('QUOTA_LIMIT_EXCEEDED'));
        } else {
          callback(null, chunk);
        }
      },
    });

    try {
      await pipeline(req.body, guardStream, writeStream);
    } catch (streamErr) {
      try { writeStream.destroy(); } catch (_) {}
      // Roll back partial chunk bytes so offset & file size stay strictly aligned for clean resume
      try { fs.truncateSync(partPath, offset); } catch (_) {}

      if (streamErr.message === 'QUOTA_LIMIT_EXCEEDED') {
        return reply.code(413).send({
          error: { code: 'QUOTA_EXCEEDED', message: 'Storage quota exceeded while uploading chunk' },
        });
      }
      if (streamErr.message === 'CHUNK_TOO_LARGE' || streamErr.message === 'EXCEEDS_DECLARED_SIZE') {
        return reply.code(400).send({
          error: { code: streamErr.message, message: 'Chunk size exceeds declared bounds' },
        });
      }
      if (streamErr.code === 'ENOSPC') {
        return reply.code(507).send({
          error: { code: 'INSUFFICIENT_SERVER_DISK', message: 'Not enough free disk space on the home server' },
        });
      }
      return reply.code(500).send({
        error: { code: 'CHUNK_WRITE_FAILED', message: 'Failed to store uploaded chunk' },
      });
    } finally {
      activeChunkLocks.delete(uploadId);
    }

    meta.bytesReceived = offset + chunkBytes;
    meta.updatedAt = new Date().toISOString();
    writeSessionMetaAtomic(metaPath, meta);

    return {
      uploadId: meta.uploadId,
      bytesReceived: meta.bytesReceived,
      totalBytes: meta.totalBytes,
    };
  });

  // 1e. Chunked upload — finalize file into library (instant rename + thumbnail + DB commit)
  fastify.post('/media/upload/:uploadId/complete', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const uploadId = req.params.uploadId;
    const access = validateUploadSessionAccess(uploadId, req.user.id);
    if (access.error) {
      return reply.code(access.error.statusCode).send({
        error: { code: access.error.code, message: access.error.message },
      });
    }

    if (activeChunkLocks.has(uploadId)) {
      return reply.code(409).send({
        error: { code: 'UPLOAD_IN_PROGRESS', message: 'Upload chunk still writing' },
      });
    }

    const { sessionDir, partPath, meta } = access;
    const finalSize = fs.statSync(partPath).size;
    if (finalSize !== meta.totalBytes || meta.bytesReceived !== meta.totalBytes) {
      return reply.code(400).send({
        error: {
          code: 'INCOMPLETE_UPLOAD',
          message: `Upload is incomplete (${finalSize} of ${meta.totalBytes} bytes received)`,
        },
      });
    }

    const userId = req.user.id;
    const originalFilename = meta.filename;
    const mimeType = meta.mimeType;
    const isVideo = mimeType.startsWith('video/') ||
      ['.mp4', '.mov', '.mkv', '.webm', '.avi', '.3gp'].some(ext => originalFilename.toLowerCase().endsWith(ext));
    const kind = isVideo ? 'video' : 'photo';

    const mediaId = 'm_' + crypto.randomBytes(16).toString('hex');
    const rawExt = path.extname(originalFilename).toLowerCase();
    const ext = /^\.[a-z0-9]{1,10}$/.test(rawExt) ? rawExt : (isVideo ? '.mp4' : '.jpg');

    const userOriginalsDir = path.join(resolvedDataDir, 'users', userId, 'originals');
    const userThumbsDir = path.join(resolvedDataDir, 'users', userId, 'thumbnails');
    fs.mkdirSync(userOriginalsDir, { recursive: true, mode: 0o700 });
    fs.mkdirSync(userThumbsDir, { recursive: true, mode: 0o700 });

    const targetOriginalPath = path.join(userOriginalsDir, `${mediaId}${ext}`);
    const targetThumbPath = path.join(userThumbsDir, `${mediaId}.webp`);

    moveFileSync(partPath, targetOriginalPath);
    try { fs.rmSync(sessionDir, { recursive: true, force: true }); } catch (_) {}

    const result = await finalizeUploadedMedia({
      userId,
      mediaId,
      originalFilename,
      mimeType,
      kind,
      ext,
      takenAt: meta.takenAt,
      bytesWritten: finalSize,
      targetOriginalPath,
      targetThumbPath,
      userThumbsDir,
    });

    return reply.code(result.statusCode).send(result.body);
  });

  // 1f. Chunked upload — cancel and immediately free temp storage
  fastify.delete('/media/upload/:uploadId', {
    preHandler: [fastify.authenticate],
  }, async (req, reply) => {
    const uploadId = req.params.uploadId;
    const access = validateUploadSessionAccess(uploadId, req.user.id);
    if (access.error) {
      if (access.error.statusCode === 404) {
        return { canceled: true };
      }
      return reply.code(access.error.statusCode).send({
        error: { code: access.error.code, message: access.error.message },
      });
    }

    try {
      fs.rmSync(access.sessionDir, { recursive: true, force: true });
    } catch (_) {}

    return { canceled: true };
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
