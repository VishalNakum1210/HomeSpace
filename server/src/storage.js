import fs from 'node:fs';
import path from 'node:path';

// Enforce strict alphanumeric + hyphen/underscore IDs to prevent path traversal
const SAFE_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

export const ALLOWED_MIME_TYPES = new Set([
  'image/jpeg',
  'image/png',
  'image/webp',
  'image/gif',
  'image/heic',
  'image/avif',
  'video/mp4',
  'video/webm',
  'video/quicktime',
  'video/x-matroska',
  'video/3gpp',
  'video/x-msvideo',
]);

export const EXTENSION_MAP = {
  'image/jpeg': 'jpg',
  'image/png': 'png',
  'image/webp': 'webp',
  'image/gif': 'gif',
  'image/heic': 'heic',
  'image/avif': 'avif',
  'video/mp4': 'mp4',
  'video/webm': 'webm',
  'video/quicktime': 'mov',
  'video/x-matroska': 'mkv',
  'video/3gpp': '3gp',
  'video/x-msvideo': 'avi',
};

export function validateMagicBytes(filePath) {
  let fd;
  try {
    fd = fs.openSync(filePath, 'r');
    const buffer = Buffer.alloc(32);
    const bytesRead = fs.readSync(fd, buffer, 0, 32, 0);
    if (bytesRead < 4) return null;

    // JPEG: FF D8 FF
    if (buffer[0] === 0xff && buffer[1] === 0xd8 && buffer[2] === 0xff) {
      return 'image/jpeg';
    }

    // PNG: 89 50 4E 47 0D 0A 1A 0A
    if (
      bytesRead >= 8 &&
      buffer[0] === 0x89 &&
      buffer[1] === 0x50 &&
      buffer[2] === 0x4e &&
      buffer[3] === 0x47 &&
      buffer[4] === 0x0d &&
      buffer[5] === 0x0a &&
      buffer[6] === 0x1a &&
      buffer[7] === 0x0a
    ) {
      return 'image/png';
    }

    // GIF: GIF87a or GIF89a
    if (
      buffer[0] === 0x47 &&
      buffer[1] === 0x49 &&
      buffer[2] === 0x46 &&
      buffer[3] === 0x38
    ) {
      return 'image/gif';
    }

    // WebP: RIFF .... WEBP
    if (
      bytesRead >= 12 &&
      buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
      buffer.subarray(8, 12).toString('ascii') === 'WEBP'
    ) {
      return 'image/webp';
    }

    // MKV / WebM: 1A 45 DF A3 (EBML)
    if (
      buffer[0] === 0x1a &&
      buffer[1] === 0x45 &&
      buffer[2] === 0xdf &&
      buffer[3] === 0xa3
    ) {
      return 'video/webm';
    }

    // ISO Base Media File Format: MP4, MOV, HEIC, AVIF, 3GP
    if (bytesRead >= 12 && buffer.subarray(4, 8).toString('ascii') === 'ftyp') {
      const brand = buffer.subarray(8, 12).toString('ascii').toLowerCase();
      if (brand.startsWith('heic') || brand.startsWith('heix') || brand.startsWith('mif1')) {
        return 'image/heic';
      }
      if (brand.startsWith('avif') || brand.startsWith('avis')) {
        return 'image/avif';
      }
      if (brand.startsWith('qt')) {
        return 'video/quicktime';
      }
      if (brand.startsWith('3g')) {
        return 'video/3gpp';
      }
      return 'video/mp4';
    }

    // QuickTime alternate atom header: moov, wide, mdat at offset 4
    const atom = buffer.subarray(4, 8).toString('ascii');
    if (atom === 'moov' || atom === 'mdat' || atom === 'wide' || atom === 'skip') {
      return 'video/quicktime';
    }

    // AVI: RIFF .... AVI
    if (
      bytesRead >= 12 &&
      buffer.subarray(0, 4).toString('ascii') === 'RIFF' &&
      buffer.subarray(8, 12).toString('ascii') === 'AVI '
    ) {
      return 'video/x-msvideo';
    }

    return null;
  } catch (_) {
    return null;
  } finally {
    if (fd !== undefined) {
      try { fs.closeSync(fd); } catch (_) {}
    }
  }
}

