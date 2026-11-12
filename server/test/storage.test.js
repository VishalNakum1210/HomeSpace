import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { getUserDirs, sanitizeUserId, checkQuota, updateStorageUsage } from '../src/storage.js';

test('Storage module: directory isolation and safety', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-storage-test-'));

  t.after(() => {
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  await t.test('rejects malicious or traversing user IDs', () => {
    assert.throws(() => sanitizeUserId('../hack'), /Invalid user ID/);
    assert.throws(() => sanitizeUserId('user/123'), /Invalid user ID/);
    assert.throws(() => sanitizeUserId(''), /Invalid user ID/);
    assert.throws(() => sanitizeUserId('user\\traversal'), /Invalid user ID/);
    assert.equal(sanitizeUserId('u_12345678_valid'), 'u_12345678_valid');
  });

  await t.test('provisions user directories physically on disk', () => {
    const dirs = getUserDirs(tmpDir, 'user_alice');
    assert.ok(fs.existsSync(dirs.base));
    assert.ok(fs.existsSync(dirs.originals));
    assert.ok(fs.existsSync(dirs.thumbnails));
    assert.equal(dirs.originals, path.join(tmpDir, 'users', 'user_alice', 'originals'));
    assert.equal(dirs.thumbnails, path.join(tmpDir, 'users', 'user_alice', 'thumbnails'));
  });

  await t.test('computes quota correctly and rejects overflow', () => {
    const db = initDatabase(':memory:');
    const now = new Date().toISOString();

    db.prepare(`
      INSERT INTO users (id, email, password_hash, password_salt, name, storage_quota_bytes, storage_used_bytes, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?)
    `).run('u_bob', 'bob@test.com', 'h', 's', 'Bob', 1000, 800, now, now);

    // 800 used out of 1000. 150 incoming should be allowed (total 950 <= 1000)
    const check1 = checkQuota(db, 'u_bob', 150);
    assert.equal(check1.allowed, true);
    assert.equal(check1.usedBytes, 800);
    assert.equal(check1.quotaBytes, 1000);
    assert.equal(check1.remainingBytes, 200);

    // 250 incoming should be rejected (total 1050 > 1000)
    const check2 = checkQuota(db, 'u_bob', 250);
    assert.equal(check2.allowed, false);

    // Update storage delta +150
    const updated = updateStorageUsage(db, 'u_bob', 150);
    assert.equal(updated.usedBytes, 950);

    // Check again
    const check3 = checkQuota(db, 'u_bob', 100);
    assert.equal(check3.allowed, false);
    assert.equal(check3.remainingBytes, 50);

    // Reduce storage delta -500 (e.g. after deletion)
    const reduced = updateStorageUsage(db, 'u_bob', -500);
    assert.equal(reduced.usedBytes, 450);
  });
});
