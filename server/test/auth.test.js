import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

test('Authentication & Quotas flow', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-auth-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
    DEFAULT_USER_QUOTA_BYTES: '5000000000', // 5 GB
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  let userToken = '';
  let userId = '';

  await t.test('POST /api/auth/register validates payload', async () => {
    // Bad email
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'invalid-email', password: 'password123', name: 'Alice' },
    });
    assert.equal(res1.statusCode, 400);

    // Short password
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'alice@test.com', password: 'short', name: 'Alice' },
    });
    assert.equal(res2.statusCode, 400);

    // Missing name
    const res3 = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: { email: 'alice@test.com', password: 'password123', name: '' },
    });
    assert.equal(res3.statusCode, 400);
  });

  await t.test('POST /api/auth/register successfully creates user and directory', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'alice@homespace.local',
        password: 'securepassword123',
        name: 'Alice Family',
        avatarTone: 'orange',
      },
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.token);
    assert.ok(body.user.id);
    assert.equal(body.user.email, 'alice@homespace.local');
    assert.equal(body.user.name, 'Alice Family');
    assert.equal(body.user.storageQuotaBytes, 5000000000);
    assert.equal(body.user.storageUsedBytes, 0);

    userId = body.user.id;
    userToken = body.token;

    // Verify physical folder exists
    assert.ok(fs.existsSync(path.join(tmpDir, 'users', userId, 'originals')));
    assert.ok(fs.existsSync(path.join(tmpDir, 'users', userId, 'thumbnails')));
  });

  await t.test('POST /api/auth/register rejects duplicate email', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'ALICE@homespace.local', // check case-insensitivity
        password: 'anotherpassword123',
        name: 'Alice Duplicate',
      },
    });

    assert.equal(res.statusCode, 409);
    const body = JSON.parse(res.payload);
    assert.equal(body.error.code, 'EMAIL_EXISTS');
  });

  await t.test('POST /api/auth/login verifies credentials', async () => {
    // Wrong password
    const wrong = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: {
        email: 'alice@homespace.local',
        password: 'wrongpassword',
      },
    });
    assert.equal(wrong.statusCode, 401);

    // Correct password
    const correct = await app.inject({
      method: 'POST',
      url: '/api/auth/login',
      payload: {
        email: 'alice@homespace.local',
        password: 'securepassword123',
      },
    });
    assert.equal(correct.statusCode, 200);
    const body = JSON.parse(correct.payload);
    assert.ok(body.token);
    assert.equal(body.user.id, userId);
  });

  await t.test('GET /api/auth/me returns profile and live storage quota', async () => {
    // Without token
    const unauth = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
    });
    assert.equal(unauth.statusCode, 401);

    // With token
    const auth = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: {
        authorization: `Bearer ${userToken}`,
      },
    });
    assert.equal(auth.statusCode, 200);
    const body = JSON.parse(auth.payload);
    assert.equal(body.user.id, userId);
    assert.equal(body.user.storage.quotaBytes, 5000000000);
    assert.equal(body.user.storage.usedBytes, 0);
    assert.equal(body.user.storage.percentUsed, 0);
  });

  await t.test('POST /api/auth/logout revokes session', async () => {
    const logoutRes = await app.inject({
      method: 'POST',
      url: '/api/auth/logout',
      headers: {
        authorization: `Bearer ${userToken}`,
      },
    });
    assert.equal(logoutRes.statusCode, 200);

    // Subsequent call with same token must fail
    const meRes = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: {
        authorization: `Bearer ${userToken}`,
      },
    });
    assert.equal(meRes.statusCode, 401);
  });
});
