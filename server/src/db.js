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
  `);

  return db;
}
