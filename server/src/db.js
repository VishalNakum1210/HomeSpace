import { DatabaseSync } from 'node:sqlite';
import fs from 'node:fs';
import path from 'node:path';

export function initDatabase(dbPath = ':memory:') {
  if (dbPath !== ':memory:') {
    const parentDir = path.dirname(dbPath);
    if (!fs.existsSync(parentDir)) {
      fs.mkdirSync(parentDir, { recursive: true, mode: 0o700 });
    }
  }

  const db = new DatabaseSync(dbPath);
  if (dbPath !== ':memory:') {
    try { fs.chmodSync(dbPath, 0o600); } catch (_) {}
  }

  // Performance and integrity pragmas
  db.exec('PRAGMA foreign_keys = ON;');
  db.exec('PRAGMA busy_timeout = 5000;');
  if (dbPath !== ':memory:') {
    db.exec('PRAGMA journal_mode = WAL;');
    db.exec('PRAGMA synchronous = NORMAL;');
  }

  // Schema migrations
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE COLLATE NOCASE NOT NULL,
      password_hash TEXT NOT NULL,
      password_salt TEXT NOT NULL,
      name TEXT NOT NULL,
      avatar_tone TEXT NOT NULL DEFAULT 'orange',
      storage_quota_bytes INTEGER NOT NULL,
      storage_used_bytes INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS sessions (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      token_hash TEXT UNIQUE NOT NULL,
      created_at TEXT NOT NULL,
      expires_at TEXT NOT NULL,
      last_seen_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      file_name TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      byte_size INTEGER NOT NULL,
      width INTEGER NOT NULL DEFAULT 0,
      height INTEGER NOT NULL DEFAULT 0,
      taken_at TEXT NOT NULL,
      created_at TEXT NOT NULL,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      is_trashed INTEGER NOT NULL DEFAULT 0,
      trashed_at TEXT
    );

    CREATE TABLE IF NOT EXISTS albums (
      id TEXT PRIMARY KEY,
      owner_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      cover_media_id TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS album_media (
      album_id TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
      media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      added_at TEXT NOT NULL,
      PRIMARY KEY (album_id, media_id)
    );

    CREATE TABLE IF NOT EXISTS album_members (
      album_id TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role TEXT NOT NULL DEFAULT 'viewer',
      invited_at TEXT NOT NULL,
      PRIMARY KEY (album_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);
    CREATE INDEX IF NOT EXISTS idx_media_user_id ON media(user_id);
    CREATE INDEX IF NOT EXISTS idx_media_is_trashed ON media(is_trashed);
    CREATE INDEX IF NOT EXISTS idx_media_taken_at ON media(taken_at);
    CREATE INDEX IF NOT EXISTS idx_albums_owner_id ON albums(owner_id);
  `);

  // Auto-heal any existing media records where taken_at matches created_at but file_name contains camera timestamp
  try {
    const rows = db.prepare("SELECT id, file_name, taken_at FROM media WHERE file_name LIKE 'IMG_%' OR file_name LIKE 'VID_%' OR file_name LIKE 'PXL_%'").all();
    const updateStmt = db.prepare("UPDATE media SET taken_at = ? WHERE id = ?");
    for (const row of rows) {
      const match = row.file_name.match(/(\d{4})(\d{2})(\d{2})[_-](\d{2})(\d{2})(\d{2})/);
      if (match) {
        const [_, year, month, day, hour, min, sec] = match;
        const iso = `${year}-${month}-${day}T${hour}:${min}:${sec}.000Z`;
        if (row.taken_at !== iso) {
          updateStmt.run(iso, row.id);
        }
      }
    }
  } catch (_) {}

  // Auto-deduplicate any duplicate media rows for the same user and file_name
  try {
    db.exec(`
      DELETE FROM media
      WHERE is_trashed = 0
        AND id NOT IN (
          SELECT MIN(id)
          FROM media
          WHERE is_trashed = 0
          GROUP BY user_id, file_name
        );
    `);
  } catch (_) {}

  return db;
}
