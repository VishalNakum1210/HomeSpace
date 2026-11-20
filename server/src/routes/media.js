import crypto from 'node:crypto';
import fs from 'node:fs';
import path from 'node:path';
import { execFile } from 'node:child_process';
import { pipeline } from 'node:stream/promises';
import sharp from 'sharp';
import { getMediaPaths, deleteMediaFiles, checkQuota, updateStorageUsage, sanitizeMediaId, sanitizeUserId, ALLOWED_MIME_TYPES, EXTENSION_MAP, validateMagicBytes } from '../storage.js';

export function parseExifDate(exifBuffer) {
  if (!exifBuffer || !Buffer.isBuffer(exifBuffer)) return null;
  try {
    const exifStr = exifBuffer.toString('binary');
    const match = exifStr.match(/(\d{4}):(\d{2}):(\d{2}) (\d{2}):(\d{2}):(\d{2})/);
    if (match) {
      const [_, year, month, day, hour, min, sec] = match;
      const y = parseInt(year, 10);
      if (y >= 1900 && y <= 2100) {
        const iso = `${year}-${month}-${day}T${hour}:${min}:${sec}.000Z`;
        const date = new Date(iso);
        if (!isNaN(date.getTime())) {
          return date.toISOString();
        }
      }
    }
  } catch (_) {}
  return null;
}

