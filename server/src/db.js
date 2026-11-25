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

  // Schema migrations for authentication
  db.exec(`
    CREATE TABLE IF NOT EXISTS users (
      id TEXT PRIMARY KEY,
      email TEXT UNIQUE COLLATE NOCASE NOT NULL,
      password_hash TEXT NOT NULL,
      password_salt TEXT NOT NULL,
      name TEXT NOT NULL,
      avatar_tone TEXT NOT NULL DEFAULT 'orange',
      is_admin INTEGER NOT NULL DEFAULT 0,
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

    CREATE INDEX IF NOT EXISTS idx_sessions_token_hash ON sessions(token_hash);

    CREATE TABLE IF NOT EXISTS media (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      filename TEXT NOT NULL,
      mime_type TEXT NOT NULL,
      size_bytes INTEGER NOT NULL,
      taken_at TEXT NOT NULL,
      kind TEXT NOT NULL DEFAULT 'photo',
      original_path TEXT NOT NULL,
      thumbnail_path TEXT,
      is_favorite INTEGER NOT NULL DEFAULT 0,
      is_trashed INTEGER NOT NULL DEFAULT 0,
      trashed_at TEXT,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE INDEX IF NOT EXISTS idx_media_user_timeline ON media(user_id, is_trashed, taken_at DESC);
    CREATE INDEX IF NOT EXISTS idx_media_user_favorites ON media(user_id, is_favorite, is_trashed, taken_at DESC);

    CREATE TABLE IF NOT EXISTS albums (
      id TEXT PRIMARY KEY,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      title TEXT NOT NULL,
      description TEXT NOT NULL DEFAULT '',
      cover_media_id TEXT REFERENCES media(id) ON DELETE SET NULL,
      is_shared INTEGER NOT NULL DEFAULT 0,
      created_at TEXT NOT NULL,
      updated_at TEXT NOT NULL
    );

    CREATE TABLE IF NOT EXISTS album_media (
      album_id TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
      media_id TEXT NOT NULL REFERENCES media(id) ON DELETE CASCADE,
      added_at TEXT NOT NULL,
      PRIMARY KEY (album_id, media_id)
    );

    CREATE INDEX IF NOT EXISTS idx_album_media_media ON album_media(media_id);

    CREATE TABLE IF NOT EXISTS album_members (
      album_id TEXT NOT NULL REFERENCES albums(id) ON DELETE CASCADE,
      user_id TEXT NOT NULL REFERENCES users(id) ON DELETE CASCADE,
      role TEXT NOT NULL DEFAULT 'viewer',
      added_by TEXT REFERENCES users(id) ON DELETE SET NULL,
      created_at TEXT NOT NULL,
      PRIMARY KEY (album_id, user_id)
    );

    CREATE INDEX IF NOT EXISTS idx_album_members_user ON album_members(user_id);
  `);

  try {
    db.exec('ALTER TABLE albums ADD COLUMN is_shared INTEGER NOT NULL DEFAULT 0;');
  } catch (_) {}

  try {
    db.exec('ALTER TABLE users ADD COLUMN is_admin INTEGER NOT NULL DEFAULT 0;');
  } catch (_) {}

  return db;
}
