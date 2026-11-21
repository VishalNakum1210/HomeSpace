import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

test('Albums REST API: create, list, details, add/remove media, update, and delete', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-albums-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  let token1 = '';
  let userId1 = '';
  let token2 = '';
  let userId2 = '';
  let testMediaId1 = 'media-test-01';
  let testMediaId2 = 'media-test-02';
  let testMediaId3 = 'media-test-03';
  let createdAlbumId = '';

  // Setup: Register two test users and insert mock media
  await t.test('Setup: register test users & mock media', async () => {
    const res1 = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'user1@homespace.local',
        password: 'password12345',
        name: 'User One',
      },
    });
    assert.equal(res1.statusCode, 201);
    const body1 = JSON.parse(res1.payload);
    token1 = body1.token;
    userId1 = body1.user.id;

    const res2 = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'user2@homespace.local',
        password: 'password12345',
        name: 'User Two',
      },
    });
    assert.equal(res2.statusCode, 201);
    const body2 = JSON.parse(res2.payload);
    token2 = body2.token;
    userId2 = body2.user.id;

    // Insert mock media directly into media table
    const nowIso = new Date().toISOString();
    const insertMedia = db.prepare(`
      INSERT INTO media (id, user_id, filename, mime_type, size_bytes, taken_at, kind, original_path, created_at, updated_at)
      VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    `);
    insertMedia.run(testMediaId1, userId1, 'photo1.jpg', 'image/jpeg', 5000, nowIso, 'photo', 'orig1.jpg', nowIso, nowIso);
    insertMedia.run(testMediaId2, userId1, 'photo2.jpg', 'image/jpeg', 6000, nowIso, 'photo', 'orig2.jpg', nowIso, nowIso);
    insertMedia.run(testMediaId3, userId1, 'photo3.jpg', 'image/jpeg', 7000, nowIso, 'photo', 'orig3.jpg', nowIso, nowIso);
  });

  // 1. POST /api/albums - Create album
  await t.test('POST /api/albums creates virtual album', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/albums',
      headers: { authorization: `Bearer ${token1}` },
      payload: {
        title: 'Summer Vacation 2026',
        description: 'Trip to the coast',
        mediaIds: [testMediaId1, testMediaId2],
      },
    });
    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.album);
    assert.equal(body.album.title, 'Summer Vacation 2026');
    assert.equal(body.album.description, 'Trip to the coast');
    assert.equal(body.album.mediaCount, 2);
    assert.equal(body.album.coverMediaId, testMediaId1);
    assert.equal(body.album.isShared, false);
    createdAlbumId = body.album.id;
  });

  // 2. GET /api/albums - List albums
  await t.test('GET /api/albums returns user albums with media counts', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/albums',
      headers: { authorization: `Bearer ${token1}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.total, 1);
    assert.equal(body.albums[0].id, createdAlbumId);
    assert.equal(body.albums[0].mediaCount, 2);
  });

  // 3. GET /api/albums/:id - Album details
  await t.test('GET /api/albums/:id returns details with mediaIds', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/albums/${createdAlbumId}`,
      headers: { authorization: `Bearer ${token1}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.album.id, createdAlbumId);
    assert.deepEqual(body.album.mediaIds.sort(), [testMediaId1, testMediaId2].sort());
  });

  // 4. POST /api/albums/:id/media - Add item
  await t.test('POST /api/albums/:id/media adds media pointer without duplicating file', async () => {
    const res = await app.inject({
      method: 'POST',
      url: `/api/albums/${createdAlbumId}/media`,
      headers: { authorization: `Bearer ${token1}` },
      payload: { mediaIds: [testMediaId3] },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.success, true);
    assert.equal(body.count, 1);

    const getRes = await app.inject({
      method: 'GET',
      url: `/api/albums/${createdAlbumId}`,
      headers: { authorization: `Bearer ${token1}` },
    });
    const album = JSON.parse(getRes.payload).album;
    assert.equal(album.mediaCount, 3);
  });

  // 5. DELETE /api/albums/:id/media/:mediaId - Remove single item
  await t.test('DELETE /api/albums/:id/media/:mediaId removes item pointer but keeps original media', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/albums/${createdAlbumId}/media/${testMediaId3}`,
      headers: { authorization: `Bearer ${token1}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.success, true);
    assert.equal(body.removedId, testMediaId3);

    // Verify original media still exists!
    const mediaRow = db.prepare('SELECT id FROM media WHERE id = ?').get(testMediaId3);
    assert.ok(mediaRow, 'Original media must NOT be deleted');
  });

  // 6. PATCH /api/albums/:id - Update album settings
  await t.test('PATCH /api/albums/:id updates title and sharing', async () => {
    const res = await app.inject({
      method: 'PATCH',
      url: `/api/albums/${createdAlbumId}`,
      headers: { authorization: `Bearer ${token1}` },
      payload: {
        title: 'Coastal Memories',
        isShared: true,
      },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.album.title, 'Coastal Memories');
    assert.equal(body.album.isShared, true);

    // Since isShared is true, user2 should now be able to view it!
    const user2Res = await app.inject({
      method: 'GET',
      url: `/api/albums/${createdAlbumId}`,
      headers: { authorization: `Bearer ${token2}` },
    });
    assert.equal(user2Res.statusCode, 200);
  });

  // 7. DELETE /api/albums/:id - Delete album container
  await t.test('DELETE /api/albums/:id deletes album container and preserves all photos', async () => {
    const res = await app.inject({
      method: 'DELETE',
      url: `/api/albums/${createdAlbumId}`,
      headers: { authorization: `Bearer ${token1}` },
    });
    assert.equal(res.statusCode, 200);

    // Verify album is gone
    const albumRow = db.prepare('SELECT id FROM albums WHERE id = ?').get(createdAlbumId);
    assert.equal(albumRow, undefined);

    // Verify photos still exist 100% untouched!
    const m1 = db.prepare('SELECT id FROM media WHERE id = ?').get(testMediaId1);
    const m2 = db.prepare('SELECT id FROM media WHERE id = ?').get(testMediaId2);
    assert.ok(m1);
    assert.ok(m2);
  });
});