export function parseDateFromFileName(filename) {
  if (!filename || typeof filename !== 'string') return null;
  const match = filename.match(/(\d{4})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})/);
  if (match) {
    const [_, year, month, day, hour, min, sec] = match;
    const y = parseInt(year, 10);
    const m = parseInt(month, 10);
    const d = parseInt(day, 10);
    if (y >= 1970 && y <= 2100 && m >= 1 && m <= 12 && d >= 1 && d <= 31) {
      const iso = `${year}-${month}-${day}T${hour}:${min}:${sec}.000Z`;
      const date = new Date(iso);
      if (!isNaN(date.getTime())) return date.toISOString();
    }
  }
  return null;
}

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

  // 1. Upload media item (allow up to 5GB video/photo payloads)
  fastify.post('/media/upload', { bodyLimit: 5 * 1024 * 1024 * 1024 }, async (req, reply) => {
    let tempUploadPath = null;
    let thumbBuffer = null;
    let filename = '';
    let mimeType = '';
    const formFields = {};

    const uploadTempDir = path.join(dataDir, 'users', sanitizeUserId(req.user.id), 'temp');
    if (!fs.existsSync(uploadTempDir)) fs.mkdirSync(uploadTempDir, { recursive: true });
    const tempFileId = 'tmp_' + crypto.randomBytes(8).toString('hex');
    const targetTempPath = path.join(uploadTempDir, tempFileId);

    try {
      if (req.isMultipart()) {
        for await (const part of req.parts()) {
          if (part.type === 'file') {
            if (part.fieldname === 'thumb' || part.fieldname === 'thumbnail') {
              thumbBuffer = await part.toBuffer();
            } else {
              filename = part.filename;
              mimeType = part.mimetype;
              const outStream = fs.createWriteStream(targetTempPath);
              await pipeline(part.file, outStream);
              tempUploadPath = targetTempPath;
            }
          } else {
            formFields[part.fieldname] = part.value;
          }
        }
      } else {
        const data = await req.file();
        if (data) {
          filename = data.filename;
          mimeType = data.mimetype;
          const outStream = fs.createWriteStream(targetTempPath);
          await pipeline(data.file, outStream);
          tempUploadPath = targetTempPath;
        }
      }
    } catch (streamErr) {
      if (fs.existsSync(targetTempPath)) {
        try { fs.unlinkSync(targetTempPath); } catch (_) {}
      }
      throw streamErr;
    }

    if (!tempUploadPath || !fs.existsSync(tempUploadPath)) {
      return reply.code(400).send({
        error: { code: 'NO_FILE', message: 'No file uploaded' },
      });
    }

    const stat = fs.statSync(tempUploadPath);
    if (stat.size === 0) {
      if (fs.existsSync(tempUploadPath)) {
        try { fs.unlinkSync(tempUploadPath); } catch (_) {}
      }
      return reply.code(400).send({
        error: { code: 'NO_FILE', message: 'Uploaded file is empty' },
      });
    }

    if ((!mimeType || mimeType === 'application/octet-stream') && filename) {
      const fileExt = path.extname(filename).toLowerCase().replace('.', '');
      const reverseMap = {
        jpg: 'image/jpeg',
        jpeg: 'image/jpeg',
        png: 'image/png',
        webp: 'image/webp',
        gif: 'image/gif',
        heic: 'image/heic',
        avif: 'image/avif',
        mp4: 'video/mp4',
        mov: 'video/quicktime',
        webm: 'video/webm',
        mkv: 'video/x-matroska',
        '3gp': 'video/3gpp',
        avi: 'video/x-msvideo',
      };
      if (reverseMap[fileExt]) mimeType = reverseMap[fileExt];
    }
    // 1. Validate magic bytes from binary header to prevent MIME spoofing or disguised scripts
    const verifiedMagicMime = validateMagicBytes(tempUploadPath);
    if (verifiedMagicMime) {
      mimeType = verifiedMagicMime;
    } else if (!ALLOWED_MIME_TYPES.has(mimeType)) {
      if (fs.existsSync(tempUploadPath)) {
        try { fs.unlinkSync(tempUploadPath); } catch (_) {}
      }
      return reply.code(415).send({
        error: {
          code: 'UNSUPPORTED_MEDIA_TYPE',
          message: `Unsupported or corrupted media format. Supported: JPEG, PNG, WebP, GIF, HEIC, AVIF, MP4, MOV, WebM, MKV`,
        },
      });
    }

    const byteSize = stat.size;
    const ext = EXTENSION_MAP[mimeType] || 'jpg';
    const originalFileName = filename || `photo_${Date.now()}.${ext}`;

    // 1. Deduplication check: Check if user already uploaded this file (e.g. retry after client timeout)
    const existing = db.prepare(`
      SELECT * FROM media
      WHERE user_id = ? AND file_name = ? AND is_trashed = 0
      ORDER BY created_at DESC
      LIMIT 1
    `).get(req.user.id, originalFileName);

    if (existing) {
      const sizeDiff = Math.abs(existing.byte_size - byteSize);
      if (sizeDiff < 500 * 1024) {
        // File already exists on server! Clean up temp upload file and return existing record
        if (fs.existsSync(tempUploadPath)) {
          try { fs.unlinkSync(tempUploadPath); } catch (_) {}
        }
        return reply.code(200).send({
          id: existing.id,
          userId: existing.user_id,
          fileName: existing.file_name,
          mimeType: existing.mime_type,
          byteSize: existing.byte_size,
          width: existing.width,
          height: existing.height,
          takenAt: existing.taken_at,
          createdAt: existing.created_at,
          isFavorite: Boolean(existing.is_favorite),
          isTrashed: Boolean(existing.is_trashed),
        });
      }
    }

    // Estimate total size with thumbnail (~80KB thumbnail estimate)
    const estimatedTotalBytes = byteSize + 80 * 1024;
    const quotaCheck = checkQuota(db, req.user.id, estimatedTotalBytes);
    if (!quotaCheck.allowed) {
      if (fs.existsSync(tempUploadPath)) {
        try { fs.unlinkSync(tempUploadPath); } catch (_) {}
      }
      return reply.code(413).send({
        error: {
          code: 'QUOTA_EXCEEDED',
          message: `Storage quota exceeded. Free space: ${(quotaCheck.remainingBytes / (1024 * 1024)).toFixed(1)} MB, Upload requires: ${(byteSize / (1024 * 1024)).toFixed(1)} MB`,
        },
      });
    }

    const mediaId = 'm_' + crypto.randomBytes(8).toString('hex');
    const paths = getMediaPaths(dataDir, req.user.id, mediaId, ext);

    // Atomically move streamed temp upload file into user's originals storage and enforce non-executable 0o600 permissions
    fs.renameSync(tempUploadPath, paths.original);
    try { fs.chmodSync(paths.original, 0o600); } catch (_) {}

    const isVideo = mimeType.startsWith('video/');
    let width = 0;
    let height = 0;
    let thumbSize = 0;
    let imageExif = null;

    try {
      if (isVideo) {
        if (thumbBuffer && thumbBuffer.length > 0) {
          await sharp(thumbBuffer)
            .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
            .webp({ quality: 80 })
            .toFile(paths.thumbnail);
          await sharp(thumbBuffer)
            .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true })
            .webp({ quality: 85 })
            .toFile(paths.preview);
        } else {
          // If no thumb uploaded with video, extract via ffmpeg or generate slick poster card
          const ffmpegInstalled = await new Promise((resolve) => {
            execFile('ffmpeg', ['-version'], (err) => resolve(!err));
          });
          let extracted = false;
          if (ffmpegInstalled) {
            try {
              await new Promise((resolve, reject) => {
                execFile(
                  'ffmpeg',
                  ['-y', '-ss', '00:00:01', '-i', paths.original, '-vframes', '1', '-f', 'image2', paths.thumbnail],
                  (err) => {
                    if (err) reject(err);
                    else resolve();
                  }
                );
              });
              extracted = fs.existsSync(paths.thumbnail) && fs.statSync(paths.thumbnail).size > 0;
              if (extracted) {
                fs.copyFileSync(paths.thumbnail, paths.preview);
              }
            } catch (_) {}
          }
          if (!extracted) {
            // Sleek fallback: Generate an artistic SVG/WebP video poster with play badge
            const posterSvg = `<svg width="400" height="400" viewBox="0 0 400 400" xmlns="http://www.w3.org/2000/svg">
              <defs>
                <linearGradient id="grad" x1="0%" y1="0%" x2="100%" y2="100%">
                  <stop offset="0%" stop-color="#1E293B" />
                  <stop offset="100%" stop-color="#0F172A" />
                </linearGradient>
              </defs>
              <rect width="100%" height="100%" fill="url(#grad)" />
              <circle cx="200" cy="200" r="48" fill="rgba(255,255,255,0.2)" />
              <polygon points="188,176 224,200 188,224" fill="#FFFFFF" />
            </svg>`;
            await sharp(Buffer.from(posterSvg))
              .resize(400, 400)
              .webp({ quality: 80 })
              .toFile(paths.thumbnail);
            fs.copyFileSync(paths.thumbnail, paths.preview);
          }
        }
      } else {
        // Image processing: Sharp streams directly from paths.original file on disk (0 RAM buffering)
        const image = sharp(paths.original);
        const metadata = await image.metadata();
        width = metadata.width || 0;
        height = metadata.height || 0;

        await image
          .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 80 })
          .toFile(paths.thumbnail);

        setImmediate(async () => {
          try {
            await sharp(paths.original)
              .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true })
              .webp({ quality: 85 })
              .toFile(paths.preview);
          } catch (_) {}
        });

        if (metadata.exif) {
          imageExif = metadata.exif;
        }
      }

      const thumbStat = fs.statSync(paths.thumbnail);
      thumbSize = thumbStat.size;
      try { fs.chmodSync(paths.thumbnail, 0o600); } catch (_) {}
      if (fs.existsSync(paths.preview)) {
        try { fs.chmodSync(paths.preview, 0o600); } catch (_) {}
      }
    } catch (err) {
      // Cleanup on failure
      if (fs.existsSync(paths.original)) fs.unlinkSync(paths.original);
      if (fs.existsSync(paths.thumbnail)) fs.unlinkSync(paths.thumbnail);
      if (fs.existsSync(paths.preview)) fs.unlinkSync(paths.preview);
      throw err;
    }

    const actualTotalBytes = byteSize + thumbSize;
    const now = new Date().toISOString();
    const originalFileName = filename || `photo_${Date.now()}.${ext}`;

    // Resolve takenAt: 1) Client provided, 2) EXIF metadata, 3) Current timestamp
    let resolvedTakenAt = null;
    const clientDateStr =
      req.query?.takenAt ||
      req.headers?.['x-taken-at'] ||
      formFields.takenAt;

    if (clientDateStr && typeof clientDateStr === 'string') {
      const parsed = new Date(clientDateStr);
      if (!isNaN(parsed.getTime())) {
        const maxFuture = Date.now() + 24 * 60 * 60 * 1000;
        if (parsed.getTime() <= maxFuture && parsed.getFullYear() >= 1900) {
          resolvedTakenAt = parsed.toISOString();
        }
      }
    }

    if (!resolvedTakenAt && imageExif) {
      resolvedTakenAt = parseExifDate(imageExif);
    }

    if (!resolvedTakenAt) {
      resolvedTakenAt = parseDateFromFileName(originalFileName);
    }

    if (!resolvedTakenAt) {
      resolvedTakenAt = now;
    }

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
      resolvedTakenAt,
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
      takenAt: resolvedTakenAt,
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
      if (fs.existsSync(paths.original) && media.mime_type.startsWith('image/')) {
        try {
          await sharp(paths.original)
            .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
            .webp({ quality: 80 })
            .toFile(paths.thumbnail);
        } catch (_) {
          reply.header('Content-Type', media.mime_type);
          return reply.send(fs.createReadStream(paths.original));
        }
      } else if (media.mime_type.startsWith('video/') && fs.existsSync(paths.original)) {
        try {
          await new Promise((resolve, reject) => {
            execFile('ffmpeg', [
              '-ss', '00:00:01',
              '-i', paths.original,
              '-vframes', '1',
              '-vf', 'scale=400:400:force_original_aspect_ratio=decrease',
              '-q:v', '2',
              '-y',
              paths.thumbnail,
            ], (err) => {
              if (err) reject(err);
              else resolve();
            });
          });
        } catch (_) {
          // If ffmpeg fails or is not installed, generate a WebP video poster
          const posterSvg = `
          <svg width="400" height="400" xmlns="http://www.w3.org/2000/svg">
            <rect width="400" height="400" fill="#1b2838"/>
            <circle cx="200" cy="200" r="50" fill="#2A3B4C"/>
            <polygon points="190,178 190,222 226,200" fill="#FFFFFF"/>
          </svg>`;
          try {
            await sharp(Buffer.from(posterSvg)).webp({ quality: 80 }).toFile(paths.thumbnail);
          } catch (_) {
            return reply.code(404).send({
              error: { code: 'NOT_FOUND', message: 'Thumbnail file missing' },
            });
          }
        }
      } else if (fs.existsSync(paths.preview) && !media.mime_type.startsWith('video/')) {
        reply.header('Content-Type', 'image/webp');
        return reply.send(fs.createReadStream(paths.preview));
      } else {
        return reply.code(404).send({
          error: { code: 'NOT_FOUND', message: 'Thumbnail file missing' },
        });
      }
    }

    reply.header('Content-Type', 'image/webp');
    reply.header('Cache-Control', 'private, max-age=86400');
    return reply.send(fs.createReadStream(paths.thumbnail));
  });

  // 4b. Upload / update thumbnail for an existing media item (especially videos)
  fastify.put('/media/:id/thumb', async (req, reply) => {
    const media = canAccessMedia(db, req.user.id, req.params.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found or access denied' },
      });
    }

    const data = await req.file();
    if (!data) {
      return reply.code(400).send({
        error: { code: 'NO_FILE', message: 'No thumbnail uploaded' },
      });
    }

    const buffer = await data.toBuffer();
    const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
    const paths = getMediaPaths(dataDir, media.user_id, media.id, ext);

    await sharp(buffer)
      .resize(400, 400, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 80 })
      .toFile(paths.thumbnail);

    await sharp(buffer)
      .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true })
      .webp({ quality: 85 })
      .toFile(paths.preview);

    try {
      fs.chmodSync(paths.thumbnail, 0o600);
      fs.chmodSync(paths.preview, 0o600);
    } catch (_) {}

    return { success: true, id: media.id };
  });

  // 4b. Stream preview (fast 1600px screen-fit WebP image, Google Photos technique)
  fastify.get('/media/:id/preview', async (req, reply) => {
    const media = canAccessMedia(db, req.user.id, req.params.id);
    if (!media) {
      return reply.code(404).send({
        error: { code: 'NOT_FOUND', message: 'Media item not found or access denied' },
      });
    }

    const ext = EXTENSION_MAP[media.mime_type] || 'jpg';
    const paths = getMediaPaths(dataDir, media.user_id, media.id, ext);

    // If preview already generated, stream directly
    if (fs.existsSync(paths.preview)) {
      reply.header('Content-Type', 'image/webp');
      reply.header('Cache-Control', 'private, max-age=604800'); // Cache for 7 days
      return reply.send(fs.createReadStream(paths.preview));
    }

    // On-the-fly generation fallback if preview does not exist yet but original exists
    if (fs.existsSync(paths.original)) {
      try {
        await sharp(paths.original)
          .resize(1600, 1600, { fit: 'inside', withoutEnlargement: true })
          .webp({ quality: 85 })
          .toFile(paths.preview);

        reply.header('Content-Type', 'image/webp');
        reply.header('Cache-Control', 'private, max-age=604800');
        return reply.send(fs.createReadStream(paths.preview));
      } catch (err) {
        // Fallback to original if sharp fails
        reply.header('Content-Type', media.mime_type);
        return reply.send(fs.createReadStream(paths.original));
      }
    }

    return reply.code(404).send({
      error: { code: 'NOT_FOUND', message: 'Media file missing' },
    });
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
    reply.header('Cache-Control', 'public, max-age=604800, immutable');

    if (range) {
      const parts = range.replace(/bytes=/, '').split('-');
      const start = parseInt(parts[0], 10);
      if (isNaN(start) || start < 0 || start >= stat.size) {
        reply.header('Content-Range', `bytes */${stat.size}`);
        return reply.code(416).send({ error: { code: 'RANGE_NOT_SATISFIABLE' } });
      }

      // If client requests open-ended range (e.g. "bytes=0-"), cap chunk size to 16MB.
      // 16MB provides smooth buffer-free video playback for high-bitrate phone videos,
      // avoiding frequent round-trip stalls while keeping memory and socket overhead low.
      const CHUNK_SIZE = 16 * 1024 * 1024;
      const explicitEnd = parts[1] ? parseInt(parts[1], 10) : NaN;
      const end = !isNaN(explicitEnd) ? Math.min(explicitEnd, stat.size - 1) : Math.min(start + CHUNK_SIZE - 1, stat.size - 1);
      const chunksize = end - start + 1;

      reply.code(206);
      reply.header('Content-Range', `bytes ${start}-${end}/${stat.size}`);
      reply.header('Content-Length', chunksize);
      const stream = fs.createReadStream(paths.original, { start, end });
      req.raw.on('close', () => {
        stream.destroy();
      });
      return reply.send(stream);
    }

    reply.header('Content-Length', stat.size);
    const fullStream = fs.createReadStream(paths.original);
    req.raw.on('close', () => {
      fullStream.destroy();
    });
    return reply.send(fullStream);
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
