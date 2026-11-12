import fs from 'node:fs';
import path from 'node:path';

// Enforce strict alphanumeric + hyphen/underscore IDs to prevent path traversal
const SAFE_ID_REGEX = /^[a-zA-Z0-9_-]{1,64}$/;

export function sanitizeUserId(userId) {
  if (!userId || typeof userId !== 'string' || !SAFE_ID_REGEX.test(userId)) {
    throw new Error('Invalid user ID');
  }
  return userId;
}

export function getUserDirs(dataDir, userId) {
  const safeId = sanitizeUserId(userId);
  const userBase = path.join(dataDir, 'users', safeId);
  const originals = path.join(userBase, 'originals');
  const thumbnails = path.join(userBase, 'thumbnails');

  // Ensure directories exist
  if (!fs.existsSync(originals)) {
    fs.mkdirSync(originals, { recursive: true });
  }
  if (!fs.existsSync(thumbnails)) {
    fs.mkdirSync(thumbnails, { recursive: true });
  }

  return {
    base: userBase,
    originals,
    thumbnails,
  };
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