export function sanitizeUserId(userId) {
  if (!userId || typeof userId !== 'string' || !SAFE_ID_REGEX.test(userId)) {
    throw new Error('Invalid user ID');
  }
  return userId;
}

export function sanitizeMediaId(mediaId) {
  if (!mediaId || typeof mediaId !== 'string' || !SAFE_ID_REGEX.test(mediaId)) {
    throw new Error('Invalid media ID');
  }
  return mediaId;
}

export function getUserDirs(dataDir, userId) {
  const safeId = sanitizeUserId(userId);
  const userBase = path.join(dataDir, 'users', safeId);
  const originals = path.join(userBase, 'originals');
  const thumbnails = path.join(userBase, 'thumbnails');
  const previews = path.join(userBase, 'previews');

  // Ensure directories exist with restricted 0o700 owner-only permissions
  if (!fs.existsSync(originals)) {
    fs.mkdirSync(originals, { recursive: true, mode: 0o700 });
  }
  if (!fs.existsSync(thumbnails)) {
    fs.mkdirSync(thumbnails, { recursive: true, mode: 0o700 });
  }
  if (!fs.existsSync(previews)) {
    fs.mkdirSync(previews, { recursive: true, mode: 0o700 });
  }

  return {
    base: userBase,
    originals,
    thumbnails,
    previews,
  };
}

export function getMediaPaths(dataDir, userId, mediaId, ext = 'jpg') {
  const dirs = getUserDirs(dataDir, userId);
  const safeMid = sanitizeMediaId(mediaId);
  const cleanExt = ext.replace(/^\./, '');
  
  return {
    original: path.join(dirs.originals, `${safeMid}.${cleanExt}`),
    thumbnail: path.join(dirs.thumbnails, `${safeMid}.webp`),
    preview: path.join(dirs.previews, `${safeMid}.webp`),
  };
}

export function deleteMediaFiles(dataDir, userId, mediaId, ext = 'jpg') {
  const paths = getMediaPaths(dataDir, userId, mediaId, ext);
  if (fs.existsSync(paths.original)) {
    fs.unlinkSync(paths.original);
  }
  if (fs.existsSync(paths.thumbnail)) {
    fs.unlinkSync(paths.thumbnail);
  }
  if (fs.existsSync(paths.preview)) {
    fs.unlinkSync(paths.preview);
  }
}

export function checkQuota(db, userId, incomingBytes = 0) {
  const safeId = sanitizeUserId(userId);
  const stmt = db.prepare('SELECT storage_used_bytes, storage_quota_bytes FROM users WHERE id = ?');
  const user = stmt.get(safeId);

  if (!user) {
    throw new Error('User not found');
  }

  const used = Number(user.storage_used_bytes || 0);
  const quota = Number(user.storage_quota_bytes || 0);
  const remaining = Math.max(0, quota - used);
  const wouldExceed = used + incomingBytes > quota;

  return {
    allowed: !wouldExceed,
    usedBytes: used,
    quotaBytes: quota,
    remainingBytes: remaining,
    percentUsed: quota > 0 ? (used / quota) * 100 : 0,
  };
}

export function updateStorageUsage(db, userId, deltaBytes) {
  const safeId = sanitizeUserId(userId);
  const now = new Date().toISOString();
  
  const stmt = db.prepare(`
    UPDATE users 
    SET storage_used_bytes = MAX(0, storage_used_bytes + ?),
        updated_at = ?
    WHERE id = ?
  `);
  stmt.run(deltaBytes, now, safeId);

  const check = db.prepare('SELECT storage_used_bytes, storage_quota_bytes FROM users WHERE id = ?').get(safeId);
  return {
    usedBytes: Number(check.storage_used_bytes),
    quotaBytes: Number(check.storage_quota_bytes),
  };
}
