import test from 'node:test';
import assert from 'node:assert/strict';
import fs from 'node:fs';
import path from 'node:path';
import os from 'node:os';
import { initDatabase } from '../src/db.js';
import { buildApp } from '../src/app.js';
import { loadConfig } from '../src/config.js';

test('Media Pipeline: upload, thumbnail, timeline, streaming, favorites, and trash', async (t) => {
  const tmpDir = fs.mkdtempSync(path.join(os.tmpdir(), 'homespace-media-test-'));
  const db = initDatabase(':memory:');
  const config = loadConfig({
    DATA_DIR: tmpDir,
    DEFAULT_USER_QUOTA_BYTES: '100000', // 100 KB small quota to test limits
  });
  const app = await buildApp({ db, dataDir: tmpDir, config });

  t.after(async () => {
    await app.close();
    fs.rmSync(tmpDir, { recursive: true, force: true });
  });

  let token = '';
  let userId = '';
  let uploadedMediaId = '';

  // Setup: register user
  await t.test('Setup: register test user', async () => {
    const res = await app.inject({
      method: 'POST',
      url: '/api/auth/register',
      payload: {
        email: 'media_test@homespace.local',
        password: 'password12345',
        name: 'Media Tester',
      },
    });
    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    token = body.token;
    userId = body.user.id;
  });

  // 1x1 24-bit JPEG buffer
  const sampleJpeg = Buffer.from([
    0xff, 0xd8, 0xff, 0xe0, 0x00, 0x10, 0x4a, 0x46, 0x49, 0x46, 0x00, 0x01, 0x01, 0x01, 0x00, 0x48,
    0x00, 0x48, 0x00, 0x00, 0xff, 0xdb, 0x00, 0x43, 0x00, 0x08, 0x06, 0x06, 0x07, 0x06, 0x05, 0x08,
    0x07, 0x07, 0x07, 0x09, 0x09, 0x08, 0x0a, 0x0c, 0x14, 0x0d, 0x0c, 0x0b, 0x0b, 0x0c, 0x19, 0x12,
    0x13, 0x0f, 0x14, 0x1d, 0x1a, 0x1f, 0x1e, 0x1d, 0x1a, 0x1c, 0x1c, 0x20, 0x24, 0x2e, 0x27, 0x20,
    0x22, 0x2c, 0x23, 0x1c, 0x1c, 0x28, 0x37, 0x29, 0x2c, 0x30, 0x31, 0x34, 0x34, 0x34, 0x1f, 0x27,
    0x39, 0x3d, 0x38, 0x32, 0x3c, 0x2e, 0x33, 0x34, 0x32, 0xff, 0xc0, 0x00, 0x0b, 0x08, 0x00, 0x01,
    0x00, 0x01, 0x01, 0x01, 0x11, 0x00, 0xff, 0xc4, 0x00, 0x1f, 0x00, 0x00, 0x01, 0x05, 0x01, 0x01,
    0x01, 0x01, 0x01, 0x01, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x00, 0x01, 0x02, 0x03, 0x04,
    0x05, 0x06, 0x07, 0x08, 0x09, 0x0a, 0x0b, 0xff, 0xda, 0x00, 0x08, 0x01, 0x01, 0x00, 0x00, 0x3f,
    0x00, 0xbf, 0x00, 0xff, 0xd9
  ]);

  function buildMultipart(filename, fileBuffer, mimeType = 'image/jpeg', boundary = '----WebKitFormBoundaryXYZ') {
    const header = Buffer.from(
      `--${boundary}\r\n` +
      `Content-Disposition: form-data; name="file"; filename="${filename}"\r\n` +
      `Content-Type: ${mimeType}\r\n\r\n`
    );
    const footer = Buffer.from(`\r\n--${boundary}--\r\n`);
    return {
      payload: Buffer.concat([header, fileBuffer, footer]),
      contentType: `multipart/form-data; boundary=${boundary}`,
    };
  }

  await t.test('POST /api/media/upload creates media and updates quota', async () => {
    const multipart = buildMultipart('IMG_20261121_120000.jpg', sampleJpeg);
    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload?takenAt=2026-11-21T12:00:00.000Z',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': multipart.contentType,
      },
      payload: multipart.payload,
    });

    assert.equal(res.statusCode, 201);
    const body = JSON.parse(res.payload);
    assert.ok(body.media.id);
    assert.equal(body.media.filename, 'IMG_20261121_120000.jpg');
    assert.equal(body.media.kind, 'photo');
    assert.equal(body.media.size, sampleJpeg.length);
    assert.equal(body.media.isFavorite, false);

    uploadedMediaId = body.media.id;

    // Check user quota updated
    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), sampleJpeg.length);
  });

  await t.test('GET /api/media returns timeline with uploaded item', async () => {
    const res = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.total, 1);
    assert.equal(body.items[0].id, uploadedMediaId);
    assert.equal(body.items[0].filename, 'IMG_20261121_120000.jpg');
  });

  await t.test('GET /api/media/:id returns single metadata', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    const body = JSON.parse(res.payload);
    assert.equal(body.media.id, uploadedMediaId);
  });

  await t.test('GET /api/media/:id/thumb streams thumbnail', async () => {
    const res = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/thumb`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(res.statusCode, 200);
    assert.ok(res.headers['content-type'].includes('image/'));
    assert.ok(res.rawPayload.length > 0);
  });

  await t.test('GET /api/media/:id/file streams full original and supports Range requests', async () => {
    // Full request
    const fullRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });

    assert.equal(fullRes.statusCode, 200);
    assert.equal(fullRes.rawPayload.length, sampleJpeg.length);
    assert.equal(fullRes.headers['accept-ranges'], 'bytes');

    // Partial Range request: first 10 bytes
    const rangeRes = await app.inject({
      method: 'GET',
      url: `/api/media/${uploadedMediaId}/file`,
      headers: {
        authorization: `Bearer ${token}`,
        range: 'bytes=0-9',
      },
    });

    assert.equal(rangeRes.statusCode, 206);
    assert.equal(rangeRes.rawPayload.length, 10);
    assert.equal(rangeRes.headers['content-range'], `bytes 0-9/${sampleJpeg.length}`);
    assert.deepEqual(rangeRes.rawPayload, sampleJpeg.subarray(0, 10));
  });

  await t.test('PATCH /api/media/:id toggles favorite', async () => {
    const favRes = await app.inject({
      method: 'PATCH',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
      payload: { isFavorite: true },
    });

    assert.equal(favRes.statusCode, 200);
    const body = JSON.parse(favRes.payload);
    assert.equal(body.media.isFavorite, true);

    // Filter query
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media?favorite=true',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    const listBody = JSON.parse(listRes.payload);
    assert.equal(listBody.total, 1);
  });

  await t.test('POST /api/media/:id/trash moves to trash and hides from timeline', async () => {
    const trashRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/trash`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(trashRes.statusCode, 200);

    // Standard timeline should now be empty
    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(listRes.payload).total, 0);

    // Trash query should return 1
    const trashListRes = await app.inject({
      method: 'GET',
      url: '/api/media?trashed=true',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(trashListRes.payload).total, 1);
  });

  await t.test('POST /api/media/:id/restore restores from trash', async () => {
    const restoreRes = await app.inject({
      method: 'POST',
      url: `/api/media/${uploadedMediaId}/restore`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(restoreRes.statusCode, 200);

    const listRes = await app.inject({
      method: 'GET',
      url: '/api/media',
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(JSON.parse(listRes.payload).total, 1);
  });

  await t.test('DELETE /api/media/:id removes file and refunds quota', async () => {
    const delRes = await app.inject({
      method: 'DELETE',
      url: `/api/media/${uploadedMediaId}`,
      headers: {
        authorization: `Bearer ${token}`,
      },
    });
    assert.equal(delRes.statusCode, 200);

    // Database record deleted
    const checkDb = db.prepare('SELECT id FROM media WHERE id = ?').get(uploadedMediaId);
    assert.equal(checkDb, undefined);

    // Quota refunded back to 0
    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), 0);
  });

  await t.test('Upload rejects when file exceeds user quota (413 QUOTA_EXCEEDED)', async () => {
    // Quota was set to 100 KB (100,000 bytes)
    const giantPayload = Buffer.alloc(150000, 0x41);
    const multipart = buildMultipart('giant.bin', giantPayload);

    const res = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': multipart.contentType,
      },
      payload: multipart.payload,
    });

    assert.equal(res.statusCode, 413);
    const body = JSON.parse(res.payload);
    assert.equal(body.error.code, 'QUOTA_EXCEEDED');
  });

  await t.test('Phase 6: Trash aliases and empty / purge lifecycle', async () => {
    // Upload a test photo
    const payload = Buffer.from('phase6-test-content');
    const mp = buildMultipart('trash-photo.jpg', payload);
    const upRes = await app.inject({
      method: 'POST',
      url: '/api/media/upload',
      headers: {
        authorization: `Bearer ${token}`,
        'content-type': mp.contentType,
      },
      payload: mp.payload,
    });
    assert.equal(upRes.statusCode, 201);
    const item = JSON.parse(upRes.payload).media;

    // Move to trash
    const trashRes = await app.inject({
      method: 'POST',
      url: '/api/media/trash',
      headers: { authorization: `Bearer ${token}` },
      payload: { ids: [item.id] },
    });
    assert.equal(trashRes.statusCode, 200);

    // GET /api/trash
    const listTrashRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(listTrashRes.statusCode, 200);
    const trashData = JSON.parse(listTrashRes.payload);
    assert.equal(trashData.total, 1);
    assert.equal(trashData.items[0].id, item.id);
    assert.equal(trashData.items[0].isTrashed, true);
    assert.ok(trashData.items[0].trashedAt);

    // Empty trash
    const emptyRes = await app.inject({
      method: 'POST',
      url: '/api/trash/empty',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(emptyRes.statusCode, 200);
    const emptyBody = JSON.parse(emptyRes.payload);
    assert.equal(emptyBody.count, 1);

    // Verify trash is now empty and user quota is 0
    const checkTrashRes = await app.inject({
      method: 'GET',
      url: '/api/trash',
      headers: { authorization: `Bearer ${token}` },
    });
    assert.equal(JSON.parse(checkTrashRes.payload).total, 0);

    const userRow = db.prepare('SELECT storage_used_bytes FROM users WHERE id = ?').get(userId);
    assert.equal(Number(userRow.storage_used_bytes), 0);
  });
});
