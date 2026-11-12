import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import sharp from 'sharp';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

async function createMultipartPayload(fieldName, buffer, filename, mimeType) {
  const form = new FormData();
  form.append(fieldName, new Blob([buffer], { type: mimeType }), filename);
  const response = new Response(form);
  const payload = Buffer.from(await response.arrayBuffer());
  const contentType = response.headers.get('content-type');
  return { payload, contentType };
}

test('Media API: Upload, Quota, Access Control, Streaming, Favorites, Trash', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-media-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
    DEFAULT_USER_QUOTA_BYTES: '1000000', // ~1 MB quota to test quota limit
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  // Create User Alice
  const aliceRes = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'alice@test.com', password: 'password123', name: 'Alice' },
  });
  const alice = JSON.parse(aliceRes.payload);
  const aliceToken = alice.token;

  // Create User Bob
  const bobRes = await app.inject({
    method: 'POST',
    url: '/api/auth/register',
    payload: { email: 'bob@test.com', password: 'password123', name: 'Bob' },
  });
  const bob = JSON.parse(bobRes.payload);
  const bobToken = bob.token;

  // Generate a valid small PNG test image using Sharp (50x50 red square)
  const smallImageBuffer = await sharp({
    create: {
      width: 50,
      height: 50,
      channels: 4,
      background: { r: 255, g: 0, b: 0, alpha: 1 },
    },
  }).png().toBuffer();

  let uploadedMediaId = '';

  await t.test('POST /api/media/upload successfully uploads image and creates thumbnail', async () => {
    const { payload, contentType } = await createMultipartPayload(
      'file',
      smallImageBuffer,
      'red_square.png',
      'image/png'
    );

    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${aliceToken}`,
        'content-type': contentType,
      },
      payload,
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.id);
    assert.equal(body.userId, alice.user.id);
    assert.equal(body.width, 50);
    assert.equal(body.height, 50);
    assert.equal(body.mimeType, 'image/png');
    assert.equal(body.isFavorite, false);
    assert.equal(body.isTrashed, false);

    uploadedMediaId = body.id;

    // Verify files on disk
    assert.ok(fs.existsSync(path.join(tmpDir, 'users', alice.user.id, 'originals', `${body.id}.png`)));
    assert.ok(fs.existsSync(path.join(tmpDir, 'users', alice.user.id, 'thumbnails', `${body.id}.webp`)));
  });

  await t.test('POST /api/media/upload rejects uploads that exceed user quota', async () => {
    // Generate a large 2MB image (exceeds the 1MB test quota)
    const largeBuffer = Buffer.alloc(1.5 * 1024 * 1024, 0);
    const { payload, contentType } = await createMultipartPayload(
      'file',
      largeBuffer,
      'large.png',
      'image/png'
    );

    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${aliceToken}`,
        'content-type': contentType,
      },
      payload,
    });

    assert.equal(res.statusCode, 413);
    const body = JSON.parse(res.payload);
    assert.equal(body.error.code, 'QUOTA_EXCEEDED');
  });

  await t.test('GET /api/media lists uploaded photos for Alice', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.items.length, 1);
    assert.equal(body.items[0].id, uploadedMediaId);
  });

  await t.test('Access Control: Bob cannot access Alice’s private media', async () => {
    // Details
    const detailsRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(detailsRes.statusCode, 404);

    // Thumbnail
    const thumbRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/thumb`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(thumbRes.statusCode, 404);

    // Original file
    const fileRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: { authorization: `Bearer ${bobToken}` },
    });
    assert.equal(fileRes.statusCode, 404);
  });

  await t.test('Streaming: Alice can stream her thumbnail and original file', async () => {
    const thumbRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/thumb`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(thumbRes.statusCode, 200);
    assert.equal(thumbRes.headers['content-type'], 'image/webp');

    const fileRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(fileRes.statusCode, 200);
    assert.equal(fileRes.headers['content-type'], 'image/png');
  });

  await t.test('PATCH /api/media/:id toggles favorite status', async () => {
    const res1 = await app.inject({
      method: 'PATCH',
      url: `/api/media/${uploadedMediaId}`,
      headers: { authorization: `Bearer ${aliceToken}` },
      payload: { favorite: true },
    });
    assert.equal(res1.statusCode, 200);
    assert.equal(JSON.parse(res1.payload).isFavorite, true);

    const res2 = await app.inject({
      method: 'PATCH',
      url: `/api/media/${uploadedMediaId}`,
      headers: { authorization: `Bearer ${aliceToken}` },
      payload: { favorite: false },
    });
    assert.equal(res2.statusCode, 200);
    assert.equal(JSON.parse(res2.payload).isFavorite, false);
  });

  await t.test('Trash & Restore lifecycle', async () => {
    // Trash
    const trashRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/trash`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(trashRes.statusCode, 200);
    assert.equal(JSON.parse(trashRes.payload).isTrashed, true);

    // Verify not in main feed
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(JSON.parse(listRes.payload).items.length, 0);

    // Verify present in trash feed
    const trashListRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(JSON.parse(trashListRes.payload).items.length, 1);

    // Restore
    const restoreRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/restore`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(restoreRes.statusCode, 200);
    assert.equal(JSON.parse(restoreRes.payload).isTrashed, false);
  });

  await t.test('DELETE /api/media/:id permanently deletes file and recovers quota', async () => {
    // Check quota before
    const beforeStats = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    const beforeUsed = JSON.parse(beforeStats.payload).user.storage.usedBytes;
    assert.ok(beforeUsed > 0);

    // Permanent delete
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/media/${uploadedMediaId}`,
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(delRes.statusCode, 200);

    // Verify files deleted from disk
    assert.equal(fs.existsSync(path.join(tmpDir, 'users', alice.user.id, 'originals', `${uploadedMediaId}.png`)), false);
    assert.equal(fs.existsSync(path.join(tmpDir, 'users', alice.user.id, 'thumbnails', `${uploadedMediaId}.webp`)), false);

    // Verify quota recovered
    const afterStats = await app.inject({
      method: 'GET',
      url: '/api/auth/me',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    const afterUsed = JSON.parse(afterStats.payload).user.storage.usedBytes;
    assert.equal(afterUsed, 0);
  });

  await t.test('Date Handling: Preserves client phone capture date, rejects future dates, and orders timeline', async () => {
    const historicalDate = '2022-06-15T11:22:33.000Z';
    const recentDate = '2024-01-10T09:00:00.000Z';

    // 1. Upload with ?takenAt=<historicalDate>
    const { payload: p1, contentType: ct1 } = await createMultipartPayload(
      'file',
      smallImageBuffer,
      'old_photo.png',
      'image/png'
    );
    const res1 = await app.inject({
      method: 'POST',
      url: `/api/media/upload?takenAt=${encodeURIComponent(historicalDate)}`,
      headers: {
        authorization: `Bearer ${aliceToken}`,
        'content-type': ct1,
      },
      payload: p1,
    });
    assert.equal(res1.statusCode, 201);
    const body1 = JSON.parse(res1.payload);
    assert.equal(body1.takenAt, historicalDate);

    // 2. Upload with X-Taken-At header
    const { payload: p2, contentType: ct2 } = await createMultipartPayload(
      'file',
      smallImageBuffer,
      'recent_photo.png',
      'image/png'
    );
    const res2 = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${aliceToken}`,
        'content-type': ct2,
        'x-taken-at': recentDate,
      },
      payload: p2,
    });
    assert.equal(res2.statusCode, 201);
    const body2 = JSON.parse(res2.payload);
    assert.equal(body2.takenAt, recentDate);

    // 3. Upload with invalid date fallback
    const { payload: p3, contentType: ct3 } = await createMultipartPayload(
      'file',
      smallImageBuffer,
      'invalid_date.png',
      'image/png'
    );
    const res3 = await app.inject({
      method: 'POST',
      url: '/api/media/upload?takenAt=not-a-valid-date',
      headers: {
        authorization: `Bearer ${aliceToken}`,
        'content-type': ct3,
      },
      payload: p3,
    });
    assert.equal(res3.statusCode, 201);
    const body3 = JSON.parse(res3.payload);
    assert.ok(body3.takenAt);
    assert.ok(!isNaN(new Date(body3.takenAt).getTime()));

    // 4. Verify ordering in GET /api/media (recentDate must appear before historicalDate)
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: { authorization: `Bearer ${aliceToken}` },
    });
    assert.equal(listRes.statusCode, 200);
    const listBody = JSON.parse(listRes.payload);
    const items = listBody.items;
    assert.ok(items.length >= 2);
    const recentIndex = items.findIndex(i => i.id === body2.id);
    const oldIndex = items.findIndex(i => i.id === body1.id);
    assert.ok(recentIndex < oldIndex, 'Newer photo should appear before older photo');
  });
});
